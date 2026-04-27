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

local EVAL_DELAY = 2  -- seconds before evaluating (TODO: make configurable)

local evalTimerFrame   = nil
local evalTimerElapsed = 0
local evalTimerActive  = false
local pendingChoices   = nil
local origPerkUIShow   = nil

------------------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------------------

local function StartEvalTimer()
    if not evalTimerFrame then
        evalTimerFrame = CreateFrame("Frame")
        evalTimerFrame:SetScript("OnUpdate", function(self, dt)
            evalTimerElapsed = evalTimerElapsed + dt
            if evalTimerElapsed >= EVAL_DELAY then
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
    local score  = EbonBuilds.Scoring.Score(entry, weight, settings)
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
        if not whitelist[key] then return false end
    end
    return true
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

function EbonBuilds.Automation.Evaluate()
    local build = EbonBuilds.Build.GetActive()
    if not build or not build.automationEnabled then return false end

    local choices = ProjectEbonhold.PerkService.GetCurrentChoice()
    if not choices or #choices == 0 then return false end

    local settings   = build.settings or EbonBuilds.Build.DefaultSettings()
    local runData    = GetRunData()
    local lockedList = build.lockedEchoes or {}

    local _, peakScore = EbonBuilds.Scoring.ComputePeak(build.class, settings)
    if not peakScore or peakScore == 0 then peakScore = 1 end

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
                        LogAndToast(scored, "Banish", s.index)
                        return true
                    end
                end
            end
        end
    end

    --------------------------------------------------------------------
    -- 2. TRY REROLL
    --------------------------------------------------------------------
    if runData and (runData.totalRerolls or 0) - (runData.usedRerolls or 0) > 0 then
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

    --------------------------------------------------------------------
    -- 3. TRY FREEZE
    --------------------------------------------------------------------
    if runData and (runData.totalFreezes or 0) - (runData.usedFreezes or 0) > 0 then
        local threshold = math.floor(peakScore * settings.autoFreezePct / 100)

        -- Offered choices above freeze threshold
        local aboveChoices = {}
        for _, s in ipairs(scored) do
            if not s.isFrozen and not s.isCarried and s.score > threshold then
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

        if (#aboveChoices + lockedAbove) >= 2 and #aboveChoices > 0 then
            table.sort(aboveChoices, function(a, b) return a.score > b.score end)
            local target = aboveChoices[1]
            local ok = ProjectEbonhold.PerkService.FreezePerk(target.index - 1)
            if ok then
                UpdateStat(build, "freezesUsed")
                LogAndToast(scored, "Freeze", target.index)
                -- Freeze is not terminal; proceed to select the best remaining
                local _, pick = TrySelect(scored, settings, build)
                if pick then
                    LogAndToast(scored, "Select", pick.index)
                end
                return true
            end
        end
    end

    --------------------------------------------------------------------
    -- 4. SELECT (fallback)
    --------------------------------------------------------------------
    local ok, pick = TrySelect(scored, settings, build)
    if ok and pick then
        LogAndToast(scored, "Select", pick.index)
    end
    return ok
end

------------------------------------------------------------------------
-- Hook installation
------------------------------------------------------------------------

function EbonBuilds.Automation.Init()
    if not ProjectEbonhold or not ProjectEbonhold.PerkUI then return end
    if ProjectEbonhold.PerkUI._ebonBuildsHooked then return end

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
