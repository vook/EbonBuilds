-- EbonBuilds: modules/ui/BuildOverview.lua
-- Responsibility: build overview dashboard with tabs (Overview + Stats +
-- Logbook). Registered as "buildOverview" view. Shows build metadata,
-- permanent echoes, automation toggle, and runtime statistics.

EbonBuilds.BuildOverview = {}

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

local QUALITY_BORDER_COLORS = {
    [0] = { 1.0, 1.0, 1.0 },
    [1] = { 30/255, 1.0, 0.0 },
    [2] = { 0.0, 112/255, 221/255 },
    [3] = { 163/255, 53/255, 238/255 },
    [4] = { 1.0, 128/255, 0.0 },
}

local QUALITY_LABELS = {
    [0] = "Common", [1] = "Uncommon", [2] = "Rare", [3] = "Epic", [4] = "Legendary",
}

local viewFrame
local tab1, tab2, tab3
local contentArea
local state = { build = nil }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function SetClassIcon(tex, classToken)
    local coords = CLASS_ICON_TCOORDS[classToken]
    if coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
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

------------------------------------------------------------------------
-- Overview tab
------------------------------------------------------------------------

local function BuildOverviewTab(parent)
    local outer = CreateFrame("Frame", nil, parent)
    outer:SetAllPoints(parent)

    -- Class icon + Build name header
    local classIcon = outer:CreateTexture(nil, "ARTWORK")
    classIcon:SetWidth(32)
    classIcon:SetHeight(32)
    classIcon:SetPoint("TOPLEFT", outer, "TOPLEFT", 10, -10)
    outer._classIcon = classIcon

    local nameLabel = outer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("TOPLEFT", classIcon, "TOPRIGHT", 8, -6)
    nameLabel:SetPoint("RIGHT",   outer,     "RIGHT",     -10, 0)
    nameLabel:SetJustifyH("LEFT")
    outer._nameLabel = nameLabel

    -- Author + last modified
    local metaLabel = outer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    metaLabel:SetPoint("TOPLEFT", classIcon, "BOTTOMLEFT", 0, -2)
    metaLabel:SetPoint("RIGHT",  outer,     "RIGHT",      -10, 0)
    metaLabel:SetJustifyH("LEFT")
    outer._metaLabel = metaLabel

    -- Permanent echoes
    local permHeader = outer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    permHeader:SetPoint("TOPLEFT", metaLabel, "BOTTOMLEFT", 0, -8)
    permHeader:SetText("Permanent Echoes:")
    outer._permHeader = permHeader

    local permButtons = {}
    for i = 1, 4 do
        local btn = CreateIconButton(outer, 36)
        btn:SetPoint("TOPLEFT", permHeader, "BOTTOMLEFT", (i - 1) * 42, -2)
        local border = btn:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -2,  2)
        border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  2, -2)
        border:Hide()
        btn._border = border
        btn:SetScript("OnEnter", function(self)
            if not self._spellId then return end
            local name = GetSpellInfo(self._spellId)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            if name then GameTooltip:AddLine(name, 1, 0.82, 0) end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        permButtons[i] = btn
    end
    outer._permButtons = permButtons

    -- Automation toggle + Edit button
    local autoToggle = CreateFrame("Button", nil, outer, "UIPanelButtonTemplate")
    autoToggle:SetWidth(140)
    autoToggle:SetHeight(22)
    autoToggle:SetPoint("TOPLEFT", permButtons[1], "BOTTOMLEFT", 0, -10)
    autoToggle:SetText("Automation: ON")
    autoToggle:SetScript("OnClick", function(self)
        local build = state.build
        if not build then return end
        build.automationEnabled = not build.automationEnabled
        self:SetText(build.automationEnabled and "Automation: ON" or "Automation: OFF")
    end)
    outer._autoToggle = autoToggle

    local editBtn = CreateFrame("Button", nil, outer, "UIPanelButtonTemplate")
    editBtn:SetWidth(120)
    editBtn:SetHeight(22)
    editBtn:SetPoint("LEFT", autoToggle, "RIGHT", 8, 0)
    editBtn:SetText("Edit Build")
    editBtn:SetScript("OnClick", function()
        if state.build then
            EbonBuilds.ViewRouter.Show("buildTabs", { mode = "edit", build = state.build })
        end
    end)

    -- Description header
    local descHeader = outer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    descHeader:SetPoint("TOPLEFT", autoToggle, "BOTTOMLEFT", 0, -14)
    descHeader:SetText("Description:")
    outer._descHeader = descHeader

    -- Description with its own scroll frame
    local descScroll = CreateFrame("ScrollFrame", nil, outer)
    descScroll:SetPoint("TOPLEFT",     descHeader, "BOTTOMLEFT", 0, -4)
    descScroll:SetPoint("BOTTOMRIGHT", outer,      "BOTTOMRIGHT", -22, 8)

    local descChild = CreateFrame("Frame", nil, descScroll)
    descChild:SetWidth(420)
    descChild:SetHeight(1)
    descScroll:SetScrollChild(descChild)

    local descBar = CreateFrame("Slider", nil, descScroll, "UIPanelScrollBarTemplate")
    descBar:SetPoint("TOPLEFT",    descScroll, "TOPRIGHT",    -2, -4)
    descBar:SetPoint("BOTTOMLEFT", descScroll, "BOTTOMRIGHT", -2,  4)
    descBar:SetValueStep(20)

    descBar:SetScript("OnValueChanged", function(self, value)
        descChild:SetPoint("TOPLEFT", descScroll, "TOPLEFT", 0, value)
    end)
    descScroll:EnableMouseWheel(true)
    descScroll:SetScript("OnMouseWheel", function(self, delta)
        local v = descBar:GetValue()
        local mn, mx = descBar:GetMinMaxValues()
        descBar:SetValue(math.max(mn, math.min(mx, v - delta * 20)))
    end)

    local descText = descChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descText:SetPoint("TOPLEFT",     descChild, "TOPLEFT",  0, -2)
    descText:SetPoint("RIGHT",       descChild, "RIGHT",   -2,  0)
    descText:SetJustifyH("LEFT")
    descText:SetJustifyV("TOP")
    descText:SetTextColor(0.8, 0.8, 0.8, 1)
    outer._descText = descText
    outer._descScroll = descScroll
    outer._descChild  = descChild
    outer._descBar    = descBar

    return outer, descText, descScroll, descChild, descBar
end

------------------------------------------------------------------------
-- Stats tab
------------------------------------------------------------------------

local STAT_ROWS = {
    { key = "echoesSeen",    label = "Echoes Seen" },
    { key = "runsCompleted", label = "Runs Completed" },
    { key = "runsReset",     label = "Runs Reset" },
    { key = "picks",         label = "Picks" },
    { key = "rerollsUsed",   label = "Rerolls Used" },
    { key = "banishesUsed",  label = "Banishes Used" },
    { key = "freezesUsed",   label = "Freezes Used" },
}

local function BuildStatsTab(parent)
    local y = -10

    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    header:SetText("Build Statistics")

    y = y - 30
    local valueLabels = {}
    for i, row in ipairs(STAT_ROWS) do
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
        lbl:SetText(row.label .. ":")
        lbl:SetWidth(160)
        lbl:SetJustifyH("LEFT")

        local val = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        val:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
        val:SetText("0")
        val:SetWidth(60)
        val:SetJustifyH("RIGHT")
        valueLabels[row.key] = val

        y = y - 22
    end

    -- Quality distribution
    y = y - 8
    local qHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, y)
    qHeader:SetText("Quality Distribution:")

    y = y - 22
    local qualityLabels = {}
    for q = 0, 4 do
        local qlbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        qlbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
        qlbl:SetText(QUALITY_LABELS[q] .. ":")
        qlbl:SetWidth(100)
        qlbl:SetJustifyH("LEFT")

        local qval = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        qval:SetPoint("LEFT", qlbl, "RIGHT", 4, 0)
        qval:SetText("0 (0%)")
        qval:SetWidth(80)
        qval:SetJustifyH("RIGHT")
        qualityLabels[q] = qval

        y = y - 18
    end

    -- Most picked / Most banned
    y = y - 6
    local mostPickedLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mostPickedLbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    mostPickedLbl:SetText("Most Picked:")
    mostPickedLbl:SetWidth(100)
    mostPickedLbl:SetJustifyH("LEFT")
    local mostPickedVal = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mostPickedVal:SetPoint("LEFT", mostPickedLbl, "RIGHT", 4, 0)
    mostPickedVal:SetText("-")
    mostPickedVal:SetWidth(150)
    mostPickedVal:SetJustifyH("LEFT")
    valueLabels.mostPicked = mostPickedVal

    y = y - 18
    local mostBannedLbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mostBannedLbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    mostBannedLbl:SetText("Most Banned:")
    mostBannedLbl:SetWidth(100)
    mostBannedLbl:SetJustifyH("LEFT")
    local mostBannedVal = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mostBannedVal:SetPoint("LEFT", mostBannedLbl, "RIGHT", 4, 0)
    mostBannedVal:SetText("-")
    mostBannedVal:SetWidth(150)
    mostBannedVal:SetJustifyH("LEFT")
    valueLabels.mostBanned = mostBannedVal

    return valueLabels, qualityLabels
