-- EbonBuilds: modules/session/Session.lua
-- Responsibility: session lifecycle management (start, end, log actions).
-- A session spans from level 1 until the player dies and resets back to
-- level 1. Logs are persisted per-session in EbonBuildsDB.sessions.

EbonBuilds.Session = {}

local POLL_INTERVAL = 2  -- seconds between level checks for reset detection

local maxLevel     = 0   -- highest level seen in the active session
local pollFrame    = nil
local pollElapsed  = 0

------------------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------------------

local function GetRunSoulAshes()
    local rd = EbonholdPlayerRunData
    if not rd and ProjectEbonhold and ProjectEbonhold.PlayerRunService then
        local get = ProjectEbonhold.PlayerRunService.GetCurrentData
        if get then rd = get() end
    end
    return (rd and rd.soulPoints) or 0
end

local function GetClassName()
    local _, class = UnitClass("player")
    return class  -- English token (WARRIOR, MAGE, etc.)
end

local function GetActiveBuildTitle()
    local build = EbonBuilds.Build.GetActive()
    return build and build.title or "No Build"
end

local function ThresholdScore(peakScore, pct)
    return math.floor(peakScore * pct / 100)
end

local function FormatDuration(startTime, endTime)
    local t = (endTime or time()) - startTime
    local h = math.floor(t / 3600)
    local m = math.floor((t % 3600) / 60)
    local s = math.floor(t % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function FormatTimestamp(ts)
    return date("%H:%M:%S", ts)
end

local function FormatDateTime(ts)
    if not ts then return "n/a" end
    return date("%Y-%m-%d %H:%M:%S", ts)
end

local function FindBuildForSession(session)
    if not session then
        return EbonBuilds.Build.GetActive()
    end

    local builds = EbonBuildsDB and EbonBuildsDB.builds
    if builds then
        if session.buildId and EbonBuilds.Build.Get then
            local byId = EbonBuilds.Build.Get(session.buildId)
            if byId then return byId end
        end
        if session.buildTitle then
            for _, build in pairs(builds) do
                if build.title == session.buildTitle then
                    return build
                end
            end
        end
    end

    return EbonBuilds.Build.GetActive()
end

local function HasAutomationSnapshot(session)
    local snap = session and session.automationSnapshot
    if not snap or not snap.thresholds then return false end
    local t = snap.thresholds
    return t.autoBanishPct ~= nil
        and t.autoRerollPct ~= nil
        and t.rerollGuardPct ~= nil
        and t.autoFreezePct ~= nil
        and t.freezePenaltyPct ~= nil
end

local function CaptureAutomationSnapshot(build)
    build = build or EbonBuilds.Build.GetActive()
    local settings
    if build then
        EbonBuilds.Build.EnsureSettings(build)
        settings = build.settings
    else
        settings = EbonBuilds.Build.DefaultSettings()
    end

    local peakScore = 1
    if EbonBuilds.Automation and EbonBuilds.Automation.GetPeak then
        peakScore = EbonBuilds.Automation.GetPeak()
    elseif build and EbonBuilds.Scoring and EbonBuilds.Scoring.ComputePeak then
        local _, score = EbonBuilds.Scoring.ComputePeak(build.class, settings)
        peakScore = (score and score > 0) and score or 1
    end

    return {
        buildTitle = build and build.title or "No Build",
        buildId    = build and build.id or nil,
        peakScore  = peakScore,
        source     = "runStart",
        thresholds = {
            autoBanishPct    = settings.autoBanishPct,
            autoRerollPct    = settings.autoRerollPct,
            rerollGuardPct   = settings.rerollGuardPct,
            autoFreezePct    = settings.autoFreezePct,
            freezePenaltyPct = settings.freezePenaltyPct,
        },
    }
end

local function FormatAutomationBlock(snapshot, legacy)
    local lines = {}
    if legacy then
        lines[#lines + 1] = "Automation (current values — no run-start snapshot for this session)"
        lines[#lines + 1] = string.format(
            "Using build: %s",
            snapshot.buildTitle or "No Build")
    elseif snapshot.source == "current" then
        lines[#lines + 1] = "Automation (current values — captured during session)"
        lines[#lines + 1] = string.format(
            "Using build: %s",
            snapshot.buildTitle or "No Build")
    else
        lines[#lines + 1] = "Automation (snapshot at run start)"
    end

    local peak = snapshot.peakScore or 1
    lines[#lines + 1] = string.format("Peak score: %d", peak)

    local t = snapshot.thresholds or {}
    local banPct = t.autoBanishPct or 20
    lines[#lines + 1] = string.format(
        "Auto-banish:     %3d%%  (%d per echo)",
        banPct, ThresholdScore(peak, banPct))

    local rerollPct = t.autoRerollPct or 120
    lines[#lines + 1] = string.format(
        "Auto-reroll:    %3d%%  (%d sum of 3 echoes)",
        rerollPct, ThresholdScore(peak, rerollPct))

    local guardPct = t.rerollGuardPct or 90
    lines[#lines + 1] = string.format(
        "Reroll guard:    %3d%%  (%d blocks reroll if any echo >= this)",
        guardPct, ThresholdScore(peak, guardPct))

    local freezePct = t.autoFreezePct or 80
    lines[#lines + 1] = string.format(
        "Auto-freeze:     %3d%%  (%d per echo)",
        freezePct, ThresholdScore(peak, freezePct))

    local penaltyPct = t.freezePenaltyPct or 10
    local mult = 1 - penaltyPct / 100
    lines[#lines + 1] = string.format(
        "Freeze penalty:  %3d%%  (frozen echo score x%.2f)",
        penaltyPct, mult)

    return table.concat(lines, "\n")
end

local function FormatEchoCell(choice, isTarget)
    if not choice then return "" end
    local text = string.format("%s (%.0f)", choice.name, choice.score)
    if isTarget then
        text = ">>" .. text .. "<<"
    end
    return text
end

local function FormatLogBlock(session)
    local logs = session.logs or {}
    if #logs == 0 then return "" end

    local actionW = 6
    local echoW = 24
    for _, entry in ipairs(logs) do
        actionW = math.max(actionW, #(entry.action or ""))
        for j, ch in ipairs(entry.choices or {}) do
            echoW = math.max(echoW, #FormatEchoCell(ch, j == entry.targetIndex))
        end
    end

    local numW = math.max(3, #tostring(#logs))
    local chargeW = 11

    local function Row(cols)
        return table.concat(cols, " | ")
    end

    local function Pad(width, text, right)
        text = text or ""
        if right then
            return string.format("%" .. width .. "s", text)
        end
        return string.format("%-" .. width .. "s", text)
    end

    local header = Row({
        Pad(numW, "#"),
        Pad(actionW, "Action"),
        Pad(echoW, "Echo 1"),
        Pad(echoW, "Echo 2"),
        Pad(echoW, "Echo 3"),
        Pad(chargeW, "Charges"),
    })

    local divider = Row({
        string.rep("-", numW),
        string.rep("-", actionW),
        string.rep("-", echoW),
        string.rep("-", echoW),
        string.rep("-", echoW),
        string.rep("-", chargeW),
    })

    local lines = {}
    lines[#lines + 1] = string.format("Logbook (%d actions)", #logs)
    lines[#lines + 1] = header
    lines[#lines + 1] = divider

    for i, entry in ipairs(logs) do
        local ch = entry.charges or {}
        local charges = string.format("B:%d R:%d F:%d",
            ch.ban or 0, ch.reroll or 0, ch.freeze or 0)
        lines[#lines + 1] = Row({
            Pad(numW, tostring(i), true),
            Pad(actionW, entry.action or ""),
            Pad(echoW, FormatEchoCell(entry.choices[1], entry.targetIndex == 1)),
            Pad(echoW, FormatEchoCell(entry.choices[2], entry.targetIndex == 2)),
            Pad(echoW, FormatEchoCell(entry.choices[3], entry.targetIndex == 3)),
            Pad(chargeW, charges),
        })
    end

    return table.concat(lines, "\n")
end

local function CreateSession()
    local sessions = EbonBuildsDB.sessions
    local id = tostring(time()) .. "-" .. tostring(#sessions + 1)

    local activeBuild = EbonBuilds.Build.GetActive()
    local session = {
        id            = id,
        characterName = UnitName("player"),
        className     = GetClassName(),
        startTime     = time(),
        endTime       = nil,
        soulAshes     = 0,
        buildTitle    = GetActiveBuildTitle(),
        buildId       = activeBuild and activeBuild.id or nil,
        logs          = {},
    }

    table.insert(sessions, 1, session)
    EbonBuildsDB.currentSessionIndex = 1
    maxLevel = UnitLevel("player")

    if EbonBuilds.Automation and EbonBuilds.Automation.ResetRunState then
        EbonBuilds.Automation.ResetRunState()
    end

    session.automationSnapshot = CaptureAutomationSnapshot()

    -- Shift existing indices since we inserted at position 1
    for i = 2, #sessions do
        -- indices are relative to array position; no reindex needed since
        -- currentSessionIndex always points to the live session at [1]
    end

    return session
end

------------------------------------------------------------------------
-- Event handlers
------------------------------------------------------------------------

local function OnPlayerEnteringWorld()
    local level = UnitLevel("player")

    -- No active session: start one at the current level
    if not EbonBuildsDB.currentSessionIndex then
        CreateSession()
        return
    end

    -- Active session exists, but player is now level 1 after being higher:
    -- the run ended (death accepted, reset to level 1)
    if level == 1 and maxLevel > 1 then
        EbonBuilds.Session.EndCurrentSession()
        CreateSession()
        return
    end

    -- Update max level if player leveled up while offline / zoning
    if level > maxLevel then
        maxLevel = level
    end
end

local function OnPlayerLevelUp(newLevel)
    if not EbonBuildsDB.currentSessionIndex then
        -- No session yet: start one at the current level
        CreateSession()
        return
    end

    if newLevel > maxLevel then
        maxLevel = newLevel
    end
end

local function OnPollUpdate(self, dt)
    pollElapsed = pollElapsed + dt
    if pollElapsed < POLL_INTERVAL then return end
    pollElapsed = 0

    local level = UnitLevel("player")

    -- Level reset detection: player went from >1 back to 1
    if EbonBuildsDB.currentSessionIndex and level == 1 and maxLevel > 1 then
        EbonBuilds.Session.EndCurrentSession()
        CreateSession()
        return
    end

    if level > maxLevel then
        maxLevel = level
    end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

function EbonBuilds.Session.EndCurrentSession()
    local idx = EbonBuildsDB.currentSessionIndex
    if not idx then return end

    local session = EbonBuildsDB.sessions[idx]
    if not session then
        EbonBuildsDB.currentSessionIndex = nil
        return
    end

    session.endTime   = time()
    session.soulAshes = GetRunSoulAshes()
    session.maxLevel  = maxLevel

    local build = EbonBuilds.Build.GetActive()
    if build and EbonBuilds.Build.RecordRunEnd then
        local rd = _G.EbonholdPlayerRunData
        EbonBuilds.Build.RecordRunEnd(build, {
            reachedMax = rd and rd.hasReachedMaxLevel or false,
            maxLevel   = maxLevel,
        })
    end

    EbonBuildsDB.currentSessionIndex = nil
    maxLevel = 0
end

function EbonBuilds.Session.LogAction(scored, action, targetIndex)
    -- Detect run reset: player is level 1 but we tracked a higher peak.
    -- This catches resets that happen without a loading screen where
    -- PLAYER_ENTERING_WORLD never fires.
    local level = UnitLevel("player")
    if EbonBuildsDB.currentSessionIndex and level == 1 and maxLevel > 1 then
        EbonBuilds.Session.EndCurrentSession()
        CreateSession()
    end

    local idx = EbonBuildsDB.currentSessionIndex
    if not idx then
        -- No active session yet: create one on the fly so logs are never lost
        CreateSession()
        idx = EbonBuildsDB.currentSessionIndex
        if not idx then return end
    end

    local session = EbonBuildsDB.sessions[idx]
    if not session then return end

    if not HasAutomationSnapshot(session) then
        local snap = CaptureAutomationSnapshot(FindBuildForSession(session))
        snap.source = "current"
        session.automationSnapshot = snap
    end

    local choices = {}
    for _, s in ipairs(scored) do
        choices[#choices + 1] = {
            name    = s.name,
            score   = s.score,
            quality = s.quality,
        }
    end

    local rd = EbonholdPlayerRunData
    if not rd and ProjectEbonhold and ProjectEbonhold.PlayerRunService then
        local get = ProjectEbonhold.PlayerRunService.GetCurrentData
        if get then rd = get() end
    end

    local charges = {
        ban    = (rd and rd.remainingBanishes) or 0,
        reroll = (rd and ((rd.totalRerolls or 0) - (rd.usedRerolls or 0))) or 0,
        freeze = (rd and ((rd.totalFreezes or 0) - (rd.usedFreezes or 0))) or 0,
    }

    local entry = {
        timestamp   = time(),
        action      = action,
        choices     = choices,
        targetIndex = targetIndex,
        charges     = charges,
    }

    session.logs[#session.logs + 1] = entry
end

function EbonBuilds.Session.GetSessions()
    return EbonBuildsDB.sessions or {}
end

function EbonBuilds.Session.GetActiveSession()
    local idx = EbonBuildsDB.currentSessionIndex
    if not idx then return nil end
    return EbonBuildsDB.sessions[idx]
end

function EbonBuilds.Session.DeleteSession(id)
    -- Refuse to delete the active session individually
    if EbonBuildsDB.currentSessionIndex then
        local active = EbonBuildsDB.sessions[EbonBuildsDB.currentSessionIndex]
        if active and active.id == id then
            return false
        end
    end

    local sessions = EbonBuildsDB.sessions
    for i, s in ipairs(sessions) do
        if s.id == id then
            if EbonBuildsDB.currentSessionIndex and i < EbonBuildsDB.currentSessionIndex then
                EbonBuildsDB.currentSessionIndex = EbonBuildsDB.currentSessionIndex - 1
            end
            table.remove(sessions, i)
            return true
        end
    end
    return false
end

function EbonBuilds.Session.ClearAllSessions()
    EbonBuildsDB.sessions = {}
    EbonBuildsDB.currentSessionIndex = nil
    maxLevel = 0
    -- Immediately create a fresh session at the current player level
    CreateSession()
end

function EbonBuilds.Session.FormatReport(session)
    if not session then
        return "No session selected."
    end

    local lines = {}
    lines[#lines + 1] = "EbonBuilds Logbook Report"
    lines[#lines + 1] = string.format(
        "Character: %s | Class: %s | Build: %s",
        session.characterName or "Unknown",
        session.className or "Unknown",
        session.buildTitle or "No Build")
    lines[#lines + 1] = string.format(
        "Session: Level %d | Duration: %s | Soul Ashes: %s",
        session.maxLevel or (UnitLevel and UnitLevel("player")) or 0,
        FormatDuration(session.startTime or time(), session.endTime),
        session.endTime and tostring(session.soulAshes or 0) or "...")
    lines[#lines + 1] = string.format(
        "Started: %s%s",
        FormatDateTime(session.startTime),
        session.endTime and (" | Ended: " .. FormatDateTime(session.endTime)) or "")
    lines[#lines + 1] = ""

    local snapshot, legacy
    if HasAutomationSnapshot(session) then
        snapshot = session.automationSnapshot
        legacy = session.automationSnapshot.source == "current"
    else
        snapshot = CaptureAutomationSnapshot(FindBuildForSession(session))
        legacy = true
    end
    lines[#lines + 1] = FormatAutomationBlock(snapshot, legacy)
    lines[#lines + 1] = ""

    local logBlock = FormatLogBlock(session)
    if logBlock ~= "" then
        lines[#lines + 1] = logBlock
    end

    return table.concat(lines, "\n")
end

function EbonBuilds.Session.DeleteLogEntry(sessionId, logIndex)
    local sessions = EbonBuildsDB.sessions
    for _, s in ipairs(sessions) do
        if s.id == sessionId then
            if s.logs and logIndex >= 1 and logIndex <= #s.logs then
                table.remove(s.logs, logIndex)
                return true
            end
            return false
        end
    end
    return false
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function EbonBuilds.Session.Init()
    -- Ensure DB arrays exist
    EbonBuildsDB.sessions = EbonBuildsDB.sessions or {}
    if EbonBuildsDB.currentSessionIndex == nil then
        EbonBuildsDB.currentSessionIndex = nil  -- normalize falsey
    end

    -- Event frame for lifecycle detection
    local ef = CreateFrame("Frame", nil, UIParent)
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    ef:RegisterEvent("PLAYER_LEVEL_UP")
    ef:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_ENTERING_WORLD" then
            OnPlayerEnteringWorld()
        elseif event == "PLAYER_LEVEL_UP" then
            OnPlayerLevelUp(...)
        end
    end)

    -- Polling frame for level reset detection without loading screen
    pollFrame = CreateFrame("Frame", nil, UIParent)
    pollFrame:SetScript("OnUpdate", OnPollUpdate)
end
