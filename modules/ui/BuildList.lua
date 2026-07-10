-- EbonBuilds: modules/ui/BuildList.lua
-- Responsibility: full-width build picker (My Build selection screen).

EbonBuilds.BuildList = {}

local SW = EbonBuilds.SiteWidgets
local ST = EbonBuilds.SiteTheme
local C  = ST.C
local L  = ST.Layout

local PICKER_ROW_H   = 96
local CARD_MARGIN    = 6
local CLASS_ICON     = 32
local ECHO_ICON      = 24
local ECHO_STEP      = 26
local SCROLLBAR_W    = 10
local MAX_KEY_ECHOES = 10
local CLASS_COORDS   = CLASS_ICON_TCOORDS
local CLASS_TEXTURE  = "Interface\\TargetingFrame\\UI-Classes-Circles"

local container
local rowPool     = {}
local scrollFrame
local scrollChild
local scrollBar
local newBuildBtn
local importBtn
local publicBuildsBtn
local lastScrollBarShown

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function SetClassIcon(tex, classToken)
    local coords = classToken and CLASS_COORDS[classToken]
    if coords then
        tex:SetTexture(CLASS_TEXTURE)
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0, 1, 0, 1)
    end
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

local function NormalizeName(name)
    if not name then return "" end
    return name:lower()
end

local function BuildLockedNameSet(lockeds)
    local set = {}
    for _, spellId in ipairs(lockeds or {}) do
        if spellId then
            set[spellId] = true
            local name = GetSpellInfo(spellId)
            if name then set[NormalizeName(name)] = true end
            if EbonBuilds.Scoring and EbonBuilds.Scoring.ResolveEchoDisplayName then
                local display = EbonBuilds.Scoring.ResolveEchoDisplayName(spellId, name)
                if display then set[NormalizeName(display)] = true end
            end
        end
    end
    return set
end

local function GetKeyEchoes(build, maxCount)
    maxCount = maxCount or MAX_KEY_ECHOES
    local lockedSet = BuildLockedNameSet(build.lockedEchoes)
    local entries = EbonBuilds.Weights
        and EbonBuilds.Weights.CollectWeightedEchoes
        and EbonBuilds.Weights.CollectWeightedEchoes(build.echoWeights or {})
        or {}

    local result = {}
    for _, entry in ipairs(entries) do
        local norm = NormalizeName(entry.name)
        if not lockedSet[norm] then
            local spellId = EbonBuilds.EchoTableRows
                and EbonBuilds.EchoTableRows.ResolveSpellId
                and EbonBuilds.EchoTableRows.ResolveSpellId(entry.name)
            if spellId and not lockedSet[spellId] then
                result[#result + 1] = {
                    name = entry.name,
                    spellId = spellId,
                    weight = entry.baseWeight,
                }
                if #result >= maxCount then break end
            end
        end
    end
    return result
end

local function GetScrollChildWidth()
    if scrollFrame then
        local w = scrollFrame:GetWidth()
        if w and w > 0 then return w end
    end
    if container then
        local gutter = (scrollBar and scrollBar:IsShown()) and (SCROLLBAR_W + 4) or 0
        return math.max(1, container:GetWidth() - L.PAD - L.PAD - gutter)
    end
    return 400
end

local function SyncScrollInsets()
    if not scrollFrame or not container then return end
    local gutter = (scrollBar and scrollBar:IsShown()) and (SCROLLBAR_W + 4) or 0
    scrollFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -(L.PAD + gutter), L.PAD)
end

local function UpdateScrollRange()
    if not scrollFrame or not scrollChild or not scrollBar then return end
    scrollChild:SetWidth(GetScrollChildWidth())
    local needsBar = SW.UpdateVerticalScroll(scrollFrame, scrollChild, scrollBar)
    if lastScrollBarShown ~= needsBar then
        lastScrollBarShown = needsBar
        SyncScrollInsets()
        scrollChild:SetWidth(GetScrollChildWidth())
    end
    return needsBar
end

