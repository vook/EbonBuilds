-- EbonBuilds: modules/ui/BuildOverview.lua
-- Responsibility: build overview dashboard with tabs (Overview + Stats +
-- Echoes + Banish + Logbook + Affixes). Registered as "buildOverview" view.

EbonBuilds.BuildOverview = {}

local ST = EbonBuilds.SiteTheme
local SW = EbonBuilds.SiteWidgets
local C  = ST.C
local L  = ST.Layout

local CLASS_COLORS = ST.CLASS_COLORS

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

local activeOverviewTab = 1

local QUALITY_COLORS = {
    [0] = { 1.0, 1.0, 1.0 },
    [1] = { 30/255, 1.0, 0.0 },
    [2] = { 0.0, 112/255, 221/255 },
    [3] = { 163/255, 53/255, 238/255 },
    [4] = { 1.0, 128/255, 0.0 },
}

local viewFrame
local tab1, tab2, tab3, tab4, tab5, tab6
local contentArea
local sidebarFrame
local buildHeader
local tabBarFrame
local tabState = { selectedIndex = 1, tabs = {} }
local state = { build = nil }

------------------------------------------------------------------------
-- Delete confirmation dialog
------------------------------------------------------------------------

StaticPopupDialogs["EBONBUILDS_DELETE_BUILD"] = {
    text = "",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function()
        local build = state.build
        if not build or not build.id then return end
        local id = build.id
        EbonBuilds.Build.Delete(id)
        if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
            EbonBuilds.BuildList.Refresh()
        end
        local builds = EbonBuilds.Build.List()
        if #builds > 0 then
            EbonBuilds.Build.SetActive(builds[1].id)
            EbonBuilds.ViewRouter.Show("buildOverview", { build = builds[1] })
        else
            EbonBuilds.ViewRouter.Show("welcome")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

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

------------------------------------------------------------------------
-- Missing Echoes computation
------------------------------------------------------------------------

local CLASS_MASK = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8,
    PRIEST = 16, DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128,
    WARLOCK = 256, DRUID = 1024,
}

-- Strip common prefixes/suffixes so spell-name comparison is robust against
-- cosmetic variants like "Tome of Brittle Forging" vs "Brittle Forging".
local PREFIXES = { "tome of ", "codex of ", "scroll of ", "manual of ", "grimoire of ", "libram of ", "tablet of " }
local QUALITY_SUFFIXES = { " %- common", " %- uncommon", " %- rare", " %- epic", " %- legendary" }
local COMMENT_QUALITY_SUFFIX_NAMES = {
    "common", "uncommon", "rare", "epic", "legendary",
}

local function StripCommentQualitySuffix(raw)
    if not raw then return raw end
    local base, suffix = raw:match("^(.+) %- (.+)$")
    if base and suffix then
        local lower = string.lower(suffix)
        for _, q in ipairs(COMMENT_QUALITY_SUFFIX_NAMES) do
            if lower == q then
                return base
            end
        end
    end
    return raw
end

local function GetBuildWeights(build)
    if not build then return {} end
    local active = EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if active and active.id == build.id and EbonBuilds.Build.GetActiveWeights then
        return EbonBuilds.Build.GetActiveWeights()
    end
    return build.echoWeights or {}
end

