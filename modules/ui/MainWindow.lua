-- EbonBuilds: modules/ui/MainWindow.lua
-- Responsibility: top-level window shell (800x550) with left column and right panel.
-- Hosts the build list and the view router.

EbonBuilds.MainWindow = {}

local WINDOW_WIDTH  = 800
local WINDOW_HEIGHT = 550
local LEFT_WIDTH    = 200
local FRAME_NAME    = "EbonBuildsMainWindow"

local function ApplyBackdrop(frame)
    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 32,
        insets   = { left = 11, right = 12, top = 12, bottom = 11 },
    })
end

local function CreateTitleBar(frame)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", frame, "TOP", 0, -16)
    title:SetText("EbonBuilds")

    local dragRegion = CreateFrame("Frame", nil, frame)
    dragRegion:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0,   0)
    dragRegion:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -37, 0)
    dragRegion:SetHeight(30)
    dragRegion:EnableMouse(true)
    dragRegion:RegisterForDrag("LeftButton")
    dragRegion:SetScript("OnDragStart", function() frame:StartMoving() end)
    dragRegion:SetScript("OnDragStop",  function() frame:StopMovingOrSizing() end)
end

local function CreateCloseButton(frame)
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    closeBtn:SetFrameLevel(100)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
end

------------------------------------------------------------------------
-- Global settings popup
------------------------------------------------------------------------

local function BuildSettingsPopup()
    local popup = CreateFrame("Frame", "EbonBuildsGlobalSettingsPopup", UIParent)
    popup:SetSize(340, 200)
    popup:SetPoint("CENTER", UIParent, "CENTER")
    popup:SetFrameStrata("DIALOG")
    popup:SetToplevel(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 32,
        insets   = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    popup:SetBackdropColor(0, 0, 0, 0.9)
    popup:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    popup:Hide()

    -- Title bar / drag region
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", popup, "TOP", 0, -16)
    title:SetText("EbonBuilds Settings")

    local drag = CreateFrame("Frame", nil, popup)
    drag:SetPoint("TOPLEFT",  popup, "TOPLEFT",  0,   0)
    drag:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -37, 0)
    drag:SetHeight(30)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() popup:StartMoving() end)
    drag:SetScript("OnDragStop",  function() popup:StopMovingOrSizing() end)

    -- Close button for popup
    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function() popup:Hide() end)

    -- Action delay
    local delayLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    delayLabel:SetPoint("TOPLEFT", popup, "TOPLEFT", 24, -44)
    delayLabel:SetText("Action delay (seconds):")

    local delayInput = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    delayInput:SetSize(60, 22)
    delayInput:SetPoint("LEFT", delayLabel, "RIGHT", 8, 0)
    delayInput:SetAutoFocus(false)
    delayInput:SetMaxLetters(4)

    local delayFlavor = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    delayFlavor:SetPoint("TOPLEFT", delayLabel, "BOTTOMLEFT", 0, -2)
    delayFlavor:SetPoint("RIGHT", popup, "RIGHT", -24, 0)
    delayFlavor:SetJustifyH("LEFT")
    delayFlavor:SetText("Very low values may cause the addon to malfunction.")

    -- Toast duration
    local toastLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    toastLabel:SetPoint("TOPLEFT", delayFlavor, "BOTTOMLEFT", 0, -16)
    toastLabel:SetText("Toast duration (seconds):")

    local toastInput = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
    toastInput:SetSize(60, 22)
    toastInput:SetPoint("LEFT", toastLabel, "RIGHT", 8, 0)
    toastInput:SetAutoFocus(false)
    toastInput:SetMaxLetters(4)

    -- Buttons
    local saveBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    saveBtn:SetSize(80, 22)
    saveBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -6, 16)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        local gs = EbonBuildsDB.globalSettings
        local delayVal = tonumber(delayInput:GetText())
        if delayVal and delayVal > 0 then
            gs.evalDelay = delayVal
        end
        local toastVal = tonumber(toastInput:GetText())
        if toastVal and toastVal > 0 then
            gs.toastDuration = toastVal
        end
        popup:Hide()
    end)

    local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -6, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() popup:Hide() end)

    popup:SetScript("OnShow", function()
        local gs = EbonBuildsDB.globalSettings
        delayInput:SetText(tostring(gs.evalDelay or 2))
        toastInput:SetText(tostring(gs.toastDuration or 3))
    end)

    return popup
