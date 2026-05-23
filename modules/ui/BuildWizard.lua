-- EbonBuilds: modules/ui/BuildWizard.lua
-- Responsibility: guided build creation wizard (6 steps). Generates a build
-- configuration via preset buttons, then hands off to manual editing for refinement.

EbonBuilds.BuildWizard = {}

local CLASS_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"
local QUALITY_COLOR = {
    [0] = "ffffff", [1] = "19ff19", [2] = "0066ff", [3] = "cc66ff", [4] = "ff8000",
}
local QUALITY_BORDER_COLORS = {
    [0] = { 1.0,  1.0,  1.0 },
    [1] = { 30/255, 1.0, 0.0 },
    [2] = { 0.0, 112/255, 221/255 },
    [3] = { 163/255, 53/255, 238/255 },
    [4] = { 1.0, 128/255, 0.0 },
}
local QUALITY_LABELS = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local FAMILIES = {
    { key = "Tank",         label = "Tank" },
    { key = "Survivability", label = "Survivability" },
    { key = "Healer",       label = "Healer" },
    { key = "Caster",       label = "Caster DPS" },
    { key = "Melee",        label = "Melee DPS" },
    { key = "Ranged",       label = "Ranged DPS" },
}
local WEIGHT_OPTIONS = {
    { label = "Want it", value = 50 },
    { label = "Good",   value = 40 },
    { label = "OK",     value = 30 },
    { label = "Mehh",   value = 20 },
}

local viewFrame, contentArea
local stepLabel, backBtn, nextBtn

local state = {}
local echoListCache = {}

local function BuildFilteredEchoList()
    local best = EbonBuilds.EchoTableRows.BuildBestByName()
    local lockedSet = {}
    for i = 1, 4 do
        if state.locked[i] then
            local n = GetSpellInfo(state.locked[i])
            if n then lockedSet[n] = true end
        end
    end
    local list = {}
    for name, entry in pairs(best) do
        if not state.echoes[name] and not lockedSet[name] then
            list[#list + 1] = {
                spellId = entry.spellId,
                name    = name,
                quality = entry.quality,
            }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function SetClassIcon(tex, classToken)
    local coords = CLASS_ICON_TCOORDS[classToken]
    tex:SetTexture(CLASS_TEXTURE)
    if coords then tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
end

local function CreateIconButton(parent, size)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(size)
    btn:SetHeight(size)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn._icon = icon
    return btn
end

local function HighlightButton(btn, on)
    if not btn._hl then
        local b = btn:CreateTexture(nil, "OVERLAY")
        b:SetAllPoints(btn)
        b:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        b:SetBlendMode("ADD")
        b:Hide()
        btn._hl = b
    end
    if on then btn._hl:Show() else btn._hl:Hide() end
end

local function ClearContent()
    if not contentArea then return end
    for _, child in ipairs({ contentArea:GetChildren() }) do
        child:Hide()
    end
    for _, region in ipairs({ contentArea:GetRegions() }) do
        region:Hide()
    end
end

local function HasAdaptivePower()
    for i = 1, 4 do
        local id = state.locked[i]
        if id then
            local name = GetSpellInfo(id)
            if name and name:lower():find("adaptive power") then
                return true
            end
        end
    end
    return false
end

local function TotalSteps()
    return HasAdaptivePower() and 6 or 5
end

local function UpdateNavButtons()
    local total = TotalSteps()
    local realStep = state.step
    -- If step 2 was skipped (no adaptive power), steps 3-5 are really steps 2-4 and review is 5
    -- We track a displayStep that shifts when adaptive power is absent
    if not HasAdaptivePower() and state.step >= 2 then
        realStep = state.step - 1
    end
    stepLabel:SetText("Step " .. realStep .. "/" .. total)
    if state.step <= 0 then
        backBtn:Disable()
    else
        backBtn:Enable()
    end
    if state.step >= 6 then
        nextBtn:SetText("Create Build")
    else
        nextBtn:SetText("Next")
    end
end

local function NextStep()
    if state.step == 2 and not HasAdaptivePower() then
        state.step = 3
    end
    state.step = state.step + 1
