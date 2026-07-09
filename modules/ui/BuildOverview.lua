-- EbonBuilds: modules/ui/BuildOverview.lua
-- Responsibility: build overview dashboard with tabs (Overview + Stats +
-- Echoes + Banish + Logbook + Affixes). Registered as "buildOverview" view.

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
    -- Prefer specific place + mob locations from the World of Echoes map data.
    local locations = EbonBuilds.EchoLocations
    if locations and data.groupId and locations[data.groupId] then
        return locations[data.groupId]
    end
    local sources = ProjectEbonhold.PerkDropSources
    local byGroup = ProjectEbonhold.PerkDropSourceByGroup
    if sources and sources[spellId] then
        return sources[spellId]
    end
    if data.groupId and byGroup and byGroup[data.groupId] then
        return byGroup[data.groupId]
    end
    -- Some tiers lack a direct entry; scan siblings in the same group.
    if data.groupId and sources then
        local perkDb = (EbonBuilds.EchoOwnership and EbonBuilds.EchoOwnership.GetPerkDatabase())
            or (ProjectEbonhold and ProjectEbonhold.PerkDatabase)
        if perkDb then
            for sid, perkData in pairs(perkDb) do
                if perkData.groupId == data.groupId and sources[sid] then
                    return sources[sid]
                end
            end
        end
    end
    local requiresTome = data.requiredSpell and data.requiredSpell ~= 0
    if not requiresTome then
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
                        }
                    else
                        existing.qualities[data.quality or 0] = true
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
            missing[#missing + 1] = {
                spellId = entry.spellId,
                name = entry.displayName,
                quality = quality,
                qualities = entry.qualities,
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
                requiresTome = entry.data.requiredSpell and entry.data.requiredSpell > 0,
                tomeSpellId = (entry.data.requiredSpell and entry.data.requiredSpell > 0)
                    and entry.data.requiredSpell or nil,
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

    -- Class icon + Build name header
    local classIcon = outer:CreateTexture(nil, "ARTWORK")
    classIcon:SetWidth(32)
    classIcon:SetHeight(32)
    classIcon:SetPoint("TOPLEFT", outer, "TOPLEFT", 10, -10)
    outer._classIcon = classIcon

    local nameLabel = outer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameLabel:SetPoint("TOPLEFT", classIcon, "TOPRIGHT", 8, -6)
    nameLabel:SetPoint("TOPRIGHT", outer, "TOPRIGHT", -10, -16)
    nameLabel:SetJustifyH("LEFT")
    outer._nameLabel = nameLabel

    -- Author + last modified
    local metaLabel = outer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    metaLabel:SetPoint("TOPLEFT", classIcon, "BOTTOMLEFT", 0, -2)
    metaLabel:SetPoint("RIGHT",  outer,     "RIGHT",      -10, 0)
    metaLabel:SetJustifyH("LEFT")
    outer._metaLabel = metaLabel

    -- Locked echoes
    local lockedHeader = outer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lockedHeader:SetPoint("TOPLEFT", metaLabel, "BOTTOMLEFT", 0, -14)
    lockedHeader:SetText("Locked Echoes:")
    outer._lockedHeader = lockedHeader

    local lockedButtons = {}
    local maxSlots = (EbonBuilds.Build and EbonBuilds.Build.MAX_LOCKED_SLOTS) or 6
    for i = 1, maxSlots do
        local btn = CreateIconButton(outer, 36)
        btn:SetPoint("TOPLEFT", lockedHeader, "BOTTOMLEFT", (i - 1) * 42, -6)
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
    outer._lockedButtons = lockedButtons

    -- Automation toggle + Edit button
    local autoToggle = CreateFrame("Button", nil, outer, "UIPanelButtonTemplate")
    autoToggle:SetWidth(140)
    autoToggle:SetHeight(22)
    autoToggle:SetPoint("TOPLEFT", lockedButtons[1], "BOTTOMLEFT", 0, -22)
    autoToggle:SetText("Automation: ON")
    autoToggle:SetScript("OnClick", function(self)
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
        self:SetText(enabled and "Automation: ON" or "Automation: OFF")
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

    local echoJournalBtn = CreateFrame("Button", nil, outer, "UIPanelButtonTemplate")
    echoJournalBtn:SetWidth(120)
    echoJournalBtn:SetHeight(22)
    echoJournalBtn:SetPoint("LEFT", editBtn, "RIGHT", 8, 0)
    echoJournalBtn:SetText("Echo Journal")
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
    outer._echoJournalBtn = echoJournalBtn

    -- Description header
    local descHeader = outer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    descHeader:SetPoint("TOPLEFT", autoToggle, "BOTTOMLEFT", 0, -14)
    descHeader:SetText("Description:")
    outer._descHeader = descHeader

    -- Description scroll frame (owns scrollbar)
    local descScroll = CreateFrame("ScrollFrame", nil, outer)
    descScroll:SetPoint("TOPLEFT",     descHeader, "BOTTOMLEFT", 0, -4)
    descScroll:SetPoint("BOTTOMRIGHT", outer,      "BOTTOMRIGHT", -22, 28)

    local descChild = CreateFrame("Frame", nil, descScroll)
    descChild:SetWidth(416)
    descChild:SetHeight(1)
    descScroll:SetScrollChild(descChild)

    local descBar = CreateFrame("Slider", nil, descScroll, "UIPanelScrollBarTemplate")
    descBar:SetPoint("TOPLEFT",    descScroll, "TOPRIGHT",    -2, -4)
    descBar:SetPoint("BOTTOMLEFT", descScroll, "BOTTOMRIGHT", -2,  4)
    EbonBuilds.ScrollWheel.SetupBar(descBar)
    descBar:SetValueStep(1)
    local wireDescWheel = select(1, EbonBuilds.ScrollWheel.Bind(descBar, 20))
    descBar:SetScript("OnValueChanged", function(self, value)
        descChild:SetPoint("TOPLEFT", descScroll, "TOPLEFT", 0, value)
    end)
    wireDescWheel(descScroll)
    wireDescWheel(descChild)

    -- SMF inside scroll child -- renders text with hyperlink tooltip support
    local descSmf = CreateFrame("ScrollingMessageFrame", nil, descChild)
    descSmf:SetPoint("TOPLEFT", descChild, "TOPLEFT", 0, -2)
    descSmf:SetWidth(416)
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

    -- Hidden FontString with same width -- used only to measure wrapped text height
    local descMeasure = descChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descMeasure:SetWidth(416)
    descMeasure:Hide()

    outer._descSmf = descSmf
    outer._descMeasure = descMeasure
    outer._descScroll = descScroll
    outer._descChild  = descChild
    outer._descBar    = descBar

    -- Delete button (bottom-left, below description, low misclick probability)
    local deleteBtn = CreateFrame("Button", nil, outer, "UIPanelButtonTemplate")
    deleteBtn:SetSize(64, 20)
    deleteBtn:SetPoint("BOTTOMLEFT", outer, "BOTTOMLEFT", 10, 4)
    deleteBtn:SetText("Delete")
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

    -- Left column: Build Statistics header + rows
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

    -- Most picked / Most banned (left column)
    y = y - 8
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

    -- Right column: Quality Distribution
    local qy = -10
    local qHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 270, qy)
    qHeader:SetText("Quality Distribution:")

    qy = qy - 26
    local qualityLabels = {}
    for q = 0, 4 do
        local qlbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        qlbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 274, qy)
        qlbl:SetText(QUALITY_LABELS[q] .. ":")
        qlbl:SetWidth(90)
        qlbl:SetJustifyH("LEFT")

        local qval = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        qval:SetPoint("LEFT", qlbl, "RIGHT", 4, 0)
        qval:SetText("0 (0%)")
        qval:SetWidth(80)
        qval:SetJustifyH("RIGHT")
        qualityLabels[q] = qval

        qy = qy - 18
    end

    return valueLabels, qualityLabels
