-- EbonBuilds: modules/ui/MainWindow.lua
-- Responsibility: top-level site-styled window shell with left build list and right panel.

EbonBuilds.MainWindow = {}

local ST = EbonBuilds.SiteTheme
local SW = EbonBuilds.SiteWidgets
local L  = ST.Layout

local LEFT_WIDTH = 220
local FRAME_NAME = "EbonBuildsMainWindow"

local NAV_VIEW_MAP = {
    welcome       = "myBuild",
    buildOverview = "myBuild",
    buildTabs     = "myBuild",
    buildWizard   = "myBuild",
    publicBuilds  = "publicBuilds",
}

local frame
local bodyRow
local leftPanel
local divider
local rightPanel
local buildListCollapsed = false

local function ResolveThemeClass(context)
    if context and context.build and context.build.class then
        return context.build.class
    end
    if EbonBuilds.Build and EbonBuilds.Build.PlayerClassToken then
        return EbonBuilds.Build.PlayerClassToken()
    end
    return select(2, UnitClass("player"))
end

local function ApplyThemeClass(context)
    if ST and ST.SetAccentClass then
        ST.SetAccentClass(ResolveThemeClass(context))
    end
end

local function IsBuildDetailView(viewName)
    return viewName == "buildOverview" or viewName == "buildTabs"
end

local function ApplyBodyLayout(viewName)
    if not frame or not bodyRow or not leftPanel or not rightPanel then return end

    if viewName == "welcome"
        or viewName == "buildWizard"
        or viewName == "publicBuilds" then
        leftPanel:Hide()
        if divider then divider:Hide() end
        rightPanel:Show()
        rightPanel:ClearAllPoints()
        rightPanel:SetPoint("TOPLEFT", bodyRow, "TOPLEFT", 0, 0)
        rightPanel:SetPoint("BOTTOMRIGHT", bodyRow, "BOTTOMRIGHT", 0, 0)
    elseif IsBuildDetailView(viewName) and not buildListCollapsed then
        -- Build picker: list fills the main window; hide overview + tabs.
        leftPanel:Show()
        if divider then divider:Hide() end
        leftPanel:ClearAllPoints()
        leftPanel:SetPoint("TOPLEFT", bodyRow, "TOPLEFT", 0, 0)
        leftPanel:SetPoint("BOTTOMRIGHT", bodyRow, "BOTTOMRIGHT", 0, 0)
        rightPanel:Hide()
    elseif IsBuildDetailView(viewName) and buildListCollapsed then
        -- Build detail: overview sidebar + tabs only.
        leftPanel:Hide()
        if divider then divider:Hide() end
        rightPanel:Show()
        rightPanel:ClearAllPoints()
        rightPanel:SetPoint("TOPLEFT", bodyRow, "TOPLEFT", 0, 0)
        rightPanel:SetPoint("BOTTOMRIGHT", bodyRow, "BOTTOMRIGHT", 0, 0)
    else
        leftPanel:Show()
        if divider then divider:Show() end
        leftPanel:ClearAllPoints()
        leftPanel:SetPoint("TOPLEFT", bodyRow, "TOPLEFT", 0, 0)
        leftPanel:SetPoint("BOTTOMLEFT", bodyRow, "BOTTOMLEFT", 0, 0)
        leftPanel:SetWidth(LEFT_WIDTH)
        rightPanel:Show()
        rightPanel:ClearAllPoints()
        rightPanel:SetPoint("TOPLEFT", divider, "TOPRIGHT", 8, 0)
        rightPanel:SetPoint("BOTTOMRIGHT", bodyRow, "BOTTOMRIGHT", 0, 0)
    end

    if IsBuildDetailView(viewName)
        and EbonBuilds.BuildOverview
        and EbonBuilds.BuildOverview.SetDetailPanelVisible then
        EbonBuilds.BuildOverview.SetDetailPanelVisible(
            buildListCollapsed and viewName == "buildOverview")
    end

    if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
        EbonBuilds.BuildList.Refresh()
    end
end

function EbonBuilds.MainWindow.IsBuildListCollapsed()
    return buildListCollapsed
end

function EbonBuilds.MainWindow.SetBuildListCollapsed(collapsed)
    if buildListCollapsed == collapsed then return end
    buildListCollapsed = collapsed and true or false
    local viewName = EbonBuilds.ViewRouter and EbonBuilds.ViewRouter.Current()
    if viewName then ApplyBodyLayout(viewName) end
    if EbonBuilds.BuildOverview and EbonBuilds.BuildOverview.OnBuildListLayoutChanged then
        EbonBuilds.BuildOverview.OnBuildListLayoutChanged()
    end
end

