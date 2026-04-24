-- EbonBuilds: modules/ui/BuildList.lua
-- Responsibility: render the left-column list of builds plus a "+ New Build"
-- button. Clicking a row activates that build and opens the weights view.

EbonBuilds.BuildList = {}

local ROW_HEIGHT     = 32
local CLASS_COORDS   = CLASS_ICON_TCOORDS
local CLASS_TEXTURE  = "Interface\\TargetingFrame\\UI-Classes-Circles"

local container
local rowPool     = {}
local scrollFrame
local scrollChild
local newBuildBtn

------------------------------------------------------------------------
-- Row factory
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

local function CreateRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT",  parent, "LEFT",  0, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(row)
    highlight:SetTexture(1, 1, 1, 0.1)

    local active = row:CreateTexture(nil, "BACKGROUND")
    active:SetAllPoints(row)
    active:SetTexture(0.2, 0.4, 0.8, 0.25)
    active:Hide()
    row._active = active

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(24)
    icon:SetHeight(24)
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row._icon = icon

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT",  icon, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", row,  "RIGHT", -4, 0)
    label:SetJustifyH("LEFT")
    row._label = label

    return row
end

local function PopulateRow(row, index, build, activeId)
    row:ClearAllPoints()
    row:SetPoint("LEFT",  scrollChild, "LEFT",  0, 0)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    row:SetPoint("TOP",   scrollChild, "TOP",   0, -(index - 1) * ROW_HEIGHT)
    SetClassIcon(row._icon, build.class)
    row._label:SetText(build.title or "Untitled")
    if build.id == activeId then row._active:Show() else row._active:Hide() end
    row:SetScript("OnClick", function()
        EbonBuilds.Build.SetActive(build.id)
        EbonBuilds.ViewRouter.Show("weights")
    end)
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
    scrollChild:SetHeight(math.max(1, #builds * ROW_HEIGHT))
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
        EbonBuilds.ViewRouter.Show("buildForm", { mode = "create" })
    end)
    return btn
end

local function CreateScrollArea(parent, topAnchor)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     topAnchor, "BOTTOMLEFT",  0, -6)
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

    scrollChild:SetWidth(parent:GetWidth() - 22)
    parent:SetScript("OnSizeChanged", function()
        scrollChild:SetWidth(parent:GetWidth() - 22)
    end)

    Render()

    if EbonBuilds.Build and EbonBuilds.Build.OnActiveChanged then
        EbonBuilds.Build.OnActiveChanged(Render)
    end
end