end

local function CreateOverviewScrollFrame(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetHeight(1)
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

    local wireWheel = select(1, EbonBuilds.ScrollWheel.Bind(bar, 16))

    bar:SetScript("OnValueChanged", function(self, value)
        child:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, value)
    end)
    wireWheel(scroll)
    wireWheel(child)

    scroll:SetScript("OnSizeChanged", SyncChildWidth)
    scroll:SetScript("OnShow", SyncChildWidth)

    return scroll, child, bar, SyncChildWidth, wireWheel
end

------------------------------------------------------------------------
-- Echoes tab (merged Rolled + Missing)
------------------------------------------------------------------------

local missingSearchText = ""
local missingRequiresTomeFilter = nil
local missingMultipleRanksFilter = nil
local missingShowAllClasses = false
local missingSourceFilter = {}
local missingTomeFilterCb
local missingTomeFilterLabel
local missingMultiRankFilterCb
local missingMultiRankFilterLabel
local RefreshMissing

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

local function SyncMissingTomeFilterUI()
    if EbonBuilds.Filters and EbonBuilds.Filters.SyncRequiresTomeFilterUI then
        EbonBuilds.Filters.SyncRequiresTomeFilterUI(
            missingTomeFilterCb,
            missingTomeFilterLabel,
            missingRequiresTomeFilter
        )
    end
