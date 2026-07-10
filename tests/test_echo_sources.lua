-- tests/test_echo_sources.lua

local ES = EbonBuilds.EchoSources

function test_classify_naxx_from_meta()
    local info = ES.Classify(122, "ignored")
    lu.assertEquals(info.kind, "raid")
    lu.assertEquals(info.raid, "naxxramas")
end

function test_classify_icc_from_drop_source()
    local info = ES.Classify(nil, "Can be found on Icecrown Citadel - Lord Marrowgar")
    lu.assertEquals(info.kind, "raid")
    lu.assertEquals(info.raid, "icecrown_citadel")
end

function test_classify_open_world_northrend()
    local info = ES.Classify(nil, "Wintergrasp - Whispering Wind")
    lu.assertEquals(info.kind, "open_world")
    lu.assertEquals(info.region, "northrend")
end

function test_classify_southwind_kalimdor()
    local info = ES.Classify(247, "ignored")
    lu.assertEquals(info.kind, "open_world")
    lu.assertEquals(info.region, "kalimdor")
end

function test_classify_southwind_from_text()
    local info = ES.Classify(nil, "Southwind Village - Tortured Druids")
    lu.assertEquals(info.kind, "open_world")
    lu.assertEquals(info.region, "kalimdor")
end

function test_classify_gormok_toc()
    local info = ES.Classify(nil, "Gormok the Impaler")
    lu.assertEquals(info.kind, "raid")
    lu.assertEquals(info.raid, "trial_of_the_crusader")
end

function test_filter_passes_when_none_selected()
    local entry = { groupId = 122, dropSource = "Naxxramas - Anub'Rekhan", requiresTome = true }
    lu.assertTrue(ES.PassesFilter(entry, {}))
end

function test_filter_matches_selected_raid()
    local entry = { groupId = 122, dropSource = "Naxxramas - Anub'Rekhan", requiresTome = true }
    lu.assertTrue(ES.PassesFilter(entry, { ["raid:naxxramas"] = true }))
    lu.assertFalse(ES.PassesFilter(entry, { ["raid:ulduar"] = true }))
end

function test_filter_matches_open_world_region()
    local entry = { groupId = 31, dropSource = "Wintergrasp - Fire zone - Flame Revenant", requiresTome = true }
    lu.assertTrue(ES.PassesFilter(entry, { ["open_world:northrend"] = true }))
    lu.assertFalse(ES.PassesFilter(entry, { ["open_world:kalimdor"] = true }))
end

function test_filter_all_raids()
    local naxx = { groupId = 122, dropSource = "Naxxramas - Anub'Rekhan", requiresTome = true }
    local ulduar = { groupId = 128, dropSource = "Ulduar - Instructor Razuvious", requiresTome = true }
    local ow = { groupId = 31, dropSource = "Wintergrasp - Fire zone", requiresTome = true }
    local selected = { ["raid:all"] = true }
    lu.assertTrue(ES.PassesFilter(naxx, selected))
    lu.assertTrue(ES.PassesFilter(ulduar, selected))
    lu.assertFalse(ES.PassesFilter(ow, selected))
end

function test_filter_all_open_world()
    local ow = { groupId = 31, dropSource = "Wintergrasp - Fire zone", requiresTome = true }
    local raid = { groupId = 122, dropSource = "Naxxramas - Anub'Rekhan", requiresTome = true }
    local selected = { ["open_world:all"] = true }
    lu.assertTrue(ES.PassesFilter(ow, selected))
    lu.assertFalse(ES.PassesFilter(raid, selected))
end

function test_filter_no_tome_required()
    local entry = { dropSource = "No tome required", requiresTome = false }
    lu.assertTrue(ES.PassesFilter(entry, { ["special:no_tome"] = true }))
    lu.assertFalse(ES.PassesFilter(entry, { ["raid:naxxramas"] = true }))
end

function test_filter_unknown_source()
    local entry = { groupId = 999, dropSource = "Unknown", requiresTome = true }
    lu.assertTrue(ES.PassesFilter(entry, { ["special:unknown"] = true }))
    lu.assertFalse(ES.PassesFilter(entry, { ["raid:icecrown_citadel"] = true }))
    lu.assertEquals(ES.EntryFilterKey(entry), "special:unknown")
end

function test_filter_unknown_does_not_match_classified_icc()
    local entry = { groupId = nil, dropSource = "Can be found on Icecrown Citadel - Lord Marrowgar", requiresTome = true }
    lu.assertFalse(ES.PassesFilter(entry, { ["special:unknown"] = true }))
    lu.assertTrue(ES.PassesFilter(entry, { ["raid:icecrown_citadel"] = true }))
end

function test_filter_unknown_excludes_place_name_text()
    local entry = { groupId = nil, dropSource = "Southwind Village - Tortured Druids", requiresTome = true }
    lu.assertFalse(ES.PassesFilter(entry, { ["special:unknown"] = true }))
    lu.assertTrue(ES.PassesFilter(entry, { ["open_world:kalimdor"] = true }))
end

function test_filter_unknown_excludes_onyxia_group_without_drop_source()
    local entry = { spellId = 1, groupId = 285, requiresTome = true }
    lu.assertFalse(ES.PassesFilter(entry, { ["special:unknown"] = true }))
    lu.assertTrue(ES.PassesFilter(entry, { ["raid:onyxias_lair"] = true }))
    lu.assertEquals(ES.EntryFilterKey(entry), "raid:onyxias_lair")
end

function test_filter_unknown_excludes_toc_boss_name()
    local entry = { groupId = nil, dropSource = "Gormok the Impaler", requiresTome = true }
    lu.assertFalse(ES.PassesFilter(entry, { ["special:unknown"] = true }))
    lu.assertTrue(ES.PassesFilter(entry, { ["raid:trial_of_the_crusader"] = true }))
end

function test_clear_selection()
    local selected = { ["raid:naxxramas"] = true, ["open_world:all"] = true }
    ES.ClearSelection(selected)
    lu.assertEquals(ES.CountSelected(selected), 0)
end

function test_resolve_requires_tome_sentinel_nine()
    lu.assertFalse(ES.ResolveRequiresTome({ requiredSpell = 9 }))
    lu.assertFalse(ES.ResolveRequiresTome({ requiredSpell = 0 }))
    lu.assertTrue(ES.ResolveRequiresTome({ requiredSpell = 300100 }))
end

function test_resolve_requires_tome_override()
    lu.assertFalse(ES.ResolveRequiresTome({ requiredSpell = 300100, requiresTome = false }))
    lu.assertTrue(ES.ResolveRequiresTome({ requiredSpell = 0, requiresTome = true }))
end

function test_aggregate_echo_tome_info_across_qualities()
    local perkDb = {
        [1] = { requiredSpell = 9, quality = 0 },
        [2] = { requiredSpell = 300100, quality = 3 },
    }
    local requiresTome, tomeSpellId = ES.AggregateEchoTomeInfo({ [0] = 1, [3] = 2 }, perkDb)
    lu.assertTrue(requiresTome)
    lu.assertEquals(tomeSpellId, 300100)
end

function test_aggregate_echo_tome_info_no_tome_ranks()
    local perkDb = {
        [1] = { requiredSpell = 9, quality = 3, requiresTome = false },
    }
    local requiresTome, tomeSpellId = ES.AggregateEchoTomeInfo({ [3] = 1 }, perkDb)
    lu.assertFalse(requiresTome)
    lu.assertNil(tomeSpellId)
end
