-- EbonBuilds: modules/ui/Filters.lua
-- Responsibility: filter bar UI + filter state + list filtering.

EbonBuilds.Filters = {}

local SW = EbonBuilds.SiteWidgets

local FAMILIES = { "Tank", "Survivability", "Healer", "Caster DPS", "Melee DPS", "Ranged DPS", "No family" }
local QUALITY_LABELS = { "All", "Common", "Uncommon", "Rare", "Epic", "Legendary" }

local state = {
    text     = "",
    quality  = nil,
    families = {},
    sources  = {},
    showAllClasses = false,
    requiresTomeFilter = nil,  -- nil | "only" | "exclude"
    multipleRanksFilter = nil, -- nil | "only" | "exclude"
}
local changeCallbacks = {}
local searchEditBox = nil

local function Notify()
    for i = 1, #changeCallbacks do
        changeCallbacks[i]()
    end
end

function EbonBuilds.Filters.OnChange(fn)
    changeCallbacks[#changeCallbacks + 1] = fn
end

------------------------------------------------------------------------
-- Apply
------------------------------------------------------------------------

local function FamiliesActive()
    for _ in pairs(state.families) do return true end
    return false
end

local function MatchesFamilies(entry)
    if not next(state.families) then return true end
    local has = {}
    local hasAnyFamily = false
    for _, fam in ipairs(entry.families or {}) do
        has[fam] = true
        hasAnyFamily = true
    end
    for required in pairs(state.families) do
        if required == "No family" then
            if hasAnyFamily then return false end
        else
            if not has[required] then return false end
        end
    end
    return true
end

local TRI_STATE_CYCLE = { "off", "only", "exclude" }

local function EntryQualityCount(entry)
    if not entry or not entry.qualities then return 0 end
    return EbonBuilds.EchoTableRows.CountQualities
        and EbonBuilds.EchoTableRows.CountQualities(entry.qualities) or 0
end

function EbonBuilds.Filters.CycleTriStateFilter(mode)
    local current = mode or "off"
    for i, value in ipairs(TRI_STATE_CYCLE) do
        if value == current then
            local nextValue = TRI_STATE_CYCLE[(i % #TRI_STATE_CYCLE) + 1]
            return nextValue == "off" and nil or nextValue
        end
    end
    return nil
end

function EbonBuilds.Filters.PassesRequiresTomeFilter(entry, mode)
    if not mode then return true end
    if mode == "only" then return entry.requiresTome == true end
    if mode == "exclude" then return not entry.requiresTome end
    return true
end

function EbonBuilds.Filters.SyncRequiresTomeFilterUI(cb, label, mode)
    local box = cb and cb._checkbox
    if not box or not box.SetChecked then return end
    if mode == "only" then
        box:SetMarkColor({ 1.0, 0.82, 0.0 })
        box:SetChecked(true)
        if label then
            label:SetText("Requires Tome")
            label:SetTextColor(1.0, 0.82, 0.0)
        end
    elseif mode == "exclude" then
        box:SetMarkColor({ 1.0, 0.55, 0.2 })
        box:SetChecked(true)
        if label then
            label:SetText("Does Not Require Tome")
            label:SetTextColor(1.0, 0.55, 0.2)
        end
    else
        box:SetChecked(false)
        if label then
            label:SetText("Requires Tome")
            label:SetTextColor(0.8, 0.8, 0.8)
        end
    end
    if cb.SetChipWidth then cb:SetChipWidth() end
end

function EbonBuilds.Filters.PassesMultipleRanksFilter(entry, mode)
    if not mode then return true end
    local isMulti = EntryQualityCount(entry) >= 2
    if mode == "only" then return isMulti end
    if mode == "exclude" then return not isMulti end
    return true
end

function EbonBuilds.Filters.CycleMultipleRanksFilter(mode)
    return EbonBuilds.Filters.CycleTriStateFilter(mode)
end

function EbonBuilds.Filters.CycleRequiresTomeFilter(mode)
    return EbonBuilds.Filters.CycleTriStateFilter(mode)
end

function EbonBuilds.Filters.SyncMultiRankFilterUI(cb, label, mode)
    local box = cb and cb._checkbox
    if not box or not box.SetChecked then return end
    if mode == "only" then
        box:SetMarkColor({ 0.6, 0.8, 1.0 })
        box:SetChecked(true)
        if label then
            label:SetText("Multi-Rank")
            label:SetTextColor(0.6, 0.8, 1.0)
        end
    elseif mode == "exclude" then
        box:SetMarkColor({ 1.0, 0.55, 0.2 })
        box:SetChecked(true)
        if label then
            label:SetText("Exclude Multi-Rank")
            label:SetTextColor(1.0, 0.55, 0.2)
        end
    else
        box:SetChecked(false)
        if label then
            label:SetText("Multi-Rank")
            label:SetTextColor(0.8, 0.8, 0.8)
        end
    end
    if cb.SetChipWidth then cb:SetChipWidth() end
end

function EbonBuilds.Filters.SyncClassFilterUI(cb, label)
    local box = cb and cb._checkbox
    if not box or not box.SetChecked then return end
    if state.showAllClasses then
        box:SetMarkColor({ 0.6, 0.8, 1.0 })
        box:SetChecked(true)
        if label then
            label:SetText("Show All Classes")
            label:SetTextColor(0.6, 0.8, 1.0)
        end
    else
        box:SetChecked(false)
        if label then
            label:SetText("Show All Classes")
            label:SetTextColor(0.8, 0.8, 0.8)
        end
    end
    if cb.SetChipWidth then cb:SetChipWidth() end
end

local function PassesFilters(entry, famActive)
    if state.text ~= "" then
        if not entry.name:lower():find(state.text, 1, true) then return false end
    end
    if state.quality ~= nil then
        if not (entry.qualities and entry.qualities[state.quality]) then return false end
    end
    if famActive then
        if not MatchesFamilies(entry) then return false end
    end
    if not EbonBuilds.Filters.PassesRequiresTomeFilter(entry, state.requiresTomeFilter) then
        return false
    end
    if not EbonBuilds.Filters.PassesMultipleRanksFilter(entry, state.multipleRanksFilter) then
        return false
    end
    if EbonBuilds.EchoSources and next(state.sources) then
        if not EbonBuilds.EchoSources.PassesFilter(entry, state.sources) then
            return false
        end
    end
    return true
end

function EbonBuilds.Filters.Apply(echoList)
    local out = {}
    local famActive = FamiliesActive()
    for i = 1, #echoList do
        local entry = echoList[i]
        if PassesFilters(entry, famActive) then
            out[#out + 1] = entry
        end
    end
    return out
end

------------------------------------------------------------------------
-- UI helpers
------------------------------------------------------------------------

local function CreateSearchBox(bar)
    local container = CreateFrame("Frame", nil, bar)
    container:SetHeight(22)
    container:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    container:SetBackdropColor(0, 0, 0, 0.6)
    container:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local edit = CreateFrame("EditBox", nil, container)
    edit:SetHeight(18)
    edit:SetPoint("LEFT", container, "LEFT", 3, 0)
    edit:SetPoint("RIGHT", container, "RIGHT", -3, 0)
    edit:SetPoint("TOP", container, "TOP", 0, -2)
    edit:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    edit:SetTextColor(1, 1, 1, 1)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(60)
    edit:SetScript("OnTextChanged", function(self)
        state.text = self:GetText():lower()
        Notify()
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchEditBox = edit
    return container
end

function EbonBuilds.Filters.FocusSearch()
    if searchEditBox then searchEditBox:SetFocus() end
end

function EbonBuilds.Filters.ShowAllClasses()
    return state.showAllClasses
end

local function CreateQualityMenu(bar)
    local qualityMenu
    qualityMenu = SW.CreateSiteMenu(bar, {
        width = 80,
        menuWidth = 120,
        getLabel = function()
            if state.quality == nil then return "All" end
            return QUALITY_LABELS[state.quality + 2] or "All"
        end,
        buildRows = function()
            local rows = {}
            for index, name in ipairs(QUALITY_LABELS) do
                local q = index == 1 and nil or (index - 2)
                rows[#rows + 1] = {
                    text = name,
                    checked = state.quality == q,
                    onClick = function()
                        state.quality = q
                        qualityMenu:RefreshLabel()
                        Notify()
                    end,
                }
            end
            return rows
        end,
    })
    return qualityMenu
end

local function CreateFamilyMenu(bar)
    local familyMenu
    familyMenu = SW.CreateSiteMenu(bar, {
        width = 110,
        menuWidth = 180,
        keepOpen = true,
        getLabel = function()
            local count = 0
            for _ in pairs(state.families) do count = count + 1 end
            if count == 0 then return "All families" end
            return "Families (" .. count .. ")"
        end,
        buildRows = function()
            local rows = {}
            for _, family in ipairs(FAMILIES) do
                rows[#rows + 1] = {
                    text = family,
                    checked = state.families[family] and true or false,
                    onClick = function()
                        if state.families[family] then
                            state.families[family] = nil
                        else
                            state.families[family] = true
                        end
                        familyMenu:RefreshLabel()
                        Notify()
                    end,
                }
            end
            return rows
        end,
    })
    return familyMenu
end

local function CreateSourcesMenu(bar)
    local sourcesMenu
    sourcesMenu = SW.CreateSiteMenu(bar, {
        width = 120,
        menuWidth = 220,
        keepOpen = true,
        getLabel = function()
            if EbonBuilds.EchoSources then
                return EbonBuilds.EchoSources.FilterLabel(state.sources)
            end
            return "All sources"
        end,
        buildRows = function()
            if not EbonBuilds.EchoSources then return {} end
            return EbonBuilds.EchoSources.BuildFilterMenuRows(state.sources, function()
                sourcesMenu:RefreshLabel()
                Notify()
            end)
        end,
    })
    return sourcesMenu
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function EbonBuilds.Filters.Init(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT",  parent, "TOPLEFT",   10, -34)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -34)
    bar:SetHeight(56)

    local row1 = CreateFrame("Frame", nil, bar)
    row1:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    row1:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    row1:SetHeight(26)

    local row2 = CreateFrame("Frame", nil, bar)
    row2:SetPoint("TOPLEFT", row1, "BOTTOMLEFT", 0, -2)
    row2:SetPoint("TOPRIGHT", row1, "BOTTOMRIGHT", 0, -2)
    row2:SetHeight(28)

    local classChip, tomeChip, multiChip

    classChip = SW.CreateTriStateFilterChip(row2, "Show All Classes", function()
        state.showAllClasses = not state.showAllClasses
        EbonBuilds.Filters.SyncClassFilterUI(classChip, classChip._label)
        Notify()
    end, "Class Filter", function()
        if state.showAllClasses then
            GameTooltip:AddLine("Showing echoes for all classes.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("Showing echoes for your class only.", 0.8, 0.8, 0.8, true)
        end
    end, { "Show All Classes" })
    classChip:SetPoint("RIGHT", row2, "RIGHT", 0, 0)

    tomeChip = SW.CreateTriStateFilterChip(row2, "Requires Tome", function()
        state.requiresTomeFilter = EbonBuilds.Filters.CycleRequiresTomeFilter(state.requiresTomeFilter)
        EbonBuilds.Filters.SyncRequiresTomeFilterUI(tomeChip, tomeChip._label, state.requiresTomeFilter)
        Notify()
    end, "Requires Tome Filter", function()
        local mode = state.requiresTomeFilter
        if mode == "only" then
            GameTooltip:AddLine("Showing echoes that require a tome only.", 0.8, 0.8, 0.8, true)
        elseif mode == "exclude" then
            GameTooltip:AddLine("Showing echoes that do not require a tome only.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("No tome filter active.", 0.8, 0.8, 0.8, true)
        end
    end, { "Requires Tome", "Does Not Require Tome" })
    tomeChip:SetPoint("RIGHT", classChip, "LEFT", -12, 0)

    multiChip = SW.CreateTriStateFilterChip(row2, "Multi-Rank", function()
        state.multipleRanksFilter = EbonBuilds.Filters.CycleMultipleRanksFilter(state.multipleRanksFilter)
        EbonBuilds.Filters.SyncMultiRankFilterUI(multiChip, multiChip._label, state.multipleRanksFilter)
        Notify()
    end, "Multi-Rank Filter", function()
        local mode = state.multipleRanksFilter
        if mode == "only" then
            GameTooltip:AddLine("Showing multi-rank echoes only.", 0.8, 0.8, 0.8, true)
        elseif mode == "exclude" then
            GameTooltip:AddLine("Hiding multi-rank echoes.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("No multi-rank filter active.", 0.8, 0.8, 0.8, true)
        end
    end, { "Multi-Rank", "Exclude Multi-Rank" })
    multiChip:SetPoint("RIGHT", tomeChip, "LEFT", -12, 0)

    EbonBuilds.Filters.SyncClassFilterUI(classChip, classChip._label)
    EbonBuilds.Filters.SyncRequiresTomeFilterUI(tomeChip, tomeChip._label, state.requiresTomeFilter)
    EbonBuilds.Filters.SyncMultiRankFilterUI(multiChip, multiChip._label, state.multipleRanksFilter)

    local familyMenu = CreateFamilyMenu(row1)
    familyMenu:SetPoint("RIGHT", row1, "RIGHT", 0, 0)

    local sourcesMenu = CreateSourcesMenu(row1)
    sourcesMenu:SetPoint("RIGHT", familyMenu, "LEFT", 4, 0)

    local qualityMenu = CreateQualityMenu(row1)
    qualityMenu:SetPoint("RIGHT", sourcesMenu, "LEFT", 4, 0)

    local searchContainer = CreateSearchBox(row1)
    searchContainer:SetPoint("LEFT", row1, "LEFT", 0, 0)
    searchContainer:SetPoint("RIGHT", qualityMenu, "LEFT", -8, 0)

    return bar
end
