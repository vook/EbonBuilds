#!/usr/bin/env lua
-- tests/run.lua -- EbonBuilds test runner
-- Usage: lua51.exe tests/run.lua

-- Resolve paths relative to the script location
local scriptDir = (arg and arg[0] and arg[0]:match("(.+)[/\\]")) or "tests/"
local addonRoot = scriptDir:gsub("[/\\]?tests[/\\]?$", "")
if addonRoot == scriptDir then addonRoot = "" end

local function P(relative)
    if addonRoot ~= "" then return addonRoot .. "/" .. relative end
    return relative
end

-- Export assertions to globals so test files can use them directly
_G.EXPORT_ASSERT_TO_GLOBALS = true

-- 1. Load luaunit (captures return value as global for LuaUnit.run)
local M = dofile(P("tests/luaunit.lua"))
_G.luaunit = M

-- 2. Load test environment (mocks + EbonBuilds modules)
dofile(P("tests/helper.lua"))

-- 3. Load test files (these define test tables in _G)
dofile(P("tests/test_export_import.lua"))
dofile(P("tests/test_scoring.lua"))
dofile(P("tests/test_build.lua"))
dofile(P("tests/test_automation.lua"))

-- 4. Run all tests
print("\n" .. string.rep("=", 60))
print("EbonBuilds Test Suite")
print(string.rep("=", 60) .. "\n")

local runner = M.LuaUnit.new()
local exitCode = runner:runSuite()
os.exit(exitCode or 0)
