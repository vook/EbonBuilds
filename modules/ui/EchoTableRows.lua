-- EbonBuilds: modules/ui/EchoTableRows.lua
-- Responsibility: data preparation and row-frame factory for EchoTable.
--
-- Layout (per-quality expanded rows):
--   [icon] Echo Name                         [base weight]
--     · Common                   [score]     [weight override]
--     · Rare                     [score]     [weight override]
--   [icon] Next Echo Name                    [base weight]
--   ...
--
-- Entries produced by BuildSortedList:
--   { name, spellId, quality, qualityTier, families, classMask,
--     qualities, spellIds, requiresTome,
--     isGroupHeader (bool), isSubRow (bool) }

EbonBuilds.EchoTableRows = {}

local C = EbonBuilds.EchoTableColumns
local COL_ICON      = C.COL_ICON
local COL_WEIGHT    = C.COL_WEIGHT
local COL_SCORE     = C.COL_SCORE
local COL_POLICY    = C.COL_POLICY
local COL_TOME      = C.COL_TOME
local ROW_HEIGHT    = 32   -- header / single rows
local SUBROW_HEIGHT = 28   -- per-quality rows
local WEIGHT_MAX    = (EbonBuilds.Weights and EbonBuilds.Weights.MAX) or 100

local onWeightChanged = nil
local policyDdSerial = 0
local scrollWheelForward = nil

function EbonBuilds.EchoTableRows.SetOnWeightChanged(fn)
    onWeightChanged = fn
end

function EbonBuilds.EchoTableRows.SetScrollWheelForward(fn)
    scrollWheelForward = fn
end

local function WireScrollWheelPassthrough(frame)
    if not frame or not scrollWheelForward or frame._ebonScrollWheelPass then return end
    frame._ebonScrollWheelPass = true
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        scrollWheelForward(delta)
    end)
end

local function WireRowScrollPassthrough(row)
    if not row then return end
    WireScrollWheelPassthrough(row)
    WireScrollWheelPassthrough(row.iconFrame)
    WireScrollWheelPassthrough(row.nameHitbox)
    WireScrollWheelPassthrough(row.qualHitbox)
    WireScrollWheelPassthrough(row.policyDd)
    WireScrollWheelPassthrough(row.tomeOwned)
    if row.weightBox then
        WireScrollWheelPassthrough(row.weightBox)
        local container = row.weightBox:GetParent()
        if container and container ~= row then
            WireScrollWheelPassthrough(container)
        end
    end
end

local QUALITY_COLORS = {
    [0] = "ffffff", [1] = "19ff19", [2] = "0066ff", [3] = "cc66ff", [4] = "ff8000",
}

local QUALITY_NAMES = {
    [0] = "Common", [1] = "Uncommon", [2] = "Rare", [3] = "Epic", [4] = "Legendary",
}

-- Data preparation -----------------------------------------------------

local QUALITY_SUFFIX_NAMES = { "common", "uncommon", "rare", "epic", "legendary" }

local function StripQualitySuffix(name)
    if not name then return name end
    local base, suffix = name:match("^(.+) %- (.+)$")
    if base and suffix then
        local lower = string.lower(suffix)
        for _, q in ipairs(QUALITY_SUFFIX_NAMES) do
            if lower == q then
                return base
            end
        end
    end
    return name
end

local function GetPerkDatabase()
    if EbonBuilds.EchoOwnership and EbonBuilds.EchoOwnership.GetPerkDatabase then
        return EbonBuilds.EchoOwnership.GetPerkDatabase()
    end
    return ProjectEbonhold and ProjectEbonhold.PerkDatabase
end

local function BuildBestByName()
    local best = {}
    local db = GetPerkDatabase()
    if not db then return best end
    for spellId, data in pairs(db) do
        local raw = data.comment
        if raw and raw ~= "" then
            local name = StripQualitySuffix(raw)
            local existing = best[name]
            local mask = data.classMask or 0
            if not existing then
                existing = {
                    spellId = spellId, quality = data.quality, qualities = {},
                    families = data.families or {}, classMask = mask, spellIds = {},
                    requiresTome = false, tomeSpellId = nil,
                    groupId = data.groupId, requiredSpell = data.requiredSpell,
                }
                best[name] = existing
            else
                existing.classMask = bit.bor(existing.classMask or 0, mask)
                if data.quality > existing.quality then
                    existing.spellId  = spellId
                    existing.quality  = data.quality
                    existing.families = data.families or {}
                    existing.groupId = data.groupId
                    existing.requiredSpell = data.requiredSpell
                elseif not existing.groupId and data.groupId then
                    existing.groupId = data.groupId
                end
            end
            local rs = data.requiredSpell
            if rs and rs ~= 0 then
                existing.requiresTome = true
                if rs ~= 9 then
                    if not existing.tomeSpellId or (data.quality or 0) > (existing.tomeQuality or -1) then
                        existing.tomeSpellId = rs
                        existing.tomeQuality = data.quality
                    end
                end
            end
            existing.qualities[data.quality] = true
            existing.spellIds[data.quality] = spellId
        end
    end
    return best
end

EbonBuilds.EchoTableRows.BuildBestByName = BuildBestByName

local bestByNameCache = nil
local sortedListCache = nil

local function GetBestByName()
    if not bestByNameCache then
        bestByNameCache = BuildBestByName()
        sortedListCache = nil
    end
    return bestByNameCache
end

function EbonBuilds.EchoTableRows.GetBestByName()
    return GetBestByName()
end

function EbonBuilds.EchoTableRows.InvalidateCaches()
    bestByNameCache = nil
    sortedListCache = nil
    if EbonBuilds.EchoSearch and EbonBuilds.EchoSearch.InvalidateCache then
        EbonBuilds.EchoSearch.InvalidateCache()
    end
end

-- Legacy no-op: echoes are no longer tracked via spellbook tomes.
function EbonBuilds.EchoTableRows.InvalidateTomeCache()
end

-- Missing targets: echoes that need a tome count only when that echo is account-owned.
function EbonBuilds.EchoTableRows.IsEchoTomeOwnedForRun(name)
    if not name then return true end
    local entry = GetBestByName()[name]
    if not entry or not entry.requiresTome then return true end
    if EbonBuilds.EchoOwnership then
        return EbonBuilds.EchoOwnership.IsEchoRollable(name, entry.tomeSpellId)
    end
    return false
end

function EbonBuilds.EchoTableRows.ResolveSpellId(name, quality)
    if not name then return nil end
    local entry = GetBestByName()[name]
    if not entry then return nil end
    if quality ~= nil and entry.spellIds and entry.spellIds[quality] then
        return entry.spellIds[quality]
    end
    return entry.spellId
