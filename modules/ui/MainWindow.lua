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

    EbonBuilds.ViewRouter.Register("welcome", {
        Show = function(container, _)
            EbonBuilds.WelcomeView.Mount(container)
        end,
        Hide = function()
            EbonBuilds.WelcomeView.Unmount()
        end,
    })

    EbonBuilds.MainWindow._ShowInitialView()
end

function EbonBuilds.MainWindow._ShowInitialView()
    local active = EbonBuilds.Build.GetActive()
    if active then
        EbonBuilds.ViewRouter.Show("buildTabs", { mode = "edit", build = active })
    elseif #EbonBuilds.Build.List() > 0 then
        EbonBuilds.ViewRouter.Show("buildTabs", { mode = "create" })
    else
        EbonBuilds.ViewRouter.Show("welcome")
    end
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
