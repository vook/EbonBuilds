-- EbonBuilds: modules/ui/SettingsView.lua
-- Responsibility: render the Automation tab (banish protection, echo ban,
-- peak display and auto-behaviour thresholds).
-- Exposes Mount/Unmount. Reads and writes into BuildForm state.settings
-- so unsaved edits persist across tabs.
-- Layout-heavy/declarative: template-file exception applies.

EbonBuilds.SettingsView = {}

local QUALITY_LABELS = {
    [0] = { name = "Common",    color = "ffffff" },
    [1] = { name = "Uncommon",  color = "19ff19" },
    [2] = { name = "Rare",      color = "0066ff" },
    [3] = { name = "Epic",      color = "cc66ff" },
    [4] = { name = "Legendary", color = "ff8000" },
}

local FAMILY_ORDER = {
    "Tank", "Survivability", "Healer", "Caster", "Melee", "Ranged", "No family",
}

local THRESHOLDS = {
    { key = "autoBanishPct",    label = "Auto-banish %",   hint = "Banish echoes below this % of peak.",       min = 0, max = 100, step = 1 },
    { key = "autoRerollPct",    label = "Auto-reroll %",   hint = "Reroll when best offered is below this %.", min = 0, max = 300, step = 1 },
    { key = "autoFreezePct",    label = "Auto-freeze %",   hint = "Freeze echoes above this % of peak.",       min = 0, max = 100, step = 1 },
    { key = "freezePenaltyPct", label = "Freeze penalty %", hint = "Score penalty applied to frozen echoes.",  min = 0, max = 50,  step = 1 },
}

local viewFrame
local scrollFrame, scrollChild, scrollBar
local thresholdSliders = {}
local peakLabel
local whitelistToggles = {}
local whitelistWarningLabel

-- Echo ban state
local echoBanItems = {}
local echoBanFrame
local echoBanScroll, echoBanScrollChild, echoBanScrollBar
local echoBanAllButton

local CONTENT_HEIGHT = 600

local function CreateModeToggle(parent, x, y)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(20)
    btn:SetHeight(22)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
    btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetText("+")
    btn.modeLabel = label
    btn.multiplicative = false

    btn:SetScript("OnClick", function()
        btn.multiplicative = not btn.multiplicative
        btn.modeLabel:SetText(btn.multiplicative and "|cff19ff19x|r" or "+")
        btn.onToggle()
    end)
    return btn
end

------------------------------------------------------------------------
-- Highlight border helper (shared by toggle buttons)
------------------------------------------------------------------------

local function HighlightBorder(btn, on)
    if not btn._border then
        local b = btn:CreateTexture(nil, "OVERLAY")
        b:SetAllPoints(btn)
        b:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        b:SetBlendMode("ADD")
        b:Hide()
        btn._border = b
    end
    if on then btn._border:Show() else btn._border:Hide() end
end

------------------------------------------------------------------------
-- Peak display
------------------------------------------------------------------------

local function RefreshPeak()
    if not peakLabel then return end
    local settings = EbonBuilds.BuildForm.GetEditingSettings()
    local class    = EbonBuilds.BuildForm.GetEditingClass()
    local name, score = EbonBuilds.Scoring.ComputePeak(class, settings)
    if name then
        peakLabel:SetText(string.format("Peak: %s = %d", name, score))
    else
        peakLabel:SetText("Peak: (no echoes)")
    end
end

------------------------------------------------------------------------
-- Banish family whitelist section
------------------------------------------------------------------------

local function RefreshWhitelistToggles()
    local settings = EbonBuilds.BuildForm.GetEditingSettings()
    settings.banishFamilyWhitelist = settings.banishFamilyWhitelist or {}
    local allSelected = true
    for _, fam in ipairs(FAMILY_ORDER) do
        local row = whitelistToggles[fam]
        if row and row.checkTex then
            local selected = settings.banishFamilyWhitelist[fam] or false
            if selected then row.checkTex:Show() else row.checkTex:Hide() end
            if not selected then allSelected = false end
        end
    end
    if whitelistWarningLabel then
        if allSelected then
            whitelistWarningLabel:Show()
        else
            whitelistWarningLabel:Hide()
        end
    end
