-- EbonBuilds: modules/weights/Weights.lua
-- Responsibility: read/write echo weights stored on the active build.

EbonBuilds.Weights = {}

function EbonBuilds.Weights.Init()
    -- Storage now lives on each build; nothing to pre-allocate globally.
end

-- Returns the weight for the named echo on the active build, or 0.
function EbonBuilds.Weights.Get(echoName)
    local weights = EbonBuilds.Build.GetActiveWeights()
    if not weights then return 0 end
    return weights[echoName] or 0
end

-- Persists a weight value. value must be an integer >= 0; invalid input is ignored.
-- No-op if there is no active build.
function EbonBuilds.Weights.Set(echoName, value)
    if type(value) ~= "number" then return end
    local intVal = math.floor(value)
    if intVal < 0 then return end
    local weights = EbonBuilds.Build.GetActiveWeights()
    if not weights then return end
    weights[echoName] = intVal
end
