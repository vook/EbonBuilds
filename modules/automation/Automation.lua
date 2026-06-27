-- EbonBuilds: modules/automation/Automation.lua
-- Responsibility: evaluate offered echo choices against the active build's
-- automation thresholds and execute the optimal action (banish -> reroll ->
-- freeze -> select). Pre-hooks PerkUI.Show so automation runs before the
-- native UI appears.

EbonBuilds.Automation = {}

local FAMILY_MAP = {
    Tank = "Tank", Survivability = "Survivability", Healer = "Healer",
    Caster = "Caster", ["Caster DPS"] = "Caster",
    Melee  = "Melee",  ["Melee DPS"]  = "Melee",
    Ranged = "Ranged", ["Ranged DPS"] = "Ranged",
    None   = "No family",
}

local function GetEvalDelay()
    return (EbonBuildsDB.globalSettings and EbonBuildsDB.globalSettings.evalDelay) or 2
end

local evalTimerFrame    = nil
local evalTimerElapsed  = 0
local evalTimerActive   = false
local pendingChoices    = nil
local origPerkUIShow    = nil
local freezeRoundActive    = false  -- true after freeze batch, cleared on select
local locallyFrozenIndices = {}     -- indices frozen this round, for penalty tracking
local cachedPeak           = nil    -- locked at first evaluation of the run

local MAX_LEVEL_SHUTDOWN_DELAY = 20  -- seconds of inactivity after level 80 before disabling
local maxLevelReached          = false
local maxLevelShutdownFrame    = nil
local maxLevelShutdownElapsed  = 0
local maxLevelEventFrame       = nil
local wasAutoDisabled          = false  -- true when the shutdown timer (not the user) disabled automation

------------------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------------------

local function StartEvalTimer()
    if not evalTimerFrame then
        evalTimerFrame = CreateFrame("Frame")
        evalTimerFrame:SetScript("OnUpdate", function(self, dt)
            evalTimerElapsed = evalTimerElapsed + dt
            if evalTimerElapsed >= GetEvalDelay() then
                evalTimerActive = false
                evalTimerFrame:Hide()
                if EbonBuilds.Automation.Evaluate() then
                    pendingChoices = nil
                    return
                end
                -- Automation couldn't act, show the native perk UI
                if pendingChoices and origPerkUIShow then
                    origPerkUIShow(pendingChoices)
                end
                pendingChoices = nil
            end
        end)
    end
    evalTimerElapsed = 0
    evalTimerActive = true
    evalTimerFrame:Show()
end

local function StartMaxLevelShutdownTimer()
    if not maxLevelShutdownFrame then
        maxLevelShutdownFrame = CreateFrame("Frame")
        maxLevelShutdownFrame:SetScript("OnUpdate", function(self, dt)
            maxLevelShutdownElapsed = maxLevelShutdownElapsed + dt
            if maxLevelShutdownElapsed >= MAX_LEVEL_SHUTDOWN_DELAY then
                self:Hide()
                maxLevelShutdownElapsed = 0
                local build = EbonBuilds.Build.GetActive()
                if build and build.automationEnabled then
                    build.automationEnabled = false
                    EbonBuilds.Build.Save(build.id, build)
                    wasAutoDisabled = true
                    EbonBuildsDB._autoDisabledAt80 = true
                end
                maxLevelReached = false
            end
        end)
    end
    maxLevelShutdownElapsed = 0
    maxLevelShutdownFrame:Show()
end

-- Returns the cached peak (computed at first evaluation of the current run).
-- The peak includes novelty and is locked for the duration of the run so
-- threshold percentages remain stable.
function EbonBuilds.Automation.GetPeak()
    if cachedPeak then return cachedPeak end
    local build = EbonBuilds.Build.GetActive()
    if not build then return 1 end
    local settings = EbonBuilds.Scoring.GetEffectiveSettings()
    local _, score = EbonBuilds.Scoring.ComputePeak(build.class, settings)
    cachedPeak = (score and score > 0) and score or 1
    return cachedPeak
