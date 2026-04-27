-- EbonBuilds: modules/ui/SessionHistory.lua
-- Responsibility: session history UI replacing the Logbook tab content.
-- Top: horizontal row of session cards. Bottom: full-width log table.

EbonBuilds.SessionHistory = {}

local QUALITY_HEX = { [0]="ffffff", [1]="19ff19", [2]="0066ff", [3]="cc66ff", [4]="ff8000" }
local ACTION_COLORS = {
    Banish         = { 1.0, 0.27, 0.27 },
    Reroll         = { 0.27, 0.67, 1.0 },
    Freeze         = { 0.27, 0.80, 1.0 },
    Select         = { 0.27, 1.0, 0.27 },
    ["Select (Locked)"] = { 1.0, 0.53, 0.0 },
}

local CARD_W     = 170
local CARD_H     = 48
local CARD_GAP   = 6
local TOP_H      = 68

local topPanel, bottomPanel
local sessionItems = {}
local logRows      = {}
local selectedSessionId = nil

local sessionChild, sessionClip, scrollOffset = nil, nil, 0
local logScroll, logChild, logBar
local durationTimer

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------

local function FormatDuration(startTime, endTime)
    local t = (endTime or time()) - startTime
    local h = math.floor(t / 3600)
    local m = math.floor((t % 3600) / 60)
    local s = math.floor(t % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function FormatTimestamp(ts)
    return date("%H:%M:%S", ts)
end

------------------------------------------------------------------------
-- Duration timer (updates active session card every ~1s)
------------------------------------------------------------------------

local activeSessionCard = nil

local function OnDurationTick(self, dt)
    self._elapsed = (self._elapsed or 0) + dt
    if self._elapsed < 1 then return end
    self._elapsed = 0

    if not activeSessionCard then
        self:Hide()
        return
    end
    if not activeSessionCard._isActive then
        activeSessionCard = nil
        self:Hide()
        return
    end
    activeSessionCard._durationLabel:SetText(FormatDuration(activeSessionCard._startTime, nil))
end

local function StartDurationTimer(card)
    activeSessionCard = card
    if not durationTimer then
        durationTimer = CreateFrame("Frame")
        durationTimer:SetScript("OnUpdate", OnDurationTick)
    end
    durationTimer._elapsed = 0
    durationTimer:Show()
end

------------------------------------------------------------------------
-- Session cards (horizontal row at top)
------------------------------------------------------------------------

local function ClearSessionItems()
    for _, item in ipairs(sessionItems) do
        item:Hide()
    end
end

local function SelectSession(id)
    selectedSessionId = id
    for _, item in ipairs(sessionItems) do
        if item._id == id then
            item:SetBackdropBorderColor(1.0, 0.84, 0.0, 1)
        else
            local isActive = item._isActive
            item:SetBackdropBorderColor(isActive and 0.27 or 0.4, isActive and 1.0 or 0.4, isActive and 0.27 or 0.4, 1)
        end
    end
    EbonBuilds.SessionHistory.RefreshLogView()
end

local function BuildCard(parent)
    local item = CreateFrame("Frame", nil, parent)
    item:SetSize(CARD_W, CARD_H)

    item:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 8, edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    item:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
    item:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    item._levelLabel = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    item._levelLabel:SetPoint("TOPLEFT", item, "TOPLEFT", 6, -4)
    item._levelLabel:SetPoint("RIGHT", item, "RIGHT", -6, 0)
    item._levelLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    item._soulLabel = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    item._soulLabel:SetPoint("TOPLEFT", item._levelLabel, "BOTTOMLEFT", 0, -2)
    item._soulLabel:SetPoint("RIGHT", item, "RIGHT", -6, 0)
    item._soulLabel:SetTextColor(0.7, 0.7, 0.7, 1)

    item._durationLabel = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    item._durationLabel:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 6, 4)
    item._durationLabel:SetTextColor(0.5, 0.5, 0.5, 1)

    -- Delete button (hidden for active sessions)
    local delBtn = CreateFrame("Button", nil, item)
    delBtn:SetSize(14, 14)
    delBtn:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -6, 4)
    delBtn:SetNormalFontObject("GameFontHighlightSmall")
    delBtn:SetText("|cff888888X|r")
    delBtn:SetScript("OnClick", function()
        if item._id then
            StaticPopupDialogs["EBONBUILDS_DELETE_SESSION"] = {
                text = "Delete this session and all its logs?",
                button1 = "Yes", button2 = "No",
                OnAccept = function()
                    EbonBuilds.Session.DeleteSession(item._id)
                    selectedSessionId = nil
                    EbonBuilds.SessionHistory.RefreshSessionList()
                    EbonBuilds.SessionHistory.RefreshLogView()
                end,
                timeout = 0, whileDead = true, hideOnEscape = true,
            }
            StaticPopup_Show("EBONBUILDS_DELETE_SESSION")
        end
    end)
    item._delBtn = delBtn

    item:SetScript("OnMouseDown", function()
        if item._id then SelectSession(item._id) end
    end)

    item:Hide()
    return item
