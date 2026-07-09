-- EbonBuilds: modules/ui/EchoTable.lua
-- Responsibility: scroll frame, scroll bar, headers, and row pool management.
-- Row frame creation and data preparation are handled by EchoTableRows.lua.

EbonBuilds.EchoTable = {}

local C = EbonBuilds.EchoTableColumns
local PADDING       = 10
local TITLE_HEIGHT  = 30
local HEADER_HEIGHT = 24
local ROW_HEIGHT    = 32
local FILTER_BAR_OFFSET = 58

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
-- rowPool is split into two sub-pools keyed by row type.
local headerPool   = {}  -- header row frames
local subPool      = {}  -- sub-row frames
local singlePool   = {}  -- single-rarity row frames
local scrollFrame, scrollChild, scrollBar
local wireScrollWheel
local headerBtns = {}

local sortMode = "name"
local sortDescending = false

local SORT_COLUMNS = { "name", "score", "policy", "weight" }

local function GetEntryWeight(entry)
    if entry.isSubRow and entry.qualityTier ~= nil then
        return EbonBuilds.Weights.GetForQuality(entry.name, entry.qualityTier) or 0
    end
    return EbonBuilds.Weights.Get(entry.name) or 0
end

local function CompareHeaders(a, b)
    local cmp = 0
    if sortMode == "weight" then
        local wa = GetEntryWeight(a)
        local wb = GetEntryWeight(b)
        if wa ~= wb then cmp = wa < wb and -1 or 1 end
    elseif sortMode == "score" then
        local sa = EbonBuilds.EchoTableRows.GetSortScore(a)
        local sb = EbonBuilds.EchoTableRows.GetSortScore(b)
        if sa ~= sb then cmp = sa < sb and -1 or 1 end
    elseif sortMode == "policy" then
        local pa = EbonBuilds.EchoTableRows.GetPolicyOrdinal(a.name)
        local pb = EbonBuilds.EchoTableRows.GetPolicyOrdinal(b.name)
        if pa ~= pb then cmp = pa < pb and -1 or 1 end
    else
        if a.name ~= b.name then cmp = a.name < b.name and -1 or 1 end
    end
    if cmp == 0 then
        cmp = a.name < b.name and -1 or (a.name > b.name and 1 or 0)
    end
    if sortDescending then cmp = -cmp end
    return cmp < 0
end

