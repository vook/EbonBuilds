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

-- Mock EbonholdPlayerRunData (global set by ProjectEbonhold)
_G.EbonholdPlayerRunData = {
    usedRerolls = 0,
    totalRerolls = 3,
    usedFreezes = 0,
    totalFreezes = 3,
    remainingBanishes = 3,
}

-- Mock ProjectEbonhold namespace
_G.ProjectEbonhold = {
    PerkService = {
        GetGrantedPerks = function()
            return _G.MOCK_GRANTED_PERKS or {}
        end,
        GetLockedPerks = function()
            return _G.MOCK_LOCKED_PERKS or {}
        end,
        GetCurrentChoice = function()
            return _G.MOCK_CURRENT_CHOICES or {}
        end,
        SelectPerk = function(spellId)
            _G.MOCK_LAST_SELECT = spellId
            return true
        end,
        BanishPerk = function(index)
            _G.MOCK_LAST_BANISH = index
            return true
        end,
        FreezePerk = function(index)
            _G.MOCK_LAST_FREEZE = index
            return true
        end,
        RequestReroll = function()
            _G.MOCK_LAST_REROLL = true
            return true
        end,
    },
    PerkUI = {},
    PerkDatabase = _G.MOCK_PERK_DATABASE or {},
    PerkDropSources = _G.MOCK_PERK_DROP_SOURCES or {},
    PerkDropSourceByGroup = _G.MOCK_PERK_DROP_SOURCE_BY_GROUP or {},
    Constants = {
        ENABLE_BANISH_SYSTEM = true,
    },
}

-- Stub EbonBuilds modules that Automation depends on
_G.EbonBuilds.Toast = { ShowAutomationResult = function() end }
_G.EbonBuilds.Session = { LogAction = function() end }