end

local function CountQualities(qualities)
    local n, onlyQ = 0, nil
    if not qualities then return 0, nil end
    for q = 0, 4 do
        if qualities[q] then
            n = n + 1
            onlyQ = q
        end
    end
    return n, onlyQ
end

local function MakeEntryFields(entry, name, spellId)
    local ES = EbonBuilds.EchoSources
    local groupId = entry.groupId
    local requiresTome = entry.requiresTome == true
    local dropSource = nil
    if ES and ES.ResolveDropSource then
        dropSource = ES.ResolveDropSource(spellId, {
            groupId = groupId,
            requiredSpell = entry.requiredSpell,
            requiresTome = requiresTome,
        })
    end
    return {
        name          = name,
        qualities     = entry.qualities,
        families      = entry.families,
        classMask     = entry.classMask or 0,
        spellIds      = entry.spellIds,
        requiresTome  = requiresTome,
        tomeSpellId   = entry.tomeSpellId,
        groupId       = groupId,
        dropSource    = dropSource,
    }
end

-- Returns the sorted flat list used by EchoTable.
-- Multi-rarity echoes: one group-header row + one sub-row per quality tier.
-- Single-rarity echoes: one combined row (icon, name, weight, score, banish toggle).
function EbonBuilds.EchoTableRows.BuildSortedList()
    if sortedListCache then
        return sortedListCache
    end
    local best = GetBestByName()

    local names = {}
    for name in pairs(best) do
        names[#names + 1] = name
    end
    table.sort(names)

    local list = {}
    for _, name in ipairs(names) do
        local entry = best[name]
        local qCount, onlyQ = CountQualities(entry.qualities)

        if qCount <= 1 then
            local q = onlyQ or entry.quality or 0
            local sid = (entry.spellIds and entry.spellIds[q]) or entry.spellId
            local fields = MakeEntryFields(entry, name, sid)
            list[#list + 1] = {
                spellId       = sid,
                name          = name,
                quality       = q,
                qualityTier   = q,
                isSingleRow   = true,
                isGroupHeader = false,
                isSubRow      = false,
                qualities     = fields.qualities,
                families      = fields.families,
                classMask     = fields.classMask,
                spellIds      = fields.spellIds,
                requiresTome  = fields.requiresTome,
                tomeSpellId   = fields.tomeSpellId,
                groupId       = fields.groupId,
                dropSource    = fields.dropSource,
            }
        else
            local fields = MakeEntryFields(entry, name, entry.spellId)
            list[#list + 1] = {
                spellId       = entry.spellId,
                name          = name,
                quality       = entry.quality,
                qualityTier   = nil,
                isSingleRow   = false,
                isGroupHeader = true,
                isSubRow      = false,
                qualities     = fields.qualities,
                families      = fields.families,
                classMask     = fields.classMask,
                spellIds      = fields.spellIds,
                requiresTome  = fields.requiresTome,
                tomeSpellId   = fields.tomeSpellId,
                groupId       = fields.groupId,
                dropSource    = fields.dropSource,
            }

            for q = 0, 4 do
                if entry.qualities[q] then
                    local sid = entry.spellIds and entry.spellIds[q]
                    local subFields = MakeEntryFields(entry, name, sid or entry.spellId)
                    list[#list + 1] = {
                        spellId       = sid or entry.spellId,
                        name          = name,
                        quality       = q,
                        qualityTier   = q,
                        isSingleRow   = false,
                        isGroupHeader = false,
                        isSubRow      = true,
                        qualities     = subFields.qualities,
                        families      = subFields.families,
                        classMask     = subFields.classMask,
                        spellIds      = subFields.spellIds,
                        requiresTome  = subFields.requiresTome,
                        groupId       = subFields.groupId,
                        dropSource    = subFields.dropSource,
                    }
                end
            end
        end
    end

    sortedListCache = list
    return list
end

function EbonBuilds.EchoTableRows.BuildAllQualitiesList()
    local list = {}
    local db = GetPerkDatabase()
    if not db then return list end
    for spellId, data in pairs(db) do
        local raw = data.comment
        if raw and raw ~= "" then
            local name = StripQualitySuffix(raw)
            list[#list + 1] = {
                spellId = spellId,
                name = name,
                quality = data.quality,
                classMask = data.classMask or 0,
            }
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.quality < b.quality
    end)
    return list
end

local PICKER_CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

function EbonBuilds.EchoTableRows.GetDisplayNameForSpellId(spellId)
    if not spellId then return nil end
    local db = GetPerkDatabase()
    local data = db and db[spellId]
    if data and data.comment and data.comment ~= "" then
        return StripQualitySuffix(data.comment)
    end
    return GetSpellInfo(spellId)
end

function EbonBuilds.EchoTableRows.GetPickerClassToken()
    if EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingClass then
        local token = EbonBuilds.BuildForm.GetEditingClass()
        if token then return token end
    end
    local build = EbonBuilds.Build and EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if build and build.class then return build.class end
    if EbonBuilds.Build and EbonBuilds.Build.PlayerClassToken then
        return EbonBuilds.Build.PlayerClassToken()
    end
end

-- One row per echo name for the build's class (highest quality tier wins).
function EbonBuilds.EchoTableRows.BuildPickerList(opts)
    opts = opts or {}
    local classToken = opts.classToken
    if classToken == nil then
        classToken = EbonBuilds.EchoTableRows.GetPickerClassToken()
    end
    local classBit = classToken and PICKER_CLASS_BITS[classToken]
    local excludeSpellIds = opts.excludeSpellIds or {}
    local excludeNames = opts.excludeNames or {}
    local excludeNameSet = {}
    for i = 1, #excludeNames do
        excludeNameSet[excludeNames[i]] = true
    end

    local byName = {}
    local db = GetPerkDatabase()
    if not db then return {} end
    for spellId, data in pairs(db) do
        if not excludeSpellIds[spellId]
            and data.comment and data.comment ~= "" then
            local name = StripQualitySuffix(data.comment)
            if not excludeNameSet[name] then
                local mask = data.classMask or 0
                local matchesClass = not classBit or mask == 0
                    or bit.band(mask, classBit) ~= 0
                if matchesClass then
                    local quality = data.quality or 0
                    local existing = byName[name]
                    if not existing or quality > existing.quality then
                        byName[name] = {
                            spellId   = spellId,
                            name      = name,
                            quality   = quality,
                            classMask = mask,
                            spellIds  = { [quality] = spellId },
                        }
                    elseif existing and quality == existing.quality then
                        existing.spellIds = existing.spellIds or {}
                        existing.spellIds[quality] = spellId
                    end
                end
            end
        end
    end

    local list = {}
    for _, entry in pairs(byName) do
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- Score display helpers ------------------------------------------------

