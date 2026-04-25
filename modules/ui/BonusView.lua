-- EbonBuilds: modules/ui/BonusView.lua
-- Responsibility: render the Bonus tab (quality and family bonuses).
-- Exposes Mount/Unmount. Reads and writes into BuildForm state.settings
-- so unsaved edits persist across tabs.
-- Layout-heavy/declarative: template-file exception applies.

EbonBuilds.BonusView = {}

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

local viewFrame
local scrollFrame, scrollChild, scrollBar
local qualityBoxes     = {}
local qualityModeToggles = {}
local familyBoxes      = {}
local familyModeToggles = {}
local noveltyBox, noveltyModeToggle

local CONTENT_HEIGHT = 400

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

local function CreateNumberEditBox(parent, width, height, allowNegative, allowDecimal)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width, height)
    c:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    c:SetBackdropColor(0, 0, 0, 0.6)
    c:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local box = CreateFrame("EditBox", nil, c)
    box:SetPoint("TOPLEFT",     c, "TOPLEFT",     4, -4)
    box:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -4, 4)
    box:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    box:SetTextColor(1, 1, 1, 1)
    box:SetJustifyH("CENTER")
    box:SetAutoFocus(false)
    box:SetMaxLetters(6)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnChar", function(self, char)
        local valid = (char >= "0" and char <= "9")
        if allowDecimal and char == "." then
            local text = self:GetText()
            if not text:find("%.") then valid = true end
        end
        if allowNegative and char == "-" then
            if self:GetCursorPosition() == 0 then valid = true end
        end
        if not valid then
            local pos  = self:GetCursorPosition()
            local text = self:GetText()
            self:SetText(string.sub(text, 1, pos) .. string.sub(text, pos + 2))
            self:SetCursorPosition(pos)
        end
    end)
    return box
end

------------------------------------------------------------------------
-- Quality bonus section
------------------------------------------------------------------------

local function CommitQualityBox(box)
    local settings = EbonBuilds.BuildForm.GetEditingSettings()
    local num = tonumber(box:GetText())
    if num then
        settings.qualityBonus[box.qIndex] = num
    end
    box:SetText(tostring(settings.qualityBonus[box.qIndex] or 0))
end