end

------------------------------------------------------------------------
-- Logbook tab
------------------------------------------------------------------------

local function BuildLogbookTab(parent)
    local placeholder = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("CENTER", parent, "CENTER")
    placeholder:SetText("No log entries yet.")
    return placeholder
end

------------------------------------------------------------------------
-- Tab switching
------------------------------------------------------------------------

local overviewOuter
local overviewDescText, overviewDescScroll, overviewDescChild, overviewDescBar
local statsValueLabels, statsQualityLabels
local function RefreshOverview()
    local build = state.build
    if not build then return end
    local cc = CLASS_COLORS[build.class] or { 0.5, 0.5, 0.5 }

    SetClassIcon(overviewOuter._classIcon, build.class)
    overviewOuter._nameLabel:SetText(build.title or "Untitled")
    overviewOuter._nameLabel:SetTextColor(cc[1], cc[2], cc[3], 1)

    local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[build.class]
    local specName = specs and specs[build.spec or 1] and specs[build.spec or 1].name or ""
    overviewOuter._metaLabel:SetText(string.format("by %s | %s | %s",
        build.author or "Unknown",
        specName,
        build.lastModified or ""))

    overviewOuter._autoToggle:SetText(build.automationEnabled and "Automation: ON" or "Automation: OFF")

    local desc = build.comments or ""
    overviewDescText:SetText(desc)

    for i = 1, 4 do
        local btn = overviewOuter._permButtons[i]
        local spellId = build.permanentEchoes and build.permanentEchoes[i]
        if spellId then
            btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
            btn._spellId = spellId
            btn:Show()
            local data = ProjectEbonhold.PerkDatabase[spellId]
            local quality = data and data.quality or 0
            local bc = QUALITY_BORDER_COLORS[quality] or QUALITY_BORDER_COLORS[0]
            btn._border:SetTexture(bc[1], bc[2], bc[3])
            btn._border:Show()
        else
            btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
            btn._spellId = nil
            btn._border:Hide()
            btn:Show()
        end
    end

    -- Adjust description scroll range
    local textHeight = overviewDescText:GetStringHeight() or 0
    overviewDescChild:SetHeight(math.max(textHeight + 4, overviewDescScroll:GetHeight()))
    overviewDescBar:SetMinMaxValues(0, math.max(0, overviewDescChild:GetHeight() - overviewDescScroll:GetHeight()))
