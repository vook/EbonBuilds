-- tests/test_session_report.lua
-- Tests for Session.FormatReport logbook copy output.

TestSessionReport = {}

function TestSessionReport.testFormatReportWithSnapshot()
    local session = {
        characterName = "Jhony",
        className = "WARRIOR",
        buildTitle = "Arms PvE",
        startTime = 1700000000,
        endTime = 1700005000,
        maxLevel = 52,
        soulAshes = 980,
        automationSnapshot = {
            buildTitle = "Arms PvE",
            peakScore = 2450,
            thresholds = {
                autoBanishPct = 20,
                autoRerollPct = 120,
                rerollGuardPct = 90,
                autoFreezePct = 80,
                freezePenaltyPct = 10,
            },
        },
        logs = {
            {
                timestamp = 1700000100,
                action = "Banish",
                choices = {
                    { name = "Weak Echo", score = 120, quality = 0 },
                },
                targetIndex = 1,
                charges = { ban = 2, reroll = 1, freeze = 0 },
            },
        },
    }

    local report = EbonBuilds.Session.FormatReport(session)
    assertNotNil(report)
    assertStrContains(report, "EbonBuilds Logbook Report")
    assertStrContains(report, "Peak score: 2450")
    assertStrContains(report, "Auto-banish")
    assertStrContains(report, "Auto-reroll")
    assertStrContains(report, "Reroll guard")
    assertStrContains(report, "Auto-freeze")
    assertStrContains(report, "Freeze penalty")
    assertStrContains(report, "snapshot at run start")
    assertStrContains(report, ">>Weak Echo (120)<<")
    assertStrContains(report, "Logbook (1 actions)")
    assertStrContains(report, "Echo 1")
    assertStrContains(report, "Charges")
    assertStrContains(report, "490 per echo")
    assertStrContains(report, "2940 sum of 3 echoes")
end

function TestSessionReport.testFormatReportLegacyFallback()
    local session = {
        characterName = "Test",
        className = "MAGE",
        buildTitle = "Old",
        startTime = 1700000000,
        endTime = 1700001000,
        maxLevel = 10,
        soulAshes = 100,
        logs = {},
    }

    local report = EbonBuilds.Session.FormatReport(session)
    assertStrContains(report, "current values")
    assertStrContains(report, "no run-start snapshot")
    assertStrContains(report, "Peak score:")
    assertStrContains(report, "Auto-banish")
    assertStrContains(report, "Freeze penalty")
end

function TestSessionReport.testFormatReportCurrentFallbackSnapshot()
    local session = {
        characterName = "Test",
        className = "MAGE",
        buildTitle = "Old",
        startTime = 1700000000,
        endTime = 1700001000,
        maxLevel = 10,
        soulAshes = 100,
        automationSnapshot = {
            buildTitle = "Old",
            peakScore = 1000,
            source = "current",
            thresholds = {
                autoBanishPct = 30,
                autoRerollPct = 110,
                rerollGuardPct = 85,
                autoFreezePct = 75,
                freezePenaltyPct = 15,
            },
        },
        logs = {},
    }

    local report = EbonBuilds.Session.FormatReport(session)
    assertStrContains(report, "current values")
    assertStrContains(report, "captured during session")
    assertStrContains(report, "Peak score: 1000")
    assertStrContains(report, "Auto-banish:      30%")
end

function TestSessionReport.testFormatReportLogColumns()
    local session = {
        characterName = "Test",
        className = "WARLOCK",
        buildTitle = "Warlock",
        startTime = 1700000000,
        endTime = 1700001000,
        maxLevel = 10,
        soulAshes = 0,
        automationSnapshot = {
            peakScore = 160,
            source = "runStart",
            thresholds = {
                autoBanishPct = 25,
                autoRerollPct = 75,
                rerollGuardPct = 40,
                autoFreezePct = 40,
                freezePenaltyPct = 10,
            },
        },
        logs = {
            {
                timestamp = 1700000100,
                action = "Freeze",
                choices = {
                    { name = "Reaper's Verdict", score = 130 },
                    { name = "Overcharged", score = 140 },
                    { name = "Bolstered Vitality", score = 50 },
                },
                targetIndex = 1,
                charges = { ban = 14, reroll = 18, freeze = 8 },
            },
        },
    }

    local report = EbonBuilds.Session.FormatReport(session)
    assertStrContains(report, "Logbook (1 actions)")
    assertStrContains(report, "# | Action | Echo 1")
    assertNotNil(report:match("1 | Freeze"))
    assertStrContains(report, ">>Reaper's Verdict (130)<<")
    assertStrContains(report, "B:14 R:18 F:8")
    assertEquals(report:find("11:33:27", 1, true), nil)
end

function TestSessionReport.testFormatReportNoSession()
    assertEquals(report, "No session selected.")
end