local function GetBaseWeight(entry)
    return EbonBuilds.Weights.Get(entry.name) or 0
end

local function GetQualityWeight(entry, q)
    return EbonBuilds.Weights.GetForQuality(entry.name, q) or 0
end

local function UpdateHeaderScores(row, entry)
    -- Multi-rank headers only show base weight; per-quality scores live on sub-rows.
    if not row.scoreLabel then return end
    row.scoreLabel:SetText("")
end

local function UpdateSubRowScore(row, entry)
    if not row.scoreLabel then return end
    local q = entry.qualityTier
    if q == nil then return end
    local settings = EbonBuilds.Scoring.GetEffectiveSettings()
    local spellId  = entry.spellId
    if spellId and EbonBuilds.Scoring.IsLocked(spellId) then
        row.scoreLabel:SetText(string.format("|cff%sLocked|r", QUALITY_COLORS[q]))
    elseif spellId and EbonBuilds.Scoring.IsBanned(spellId) then
        row.scoreLabel:SetText(string.format("|cff%sBanned|r", QUALITY_COLORS[q]))
    else
        local w  = GetQualityWeight(entry, q)
        local sc = EbonBuilds.Scoring.ScorePerQuality(entry, w, settings, q)
        row.scoreLabel:SetText(string.format("|cff%s%d|r", QUALITY_COLORS[q], sc))
    end
end

local function UpdateSingleRowScore(row, entry)
    UpdateSubRowScore(row, entry)
end

function EbonBuilds.EchoTableRows.CountQualities(qualities)
    return CountQualities(qualities)
end

function EbonBuilds.EchoTableRows.GetSortScore(entry)
    if not entry then return 0 end
    local settings = EbonBuilds.Scoring.GetEffectiveSettings()
    if entry.isSubRow and entry.qualityTier ~= nil then
        local w = GetQualityWeight(entry, entry.qualityTier)
        return EbonBuilds.Scoring.ScorePerQuality(entry, w, settings, entry.qualityTier)
    end
    local best = 0
    for q = 0, 4 do
        if entry.qualities and entry.qualities[q] then
            local w = GetQualityWeight(entry, q)
            local sc = EbonBuilds.Scoring.ScorePerQuality(entry, w, settings, q)
            if sc > best then best = sc end
        end
    end
    return best
end

function EbonBuilds.EchoTableRows.GetPolicyOrdinal(name)
    local policy = EbonBuilds.Build.GetEchoPolicy(name)
    for i, p in ipairs(EbonBuilds.Build.GetPolicyList()) do
        if p.id == policy then return i end
    end
    return 1
end

function EbonBuilds.EchoTableRows.SyncPolicyDropdown(dropdown)
    if not dropdown or not dropdown._echoName then return end
    local policy = EbonBuilds.Build.GetEchoPolicy(dropdown._echoName)
    local info = EbonBuilds.Build.GetEchoPolicyInfo(policy)
    UIDropDownMenu_SetText(dropdown, info.short or "Normal")
    if EbonBuilds.SiteWidgets and EbonBuilds.SiteWidgets.SyncDropDownLabel then
        EbonBuilds.SiteWidgets.SyncDropDownLabel(dropdown)
    end
end

local function ShowPolicyTooltip(owner, echoName)
    if not echoName or echoName == "" then return end
    local policy = EbonBuilds.Build.GetEchoPolicy(echoName)
    local info = EbonBuilds.Build.GetEchoPolicyInfo(policy)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("Automation Policy", 1, 0.82, 0)
    GameTooltip:AddLine("Current: " .. (info.title or policy), 1, 1, 1)
    if info.desc and info.desc ~= "" then
        GameTooltip:AddLine(info.desc, 0.8, 0.8, 0.8, true)
    elseif info.menuDesc and info.menuDesc ~= "" then
        GameTooltip:AddLine(info.menuDesc, 0.8, 0.8, 0.8, true)
    end
    GameTooltip:Show()
end

local POLICY_MENU_PAD_X = 12
local POLICY_MENU_BORDER_FUDGE = 10
local POLICY_ROW_HEIGHT = 32
local POLICY_ROW_GAP = 3
local POLICY_PAD_Y = 8
local DEFAULT_DROPDOWN_BUTTON_HEIGHT = UIDROPDOWNMENU_BUTTON_HEIGHT or 16

local policyMenuMeasureFS
local policyMenuWidthCache
local policyPopup

local function GetPolicyMenuWidth()
    if policyMenuWidthCache then return policyMenuWidthCache end
    if not policyMenuMeasureFS then
        policyMenuMeasureFS = UIParent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        policyMenuMeasureFS:Hide()
    end
    local maxW = 0
    for _, p in ipairs(EbonBuilds.Build.GetPolicyList()) do
        policyMenuMeasureFS:SetText(p.title)
        maxW = math.max(maxW, policyMenuMeasureFS:GetStringWidth() or 0)
        local sub = p.menuDesc or p.desc or ""
        if sub ~= "" then
            policyMenuMeasureFS:SetText(sub)
            maxW = math.max(maxW, policyMenuMeasureFS:GetStringWidth() or 0)
        end
    end
    policyMenuWidthCache = math.ceil(maxW) + POLICY_MENU_PAD_X * 2 + POLICY_MENU_BORDER_FUDGE
    return policyMenuWidthCache
end

-- DropDownList1 is shared globally; restore defaults once if an older build touched it.
local function RestoreSharedDropDownLists()
    for i = 1, (UIDROPDOWNMENU_MAXLEVELS or 2) do
        local list = _G["DropDownList" .. i]
        if not list then break end
        for j = 1, (UIDROPDOWNMENU_MAXBUTTONS or 32) do
            local btn = _G[list:GetName() .. "Button" .. j]
            if btn then
                btn:SetHeight(DEFAULT_DROPDOWN_BUTTON_HEIGHT)
            end
        end
    end
end

local function HidePolicyPopup()
    if not policyPopup then return end
    if policyPopup._root then
        policyPopup._root:Hide()
    end
    policyPopup._anchor = nil
end

local function IsPolicyPopupOpenFor(anchor)
    return policyPopup
        and policyPopup._root
        and policyPopup._root:IsShown()
        and policyPopup._anchor == anchor
end

