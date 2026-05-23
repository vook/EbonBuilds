-- EbonBuilds: modules/sync/Sync.lua
-- Responsibility: peer-to-peer build synchronisation.
-- Discovery via hidden chat channel + known-peers fallback.
-- Data transfer via SendAddonMessage WHISPER chunks.
-- Batch protocol: LST (list batch) → WNT/SKP (want/skip) → BLD (build data).

EbonBuilds.Sync = {}

local PREFIX        = "EbonBuilds"
local SYNC_CHANNEL  = "ebonbuildssync"

-- Must be called at file scope (during addon load), not inside ADDON_LOADED event
if RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(PREFIX)
end
local MAX_CHUNK     = 180
local SYNC_TIMEOUT  = 15
local BATCH_SIZE    = 3
local WANT_TIMEOUT  = 15
local REQ_COOLDOWN  = 30

-- Bump this to invalidate remote builds from older addon versions.
-- Only affects builds that have NOT been imported — imported builds stay.
local SYNC_VERSION  = 1

-- Set to true to only share builds that reached level 80 while active
local VALIDATION_REQUIRED = true
local VERBOSE_LOG = false

local syncFrame
local syncChannelIndex
local inflight = {}
local sendQueue = {}
local nextSendTime = 0
local SEND_DELAY = 0.05
local pendingBatches = {}
local lastRequestTime = 0
local channelRetries = { remaining = 0, payload = nil, nextTime = 0 }

local function Now()
    return GetTime()
end

