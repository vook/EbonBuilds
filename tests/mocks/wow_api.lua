-- tests/mocks/wow_api.lua
-- Mock of WoW 3.3.5a API globals. Extend as needed.

-- Time functions (use real os.time / os.date)
_G.time = os.time
_G.date = os.date
_G.GetTime = function() return os.clock() end

-- Math: bit is a global library in WoW 3.3.5a
_G.bit = _G.bit or {
    band = function(a, b)
        local result = 0
        local n = 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then
                result = result + n
            end
            a = math.floor(a / 2)
            b = math.floor(b / 2)
            n = n * 2
        end
        return result
    end,
}

_G.math.random = _G.math.random or math.random
_G.math.randomseed = _G.math.randomseed or math.randomseed

-- String
_G.string = string
_G.table = table

-- WoW-specific stubs (override in individual tests)
_G.UnitName = function(unit) return "TestPlayer" end
_G.UnitClass = function(unit) return "Warrior", "WARRIOR" end
_G.GetSpellInfo = function(id) return "Spell_" .. tostring(id) end
_G.GetTalentTabInfo = function(i) return "Tab" .. i, nil, i * 5 end
_G.GetNumSpellTabs = function() return 0 end
_G.GetSpellTabInfo = function(idx) return "Tab" .. idx, nil, 0, 0 end
_G.GetSpellLink = function(slot, type) return nil end
_G.UnitLevel = function(unit) return 80 end

-- Chat frames
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(msg) end }
_G.NUM_CHAT_WINDOWS = 1
_G.ChatFrame1 = { AddMessage = function(msg) end }
_G.ChatFrame_RemoveChannel = function(frame, name) end

-- SendAddonMessage
_G.SendAddonMessage = function(prefix, msg, channel, target) end
_G.RegisterAddonMessagePrefix = function(prefix) end

-- Channel functions
_G.GetChannelName = function(i) return nil end
_G.JoinChannelByName = function(name) return 1 end
_G.SendChatMessage = function(msg, channel, lang, index) end