end

function EbonBuilds.Automation.ResetPeakCache()
    cachedPeak = nil
end

local function GetRunData()
    if EbonholdPlayerRunData and EbonholdPlayerRunData.remainingBanishes ~= nil then
        return EbonholdPlayerRunData
    end
    if ProjectEbonhold and ProjectEbonhold.PlayerRunService then
        local get = ProjectEbonhold.PlayerRunService.GetCurrentData
        if get then return get() end
    end
    return nil
end

local function ScoreChoice(choice, settings)
    local spellId = choice.spellId
    local name = GetSpellInfo(spellId)
    if not name then return nil end
    local data = ProjectEbonhold.PerkDatabase[spellId]
    if not data then return nil end
    local entry = {
        spellId   = spellId,
        name      = name,
        quality   = choice.quality,
        families  = data.families,
        classMask = data.classMask,
    }
    local weight = EbonBuilds.Weights.Get(name) or 0
    -- Novelty only applies if the player has never picked this echo (by name,
    -- across all quality tiers). Once picked, all qualities lose the bonus.
    local granted = ProjectEbonhold.PerkService.GetGrantedPerks()
    local isNovel = not granted or not granted[name]
    local score
    if isNovel then
        score = EbonBuilds.Scoring.Score(entry, weight, settings)
    else
        score = EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, entry.quality)
    end
    -- Freeze penalty: frozen and carried echoes get a score reduction so they
    -- are deprioritized in subsequent evaluations until eventually picked.
    if (choice.isFrozen or choice.isCarried) and settings.freezePenaltyPct and settings.freezePenaltyPct > 0 then
        score = score * (1 - settings.freezePenaltyPct / 100)
    end
    return {
        index     = 0,
        spellId   = spellId,
        name      = name,
        quality   = choice.quality,
        score     = score,
        entry     = entry,
        data      = data,
        isFrozen  = choice.isFrozen,
        isCarried = choice.isCarried,
    }
end

local function NormFamily(f) return FAMILY_MAP[f] end

local function IsProtected(data, whitelist)
    if not whitelist or next(whitelist) == nil then return false end
    local families = data.families
    if not families or #families == 0 then
        return whitelist["No family"] or false
    end
    for _, fam in ipairs(families) do
        local key = NormFamily(fam) or fam
        if whitelist[key] then return true end
    end
    return false
end

local function ScoreLockedEcho(lockedId, settings)
    local name = GetSpellInfo(lockedId)
    if not name then return 0 end
    local data = ProjectEbonhold.PerkDatabase[lockedId]
    if not data then return 0 end
    local entry = {
        spellId   = lockedId,
        name      = name,
        quality   = data.quality or 0,
        families  = data.families,
        classMask = data.classMask,
    }
    local w = EbonBuilds.Weights.Get(name) or 0
    return EbonBuilds.Scoring.Score(entry, w, settings)
end

local function UpdateStat(build, key)
    if build and build.stats then
        build.stats[key] = (build.stats[key] or 0) + 1
    end
end

local function LogAndToast(scored, action, targetIndex)
    EbonBuilds.Toast.ShowAutomationResult(scored, action, targetIndex)
    EbonBuilds.Session.LogAction(scored, action, targetIndex)
end

------------------------------------------------------------------------
-- Action attempts (called in priority order)
------------------------------------------------------------------------

