-- tests/test_sync.lua
-- Tests for Sync._StripChatPrefix: hardcore prefix and colour stripping.

TestSyncStripPrefix = {}

local S = EbonBuilds.Sync._StripChatPrefix
if not S then
    error("EbonBuilds.Sync._StripChatPrefix is nil — was the module loaded?")
end

function TestSyncStripPrefix.testNoPrefix()
    assertEquals(S("REQ|Vookan"), "REQ|Vookan")
end

function TestSyncStripPrefix.testHardcoreIVWithRedColour()
    -- Exact user-reported scenario
    assertEquals(S("|cffff0000[HCIV]|r REQ|Vookan"), "REQ|Vookan")
end

function TestSyncStripPrefix.testHardcoreIVNoColour()
    assertEquals(S("[HCIV] REQ|Vookan"), "REQ|Vookan")
end

function TestSyncStripPrefix.testHardcoreI()
    assertEquals(S("|cffff0000[HCI]|r REQ|Someone"), "REQ|Someone")
end

function TestSyncStripPrefix.testHardcoreII()
    assertEquals(S("|cff19ff19[HCII]|r REQ|GreenGuy"), "REQ|GreenGuy")
end

function TestSyncStripPrefix.testHardcoreIII()
    assertEquals(S("[HCIII] REQ|MultiColor"), "REQ|MultiColor")
end

function TestSyncStripPrefix.testHardcoreV()
    assertEquals(S("[HCV] REQ|Player"), "REQ|Player")
end

function TestSyncStripPrefix.testHardcoreX()
    assertEquals(S("[HCX] REQ|MaxTier"), "REQ|MaxTier")
end

function TestSyncStripPrefix.testLeadingWhitespace()
    assertEquals(S("  [HCIV] REQ|SpaceGuy"), "REQ|SpaceGuy")
end

function TestSyncStripPrefix.testBlueColour()
    assertEquals(S("|cff0066ff[HCIV]|r REQ|BlueGuy"), "REQ|BlueGuy")
end

function TestSyncStripPrefix.testOnlyColourNoHardcore()
    -- Colour codes are stripped; message otherwise intact
    assertEquals(S("|cffff0000REQ|NormalGuy|r"), "REQ|NormalGuy")
end

function TestSyncStripPrefix.testEmptyString()
    assertEquals(S(""), "")
end

function TestSyncStripPrefix.testNoMatch()
    assertEquals(S("Just a normal chat message"), "Just a normal chat message")
end

function TestSyncStripPrefix.testHardcorePrefixNotAtStart()
    -- Only stripped at start (anchored with ^)
    assertEquals(S("REQ|[HCIV]Embedded"), "REQ|[HCIV]Embedded")
end

function TestSyncStripPrefix.testEscapedPipesUnaffected()
    -- || (escaped pipe) in message should NOT be touched by colour/HC stripping.
    -- The unescape happens separately in HandleChannelMessage.
    local input = "|cffff0000[HCIV]|r REQ||Player||With||Pipes"
    local result = S(input)
    assertEquals(result, "REQ||Player||With||Pipes")
end

function TestSyncStripPrefix.testMultipleColourCodes()
    assertEquals(S("|cffff0000|r|cff00ff00[HCIII]|r REQ|Multi"), "REQ|Multi")
end

function TestSyncStripPrefix.testUnknownPrefixFormat()
    -- New approach finds REQ| marker regardless of prefix shape
    assertEquals(S("|cffFF0000[SOMETHING_UNKNOWN]|r REQ|Vookan"), "REQ|Vookan")
end

function TestSyncStripPrefix.testEbonholdExactFormat()
    -- Exact format reported: [1] [Tangjiwl]: [HCIV] REQ|Tangjiwl
    -- Channel number and sender tag are NOT in the raw msg arg — but if they were,
    -- the find-REQ approach would handle it.
    assertEquals(S("[HCIV] REQ|Tangjiwl"), "REQ|Tangjiwl")
end

function TestSyncStripPrefix.testColourWithHCIVNoPipe()
    -- Colour strip must not mangle the pipe that follows the prefix
    assertEquals(S("|cffff0000[HCIV]|r REQ|Tangjiwl"), "REQ|Tangjiwl")
end

-- Protocol codes other than REQ (used in SendAddonMessage responses)

function TestSyncStripPrefix.testLSTwithPrefix()
    assertEquals(S("[HCIV] LST|Vookan|1/15|uuid|123456"), "LST|Vookan|1/15|uuid|123456")
end

function TestSyncStripPrefix.testWNTwithPrefix()
    assertEquals(S("[HCIV] WNT|Weedola|uuid1|uuid2"), "WNT|Weedola|uuid1|uuid2")
end

function TestSyncStripPrefix.testSKPwithPrefix()
    assertEquals(S("[HCIV] SKP|Weedola"), "SKP|Weedola")
end

function TestSyncStripPrefix.testBLDwithPrefix()
    assertEquals(S("[HCIV] BLD|Vookan|buildId|1/5|base64data"), "BLD|Vookan|buildId|1/5|base64data")
end

function TestSyncStripPrefix.testENDwithPrefix()
    assertEquals(S("[HCIV] END|Vookan|3"), "END|Vookan|3")
end

function TestSyncStripPrefix.testAddonMessageWithColourAndPrefix()
    -- Simulates SendAddonMessage receiving HC prefix with colour
    assertEquals(S("|cffff0000[HCIV]|r LST|Vookan|1/15|uuid|epoch"), "LST|Vookan|1/15|uuid|epoch")
end

function TestSyncStripPrefix.testNormalAddonMessage()
    -- Messages without prefix pass through unchanged
    assertEquals(S("LST|Vookan|1/15|uuid|epoch"), "LST|Vookan|1/15|uuid|epoch")
end