------------------------------------------------------------------------
-- Row factory
------------------------------------------------------------------------

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(PICKER_ROW_H)
    row:RegisterForClicks("LeftButtonUp")

    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
    stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
    stripe:SetWidth(4)
    row._stripe = stripe

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -2)
    bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 2)
    row._bg = bg

    local selected = row:CreateTexture(nil, "BACKGROUND")
    selected:SetAllPoints(row)
    selected:SetTexture(0.2, 0.5, 0.9, 0.18)
    selected:Hide()
    row._selected = selected

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -2)
    hl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -2, 2)
    hl:SetTexture(1, 1, 1, 0.08)
    hl:Hide()
    row:SetScript("OnEnter", function() hl:Show() end)
    row:SetScript("OnLeave", function() hl:Hide() end)

    local classBtn = CreateIconButton(row, CLASS_ICON)
    classBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 14, -12)
    row._classBtn = classBtn

    local titleLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleLabel:SetPoint("TOPLEFT", classBtn, "TOPRIGHT", 10, -2)
    titleLabel:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    titleLabel:SetJustifyH("LEFT")
    titleLabel:SetHeight(18)
    row._titleLabel = titleLabel

    local metaLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    metaLabel:SetPoint("TOPLEFT", titleLabel, "BOTTOMLEFT", 0, -2)
    metaLabel:SetPoint("RIGHT", row, "RIGHT", -14, 0)
    metaLabel:SetJustifyH("LEFT")
    metaLabel:SetHeight(14)
    row._metaLabel = metaLabel

    local specBtn = CreateIconButton(row, 16)
    specBtn:SetPoint("TOPLEFT", classBtn, "BOTTOMLEFT", 0, -4)
    row._specBtn = specBtn

    row._talentLabel = SW.Label(row, "", 12, C.text, false, "semibold")
    row._talentLabel:SetPoint("LEFT", specBtn, "RIGHT", 8, 0)
    row._talentLabel:SetPoint("BOTTOM", specBtn, "BOTTOM", 0, 1)

    row._lockedLabel = SW.Label(row, "LOCKED", 10, C.textMuted, false, "semibold")
    row._lockedLabel:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 58, 10)

    row._lockedBtns = {}
    local maxSlots = (EbonBuilds.Build and EbonBuilds.Build.MAX_LOCKED_SLOTS) or 6
    for i = 1, maxSlots do
        local btn = CreateIconButton(row, ECHO_ICON)
        btn:Hide()
        local border = btn:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT", btn, "TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
        border:SetTexture(ST.FLAT)
        border:SetVertexColor(unpack(C.accent))
        border:SetAlpha(0.55)
        btn._border = border
        row._lockedBtns[i] = btn
    end

    row._keyLabel = SW.Label(row, "KEY", 10, C.textMuted, false, "semibold")
    row._keyBtns = {}
    for i = 1, MAX_KEY_ECHOES do
        local btn = CreateIconButton(row, ECHO_ICON)
        btn:Hide()
        row._keyBtns[i] = btn
    end

    return row
end

local function WireNavigate(btn, build)
    btn:SetScript("OnClick", function()
        EbonBuilds.Build.SetActive(build.id)
        EbonBuilds.ViewRouter.Show("buildOverview", { build = build })
    end)
end

local function WireEchoTooltip(btn, spellId, extraLine)
    btn:SetScript("OnEnter", function(self)
        if not self._spellId then return end
        local spellName = GetSpellInfo(self._spellId)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if spellName then
            GameTooltip:AddLine(spellName, 1, 0.82, 0)
        end
        if extraLine then
            GameTooltip:AddLine(extraLine, 0.75, 0.75, 0.75)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function LayoutEchoButtons(row, lockedStartX, keyStartX)
    local slotCount = (EbonBuilds.Build and EbonBuilds.Build.GetLockedSlotCount
        and EbonBuilds.Build.GetLockedSlotCount()) or 5
    local x = lockedStartX
    for i = 1, #row._lockedBtns do
        local btn = row._lockedBtns[i]
        btn:ClearAllPoints()
        if i <= slotCount and btn._spellId then
            btn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 8)
            btn:Show()
            x = x + ECHO_STEP
        else
            btn:Hide()
        end
    end

    x = keyStartX
    for i = 1, #row._keyBtns do
        local btn = row._keyBtns[i]
        btn:ClearAllPoints()
        if btn._spellId then
            btn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 8)
            btn:Show()
            x = x + ECHO_STEP
        else
            btn:Hide()
        end
    end
end

