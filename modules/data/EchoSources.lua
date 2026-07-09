-- EbonBuilds: modules/data/EchoSources.lua
-- Classify echo drop sources for Collection tab filtering.

EbonBuilds = EbonBuilds or {}
EbonBuilds.EchoSources = {}

local ES = EbonBuilds.EchoSources

ES.FILTER_OPTIONS = {
    { key = "special:no_tome", kind = "special", label = "No Tome Required" },
    { key = "special:unknown", kind = "special", label = "Unknown Source" },
    { key = "open_world:all", kind = "open_world", label = "All Open World", all = true },
    { key = "open_world:northrend", kind = "open_world", region = "northrend", label = "Northrend" },
    { key = "open_world:kalimdor", kind = "open_world", region = "kalimdor", label = "Kalimdor" },
    { key = "open_world:eastern_kingdoms", kind = "open_world", region = "eastern_kingdoms", label = "Eastern Kingdoms" },
    { key = "open_world:outland", kind = "open_world", region = "outland", label = "Outland" },
    { key = "raid:all", kind = "raid", label = "All Raids", all = true },
    { key = "raid:naxxramas", kind = "raid", raid = "naxxramas", label = "Naxxramas" },
    { key = "raid:ulduar", kind = "raid", raid = "ulduar", label = "Ulduar" },
    { key = "raid:trial_of_the_crusader", kind = "raid", raid = "trial_of_the_crusader", label = "Trial of the Crusader" },
    { key = "raid:icecrown_citadel", kind = "raid", raid = "icecrown_citadel", label = "Icecrown Citadel" },
    { key = "raid:onyxias_lair", kind = "raid", raid = "onyxias_lair", label = "Onyxia's Lair" },
    { key = "raid:obsidian_sanctum", kind = "raid", raid = "obsidian_sanctum", label = "Obsidian Sanctum" },
    { key = "raid:eye_of_eternity", kind = "raid", raid = "eye_of_eternity", label = "Eye of Eternity" },
    { key = "raid:black_temple", kind = "raid", raid = "black_temple", label = "Black Temple" },
    { key = "raid:culling_of_stratholme", kind = "raid", raid = "culling_of_stratholme", label = "Culling of Stratholme" },
    { key = "raid:scarlet_monastery", kind = "raid", raid = "scarlet_monastery", label = "Scarlet Monastery" },
}

local RAID_RULES = {
    { raid = "icecrown_citadel", patterns = {
        "icecrown citadel",
        "lord marrowgar", "lady deathwhisper", "gunship battle", "deathbringer saurfang",
        "festergut", "rotface", "professor putricide", "blood prince", "blood-queen",
        "valithria", "sindragosa", "lich king",
    }},
    { raid = "trial_of_the_crusader", patterns = {
        "trial of the crusader", "icecrown - trial",
        "gormok", "icehowl", "lord jaraxxus", "fjola", "lightbane", "anub'arak",
        "champions of the horde", "champions of the alliance",
    }},
    { raid = "naxxramas", patterns = { "naxxramas" } },
    { raid = "ulduar", patterns = { "ulduar" } },
    { raid = "onyxias_lair", patterns = { "onyxia" } },
    { raid = "obsidian_sanctum", patterns = { "obsidian sanctum" } },
    { raid = "eye_of_eternity", patterns = { "eye of eternity" } },
    { raid = "black_temple", patterns = { "black temple" } },
    { raid = "culling_of_stratholme", patterns = { "culling of stratholme" } },
    { raid = "scarlet_monastery", patterns = { "scarlet monastery" } },
}

local REGION_RULES = {
    { region = "northrend", patterns = {
        "northrend", "icecrown", "wintergrasp", "crystalsong", "dragonblight", "zul'drak",
        "borean tundra", "howling fjord", "grizzly hills", "sholazar basin", "storm peaks",
        "coldarra", "malykriss", "forlorn woods",
    }},
    { region = "kalimdor", patterns = {
        "kalimdor", "durotar", "barrens", "feralas", "tanaris", "ungoro", "silithus",
        "winterspring", "ashenvale", "darkshore", "moonglade", "dustwallow", "thousand needles",
        "stonetalon", "desolace", "felwood", "azshara", "ungoro crater", "southwind",
        "stranglethorn", "booty bay",
    }},
    { region = "eastern_kingdoms", patterns = {
        "eastern kingdoms", "plaguelands", "tirisfal", "silverpine", "hillsbrad", "arathi",
        "wetlands", "loch modan", "redridge", "duskwood", "westfall", "elwynn", "dun morogh",
        "searing gorge", "burning steppes", "blasted lands", "swamp of sorrows", "stranglethorn",
        "hinterlands", "alterac", "hearthglen", "blackrock", "scarlet encampments",
        "pestilent scar", "sorrow hill", "writhing haunt",
    }},
    { region = "outland", patterns = {
        "outland", "hellfire", "zangarmarsh", "terokkar", "nagrand", "blade's edge",
        "netherstorm", "shadowmoon", "shattrath", "bash'ir",
    }},
}

