-- EbonBuilds: modules/ui/BuildTabs.lua
-- Responsibility: tabbed container for a single build (Overview + Echoes +
-- Bonus + Automation). Registered as the "buildTabs" view. Delegates
-- content to BuildForm, WeightsView, BonusView and SettingsView via
-- their Mount/Unmount API.

EbonBuilds.BuildTabs = {}

local viewFrame
local contentArea
local tab1, tab2, tab3, tab4
local saveBtn, cancelBtn
local state = { context = nil }

------------------------------------------------------------------------
-- Tab switching
------------------------------------------------------------------------

local function RefreshButtons()
    -- cancel is always visible in both modes
end

function EbonBuilds.BuildTabs.OnBuildSaved()
    state.context = { mode = "edit", build = EbonBuilds.Build.GetActive() }
    RefreshButtons()
end

local function ShowOverview()
    PanelTemplates_SetTab(viewFrame, 1)
    EbonBuilds.WeightsView.Unmount()
    EbonBuilds.BonusView.Unmount()
    EbonBuilds.SettingsView.Unmount()
    EbonBuilds.BuildForm.Mount(contentArea, state.context)
end

local function ShowEchoes()
    PanelTemplates_SetTab(viewFrame, 2)
    EbonBuilds.BuildForm.Unmount()
    EbonBuilds.BonusView.Unmount()
    EbonBuilds.SettingsView.Unmount()
    EbonBuilds.WeightsView.Mount(contentArea)
end

local function ShowBonus()
    PanelTemplates_SetTab(viewFrame, 3)
    EbonBuilds.BuildForm.Unmount()
    EbonBuilds.WeightsView.Unmount()
    EbonBuilds.SettingsView.Unmount()
    EbonBuilds.BonusView.Mount(contentArea)
end

local function ShowAutomation()
    PanelTemplates_SetTab(viewFrame, 4)
    EbonBuilds.BuildForm.Unmount()
    EbonBuilds.WeightsView.Unmount()
    EbonBuilds.BonusView.Unmount()
    EbonBuilds.SettingsView.Mount(contentArea)
end

------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------

local function CreateTabs(parent)
    tab1 = CreateFrame("Button", "EbonBuildsBuildTabsTab1", parent, "OptionsFrameTabButtonTemplate")
    tab1:SetID(1)
    tab1:SetText("Overview")
    tab1:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, 0)
    PanelTemplates_TabResize(tab1, 0)
    tab1:SetScript("OnClick", ShowOverview)

    tab2 = CreateFrame("Button", "EbonBuildsBuildTabsTab2", parent, "OptionsFrameTabButtonTemplate")
    tab2:SetID(2)
    tab2:SetText("Echoes")
    tab2:SetPoint("LEFT", tab1, "RIGHT", -16, 0)
    PanelTemplates_TabResize(tab2, 0)
    tab2:SetScript("OnClick", ShowEchoes)

    tab3 = CreateFrame("Button", "EbonBuildsBuildTabsTab3", parent, "OptionsFrameTabButtonTemplate")
    tab3:SetID(3)
    tab3:SetText("Bonus")
    tab3:SetPoint("LEFT", tab2, "RIGHT", -16, 0)
    PanelTemplates_TabResize(tab3, 0)
    tab3:SetScript("OnClick", ShowBonus)

    tab4 = CreateFrame("Button", "EbonBuildsBuildTabsTab4", parent, "OptionsFrameTabButtonTemplate")
    tab4:SetID(4)
    tab4:SetText("Automation")
    tab4:SetPoint("LEFT", tab3, "RIGHT", -16, 0)
    PanelTemplates_TabResize(tab4, 0)
    tab4:SetScript("OnClick", ShowAutomation)
end

local function CreateContentArea(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT",     parent, "TOPLEFT",     0, -24)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 34)
    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true,
        tileSize = 16,
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.6)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    local inner = CreateFrame("Frame", nil, frame)
    inner:SetPoint("TOPLEFT",     frame, "TOPLEFT",     6, -6)
    inner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    return inner
end

local function BuildViewFrame()
    local f = CreateFrame("Frame", "EbonBuildsBuildTabs", UIParent)
    CreateTabs(f)
    contentArea = CreateContentArea(f)
    PanelTemplates_SetNumTabs(f, 4)
    PanelTemplates_SetTab(f, 1)

    saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveBtn:SetSize(90, 22)
    saveBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function() EbonBuilds.BuildForm.Save() end)

    cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancelBtn:SetSize(90, 22)
    cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -6, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() EbonBuilds.BuildForm.Cancel() end)

    local exportBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    exportBtn:SetSize(90, 22)
    exportBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        local build = EbonBuilds.Build.GetActive()
        if build then
            EbonBuilds.ExportImport.ShowExportDialog(build)
        end
    end)

    return f
end

------------------------------------------------------------------------
-- Public helper
------------------------------------------------------------------------

function EbonBuilds.BuildTabs.EnableEchoesTab()
    if viewFrame then PanelTemplates_EnableTab(viewFrame, 2) end
end

------------------------------------------------------------------------
-- View interface
------------------------------------------------------------------------

local view = {}

function view.Show(container, context)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)

    state.context = context or { mode = "create" }

    PanelTemplates_SetTab(viewFrame, 1)
    PanelTemplates_EnableTab(viewFrame, 2)
    PanelTemplates_EnableTab(viewFrame, 3)
    PanelTemplates_EnableTab(viewFrame, 4)

    EbonBuilds.WeightsView.Unmount()
    EbonBuilds.BonusView.Unmount()
    EbonBuilds.SettingsView.Unmount()
    EbonBuilds.BuildForm.Mount(contentArea, state.context)
    viewFrame:Show()
end

function view.Hide()
    EbonBuildsDB._isEditingBuild = nil
    EbonBuildsDB.pendingWeights = nil
    EbonBuilds.BuildForm.Unmount()
    EbonBuilds.WeightsView.Unmount()
    EbonBuilds.BonusView.Unmount()
    EbonBuilds.SettingsView.Unmount()
    if viewFrame then viewFrame:Hide() end
end

------------------------------------------------------------------------
-- Init
------------------------------------------------------------------------

function EbonBuilds.BuildTabs.Init()
    viewFrame = BuildViewFrame()
    viewFrame:Hide()
    EbonBuilds.ViewRouter.Register("buildTabs", view)
end