end

local function PrevStep()
    state.step = state.step - 1
    if state.step == 2 and not HasAdaptivePower() then
        state.step = 1
    end
end

------------------------------------------------------------------------
-- Step 1: Locked Echoes
------------------------------------------------------------------------

local lockedButtons = {}

local function RenderStep1()
    ClearContent()

    local title = contentArea:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", contentArea, "TOP", 0, -20)
    title:SetText("Select your 4 locked echoes")

    local slotSize = 48
    local spacing  = 10
    local totalW   = 4 * slotSize + 3 * spacing
    local startX   = -math.floor(totalW / 2)

    for i = 1, 4 do
        local btn = CreateIconButton(contentArea, slotSize)
        btn:SetPoint("TOP", contentArea, "TOP", startX + (i - 1) * (slotSize + spacing), -90)
        btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
        btn.spellId = nil
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        EbonBuilds.EchoTableRows.WireIconTooltip(btn)

        local border = btn:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -3,  3)
        border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  3, -3)
        border:Hide()
        btn._border = border

        if state.locked[i] then
            btn.spellId = state.locked[i]
            btn._icon:SetTexture(select(3, GetSpellInfo(state.locked[i])))
            local data = ProjectEbonhold.PerkDatabase[state.locked[i]]
            local quality = data and data.quality or 0
            local bc = QUALITY_BORDER_COLORS[quality] or QUALITY_BORDER_COLORS[0]
            border:SetTexture(bc[1], bc[2], bc[3])
            border:Show()
        end

        local idx = i
        btn:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                state.locked[idx] = nil
                btn.spellId = nil
                btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
                btn._border:Hide()
                return
            end
            EbonBuilds.EchoPicker.Show(function(spellId, quality, _)
                state.locked[idx] = spellId
                btn.spellId = spellId
                btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
                local bc = QUALITY_BORDER_COLORS[quality] or QUALITY_BORDER_COLORS[0]
                btn._border:SetTexture(bc[1], bc[2], bc[3])
                btn._border:Show()
            end, BuildFilteredEchoList())
        end)
        lockedButtons[i] = btn
    end
end

------------------------------------------------------------------------
-- Step 2: Adaptive Power (conditional)
------------------------------------------------------------------------

local noveltySlider, noveltyValueLabel

local function RenderStep2()
    ClearContent()

    local title = contentArea:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", contentArea, "TOP", 0, -30)
    title:SetText("Adaptive Power detected!")

    local desc = contentArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOP", contentArea, "TOP", 0, -52)
    desc:SetText("Adaptive Power gains bonus for echoes you haven't picked yet.")

    local slider = CreateFrame("Slider", "EbonBuildsWizardNoveltySlider", contentArea, "OptionsSliderTemplate")
    slider:SetPoint("TOP", contentArea, "TOP", 0, -110)
    slider:SetWidth(300)
    slider:SetHeight(24)
    slider:SetMinMaxValues(0, 100)
    slider:SetValueStep(1)
    slider:SetValue(state.noveltyValue or 30)
    local sliderName = slider:GetName()
    if sliderName then
        _G[sliderName .. "Low"]:SetText("0")
        _G[sliderName .. "High"]:SetText("100")
    end

    local valLabel = contentArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    valLabel:SetPoint("TOP", slider, "BOTTOM", 0, -10)
    valLabel:SetText(tostring(state.noveltyValue or 30))
    noveltyValueLabel = valLabel

    local hint = contentArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", valLabel, "BOTTOM", 0, -8)
    hint:SetText("Suggested: 30 points")

    slider:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v)
        state.noveltyValue = v
        noveltyValueLabel:SetText(tostring(v))
    end)
    noveltySlider = slider
end

------------------------------------------------------------------------
-- Step 3: Family Bonuses
------------------------------------------------------------------------

local familyCycleLabels = { [0] = "|cff888888None|r", [10] = "Secondary +10", [20] = "Primary +20" }
local familyCycleValues = { 0, 10, 20 }

