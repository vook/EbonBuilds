-- EbonBuilds: modules/build/Build.lua
-- Responsibility: build CRUD, UUID generation, active-build tracking,
-- one-time migration from the legacy single-weight-table shape.

EbonBuilds.Build = {}

local function DefaultSettings()
    return {
        qualityBonus        = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0 },
        qualityBonusMode    = { [0] = false, [1] = false, [2] = false, [3] = false, [4] = false },
        familyBonus         = { Tank = 0, Survivability = 0, Healer = 0, Caster = 0, Melee = 0, Ranged = 0, ["No family"] = 0 },
        familyBonusMode     = { Tank = false, Survivability = false, Healer = false, Caster = false, Melee = false, Ranged = false, ["No family"] = false },
        banishFamilyWhitelist = {},
        autoBanishPct    = 0,
        autoRerollPct    = 0,
        autoFreezePct    = 0,
        freezePenaltyPct = 0,
        noveltyValue     = 0,
        noveltyMode      = false,
        echoBanList      = {},
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

------------------------------------------------------------------------
-- Migration
------------------------------------------------------------------------

function EbonBuilds.Build.Migrate()
    EbonBuildsDB.builds        = EbonBuildsDB.builds        or {}
    EbonBuildsDB.activeBuildId = EbonBuildsDB.activeBuildId or nil

    local legacy = EbonBuildsDB.echoWeights
    if legacy and not next(EbonBuildsDB.builds) then
        local id = EbonBuilds.Build.NewId()
        EbonBuildsDB.builds[id] = {
            id              = id,
            title           = "Migrated",
            class           = PlayerClassToken(),
            spec            = PlayerTopTalentTab(),
            comments        = "",
            permanentEchoes = { nil, nil, nil, nil },
            echoWeights     = legacy,
            settings        = DefaultSettings(),
            version         = 1,
        }
        EbonBuildsDB.activeBuildId = id
    end
    EbonBuildsDB.echoWeights = nil

    for _, b in pairs(EbonBuildsDB.builds) do EnsureSettings(b) end
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

function EbonBuilds.Build.Get(id)
    if not id then return nil end
    return EbonBuildsDB.builds[id]
end

function EbonBuilds.Build.GetActive()
    return EbonBuilds.Build.Get(EbonBuildsDB.activeBuildId)
end

function EbonBuilds.Build.SetActive(id)
    if EbonBuildsDB.activeBuildId == id then return end
    EbonBuildsDB.activeBuildId = id
    Notify()
end

function EbonBuilds.Build.GetActiveWeights()
    local build = EbonBuilds.Build.GetActive()
    if build then
        build.echoWeights = build.echoWeights or {}
        return build.echoWeights
    end
    EbonBuildsDB.pendingWeights = EbonBuildsDB.pendingWeights or {}
    return EbonBuildsDB.pendingWeights
end

function EbonBuilds.Build.Create(data)
    local id = EbonBuilds.Build.NewId()
    local build = {
        id              = id,
        title           = data.title or "Untitled",
        class           = data.class or PlayerClassToken(),
        spec            = data.spec or PlayerTopTalentTab(),
        comments        = data.comments or "",
        permanentEchoes = data.permanentEchoes or { nil, nil, nil, nil },
        echoWeights     = EbonBuildsDB.pendingWeights or {},
        settings        = data.settings or DefaultSettings(),
        version         = 1,
    }
    EbonBuildsDB.pendingWeights = nil
    EbonBuildsDB.builds[id] = build
    return build
end

function EbonBuilds.Build.Save(id, data)
    local build = EbonBuildsDB.builds[id]
    if not build then return nil end
    local classChanged = data.class and data.class ~= build.class
    build.title           = data.title           or build.title
    build.class           = data.class           or build.class
    build.spec            = data.spec            or build.spec
    build.comments        = data.comments        or build.comments
    build.permanentEchoes = data.permanentEchoes or build.permanentEchoes
    if data.settings then build.settings = data.settings end
    build.version         = (build.version or 1) + 1
    if classChanged and EbonBuildsDB.activeBuildId == id then
        Notify()
    end
    return build
end

function EbonBuilds.Build.Delete(id)
    if not id then return end
    EbonBuildsDB.builds[id] = nil
    if EbonBuildsDB.activeBuildId == id then
        EbonBuildsDB.activeBuildId = nil
        Notify()
    end
end
