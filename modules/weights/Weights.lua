-- EbonBuilds: modules/weights/Weights.lua
-- Responsibility: read/write echo weights stored on the active build.
--
-- Weight key format:
--   base weight  : "Echo Name"           (integer 0–100)
--   quality tier : "Echo Name\0Q"        (Q = 0..4; \0 is the delimiter)
--
-- GetForQuality returns the quality-specific weight if set, otherwise falls
-- back to the base weight.  This means existing builds keep working unchanged
-- and per-quality weights are purely additive.

EbonBuilds.Weights = {}

local QUALITY_SEP = "\0"  -- not a valid echo name char

local function QKey(name, quality)
    return name .. QUALITY_SEP .. tostring(quality)
end

-- Returns true when the key is a quality-keyed entry (contains the separator).
local function IsQKey(key)
    return key:find(QUALITY_SEP, 1, true) ~= nil
end

EbonBuilds.Weights.QUALITY_SEP = QUALITY_SEP
EbonBuilds.Weights.IsQKey      = IsQKey
EbonBuilds.Weights.QKey        = QKey

function EbonBuilds.Weights.Init()
    -- Storage now lives on each build; nothing to pre-allocate globally.
end

-- Returns the base weight for the named echo on the active build, or 0.
function EbonBuilds.Weights.Get(echoName)
    local weights = EbonBuilds.Build.GetActiveWeights()
    if not weights then return 0 end
    local w = weights[echoName] or 0
    if w > 100 then return 100 end
    return w
end

-- Returns the quality-specific weight when explicitly set, otherwise falls
-- back to the base echo weight.
function EbonBuilds.Weights.GetForQuality(echoName, quality)
    local weights = EbonBuilds.Build.GetActiveWeights()
    if not weights then return 0 end
    local qkey = QKey(echoName, quality)
    if weights[qkey] ~= nil then
        local w = weights[qkey]
        if w > 100 then return 100 end
        return w
    end
    local w = weights[echoName] or 0
    if w > 100 then return 100 end
    return w
end

-- Returns true when there is an explicit per-quality override (not just a fallback).
function EbonBuilds.Weights.HasQualityOverride(echoName, quality)
    local weights = EbonBuilds.Build.GetActiveWeights()
    if not weights then return false end
    return weights[QKey(echoName, quality)] ~= nil
end

-- Persists a base weight value. value must be an integer 0–100; invalid input is ignored.
-- No-op if there is no active build.
function EbonBuilds.Weights.Set(echoName, value)
    if type(value) ~= "number" then return end
    local intVal = math.floor(value)
    if intVal < 0 then return end
    if intVal > 100 then intVal = 100 end
    local weights = EbonBuilds.Build.GetActiveWeights()
    if not weights then return end
    weights[echoName] = intVal
    if EbonBuilds.Automation and EbonBuilds.Automation.ResetPeakCache then
        EbonBuilds.Automation.ResetPeakCache()
    end
end

-- Persists a per-quality weight override.
-- Pass nil or a negative number to clear the override (revert to base weight).
function EbonBuilds.Weights.SetForQuality(echoName, quality, value)
    local weights = EbonBuilds.Build.GetActiveWeights()
    if not weights then return end
    local qkey = QKey(echoName, quality)
    if value == nil or (type(value) == "number" and value < 0) then
        weights[qkey] = nil
        if EbonBuilds.Automation and EbonBuilds.Automation.ResetPeakCache then
            EbonBuilds.Automation.ResetPeakCache()
        end
        return
    end
    if type(value) ~= "number" then return end
    local intVal = math.floor(value)
    if intVal > 100 then intVal = 100 end
    weights[qkey] = intVal
    if EbonBuilds.Automation and EbonBuilds.Automation.ResetPeakCache then
        EbonBuilds.Automation.ResetPeakCache()
    end
end

EbonBuilds.Weights.MAX = 100

local QUALITY_LABELS = {
    [0] = "Common", [1] = "Uncommon", [2] = "Rare", [3] = "Epic", [4] = "Legendary",
}

local function BaseNameFromQKey(key)
    local sep = QUALITY_SEP
    local pos = key:find(sep, 1, true)
    if not pos then return nil end
    return key:sub(1, pos - 1)
end

-- Collect echo names with any configured weight (base or per-quality override).
function EbonBuilds.Weights.CollectWeightedEchoes(weights)
    weights = weights or EbonBuilds.Build.GetActiveWeights() or {}
    local byName = {}

    local function note(name)
        if not name or name == "" then return end
        if not byName[name] then
            byName[name] = true
        end
    end

    for key, w in pairs(weights) do
        if type(w) == "number" and w > 0 then
            if IsQKey(key) then
                note(BaseNameFromQKey(key))
            else
                note(key)
            end
        end
    end

    local entries = {}
    for name in pairs(byName) do
        entries[#entries + 1] = {
            name = name,
            baseWeight = weights[name] or 0,
        }
    end

    table.sort(entries, function(a, b)
        if a.baseWeight ~= b.baseWeight then
            return a.baseWeight > b.baseWeight
        end
        return a.name < b.name
    end)

    return entries
end

function EbonBuilds.Weights.FormatExportList(build)
    build = build or (EbonBuilds.Build.GetActive and EbonBuilds.Build.GetActive())
    if not build then return "No build selected." end

    local weights = EbonBuilds.Build.GetActiveWeights() or build.echoWeights or {}
    local entries = EbonBuilds.Weights.CollectWeightedEchoes(weights)
    local lines = {}

    local title = build.title or "Untitled"
    lines[#lines + 1] = string.format("Echo Weights - %s", title)
    if build.class then
        lines[#lines + 1] = string.format("Class: %s", build.class)
    end
    if build.comments and build.comments ~= "" then
        lines[#lines + 1] = build.comments
    end
    lines[#lines + 1] = ""

    if #entries == 0 then
        lines[#lines + 1] = "No echoes with weights configured."
    else
        for _, entry in ipairs(entries) do
            lines[#lines + 1] = string.format("%3d  %s", entry.baseWeight, entry.name)
            for q = 0, 4 do
                local qkey = QKey(entry.name, q)
                if weights[qkey] ~= nil and type(weights[qkey]) == "number" then
                    local label = QUALITY_LABELS[q] or ("Tier " .. tostring(q))
                    lines[#lines + 1] = string.format("       %s: %d", label, weights[qkey])
                end
            end
        end
    end

    return table.concat(lines, "\n")
end

function EbonBuilds.Weights.ShowExportListDialog(build)
    if not EbonBuilds.ExportImport or not EbonBuilds.ExportImport.ShowTextExportDialog then
        return
    end
    local text = EbonBuilds.Weights.FormatExportList(build)
    local buildTitle = build and build.title or "Echo Weights"
    EbonBuilds.ExportImport.ShowTextExportDialog("Export Echo Weights - " .. buildTitle, text)
end
