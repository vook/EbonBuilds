-- EbonBuilds: modules/build/Build.lua
-- Responsibility: build CRUD, UUID generation, active-build tracking,
-- one-time migration from the legacy single-weight-table shape.

EbonBuilds.Build = {}

EbonBuilds.Build.DEFAULT_LOCKED_SLOTS = 5
EbonBuilds.Build.MAX_LOCKED_SLOTS = 6
EbonBuilds.Build.FALLBACK_LOCKED_SLOTS = 6
EbonBuilds.Build.LOCKED_SLOTS = EbonBuilds.Build.DEFAULT_LOCKED_SLOTS

local LOCKED_SLOT_CANDIDATE_KEYS = {
    "lockedPerkSlots",
    "lockedEchoSlots",
    "maxLockedPerks",
    "maxLockedEchoes",
    "maxPerkLocks",
    "perkLockSlots",
    "echoLockSlots",
}
local lockedSlotCache = { value = nil, at = 0 }

local function ClampLockedSlotCount(value)
    local n = tonumber(value)
    if not n then return nil end
    n = math.floor(n + 0.5)
    if n < 5 then
        return 5
    end
    if n > EbonBuilds.Build.MAX_LOCKED_SLOTS then
        return EbonBuilds.Build.MAX_LOCKED_SLOTS
    end
    return n
end

local function ReadLockedSlotCountFromTable(tbl)
    if type(tbl) ~= "table" then return nil end
    for i = 1, #LOCKED_SLOT_CANDIDATE_KEYS do
        local key = LOCKED_SLOT_CANDIDATE_KEYS[i]
        local clamped = ClampLockedSlotCount(tbl[key])
        if clamped then return clamped end
    end
    return nil
end

local function DetectLockedSlotCount()
    local pe = ProjectEbonhold
    local perkUI = pe and pe.PerkUI
    local safeCandidates = {
        ReadLockedSlotCountFromTable(pe),
        ReadLockedSlotCountFromTable(perkUI),
        ReadLockedSlotCountFromTable(pe and pe.Constants),
        ReadLockedSlotCountFromTable(ProjectEbonholdDB and ProjectEbonholdDB.settings),
    }
    for i = 1, #safeCandidates do
        if safeCandidates[i] == 6 then return 6 end
    end

    -- Keep gameplay stable: do not call runtime API methods here.
    -- If no explicit 6 is visible in safe tables, prefer 6 for unlocked clients.
    return ClampLockedSlotCount(EbonBuilds.Build.FALLBACK_LOCKED_SLOTS)
end

function EbonBuilds.Build.GetLockedSlotCount()
    local now = GetTime and GetTime() or 0
    if lockedSlotCache.value and now > 0 and (now - (lockedSlotCache.at or 0)) < 2 then
        return lockedSlotCache.value
    end
    local count = DetectLockedSlotCount()
    lockedSlotCache.value = count
    lockedSlotCache.at = now
    EbonBuilds.Build.LOCKED_SLOTS = count
    return count
end

function EbonBuilds.Build.InvalidateLockedSlotCache()
    lockedSlotCache.value = nil
    lockedSlotCache.at = 0
end

function EbonBuilds.Build.NormalizeLockedEchoes(list)
    local out = {}
    local src = type(list) == "table" and list or {}
    for i = 1, EbonBuilds.Build.MAX_LOCKED_SLOTS do
        out[i] = src[i] or nil
    end
    return out
end

local function DefaultSettings()
    return {
        qualityBonus        = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0 },
        qualityBonusMode    = { [0] = false, [1] = false, [2] = false, [3] = false, [4] = false },
        familyBonus         = { Tank = 0, Survivability = 0, Healer = 0, Caster = 0, Melee = 0, Ranged = 0, ["No family"] = 0 },
        familyBonusMode     = { Tank = false, Survivability = false, Healer = false, Caster = false, Melee = false, Ranged = false, ["No family"] = false },
        banishFamilyWhitelist = {},
        autoBanishPct    = 20,
        autoRerollPct    = 120,
        rerollGuardPct   = 90,
        autoFreezePct    = 80,
        freezePenaltyPct = 10,
        noveltyValue     = 0,
        noveltyMode      = false,
        echoBanList      = {},
        echoPolicies     = {},
        echoBanAllMode   = "highestScore",
    }
end

EbonBuilds.Build.DefaultSettings = DefaultSettings