end

function EbonBuilds.SessionHistory.RefreshSessionList()
    ClearSessionItems()

    local sessions = EbonBuilds.Session.GetSessions()
    local activeSession = EbonBuilds.Session.GetActiveSession()

    local sorted = {}
    for i, s in ipairs(sessions) do
        sorted[#sorted + 1] = s
    end
    table.sort(sorted, function(a, b)
        if a == activeSession then return true end
        if b == activeSession then return false end
        return (a.startTime or 0) > (b.startTime or 0)
    end)

    if not selectedSessionId and activeSession then
        selectedSessionId = activeSession.id
    end

    local activeCard = nil
    local x = 4
    for i, s in ipairs(sorted) do
        if #sessionItems < i then
            sessionItems[i] = BuildCard(sessionChild)
        end
        local item = sessionItems[i]

        item._id        = s.id
        item._isActive  = (s.endTime == nil)
        item._startTime = s.startTime
        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", sessionChild, "TOPLEFT", x, -2)
        item:SetSize(CARD_W, CARD_H)

        local isActive = (s.endTime == nil)

        if isActive then
            item:SetBackdropBorderColor(0.27, 1.0, 0.27, 1)
            item._levelLabel:SetText(("|cff44ff44[Active]|r  Level %d"):format(s.maxLevel or UnitLevel("player")))
            item._durationLabel:SetText(FormatDuration(s.startTime, nil))
            if item._delBtn then item._delBtn:Hide() end
            activeCard = item
        else
            item:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            item._levelLabel:SetText(("Level %d"):format(s.maxLevel or UnitLevel("player")))
            item._durationLabel:SetText(FormatDuration(s.startTime, s.endTime))
            if item._delBtn then item._delBtn:Show() end
        end
        item._levelLabel:SetTextColor(0.7, 0.7, 0.7, 1)

        item._soulLabel:SetText(("Soul Ashes: %s"):format(isActive and "..." or tostring(s.soulAshes)))

        if s.id == selectedSessionId then
            item:SetBackdropBorderColor(1.0, 0.84, 0.0, 1)
        end

        item:Show()
        x = x + CARD_W + CARD_GAP
    end

    sessionChild:SetWidth(math.max(x, 1))

    -- Start or stop the duration timer for the active session
    if activeCard then
        StartDurationTimer(activeCard)
    elseif durationTimer then
        durationTimer:Hide()
        activeSessionCard = nil
    end

    -- Reset scroll offset if content is smaller than viewport now
    local clipW = sessionClip:GetWidth()
    if x <= clipW then
        scrollOffset = 0
        sessionChild:SetPoint("TOPLEFT", sessionClip, "TOPLEFT", 0, -2)
    end
end

------------------------------------------------------------------------
-- Log table (full width below)
------------------------------------------------------------------------

local function ClearLogRows()
    for _, row in ipairs(logRows) do
        row:Hide()
    end
end

local function BuildLogRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(16)

    -- Timestamp
    local timeFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeFs:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -1)
    timeFs:SetWidth(48)
    row._timeFs = timeFs

    -- Action
    local actionFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    actionFs:SetPoint("LEFT", timeFs, "RIGHT", 3, 0)
    actionFs:SetWidth(58)
    row._actionFs = actionFs

    -- Echo columns (with optional action-colored border)
    row._echoFrames = {}
    row._echoNameFonts  = {}
    row._echoScoreFonts = {}
    local echoAnchor = actionFs
    for i = 1, 3 do
        local echoFrame = CreateFrame("Frame", nil, row)
        echoFrame:SetHeight(14)
        echoFrame:SetWidth(120)
        echoFrame:SetPoint("LEFT", echoAnchor, "RIGHT", 3, 0)
        echoFrame:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        echoFrame:SetBackdropBorderColor(0, 0, 0, 0)
        echoFrame:EnableMouse(true)

        -- Score label (right side, fixed, always visible)
        local scoreFont = echoFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        scoreFont:SetPoint("TOPRIGHT", echoFrame, "TOPRIGHT", -4, -2)
        scoreFont:SetPoint("BOTTOMRIGHT", echoFrame, "BOTTOMRIGHT", -4, 2)
        scoreFont:SetWidth(35)
        scoreFont:SetJustifyH("RIGHT")

        -- Name label (left side, truncated when too long)
        local nameFont = echoFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameFont:SetPoint("TOPLEFT", echoFrame, "TOPLEFT", 4, -2)
        nameFont:SetPoint("RIGHT", scoreFont, "LEFT", -2, 0)
        nameFont:SetJustifyH("LEFT")

        -- Tooltip
        echoFrame:SetScript("OnEnter", function(self)
            if self._echoName then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self._echoName, 1, 1, 1)
                if self._echoScore then
                    GameTooltip:AddLine(("Score: %.0f"):format(self._echoScore), 0.7, 0.7, 0.7)
                end
                GameTooltip:Show()
            end
        end)
        echoFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row._echoFrames[i]      = echoFrame
        row._echoNameFonts[i]   = nameFont
        row._echoScoreFonts[i]  = scoreFont
        echoAnchor = echoFrame
    end

    -- Charges
    local chargesFs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chargesFs:SetPoint("LEFT", echoAnchor, "RIGHT", 6, 0)
    chargesFs:SetWidth(80)
    chargesFs:SetJustifyH("LEFT")
    row._chargesFs = chargesFs

    row:Hide()
    return row