local function FamilyNextValue(current)
    for i, v in ipairs(familyCycleValues) do
        if v == current then
            local nextIdx = i + 1
            if nextIdx > #familyCycleValues then nextIdx = 1 end
            return familyCycleValues[nextIdx]
        end
    end
    return 0
end

local function FamilyPrevValue(current)
    for i, v in ipairs(familyCycleValues) do
        if v == current then
            local prevIdx = i - 1
            if prevIdx < 1 then prevIdx = #familyCycleValues end
            return familyCycleValues[prevIdx]
        end
    end
    return 0
end

local function RenderFamilyRow(familyEntry, anchorY)
    local rowW = 360
    local row = CreateFrame("Frame", nil, contentArea)
    row:SetPoint("TOP", contentArea, "TOP", 0, anchorY)
    row:SetWidth(rowW)
    row:SetHeight(26)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
    label:SetWidth(130)
    label:SetJustifyH("RIGHT")
    label:SetText(familyEntry.label)

    local famKey = familyEntry.key
    local currentVal = state.familyPriorities[famKey] or 0

    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetWidth(100)
    btn:SetHeight(22)
    btn:SetPoint("LEFT", label, "RIGHT", 32, 0)
    btn:SetText(familyCycleLabels[currentVal])

    local function RefreshBtn()
        btn:SetText(familyCycleLabels[state.familyPriorities[famKey] or 0])
    end

    local leftArrow = CreateFrame("Button", nil, row)
    leftArrow:SetWidth(18)
    leftArrow:SetHeight(18)
    leftArrow:SetPoint("RIGHT", btn, "LEFT", -8, 0)
    leftArrow:SetNormalFontObject("GameFontNormal")
    leftArrow:SetText("<")
    leftArrow:SetScript("OnClick", function()
        state.familyPriorities[famKey] = FamilyPrevValue(state.familyPriorities[famKey] or 0)
        RefreshBtn()
    end)

    local rightArrow = CreateFrame("Button", nil, row)
    rightArrow:SetWidth(18)
    rightArrow:SetHeight(18)
    rightArrow:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    rightArrow:SetNormalFontObject("GameFontNormal")
    rightArrow:SetText(">")
    rightArrow:SetScript("OnClick", function()
        state.familyPriorities[famKey] = FamilyNextValue(state.familyPriorities[famKey] or 0)
        RefreshBtn()
    end)

    btn:SetScript("OnClick", function()
        state.familyPriorities[famKey] = FamilyNextValue(state.familyPriorities[famKey] or 0)
        RefreshBtn()
    end)

    return row
end

local function RenderStep3()
    ClearContent()

    local title = contentArea:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", contentArea, "TOP", 0, -20)
    title:SetText("Choose your families")

    local desc = contentArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOP", contentArea, "TOP", 0, -42)
    desc:SetText("Defaults are good for most builds. Change only if you really need to.")

    for i, entry in ipairs(FAMILIES) do
        RenderFamilyRow(entry, -72 - (i - 1) * 30)
    end
end

------------------------------------------------------------------------
-- Step 4: Quality Bonuses
------------------------------------------------------------------------

local qualityValues = { 0, 5, 10, 15, 20, 25, 30, 35, 40 }

local function NextQualityValue(current)
    for i, v in ipairs(qualityValues) do
        if v == current then
            local nextIdx = i + 1
            if nextIdx > #qualityValues then nextIdx = 1 end
            return qualityValues[nextIdx]
        end
    end
    return 0
end

local function PrevQualityValue(current)
    for i, v in ipairs(qualityValues) do
        if v == current then
            local prevIdx = i - 1
            if prevIdx < 1 then prevIdx = #qualityValues end
            return qualityValues[prevIdx]
        end
    end
    return 0
end

