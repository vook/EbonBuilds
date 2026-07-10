-- EbonBuilds: modules/ui/SessionHistory.lua
-- Responsibility: session history UI replacing the Logbook tab content.

EbonBuilds.SessionHistory = {}

local ST = EbonBuilds.SiteTheme
local SW = EbonBuilds.SiteWidgets
local C  = ST.C
local L  = ST.Layout

local ACTION_COLORS = {
    Banish              = { 1.0, 0.27, 0.27 },
    Reroll              = { 0.27, 0.67, 1.0 },
    Freeze              = { 0.27, 0.80, 1.0 },
    Select              = { 0.27, 1.0, 0.27 },
    ["Select (Locked)"] = { 1.0, 0.53, 0.0 },
}

local CARD_W          = 176
local CARD_H          = 50
local CARD_GAP        = 8
local TOP_TOOLBAR_H   = 32
local TOP_SESSION_H   = 56
local TOP_H           = TOP_TOOLBAR_H + TOP_SESSION_H + 6

local LOG_CHARGES_W   = 100
local LOG_ROW_H       = 22
local LOG_WEIGHT_W    = 30
local LOG_WEIGHT_GAP  = 10
local LOG_SLOT_GAP    = 12
local LOG_ROW_GAP     = 2
local LOG_ACTION_PAD  = 8

local logColumnHeader
local measureFont

local topPanel, bottomPanel
local rootPanel
local sessionItems = {}
local logRows      = {}
local selectedSessionId = nil

local sessionChild, sessionClip, scrollOffset = nil, nil, 0
local logScroll, logChild, logBar
local durationTimer
local logRefreshTimer

local function ScheduleLogbookLayout()
    if not logScroll or not logChild then return end
    if not rootPanel or not rootPanel:IsShown() then return end

    local viewH = logScroll:GetHeight() or 0
    if viewH < 8 then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, ScheduleLogbookLayout)
        end
        return
    end

    logChild:SetWidth(math.max(logScroll:GetWidth() or 0, 450))
    if logBar then
        SW.UpdateVerticalScroll(logScroll, logChild, logBar)
    end
    EbonBuilds.SessionHistory.RefreshLogView()
end

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

local function MeasureText(text, size)
    if not measureFont then return #tostring(text) * 6 end
    SW.SetFont(measureFont, size or 10, "regular")
    measureFont:SetText(text or "")
    return measureFont:GetStringWidth() or 0
end

local function SessionCardLines(session, isActive)
    local logs = session.logs or {}
    local n = #logs
    local buildTitle = session.buildTitle or "Untitled build"
    local dur = FormatDuration(session.startTime, isActive and nil or session.endTime)

    if isActive then
        local meta = string.format("%d actions · %s", n, dur)
        return buildTitle, meta
    end

    local when = session.startTime and date("%b %d · %H:%M", session.startTime) or ""
    local peak = (session.maxLevel and session.maxLevel > 1)
        and string.format("Lv %d · ", session.maxLevel) or ""
    local meta = string.format("%s%d actions · %s", peak, n, dur)
    if when ~= "" then
        meta = meta .. " · " .. when
    end
    return buildTitle, meta
end

------------------------------------------------------------------------
-- Duration timer
------------------------------------------------------------------------

local activeSessionCard = nil

local function OnDurationTick(self, dt)
    self._elapsed = (self._elapsed or 0) + dt
    if self._elapsed < 1 then return end
    self._elapsed = 0

    if not activeSessionCard or not activeSessionCard._isActive then
        activeSessionCard = nil
        self:Hide()
        return
    end

    local _, meta = SessionCardLines({
        startTime = activeSessionCard._startTime,
        logs = activeSessionCard._logs or {},
        buildTitle = activeSessionCard._buildTitle,
    }, true)
    activeSessionCard._metaLabel:SetText(meta)
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
-- Session cards
------------------------------------------------------------------------

local function ClearSessionItems()
    for _, item in ipairs(sessionItems) do
        item:Hide()
    end
end