end

function EbonBuilds.SessionHistory.RefreshLogView()
    ClearLogRows()

    if not logScroll or not logChild then return end
    logChild:SetWidth(math.max(logScroll:GetWidth() or 0, 450))

    if not selectedSessionId then
        logChild:SetHeight(1)
        return
    end

    local sessions = EbonBuilds.Session.GetSessions()
    local session
    for _, s in ipairs(sessions) do
        if s.id == selectedSessionId then session = s; break end
    end
    if not session then
        logChild:SetHeight(1)
        return
    end

    local logs = session.logs or {}
    local ROW_H = 18

    for i, entry in ipairs(logs) do
        if #logRows < i then
            logRows[i] = BuildLogRow(logChild)
        end
        local row = logRows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", logChild, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", logChild, "RIGHT", 0, 0)
        row:SetHeight(ROW_H)

        -- Timestamp
        row._timeFs:SetText(("|cff888888%s|r"):format(FormatTimestamp(entry.timestamp)))

        -- Action
        local ac = ACTION_COLORS[entry.action] or { 1, 1, 1 }
        local acHex = string.format("%02x%02x%02x", math.floor(ac[1]*255), math.floor(ac[2]*255), math.floor(ac[3]*255))
        row._actionFs:SetText(("|cff%s%s|r"):format(acHex, entry.action))

        -- Echoes
        for j = 1, 3 do
            local ch = entry.choices[j]
            local echoFrame      = row._echoFrames[j]
            local nameFont       = row._echoNameFonts[j]
            local scoreFont      = row._echoScoreFonts[j]

            if ch then
                local hex = QUALITY_HEX[ch.quality] or "ffffff"
                nameFont:SetText(("|cff%s%s|r"):format(hex, ch.name))
                scoreFont:SetText(("|cff%s(%.0f)|r"):format(hex, ch.score))

                echoFrame._echoName  = ch.name
                echoFrame._echoScore = ch.score

                if j == entry.targetIndex then
                    echoFrame:SetBackdropBorderColor(ac[1], ac[2], ac[3], 1)
                else
                    echoFrame:SetBackdropBorderColor(0, 0, 0, 0)
                end
                echoFrame:Show()
            else
                nameFont:SetText("")
                scoreFont:SetText("")
                echoFrame._echoName  = nil
                echoFrame._echoScore = nil
                echoFrame:SetBackdropBorderColor(0, 0, 0, 0)
                echoFrame:Show()
            end
        end

        -- Charges
        local ch = entry.charges or {}
        row._chargesFs:SetText(("|cff888888B:%d R:%d F:%d|r"):format(
            ch.ban or 0, ch.reroll or 0, ch.freeze or 0))

        row:Show()
    end

    local totalH = math.max(#logs * ROW_H + 4, logScroll:GetHeight())
    logChild:SetHeight(totalH)
end

------------------------------------------------------------------------
-- Export dialog
------------------------------------------------------------------------

local exportDialog

local function BuildExportDialog()
    local f = CreateFrame("Frame", "EbonBuildsExportDialog", UIParent)
    f:SetSize(520, 380)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
    f:SetScript("OnHide", function(self) self:StopMovingOrSizing() end)
    f:Hide()

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
    title:SetText("Session Export")

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    -- ScrollFrame wrapping an EditBox
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -2, -8)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 10)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetTextInsets(6, 6, 4, 4)
    editBox:SetAutoFocus(false)
    scroll:SetScrollChild(editBox)

    local bar = CreateFrame("Slider", nil, scroll, "UIPanelScrollBarTemplate")
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", -2, -4)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -2, 4)
    bar:SetValueStep(18)

    bar:SetScript("OnValueChanged", function(self, value)
        editBox:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, value)
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local v = bar:GetValue()
        local mn, mx = bar:GetMinMaxValues()
        bar:SetValue(math.max(mn, math.min(mx, v - delta * 18)))
    end)

    f._editBox = editBox
    f._scroll  = scroll
    f._bar     = bar

    return f