local function Log(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[EbonBuilds Sync]|r " .. msg)
end

local function VerboseLog(msg)
    if VERBOSE_LOG then Log(msg) end
end

local function SortableNow()
    return date("%Y-%m-%d %H:%M:%S")
end

local function IsSyncChannelName(name)
    if type(name) ~= "string" then return false end
    return name:lower():find(SYNC_CHANNEL, 1, true) ~= nil
end


local function IsoToEpoch(iso)
    if not iso or iso == "" then return 0 end
    local y, m, d, h, min, s = iso:match("^(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)$")
    if not y then return 0 end
    local ok, result = pcall(time, {
        year = tonumber(y), month = tonumber(m), day = tonumber(d),
        hour = tonumber(h), min = tonumber(min), sec = tonumber(s),
    })
    return ok and result or 0
end

-- Handles both ISO (YYYY-MM-DD HH:MM:SS) and US (MM/DD/YY HH:MM:SS) formats
local function DateToEpoch(d)
    if not d or d == "" then return 0 end
    -- Try ISO first: 2026-05-20 16:35:08
    local epoch = IsoToEpoch(d)
    if epoch > 0 then return epoch end
    -- Try US format: 05/19/26 17:51:39  (two-digit year)
    local m, day, y, h, min, s = d:match("^(%d+)/(%d+)/(%d+) (%d+):(%d+):(%d+)$")
    if not m then return 0 end
    -- Normalize two-digit year: 26 → 2026
    local year = tonumber(y)
    if year < 100 then year = year + 2000 end
    local ok, result = pcall(time, {
        year = year, month = tonumber(m), day = tonumber(day),
        hour = tonumber(h), min = tonumber(min), sec = tonumber(s),
    })
    return ok and result or 0
end

------------------------------------------------------------------------
-- Channel management
------------------------------------------------------------------------

local function FindOrJoinChannel()
    for i = 1, 10 do
        local raw = GetChannelName(i)
        if IsSyncChannelName(raw) then
            return i
        end
    end
    local idx = JoinChannelByName(SYNC_CHANNEL)
    if idx and idx > 0 then return idx end
    return nil
end

local function HideChannelFromChat()
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = _G["ChatFrame" .. i]
        if frame then
            ChatFrame_RemoveChannel(frame, SYNC_CHANNEL)
        end
    end
end

local function RefreshChannel()
    if not syncChannelIndex or syncChannelIndex == 0 then
        syncChannelIndex = FindOrJoinChannel()
        if syncChannelIndex and syncChannelIndex > 0 then
            HideChannelFromChat()
        end
    end
end

------------------------------------------------------------------------
-- Send queue (rate-limited via OnUpdate, 50 ms between messages)
------------------------------------------------------------------------

local function Enqueue(target, payload)
    if not target or target == "" or not payload then return end
    sendQueue[#sendQueue + 1] = { target = target, payload = payload }
end

local function SendChunked(target, code, streamKey, data)
    local sender = UnitName("player")
    if #data <= MAX_CHUNK then
        local payload = string.format("%s|%s|%s|1/1|%s", code, sender, streamKey, data)
        Enqueue(target, payload)
        return
    end
    local total = math.ceil(#data / MAX_CHUNK)
    for idx = 1, total do
        local start = (idx - 1) * MAX_CHUNK + 1
        local chunk = string.sub(data, start, start + MAX_CHUNK - 1)
        local payload = string.format("%s|%s|%s|%d/%d|%s", code, sender, streamKey, idx, total, chunk)
        Enqueue(target, payload)
    end
end

------------------------------------------------------------------------
-- Inflight cleanup (received chunks)
------------------------------------------------------------------------

local function CleanupExpired()
    local t = Now()
    for k, v in pairs(inflight) do
        if t - (v.t0 or t) > SYNC_TIMEOUT then
            inflight[k] = nil
        end
    end
    for k, v in pairs(pendingBatches) do
        if t - (v.t0 or t) > WANT_TIMEOUT then
            pendingBatches[k] = nil
        end
    end
end

------------------------------------------------------------------------
-- Assembly
------------------------------------------------------------------------

local function AssembleBuild(sender, buildId, base64)
    local imported = EbonBuilds.ExportImport.DecodeBuild(base64)
    if not imported then return end

    EbonBuildsDB.remoteBuilds = EbonBuildsDB.remoteBuilds or {}

    -- If the user already owns this build by UUID (e.g. they are the author),
    -- update it in-place.
    local existing = EbonBuildsDB.builds[buildId]
    if existing then
        local incomingDate = imported.lastModified or ""
        local localDate   = existing.lastModified or ""
        if incomingDate > localDate then
            EbonBuilds.Build.UpdateFromPublic(existing, imported)
            Log("Build " .. buildId .. " updated (incoming=" .. incomingDate .. " > local=" .. localDate .. ")")
        end
        return
    end

    -- Store in remote builds (market), not in local collection
    local rb = EbonBuildsDB.remoteBuilds[buildId]
    if rb then
        local incomingDate = imported.lastModified or ""
        local storedDate   = rb.lastModified or ""
        if incomingDate > storedDate then
            imported.id = buildId
            EbonBuildsDB.remoteBuilds[buildId] = imported
            Log("Build " .. buildId .. " updated in remote (incoming=" .. incomingDate .. ")")
        end
    else
        imported.id = buildId
        EbonBuildsDB.remoteBuilds[buildId] = imported
        Log("Build " .. buildId .. " stored in remote (author: " .. (imported.author or "?") .. ")")
    end

    if EbonBuilds.PublicBuildsView and EbonBuilds.PublicBuildsView.RefreshIfMounted then
        EbonBuilds.PublicBuildsView.RefreshIfMounted()
    end
end

------------------------------------------------------------------------
-- Batch protocol (responder side)
------------------------------------------------------------------------

local function SendNextBatch(requester)
    local pb = pendingBatches[requester]
    if not pb then return end

    pb.current = pb.current + 1
    local start = (pb.current - 1) * BATCH_SIZE + 1
    if start > #pb.builds then
        -- All batches done, send END
        local endPayload = string.format("END|%s|%d", UnitName("player"), pb.sent)
        Enqueue(requester, endPayload)
        VerboseLog(string.format("All batches sent to %s (%d builds total)", requester, pb.sent))
        pendingBatches[requester] = nil
        return
    end

    local finish = math.min(start + BATCH_SIZE - 1, #pb.builds)
    local parts = { "LST", UnitName("player"), pb.current .. "/" .. pb.totalBatches }
    for i = start, finish do
        local b = pb.builds[i]
        parts[#parts + 1] = b.id
        parts[#parts + 1] = tostring(DateToEpoch(b.lastModified))
    end
    Enqueue(requester, table.concat(parts, "|"))
end

local function SendBatchBuilds(requester, wantedUuids)
    local pb = pendingBatches[requester]
    if not pb then return end

    local wanted = {}
    for uuid in pairs(wantedUuids) do wanted[uuid] = true end

    local start = (pb.current - 1) * BATCH_SIZE + 1
    local finish = math.min(start + BATCH_SIZE - 1, #pb.builds)
    for i = start, finish do
        local b = pb.builds[i]
        if wanted[b.id] then
            local b64 = EbonBuilds.ExportImport.ExportBuild(b)
            if b64 then
                SendChunked(requester, "BLD", b.id, b64)
                pb.sent = pb.sent + 1
            end
        end
    end

    SendNextBatch(requester)
end

------------------------------------------------------------------------
-- Core request handler (responder side)
------------------------------------------------------------------------

local function HandleRequest(requester)
    if not requester or requester == "" or requester == UnitName("player") then return end

    Log("Sync request from " .. requester)

    EbonBuildsDB.syncPeers = EbonBuildsDB.syncPeers or {}
    EbonBuildsDB.syncPeers[requester] = true

    local allPublic = EbonBuilds.Build.ListPublic()
    VerboseLog("HandleRequest: " .. #allPublic .. " public builds total")
    if #allPublic == 0 then
        VerboseLog("No public builds to send, replying END to " .. requester)
        local endPayload = string.format("END|%s|0", UnitName("player"))
        Enqueue(requester, endPayload)
        return
    end

    local eligible = {}
    for _, build in ipairs(allPublic) do
        if build.author ~= requester then
            if VALIDATION_REQUIRED and not build.validated then
                VerboseLog("  build " .. (build.title or "?") .. " skipped: not validated")
            else
                eligible[#eligible + 1] = build
            end
        else
            VerboseLog("  build " .. (build.title or "?") .. " skipped: authored by requester")
        end
    end

    VerboseLog("HandleRequest: " .. #eligible .. " eligible after filtering")
    if #eligible == 0 then
        VerboseLog("No eligible builds for " .. requester .. ", replying END")
        local endPayload = string.format("END|%s|0", UnitName("player"))
        Enqueue(requester, endPayload)
        return
    end

    VerboseLog(string.format("Prepared %d builds for %s in %d batch(es)",
        #eligible, requester, math.ceil(#eligible / BATCH_SIZE)))

    pendingBatches[requester] = {
        builds = eligible,
        totalBatches = math.ceil(#eligible / BATCH_SIZE),
        current = 0,
        sent = 0,
        t0 = Now(),
    }
    SendNextBatch(requester)
end

------------------------------------------------------------------------
-- Channel message handler (REQ via custom chat channel)
------------------------------------------------------------------------

local function HandleChannelMessage(msg, sender, _, channelName, _, _, channelNumber)
    if not IsSyncChannelName(channelName) then return end

    -- Learn the channel index from incoming messages (arg7)
    if channelNumber and type(channelNumber) == "number" and channelNumber > 0 then
        if not syncChannelIndex or syncChannelIndex ~= channelNumber then
            syncChannelIndex = channelNumber
            VerboseLog("Learned sync channel index from incoming message: " .. channelNumber)
        end
    end

    -- Decode escaped pipes: SendChatMessage escapes | as ||, WoW may not unescape them
    local decoded = msg:gsub("||", "|")
    local parts = {strsplit("|", decoded)}
    local code = parts[1]
    if code ~= "REQ" then return end
    Log("REQ received via channel from " .. (sender or "?"))
    local ok, err = pcall(HandleRequest, parts[2])
    if not ok then Log("HandleRequest error: " .. tostring(err)) end
end

------------------------------------------------------------------------
-- Addon message handlers (requester side)
------------------------------------------------------------------------

local function HandleAddonREQ(payload, sender)
    local parts = {strsplit("|", payload)}
    if parts[1] ~= "REQ" then return end
    HandleRequest(parts[2])
end

local function HandleChunk(payload, sender)
    local parts = {strsplit("|", payload)}
    if parts[1] ~= "BLD" or #parts < 5 then return end
    local snd, buildId, idxTotal, data = parts[2], parts[3], parts[4], parts[5]

    local idx, total = idxTotal:match("^(%d+)/(%d+)$")
    if not idx then return end
    idx = tonumber(idx)
    total = tonumber(total)

    local key = snd .. ":" .. buildId
    local rec = inflight[key]
    if not rec then
        rec = { total = total, got = 0, parts = {}, t0 = Now() }
        inflight[key] = rec
    end

    if idx >= 1 and idx <= total and not rec.parts[idx] then
        rec.parts[idx] = data
        rec.got = rec.got + 1
    end

    if rec.got == rec.total then
        local assembled = table.concat(rec.parts, "", 1, rec.total)
        inflight[key] = nil
        VerboseLog(string.format("Build %s from %s fully received (%d chunks, %d bytes)",
            buildId, snd, total, #assembled))
        local ok, err = pcall(AssembleBuild, snd, buildId, assembled)
        if not ok then
            Log("Error assembling build " .. buildId .. ": " .. tostring(err))
        end
    end

    CleanupExpired()
end

local function HandleListBatch(payload, sender)
    -- payload: "LST|sender|batch/total|uuid1|epoch1|uuid2|epoch2|..."
    local parts = {strsplit("|", payload)}
    if #parts < 4 then return end

    local wanted = {}
    for i = 4, #parts, 2 do
        local uuid = parts[i]
        local offerEpoch = tonumber(parts[i + 1]) or 0
        if uuid and uuid ~= "" then
            local needUpdate = false
            local ownBuild = EbonBuildsDB.builds[uuid]
            if ownBuild then
                local localEpoch = DateToEpoch(ownBuild.lastModified)
                needUpdate = offerEpoch > localEpoch
            else
                -- Already imported as local copy?
                local localCopy = nil
                for _, b in pairs(EbonBuildsDB.builds) do
                    if b.importedFrom == uuid then localCopy = b; break end
                end
                local localEpoch = localCopy and DateToEpoch(localCopy._importedAt) or 0
                if offerEpoch > localEpoch then
                    needUpdate = true
                end
                -- Already received via another responder?
                if not needUpdate then
                    local rb = (EbonBuildsDB.remoteBuilds or {})[uuid]
                    local rbEpoch = rb and DateToEpoch(rb.lastModified) or 0
                    needUpdate = offerEpoch > rbEpoch
                end
            end
            if needUpdate then
                wanted[#wanted + 1] = uuid
            end
        end
    end

    if #wanted == 0 then
        local skipPayload = string.format("SKP|%s", UnitName("player"))
        Enqueue(sender, skipPayload)
    else
        local wantParts = { "WNT", UnitName("player") }
        for _, uuid in ipairs(wanted) do
            wantParts[#wantParts + 1] = uuid
        end
        Enqueue(sender, table.concat(wantParts, "|"))
    end
end

local function HandleWant(payload, sender)
    -- payload: "WNT|requester|uuid1|uuid2|..."
    local parts = {strsplit("|", payload)}
    if parts[1] ~= "WNT" then return end
    local wantedUuids = {}
    for i = 3, #parts do
        wantedUuids[parts[i]] = true
    end
    SendBatchBuilds(sender, wantedUuids)
end

local function HandleSkip(payload, sender)
    SendBatchBuilds(sender, {})  -- empty = skip all in current batch
end

local function HandleEnd(payload, sender)
    local parts = {strsplit("|", payload)}
    if parts[1] ~= "END" then return end
    local snd, count = parts[2], parts[3]

    EbonBuildsDB.lastSyncDate = SortableNow()

    local c = tonumber(count) or 0
    if c > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff19ff19EbonBuilds|r: Received %d build(s) from %s.", c, snd))
    end

    if EbonBuilds.PublicBuildsView and EbonBuilds.PublicBuildsView.RefreshIfMounted then
        EbonBuilds.PublicBuildsView.RefreshIfMounted()
    end
end

------------------------------------------------------------------------
-- Dispatch (CHAT_MSG_ADDON events)
------------------------------------------------------------------------

local function DispatchAddon(prefix, payload, dist, sender)
    if prefix ~= PREFIX then return end
    if not payload or payload == "" then return end

    local code = payload:sub(1, 3)
    if code == "REQ" then
        HandleAddonREQ(payload, sender)
    elseif code == "BLD" then
        HandleChunk(payload, sender)
    elseif code == "LST" then
        HandleListBatch(payload, sender)
    elseif code == "WNT" then
        HandleWant(payload, sender)
    elseif code == "SKP" then
        HandleSkip(payload, sender)
    elseif code == "END" then
        HandleEnd(payload, sender)
    end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

function EbonBuilds.Sync.GetCooldownRemaining()
    local elapsed = Now() - lastRequestTime
    if elapsed >= REQ_COOLDOWN then return 0 end
    return math.ceil(REQ_COOLDOWN - elapsed)
end

function EbonBuilds.Sync.RequestSync()
    local remaining = EbonBuilds.Sync.GetCooldownRemaining()
    if remaining > 0 then
        Log("Sync on cooldown, wait " .. remaining .. "s before requesting again")
        return
    end
    lastRequestTime = Now()

    local me       = UnitName("player")
    local payload  = string.format("REQ|%s", me)

    Log("Requesting sync...")

    -- 1. Broadcast via hidden chat channel (all addon users on the realm)
    RefreshChannel()
    -- Escape | as || for SendChatMessage (avoids "Invalid escape code");
    -- receiver will decode || back to | before parsing.
    local escapedPayload = payload:gsub("|", "||")
    channelRetries.remaining = 5
    channelRetries.payload = escapedPayload
    channelRetries.nextTime = 0  -- fire immediately on next OnUpdate

    -- 2. Guild broadcast via SendAddonMessage (reliable, but guild-only)
    local guildName = GetGuildInfo("player")
    if guildName then
        SendAddonMessage(PREFIX, payload, "GUILD")
        VerboseLog("REQ also broadcast via GUILD")
    end

    -- 3. Whisper known peers (cross-realm / cross-guild fallback)
    EbonBuildsDB.syncPeers = EbonBuildsDB.syncPeers or {}
    local peerCount = 0
    for peer in pairs(EbonBuildsDB.syncPeers) do
        if peer ~= me then
            Enqueue(peer, payload)
            peerCount = peerCount + 1
        end
    end
    if peerCount > 0 then
        VerboseLog("REQ whispered to " .. peerCount .. " known peer(s)")
    end
end

function EbonBuilds.Sync.Init()
    syncFrame = CreateFrame("Frame")
    syncFrame:RegisterEvent("CHAT_MSG_ADDON")
    syncFrame:RegisterEvent("CHAT_MSG_CHANNEL")
    syncFrame:RegisterEvent("PLAYER_LEVEL_UP")
    syncFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            DispatchAddon(...)
        elseif event == "CHAT_MSG_CHANNEL" then
            HandleChannelMessage(...)
        elseif event == "PLAYER_LEVEL_UP" then
            local newLevel = ...
            if newLevel == 80 then
                local build = EbonBuilds.Build.GetActive()
                if build and not build.validated then
                    build.validated = true
                    VerboseLog("Build \"" .. (build.title or "?") .. "\" validated (reached level 80)")
                end
            end
        end
    end)
    syncFrame:SetScript("OnUpdate", function()
        local now = Now()
        -- Channel retry loop
        if channelRetries.remaining > 0 and now >= channelRetries.nextTime then
            channelRetries.remaining = channelRetries.remaining - 1
            local ok = pcall(SendChatMessage, channelRetries.payload, "CHANNEL", nil, 1)
            Log("REQ attempt " .. (5 - channelRetries.remaining) .. "/5: " .. (ok and "sent" or tostring("err")))
            if ok or channelRetries.remaining == 0 then
                channelRetries.remaining = 0
            else
                channelRetries.nextTime = now + 0.1
            end
        end
        -- Send queue (rate-limited)
        if #sendQueue > 0 and now >= nextSendTime then
            local entry = sendQueue[1]
            table.remove(sendQueue, 1)
            if entry.target and entry.target ~= "" and entry.payload then
                SendAddonMessage(PREFIX, entry.payload, "WHISPER", entry.target)
            end
            nextSendTime = now + SEND_DELAY
        end
    end)

    -- Join and hide the sync channel
    syncChannelIndex = FindOrJoinChannel()
    HideChannelFromChat()

    EbonBuildsDB.lastSyncDate = EbonBuildsDB.lastSyncDate or nil
    EbonBuildsDB.syncPeers    = EbonBuildsDB.syncPeers    or {}

    -- Purge remote builds from older addon versions (only unimported builds)
    local storedVersion = EbonBuildsDB.syncVersion or 0
    if storedVersion < SYNC_VERSION then
        if EbonBuildsDB.remoteBuilds and next(EbonBuildsDB.remoteBuilds) then
            EbonBuildsDB.remoteBuilds = {}
            Log("Sync version bumped to " .. SYNC_VERSION .. " — remote builds purged.")
        end
        EbonBuildsDB.syncVersion = SYNC_VERSION
    end
end

SLASH_EBBSYNC1 = "/ebbsync"
SlashCmdList["EBBSYNC"] = function(cmd)
    cmd = strtrim(cmd or "")
    if cmd == "join" then
        Log("To enable sync discovery, type: /join " .. SYNC_CHANNEL)
        Log("After joining, reload with /reload or click Reload on Public Builds.")
    elseif cmd == "status" then
        RefreshChannel()
        if syncChannelIndex and syncChannelIndex > 0 then
            local name = GetChannelName(syncChannelIndex)
            Log("Sync channel: index=" .. syncChannelIndex .. " name=" .. tostring(name))
        else
            Log("Sync channel not joined. Type /ebbsync join for help.")
        end
    elseif cmd == "reset" then
        lastRequestTime = 0
        EbonBuildsDB.lastSyncDate = nil
        EbonBuildsDB.remoteBuilds = {}
        Log("Sync cooldown and lastSyncDate reset. Remote builds cleared.")
    elseif cmd == "verbose" then
        VERBOSE_LOG = not VERBOSE_LOG
        Log("Verbose logging " .. (VERBOSE_LOG and "enabled" or "disabled") .. ".")
    else
        Log("EbonBuilds Sync commands:")
        Log("  /ebbsync join    - Show how to join the sync channel")
        Log("  /ebbsync status  - Show current sync channel status")
        Log("  /ebbsync reset   - Reset sync cooldown timer")
        Log("  /ebbsync verbose - Toggle verbose logging")
    end
end