local function ApplySessionCardState(item, selected)
    if selected then
        item._bg:SetVertexColor(
            C.accentBg10[1], C.accentBg10[2], C.accentBg10[3], 1)
    elseif item._isActive then
        item._bg:SetVertexColor(
            C.successBg10[1], C.successBg10[2], C.successBg10[3], 1)
    else
        item._bg:SetVertexColor(unpack(C.elementBg))
    end

    if item._activeStripe then
        if item._isActive then
            item._activeStripe:Show()
        else
            item._activeStripe:Hide()
        end
    end
end

local function SelectSession(id)
    selectedSessionId = id
    for _, item in ipairs(sessionItems) do
        ApplySessionCardState(item, item._id == id)
    end
    ScheduleLogbookLayout()
end

local function BuildCard(parent)
    local item = CreateFrame("Button", nil, parent)
    item:SetSize(CARD_W, CARD_H)
    item:RegisterForClicks("LeftButtonUp")
    item._bg = SW.Fill(item, "elementBg")

    item._activeStripe = item:CreateTexture(nil, "ARTWORK")
    item._activeStripe:SetTexture(ST.FLAT)
    item._activeStripe:SetVertexColor(unpack(C.success))
    item._activeStripe:SetWidth(3)
    item._activeStripe:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
    item._activeStripe:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, 0)
    item._activeStripe:Hide()

    item._titleLabel = SW.Label(item, "", 11, C.text, false, "semibold")
    item._titleLabel:SetPoint("TOPLEFT", item, "TOPLEFT", 10, -8)
    item._titleLabel:SetPoint("RIGHT", item, "RIGHT", -24, 0)
    item._titleLabel:SetJustifyH("LEFT")
    item._titleLabel:SetHeight(14)

    item._metaLabel = SW.Label(item, "", 10, C.textMuted)
    item._metaLabel:SetPoint("TOPLEFT", item._titleLabel, "BOTTOMLEFT", 0, -2)
    item._metaLabel:SetPoint("RIGHT", item, "RIGHT", -24, 0)
    item._metaLabel:SetJustifyH("LEFT")
    item._metaLabel:SetHeight(12)

    local delBtn = CreateFrame("Button", nil, item)
    delBtn:SetSize(16, 16)
    delBtn:SetPoint("TOPRIGHT", item, "TOPRIGHT", -4, -4)
    delBtn:SetNormalFontObject("GameFontHighlightSmall")
    delBtn:SetText("|cff888888×|r")
    delBtn:SetScript("OnClick", function()
        if item._id then
            StaticPopupDialogs["EBONBUILDS_DELETE_SESSION"] = {
                text = "Delete this session and all its logs?",
                button1 = "Yes", button2 = "No",
                OnAccept = function()
                    EbonBuilds.Session.DeleteSession(item._id)
                    if selectedSessionId == item._id then
                        selectedSessionId = nil
                    end
                    EbonBuilds.SessionHistory.RefreshSessionList()
                    EbonBuilds.SessionHistory.RefreshLogView()
                end,
                timeout = 0, whileDead = true, hideOnEscape = true,
            }
            StaticPopup_Show("EBONBUILDS_DELETE_SESSION")
        end
    end)
    item._delBtn = delBtn

    item:SetScript("OnClick", function()
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
    local x = 0
    for i, s in ipairs(sorted) do
        if #sessionItems < i then
            sessionItems[i] = BuildCard(sessionChild)
        end
        local item = sessionItems[i]

        item._id         = s.id
        item._isActive   = (s.endTime == nil)
        item._startTime  = s.startTime
        item._logs       = s.logs
        item._buildTitle = s.buildTitle

        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", sessionChild, "TOPLEFT", x, 0)
        item:SetSize(CARD_W, CARD_H)

        local title, meta = SessionCardLines(s, item._isActive)
        item._titleLabel:SetText(title)
        item._metaLabel:SetText(meta)

        if item._isActive then
            if item._delBtn then item._delBtn:Hide() end
            activeCard = item
        else
            if item._delBtn then item._delBtn:Show() end
        end

        ApplySessionCardState(item, s.id == selectedSessionId)
        item:Show()
        x = x + CARD_W + CARD_GAP
    end

    sessionChild:SetWidth(math.max(x, 1))

    if activeCard then
        StartDurationTimer(activeCard)
    elseif durationTimer then
        durationTimer:Hide()
        activeSessionCard = nil
    end

    local clipW = sessionClip:GetWidth()
    if x <= clipW then
        scrollOffset = 0
        sessionChild:SetPoint("TOPLEFT", sessionClip, "TOPLEFT", 0, 0)
    end
end

------------------------------------------------------------------------
-- Log table
------------------------------------------------------------------------

local function ClearLogRows()
    for _, row in ipairs(logRows) do
        row:Hide()
    end
end

local function ComputeLogLayout(logs, rowW)
    local actionW = LOG_ACTION_PAD
    for _, entry in ipairs(logs) do
        local w = MeasureText(entry.action or "", 11) + LOG_ACTION_PAD
        if w > actionW then actionW = w end
    end
    actionW = math.max(44, math.ceil(actionW))

    local slotWidths = { 0, 0, 0 }
    for _, entry in ipairs(logs) do
        for j = 1, 3 do
            local ch = entry.choices and entry.choices[j]
            if ch then
                local need = LOG_WEIGHT_W + LOG_WEIGHT_GAP
                    + MeasureText(ch.name or "", 10) + 6
                if need > slotWidths[j] then slotWidths[j] = need end
            end
        end
    end

    local gaps = LOG_ACTION_PAD + LOG_SLOT_GAP * 2 + 16 + 8
    local avail = rowW - actionW - LOG_CHARGES_W - gaps
    local ideal = slotWidths[1] + slotWidths[2] + slotWidths[3]

    if ideal <= 0 then
        local even = math.max(80, math.floor(avail / 3))
        return actionW, even, even, even
    end

    if ideal <= avail then
        return actionW, slotWidths[1], slotWidths[2], slotWidths[3]
    end

    local scale = avail / ideal
    return actionW,
        math.max(72, math.floor(slotWidths[1] * scale)),
        math.max(72, math.floor(slotWidths[2] * scale)),
        math.max(72, math.floor(slotWidths[3] * scale))
end

local function LayoutLogColumnHeader(actionW, w1, w2, w3)
    if not logColumnHeader then return end
    local x = LOG_ACTION_PAD
    logColumnHeader._actionLbl:ClearAllPoints()
    logColumnHeader._actionLbl:SetPoint("LEFT", logColumnHeader, "LEFT", x, 0)
    logColumnHeader._actionLbl:SetWidth(actionW)
    x = x + actionW + LOG_SLOT_GAP

    local widths = { w1, w2, w3 }
    for i = 1, 3 do
        local lbl = logColumnHeader._choiceLbls[i]
        lbl:ClearAllPoints()
        lbl:SetPoint("LEFT", logColumnHeader, "LEFT", x, 0)
        lbl:SetWidth(widths[i])
        x = x + widths[i] + LOG_SLOT_GAP
    end
end

local function BuildLogRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(LOG_ROW_H)

    row._bg = row:CreateTexture(nil, "BACKGROUND")
    row._bg:SetTexture(ST.FLAT)
    row._bg:SetAllPoints(row)
    row._bg:SetVertexColor(0, 0, 0, 0)

    local actionLabel = SW.Label(row, "", 11, C.text)
    actionLabel:SetPoint("LEFT", row, "LEFT", LOG_ACTION_PAD, 0)
    actionLabel:SetJustifyH("LEFT")
    actionLabel:SetHeight(14)
    row._actionLabel = actionLabel

    local chargesFs = SW.Label(row, "", 10, C.textMuted)
    chargesFs:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    chargesFs:SetWidth(LOG_CHARGES_W)
    chargesFs:SetJustifyH("RIGHT")
    chargesFs:SetHeight(14)
    row._chargesFs = chargesFs

    row._echoSlots = {}
    row._slotsRow = CreateFrame("Frame", nil, row)
    row._slotsRow:SetPoint("LEFT", actionLabel, "RIGHT", LOG_SLOT_GAP, 0)
    row._slotsRow:SetPoint("RIGHT", chargesFs, "LEFT", -8, 0)
    row._slotsRow:SetPoint("TOP", row, "TOP", 0, 0)
    row._slotsRow:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)

    for i = 1, 3 do
        local slot = CreateFrame("Frame", nil, row._slotsRow)
        slot:SetHeight(LOG_ROW_H)

        local scoreFont = SW.Label(slot, "", 9, C.textMuted)
        scoreFont:SetPoint("LEFT", slot, "LEFT", 0, 0)
        scoreFont:SetWidth(LOG_WEIGHT_W)
        scoreFont:SetJustifyH("RIGHT")
        scoreFont:SetHeight(14)

        local nameFont = SW.Label(slot, "", 10, C.text)
        nameFont:SetPoint("LEFT", scoreFont, "RIGHT", LOG_WEIGHT_GAP, 0)
        nameFont:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
        nameFont:SetJustifyH("LEFT")
        nameFont:SetHeight(14)

        slot._nameFont = nameFont
        slot._scoreFont = scoreFont
        slot:EnableMouse(true)
        slot:SetScript("OnEnter", function(self)
            if self._spellId and EbonBuilds.EchoTableRows.ShowEchoTooltip then
                local extra
                if self._echoScore then
                    extra = {
                        { text = string.format("Score: %.0f", self._echoScore), r = 0.7, g = 0.7, b = 0.7 },
                    }
                end
                EbonBuilds.EchoTableRows.ShowEchoTooltip(self, self._spellId, extra)
            elseif self._echoName then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:ClearLines()
                GameTooltip:AddLine(self._echoName, 1, 1, 1)
                if self._echoScore then
                    GameTooltip:AddLine(("Score: %.0f"):format(self._echoScore), 0.7, 0.7, 0.7)
                end
                GameTooltip:Show()
            end
        end)
        slot:SetScript("OnLeave", function()
            if EbonBuilds.EchoTableRows.HideEchoTooltip then
                EbonBuilds.EchoTableRows.HideEchoTooltip()
            else
                GameTooltip:Hide()
            end
        end)

        row._echoSlots[i] = slot
    end

    row:Hide()
    return row