function EbonBuilds.MainWindow.CollapseBuildList()
    EbonBuilds.MainWindow.SetBuildListCollapsed(true)
end

function EbonBuilds.MainWindow.ExpandBuildList()
    EbonBuilds.MainWindow.SetBuildListCollapsed(false)
end

function EbonBuilds.MainWindow.ShowBuildPicker()
    EbonBuilds.MainWindow.SetBuildListCollapsed(false)
    EbonBuilds.ViewRouter.Show("buildOverview", { keepBuildListExpanded = true })
end

function EbonBuilds.MainWindow.ShowMyBuildView()
    local active = EbonBuilds.Build.GetActive()
    if active then
        ApplyThemeClass({ build = active })
        EbonBuilds.ViewRouter.Show("buildOverview", { build = active })
        return
    end

    local builds = EbonBuilds.Build.List()
    if builds and #builds > 0 then
        ApplyThemeClass(nil)
        EbonBuilds.MainWindow.ShowBuildPicker()
        return
    end

    ApplyThemeClass(nil)
    EbonBuilds.ViewRouter.Show("welcome")
end

------------------------------------------------------------------------
-- Global settings popup
------------------------------------------------------------------------

function EbonBuilds.MainWindow.ApplyWindowOpacity(opacity)
    if opacity == nil then
        local gs = EbonBuildsDB and EbonBuildsDB.globalSettings
        opacity = gs and gs.windowOpacity or 1
    end
    if frame then
        frame:SetAlpha(1)
    end
    if SW.SetWindowOpacity then
        SW.SetWindowOpacity(opacity)
    end
end