local function RenderQualityRow(q, anchorY)
    local row = CreateFrame("Frame", nil, contentArea)
    row:SetPoint("TOP", contentArea, "TOP", 0, anchorY)
    row:SetWidth(360)
    row:SetHeight(28)

    local colorHex = QUALITY_COLOR[q] or "ffffff"
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetWidth(130)
    label:SetJustifyH("RIGHT")
    label:SetText("|cff" .. colorHex .. QUALITY_LABELS[q + 1] .. "|r")

    local currentVal = state.qualityBonus[q]
    if currentVal == nil then currentVal = q * 10 end
    state.qualityBonus[q] = currentVal

    local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetWidth(100)
    btn:SetHeight(22)
    btn:SetPoint("LEFT", label, "RIGHT", 32, 0)
    btn:SetText("+" .. tostring(currentVal))

    local function RefreshBtn()
        btn:SetText("+" .. tostring(state.qualityBonus[q]))
    end

    local leftArrow = CreateFrame("Button", nil, row)
    leftArrow:SetWidth(18)
    leftArrow:SetHeight(18)
    leftArrow:SetPoint("RIGHT", btn, "LEFT", -8, 0)
    leftArrow:SetNormalFontObject("GameFontNormal")
    leftArrow:SetText("<")
    leftArrow:SetScript("OnClick", function()
        state.qualityBonus[q] = PrevQualityValue(state.qualityBonus[q])
        RefreshBtn()
    end)

    local rightArrow = CreateFrame("Button", nil, row)
    rightArrow:SetWidth(18)
    rightArrow:SetHeight(18)
    rightArrow:SetPoint("LEFT", btn, "RIGHT", 8, 0)
    rightArrow:SetNormalFontObject("GameFontNormal")
    rightArrow:SetText(">")
    rightArrow:SetScript("OnClick", function()
        state.qualityBonus[q] = NextQualityValue(state.qualityBonus[q])
        RefreshBtn()
    end)

    btn:SetScript("OnClick", function()
        state.qualityBonus[q] = NextQualityValue(state.qualityBonus[q])
        RefreshBtn()
    end)
end

local function RenderStep4()
    ClearContent()

    local title = contentArea:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", contentArea, "TOP", 0, -20)
    title:SetText("Rate each quality tier")

    local desc = contentArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOP", contentArea, "TOP", 0, -42)
    desc:SetText("Defaults are good for most builds. Change only if you really need to.")

    for i, q in ipairs({ 0, 1, 2, 3, 4 }) do
        RenderQualityRow(q, -72 - (i - 1) * 32)
    end
end

------------------------------------------------------------------------
-- Step 5: Echo Weights
------------------------------------------------------------------------

local echoRows = {}

local function RenderEchoRow(entry, index, y)
    local row = CreateFrame("Frame", nil, contentArea)
    row:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 10, y)
    row:SetPoint("RIGHT",   contentArea, "RIGHT",   10, 0)
    row:SetHeight(28)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(22)
    icon:SetHeight(22)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(select(3, GetSpellInfo(entry.spellId)))

    local color = QUALITY_COLOR[entry.quality] or "ffffff"
    local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("LEFT",  icon, "RIGHT", 4, 0)
    nameLabel:SetWidth(140)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetText("|cff" .. color .. entry.name .. "|r")

    local btns = {}
    local currentVal = state.echoes[entry.name] and state.echoes[entry.name].weight or 40
    local btnStartX = 170

    for j, opt in ipairs(WEIGHT_OPTIONS) do
        local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btn:SetWidth(55)
        btn:SetHeight(18)
        btn:SetPoint("LEFT", row, "LEFT", btnStartX + (j - 1) * 60, -2)
        btn:SetText(opt.label)
        btn._val = opt.value

        if opt.value == currentVal then
            HighlightButton(btn, true)
        end

        btn:SetScript("OnClick", function(self)
            state.echoes[entry.name].weight = self._val
            for _, b in ipairs(btns) do
                HighlightButton(b, b._val == self._val)
            end
        end)
        btns[j] = btn
    end

    local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    removeBtn:SetWidth(56)
    removeBtn:SetHeight(18)
    removeBtn:SetPoint("LEFT", row, "LEFT", btnStartX + 4 * 60 + 6, -2)
    removeBtn:SetText("Remove")
    removeBtn:SetScript("OnClick", function()
        state.echoes[entry.name] = nil
        RenderStep5()
    end)

    table.insert(echoRows, row)
    return row
