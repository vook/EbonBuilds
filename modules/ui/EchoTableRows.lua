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

local function BuildBestByName()
    local best = {}
    for spellId, data in pairs(ProjectEbonhold.PerkDatabase) do
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
                }
                best[name] = existing
            else
                existing.classMask = bit.bor(existing.classMask or 0, mask)
                if data.quality > existing.quality then
                    existing.spellId  = spellId
                    existing.quality  = data.quality
                    existing.families = data.families or {}
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
    EbonBuilds.EchoTableRows.InvalidateTomeCache()
    if EbonBuilds.EchoSearch and EbonBuilds.EchoSearch.InvalidateCache then
        EbonBuilds.EchoSearch.InvalidateCache()
    end
end

local tomeKnownCache = {}

function EbonBuilds.EchoTableRows.InvalidateTomeCache()
    tomeKnownCache = {}
    if EbonBuilds.Scoring and EbonBuilds.Scoring.ResetCache then
        EbonBuilds.Scoring.ResetCache()
    end
    if EbonBuilds.PlayerRunScore and EbonBuilds.PlayerRunScore.Invalidate then
        EbonBuilds.PlayerRunScore.Invalidate()
    end
end

function EbonBuilds.EchoTableRows.IsTomeInSpellbook(tomeSpellId)
    if not tomeSpellId or tomeSpellId == 0 or tomeSpellId == 9 then
        return false
    end
    if tomeKnownCache[tomeSpellId] ~= nil then
        return tomeKnownCache[tomeSpellId]
    end
    local known = false
    if IsSpellKnown then
        local ok, result = pcall(IsSpellKnown, tomeSpellId)
        if ok and result then
            known = true
        end
    end
    tomeKnownCache[tomeSpellId] = known
    return known
end

-- Run score / missing targets: echoes that need a tome count only when that tome is in the spellbook.
function EbonBuilds.EchoTableRows.IsEchoTomeOwnedForRun(name)
    if not name then return true end
    local entry = GetBestByName()[name]
    if not entry or not entry.requiresTome then return true end
    local tomeId = entry.tomeSpellId
    if not tomeId or tomeId == 0 or tomeId == 9 then return false end
    return EbonBuilds.EchoTableRows.IsTomeInSpellbook(tomeId)
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

