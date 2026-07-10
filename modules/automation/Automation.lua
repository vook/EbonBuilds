-- EbonBuilds: modules/automation/Automation.lua
-- Responsibility: evaluate offered echo choices against the active build's
-- automation thresholds and execute the optimal action (banish -> reroll ->
-- freeze -> select). Hooks PerkUI.Show after the native UI opens.

EbonBuilds.Automation = {}

local FAMILY_MAP = {
    Tank = "Tank", Survivability = "Survivability", Healer = "Healer",
    Caster = "Caster", ["Caster DPS"] = "Caster",
    Melee  = "Melee",  ["Melee DPS"]  = "Melee",
    Ranged = "Ranged", ["Ranged DPS"] = "Ranged",
    None   = "No family",
}

local function GetEvalDelay()
    return (EbonBuildsDB.globalSettings and EbonBuildsDB.globalSettings.evalDelay) or 0.1
end

local evalTimerFrame    = nil
local evalTimerElapsed  = 0
local evalTimerActive   = false
local evalInProgress    = false
local pendingChoices    = nil
local pendingWaitCount  = 0
local PENDING_WAIT_MAX  = 50
local suppressAutoHook  = false
local hooksInstalled    = false
local hideHookInstalled = false
local nativePerkUIShow  = nil
local freezeRoundActive       = false
local locallyFrozenIndices    = {}
local seenEchoFamilies        = {}
local echoOffersThisRun       = 0

local SHOW_DEBOUNCE     = 0.5
local lastShowChoices   = nil
local lastShowTime      = 0

local POLICY_IGNORE_FACTOR = 0.05
local RARE_QUALITY         = 2
local MAX_AUTOMATION_LEVEL = 80

local function ChoiceSignature(choices)
    if not choices then return nil end
    local parts = {}
    for i = 1, #choices do
        parts[i] = tostring(choices[i].spellId or 0) .. ":" .. tostring(choices[i].quality or 0)
    end
    return table.concat(parts, "|")
end

local function ResolveBuildWeights(build)
    if not build then return nil end
    local w = build.echoWeights
    if w and next(w) then return w end
    return nil
end

local function GetGrantedPerks()
    if EbonBuilds.EchoOwnership and EbonBuilds.EchoOwnership.GetGrantedPerksMap then
        return EbonBuilds.EchoOwnership.GetGrantedPerksMap()
    end
    if ProjectEbonhold and ProjectEbonhold.PerkService then
        return ProjectEbonhold.PerkService.GetGrantedPerks() or {}
    end
    return {}
end

local ResetAutomationRound

------------------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------------------

local function GetLivePickChoices()
    local ps = ProjectEbonhold and ProjectEbonhold.PerkService
    if not ps or not ps.GetCurrentChoice then return nil end
    local choices = ps.GetCurrentChoice()
    if choices and #choices > 0 then return choices end
    return nil
end

local function StopEvalTimer()
    evalTimerActive = false
    evalTimerElapsed = 0
    if evalTimerFrame then
        evalTimerFrame:Hide()
    end
end

local function ClearPickState()
    pendingChoices = nil
    pendingWaitCount = 0
    StopEvalTimer()
end

local function ClearPickStateIfStale()
    if not pendingChoices then return end
    if not GetLivePickChoices() then
        ClearPickState()
    end
end

local function ClearStuckPendingActions()
    local perks = ProjectEbonhold and ProjectEbonhold.Perks
    if not perks then return end
    perks.pendingSelectSpellId = nil
    perks.pendingBanishIndex = nil
    perks.pendingReroll = nil
    perks.pendingFreezeIndex = nil
end

local function IsInActivePickWindow()
    return GetLivePickChoices() ~= nil
end

local function ShouldSuspendAtMaxLevel()
    return UnitLevel("player") >= MAX_AUTOMATION_LEVEL and not IsInActivePickWindow()
end

local function UnblockPerkInteraction()
    if not IsInActivePickWindow() and not pendingChoices then return end
    ClearStuckPendingActions()
    local PerkUI = ProjectEbonhold and ProjectEbonhold.PerkUI
    if PerkUI and PerkUI.ResetSelection then
        PerkUI.ResetSelection()
    end
end

local function ShowNativePerkUI()
    pendingWaitCount = 0
    ResetAutomationRound()
    UnblockPerkInteraction()

    local PerkUI = ProjectEbonhold and ProjectEbonhold.PerkUI
    local choices = GetLivePickChoices() or pendingChoices
    if choices and nativePerkUIShow then
        suppressAutoHook = true
        nativePerkUIShow(choices)
        suppressAutoHook = false
    elseif choices and PerkUI and PerkUI.Show then
        suppressAutoHook = true
        PerkUI.Show(choices)
        suppressAutoHook = false
    end
end