end

local function SyncMissingMultiRankFilterUI()
    if EbonBuilds.Filters and EbonBuilds.Filters.SyncMultiRankFilterUI then
        EbonBuilds.Filters.SyncMultiRankFilterUI(
            missingMultiRankFilterCb,
            missingMultiRankFilterLabel,
            missingMultipleRanksFilter
        )
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

local function CreateFilterCheckbox(parent, labelText, labelColor, anchorFrame, anchorPoint, xOff, yOff, onToggle, relPoint)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetSize(16, 16)
    cb:SetPoint(anchorPoint, anchorFrame, relPoint or anchorPoint, xOff, yOff)

    local cbBg = cb:CreateTexture(nil, "BORDER")
    cbBg:SetAllPoints(cb)
    cbBg:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cbBg:SetAlpha(0.8)

    local cbCheck = cb:CreateTexture(nil, "ARTWORK")
    cbCheck:SetWidth(14)
    cbCheck:SetHeight(14)
    cbCheck:SetPoint("CENTER", cb, "CENTER", 0, 0)
    cbCheck:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cbCheck:Hide()
    cb._checkTex = cbCheck

    local cbLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cbLabel:SetPoint("RIGHT", cb, "LEFT", -4, 0)
    cbLabel:SetPoint("TOP", cb, "TOP", 0, 0)
    cbLabel:SetPoint("BOTTOM", cb, "BOTTOM", 0, 0)
    cbLabel:SetJustifyH("RIGHT")
    cbLabel:SetJustifyV("MIDDLE")
    cbLabel:SetText(labelText)
    if labelColor then
        cbLabel:SetTextColor(labelColor[1], labelColor[2], labelColor[3])
    end

    cb:SetScript("OnClick", function()
        local checked = onToggle()
        if checked then cbCheck:Show() else cbCheck:Hide() end
        RefreshMissing()
    end)

    return cb, cbLabel
end

