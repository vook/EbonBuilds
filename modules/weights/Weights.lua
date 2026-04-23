-- EbonBuilds: modules/weights/Weights.lua
-- Responsibility: read/write echo weights stored in EbonBuildsDB.echoWeights.

EbonBuilds.Weights = {}

function EbonBuilds.Weights.Init()
    EbonBuildsDB.echoWeights = EbonBuildsDB.echoWeights or {}
end

-- Returns the weight for the named echo, or 0 if not set.
function EbonBuilds.Weights.Get(echoName)
    return EbonBuildsDB.echoWeights[echoName] or 0
end

-- Persists a weight value. value must be an integer >= 0; invalid input is ignored.
function EbonBuilds.Weights.Set(echoName, value)
    if type(value) ~= "number" then return end
    local intVal = math.floor(value)
    if intVal < 0 then return end
    EbonBuildsDB.echoWeights[echoName] = intVal
end
