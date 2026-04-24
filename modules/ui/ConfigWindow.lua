-- EbonBuilds: modules/ui/ConfigWindow.lua
-- Responsibility: main configuration window frame creation and toggle logic.

EbonBuilds.ConfigWindow = {}

local WINDOW_WIDTH  = 600
local WINDOW_HEIGHT = 500
local FRAME_NAME    = "EbonBuildsConfigWindow"

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

    -- Drag region covers the top strip of the frame.
    local dragRegion = CreateFrame("Frame", nil, frame)
    dragRegion:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0,   0)
    dragRegion:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0,   0)
    dragRegion:SetHeight(30)
    dragRegion:EnableMouse(true)
    dragRegion:RegisterForDrag("LeftButton")
    dragRegion:SetScript("OnDragStart", function() frame:StartMoving() end)
    dragRegion:SetScript("OnDragStop",  function() frame:StopMovingOrSizing() end)
end

local function CreateCloseButton(frame)
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
end

local function BuildFrame()
    local frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetWidth(WINDOW_WIDTH)
    frame:SetHeight(WINDOW_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)

    ApplyBackdrop(frame)
    CreateTitleBar(frame)
    CreateCloseButton(frame)

    frame:Hide()
    return frame
end

function EbonBuilds.ConfigWindow.Init()
    local frame = BuildFrame()
    EbonBuilds.ConfigWindow._frame = frame
    EbonBuilds.Filters.Init(frame)
    EbonBuilds.EchoTable.Init(frame)
end

function EbonBuilds.ConfigWindow.Toggle()
    local frame = EbonBuilds.ConfigWindow._frame
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