end

function EbonBuilds.SessionHistory.RefreshLogView()
    ClearLogRows()

    if not logScroll or not logChild then return end

    local viewH = logScroll:GetHeight() or 0
    if viewH < 8 and logScroll:IsShown() then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, ScheduleLogbookLayout)
        end
        return
    end

    logChild:SetWidth(math.max(logScroll:GetWidth() or 0, 450))

    local prevSessionId = logChild._sessionId
    local sessionSwitched = (selectedSessionId ~= prevSessionId)

    if not selectedSessionId then
        logChild:SetHeight(1)
        logChild._sessionId = nil
        if logBar then logBar:SetMinMaxValues(0, 0) end
        return
    end

    local session
    for _, s in ipairs(EbonBuilds.Session.GetSessions()) do
        if s.id == selectedSessionId then session = s; break end
    end
    if not session then
        logChild:SetHeight(1)
        logChild._sessionId = nil
        if logBar then logBar:SetMinMaxValues(0, 0) end
        return
    end

    logChild._sessionId = selectedSessionId

    local savedScroll = logBar and logBar:GetValue() or 0
    if sessionSwitched and logBar then
        savedScroll = 0
        logBar:SetValue(0)
    end

    local logs = session.logs or {}
    local rowW = math.max(logChild:GetWidth() or 0, 500)
    local actionW, w1, w2, w3 = ComputeLogLayout(logs, rowW)
    local slotWidths = { w1, w2, w3 }
    LayoutLogColumnHeader(actionW, w1, w2, w3)

    local function LayoutEchoSlots(row)
        local x = 0
        for j = 1, 3 do
            local slot = row._echoSlots[j]
            local sw = slotWidths[j]
            slot:ClearAllPoints()
            slot:SetSize(sw, LOG_ROW_H)
            slot:SetPoint("LEFT", row._slotsRow, "LEFT", x, 0)
            x = x + sw + LOG_SLOT_GAP
        end
        row._actionLabel:SetWidth(actionW)
    end

    for i, entry in ipairs(logs) do
        if #logRows < i then
            logRows[i] = BuildLogRow(logChild)
        end
        local row = logRows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", logChild, "TOPLEFT", 0, -((i - 1) * (LOG_ROW_H + LOG_ROW_GAP)))
        row:SetPoint("RIGHT", logChild, "RIGHT", 0, 0)
        row:SetHeight(LOG_ROW_H)
        LayoutEchoSlots(row)

        if i % 2 == 0 then
            row._bg:SetVertexColor(C.tierRowBg[1], C.tierRowBg[2], C.tierRowBg[3], 0.45)
        else
            row._bg:SetVertexColor(0, 0, 0, 0)
        end

        local ac = ACTION_COLORS[entry.action] or C.text
        row._actionLabel:SetText(entry.action or "")
        row._actionLabel:SetTextColor(ac[1], ac[2], ac[3], 1)

        for j = 1, 3 do
            local ch = entry.choices and entry.choices[j]
            local slot = row._echoSlots[j]

            if ch then
                local qColor = ST.QUALITY_BORDER[ch.quality] or ST.QUALITY_BORDER[0]
                if j == entry.targetIndex then
                    slot._nameFont:SetTextColor(ac[1], ac[2], ac[3], 1)
                else
                    slot._nameFont:SetTextColor(unpack(qColor))
                end
                slot._nameFont:SetText(ch.name)
                slot._scoreFont:SetText(string.format("%.0f", ch.score or 0))
                slot._echoName  = ch.name
                slot._echoScore = ch.score
                slot._spellId   = EbonBuilds.EchoTableRows
                    and EbonBuilds.EchoTableRows.ResolveSpellId
                    and EbonBuilds.EchoTableRows.ResolveSpellId(ch.name, ch.quality)
                    or nil
            else
                slot._nameFont:SetText("—")
                slot._nameFont:SetTextColor(unpack(C.textMuted))
                slot._scoreFont:SetText("")
                slot._echoName  = nil
                slot._echoScore = nil
                slot._spellId   = nil
            end
        end

        local ch = entry.charges or {}
        row._chargesFs:SetText(string.format("B:%d  R:%d  F:%d",
            ch.ban or 0, ch.reroll or 0, ch.freeze or 0))

        row:Show()
    end

    local totalH = math.max(#logs * (LOG_ROW_H + LOG_ROW_GAP) + 4, viewH)
    logChild:SetHeight(totalH)
    if logBar then
        local mx = math.max(0, totalH - viewH)
        logBar:SetMinMaxValues(0, mx)
        if not sessionSwitched then
            logBar:SetValue(math.min(savedScroll, mx))
        end
        SW.UpdateVerticalScroll(logScroll, logChild, logBar)
        local offset = logBar:GetValue() or 0
        logChild:ClearAllPoints()
        logChild:SetPoint("TOPLEFT", logScroll, "TOPLEFT", 0, offset)
    end
end

------------------------------------------------------------------------
-- Copy dialog
------------------------------------------------------------------------

local copyDialog

local function HideCopyDialog()
    if not copyDialog then return end
    if copyDialog._editBox then
        copyDialog._editBox:ClearFocus()
    end
    copyDialog:Hide()
end

local function UpdateCopyDialogScroll()
    if not copyDialog or not copyDialog._scroll or not copyDialog._editBox then return end

    local scroll = copyDialog._scroll
    local editBox = copyDialog._editBox
    local bar = copyDialog._bar
    local scrollW = scroll:GetWidth()
    local scrollH = scroll:GetHeight()
    if scrollW <= 0 or scrollH <= 0 then return end

    editBox:SetWidth(scrollW)
    local text = editBox:GetText() or ""
    local lineCount = select(2, text:gsub("\n", "\n")) + 1
    local contentH = math.max(lineCount * 14 + 16, scrollH)
    editBox:SetHeight(contentH)

    local maxScroll = math.max(0, contentH - scrollH)
    if maxScroll > 0 then
        bar:SetMinMaxValues(0, maxScroll)
        if bar:GetValue() > maxScroll then
            bar:SetValue(maxScroll)
        end
        bar:Show()
        editBox:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, bar:GetValue())
    else
        bar:SetValue(0)
        bar:SetMinMaxValues(0, 0)
        bar:Hide()
        editBox:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    end