-- Sort only operates on group-header rows; sub-rows follow their parent.
-- We rebuild a sorted flat list by: sort headers, then re-attach their sub-rows.
local function SortList(list)
    -- Separate headers and sub-rows.
    local headers = {}
    local subsByName = {}
    for i = 1, #list do
        local e = list[i]
        if e.isGroupHeader or e.isSingleRow then
            headers[#headers + 1] = e
        elseif e.isSubRow then
            local t = subsByName[e.name]
            if not t then t = {}; subsByName[e.name] = t end
            t[#t + 1] = e
        end
    end
    -- Sort headers.
    table.sort(headers, CompareHeaders)
    -- Rebuild flat list: header/single row then its sub-rows in quality order.
    local out = {}
    for i = 1, #headers do
        local h = headers[i]
        out[#out + 1] = h
        if h.isGroupHeader then
            local subs = subsByName[h.name]
            if subs then
                for j = 1, #subs do out[#out + 1] = subs[j] end
            end
        end
    end
    return out
end

local function UpdateHeaderLabels()
    local labels = {
        name   = "Name",
        score  = "Score",
        policy = "Policy",
        weight = "Weight",
    }
    local arrow = sortDescending and " v" or " ^"
    for col, btn in pairs(headerBtns) do
        if btn and btn.text then
            if col == sortMode then
                btn.text:SetText("|cffffd100" .. labels[col] .. arrow .. "|r")
            else
                btn.text:SetText(labels[col] or col)
            end
        end
    end
end

-- Forward declarations (must precede OnHeaderClick).
local UpdateScrollRange, RefreshRows, RebuildFilteredList

local function OnHeaderClick(col)
    if sortMode == col then
        sortDescending = not sortDescending
    else
        sortMode = col
        sortDescending = (col == "score" or col == "weight")
    end
    UpdateHeaderLabels()
    RebuildFilteredList(true)
end

------------------------------------------------------------------------
-- Helpers for variable-height rows
------------------------------------------------------------------------

local function EntryHeight(entry)
    return EbonBuilds.EchoTableRows.GetRowHeight(entry)
end

-- Total pixel height of the filtered list.
local function TotalListHeight()
    local h = 0
    for i = 1, #filteredList do
        h = h + EntryHeight(filteredList[i])
    end
    return h
end

-- Build a cumulative offset table so we can binary-search for the first
-- visible entry given a pixel scroll offset.
local yOffsets = {}  -- yOffsets[i] = pixel top of filteredList[i]

local function RebuildOffsets()
    local y = 0
    for i = 1, #filteredList do
        yOffsets[i] = y
        y = y + EntryHeight(filteredList[i])
    end
    yOffsets[#filteredList + 1] = y  -- sentinel
end

-- Return the index of the first entry whose top >= scrollY.
local function FirstVisibleIndex(scrollY)
    for i = 1, #filteredList do
        if yOffsets[i] + EntryHeight(filteredList[i]) > scrollY then
            return i
        end
    end
    return #filteredList
end

------------------------------------------------------------------------
-- Headers
------------------------------------------------------------------------

local function MakeHeaderBtn(parent, width, text, col, justify)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, 18)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if justify == "RIGHT" then
        label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
        label:SetJustifyH("RIGHT")
    elseif justify == "CENTER" then
        label:SetPoint("CENTER", btn, "CENTER", 0, 0)
        label:SetJustifyH("CENTER")
    else
        label:SetPoint("LEFT", btn, "LEFT", 0, 0)
        label:SetJustifyH("LEFT")
    end
    label:SetText(text)
    label:SetTextColor(0.6, 0.6, 0.6)
    btn.text = label
    btn._col = col
    btn:SetScript("OnClick", function() OnHeaderClick(col) end)
    btn:SetScript("OnEnter", function(self)
        if sortMode ~= col then self.text:SetTextColor(1, 1, 1) end
    end)
    btn:SetScript("OnLeave", function(self)
        UpdateHeaderLabels()
    end)
    headerBtns[col] = btn
    return btn
end

local function CreateHeaders(parent, top)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, top)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(PADDING + 20), top)
    row:SetHeight(18)

    local gap = C.COL_GAP

    local weightBtn = MakeHeaderBtn(row, C.COL_WEIGHT, "Weight", "weight", "RIGHT")
    C.AnchorColumnRight(weightBtn, row, C.INSET_WEIGHT, C.COL_WEIGHT)

    local scoreBtn = MakeHeaderBtn(row, C.COL_SCORE, "Score", "score", "RIGHT")
    C.AnchorBoundedColumn(scoreBtn, row, C.INSET_SCORE, C.COL_SCORE)

    local policyBtn = MakeHeaderBtn(row, C.COL_POLICY, "Policy", "policy", "CENTER")
    C.AnchorBoundedColumn(policyBtn, row, C.INSET_POLICY, C.COL_POLICY)

    local tomeHdr = CreateFrame("Frame", nil, row)
    tomeHdr:SetSize(C.COL_TOME, 18)
    C.AnchorColumnRight(tomeHdr, row, C.INSET_TOME, C.COL_TOME)
    local tomeLabel = tomeHdr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tomeLabel:SetPoint("CENTER", tomeHdr, "CENTER", 0, 0)
    tomeLabel:SetText("Owned")
    tomeLabel:SetTextColor(0.6, 0.6, 0.6)
    tomeHdr:EnableMouse(true)
    tomeHdr:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Owned", 1, 0.82, 0)
        GameTooltip:AddLine("Checked when the echo is discovered on your account.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    tomeHdr:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local nameBtn = MakeHeaderBtn(row, 80, "Name", "name", "LEFT")
    nameBtn:ClearAllPoints()
    nameBtn:SetPoint("LEFT", row, "LEFT", C.GetNameLeft(), 0)
    nameBtn:SetPoint("RIGHT", tomeHdr, "LEFT", -gap, 0)
    nameBtn:SetHeight(18)

    UpdateHeaderLabels()
end

------------------------------------------------------------------------
-- Scroll rendering (variable-height rows)
------------------------------------------------------------------------

UpdateScrollRange = function()
    local totalH    = TotalListHeight()
    local viewH     = scrollFrame:GetHeight()
    local maxOffset = math.max(0, totalH - viewH)
    scrollBar:SetMinMaxValues(0, maxOffset)
    if scrollBar:GetValue() > maxOffset then scrollBar:SetValue(maxOffset) end
end

-- Hide all pooled rows that are currently shown.
local function HideAllPooled()
    for _, r in ipairs(headerPool) do if r:IsShown() then r:Hide() end end
    for _, r in ipairs(subPool)    do if r:IsShown() then r:Hide() end end
    for _, r in ipairs(singlePool) do if r:IsShown() then r:Hide() end end
end

RefreshRows = function()
    HideAllPooled()
    if #filteredList == 0 then return end

    local scrollY   = scrollBar:GetValue()
    local viewH     = scrollFrame:GetHeight()
    local startIdx  = FirstVisibleIndex(scrollY)

    local hIdx  = 0
    local sIdx  = 0
    local gIdx  = 0
    local i     = startIdx

    while i <= #filteredList do
        local entry   = filteredList[i]
        local entryH  = EntryHeight(entry)
        local yTop    = yOffsets[i] - scrollY
        if yTop > viewH + entryH then break end

        local rowType = EbonBuilds.EchoTableRows.GetRowType(entry)
        local row
        if rowType == "sub" then
            sIdx = sIdx + 1
            if not subPool[sIdx] then
                subPool[sIdx] = EbonBuilds.EchoTableRows.CreateRow(scrollChild, sIdx, "sub")
            end
            row = subPool[sIdx]
        elseif rowType == "single" then
            gIdx = gIdx + 1
            if not singlePool[gIdx] then
                singlePool[gIdx] = EbonBuilds.EchoTableRows.CreateRow(scrollChild, gIdx, "single")
            end
            row = singlePool[gIdx]
        else
            hIdx = hIdx + 1
            if not headerPool[hIdx] then
                headerPool[hIdx] = EbonBuilds.EchoTableRows.CreateRow(scrollChild, hIdx, "header")
            end
            row = headerPool[hIdx]
        end

        EbonBuilds.EchoTableRows.Populate(row, -yTop, entry)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  0, -yTop)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -yTop)
        row:Show()

        i = i + 1
    end