local function ShouldShowOffer(choices)
    if suppressAutoHook or not choices or #choices == 0 then
        return true
    end
    local sig = ChoiceSignature(choices)
    local now = GetTime()
    if sig and sig == lastShowChoices and (now - lastShowTime) < SHOW_DEBOUNCE then
        return false
    end
    lastShowChoices = sig
    lastShowTime = now
    return true
end

local function RunEvaluate()
    if UnitIsDeadOrGhost("player") then
        ClearPickState()
        return false
    end
    if evalInProgress then return false end
    evalInProgress = true
    local ok, result = pcall(EbonBuilds.Automation.Evaluate)
    evalInProgress = false
    if not ok then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffff0000[EbonBuilds] Automation error: " .. tostring(result) .. "|r")
        return false
    end
    if not result and not GetLivePickChoices() then
        ClearPickState()
    end
    return result
end

local function StartEvalTimer()
    if not EbonBuilds.Automation.IsEnabled() then return end
    ClearPickStateIfStale()
    if not pendingChoices or #pendingChoices == 0 then return end
    if not GetLivePickChoices() then
        ClearPickState()
        return
    end
    if not evalTimerFrame then
        evalTimerFrame = CreateFrame("Frame")
        evalTimerFrame:Hide()
        evalTimerFrame:SetScript("OnUpdate", function(self, dt)
            if not evalTimerActive then return end
            evalTimerElapsed = evalTimerElapsed + dt
            if evalTimerElapsed >= GetEvalDelay() then
                StopEvalTimer()
                local result = RunEvaluate()
                if result == true or result == "wait" then
                    return
                end
                if not GetLivePickChoices() then
                    ClearPickState()
                end
                UnblockPerkInteraction()
            end
        end)
    end
    evalTimerElapsed = 0
    evalTimerActive = true
    evalTimerFrame:Show()
end

ResetAutomationRound = function(opts)
    opts = opts or {}
    if not opts.keepFreezeRound then
        freezeRoundActive = false
        locallyFrozenIndices = {}
    end
    pendingWaitCount = 0
    if opts.clearDebounce then
        lastShowChoices = nil
        lastShowTime = 0
    end
end

local function InAutoFreezeRound()
    return freezeRoundActive or next(locallyFrozenIndices) ~= nil
end

local function ScheduleAutomation(choices, opts)
    if UnitIsDeadOrGhost("player") then return end
    if not choices or #choices == 0 then return end
    if ShouldSuspendAtMaxLevel() then return end
    if not EbonBuilds.Automation.IsArmed() then return end
    opts = opts or {}
    if opts.keepFreezeRound == nil and InAutoFreezeRound() then
        opts.keepFreezeRound = true
    end
    local sig = ChoiceSignature(choices)
    if not opts.bypassDebounce and evalTimerActive and sig and sig == ChoiceSignature(pendingChoices) then
        pendingChoices = choices
        return
    end
    pendingChoices = choices
    pendingWaitCount = 0
    if opts.bypassDebounce then
        lastShowChoices = nil
    end
    if not opts.keepFreezeRound then
        locallyFrozenIndices = {}
        freezeRoundActive = false
    end
    if not opts.keepPending and IsInActivePickWindow() then
        UnblockPerkInteraction()
    end
    StartEvalTimer()
end

function EbonBuilds.Automation.IsArmed()
    local build = EbonBuilds.Build.GetActive()
    return build and build.automationEnabled and true or false
end

function EbonBuilds.Automation.IsPickPhaseActive()
    if IsInActivePickWindow() then return true end
    if UnitLevel("player") >= MAX_AUTOMATION_LEVEL then return false end
    return EbonBuilds.Automation.IsArmed()
end

function EbonBuilds.Automation.SetEnabled(enabled)
    local build = EbonBuilds.Build.GetActive()
    if build then
        build.automationEnabled = enabled and true or false
    end
    if not enabled then
        ClearPickState()
        ResetAutomationRound({ clearDebounce = true })
        EbonBuilds.Automation.ReleaseHooks()
    else
        EbonBuilds.Automation.EnsureHooked()
        if ShouldSuspendAtMaxLevel() then return end
        local choices = GetLivePickChoices()
        if choices then
            ScheduleAutomation(choices, { bypassDebounce = true })
        end
    end
end

function EbonBuilds.Automation.IsEnabled()
    if not EbonBuilds.Automation.IsArmed() then return false end
    if ShouldSuspendAtMaxLevel() then return false end
    return true
end

local lastStatsOfferSig = nil

