-- EbonBuilds: modules/ui/Filters.lua
-- Responsibility: filter bar UI + filter state + list filtering.

EbonBuilds.Filters = {}

local FAMILIES = { "Tank", "Survivability", "Healer", "Caster DPS", "Melee DPS", "Ranged DPS", "No family" }
local QUALITY_LABELS = { "All", "Common", "Uncommon", "Rare", "Epic", "Legendary" }

local state = {
    text     = "",
    quality  = nil,
    families = {},
    showAllClasses = false,
    requiresTomeFilter = nil,  -- nil | "only" | "exclude"
    multipleRanksFilter = nil, -- nil | "only" | "exclude"
}
local changeCallbacks = {}
local searchEditBox = nil

local function Notify()
    for i = 1, #changeCallbacks do
        changeCallbacks[i]()
    end
end

function EbonBuilds.Filters.OnChange(fn)
    changeCallbacks[#changeCallbacks + 1] = fn
end

------------------------------------------------------------------------
-- Apply
------------------------------------------------------------------------

local function FamiliesActive()
    for _ in pairs(state.families) do return true end
    return false
end

local function MatchesFamilies(entry)
    if not next(state.families) then return true end
    local has = {}
    local hasAnyFamily = false
    for _, fam in ipairs(entry.families or {}) do
        has[fam] = true
        hasAnyFamily = true
    end
    for required in pairs(state.families) do
        if required == "No family" then
            if hasAnyFamily then return false end
        else
            if not has[required] then return false end
        end
    end
    return true
end

local TRI_STATE_CYCLE = { "off", "only", "exclude" }

local function EntryQualityCount(entry)
    if not entry or not entry.qualities then return 0 end
    return EbonBuilds.EchoTableRows.CountQualities
        and EbonBuilds.EchoTableRows.CountQualities(entry.qualities) or 0
end

function EbonBuilds.Filters.CycleTriStateFilter(mode)
    local current = mode or "off"
    for i, value in ipairs(TRI_STATE_CYCLE) do
        if value == current then
            local nextValue = TRI_STATE_CYCLE[(i % #TRI_STATE_CYCLE) + 1]
            return nextValue == "off" and nil or nextValue
        end
    end
    return nil
end

function EbonBuilds.Filters.PassesRequiresTomeFilter(entry, mode)
    if not mode then return true end
    if mode == "only" then return entry.requiresTome == true end
    if mode == "exclude" then return not entry.requiresTome end
    return true
end

function EbonBuilds.Filters.SyncRequiresTomeFilterUI(cb, label, mode)
    if not cb or not cb._checkTex then return end
    if mode == "only" then
        cb._checkTex:Show()
        cb._checkTex:SetVertexColor(1.0, 0.82, 0.0, 1)
        if label then
            label:SetText("Requires Tome")
            label:SetTextColor(1.0, 0.82, 0.0)
        end
    elseif mode == "exclude" then
        cb._checkTex:Show()
        cb._checkTex:SetVertexColor(1.0, 0.55, 0.2, 1)
        if label then
            label:SetText("Does Not Require Tome")
            label:SetTextColor(1.0, 0.55, 0.2)
        end
    else
        cb._checkTex:Hide()
        if label then
            label:SetText("Requires Tome")
            label:SetTextColor(0.8, 0.8, 0.8)
        end
    end
end

function EbonBuilds.Filters.PassesMultipleRanksFilter(entry, mode)
    if not mode then return true end
    local isMulti = EntryQualityCount(entry) >= 2
    if mode == "only" then return isMulti end
    if mode == "exclude" then return not isMulti end
    return true
end

function EbonBuilds.Filters.CycleMultipleRanksFilter(mode)
    return EbonBuilds.Filters.CycleTriStateFilter(mode)
end

function EbonBuilds.Filters.CycleRequiresTomeFilter(mode)
    return EbonBuilds.Filters.CycleTriStateFilter(mode)
end

function EbonBuilds.Filters.SyncMultiRankFilterUI(cb, label, mode)
    if not cb or not cb._checkTex then return end
    if mode == "only" then
        cb._checkTex:Show()
        cb._checkTex:SetVertexColor(0.6, 0.8, 1.0, 1)
        if label then
            label:SetText("Multi-Rank")
            label:SetTextColor(0.6, 0.8, 1.0)
        end
    elseif mode == "exclude" then
        cb._checkTex:Show()
        cb._checkTex:SetVertexColor(1.0, 0.55, 0.2, 1)
        if label then
            label:SetText("Exclude Multi-Rank")
            label:SetTextColor(1.0, 0.55, 0.2)
        end
    else
        cb._checkTex:Hide()
        if label then
            label:SetText("Multi-Rank")
            label:SetTextColor(0.8, 0.8, 0.8)
        end
    end
end

local function PassesFilters(entry, famActive)
    if state.text ~= "" then
        if not entry.name:lower():find(state.text, 1, true) then return false end
    end
    if state.quality ~= nil then
        if not (entry.qualities and entry.qualities[state.quality]) then return false end
    end
    if famActive then
        if not MatchesFamilies(entry) then return false end
    end
    if not EbonBuilds.Filters.PassesRequiresTomeFilter(entry, state.requiresTomeFilter) then
        return false
    end
    if not EbonBuilds.Filters.PassesMultipleRanksFilter(entry, state.multipleRanksFilter) then
        return false
    end
    return true
end

function EbonBuilds.Filters.Apply(echoList)
    local out = {}
    local famActive = FamiliesActive()
    for i = 1, #echoList do
        local entry = echoList[i]
        if PassesFilters(entry, famActive) then
            out[#out + 1] = entry
        end
    end
    return out
end

------------------------------------------------------------------------
-- UI helpers
------------------------------------------------------------------------

local function CreateSearchBox(bar)
    local container = CreateFrame("Frame", nil, bar)
    container:SetHeight(22)
    container:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    container:SetBackdropColor(0, 0, 0, 0.6)
    container:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local edit = CreateFrame("EditBox", nil, container)
    edit:SetHeight(18)
    edit:SetPoint("LEFT", container, "LEFT", 3, 0)
    edit:SetPoint("RIGHT", container, "RIGHT", -3, 0)
    edit:SetPoint("TOP", container, "TOP", 0, -2)
    edit:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    edit:SetTextColor(1, 1, 1, 1)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(60)
    edit:SetScript("OnTextChanged", function(self)
        state.text = self:GetText():lower()
        Notify()
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchEditBox = edit
    return container
end

function EbonBuilds.Filters.FocusSearch()
    if searchEditBox then searchEditBox:SetFocus() end
end

function EbonBuilds.Filters.ShowAllClasses()
    return state.showAllClasses
end

local function CreateCheckbox(bar, labelText, labelColor, anchorFrame, anchorPoint, xOff, yOff, relPoint, onToggle)
    local cb = CreateFrame("Button", nil, bar)
    cb:SetSize(16, 16)
    cb:SetPoint(anchorPoint, anchorFrame, relPoint or anchorPoint, xOff, yOff)

    local cbBg = cb:CreateTexture(nil, "BORDER")
    cbBg:SetAllPoints(cb)
    cbBg:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cbBg:SetAlpha(0.8)

    local cbCheck = cb:CreateTexture(nil, "ARTWORK")
    cbCheck:SetWidth(14)
    cbCheck:SetHeight(14)
    cbCheck:SetPoint("CENTER", cb, "CENTER", 0, 0)
    cbCheck:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cbCheck:Hide()

    local cbLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cbLabel:SetPoint("RIGHT", cb, "LEFT", -4, 0)
    cbLabel:SetPoint("TOP", cb, "TOP", 0, 0)
    cbLabel:SetPoint("BOTTOM", cb, "BOTTOM", 0, 0)
    cbLabel:SetJustifyH("RIGHT")
    cbLabel:SetJustifyV("MIDDLE")
    cbLabel:SetText(labelText)
    if labelColor then
        cbLabel:SetTextColor(labelColor[1], labelColor[2], labelColor[3])
    end

    cb:SetScript("OnClick", function()
        local checked = onToggle()
        if checked then cbCheck:Show() else cbCheck:Hide() end
        Notify()
    end)

    return cb, cbLabel
end

local function CreateRequiresTomeCycleCheckbox(bar, anchorFrame, anchorPoint, xOff, yOff, relPoint)
    local cb = CreateFrame("Button", nil, bar)
    cb:SetSize(16, 16)
    cb:SetPoint(anchorPoint, anchorFrame, relPoint or anchorPoint, xOff, yOff)

    local cbBg = cb:CreateTexture(nil, "BORDER")
    cbBg:SetAllPoints(cb)
    cbBg:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cbBg:SetAlpha(0.8)

    local cbCheck = cb:CreateTexture(nil, "ARTWORK")
    cbCheck:SetWidth(14)
    cbCheck:SetHeight(14)
    cbCheck:SetPoint("CENTER", cb, "CENTER", 0, 0)
    cbCheck:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cbCheck:Hide()
    cb._checkTex = cbCheck

    local cbLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cbLabel:SetPoint("RIGHT", cb, "LEFT", -4, 0)
    cbLabel:SetPoint("TOP", cb, "TOP", 0, 0)
    cbLabel:SetPoint("BOTTOM", cb, "BOTTOM", 0, 0)
    cbLabel:SetJustifyH("RIGHT")
    cbLabel:SetJustifyV("MIDDLE")
    cbLabel:SetText("Requires Tome")
    cbLabel:SetTextColor(0.8, 0.8, 0.8)

    cb:SetScript("OnEnter", function()
        GameTooltip:SetOwner(cb, "ANCHOR_TOP")
        GameTooltip:SetText("Requires Tome Filter", 1, 0.82, 0)
        local mode = state.requiresTomeFilter
        if mode == "only" then
            GameTooltip:AddLine("Showing echoes that require a tome only.", 0.8, 0.8, 0.8, true)
        elseif mode == "exclude" then
            GameTooltip:AddLine("Showing echoes that do not require a tome only.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("No tome filter active.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine("Click to cycle filter.", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cb:SetScript("OnClick", function()
        state.requiresTomeFilter = EbonBuilds.Filters.CycleRequiresTomeFilter(state.requiresTomeFilter)
        EbonBuilds.Filters.SyncRequiresTomeFilterUI(cb, cbLabel, state.requiresTomeFilter)
        Notify()
    end)

    EbonBuilds.Filters.SyncRequiresTomeFilterUI(cb, cbLabel, state.requiresTomeFilter)
    return cb, cbLabel
end

local function CreateMultiRankCycleCheckbox(bar, anchorFrame, anchorPoint, xOff, yOff, relPoint)
    local cb = CreateFrame("Button", nil, bar)
    cb:SetSize(16, 16)
    cb:SetPoint(anchorPoint, anchorFrame, relPoint or anchorPoint, xOff, yOff)

    local cbBg = cb:CreateTexture(nil, "BORDER")
    cbBg:SetAllPoints(cb)
    cbBg:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cbBg:SetAlpha(0.8)

    local cbCheck = cb:CreateTexture(nil, "ARTWORK")
    cbCheck:SetWidth(14)
    cbCheck:SetHeight(14)
    cbCheck:SetPoint("CENTER", cb, "CENTER", 0, 0)
    cbCheck:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cbCheck:Hide()
    cb._checkTex = cbCheck

    local cbLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cbLabel:SetPoint("RIGHT", cb, "LEFT", -4, 0)
    cbLabel:SetPoint("TOP", cb, "TOP", 0, 0)
    cbLabel:SetPoint("BOTTOM", cb, "BOTTOM", 0, 0)
    cbLabel:SetJustifyH("RIGHT")
    cbLabel:SetJustifyV("MIDDLE")
    cbLabel:SetText("Multi-Rank")
    cbLabel:SetTextColor(0.8, 0.8, 0.8)

    cb:SetScript("OnEnter", function()
        GameTooltip:SetOwner(cb, "ANCHOR_TOP")
        GameTooltip:SetText("Multi-Rank Filter", 1, 0.82, 0)
        local mode = state.multipleRanksFilter
        if mode == "only" then
            GameTooltip:AddLine("Showing multi-rank echoes only.", 0.8, 0.8, 0.8, true)
        elseif mode == "exclude" then
            GameTooltip:AddLine("Hiding multi-rank echoes.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("No multi-rank filter active.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine("Click to cycle filter.", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cb:SetScript("OnClick", function()
        state.multipleRanksFilter = EbonBuilds.Filters.CycleMultipleRanksFilter(state.multipleRanksFilter)
        EbonBuilds.Filters.SyncMultiRankFilterUI(cb, cbLabel, state.multipleRanksFilter)
        Notify()
    end)

    EbonBuilds.Filters.SyncMultiRankFilterUI(cb, cbLabel, state.multipleRanksFilter)
    return cb, cbLabel
end

local function CreateQualityDropdown(bar)
    local dropdown = CreateFrame("Frame", "EbonBuildsFiltersQualityDD", bar, "UIDropDownMenuTemplate")

    UIDropDownMenu_SetWidth(dropdown, 80)
    UIDropDownMenu_SetText(dropdown, "All")

    UIDropDownMenu_Initialize(dropdown, function()
        for index, name in ipairs(QUALITY_LABELS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.func = function()
                if index == 1 then state.quality = nil else state.quality = index - 2 end
                UIDropDownMenu_SetText(dropdown, name)
                Notify()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    return dropdown
end

local function CreateFamilyDropdown(bar)
    local dropdown = CreateFrame("Frame", "EbonBuildsFiltersFamilyDD", bar, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dropdown, 110)

    local function UpdateFamilyLabel()
        local count = 0
        for _ in pairs(state.families) do count = count + 1 end
        if count == 0 then
            UIDropDownMenu_SetText(dropdown, "All families")
        else
            UIDropDownMenu_SetText(dropdown, "Families (" .. count .. ")")
        end
    end

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        for _, family in ipairs(FAMILIES) do
            local info = UIDropDownMenu_CreateInfo()
            info.text             = family
            info.isNotRadio       = true
            info.keepShownOnClick = true
            info.checked          = state.families[family] and true or false
            info.func             = function(_, _, _, checked)
                if checked then
                    state.families[family] = true
                else
                    state.families[family] = nil
                end
                UpdateFamilyLabel()
                Notify()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    UpdateFamilyLabel()
    return dropdown
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function EbonBuilds.Filters.Init(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT",  parent, "TOPLEFT",   10, -34)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -34)
    bar:SetHeight(54)

    local row1 = CreateFrame("Frame", nil, bar)
    row1:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    row1:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    row1:SetHeight(26)

    local row2 = CreateFrame("Frame", nil, bar)
    row2:SetPoint("TOPLEFT", row1, "BOTTOMLEFT", 0, -2)
    row2:SetPoint("TOPRIGHT", row1, "BOTTOMRIGHT", 0, -2)
    row2:SetHeight(22)

    local classCb, classLabel = CreateCheckbox(row2, "Show All Classes", nil, row2, "RIGHT", 0, 0, function()
        state.showAllClasses = not state.showAllClasses
        return state.showAllClasses
    end)

    local _, tomeLabel = CreateRequiresTomeCycleCheckbox(row2, classLabel, "LEFT", -16, 0, "LEFT")
    CreateMultiRankCycleCheckbox(row2, tomeLabel, "LEFT", -16, 0, "LEFT")

    local familyDropdown = CreateFamilyDropdown(row1)
    familyDropdown:SetPoint("RIGHT", row1, "RIGHT", 0, 0)

    local qualityDropdown = CreateQualityDropdown(row1)
    qualityDropdown:SetPoint("RIGHT", familyDropdown, "LEFT", 4, -2)

    local searchContainer = CreateSearchBox(row1)
    searchContainer:SetPoint("LEFT", row1, "LEFT", 0, 0)
    searchContainer:SetPoint("RIGHT", qualityDropdown, "LEFT", -8, 0)

    return bar
end