end

local function RenderStep5()
    ClearContent()
    for _, row in ipairs(echoRows) do row:Hide() end
    echoRows = {}

    local title = contentArea:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", contentArea, "TOP", 0, -20)
    title:SetText("Which echoes matter most?")

    local subtitle = contentArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOP", contentArea, "TOP", 0, -42)
    subtitle:SetText("Add echoes and rate how much you want them.")

    local addBtn = CreateFrame("Button", nil, contentArea, "UIPanelButtonTemplate")
    addBtn:SetWidth(120)
    addBtn:SetHeight(20)
    addBtn:SetPoint("TOP", contentArea, "TOP", 0, -64)
    addBtn:SetText("+ Add Echo")
    addBtn:SetScript("OnClick", function()
        EbonBuilds.EchoPicker.Show(function(spellId, quality, name)
            state.echoes[name] = { spellId = spellId, quality = quality, name = name, weight = 40 }
            RenderStep5()
        end, BuildFilteredEchoList())
    end)

    local rowStartY = -96
    local count = 0
    local sorted = {}
    for _, entry in pairs(state.echoes) do
        sorted[#sorted + 1] = entry
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)

    for _, entry in ipairs(sorted) do
        count = count + 1
        RenderEchoRow(entry, count, rowStartY - (count - 1) * 30)
    end

    if count == 0 then
        local hint = contentArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOP", contentArea, "TOP", 0, -96)
        hint:SetText("No echoes added yet. Click \"+ Add Echo\" to start.")
    end
end

------------------------------------------------------------------------
-- Step 6: Title & Description
------------------------------------------------------------------------

local function RenderStep6()
    ClearContent()

    local title = contentArea:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", contentArea, "TOP", 0, -20)
    title:SetText("Name and describe your build")

    local desc = contentArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    desc:SetPoint("TOP", contentArea, "TOP", 0, -44)
    desc:SetText("You can link items, spells, and echoes in the description.")

    -- Title field
    local titleLabel = contentArea:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLabel:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 40, -80)
    titleLabel:SetText("Title:")

    local titleBox = CreateFrame("EditBox", nil, contentArea)
    titleBox:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 40, -100)
    titleBox:SetPoint("RIGHT", contentArea, "RIGHT", -40, 0)
    titleBox:SetHeight(22)
    titleBox:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    titleBox:SetTextColor(1, 1, 1, 1)
    titleBox:SetAutoFocus(false)
    titleBox:SetMaxLetters(40)
    titleBox:SetText(state.wizardTitle or "")
    titleBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    titleBox:SetScript("OnTextChanged", function(self)
        state.wizardTitle = self:GetText()
    end)

    local titleBg = CreateFrame("Frame", nil, contentArea)
    titleBg:SetPoint("TOPLEFT",     titleBox, "TOPLEFT",     -2,  2)
    titleBg:SetPoint("BOTTOMRIGHT", titleBox, "BOTTOMRIGHT",  2, -2)
    titleBg:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    titleBg:SetBackdropColor(0, 0, 0, 0.6)
    titleBg:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    titleBg:SetFrameLevel(titleBox:GetFrameLevel() - 1)

    -- Description field
    local descLabel = contentArea:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    descLabel:SetPoint("TOPLEFT", contentArea, "TOPLEFT", 40, -140)
    descLabel:SetText("Description:")

    local descBox = CreateFrame("EditBox", nil, contentArea)
    descBox:SetMultiLine(true)
    descBox:SetMaxLetters(0)
    descBox:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    descBox:SetPoint("TOPLEFT",     contentArea, "TOPLEFT",     40, -160)
    descBox:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -40,  16)
    descBox:SetAutoFocus(false)
    descBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    descBox:SetText(state.wizardDescription or "")

    local descBg = CreateFrame("Frame", nil, contentArea)
    descBg:SetPoint("TOPLEFT",     descBox, "TOPLEFT",     -2,  2)
    descBg:SetPoint("BOTTOMRIGHT", descBox, "BOTTOMRIGHT",  2, -2)
    descBg:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    descBg:SetBackdropColor(0, 0, 0, 0.6)
    descBg:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    descBg:SetFrameLevel(descBox:GetFrameLevel() - 1)

    local placeHolder = descBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeHolder:SetPoint("TOPLEFT",     descBox, "TOPLEFT",     2, -2)
    placeHolder:SetPoint("BOTTOMRIGHT", descBox, "BOTTOMRIGHT", -2,  2)
    placeHolder:SetJustifyH("LEFT")
    placeHolder:SetJustifyV("TOP")
    placeHolder:SetTextColor(0.5, 0.5, 0.5, 1)
    placeHolder:SetText("List important items, strategies, and affixes that work well with this build. You can shift-click items to link them.")

    descBox:SetScript("OnEditFocusGained", function() placeHolder:Hide() end)
    descBox:SetScript("OnEditFocusLost", function(self)
        if (self:GetText() or "") == "" then placeHolder:Show() end
    end)
    descBox:SetScript("OnTextChanged", function(self)
        if self:HasFocus() then
            placeHolder:Hide()
        else
            if (self:GetText() or "") == "" then placeHolder:Show() else placeHolder:Hide() end
        end
        state.wizardDescription = self:GetText()
    end)

    -- Show placeholder if empty
    if (descBox:GetText() or "") == "" then placeHolder:Show() else placeHolder:Hide() end
