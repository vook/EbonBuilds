-- EbonBuilds: modules/ui/BuildOverview.lua
-- Responsibility: build overview dashboard with tabs (Overview + Stats +
-- Missing + Logbook). Registered as "buildOverview" view. Shows build metadata,
-- locked echoes, automation toggle, runtime statistics, and missing echoes.

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
local tab1, tab2, tab3, tab4
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

local function ComputeMissingEchoes(build)
    if not build or not build.class then return nil end

    local classMask = CLASS_MASK[build.class] or 0
    local playerLevel = UnitLevel("player")

    -- Read the spellbook's "Echoes" tab to find locked echo spells.
    -- Spellbook spellIds are in the 300xxx range (Tome spells). The actual echo
    -- data lives in PerkDatabase under 200xxx spellIds. We resolve via
    -- PerkDatabase[spellId].requiredSpell matching the spellbook spellId,
    -- or by subtracting 100000 as fallback.
    local ownedLower = {}
    local ownedGroups = {}
    local spellbookIds = {}
    local numTabs = GetNumSpellTabs and GetNumSpellTabs() or 0
    for tabIdx = 1, numTabs do
        local tabName, _, offset, numSpells = GetSpellTabInfo(tabIdx)
        if tabName == "Echoes" then
            for slot = offset + 1, offset + numSpells do
                local link = GetSpellLink(slot, "spell")
                local tomeSpellId = link and tonumber(link:match("spell:(%d+)"))
                if tomeSpellId then
                    spellbookIds[tomeSpellId] = true
                end
            end
            break
        end
    end

    -- Resolve each spellbook spell to its PerkDatabase echo entry,
    -- then build owned sets from the echo's name + groupId.
    for spellId, data in pairs(ProjectEbonhold.PerkDatabase) do
        local isOwned = spellbookIds[data.requiredSpell] or spellbookIds[spellId + 100000]
        if isOwned then
            local name = GetSpellInfo(spellId)
            local norm = NormalizeEchoName(name)
            if norm then ownedLower[norm] = true end
            if data.groupId then ownedGroups[data.groupId] = true end
        end
    end

    -- Also mark echoes owned via granted perks (catches echoes without a
    -- required tome, which aren't visible in the spellbook).
    if ProjectEbonhold.PerkService.GetGrantedPerks then
        local granted = ProjectEbonhold.PerkService.GetGrantedPerks()
        for name in pairs(granted or {}) do
            local norm = NormalizeEchoName(name)
            if norm then ownedLower[norm] = true end
        end
    end

    -- Build locked echo name set for priority sorting
    local lockedLower = {}
    if build.lockedEchoes then
        for _, spellId in ipairs(build.lockedEchoes) do
            if spellId then
                local name = GetSpellInfo(spellId)
                if name then lockedLower[NormalizeEchoName(name)] = true end
            end
        end
    end

    -- Group by spell name, keep highest quality per name
    local byName = {}
    for spellId, data in pairs(ProjectEbonhold.PerkDatabase) do
        local spellName = GetSpellInfo(spellId)
        if spellName then
            local key = NormalizeEchoName(spellName)
            local isOwned = ownedLower[key] or (data.groupId and ownedGroups[data.groupId])
            if not isOwned then
                if classMask == 0 or bit.band(data.classMask or 0, classMask) ~= 0 then
                    if not data.minLevel or playerLevel >= data.minLevel then
                        local existing = byName[key]
                        if not existing or (data.quality or 0) > (existing.quality or 0) then
                            byName[key] = { spellId = spellId, data = data, displayName = spellName }
                        end
                    end
                end
            end
        end
    end

    -- Collect missing echoes (only those with known drop source, exclude banned)
    local settings = build.settings or EbonBuilds.Build.DefaultSettings()
    local banList = settings.echoBanList or {}
    local weights = build.echoWeights or {}
    local missing = {}
    for key, entry in pairs(byName) do
        local source = ProjectEbonhold.PerkDropSources and ProjectEbonhold.PerkDropSources[entry.spellId]
        if not source and entry.data.groupId and ProjectEbonhold.PerkDropSourceByGroup then
            source = ProjectEbonhold.PerkDropSourceByGroup[entry.data.groupId]
        end
        local needsTome = entry.data.requiredSpell and entry.data.requiredSpell > 0
        if not banList[entry.spellId] and needsTome then
            -- Build scoring entry
            local scoringEntry = {
                spellId = entry.spellId,
                name = entry.displayName,
                quality = entry.data.quality or 0,
                families = entry.data.families,
                classMask = entry.data.classMask,
            }
            local weight = weights[entry.displayName] or 0
            local score = EbonBuilds.Scoring.Score(scoringEntry, weight, settings)
            missing[#missing + 1] = {
                spellId = entry.spellId,
                name = entry.displayName,
                quality = entry.data.quality or 0,
                dropSource = source or "Unknown",
                isLocked = lockedLower[key] or false,
                score = score,
            }
        end
    end

    -- Sort: locked echoes first, then score desc, then quality desc, then name asc
    table.sort(missing, function(a, b)
        if a.isLocked ~= b.isLocked then
            return a.isLocked
        end
        if a.score ~= b.score then
            return a.score > b.score
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
    nameLabel:SetPoint("RIGHT",   outer,     "RIGHT",     -10, 0)
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
    lockedHeader:SetPoint("TOPLEFT", metaLabel, "BOTTOMLEFT", 0, -18)
    lockedHeader:SetText("Locked Echoes:")
    outer._lockedHeader = lockedHeader

    local lockedButtons = {}
    for i = 1, 4 do
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
    descScroll:SetPoint("BOTTOMRIGHT", outer,      "BOTTOMRIGHT", -22, 28)

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

------------------------------------------------------------------------
-- Missing tab
------------------------------------------------------------------------

local function BuildMissingTab(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT",     parent, "TOPLEFT",     10, -14)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -18, 8)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(460)
    child:SetHeight(1)
    scroll:SetScrollChild(child)

    local bar = CreateFrame("Slider", nil, scroll, "UIPanelScrollBarTemplate")
    bar:SetPoint("TOPLEFT",    scroll, "TOPRIGHT",    -2, -4)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -2,  4)
    bar:SetValueStep(16)

    bar:SetScript("OnValueChanged", function(self, value)
        child:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, value)
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local v = bar:GetValue()
        local mn, mx = bar:GetMinMaxValues()
        bar:SetValue(math.max(mn, math.min(mx, v - delta * 16)))
    end)

    return scroll, child, bar
end

------------------------------------------------------------------------
-- Logbook tab
------------------------------------------------------------------------

local function BuildLogbookTab(parent)
    EbonBuilds.SessionHistory.Show(parent)
end

------------------------------------------------------------------------
-- Tab switching
------------------------------------------------------------------------

local overviewOuter
local overviewDescText, overviewDescScroll, overviewDescChild, overviewDescBar
local statsValueLabels, statsQualityLabels
local missingScroll, missingChild, missingBar
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
    overviewDescText:SetText(desc)

    for i = 1, 4 do
        local btn = overviewOuter._lockedButtons[i]
        local spellId = build.lockedEchoes and build.lockedEchoes[i]
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

local QUALITY_COLORS = {
    [0] = { 1.0, 1.0, 1.0 },
    [1] = { 30/255, 1.0, 0.0 },
    [2] = { 0.0, 112/255, 221/255 },
    [3] = { 163/255, 53/255, 238/255 },
    [4] = { 1.0, 128/255, 0.0 },
}

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

local function RefreshMissing()
    local build = state.build
    if not build or not missingChild then return end
    for _, btn in ipairs(missingRows) do btn:Hide() end
    local missing = ComputeMissingEchoes(build)
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
    local currY = 0
    for _, entry in ipairs(missing) do
        local rowIdx = #missingRows + 1
        while #missingRows < rowIdx do
            local n = #missingRows + 1
            local btn = CreateFrame("Button", nil, missingChild)
            btn:SetPoint("LEFT", missingChild, "LEFT", 4, 0)
            btn:SetPoint("RIGHT", missingChild, "RIGHT", -4, 0)
            btn:RegisterForClicks("LeftButtonUp")
            btn:SetScript("OnEnter", function(self)
                if not self._spellId then return end
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:ClearLines()
                local spellName = GetSpellInfo(self._spellId)
                if spellName then
                    GameTooltip:AddLine(spellName, 1, 0.82, 0)
                end
                if utils and utils.GetSpellDescription then
                    local desc = utils.GetSpellDescription(self._spellId, 500, 1)
                    if desc and desc ~= "" then
                        GameTooltip:AddLine(desc, 1, 1, 1, true)
                    end
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            -- Icon
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetWidth(24)
            icon:SetHeight(24)
            icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn._icon = icon
            -- Name column
            local labelName = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            labelName:SetPoint("TOPLEFT", icon, "TOPRIGHT", 2, 0)
            labelName:SetWidth(160)
            labelName:SetJustifyH("LEFT")
            btn._labelName = labelName
            -- Drop Source column
            local labelSource = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            labelSource:SetPoint("TOPLEFT", labelName, "TOPRIGHT", 4, 0)
            labelSource:SetWidth(200)
            labelSource:SetJustifyH("LEFT")
            labelSource:SetTextColor(0.6, 0.6, 0.6, 1)
            btn._labelSource = labelSource
            -- Score column
            local labelScore = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            labelScore:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, -2)
            labelScore:SetWidth(54)
            labelScore:SetJustifyH("RIGHT")
            btn._labelScore = labelScore
            missingRows[n] = btn
        end
        local btn = missingRows[rowIdx]
        btn:ClearAllPoints()
        btn._spellId = entry.spellId
        btn._icon:SetTexture(select(3, GetSpellInfo(entry.spellId)))
        local cc = QUALITY_COLORS[entry.quality] or QUALITY_COLORS[0]
        btn._labelName:SetText(entry.name)
        btn._labelName:SetTextColor(cc[1], cc[2], cc[3], 1)
        local cleanSource = (entry.dropSource or ""):gsub("^Can be found on ", "")
        btn._labelSource:SetText(cleanSource)
        btn._labelScore:SetText(string.format("%.0f", entry.score))
        local srcH = btn._labelSource:GetStringHeight() or 16
        local rowH = math.max(26, srcH + 4)
        btn:SetHeight(rowH)
        btn:SetPoint("TOPLEFT", missingChild, "TOPLEFT", 0, -currY)
        btn:SetPoint("RIGHT", missingChild, "RIGHT", -4, 0)
        btn:Show()
        currY = currY + rowH + 2
    end
    missingChild:SetHeight(math.max(1, currY))
    missingBar:SetMinMaxValues(0, math.max(0, missingChild:GetHeight() - missingScroll:GetHeight()))
end
------------------------------------------------------------------------
-- BuildViewFrame
------------------------------------------------------------------------

local switchOverview, switchStats, switchMissing, switchLogbook

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

    -- Missing Echoes tab content (hidden by default)
    local missingParent = CreateFrame("Frame", nil, contentArea)
    missingParent:SetAllPoints(contentArea)
    missingParent:Hide()
    missingScroll, missingChild, missingBar = BuildMissingTab(missingParent)

    -- Build Logbook tab content (hidden by default)
    local logbookParent = CreateFrame("Frame", nil, contentArea)
    logbookParent:SetAllPoints(contentArea)
    logbookParent:Hide()
    BuildLogbookTab(logbookParent)

    -- Hide all tab content
    local function HideAllContent()
        overviewOuter:Hide()
        statsParent:Hide()
        missingParent:Hide()
        logbookParent:Hide()
    end

    -- Tab switching functions (defined after content so refs are valid)
    switchOverview = function()
        HideAllContent()
        overviewOuter:Show()
        overviewOuter._deleteBtn:Show()
        PanelTemplates_SetTab(f, 1)
        PanelTemplates_EnableTab(f, 2)
        PanelTemplates_EnableTab(f, 3)
        PanelTemplates_EnableTab(f, 4)
        RefreshOverview()
    end

    switchStats = function()
        HideAllContent()
        overviewOuter._deleteBtn:Hide()
        statsParent:Show()
        PanelTemplates_SetTab(f, 2)
        PanelTemplates_EnableTab(f, 1)
        PanelTemplates_EnableTab(f, 3)
        PanelTemplates_EnableTab(f, 4)
        RefreshStats()
    end

    switchMissing = function()
        HideAllContent()
        overviewOuter._deleteBtn:Hide()
        missingParent:Show()
        PanelTemplates_SetTab(f, 3)
        PanelTemplates_EnableTab(f, 1)
        PanelTemplates_EnableTab(f, 2)
        PanelTemplates_EnableTab(f, 4)
        RefreshMissing()
    end

    switchLogbook = function()
        HideAllContent()
        overviewOuter._deleteBtn:Hide()
        logbookParent:Show()
        PanelTemplates_SetTab(f, 4)
        PanelTemplates_EnableTab(f, 1)
        PanelTemplates_EnableTab(f, 2)
        PanelTemplates_EnableTab(f, 3)
        EbonBuilds.SessionHistory.Show(logbookParent)
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
    tab3:SetText("Missing")
    tab3:SetPoint("LEFT", tab2, "RIGHT", -16, 0)
    PanelTemplates_TabResize(tab3, 0)
    tab3:SetScript("OnClick", function() if switchMissing then switchMissing() end end)

    tab4 = CreateFrame("Button", "EbonBuildsBuildOverviewTab4", f, "OptionsFrameTabButtonTemplate")
    tab4:SetID(4)
    tab4:SetText("Logbook")
    tab4:SetPoint("LEFT", tab3, "RIGHT", -16, 0)
    PanelTemplates_TabResize(tab4, 0)
    tab4:SetScript("OnClick", function() if switchLogbook then switchLogbook() end end)

    PanelTemplates_SetNumTabs(f, 4)
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