end

local function ScrollCopyDialog(delta)
    if not copyDialog or not copyDialog._bar or not copyDialog._bar:IsShown() then return end
    local bar = copyDialog._bar
    local step = 36
    local v = bar:GetValue()
    local mn, mx = bar:GetMinMaxValues()
    bar:SetValue(math.max(mn, math.min(mx, v - delta * step)))
end

local function BuildCopyDialog()
    local f = CreateFrame("Frame", "EbonBuildsCopyLogbookDialog", UIParent)
    f:SetSize(800, 550)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self:StartMoving() end
    end)
    f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)
    f:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        if self._editBox then self._editBox:ClearFocus() end
    end)
    f:SetScript("OnShow", function(self)
        self:Raise()
        if type(PromoteSpecialFrame) == "function" then
            PromoteSpecialFrame(self:GetName())
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, UpdateCopyDialogScroll)
        else
            UpdateCopyDialogScroll()
        end
    end)
    f:Hide()

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, f:GetName())
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
    title:SetText("Export Logbook")

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetPoint("RIGHT", f, "RIGHT", -48, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("|cff888888Select all (Ctrl+A) and copy (Ctrl+C), or click Close when done.|r")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    close:SetFrameLevel(f:GetFrameLevel() + 20)
    close:SetScript("OnClick", function() HideCopyDialog() end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 22)
    closeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() HideCopyDialog() end)

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -4, -10)
    scroll:SetPoint("BOTTOMRIGHT", closeBtn, "TOPRIGHT", -28, 10)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(0)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetTextInsets(6, 6, 4, 4)
    editBox:SetAutoFocus(false)
    editBox:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    editBox:SetScript("OnEscapePressed", function() HideCopyDialog() end)
    editBox:SetScript("OnMouseWheel", function(_, delta) ScrollCopyDialog(delta) end)
    scroll:SetScrollChild(editBox)

    local bar = CreateFrame("Slider", nil, scroll, "UIPanelScrollBarTemplate")
    bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", -2, -18)
    bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -2, 18)
    bar:SetValueStep(18)
    SW.StyleVerticalScrollBar(bar)
    bar:Hide()
    bar:SetScript("OnValueChanged", function(_, value)
        editBox:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, value)
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) ScrollCopyDialog(delta) end)

    f._editBox = editBox
    f._scroll  = scroll
    f._bar     = bar
    return f