local function EnsureSettings(build)
    build.settings = build.settings or DefaultSettings()
    local d = DefaultSettings()
    for k, v in pairs(d) do
        if build.settings[k] == nil then
            build.settings[k] = v
        elseif type(v) == "table" then
            for sk, sv in pairs(v) do
                if build.settings[k][sk] == nil then
                    build.settings[k][sk] = sv
                end
            end
        end
    end
end

EbonBuilds.Build.EnsureSettings = EnsureSettings

EbonBuilds.Build.POLICIES = {
    { id = "normal",          title = "Normal",                 short = "Normal",       menuDesc = "Score by weight; novelty while unpicked.", desc = "Score by weight and bonuses. Novelty applies while the echo family is unpicked." },
    { id = "ban1st",          title = "Banish on First Sight",  short = "Banish First", menuDesc = "Banish all rarities on first offer.", desc = "On first offer this run, banish the echo (all rarities). If no banishes remain, heavily deprioritize instead." },
    { id = "banAfterPick",    title = "Banish After Pick",      short = "Banish After", menuDesc = "Banish low-tier re-offers after pick.", desc = "After you pick this echo, banish re-offers at or below your highest picked rarity." },
    { id = "ignoreAfterPick", title = "Ignore After Pick",      short = "Ignore After", menuDesc = "Deprioritize Common/Uncommon after pick.", desc = "After you pick this echo, deprioritize Common and Uncommon re-offers. Rare+ still considered." },
    { id = "neverPick",       title = "Never Pick",             short = "Never Pick",   menuDesc = "Never auto-pick.", desc = "Never auto-pick. May still be banished or rerolled by automation thresholds." },
}

local POLICY_BY_ID = {}
for _, p in ipairs(EbonBuilds.Build.POLICIES) do
    POLICY_BY_ID[p.id] = p
end

local NON_NORMAL_POLICIES = {}
for _, p in ipairs(EbonBuilds.Build.POLICIES) do
    if p.id ~= "normal" then NON_NORMAL_POLICIES[p.id] = true end
end

function EbonBuilds.Build.GetPolicyList()
    return EbonBuilds.Build.POLICIES
end

function EbonBuilds.Build.GetEchoPolicyInfo(policy)
    local p = POLICY_BY_ID[policy] or POLICY_BY_ID.normal
    return { title = p.title, short = p.short, menuDesc = p.menuDesc, desc = p.desc }
end

function EbonBuilds.Build.GetEchoPolicy(echoName)
    if not echoName then return "normal" end
    local build = EbonBuilds.Build.GetActive()
    if not build then return "normal" end
    EnsureSettings(build)
    local policy = build.settings.echoPolicies and build.settings.echoPolicies[echoName]
    if policy and NON_NORMAL_POLICIES[policy] then return policy end
    return "normal"
end

function EbonBuilds.Build.SetEchoPolicy(echoName, policy)
    if not echoName then return end
    local build = EbonBuilds.Build.GetActive()
    if not build then return end
    EnsureSettings(build)
    build.settings.echoPolicies = build.settings.echoPolicies or {}
    if not policy or policy == "normal" then
        build.settings.echoPolicies[echoName] = nil
    elseif NON_NORMAL_POLICIES[policy] then
        build.settings.echoPolicies[echoName] = policy
    end
end

