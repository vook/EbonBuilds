-- tests/test_scoring.lua
-- Tests for Scoring: ScorePerQuality, Score, IsLocked, IsBanned.

TestScoring = {}

local settings

function TestScoring.setUp()
    settings = EbonBuilds.Build.DefaultSettings()
end

local function makeEntry(name, quality, families)
    return {
        name = name or "Fireball",
        quality = quality or 0,
        families = families or { "Caster DPS" },
    }
end

function TestScoring.testScoreNoBonuses()
    local entry = makeEntry("Fireball", 2)
    local score = EbonBuilds.Scoring.ScorePerQuality(entry, 100, settings, 2)
    assertEquals(score, 100)
end

function TestScoring.testScoreQualityBonusAdditive()
    settings.qualityBonus[2] = 20
    settings.qualityBonusMode[2] = false
    local entry = makeEntry("Fireball", 2)
    local score = EbonBuilds.Scoring.ScorePerQuality(entry, 100, settings, 2)
    assertEquals(score, 120)
end

function TestScoring.testScoreQualityBonusMultiplicative()
    settings.qualityBonus[2] = 1.5
    settings.qualityBonusMode[2] = true
    local entry = makeEntry("Fireball", 2)
    local score = EbonBuilds.Scoring.ScorePerQuality(entry, 100, settings, 2)
    assertEquals(score, 150)
end

function TestScoring.testScoreMultiplicativeZeroBaseWeight()
    settings.qualityBonus[2] = 1.5
    settings.qualityBonusMode[2] = true
    local entry = makeEntry("Fireball", 2)
    local score = EbonBuilds.Scoring.ScorePerQuality(entry, 0, settings, 2)
    assertEquals(score, 0)
end

function TestScoring.testScoreFamilyBonusAdditive()
    settings.familyBonus["Caster"] = 30
    settings.familyBonusMode["Caster"] = false
    local entry = makeEntry("Fireball", 0, { "Caster DPS" })
    local score = EbonBuilds.Scoring.ScorePerQuality(entry, 100, settings, 0)
    assertEquals(score, 130)
end

function TestScoring.testScoreFamilyBonusMultiplicative()
    settings.familyBonus["Caster"] = 2.0
    settings.familyBonusMode["Caster"] = true
    local entry = makeEntry("Fireball", 0, { "Caster DPS" })
    local score = EbonBuilds.Scoring.ScorePerQuality(entry, 100, settings, 0)
    assertEquals(score, 200)
end

function TestScoring.testScoreMultipleFamilies()
    settings.familyBonus["Caster"] = 10
    settings.familyBonus["Melee"] = 5
    settings.familyBonusMode["Caster"] = false
    settings.familyBonusMode["Melee"] = false
    local entry = makeEntry("Hybrid", 0, { "Caster DPS", "Melee DPS" })
    local score = EbonBuilds.Scoring.ScorePerQuality(entry, 100, settings, 0)
    assertEquals(score, 115)
end

function TestScoring.testScoreNoFamilyEcho()
    settings.familyBonus["No family"] = 20
    settings.familyBonusMode["No family"] = false
    local entry = makeEntry("Independent", 0, {})
    local score = EbonBuilds.Scoring.ScorePerQuality(entry, 100, settings, 0)
    assertEquals(score, 120)
end

function TestScoring.testScoreDifferentQualityBrackets()
    settings.qualityBonus[0] = 0
    settings.qualityBonus[1] = 10
    settings.qualityBonus[2] = 20
    settings.qualityBonus[3] = 30
    settings.qualityBonus[4] = 40
    for q = 0, 4 do
        local entry = makeEntry("Fireball", q)
        local score = EbonBuilds.Scoring.ScorePerQuality(entry, 100, settings, q)
        assertEquals(score, 100 + q * 10)
    end
end

function TestScoring.testScoreWithNoveltyAdditive()
    settings.noveltyValue = 50
    settings.noveltyMode = false
    local entry = makeEntry("Fireball", 2)
    local score = EbonBuilds.Scoring.Score(entry, 100, settings)
    assertEquals(score, 150)
end

function TestScoring.testScoreWithNoveltyMultiplicative()
    settings.noveltyValue = 1.5
    settings.noveltyMode = true
    local entry = makeEntry("Fireball", 2)
    local score = EbonBuilds.Scoring.Score(entry, 100, settings)
    assertEquals(score, 150)
end

function TestScoring.testScoreNoveltyMultiplicativeZeroBase()
    settings.noveltyValue = 1.5
    settings.noveltyMode = true
    local entry = makeEntry("Fireball", 2)
    local score = EbonBuilds.Scoring.Score(entry, 0, settings)
    assertEquals(score, 0)
end

function TestScoring.testScoreCombinedBonus()
    settings.qualityBonus[2] = 20
    settings.qualityBonusMode[2] = false
    settings.familyBonus["Caster"] = 30
    settings.familyBonusMode["Caster"] = false
    local entry = makeEntry("Fireball", 2, { "Caster DPS" })
    local score = EbonBuilds.Scoring.ScorePerQuality(entry, 100, settings, 2)
    assertEquals(score, 150)
end

function TestScoring.testScoreWhitelistFiltersFamilies()
    settings.familyBonus["Caster"] = 30
    settings.familyBonus["Melee"] = 10
    settings.familyBonusMode["Caster"] = false
    settings.familyBonusMode["Melee"] = false
    settings.banishFamilyWhitelist = { Caster = true }
    local entry = makeEntry("Hybrid", 0, { "Caster DPS", "Melee DPS" })
    local score = EbonBuilds.Scoring.ScorePerQuality(entry, 100, settings, 0)
    assertEquals(score, 130)  -- only Caster bonus applies (Melee not whitelisted)
end

function TestScoring.testIsLocked()
    local oldGetActive = EbonBuilds.Build.GetActive
    EbonBuilds.Build.GetActive = function()
        return { lockedEchoes = { nil, 200234, nil, nil } }
    end
    EbonBuilds.BuildForm = nil
    assertTrue(EbonBuilds.Scoring.IsLocked(200234))
    assertFalse(EbonBuilds.Scoring.IsLocked(999999))
    assertFalse(EbonBuilds.Scoring.IsLocked(nil))
    EbonBuilds.Build.GetActive = oldGetActive
end

function TestScoring.testIsBanned()
    local oldGetActive = EbonBuilds.Build.GetActive
    EbonBuilds.Build.GetActive = function()
        return { settings = { echoBanList = { [200234] = true } } }
    end
    EbonBuilds.ViewRouter = nil
    assertTrue(EbonBuilds.Scoring.IsBanned(200234))
    assertFalse(EbonBuilds.Scoring.IsBanned(999999))
    assertFalse(EbonBuilds.Scoring.IsBanned(nil))
    EbonBuilds.Build.GetActive = oldGetActive
end