local function OnEchoOfferShown(choices)
    if suppressAutoHook then return end
    if not choices or #choices == 0 then return end
    local build = EbonBuilds.Build.GetActive()
    local sig = ChoiceSignature(choices)
    if sig and sig ~= lastStatsOfferSig then
        lastStatsOfferSig = sig
        echoOffersThisRun = echoOffersThisRun + 1
        if build and EbonBuilds.Build.RecordEchoOffer then
            EbonBuilds.Build.RecordEchoOffer(build, choices)
        end
    end
    if not EbonBuilds.Automation.IsArmed() then return end
    if ShouldSuspendAtMaxLevel() then return end
    ScheduleAutomation(choices)
end

local function IsEchoFrozenForPick(s, choices)
    if s.isFrozen or locallyFrozenIndices[s.index] then
        return true
    end
    local choice = choices and choices[s.index]
    return choice and choice.justFrozen and true or false
end

local function GetAutomationSettings()
    local build = EbonBuilds.Build.GetActive()
    if not build then return EbonBuilds.Build.DefaultSettings() end
    EbonBuilds.Build.EnsureSettings(build)
    return build.settings
end

local function ThresholdScore(peakScore, pct)
    return math.floor(peakScore * pct / 100)
end

local function IsBlockedByRerollGuard(scored, peakScore, settings)
    local guardThreshold = ThresholdScore(peakScore, settings.rerollGuardPct or 90)
    for _, s in ipairs(scored) do
        if s.score >= guardThreshold then
            return true
        end
    end
    return false
end

local function HasPendingPerkAction(includeSelect)
    local perks = ProjectEbonhold.Perks
    if not perks then return false end
    if perks.pendingBanishIndex ~= nil
        or perks.pendingReroll
        or perks.pendingFreezeIndex ~= nil then
        return true
    end
    if includeSelect and perks.pendingSelectSpellId ~= nil then
        return true
    end
    return false
end

local function WaitForPendingAction()
    pendingWaitCount = pendingWaitCount + 1
    if pendingWaitCount >= PENDING_WAIT_MAX then
        pendingWaitCount = 0
        UnblockPerkInteraction()
        return false
    end
    StartEvalTimer()
    return true
end

local cachedPeakScore = nil
local cachedPeakSignature = nil
local cachedPeakBuildStamp = nil

local function BuildPeakBuildStamp(build)
    if not build then return nil end
    return table.concat({
        tostring(build.id or ""),
        tostring(build.version or 0),
        tostring(build.lastModified or ""),
    }, "\31")
end

