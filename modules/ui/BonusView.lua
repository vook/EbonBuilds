-- EbonBuilds: modules/ui/BonusView.lua
-- Responsibility: render the Bonus tab (quality and family bonuses).
-- Exposes Mount/Unmount. Reads and writes into BuildForm state.settings
-- so unsaved edits persist across tabs.
-- Layout-heavy/declarative: template-file exception applies.

EbonBuilds.BonusView = {}

local SW = EbonBuilds.SiteWidgets

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
local lastScrollBarShown
local qualityBoxes     = {}
local qualityModeToggles = {}
local familyBoxes      = {}
local familyModeToggles = {}
local noveltyBox, noveltyModeToggle

local CONTENT_HEIGHT = 275
local SCROLLBAR_W = 8

local function SyncScrollInsets()
    if not scrollFrame or not viewFrame then return end
    local gutter = (scrollBar and scrollBar:IsShown()) and (SCROLLBAR_W + 4) or 0
    scrollFrame:SetPoint("BOTTOMRIGHT", viewFrame, "BOTTOMRIGHT", -(gutter), 10)
end

local function CreateModeToggle(parent, x, y)
    return SW.CreateModeToggleButton(parent, { x = x, y = y })
end

local function CreateNumberEditBox(parent, width, height, allowNegative, allowDecimal)
    local _, edit = SW.CreateNumericEditBox(parent, {
        width = width,
        height = height,
        allowNegative = allowNegative,
        allowDecimal = allowDecimal,
        maxLetters = 6,
    })
    return edit
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
            toggle:SetMultiplicative(settings.qualityBonusMode[q])
        end
    end
    for _, fam in ipairs(FAMILY_ORDER) do
        familyBoxes[fam]:SetText(tostring(settings.familyBonus[fam] or 0))
        local toggle = familyModeToggles[fam]
        if toggle then
            toggle:SetMultiplicative(settings.familyBonusMode[fam])
        end
    end
    if noveltyBox then
        noveltyBox:SetText(tostring(settings.noveltyValue or 0))
    end
    if noveltyModeToggle then
        noveltyModeToggle:SetMultiplicative(settings.noveltyMode)
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
    if not scrollFrame or not scrollChild or not scrollBar then return end
    scrollChild:SetHeight(CONTENT_HEIGHT)
    local needsBar = SW.UpdateVerticalScroll(scrollFrame, scrollChild, scrollBar)
    if lastScrollBarShown ~= needsBar then
        lastScrollBarShown = needsBar
        SyncScrollInsets()
    end
    return needsBar
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
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 10)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(520)
    scrollChild:SetHeight(CONTENT_HEIGHT)
    scrollFrame:SetScrollChild(scrollChild)

    scrollBar = CreateFrame("Slider", nil, scrollFrame, "UIPanelScrollBarTemplate")
    scrollBar:SetPoint("TOPLEFT",     scrollFrame, "TOPRIGHT",     -SCROLLBAR_W, -4)
    scrollBar:SetPoint("BOTTOMLEFT",  scrollFrame, "BOTTOMRIGHT",  -SCROLLBAR_W,  4)
    scrollBar:SetValueStep(20)
    scrollBar:SetValue(0)
    scrollBar:Hide()

    scrollFrame:SetScript("OnSizeChanged", UpdateScrollRange)

    BuildQualityBonusSection(scrollChild, 10,  -5)
    BuildFamilyBonusSection (scrollChild, 10, -90)
    BuildNoveltyBonusSection(scrollChild, 10, -215)

    EbonBuilds.ScrollWheel.WireSliderScroll(scrollFrame, scrollChild, scrollBar, 20)
    if SW.StyleVerticalScrollBar then
        SW.StyleVerticalScrollBar(scrollBar)
    end
    scrollBar:SetScript("OnValueChanged", function()
        SW.UpdateVerticalScroll(scrollFrame, scrollChild, scrollBar)
    end)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        if not scrollBar:IsShown() then return end
        EbonBuilds.ScrollWheel.Apply(scrollBar, delta, 20)
    end)

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
    SW.ScheduleVerticalScroll(scrollFrame, scrollChild, scrollBar)
end

function EbonBuilds.BonusView.Unmount()
    if not viewFrame then return end
    CommitFocusedBoxes()
    viewFrame:Hide()
end

function EbonBuilds.BonusView.Init()
end