end

------------------------------------------------------------------------
-- Build creation
------------------------------------------------------------------------

local function CreateBuildFromWizard()
    EbonBuildsDB.pendingWeights = EbonBuildsDB.pendingWeights or {}

    -- Apply echo weights
    for name, entry in pairs(state.echoes) do
        EbonBuildsDB.pendingWeights[name] = entry.weight
    end

    -- Build settings from wizard
    local settings = EbonBuilds.Build.DefaultSettings()

    -- Quality bonus
    for q = 0, 4 do
        settings.qualityBonus[q] = state.qualityBonus[q] or (q * 10)
    end

    -- Family bonus
    for _, entry in ipairs(FAMILIES) do
        local val = state.familyPriorities[entry.key] or 0
        if val > 0 then
            settings.familyBonus[entry.key] = val
        end
    end

    -- Novelty
    if HasAdaptivePower() then
        settings.noveltyValue = state.noveltyValue or 30
    else
        settings.noveltyValue = 0
    end

    -- Locked echoes
    local locked = { state.locked[1], state.locked[2], state.locked[3], state.locked[4] }

    local playerClass = EbonBuilds.Build.PlayerClassToken()

    -- Store wizard data so BuildForm can load it in create mode
    EbonBuildsDB._wizardPrefill = {
        title        = state.wizardTitle ~= "" and state.wizardTitle or "New Build",
        class        = playerClass,
        spec         = EbonBuilds.Build.PlayerTopTalentTab(),
        comments     = state.wizardDescription or "",
        lockedEchoes = locked,
        settings     = settings,
        isPublic     = false,
    }
    EbonBuildsDB._isEditingBuild = true

    EbonBuilds.ViewRouter.Show("buildTabs", { mode = "create", fromWizard = true })
end

------------------------------------------------------------------------
-- Step 0: Mode Selection (landing page)
------------------------------------------------------------------------