end

function EbonBuilds.SessionHistory.ExportSession()
    if not exportDialog then
        exportDialog = BuildExportDialog()
    end

    local session
    if selectedSessionId then
        for _, s in ipairs(EbonBuilds.Session.GetSessions()) do
            if s.id == selectedSessionId then session = s; break end
        end
    end

    if not session then
        exportDialog._editBox:SetText("No session selected.")
        exportDialog._editBox:SetWidth(exportDialog._scroll:GetWidth() - 12)
        exportDialog._editBox:SetHeight(40)
    else
        local lines = {}
        lines[#lines + 1] = string.format("Session: Level %d | Duration: %s | Soul Ashes: %s",
            session.maxLevel or UnitLevel("player"),
            FormatDuration(session.startTime, session.endTime),
            session.soulAshes or 0)
        lines[#lines + 1] = ""

        local logs = session.logs or {}
        for _, entry in ipairs(logs) do
            local parts = {}
            parts[#parts + 1] = FormatTimestamp(entry.timestamp)
            parts[#parts + 1] = string.format("%-16s", entry.action)

            for j, ch in ipairs(entry.choices) do
                local text = string.format("%s (%.0f)", ch.name, ch.score)
                if j == entry.targetIndex then
                    text = ">>" .. text .. "<<"
                end
                parts[#parts + 1] = string.format("%-34s", text)
            end

            local ch = entry.charges or {}
            parts[#parts + 1] = string.format("B:%d  R:%d  F:%d",
                ch.ban or 0, ch.reroll or 0, ch.freeze or 0)

            lines[#lines + 1] = table.concat(parts, "")
        end

        local text = table.concat(lines, "\n")
        exportDialog._editBox:SetText(text)

        local editW = exportDialog._scroll:GetWidth() - 12
        exportDialog._editBox:SetWidth(editW)
        -- Estimate height: ~14px per line + padding
        local lineCount = #lines + 1
        local estH = math.max(lineCount * 14 + 12, exportDialog._scroll:GetHeight())
        exportDialog._editBox:SetHeight(estH)
        exportDialog._bar:SetMinMaxValues(0, math.max(0, estH - exportDialog._scroll:GetHeight()))
    end

    exportDialog:Show()
end

------------------------------------------------------------------------
-- Main UI construction
------------------------------------------------------------------------

local function ScrollCards(delta)
    local childW = sessionChild:GetWidth() or 0
    local clipW  = sessionClip:GetWidth() or 1
    local maxScroll = childW - clipW
    if maxScroll <= 0 then
        scrollOffset = 0
    else
        scrollOffset = math.max(0, math.min(maxScroll, scrollOffset + delta * 30))
    end
    sessionChild:SetPoint("TOPLEFT", sessionClip, "TOPLEFT", -scrollOffset, -2)
end

local function BuildUI(container)
    -- Top panel: session cards row
    topPanel = CreateFrame("Frame", nil, container)
    topPanel:SetPoint("TOPLEFT",     container, "TOPLEFT",  0, -4)
    topPanel:SetPoint("TOPRIGHT",    container, "TOPRIGHT", 0,  0)
    topPanel:SetHeight(TOP_H)

    local topHeader = topPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    topHeader:SetPoint("TOPLEFT", topPanel, "TOPLEFT", 4, -2)
    topHeader:SetText("|cff888888Click a session to view its logs|r")

    -- Export button
    local exportBtn = CreateFrame("Button", nil, topPanel)
    exportBtn:SetSize(60, 18)
    exportBtn:SetPoint("TOPRIGHT", topPanel, "TOPRIGHT", -110, -2)
    exportBtn:SetNormalFontObject("GameFontHighlightSmall")
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        EbonBuilds.SessionHistory.ExportSession()
    end)

    -- Clear All button (right side)
    local clearBtn = CreateFrame("Button", nil, topPanel)
    clearBtn:SetSize(100, 18)
    clearBtn:SetPoint("TOPRIGHT", topPanel, "TOPRIGHT", -4, -2)
    clearBtn:SetNormalFontObject("GameFontHighlightSmall")
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        StaticPopup_Show("EBONBUILDS_CLEAR_SESSIONS")
    end)

    -- Horizontal scroll buttons for session cards
    local scrollLeft = CreateFrame("Button", nil, topPanel)
    scrollLeft:SetSize(16, CARD_H)
    scrollLeft:SetPoint("BOTTOMLEFT", topPanel, "BOTTOMLEFT", 2, 0)
    scrollLeft:SetNormalFontObject("GameFontNormal")
    scrollLeft:SetText("|cff888888<|r")
    scrollLeft:SetScript("OnMouseDown", function() ScrollCards(-1) end)

    local scrollRight = CreateFrame("Button", nil, topPanel)
    scrollRight:SetSize(16, CARD_H)
    scrollRight:SetPoint("BOTTOMRIGHT", topPanel, "BOTTOMRIGHT", -2, 0)
    scrollRight:SetNormalFontObject("GameFontNormal")
    scrollRight:SetText("|cff888888>|r")
    scrollRight:SetScript("OnMouseDown", function() ScrollCards(1) end)

    -- ScrollFrame for session cards: clips children and supports mouse wheel
    sessionClip = CreateFrame("ScrollFrame", nil, topPanel)
    sessionClip:SetPoint("TOP",    topHeader,   "BOTTOM",   0, -4)
    sessionClip:SetPoint("BOTTOM", topPanel,    "BOTTOM",   0,  2)
    sessionClip:SetPoint("LEFT",   scrollLeft,  "RIGHT",    2,  0)
    sessionClip:SetPoint("RIGHT",  scrollRight, "LEFT",    -2,  0)
    sessionClip:EnableMouse(true)
    sessionClip:EnableMouseWheel(true)
    sessionClip:SetScript("OnMouseWheel", function(self, delta) ScrollCards(delta) end)

    sessionChild = CreateFrame("Frame", nil, sessionClip)
    sessionChild:SetPoint("TOPLEFT", sessionClip, "TOPLEFT", 0, -2)
    sessionChild:SetHeight(CARD_H)
    sessionClip:SetScrollChild(sessionChild)

    -- Bottom panel: log table
    bottomPanel = CreateFrame("Frame", nil, container)
    bottomPanel:SetPoint("TOPLEFT",     topPanel, "BOTTOMLEFT", 0, -6)
    bottomPanel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 4)

    local logHeader = bottomPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    logHeader:SetPoint("TOPLEFT", bottomPanel, "TOPLEFT", 4, -2)
    logHeader:SetText("|cff888888Time       Action         Echo 1                Echo 2                Echo 3                Charges|r")

    logScroll = CreateFrame("ScrollFrame", nil, bottomPanel)
    logScroll:SetPoint("TOPLEFT",     logHeader, "BOTTOMLEFT", 0, -4)
    logScroll:SetPoint("BOTTOMRIGHT", bottomPanel, "BOTTOMRIGHT", -2, 2)

    logChild = CreateFrame("Frame", nil, logScroll)
    logScroll:SetScrollChild(logChild)

    logBar = CreateFrame("Slider", nil, logScroll, "UIPanelScrollBarTemplate")
    logBar:SetPoint("TOPLEFT",    logScroll, "TOPRIGHT",    -2, -4)
    logBar:SetPoint("BOTTOMLEFT", logScroll, "BOTTOMRIGHT", -2,  4)
    logBar:SetValueStep(20)
    logBar:SetScript("OnValueChanged", function(self, value)
        logChild:SetPoint("TOPLEFT", logScroll, "TOPLEFT", 0, value)
    end)
    logScroll:EnableMouseWheel(true)
    logScroll:SetScript("OnMouseWheel", function(self, delta)
        local v = logBar:GetValue()
        local mn, mx = logBar:GetMinMaxValues()
        logBar:SetValue(math.max(mn, math.min(mx, v - delta * 20)))
    end)
end

------------------------------------------------------------------------
-- Public interface
------------------------------------------------------------------------

function EbonBuilds.SessionHistory.Show(container)
    if not topPanel then
        BuildUI(container)
        -- Defer data refresh by one frame so parents resolve their sizes first.
        -- Without this, the initial render after /reload may produce hidden rows.
        local defer = CreateFrame("Frame")
        defer:SetScript("OnUpdate", function(self)
            self:Hide()
            logChild:SetWidth(math.max(logScroll:GetWidth() or 0, 450))
            EbonBuilds.SessionHistory.RefreshSessionList()
            EbonBuilds.SessionHistory.RefreshLogView()
        end)
        return
    end

    topPanel:SetParent(container)
    bottomPanel:SetParent(container)
    topPanel:Show()
    bottomPanel:Show()

    logChild:SetWidth(math.max(logScroll:GetWidth() or 0, 450))
    EbonBuilds.SessionHistory.RefreshSessionList()
    EbonBuilds.SessionHistory.RefreshLogView()
end

function EbonBuilds.SessionHistory.Hide()
    if topPanel    then topPanel:Hide()    end
    if bottomPanel then bottomPanel:Hide() end
    if exportDialog then exportDialog:Hide() end
    if durationTimer then
        durationTimer:Hide()
        activeSessionCard = nil
    end
end

function EbonBuilds.SessionHistory.Init()
    StaticPopupDialogs["EBONBUILDS_CLEAR_SESSIONS"] = {
        text = "Delete all session history? This cannot be undone.",
        button1 = "Yes", button2 = "No",
        OnAccept = function()
            EbonBuilds.Session.ClearAllSessions()
            selectedSessionId = nil
            EbonBuilds.SessionHistory.RefreshSessionList()
            EbonBuilds.SessionHistory.RefreshLogView()
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
end
