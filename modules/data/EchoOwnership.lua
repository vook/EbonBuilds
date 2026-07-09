-- EbonBuilds: modules/data/EchoOwnership.lua
-- Canonical adapter for ProjectEbonhold echo discovery / ownership data.
-- See Interface/AddOns/docs/ProjectEbonhold-API.md for underlying stores and semantics.

EbonBuilds.EchoOwnership = {}

local discoveryCache = nil
local countsCache = nil
local groupDiscoveryCache = nil
local hooksInstalled = false

local QUALITY_SUFFIXES = { "common", "uncommon", "rare", "epic", "legendary" }

local function StripQualitySuffix(name)
    if not name then return name end
    local base, suffix = name:match("^(.+) %- (.+)$")
    if base and suffix then
        local lower = string.lower(suffix)
        for i = 1, #QUALITY_SUFFIXES do
            if lower == QUALITY_SUFFIXES[i] then
                return base
            end
        end
    end
    return name
end

local function NormalizeName(name)
    if not name then return nil end
    return string.lower(StripQualitySuffix(name))
end

function EbonBuilds.EchoOwnership.GetCharacterKey()
    local name = UnitName and UnitName("player")
    if not name then return nil end
    return "Unknown\t" .. name
end

function EbonBuilds.EchoOwnership.Invalidate()
    discoveryCache = nil
    countsCache = nil
    groupDiscoveryCache = nil
end

function EbonBuilds.EchoOwnership.GetPerkDatabase()
    if not ProjectEbonhold then return nil end
    return ProjectEbonhold.PerkDatabase
end

function EbonBuilds.EchoOwnership.IsCatalogReady()
    local db = EbonBuilds.EchoOwnership.GetPerkDatabase()
    return db ~= nil and next(db) ~= nil
end

local function GetDiscoveryTable()
    if discoveryCache then return discoveryCache end
    local db = ProjectEbonholdDB and ProjectEbonholdDB.echoDiscovery
    if not db then
        discoveryCache = {}
        return discoveryCache
    end
    local key = EbonBuilds.EchoOwnership.GetCharacterKey()
    discoveryCache = (key and db[key]) or {}
    return discoveryCache
end

local function GetCountsTable()
    if countsCache then return countsCache end
    countsCache = (ProjectEbonholdDB and ProjectEbonholdDB.cachedPerkCounts) or {}
    return countsCache
end

local function BuildGroupDiscoveryCache()
    if groupDiscoveryCache then return groupDiscoveryCache end
    groupDiscoveryCache = {}
    local discovery = GetDiscoveryTable()
    local perkDb = EbonBuilds.EchoOwnership.GetPerkDatabase()
    if not perkDb then return groupDiscoveryCache end
    for spellId in pairs(discovery) do
        local data = perkDb[spellId]
        if data and data.groupId then
            groupDiscoveryCache[data.groupId] = true
        end
    end
    return groupDiscoveryCache
end

function EbonBuilds.EchoOwnership.IsDiscovered(spellId)
    if not spellId or spellId == 0 then return false end
    local discovery = GetDiscoveryTable()
    if discovery[spellId] then return true end

    if ProjectEbonhold and ProjectEbonhold.GetPerkData then
        local ok, data = pcall(ProjectEbonhold.GetPerkData, spellId)
        if ok and type(data) == "table" then
            if data.discovered == true or data.isDiscovered == true or data.owned == true then
                return true
            end
        end
    end
    return false
end

local function IsOwnedByCounts(displayName)
    if not displayName or displayName == "" then return false end
    local counts = GetCountsTable()
    if counts[displayName] and counts[displayName] > 0 then return true end
    local stripped = StripQualitySuffix(displayName)
    if stripped ~= displayName and counts[stripped] and counts[stripped] > 0 then
        return true
    end
    local norm = NormalizeName(displayName)
    for key, count in pairs(counts) do
        if count and count > 0 and NormalizeName(key) == norm then
            return true
        end
    end
    return false
end

function EbonBuilds.EchoOwnership.IsAccountOwned(displayName, spellIds, groupId, primarySpellId)
    if primarySpellId and EbonBuilds.EchoOwnership.IsDiscovered(primarySpellId) then
        return true
    end
    if type(spellIds) == "table" then
        for _, sid in pairs(spellIds) do
            if EbonBuilds.EchoOwnership.IsDiscovered(sid) then
                return true
            end
        end
    end
    if groupId then
        local groups = BuildGroupDiscoveryCache()
        if groups[groupId] then return true end
    end
    if IsOwnedByCounts(displayName) then
        return true
    end
    return false