end

RebuildFilteredList = function(resetScroll)
    -- Apply class + addon filters (only to group-header rows; sub-rows follow).
    local raw = EbonBuilds.Filters.Apply(ApplyClassFilter(echoList))
    -- Re-attach sub-rows for echoes that passed the filter.
    local passedNames = {}
    for _, e in ipairs(raw) do
        if e.isGroupHeader or e.isSingleRow then passedNames[e.name] = true end
    end
    local full = {}
    for _, e in ipairs(echoList) do
        if passedNames[e.name] then full[#full + 1] = e end
    end
    filteredList = SortList(full)
    RebuildOffsets()
    UpdateScrollRange()
    if resetScroll and scrollBar then scrollBar:SetValue(0) end
    RefreshRows()
end

local function SyncChildWidth(sf, child)
    local w = sf:GetWidth()
    if w and w > 0 then child:SetWidth(w) end
end

------------------------------------------------------------------------
-- ScrollBar wiring
------------------------------------------------------------------------

local function WireScrollBar(sf, bar)
    EbonBuilds.ScrollWheel.SetupBar(bar)
    wireScrollWheel, _ = EbonBuilds.ScrollWheel.Bind(bar, ROW_HEIGHT)

    bar:SetScript("OnValueChanged", function()
        RefreshRows()
    end)

    wireScrollWheel(sf)
    wireScrollWheel(scrollChild)

    sf:EnableMouseWheel(true)
    sf:SetScript("OnSizeChanged", function()
        SyncChildWidth(sf, scrollChild)
        RebuildOffsets()
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
    EbonBuilds.ScrollWheel.SetupBar(bar)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
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

function EbonBuilds.EchoTable.Init(parent)
    echoList     = EbonBuilds.EchoTableRows.BuildSortedList()
    -- SortList handles the header/sub-row interleaving.
    echoList     = SortList(echoList)

    local rawFiltered = EbonBuilds.Filters.Apply(ApplyClassFilter(echoList))
    local passedNames = {}
    for _, e in ipairs(rawFiltered) do
        if e.isGroupHeader or e.isSingleRow then passedNames[e.name] = true end
    end
    local full = {}
    for _, e in ipairs(echoList) do
        if passedNames[e.name] then full[#full + 1] = e end
    end
    filteredList = full
    RebuildOffsets()

    EbonBuilds.EchoTableRows.SetOnWeightChanged(function()
        if EbonBuilds.Scoring and EbonBuilds.Scoring.ResetCache then
            EbonBuilds.Scoring.ResetCache()
        end
        if sortMode == "name" then
            RefreshRows()
            return
        end
        RebuildFilteredList(false)
    end)

    local top = -(TITLE_HEIGHT + PADDING) - FILTER_BAR_OFFSET

    CreateHeaders(parent, top)

    local sfTop = top - HEADER_HEIGHT
    scrollFrame, scrollChild = CreateScrollFrame(parent, PADDING, sfTop)

    scrollBar = CreateScrollBar(parent, scrollFrame)

    WireScrollBar(scrollFrame, scrollBar)

    EbonBuilds.EchoTableRows.SetScrollWheelForward(function(delta)
        EbonBuilds.ScrollWheel.Apply(scrollBar, delta, ROW_HEIGHT)
    end)

    scrollFrame:SetScript("OnShow", function()
        SyncChildWidth(scrollFrame, scrollChild)
        RebuildOffsets()
        UpdateScrollRange()
        RefreshRows()
    end)

    if EbonBuilds.Filters and EbonBuilds.Filters.OnChange then
        EbonBuilds.Filters.OnChange(function()
            RebuildFilteredList(true)
        end)
    end

    local function Rebuild()
        echoList = SortList(EbonBuilds.EchoTableRows.BuildSortedList())
        RebuildFilteredList(false)
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

function EbonBuilds.EchoTable.Refresh()
    if RefreshRows then
        RefreshRows()
    end
end