local function FindMainWindowFrame(anchor)
    local p = anchor
    while p do
        if p.GetName and p:GetName() == "EbonBuildsMainWindow" then
            return p
        end
        p = p:GetParent()
    end
    if EbonBuilds.MainWindow and EbonBuilds.MainWindow._frame then
        return EbonBuilds.MainWindow._frame
    end
    return UIParent
end

local function EnsurePolicyPopup()
    if policyPopup and not policyPopup._siteStyled then
        if policyPopup._root then policyPopup._root:Hide() end
        policyPopup = nil
    end
    if policyPopup then return policyPopup end

    local SW = EbonBuilds.SiteWidgets
    local ST = EbonBuilds.SiteTheme
    local C  = ST.C
    local FLAT = ST.FLAT

    local root = CreateFrame("Frame", "EbonBuildsPolicyPopupRoot", UIParent)
    root:SetFrameStrata("DIALOG")
    root:SetToplevel(true)
    root:Hide()

    local backdrop = CreateFrame("Button", nil, root)
    backdrop:SetFrameLevel(1)
    backdrop:SetAllPoints(root)
    backdrop:RegisterForClicks("AnyUp")
    backdrop:SetScript("OnClick", HidePolicyPopup)

    local f = CreateFrame("Frame", "EbonBuildsPolicyPopup", root)
    f:SetFrameLevel(10)
    f:EnableMouse(true)
    SW.Fill(f, "bgElevated")
    f._border = SW.ThinBorder(f, "border", 1)
    f:SetScript("OnMouseDown", function() end)

    f.rows = {}
    for i, p in ipairs(EbonBuilds.Build.GetPolicyList()) do
        local row = CreateFrame("Button", nil, f)
        row:EnableMouse(true)
        row:SetHeight(POLICY_ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row._policyId = p.id

        row._highlight = row:CreateTexture(nil, "BACKGROUND")
        row._highlight:SetTexture(FLAT)
        row._highlight:SetVertexColor(unpack(C.accentBg12))
        row._highlight:Hide()

        row._title = SW.Label(row, p.title, 11, C.text, false, "medium")
        row._title:SetPoint("TOPLEFT", row, "TOPLEFT", POLICY_MENU_PAD_X, -4)
        row._title:SetPoint("RIGHT", row, "RIGHT", -POLICY_MENU_PAD_X, 0)
        row._title:SetJustifyH("LEFT")

        row._desc = SW.Label(row, p.menuDesc or p.desc or "", 10, C.textMuted)
        row._desc:SetPoint("TOPLEFT", row._title, "BOTTOMLEFT", 0, -1)
        row._desc:SetPoint("RIGHT", row, "RIGHT", -POLICY_MENU_PAD_X, 0)
        row._desc:SetJustifyH("LEFT")

        row._highlight:ClearAllPoints()
        row._highlight:SetPoint("TOPLEFT", row._title, "TOPLEFT", -6, 2)
        row._highlight:SetPoint("BOTTOMRIGHT", row._desc, "BOTTOMRIGHT", 6, -2)

        local function SelectPolicyRow(self)
            local popup = policyPopup
            if not popup or not popup._echoName then return end
            EbonBuilds.Build.SetEchoPolicy(popup._echoName, self._policyId)
            if popup._anchor then
                EbonBuilds.EchoTableRows.SyncPolicyDropdown(popup._anchor)
            end
            if popup._onChanged then popup._onChanged() end
            HidePolicyPopup()
        end

        row:SetScript("OnEnter", function(self)
            self._highlight:Show()
        end)
        row:SetScript("OnLeave", function(self)
            self._highlight:Hide()
        end)
        row:SetScript("OnClick", SelectPolicyRow)
        row:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then SelectPolicyRow(self) end
        end)

        f.rows[i] = row
    end

    f._root = root
    f._backdrop = backdrop
    f._siteStyled = true
    policyPopup = f
    return f
end

local function ShowPolicyPopup(anchor, echoName, onChanged)
    if not anchor or not echoName then return end
    local f = EnsurePolicyPopup()
    local root = f._root
    f._anchor = anchor
    f._echoName = echoName
    f._onChanged = onChanged

    local win = FindMainWindowFrame(anchor)
    root:SetParent(win)
    root:ClearAllPoints()
    root:SetAllPoints(win)
    root:SetFrameLevel((win.GetFrameLevel and win:GetFrameLevel() or 0) + 50)

    local policies = EbonBuilds.Build.GetPolicyList()
    local width = GetPolicyMenuWidth()
    f:SetWidth(width)

    local y = -POLICY_PAD_Y
    for i, row in ipairs(f.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
        row:SetHeight(POLICY_ROW_HEIGHT)
        row:Show()
        y = y - POLICY_ROW_HEIGHT - POLICY_ROW_GAP
    end

    local count = #policies
    local height = POLICY_PAD_Y + count * POLICY_ROW_HEIGHT
        + math.max(0, count - 1) * POLICY_ROW_GAP + POLICY_PAD_Y
    f:SetHeight(height)

    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)

    root:Show()
    f._backdrop:Show()
    f:Show()
    if f.Raise then f:Raise() end
end

local function EnsurePolicyDropDownHooks()
    if EbonBuilds.EchoTableRows._policyDropDownHooks then return end
    EbonBuilds.EchoTableRows._policyDropDownHooks = true
    RestoreSharedDropDownLists()
end

function EbonBuilds.EchoTableRows.CreatePolicyDropdown(parent, opts)
    opts = opts or {}
    policyDdSerial = policyDdSerial + 1
    local width = opts.width or (COL_POLICY - 4)
    local dd = CreateFrame("Frame", "EbonBuildsEchoPolicyDD" .. policyDdSerial, parent, "UIDropDownMenuTemplate")
    if opts.anchorFn then
        opts.anchorFn(dd, parent)
    else
        local inset = opts.rightInset or C.GetPolicyRightInset()
        local colW = opts.columnWidth or COL_POLICY
        C.AnchorColumnRight(dd, parent, inset, colW)
    end
    UIDropDownMenu_SetWidth(dd, width)
    if EbonBuilds.SiteWidgets and EbonBuilds.SiteWidgets.StyleUIDropDown then
        EbonBuilds.SiteWidgets.StyleUIDropDown(dd, width)
    end
    UIDropDownMenu_SetText(dd, "Normal")
    dd._ebonPolicyMenu = true
    EnsurePolicyDropDownHooks()

    local onChanged = opts.onChanged
    UIDropDownMenu_Initialize(dd, function() end)

    local ddButton = _G[dd:GetName() .. "Button"]
    if ddButton then
        ddButton:SetScript("OnClick", function()
            if IsPolicyPopupOpenFor(dd) then
                HidePolicyPopup()
                return
            end
            HidePolicyPopup()
            ShowPolicyPopup(dd, dd._echoName, function()
                if onChanged then
                    onChanged()
                elseif onWeightChanged then
                    onWeightChanged()
                end
            end)
        end)
        ddButton:HookScript("OnEnter", function()
            ShowPolicyTooltip(ddButton, dd._echoName)
        end)
        ddButton:HookScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    else
        dd:EnableMouse(true)
        dd:SetScript("OnEnter", function()
            ShowPolicyTooltip(dd, dd._echoName)
        end)
        dd:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return dd
