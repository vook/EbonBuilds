-- tests/mocks/ebonhold.lua
-- Mock of ProjectEbonhold globals and EbonBuilds DB.

_G.EbonBuildsDB = {
    builds = {},
    sessions = {},
    syncPeers = {},
    lastSyncDate = nil,
    activeBuildId = nil,
    currentSessionIndex = nil,
    pendingWeights = {},
    _isEditingBuild = false,
}

_G.EbonBuilds = {}

-- Mock ProjectEbonhold namespace
_G.ProjectEbonhold = {
    PerkService = {
        GetGrantedPerks = function()
            return _G.MOCK_GRANTED_PERKS or {}
        end,
        GetLockedPerks = function()
            return _G.MOCK_LOCKED_PERKS or {}
        end,
    },
    PerkDatabase = _G.MOCK_PERK_DATABASE or {},
    PerkDropSources = _G.MOCK_PERK_DROP_SOURCES or {},
    PerkDropSourceByGroup = _G.MOCK_PERK_DROP_SOURCE_BY_GROUP or {},
}