local function RenderStep0()
    ClearContent()
    local y = -20

    local title = contentArea:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", contentArea, "TOP", 0, y)
    title:SetText("How would you like to create your build?")

    y = y - 20
    local subtitle = contentArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOP", contentArea, "TOP", 0, y)
    subtitle:SetText("Choose the mode that fits your style.")

    -- Wizard button
    local wizardBtn = CreateFrame("Button", nil, contentArea, "UIPanelButtonTemplate")
    wizardBtn:SetWidth(200)
    wizardBtn:SetHeight(40)
    wizardBtn:SetPoint("TOP", contentArea, "TOP", 0, y - 30)
    wizardBtn:SetText("Wizard Mode")
    wizardBtn:SetScript("OnClick", function()
        state.step = 1
        RenderCurrentStep()
    end)

    local wizardDesc = contentArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wizardDesc:SetPoint("TOP", wizardBtn, "BOTTOM", 0, -2)
    wizardDesc:SetText("Learn how the addon works with a guided setup. Takes you to the editor at the end.")

    -- Pro button (anchored below wizard description, not at absolute y)
    local proBtn = CreateFrame("Button", nil, contentArea, "UIPanelButtonTemplate")
    proBtn:SetWidth(200)
    proBtn:SetHeight(40)
    proBtn:SetPoint("TOP", wizardDesc, "BOTTOM", 0, -18)
    proBtn:SetText("Pro Mode")
    proBtn:SetScript("OnClick", function()
        EbonBuilds.ViewRouter.Show("buildTabs", { mode = "create" })
    end)

    local proDesc = contentArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    proDesc:SetPoint("TOP", proBtn, "BOTTOM", 0, -2)
    proDesc:SetText("Go straight to the editor with full manual control over all settings.")
end

------------------------------------------------------------------------
-- Navigation
------------------------------------------------------------------------

local function GoNext()
    if state.step >= 6 then
        CreateBuildFromWizard()
        return
    end

    -- Skip step 2 if no Adaptive Power
    if state.step == 1 and not HasAdaptivePower() then
        state.step = 3
    else
        state.step = state.step + 1
    end

    RenderCurrentStep()
end

local function GoBack()
    if state.step <= 1 then
        state.step = 0
        RenderCurrentStep()
        return
    end

    -- Skip step 2 going back if no Adaptive Power
    if state.step == 3 and not HasAdaptivePower() then
        state.step = 1
    else
        state.step = state.step - 1
    end

    RenderCurrentStep()
end

function RenderCurrentStep()
    ClearContent()
    if state.step == 0 then
        stepLabel:SetText("")
        backBtn:Hide()
        nextBtn:Hide()
        RenderStep0()
        return
    end
    backBtn:Show()
    nextBtn:Show()
    UpdateNavButtons()
    if state.step == 1 then
        RenderStep1()
    elseif state.step == 2 then
        RenderStep2()
    elseif state.step == 3 then
        RenderStep3()
    elseif state.step == 4 then
        RenderStep4()
    elseif state.step == 5 then
        RenderStep5()
    elseif state.step == 6 then
        RenderStep6()
    end
end

------------------------------------------------------------------------
-- View interface
------------------------------------------------------------------------

local view = {}

function view.Show(container, context)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)

    -- Reset state
    state.step = 0
    state.locked = { nil, nil, nil, nil }
    state.noveltyValue = 30
    state.qualityBonus = { [0] = 0, [1] = 10, [2] = 20, [3] = 30, [4] = 40 }
    state.familyPriorities = {}
    state.echoes = {}
    state.wizardTitle = ""
    state.wizardDescription = ""

    RenderCurrentStep()
    viewFrame:Show()
end

function view.Hide()
    if viewFrame then viewFrame:Hide() end
end

------------------------------------------------------------------------
-- Build view frame
------------------------------------------------------------------------

local function BuildViewFrame()
    local f = CreateFrame("Frame", nil, UIParent)

    -- Header
    local header = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
    header:SetText("Build Wizard")

    -- Step indicator
    stepLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    stepLabel:SetPoint("TOP", f, "TOP", 0, -10)

    -- Content area
    contentArea = CreateFrame("Frame", nil, f)
    contentArea:SetPoint("TOPLEFT",     f, "TOPLEFT",     0, -40)
    contentArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,  50)

    -- Navigation buttons
    backBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    backBtn:SetWidth(80)
    backBtn:SetHeight(22)
    backBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 20)
    backBtn:SetText("Back")
    backBtn:SetScript("OnClick", GoBack)

    nextBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nextBtn:SetWidth(80)
    nextBtn:SetHeight(22)
    nextBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 100, 20)
    nextBtn:SetText("Next")
    nextBtn:SetScript("OnClick", GoNext)

    f:Hide()
    return f
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function EbonBuilds.BuildWizard.Init()
    viewFrame = BuildViewFrame()
    EbonBuilds.ViewRouter.Register("buildWizard", view)
end