local function BuildSettingsPopup()
    local popup = CreateFrame("Frame", "EbonBuildsGlobalSettingsPopup", UIParent)
    popup:SetSize(340, 270)
    popup:SetPoint("CENTER", UIParent, "CENTER")
    popup:SetFrameStrata("DIALOG")
    popup:SetToplevel(true)
    popup:SetMovable(true)
    popup:EnableMouse(true)
    SW.Fill(popup, "bgElevated")
    SW.ThinBorder(popup, "border", 1)
    popup:Hide()

    local title = SW.Label(popup, "EbonBuilds Settings", 14, ST.C.text, false, "semibold")
    title:SetPoint("TOP", popup, "TOP", 0, -16)

    local drag = CreateFrame("Frame", nil, popup)
    drag:SetPoint("TOPLEFT",  popup, "TOPLEFT",  0,   0)
    drag:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -40, 0)
    drag:SetHeight(30)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() popup:StartMoving() end)
    drag:SetScript("OnDragStop",  function() popup:StopMovingOrSizing() end)

    local savedOpacity = 1

    local function CloseSettingsPopup()
        EbonBuilds.MainWindow.ApplyWindowOpacity(savedOpacity)
        popup:Hide()
    end

    local closeBtn = SW.CreateNavIconButton(popup, "close", CloseSettingsPopup, { size = 28 })
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -8, -8)
    closeBtn:SetFrameLevel(popup:GetFrameLevel() + 4)

    local function AddSlider(labelText, yAnchor, yOffset, value, minVal, maxVal, step, formatFn, onChange)
        minVal = minVal or 0.1
        maxVal = maxVal or 3.0
        step = step or 0.1
        formatFn = formatFn or function(v) return string.format("%.1fs", v) end

        local label = SW.Label(popup, labelText, 12, ST.C.text)
        label:SetPoint("TOPLEFT", yAnchor, "BOTTOMLEFT", 0, yOffset)

        local slider = CreateFrame("Slider", nil, popup)
        slider:SetOrientation("HORIZONTAL")
        slider:SetWidth(190)
        slider:SetHeight(20)
        slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        slider:SetMinMaxValues(minVal, maxVal)
        slider:SetValueStep(step)
        slider:SetValue(value)
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetTexture(ST.FLAT)
        track:SetVertexColor(0.25, 0.25, 0.25, 1)
        track:SetHeight(6)
        track:SetPoint("CENTER", slider)
        track:SetPoint("LEFT", slider)
        track:SetPoint("RIGHT", slider)

        local valText = SW.Label(popup, "", 11, ST.C.textDim)
        valText:SetPoint("LEFT", slider, "RIGHT", 6, 0)

        local function RefreshLabel(fromUser)
            local v = slider:GetValue()
            label:SetText(string.format("%s %s", labelText, formatFn(v)))
            valText:SetText(formatFn(v))
            if fromUser and onChange then onChange(v) end
        end

        slider:SetScript("OnValueChanged", function() RefreshLabel(true) end)
        RefreshLabel(false)

        return slider
    end

    local delayLabel = SW.Label(popup, "Action delay:", 12, ST.C.text)
    delayLabel:SetPoint("TOPLEFT", popup, "TOPLEFT", 24, -44)

    local delayFlavor = SW.Label(popup, "Very low values may cause the addon to malfunction.", 10, ST.C.textMuted)
    delayFlavor:SetPoint("TOPLEFT", delayLabel, "BOTTOMLEFT", 0, -2)
    delayFlavor:SetPoint("RIGHT", popup, "RIGHT", -24, 0)
    delayFlavor:SetJustifyH("LEFT")

    local delaySlider = CreateFrame("Slider", nil, popup)
    delaySlider:SetOrientation("HORIZONTAL")
    delaySlider:SetWidth(190)
    delaySlider:SetHeight(20)
    delaySlider:SetPoint("TOPLEFT", delayFlavor, "BOTTOMLEFT", 0, -4)
    delaySlider:SetMinMaxValues(0.1, 3.0)
    delaySlider:SetValueStep(0.1)
    delaySlider:SetValue(2)
    delaySlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

    local delayTrack = delaySlider:CreateTexture(nil, "BACKGROUND")
    delayTrack:SetTexture(ST.FLAT)
    delayTrack:SetVertexColor(0.25, 0.25, 0.25, 1)
    delayTrack:SetHeight(6)
    delayTrack:SetPoint("CENTER", delaySlider)
    delayTrack:SetPoint("LEFT", delaySlider)
    delayTrack:SetPoint("RIGHT", delaySlider)

    local delayValText = SW.Label(popup, "", 11, ST.C.textDim)
    delayValText:SetPoint("LEFT", delaySlider, "RIGHT", 6, 0)

    delaySlider:SetScript("OnValueChanged", function()
        local v = delaySlider:GetValue()
        delayValText:SetText(string.format("%.1fs", v))
    end)
    delaySlider:GetScript("OnValueChanged")()

    local toastSlider = AddSlider("Toast duration:", delaySlider, -14, 3)

    local opacitySlider = AddSlider(
        "Window opacity:",
        toastSlider,
        -14,
        1,
        0.5,
        1.0,
        0.05,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
        function(v)
            EbonBuilds.MainWindow.ApplyWindowOpacity(v)
        end
    )

    local saveBtn = SW.CreateAccentButton(popup, "Save", function()
        local gs = EbonBuildsDB.globalSettings
        gs.evalDelay = delaySlider:GetValue()
        gs.toastDuration = toastSlider:GetValue()
        gs.windowOpacity = opacitySlider:GetValue()
        popup:Hide()
    end)
    saveBtn:SetSize(80, 28)
    saveBtn:SetPoint("BOTTOM", popup, "BOTTOM", 43, 18)

    local cancelBtn = SW.CreateOutlineButton(popup, "Cancel", 80)
    cancelBtn:SetPoint("BOTTOM", popup, "BOTTOM", -43, 18)
    cancelBtn:SetScript("OnClick", CloseSettingsPopup)

    popup:SetScript("OnShow", function()
        local gs = EbonBuildsDB.globalSettings
        delaySlider:SetValue(gs.evalDelay or 2)
        toastSlider:SetValue(gs.toastDuration or 3)
        savedOpacity = gs.windowOpacity or 1
        opacitySlider:SetValue(savedOpacity)
    end)

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "EbonBuildsGlobalSettingsPopup")
    end

    return popup
end

