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

function EbonBuilds.Scoring.Score(entry, weight, settings)
    local s = EbonBuilds.Scoring.ScorePerQuality(entry, weight, settings, entry.quality)
    local base = weight or 0
    s = ApplyModifier(s, base, settings.noveltyValue or 0, settings.noveltyMode)
    return s
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
            local w  = EbonBuilds.Weights.Get(e.name) or 0
            local sc = EbonBuilds.Scoring.Score(e, w, settings)
            if bestScore == nil or sc > bestScore then
                bestScore, bestName = sc, e.name
            end
        end
    end
    return bestName, bestScore or 0
end

function EbonBuilds.Scoring.GetEffectivePermanentEchoes()
    if EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingPermanentEchoes then
        local p = EbonBuilds.BuildForm.GetEditingPermanentEchoes()
        if p then return p end
    end
    local build = EbonBuilds.Build.GetActive()
    if build and build.permanentEchoes then return build.permanentEchoes end
    return { nil, nil, nil, nil }
end

function EbonBuilds.Scoring.IsPermanent(spellId)
    if not spellId then return false end
    local permanents = EbonBuilds.Scoring.GetEffectivePermanentEchoes()
    if not permanents then return false end
    for i = 1, 4 do
        if permanents[i] and permanents[i] == spellId then
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
    if EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingSettings then
        local s = EbonBuilds.BuildForm.GetEditingSettings()
        if s then return s end
    end
    local build = EbonBuilds.Build.GetActive()
    if build and build.settings then return build.settings end
    return EbonBuilds.Build.DefaultSettings()
end
