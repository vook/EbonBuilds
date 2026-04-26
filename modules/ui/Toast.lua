-- EbonBuilds: modules/ui/Toast.lua
-- Responsibility: queue-based toast notifications. Supports simple text
-- messages and rich automation-action summaries (3 echoes inline + scores).
-- Auto-dismisses after 3 s, pauses on mouseover, click-to-dismiss,
-- dequeues the next entry automatically.

EbonBuilds.Toast = {}

local TOAST_W  = 520
local TOAST_H  = 72
local DURATION = 3
local QUALITY_HEX = { [0]="ffffff", [1]="19ff19", [2]="0066ff", [3]="cc66ff", [4]="ff8000" }

local queue   = {}
local frame
local elapsed = 0
local hovered = false
local header, echoLine, footerLine

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function GetRunInfo()
    -- Use the choice-round level (the level the echoes were offered at),
    -- not necessarily the current player level.
    local level = 0
    if ProjectEbonhold and ProjectEbonhold.PerkService then
        local getDebug = ProjectEbonhold.PerkService.GetRollsDebugInfo
        if getDebug then
            local choiceLevel = getDebug()
            if choiceLevel then level = choiceLevel end
        end
    end
    if level == 0 then
        level = UnitLevel("player") or 0
    end

    local rd = EbonholdPlayerRunData
    if not rd and ProjectEbonhold and ProjectEbonhold.PlayerRunService then
        local get = ProjectEbonhold.PlayerRunService.GetCurrentData
        if get then rd = get() end
    end
    local banRemain    = (rd and rd.remainingBanishes) or 0
    local totalRerolls = (rd and rd.totalRerolls) or 0
    local usedRerolls  = (rd and rd.usedRerolls) or 0
    local totalFreezes = (rd and rd.totalFreezes) or 0
    local usedFreezes  = (rd and rd.usedFreezes) or 0
    return level, banRemain, totalRerolls - usedRerolls, totalFreezes - usedFreezes
end

local function ClearLines()
    header:SetText("")
    echoLine:SetText("")
    footerLine:SetText("")
end

------------------------------------------------------------------------
-- Rendering
------------------------------------------------------------------------

local function ShowNext()
    ClearLines()
    if #queue == 0 then
        frame:Hide()
        return
    end

    local entry = table.remove(queue, 1)
    if entry.action then
        local actionColors = {
            Banish = "|cffff4444", Reroll = "|cff44aaff",
            Freeze = "|cff44ccff", Select  = "|cff44ff44",
        }
        local colorKey = entry.action:match("^(%a+)") or entry.action
        local ac = actionColors[colorKey] or "|cffffffff"
        header:SetText(ac .. "Automation: " .. entry.action .. "|r")

        -- Build inline echo line:  Echo1 (s)    >> Echo2 (s) <<    Echo3 (s)
        local parts = {}
        for i, ch in ipairs(entry.choices) do
            if i > 1 then
                parts[#parts + 1] = "    "
            end
            local hex = QUALITY_HEX[ch.quality] or "ffffff"
            local isTarget = (ch.index == entry.targetIndex)
            if isTarget then
                parts[#parts + 1] = "|cffffff00>> |r"
            end
            parts[#parts + 1] = string.format("|cff%s%s (%.0f)|r", hex, ch.name, ch.score)
            if isTarget then
                parts[#parts + 1] = " |cffffff00<<|r"
            end
        end
        echoLine:SetText(table.concat(parts))

        -- Footer: level and remaining charges
        local level, banRemain, rerollRemain, freezeRemain = GetRunInfo()
        footerLine:SetText(string.format(
            "|cff888888Ban: %d    Reroll: %d    Freeze: %d|r",
            banRemain, rerollRemain, freezeRemain))

        frame:SetHeight(TOAST_H)
    else
        -- Simple text message
        header:SetText(entry.text or "")
        frame:SetHeight(32)
    end

    frame:Show()
    elapsed  = 0
    hovered  = false
end

local function DismissCurrent()
    frame:Hide()
    ShowNext()
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

function EbonBuilds.Toast.ShowAutomationResult(scored, action, targetIndex)
    local entry = { action = action, targetIndex = targetIndex, choices = {} }
    for _, s in ipairs(scored) do
        entry.choices[#entry.choices + 1] = {
            index   = s.index,
            name    = s.name,
            quality = s.quality,
            score   = s.score,
        }
    end
    table.insert(queue, entry)
    if not frame:IsShown() then ShowNext() end
end

function EbonBuilds.Toast.Show(message)
    table.insert(queue, { text = message })
    if not frame:IsShown() then ShowNext() end
end

------------------------------------------------------------------------
-- Frame construction / Init
------------------------------------------------------------------------

local function BuildFrame()
    local f = CreateFrame("Frame", "EbonBuildsToastFrame", UIParent)
    f:SetSize(TOAST_W, TOAST_H)
    f:SetPoint("TOP", UIParent, "TOP", 0, -20)
    f:SetFrameStrata("TOOLTIP")
    f:Hide()

    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    -- Click to dismiss
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function() DismissCurrent() end)

    -- Mouseover pauses timer, mouseout resumes + resets elapsed
    f:SetScript("OnEnter", function() hovered = true end)
    f:SetScript("OnLeave", function() hovered = false; elapsed = 0 end)

    -- Header (centered)
    header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    header:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    header:SetJustifyH("CENTER")

    -- Single echo line (all 3 echoes inline, centered)
    echoLine = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    echoLine:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    echoLine:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    echoLine:SetJustifyH("CENTER")
    echoLine:SetTextColor(1, 1, 1, 1)

    -- Footer: level and charges (centered, gray)
    footerLine = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    footerLine:SetPoint("TOPLEFT", echoLine, "BOTTOMLEFT", 0, -4)
    footerLine:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    footerLine:SetJustifyH("CENTER")

    -- OnUpdate timer
    f:SetScript("OnUpdate", function(self, dt)
        if hovered then
            elapsed = 0
            return
        end
        elapsed = elapsed + dt
        if elapsed >= DURATION then
            DismissCurrent()
        end
    end)

    return f
end

function EbonBuilds.Toast.Init()
    frame = BuildFrame()
end
