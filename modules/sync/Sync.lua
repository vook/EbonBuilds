-- EbonBuilds: modules/sync/Sync.lua
-- Responsibility: peer-to-peer build synchronisation.
-- Discovery via hidden chat channel + known-peers fallback.
-- Data transfer via SendAddonMessage WHISPER chunks.
-- Batch protocol: LST (list batch) → WNT/SKP (want/skip) → BLD (build data).

EbonBuilds.Sync = {}

local PREFIX        = "EbonBuilds"
local SYNC_CHANNEL  = "EbonBuildsSync"
local MAX_CHUNK     = 180
local SYNC_TIMEOUT  = 15
local BATCH_SIZE    = 3
local WANT_TIMEOUT  = 15

-- Set to true to only share builds that reached level 80 while active
local VALIDATION_REQUIRED = false

local syncFrame
local syncChannelIndex
local inflight = {}
local sendQueue = {}
local nextSendTime = 0
local SEND_DELAY = 0.05
local pendingBatches = {}

local function Now()
    return GetTime()
end

local function Log(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[EbonBuilds Sync]|r " .. msg)
end

local function SortableNow()
    return date("%Y-%m-%d %H:%M:%S")
end

local function SixtyDaysAgo()
    return date("%Y-%m-%d %H:%M:%S", time() - 60 * 24 * 3600)
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

------------------------------------------------------------------------
-- Channel management
------------------------------------------------------------------------

local function FindOrJoinChannel()
    for i = 1, 10 do
        local name = GetChannelName(i)
        if name == SYNC_CHANNEL then
            return i
        end
    end
    return JoinChannelByName(SYNC_CHANNEL)
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
    if not syncChannelIndex or GetChannelName(syncChannelIndex) ~= SYNC_CHANNEL then
        syncChannelIndex = FindOrJoinChannel()
        HideChannelFromChat()
    end
end

------------------------------------------------------------------------
-- Send queue (rate-limited via OnUpdate, 50 ms between messages)
------------------------------------------------------------------------

local function Enqueue(target, payload)
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

    local existing = EbonBuildsDB.builds[buildId]
    if existing then
        Log("Build " .. buildId .. " already exists locally, checking dates...")
        local incomingDate = imported.lastModified or ""
        local localDate   = existing.lastModified or ""
        if incomingDate > localDate then
            EbonBuilds.Build.UpdateFromPublic(existing, imported)
            Log("Build " .. buildId .. " updated (incoming=" .. incomingDate .. " > local=" .. localDate .. ")")
        else
            Log("Build " .. buildId .. " skipped (local date is same or newer)")
        end
    else
        imported.id          = buildId
        imported.importedFrom = buildId
        imported._importedAt = imported.lastModified
        imported.isPublic    = false
        EbonBuildsDB.builds[buildId] = imported
        Log("Build " .. buildId .. " imported as new (author: " .. (imported.author or "?") .. ")")
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
        Log(string.format("All batches sent to %s (%d builds total)", requester, pb.sent))
        pendingBatches[requester] = nil
        return
    end

    local finish = math.min(start + BATCH_SIZE - 1, #pb.builds)
    local parts = { "LST", UnitName("player"), pb.current .. "/" .. pb.totalBatches }
    for i = start, finish do
        local b = pb.builds[i]
        parts[#parts + 1] = b.id
        parts[#parts + 1] = tostring(IsoToEpoch(b.lastModified))
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

local function HandleRequest(requester, lastDate)
    if requester == UnitName("player") then return end

    Log("Sync request from " .. requester .. " (lastSyncDate=" .. lastDate .. ")")

    EbonBuildsDB.syncPeers = EbonBuildsDB.syncPeers or {}
    EbonBuildsDB.syncPeers[requester] = true

    local allPublic = EbonBuilds.Build.ListPublic()
    if #allPublic == 0 then
        Log("No public builds to send, replying END to " .. requester)
        local endPayload = string.format("END|%s|0", UnitName("player"))
        Enqueue(requester, endPayload)
        return
    end

    local cutoff = SixtyDaysAgo()
    local eligible = {}
    for _, build in ipairs(allPublic) do
        if build.author ~= requester then
            if VALIDATION_REQUIRED and not build.validated then
                -- skip non-validated builds when validation is required
            else
                local mod = build.lastModified or ""
                if lastDate == "0" then
                    if mod >= cutoff then eligible[#eligible + 1] = build end
                else
                    if mod > lastDate then eligible[#eligible + 1] = build end
                end
            end
        end
    end

    if #eligible == 0 then
        Log("No eligible builds for " .. requester .. ", replying END")
        local endPayload = string.format("END|%s|0", UnitName("player"))
        Enqueue(requester, endPayload)
        return
    end

    Log(string.format("Prepared %d builds for %s in %d batch(es)",
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

local function HandleChannelMessage(msg, sender, channelName)
    if channelName ~= SYNC_CHANNEL then return end
    local code, requester, lastDate = msg:match("^(REQ)|([^|]+)|(.+)$")
    if not code then return end
    Log("REQ received via channel from " .. (sender or "?"))
    HandleRequest(requester, lastDate)
end

------------------------------------------------------------------------
-- Addon message handlers (requester side)
------------------------------------------------------------------------

local function HandleAddonREQ(payload, sender)
    local code, requester, lastDate = payload:match("^(REQ)|([^|]+)|(.+)$")
    if not code then return end
    HandleRequest(requester, lastDate)
end

local function HandleChunk(payload, sender)
    local code, snd, buildId, idxTotal, data = payload:match("^(BLD)|([^|]+)|([^|]+)|([^|]+)|(.+)$")
    if not code then return end

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
        Log(string.format("Build %s from %s fully received (%d chunks, %d bytes)",
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
    local parts = {}
    for part in payload:gmatch("[^|]+") do parts[#parts + 1] = part end
    if #parts < 4 then return end

    local wanted = {}
    for i = 4, #parts, 2 do
        local uuid = parts[i]
        local remoteEpoch = tonumber(parts[i + 1]) or 0
        if uuid and uuid ~= "" then
            local ownBuild = EbonBuildsDB.builds[uuid]
            if ownBuild then
                local localEpoch = IsoToEpoch(ownBuild.lastModified)
                if remoteEpoch > localEpoch then
                    wanted[#wanted + 1] = uuid
                end
            else
                local localCopy = nil
                for _, b in pairs(EbonBuildsDB.builds) do
                    if b.importedFrom == uuid then localCopy = b; break end
                end
                local localEpoch = localCopy and IsoToEpoch(localCopy._importedAt) or 0
                if remoteEpoch > localEpoch then
                    wanted[#wanted + 1] = uuid
                end
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
    local code, requester, uuids = payload:match("^(WNT)|([^|]+)|(.+)$")
    if not code then return end
    local wantedUuids = {}
    if uuids then
        for uuid in uuids:gmatch("[^|]+") do
            wantedUuids[uuid] = true
        end
    end
    SendBatchBuilds(sender, wantedUuids)
end

local function HandleSkip(payload, sender)
    SendBatchBuilds(sender, {})  -- empty = skip all in current batch
end

local function HandleEnd(payload, sender)
    local code, snd, count = payload:match("^(END)|([^|]+)|(.+)$")
    if not code then return end

    EbonBuildsDB.lastSyncDate = SortableNow()

    local c = tonumber(count) or 0
    if c > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff19ff19EbonBuilds|r: Received %d build(s) from %s.", c, snd))
    end

    -- Refresh left panel when a responder finishes
    if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
        EbonBuilds.BuildList.Refresh()
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

function EbonBuilds.Sync.RequestSync()
    local me       = UnitName("player")
    local lastDate = EbonBuildsDB.lastSyncDate or "0"
    local payload  = string.format("REQ|%s|%s", me, lastDate)

    if lastDate == "0" then
        Log("Requesting sync (first time, builds from last 60 days)...")
    else
        Log("Requesting sync (builds newer than " .. lastDate .. ")...")
    end

    -- Broadcast via hidden chat channel (primary discovery path)
    RefreshChannel()
    if syncChannelIndex and GetChannelName(syncChannelIndex) == SYNC_CHANNEL then
        SendChatMessage(payload, "CHANNEL", nil, syncChannelIndex)
        Log("REQ broadcast on hidden channel " .. SYNC_CHANNEL)
    end

    -- Fallback: whisper known peers (redundancy for cross-realm / channel issues)
    EbonBuildsDB.syncPeers = EbonBuildsDB.syncPeers or {}
    local peerCount = 0
    for peer in pairs(EbonBuildsDB.syncPeers) do
        if peer ~= me then
            Enqueue(peer, payload)
            peerCount = peerCount + 1
        end
    end
    if peerCount > 0 then
        Log("REQ also whispered to " .. peerCount .. " known peer(s)")
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
            local msg, sender, _, _, _, _, _, channelName = ...
            HandleChannelMessage(msg, sender, channelName)
        elseif event == "PLAYER_LEVEL_UP" then
            local newLevel = ...
            if newLevel == 80 then
                local build = EbonBuilds.Build.GetActive()
                if build and not build.validated then
                    build.validated = true
                    Log("Build \"" .. (build.title or "?") .. "\" validated (reached level 80)")
                end
            end
        end
    end)
    syncFrame:SetScript("OnUpdate", function()
        if #sendQueue > 0 and Now() >= nextSendTime then
            local entry = sendQueue[1]
            SendAddonMessage(PREFIX, entry.payload, "WHISPER", entry.target)
            table.remove(sendQueue, 1)
            nextSendTime = Now() + SEND_DELAY
        end
    end)

    if RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(PREFIX)
    end

    -- Join and hide the sync channel
    syncChannelIndex = FindOrJoinChannel()
    HideChannelFromChat()

    EbonBuildsDB.lastSyncDate = EbonBuildsDB.lastSyncDate or nil
    EbonBuildsDB.syncPeers    = EbonBuildsDB.syncPeers    or {}
end