local function PopulateRow(row, build, activeId, yOffset)
    local isActive = (build.id == activeId)
    local classToken = build.class
    local cc = ST.CLASS_COLORS[classToken] or { 0.5, 0.5, 0.5 }

    row:ClearAllPoints()
    row:SetPoint("LEFT", scrollChild, "LEFT", 0, 0)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    row:SetPoint("TOP", scrollChild, "TOP", 0, -yOffset)
    row:SetHeight(PICKER_ROW_H)

    if isActive then
        row._stripe:SetWidth(6)
        row._stripe:SetTexture(cc[1], cc[2], cc[3], 1.0)
        row._bg:SetTexture(cc[1], cc[2], cc[3], 0.12)
        row._selected:Show()
    else
        row._stripe:SetWidth(4)
        row._stripe:SetTexture(cc[1], cc[2], cc[3], 0.6)
        row._bg:SetTexture(cc[1], cc[2], cc[3], 0.06)
        row._selected:Hide()
    end

    SetClassIcon(row._classBtn._icon, classToken)
    row._classBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(classToken or "Unknown", 1, 1, 1)
        GameTooltip:Show()
    end)
    row._classBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    WireNavigate(row._classBtn, build)

    row._titleLabel:SetText(build.title or "Untitled")
    row._titleLabel:SetTextColor(cc[1], cc[2], cc[3], 1)

    local specName = ""
    local specIdx = ST.SpecIndex(classToken, build.spec or 1)
    local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[classToken]
    local specEntry = specs and specs[specIdx]
    if specEntry then
        specName = specEntry.name
        row._specBtn._icon:SetTexture(specEntry.icon)
        row._specBtn:Show()
        row._specBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(specEntry.name, 1, 1, 1)
            GameTooltip:Show()
        end)
        row._specBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        WireNavigate(row._specBtn, build)
    else
        row._specBtn:Hide()
    end

    local author = build.author or UnitName("player") or "Unknown"
    local modified = build.lastModified or ""
    if EbonBuilds.Build.EnsureTalentSnapshot then
        EbonBuilds.Build.EnsureTalentSnapshot(build)
    end
    local talentDist = EbonBuilds.Build.FormatTalentDistribution(build)
    local specPart = specName ~= "" and specName or "No spec"
    row._metaLabel:SetText(string.format("%s · by %s · %s", specPart, author, modified))
    if talentDist and row._talentLabel then
        row._talentLabel:SetText(talentDist)
        row._talentLabel:SetTextColor(cc[1], cc[2], cc[3], 1)
        row._talentLabel:Show()
    elseif row._talentLabel then
        row._talentLabel:Hide()
    end

    local lockeds = build.lockedEchoes
    local slotCount = (EbonBuilds.Build and EbonBuilds.Build.GetLockedSlotCount and EbonBuilds.Build.GetLockedSlotCount()) or 5
    local lockedShown = 0
    for i = 1, #row._lockedBtns do
        local btn = row._lockedBtns[i]
        local spellId = (i <= slotCount) and lockeds and lockeds[i] or nil
        btn._spellId = spellId
        if spellId then
            btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
            lockedShown = lockedShown + 1
            WireEchoTooltip(btn, spellId, "Locked echo")
            WireNavigate(btn, build)
        else
            btn:Hide()
        end
    end

    local lockedLabelW = 40
    local lockedStartX = 58
    local keyLabelX = 58
    if lockedShown > 0 then
        row._lockedLabel:Show()
        lockedLabelW = row._lockedLabel:GetStringWidth() or 40
        lockedStartX = 58 + lockedLabelW + 6
        keyLabelX = lockedStartX + lockedShown * ECHO_STEP + 12
    else
        row._lockedLabel:Hide()
    end

    row._keyLabel:ClearAllPoints()
    row._keyLabel:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", keyLabelX, 10)
    local keyLabelW = row._keyLabel:GetStringWidth() or 24
    local keyStartX = keyLabelX + keyLabelW + 6
    local rowW = GetScrollChildWidth()
    local maxKey = math.floor((rowW - keyStartX - 8) / ECHO_STEP)
    maxKey = math.max(0, math.min(maxKey, MAX_KEY_ECHOES))

    local keyEchoes = GetKeyEchoes(build, maxKey)
    if #keyEchoes == 0 then
        row._keyLabel:Hide()
    else
        row._keyLabel:Show()
    end

    for i = 1, #row._keyBtns do
        local btn = row._keyBtns[i]
        local entry = keyEchoes[i]
        if entry then
            btn._spellId = entry.spellId
            btn._icon:SetTexture(select(3, GetSpellInfo(entry.spellId)))
            WireEchoTooltip(btn, entry.spellId, string.format("Weight %d", entry.weight or 0))
            WireNavigate(btn, build)
        else
            btn._spellId = nil
            btn:Hide()
        end
    end

    LayoutEchoButtons(row, lockedStartX, keyStartX)

    WireNavigate(row, build)
    row:Show()
