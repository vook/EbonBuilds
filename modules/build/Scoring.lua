-- EbonBuilds: modules/build/Scoring.lua
-- Responsibility: compute echo scores and the class peak from a settings
-- table. Pure — no UI, no SavedVariables mutation.

EbonBuilds.Scoring = {}

local CLASS_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    DEATHKNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

-- Normalize family tokens produced by ProjectEbonhold to the 6 canonical keys
-- used in settings.familyBonus.
local FAMILY_MAP = {
    Tank = "Tank", Survivability = "Survivability", Healer = "Healer",
    Caster = "Caster", ["Caster DPS"] = "Caster",
    Melee  = "Melee",  ["Melee DPS"]  = "Melee",
    Ranged = "Ranged", ["Ranged DPS"] = "Ranged",
    None   = "No family",
}

local function NormFamily(f) return FAMILY_MAP[f] end

local function ApplyModifier(score, baseWeight, value, multiplicative)
    if multiplicative then
        if value == 0 then return score end
        return score + baseWeight * (value - 1)
    else
        return score + value
    end
end

local function ApplyFamilyBonuses(s, base, entry, fb, fm, wl)
    local hasWhitelist = false
    for _ in pairs(wl) do hasWhitelist = true; break end

    if entry.families and #entry.families > 0 then
        for i = 1, #entry.families do
            local key = NormFamily(entry.families[i])
            if key and (not hasWhitelist or wl[key]) then
                s = ApplyModifier(s, base, fb[key] or 0, fm[key])
            end
        end
    else
        if not hasWhitelist or wl["No family"] then
            s = ApplyModifier(s, base, fb["No family"] or 0, fm["No family"])
        end
    end
    return s
end

function EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, quality)
    local qb = settings.qualityBonus or {}
    local qm = settings.qualityBonusMode or {}
    local fb = settings.familyBonus  or {}
    local fm = settings.familyBonusMode or {}
    local wl = settings.banishFamilyWhitelist or {}
    local base = weight or 0
    local s = base

    s = ApplyModifier(s, base, qb[quality] or 0, qm[quality])
    s = ApplyFamilyBonuses(s, base, entry, fb, fm, wl)
    return s
end

-- Weight after quality and family bonuses (Bonus tab); excludes novelty.
function EbonBuilds.Scoring.EffectiveWeight(entry, weight, settings, quality)
    return EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, quality)
end

function EbonBuilds.Scoring.Score(entry, weight, settings)
    local s = EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, entry.quality)
    local base = weight or 0
    s = ApplyModifier(s, base, settings.noveltyValue or 0, settings.noveltyMode)
    return s
end

local WEIGHT_PREFIXES = {
    "tome of ", "codex of ", "scroll of ", "manual of ",
    "grimoire of ", "libram of ", "tablet of ",
}