local function TrySelect(scored, settings, build)
    local banList = settings.echoBanList or {}
    local nonBanned, all = {}, {}
    for _, s in ipairs(scored) do
        all[#all + 1] = s
        if not banList[s.spellId] then
            nonBanned[#nonBanned + 1] = s
        end
    end
    local candidates = #nonBanned > 0 and nonBanned or all
    if #candidates == 0 then return false, nil end

    table.sort(candidates, function(a, b) return a.score > b.score end)

    local pick
    if #nonBanned == 0 and settings.echoBanAllMode == "random" then
        pick = candidates[math.random(1, #candidates)]
    else
        pick = candidates[1]
    end

    ProjectEbonhold.PerkService.SelectPerk(pick.spellId)
    UpdateStat(build, "picks")
    return true, pick
end

local function AnnotateScored(scored, banList, whitelist, lockedList)
    for _, s in ipairs(scored) do
        s.isBanned    = banList[s.spellId] and true or false
        s.isProtected = IsProtected(s.data, whitelist)
        s.isLocked    = false
        for _, lockedId in ipairs(lockedList) do
            if lockedId and lockedId == s.spellId then
                s.isLocked = true
                break
            end
        end
    end
end

------------------------------------------------------------------------
-- Main evaluation entry point
------------------------------------------------------------------------

local evalInProgress = false

function EbonBuilds.Automation.Evaluate()
    if evalInProgress then return false end
    evalInProgress = true

    local function body()
        -- While echoes are still being offered at max level, keep
        -- resetting the shutdown countdown so queued echoes are
        -- processed before automation is disabled.
        if maxLevelReached and UnitLevel("player") == 80 then
            StartMaxLevelShutdownTimer()
        end

        local build = EbonBuilds.Build.GetActive()
        if not build or not build.automationEnabled then return false end

        local choices = ProjectEbonhold.PerkService.GetCurrentChoice()
        if not choices or #choices == 0 then return false end

        local settings   = EbonBuilds.Scoring.GetEffectiveSettings()
        local runData    = GetRunData()
        local lockedList = build.lockedEchoes or {}

        local peakScore = EbonBuilds.Automation.GetPeak()

        -- Score all offered choices
        local scored = {}
        for i, choice in ipairs(choices) do
            local s = ScoreChoice(choice, settings)
            if s then
                s.index = i -- 1-based
                scored[#scored + 1] = s
            end
        end
        if #scored == 0 then return false end

        local banList    = settings.echoBanList or {}
        local whitelist  = settings.banishFamilyWhitelist or {}
        AnnotateScored(scored, banList, whitelist, lockedList)

        -- PRE-CHECK: if any offered echo matches a locked echo slot, select it
        for _, s in ipairs(scored) do
            for _, lockedId in ipairs(lockedList) do
                if lockedId and lockedId == s.spellId then
                    ProjectEbonhold.PerkService.SelectPerk(s.spellId)
                    UpdateStat(build, "picks")
                    LogAndToast(scored, "Select (Locked)", s.index)
                    return true
                end
            end
        end

        --------------------------------------------------------------------
        -- 1. TRY BANISH (highest action priority)
        --------------------------------------------------------------------
        if runData and (runData.remainingBanishes or 0) > 0 then
            table.sort(scored, function(a, b) return a.score < b.score end)

            -- Ban-list echoes first (these have minimum priority)
            for _, s in ipairs(scored) do
                if not s.isFrozen and not s.isCarried and banList[s.spellId] then
                    if not s.isProtected then
                        local ok = ProjectEbonhold.PerkService.BanishPerk(s.index - 1)
                        if ok then
                            UpdateStat(build, "banishesUsed")
                            table.sort(scored, function(a, b) return a.index < b.index end)
                            LogAndToast(scored, "Banish", s.index)
                            return true
                        end
                    end
                end
            end

            -- Then echoes below autoBanishPct threshold
            local threshold = math.floor(peakScore * settings.autoBanishPct / 100)
            for _, s in ipairs(scored) do
                if not s.isFrozen and not s.isCarried and s.score < threshold then
                    if not s.isProtected then
                        local ok = ProjectEbonhold.PerkService.BanishPerk(s.index - 1)
                        if ok then
                            UpdateStat(build, "banishesUsed")
                            table.sort(scored, function(a, b) return a.index < b.index end)
                            LogAndToast(scored, "Banish", s.index)
                            return true
                        end
                    end
                end
            end
        end

        -- Restore original display order (left-to-right by index) after the
        -- banish step may have re-sorted by score.
        table.sort(scored, function(a, b) return a.index < b.index end)

        --------------------------------------------------------------------
        -- 2. TRY REROLL
        --------------------------------------------------------------------
        if runData and (runData.totalRerolls or 0) - (runData.usedRerolls or 0) > 0 then
            -- Reroll guard: skip if any single echo is above the guard threshold,
            -- regardless of the sum. Prevents rerolling when one good echo is
            -- offered alongside weak ones.
            local guardPct = settings.rerollGuardPct or 90
            local guardThreshold = math.floor(peakScore * guardPct / 100)
            local blockedByGuard = false
            for _, s in ipairs(scored) do
                if s.score >= guardThreshold then
                    blockedByGuard = true
                    break
                end
            end
            if not blockedByGuard then
                local sum = 0
                for _, s in ipairs(scored) do sum = sum + s.score end
                if sum < peakScore * settings.autoRerollPct / 100 then
                    local ok = ProjectEbonhold.PerkService.RequestReroll()
                    if ok then
                        UpdateStat(build, "rerollsUsed")
                        LogAndToast(scored, "Reroll", 0)
                        return true
                    end
                end
            end
        end

        --------------------------------------------------------------------
        --------------------------------------------------------------------
        -- 3. TRY FREEZE
        --------------------------------------------------------------------
        -- Freeze one echo per evaluation so the server has time to confirm
        -- each freeze before the next one.  The timer re-invokes Evaluate()
        -- which scores fresh (reflecting isFrozen / isCarried state) and
        -- applies the penalty to locally-frozen echoes so their scores
        -- degrade toward the eventual pick.
        if runData and (runData.totalFreezes or 0) - (runData.usedFreezes or 0) > 0 then
            local penalty = (settings.freezePenaltyPct or 0) / 100

            -- Apply freeze penalty to echoes we already froze this round
            -- so they are deprioritised in subsequent evaluations.
            -- Only applied when the server hasn't confirmed isFrozen yet;
            -- ScoreChoice already handles the penalty once isFrozen is true.
            if penalty > 0 then
                for _, s in ipairs(scored) do
                    if locallyFrozenIndices[s.index] and not s.isFrozen then
                        s.score = math.floor(s.score * (1 - penalty))
                    end
                end
            end

            local threshold = math.floor(peakScore * settings.autoFreezePct / 100)

            -- Offered choices above freeze threshold, excluding echoes that
            -- are already frozen (server), carried, or locally frozen this round.
            local aboveChoices = {}
            for _, s in ipairs(scored) do
                if not s.isFrozen and not s.isCarried and not locallyFrozenIndices[s.index] and s.score > threshold then
                    aboveChoices[#aboveChoices + 1] = s
                end
            end

            -- Locked echoes above freeze threshold
            local lockedAbove = 0
            for _, lockedId in ipairs(lockedList) do
                if lockedId then
                    local ls = ScoreLockedEcho(lockedId, settings)
                    if ls > threshold then lockedAbove = lockedAbove + 1 end
                end
            end

            -- Requires at least 2 offered echoes above threshold so we can
            -- freeze the lowest and select a different highest one.
            if (#aboveChoices + lockedAbove) >= 2 and #aboveChoices >= 2 then
                table.sort(aboveChoices, function(a, b) return a.score > b.score end)

                -- Freeze the single lowest-scored echo above the threshold.
                -- (Multiple would race the server; one-per-eval is reliable.)
                local lowest = aboveChoices[#aboveChoices]
                local ok = ProjectEbonhold.PerkService.FreezePerk(lowest.index - 1)
                if ok then
                    UpdateStat(build, "freezesUsed")
                    locallyFrozenIndices[lowest.index] = true

                    -- Optimistically update runData so the toast and session log
                    -- reflect the correct remaining freeze count immediately.
                    if runData and runData.usedFreezes ~= nil then
                        runData.usedFreezes = runData.usedFreezes + 1
                    end

                    LogAndToast(scored, "Freeze", lowest.index)
                    freezeRoundActive = true
                    StartEvalTimer()
                    return true
                end
            end
        end

        --------------------------------------------------------------------
        -- 4. SELECT (fallback)
        --------------------------------------------------------------------
        locallyFrozenIndices = {}
        freezeRoundActive = false
        local ok, pick = TrySelect(scored, settings, build)
        if ok and pick then
            LogAndToast(scored, "Select", pick.index)
        end
        return ok
    end

    local result = body()
    evalInProgress = false
    return result
end

------------------------------------------------------------------------
-- Hook installation
------------------------------------------------------------------------

function EbonBuilds.Automation.Init()
    if not ProjectEbonhold or not ProjectEbonhold.PerkUI then return end
    if ProjectEbonhold.PerkUI._ebonBuildsHooked then return end

    -- Schedule automation shutdown when the player hits max level.
    -- The timer resets every time Evaluate() runs, so queued echoes
    -- from the level-80 ding are processed before disabling.
    if not maxLevelEventFrame then
        maxLevelEventFrame = CreateFrame("Frame")
        maxLevelEventFrame:RegisterEvent("PLAYER_LEVEL_UP")
        maxLevelEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        maxLevelEventFrame:SetScript("OnEvent", function(_, event, level)
            if event == "PLAYER_LEVEL_UP" then
                if level == 80 then
                    maxLevelReached = true
                    StartMaxLevelShutdownTimer()
                end
            elseif event == "PLAYER_ENTERING_WORLD" then
                if UnitLevel("player") < 80 then
                    if wasAutoDisabled or EbonBuildsDB._autoDisabledAt80 then
                        local build = EbonBuilds.Build.GetActive()
                        if build and not build.automationEnabled then
                            build.automationEnabled = true
                            EbonBuilds.Build.Save(build.id, build)
                        end
                        wasAutoDisabled = false
                        EbonBuildsDB._autoDisabledAt80 = nil
                        maxLevelReached = false
                    end
                end
            end
        end)
    end

    -- Handle reload at 80: PLAYER_LEVEL_UP won't fire again.
    -- Also handle reload below 80 after an auto-disable (reset before PEW fired).
    local currentLevel = UnitLevel("player")
    if currentLevel == 80 then
        local build = EbonBuilds.Build.GetActive()
        if build and build.automationEnabled then
            maxLevelReached = true
            StartMaxLevelShutdownTimer()
            EbonBuildsDB._autoDisabledAt80 = nil
        elseif build and EbonBuildsDB._autoDisabledAt80 then
            EbonBuildsDB._autoDisabledAt80 = nil
        end
    elseif currentLevel < 80 and EbonBuildsDB._autoDisabledAt80 then
        local build = EbonBuilds.Build.GetActive()
        if build and not build.automationEnabled then
            build.automationEnabled = true
            EbonBuilds.Build.Save(build.id, build)
        end
        EbonBuildsDB._autoDisabledAt80 = nil
    end

    local PerkUI = ProjectEbonhold.PerkUI

    -- Pre-hook Show: suppress the native UI and start a delayed evaluation.
    -- A timer gives the game time to fully set up the choice data before
    -- automation tries to act on it, preventing race conditions that cause
    -- the perk window to disappear without any action being taken.
    origPerkUIShow = PerkUI.Show
    PerkUI.Show = function(choices)
        pendingChoices = choices
        StartEvalTimer()
    end

    -- Post-hook UpdateSinglePerk: called after a banish replacement animates
    -- the card. Start a fresh timer so automation can chain actions (e.g.
    -- banish the replacement if it is also below threshold).
    hooksecurefunc(PerkUI, "UpdateSinglePerk", function()
        StartEvalTimer()
    end)

    PerkUI._ebonBuildsHooked = true
end

-- Exported for unit testing
EbonBuilds.Automation._ScoreChoice       = ScoreChoice
EbonBuilds.Automation._TrySelect         = TrySelect
EbonBuilds.Automation._AnnotateScored    = AnnotateScored
EbonBuilds.Automation._IsProtected       = IsProtected
EbonBuilds.Automation._ResetFreezeRound  = function()
    freezeRoundActive = false
    locallyFrozenIndices = {}
end
