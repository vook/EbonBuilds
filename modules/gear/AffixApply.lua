-- EbonBuilds: modules/gear/AffixApply.lua
-- Set-coverage affix planner and sequential apply queue via Enchanted Anvil.

EbonBuilds.AffixApply = {}

local UNIQUE_AFFIX_BASES = {
    ["spell mastery"] = true,
    ["temporal flux"]  = true,
}

-- Unranked affix families that only apply to weapons (never trust server weaponOnly alone).
local WEAPON_ONLY_BASES = {
    ["shackling"]     = true,
    ["affliction"]    = true,
    ["decay"]         = true,
    ["vulnerability"] = true,
}

local queueState = nil

local function Toast(msg)
    if EbonBuilds.Toast then
        EbonBuilds.Toast.Show(msg)
    end
end

local function IsAnvilOpen()
    if EbonBuilds.AnvilIntegration and EbonBuilds.AnvilIntegration.IsOpen then
        return EbonBuilds.AnvilIntegration.IsOpen()
    end
    if ExtractionUI and ExtractionUI.IsOpen and ExtractionUI.IsOpen() then
        return true
    end
    local frame = _G.EbonholdExtractionFrame
    return frame and frame.IsShown and frame:IsShown()
end

function EbonBuilds.AffixApply.FormatCost(copper)
    if not copper or copper <= 0 then return "0g" end
    local gold = math.floor(copper / 10000)
    if gold > 0 then
        return gold .. "g"
    end
    local silver = math.floor(copper / 100)
    if silver > 0 then
        return silver .. "s"
    end
    return copper .. "c"
end

local function GetAffixBase(name)
    if not name then return "" end
    local clean = EbonBuilds.AffixScan.NormalizeAffixName(name) or name
    local lower = clean:lower()
    return lower:match("^(.-)%s+(i|ii|iii|iv|v)$") or lower
end

local function IsUniqueAffix(name)
    return UNIQUE_AFFIX_BASES[GetAffixBase(name)] or false
end