end

local function RefreshStats()
    local build = state.build
    if not build or not statsValueLabels then return end
    local st = build.stats or {}
    for _, row in ipairs(STAT_ROWS) do
        if statsValueLabels[row.key] then
            statsValueLabels[row.key]:SetText(tostring(st[row.key] or 0))
        end
    end
    for q = 0, 4 do
        if statsQualityLabels[q] then
            local count = (st.qualityPicks or {})[q] or 0
            local total = st.picks or 0
            local pct = total > 0 and math.floor(count / total * 100) or 0
            statsQualityLabels[q]:SetText(string.format("%d (%d%%)", count, pct))
        end
    end
    local mostPickedName = next(st.mostPicked or {}) or "-"
    statsValueLabels.mostPicked:SetText(type(mostPickedName) == "string" and mostPickedName or tostring(mostPickedName))
    local mostBannedName = next(st.mostBanned or {}) or "-"
    statsValueLabels.mostBanned:SetText(type(mostBannedName) == "string" and mostBannedName or tostring(mostBannedName))
end
------------------------------------------------------------------------
-- BuildViewFrame
------------------------------------------------------------------------

local switchOverview, switchStats, switchLogbook

local function BuildViewFrame()
    local f = CreateFrame("Frame", "EbonBuildsBuildOverview", UIParent)

    -- Bordered container
    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT",     f, "TOPLEFT",     0, -24)
    box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,  10)
    box:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    box:SetBackdropColor(0, 0, 0, 0.6)
    box:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    -- Inner content area
    contentArea = CreateFrame("Frame", nil, box)
    contentArea:SetPoint("TOPLEFT",     box, "TOPLEFT",     6, -6)
    contentArea:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6,  6)

    -- Build Overview tab content
    overviewOuter, overviewDescText, overviewDescScroll, overviewDescChild, overviewDescBar = BuildOverviewTab(contentArea)

    -- Build Stats tab content (hidden by default)
    local statsParent = CreateFrame("Frame", nil, contentArea)
    statsParent:SetAllPoints(contentArea)
    statsParent:Hide()
    statsValueLabels, statsQualityLabels = BuildStatsTab(statsParent)

    -- Build Logbook tab content (hidden by default)
    local logbookParent = CreateFrame("Frame", nil, contentArea)
    logbookParent:SetAllPoints(contentArea)
    logbookParent:Hide()
    BuildLogbookTab(logbookParent)

    -- Tab switching functions (defined after content so refs are valid)
    switchOverview = function()
        statsParent:Hide()
        logbookParent:Hide()
        overviewOuter:Show()
        PanelTemplates_SetTab(f, 1)
        PanelTemplates_EnableTab(f, 2)
        PanelTemplates_EnableTab(f, 3)
        RefreshOverview()
    end

    switchStats = function()
        overviewOuter:Hide()
        logbookParent:Hide()
        statsParent:Show()
        PanelTemplates_SetTab(f, 2)
        PanelTemplates_EnableTab(f, 1)
        PanelTemplates_EnableTab(f, 3)
        RefreshStats()
    end

    switchLogbook = function()
        overviewOuter:Hide()
        statsParent:Hide()
        logbookParent:Show()
        PanelTemplates_SetTab(f, 3)
        PanelTemplates_EnableTab(f, 1)
        PanelTemplates_EnableTab(f, 2)
    end

    tab1 = CreateFrame("Button", "EbonBuildsBuildOverviewTab1", f, "OptionsFrameTabButtonTemplate")
    tab1:SetID(1)
    tab1:SetText("Overview")
    tab1:SetPoint("TOPLEFT", f, "TOPLEFT", 10, 0)
    PanelTemplates_TabResize(tab1, 0)
    tab1:SetScript("OnClick", function() if switchOverview then switchOverview() end end)

    tab2 = CreateFrame("Button", "EbonBuildsBuildOverviewTab2", f, "OptionsFrameTabButtonTemplate")
    tab2:SetID(2)
    tab2:SetText("Stats")
    tab2:SetPoint("LEFT", tab1, "RIGHT", -16, 0)
    PanelTemplates_TabResize(tab2, 0)
    tab2:SetScript("OnClick", function() if switchStats then switchStats() end end)

    tab3 = CreateFrame("Button", "EbonBuildsBuildOverviewTab3", f, "OptionsFrameTabButtonTemplate")
    tab3:SetID(3)
    tab3:SetText("Logbook")
    tab3:SetPoint("LEFT", tab2, "RIGHT", -16, 0)
    PanelTemplates_TabResize(tab3, 0)
    tab3:SetScript("OnClick", function() if switchLogbook then switchLogbook() end end)

    PanelTemplates_SetNumTabs(f, 3)
    PanelTemplates_SetTab(f, 1)

    return f
end

------------------------------------------------------------------------
-- View interface
------------------------------------------------------------------------

local view = {}

function view.Show(container, context)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)

    context = context or {}
    state.build = context.build
    if switchOverview then switchOverview() end
    viewFrame:Show()
end

function view.Hide()
    if viewFrame then viewFrame:Hide() end
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function EbonBuilds.BuildOverview.Init()
    viewFrame = BuildViewFrame()
    viewFrame:Hide()
    EbonBuilds.ViewRouter.Register("buildOverview", view)
end