local function BuildPeakSignature(build)
    if not build then return nil end
    local parts = { tostring(build.id or ""), tostring(build.class or "") }
    local weights = ResolveBuildWeights(build) or {}
    for name, w in pairs(weights) do
        parts[#parts + 1] = name .. "=" .. tostring(w)
    end
    table.sort(parts)
    return table.concat(parts, "\31")
end

function EbonBuilds.Automation.GetPeak()
    local build = EbonBuilds.Build.GetActive()
    if not build then return 1 end
    local stamp = BuildPeakBuildStamp(build)
    if stamp and stamp == cachedPeakBuildStamp and cachedPeakScore then
        return cachedPeakScore
    end
    local signature = BuildPeakSignature(build)
    if cachedPeakSignature == signature and cachedPeakScore then
        cachedPeakBuildStamp = stamp
        return cachedPeakScore
    end
    local settings = GetAutomationSettings()
    local _, score = EbonBuilds.Scoring.ComputePeak(build.class, settings)
    cachedPeakScore = (score and score > 0) and score or 1
    cachedPeakSignature = signature
    cachedPeakBuildStamp = stamp
    return cachedPeakScore
end

function EbonBuilds.Automation.ResetPeakCache()
    cachedPeakScore = nil
    cachedPeakSignature = nil
    cachedPeakBuildStamp = nil
    seenEchoFamilies = {}
    if EbonBuilds.Scoring and EbonBuilds.Scoring.ResetCache then
        EbonBuilds.Scoring.ResetCache()
    end
end

function EbonBuilds.Automation.ResetRunState()
    echoOffersThisRun = 0
    lastStatsOfferSig = nil
    evalInProgress = false
    ClearPickState()
    ResetAutomationRound({ clearDebounce = true })
    EbonBuilds.Automation.ResetPeakCache()
end

local function MarkEchoFamilySeen(spellId, displayName, grantedKey)
    local fk = EbonBuilds.Scoring.GetEchoFamilyKey
        and EbonBuilds.Scoring.GetEchoFamilyKey(spellId, displayName, grantedKey)
    if fk then seenEchoFamilies[fk] = true end
end

local function SeedSeenFromGranted(granted)
    if not granted then return end
    for key, instances in pairs(granted) do
        if type(instances) == "table" then
            for _, inst in ipairs(instances) do
                if inst and inst.spellId then
                    MarkEchoFamilySeen(inst.spellId, nil, key)
                end
            end
        end
    end
end

local function IsCarriedOrFrozenChoice(s)
    return s.isCarried or s.isFrozen or locallyFrozenIndices[s.index]
end

local function MarkScoredFamiliesSeen(scored, shouldMark)
    for _, s in ipairs(scored) do
        if shouldMark(s) then
            MarkEchoFamilySeen(s.spellId, s.name)
        end
    end
end

local function MarkRerolledFamiliesSeen(scored)
    MarkScoredFamiliesSeen(scored, function(s) return not IsCarriedOrFrozenChoice(s) end)
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

local function GetAvailableBanishes(runData)
    if not runData then return 0 end
    return runData.remainingBanishes or 0
end

local function GetAvailableRerolls(runData)
    if not runData then return 0 end
    return math.max(0, (runData.totalRerolls or 0) - (runData.usedRerolls or 0))
end

local function IsEchoUnpicked(displayName, spellId, granted)
    return EbonBuilds.Scoring.IsEchoNovel
        and EbonBuilds.Scoring.IsEchoNovel(displayName, spellId, granted)
end

local function IsEchoFirstSight(familyKey, offerState)
    if not familyKey then return false end
    if seenEchoFamilies[familyKey] then return false end
    if offerState then
        if offerState.firstSightInOffer[familyKey] then return false end
        offerState.firstSightInOffer[familyKey] = true
    end
    return true
end

local function ScoreChoice(choice, settings, granted, offerState, runData)
    local spellId = choice.spellId
    local spellName = GetSpellInfo(spellId)
    if not spellName then return nil end
    local data = ProjectEbonhold.PerkDatabase[spellId]
    if not data then return nil end
    local name = (EbonBuilds.Scoring.ResolveEchoDisplayName
        and EbonBuilds.Scoring.ResolveEchoDisplayName(spellId, spellName))
        or spellName
    local entry = {
        spellId   = spellId,
        name      = name,
        quality   = choice.quality,
        families  = data.families,
        classMask = data.classMask,
    }
    local weights = EbonBuilds.Build.GetActiveWeights and EbonBuilds.Build.GetActiveWeights() or {}
    local quality = choice.quality
    local weight = (EbonBuilds.Scoring.LookupWeight and EbonBuilds.Scoring.LookupWeight(weights, name, quality))
        or (EbonBuilds.Weights.GetForQuality and EbonBuilds.Weights.GetForQuality(name, quality))
        or EbonBuilds.Weights.Get(name)
        or 0
    granted = granted or GetGrantedPerks()
    local pickedQuality = EbonBuilds.Scoring.GetHighestPickedQuality
        and EbonBuilds.Scoring.GetHighestPickedQuality(name, spellId, granted)
    local familyKey = EbonBuilds.Scoring.GetEchoFamilyKey
        and EbonBuilds.Scoring.GetEchoFamilyKey(spellId, name)
    local isUnpicked = IsEchoUnpicked(name, spellId, granted)
    local isFirstSight = IsEchoFirstSight(familyKey, offerState)
    local pickedAtOrAbove = pickedQuality ~= nil and pickedQuality >= choice.quality

    local policy = (EbonBuilds.Build.GetEchoPolicy and EbonBuilds.Build.GetEchoPolicy(name)) or "normal"
    local banByPolicy, ignoreByPolicy, suppressNovelty = false, false, false
    local deprioritizePick = false
    local neverPick = false
    if policy == "ban1st" then
        if isFirstSight then
            banByPolicy = true
            suppressNovelty = true
            if GetAvailableBanishes(runData) <= 0 then
                ignoreByPolicy = true
                deprioritizePick = true
            end
        end
    elseif policy == "banAfterPick" then
        if pickedAtOrAbove then
            banByPolicy = true
        end
    elseif policy == "ignoreAfterPick" then
        if pickedQuality ~= nil and quality < RARE_QUALITY then
            ignoreByPolicy = true
            deprioritizePick = true
        end
    elseif policy == "neverPick" then
        neverPick = true
        deprioritizePick = true
    end

    local score
    if neverPick then
        score = 0
    elseif isUnpicked and not suppressNovelty then
        score = EbonBuilds.Scoring.Score(entry, weight, settings)
    else
        score = EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, entry.quality)
    end
    if ignoreByPolicy then
        score = score * POLICY_IGNORE_FACTOR
    end
    if (choice.isFrozen or choice.justFrozen)
        and settings.freezePenaltyPct and settings.freezePenaltyPct > 0 then
        score = score * (1 - settings.freezePenaltyPct / 100)
    end
    return {
        index     = 0,
        spellId   = spellId,
        name      = name,
        quality   = choice.quality,
        score     = score,
        baseWeight = weight,
        entry     = entry,
        data      = data,
        isFrozen  = choice.isFrozen,
        isCarried = choice.isCarried,
        banByPolicy = banByPolicy,
        deprioritizePick = deprioritizePick,
        neverPick = neverPick,
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

local function UpdateStat(build, key)
    if not build then return end
    if EbonBuilds.Build.EnsureStats then
        EbonBuilds.Build.EnsureStats(build)
    elseif not build.stats then
        return
    end
    build.stats[key] = (build.stats[key] or 0) + 1
    if EbonBuilds.BuildOverview and EbonBuilds.BuildOverview.NotifyStatsChanged then
        EbonBuilds.BuildOverview.NotifyStatsChanged()
    end
end

local function RecordPick(build, echoName, quality)
    if EbonBuilds.Build.RecordPick then
        EbonBuilds.Build.RecordPick(build, echoName, quality)
    else
        UpdateStat(build, "picks")
    end
end

local function RecordBanish(build, echoName)
    if EbonBuilds.Build.RecordBanish then
        EbonBuilds.Build.RecordBanish(build, echoName)
    else
        UpdateStat(build, "banishesUsed")
    end
end

local function GetEchoSkipReason(s, choices, settings)
    if not s or not settings then return nil end
    local banList = settings.echoBanList or {}
    if banList[s.spellId] then return "banned" end
    if IsEchoFrozenForPick(s, choices) then return "frozen" end
    return nil
end

local function LogAndToast(scored, action, targetIndex, choices, settings)
    local displayChoices = {}
    for _, s in ipairs(scored) do
        displayChoices[#displayChoices + 1] = {
            index      = s.index,
            name       = s.name,
            quality    = s.quality,
            score      = s.score,
            skipReason = GetEchoSkipReason(s, choices, settings),
        }
    end
    EbonBuilds.Toast.ShowAutomationResult(displayChoices, action, targetIndex)
    EbonBuilds.Session.LogAction(scored, action, targetIndex)
end

------------------------------------------------------------------------
-- Action attempts (called in priority order)
------------------------------------------------------------------------

local function CompareByScoreThenBaseWeight(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return (a.baseWeight or 0) > (b.baseWeight or 0)
end

local function IsBetterPickCandidate(a, b)
    if not b then return true end
    return CompareByScoreThenBaseWeight(a, b)
end

local function TrySelect(scored, settings, build, choices)
    local banList = settings.echoBanList or {}
    local penalty = (settings.freezePenaltyPct or 0) / 100
    local nonBanned, deprioritized, neverPool, all = {}, {}, {}, {}
    for _, s in ipairs(scored) do
        if not IsEchoFrozenForPick(s, choices) then
            local pickScore = s.score
            if penalty > 0 and locallyFrozenIndices[s.index] and not s.isFrozen then
                pickScore = math.floor(pickScore * (1 - penalty))
            end
            local entry = {
                index = s.index, spellId = s.spellId, name = s.name,
                quality = s.quality, score = pickScore,
                baseWeight = s.baseWeight or 0,
            }
            all[#all + 1] = entry
            if not banList[s.spellId] then
                if s.neverPick then
                    neverPool[#neverPool + 1] = entry
                elseif s.deprioritizePick then
                    deprioritized[#deprioritized + 1] = entry
                else
                    nonBanned[#nonBanned + 1] = entry
                end
            end
        end
    end
    local candidates = #nonBanned > 0 and nonBanned
        or (#deprioritized > 0 and deprioritized)
        or (#neverPool > 0 and neverPool)
        or all
    if #candidates == 0 then return false, nil end

    table.sort(candidates, CompareByScoreThenBaseWeight)

    local pick
    if #nonBanned == 0 and settings.echoBanAllMode == "random" then
        pick = candidates[math.random(1, #candidates)]
    else
        pick = candidates[1]
    end

    if not ProjectEbonhold.PerkService.SelectPerk(pick.spellId) then
        return false, nil
    end
    MarkEchoFamilySeen(pick.spellId, pick.name)
    RecordPick(build, pick.name, pick.quality)
    ResetAutomationRound()
    pendingChoices = nil
    return true, pick
end

local function FindFreezeRoundKeeper(scored, threshold)
    if next(locallyFrozenIndices) == nil then return nil end

    local bestKeeper, bestFallback = nil, nil
    for _, s in ipairs(scored) do
        if locallyFrozenIndices[s.index] then
            -- frozen this round, not the keeper
        else
            if s.score > threshold then
                if IsBetterPickCandidate(s, bestKeeper) then
                    bestKeeper = s
                end
            end
            if IsBetterPickCandidate(s, bestFallback) then
                bestFallback = s
            end
        end
    end
    return bestKeeper or bestFallback
end

local function TrySelectFreezeRoundKeeper(scored, settings, build, choices, threshold)
    local keeper = FindFreezeRoundKeeper(scored, threshold)
    if not keeper then return false, nil end
    if not ProjectEbonhold.PerkService.SelectPerk(keeper.spellId) then
        return false, nil
    end
    MarkEchoFamilySeen(keeper.spellId, keeper.name)
    RecordPick(build, keeper.name, keeper.quality)
    ResetAutomationRound()
    pendingChoices = nil
    return true, keeper
end

local function GetAvailableFreezes(runData)
    if not runData then return 0 end
    return math.max(0, (runData.totalFreezes or 0) - (runData.usedFreezes or 0))
end

local function CollectAboveThreshold(scored, threshold)
    local list = {}
    for _, s in ipairs(scored) do
        if not s.isFrozen and not s.isCarried and not locallyFrozenIndices[s.index]
            and s.score > threshold then
            list[#list + 1] = s
        end
    end
    table.sort(list, CompareByScoreThenBaseWeight)
    return list
end

local function FindNextFreezeTarget(scored, threshold)
    local above = CollectAboveThreshold(scored, threshold)
    if #above < 2 then return nil end
    for i = #above, 2, -1 do
        local s = above[i]
        if not locallyFrozenIndices[s.index] then
            return s
        end
    end
    return nil
end

local function FreezeRoundSelectReady(scored, threshold)
    if not InAutoFreezeRound() then return false end
    return FindNextFreezeTarget(scored, threshold) == nil
end

local function ApplyLocalFreezePenalties(scored, settings)
    local penalty = (settings.freezePenaltyPct or 0) / 100
    if penalty <= 0 then return end
    for _, s in ipairs(scored) do
        if locallyFrozenIndices[s.index] and not s.isFrozen then
            s.score = math.floor(s.score * (1 - penalty))
        end
    end
end

local function TryContinueFreezeRound(scored, settings, build, choices, threshold, runData)
    if not InAutoFreezeRound() then return nil end
    freezeRoundActive = true

    ApplyLocalFreezePenalties(scored, settings)

    if HasPendingPerkAction(false) then
        if WaitForPendingAction() then return "wait" end
    end
    pendingWaitCount = 0

    local freezeTarget = FindNextFreezeTarget(scored, threshold)
    if freezeTarget and GetAvailableFreezes(runData) > 0 then
        local ok = ProjectEbonhold.PerkService.FreezePerk(freezeTarget.index - 1)
        if ok then
            UpdateStat(build, "freezesUsed")
            locallyFrozenIndices[freezeTarget.index] = true
            if runData and runData.usedFreezes ~= nil then
                runData.usedFreezes = runData.usedFreezes + 1
            end
            LogAndToast(scored, "Freeze", freezeTarget.index, choices, settings)
            ScheduleAutomation(choices, { keepFreezeRound = true, keepPending = true })
            return true
        end
    end

    if FreezeRoundSelectReady(scored, threshold) then
        local ok, pick = TrySelectFreezeRoundKeeper(scored, settings, build, choices, threshold)
        if ok and pick then
            LogAndToast(scored, "Select", pick.index, choices, settings, { afterFreeze = true })
            return true
        end
        ResetAutomationRound()
        UnblockPerkInteraction()
        return false
    end

    if WaitForPendingAction() then return "wait" end
    return "wait"
end

local function FindBanishTarget(scored, settings, banList, peakScore)
    if not scored or #scored == 0 then return nil end
    local threshold = ThresholdScore(peakScore, settings.autoBanishPct)
    local byScore = {}
    for i = 1, #scored do byScore[i] = scored[i] end
    table.sort(byScore, function(a, b) return a.score < b.score end)

    for _, s in ipairs(byScore) do
        if not s.isFrozen and not s.isCarried and not s.isProtected then
            if banList[s.spellId] or s.banByPolicy then
                return s
            end
        end
    end
    for _, s in ipairs(byScore) do
        if not s.isFrozen and not s.isCarried and s.score < threshold and not s.isProtected then
            return s
        end
    end
    return nil
end

local function HasActionableBanishTarget(scored, settings, banList, peakScore, runData)
    if GetAvailableBanishes(runData) <= 0 then return false end
    return FindBanishTarget(scored, settings, banList, peakScore) ~= nil
end

local function OfferedScoreSum(scored)
    local sum = 0
    for _, s in ipairs(scored) do
        sum = sum + s.score
    end
    return sum
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
    if ShouldSuspendAtMaxLevel() then
        ClearPickState()
        return false
    end
    if not EbonBuilds.Automation.IsEnabled() then return false end

    local build = EbonBuilds.Build.GetActive()
    if not build then return false end

    local choices = GetLivePickChoices()
    if not choices then
        ClearPickState()
        return false
    end

    local settings   = GetAutomationSettings()
    local runData    = GetRunData()
    local lockedList = build.lockedEchoes or {}

    local peakScore = EbonBuilds.Automation.GetPeak()

    local granted = GetGrantedPerks()
    SeedSeenFromGranted(granted)
    local offerState = { firstSightInOffer = {} }
    local scored = {}
    for i, choice in ipairs(choices) do
        local s = ScoreChoice(choice, settings, granted, offerState, runData)
        if s then
            s.index = i
            scored[#scored + 1] = s
        end
    end
    if #scored == 0 then return false end

    local banList    = settings.echoBanList or {}
    local whitelist  = settings.banishFamilyWhitelist or {}
    AnnotateScored(scored, banList, whitelist, lockedList)

    local threshold = ThresholdScore(peakScore, settings.autoFreezePct)

    if InAutoFreezeRound() then
        local freezeResult = TryContinueFreezeRound(scored, settings, build, choices, threshold, runData)
        if freezeResult ~= nil then
            return freezeResult
        end
    end

    for _, s in ipairs(scored) do
        for _, lockedId in ipairs(lockedList) do
            if lockedId and lockedId == s.spellId then
                if ProjectEbonhold.PerkService.SelectPerk(s.spellId) then
                    MarkEchoFamilySeen(s.spellId, s.name)
                    RecordPick(build, s.name, s.quality)
                    LogAndToast(scored, "Select (Locked)", s.index, choices, settings)
                    pendingChoices = nil
                    return true
                end
                return false
            end
        end
    end

    if GetAvailableBanishes(runData) > 0 then
        local target = FindBanishTarget(scored, settings, banList, peakScore)
        if target then
            local ok = ProjectEbonhold.PerkService.BanishPerk(target.index - 1)
            if ok then
                MarkEchoFamilySeen(target.spellId, target.name)
                RecordBanish(build, target.name)
                if runData and runData.remainingBanishes ~= nil then
                    runData.remainingBanishes = math.max(0, runData.remainingBanishes - 1)
                end
                table.sort(scored, function(a, b) return a.index < b.index end)
                LogAndToast(scored, "Banish", target.index, choices, settings)
                StartEvalTimer()
                return true
            end
        end
    end

    table.sort(scored, function(a, b) return a.index < b.index end)

    if HasPendingPerkAction(false) then
        if WaitForPendingAction() then return "wait" end
    end
    pendingWaitCount = 0

    local rerollsLeft = GetAvailableRerolls(runData)
    local skipFirstOfferReroll = echoOffersThisRun <= 1
    if not skipFirstOfferReroll and not InAutoFreezeRound() and rerollsLeft > 0 then
        -- Reroll guard: skip if any single echo is above the guard threshold,
        -- regardless of the sum. Prevents rerolling when one good echo is
        -- offered alongside weak ones.
        if not IsBlockedByRerollGuard(scored, peakScore, settings) then
            local sum = OfferedScoreSum(scored)
            if sum < ThresholdScore(peakScore, settings.autoRerollPct) then
                local ok = ProjectEbonhold.PerkService.RequestReroll()
                if ok then
                    MarkRerolledFamiliesSeen(scored)
                    UpdateStat(build, "rerollsUsed")
                    if runData and runData.usedRerolls ~= nil then
                        runData.usedRerolls = runData.usedRerolls + 1
                    end
                    ResetAutomationRound()
                    LogAndToast(scored, "Reroll", 0, choices, settings)
                    return true
                end
            end
        end
    end

    if GetAvailableFreezes(runData) > 0 and not InAutoFreezeRound() then
        ApplyLocalFreezePenalties(scored, settings)

        local freezeTarget = FindNextFreezeTarget(scored, threshold)
        if freezeTarget then
            local ok = ProjectEbonhold.PerkService.FreezePerk(freezeTarget.index - 1)
            if ok then
                UpdateStat(build, "freezesUsed")
                locallyFrozenIndices[freezeTarget.index] = true
                if runData and runData.usedFreezes ~= nil then
                    runData.usedFreezes = runData.usedFreezes + 1
                end
                LogAndToast(scored, "Freeze", freezeTarget.index, choices, settings)
                freezeRoundActive = true
                ScheduleAutomation(choices, { keepFreezeRound = true, keepPending = true })
                return true
            end
        end
    end

    if HasActionableBanishTarget(scored, settings, banList, peakScore, runData) then
        if HasPendingPerkAction(false) then
            if WaitForPendingAction() then return "wait" end
            pendingWaitCount = 0
        end
        local target = FindBanishTarget(scored, settings, banList, peakScore)
        if target then
            local ok = ProjectEbonhold.PerkService.BanishPerk(target.index - 1)
            if ok then
                MarkEchoFamilySeen(target.spellId, target.name)
                RecordBanish(build, target.name)
                if runData and runData.remainingBanishes ~= nil then
                    runData.remainingBanishes = math.max(0, runData.remainingBanishes - 1)
                end
                table.sort(scored, function(a, b) return a.index < b.index end)
                LogAndToast(scored, "Banish", target.index, choices, settings)
                StartEvalTimer()
                return true
            end
            if WaitForPendingAction() then return "wait" end
        end
    end

    if HasPendingPerkAction(true) then
        if WaitForPendingAction() then return "wait" end
    end
    pendingWaitCount = 0

    local ok, pick = TrySelect(scored, settings, build, choices)
    if ok and pick then
        LogAndToast(scored, "Select", pick.index, choices, settings)
    end
    return ok
end

------------------------------------------------------------------------
-- Hook installation (lazy — only while automation is armed)
------------------------------------------------------------------------

local function InstallHooks()
    if hooksInstalled then return true end
    if not ProjectEbonhold or not ProjectEbonhold.PerkUI then return false end
    local PerkUI = ProjectEbonhold.PerkUI
    if type(PerkUI) ~= "table" or not PerkUI.Show then return false end
    if PerkUI._ebonholdHubHooked then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffffcc00[EbonBuilds] EbonholdHub automation is active — disable it there or turn off EbonholdHub to avoid duplicate perk hooks.|r")
        return false
    end

    nativePerkUIShow = nativePerkUIShow or PerkUI.Show

    PerkUI.Show = function(choices)
        if not ShouldShowOffer(choices) then
            return
        end
        nativePerkUIShow(choices)
        if choices and #choices > 0 then
            OnEchoOfferShown(choices)
        end
    end

    if PerkUI.Hide and not hideHookInstalled then
        hideHookInstalled = true
        hooksecurefunc(PerkUI, "Hide", function()
            ClearPickState()
        end)
    end

    PerkUI._ebonBuildsHooked = true
    hooksInstalled = true
    return true
end

function EbonBuilds.Automation.ReleaseHooks()
    ClearPickState()
    local PerkUI = ProjectEbonhold and ProjectEbonhold.PerkUI
    if PerkUI and nativePerkUIShow and PerkUI.Show ~= nativePerkUIShow then
        PerkUI.Show = nativePerkUIShow
    end
    hooksInstalled = false
    if PerkUI then
        PerkUI._ebonBuildsHooked = nil
    end
end

function EbonBuilds.Automation.SyncHookState()
    if EbonBuilds.Automation.IsArmed() then
        return EbonBuilds.Automation.EnsureHooked()
    end
    EbonBuilds.Automation.ReleaseHooks()
    return false
end

function EbonBuilds.Automation.Init()
    return EbonBuilds.Automation.SyncHookState()
end

function EbonBuilds.Automation.EnsureHooked()
    if not EbonBuilds.Automation.IsArmed() then
        EbonBuilds.Automation.ReleaseHooks()
        return false
    end
    return InstallHooks()
end

function EbonBuilds.Automation.ShowManualUI()
    ShowNativePerkUI()
end

local hookRetryFrame = CreateFrame("Frame")
hookRetryFrame:RegisterEvent("PLAYER_LOGIN")
hookRetryFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
hookRetryFrame:RegisterEvent("PLAYER_LEVEL_UP")
hookRetryFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LEVEL_UP" then
        local newLevel = ...
        ClearPickState()
        ResetAutomationRound({ clearDebounce = true })
        if newLevel and newLevel >= MAX_AUTOMATION_LEVEL then
            EbonBuilds.Automation.ResetRunState()
        end
        EbonBuilds.Automation.SyncHookState()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        if UnitLevel("player") >= MAX_AUTOMATION_LEVEL then
            ClearPickState()
            ResetAutomationRound({ clearDebounce = true })
        end
    end
    EbonBuilds.Automation.SyncHookState()
end)

EbonBuilds.Automation._ScoreChoice       = ScoreChoice
EbonBuilds.Automation._TrySelect         = TrySelect
EbonBuilds.Automation._AnnotateScored  = AnnotateScored
EbonBuilds.Automation._IsProtected     = IsProtected
EbonBuilds.Automation._CollectAboveThreshold = CollectAboveThreshold
EbonBuilds.Automation._FindBanishTarget     = FindBanishTarget
EbonBuilds.Automation._HasActionableBanishTarget = HasActionableBanishTarget
EbonBuilds.Automation._OfferedScoreSum           = OfferedScoreSum
EbonBuilds.Automation._IsBlockedByRerollGuard  = IsBlockedByRerollGuard
EbonBuilds.Automation._FindNextFreezeTarget   = FindNextFreezeTarget
EbonBuilds.Automation._FindFreezeRoundKeeper  = FindFreezeRoundKeeper
EbonBuilds.Automation._TrySelectFreezeRoundKeeper = TrySelectFreezeRoundKeeper
EbonBuilds.Automation._TryContinueFreezeRound = TryContinueFreezeRound
EbonBuilds.Automation._InAutoFreezeRound = InAutoFreezeRound
EbonBuilds.Automation._ResetAutomationRound   = ResetAutomationRound