end

local function CommitWhitelistToggle(family)
    local settings = EbonBuilds.BuildForm.GetEditingSettings()
    settings.banishFamilyWhitelist = settings.banishFamilyWhitelist or {}
    if settings.banishFamilyWhitelist[family] then
        settings.banishFamilyWhitelist[family] = nil
    else
        settings.banishFamilyWhitelist[family] = true
    end
    RefreshWhitelistToggles()
end

local WHITELIST_ROW1 = { "Tank", "Survivability", "Healer", "Caster" }
local WHITELIST_ROW2 = { "Melee", "Ranged", "No family" }

local function BuildBanishWhitelistSection(parent, x, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    header:SetText("Banish Protection:")

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    hint:SetText("Checked families are protected from banish.")

    local function CreateWhitelistRow(parent, fam, px, py)
        local row = CreateFrame("Button", nil, parent)
        row:SetWidth(18)
        row:SetHeight(18)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", px, py)
        row.family = fam

        local cb = row:CreateTexture(nil, "ARTWORK")
        cb:SetWidth(14)
        cb:SetHeight(14)
        cb:SetPoint("LEFT", row, "LEFT", 2, 0)
        cb:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        cb:Hide()
        row.checkTex = cb

        local bg = row:CreateTexture(nil, "BORDER")
        bg:SetWidth(14)
        bg:SetHeight(14)
        bg:SetPoint("LEFT", row, "LEFT", 1, 0)
        bg:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
        bg:SetAlpha(0.8)

        row:SetScript("OnClick", function(self) CommitWhitelistToggle(self.family) end)
        whitelistToggles[fam] = row

        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetText(fam)
        lbl:SetPoint("LEFT", row, "RIGHT", 4, 0)
        lbl:SetJustifyH("LEFT")
    end

    for i, fam in ipairs(WHITELIST_ROW1) do
        CreateWhitelistRow(parent, fam, x + (i - 1) * 110, y - 32)
    end

    for i, fam in ipairs(WHITELIST_ROW2) do
        CreateWhitelistRow(parent, fam, x + (i - 1) * 110, y - 58)
    end

    whitelistWarningLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    whitelistWarningLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 86)
    whitelistWarningLabel:SetWidth(400)
    whitelistWarningLabel:SetJustifyH("LEFT")
    whitelistWarningLabel:SetText("|cffff0000All families are protected. At least one must be unprotected for banish to work.|r")
    whitelistWarningLabel:Hide()
end

------------------------------------------------------------------------
-- Echo Ban section
------------------------------------------------------------------------

local QUALITY_BORDER_COLORS = {
    [0] = { 1.0, 1.0, 1.0 },
    [1] = { 30/255, 1.0, 0.0 },
    [2] = { 0.0, 112/255, 221/255 },
    [3] = { 163/255, 53/255, 238/255 },
    [4] = { 1.0, 128/255, 0.0 },
}

local ICON_SIZE  = 28
local ICON_GAP   = 4
local ICON_STEP  = ICON_SIZE + ICON_GAP
local BAN_LIST_W = 380