end

local function CreateSettingsButton(frame, popup)
    local btn = CreateFrame("Button", nil, frame)
    btn:SetSize(28, 28)
    btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -33, -5)
    btn:SetFrameLevel(100)
    btn:SetNormalFontObject("GameFontNormalSmall")
    btn:SetText("S")
    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\UI-Panel-Button-Up",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 16,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    btn:SetBackdropColor(0, 0, 0, 0.4)
    btn:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
    btn:SetScript("OnClick", function()
        if popup:IsShown() then popup:Hide() else popup:Show() end
    end)
end

local function CreateLeftColumn(frame)
    local col = CreateFrame("Frame", nil, frame)
    col:SetPoint("TOPLEFT",    frame, "TOPLEFT",    14, -34)
    col:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14,  14)
    col:SetWidth(LEFT_WIDTH)
    return col
end

local function CreateRightPanel(frame)
    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT",     frame, "TOPLEFT",     14 + LEFT_WIDTH + 6, -34)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 14)
    return panel
end

local function BuildFrame()
    local frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetWidth(WINDOW_WIDTH)
    frame:SetHeight(WINDOW_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetMovable(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)

    ApplyBackdrop(frame)
    CreateTitleBar(frame)
    CreateCloseButton(frame)

    local settingsPopup = BuildSettingsPopup()
    CreateSettingsButton(frame, settingsPopup)
    frame._settingsPopup = settingsPopup

    frame:Hide()
    return frame
end

function EbonBuilds.MainWindow.Init()
    local frame = BuildFrame()
    local left  = CreateLeftColumn(frame)
    local right = CreateRightPanel(frame)

    EbonBuilds.MainWindow._frame = frame
    EbonBuilds.MainWindow._left  = left
    EbonBuilds.MainWindow._right = right

    EbonBuilds.ViewRouter.SetContainer(right)
    EbonBuilds.BuildList.Init(left)
    EbonBuilds.WeightsView.Init()
    EbonBuilds.BuildForm.Init()
    EbonBuilds.SettingsView.Init()
    EbonBuilds.BuildTabs.Init()
    EbonBuilds.BuildOverview.Init()
    EbonBuilds.PublicBuildsView.Init()

    EbonBuilds.ViewRouter.Register("welcome", {
        Show = function(container, _)
            EbonBuilds.WelcomeView.Mount(container)
        end,
        Hide = function()
            EbonBuilds.WelcomeView.Unmount()
        end,
    })

    EbonBuilds.ViewRouter.Register("publicBuilds", {
        Show = function(container, _)
            EbonBuilds.PublicBuildsView.Mount(container)
        end,
        Hide = function()
            EbonBuilds.PublicBuildsView.Unmount()
        end,
    })

    EbonBuilds.MainWindow._ShowInitialView()
end

function EbonBuilds.MainWindow._ShowInitialView()
    local active = EbonBuilds.Build.GetActive()
    if active then
        EbonBuilds.ViewRouter.Show("buildOverview", { build = active })
    else
        EbonBuilds.ViewRouter.Show("welcome")
    end
end

SLASH_EbonBuilds1 = "/ebb"
SLASH_EbonBuilds2 = "/ebonbuilds"
SlashCmdList["EbonBuilds"] = function()
    EbonBuilds.MainWindow.Toggle()
end

function EbonBuilds.MainWindow.Toggle()
    local frame = EbonBuilds.MainWindow._frame
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    else
        EbonBuilds.MainWindow._ShowInitialView()
        frame:Show()
    end
end

function EbonBuilds.MainWindow.GetRightPanel()
    return EbonBuilds.MainWindow._right
end