local function NormalizeEchoName(name)
    if not name then return nil end
    local n = strlower(name)
    for _, prefix in ipairs(PREFIXES) do
        if n:sub(1, #prefix) == prefix then
            n = n:sub(#prefix + 1)
            break
        end
    end
    for _, suffix in ipairs(QUALITY_SUFFIXES) do
        if n:sub(-#suffix) == suffix then
            n = n:sub(1, -(#suffix + 1))
            break
        end
    end
    return n
end

local function ResolveMissingDropSource(spellId, data)
    if EbonBuilds.EchoSources and EbonBuilds.EchoSources.ResolveDropSource then
        return EbonBuilds.EchoSources.ResolveDropSource(spellId, data)
    end
    if EbonBuilds.EchoSources and EbonBuilds.EchoSources.ResolveRequiresTome then
        if not EbonBuilds.EchoSources.ResolveRequiresTome(data) then
            return "No tome required"
        end
    elseif not data.requiredSpell or data.requiredSpell == 0 or data.requiredSpell == 9 then
        return "No tome required"
    end
    return "Unknown"
end

local function ComputeMissingEchoes(build, opts)
    if not build or not build.class then return nil end
    if EbonBuilds.EchoOwnership and not EbonBuilds.EchoOwnership.IsCatalogReady() then
        return nil
    end
    opts = opts or {}

    local classMask = CLASS_MASK[build.class] or 0
    local showAllClasses = opts.showAllClasses == true
    local playerLevel = UnitLevel("player")

    local perkDb = (EbonBuilds.EchoOwnership and EbonBuilds.EchoOwnership.GetPerkDatabase())
        or (ProjectEbonhold and ProjectEbonhold.PerkDatabase)
    if not perkDb or not next(perkDb) then return nil end

    -- Rolled this run: granted perks + build locked echoes (always active in-run).
    local rolledLower = {}
    local rolledGroups = {}
    local granted = EbonBuilds.EchoOwnership
        and EbonBuilds.EchoOwnership.GetGrantedPerksMap()
        or {}

    for gkey, instances in pairs(granted) do
        local norm = NormalizeEchoName(gkey)
        if norm then rolledLower[norm] = true end
        if type(instances) == "table" then
            for _, inst in ipairs(instances) do
                if inst and inst.spellId then
                    local data = perkDb[inst.spellId]
                    local displayName = EbonBuilds.Scoring.ResolveEchoDisplayName
                        and EbonBuilds.Scoring.ResolveEchoDisplayName(inst.spellId, gkey)
                        or gkey
                    local n = NormalizeEchoName(displayName)
                    if n then rolledLower[n] = true end
                    if data and data.groupId then
                        rolledGroups[data.groupId] = true
                    end
                end
            end
        end
    end

    local lockedSpellIds = build.lockedEchoes or {}
    for _, spellId in ipairs(lockedSpellIds) do
        if spellId then
            local data = perkDb[spellId]
            local displayName = EbonBuilds.Scoring.ResolveEchoDisplayName
                and EbonBuilds.Scoring.ResolveEchoDisplayName(spellId)
            if not displayName then
                displayName = GetSpellInfo(spellId)
            end
            if data and data.comment and data.comment ~= "" then
                displayName = StripCommentQualitySuffix(data.comment)
            end
            local n = NormalizeEchoName(displayName)
            if n then rolledLower[n] = true end
            if data and data.groupId then
                rolledGroups[data.groupId] = true
            end
        end
    end

    -- Build locked echo name set for priority sorting
    local lockedLower = {}
    for _, spellId in ipairs(lockedSpellIds) do
        if spellId then
            local data = perkDb[spellId]
            local displayName = EbonBuilds.Scoring.ResolveEchoDisplayName
                and EbonBuilds.Scoring.ResolveEchoDisplayName(spellId)
            if not displayName then
                displayName = GetSpellInfo(spellId)
            end
            if data and data.comment and data.comment ~= "" then
                displayName = StripCommentQualitySuffix(data.comment)
            end
            local n = NormalizeEchoName(displayName)
            if n then lockedLower[n] = true end
        end
    end

    -- Group by echo name (comment-based, same keys as echo weights), keep highest quality
    local byName = {}
    for spellId, data in pairs(perkDb) do
        if data.comment and data.comment ~= "" then
            local displayName = StripCommentQualitySuffix(data.comment)
            local key = NormalizeEchoName(displayName)
            local matchesClass = showAllClasses
                or classMask == 0
                or bit.band(data.classMask or 0, classMask) ~= 0
            if matchesClass then
                if not data.minLevel or playerLevel >= data.minLevel then
                    local existing = byName[key]
                    if not existing then
                        byName[key] = {
                            spellId = spellId,
                            data = data,
                            displayName = displayName,
                            qualities = { [data.quality or 0] = true },
                            spellIds = { [data.quality or 0] = spellId },
                        }
                    else
                        existing.qualities[data.quality or 0] = true
                        if not existing.spellIds then
                            existing.spellIds = { [existing.data.quality or 0] = existing.spellId }
                        end
                        existing.spellIds[data.quality or 0] = spellId
                        if (data.quality or 0) > (existing.data.quality or 0) then
                            existing.spellId = spellId
                            existing.data = data
                            existing.displayName = displayName
                        end
                    end
                end
            end
        end
    end

    -- Collect echoes (exclude banned)
    local settings = build.settings or EbonBuilds.Build.DefaultSettings()
    local banList = settings.echoBanList or {}
    local weights = GetBuildWeights(build)
    local missing = {}
    for key, entry in pairs(byName) do
        local source = ResolveMissingDropSource(entry.spellId, entry.data)
        local sourceMeta = EbonBuilds.EchoSources
            and EbonBuilds.EchoSources.Classify(entry.data.groupId, source)
            or nil
        if not banList[entry.spellId] then
            -- Build scoring entry
            local scoringEntry = {
                spellId = entry.spellId,
                name = entry.displayName,
                quality = entry.data.quality or 0,
                families = entry.data.families,
                classMask = entry.data.classMask,
            }
            local quality = entry.data.quality or 0
            local baseWeight = EbonBuilds.Scoring.LookupWeight(weights, entry.displayName, quality)
            local score = EbonBuilds.Scoring.EffectiveWeight(scoringEntry, baseWeight, settings, quality)
            local requiresTome, tomeSpellId = false, nil
            if EbonBuilds.EchoSources and EbonBuilds.EchoSources.AggregateEchoTomeInfo then
                requiresTome, tomeSpellId = EbonBuilds.EchoSources.AggregateEchoTomeInfo(
                    entry.spellIds or { [quality] = entry.spellId },
                    perkDb
                )
            else
                requiresTome = entry.data.requiredSpell and entry.data.requiredSpell > 0
                    and entry.data.requiredSpell ~= 9
                tomeSpellId = requiresTome and entry.data.requiredSpell or nil
            end
            missing[#missing + 1] = {
                spellId = entry.spellId,
                name = entry.displayName,
                quality = quality,
                qualities = entry.qualities,
                spellIds = entry.spellIds or { [quality] = entry.spellId },
                groupId = entry.data.groupId,
                dropSource = source,
                sourceMeta = sourceMeta,
                isLocked = lockedLower[key] or false,
                rolled = EbonBuilds.EchoOwnership
                    and EbonBuilds.EchoOwnership.IsRolledThisRun(
                        entry.displayName, entry.spellId, entry.data.groupId, granted, lockedSpellIds)
                    or (rolledLower[key]
                        or (entry.data.groupId and rolledGroups[entry.data.groupId])
                        or false),
                owned = EbonBuilds.EchoOwnership
                    and EbonBuilds.EchoOwnership.IsAccountOwned(
                        entry.displayName, nil, entry.data.groupId, entry.spellId)
                    or false,
                baseWeight = baseWeight,
                score = score,
                requiresTome = requiresTome,
                tomeSpellId = tomeSpellId,
            }
        end
    end

    -- Sort: locked echoes first, then base weight desc, then quality desc, then name asc
    table.sort(missing, function(a, b)
        if a.isLocked ~= b.isLocked then
            return a.isLocked
        end
        if a.baseWeight ~= b.baseWeight then
            return a.baseWeight > b.baseWeight
        end
        if a.quality ~= b.quality then
            return a.quality > b.quality
        end
        return a.name < b.name
    end)
    return missing
end

------------------------------------------------------------------------
-- Overview tab content

local function BuildOverviewTab(parent)
    local outer = CreateFrame("Frame", nil, parent)
    outer:SetAllPoints(parent)

    local card = CreateFrame("Frame", nil, outer)
    card:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, 0)
    card:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT", 0, 0)
    SW.Fill(card, "mainBg")
    SW.ThinBorder(card, "borderSoft", 1)

    local descHeader = SW.Label(card, "DESCRIPTION", 11, C.textMuted, false, "semibold")
    descHeader:SetPoint("TOPLEFT", card, "TOPLEFT", L.PAD, -L.PAD)

    local descScroll = CreateFrame("ScrollFrame", nil, card)
    descScroll:SetPoint("TOPLEFT", descHeader, "BOTTOMLEFT", 0, -6)
    descScroll:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -L.PAD, 36)

    local descChild = CreateFrame("Frame", nil, descScroll)
    descChild:SetWidth(400)
    descChild:SetHeight(1)
    descScroll:SetScrollChild(descChild)

    local descBar = CreateFrame("Slider", "EbonBuildsOverviewDescBar", descScroll, "UIPanelScrollBarTemplate")
    descBar:SetPoint("TOPLEFT", descScroll, "TOPRIGHT", -8, -2)
    descBar:SetPoint("BOTTOMLEFT", descScroll, "BOTTOMRIGHT", -8, 2)
    descBar:Hide()
    SW.StyleVerticalScrollBar(descBar)
    EbonBuilds.ScrollWheel.SetupBar(descBar)
    descBar:SetValueStep(1)
    local wireDescWheel = select(1, EbonBuilds.ScrollWheel.Bind(descBar, 20))
    descBar:SetScript("OnValueChanged", function(self, value)
        descChild:ClearAllPoints()
        descChild:SetPoint("TOPLEFT", descScroll, "TOPLEFT", 0, value)
    end)
    wireDescWheel(descScroll)
    wireDescWheel(descChild)

    local descSmf = CreateFrame("ScrollingMessageFrame", nil, descChild)
    descSmf:SetPoint("TOPLEFT", descChild, "TOPLEFT", 0, -2)
    descSmf:SetWidth(400)
    descSmf:SetFontObject("GameFontNormalSmall")
    descSmf:SetJustifyH("LEFT")
    descSmf:SetFading(false)
    descSmf:SetInsertMode("TOP")
    descSmf:SetMaxLines(500)
    descSmf:SetHyperlinksEnabled(true)
    descSmf:EnableMouse(true)
    wireDescWheel(descSmf)
    descSmf:SetScript("OnHyperlinkEnter", function(self, link)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    descSmf:SetScript("OnHyperlinkLeave", function()
        GameTooltip:Hide()
    end)

    local descMeasure = descChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descMeasure:SetWidth(400)
    descMeasure:Hide()

    local descPlaceholder = SW.Label(descChild, "", 11, C.textMuted)
    descPlaceholder:SetPoint("TOPLEFT", descChild, "TOPLEFT", 0, -2)
    descPlaceholder:SetPoint("RIGHT", descScroll, "RIGHT", -24, 0)
    descPlaceholder:SetJustifyH("LEFT")
    descPlaceholder:SetWordWrap(true)
    descPlaceholder:Hide()

    local function SyncDescWidth()
        local w = descScroll:GetWidth()
        if w and w > 40 then
            descChild:SetWidth(w)
            descSmf:SetWidth(w)
            descMeasure:SetWidth(w)
            if descPlaceholder then
                descPlaceholder:SetWidth(w - 8)
            end
        end
    end

    local function SyncDescScroll()
        SyncDescWidth()
        local visible = descScroll:GetHeight() or 0
        local content = descChild:GetHeight() or 0
        local overflow = math.max(0, content - visible)
        if overflow <= 0 then
            descBar:Hide()
            if descBar._siteTrack then descBar._siteTrack:Hide() end
            descBar:SetMinMaxValues(0, 0)
            descBar:SetValue(0)
            descScroll:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -L.PAD, 36)
            descChild:ClearAllPoints()
            descChild:SetPoint("TOPLEFT", descScroll, "TOPLEFT", 0, 0)
        else
            descBar:Show()
            if descBar._siteTrack then descBar._siteTrack:Show() end
            descBar:SetMinMaxValues(0, overflow)
            if descBar:GetValue() > overflow then
                descBar:SetValue(overflow)
            end
            descScroll:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -20, 36)
        end
    end
    descScroll:SetScript("OnShow", SyncDescScroll)
    descScroll:SetScript("OnSizeChanged", SyncDescScroll)
    outer._syncDescWidth = SyncDescScroll

    outer._descSmf = descSmf
    outer._descMeasure = descMeasure
    outer._descPlaceholder = descPlaceholder
    outer._descScroll = descScroll
    outer._descChild  = descChild
    outer._descBar    = descBar

    local deleteBtn = SW.CreateOutlineButton(card, "Delete", 64)
    deleteBtn:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", L.PAD, 10)
    deleteBtn:SetScript("OnClick", function()
        local build = state.build
        if not build then return end
        local name = build.title or "Untitled"
        StaticPopupDialogs["EBONBUILDS_DELETE_BUILD"].text = "Delete build \"" .. name .. "\"?\n\nThis action cannot be undone."
        StaticPopup_Show("EBONBUILDS_DELETE_BUILD")
    end)
    outer._deleteBtn = deleteBtn

    return outer, descSmf, descMeasure, descScroll, descChild, descBar
end

------------------------------------------------------------------------
-- Stats tab
------------------------------------------------------------------------

local STAT_ROW1 = {
    { key = "echoesSeen",    label = "Echoes Seen" },
    { key = "picks",         label = "Picks" },
    { key = "runsCompleted", label = "Runs Completed" },
    { key = "runsReset",     label = "Runs Reset" },
}

local STAT_ROW2 = {
    { key = "rerollsUsed",   label = "Rerolls Used" },
    { key = "banishesUsed",  label = "Banishes Used" },
    { key = "freezesUsed",   label = "Freezes Used" },
}

local STAT_ROWS = {}
for _, row in ipairs(STAT_ROW1) do STAT_ROWS[#STAT_ROWS + 1] = row end
for _, row in ipairs(STAT_ROW2) do STAT_ROWS[#STAT_ROWS + 1] = row end

local function LayoutStatCells(parent, rows, startY, columns)
    local innerW = 388
    local gap = 6
    local cellW = math.floor((innerW - gap * (columns - 1)) / columns)
    local labels = {}
    for i, row in ipairs(rows) do
        local cell = SW.CreateStatCell(parent, row.label, "0")
        cell:SetSize(cellW, 44)
        local col = (i - 1) % columns
        local rowIdx = math.floor((i - 1) / columns)
        cell:SetPoint("TOPLEFT", parent, "TOPLEFT", L.PAD + col * (cellW + gap), startY - rowIdx * 50)
        labels[row.key] = cell._valueLabel
    end
    return labels
end

local function BuildStatsTab(parent)
    local card = SW.WrapContentCard(parent, L.PAD)

    local leftBlock = SW.CreateSidebarBlock(card, "Build statistics")
    leftBlock:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    leftBlock:SetWidth(420)
    leftBlock:SetHeight(300)

    local valueLabels = {}
    local y = leftBlock._contentTop
    local row1Labels = LayoutStatCells(leftBlock, STAT_ROW1, y, 4)
    for key, label in pairs(row1Labels) do valueLabels[key] = label end
    local row2Y = y - 50
    local row2Labels = LayoutStatCells(leftBlock, STAT_ROW2, row2Y, 3)
    for key, label in pairs(row2Labels) do valueLabels[key] = label end

    local gridBottom = row2Y - 50 - 8
    local mostRow = CreateFrame("Frame", nil, leftBlock)
    mostRow:SetPoint("TOPLEFT", leftBlock, "TOPLEFT", L.PAD, gridBottom)
    mostRow:SetPoint("RIGHT", leftBlock, "RIGHT", -L.PAD, 0)
    mostRow:SetHeight(40)

    local mostPickedLbl = SW.Label(mostRow, "Most Picked Echo", 10, C.textMuted)
    mostPickedLbl:SetPoint("TOPLEFT", mostRow, "TOPLEFT", 0, 0)
    local mostPickedVal = SW.Label(mostRow, "-", 11, C.text)
    mostPickedVal:SetPoint("TOPLEFT", mostPickedLbl, "BOTTOMLEFT", 0, -2)
    mostPickedVal:SetWidth(180)
    mostPickedVal:SetJustifyH("LEFT")
    valueLabels.mostPicked = mostPickedVal

    local mostBannedLbl = SW.Label(mostRow, "Most Banned Echo", 10, C.textMuted)
    mostBannedLbl:SetPoint("TOPLEFT", mostRow, "TOPLEFT", 200, 0)
    local mostBannedVal = SW.Label(mostRow, "-", 11, C.text)
    mostBannedVal:SetPoint("TOPLEFT", mostBannedLbl, "BOTTOMLEFT", 0, -2)
    mostBannedVal:SetWidth(180)
    mostBannedVal:SetJustifyH("LEFT")
    valueLabels.mostBanned = mostBannedVal

    local rightBlock = SW.CreateSidebarBlock(card, "Quality distribution")
    rightBlock:SetPoint("TOPLEFT", leftBlock, "TOPRIGHT", 16, 0)
    rightBlock:SetWidth(220)
    rightBlock:SetHeight(300)

    local qualityLabels = {}
    local qy = rightBlock._contentTop
    for q = 0, 4 do
        local qColor = QUALITY_COLORS[q] or { 1, 1, 1 }
        local qlbl = SW.Label(rightBlock, QUALITY_LABELS[q], 11, qColor)
        qlbl:SetPoint("TOPLEFT", rightBlock, "TOPLEFT", L.PAD, qy)
        qlbl:SetWidth(90)
        local qval = SW.Label(rightBlock, "0 (0%)", 11, C.text)
        qval:SetPoint("LEFT", qlbl, "RIGHT", 8, 0)
        qualityLabels[q] = qval
        qy = qy - 22
    end

    return valueLabels, qualityLabels
end

local function ResolveEchoStatQuality(echoName)
    if not echoName or echoName == "" then return nil end
    local spellId = EbonBuilds.EchoTableRows
        and EbonBuilds.EchoTableRows.ResolveSpellId
        and EbonBuilds.EchoTableRows.ResolveSpellId(echoName)
    if not spellId then return nil end
    local data = ProjectEbonhold and ProjectEbonhold.PerkDatabase
        and ProjectEbonhold.PerkDatabase[spellId]
    if not data then return nil end
    return data.quality or 0
end

local function SetEchoStatLabel(label, echoName)
    if not label then return end
    if not echoName then
        label:SetText("-")
        label:SetTextColor(unpack(C.text))
        return
    end
    label:SetText(echoName)
    local quality = ResolveEchoStatQuality(echoName)
    local qc = QUALITY_COLORS[quality] or C.text
    label:SetTextColor(unpack(qc))
end

local function CreateOverviewScrollFrame(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetHeight(1)
    child:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    scroll:SetScrollChild(child)

    local function SyncChildWidth()
        local w = scroll:GetWidth()
        if w and w > 0 then
            child:SetWidth(w)
        end
    end

    local bar = CreateFrame("Slider", nil, scroll, "UIPanelScrollBarTemplate")
    bar:SetPoint("TOPLEFT",    scroll, "TOPRIGHT",    -2, -4)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -2,  4)
    EbonBuilds.ScrollWheel.SetupBar(bar)
    bar:SetValueStep(1)
    bar:SetValue(0)
    SW.StyleVerticalScrollBar(bar)

    local wireWheel = select(1, EbonBuilds.ScrollWheel.Bind(bar, 16))

    local function UpdateOverviewScroll()
        if scroll._fixedScrollChild then
            SW.UpdateVerticalScroll(scroll, child, bar)
        else
            SW.ScheduleVerticalScroll(scroll, child, bar)
        end
    end

    bar:SetScript("OnValueChanged", function(self, value)
        if scroll._fixedScrollChild then
            if scroll._onScroll then scroll._onScroll(value) end
        else
            child:ClearAllPoints()
            child:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, value)
        end
        if scroll._onScroll and not scroll._fixedScrollChild then
            scroll._onScroll(value)
        end
    end)
    wireWheel(scroll)
    wireWheel(child)

    scroll:SetScript("OnSizeChanged", function()
        SyncChildWidth()
        UpdateOverviewScroll()
        if scroll._fixedScrollChild and scroll._onScroll then
            scroll._onScroll()
        end
    end)
    scroll:SetScript("OnShow", function()
        SyncChildWidth()
        UpdateOverviewScroll()
        if scroll._onScroll then scroll._onScroll() end
    end)

    return scroll, child, bar, SyncChildWidth, wireWheel, UpdateOverviewScroll
end

------------------------------------------------------------------------
-- Echoes tab (merged Rolled + Missing)
------------------------------------------------------------------------

local missingSearchText = ""
local missingCatalogBuildId = nil
local missingCatalogShowAll = nil
local missingCatalogEntries = nil
local missingSearchTimer = nil
local MISS_MAIN_ROW_H = 26
local MISS_SUB_ROW_H = 24
local missingRequiresTomeFilter = nil
local missingMultipleRanksFilter = nil
local missingShowAllClasses = false
local missingSourceFilter = {}
local missingTomeFilterCb
local missingTomeFilterLabel
local missingMultiRankFilterCb
local missingMultiRankFilterLabel
local missingClassFilterCb
local missingClassFilterLabel
local RefreshMissing
local LayoutAllMissingRows
local RefreshMissingVisibleRows

local function InvalidateMissingCatalog()
    missingCatalogBuildId = nil
    missingCatalogShowAll = nil
    missingCatalogEntries = nil
end

local function ScheduleMissingFilterRefresh()
    if missingSearchTimer and missingSearchTimer.Cancel then
        missingSearchTimer:Cancel()
        missingSearchTimer = nil
    end
    if C_Timer and C_Timer.NewTimer then
        missingSearchTimer = C_Timer.NewTimer(0.2, function()
            missingSearchTimer = nil
            RefreshMissing()
        end)
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, RefreshMissing)
        return
    end
    RefreshMissing()
end

local function GetMissingCatalog(build)
    local buildId = build.id or tostring(build)
    if missingCatalogEntries
        and missingCatalogBuildId == buildId
        and missingCatalogShowAll == missingShowAllClasses then
        return missingCatalogEntries
    end

    local missing = ComputeMissingEchoes(build, {
        showAllClasses = missingShowAllClasses,
    })
    if missing ~= nil then
        missingCatalogBuildId = buildId
        missingCatalogShowAll = missingShowAllClasses
        missingCatalogEntries = missing
    end
    return missing
end

local function LoadMissingFilterPrefs()
    local gs = EbonBuildsDB and EbonBuildsDB.globalSettings
    if gs and gs.missingRequiresTome ~= nil then
        if gs.missingRequiresTome == true then
            missingRequiresTomeFilter = "only"
        elseif gs.missingRequiresTome == false then
            missingRequiresTomeFilter = nil
        elseif gs.missingRequiresTome == "only" or gs.missingRequiresTome == "exclude" then
            missingRequiresTomeFilter = gs.missingRequiresTome
        end
    end
    if gs and gs.missingMultipleRanks ~= nil then
        if gs.missingMultipleRanks == true then
            missingMultipleRanksFilter = "only"
        elseif gs.missingMultipleRanks == false then
            missingMultipleRanksFilter = nil
        elseif gs.missingMultipleRanks == "only" or gs.missingMultipleRanks == "exclude" then
            missingMultipleRanksFilter = gs.missingMultipleRanks
        end
    end
    missingSourceFilter = {}
    if gs and gs.missingSourceFilter ~= nil then
        gs.missingSourceFilter = nil
    end
end

local function PersistMissingFilterPrefs()
    if not EbonBuildsDB then return end
    EbonBuildsDB.globalSettings = EbonBuildsDB.globalSettings or {}
    EbonBuildsDB.globalSettings.missingRequiresTome = missingRequiresTomeFilter
    EbonBuildsDB.globalSettings.missingMultipleRanks = missingMultipleRanksFilter
    if EbonBuildsDB.globalSettings.missingSourceFilter ~= nil then
        EbonBuildsDB.globalSettings.missingSourceFilter = nil
    end
end

local function SyncMissingClassFilterUI()
    local box = missingClassFilterCb and missingClassFilterCb._checkbox
    if not box or not box.SetChecked then return end
    if missingShowAllClasses then
        box:SetMarkColor({ 0.6, 0.8, 1.0 })
        box:SetChecked(true)
        if missingClassFilterLabel then
            missingClassFilterLabel:SetText("All Classes")
            missingClassFilterLabel:SetTextColor(0.6, 0.8, 1.0)
        end
    else
        box:SetChecked(false)
        if missingClassFilterLabel then
            missingClassFilterLabel:SetText("All Classes")
            missingClassFilterLabel:SetTextColor(0.8, 0.8, 0.8)
        end
    end
    if missingClassFilterCb.SetChipWidth then
        missingClassFilterCb:SetChipWidth()
    end
end

local function SyncMissingTomeFilterUI()
    if EbonBuilds.Filters and EbonBuilds.Filters.SyncRequiresTomeFilterUI then
        EbonBuilds.Filters.SyncRequiresTomeFilterUI(
            missingTomeFilterCb,
            missingTomeFilterLabel,
            missingRequiresTomeFilter
        )
    elseif missingTomeFilterCb and missingTomeFilterCb.SetChipActive then
        missingTomeFilterCb:SetChipActive(missingRequiresTomeFilter ~= nil)
        if missingTomeFilterLabel then
            local suffix = missingRequiresTomeFilter == "only" and " (only)"
                or missingRequiresTomeFilter == "exclude" and " (exclude)" or ""
            missingTomeFilterLabel:SetText("Requires Tome" .. suffix)
        end
    end
    if missingTomeFilterCb and missingTomeFilterCb.SetChipWidth then
        missingTomeFilterCb:SetChipWidth()
    end
end

local function SyncMissingMultiRankFilterUI()
    if EbonBuilds.Filters and EbonBuilds.Filters.SyncMultiRankFilterUI then
        EbonBuilds.Filters.SyncMultiRankFilterUI(
            missingMultiRankFilterCb,
            missingMultiRankFilterLabel,
            missingMultipleRanksFilter
        )
    elseif missingMultiRankFilterCb and missingMultiRankFilterCb.SetChipActive then
        missingMultiRankFilterCb:SetChipActive(missingMultipleRanksFilter ~= nil)
        if missingMultiRankFilterLabel then
            local suffix = missingMultipleRanksFilter == "only" and " (only)"
                or missingMultipleRanksFilter == "exclude" and " (exclude)" or ""
            missingMultiRankFilterLabel:SetText("Multi-Rank" .. suffix)
        end
    end
    if missingMultiRankFilterCb and missingMultiRankFilterCb.SetChipWidth then
        missingMultiRankFilterCb:SetChipWidth()
    end
end

local function SetMissingTomeFilter(mode, persist)
    missingRequiresTomeFilter = mode
    SyncMissingTomeFilterUI()
    if persist ~= false then
        PersistMissingFilterPrefs()
    end
end

local function CycleMissingTomeFilter()
    local nextMode = EbonBuilds.Filters.CycleRequiresTomeFilter(missingRequiresTomeFilter)
    SetMissingTomeFilter(nextMode)
    return missingRequiresTomeFilter
end

local function SetMissingMultiRankFilter(mode, persist)
    missingMultipleRanksFilter = mode
    SyncMissingMultiRankFilterUI()
    if persist ~= false then
        PersistMissingFilterPrefs()
    end
end

local function CycleMissingMultiRankFilter()
    local nextMode = EbonBuilds.Filters.CycleMultipleRanksFilter(missingMultipleRanksFilter)
    SetMissingMultiRankFilter(nextMode)
    return missingMultipleRanksFilter
end

local missingSourceMenu

local function SyncMissingSourceFilterUI()
    if not missingSourceMenu then return end
    local label = EbonBuilds.EchoSources
        and EbonBuilds.EchoSources.FilterLabel(missingSourceFilter)
        or "All sources"
    missingSourceMenu:SetMenuLabel(label)
end

local function CreateMissingSourceMenu(parent)
    local menu
    menu = SW.CreateSiteMenu(parent, {
        width = 120,
        menuWidth = 220,
        keepOpen = true,
        getLabel = function()
            return EbonBuilds.EchoSources
                and EbonBuilds.EchoSources.FilterLabel(missingSourceFilter)
                or "All sources"
        end,
        buildRows = function()
            if not EbonBuilds.EchoSources then return {} end
            return EbonBuilds.EchoSources.BuildFilterMenuRows(missingSourceFilter, function()
                menu:RefreshLabel()
                PersistMissingFilterPrefs()
                RefreshMissing()
            end)
        end,
    })
    missingSourceMenu = menu
    SyncMissingSourceFilterUI()
    return menu
end

-- Echoes tab column layout (Echo | Source | Rolled | Tome | Base Weight | Score).
local MISS_PAD_R             = 8
local MISS_COL_SCORE         = 56
local MISS_COL_BASE_WEIGHT   = 72
local MISS_COL_TOME          = 36
local MISS_COL_ROLLED        = 40
local MISS_COL_GAP           = 8
local MISS_ICON_PAD          = 2
local MISS_ICON_W            = 24
local MISS_NAME_GAP          = 6
local MISS_NAME_W            = 160
local MISS_NAME_LEFT         = MISS_ICON_PAD + MISS_ICON_W + MISS_NAME_GAP
local MISS_INSET_SCORE       = MISS_PAD_R
local MISS_INSET_BASE_WEIGHT = MISS_INSET_SCORE + MISS_COL_SCORE + MISS_COL_GAP
local MISS_INSET_TOME        = MISS_INSET_BASE_WEIGHT + MISS_COL_BASE_WEIGHT + MISS_COL_GAP
local MISS_INSET_ROLLED      = MISS_INSET_TOME + MISS_COL_TOME + MISS_COL_GAP

local missingColumnHeader
local missingParent

local function SyncRolledDisplay(frame, isRolled)
    if not frame or not frame._checkbox then return end
    frame:Show()
    frame._checkbox:Show()
    frame._checkbox:SetChecked(isRolled and true or false)
    frame._isRolled = isRolled and true or false
end

local function CreateRolledDisplay(row, opts)
    opts = opts or {}
    local rightInset = opts.rightInset or MISS_INSET_ROLLED
    local width = opts.width or MISS_COL_ROLLED
    local frame = CreateFrame("Frame", nil, row)
    frame:ClearAllPoints()
    frame:SetPoint("RIGHT", row, "RIGHT", -rightInset, 0)
    frame:SetPoint("TOP", row, "TOP", 0, 0)
    frame:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    frame:SetWidth(width)

    local SW = EbonBuilds.SiteWidgets
    local box = SW.CreateCheckbox(frame, { displayOnly = true, size = 16 })
    box:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame._checkbox = box

    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Rolled", 1, 0.82, 0)
        if self._isRolled then
            GameTooltip:AddLine("Granted this run.", 0.5, 1, 0.5, true)
        else
            GameTooltip:AddLine("Not granted this run.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return frame
end

local function MissAnchorRight(frame, parentFrame, inset, width)
    frame:ClearAllPoints()
    frame:SetPoint("RIGHT", parentFrame, "RIGHT", -inset, 0)
    if width and frame.SetWidth then
        frame:SetWidth(width)
    end
end

local function LayoutMissingHeader(hdr, parentFrame)
    MissAnchorRight(hdr._score, parentFrame, MISS_INSET_SCORE, MISS_COL_SCORE)
    MissAnchorRight(hdr._baseWeight, parentFrame, MISS_INSET_BASE_WEIGHT, MISS_COL_BASE_WEIGHT)
    if hdr._tomeFrame then
        MissAnchorRight(hdr._tomeFrame, parentFrame, MISS_INSET_TOME, MISS_COL_TOME)
    end
    if hdr._rolledFrame then
        MissAnchorRight(hdr._rolledFrame, parentFrame, MISS_INSET_ROLLED, MISS_COL_ROLLED)
    end
    hdr._source:ClearAllPoints()
    hdr._source:SetPoint("LEFT", parentFrame, "LEFT", MISS_NAME_LEFT + MISS_NAME_W + MISS_COL_GAP, 0)
    if hdr._rolledFrame then
        hdr._source:SetPoint("RIGHT", hdr._rolledFrame, "LEFT", -MISS_COL_GAP, 0)
    elseif hdr._tomeFrame then
        hdr._source:SetPoint("RIGHT", hdr._tomeFrame, "LEFT", -MISS_COL_GAP, 0)
    else
        hdr._source:SetPoint("RIGHT", hdr._baseWeight, "LEFT", -MISS_COL_GAP, 0)
    end
    hdr._echo:ClearAllPoints()
    hdr._echo:SetPoint("LEFT", parentFrame, "LEFT", MISS_NAME_LEFT, 0)
end

local function LayoutMissingRow(btn)
    btn._icon:ClearAllPoints()
    btn._icon:SetWidth(MISS_ICON_W)
    btn._icon:SetHeight(MISS_ICON_W)
    btn._icon:SetPoint("LEFT", btn, "LEFT", MISS_ICON_PAD, 0)
    btn._icon:SetPoint("TOP", btn, "TOP", 0, -5)
    MissAnchorRight(btn._labelScore, btn, MISS_INSET_SCORE, MISS_COL_SCORE)
    btn._labelScore:SetJustifyH("RIGHT")
    if btn._labelScore.SetNonSpaceWrap then
        btn._labelScore:SetNonSpaceWrap(true)
    end
    MissAnchorRight(btn._labelBaseWeight, btn, MISS_INSET_BASE_WEIGHT, MISS_COL_BASE_WEIGHT)
    btn._labelBaseWeight:SetJustifyH("RIGHT")
    if not btn._tomeOwned then
        btn._tomeOwned = EbonBuilds.EchoTableRows.CreateTomeOwnedDisplay(btn, {
            rightInset      = MISS_INSET_TOME,
            width           = MISS_COL_TOME,
            stretchVertical = true,
        })
    end
    if not btn._rolledDisplay then
        btn._rolledDisplay = CreateRolledDisplay(btn, {
            rightInset = MISS_INSET_ROLLED,
            width      = MISS_COL_ROLLED,
        })
    end
    btn._labelName:ClearAllPoints()
    btn._labelName:SetPoint("LEFT", btn, "LEFT", MISS_NAME_LEFT, 0)
    btn._labelName:SetPoint("TOP", btn, "TOP", 0, -4)
    btn._labelName:SetWidth(MISS_NAME_W)
    btn._labelName:SetJustifyH("LEFT")
    btn._labelSource:ClearAllPoints()
    btn._labelSource:SetPoint("LEFT", btn._labelName, "RIGHT", MISS_COL_GAP, 0)
    btn._labelSource:SetPoint("RIGHT", btn._rolledDisplay, "LEFT", -MISS_COL_GAP, 0)
    btn._labelSource:SetPoint("TOP", btn, "TOP", 0, -4)
    btn._labelSource:SetJustifyH("LEFT")
    if btn._labelSource.SetWordWrap then btn._labelSource:SetWordWrap(false) end
    if btn._labelSource.SetMaxLines then btn._labelSource:SetMaxLines(1) end
    if not btn._echoHit then
        btn._echoHit = CreateFrame("Frame", nil, btn)
        btn._echoHit:EnableMouse(true)
        btn._echoHit:SetScript("OnEnter", function(self)
            local row = self:GetParent()
            if not row or not row._spellId then return end
            if EbonBuilds.EchoTableRows and EbonBuilds.EchoTableRows.ShowEchoTooltip then
                EbonBuilds.EchoTableRows.ShowEchoTooltip(self, row._spellId)
            else
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:ClearLines()
                local spellName = GetSpellInfo(row._spellId)
                if spellName then
                    GameTooltip:AddLine(spellName, 1, 0.82, 0)
                end
                if utils and utils.GetSpellDescription then
                    local desc = utils.GetSpellDescription(row._spellId, 500, 1)
                    if desc and desc ~= "" then
                        GameTooltip:AddLine(desc, 1, 1, 1, true)
                    end
                end
                GameTooltip:Show()
            end
        end)
        btn._echoHit:SetScript("OnLeave", function()
            if EbonBuilds.EchoTableRows and EbonBuilds.EchoTableRows.HideEchoTooltip then
                EbonBuilds.EchoTableRows.HideEchoTooltip()
            else
                GameTooltip:Hide()
            end
        end)
    end
    if not btn._sourceHit then
        btn._sourceHit = CreateFrame("Frame", nil, btn)
        btn._sourceHit:EnableMouse(true)
        btn._sourceHit:SetScript("OnEnter", function(self)
            local row = self:GetParent()
            local text = row and row._sourceText
            if not text or text == "" then return end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Source", 1, 0.82, 0)
            GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        btn._sourceHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    btn._echoHit:ClearAllPoints()
    btn._echoHit:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
    btn._echoHit:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    btn._echoHit:SetPoint("RIGHT", btn._labelName, "RIGHT", 0, 0)
    btn._sourceHit:ClearAllPoints()
    btn._sourceHit:SetPoint("TOPLEFT", btn._labelName, "TOPRIGHT", MISS_COL_GAP, 0)
    btn._sourceHit:SetPoint("BOTTOMRIGHT", btn._rolledDisplay, "BOTTOMLEFT", -MISS_COL_GAP, 0)
end

local function BuildMissingTab(parent)
    local card = SW.WrapContentCard(parent, L.PAD)

    local headerRow = CreateFrame("Frame", nil, card)
    headerRow:SetPoint("TOPLEFT", card, "TOPLEFT", L.PAD, -L.PAD)
    headerRow:SetPoint("TOPRIGHT", card, "TOPRIGHT", -L.PAD, -L.PAD)
    headerRow:SetHeight(64)

    local controlsRow = CreateFrame("Frame", nil, headerRow)
    controlsRow:SetPoint("TOPLEFT", headerRow, "TOPLEFT", 0, 0)
    controlsRow:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
    controlsRow:SetHeight(28)

    local sourceMenu = CreateMissingSourceMenu(controlsRow)
    sourceMenu:SetPoint("TOPRIGHT", controlsRow, "TOPRIGHT", 0, 0)

    local searchFrame, searchEdit = SW.CreateSearchBox(controlsRow, "Search echoes...", function(text)
        missingSearchText = string.lower(text or "")
        ScheduleMissingFilterRefresh()
    end)
    searchFrame:SetPoint("TOPLEFT", controlsRow, "TOPLEFT", 0, 0)
    searchFrame:SetPoint("RIGHT", sourceMenu, "LEFT", -8, 0)

    local filterRow = CreateFrame("Frame", nil, headerRow)
    filterRow:SetPoint("TOPLEFT", controlsRow, "BOTTOMLEFT", 0, -8)
    filterRow:SetPoint("TOPRIGHT", controlsRow, "BOTTOMRIGHT", 0, -8)
    filterRow:SetHeight(28)

    local classChip = SW.CreateTriStateFilterChip(filterRow, "All Classes", function()
        missingShowAllClasses = not missingShowAllClasses
        SyncMissingClassFilterUI()
        InvalidateMissingCatalog()
        RefreshMissing()
    end, "Class Filter", function()
        if missingShowAllClasses then
            GameTooltip:AddLine("Showing echoes for all classes.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("Showing echoes for your class only.", 0.8, 0.8, 0.8, true)
        end
    end, { "All Classes" })
    classChip:SetPoint("LEFT", filterRow, "LEFT", 0, 0)
    missingClassFilterCb = classChip
    missingClassFilterLabel = classChip._label

    local tomeChip = SW.CreateTriStateFilterChip(filterRow, "Requires Tome", function()
        CycleMissingTomeFilter()
        SyncMissingTomeFilterUI()
        RefreshMissing()
    end, "Requires Tome Filter", function()
        local mode = missingRequiresTomeFilter
        if mode == "only" then
            GameTooltip:AddLine("Showing echoes that require a tome only.", 0.8, 0.8, 0.8, true)
        elseif mode == "exclude" then
            GameTooltip:AddLine("Showing echoes that do not require a tome only.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("No tome filter active.", 0.8, 0.8, 0.8, true)
        end
    end, { "Requires Tome", "Does Not Require Tome" })
    tomeChip:SetPoint("LEFT", classChip, "RIGHT", 12, 0)
    missingTomeFilterCb = tomeChip
    missingTomeFilterLabel = tomeChip._label

    local multiChip = SW.CreateTriStateFilterChip(filterRow, "Multi-Rank", function()
        CycleMissingMultiRankFilter()
        SyncMissingMultiRankFilterUI()
        RefreshMissing()
    end, "Multi-Rank Filter", function()
        local mode = missingMultipleRanksFilter
        if mode == "only" then
            GameTooltip:AddLine("Showing multi-rank echoes only.", 0.8, 0.8, 0.8, true)
        elseif mode == "exclude" then
            GameTooltip:AddLine("Hiding multi-rank echoes.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("No multi-rank filter active.", 0.8, 0.8, 0.8, true)
        end
    end, { "Multi-Rank", "Exclude Multi-Rank" })
    multiChip:SetPoint("LEFT", tomeChip, "RIGHT", 12, 0)
    missingMultiRankFilterCb = multiChip
    missingMultiRankFilterLabel = multiChip._label

    LoadMissingFilterPrefs()
    SyncMissingClassFilterUI()
    SyncMissingTomeFilterUI()
    SyncMissingMultiRankFilterUI()
    SyncMissingSourceFilterUI()

    missingColumnHeader = CreateFrame("Frame", nil, card)
    missingColumnHeader:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -10)
    missingColumnHeader:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, -10)
    missingColumnHeader:SetHeight(16)

    local function MakeMissHdr(text, justify)
        local fs = missingColumnHeader:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetTextColor(0.53, 0.53, 0.53, 1)
        fs:SetText(text)
        fs:SetJustifyH(justify or "LEFT")
        return fs
    end

    local tomeHdr = CreateFrame("Frame", nil, missingColumnHeader)
    tomeHdr:SetSize(MISS_COL_TOME, 16)
    local tomeHdrLabel = tomeHdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tomeHdrLabel:SetPoint("CENTER", tomeHdr, "CENTER", 0, 0)
    tomeHdrLabel:SetText("Owned")
    tomeHdrLabel:SetTextColor(0.53, 0.53, 0.53, 1)
    tomeHdr:EnableMouse(true)
    tomeHdr:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Owned", 1, 0.82, 0)
        GameTooltip:AddLine("Checked when the echo is discovered on your account.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    tomeHdr:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local rolledHdr = CreateFrame("Frame", nil, missingColumnHeader)
    rolledHdr:SetSize(MISS_COL_ROLLED, 16)
    local rolledHdrLabel = rolledHdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rolledHdrLabel:SetPoint("CENTER", rolledHdr, "CENTER", 0, 0)
    rolledHdrLabel:SetText("Rolled")
    rolledHdrLabel:SetTextColor(0.53, 0.53, 0.53, 1)
    rolledHdr:EnableMouse(true)
    rolledHdr:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Rolled", 1, 0.82, 0)
        GameTooltip:AddLine("Checked when the echo was granted or locked into this run.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    rolledHdr:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local scroll, child, bar, syncWidth, wireWheel = CreateOverviewScrollFrame(card)
    scroll._fixedScrollChild = true
    scroll._layoutCard = card
    scroll._layoutHeader = missingColumnHeader
    missingCollectionCard = card
    scroll._onScroll = function()
        if RefreshMissingVisibleRows then RefreshMissingVisibleRows() end
    end

    LayoutMissingHeader({
        _echo       = MakeMissHdr("Echo", "LEFT"),
        _source     = MakeMissHdr("Source", "LEFT"),
        _rolledFrame = rolledHdr,
        _tomeFrame  = tomeHdr,
        _baseWeight = MakeMissHdr("Base Weight", "RIGHT"),
        _score      = MakeMissHdr("Score", "RIGHT"),
    }, missingColumnHeader)

    if syncWidth then syncWidth() end

    return scroll, child, bar, wireWheel
end

------------------------------------------------------------------------
-- Tab switching
------------------------------------------------------------------------

local overviewOuter
local overviewDescSmf, overviewDescMeasure, overviewDescPlaceholder, overviewDescScroll, overviewDescChild, overviewDescBar

local DESC_PLACEHOLDER = "No description yet. Edit this build to add notes."
local statsValueLabels, statsQualityLabels
local missingScroll, missingChild, missingBar
local missingWireWheel
local missingCollectionCard
local collectionLayoutPass = 0
local missingRows = {}
local missingSubRows = {}
local missingDisplayRows = {}
local missingRowOffsetY = {}
local missingDisplayCount = 0

local function ComputeCollectionScrollHeight()
    local card = missingCollectionCard or (missingScroll and missingScroll._layoutCard)
    local header = missingColumnHeader or (missingScroll and missingScroll._layoutHeader)
    if not card or not header then return 0 end
    local headerBottom = header:GetBottom()
    local cardBottom = card:GetBottom()
    if headerBottom and cardBottom then
        return math.max(80, headerBottom - cardBottom - L.PAD)
    end
    return math.max(80, (card:GetHeight() or 0) - 120)
end

local function RelayoutCollectionScroll()
    if not missingScroll then return end
    local card = missingScroll._layoutCard or missingCollectionCard
    local header = missingScroll._layoutHeader or missingColumnHeader
    if not card or not header then return end

    local scrollH = ComputeCollectionScrollHeight()
    missingScroll:ClearAllPoints()
    missingScroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    missingScroll:SetPoint("TOPRIGHT", card, "TOPRIGHT", -L.PAD - 10, 0)
    if scrollH > 0 then
        missingScroll:SetHeight(scrollH)
    end

    if missingBar then
        missingBar:ClearAllPoints()
        missingBar:SetPoint("TOPLEFT", missingScroll, "TOPRIGHT", -2, -4)
        missingBar:SetPoint("BOTTOMLEFT", missingScroll, "BOTTOMRIGHT", -2, 4)
    end
end

local function RefreshCollectionLayout()
    if not missingScroll or not missingChild or not missingBar then return end
    if not missingScroll:IsShown() then return end

    RelayoutCollectionScroll()

    local viewH = missingScroll:GetHeight() or 0
    local expectedH = ComputeCollectionScrollHeight()
    if expectedH > 100 and viewH < expectedH * 0.85 then
        collectionLayoutPass = collectionLayoutPass + 1
        if collectionLayoutPass <= 6 and C_Timer and C_Timer.After then
            C_Timer.After(0, RefreshCollectionLayout)
            if collectionLayoutPass <= 2 then
                C_Timer.After(0.05, RefreshCollectionLayout)
            end
        end
        return
    end

    collectionLayoutPass = 0
    SW.ScheduleVerticalScroll(missingScroll, missingChild, missingBar)
    if missingScroll._savedScrollValue then
        local overflow = math.max(0, (missingChild:GetHeight() or 0) - (missingScroll:GetHeight() or 0))
        local v = math.min(missingScroll._savedScrollValue, overflow)
        if v > 0 and math.abs((missingBar:GetValue() or 0) - v) > 0.01 then
            missingBar:SetValue(v)
        end
        missingScroll._savedScrollValue = nil
    end
    if RefreshMissingVisibleRows then
        RefreshMissingVisibleRows()
    end
end

local COLLECTION_QUALITY_NAMES = {
    [0] = "Common", [1] = "Uncommon", [2] = "Rare", [3] = "Epic", [4] = "Legendary",
}

local function SortedQualities(qualities)
    local list = {}
    for q in pairs(qualities or {}) do
        list[#list + 1] = q
    end
    table.sort(list)
    return list
end

local function QualityCount(qualities)
    local n = 0
    for _ in pairs(qualities or {}) do n = n + 1 end
    return n
end

local function ExpandMissingDisplayRows(entries)
    local expanded = {}
    for _, entry in ipairs(entries) do
        local qs = SortedQualities(entry.qualities)
        if #qs <= 1 then
            expanded[#expanded + 1] = { kind = "single", entry = entry, quality = qs[1] or entry.quality }
        else
            expanded[#expanded + 1] = { kind = "header", entry = entry }
            for _, q in ipairs(qs) do
                expanded[#expanded + 1] = { kind = "sub", entry = entry, quality = q }
            end
        end
    end
    return expanded
end

local function ComputeMissingDisplayRowHeight(display)
    if display.kind == "sub" then return MISS_SUB_ROW_H end
    return MISS_MAIN_ROW_H
end

local function ScoreEntryQuality(entry, quality)
    local build = state.build
    if not build then return 0 end
    local spellId = entry.spellIds and entry.spellIds[quality] or entry.spellId
    local data = spellId and ProjectEbonhold.PerkDatabase[spellId]
    local settings = build.settings or EbonBuilds.Build.DefaultSettings()
    local weights = GetBuildWeights(build)
    local scoringEntry = {
        spellId = spellId,
        name = entry.name,
        quality = quality,
        families = data and data.families,
        classMask = data and data.classMask,
    }
    local baseWeight = EbonBuilds.Scoring.LookupWeight(weights, entry.name, quality)
    return EbonBuilds.Scoring.EffectiveWeight(scoringEntry, baseWeight, settings, quality)
end

local function AttachMissingWeightBox(row, echoName, quality)
    if not row._weightContainer then
        row._weightContainer = CreateFrame("Frame", nil, row)
        MissAnchorRight(row._weightContainer, row, MISS_INSET_BASE_WEIGHT, MISS_COL_BASE_WEIGHT)
        row._weightContainer:SetPoint("TOP", row, "TOP", 4, 0)
        row._weightContainer:SetPoint("BOTTOM", row, "BOTTOM", -4, 0)
        SW.Fill(row._weightContainer, "elementBg")
        row._weightContainer._border = SW.ThinBorder(row._weightContainer, "border", 1)
        local edit = CreateFrame("EditBox", nil, row._weightContainer)
        edit:SetPoint("LEFT", row._weightContainer, "LEFT", 4, 0)
        edit:SetPoint("RIGHT", row._weightContainer, "RIGHT", -4, 0)
        edit:SetHeight(18)
        edit:SetFont(ST.FONT.regular, 11, "")
        edit:SetTextColor(unpack(C.text))
        edit:SetJustifyH("CENTER")
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(3)
        row._weightEdit = edit
        if EbonBuilds.EchoTableRows.WireWeightEditBox then
            EbonBuilds.EchoTableRows.WireWeightEditBox(edit)
        end
        local prevLost = edit:GetScript("OnEditFocusLost")
        edit:SetScript("OnEditFocusLost", function(self)
            if prevLost then prevLost(self) end
            RefreshMissing()
        end)
        local prevEnter = edit:GetScript("OnEnterPressed")
        edit:SetScript("OnEnterPressed", function(self)
            if prevEnter then prevEnter(self) end
            RefreshMissing()
        end)
    end
    if row._labelBaseWeight then row._labelBaseWeight:Hide() end
    local edit = row._weightEdit
    edit.echoName = echoName
    edit.echoQuality = quality
    edit._row = row
    if quality ~= nil then
        if EbonBuilds.Weights.HasQualityOverride(echoName, quality) then
            edit:SetText(tostring(EbonBuilds.Weights.GetForQuality(echoName, quality)))
        else
            edit:SetText("")
        end
    else
        edit:SetText(tostring(EbonBuilds.Weights.Get(echoName)))
    end
    row._weightContainer:Show()
end

local function CreateMissingSubRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)
    row._bg = SW.Fill(row, "tierRowBg")

    local dot = SW.Label(row, "·", 11, C.textMuted)
    dot:SetPoint("LEFT", row, "LEFT", MISS_NAME_LEFT - 10, 0)

    row._qualLabel = SW.Label(row, "", 10, C.text)
    row._qualLabel:SetPoint("LEFT", dot, "RIGHT", 4, 0)
    row._qualLabel:SetWidth(78)

    row._labelScore = SW.Label(row, "", 10, C.textMuted)
    MissAnchorRight(row._labelScore, row, MISS_INSET_SCORE, MISS_COL_SCORE)
    row._labelScore:SetJustifyH("RIGHT")

    row:Hide()
    return row
end

local function EnsureMissingMainRow(index)
    while #missingRows < index do
        local n = #missingRows + 1
        local btn = CreateFrame("Button", nil, missingChild)
        btn:SetHeight(26)
        btn:RegisterForClicks("LeftButtonUp")
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn._icon = icon
        local labelName = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn._labelName = labelName
        local labelSource = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        labelSource:SetTextColor(0.6, 0.6, 0.6, 1)
        if labelSource.SetWordWrap then labelSource:SetWordWrap(false) end
        if labelSource.SetMaxLines then labelSource:SetMaxLines(1) end
        btn._labelSource = labelSource
        local labelBaseWeight = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn._labelBaseWeight = labelBaseWeight
        local labelScore = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn._labelScore = labelScore
        LayoutMissingRow(btn)
        missingRows[n] = btn
    end
    return missingRows[index]
end

local function PopulateMissingMainRow(btn, display, yPos)
    local entry = display.entry
    if btn._labelWeight then btn._labelWeight:Hide() end
    LayoutMissingRow(btn)
    local q = display.quality or entry.quality
    local spellId = entry.spellIds and entry.spellIds[q] or entry.spellId
    btn._spellId = spellId
    btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
    local cc = QUALITY_COLORS[q] or QUALITY_COLORS[0]
    btn._labelName:SetText(entry.name)
    btn._labelName:SetTextColor(cc[1], cc[2], cc[3], 1)
    local cleanSource = (entry.dropSource or ""):gsub("^Can be found on ", "")
    btn._sourceText = cleanSource
    btn._labelSource:SetText(cleanSource)
    if display.kind == "header" then
        btn._labelScore:SetText("")
        AttachMissingWeightBox(btn, entry.name, nil)
    else
        btn._labelScore:SetText(string.format("%.0f", ScoreEntryQuality(entry, q)))
        AttachMissingWeightBox(btn, entry.name, nil)
    end
    if EbonBuilds.EchoTableRows.SyncTomeOwnedDisplay then
        EbonBuilds.EchoTableRows.SyncTomeOwnedDisplay(btn._tomeOwned, {
            name = entry.name,
            spellId = spellId,
            groupId = entry.groupId,
            tomeSpellId = entry.tomeSpellId,
            owned = entry.owned,
        })
    end
    if btn._rolledDisplay then
        btn._rolledDisplay._isRolled = entry.rolled
        SyncRolledDisplay(btn._rolledDisplay, entry.rolled)
    end
    local rowH = display._rowH or MISS_MAIN_ROW_H
    btn:SetHeight(rowH)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", missingChild, "TOPLEFT", 0, -yPos)
    btn:SetPoint("RIGHT", missingChild, "RIGHT", 0, 0)
    btn:Show()
    if missingWireWheel then
        missingWireWheel(btn)
        if btn._tomeOwned then missingWireWheel(btn._tomeOwned) end
        if btn._rolledDisplay then missingWireWheel(btn._rolledDisplay) end
    end
end

local function PopulateMissingSubRow(sub, display, yPos)
    local entry = display.entry
    local q = display.quality
    local qColor = QUALITY_COLORS[q] or QUALITY_COLORS[0]
    local qName = COLLECTION_QUALITY_NAMES[q] or ("Q" .. tostring(q))
    sub._qualLabel:SetText(qName)
    sub._qualLabel:SetTextColor(qColor[1], qColor[2], qColor[3], 1)
    sub._labelScore:SetText(string.format("%.0f", ScoreEntryQuality(entry, q)))
    AttachMissingWeightBox(sub, entry.name, q)
    sub:ClearAllPoints()
    sub:SetPoint("TOPLEFT", missingChild, "TOPLEFT", 0, -yPos)
    sub:SetPoint("RIGHT", missingChild, "RIGHT", 0, 0)
    sub:SetHeight(MISS_SUB_ROW_H)
    sub:Show()
    if missingWireWheel then missingWireWheel(sub) end
end

local function RebuildMissingRowLayout(displayRows)
    missingDisplayRows = displayRows
    missingDisplayCount = #displayRows
    local currY = 0
    for i = 1, missingDisplayCount do
        local display = displayRows[i]
        display._rowH = ComputeMissingDisplayRowHeight(display)
        missingRowOffsetY[i] = currY
        currY = currY + display._rowH
        if display.kind ~= "sub" then
            currY = currY + 2
        end
    end
    missingChild:SetHeight(math.max(1, currY))
    SW.UpdateVerticalScroll(missingScroll, missingChild, missingBar)
end

LayoutAllMissingRows = function()
    if not missingChild or missingDisplayCount == 0 then return end

    local mainIdx = 0
    local subIdx = 0

    for i = 1, missingDisplayCount do
        local yTop = missingRowOffsetY[i] or 0
        local display = missingDisplayRows[i]
        if display.kind == "sub" then
            subIdx = subIdx + 1
            while #missingSubRows < subIdx do
                missingSubRows[#missingSubRows + 1] = CreateMissingSubRow(missingChild)
            end
            PopulateMissingSubRow(missingSubRows[subIdx], display, yTop)
        else
            mainIdx = mainIdx + 1
            PopulateMissingMainRow(EnsureMissingMainRow(mainIdx), display, yTop)
        end
    end

    for i = mainIdx + 1, #missingRows do
        missingRows[i]:Hide()
    end
    for i = subIdx + 1, #missingSubRows do
        missingSubRows[i]:Hide()
    end
end

RefreshMissingVisibleRows = function()
    if not missingChild or missingDisplayCount == 0 then return end
    for _, btn in ipairs(missingRows) do btn:Hide() end
    for _, row in ipairs(missingSubRows) do row:Hide() end

    local scrollY = (missingBar and missingBar:GetValue()) or 0
    local viewH = (missingScroll and missingScroll:GetHeight()) or 0
    local mainIdx = 0
    local subIdx = 0

    for i = 1, missingDisplayCount do
        local yTop = missingRowOffsetY[i] or 0
        local rowH = missingDisplayRows[i]._rowH or 26
        if yTop + rowH < scrollY - 200 then
            -- above viewport
        elseif yTop > scrollY + viewH + 200 then
            break
        else
            local yPos = yTop - scrollY
            local display = missingDisplayRows[i]
            if display.kind == "sub" then
                subIdx = subIdx + 1
                while #missingSubRows < subIdx do
                    missingSubRows[#missingSubRows + 1] = CreateMissingSubRow(missingChild)
                end
                PopulateMissingSubRow(missingSubRows[subIdx], display, yPos)
            else
                mainIdx = mainIdx + 1
                PopulateMissingMainRow(EnsureMissingMainRow(mainIdx), display, yPos)
            end
        end
    end
end

local function ResolveDisplaySpec(build)
    local classToken = build.class
    local specIdx = build.spec or 1
    if type(specIdx) ~= "number" then
        specIdx = ST.SpecIndex(classToken, specIdx)
    end

    local active = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if active and active.id == build.id then
        local playerClass = EbonBuilds.Build.PlayerClassToken and EbonBuilds.Build.PlayerClassToken()
        if playerClass and classToken == playerClass then
            specIdx = EbonBuilds.Build.PlayerTopTalentTab()
        end
    end

    local specName = ST.SpecDisplay(classToken, specIdx)
    return specIdx, specName
end

local function RefreshOverview()
    local build = state.build
    if not build then return end
    local cc = CLASS_COLORS[build.class] or { 0.5, 0.5, 0.5 }

    if buildHeader then
        buildHeader._title:SetText(build.title or "Untitled")
        buildHeader._title:SetTextColor(cc[1], cc[2], cc[3], 1)
        local specIdx, specName = ResolveDisplaySpec(build)
        if buildHeader.SetClass then
            buildHeader:SetClass(build.class, specIdx)
        end
        if buildHeader._subtitle then
            buildHeader._subtitle:SetText(string.format("by %s\n%s · %s",
                build.author or "Unknown",
                specName,
                build.lastModified or ""))
        end
    end

    if sidebarFrame and sidebarFrame._autoToggle then
        local label = build.automationEnabled and "Automation: ON" or "Automation: OFF"
        sidebarFrame._autoToggle._label:SetText(label)
    end

    if sidebarFrame and EbonBuilds.Build.EnsureStats then
        EbonBuilds.Build.EnsureStats(build)
        local st = build.stats or {}
        if sidebarFrame._runsCell and sidebarFrame._runsCell._valueLabel then
            sidebarFrame._runsCell._valueLabel:SetText(tostring(st.runsCompleted or 0))
        end
        if sidebarFrame._picksCell and sidebarFrame._picksCell._valueLabel then
            sidebarFrame._picksCell._valueLabel:SetText(tostring(st.picks or 0))
        end
    end

    if overviewOuter and overviewOuter._syncDescWidth then
        overviewOuter._syncDescWidth()
    end

    local comments = build.comments or ""
    local hasDesc = comments ~= "" and comments:match("%S")

    if hasDesc then
        if overviewDescPlaceholder then overviewDescPlaceholder:Hide() end
        if overviewDescSmf then
            overviewDescSmf:Show()
            overviewDescSmf:Clear()
            overviewDescSmf:AddMessage(comments, 0.8, 0.8, 0.8, 1.0)
        end
        overviewDescMeasure:SetText(comments)
    else
        if overviewDescSmf then
            overviewDescSmf:Clear()
            overviewDescSmf:Hide()
        end
        if overviewDescPlaceholder then
            overviewDescPlaceholder:SetText(DESC_PLACEHOLDER)
            overviewDescPlaceholder:Show()
        end
        overviewDescMeasure:SetText(DESC_PLACEHOLDER)
    end

    if overviewDescBar then
        overviewDescBar:SetValue(0)
    end
    if overviewDescChild and overviewDescScroll then
        overviewDescChild:SetPoint("TOPLEFT", overviewDescScroll, "TOPLEFT", 0, 0)
    end

    local lockedButtons = sidebarFrame and sidebarFrame._lockedButtons or {}
    local slotCount = (EbonBuilds.Build and EbonBuilds.Build.GetLockedSlotCount and EbonBuilds.Build.GetLockedSlotCount()) or 5
    for i = 1, #lockedButtons do
        local btn = lockedButtons[i]
        if i > slotCount then
            btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
            btn._spellId = nil
            btn._border:Hide()
            btn:Hide()
        else
            btn:Show()
        end
        local spellId = build.lockedEchoes and build.lockedEchoes[i]
        if spellId then
            btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
            btn._spellId = spellId
            local data = ProjectEbonhold.PerkDatabase[spellId]
            local quality = data and data.quality or 0
            local bc = QUALITY_BORDER_COLORS[quality] or QUALITY_BORDER_COLORS[0]
            btn._border:SetTexture(bc[1], bc[2], bc[3])
            btn._border:Show()
        else
            btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
            btn._spellId = nil
            btn._border:Hide()
        end
    end

    local textHeight = overviewDescMeasure:GetStringHeight() or 0
    if not hasDesc and overviewDescPlaceholder then
        textHeight = overviewDescPlaceholder:GetStringHeight() or textHeight
    end
    overviewDescSmf:SetHeight(math.max(textHeight + 4, 14))
    overviewDescChild:SetHeight(math.max(textHeight + 6, 14))
    if overviewOuter and overviewOuter._syncDescWidth then
        overviewOuter._syncDescWidth()
    end
end

local function RefreshStats()
    local build = state.build
    if not build or not statsValueLabels then return end
    if EbonBuilds.Build.EnsureStats then
        EbonBuilds.Build.EnsureStats(build)
    end
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
    local topPicked = EbonBuilds.Build.TopEchoStatName and EbonBuilds.Build.TopEchoStatName(st.mostPicked)
        or nil
    SetEchoStatLabel(statsValueLabels.mostPicked, topPicked)
    local topBanned = EbonBuilds.Build.TopEchoStatName and EbonBuilds.Build.TopEchoStatName(st.mostBanned)
        or nil
    SetEchoStatLabel(statsValueLabels.mostBanned, topBanned)
end

function EbonBuilds.BuildOverview.NotifyStatsChanged()
    if activeOverviewTab == 2 then
        RefreshStats()
    end
end

RefreshMissing = function(forceCatalog)
    local build = state.build
    if not build or not missingChild then return end
    for _, btn in ipairs(missingRows) do btn:Hide() end
    if forceCatalog then
        InvalidateMissingCatalog()
    end
    local missing = GetMissingCatalog(build)
    if missing == nil then
        missingChild.loadingLabel = missingChild.loadingLabel or missingChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        missingChild.loadingLabel:SetPoint("TOPLEFT", missingChild, "TOPLEFT", 4, -2)
        missingChild.loadingLabel:SetText("Requesting data...")
        missingChild.loadingLabel:Show()
        missingChild:SetHeight(20)
        missingDisplayCount = 0
        SW.UpdateVerticalScroll(missingScroll, missingChild, missingBar)
        RefreshMissingVisibleRows()
        return
    end
    if missingChild.loadingLabel then
        missingChild.loadingLabel:Hide()
    end
    if missingChild.noMatchLabel then
        missingChild.noMatchLabel:Hide()
    end

    local filtered = {}
    for _, entry in ipairs(missing) do
        local passesTome = EbonBuilds.Filters.PassesRequiresTomeFilter(entry, missingRequiresTomeFilter)
        local passesMultiRank = EbonBuilds.Filters.PassesMultipleRanksFilter(entry, missingMultipleRanksFilter)
        local passesSearch = EbonBuilds.EchoSearch.Matches(entry, missingSearchText)
        local passesSource = true
        if EbonBuilds.EchoSources then
            passesSource = EbonBuilds.EchoSources.PassesFilter(entry, missingSourceFilter)
        end
        if passesTome and passesMultiRank and passesSearch and passesSource then
            filtered[#filtered + 1] = entry
        end
    end

    if #filtered == 0 then
        missingChild.noMatchLabel = missingChild.noMatchLabel or missingChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        missingChild.noMatchLabel:SetPoint("TOPLEFT", missingChild, "TOPLEFT", 4, -2)
        if (missingSearchText ~= "" or missingRequiresTomeFilter or missingMultipleRanksFilter
                or (EbonBuilds.EchoSources and EbonBuilds.EchoSources.CountSelected(missingSourceFilter) > 0))
                and #missing > 0 then
            missingChild.noMatchLabel:SetText("No matches.")
        else
            missingChild.noMatchLabel:SetText("No echoes.")
        end
        missingChild.noMatchLabel:Show()
        missingChild:SetHeight(20)
        missingDisplayCount = 0
        SW.UpdateVerticalScroll(missingScroll, missingChild, missingBar)
        RefreshMissingVisibleRows()
        return
    end

    for _, btn in ipairs(missingRows) do btn:Hide() end
    for _, row in ipairs(missingSubRows) do row:Hide() end

    local displayRows = ExpandMissingDisplayRows(filtered)
    RebuildMissingRowLayout(displayRows)
    RefreshMissingVisibleRows()
    RefreshCollectionLayout()
end

------------------------------------------------------------------------
-- Banish / deprioritize policy tab (ban1st, banAfterPick, ignoreAfterPick)
------------------------------------------------------------------------

local banishScroll, banishChild, banishBar
local banishWireWheel
local banishRows = {}
local RefreshBanish

local BANISH_POLICY_IDS = {
    ban1st          = true,
    banAfterPick    = true,
    ignoreAfterPick = true,
}

local function ComputeBanishPolicyEchoes(build)
    if not build then return {} end
    EbonBuilds.Build.EnsureSettings(build)
    local policies = build.settings.echoPolicies or {}
    if not next(policies) then return {} end

    local weights = GetBuildWeights(build)
    local settings = build.settings
    local list = {}

    for name, policy in pairs(policies) do
        if BANISH_POLICY_IDS[policy] then
            local spellId = EbonBuilds.EchoTableRows.ResolveSpellId(name)
            if spellId then
                local data = ProjectEbonhold.PerkDatabase[spellId]
                local quality = data and data.quality or 0
                local displayName = name
                if EbonBuilds.Scoring.ResolveEchoDisplayName then
                    displayName = EbonBuilds.Scoring.ResolveEchoDisplayName(spellId, name) or name
                end
                local scoringEntry = {
                    spellId = spellId,
                    name = displayName,
                    quality = quality,
                    families = data and data.families,
                    classMask = data and data.classMask,
                }
                local weight = weights[displayName] or weights[name] or 0
                local score = EbonBuilds.Scoring.ScorePerQuality(scoringEntry, weight, settings, quality)
                local info = EbonBuilds.Build.GetEchoPolicyInfo(policy)
                list[#list + 1] = {
                    spellId = spellId,
                    name = displayName,
                    policyName = name,
                    quality = quality,
                    policy = policy,
                    policyTitle = info.title or policy,
                    weight = weight,
                    score = score,
                }
            end
        end
    end

    table.sort(list, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return list
end

-- Column layout shared by Banish tab header + rows (right-anchored fixed columns).
local BAN_PAD_R                 = 10
local BAN_COL_SCORE               = 60
local BAN_COL_WEIGHT              = 60
local BAN_COL_GAP                 = 14
local BAN_COL_GAP_BEFORE_POLICY   = 12
local BAN_COL_GAP_NAME_POLICY     = 10
local BAN_COL_POLICY              = 108
local BAN_ICON_PAD    = 2
local BAN_ICON_W      = 24
local BAN_NAME_GAP    = 6
local BAN_INSET_SCORE  = BAN_PAD_R
local BAN_INSET_WEIGHT = BAN_PAD_R + BAN_COL_SCORE + BAN_COL_GAP
local BAN_INSET_POLICY = BAN_INSET_WEIGHT + BAN_COL_WEIGHT + BAN_COL_GAP + BAN_COL_GAP_BEFORE_POLICY
local BAN_NAME_LEFT    = BAN_ICON_PAD + BAN_ICON_W + BAN_NAME_GAP

local function BanishAnchorRight(frame, row, inset, width)
    frame:ClearAllPoints()
    frame:SetPoint("RIGHT", row, "RIGHT", -inset, 0)
    if width and frame.SetWidth then
        frame:SetWidth(width)
    end
end

local function LayoutBanishHeader(hdr, row)
    BanishAnchorRight(hdr._score, row, BAN_INSET_SCORE, BAN_COL_SCORE)
    BanishAnchorRight(hdr._weight, row, BAN_INSET_WEIGHT, BAN_COL_WEIGHT)
    BanishAnchorRight(hdr._policy, row, BAN_INSET_POLICY, BAN_COL_POLICY)
    hdr._echo:ClearAllPoints()
    hdr._echo:SetPoint("LEFT", row, "LEFT", BAN_NAME_LEFT, 0)
    hdr._echo:SetPoint("RIGHT", hdr._policy, "LEFT", -BAN_COL_GAP_NAME_POLICY, 0)
    hdr._policy:SetJustifyH("CENTER")
end

local function LayoutBanishRowLabels(btn, row)
    btn._icon:ClearAllPoints()
    btn._icon:SetPoint("LEFT", row, "LEFT", BAN_ICON_PAD, 0)
    BanishAnchorRight(btn._labelScore, row, BAN_INSET_SCORE, BAN_COL_SCORE)
    BanishAnchorRight(btn._labelWeight, row, BAN_INSET_WEIGHT, BAN_COL_WEIGHT)
    if btn._policyDd then
        BanishAnchorRight(btn._policyDd, row, BAN_INSET_POLICY, BAN_COL_POLICY)
    elseif btn._labelPolicy then
        BanishAnchorRight(btn._labelPolicy, row, BAN_INSET_POLICY, BAN_COL_POLICY)
    end
    btn._labelName:ClearAllPoints()
    btn._labelName:SetPoint("LEFT", row, "LEFT", BAN_NAME_LEFT, 0)
    local policyAnchor = btn._policyDd or btn._labelPolicy
    if policyAnchor then
        btn._labelName:SetPoint("RIGHT", policyAnchor, "LEFT", -BAN_COL_GAP_NAME_POLICY, 0)
    end
    btn._labelName:SetJustifyH("LEFT")
    if btn._labelPolicy then
        btn._labelPolicy:SetJustifyH("LEFT")
    end
    btn._labelWeight:SetJustifyH("RIGHT")
    btn._labelScore:SetJustifyH("RIGHT")
end

local function BuildBanishTab(parent)
    local card = SW.WrapContentCard(parent, L.PAD)
    local outer = card

    local hint = SW.Label(outer, "Echoes with banish or ignore automation policies. Change policy here or in the Echoes tab.", 11, C.textDim)
    hint:SetPoint("TOPLEFT", outer, "TOPLEFT", L.PAD, -L.PAD)
    hint:SetPoint("TOPRIGHT", outer, "TOPRIGHT", -L.PAD, -L.PAD)
    hint:SetJustifyH("LEFT")

    local listArea = CreateFrame("Frame", nil, outer)
    listArea:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)
    listArea:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT", -L.PAD, L.PAD)

    local headerRow = CreateFrame("Frame", nil, listArea)
    headerRow:SetPoint("TOPLEFT", listArea, "TOPLEFT", 0, 0)
    headerRow:SetPoint("TOPRIGHT", listArea, "TOPRIGHT", -18, 0)
    headerRow:SetHeight(16)

    local function MakeBanishHeader(text, justify)
        local fs = headerRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetTextColor(0.53, 0.53, 0.53, 1)
        fs:SetText(text)
        fs:SetJustifyH(justify or "LEFT")
        return fs
    end

    local banishHeader = {
        _echo   = MakeBanishHeader("Name", "LEFT"),
        _policy = MakeBanishHeader("Policy", "CENTER"),
        _weight = MakeBanishHeader("Weight", "RIGHT"),
        _score  = MakeBanishHeader("Score", "RIGHT"),
    }
    LayoutBanishHeader(banishHeader, headerRow)

    local syncBanishWidth
    banishScroll, banishChild, banishBar, syncBanishWidth, banishWireWheel = CreateOverviewScrollFrame(listArea)
    banishScroll:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -4)
    banishScroll:SetPoint("BOTTOMRIGHT", listArea, "BOTTOMRIGHT", -18, 12)
    if syncBanishWidth then syncBanishWidth() end

    return banishScroll, banishChild, banishBar
end

RefreshBanish = function()
    local build = state.build
    if not build or not banishChild then return end
    for _, btn in ipairs(banishRows) do btn:Hide() end

    local entries = ComputeBanishPolicyEchoes(build)
    if banishChild.emptyLabel then banishChild.emptyLabel:Hide() end

    if #entries == 0 then
        banishChild.emptyLabel = banishChild.emptyLabel or banishChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        banishChild.emptyLabel:SetPoint("TOPLEFT", banishChild, "TOPLEFT", 4, -2)
        banishChild.emptyLabel:SetText("No banish or deprioritize policies configured — set them in the Echoes tab Policy column.")
        banishChild.emptyLabel:Show()
        banishChild:SetHeight(20)
        if banishBar then SW.ScheduleVerticalScroll(banishScroll, banishChild, banishBar) end
        return
    end

    local currY = 0
    for rowIdx, entry in ipairs(entries) do
        local n = #banishRows + 1
        if rowIdx > #banishRows then
            local btn = CreateFrame("Button", nil, banishChild)
            btn:SetHeight(26)
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetWidth(BAN_ICON_W)
            icon:SetHeight(BAN_ICON_W)
            btn._icon = icon
            local labelName = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            labelName:SetWordWrap(true)
            btn._labelName = labelName
            btn._policyDd = EbonBuilds.EchoTableRows.CreatePolicyDropdown(btn, {
                rightInset  = BAN_INSET_POLICY,
                columnWidth = BAN_COL_POLICY,
                width       = BAN_COL_POLICY - 8,
                onChanged   = function()
                    RefreshBanish()
                end,
            })
            local labelWeight = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn._labelWeight = labelWeight
            local labelScore = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn._labelScore = labelScore
            LayoutBanishRowLabels(btn, btn)
            btn:SetScript("OnEnter", function(self)
                if self._spellId and EbonBuilds.EchoTableRows.ShowEchoTooltip then
                    EbonBuilds.EchoTableRows.ShowEchoTooltip(self, self._spellId)
                end
            end)
            btn:SetScript("OnLeave", function()
                if EbonBuilds.EchoTableRows and EbonBuilds.EchoTableRows.HideEchoTooltip then
                    EbonBuilds.EchoTableRows.HideEchoTooltip()
                else
                    GameTooltip:Hide()
                end
            end)
            banishRows[n] = btn
        end
        local btn = banishRows[rowIdx]
        LayoutBanishRowLabels(btn, btn)
        btn._spellId = entry.spellId
        btn._icon:SetTexture(select(3, GetSpellInfo(entry.spellId)))
        local cc = QUALITY_COLORS[entry.quality] or QUALITY_COLORS[0]
        btn._labelName:SetText(entry.name)
        btn._labelName:SetTextColor(cc[1], cc[2], cc[3], 1)
        if btn._policyDd then
            btn._policyDd._echoName = entry.policyName or entry.name
            EbonBuilds.EchoTableRows.SyncPolicyDropdown(btn._policyDd)
            btn._policyDd:Show()
        end
        btn._labelWeight:SetText(tostring(entry.weight))
        btn._labelScore:SetText(string.format("%.0f", entry.score))
        local nameH = btn._labelName:GetStringHeight() or 16
        local rowH = math.max(26, nameH + 6)
        btn:SetHeight(rowH)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", banishChild, "TOPLEFT", 0, -currY)
        btn:SetPoint("RIGHT", banishChild, "RIGHT", 0, 0)
        btn:Show()
        if banishWireWheel then
            banishWireWheel(btn)
            if btn._policyDd then banishWireWheel(btn._policyDd) end
        end
        currY = currY + rowH + 4
    end
    banishChild:SetHeight(math.max(1, currY))
    if banishBar then
        SW.ScheduleVerticalScroll(banishScroll, banishChild, banishBar)
    end
end

------------------------------------------------------------------------
-- Logbook tab
------------------------------------------------------------------------

local function BuildLogbookTab(parent)
    EbonBuilds.SessionHistory.Show(parent)
end

------------------------------------------------------------------------
-- Sidebar (build identity + quick actions)
------------------------------------------------------------------------

local function BuildSidebar(parent)
    local sidebar = CreateFrame("Frame", nil, parent)
    sidebar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", L.SIDEBAR_W, 0)
    SW.FillChrome(sidebar, "sidebarBg")

    local footer = CreateFrame("Frame", nil, sidebar)
    footer:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(L.PAD + 28 + L.PAD)
    footer:SetFrameLevel(sidebar:GetFrameLevel() + 4)
    SW.FillChrome(footer, "sidebarBg")

    local backBtn = SW.CreateOutlineButton(footer, "< Builds", 0)
    backBtn:SetPoint("LEFT", footer, "LEFT", L.PAD, 0)
    backBtn:SetPoint("RIGHT", footer, "RIGHT", -L.PAD, 0)
    backBtn:SetHeight(28)
    backBtn:SetPoint("BOTTOM", footer, "BOTTOM", 0, L.PAD)
    backBtn:SetScript("OnClick", function()
        if EbonBuilds.MainWindow and EbonBuilds.MainWindow.ExpandBuildList then
            EbonBuilds.MainWindow.ExpandBuildList()
        end
    end)
    sidebar._footer = footer
    sidebar._backBtn = backBtn

    buildHeader = SW.CreateBuildHeader(sidebar, {
        height   = 132,
        class    = "MAGE",
        title    = "Untitled",
        subtitle = "",
    })
    buildHeader:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, 0)
    buildHeader:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)

    local lockedBlock = SW.CreateSidebarBlock(sidebar, "Locked echoes")
    lockedBlock:SetPoint("TOPLEFT", buildHeader, "BOTTOMLEFT", 0, -4)
    lockedBlock:SetHeight(72)

    local lockedRow = CreateFrame("Frame", nil, lockedBlock)
    lockedRow:SetPoint("TOPLEFT", lockedBlock, "TOPLEFT", L.PAD, lockedBlock._contentTop)
    lockedRow:SetPoint("RIGHT", lockedBlock, "RIGHT", -L.PAD, 0)
    lockedRow:SetHeight(L.ICON_LOCKED)

    local lockedButtons = {}
    local maxSlots = (EbonBuilds.Build and EbonBuilds.Build.MAX_LOCKED_SLOTS) or 6
    for i = 1, maxSlots do
        local btn = CreateIconButton(lockedRow, L.ICON_LOCKED - 4)
        btn:SetPoint("LEFT", lockedRow, "LEFT", (i - 1) * (L.ICON_LOCKED + 2), 0)
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
        lockedButtons[i] = btn
    end
    sidebar._lockedButtons = lockedButtons

    local actionsBlock = SW.CreateSidebarBlock(sidebar, "Actions")
    actionsBlock:SetPoint("TOPLEFT", lockedBlock, "BOTTOMLEFT", 0, -4)
    actionsBlock:SetHeight(88)

    local autoToggle = SW.CreateAccentButton(actionsBlock, "Automation: ON", function(self)
        local build = state.build
        if not build then return end
        local active = EbonBuilds.Build.GetActive()
        if active and active.id ~= build.id then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffffcc00[EbonBuilds] Activate this build to change automation.|r")
            return
        end
        local enabled = not build.automationEnabled
        build.automationEnabled = enabled
        if EbonBuilds.Automation.SetEnabled then
            EbonBuilds.Automation.SetEnabled(enabled)
        end
        self._label:SetText(enabled and "Automation: ON" or "Automation: OFF")
    end)
    autoToggle:SetSize(L.SIDEBAR_W - L.PAD * 2, 28)
    autoToggle:SetPoint("TOPLEFT", actionsBlock, "TOPLEFT", L.PAD, actionsBlock._contentTop)

    local actionW = L.SIDEBAR_W - L.PAD * 2
    local halfW = math.floor((actionW - 6) / 2)

    local editBtn = SW.CreateOutlineButton(actionsBlock, "Edit Build", halfW)
    editBtn:SetSize(halfW, 28)
    editBtn:SetPoint("TOPLEFT", autoToggle, "BOTTOMLEFT", 0, -8)
    editBtn:SetScript("OnClick", function()
        if state.build then
            EbonBuilds.ViewRouter.Show("buildTabs", { mode = "edit", build = state.build })
        end
    end)

    local echoJournalBtn = SW.CreateOutlineButton(actionsBlock, "Echo Journal", halfW)
    echoJournalBtn:SetSize(halfW, 28)
    echoJournalBtn:SetPoint("LEFT", editBtn, "RIGHT", 6, 0)
    echoJournalBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Echo Journal", 1, 0.82, 0)
        GameTooltip:AddLine("Opens the native /echoes browser.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    echoJournalBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    echoJournalBtn:SetScript("OnClick", function()
        if EbonBuilds.OpenEchoJournal then
            EbonBuilds.OpenEchoJournal()
        end
    end)

    sidebar._autoToggle = autoToggle

    local statsBlock = SW.CreateSidebarBlock(sidebar, "Quick stats")
    statsBlock:SetPoint("TOPLEFT", actionsBlock, "BOTTOMLEFT", 0, -4)
    statsBlock:SetPoint("BOTTOM", footer, "TOP", 0, -4)

    local statsInnerW = L.SIDEBAR_W - L.PAD * 2
    local cellGap = 6
    local cellW = math.floor((statsInnerW - cellGap) / 2)

    local runsCell = SW.CreateStatCell(statsBlock, "Runs", "0")
    runsCell:SetSize(cellW, 44)
    runsCell:SetPoint("TOPLEFT", statsBlock, "TOPLEFT", L.PAD, statsBlock._contentTop)
    sidebar._runsCell = runsCell

    local picksCell = SW.CreateStatCell(statsBlock, "Picks", "0")
    picksCell:SetSize(cellW, 44)
    picksCell:SetPoint("TOPLEFT", runsCell, "TOPRIGHT", cellGap, 0)
    sidebar._picksCell = picksCell

    return sidebar
end

------------------------------------------------------------------------
-- BuildViewFrame
------------------------------------------------------------------------

local switchOverview, switchStats, switchMissing, switchBanish, switchLogbook, switchAffixes
local affixParent

local function BuildViewFrame()
    local f = CreateFrame("Frame", "EbonBuildsBuildOverview", UIParent)
    SW.FillChrome(f, "bg")

    sidebarFrame = BuildSidebar(f)

    local mainCol = CreateFrame("Frame", nil, f)
    mainCol:SetPoint("TOPLEFT", sidebarFrame, "TOPRIGHT", 0, 0)
    mainCol:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    SW.FillChrome(mainCol, "mainBg")

    tabBarFrame = CreateFrame("Frame", nil, mainCol)
    tabBarFrame:SetPoint("TOPLEFT", mainCol, "TOPLEFT", 0, 0)
    tabBarFrame:SetPoint("TOPRIGHT", mainCol, "TOPRIGHT", 0, 0)
    tabBarFrame:SetHeight(40)
    SW.FillChrome(tabBarFrame, "tabBarBg")

    local tabSep = tabBarFrame:CreateTexture(nil, "ARTWORK")
    tabSep:SetTexture(ST.FLAT)
    tabSep:SetVertexColor(unpack(C.border))
    tabSep:SetHeight(1)
    tabSep:SetPoint("BOTTOMLEFT", tabBarFrame, "BOTTOMLEFT", 0, 0)
    tabSep:SetPoint("BOTTOMRIGHT", tabBarFrame, "BOTTOMRIGHT", 0, 0)

    contentArea = CreateFrame("Frame", nil, mainCol)
    contentArea:SetPoint("TOPLEFT", tabBarFrame, "BOTTOMLEFT", 0, 0)
    contentArea:SetPoint("BOTTOMRIGHT", mainCol, "BOTTOMRIGHT", 0, 0)

    overviewOuter, overviewDescSmf, overviewDescMeasure, overviewDescScroll, overviewDescChild, overviewDescBar = BuildOverviewTab(contentArea)
    overviewDescPlaceholder = overviewOuter and overviewOuter._descPlaceholder

    if not EbonBuilds.BuildOverview._overviewHooksInstalled then
        EbonBuilds.BuildOverview._overviewHooksInstalled = true

        if EbonBuilds.Build and EbonBuilds.Build.OnActiveChanged then
            EbonBuilds.Build.OnActiveChanged(function()
                if overviewOuter and overviewOuter:IsShown() and state.build then
                    RefreshOverview()
                end
            end)
        end
    end

    local statsParent = CreateFrame("Frame", nil, contentArea)
    statsParent:SetAllPoints(contentArea)
    statsParent:Hide()
    statsValueLabels, statsQualityLabels = BuildStatsTab(statsParent)

    missingParent = CreateFrame("Frame", nil, contentArea)
    missingParent:SetAllPoints(contentArea)
    missingParent:Hide()
    missingScroll, missingChild, missingBar, missingWireWheel = BuildMissingTab(missingParent)
    missingParent:SetScript("OnHide", function()
        if missingBar and missingScroll then
            missingScroll._savedScrollValue = missingBar:GetValue()
        end
    end)
    missingParent:SetScript("OnShow", function()
        collectionLayoutPass = 0
        if C_Timer and C_Timer.After then
            C_Timer.After(0, RefreshCollectionLayout)
            C_Timer.After(0.05, RefreshCollectionLayout)
            C_Timer.After(0.15, RefreshCollectionLayout)
        else
            RefreshCollectionLayout()
        end
    end)
    missingParent:HookScript("OnSizeChanged", function()
        if missingScroll and missingScroll:IsShown() then
            RefreshCollectionLayout()
        end
    end)
    if missingCollectionCard then
        missingCollectionCard:HookScript("OnSizeChanged", function()
            if missingScroll and missingScroll:IsShown() then
                RefreshCollectionLayout()
            end
        end)
    end

    local banishParent = CreateFrame("Frame", nil, contentArea)
    banishParent:SetAllPoints(contentArea)
    banishParent:Hide()
    BuildBanishTab(banishParent)

    local logbookParent = CreateFrame("Frame", nil, contentArea)
    logbookParent:SetAllPoints(contentArea)
    logbookParent:Hide()
    BuildLogbookTab(logbookParent)

    affixParent = CreateFrame("Frame", nil, contentArea)
    affixParent:SetAllPoints(contentArea)
    affixParent:Hide()

    local function HideAllContent()
        overviewOuter:Hide()
        statsParent:Hide()
        missingParent:Hide()
        banishParent:Hide()
        logbookParent:Hide()
        affixParent:Hide()
        EbonBuilds.AffixView.Unmount()
        if EbonBuilds.SessionHistory and EbonBuilds.SessionHistory.HideCopyDialog then
            EbonBuilds.SessionHistory.HideCopyDialog()
        end
        if overviewOuter and overviewOuter._updateCollectionTicker then
            overviewOuter._updateCollectionTicker()
        end
    end

    local function SelectTabVisual(index)
        tabState.selectedIndex = index
        SW.UpdateTabBar(tabState)
    end

    switchOverview = function()
        HideAllContent()
        overviewOuter:Show()
        if overviewOuter._deleteBtn then overviewOuter._deleteBtn:Show() end
        activeOverviewTab = 1
        SelectTabVisual(1)
        RefreshOverview()
    end

    switchStats = function()
        HideAllContent()
        if overviewOuter._deleteBtn then overviewOuter._deleteBtn:Hide() end
        statsParent:Show()
        activeOverviewTab = 2
        SelectTabVisual(2)
        RefreshStats()
    end

    switchMissing = function()
        HideAllContent()
        if overviewOuter._deleteBtn then overviewOuter._deleteBtn:Hide() end
        missingParent:Show()
        activeOverviewTab = 3
        SelectTabVisual(3)
        collectionLayoutPass = 0
        SyncMissingTomeFilterUI()
        RefreshMissing()
        RefreshCollectionLayout()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, RefreshCollectionLayout)
            C_Timer.After(0.15, RefreshCollectionLayout)
        end
        if overviewOuter and overviewOuter._updateCollectionTicker then
            overviewOuter._updateCollectionTicker()
        end
    end

    switchBanish = function()
        HideAllContent()
        if overviewOuter._deleteBtn then overviewOuter._deleteBtn:Hide() end
        banishParent:Show()
        activeOverviewTab = 4
        SelectTabVisual(4)
        RefreshBanish()
    end

    switchLogbook = function()
        HideAllContent()
        if overviewOuter._deleteBtn then overviewOuter._deleteBtn:Hide() end
        logbookParent:Show()
        activeOverviewTab = 5
        SelectTabVisual(5)
        EbonBuilds.SessionHistory.Show(logbookParent)
    end

    switchAffixes = function()
        HideAllContent()
        if overviewOuter._deleteBtn then overviewOuter._deleteBtn:Hide() end
        affixParent:Show()
        activeOverviewTab = 6
        SelectTabVisual(6)
        EbonBuilds.AffixView.SetOverviewBuild(state.build)
        EbonBuilds.AffixView.Mount(affixParent, { build = state.build })
    end

    tabState.SelectTab = function(index)
        if index == 1 then switchOverview()
        elseif index == 2 then switchStats()
        elseif index == 3 then switchMissing()
        elseif index == 4 then switchBanish()
        elseif index == 5 then switchLogbook()
        elseif index == 6 then switchAffixes()
        end
    end

    local TAB_LABELS = { "Overview", "Stats", "Collection", "Policies", "Logbook", "Affixes" }
    tabState.tabs = {}
    local prevTab
    for i, label in ipairs(TAB_LABELS) do
        local btn = SW.CreateTabButton(tabBarFrame, label, i, tabState)
        btn:SetPoint("TOP", tabBarFrame, "TOP", 0, 0)
        if prevTab then
            btn:SetPoint("LEFT", prevTab, "RIGHT", 4, 0)
        else
            btn:SetPoint("LEFT", tabBarFrame, "LEFT", L.PAD, 0)
        end
        tabState.tabs[i] = btn
        if i == 1 then tab1 = btn elseif i == 2 then tab2 = btn elseif i == 3 then tab3 = btn
        elseif i == 4 then tab4 = btn elseif i == 5 then tab5 = btn else tab6 = btn end
        prevTab = btn
    end
    SW.UpdateTabBar(tabState)

    local function IsCollectionTabVisible()
        return activeOverviewTab == 3
            and missingParent
            and missingParent:IsVisible()
            and EbonBuilds.MainWindow
            and EbonBuilds.MainWindow.IsVisible
            and EbonBuilds.MainWindow.IsVisible()
    end

    local function RefreshCollectionIfVisible()
        if not IsCollectionTabVisible() then return end
        if RefreshMissing then RefreshMissing() end
    end

    local function UpdateCollectionTicker()
        if not collectionRefreshTicker then return end
        if IsCollectionTabVisible() then
            collectionRefreshTicker:Show()
        else
            collectionRefreshTicker:Hide()
            collectionRefreshTicker.elapsed = 0
        end
    end

    local refreshFrame = CreateFrame("Frame")
    refreshFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    refreshFrame:SetScript("OnEvent", function()
        if EbonBuilds.EchoOwnership then
            EbonBuilds.EchoOwnership.Invalidate()
        end
        InvalidateMissingCatalog()
        RefreshCollectionIfVisible()
    end)

    local collectionRefreshTicker = CreateFrame("Frame")
    collectionRefreshTicker:Hide()
    collectionRefreshTicker.elapsed = 0
    collectionRefreshTicker:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 2 then
            self.elapsed = 0
            if RefreshMissing then RefreshMissing(true) end
        end
    end)
    overviewOuter._collectionTicker = collectionRefreshTicker
    overviewOuter._updateCollectionTicker = UpdateCollectionTicker

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
    if state.build and EbonBuilds.Build.SetSettingsContext then
        EbonBuilds.Build.SetSettingsContext(state.build)
    end
    if switchOverview then switchOverview() end
    viewFrame:Show()
    if EbonBuilds.BuildOverview.OnBuildListLayoutChanged then
        EbonBuilds.BuildOverview.OnBuildListLayoutChanged()
    end
end

function view.Hide()
    if EbonBuilds.Build.ClearSettingsContext then
        EbonBuilds.Build.ClearSettingsContext()
    end
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

function EbonBuilds.BuildOverview.OnBuildListLayoutChanged()
    if not sidebarFrame or not sidebarFrame._footer then return end
    local collapsed = EbonBuilds.MainWindow
        and EbonBuilds.MainWindow.IsBuildListCollapsed
        and EbonBuilds.MainWindow.IsBuildListCollapsed()
    if collapsed then
        sidebarFrame._footer:Show()
    else
        sidebarFrame._footer:Hide()
    end
end

function EbonBuilds.BuildOverview.SetDetailPanelVisible(visible)
    if not viewFrame then return end
    local current = EbonBuilds.ViewRouter and EbonBuilds.ViewRouter.Current()
    if visible and current ~= "buildOverview" then
        viewFrame:Hide()
        return
    end
    if visible then
        viewFrame:Show()
    else
        viewFrame:Hide()
    end
end

function EbonBuilds.BuildOverview.ShowMissingTab(opts)
    opts = opts or {}
    local build = opts.build
    if not build and EbonBuilds.Build and EbonBuilds.Build.GetActive then
        build = EbonBuilds.Build.GetActive()
    end
    if not build then return end

    if EbonBuilds.MainWindow and EbonBuilds.MainWindow.Show then
        EbonBuilds.MainWindow.Show()
    end

    EbonBuilds.ViewRouter.Show("buildOverview", { build = build })

    if switchMissing then
        switchMissing()
    end
end

function EbonBuilds.BuildOverview.IsMissingTabActive()
    if activeOverviewTab ~= 3 then return false end
    if not viewFrame or not viewFrame:IsShown() then return false end
    if EbonBuilds.ViewRouter and EbonBuilds.ViewRouter.Current() ~= "buildOverview" then
        return false
    end
    local main = EbonBuilds.MainWindow and EbonBuilds.MainWindow._frame
    return main and main:IsShown() or false
end