local function MakeEntryFields(entry, name)
    return {
        name          = name,
        qualities     = entry.qualities,
        families      = entry.families,
        classMask     = entry.classMask or 0,
        spellIds      = entry.spellIds,
        requiresTome  = entry.requiresTome == true,
        tomeSpellId   = entry.tomeSpellId,
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
            local fields = MakeEntryFields(entry, name)
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
            }
        else
            local fields = MakeEntryFields(entry, name)
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
            }

            for q = 0, 4 do
                if entry.qualities[q] then
                    local sid = entry.spellIds and entry.spellIds[q]
                    list[#list + 1] = {
                        spellId       = sid or entry.spellId,
                        name          = name,
                        quality       = q,
                        qualityTier   = q,
                        isSingleRow   = false,
                        isGroupHeader = false,
                        isSubRow      = true,
                        qualities     = fields.qualities,
                        families      = fields.families,
                        classMask     = fields.classMask,
                        spellIds      = fields.spellIds,
                        requiresTome  = fields.requiresTome,
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
    for spellId, data in pairs(ProjectEbonhold.PerkDatabase) do
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
    local data = ProjectEbonhold.PerkDatabase and ProjectEbonhold.PerkDatabase[spellId]
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
    for spellId, data in pairs(ProjectEbonhold.PerkDatabase) do
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
    return 1
end

function EbonBuilds.EchoTableRows.SyncPolicyDropdown(dropdown)
end

function EbonBuilds.EchoTableRows.CreatePolicyDropdown(parent, opts)
    return nil
end

local function AnchorScoreColumn(label, row)
    C.AnchorBoundedColumn(label, row, C.GetScoreRightInset(), COL_SCORE)
    label:SetJustifyH("RIGHT")
    if label.SetNonSpaceWrap then
        label:SetNonSpaceWrap(true)
    end
end

local function CreatePolicyDropdown(row)
    return nil
end

local function CreateTomeOwnedDisplay(row)
    return nil
end

function EbonBuilds.EchoTableRows.SyncTomeOwnedDisplay(frame, tomeSpellId)
    if not frame then return end
    frame._tomeSpellId = tomeSpellId
    if not tomeSpellId or tomeSpellId == 9 then
        frame:Hide()
        return
    end
    frame:Show()
    frame._bg:Show()
    if EbonBuilds.EchoTableRows.IsTomeInSpellbook(tomeSpellId) then
        frame._check:Show()
    else
        frame._check:Hide()
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
        if not self._tomeSpellId then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Tome Owned", 1, 0.82, 0)
        local tomeName = GetSpellInfo(self._tomeSpellId)
        if EbonBuilds.EchoTableRows.IsTomeInSpellbook(self._tomeSpellId) then
            GameTooltip:AddLine(
                tomeName and (tomeName .. " is in your spellbook.") or "Tome is in your spellbook.",
                0.5, 1, 0.5, true)
        else
            GameTooltip:AddLine(
                tomeName and (tomeName .. " is not in your spellbook.") or "Tome is not in your spellbook.",
                0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:Hide()
    return frame
end

-- Tooltip helpers -------------------------------------------------------

local function ShowMultiRankEchoTooltip(owner, entry)
    if not entry then return end
    local anchor = "ANCHOR_RIGHT"
    if owner.GetBottom then
        local bottom = owner:GetBottom()
        if bottom and bottom < 220 then
            anchor = "ANCHOR_BOTTOMRIGHT"
        end
    end
    GameTooltip:SetOwner(owner, anchor)
    GameTooltip:ClearLines()
    if GameTooltip.SetMinimumWidth then
        GameTooltip:SetMinimumWidth(340)
    end
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
                if utils and utils.GetSpellDescription then
                    local desc = utils.GetSpellDescription(spellId, 300, 1)
                    if desc and desc ~= "" and desc ~= "Click for details" then
                        GameTooltip:AddLine(desc, 1, 1, 1, true)
                        hasLine = true
                    end
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
    local spellName = GetSpellInfo(spellId)
    local anchor = "ANCHOR_RIGHT"
    if owner.GetBottom then
        local bottom = owner:GetBottom()
        if bottom and bottom < 220 then
            anchor = "ANCHOR_BOTTOMRIGHT"
        end
    end
    GameTooltip:SetOwner(owner, anchor)
    GameTooltip:ClearLines()
    if GameTooltip.SetMinimumWidth then
        GameTooltip:SetMinimumWidth(340)
    end
    if spellName then
        GameTooltip:AddLine(spellName, 1, 0.82, 0)
    end
    if utils and utils.AddSpellDescriptionToTooltip then
        utils.AddSpellDescriptionToTooltip(GameTooltip, spellId, 1)
    elseif utils and utils.GetSpellDescription then
        local description = utils.GetSpellDescription(spellId, 0, 1)
        if description and description ~= "" then
            GameTooltip:AddLine(description, 1, 1, 1, true)
        end
    end
    if extraLines then
        for i = 1, #extraLines do
            local line = extraLines[i]
            GameTooltip:AddLine(line.text, line.r or 0.7, line.g or 0.7, line.b or 0.7)
        end
    end
    GameTooltip:Show()
end

EbonBuilds.EchoTableRows.ShowEchoTooltip = ShowEchoTooltip
EbonBuilds.EchoTableRows.ShowMultiRankEchoTooltip = ShowMultiRankEchoTooltip

local function HideEchoTooltip()
    if GameTooltip.SetMinimumWidth then
        GameTooltip:SetMinimumWidth(0)
    end
    GameTooltip:Hide()
end

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
            EbonBuilds.EchoTableRows.SyncTomeOwnedDisplay(row.tomeOwned, entry.tomeSpellId)
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
            EbonBuilds.EchoTableRows.SyncTomeOwnedDisplay(row.tomeOwned, entry.tomeSpellId)
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
