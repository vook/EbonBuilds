-- tests/test_export_import.lua
-- Tests for ExportImport: JSON encode/decode, Export/Import pipeline.
-- Base64 is tested indirectly through export/import roundtrips.

-- Assertions available globally: assertEquals, assertNotNil, assertStrContains, etc.

TestJSON = {}

function TestJSON.testEncodeNull()
    assertEquals(EbonBuilds.ExportImport.JSONEncode(nil), "null")
end

function TestJSON.testEncodeBool()
    assertEquals(EbonBuilds.ExportImport.JSONEncode(true), "true")
    assertEquals(EbonBuilds.ExportImport.JSONEncode(false), "false")
end

function TestJSON.testEncodeNumber()
    assertEquals(EbonBuilds.ExportImport.JSONEncode(42), "42")
    assertEquals(EbonBuilds.ExportImport.JSONEncode(-3.14), "-3.14")
    assertEquals(EbonBuilds.ExportImport.JSONEncode(0), "0")
end

function TestJSON.testEncodeString()
    assertEquals(EbonBuilds.ExportImport.JSONEncode("hello"), '"hello"')
end

function TestJSON.testEncodeArray()
    local result = EbonBuilds.ExportImport.JSONEncode({1, 2, 3})
    assertEquals(result, "[1,2,3]")
end

function TestJSON.testEncodeObject()
    local result = EbonBuilds.ExportImport.JSONEncode({a = 1, b = "two"})
    assertStrContains(result, '"a":1')
    assertStrContains(result, '"b":"two"')
end

function TestJSON.testRoundtrip()
    local inputs = { true, false, 42, -3.14, "hello", { 1, 2, 3 } }
    for _, val in ipairs(inputs) do
        local encoded = EbonBuilds.ExportImport.JSONEncode(val)
        local decoded = EbonBuilds.ExportImport.JSONDecode(encoded)
        assertEquals(
            EbonBuilds.ExportImport.JSONEncode(decoded),
            EbonBuilds.ExportImport.JSONEncode(val),
            "Roundtrip failed for: " .. tostring(encoded)
        )
    end
end

function TestJSON.testObjectRoundtrip()
    local obj = { a = 1, b = "two", c = { true, false } }
    local encoded = EbonBuilds.ExportImport.JSONEncode(obj)
    local decoded = EbonBuilds.ExportImport.JSONDecode(encoded)
    assertEquals(decoded.a, 1)
    assertEquals(decoded.b, "two")
    assertEquals(#decoded.c, 2)
    assertEquals(decoded.c[1], true)
    assertEquals(decoded.c[2], false)
end

function TestJSON.testDecodeEmpty()
    assertNil(EbonBuilds.ExportImport.JSONDecode(""))
    assertNil(EbonBuilds.ExportImport.JSONDecode(nil))
end

TestExportImport = {}

function TestExportImport.testExportBuild()
    local build = EbonBuilds.Build.NewObject({
        title = "Test Build",
        class = "WARRIOR",
        spec = 1,
        echoWeights = { ["Fireball"] = 100, ["Frostbolt"] = 50 },
    })
    local b64 = EbonBuilds.ExportImport.ExportBuild(build)
    assertNotNil(b64)
    assertNotEquals(b64, "")
end

function TestExportImport.testRoundtrip()
    local build = EbonBuilds.Build.NewObject({
        title = "Test Build",
        class = "WARRIOR",
        spec = 2,
        echoWeights = { ["Fireball"] = 100 },
        settings = EbonBuilds.Build.DefaultSettings(),
    })
    local b64 = EbonBuilds.ExportImport.ExportBuild(build)
    local decoded = EbonBuilds.ExportImport.DecodeBuild(b64)
    assertNotNil(decoded)
    assertEquals(decoded.title, "Test Build")
    assertEquals(decoded.class, "WARRIOR")
    assertEquals(decoded.spec, 2)
end

function TestExportImport.testRoundtripPreservesWeights()
    local build = EbonBuilds.Build.NewObject({
        title = "Test",
        echoWeights = { ["Fireball"] = 100, ["Frostbolt"] = 50 },
    })
    local b64 = EbonBuilds.ExportImport.ExportBuild(build)
    local decoded = EbonBuilds.ExportImport.DecodeBuild(b64)
    assertEquals(decoded.echoWeights["Fireball"], 100)
    assertEquals(decoded.echoWeights["Frostbolt"], 50)
end

function TestExportImport.testRoundtripFiltersZeroWeights()
    local build = EbonBuilds.Build.NewObject({
        title = "Test",
        echoWeights = { ["Fireball"] = 100, ["Frostbolt"] = 0 },
    })
    local b64 = EbonBuilds.ExportImport.ExportBuild(build)
    local decoded = EbonBuilds.ExportImport.DecodeBuild(b64)
    assertNotNil(decoded.echoWeights["Fireball"])
    assertNil(decoded.echoWeights["Frostbolt"])
end

function TestExportImport.testRoundtripFiltersNegativeWeights()
    local build = EbonBuilds.Build.NewObject({
        title = "Test",
        echoWeights = { ["Fireball"] = 100, ["Frostbolt"] = -5 },
    })
    local b64 = EbonBuilds.ExportImport.ExportBuild(build)
    local decoded = EbonBuilds.ExportImport.DecodeBuild(b64)
    assertNotNil(decoded.echoWeights["Fireball"])
    assertNil(decoded.echoWeights["Frostbolt"])
end

function TestExportImport.testDecodeInvalid()
    assertNil(EbonBuilds.ExportImport.DecodeBuild(""))
    assertNil(EbonBuilds.ExportImport.DecodeBuild("!!!invalid!!!"))
end

function TestExportImport.testExportPreservesSettings()
    -- Test scalar settings and other non-index-keyed values survive roundtrip.
    local settings = EbonBuilds.Build.DefaultSettings()
    settings.autoBanishPct = 75
    settings.noveltyValue = 30
    local build = EbonBuilds.Build.NewObject({
        title = "Test",
        settings = settings,
    })
    local b64 = EbonBuilds.ExportImport.ExportBuild(build)
    local decoded = EbonBuilds.ExportImport.DecodeBuild(b64)
    assertEquals(decoded.settings.autoBanishPct, 75)
    assertEquals(decoded.settings.noveltyValue, 30)
end

function TestExportImport.testExportPreservesLockedEchoes()
    -- When lockedEchoes contains no nil gaps (e.g. two consecutive echoes),
    -- the JSON array roundtrips correctly.
    local build = EbonBuilds.Build.NewObject({
        title = "Test",
        lockedEchoes = { 200234, 200235, nil, nil },
    })
    local b64 = EbonBuilds.ExportImport.ExportBuild(build)
    local decoded = EbonBuilds.ExportImport.DecodeBuild(b64)
    assertEquals(decoded.lockedEchoes[1], 200234)
    assertEquals(decoded.lockedEchoes[2], 200235)
end
