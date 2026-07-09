-- EbonBuilds: modules/gear/AffixScan.lua
-- Scans equipped gear on a unit (player or inspect target) for PE affix names.

EbonBuilds.AffixScan = {}

local ROMAN_VALUES = { I = 1, V = 5, X = 10, L = 50, C = 100, D = 500, M = 1000 }
local TIER_ROMANS  = { "I", "II", "III", "IV", "V" }

EbonBuilds.AffixScan.SLOT_LABELS = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulders", [4] = "Shirt",
    [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
    [9] = "Wrists", [10] = "Hands", [11] = "Ring 1", [12] = "Ring 2",
    [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back",
    [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged", [19] = "Tabard",
}

local scanTooltip = CreateFrame("GameTooltip", "EbonBuildsAffixScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

-- Defer inspect scans briefly after INSPECT_READY so we don't run slot reads in
-- the same tick as DBM/Skada LibGroupTalents talent refresh (pool corruption).
local SCAN_DEFER_SEC = 0.75
local scanInFlight = false

local function StripColor(text)
    if not text then return nil end
    return text:gsub("|c%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function RomanToInt(s)
    if not s or s == "" then return nil end
    local total, prev = 0, 0
    for i = #s, 1, -1 do
        local v = ROMAN_VALUES[s:sub(i, i)]
        if not v then return nil end
        if v < prev then total = total - v else total = total + v end
        prev = v
    end
    return total > 0 and total or nil
end

function EbonBuilds.AffixScan.NormalizeAffixName(name)
    if not name then return nil end
    return name:gsub("|c%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
end

function EbonBuilds.AffixScan.HasRomanTierSuffix(name)
    local clean = EbonBuilds.AffixScan.NormalizeAffixName(name)
    if not clean then return false end
    if clean:match(" (I|II|III|IV|V)$") then return true end
    if clean:match(" (i|ii|iii|iv|v)$") then return true end
    -- Fallback: last token is a tier numeral (handles odd spacing / spell names).
    local last = clean:match("%s(%S+)$")
    if last then
        local upper = last:upper()
        if upper == "I" or upper == "II" or upper == "III" or upper == "IV" or upper == "V" then
            return true
        end
    end
    return false
end

-- Unranked affixes (e.g. Vulnerability, Shackling) are weapon-only; armor uses I–V tiers.
function EbonBuilds.AffixScan.IsWeaponOnlyAffixName(name)
    return name ~= nil and not EbonBuilds.AffixScan.HasRomanTierSuffix(name)
end

local function ParseUnrankedAffixFromTitle(liveName, baseName)
    if not liveName or liveName == "" or not baseName or liveName == baseName then
        return nil
    end
    if liveName:match(" [IVXLCDM]+$") then
        return nil
    end
    if liveName:sub(1, #baseName) ~= baseName then
        return nil
    end
    local affixName = liveName:sub(#baseName + 1):match("^ of (.+)$")
    if not affixName or affixName == "" then
        return nil
    end
    return { name = affixName, rank = nil }
end

local function ParseAffixFromTitle(liveName, baseName)
    if not liveName or liveName == "" or not baseName or liveName == baseName then
        return nil
    end
    local rankStr = liveName:match(" ([IVXLCDM]+)$")
    if not rankStr then return nil end
    local rank = RomanToInt(rankStr)
    if not rank then return nil end

    local affixName
    if liveName:sub(1, #baseName + 1) == (baseName .. " ") then
        affixName = liveName:sub(#baseName + 2, #liveName - #rankStr - 1)
    else
        affixName = liveName:sub(1, #liveName - #rankStr - 1)
    end
    if not affixName or affixName == "" then return nil end
    return { name = affixName, rank = rank }
end

local function FormatAffixName(parsed)
    local name = parsed.name
    if name:sub(1, 3):lower() == "of " then
        name = name:sub(4)
    end
    local roman = TIER_ROMANS[parsed.rank]
    if roman then
        return name .. " " .. roman
    end
    return name
end

local function HasRandomProperty(link)
    if not link then return false end
    local randomProp = select(8, strsplit(":", link))
    randomProp = randomProp and tonumber(randomProp)
    return randomProp and randomProp ~= 0
end

local function FindLearnedAffixOnTooltip(link)
    if not link or not HasRandomProperty(link) then return nil end
    local svc = _G.ExtractionService
    local affixes = svc and svc.learnedAffixes
    if not affixes or #affixes == 0 then return nil end

    local nameToAffix = {}
    for _, affix in ipairs(affixes) do
        if affix.name then
            nameToAffix[affix.name:lower()] = affix.name
        end
    end

    scanTooltip:ClearLines()
    scanTooltip:SetHyperlink(link)
    for j = 1, scanTooltip:NumLines() do
        local lineObj = _G["EbonBuildsAffixScanTooltipTextLeft" .. j]
        local text = lineObj and lineObj:GetText()
        if text then
            local lower = text:lower()
            for name, displayName in pairs(nameToAffix) do
                local startPos, endPos = lower:find(name, 1, true)
                if startPos then
                    local before = startPos > 1 and lower:sub(startPos - 1, startPos - 1) or ""
                    local after = lower:sub(endPos + 1, endPos + 1)
                    if (before == "" or not before:match("%w")) and (after == "" or not after:match("%w")) then
                        return displayName
                    end
                end
            end
        end
    end
    return nil
end

local function GetTooltipLiveName(unit, slot, link, hyperlinkOnly)
    scanTooltip:ClearLines()
    if link then
        scanTooltip:SetHyperlink(link)
        local lineObj = _G["EbonBuildsAffixScanTooltipTextLeft1"]
        local liveName = lineObj and StripColor(lineObj:GetText())
        if liveName and liveName ~= "" then
            return liveName
        end
    end
    -- Never touch inspect-unit inventory slots; SetInventoryItem on an inspected
    -- player can re-enter inspect handling and trip LibGroupTalents.
    if hyperlinkOnly or not unit or not slot then
        return nil
    end
    scanTooltip:ClearLines()
    scanTooltip:SetInventoryItem(unit, slot)
    local lineObj = _G["EbonBuildsAffixScanTooltipTextLeft1"]
    return lineObj and StripColor(lineObj:GetText())
end

local function GetAffixNameFromSlot(unit, slot, link, hyperlinkOnly)
    local baseName = GetItemInfo(link)
    if baseName then
        local liveName = GetTooltipLiveName(unit, slot, link, hyperlinkOnly)
        local parsed = ParseAffixFromTitle(liveName, baseName)
        if not parsed then
            parsed = ParseUnrankedAffixFromTitle(liveName, baseName)
        end
        if parsed then
            return FormatAffixName(parsed)
        end
    end
    return FindLearnedAffixOnTooltip(link)
end

function EbonBuilds.AffixScan.IsWeaponInvSlot(invSlot)
    return invSlot == 16 or invSlot == 17 or invSlot == 18
end

function EbonBuilds.AffixScan.ClientBagSlotToServer(bag, slot)
    if bag == 0 then
        return 255, 22 + slot
    end
    return 18 + bag, slot - 1
end

function EbonBuilds.AffixScan.FindEmptyBagSlot()
    for bag = 0, 4 do
        for slotIdx = 1, GetContainerNumSlots(bag) do
            if not GetContainerItemInfo(bag, slotIdx) then
                return bag, slotIdx
            end
        end
    end
    return nil, nil
end

function EbonBuilds.AffixScan.ResolveAffixNameToRecord(name)
    if not name then return nil end
    local svc = _G.ExtractionService
    local affixes = svc and svc.learnedAffixes
    if not affixes then return nil end
    local key = name:lower()
    for _, affix in ipairs(affixes) do
        if affix.name and affix.name:lower() == key then
            return affix
        end
    end
    return nil
end

function EbonBuilds.AffixScan.IsEquipableGreenPlus(link)
    if not link then return false end
    local _, _, quality, _, _, _, _, _, itemEquipLoc = GetItemInfo(link)
    if not itemEquipLoc or itemEquipLoc == "" or itemEquipLoc == "INVTYPE_NON_EQUIP" then
        return false
    end
    return quality and quality >= 2
end

function EbonBuilds.AffixScan.ScanEquippedSlots(unit)
    unit = unit or "player"
    local slots = {}
    for invSlot = 1, 19 do
        local link = GetInventoryItemLink(unit, invSlot)
        if link and EbonBuilds.AffixScan.IsEquipableGreenPlus(link) then
            slots[#slots + 1] = {
                invSlot   = invSlot,
                link      = link,
                slotLabel = EbonBuilds.AffixScan.SLOT_LABELS[invSlot] or ("Slot " .. invSlot),
                affixName = GetAffixNameFromSlot(unit, invSlot, link),
            }
        end
    end
    return slots
end

function EbonBuilds.AffixScan.GetInspectUnit()
    -- Require the native inspect UI to be open. Scanning via NotifyInspect on
    -- "target" alone can trip LibGroupTalents/DBM talent-query hooks.
    if InspectFrame
        and InspectFrame:IsShown()
        and InspectFrame.unit
        and UnitExists(InspectFrame.unit) then
        return InspectFrame.unit
    end
    return nil
end

function EbonBuilds.AffixScan.ScanUnit(unit, hyperlinkOnly)
    unit = unit or "player"
    local names = {}
    local seen = {}

    for slot = 1, 19 do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local affixName = GetAffixNameFromSlot(unit, slot, link, hyperlinkOnly)
            if affixName and not seen[affixName:lower()] then
                seen[affixName:lower()] = true
                names[#names + 1] = affixName
            end
        end
    end

    return names
end

local INSPECT_TIMEOUT = 3.0

local function HasInspectItemLinks(unit)
    for slot = 1, 19 do
        if GetInventoryItemLink(unit, slot) then
            return true
        end
    end
    return false
end

local function InspectUiOpenForUnit(unit)
    return InspectFrame
        and InspectFrame:IsShown()
        and InspectFrame.unit
        and UnitExists(InspectFrame.unit)
        and UnitGUID(InspectFrame.unit) == UnitGUID(unit)
end

function EbonBuilds.AffixScan.ScanInspectedPlayer(onComplete, onError)
    if scanInFlight then
        if onError then onError("Affix scan already in progress.") end
        return
    end

    local unit = EbonBuilds.AffixScan.GetInspectUnit()
    if not unit then
        if onError then onError("Open the inspect window on a player first.") end
        return
    end
    if not CanInspect(unit) then
        if onError then onError("Cannot inspect this player.") end
        return
    end

    scanInFlight = true

    if ExtractionService and ExtractionService.RequestLearnedAffixes then
        ExtractionService.RequestLearnedAffixes()
    end

    local function finish()
        scanInFlight = false
        if not InspectUiOpenForUnit(unit) then
            if onError then onError("Inspect window closed before scan finished.") end
            return
        end
        local names = EbonBuilds.AffixScan.ScanUnit(unit, true)
        local playerName = UnitName(unit) or "Unknown"
        local _, classToken = UnitClass(unit)
        if onComplete then onComplete(names, playerName, classToken) end
    end

    local function scheduleFinish()
        C_Timer.After(SCAN_DEFER_SEC, finish)
    end

    if HasInspectItemLinks(unit) then
        scheduleFinish()
        return
    end

    -- Inspect frame is open but gear links are not cached yet. Wait for
    -- Blizzard's inspect request (INSPECT_READY) — never call NotifyInspect
    -- ourselves; redundant inspect requests crash LibGroupTalents.
    local waiter = CreateFrame("Frame")
    local guid = UnitGUID(unit)
    local elapsed = 0

    local function cleanup()
        waiter:UnregisterAllEvents()
        waiter:SetScript("OnEvent", nil)
        waiter:SetScript("OnUpdate", nil)
    end

    local function complete()
        cleanup()
        scheduleFinish()
    end

    local function abortScan(msg)
        cleanup()
        scanInFlight = false
        if onError then onError(msg) end
    end

    local function tryComplete()
        if not InspectUiOpenForUnit(unit) then
            abortScan("Inspect window closed before scan finished.")
            return true
        end
        if HasInspectItemLinks(unit) then
            complete()
            return true
        end
        return false
    end

    waiter:RegisterEvent("INSPECT_READY")
    waiter:SetScript("OnEvent", function(_, _, readyGuid)
        if readyGuid == guid then
            tryComplete()
        end
    end)

    waiter:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if tryComplete() then return end

        if elapsed >= INSPECT_TIMEOUT then
            complete()
        end
    end)
end

local inspectScanBtn

local function EnsureInspectScanButton()
    if inspectScanBtn or not InspectFrame then return end

    inspectScanBtn = CreateFrame("Button", "EbonBuildsInspectScanBtn", InspectFrame, "UIPanelButtonTemplate")
    inspectScanBtn:SetSize(96, 22)
    inspectScanBtn:SetText("Scan Affixes")
    inspectScanBtn:SetScript("OnClick", function()
        if EbonBuilds.Build and EbonBuilds.Build.QuickScanInspectedAffixes then
            EbonBuilds.Build.QuickScanInspectedAffixes()
        end
    end)
    inspectScanBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("EbonBuilds: Scan Affixes")
        GameTooltip:AddLine("Save this player's gear affixes to your matching class build.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    inspectScanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if InspectFrameCloseButton then
        inspectScanBtn:SetPoint("RIGHT", InspectFrameCloseButton, "LEFT", -4, 0)
    else
        inspectScanBtn:SetPoint("TOPRIGHT", InspectFrame, "TOPRIGHT", -40, -12)
    end
    inspectScanBtn:Hide()

    InspectFrame:HookScript("OnShow", function()
        if inspectScanBtn then inspectScanBtn:Show() end
    end)
    InspectFrame:HookScript("OnHide", function()
        if inspectScanBtn then inspectScanBtn:Hide() end
    end)
end

function EbonBuilds.AffixScan.Init()
    if InspectFrame then
        EnsureInspectScanButton()
        return
    end
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("PLAYER_LOGIN")
    loader:SetScript("OnEvent", function(self)
        EnsureInspectScanButton()
        self:UnregisterAllEvents()
    end)
end
