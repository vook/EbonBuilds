-- EbonBuilds: modules/ui/BuildList.lua
-- Responsibility: render the left-column list of builds as class-colored cards
-- plus a "+ New Build" button. Clicking a card opens that build for editing.

EbonBuilds.BuildList = {}

local ROW_SINGLE   = 56
local ROW_DOUBLE   = 74
local CARD_MARGIN  = 3
local CLASS_COORDS = CLASS_ICON_TCOORDS
local CLASS_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"

local CLASS_COLORS = {
    WARRIOR     = { 0.78, 0.61, 0.43 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    ROGUE       = { 1.0,  0.96, 0.41 },
    PRIEST      = { 1.0,  1.0,  1.0  },
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN      = { 0.0,  0.44, 0.87 },
    MAGE        = { 0.41, 0.8,  0.94 },
    WARLOCK     = { 0.58, 0.51, 0.79 },
    DRUID       = { 1.0,  0.49, 0.04 },
}

local container
local rowPool     = {}
local scrollFrame
local scrollChild
local newBuildBtn
local titleMeasureFont

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

local TITLE_MAX_W = 136

local function NeedsTwoLines(text)
    if not text or text == "" then return false end
    titleMeasureFont:SetText(text)
    local w = titleMeasureFont:GetStringWidth() or 0
    return w > TITLE_MAX_W
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

------------------------------------------------------------------------
-- Row factory
------------------------------------------------------------------------

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetPoint("LEFT",  parent, "LEFT",  0, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:SetHeight(ROW_SINGLE)

    -- Left accent stripe
    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetPoint("TOPLEFT",      row, "TOPLEFT",      2, -2)
    stripe:SetPoint("BOTTOMLEFT",   row, "BOTTOMLEFT",   2,  2)
    stripe:SetWidth(4)
    row._stripe = stripe

    -- Class-colored background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT",      row, "TOPLEFT",      6, -2)
    bg:SetPoint("BOTTOMRIGHT",  row, "BOTTOMRIGHT", -2,  2)
    row._bg = bg

    -- Selected highlight
    local selected = row:CreateTexture(nil, "BACKGROUND")
    selected:SetAllPoints(row)
    selected:SetTexture(0.2, 0.5, 0.9, 0.18)
    selected:Hide()
    row._selected = selected

    -- Hover highlight
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT",      row, "TOPLEFT",      6, -2)
    hl:SetPoint("BOTTOMRIGHT",  row, "BOTTOMRIGHT", -2,  2)
    hl:SetTexture(1, 1, 1, 0.08)
    hl:Hide()
    row:SetScript("OnEnter", function() hl:Show() end)
    row:SetScript("OnLeave", function() hl:Hide() end)

    -- Class icon button (22x22, top-left)
    local classBtn = CreateIconButton(row, 22)
    classBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -6)
    row._classBtn = classBtn

    -- Title label
    local titleLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLabel:SetPoint("TOPLEFT",  classBtn, "TOPRIGHT",  6, -2)
    titleLabel:SetPoint("RIGHT",    row,      "RIGHT",    -8, 0)
    titleLabel:SetJustifyH("LEFT")
    titleLabel:SetHeight(0)
    row._titleLabel = titleLabel

    -- Spec icon button (14x14, bottom-left)
    local specBtn = CreateIconButton(row, 14)
    specBtn:SetPoint("TOPLEFT", classBtn, "BOTTOMLEFT", 0, -2)
    row._specBtn = specBtn

    -- Permanent echo icon buttons (22x22, bottom row)
    row._permBtns = {}
    for i = 1, 4 do
        local btn = CreateIconButton(row, 22)
        btn:Hide()
        row._permBtns[i] = btn
    end

    return row
end

local function WireNavigate(btn, build)
    btn:SetScript("OnClick", function()
        EbonBuilds.Build.SetActive(build.id)
        EbonBuilds.ViewRouter.Show("buildTabs", { mode = "edit", build = build })
    end)
end

local PERM_X_START = 32
local PERM_STEP    = 28

local function PopulateRow(row, index, build, activeId)
    local isActive = (build.id == activeId)
    local classToken = build.class
    local cc = CLASS_COLORS[classToken] or { 0.5, 0.5, 0.5 }

    local twoLines = NeedsTwoLines(build.title)
    local rowHeight = twoLines and ROW_DOUBLE or ROW_SINGLE
    row:SetHeight(rowHeight)

    row:ClearAllPoints()
    row:SetPoint("LEFT",  scrollChild, "LEFT",  0, 0)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    row:SetPoint("TOP",   scrollChild, "TOP",   0, -(index - 1) * (rowHeight + CARD_MARGIN))

    -- Stripe and background
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

    -- Class icon
    SetClassIcon(row._classBtn._icon, classToken)
    row._classBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(classToken or "Unknown", 1, 1, 1)
        GameTooltip:Show()
    end)
    row._classBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    WireNavigate(row._classBtn, build)

    -- Title (class-colored)
    local title = build.title or "Untitled"
    row._titleLabel:SetText(title)
    row._titleLabel:SetTextColor(cc[1], cc[2], cc[3], 1)

    -- Spec icon
    local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[classToken]
    local specEntry = specs and specs[build.spec or 1]
    if specEntry then
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

    -- Permanent echo icons
    local permanents = build.permanentEchoes
    for i = 1, 4 do
        local btn = row._permBtns[i]
        local spellId = permanents and permanents[i]
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", PERM_X_START + (i - 1) * PERM_STEP, 4)
        if spellId then
            btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
            btn._spellId = spellId
            btn:Show()

            btn:SetScript("OnEnter", function(self)
                local spellName = GetSpellInfo(self._spellId)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                if spellName then
                    GameTooltip:AddLine(spellName, 1, 0.82, 0)
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            WireNavigate(btn, build)
        else
            btn:Hide()
        end
    end

    WireNavigate(row, build)
    row:Show()
end

------------------------------------------------------------------------
-- Render
------------------------------------------------------------------------

local function Render()
    local builds   = EbonBuilds.Build.List()
    local activeId = EbonBuildsDB.activeBuildId
    for i = 1, #builds do
        if not rowPool[i] then rowPool[i] = CreateRow(scrollChild) end
        PopulateRow(rowPool[i], i, builds[i], activeId)
    end
    for i = #builds + 1, #rowPool do rowPool[i]:Hide() end

    local total = 0
    for i = 1, #builds do
        local h = NeedsTwoLines(builds[i].title) and ROW_DOUBLE or ROW_SINGLE
        total = total + h + CARD_MARGIN
    end
    scrollChild:SetHeight(math.max(1, total))
end

EbonBuilds.BuildList.Refresh = Render

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------

local function CreateNewBuildButton(parent)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetHeight(24)
    btn:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, 0)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    btn:SetText("+ New Build")
    btn:SetScript("OnClick", function()
        EbonBuilds.ViewRouter.Show("buildTabs", { mode = "create" })
    end)
    return btn
end

local function CreateScrollArea(parent, topAnchor)
    local sf = CreateFrame("ScrollFrame", "EbonBuildsBuildListSF", parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     topAnchor, "BOTTOMLEFT",  0, -4)
    sf:SetPoint("BOTTOMRIGHT", parent,    "BOTTOMRIGHT", -22, 0)

    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(1)
    child:SetHeight(1)
    sf:SetScrollChild(child)
    return sf, child
end

function EbonBuilds.BuildList.Init(parent)
    container    = parent
    newBuildBtn  = CreateNewBuildButton(parent)
    scrollFrame, scrollChild = CreateScrollArea(parent, newBuildBtn)

    titleMeasureFont = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleMeasureFont:Hide()

    scrollChild:SetWidth(parent:GetWidth() - 22)
    parent:SetScript("OnSizeChanged", function()
        scrollChild:SetWidth(parent:GetWidth() - 22)
        Render()
    end)

    Render()

    if EbonBuilds.Build and EbonBuilds.Build.OnActiveChanged then
        EbonBuilds.Build.OnActiveChanged(Render)
    end
end