local function BuildFrame()
    local f
    f = SW.CreateSiteWindow({
        name     = FRAME_NAME,
        width    = L.WIN_W,
        height   = L.WIN_H,
        closable = false,
        onClose  = function()
            f:Hide()
            if EbonBuilds.MainNav and EbonBuilds.MainNav.Hide then
                EbonBuilds.MainNav.Hide()
            end
            if f._settingsPopup and f._settingsPopup:IsShown() then
                f._settingsPopup:Hide()
            end
            if EbonBuilds.SessionHistory and EbonBuilds.SessionHistory.HideCopyDialog then
                EbonBuilds.SessionHistory.HideCopyDialog()
            end
        end,
    })

    local body = f.body

    bodyRow = CreateFrame("Frame", nil, body)
    bodyRow:SetAllPoints(body)

    leftPanel = CreateFrame("Frame", nil, bodyRow)
    leftPanel:SetPoint("TOPLEFT", bodyRow, "TOPLEFT", 0, 0)
    leftPanel:SetPoint("BOTTOMLEFT", bodyRow, "BOTTOMLEFT", 0, 0)
    leftPanel:SetWidth(LEFT_WIDTH)
    SW.FillChrome(leftPanel, "sidebarBg")

    divider = bodyRow:CreateTexture(nil, "ARTWORK")
    divider:SetTexture(ST.FLAT)
    divider:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 8, 0)
    divider:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMRIGHT", 8, 0)
    divider:SetWidth(1)
    ST.OnThemeChanged(function()
        if divider then divider:SetVertexColor(unpack(ST.C.border)) end
    end)
    divider:SetVertexColor(unpack(ST.C.border))

    rightPanel = CreateFrame("Frame", nil, bodyRow)
    rightPanel:SetPoint("TOPLEFT", divider, "TOPRIGHT", 8, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", bodyRow, "BOTTOMRIGHT", 0, 0)

    local rightContent = CreateFrame("Frame", nil, rightPanel)
    rightContent:SetAllPoints(rightPanel)

    f._left = leftPanel
    f._right = rightPanel
    f._rightContent = rightContent
    f._divider = divider
    f._bodyRow = bodyRow

    f._settingsPopup = BuildSettingsPopup()

    if EbonBuilds.MainNav and EbonBuilds.MainNav.Create then
        EbonBuilds.MainNav.Create(f, {
            onClose = function()
                f:Hide()
                if EbonBuilds.MainNav and EbonBuilds.MainNav.Hide then
                    EbonBuilds.MainNav.Hide()
                end
                if f._settingsPopup and f._settingsPopup:IsShown() then
                    f._settingsPopup:Hide()
                end
                if EbonBuilds.SessionHistory and EbonBuilds.SessionHistory.HideCopyDialog then
                    EbonBuilds.SessionHistory.HideCopyDialog()
                end
            end,
            onSettings = function()
                local popup = f._settingsPopup
                if popup then
                    if popup:IsShown() then popup:Hide() else popup:Show() end
                end
            end,
        })
    end

    f:Hide()
    f:SetScript("OnHide", function()
        if EbonBuilds.MainNav and EbonBuilds.MainNav.Hide then
            EbonBuilds.MainNav.Hide()
        end
        if EbonBuilds.SessionHistory and EbonBuilds.SessionHistory.HideCopyDialog then
            EbonBuilds.SessionHistory.HideCopyDialog()
        end
    end)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, FRAME_NAME)
    end

    EbonBuilds.ViewRouter.OnChanged(function(viewName, context)
        ApplyThemeClass(context)
        local navId = NAV_VIEW_MAP[viewName]
        if navId and EbonBuilds.MainNav and EbonBuilds.MainNav.SetActiveId then
            EbonBuilds.MainNav.SetActiveId(navId)
        end
        if (viewName == "buildOverview" or viewName == "buildTabs")
            and not (context and context.keepBuildListExpanded) then
            buildListCollapsed = true
        end
        ApplyBodyLayout(viewName)
        if viewName == "buildOverview"
            and EbonBuilds.BuildOverview
            and EbonBuilds.BuildOverview.OnBuildListLayoutChanged then
            EbonBuilds.BuildOverview.OnBuildListLayoutChanged()
        end
    end)

    return f
end

function EbonBuilds.MainWindow.Init()
    frame = BuildFrame()

    EbonBuilds.MainWindow._frame = frame
    EbonBuilds.MainWindow._left  = frame._left
    EbonBuilds.MainWindow._right = frame._right

    EbonBuilds.MainWindow.ApplyWindowOpacity()

    EbonBuilds.ViewRouter.SetContainer(frame._rightContent)
    EbonBuilds.BuildList.Init(frame._left)
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
    EbonBuilds.MainWindow.ShowMyBuildView()
end

SLASH_EbonBuilds1 = "/ebb"
SLASH_EbonBuilds2 = "/ebonbuilds"
SlashCmdList["EbonBuilds"] = function()
    EbonBuilds.MainWindow.Toggle()
end

function EbonBuilds.MainWindow.Toggle()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
        if EbonBuilds.MainNav and EbonBuilds.MainNav.Hide then
            EbonBuilds.MainNav.Hide()
        end
    else
        EbonBuilds.MainWindow._ShowInitialView()
        frame:Show()
        if EbonBuilds.MainNav and EbonBuilds.MainNav.Show then
            EbonBuilds.MainNav.Show()
        end
    end
end

function EbonBuilds.MainWindow.Show()
    if not frame then return end
    EbonBuilds.MainWindow._ShowInitialView()
    frame:Show()
    if EbonBuilds.MainNav and EbonBuilds.MainNav.Show then
        EbonBuilds.MainNav.Show()
    end
end

function EbonBuilds.MainWindow.GetRightPanel()
    return EbonBuilds.MainWindow._right
end

function EbonBuilds.MainWindow.IsVisible()
    return frame and frame:IsVisible()
end