local function RefreshBanList()
    if not echoBanFrame then return end
    for _, item in ipairs(echoBanItems) do
        item:Hide()
    end

    local settings = EbonBuilds.BuildForm.GetEditingSettings()
    local banList = settings.echoBanList or {}
    local cols = math.floor(BAN_LIST_W / ICON_STEP)
    local idx = 0

    for spellId, echoName in pairs(banList) do
        local quality = 0
        local data = ProjectEbonhold.PerkDatabase[spellId]
        if data then quality = data.quality or 0 end
        local borderColor = QUALITY_BORDER_COLORS[quality] or QUALITY_BORDER_COLORS[0]

        idx = idx + 1
        if not echoBanItems[idx] then
            local btn = CreateFrame("Button", nil, echoBanScrollChild)
            btn:SetSize(ICON_SIZE, ICON_SIZE)

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT",     btn, "TOPLEFT",     2, -2)
            icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2,  2)
            btn._icon = icon

            local border = btn:CreateTexture(nil, "OVERLAY")
            border:SetAllPoints(btn)
            border:SetTexture("Interface\\Buttons\\CheckButtonHilight")
            border:SetBlendMode("ADD")
            btn._border = border

            btn:RegisterForClicks("LeftButtonUp")
            btn:SetScript("OnEnter", function(self)
                if not self.spellId then return end
                local spellName = GetSpellInfo(self.spellId)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                if spellName then
                    local q = self._quality or 0
                    local c = QUALITY_LABELS[q] and QUALITY_LABELS[q].color or "ffffff"
                    GameTooltip:AddLine(string.format("|cff%s%s|r", c, spellName), 1, 1, 1)
                end
                if utils and utils.GetSpellDescription then
                    local desc = utils.GetSpellDescription(self.spellId, 500, 1)
                    if desc and desc ~= "" then
                        GameTooltip:AddLine(desc, 1, 1, 1, true)
                    end
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            btn:SetScript("OnClick", function(self)
                local s = EbonBuilds.BuildForm.GetEditingSettings()
                local id = self._spellId
                if id then s.echoBanList[id] = nil end
                RefreshBanList()
            end)
            echoBanItems[idx] = btn
        end

        local btn = echoBanItems[idx]
        btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
        btn.spellId = spellId
        btn._spellId = spellId
        btn._quality = quality
        btn._border:SetVertexColor(borderColor[1], borderColor[2], borderColor[3])
        btn._border:Show()
        local col = (idx - 1) % cols
        local row = math.floor((idx - 1) / cols)
        btn:SetPoint("TOPLEFT", echoBanScrollChild, "TOPLEFT", col * ICON_STEP, -row * ICON_STEP)
        btn:Show()
    end

    local rows = math.ceil(idx / math.max(cols, 1))
    local contentHeight = math.max(rows * ICON_STEP, echoBanFrame:GetHeight())
    echoBanScrollChild:SetHeight(contentHeight)
    local range = math.max(0, contentHeight - echoBanFrame:GetHeight())
    echoBanScrollBar:SetMinMaxValues(0, range)

    if idx == 0 then
        echoBanFrame._emptyLabel:Show()
    else
        echoBanFrame._emptyLabel:Hide()
    end
end

local function AddEchoToBan(name, spellId)
    local settings = EbonBuilds.BuildForm.GetEditingSettings()
    settings.echoBanList = settings.echoBanList or {}
    settings.echoBanList[spellId] = name
    RefreshBanList()
end

local function BuildEchoBanSection(parent, x, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    header:SetText("Echo Ban:")

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    hint:SetText("Echoes listed here get max banish priority and ignore scores.")

    local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBtn:SetWidth(90)
    addBtn:SetHeight(20)
    addBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 24)
    addBtn:SetText("Add Echo")
    addBtn:SetScript("OnClick", function()
        local allList = EbonBuilds.EchoTableRows.BuildAllQualitiesList()
        local settings = EbonBuilds.BuildForm.GetEditingSettings()
        local banList = settings.echoBanList or {}
        local filtered = {}
        for _, entry in ipairs(allList) do
            if not banList[entry.spellId] then
                filtered[#filtered + 1] = entry
            end
        end
        EbonBuilds.EchoPicker.Show(function(spellId, quality, name)
            AddEchoToBan(name, spellId)
        end, filtered)
    end)

    local listFrame = CreateFrame("Frame", nil, parent)
    listFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 50)
    listFrame:SetWidth(BAN_LIST_W)
    listFrame:SetHeight(80)

    echoBanScroll = CreateFrame("ScrollFrame", nil, listFrame)
    echoBanScroll:SetPoint("TOPLEFT",     listFrame, "TOPLEFT",     0, 0)
    echoBanScroll:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -16, 0)

    echoBanScrollChild = CreateFrame("Frame", nil, echoBanScroll)
    echoBanScrollChild:SetWidth(BAN_LIST_W)
    echoBanScrollChild:SetHeight(80)
    echoBanScroll:SetScrollChild(echoBanScrollChild)

    echoBanScrollBar = CreateFrame("Slider", nil, echoBanScroll, "UIPanelScrollBarTemplate")
    echoBanScrollBar:SetPoint("TOPLEFT",     echoBanScroll, "TOPRIGHT",     -14, -2)
    echoBanScrollBar:SetPoint("BOTTOMLEFT",  echoBanScroll, "BOTTOMRIGHT",  -14,  2)
    echoBanScrollBar:SetValueStep(ICON_STEP)
    echoBanScrollBar:SetValue(0)
    echoBanScrollBar:SetScript("OnValueChanged", function(self, value)
        echoBanScrollChild:SetPoint("TOPLEFT", echoBanScroll, "TOPLEFT", 0, value)
    end)

    echoBanScroll:EnableMouseWheel(true)
    echoBanScroll:SetScript("OnMouseWheel", function(self, delta)
        local current  = echoBanScrollBar:GetValue()
        local min, max = echoBanScrollBar:GetMinMaxValues()
        echoBanScrollBar:SetValue(math.max(min, math.min(max, current - delta * ICON_STEP)))
    end)

    local empty = listFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 10, -4)
    empty:SetText("No echoes banned.")
    listFrame._emptyLabel = empty

    echoBanFrame = listFrame

    local allLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    allLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 178)
    allLabel:SetWidth(300)
    allLabel:SetJustifyH("LEFT")
    allLabel:SetText("When all offered are banned and no charges left:")

    echoBanAllButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    echoBanAllButton:SetWidth(110)
    echoBanAllButton:SetHeight(20)
    echoBanAllButton:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 310, y - 173)
    echoBanAllButton:SetText("Highest Score")
    echoBanAllButton._value = "highestScore"
    echoBanAllButton:SetScript("OnClick", function(self)
        if self._value == "highestScore" then
            self._value = "random"
            self:SetText("Random")
        else
            self._value = "highestScore"
            self:SetText("Highest Score")
        end
        local s = EbonBuilds.BuildForm.GetEditingSettings()
        s.echoBanAllMode = self._value
    end)
