-- tests/helper.lua
-- Test environment setup. dofile mocks, then addon source modules.

-- Resolve path relative to addon root (parent of tests/)
local function addonPath(relative)
    -- tests/helper.lua → go up one level → addon root
    local dir = debug.getinfo(1, "S").source:match("@(.+)[/\\]tests[/\\]helper%.lua$")
    if dir then
        return dir .. "/" .. relative
    end
    -- Fallback: assume CWD is addon root
    return relative
end

-- 1. WoW API mocks
dofile(addonPath("tests/mocks/wow_api.lua"))

-- 2. ProjectEbonhold mocks
dofile(addonPath("tests/mocks/ebonhold.lua"))

-- 3. Stub modules that have complex dependencies
_G.EbonBuilds.SpecData = _G.EbonBuilds.SpecData or {}
_G.EbonBuilds.Filters = _G.EbonBuilds.Filters or {}
_G.EbonBuilds.EchoTable = _G.EbonBuilds.EchoTable or {}

if not _G.EbonBuilds.EchoTableRows then
    _G.EbonBuilds.EchoTableRows = {
        BuildSortedList = function() return {} end,
    }
end
if not _G.EbonBuilds.Weights then
    _G.EbonBuilds.Weights = { Get = function() return 0 end }
end

-- 4. Load addon source modules in dependency order
dofile(addonPath("modules/build/Build.lua"))
dofile(addonPath("modules/build/ExportImport.lua"))
dofile(addonPath("modules/build/Scoring.lua"))
dofile(addonPath("modules/weights/Weights.lua"))
dofile(addonPath("modules/automation/Automation.lua"))
dofile(addonPath("modules/sync/Sync.lua"))

-- 5. Test utilities
function printSection(name)
    print(string.format("\n=== %s ===", name))
end

print("Test environment loaded from: " .. (addonPath("") or "unknown"))
