-- EbonBuilds: modules/ui/EchoTable.lua
-- Responsibility: scroll frame, scroll bar, headers, and row pool management.
-- Row frame creation and data preparation are handled by EchoTableRows.lua.

EbonBuilds.EchoTable = {}

local PADDING      = 10
local TITLE_HEIGHT = 30
local HEADER_HEIGHT= 24
local ROW_HEIGHT   = 36
local COL_ICON     = 40
local COL_WEIGHT   = 80
local COL_SCORE    = 140

local CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

local function ApplyClassFilter(list)
    if EbonBuilds.Filters and EbonBuilds.Filters.ShowAllClasses and EbonBuilds.Filters.ShowAllClasses() then
        return list
    end
    local token
    if EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingClass then
        token = EbonBuilds.BuildForm.GetEditingClass()
    end
    if not token then
        local build = EbonBuilds.Build.GetActive()
        token = build and build.class
    end
    local bitVal = token and CLASS_BITS[token]
    if not bitVal then return list end
    local out = {}
    for i = 1, #list do
        local e = list[i]
        if not e.classMask or e.classMask == 0 or bit.band(e.classMask, bitVal) ~= 0 then
            out[#out + 1] = e
        end
    end
    return out
end

local echoList     = {}
local filteredList = {}
local rowPool      = {}
local scrollFrame, scrollChild, scrollBar

------------------------------------------------------------------------
-- Headers
------------------------------------------------------------------------

local function CreateHeaders(parent, top, left)
    local nameHdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameHdr:SetPoint("TOPLEFT", parent, "TOPLEFT", left + COL_ICON + 4, top)
    nameHdr:SetText("Name")

    local weightHdr = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    weightHdr:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(PADDING + 28), top)
    weightHdr:SetText("Weight")
end

------------------------------------------------------------------------
-- Scroll rendering
------------------------------------------------------------------------

local function GetVisibleCount()
    return math.ceil(scrollFrame:GetHeight() / ROW_HEIGHT) + 1
end

local function UpdateScrollRange()
    local visibleCount = GetVisibleCount()
    local maxOffset    = math.max(0, (#filteredList - visibleCount + 1) * ROW_HEIGHT)
    scrollBar:SetMinMaxValues(0, maxOffset)
    if scrollBar:GetValue() > maxOffset then scrollBar:SetValue(maxOffset) end
end

local function RefreshRows()
    local scrollOffset = math.floor(scrollBar:GetValue() / ROW_HEIGHT + 0.5)
    local visibleCount = GetVisibleCount()
    for poolIdx = 1, visibleCount do
        if not rowPool[poolIdx] then
            rowPool[poolIdx] = EbonBuilds.EchoTableRows.CreateRow(scrollChild, poolIdx)
        end
        local listIdx = scrollOffset + poolIdx
        local entry   = filteredList[listIdx]
        if entry then
            local yOffset = -(poolIdx - 1) * ROW_HEIGHT
            EbonBuilds.EchoTableRows.Populate(rowPool[poolIdx], yOffset, entry)
        else
            rowPool[poolIdx]:Hide()
        end
    end
end

local function SyncChildWidth(sf, child)
    local w = sf:GetWidth()
    if w and w > 0 then child:SetWidth(w) end
end

------------------------------------------------------------------------
-- ScrollBar wiring
------------------------------------------------------------------------

local function WireScrollBar(sf, bar)
    bar:SetScript("OnValueChanged", function(self, value)
        RefreshRows()
    end)

    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local current  = bar:GetValue()
        local min, max = bar:GetMinMaxValues()
        bar:SetValue(math.max(min, math.min(max, current - delta * ROW_HEIGHT)))
    end)

    sf:SetScript("OnSizeChanged", function()
        SyncChildWidth(sf, scrollChild)
        UpdateScrollRange()
        RefreshRows()
    end)
end

------------------------------------------------------------------------
-- Frame construction
------------------------------------------------------------------------

local function CreateScrollBar(parent, sf)
    local bar = CreateFrame("Slider", nil, sf, "UIPanelScrollBarTemplate")
    bar:SetPoint("TOPRIGHT",    sf, "TOPRIGHT",    18, -16)
    bar:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 18,  16)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(ROW_HEIGHT)
    bar:SetValue(0)
    return bar
end

local function CreateScrollFrame(parent, x, y)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetPoint("TOPLEFT",     parent, "TOPLEFT",     x,       y)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -x - 20, PADDING)

    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    return sf, child
end

------------------------------------------------------------------------
-- Public Init
------------------------------------------------------------------------

local FILTER_BAR_OFFSET = 34

function EbonBuilds.EchoTable.Init(parent)
    echoList     = EbonBuilds.EchoTableRows.BuildSortedList()
    filteredList = ApplyClassFilter(echoList)

    local left  = PADDING
    local top   = -(TITLE_HEIGHT + PADDING) - FILTER_BAR_OFFSET

    CreateHeaders(parent, top, left)

    local sfTop = top - HEADER_HEIGHT
    scrollFrame, scrollChild = CreateScrollFrame(parent, left, sfTop)

    scrollBar = CreateScrollBar(parent, scrollFrame)

    WireScrollBar(scrollFrame, scrollBar)

    scrollFrame:SetScript("OnShow", function()
        SyncChildWidth(scrollFrame, scrollChild)
        UpdateScrollRange()
        RefreshRows()
    end)

    if EbonBuilds.Filters and EbonBuilds.Filters.OnChange then
        EbonBuilds.Filters.OnChange(function()
            filteredList = EbonBuilds.Filters.Apply(ApplyClassFilter(echoList))
            UpdateScrollRange()
            scrollBar:SetValue(0)
            RefreshRows()
        end)
    end

    local function Rebuild()
        filteredList = EbonBuilds.Filters.Apply(ApplyClassFilter(echoList))
        UpdateScrollRange()
        RefreshRows()
    end

    if EbonBuilds.Build and EbonBuilds.Build.OnActiveChanged then
        EbonBuilds.Build.OnActiveChanged(Rebuild)
    end
    if EbonBuilds.BuildForm and EbonBuilds.BuildForm.OnClassChanged then
        EbonBuilds.BuildForm.OnClassChanged(Rebuild)
    end

    SyncChildWidth(scrollFrame, scrollChild)
    UpdateScrollRange()
    RefreshRows()
end