local function BuildTargetMultiset(names)
    local counts = {}
    local order = {}
    for _, name in ipairs(names or {}) do
        local key = name:lower()
        if not counts[key] then
            counts[key] = { display = name, needed = 0 }
            order[#order + 1] = key
        end
        counts[key].needed = counts[key].needed + 1
    end
    return counts, order
end

local function AffixNamesForCheck(affixName, affixRecord)
    local names = {}
    if affixName then names[#names + 1] = affixName end
    if affixRecord and affixRecord.name and affixRecord.name ~= affixName then
        names[#names + 1] = affixRecord.name
    end
    return names
end

local function HasRankedTier(affixName, affixRecord)
    for _, name in ipairs(AffixNamesForCheck(affixName, affixRecord)) do
        if EbonBuilds.AffixScan.HasRomanTierSuffix(name) then
            return true
        end
    end
    return false
end

local function IsAffixWeaponOnly(affixRecord, affixName)
    if HasRankedTier(affixName, affixRecord) then
        return false
    end
    for _, name in ipairs(AffixNamesForCheck(affixName, affixRecord)) do
        if WEAPON_ONLY_BASES[GetAffixBase(name)] then
            return true
        end
    end
    return false
end

local function CountEquippedWeaponOnlyAffixes(equipped)
    local count = 0
    for _, slotEntry in ipairs(equipped) do
        if EbonBuilds.AffixScan.IsWeaponInvSlot(slotEntry.invSlot) and slotEntry.affixName then
            local record = EbonBuilds.AffixScan.ResolveAffixNameToRecord(slotEntry.affixName)
            if IsAffixWeaponOnly(record, slotEntry.affixName) then
                count = count + 1
            end
        end
    end
    return count
end

local function WeaponSlotsAcceptArmorAffixes(equippedWeaponOnlyCount, plannedWeaponOnlyCount)
    return (equippedWeaponOnlyCount + plannedWeaponOnlyCount) >= 2
end

local function SlotFitsAffix(invSlot, affixRecord, affixName, weaponSlotsAcceptArmor)
    if IsAffixWeaponOnly(affixRecord, affixName) then
        return EbonBuilds.AffixScan.IsWeaponInvSlot(invSlot)
    end
    if EbonBuilds.AffixScan.IsWeaponInvSlot(invSlot) then
        return weaponSlotsAcceptArmor
    end
    return true
end

local function BuildCandidates(equipped, targetSet, targetCounts)
    -- Reserve the first N copies of each build affix found on gear (N = build
    -- target count). Extra copies and non-build affixes stay changeable.
    local needRemaining = {}
    for key, entry in pairs(targetCounts) do
        needRemaining[key] = entry.needed
    end

    local candidates = {}
    for _, slotEntry in ipairs(equipped) do
        local affixKey = slotEntry.affixName and slotEntry.affixName:lower()
        if affixKey and targetSet[affixKey] and (needRemaining[affixKey] or 0) > 0 then
            needRemaining[affixKey] = needRemaining[affixKey] - 1
        else
            candidates[#candidates + 1] = slotEntry
        end
    end
    return candidates
end

local function SlotTypePreferred(invSlot, affixRecord, toAffix, weaponSlotsAcceptArmor)
    if IsAffixWeaponOnly(affixRecord, toAffix) then
        return EbonBuilds.AffixScan.IsWeaponInvSlot(invSlot)
    end
    if EbonBuilds.AffixScan.IsWeaponInvSlot(invSlot) then
        return weaponSlotsAcceptArmor
    end
    return true
end

local function FindCandidateIndex(candidates, usedCandidates, affixRecord, toAffix, key, targetSet, weaponSlotsAcceptArmor)
    local wrongAffix, noAffix, excessBuild = {}, {}, {}
    for i, slotEntry in ipairs(candidates) do
        if usedCandidates[i] or not SlotFitsAffix(slotEntry.invSlot, affixRecord, toAffix, weaponSlotsAcceptArmor) then
        elseif not SlotTypePreferred(slotEntry.invSlot, affixRecord, toAffix, weaponSlotsAcceptArmor) then
        else
            local currentKey = slotEntry.affixName and slotEntry.affixName:lower()
            if not currentKey then
                noAffix[#noAffix + 1] = i
            elseif not targetSet[currentKey] then
                wrongAffix[#wrongAffix + 1] = i
            elseif currentKey ~= key then
                excessBuild[#excessBuild + 1] = i
            end
        end
    end
    if wrongAffix[1] then return wrongAffix[1] end
    if noAffix[1] then return noAffix[1] end
    if excessBuild[1] then return excessBuild[1] end
    return nil
end

local function SortMissingKeys(missingKeys, targetCounts)
    local weapon, armor = {}, {}
    for _, key in ipairs(missingKeys) do
        local toAffix = targetCounts[key].display
        local affixRecord = EbonBuilds.AffixScan.ResolveAffixNameToRecord(toAffix)
        if IsAffixWeaponOnly(affixRecord, toAffix) then
            weapon[#weapon + 1] = key
        else
            armor[#armor + 1] = key
        end
    end
    local sorted = {}
    for _, key in ipairs(weapon) do sorted[#sorted + 1] = key end
    for _, key in ipairs(armor) do sorted[#sorted + 1] = key end
    return sorted
end

local function CountFittingSlots(candidates, usedCandidates, affixRecord, affixName, onlyFree, weaponSlotsAcceptArmor)
    local total, free = 0, 0
    for i, slotEntry in ipairs(candidates) do
        if SlotFitsAffix(slotEntry.invSlot, affixRecord, affixName, weaponSlotsAcceptArmor) then
            total = total + 1
            if not usedCandidates[i] then
                free = free + 1
            end
        end
    end
    if onlyFree then return free end
    return total
end

local function NoSlotReason(affixRecord, affixName, candidates, usedCandidates, weaponSlotsAcceptArmor)
    local freeFitting = CountFittingSlots(candidates, usedCandidates, affixRecord, affixName, true, weaponSlotsAcceptArmor)
    if freeFitting > 0 then
        return "no slot available"
    end
    local totalFitting = CountFittingSlots(candidates, usedCandidates, affixRecord, affixName, false, weaponSlotsAcceptArmor)
    if totalFitting > 0 then
        return "all matching slots already assigned to other changes"
    end
    if #candidates == 0 then
        return "no changeable gear; build affixes already cover your slots"
    end
    if IsAffixWeaponOnly(affixRecord, affixName) then
        return "needs a weapon; none have a changeable affix"
    end
    if not weaponSlotsAcceptArmor then
        return "needs armor; apply 2 weapon affixes first to use weapon slots"
    end
    return "needs armor; none have a changeable affix"
end

local function MakeSkipStep(slotEntry, toAffix, reason)
    return {
        invSlot    = slotEntry.invSlot,
        slotLabel  = slotEntry.slotLabel,
        itemLink   = slotEntry.link,
        fromAffix  = slotEntry.affixName,
        toAffix    = toAffix,
        spellId    = nil,
        applyCost  = nil,
        skipReason = reason,
    }
end

function EbonBuilds.AffixApply.BuildPlan(build)
    local plan = {}
    local summary = {
        applyCount = 0,
        skipCount  = 0,
        totalCost  = 0,
    }

    local affixData = build and EbonBuilds.Build.GetActiveAffixScan(build)
    local targetNames = affixData and affixData.names
    if not targetNames or #targetNames == 0 then
        return plan, summary
    end

    if InCombatLockdown() then
        summary.blockReason = "Cannot apply affixes while in combat."
        return plan, summary
    end

    local targetCounts, targetOrder = BuildTargetMultiset(targetNames)
    local targetSet = {}
    for key in pairs(targetCounts) do
        targetSet[key] = true
    end

    local equipped = EbonBuilds.AffixScan.ScanEquippedSlots("player")
    local playerCounts = {}
    for _, slotEntry in ipairs(equipped) do
        if slotEntry.affixName then
            local key = slotEntry.affixName:lower()
            playerCounts[key] = (playerCounts[key] or 0) + 1
        end
    end

    local remaining = {}
    for key, entry in pairs(targetCounts) do
        remaining[key] = math.max(0, entry.needed - (playerCounts[key] or 0))
    end

    -- Only change slots with wrong/excess affixes; protect pieces already
    -- contributing a needed build affix (e.g. keep Vulnerability on libram).
    local candidates = BuildCandidates(equipped, targetSet, targetCounts)

    local missingKeys = {}
    for _, key in ipairs(targetOrder) do
        for _ = 1, remaining[key] do
            missingKeys[#missingKeys + 1] = key
        end
    end

    if #missingKeys == 0 then
        summary.blockReason = "Your gear already matches this build's affix set."
        return plan, summary
    end

    missingKeys = SortMissingKeys(missingKeys, targetCounts)

    local hasBagSpace = EbonBuilds.AffixScan.FindEmptyBagSlot() ~= nil
    local keptUniqueBases = {}
    for _, slotEntry in ipairs(equipped) do
        if slotEntry.affixName and IsUniqueAffix(slotEntry.affixName) then
            local key = slotEntry.affixName:lower()
            if targetSet[key] then
                keptUniqueBases[GetAffixBase(slotEntry.affixName)] = true
            end
        end
    end
    local plannedUniqueBases = {}

    local usedCandidates = {}
    local equippedWeaponOnlyCount = CountEquippedWeaponOnlyAffixes(equipped)
    local plannedWeaponOnlyCount = 0

    for _, key in ipairs(missingKeys) do
        local toAffix = targetCounts[key].display
        local affixRecord = EbonBuilds.AffixScan.ResolveAffixNameToRecord(toAffix)
        local weaponSlotsAcceptArmor = WeaponSlotsAcceptArmorAffixes(
            equippedWeaponOnlyCount,
            plannedWeaponOnlyCount
        )

        if not affixRecord then
            plan[#plan + 1] = MakeSkipStep(
                { invSlot = 0, slotLabel = "—", link = nil, affixName = nil },
                toAffix,
                "not learned"
            )
            summary.skipCount = summary.skipCount + 1
        elseif not affixRecord.learned then
            plan[#plan + 1] = MakeSkipStep(
                { invSlot = 0, slotLabel = "—", link = nil, affixName = nil },
                toAffix,
                "not learned"
            )
            summary.skipCount = summary.skipCount + 1
        else
            local base = GetAffixBase(toAffix)
            if IsUniqueAffix(toAffix) and (keptUniqueBases[base] or plannedUniqueBases[base]) then
                plan[#plan + 1] = MakeSkipStep(
                    { invSlot = 0, slotLabel = "—", link = nil, affixName = nil },
                    toAffix,
                    "unique affix already present"
                )
                summary.skipCount = summary.skipCount + 1
            else
                local chosenIdx = FindCandidateIndex(
                    candidates,
                    usedCandidates,
                    affixRecord,
                    toAffix,
                    key,
                    targetSet,
                    weaponSlotsAcceptArmor
                )

                if not chosenIdx then
                    local reason = NoSlotReason(
                        affixRecord,
                        toAffix,
                        candidates,
                        usedCandidates,
                        weaponSlotsAcceptArmor
                    )
                    plan[#plan + 1] = MakeSkipStep(
                        { invSlot = 0, slotLabel = "—", link = nil, affixName = nil },
                        toAffix,
                        reason
                    )
                    summary.skipCount = summary.skipCount + 1
                elseif not hasBagSpace then
                    plan[#plan + 1] = MakeSkipStep(candidates[chosenIdx], toAffix, "no bag space")
                    summary.skipCount = summary.skipCount + 1
                else
                    usedCandidates[chosenIdx] = true
                    local slotEntry = candidates[chosenIdx]
                    if IsUniqueAffix(toAffix) then
                        plannedUniqueBases[base] = true
                    end
                    if IsAffixWeaponOnly(affixRecord, toAffix)
                        and EbonBuilds.AffixScan.IsWeaponInvSlot(slotEntry.invSlot) then
                        plannedWeaponOnlyCount = plannedWeaponOnlyCount + 1
                    end
                    plan[#plan + 1] = {
                        invSlot    = slotEntry.invSlot,
                        slotLabel  = slotEntry.slotLabel,
                        itemLink   = slotEntry.link,
                        fromAffix  = slotEntry.affixName,
                        toAffix    = toAffix,
                        spellId    = affixRecord.id,
                        applyCost  = affixRecord.applyCost,
                        skipReason = nil,
                    }
                    summary.applyCount = summary.applyCount + 1
                    summary.totalCost = summary.totalCost + (affixRecord.applyCost or 0)
                end
            end
        end
    end

    return plan, summary
end

function EbonBuilds.AffixApply.CanPreview(build)
    if EbonBuilds.AffixApply.IsRunning() then
        return false, "An affix apply queue is already running."
    end
    if InCombatLockdown() then
        return false, "Cannot apply affixes while in combat."
    end
    local affixData = build and EbonBuilds.Build.GetActiveAffixScan(build)
    if not affixData or not affixData.names or #affixData.names == 0 then
        return false, "This build has no stored affixes."
    end
    return true
end

function EbonBuilds.AffixApply.CanRun(build)
    local canPreview, previewHint = EbonBuilds.AffixApply.CanPreview(build)
    if not canPreview then
        return false, previewHint
    end
    if not IsAnvilOpen() then
        return false, "Open the Enchanted Anvil first."
    end
    local _, summary = EbonBuilds.AffixApply.BuildPlan(build)
    if summary.blockReason then
        return false, summary.blockReason
    end
    if summary.applyCount < 1 then
        return false, "No applicable affix changes (check preview for skipped items)."
    end
    return true
end

function EbonBuilds.AffixApply.CancelQueue()
    queueState = nil
end

local function FinishQueue(success, message)
    local state = queueState
    queueState = nil
    if state and state.onDone then
        state.onDone(success, message)
    end
end

local function AdvanceQueue()
    local state = queueState
    if not state then return end

    state.index = state.index + 1
    while state.index <= #state.steps do
        local step = state.steps[state.index]
        if not step.skipReason then
            break
        end
        state.index = state.index + 1
    end

    if state.index > #state.steps then
        Toast(string.format("Applied %d affix change%s.", state.applied, state.applied == 1 and "" or "s"))
        FinishQueue(true, nil)
        return
    end

    if not IsAnvilOpen() then
        Toast("Enchanted Anvil closed — apply queue stopped.")
        FinishQueue(false, "anvil closed")
        return
    end

    if InCombatLockdown() then
        Toast("Entered combat — apply queue stopped.")
        FinishQueue(false, "combat")
        return
    end

    local step = state.steps[state.index]
    if state.onProgress then
        state.onProgress(state.index, #state.steps, step)
    end

    local bag, slotIdx = EbonBuilds.AffixScan.FindEmptyBagSlot()
    if not bag then
        Toast("No empty bag space — apply queue stopped.")
        FinishQueue(false, "no bag space")
        return
    end

    state.pendingBag = bag
    state.pendingSlot = slotIdx
    state.pendingInvSlot = step.invSlot
    state.phase = "unequip"

    PickupInventoryItem(step.invSlot)
    PickupContainerItem(bag, slotIdx)
    if CursorHasItem() then
        ClearCursor()
        Toast("Failed to unequip item — apply queue stopped.")
        FinishQueue(false, "unequip failed")
        return
    end

    local function waitForBag(attempt)
        if not queueState or queueState ~= state then return end
        if GetContainerItemLink(bag, slotIdx) then
            state.phase = "apply"
            local serverBag, serverSlot = EbonBuilds.AffixScan.ClientBagSlotToServer(bag, slotIdx)
            if ExtractionService and ExtractionService.RequestApplyAffix then
                ExtractionService.RequestApplyAffix(step.spellId, serverBag, serverSlot)
            else
                Toast("Extraction service unavailable — apply queue stopped.")
                FinishQueue(false, "no service")
            end
            return
        end
        if attempt >= 20 then
            Toast("Timed out waiting for item in bags — apply queue stopped.")
            FinishQueue(false, "bag timeout")
            return
        end
        C_Timer.After(0.05, function() waitForBag(attempt + 1) end)
    end

    C_Timer.After(0.05, function() waitForBag(1) end)
end

local function OnApplyResult(body)
    local state = queueState
    if not state or state.phase ~= "apply" then return end

    if body == "OK" then
        state.applied = state.applied + 1
        state.phase = "reequip"
        local bag, slotIdx = state.pendingBag, state.pendingSlot
        local invSlot = state.pendingInvSlot

        PickupContainerItem(bag, slotIdx)
        PickupInventoryItem(invSlot)
        if CursorHasItem() then
            ClearCursor()
            Toast("Affix applied but re-equip failed — check your bags.")
            FinishQueue(false, "re-equip failed")
            return
        end

        state.phase = "delay"
        C_Timer.After(0.1, AdvanceQueue)
    else
        local _, reason = body:match("^([^,]+),(.+)$")
        Toast("Apply failed: " .. (reason or "unknown error"))
        FinishQueue(false, reason)
    end
end

function EbonBuilds.AffixApply.RunPlan(plan, onProgress, onDone)
    if queueState then
        Toast("An affix apply queue is already running.")
        return false
    end

    local steps = {}
    for _, step in ipairs(plan or {}) do
        if not step.skipReason then
            steps[#steps + 1] = step
        end
    end

    if #steps == 0 then
        if onDone then onDone(false, "no steps") end
        return false
    end

    queueState = {
        steps       = steps,
        index       = 0,
        applied     = 0,
        onProgress  = onProgress,
        onDone      = onDone,
        phase       = "idle",
    }

    AdvanceQueue()
    return true
end

function EbonBuilds.AffixApply.IsRunning()
    return queueState ~= nil
end

function EbonBuilds.AffixApply.FormatPlanLine(step)
    if step.skipReason then
        return string.format("Skipped: %s (%s)", step.toAffix or "?", step.skipReason)
    end
    local fromText = step.fromAffix or "(none)"
    local costText = step.applyCost and (" (" .. EbonBuilds.AffixApply.FormatCost(step.applyCost) .. ")") or ""
    return string.format("%s: %s -> %s%s", step.slotLabel, fromText, step.toAffix, costText)
end

function EbonBuilds.AffixApply.Init()
    if not (ProjectEbonhold and ProjectEbonhold.onEventReceived and ProjectEbonhold.SS) then
        return
    end

    local id = ProjectEbonhold.SS.SEND_AFFIX_APPLY_RESULT
    ProjectEbonhold.onEventReceived(id, function(body)
        OnApplyResult(body)
        if body == "OK" then
            if ExtractionUI and ExtractionUI.OnApplySuccess then
                ExtractionUI.OnApplySuccess()
            end
        else
            local _, reason = body:match("^([^,]+),(.+)$")
            if ExtractionUI and ExtractionUI.OnApplyFail then
                ExtractionUI.OnApplyFail(reason)
            end
        end
    end)
end