local function NormalizeText(text)
    if not text or text == "" then return "" end
    text = text:lower()
    text = text:gsub("^can be found on ", "")
    text = text:gsub("^found on ", "")
    return text
end

local function MatchPatterns(text, patterns)
    for i = 1, #patterns do
        if text:find(patterns[i], 1, true) then
            return true
        end
    end
    return false
end

local function DetectRaid(text)
    for i = 1, #RAID_RULES do
        local rule = RAID_RULES[i]
        if MatchPatterns(text, rule.patterns) then
            return rule.raid
        end
    end
    return nil
end

local function DetectRegion(text)
    for i = 1, #REGION_RULES do
        local rule = REGION_RULES[i]
        if MatchPatterns(text, rule.patterns) then
            return rule.region
        end
    end
    return nil
end

function ES.IsNoTomeRequired(entry)
    if not entry then return false end
    if entry.requiresTome == false then return true end
    local text = NormalizeText(entry.dropSource or "")
    return text == "no tome required"
end

function ES.IsUnknownSource(entry)
    if not entry or ES.IsNoTomeRequired(entry) then return false end
    local text = NormalizeText(entry.dropSource or "")
    return text == "" or text == "unknown"
end

local function ClassifyFromText(dropSource)
    local text = NormalizeText(dropSource or "")
    if text == "" or text == "unknown" then
        return { kind = "unknown", region = nil, raid = nil }
    end
    if text == "no tome required" then
        return { kind = "no_tome", region = nil, raid = nil }
    end

    local raid = DetectRaid(text)
    if raid then
        return { kind = "raid", region = DetectRegion(text) or "northrend", raid = raid }
    end

    local region = DetectRegion(text)
    if region then
        return { kind = "open_world", region = region, raid = nil }
    end

    return { kind = "unclassified", region = nil, raid = nil }
end

function ES.Classify(groupId, dropSource)
    local metaTable = EbonBuilds.EchoSourceMeta
    if groupId and metaTable and metaTable[groupId] then
        local meta = metaTable[groupId]
        return {
            kind = meta.kind or "unknown",
            region = meta.region,
            raid = meta.raid,
        }
    end

    local sourceText = dropSource
    local locations = EbonBuilds.EchoLocations
    if groupId and locations and locations[groupId] then
        sourceText = locations[groupId]
    end

    return ClassifyFromText(sourceText)
end

function ES.EntryFilterKey(entry)
    if not entry then return nil end
    if ES.IsNoTomeRequired(entry) then
        return "special:no_tome"
    end
    local info = ES.Classify(entry.groupId, entry.dropSource)
    if info.kind == "open_world" and info.region then
        return "open_world:" .. info.region
    end
    if info.kind == "raid" and info.raid then
        return "raid:" .. info.raid
    end
    if ES.IsUnknownSource(entry) then
        return "special:unknown"
    end
    return nil
end

function ES.MatchesSelection(entry, selKey)
    if not selKey or not entry then return false end

    if selKey == "special:no_tome" then
        return ES.IsNoTomeRequired(entry)
    end

    if selKey == "special:unknown" then
        return ES.IsUnknownSource(entry)
    end

    local info = ES.Classify(entry.groupId, entry.dropSource)

    if selKey == "open_world:all" then
        return info.kind == "open_world"
    end
    if selKey == "raid:all" then
        return info.kind == "raid"
    end

    return ES.EntryFilterKey(entry) == selKey
end

function ES.PassesFilter(entry, selected)
    if not selected or not next(selected) then return true end

    for selKey, enabled in pairs(selected) do
        if enabled and ES.MatchesSelection(entry, selKey) then
            return true
        end
    end
    return false
end

function ES.ClearSelection(selected)
    if not selected then return end
    for key in pairs(selected) do
        selected[key] = nil
    end
end

function ES.CountSelected(selected)
    local count = 0
    if not selected then return 0 end
    for _ in pairs(selected) do
        count = count + 1
    end
    return count
end

function ES.FilterLabel(selected)
    local count = ES.CountSelected(selected)
    if count == 0 then return "All sources" end
    return "Sources (" .. count .. ")"
end
