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
local POOL_SIZE    = 20

local echoList   = {}
local rowPool    = {}
local scrollFrame, scrollChild, scrollBar

------------------------------------------------------------------------
-- Headers
------------------------------------------------------------------------

local function CreateHeaders(parent, top, left, width)
    local function MakeHeader(text, x)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, top)
        fs:SetText(text)
    end
    MakeHeader("Icon",   left)
    MakeHeader("Name",   left + COL_ICON + 4)
    MakeHeader("Weight", left + width - COL_WEIGHT)
end

------------------------------------------------------------------------
-- Row pool
------------------------------------------------------------------------

local function BuildRowPool(parent)
    for i = 1, POOL_SIZE do
        rowPool[i] = EbonBuilds.EchoTableRows.CreateRow(parent, i)
    end
end

------------------------------------------------------------------------
-- Scroll rendering
------------------------------------------------------------------------

local function RefreshRows()
    local scrollOffset = math.floor(scrollBar:GetValue() / ROW_HEIGHT + 0.5)
    for poolIdx = 1, POOL_SIZE do
        local listIdx = scrollOffset + poolIdx
        local entry   = echoList[listIdx]
        if entry then
            local yOffset = -(poolIdx - 1) * ROW_HEIGHT
            EbonBuilds.EchoTableRows.Populate(rowPool[poolIdx], yOffset, entry)
        else
            rowPool[poolIdx]:Hide()
        end
    end
end

------------------------------------------------------------------------
-- ScrollBar wiring
------------------------------------------------------------------------

local function WireScrollBar(sf, bar)
    sf:SetScript("OnScrollRangeChanged", function(self, xRange, yRange)
        local maxVal = math.max(0, yRange)
        bar:SetMinMaxValues(0, maxVal)
        if bar:GetValue() > maxVal then bar:SetValue(maxVal) end
    end)

    bar:SetScript("OnValueChanged", function(self, value)
        sf:SetVerticalScroll(value)
        RefreshRows()
    end)

    sf:SetScript("OnMouseWheel", function(self, delta)
        bar:SetValue(bar:GetValue() - delta * ROW_HEIGHT)
    end)
end

------------------------------------------------------------------------
-- Frame construction
------------------------------------------------------------------------

local function CreateScrollBar(parent, sf)
    local bar = CreateFrame("Slider", nil, parent, "UIPanelScrollBarTemplate")
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
    child:SetWidth(sf:GetWidth() or (parent:GetWidth() - x * 2 - 20))
    child:SetHeight(#echoList * ROW_HEIGHT)
    sf:SetScrollChild(child)
    return sf, child
end

------------------------------------------------------------------------
-- Public Init
------------------------------------------------------------------------

function EbonBuilds.EchoTable.Init(parent)
    echoList = EbonBuilds.EchoTableRows.BuildSortedList()

    local left  = PADDING
    local top   = -(TITLE_HEIGHT + PADDING)
    local width = parent:GetWidth() - PADDING * 2

    CreateHeaders(parent, top, left, width)

    local sfTop = top - HEADER_HEIGHT
    scrollFrame, scrollChild = CreateScrollFrame(parent, left, sfTop)

    scrollBar = CreateScrollBar(parent, scrollFrame)

    BuildRowPool(scrollChild)
    WireScrollBar(scrollFrame, scrollBar)

    scrollFrame:SetScript("OnShow", function() RefreshRows() end)
    RefreshRows()
end
