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
        autoBanishPct    = 20,
        autoRerollPct    = 120,
        autoFreezePct    = 80,
        freezePenaltyPct = 10,
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
    for i = 1, 4 do
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

local function EnsureStats(build)
    build.stats = build.stats or {
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
    }
    build.stats.qualityPicks = build.stats.qualityPicks or { 0, 0, 0, 0, 0 }
    build.stats.mostPicked   = build.stats.mostPicked   or {}
    build.stats.mostBanned   = build.stats.mostBanned   or {}
    if build.automationEnabled == nil then build.automationEnabled = true end
    if not build.author then build.author = "Unknown" end
    if not build.lastModified then build.lastModified = date("%Y-%m-%d %H:%M:%S") end
    if build.isPublic == nil then build.isPublic = false end
    if build.validated == nil then build.validated = false end
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
            lockedEchoes = { nil, nil, nil, nil },
            echoWeights     = legacy,
            settings        = DefaultSettings(),
            version         = 1,
        }
        EbonBuildsDB.activeBuildId = id
    end
    EbonBuildsDB.echoWeights = nil

    for _, b in pairs(EbonBuildsDB.builds) do EnsureSettings(b); EnsureStats(b) end
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
    for _, b in pairs(EbonBuildsDB.builds) do
        if b.isPublic then out[#out + 1] = b end
    end
    table.sort(out, function(a, b) return (a.lastModified or "") > (b.lastModified or "") end)
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

function EbonBuilds.Build.NewObject(data)
    local id = EbonBuilds.Build.NewId()
    local build = {
        id              = id,
        title           = data.title or "Untitled",
        class           = data.class or PlayerClassToken(),
        spec            = data.spec or PlayerTopTalentTab(),
        comments        = data.comments or "",
        lockedEchoes = data.lockedEchoes or { nil, nil, nil, nil },
        echoWeights     = data.echoWeights or {},
        settings        = data.settings or DefaultSettings(),
        version         = 1,
        author          = data.author or UnitName("player") or "Unknown",
        lastModified    = data.lastModified or date("%Y-%m-%d %H:%M:%S"),
        automationEnabled = (data.automationEnabled ~= nil) and data.automationEnabled or true,
        isPublic         = data.isPublic or false,
        validated         = data.validated or false,
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
    EbonBuildsDB.pendingWeights = nil
    EbonBuildsDB.builds[build.id] = build
    return build
end

function EbonBuilds.Build.UpdateFromPublic(localBuild, publicBuild)
    localBuild.title            = publicBuild.title            or localBuild.title
    localBuild.class            = publicBuild.class            or localBuild.class
    localBuild.spec             = publicBuild.spec             or localBuild.spec
    localBuild.comments         = publicBuild.comments         or localBuild.comments
    localBuild.lockedEchoes     = { nil, nil, nil, nil }
    for i = 1, 4 do
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
    if data.automationEnabled ~= nil then build.automationEnabled = data.automationEnabled end
    if data.isPublic ~= nil then build.isPublic = data.isPublic end
    build.version         = (build.version or 1) + 1
    build._checksum       = EbonBuilds.Build.Checksum(build)
    if build._checksum ~= oldChecksum then
        build.lastModified = date("%Y-%m-%d %H:%M:%S")
    end
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