local function NormalizeWeightKey(name)
    if not name then return nil end
    local n = string.lower(name)
    for _, prefix in ipairs(WEIGHT_PREFIXES) do
        if n:sub(1, #prefix) == prefix then
            n = n:sub(#prefix + 1)
            break
        end
    end
    for _, suffix in ipairs({
        " - common", " - uncommon", " - rare", " - epic", " - legendary",
    }) do
        if n:sub(-#suffix) == suffix then
            n = n:sub(1, -(#suffix + 1))
            break
        end
    end
    return n
end

local function LookupWeight(weights, displayName, quality)
    if not weights or not displayName then return 0 end
    if quality ~= nil and EbonBuilds.Weights and EbonBuilds.Weights.QUALITY_SEP then
        local qkey = displayName .. EbonBuilds.Weights.QUALITY_SEP .. tostring(quality)
        if weights[qkey] ~= nil then return weights[qkey] end
    end
    if weights[displayName] then return weights[displayName] end
    local norm = NormalizeWeightKey(displayName)
    if not norm then return 0 end
    for key, w in pairs(weights) do
        if EbonBuilds.Weights and EbonBuilds.Weights.IsQKey and not EbonBuilds.Weights.IsQKey(key) then
            if NormalizeWeightKey(key) == norm then return w end
        elseif not (EbonBuilds.Weights and EbonBuilds.Weights.IsQKey) then
            if NormalizeWeightKey(key) == norm then return w end
        end
    end
    return 0
end

function EbonBuilds.Scoring.LookupWeight(weights, displayName, quality)
    return LookupWeight(weights, displayName, quality)
end

local QUALITY_SUFFIX_NAMES = { "common", "uncommon", "rare", "epic", "legendary" }

local function StripQualitySuffix(name)
    if not name then return name end
    local base, suffix = name:match("^(.+) %- (.+)$")
    if base and suffix then
        local lower = string.lower(suffix)
        for _, q in ipairs(QUALITY_SUFFIX_NAMES) do
            if lower == q then return base end
        end
    end
    return name
end

local function ResolveEchoDisplayName(spellId, fallbackName)
    local data = ProjectEbonhold.PerkDatabase and ProjectEbonhold.PerkDatabase[spellId]
    if data and data.comment and data.comment ~= "" then
        return StripQualitySuffix(data.comment)
    end
    if fallbackName and not fallbackName:match("^__id:") then
        return StripQualitySuffix(fallbackName)
    end
    local spellName = GetSpellInfo(spellId)
    if spellName then return StripQualitySuffix(spellName) end
    return fallbackName
end

function EbonBuilds.Scoring.ResolveEchoDisplayName(spellId, fallbackName)
    return ResolveEchoDisplayName(spellId, fallbackName)
end

function EbonBuilds.Scoring.GetEchoFamilyKey(spellId, displayName)
    if spellId and ProjectEbonhold and ProjectEbonhold.PerkDatabase then
        local data = ProjectEbonhold.PerkDatabase[spellId]
        if data and data.groupId then
            return "g:" .. tostring(data.groupId)
        end
    end
    local name = ResolveEchoDisplayName(spellId, displayName)
    if name then return "n:" .. string.lower(name) end
    return nil
end

function EbonBuilds.Scoring.GetHighestPickedQuality(displayName, spellId, granted)
    local targetKey = displayName and string.lower(displayName)
    local targetGroupId
    if spellId and ProjectEbonhold and ProjectEbonhold.PerkDatabase then
        local data = ProjectEbonhold.PerkDatabase[spellId]
        targetGroupId = data and data.groupId
    end
    local best
    for key, instances in pairs(granted or {}) do
        if type(instances) == "table" then
            for _, inst in ipairs(instances) do
                local sid = inst and inst.spellId
                if sid then
                    local instName = ResolveEchoDisplayName(sid, key)
                    local sameEcho = targetKey and instName and string.lower(instName) == targetKey
                    local sameGroup = false
                    if targetGroupId and ProjectEbonhold.PerkDatabase then
                        local instData = ProjectEbonhold.PerkDatabase[sid]
                        sameGroup = instData and instData.groupId == targetGroupId
                    end
                    if sameEcho or sameGroup then
                        local q = inst.quality
                        if q == nil and ProjectEbonhold.PerkDatabase then
                            q = ProjectEbonhold.PerkDatabase[sid] and ProjectEbonhold.PerkDatabase[sid].quality or 0
                        end
                        if q and (not best or q > best) then best = q end
                    end
                end
            end
        end
    end
    return best
end

function EbonBuilds.Scoring.IsEchoNovel(displayName, spellId, granted)
    return EbonBuilds.Scoring.GetHighestPickedQuality(displayName, spellId, granted) == nil
end

local function MatchesClass(entry, bitVal)
    if not bitVal then return true end
    if not entry.classMask or entry.classMask == 0 then return true end
    return bit.band(entry.classMask, bitVal) ~= 0
end

function EbonBuilds.Scoring.ComputePeak(classToken, settings)
    if not settings then return nil, 0 end
    local list = EbonBuilds.EchoTableRows.BuildSortedList()
    local bitVal = classToken and CLASS_BITS[classToken]
    local bestName, bestScore = nil, nil
    for i = 1, #list do
        local e = list[i]
        if MatchesClass(e, bitVal) then
            local qualities = e.qualities or { [e.quality or 0] = true }
            for q = 0, 4 do
                if qualities[q] then
                    local entry = {
                        spellId = (e.spellIds and e.spellIds[q]) or e.spellId,
                        name = e.name,
                        quality = q,
                        families = e.families,
                        classMask = e.classMask,
                    }
                    local w = EbonBuilds.Weights.GetForQuality(e.name, q) or 0
                    local sc = EbonBuilds.Scoring.Score(entry, w, settings)
                    if bestScore == nil or sc > bestScore then
                        bestScore, bestName = sc, e.name
                    end
                end
            end
        end
    end
    return bestName, bestScore or 0
end

function EbonBuilds.Scoring.GetEffectiveLockedEchoes()
    if EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingLockedEchoes then
        local p = EbonBuilds.BuildForm.GetEditingLockedEchoes()
        if p then return p end
    end
    local build = EbonBuilds.Build.GetActive()
    if build and build.lockedEchoes then return build.lockedEchoes end
    return { nil, nil, nil, nil, nil }
end

function EbonBuilds.Scoring.IsLocked(spellId)
    if not spellId then return false end
    local lockeds = EbonBuilds.Scoring.GetEffectiveLockedEchoes()
    if not lockeds then return false end
    for i = 1, EbonBuilds.Build.LOCKED_SLOTS do
        if lockeds[i] and lockeds[i] == spellId then
            return true
        end
    end
    return false
end

function EbonBuilds.Scoring.IsBanned(spellId)
    if not spellId then return false end
    local settings = EbonBuilds.Scoring.GetEffectiveSettings()
    local banList = settings and settings.echoBanList
    return banList and banList[spellId] and true or false
end

function EbonBuilds.Scoring.GetEffectiveSettings()
    if EbonBuilds.ViewRouter and EbonBuilds.ViewRouter.Current() == "buildTabs" then
        if EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingSettings then
            local s = EbonBuilds.BuildForm.GetEditingSettings()
            if s then return s end
        end
    end
    local build = EbonBuilds.Build.GetActive()
    if build and build.settings then return build.settings end
    return EbonBuilds.Build.DefaultSettings()
end