end

local function AnchorScoreColumn(label, row)
    C.AnchorBoundedColumn(label, row, C.GetScoreRightInset(), COL_SCORE)
    label:SetJustifyH("RIGHT")
    if label.SetNonSpaceWrap then
        label:SetNonSpaceWrap(true)
    end
end

local function CreatePolicyHolder(row)
    local holder = CreateFrame("Frame", nil, row)
    holder:SetHeight(ROW_HEIGHT)
    if holder.SetClipsChildren then
        holder:SetClipsChildren(true)
    end
    C.AnchorBoundedColumn(holder, row, C.GetPolicyRightInset(), COL_POLICY)
    local dd = EbonBuilds.EchoTableRows.CreatePolicyDropdown(holder, {
        anchorFn = function(dd, parent)
            dd:ClearAllPoints()
            dd:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
            dd:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
        end,
        width = COL_POLICY - 8,
    })
    return dd, holder
end

local function CreatePolicyDropdown(row)
    local dd = CreatePolicyHolder(row)
    return dd
end

function EbonBuilds.EchoTableRows.SyncTomeOwnedDisplay(frame, arg)
    if not frame then return end

    local tomeSpellId, owned, name, spellId, groupId, spellIds
    if type(arg) == "table" then
        tomeSpellId = arg.tomeSpellId
        owned = arg.owned
        name = arg.name
        spellId = arg.spellId
        groupId = arg.groupId
        spellIds = arg.spellIds
    else
        tomeSpellId = arg
    end

    frame._tomeSpellId = tomeSpellId
    frame._echoName = name
    frame._echoSpellId = spellId
    frame._echoGroupId = groupId
    frame._echoSpellIds = spellIds

    if not tomeSpellId or tomeSpellId == 9 then
        frame:Hide()
        return
    end
    frame:Show()

    if owned == nil and EbonBuilds.EchoOwnership then
        owned = EbonBuilds.EchoOwnership.IsAccountOwned(name, spellIds, groupId, spellId)
    elseif owned == nil then
        owned = false
    end
    frame._owned = owned

    if frame._checkbox then
        frame._checkbox:Show()
        frame._checkbox:SetChecked(owned and true or false)
    end
end

function EbonBuilds.EchoTableRows.CreateTomeOwnedDisplay(row, opts)
    opts = opts or {}
    local rightInset = opts.rightInset or C.GetTomeRightInset()
    local width = opts.width or COL_TOME
    local height = opts.height or ROW_HEIGHT
    local frame = CreateFrame("Frame", nil, row)
    if opts.stretchVertical then
        frame:ClearAllPoints()
        frame:SetPoint("RIGHT", row, "RIGHT", -rightInset, 0)
        frame:SetPoint("TOP", row, "TOP", 0, 0)
        frame:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
        frame:SetWidth(width)
    else
        frame:SetSize(width, height)
        C.AnchorColumnRight(frame, row, rightInset, width)
    end

    local SW = EbonBuilds.SiteWidgets
    local box = SW.CreateCheckbox(frame, { displayOnly = true, size = 16 })
    box:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame._checkbox = box

    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        if not self._tomeSpellId then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Owned", 1, 0.82, 0)
        local owned = self._owned
        if owned == nil and EbonBuilds.EchoOwnership then
            owned = EbonBuilds.EchoOwnership.IsAccountOwned(
                self._echoName, self._echoSpellIds, self._echoGroupId, self._echoSpellId)
        elseif owned == nil then
            owned = false
        end
        if owned then
            GameTooltip:AddLine("Discovered on this account.", 0.5, 1, 0.5, true)
        else
            GameTooltip:AddLine("Not yet discovered on this account.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:Hide()
    return frame
end

local function CreateTomeOwnedDisplay(row)
    return EbonBuilds.EchoTableRows.CreateTomeOwnedDisplay(row)
end

-- Tooltip helpers -------------------------------------------------------

local TOOLTIP_MIN_WIDTH = 360
local TOOLTIP_DESC_WIDTH = 420

local function GetTooltipUtils()
    return _G.utils
end

local function ResolveTooltipStacks(spellId)
    local stacks = 1
    local db = (EbonBuilds.EchoOwnership and EbonBuilds.EchoOwnership.GetPerkDatabase())
        or (ProjectEbonhold and ProjectEbonhold.PerkDatabase)
    if db and spellId and db[spellId] and db[spellId].maxStack then
        stacks = db[spellId].maxStack
    end
    return stacks
end

local function PrepareEchoTooltip(owner)
    local anchor = "ANCHOR_RIGHT"
    if owner and owner.GetBottom then
        local bottom = owner:GetBottom()
        if bottom and bottom < 220 then
            anchor = "ANCHOR_BOTTOMRIGHT"
        end
    end
    GameTooltip:SetOwner(owner, anchor)
    GameTooltip:ClearLines()
    if GameTooltip.SetMinimumWidth then
        GameTooltip:SetMinimumWidth(TOOLTIP_MIN_WIDTH)
    end
    if GameTooltip.SetMaximumWidth then
        GameTooltip:SetMaximumWidth(TOOLTIP_DESC_WIDTH + 40)
    end
    return anchor
end

local function TrySetSpellHyperlink(spellId)
    if not spellId or spellId == 0 then return false end
    local ok = pcall(function()
        GameTooltip:SetHyperlink("spell:" .. spellId)
    end)
    return ok
end

local function AddDescriptionFallback(spellId, stacks)
    local utils = GetTooltipUtils()
    if utils and utils.AddSpellDescriptionToTooltip then
        utils.AddSpellDescriptionToTooltip(GameTooltip, spellId, stacks or 1)
        return true
    end
    if utils and utils.GetSpellDescription then
        local description = utils.GetSpellDescription(spellId, TOOLTIP_DESC_WIDTH, stacks or 1)
        if description and description ~= "" and description ~= "Click for details" then
            GameTooltip:AddLine(description, 1, 1, 1, true)
            return true
        end
    end
    return false
end

local function AppendTooltipExtraLines(extraLines)
    if not extraLines then return end
    for i = 1, #extraLines do
        local line = extraLines[i]
        if type(line) == "table" then
            GameTooltip:AddLine(line.text, line.r or 0.7, line.g or 0.7, line.b or 0.7, line.wrap)
        elseif type(line) == "string" then
            GameTooltip:AddLine(line, 0.7, 0.7, 0.7)
        end
    end
end

local function ShowMultiRankEchoTooltip(owner, entry)
    if not entry then return end
    PrepareEchoTooltip(owner)
    GameTooltip:AddLine(entry.name, 1, 0.82, 0)
    local hasLine = false
    for q = 0, 4 do
        if entry.qualities and entry.qualities[q] then
            local spellId = entry.spellIds and entry.spellIds[q]
            if spellId then
                local qname = QUALITY_NAMES[q] or ("Q" .. tostring(q))
                local color = QUALITY_COLORS[q] or "ffffff"
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(string.format("|cff%s%s|r", color, qname), 1, 1, 1)
                if AddDescriptionFallback(spellId, ResolveTooltipStacks(spellId)) then
                    hasLine = true
                end
            end
        end
    end
    if not hasLine then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Hover a rarity row for its specific bonus.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

local function ShowEchoTooltip(owner, spellId, extraLines)
    if not spellId or spellId == 0 then return end
    PrepareEchoTooltip(owner)

    local stacks = ResolveTooltipStacks(spellId)
    if not TrySetSpellHyperlink(spellId) then
        local spellName = GetSpellInfo(spellId)
        if spellName then
            GameTooltip:AddLine(spellName, 1, 0.82, 0)
        end
        AddDescriptionFallback(spellId, stacks)
    end

    AppendTooltipExtraLines(extraLines)
    GameTooltip:Show()
end

EbonBuilds.EchoTableRows.ShowEchoTooltip = ShowEchoTooltip
EbonBuilds.EchoTableRows.ShowMultiRankEchoTooltip = ShowMultiRankEchoTooltip

local function HideEchoTooltip()
    if GameTooltip.SetMinimumWidth then
        GameTooltip:SetMinimumWidth(0)
    end
    if GameTooltip.SetMaximumWidth then
        GameTooltip:SetMaximumWidth(0)
    end
    GameTooltip:Hide()
end

EbonBuilds.EchoTableRows.HideEchoTooltip = HideEchoTooltip

local function WireEchoTooltip(frame, spellIdAccessor)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        ShowEchoTooltip(self, spellIdAccessor(self))
    end)
    frame:SetScript("OnLeave", HideEchoTooltip)
