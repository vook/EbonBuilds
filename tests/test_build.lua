-- tests/test_build.lua
-- Tests for Build: DefaultSettings, EnsureSettings, CloneSettings, Checksum,
-- NewObjectId, NewObject.

TestBuild = {}

function TestBuild.testDefaultSettingsStructure()
    local s = EbonBuilds.Build.DefaultSettings()
    assertNotNil(s)
    assertNotNil(s.qualityBonus)
    assertNotNil(s.qualityBonusMode)
    assertNotNil(s.familyBonus)
    assertNotNil(s.familyBonusMode)
    assertNotNil(s.banishFamilyWhitelist)
    assertNotNil(s.echoBanList)
end

function TestBuild.testDefaultSettingsQualityRange()
    local s = EbonBuilds.Build.DefaultSettings()
    for q = 0, 4 do
        assertEquals(s.qualityBonus[q], 0)
        assertEquals(s.qualityBonusMode[q], false)
    end
end

function TestBuild.testDefaultSettingsFamilyKeys()
    local s = EbonBuilds.Build.DefaultSettings()
    local families = { "Tank", "Survivability", "Healer", "Caster", "Melee", "Ranged", "No family" }
    for _, f in ipairs(families) do
        assertEquals(s.familyBonus[f], 0)
        assertEquals(s.familyBonusMode[f], false)
    end
end

function TestBuild.testDefaultSettingsThresholds()
    local s = EbonBuilds.Build.DefaultSettings()
    assertEquals(s.autoBanishPct, 20)
    assertEquals(s.autoRerollPct, 120)
    assertEquals(s.rerollGuardPct, 90)
    assertEquals(s.autoFreezePct, 80)
    assertEquals(s.freezePenaltyPct, 10)
end

function TestBuild.testEnsureSettingsFillsMissingKeys()
    local build = { settings = { autoBanishPct = 50 } }
    EbonBuilds.Build.EnsureSettings(build)
    assertEquals(build.settings.autoBanishPct, 50)
    assertNotNil(build.settings.qualityBonus)
    assertEquals(build.settings.qualityBonus[2], 0)
end

function TestBuild.testEnsureSettingsFillsMissingNested()
    local build = { settings = { qualityBonus = { [0] = 10 } } }
    EbonBuilds.Build.EnsureSettings(build)
    assertEquals(build.settings.qualityBonus[0], 10)
    assertEquals(build.settings.qualityBonus[1], 0)  -- filled by default
    assertNotNil(build.settings.familyBonus)
end

function TestBuild.testCloneSettingsDeep()
    local original = { a = 1, b = { c = 2, d = { 3 } } }
    local copy = EbonBuilds.Build.CloneSettings(original)
    assertEquals(copy.a, 1)
    assertEquals(copy.b.c, 2)
    assertEquals(copy.b.d[1], 3)
    copy.b.c = 99
    assertEquals(original.b.c, 2)
end

function TestBuild.testCloneSettingsLeavesOriginalUnchanged()
    local s = EbonBuilds.Build.DefaultSettings()
    local clone = EbonBuilds.Build.CloneSettings(s)
    assertEquals(clone.autoBanishPct, s.autoBanishPct)
    clone.autoBanishPct = 99
    assertNotEquals(clone.autoBanishPct, s.autoBanishPct)
end

function TestBuild.testNewObjectIdFormat()
    local id = EbonBuilds.Build.NewObjectId()
    assertNotNil(id)
    assertEquals(#id, 24)
    assertStrMatches(id, "^%x+$")  -- hex characters only
end

function TestBuild.testNewObjectIdUniqueness()
    local seen = {}
    for _ = 1, 100 do
        local id = EbonBuilds.Build.NewObjectId()
        assertNil(seen[id], "Duplicate ObjectId: " .. id)
        seen[id] = true
    end
end

function TestBuild.testNewObjectDefaults()
    local build = EbonBuilds.Build.NewObject({ title = "Test" })
    assertEquals(build.title, "Test")
    assertNotNil(build.id)
    assertEquals(#build.id, 24)
    assertNotNil(build.settings)
    assertNotNil(build.stats)
    assertEquals(build.automationEnabled, true)
    assertEquals(build.version, 1)
end

function TestBuild.testChecksum()
    local build1 = EbonBuilds.Build.NewObject({ title = "Test Build", class = "WARRIOR", spec = 1 })
    local build2 = EbonBuilds.Build.NewObject({ title = "Test Build", class = "WARRIOR", spec = 1 })
    assertEquals(EbonBuilds.Build.Checksum(build1), EbonBuilds.Build.Checksum(build2))
end

function TestBuild.testChecksumDiffersOnTitleChange()
    local build = EbonBuilds.Build.NewObject({ title = "Test A" })
    local cs1 = EbonBuilds.Build.Checksum(build)
    build.title = "Test B"
    local cs2 = EbonBuilds.Build.Checksum(build)
    assertNotEquals(cs1, cs2)
end

function TestBuild.testChecksumDiffersOnClassChange()
    local build = EbonBuilds.Build.NewObject({ class = "WARRIOR" })
    local cs1 = EbonBuilds.Build.Checksum(build)
    build.class = "MAGE"
    local cs2 = EbonBuilds.Build.Checksum(build)
    assertNotEquals(cs1, cs2)
end

function TestBuild.testChecksumIndependentOfId()
    local build1 = EbonBuilds.Build.NewObject({ title = "Test" })
    local build2 = EbonBuilds.Build.NewObject({ title = "Test" })
    assertEquals(EbonBuilds.Build.Checksum(build1), EbonBuilds.Build.Checksum(build2))
end
