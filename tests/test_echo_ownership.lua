-- tests/test_echo_ownership.lua
-- Unit tests for EchoOwnership adapter (echoDiscovery + cachedPerkCounts).

local lu = _G.luaunit

TestEchoOwnership = {}

function TestEchoOwnership:setUp()
    _G.MOCK_PERK_DATABASE = {
        [200100] = {
            comment = "Arcane Cadence - Rare",
            quality = 2,
            groupId = 42,
            requiredSpell = 300100,
            classMask = 128,
            families = {},
        },
        [200101] = {
            comment = "Arcane Cadence - Epic",
            quality = 3,
            groupId = 42,
            requiredSpell = 300100,
            classMask = 128,
            families = {},
        },
    }
    _G.ProjectEbonhold.PerkDatabase = _G.MOCK_PERK_DATABASE
    _G.ProjectEbonholdDB = {
        echoDiscovery = {},
        cachedPerkCounts = {},
    }
    _G.MOCK_GRANTED_PERKS = nil
    EbonBuilds.EchoOwnership.Invalidate()
end

function TestEchoOwnership:testCharacterKey()
    local key = EbonBuilds.EchoOwnership.GetCharacterKey()
    lu.assertEquals(key, "Unknown\tTestPlayer")
end

function TestEchoOwnership:testIsDiscoveredViaEchoDiscovery()
    local key = EbonBuilds.EchoOwnership.GetCharacterKey()
    _G.ProjectEbonholdDB.echoDiscovery[key] = { [200100] = 1 }
    EbonBuilds.EchoOwnership.Invalidate()
    lu.assertTrue(EbonBuilds.EchoOwnership.IsDiscovered(200100))
    lu.assertFalse(EbonBuilds.EchoOwnership.IsDiscovered(200101))
end

function TestEchoOwnership:testIsAccountOwnedViaCachedCounts()
    _G.ProjectEbonholdDB.cachedPerkCounts["Arcane Cadence"] = 1
    EbonBuilds.EchoOwnership.Invalidate()
    lu.assertTrue(EbonBuilds.EchoOwnership.IsAccountOwned("Arcane Cadence", nil, 42, 200100))
end

function TestEchoOwnership:testIsAccountOwnedViaGroupDiscovery()
    local key = EbonBuilds.EchoOwnership.GetCharacterKey()
    _G.ProjectEbonholdDB.echoDiscovery[key] = { [200101] = 1 }
    EbonBuilds.EchoOwnership.Invalidate()
    lu.assertTrue(EbonBuilds.EchoOwnership.IsAccountOwned("Arcane Cadence", nil, 42, 200100))
end

function TestEchoOwnership:testIsRolledThisRunNilGranted()
    _G.MOCK_GRANTED_PERKS = nil
    lu.assertFalse(EbonBuilds.EchoOwnership.IsRolledThisRun("Arcane Cadence", 200100, 42))
end

function TestEchoOwnership:testIsRolledThisRunWithGranted()
    _G.MOCK_GRANTED_PERKS = {
        ["Arcane Cadence"] = { { spellId = 200100, quality = 2, stack = 1 } },
    }
    lu.assertTrue(EbonBuilds.EchoOwnership.IsRolledThisRun("Arcane Cadence", 200100, 42))
    lu.assertFalse(EbonBuilds.EchoOwnership.IsRolledThisRun("Other Echo", 999999, nil))
end

function TestEchoOwnership:testNormalizeGrantedArrayShape()
    local raw = {
        { spellId = 200100, quality = 2, stack = 1, name = "Arcane Cadence" },
    }
    local map = EbonBuilds.EchoOwnership.NormalizeGranted(raw)
    lu.assertNotNil(map["Arcane Cadence"])
    lu.assertTrue(EbonBuilds.EchoOwnership.IsRolledThisRun("Arcane Cadence", 200100, 42, map))
end

function TestEchoOwnership:testIsRolledThisRunWithLockedEcho()
    local locked = { 200101 }
    lu.assertTrue(EbonBuilds.EchoOwnership.IsRolledThisRun(
        "Arcane Cadence", 200100, 42, {}, locked))
    lu.assertFalse(EbonBuilds.EchoOwnership.IsRolledThisRun(
        "Other Echo", 999999, nil, {}, locked))
end

function TestEchoOwnership:testIsCatalogReady()
    lu.assertTrue(EbonBuilds.EchoOwnership.IsCatalogReady())
    _G.ProjectEbonhold.PerkDatabase = {}
    EbonBuilds.EchoTableRows.InvalidateCaches()
    lu.assertFalse(EbonBuilds.EchoOwnership.IsCatalogReady())
end
