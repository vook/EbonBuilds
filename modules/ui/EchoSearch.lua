-- EbonBuilds: modules/ui/EchoSearch.lua
-- Responsibility: match echo list entries by name or tooltip effect text.

EbonBuilds.EchoSearch = {}

local descriptionByName = {}
local descriptionReady = false
local prewarmQueue = nil
local prewarmIndex = 1
local prewarmCallbacks = {}
local prewarmPaused = false
local PREWARM_BATCH = 40

local function StripColorCodes(text)
    if not text then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|h", "")
    return text
end

local function GetUtils()
    return _G.utils
end

local function FetchDescription(spellId)
    local utils = GetUtils()
    if not utils or not utils.GetSpellDescription or not spellId then
        return nil
    end
    local stacks = 1
    local db = (EbonBuilds.EchoOwnership and EbonBuilds.EchoOwnership.GetPerkDatabase())
        or (ProjectEbonhold and ProjectEbonhold.PerkDatabase)
    if db and db[spellId] and db[spellId].maxStack then
        stacks = db[spellId].maxStack
    end
    local ok, desc = pcall(utils.GetSpellDescription, spellId, 500, stacks)
    if not ok or not desc or desc == "" or desc == "Click for details" then
        return nil
    end
    return StripColorCodes(desc):lower()
end

local function BuildCombinedDescription(entry)
    local name = entry and entry.name
    if not name then return false end
    if descriptionByName[name] ~= nil then
        return descriptionByName[name]
    end

    local parts = {}
    local seenSpell = {}
    local function addSpellId(spellId)
        if not spellId or seenSpell[spellId] then return end
        seenSpell[spellId] = true
        local desc = FetchDescription(spellId)
        if desc then parts[#parts + 1] = desc end
    end

    if entry.spellIds then
        for q = 0, 4 do
            addSpellId(entry.spellIds[q])
        end
    end
    addSpellId(entry.spellId)

    local combined = (#parts > 0) and table.concat(parts, " ") or false
    descriptionByName[name] = combined
    return combined
end

local function CacheDescription(name, entry)
    if not name or descriptionByName[name] ~= nil then
        return descriptionByName[name]
    end
    if type(entry) == "table" then
        return BuildCombinedDescription(entry)
    end
    -- Legacy: entry may be a spellId when prewarming from flat list.
    local desc = FetchDescription(entry)
    descriptionByName[name] = desc or false
    return descriptionByName[name]
end

function EbonBuilds.EchoSearch.NameMatches(name, text)
    if not text or text == "" then return true end
    if not name or name == "" then return false end
    local lower = name:lower()
    local from = 1
    while true do
        local s, e = lower:find(text, from, true)
        if not s then return false end
        if s == 1 then return true end
        local prev = lower:sub(s - 1, s - 1)
        if prev == " " or prev == "-" or prev == "'" then return true end
        from = e + 1
    end
end

local function DescriptionMatches(entry, text)
    if not text or text == "" then return false end
    local name = entry and entry.name
    if not name then return false end
    local cached = CacheDescription(name, entry)
    if not cached or cached == false then return false end
    return cached:find(text, 1, true) ~= nil
end

-- entry: { name, spellId, spellIds? }
function EbonBuilds.EchoSearch.Matches(entry, text)
    text = text and text:lower() or ""
    if text == "" then return true end
    if not entry then return false end
    if EbonBuilds.EchoSearch.NameMatches(entry.name, text) then return true end
    return DescriptionMatches(entry, text)
end

function EbonBuilds.EchoSearch.IsDescriptionCacheReady()
    return descriptionReady
end

function EbonBuilds.EchoSearch.OnDescriptionCacheReady(fn)
    if descriptionReady then
        fn()
        return
    end
    prewarmCallbacks[#prewarmCallbacks + 1] = fn
end

function EbonBuilds.EchoSearch.InvalidateCache()
    descriptionByName = {}
    descriptionReady = false
    prewarmQueue = nil
    prewarmIndex = 1
end

local function FinishPrewarm()
    prewarmQueue = nil
    descriptionReady = true
    for i = 1, #prewarmCallbacks do
        prewarmCallbacks[i]()
    end
    prewarmCallbacks = {}
end

function EbonBuilds.EchoSearch.PrewarmStep()
    if not prewarmQueue then return end
    -- Suspend while a loading screen is active. Touching spell/tooltip APIs
    -- (SetHyperlink) mid zone-transition can hard-crash the 3.3.5 client.
    if prewarmPaused then
        C_Timer.After(0.5, EbonBuilds.EchoSearch.PrewarmStep)
        return
    end
    local last = math.min(prewarmIndex + PREWARM_BATCH - 1, #prewarmQueue)
    for i = prewarmIndex, last do
        local item = prewarmQueue[i]
        CacheDescription(item.name, item.entry or item.spellId)
    end
    prewarmIndex = last + 1
    if prewarmIndex > #prewarmQueue then
        FinishPrewarm()
        return
    end
    C_Timer.After(0, EbonBuilds.EchoSearch.PrewarmStep)
end

function EbonBuilds.EchoSearch.StartPrewarm()
    if descriptionReady or prewarmQueue then return end
    local catalogReady = EbonBuilds.EchoOwnership and EbonBuilds.EchoOwnership.IsCatalogReady()
    if not catalogReady and (not ProjectEbonhold or not ProjectEbonhold.PerkDatabase) then return end
    if not EbonBuilds.EchoTableRows or not EbonBuilds.EchoTableRows.GetBestByName then return end

    local best = EbonBuilds.EchoTableRows.GetBestByName()
    prewarmQueue = {}
    for name, entry in pairs(best) do
        prewarmQueue[#prewarmQueue + 1] = {
            name  = name,
            entry = entry,
        }
    end
    prewarmIndex = 1
    if #prewarmQueue == 0 then
        FinishPrewarm()
        return
    end
    C_Timer.After(0, EbonBuilds.EchoSearch.PrewarmStep)
end

-- Prewarm is kicked off once from core/Init.lua on load. Here we only suspend it
-- during loading screens (login, checkpoint warp, teleport) so the batched
-- spell-description scan never runs mid zone-transition, which could hard-crash
-- the client with no Lua error after several warps.
local prewarmFrame = CreateFrame("Frame")
prewarmFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
prewarmFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
prewarmFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LEAVING_WORLD" then
        prewarmPaused = true
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Resume only after the world has settled. Never restarts a finished or
        -- in-flight prewarm; StartPrewarm self-guards on descriptionReady/queue.
        C_Timer.After(2, function()
            prewarmPaused = false
            if not descriptionReady and not prewarmQueue then
                EbonBuilds.EchoSearch.StartPrewarm()
            end
        end)
    end
end)