local function CreateMissingTomeCycleCheckbox(parent, anchorFrame, anchorPoint, xOff, yOff, relPoint)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetSize(16, 16)
    cb:SetPoint(anchorPoint, anchorFrame, relPoint or anchorPoint, xOff, yOff)

    local cbBg = cb:CreateTexture(nil, "BORDER")
    cbBg:SetAllPoints(cb)
    cbBg:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cbBg:SetAlpha(0.8)

    local cbCheck = cb:CreateTexture(nil, "ARTWORK")
    cbCheck:SetWidth(14)
    cbCheck:SetHeight(14)
    cbCheck:SetPoint("CENTER", cb, "CENTER", 0, 0)
    cbCheck:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cbCheck:Hide()
    cb._checkTex = cbCheck

    local cbLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cbLabel:SetPoint("RIGHT", cb, "LEFT", -4, 0)
    cbLabel:SetPoint("TOP", cb, "TOP", 0, 0)
    cbLabel:SetPoint("BOTTOM", cb, "BOTTOM", 0, 0)
    cbLabel:SetJustifyH("RIGHT")
    cbLabel:SetJustifyV("MIDDLE")
    cbLabel:SetText("Requires Tome")
    cbLabel:SetTextColor(0.8, 0.8, 0.8)
    missingTomeFilterLabel = cbLabel

    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Requires Tome Filter", 1, 0.82, 0)
        local mode = missingRequiresTomeFilter
        if mode == "only" then
            GameTooltip:AddLine("Showing echoes that require a tome only.", 0.8, 0.8, 0.8, true)
        elseif mode == "exclude" then
            GameTooltip:AddLine("Showing echoes that do not require a tome only.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("No tome filter active.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine("Click to cycle filter.", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cb:SetScript("OnClick", function()
        CycleMissingTomeFilter()
        RefreshMissing()
    end)

    missingTomeFilterCb = cb
    SyncMissingTomeFilterUI()
    return cb, cbLabel
end

local function CreateMissingMultiRankCycleCheckbox(parent, anchorFrame, anchorPoint, xOff, yOff, relPoint)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetSize(16, 16)
    cb:SetPoint(anchorPoint, anchorFrame, relPoint or anchorPoint, xOff, yOff)

    local cbBg = cb:CreateTexture(nil, "BORDER")
    cbBg:SetAllPoints(cb)
    cbBg:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cbBg:SetAlpha(0.8)

    local cbCheck = cb:CreateTexture(nil, "ARTWORK")
    cbCheck:SetWidth(14)
    cbCheck:SetHeight(14)
    cbCheck:SetPoint("CENTER", cb, "CENTER", 0, 0)
    cbCheck:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cbCheck:Hide()
    cb._checkTex = cbCheck

    local cbLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cbLabel:SetPoint("RIGHT", cb, "LEFT", -4, 0)
    cbLabel:SetPoint("TOP", cb, "TOP", 0, 0)
    cbLabel:SetPoint("BOTTOM", cb, "BOTTOM", 0, 0)
    cbLabel:SetJustifyH("RIGHT")
    cbLabel:SetJustifyV("MIDDLE")
    cbLabel:SetText("Multi-Rank")
    cbLabel:SetTextColor(0.8, 0.8, 0.8)
    missingMultiRankFilterLabel = cbLabel

    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Multi-Rank Filter", 1, 0.82, 0)
        local mode = missingMultipleRanksFilter
        if mode == "only" then
            GameTooltip:AddLine("Showing multi-rank echoes only.", 0.8, 0.8, 0.8, true)
        elseif mode == "exclude" then
            GameTooltip:AddLine("Hiding multi-rank echoes.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("No multi-rank filter active.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:AddLine("Click to cycle filter.", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cb:SetScript("OnClick", function()
        CycleMissingMultiRankFilter()
        RefreshMissing()
    end)

    missingMultiRankFilterCb = cb
    SyncMissingMultiRankFilterUI()
    return cb, cbLabel
end

local missingSourceDropdown

local function SyncMissingSourceFilterUI()
    if not missingSourceDropdown then return end
    local label = EbonBuilds.EchoSources
        and EbonBuilds.EchoSources.FilterLabel(missingSourceFilter)
        or "All sources"
    UIDropDownMenu_SetText(missingSourceDropdown, label)
end

local function CreateMissingSourceDropdown(parent)
    local dropdown = CreateFrame("Frame", "EbonBuildsMissingSourceDD", parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dropdown, 110)

    local function UpdateLabel()
        SyncMissingSourceFilterUI()
    end

    UIDropDownMenu_Initialize(dropdown, function(_, level)
        local clearInfo = UIDropDownMenu_CreateInfo()
        clearInfo.text = "Clear all filters"
        clearInfo.notCheckable = true
        clearInfo.func = function()
            if EbonBuilds.EchoSources then
                EbonBuilds.EchoSources.ClearSelection(missingSourceFilter)
            else
                for key in pairs(missingSourceFilter) do
                    missingSourceFilter[key] = nil
                end
            end
            UpdateLabel()
            PersistMissingFilterPrefs()
            RefreshMissing()
        end
        UIDropDownMenu_AddButton(clearInfo, level)

        if not EbonBuilds.EchoSources or not EbonBuilds.EchoSources.FILTER_OPTIONS then return end
        local options = EbonBuilds.EchoSources.FILTER_OPTIONS
        local lastKind = nil
        for i = 1, #options do
            local opt = options[i]
            if opt.kind ~= lastKind then
                local header = UIDropDownMenu_CreateInfo()
                header.isTitle = true
                header.notCheckable = true
                if opt.kind == "special" then
                    header.text = "Other"
                elseif opt.kind == "open_world" then
                    header.text = "Open World"
                elseif opt.kind == "raid" then
                    header.text = "Raids"
                else
                    header.text = "Other"
                end
                UIDropDownMenu_AddButton(header, level)
                lastKind = opt.kind
            end
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.isNotRadio = true
            info.keepShownOnClick = true
            info.arg1 = opt.key
            info.checked = missingSourceFilter[opt.key] and true or false
            info.func = function(_, key)
                if missingSourceFilter[key] then
                    missingSourceFilter[key] = nil
                else
                    missingSourceFilter[key] = true
                end
                UpdateLabel()
                PersistMissingFilterPrefs()
                RefreshMissing()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    missingSourceDropdown = dropdown
    UpdateLabel()
    return dropdown
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

local function SyncRolledDisplay(frame, isRolled)
    if not frame then return end
    frame:Show()
    frame._bg:Show()
    if isRolled then
        frame._check:Show()
    else
        frame._check:Hide()
    end
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

    local bg = frame:CreateTexture(nil, "BORDER")
    bg:SetSize(16, 16)
    bg:SetPoint("CENTER", frame, "CENTER", 0, 0)
    bg:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
    bg:SetAlpha(0.8)
    frame._bg = bg

    local check = frame:CreateTexture(nil, "ARTWORK")
    check:SetSize(14, 14)
    check:SetPoint("CENTER", bg, "CENTER", 0, 0)
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:Hide()
    frame._check = check

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
        btn._echoHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    local headerRow = CreateFrame("Frame", nil, parent)
    headerRow:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
    headerRow:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, -10)
    headerRow:SetHeight(44)

    local searchFrame = CreateFrame("Frame", nil, headerRow)
    searchFrame:SetPoint("TOPLEFT", headerRow, "TOPLEFT", 0, 0)
    searchFrame:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
    searchFrame:SetHeight(22)
    searchFrame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    searchFrame:SetBackdropColor(0, 0, 0, 0.6)
    searchFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local searchEdit = CreateFrame("EditBox", nil, searchFrame)
    searchEdit:SetHeight(18)
    searchEdit:SetPoint("LEFT", searchFrame, "LEFT", 4, 0)
    searchEdit:SetPoint("RIGHT", searchFrame, "RIGHT", -4, 0)
    searchEdit:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    searchEdit:SetTextColor(1, 1, 1, 1)
    searchEdit:SetAutoFocus(false)
    searchEdit:SetMaxLetters(60)
    searchEdit:SetScript("OnTextChanged", function(self)
        missingSearchText = self:GetText():lower()
        RefreshMissing()
    end)
    searchEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local sourceDropdown = CreateMissingSourceDropdown(headerRow)
    sourceDropdown:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
    searchFrame:SetPoint("TOPRIGHT", sourceDropdown, "TOPLEFT", -8, 0)

    local filterRow = CreateFrame("Frame", nil, headerRow)
    filterRow:SetPoint("TOPLEFT", searchFrame, "BOTTOMLEFT", 0, -2)
    filterRow:SetPoint("TOPRIGHT", searchFrame, "BOTTOMRIGHT", 0, -2)
    filterRow:SetHeight(22)

    local classCb, classLabel = CreateFilterCheckbox(filterRow, "Show All Classes", nil, filterRow, "RIGHT", 0, 0, function()
        missingShowAllClasses = not missingShowAllClasses
        return missingShowAllClasses
    end)

    missingTomeFilterCb, tomeLabel = CreateMissingTomeCycleCheckbox(filterRow, classLabel, "LEFT", -16, 0, "LEFT")

    CreateMissingMultiRankCycleCheckbox(filterRow, tomeLabel, "LEFT", -16, 0, "LEFT")

    local echoJournalBtn = CreateFrame("Button", nil, filterRow, "UIPanelButtonTemplate")
    echoJournalBtn:SetSize(110, 20)
    echoJournalBtn:SetPoint("LEFT", filterRow, "LEFT", 0, 0)
    echoJournalBtn:SetText("Echo Journal")
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

    LoadMissingFilterPrefs()
    SyncMissingTomeFilterUI()
    SyncMissingMultiRankFilterUI()
    SyncMissingSourceFilterUI()

    missingColumnHeader = CreateFrame("Frame", nil, parent)
    missingColumnHeader:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -6)
    missingColumnHeader:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, -6)
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

    local scroll, child, bar, syncWidth, wireWheel = CreateOverviewScrollFrame(parent)
    scroll:SetPoint("TOPLEFT", missingColumnHeader, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -18, 8)

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
local overviewDescSmf, overviewDescMeasure, overviewDescScroll, overviewDescChild, overviewDescBar
local statsValueLabels, statsQualityLabels
local missingScroll, missingChild, missingBar
local missingWireWheel
local missingRows = {}

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
    overviewDescSmf:Clear()
    overviewDescSmf:AddMessage(desc, 0.8, 0.8, 0.8, 1.0)
    overviewDescMeasure:SetText(desc)

    local slotCount = (EbonBuilds.Build and EbonBuilds.Build.GetLockedSlotCount and EbonBuilds.Build.GetLockedSlotCount()) or 5
    for i = 1, #overviewOuter._lockedButtons do
        local btn = overviewOuter._lockedButtons[i]
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

    -- Adjust description scroll range
    local textHeight = overviewDescMeasure:GetStringHeight() or 0
    overviewDescSmf:SetHeight(math.max(textHeight + 4, 14))
    overviewDescChild:SetHeight(math.max(textHeight + 6, overviewDescScroll:GetHeight()))
    overviewDescBar:SetMinMaxValues(0, math.max(0, overviewDescChild:GetHeight() - overviewDescScroll:GetHeight()))
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
    statsValueLabels.mostPicked:SetText(topPicked or "-")
    local topBanned = EbonBuilds.Build.TopEchoStatName and EbonBuilds.Build.TopEchoStatName(st.mostBanned)
        or nil
    statsValueLabels.mostBanned:SetText(topBanned or "-")
end

function EbonBuilds.BuildOverview.NotifyStatsChanged()
    if activeOverviewTab == 2 then
        RefreshStats()
    end
end

RefreshMissing = function()
    local build = state.build
    if not build or not missingChild then return end
    for _, btn in ipairs(missingRows) do btn:Hide() end
    local missing = ComputeMissingEchoes(build, {
        showAllClasses = missingShowAllClasses,
    })
    if missing == nil then
        missingChild.loadingLabel = missingChild.loadingLabel or missingChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        missingChild.loadingLabel:SetPoint("TOPLEFT", missingChild, "TOPLEFT", 4, -2)
        missingChild.loadingLabel:SetText("Requesting data...")
        missingChild.loadingLabel:Show()
        missingChild:SetHeight(20)
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
        missingBar:SetMinMaxValues(0, 0)
        return
    end

    local currY = 0
    for i, entry in ipairs(filtered) do
        local rowIdx = i
        while #missingRows < rowIdx do
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
            btn._labelSource = labelSource
            local labelBaseWeight = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn._labelBaseWeight = labelBaseWeight
            local labelScore = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn._labelScore = labelScore
            LayoutMissingRow(btn)
            missingRows[n] = btn
        end
        local btn = missingRows[rowIdx]
        if btn._labelWeight then btn._labelWeight:Hide() end
        LayoutMissingRow(btn)
        btn._spellId = entry.spellId
        btn._icon:SetTexture(select(3, GetSpellInfo(entry.spellId)))
        local cc = QUALITY_COLORS[entry.quality] or QUALITY_COLORS[0]
        btn._labelName:SetText(entry.name)
        btn._labelName:SetTextColor(cc[1], cc[2], cc[3], 1)
        local cleanSource = (entry.dropSource or ""):gsub("^Can be found on ", "")
        btn._sourceText = cleanSource
        btn._labelSource:SetText(cleanSource)
        btn._labelBaseWeight:SetText(tostring(entry.baseWeight or 0))
        btn._labelScore:SetText(string.format("%.0f", entry.score))
        if EbonBuilds.EchoTableRows.SyncTomeOwnedDisplay then
            EbonBuilds.EchoTableRows.SyncTomeOwnedDisplay(btn._tomeOwned, {
                name = entry.name,
                spellId = entry.spellId,
                groupId = entry.groupId,
                tomeSpellId = entry.tomeSpellId,
                owned = entry.owned,
            })
        end
        if btn._rolledDisplay then
            btn._rolledDisplay._isRolled = entry.rolled
            SyncRolledDisplay(btn._rolledDisplay, entry.rolled)
        end
        local srcH = btn._labelSource:GetStringHeight() or 16
        local rowH = math.max(26, srcH + 4)
        btn:SetHeight(rowH)
        btn:SetPoint("TOPLEFT", missingChild, "TOPLEFT", 0, -currY)
        btn:SetPoint("RIGHT", missingChild, "RIGHT", 0, 0)
        btn:Show()
        if missingWireWheel then
            missingWireWheel(btn)
            if btn._tomeOwned then missingWireWheel(btn._tomeOwned) end
            if btn._rolledDisplay then missingWireWheel(btn._rolledDisplay) end
        end
        currY = currY + rowH + 2
    end
    missingChild:SetHeight(math.max(1, currY))
    missingBar:SetMinMaxValues(0, math.max(0, missingChild:GetHeight() - missingScroll:GetHeight()))
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
    local outer = CreateFrame("Frame", nil, parent)
    outer:SetAllPoints(parent)

    local hint = outer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", outer, "TOPLEFT", 10, -8)
    hint:SetPoint("RIGHT", outer, "RIGHT", -10, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Echoes with banish or ignore automation policies. Change policy here or in the Echoes tab.")

    local listArea = CreateFrame("Frame", nil, outer)
    listArea:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -8)
    listArea:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT", -4, 4)

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
        if banishBar then banishBar:SetMinMaxValues(0, 0) end
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
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
        banishBar:SetMinMaxValues(0, math.max(0, banishChild:GetHeight() - banishScroll:GetHeight()))
    end
end

------------------------------------------------------------------------
-- Logbook tab
------------------------------------------------------------------------

local function BuildLogbookTab(parent)
    EbonBuilds.SessionHistory.Show(parent)
end

------------------------------------------------------------------------
-- BuildViewFrame
------------------------------------------------------------------------

local switchOverview, switchStats, switchMissing, switchBanish, switchLogbook, switchAffixes
local affixParent
local missingParent

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
    overviewOuter, overviewDescSmf, overviewDescMeasure, overviewDescScroll, overviewDescChild, overviewDescBar = BuildOverviewTab(contentArea)

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

    -- Build Stats tab content (hidden by default)
    local statsParent = CreateFrame("Frame", nil, contentArea)
    statsParent:SetAllPoints(contentArea)
    statsParent:Hide()
    statsValueLabels, statsQualityLabels = BuildStatsTab(statsParent)

    -- Echoes tab content (hidden by default)
    missingParent = CreateFrame("Frame", nil, contentArea)
    missingParent:SetAllPoints(contentArea)
    missingParent:Hide()
    missingScroll, missingChild, missingBar, missingWireWheel = BuildMissingTab(missingParent)

    local banishParent = CreateFrame("Frame", nil, contentArea)
    banishParent:SetAllPoints(contentArea)
    banishParent:Hide()
    BuildBanishTab(banishParent)

    -- Build Logbook tab content (hidden by default)
    local logbookParent = CreateFrame("Frame", nil, contentArea)
    logbookParent:SetAllPoints(contentArea)
    logbookParent:Hide()
    BuildLogbookTab(logbookParent)

    affixParent = CreateFrame("Frame", nil, contentArea)
    affixParent:SetAllPoints(contentArea)
    affixParent:Hide()

    -- Hide all tab content
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
    end

    -- Tab switching functions (defined after content so refs are valid)
    switchOverview = function()
        HideAllContent()
        overviewOuter:Show()
        overviewOuter._deleteBtn:Show()
        activeOverviewTab = 1
        PanelTemplates_SetTab(f, 1)
        PanelTemplates_EnableTab(f, 2)
        PanelTemplates_EnableTab(f, 3)
        PanelTemplates_EnableTab(f, 4)
        PanelTemplates_EnableTab(f, 5)
        PanelTemplates_EnableTab(f, 6)
        RefreshOverview()
    end

    switchStats = function()
        HideAllContent()
        overviewOuter._deleteBtn:Hide()
        statsParent:Show()
        activeOverviewTab = 2
        PanelTemplates_SetTab(f, 2)
        PanelTemplates_EnableTab(f, 1)
        PanelTemplates_EnableTab(f, 3)
        PanelTemplates_EnableTab(f, 4)
        PanelTemplates_EnableTab(f, 5)
        PanelTemplates_EnableTab(f, 6)
        RefreshStats()
    end

    switchMissing = function()
        HideAllContent()
        overviewOuter._deleteBtn:Hide()
        missingParent:Show()
        activeOverviewTab = 3
        PanelTemplates_SetTab(f, 3)
        PanelTemplates_EnableTab(f, 1)
        PanelTemplates_EnableTab(f, 2)
        PanelTemplates_EnableTab(f, 4)
        PanelTemplates_EnableTab(f, 5)
        PanelTemplates_EnableTab(f, 6)
        SyncMissingTomeFilterUI()
        RefreshMissing()
    end

    switchBanish = function()
        HideAllContent()
        overviewOuter._deleteBtn:Hide()
        banishParent:Show()
        activeOverviewTab = 4
        PanelTemplates_SetTab(f, 4)
        PanelTemplates_EnableTab(f, 1)
        PanelTemplates_EnableTab(f, 2)
        PanelTemplates_EnableTab(f, 3)
        PanelTemplates_EnableTab(f, 5)
        PanelTemplates_EnableTab(f, 6)
        RefreshBanish()
    end

    switchLogbook = function()
        HideAllContent()
        overviewOuter._deleteBtn:Hide()
        logbookParent:Show()
        activeOverviewTab = 5
        PanelTemplates_SetTab(f, 5)
        PanelTemplates_EnableTab(f, 1)
        PanelTemplates_EnableTab(f, 2)
        PanelTemplates_EnableTab(f, 3)
        PanelTemplates_EnableTab(f, 4)
        PanelTemplates_EnableTab(f, 6)
        EbonBuilds.SessionHistory.Show(logbookParent)
    end

    switchAffixes = function()
        HideAllContent()
        overviewOuter._deleteBtn:Hide()
        affixParent:Show()
        activeOverviewTab = 6
        PanelTemplates_SetTab(f, 6)
        PanelTemplates_EnableTab(f, 1)
        PanelTemplates_EnableTab(f, 2)
        PanelTemplates_EnableTab(f, 3)
        PanelTemplates_EnableTab(f, 4)
        PanelTemplates_EnableTab(f, 5)
        EbonBuilds.AffixView.SetOverviewBuild(state.build)
        EbonBuilds.AffixView.Mount(affixParent, { build = state.build })
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
    tab3:SetText("Collection")
    tab3:SetPoint("LEFT", tab2, "RIGHT", -16, 0)
    PanelTemplates_TabResize(tab3, 0)
    tab3:SetScript("OnClick", function() if switchMissing then switchMissing() end end)

    tab4 = CreateFrame("Button", "EbonBuildsBuildOverviewTab4", f, "OptionsFrameTabButtonTemplate")
    tab4:SetID(4)
    tab4:SetText("Policies")
    tab4:SetPoint("LEFT", tab3, "RIGHT", -16, 0)
    PanelTemplates_TabResize(tab4, 0)
    tab4:SetScript("OnClick", function() if switchBanish then switchBanish() end end)

    tab5 = CreateFrame("Button", "EbonBuildsBuildOverviewTab5", f, "OptionsFrameTabButtonTemplate")
    tab5:SetID(5)
    tab5:SetText("Logbook")
    tab5:SetPoint("LEFT", tab4, "RIGHT", -16, 0)
    PanelTemplates_TabResize(tab5, 0)
    tab5:SetScript("OnClick", function() if switchLogbook then switchLogbook() end end)

    tab6 = CreateFrame("Button", "EbonBuildsBuildOverviewTab6", f, "OptionsFrameTabButtonTemplate")
    tab6:SetID(6)
    tab6:SetText("Affixes")
    tab6:SetPoint("LEFT", tab5, "RIGHT", -16, 0)
    PanelTemplates_TabResize(tab6, 0)
    tab6:SetScript("OnClick", function() if switchAffixes then switchAffixes() end end)

    PanelTemplates_SetNumTabs(f, 6)
    PanelTemplates_SetTab(f, 1)

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

    local refreshFrame = CreateFrame("Frame")
    refreshFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    refreshFrame:SetScript("OnEvent", function()
        if EbonBuilds.EchoOwnership then
            EbonBuilds.EchoOwnership.Invalidate()
        end
        RefreshCollectionIfVisible()
    end)

    local collectionRefreshTicker = CreateFrame("Frame")
    collectionRefreshTicker.elapsed = 0
    collectionRefreshTicker:SetScript("OnUpdate", function(self, dt)
        if not IsCollectionTabVisible() then
            self.elapsed = 0
            return
        end
        self.elapsed = self.elapsed + dt
        if self.elapsed >= 2 then
            self.elapsed = 0
            if RefreshMissing then RefreshMissing() end
        end
    end)

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