end

------------------------------------------------------------------------
-- Render
------------------------------------------------------------------------

local function Render()
    local builds   = EbonBuilds.Build.List()
    local activeId = EbonBuildsCharDB.activeBuildId
    local yOffset = 0
    for i = 1, #builds do
        if not rowPool[i] then rowPool[i] = CreateRow(scrollChild) end
        PopulateRow(rowPool[i], builds[i], activeId, yOffset)
        yOffset = yOffset + PICKER_ROW_H + CARD_MARGIN
    end
    for i = #builds + 1, #rowPool do rowPool[i]:Hide() end

    scrollChild:SetHeight(math.max(1, yOffset))
    UpdateScrollRange()
end

EbonBuilds.BuildList.Refresh = Render

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------

local function CreatePublicBuildsButton(parent)
    local btn = SW.CreateOutlineButton(parent, "Public Builds", 0)
    btn:SetHeight(28)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", L.PAD, -L.PAD)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -L.PAD, -L.PAD)
    btn:SetScript("OnClick", function()
        EbonBuilds.ViewRouter.Show("publicBuilds")
    end)
    return btn
end

local function CreateImportButton(parent)
    local btn = SW.CreateOutlineButton(parent, "Import Build", 0)
    btn:SetHeight(28)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    btn:SetScript("OnClick", function()
        EbonBuilds.ExportImport.ShowImportDialog()
    end)
    return btn
end

local function CreateNewBuildButton(parent, topAnchor)
    local btn = SW.CreateAccentButton(parent, "+ New Build", function()
        EbonBuilds.ViewRouter.Show("buildWizard")
    end)
    btn:SetHeight(28)
    btn:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -6)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -L.PAD, 0)
    return btn
end

local function CreateScrollArea(parent, topAnchor)
    local sf = CreateFrame("ScrollFrame", "EbonBuildsBuildListSF", parent)
    sf:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -4)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -L.PAD, L.PAD)

    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(400)
    child:SetHeight(1)
    sf:SetScrollChild(child)

    local bar = CreateFrame("Slider", "EbonBuildsBuildListScrollBar", sf, "UIPanelScrollBarTemplate")
    bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", -SCROLLBAR_W, -4)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", -SCROLLBAR_W, 4)
    bar:SetValueStep(20)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:Hide()
    SW.StyleVerticalScrollBar(bar)

    bar:SetScript("OnValueChanged", function()
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, bar:GetValue())
    end)

    local wireWheel = EbonBuilds.ScrollWheel.Bind(bar, 40)
    wireWheel(sf)
    wireWheel(child)

    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, delta)
        if not bar:IsShown() then return end
        local v = bar:GetValue()
        local mn, mx = bar:GetMinMaxValues()
        bar:SetValue(math.max(mn, math.min(mx, v - delta * 40)))
    end)

    sf:SetScript("OnSizeChanged", function()
        Render()
    end)

    return sf, child, bar
end

function EbonBuilds.BuildList.Init(parent)
    container = parent
    publicBuildsBtn = CreatePublicBuildsButton(parent)
    importBtn = CreateImportButton(parent)
    newBuildBtn = CreateNewBuildButton(parent, importBtn)
    scrollFrame, scrollChild, scrollBar = CreateScrollArea(parent, newBuildBtn)

    importBtn:SetPoint("TOPLEFT", publicBuildsBtn, "BOTTOMLEFT", 0, -6)
    importBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -L.PAD, 0)

    parent:SetScript("OnSizeChanged", function()
        Render()
    end)

    Render()

    if EbonBuilds.Build and EbonBuilds.Build.OnActiveChanged then
        EbonBuilds.Build.OnActiveChanged(Render)
    end
end