end

------------------------------------------------------------------------
-- Peak row
------------------------------------------------------------------------

local function BuildPeakRow(parent, x, y)
    peakLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    peakLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    peakLabel:SetText("Peak: -")
end

------------------------------------------------------------------------
-- Threshold section (auto-banish / auto-reroll / auto-freeze / penalty)
------------------------------------------------------------------------

local SLIDER_W = 400

local function CreateThresholdSlider(parent, x, y, entry)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lbl:SetText(entry.label)

    local slider = CreateFrame("Slider", nil, parent)
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 20)
    slider:SetWidth(SLIDER_W)
    slider:SetHeight(24)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(entry.min, entry.max)
    slider:SetValueStep(entry.step)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetTexture(0.25, 0.25, 0.25, 0.8)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetPoint("CENTER", slider, "CENTER", 0, 0)
    track:SetHeight(6)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    thumb:SetWidth(16)
    thumb:SetHeight(24)
    slider:SetThumbTexture(thumb)

    local valText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    valText:SetWidth(40)
    valText:SetJustifyH("LEFT")
    slider._valText = valText

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -4)
    hint:SetWidth(SLIDER_W)
    hint:SetJustifyH("LEFT")
    hint:SetText(entry.hint)

    slider:SetScript("OnValueChanged", function(self, value)
        local v = math.floor(value + 0.5)
        valText:SetText(v .. "%")
        local settings = EbonBuilds.BuildForm.GetEditingSettings()
        settings[entry.key] = v
        RefreshPeak()
    end)

    return slider