end

-- Normalize GetGrantedPerks() to a name-keyed map regardless of server return shape.
function EbonBuilds.EchoOwnership.NormalizeGranted(raw)
    if type(raw) ~= "table" then return {} end

    if type(raw[1]) == "table" and raw[1].spellId then
        local hasStringKeys = false
        for key in pairs(raw) do
            if type(key) == "string" then
                hasStringKeys = true
                break
            end
        end
        if not hasStringKeys then
            local map = {}
            for i = 1, #raw do
                local inst = raw[i]
                if inst and inst.spellId then
                    local name = inst.name
                    if not name and EbonBuilds.Scoring and EbonBuilds.Scoring.ResolveEchoDisplayName then
                        name = EbonBuilds.Scoring.ResolveEchoDisplayName(inst.spellId)
                    end
                    if name then
                        local bucket = map[name]
                        if not bucket then
                            bucket = {}
                            map[name] = bucket
                        end
                        bucket[#bucket + 1] = inst
                    end
                end
            end
            return map
        end
    end

    return raw
end

function EbonBuilds.EchoOwnership.GetGrantedPerksMap()
    if not (ProjectEbonhold and ProjectEbonhold.PerkService
        and ProjectEbonhold.PerkService.GetGrantedPerks) then
        return {}
    end
    return EbonBuilds.EchoOwnership.NormalizeGranted(
        ProjectEbonhold.PerkService.GetGrantedPerks())
end

function EbonBuilds.EchoOwnership.IsRolledThisRun(displayName, spellId, groupId, granted, lockedSpellIds)
    if type(lockedSpellIds) == "table" then
        local db = EbonBuilds.EchoOwnership.GetPerkDatabase()
        local norm = NormalizeName(displayName)
        for _, sid in ipairs(lockedSpellIds) do
            if sid then
                if spellId and sid == spellId then
                    return true
                end
                if db and db[sid] then
                    local data = db[sid]
                    if groupId and data.groupId == groupId then
                        return true
                    end
                    if data.comment and data.comment ~= "" then
                        local lockedName = StripQualitySuffix(data.comment)
                        if norm and NormalizeName(lockedName) == norm then
                            return true
                        end
                    end
                end
            end
        end
    end

    if granted == nil then
        granted = EbonBuilds.EchoOwnership.GetGrantedPerksMap()
    else
        granted = EbonBuilds.EchoOwnership.NormalizeGranted(granted)
    end
    if type(granted) ~= "table" then return false end

    local norm = NormalizeName(displayName)
    if granted[displayName] or (norm and granted[norm]) then
        return true
    end
    for gkey, instances in pairs(granted) do
        if NormalizeName(gkey) == norm then
            return true
        end
        if type(instances) == "table" then
            for i = 1, #instances do
                local inst = instances[i]
                if inst and inst.spellId then
                    if spellId and inst.spellId == spellId then
                        return true
                    end
                    if groupId then
                        local db = EbonBuilds.EchoOwnership.GetPerkDatabase()
                        local data = db and db[inst.spellId]
                        if data and data.groupId == groupId then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

function EbonBuilds.EchoOwnership.IsEchoRollable(name, tomeSpellId)
    local entry = EbonBuilds.EchoTableRows
        and EbonBuilds.EchoTableRows.GetBestByName
        and EbonBuilds.EchoTableRows.GetBestByName()[name]
    if not entry or not entry.requiresTome then return true end
    return EbonBuilds.EchoOwnership.IsAccountOwned(
        name,
        entry.spellIds,
        nil,
        entry.spellId or tomeSpellId
    )
end

local function InstallHooks()
    if hooksInstalled then return end
    hooksInstalled = true

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            EbonBuilds.EchoOwnership.Invalidate()
        end
    end)

    -- Do NOT register ProjectEbonhold.onEventReceived here. That API stores one
    -- handler per event id; registering SEND_PLAYER_PERK_GRANTED overwrites the
    -- native /echoes journal handler and empties in-run perk state.
end

function EbonBuilds.EchoOwnership.Init()
    InstallHooks()
end