end

local function WireRowEchoTooltip(row, entry)
    local function onEnter(owner)
        if entry.qualities and CountQualities(entry.qualities) > 1 then
            ShowMultiRankEchoTooltip(owner, entry)
        else
            ShowEchoTooltip(owner, entry.spellId)
        end
    end
    for _, frame in ipairs({ row.iconFrame, row.nameHitbox }) do
        if frame then
            frame:EnableMouse(true)
            frame:SetScript("OnEnter", function(self) onEnter(self) end)
            frame:SetScript("OnLeave", HideEchoTooltip)
        end
    end
end

local function WireIconTooltip(iconFrame)
    WireEchoTooltip(iconFrame, function(self) return self.spellId end)
end
EbonBuilds.EchoTableRows.WireIconTooltip = WireIconTooltip

-- Weight box helpers ---------------------------------------------------

local function ApplyWeight(editBox, raw)
    local text = raw and raw:match("^%s*(.-)%s*$") or ""

    if editBox.echoQuality ~= nil then
        if text == "" then
            EbonBuilds.Weights.SetForQuality(editBox.echoName, editBox.echoQuality, nil)
        else
            local num = tonumber(text)
            if num and math.floor(num) == num and num >= 0 then
                if num > WEIGHT_MAX then num = WEIGHT_MAX end
                EbonBuilds.Weights.SetForQuality(editBox.echoName, editBox.echoQuality, num)
            end
        end
    elseif text == "" then
        -- Multi-rank / single-rank base weight: cleared field stores 0.
        EbonBuilds.Weights.Set(editBox.echoName, 0)
    else
        local num = tonumber(text)
        if num and math.floor(num) == num and num >= 0 then
            if num > WEIGHT_MAX then num = WEIGHT_MAX end
            EbonBuilds.Weights.Set(editBox.echoName, num)
        end
    end

    -- Refresh displayed value.
    local current
    if editBox.echoQuality ~= nil then
        -- Show the override if set, else empty to indicate "uses base".
        if EbonBuilds.Weights.HasQualityOverride(editBox.echoName, editBox.echoQuality) then
            current = tostring(EbonBuilds.Weights.GetForQuality(editBox.echoName, editBox.echoQuality))
        else
            current = ""
        end
    else
        current = tostring(EbonBuilds.Weights.Get(editBox.echoName))
    end
    editBox:SetText(current)

    -- Refresh scores on the row.
    if editBox._row then
        local row   = editBox._row
        local entry = row._entry
        if entry then
            if entry.isSubRow then
                UpdateSubRowScore(row, entry)
            elseif entry.isSingleRow then
                UpdateSingleRowScore(row, entry)
            else
                UpdateHeaderScores(row, entry)
            end
        end
    end
    if onWeightChanged then
        onWeightChanged()
    end
end