end

local function BuildThresholdsSection(parent, x, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    header:SetText("Automation Thresholds:")

    local sub = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    sub:SetText("Values are percentages of the Peak score.")

    for i, entry in ipairs(THRESHOLDS) do
        local cy = y - 38 - (i - 1) * 60
        local slider = CreateThresholdSlider(parent, x + 10, cy, entry)
        thresholdSliders[entry.key] = slider
    end
end

------------------------------------------------------------------------
-- Refresh (called on Mount)
------------------------------------------------------------------------

local function RefreshInputs()
    local settings = EbonBuilds.BuildForm.GetEditingSettings()
    for _, entry in ipairs(THRESHOLDS) do
        local slider = thresholdSliders[entry.key]
        if slider then
            local val = settings[entry.key] or 0
            slider:SetValue(val)
            slider._valText:SetText(val .. "%")
        end
    end
    RefreshWhitelistToggles()
    RefreshBanList()
    if echoBanAllButton then
        local mode = settings.echoBanAllMode or "highestScore"
        echoBanAllButton._value = mode
        echoBanAllButton:SetText(mode == "random" and "Random" or "Highest Score")
    end
    RefreshPeak()
end

local function CommitFocusedBoxes()
end

------------------------------------------------------------------------
-- Scroll helpers
------------------------------------------------------------------------

local function UpdateScrollRange()
    if not scrollFrame or not scrollBar then return end
    local sfHeight = scrollFrame:GetHeight()
    local range = math.max(0, CONTENT_HEIGHT - sfHeight)
    scrollBar:SetMinMaxValues(0, range)
    if scrollBar:GetValue() > range then scrollBar:SetValue(range) end
end

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------

local function BuildViewFrame(parent)
    local f = CreateFrame("Frame", nil, parent)

    local header = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
    header:SetText("Automation")

    scrollFrame = CreateFrame("ScrollFrame", nil, f)
    scrollFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",     0, -28)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 10)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(520)
    scrollChild:SetHeight(CONTENT_HEIGHT)
    scrollFrame:SetScrollChild(scrollChild)

    scrollBar = CreateFrame("Slider", nil, scrollFrame, "UIPanelScrollBarTemplate")
    scrollBar:SetPoint("TOPLEFT",     scrollFrame, "TOPRIGHT",     -2, -4)
    scrollBar:SetPoint("BOTTOMLEFT",  scrollFrame, "BOTTOMRIGHT",  -2,  4)
    scrollBar:SetValueStep(20)
    scrollBar:SetValue(0)

    scrollBar:SetScript("OnValueChanged", function(self, value)
        scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, value)
    end)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current  = scrollBar:GetValue()
        local min, max = scrollBar:GetMinMaxValues()
        scrollBar:SetValue(math.max(min, math.min(max, current - delta * 20)))
    end)

    scrollFrame:SetScript("OnSizeChanged", UpdateScrollRange)

    BuildBanishWhitelistSection (scrollChild, 10,  -5)
    BuildEchoBanSection         (scrollChild, 10, -100)
    BuildPeakRow                (scrollChild, 10, -295)
    BuildThresholdsSection      (scrollChild, 10, -325)

    return f
end

local function EnsureBuilt(container)
    if viewFrame then return end
    viewFrame = BuildViewFrame(container)
end

function EbonBuilds.SettingsView.Mount(container)
    EnsureBuilt(container)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)
    RefreshInputs()
    viewFrame:Show()
    UpdateScrollRange()
    scrollBar:SetValue(0)
end

function EbonBuilds.SettingsView.Unmount()
    if not viewFrame then return end
    CommitFocusedBoxes()
    viewFrame:Hide()
end

function EbonBuilds.SettingsView.Init()
end