local function BuildQualityBonusSection(parent, x, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    header:SetText("Quality Bonus:")

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    hint:SetText("Use + to add the value, |cff19ff19x|r to multiply. Below 1 in |cff19ff19x|r mode reduces the score.")

    for q = 0, 4 do
        local cx = x + q * 80

        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        local info = QUALITY_LABELS[q]
        lbl:SetText("|cff" .. info.color .. info.name .. "|r")
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", cx, y - 38)
        lbl:SetWidth(70)
        lbl:SetJustifyH("CENTER")

        local box = CreateNumberEditBox(parent, 38, 22, true, true)
        box:GetParent():SetPoint("TOPLEFT", parent, "TOPLEFT", cx + 5, y - 54)
        box.qIndex = q
        box:SetScript("OnEnterPressed",    function(self) CommitQualityBox(self); self:ClearFocus() end)
        box:SetScript("OnEditFocusLost",   function(self) CommitQualityBox(self) end)
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        qualityBoxes[q] = box

        local toggle = CreateModeToggle(parent, cx + 45, y - 54)
        toggle.onToggle = function()
            local s = EbonBuilds.BuildForm.GetEditingSettings()
            s.qualityBonusMode[q] = toggle.multiplicative
        end
        qualityModeToggles[q] = toggle
    end
end

------------------------------------------------------------------------
-- Family bonus section
------------------------------------------------------------------------

local FAMILY_ROW1 = { "Tank", "Survivability", "Healer", "Caster" }
local FAMILY_ROW2 = { "Melee", "Ranged", "No family" }

local function CommitFamilyBox(box)
    local settings = EbonBuilds.BuildForm.GetEditingSettings()
    local num = tonumber(box:GetText())
    if num then
        settings.familyBonus[box.famKey] = num
    end
    box:SetText(tostring(settings.familyBonus[box.famKey] or 0))
end

local function BuildFamilyBonusSection(parent, x, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    header:SetText("Family Bonus:")

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    hint:SetText("Use + to add the value, |cff19ff19x|r to multiply. Below 1 in |cff19ff19x|r mode reduces the score.")

    for i, fam in ipairs(FAMILY_ROW1) do
        local cx = x + (i - 1) * 100

        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetText(fam)
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", cx, y - 38)
        lbl:SetWidth(55)
        lbl:SetJustifyH("CENTER")

        local box = CreateNumberEditBox(parent, 38, 22, true, true)
        box:GetParent():SetPoint("TOPLEFT", parent, "TOPLEFT", cx + 5, y - 54)
        box.famKey = fam
        box:SetScript("OnEnterPressed",    function(self) CommitFamilyBox(self); self:ClearFocus() end)
        box:SetScript("OnEditFocusLost",   function(self) CommitFamilyBox(self) end)
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        familyBoxes[fam] = box

        local toggle = CreateModeToggle(parent, cx + 45, y - 54)
        toggle.onToggle = function()
            local s = EbonBuilds.BuildForm.GetEditingSettings()
            s.familyBonusMode[fam] = toggle.multiplicative
        end
        familyModeToggles[fam] = toggle
    end

    for i, fam in ipairs(FAMILY_ROW2) do
        local cx = x + (i - 1) * 100

        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetText(fam)
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", cx, y - 84)
        lbl:SetWidth(55)
        lbl:SetJustifyH("CENTER")

        local box = CreateNumberEditBox(parent, 38, 22, true, true)
        box:GetParent():SetPoint("TOPLEFT", parent, "TOPLEFT", cx + 5, y - 100)
        box.famKey = fam
        box:SetScript("OnEnterPressed",    function(self) CommitFamilyBox(self); self:ClearFocus() end)
        box:SetScript("OnEditFocusLost",   function(self) CommitFamilyBox(self) end)
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        familyBoxes[fam] = box

        local toggle = CreateModeToggle(parent, cx + 45, y - 100)
        toggle.onToggle = function()
            local s = EbonBuilds.BuildForm.GetEditingSettings()
            s.familyBonusMode[fam] = toggle.multiplicative
        end
        familyModeToggles[fam] = toggle
    end
end

------------------------------------------------------------------------
-- Novelty bonus section
------------------------------------------------------------------------

local function CommitNoveltyBox()
    local settings = EbonBuilds.BuildForm.GetEditingSettings()
    local num = tonumber(noveltyBox:GetText())
    if num then
        settings.noveltyValue = num
    end
    noveltyBox:SetText(tostring(settings.noveltyValue or 0))
end

local function BuildNoveltyBonusSection(parent, x, y)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    header:SetText("Novelty Bonus:")

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    hint:SetText("Unique echoes (seen for the first time) gain this bonus.")

    local valLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valLabel:SetText("Value:")
    valLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 32)

    noveltyBox = CreateNumberEditBox(parent, 50, 22, true, true)
    noveltyBox:GetParent():SetPoint("TOPLEFT", parent, "TOPLEFT", x + 40, y - 34)
    noveltyBox:SetScript("OnEnterPressed",    function(self) CommitNoveltyBox(); self:ClearFocus() end)
    noveltyBox:SetScript("OnEditFocusLost",   function(self) CommitNoveltyBox() end)
    noveltyBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    noveltyModeToggle = CreateModeToggle(parent, x + 95, y - 32)
    noveltyModeToggle.onToggle = function()
        local s = EbonBuilds.BuildForm.GetEditingSettings()
        s.noveltyMode = noveltyModeToggle.multiplicative
    end
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------

local function RefreshInputs()
    local settings = EbonBuilds.BuildForm.GetEditingSettings()
    for q = 0, 4 do
        qualityBoxes[q]:SetText(tostring(settings.qualityBonus[q] or 0))
        local toggle = qualityModeToggles[q]
        if toggle then
            toggle.multiplicative = settings.qualityBonusMode[q] or false
            toggle.modeLabel:SetText(toggle.multiplicative and "|cff19ff19x|r" or "+")
        end
    end
    for _, fam in ipairs(FAMILY_ORDER) do
        familyBoxes[fam]:SetText(tostring(settings.familyBonus[fam] or 0))
        local toggle = familyModeToggles[fam]
        if toggle then
            toggle.multiplicative = settings.familyBonusMode[fam] or false
            toggle.modeLabel:SetText(toggle.multiplicative and "|cff19ff19x|r" or "+")
        end
    end
    if noveltyBox then
        noveltyBox:SetText(tostring(settings.noveltyValue or 0))
    end
    if noveltyModeToggle then
        noveltyModeToggle.multiplicative = settings.noveltyMode or false
        noveltyModeToggle.modeLabel:SetText(noveltyModeToggle.multiplicative and "|cff19ff19x|r" or "+")
    end
end

local function CommitFocusedBoxes()
    for _, box in pairs(qualityBoxes) do if box:HasFocus() then CommitQualityBox(box) end end
    for _, box in pairs(familyBoxes)  do if box:HasFocus() then CommitFamilyBox(box)  end end
    if noveltyBox and noveltyBox:HasFocus() then CommitNoveltyBox() end
end

------------------------------------------------------------------------
-- Scroll
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
    header:SetText("Bonus")

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

    BuildQualityBonusSection(scrollChild, 10,  -5)
    BuildFamilyBonusSection (scrollChild, 10, -90)
    BuildNoveltyBonusSection(scrollChild, 10, -215)

    return f
end

local function EnsureBuilt(container)
    if viewFrame then return end
    viewFrame = BuildViewFrame(container)
end

function EbonBuilds.BonusView.Mount(container)
    EnsureBuilt(container)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)
    RefreshInputs()
    viewFrame:Show()
    UpdateScrollRange()
    scrollBar:SetValue(0)
end

function EbonBuilds.BonusView.Unmount()
    if not viewFrame then return end
    CommitFocusedBoxes()
    viewFrame:Hide()
end

function EbonBuilds.BonusView.Init()
end