end

local function FocusCopyEditBox()
    if not copyDialog or not copyDialog._editBox then return end
    copyDialog._editBox:SetFocus()
    copyDialog._editBox:HighlightText()
end

local function ShowCopyDialogForSession(session)
    if not copyDialog then
        copyDialog = BuildCopyDialog()
    end

    local text = EbonBuilds.Session.FormatReport(session)
    copyDialog._editBox:SetText(text)
    copyDialog._bar:SetValue(0)
    copyDialog:Show()
    UpdateCopyDialogScroll()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, FocusCopyEditBox)
    else
        FocusCopyEditBox()
    end
end

function EbonBuilds.SessionHistory.HideCopyDialog()
    HideCopyDialog()
end

function EbonBuilds.SessionHistory.ShowCopyDialog()
    local session
    if selectedSessionId then
        for _, s in ipairs(EbonBuilds.Session.GetSessions()) do
            if s.id == selectedSessionId then session = s; break end
        end
    end
    ShowCopyDialogForSession(session)
end

function EbonBuilds.SessionHistory.ExportSession()
    EbonBuilds.SessionHistory.ShowCopyDialog()
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
    sessionChild:SetPoint("TOPLEFT", sessionClip, "TOPLEFT", -scrollOffset, 0)
end

local function BuildUI(container)
    local root = SW.WrapContentCard(container, L.PAD)
    rootPanel = root

    topPanel = CreateFrame("Frame", nil, root)
    topPanel:SetPoint("TOPLEFT", root, "TOPLEFT", L.PAD, -L.PAD)
    topPanel:SetPoint("TOPRIGHT", root, "TOPRIGHT", -L.PAD, -L.PAD)
    topPanel:SetHeight(TOP_H)

    local toolbar = CreateFrame("Frame", nil, topPanel)
    toolbar:SetPoint("TOPLEFT", topPanel, "TOPLEFT", 0, 0)
    toolbar:SetPoint("TOPRIGHT", topPanel, "TOPRIGHT", 0, 0)
    toolbar:SetHeight(TOP_TOOLBAR_H)

    local topHeader = SW.Label(toolbar, "Sessions", 12, C.text, false, "semibold")
    topHeader:SetPoint("LEFT", toolbar, "LEFT", 4, 0)

    local exportBtn = SW.CreateOutlineButton(toolbar, "Export", 72)
    exportBtn:SetPoint("RIGHT", toolbar, "RIGHT", -90, 0)
    exportBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Export logbook + automation settings for the selected run", 1, 1, 1)
        GameTooltip:Show()
    end)
    exportBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    exportBtn:SetScript("OnClick", function()
        EbonBuilds.SessionHistory.ShowCopyDialog()
    end)

    local clearBtn = SW.CreateOutlineButton(toolbar, "Clear All", 84)
    clearBtn:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
    clearBtn:SetScript("OnClick", function()
        StaticPopup_Show("EBONBUILDS_CLEAR_SESSIONS")
    end)

    local sessionRow = CreateFrame("Frame", nil, topPanel)
    sessionRow:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -6)
    sessionRow:SetPoint("BOTTOMRIGHT", topPanel, "BOTTOMRIGHT", 0, 0)

    local scrollLeft = SW.CreateOutlineButton(sessionRow, "<", 24)
    scrollLeft:SetPoint("LEFT", sessionRow, "LEFT", 0, 0)
    scrollLeft:SetPoint("TOP", sessionRow, "TOP", 0, 0)
    scrollLeft:SetPoint("BOTTOM", sessionRow, "BOTTOM", 0, 0)
    scrollLeft:SetScript("OnMouseDown", function() ScrollCards(-1) end)

    local scrollRight = SW.CreateOutlineButton(sessionRow, ">", 24)
    scrollRight:SetPoint("RIGHT", sessionRow, "RIGHT", 0, 0)
    scrollRight:SetPoint("TOP", sessionRow, "TOP", 0, 0)
    scrollRight:SetPoint("BOTTOM", sessionRow, "BOTTOM", 0, 0)
    scrollRight:SetScript("OnMouseDown", function() ScrollCards(1) end)

    sessionClip = CreateFrame("ScrollFrame", nil, sessionRow)
    sessionClip:SetPoint("LEFT", scrollLeft, "RIGHT", 6, 0)
    sessionClip:SetPoint("RIGHT", scrollRight, "LEFT", -6, 0)
    sessionClip:SetPoint("TOP", sessionRow, "TOP", 0, 0)
    sessionClip:SetPoint("BOTTOM", sessionRow, "BOTTOM", 0, 0)
    sessionClip:EnableMouse(true)
    sessionClip:EnableMouseWheel(true)
    sessionClip:SetScript("OnMouseWheel", function(self, delta) ScrollCards(delta) end)

    sessionChild = CreateFrame("Frame", nil, sessionClip)
    sessionChild:SetPoint("TOPLEFT", sessionClip, "TOPLEFT", 0, 0)
    sessionChild:SetHeight(CARD_H)
    sessionClip:SetScrollChild(sessionChild)

    measureFont = topPanel:CreateFontString(nil, "OVERLAY")
    measureFont:Hide()

    bottomPanel = CreateFrame("Frame", nil, root)
    bottomPanel:SetPoint("TOPLEFT", topPanel, "BOTTOMLEFT", 0, -10)
    bottomPanel:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -L.PAD, L.PAD)

    logColumnHeader = CreateFrame("Frame", nil, bottomPanel)
    logColumnHeader:SetPoint("TOPLEFT", bottomPanel, "TOPLEFT", 0, 0)
    logColumnHeader:SetPoint("TOPRIGHT", bottomPanel, "TOPRIGHT", -18, 0)
    logColumnHeader:SetHeight(16)

    logColumnHeader._actionLbl = SW.Label(logColumnHeader, "ACTION", 9, C.textMuted, false, "semibold")
    logColumnHeader._actionLbl:SetPoint("LEFT", logColumnHeader, "LEFT", LOG_ACTION_PAD, 0)
    logColumnHeader._actionLbl:SetJustifyH("LEFT")

    logColumnHeader._choiceLbls = {}
    for i = 1, 3 do
        logColumnHeader._choiceLbls[i] = SW.Label(
            logColumnHeader, "CHOICE " .. i, 9, C.textMuted, false, "semibold")
        logColumnHeader._choiceLbls[i]:SetJustifyH("LEFT")
    end

    logColumnHeader._chargesLbl = SW.Label(logColumnHeader, "CHARGES", 9, C.textMuted, false, "semibold")
    logColumnHeader._chargesLbl:SetPoint("RIGHT", logColumnHeader, "RIGHT", -8, 0)
    logColumnHeader._chargesLbl:SetWidth(LOG_CHARGES_W)
    logColumnHeader._chargesLbl:SetJustifyH("RIGHT")

    logScroll = CreateFrame("ScrollFrame", nil, bottomPanel)
    logScroll:SetPoint("TOPLEFT", logColumnHeader, "BOTTOMLEFT", 0, -6)
    logScroll:SetPoint("BOTTOMRIGHT", bottomPanel, "BOTTOMRIGHT", -18, 0)

    logChild = CreateFrame("Frame", nil, logScroll)
    logScroll:SetScrollChild(logChild)

    logBar = CreateFrame("Slider", nil, logScroll, "UIPanelScrollBarTemplate")
    logBar:SetPoint("TOPLEFT", logScroll, "TOPRIGHT", -2, -4)
    logBar:SetPoint("BOTTOMLEFT", logScroll, "BOTTOMRIGHT", -2, 4)
    logBar:SetValueStep(20)
    SW.StyleVerticalScrollBar(logBar)
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
    if not rootPanel then
        BuildUI(container)
        rootPanel:Show()
        if topPanel then topPanel:Show() end
        if bottomPanel then bottomPanel:Show() end
        local defer = CreateFrame("Frame")
        defer:SetScript("OnUpdate", function(self)
            self:Hide()
            ScheduleLogbookLayout()
        end)
        return
    end

    rootPanel:SetParent(container)
    rootPanel:ClearAllPoints()
    rootPanel:SetAllPoints(container)
    rootPanel:Show()
    if topPanel then topPanel:Show() end
    if bottomPanel then bottomPanel:Show() end

    EbonBuilds.SessionHistory.RefreshSessionList()
    ScheduleLogbookLayout()

    if not logRefreshTimer then
        logRefreshTimer = CreateFrame("Frame")
        logRefreshTimer._elapsed = 0
        logRefreshTimer:SetScript("OnUpdate", function(self, dt)
            self._elapsed = self._elapsed + dt
            if self._elapsed < 2 then return end
            self._elapsed = 0
            EbonBuilds.SessionHistory.RefreshSessionList()
            EbonBuilds.SessionHistory.RefreshLogView()
        end)
    end
    logRefreshTimer._elapsed = 0
    logRefreshTimer:Show()
end

function EbonBuilds.SessionHistory.Hide()
    if rootPanel then rootPanel:Hide() end
    HideCopyDialog()
    if durationTimer then
        durationTimer:Hide()
        activeSessionCard = nil
    end
    if logRefreshTimer then
        logRefreshTimer:Hide()
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

function EbonBuilds.SessionHistory.CloseExportDialog()
    HideCopyDialog()
end