local function WireWeightBox(editBox)
    editBox:SetScript("OnChar", function(self, char)
        -- Let backspace/delete edit natively; only block non-digit printable input.
        if char == "\127" or char == "\008" or char == "" then return end
        if not char:match("%d") then
            local pos  = self:GetCursorPosition()
            local text = self:GetText()
            self:SetText(text:sub(1, pos - 1) .. text:sub(pos + 1))
            self:SetCursorPosition(pos - 1)
            return
        end
        local pos      = self:GetCursorPosition()
        local text     = self:GetText()
        local nextText = text:sub(1, pos - 1) .. char .. text:sub(pos + 1)
        local nextNum  = tonumber(nextText)
        if nextNum and nextNum > WEIGHT_MAX then
            self:SetText(tostring(WEIGHT_MAX))
            self:SetCursorPosition(#self:GetText())
        end
    end)
    editBox:SetScript("OnEnterPressed", function(self)
        ApplyWeight(self, self:GetText())
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        ApplyWeight(self, self:GetText())
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        if self.echoQuality ~= nil then
            EbonBuilds.Weights.SetForQuality(self.echoName, self.echoQuality, nil)
            self:SetText("")
            if self._row and self._row._entry then
                UpdateSubRowScore(self._row, self._row._entry)
            end
            if onWeightChanged then onWeightChanged() end
        end
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
end

function EbonBuilds.EchoTableRows.WireWeightEditBox(editBox)
    WireWeightBox(editBox)
end

local function CreateWeightBox(parentRow, width, boxHeight)
    width = width or COL_WEIGHT
    boxHeight = boxHeight or 22
    local editContainer = CreateFrame("Frame", nil, parentRow)
    editContainer:SetSize(width, boxHeight)
    C.AnchorColumnRight(editContainer, parentRow, C.GetWeightRightInset(), width)
    editContainer:SetPoint("TOP", parentRow, "TOP", 0, -math.floor((parentRow:GetHeight() - boxHeight) / 2))
    editContainer:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    editContainer:SetBackdropColor(0, 0, 0, 0.6)
    editContainer:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local box = CreateFrame("EditBox", nil, editContainer)
    box:SetSize(width - 6, math.max(16, boxHeight - 4))
    box:SetPoint("CENTER", editContainer, "CENTER", 0, 0)
    box:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    box:SetTextColor(1, 1, 1, 1)
    box:SetJustifyH("CENTER")
    box:SetAutoFocus(false)
    box:SetMaxLetters(3)
    box._row = parentRow
    WireWeightBox(box)
    return box
end

-- Row backgrounds -------------------------------------------------------

local function AddBackground(row, index, isSubRow)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    if isSubRow then
        bg:SetTexture(0, 0, 0, (index % 2 == 0) and 0.05 or 0.0)
    else
        bg:SetTexture(0, 0, 0, (index % 2 == 0) and 0.25 or 0.12)
    end
end

-- Row factory -----------------------------------------------------------

-- Creates a group-header row: icon + name label + base weight box + scores.
local function CreateHeaderRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT",  parent, "LEFT",  0, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    AddBackground(row, index, false)

    local iconFrame = CreateFrame("Frame", nil, row)
    iconFrame:SetWidth(COL_ICON)
    iconFrame:SetHeight(ROW_HEIGHT)
    iconFrame:SetPoint("LEFT", row, "LEFT", C.ICON_PAD, 0)
    iconFrame:EnableMouse(true)
    iconFrame.spellId = 0

    local tex = iconFrame:CreateTexture(nil, "ARTWORK")
    tex:SetWidth(24)
    tex:SetHeight(24)
    tex:SetPoint("CENTER", iconFrame, "CENTER")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconFrame.icon = tex
    WireIconTooltip(iconFrame)

    local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("LEFT",  iconFrame, "RIGHT", 4, 0)
    nameLabel:SetPoint("RIGHT", row, "RIGHT", -C.GetNameRightInset(), 0)
    nameLabel:SetJustifyH("LEFT")

    local nameHitbox = CreateFrame("Frame", nil, row)
    nameHitbox:SetPoint("LEFT",  iconFrame, "RIGHT", 4, 0)
    nameHitbox:SetPoint("RIGHT", row, "RIGHT", -C.GetNameRightInset(), 0)
    nameHitbox:SetHeight(ROW_HEIGHT)
    WireEchoTooltip(nameHitbox, function() return row.iconFrame and row.iconFrame.spellId end)

    local scoreLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    AnchorScoreColumn(scoreLabel, row)

    local policyDd = CreatePolicyDropdown(row)
    row.policyDd = policyDd

    local tomeOwned = CreateTomeOwnedDisplay(row)
    row.tomeOwned = tomeOwned

    local weightBox = CreateWeightBox(row)
    weightBox.echoQuality = nil  -- base weight

    -- Tooltip hint on weight box.
    local wbTip = CreateFrame("Frame", nil, row)
    wbTip:SetAllPoints(weightBox:GetParent())
    wbTip:EnableMouse(true)
    wbTip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Base Weight", 1, 0.82, 0)
        GameTooltip:AddLine("Sets the default weight for all rarity tiers of this echo.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Weight 100 marks the echo as required (build grade F if missing).", 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine("Override individual rarities in the rows below.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    wbTip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.iconFrame  = iconFrame
    row.nameLabel  = nameLabel
    row.scoreLabel = scoreLabel
    row.weightBox  = weightBox
    row.tomeOwned  = tomeOwned
    row.isHeaderRow = true
    row:Hide()
    return row
end

-- Creates a per-quality sub-row: indent dot + quality name + score + override weight box.
local function CreateSubRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(SUBROW_HEIGHT)
    row:SetPoint("LEFT",  parent, "LEFT",  0, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    AddBackground(row, index, true)

    -- Dot / indent
    local dot = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dot:SetPoint("LEFT", row, "LEFT", COL_ICON + 8, 0)
    dot:SetText("|cff888888·|r")
    row.dot = dot

    -- Quality name
    local qualLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qualLabel:SetPoint("LEFT", dot, "RIGHT", 4, 0)
    qualLabel:SetWidth(90)
    qualLabel:SetJustifyH("LEFT")
    row.qualLabel = qualLabel

    local qualHitbox = CreateFrame("Frame", nil, row)
    qualHitbox:SetPoint("LEFT", row, "LEFT", COL_ICON, 0)
    qualHitbox:SetPoint("RIGHT", row, "RIGHT", -C.GetNameRightInset(), 0)
    qualHitbox:SetHeight(SUBROW_HEIGHT)
    row.qualHitbox = qualHitbox

    -- Score
    local scoreLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    AnchorScoreColumn(scoreLabel, row)
    row.scoreLabel = scoreLabel

    -- Per-quality weight override box.
    local weightBox = CreateWeightBox(row, COL_WEIGHT, 20)
    weightBox.echoQuality = 0  -- set properly in Populate

    -- Tooltip hint.
    local wbTip = CreateFrame("Frame", nil, row)
    local weightContainer = weightBox:GetParent()
    wbTip:SetAllPoints(weightContainer or weightBox)
    wbTip:EnableMouse(true)
    wbTip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Quality Weight Override", 1, 0.82, 0)
        GameTooltip:AddLine("Override the base weight for this specific rarity.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Leave empty to use the base weight above.", 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine("Right-click or press Escape to clear.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    wbTip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Right-click to clear override.
    weightBox:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            EbonBuilds.Weights.SetForQuality(self.echoName, self.echoQuality, nil)
            self:SetText("")
            if self._row and self._row._entry then
                UpdateSubRowScore(self._row, self._row._entry)
            end
            if onWeightChanged then onWeightChanged() end
        end
    end)

    row.weightBox  = weightBox
    row.isSubRow   = true
    row:Hide()
    return row
end

-- Single-rarity echo: one row with icon, name, quality tag, score, banish toggle, weight.
local function CreateSingleRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT",  parent, "LEFT",  0, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    AddBackground(row, index, false)

    local iconFrame = CreateFrame("Frame", nil, row)
    iconFrame:SetWidth(COL_ICON)
    iconFrame:SetHeight(ROW_HEIGHT)
    iconFrame:SetPoint("LEFT", row, "LEFT", C.ICON_PAD, 0)
    iconFrame:EnableMouse(true)
    iconFrame.spellId = 0

    local tex = iconFrame:CreateTexture(nil, "ARTWORK")
    tex:SetWidth(24)
    tex:SetHeight(24)
    tex:SetPoint("CENTER", iconFrame, "CENTER")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconFrame.icon = tex
    WireIconTooltip(iconFrame)

    local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("LEFT",  iconFrame, "RIGHT", 4, 0)
    nameLabel:SetPoint("RIGHT", row, "RIGHT", -C.GetNameRightInset(), 0)
    nameLabel:SetJustifyH("LEFT")

    local nameHitbox = CreateFrame("Frame", nil, row)
    nameHitbox:SetPoint("LEFT",  iconFrame, "RIGHT", 4, 0)
    nameHitbox:SetPoint("RIGHT", row, "RIGHT", -C.GetNameRightInset(), 0)
    nameHitbox:SetHeight(ROW_HEIGHT)
    WireEchoTooltip(nameHitbox, function() return row.iconFrame and row.iconFrame.spellId end)

    local scoreLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    AnchorScoreColumn(scoreLabel, row)

    local policyDd = CreatePolicyDropdown(row)
    row.policyDd = policyDd

    local tomeOwned = CreateTomeOwnedDisplay(row)
    row.tomeOwned = tomeOwned

    local weightBox = CreateWeightBox(row)
    weightBox.echoQuality = nil

    row.iconFrame  = iconFrame
    row.nameLabel  = nameLabel
    row.scoreLabel = scoreLabel
    row.weightBox  = weightBox
    row.tomeOwned  = tomeOwned
    row.isSingleRow = true
    row:Hide()
    return row
end

-- Public row factory used by EchoTable (creates from pool).
-- rowType: "header", "sub", or "single"
function EbonBuilds.EchoTableRows.CreateRow(parent, index, rowType)
    if rowType == "sub" then
        return CreateSubRow(parent, index)
    elseif rowType == "single" then
        return CreateSingleRow(parent, index)
    else
        return CreateHeaderRow(parent, index)
    end
end

-- Populate: fill a row frame with entry data.
function EbonBuilds.EchoTableRows.Populate(row, yOffset, entry)
    row:SetPoint("TOP", row:GetParent(), "TOP", 0, yOffset)
    row._entry = entry

    if entry.isSubRow then
        local q = entry.qualityTier
        row:SetHeight(SUBROW_HEIGHT)
        local color = QUALITY_COLORS[q] or "ffffff"
        local qname = QUALITY_NAMES[q] or ("Q"..tostring(q))
        if row.qualLabel then
            row.qualLabel:SetText(string.format("|cff%s%s|r", color, qname))
        end
        local wb = row.weightBox
        wb.echoName    = entry.name
        wb.echoQuality = q
        if EbonBuilds.Weights.HasQualityOverride(entry.name, q) then
            wb:SetText(tostring(EbonBuilds.Weights.GetForQuality(entry.name, q)))
        else
            wb:SetText("")
        end
        if row.qualHitbox then
            WireEchoTooltip(row.qualHitbox, function() return entry.spellId end)
        end
        if row.tomeOwned then
            row.tomeOwned:Hide()
        end
        UpdateSubRowScore(row, entry)
    elseif entry.isSingleRow then
        row:SetHeight(ROW_HEIGHT)
        local q = entry.qualityTier or entry.quality or 0
        local color = QUALITY_COLORS[q] or "ffffff"
        local qname = QUALITY_NAMES[q] or ("Q"..tostring(q))
        row.iconFrame.spellId = entry.spellId
        row.iconFrame.icon:SetTexture(select(3, GetSpellInfo(entry.spellId)))
        row.nameLabel:SetText(string.format("%s  |cff888888·|r |cff%s%s|r", entry.name, color, qname))
        local wb = row.weightBox
        wb.echoName    = entry.name
        wb.echoQuality = nil
        wb:SetText(tostring(EbonBuilds.Weights.Get(entry.name)))
        if row.policyDd then
            row.policyDd._echoName = entry.name
            EbonBuilds.EchoTableRows.SyncPolicyDropdown(row.policyDd)
            row.policyDd:Show()
        end
        if row.tomeOwned then
            EbonBuilds.EchoTableRows.SyncTomeOwnedDisplay(row.tomeOwned, {
                name = entry.name,
                spellId = entry.spellId,
                spellIds = entry.spellIds,
                groupId = entry.groupId,
                tomeSpellId = entry.tomeSpellId,
            })
        end
        WireRowEchoTooltip(row, entry)
        UpdateSingleRowScore(row, entry)
    else
        row:SetHeight(ROW_HEIGHT)
        row.iconFrame.spellId = entry.spellId
        row.iconFrame.icon:SetTexture(select(3, GetSpellInfo(entry.spellId)))
        row.nameLabel:SetText(entry.name)
        local wb = row.weightBox
        wb.echoName    = entry.name
        wb.echoQuality = nil
        wb:SetText(tostring(EbonBuilds.Weights.Get(entry.name)))
        if row.policyDd then
            row.policyDd._echoName = entry.name
            EbonBuilds.EchoTableRows.SyncPolicyDropdown(row.policyDd)
            row.policyDd:Show()
        end
        if row.tomeOwned then
            EbonBuilds.EchoTableRows.SyncTomeOwnedDisplay(row.tomeOwned, {
                name = entry.name,
                spellId = entry.spellId,
                spellIds = entry.spellIds,
                groupId = entry.groupId,
                tomeSpellId = entry.tomeSpellId,
            })
        end
        row._qualities = entry.qualities
        row._families  = entry.families
        row._spellIds  = entry.spellIds
        WireRowEchoTooltip(row, entry)
        UpdateHeaderScores(row, entry)
    end
    WireRowScrollPassthrough(row)
    row:Show()
end

function EbonBuilds.EchoTableRows.GetRowHeight(entry)
    if entry and entry.isSubRow then return SUBROW_HEIGHT end
    return ROW_HEIGHT
end

function EbonBuilds.EchoTableRows.GetRowType(entry)
    if entry.isSubRow then return "sub" end
    if entry.isSingleRow then return "single" end
    return "header"
end