local function CloneTable(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[CloneTable(k)] = CloneTable(v)
    end
    return copy
end

function EbonBuilds.Build.CloneSettings(settings)
    return CloneTable(settings)
end

function EbonBuilds.Build.Checksum(build)
    local parts = {
        build.title or "",
        build.class or "",
        tostring(build.spec or 1),
        build.comments or "",
    }
    local le = build.lockedEchoes or {}
    for i = 1, EbonBuilds.Build.GetLockedSlotCount() do
        parts[#parts + 1] = tostring(le[i] or "nil")
    end
    if build.echoWeights then
        local names = {}
        for name in pairs(build.echoWeights) do
            if type(build.echoWeights[name]) == "number" and build.echoWeights[name] > 0 then
                names[#names + 1] = name
            end
        end
        table.sort(names)
        for _, name in ipairs(names) do
            parts[#parts + 1] = name .. "=" .. tostring(build.echoWeights[name])
        end
    end
    parts[#parts + 1] = tostring(build.automationEnabled and 1 or 0)
    local s = CloneTable(build.settings or DefaultSettings())
    parts[#parts + 1] = EbonBuilds.ExportImport and EbonBuilds.ExportImport.JSONEncode and EbonBuilds.ExportImport.JSONEncode(s) or ""
    return table.concat(parts, "|")
end

local function NormalizeQualityPicks(qp)
    if not qp then
        return { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
    end
    -- Legacy saves used a 1-based array; migrate to quality tier keys 0–4.
    if qp[0] == nil and qp[1] ~= nil then
        local out = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
        for q = 0, 4 do
            out[q] = tonumber(qp[q + 1]) or 0
        end
        return out
    end
    for q = 0, 4 do
        qp[q] = tonumber(qp[q]) or 0
    end
    return qp
end

local function EnsureStats(build)
    build.stats = build.stats or {
        echoesSeen    = 0,
        runsCompleted = 0,
        runsReset     = 0,
        picks         = 0,
        rerollsUsed   = 0,
        banishesUsed  = 0,
        freezesUsed   = 0,
        qualityPicks  = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0 },
        mostPicked    = {},
        mostBanned    = {},
    }
    build.stats.qualityPicks = NormalizeQualityPicks(build.stats.qualityPicks)
    build.stats.mostPicked   = build.stats.mostPicked   or {}
    build.stats.mostBanned   = build.stats.mostBanned   or {}
    if build.automationEnabled == nil then build.automationEnabled = true end
    if not build.author then build.author = "Unknown" end
    if not build.lastModified then build.lastModified = date("%Y-%m-%d %H:%M:%S") end
    if build.isPublic == nil then build.isPublic = false end
    if build.validated == nil then build.validated = false end
    if build.copiedFrom == nil then build.copiedFrom = nil end
end

EbonBuilds.Build.EnsureStats = EnsureStats

local function NotifyStatsChanged()
    if EbonBuilds.BuildOverview and EbonBuilds.BuildOverview.NotifyStatsChanged then
        EbonBuilds.BuildOverview.NotifyStatsChanged()
    end
end

function EbonBuilds.Build.RecordEchoOffer(build, choices)
    if not build or not choices then return end
    EnsureStats(build)
    local st = build.stats
    for i = 1, #choices do
        st.echoesSeen = (st.echoesSeen or 0) + 1
    end
    NotifyStatsChanged()
end

function EbonBuilds.Build.RecordPick(build, echoName, quality)
    if not build then return end
    EnsureStats(build)
    local st = build.stats
    st.picks = (st.picks or 0) + 1
    local q = tonumber(quality) or 0
    st.qualityPicks[q] = (st.qualityPicks[q] or 0) + 1
    if echoName and echoName ~= "" then
        st.mostPicked[echoName] = (st.mostPicked[echoName] or 0) + 1
    end
    NotifyStatsChanged()
end

function EbonBuilds.Build.RecordBanish(build, echoName)
    if not build then return end
    EnsureStats(build)
    local st = build.stats
    st.banishesUsed = (st.banishesUsed or 0) + 1
    if echoName and echoName ~= "" then
        st.mostBanned[echoName] = (st.mostBanned[echoName] or 0) + 1
    end
    NotifyStatsChanged()
end

function EbonBuilds.Build.RecordRunEnd(build, info)
    if not build then return end
    EnsureStats(build)
    info = info or {}
    if info.reachedMax then
        build.stats.runsCompleted = (build.stats.runsCompleted or 0) + 1
    elseif (info.maxLevel or 0) > 1 then
        build.stats.runsReset = (build.stats.runsReset or 0) + 1
    end
    NotifyStatsChanged()
end

function EbonBuilds.Build.TopEchoStatName(counts)
    local bestName, bestCount = nil, 0
    for name, count in pairs(counts or {}) do
        count = tonumber(count) or 0
        if count > bestCount then
            bestName = name
            bestCount = count
        end
    end
    return bestName
end

local activeChangeCallbacks = {}

local function Notify()
    for i = 1, #activeChangeCallbacks do
        activeChangeCallbacks[i]()
    end
end

function EbonBuilds.Build.OnActiveChanged(fn)
    activeChangeCallbacks[#activeChangeCallbacks + 1] = fn
end

------------------------------------------------------------------------
-- UUID
------------------------------------------------------------------------

function EbonBuilds.Build.NewId()
    local name = UnitName("player") or "unknown"
    return tostring(time()) .. "-" .. tostring(math.random(1, 1000000000)) .. "-" .. name
end

function EbonBuilds.Build.NewObjectId()
    return string.format("%08x%04x%04x%04x%04x",
        time(),
        math.random(0, 65535),
        math.random(0, 65535),
        math.random(0, 65535),
        math.random(0, 65535))
end

------------------------------------------------------------------------
-- Talent helpers
------------------------------------------------------------------------

local function PlayerClassToken()
    return select(2, UnitClass("player"))
end

local function PlayerTopTalentTab()
    local best, bestPoints = 1, -1
    for i = 1, 3 do
        local _, _, pointsSpent = GetTalentTabInfo(i)
        pointsSpent = pointsSpent or 0
        if pointsSpent > bestPoints then
            best, bestPoints = i, pointsSpent
        end
    end
    return best
end

EbonBuilds.Build.PlayerClassToken   = PlayerClassToken
EbonBuilds.Build.PlayerTopTalentTab = PlayerTopTalentTab

function EbonBuilds.Build.GetPlayerTalentPoints()
    local pts = { 0, 0, 0 }
    for i = 1, 3 do
        local _, _, spent = GetTalentTabInfo(i)
        pts[i] = spent or 0
    end
    return pts
end

function EbonBuilds.Build.FormatTalentDistribution(build)
    if not build then return nil end
    local pts = build.talentPoints
    local active = EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive()
    if active and active.id == build.id then
        local playerClass = PlayerClassToken()
        if playerClass and playerClass == build.class then
            pts = EbonBuilds.Build.GetPlayerTalentPoints()
        end
    end
    if not pts then return nil end
    return string.format("%d/%d/%d", pts[1] or 0, pts[2] or 0, pts[3] or 0)
end

function EbonBuilds.Build.CaptureTalentPoints(classToken)
    if classToken and classToken == PlayerClassToken() then
        return EbonBuilds.Build.GetPlayerTalentPoints()
    end
    return nil
end

function EbonBuilds.Build.EnsureTalentSnapshot(build)
    if not build then return nil end
    if build.talentPoints then return build.talentPoints end
    if build.class ~= PlayerClassToken() then return nil end
    build.talentPoints = EbonBuilds.Build.GetPlayerTalentPoints()
    return build.talentPoints
end

------------------------------------------------------------------------
-- Migration
------------------------------------------------------------------------

function EbonBuilds.Build.Migrate()
    EbonBuildsDB.builds        = EbonBuildsDB.builds        or {}
    EbonBuildsCharDB.activeBuildId = EbonBuildsCharDB.activeBuildId or nil

    -- Migrate old per-account activeBuildId to per-character
    if EbonBuildsDB.activeBuildId and not EbonBuildsCharDB.activeBuildId then
        EbonBuildsCharDB.activeBuildId = EbonBuildsDB.activeBuildId
    end
    EbonBuildsDB.activeBuildId = nil

    local legacy = EbonBuildsDB.echoWeights
    if legacy and not next(EbonBuildsDB.builds) then
        local id = EbonBuilds.Build.NewObjectId()
        EbonBuildsDB.builds[id] = {
            id              = id,
            title           = "Migrated",
            class           = PlayerClassToken(),
            spec            = PlayerTopTalentTab(),
            comments        = "",
            lockedEchoes = EbonBuilds.Build.NormalizeLockedEchoes(),
            echoWeights     = legacy,
            settings        = DefaultSettings(),
            version         = 1,
        }
        EbonBuildsCharDB.activeBuildId = id
    end
    EbonBuildsDB.echoWeights = nil

    for _, b in pairs(EbonBuildsDB.builds) do
        EnsureSettings(b)
        EnsureStats(b)
        if b.scannedAffixes then
            b.scannedAffixes = EbonBuilds.Build.NormalizeScannedAffixes(b.scannedAffixes)
        end
        if not b.talentPoints and b.class == PlayerClassToken() then
            b.talentPoints = EbonBuilds.Build.GetPlayerTalentPoints()
        end
    end

    local active = EbonBuilds.Build.GetActive()
    if active and not active.talentPoints and active.class == PlayerClassToken() then
        active.talentPoints = EbonBuilds.Build.GetPlayerTalentPoints()
    end

    EbonBuilds.Build.MigrateIds()
end

function EbonBuilds.Build.MigrateIds()
    local oldIds = {}
    for id, b in pairs(EbonBuildsDB.builds) do
        if id:match("-") then oldIds[#oldIds + 1] = id end
    end

    if #oldIds == 0 then return end

    local map = {}
    for _, oldId in ipairs(oldIds) do
        map[oldId] = EbonBuilds.Build.NewObjectId()
    end

    for _, oldId in ipairs(oldIds) do
        local newId = map[oldId]
        local build = EbonBuildsDB.builds[oldId]
        build.id = newId
        EbonBuildsDB.builds[newId] = build
        EbonBuildsDB.builds[oldId] = nil
    end

    if EbonBuildsCharDB.activeBuildId and map[EbonBuildsCharDB.activeBuildId] then
        EbonBuildsCharDB.activeBuildId = map[EbonBuildsCharDB.activeBuildId]
    end

    for _, build in pairs(EbonBuildsDB.builds) do
        if build.importedFrom and map[build.importedFrom] then
            build.importedFrom = map[build.importedFrom]
        end
    end
end

------------------------------------------------------------------------
-- CRUD
------------------------------------------------------------------------

function EbonBuilds.Build.List()
    local out = {}
    for _, b in pairs(EbonBuildsDB.builds) do
        out[#out + 1] = b
    end
    table.sort(out, function(a, b) return (a.title or "") < (b.title or "") end)
    return out
end

function EbonBuilds.Build.ListPublic()
    local out = {}
    -- Local public builds
    for _, b in pairs(EbonBuildsDB.builds) do
        if b.isPublic then out[#out + 1] = b end
    end
    -- Remote builds (received via sync)
    if EbonBuildsDB.remoteBuilds then
        for _, b in pairs(EbonBuildsDB.remoteBuilds) do
            out[#out + 1] = b
        end
    end
    table.sort(out, function(a, b) return (a.lastModified or "") > (b.lastModified or "") end)
    return out
end

function EbonBuilds.Build.Get(id)
    if not id then return nil end
    return EbonBuildsDB.builds[id]
end

function EbonBuilds.Build.GetActive()
    return EbonBuilds.Build.Get(EbonBuildsCharDB.activeBuildId)
end

------------------------------------------------------------------------
-- Scanned affix storage (multiple players per build)
------------------------------------------------------------------------

local function IsLegacyAffixScan(data)
    return data and type(data.names) == "table" and type(data.scans) ~= "table"
end

local CLASS_LABELS = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", DEATHKNIGHT = "Death Knight", SHAMAN = "Shaman", MAGE = "Mage",
    WARLOCK = "Warlock", DRUID = "Druid",
}

function EbonBuilds.Build.CoerceAffixNameList(names)
    if type(names) ~= "table" then return {} end
    local out = {}
    for i = 1, #names do
        local name = names[i]
        if type(name) == "string" and name ~= "" then
            out[#out + 1] = name
        end
    end
    if #out > 0 then return out end
    for key, val in pairs(names) do
        if type(key) == "string" and key ~= "" and type(val) ~= "string" then
            out[#out + 1] = key
        elseif type(val) == "string" and val ~= "" then
            out[#out + 1] = val
        end
    end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

local function SortAffixNames(names)
    local sorted = EbonBuilds.Build.CoerceAffixNameList(names)
    table.sort(sorted, function(a, b) return a:lower() < b:lower() end)
    return sorted
end

local CoerceAffixNameList = EbonBuilds.Build.CoerceAffixNameList

local function PickDefaultActiveSource(scans)
    local bestSource, bestAt
    for source, scan in pairs(scans) do
        local at = scan and scan.scannedAt or ""
        if not bestAt or at > bestAt then
            bestSource, bestAt = source, at
        end
    end
    return bestSource
end

function EbonBuilds.Build.NormalizeScannedAffixes(data)
    if not data then return nil end
    if IsLegacyAffixScan(data) then
        local source = data.source or "Unknown"
        return {
            activeSource = source,
            scans = {
                [source] = {
                    source    = source,
                    scannedAt = data.scannedAt,
                    names     = CoerceAffixNameList(data.names),
                },
            },
        }
    end
    if type(data.scans) ~= "table" then
        local scans = {}
        for key, val in pairs(data) do
            if key ~= "activeSource" and type(val) == "table" and val.names then
                scans[key] = {
                    source    = val.source or key,
                    scannedAt = val.scannedAt,
                    names     = CoerceAffixNameList(val.names),
                }
            end
        end
        if next(scans) then
            return {
                activeSource = data.activeSource or PickDefaultActiveSource(scans),
                scans        = scans,
            }
        end
        return nil
    end
    for _, scan in pairs(data.scans) do
        if scan and scan.names then
            scan.names = CoerceAffixNameList(scan.names)
        end
    end
    if not data.activeSource or not data.scans[data.activeSource] then
        data.activeSource = PickDefaultActiveSource(data.scans)
    end
    return data
end

function EbonBuilds.Build.GetScannedAffixStore(build)
    if not build then return nil end
    build.scannedAffixes = EbonBuilds.Build.NormalizeScannedAffixes(build.scannedAffixes)
    return build.scannedAffixes
end

function EbonBuilds.Build.GetActiveAffixScan(build)
    local store = EbonBuilds.Build.GetScannedAffixStore(build)
    if not store or not store.scans then return nil end
    local scan = store.activeSource and store.scans[store.activeSource]
    if scan and scan.names and #scan.names > 0 then return scan end
    for source, candidate in pairs(store.scans) do
        local names = CoerceAffixNameList(candidate and candidate.names)
        if #names > 0 then
            store.activeSource = source
            candidate.names = names
            return candidate
        end
    end
    return nil
end

function EbonBuilds.Build.SetActiveAffixSource(build, source)
    local store = EbonBuilds.Build.GetScannedAffixStore(build)
    if not store or not source or not store.scans[source] then return false end
    store.activeSource = source
    return true
end

function EbonBuilds.Build.UpsertAffixScan(build, scanRecord)
    if not build or not scanRecord or not scanRecord.source then return false end
    local store = EbonBuilds.Build.GetScannedAffixStore(build) or { scans = {} }
    store.scans = store.scans or {}
    store.scans[scanRecord.source] = {
        source    = scanRecord.source,
        scannedAt = scanRecord.scannedAt,
        names     = scanRecord.names or {},
    }
    store.activeSource = scanRecord.source
    build.scannedAffixes = store
    return true
end

function EbonBuilds.Build.RemoveAffixScan(build, source)
    local store = EbonBuilds.Build.GetScannedAffixStore(build)
    if not store or not source or not store.scans[source] then return false end
    store.scans[source] = nil
    if not next(store.scans) then
        build.scannedAffixes = nil
        return true
    end
    if store.activeSource == source then
        store.activeSource = PickDefaultActiveSource(store.scans)
    end
    return true
end

function EbonBuilds.Build.ClearAffixScans(build)
    if not build then return false end
    build.scannedAffixes = nil
    return true
end

function EbonBuilds.Build.ListAffixScanSources(build)
    local store = EbonBuilds.Build.GetScannedAffixStore(build)
    if not store or not store.scans then return {} end
    local out = {}
    for source, scan in pairs(store.scans) do
        out[#out + 1] = {
            source    = source,
            scannedAt = scan.scannedAt,
            count     = scan.names and #CoerceAffixNameList(scan.names) or 0,
            active    = source == store.activeSource,
        }
    end
    table.sort(out, function(a, b)
        local atA, atB = a.scannedAt or "", b.scannedAt or ""
        if atA ~= atB then return atA > atB end
        return a.source:lower() < b.source:lower()
    end)
    return out
end

local function BuildHasScannedAffixes(build)
    return EbonBuilds.Build.GetActiveAffixScan(build) ~= nil
end

function EbonBuilds.Build.GetAffixSourceForCurrentClass()
    local myClass = PlayerClassToken()
    local active = EbonBuilds.Build.GetActive()
    if active and active.class == myClass and BuildHasScannedAffixes(active) then
        return active
    end
    local best = nil
    for _, build in pairs(EbonBuildsDB.builds) do
        if build.class == myClass and BuildHasScannedAffixes(build) then
            if not best or (build.lastModified or "") > (best.lastModified or "") then
                best = build
            end
        end
    end
    return best
end

function EbonBuilds.Build.GetAffixScanTargetForClass(classToken)
    if not classToken then
        return nil, "Could not determine inspected player's class."
    end
    local active = EbonBuilds.Build.GetActive()
    if active and active.class == classToken then
        return active
    end
    local best = nil
    for _, build in pairs(EbonBuildsDB.builds) do
        if build.class == classToken then
            if not best or (build.lastModified or "") > (best.lastModified or "") then
                best = build
            end
        end
    end
    if best then return best end
    local label = CLASS_LABELS[classToken] or classToken
    return nil, "No " .. label .. " build found. Create one first."
end

function EbonBuilds.Build.StoreAffixScanForClass(classToken, names, sourceName, onSuccess, onError)
    local build, err = EbonBuilds.Build.GetAffixScanTargetForClass(classToken)
    if not build then
        if onError then onError(err) elseif EbonBuilds.Toast then EbonBuilds.Toast.Show(err) end
        return
    end
    EbonBuilds.Build.UpsertAffixScan(build, {
        source    = sourceName,
        scannedAt = date("%Y-%m-%d %H:%M"),
        names     = SortAffixNames(names),
    })
    if onSuccess then
        onSuccess(build, names, sourceName, classToken)
    elseif EbonBuilds.Toast then
        EbonBuilds.Toast.Show(string.format(
            "Stored %d affix%s from %s on %s.",
            #names, #names == 1 and "" or "es", sourceName, build.title or "Untitled"))
    end
    if EbonBuilds.AffixView and EbonBuilds.AffixView.RefreshIfMounted then
        EbonBuilds.AffixView.RefreshIfMounted(build)
    end
end

function EbonBuilds.Build.QuickScanInspectedAffixes(onSuccess, onError)
    if not EbonBuilds.AffixScan or not EbonBuilds.AffixScan.ScanInspectedPlayer then
        local msg = "Affix scanning is not available."
        if onError then onError(msg) elseif EbonBuilds.Toast then EbonBuilds.Toast.Show(msg) end
        return
    end
    EbonBuilds.AffixScan.ScanInspectedPlayer(
        function(names, playerName, classToken)
            EbonBuilds.Build.StoreAffixScanForClass(classToken, names, playerName, onSuccess, onError)
        end,
        function(msg)
            if onError then onError(msg) elseif EbonBuilds.Toast then EbonBuilds.Toast.Show(msg) end
        end
    )
end

function EbonBuilds.Build.QuickScanPlayerAffixes(onSuccess, onError)
    if not EbonBuilds.AffixScan or not EbonBuilds.AffixScan.ScanUnit then
        local msg = "Affix scanning is not available."
        if onError then onError(msg) elseif EbonBuilds.Toast then EbonBuilds.Toast.Show(msg) end
        return
    end
    if ExtractionService and ExtractionService.RequestLearnedAffixes then
        ExtractionService.RequestLearnedAffixes()
    end
    local names = EbonBuilds.AffixScan.ScanUnit("player", true)
    local _, classToken = UnitClass("player")
    local playerName = UnitName("player") or "You"
    if not names or #names == 0 then
        local msg = "No affixes found on your equipped gear."
        if onError then onError(msg) elseif EbonBuilds.Toast then EbonBuilds.Toast.Show(msg) end
        return
    end
    EbonBuilds.Build.StoreAffixScanForClass(classToken, names, playerName, onSuccess, onError)
end

function EbonBuilds.Build.SetActive(id)
    if EbonBuildsCharDB.activeBuildId == id then return end
    EbonBuildsCharDB.activeBuildId = id
    local build = EbonBuilds.Build.Get(id)
    if build and build.class == PlayerClassToken() then
        build.talentPoints = EbonBuilds.Build.GetPlayerTalentPoints()
        build.spec = PlayerTopTalentTab()
    end
    Notify()
end

function EbonBuilds.Build.GetActiveWeights()
    if EbonBuildsDB._isEditingBuild then
        EbonBuildsDB.pendingWeights = EbonBuildsDB.pendingWeights or {}
        return EbonBuildsDB.pendingWeights
    end
    local build = EbonBuilds.Build.GetActive()
    if build then
        build.echoWeights = build.echoWeights or {}
        return build.echoWeights
    end
    EbonBuildsDB.pendingWeights = EbonBuildsDB.pendingWeights or {}
    return EbonBuildsDB.pendingWeights
end

function EbonBuilds.Build.NewObject(data)
    local id = EbonBuilds.Build.NewObjectId()
    local build = {
        id              = id,
        title           = data.title or "Untitled",
        class           = data.class or PlayerClassToken(),
        spec            = data.spec or PlayerTopTalentTab(),
        comments        = data.comments or "",
        talentPoints    = data.talentPoints,
        lockedEchoes = EbonBuilds.Build.NormalizeLockedEchoes(data.lockedEchoes),
        echoWeights     = data.echoWeights or {},
        scannedAffixes  = data.scannedAffixes,
        settings        = data.settings or DefaultSettings(),
        version         = 1,
        author          = data.author or UnitName("player") or "Unknown",
        lastModified    = data.lastModified or date("%Y-%m-%d %H:%M:%S"),
        automationEnabled = (data.automationEnabled ~= nil) and data.automationEnabled or true,
        isPublic         = data.isPublic or false,
        validated         = data.validated or false,
        copiedFrom        = data.copiedFrom or nil,
        stats            = {
            echoesSeen    = 0,
            runsCompleted = 0,
            runsReset     = 0,
            picks         = 0,
            rerollsUsed   = 0,
            banishesUsed  = 0,
            freezesUsed   = 0,
            qualityPicks  = { 0, 0, 0, 0, 0 },
            mostPicked    = {},
            mostBanned    = {},
        },
    }
    build._checksum = EbonBuilds.Build.Checksum(build)
    return build
end

function EbonBuilds.Build.Create(data)
    local build = EbonBuilds.Build.NewObject(data)
    build.echoWeights = EbonBuildsDB.pendingWeights or build.echoWeights
    build.scannedAffixes = EbonBuildsDB.pendingScannedAffixes or build.scannedAffixes
    EbonBuildsDB.pendingWeights = nil
    EbonBuildsDB.pendingScannedAffixes = nil
    EbonBuildsDB.builds[build.id] = build
    return build
end

function EbonBuilds.Build.UpdateFromPublic(localBuild, publicBuild)
    localBuild.title            = publicBuild.title            or localBuild.title
    localBuild.class            = publicBuild.class            or localBuild.class
    localBuild.spec             = publicBuild.spec             or localBuild.spec
    localBuild.comments         = publicBuild.comments         or localBuild.comments
    localBuild.lockedEchoes = EbonBuilds.Build.NormalizeLockedEchoes()
    for i = 1, EbonBuilds.Build.GetLockedSlotCount() do
        localBuild.lockedEchoes[i] = (publicBuild.lockedEchoes and publicBuild.lockedEchoes[i]) or nil
    end
    if publicBuild.settings then
        localBuild.settings = EbonBuilds.Build.CloneSettings(publicBuild.settings)
    end
    if publicBuild.automationEnabled ~= nil then
        localBuild.automationEnabled = publicBuild.automationEnabled
    end
    if publicBuild.echoWeights and next(publicBuild.echoWeights) then
        localBuild.echoWeights = {}
        for name, weight in pairs(publicBuild.echoWeights) do
            localBuild.echoWeights[name] = weight
        end
    end
    if publicBuild.copiedFrom then
        localBuild.copiedFrom = publicBuild.copiedFrom
    end
    localBuild._importedAt = publicBuild.lastModified
    localBuild.lastModified = date("%Y-%m-%d %H:%M:%S")
    localBuild.version = (localBuild.version or 1) + 1
    localBuild._checksum = EbonBuilds.Build.Checksum(localBuild)
    return localBuild
end

function EbonBuilds.Build.Save(id, data)
    local build = EbonBuildsDB.builds[id]
    if not build then return nil end
    local oldChecksum = build._checksum
    local classChanged = data.class and data.class ~= build.class
    build.title           = data.title           or build.title
    build.class           = data.class           or build.class
    build.spec            = data.spec            or build.spec
    build.comments        = data.comments        or build.comments
    build.lockedEchoes = data.lockedEchoes or build.lockedEchoes
    if data.settings then build.settings = data.settings end
    if data.echoWeights then build.echoWeights = data.echoWeights end
    if data.talentPoints then build.talentPoints = data.talentPoints end
    if data.scannedAffixes ~= nil then build.scannedAffixes = data.scannedAffixes end
    if data.automationEnabled ~= nil then build.automationEnabled = data.automationEnabled end
    if data.isPublic ~= nil then build.isPublic = data.isPublic end
    build.version         = (build.version or 1) + 1
    build._checksum       = EbonBuilds.Build.Checksum(build)
    if build._checksum ~= oldChecksum then
        build.lastModified = date("%Y-%m-%d %H:%M:%S")
        build.validated = false
        local playerName = UnitName("player") or "Unknown"
        if build.author and build.author ~= playerName then
            build.copiedFrom = build.author
            build.author = playerName
            build.validated = false
            build.importedFrom = nil
            local newId = EbonBuilds.Build.NewObjectId()
            build.id = newId
            EbonBuildsDB.builds[newId] = build
            EbonBuildsDB.builds[id] = nil
            if EbonBuildsCharDB.activeBuildId == id then
                EbonBuildsCharDB.activeBuildId = newId
                Notify()
            end
        end
    end
    if classChanged and EbonBuildsCharDB.activeBuildId == id then
        Notify()
    end
    return build
end

function EbonBuilds.Build.Delete(id)
    if not id then return end
    EbonBuildsDB.builds[id] = nil
    if EbonBuildsCharDB.activeBuildId == id then
        EbonBuildsCharDB.activeBuildId = nil
        Notify()
    end
end
