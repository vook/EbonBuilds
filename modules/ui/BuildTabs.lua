-- EbonBuilds: modules/ui/BuildTabs.lua
-- Responsibility: tabbed build editor with site-styled underline tabs and footer.

EbonBuilds.BuildTabs = {}

local ST = EbonBuilds.SiteTheme
local SW = EbonBuilds.SiteWidgets
local C  = ST.C
local L  = ST.Layout

local viewFrame
local contentArea
local tabBarFrame
local tabState = { selectedIndex = 1, tabs = {} }
local saveBtn, cancelBtn, exportBtn, exportListBtn
local activeTab = 1
local state = { context = nil }

local function RefreshButtons()
    if exportListBtn and exportBtn then
        if activeTab == 2 then
            exportListBtn:Show()
            exportBtn:ClearAllPoints()
            exportBtn:SetPoint("BOTTOMLEFT", exportListBtn, "BOTTOMRIGHT", 8, 0)
        else
            exportListBtn:Hide()
            exportBtn:ClearAllPoints()
            exportBtn:SetPoint("BOTTOMLEFT", exportListBtn:GetParent(), "BOTTOMLEFT", L.PAD, 8)
        end
    end
end

function EbonBuilds.BuildTabs.OnBuildSaved()
    state.context = { mode = "edit", build = EbonBuilds.Build.GetActive() }
    RefreshButtons()
end

local function UnmountAllTabs()
    EbonBuilds.BuildForm.Unmount()
    EbonBuilds.WeightsView.Unmount()
    EbonBuilds.BonusView.Unmount()
    EbonBuilds.SettingsView.Unmount()
    EbonBuilds.AffixView.Unmount()
end

local function SelectTabVisual(index)
    activeTab = index
    tabState.selectedIndex = index
    SW.UpdateTabBar(tabState)
    RefreshButtons()
end

local function ShowOverview()
    SelectTabVisual(1)
    UnmountAllTabs()
    EbonBuilds.BuildForm.Mount(contentArea, state.context)
end

local function ShowEchoes()
    SelectTabVisual(2)
    UnmountAllTabs()
    EbonBuilds.WeightsView.Mount(contentArea)
end

local function ShowBonus()
    SelectTabVisual(3)
    UnmountAllTabs()
    EbonBuilds.BonusView.Mount(contentArea)
end

local function ShowAutomation()
    SelectTabVisual(4)
    UnmountAllTabs()
    EbonBuilds.SettingsView.Mount(contentArea)
end

tabState.SelectTab = function(index)
    if index == 1 then ShowOverview()
    elseif index == 2 then ShowEchoes()
    elseif index == 3 then ShowBonus()
    elseif index == 4 then ShowAutomation()
    end
end

local function CreateTabBar(parent)
    tabBarFrame = CreateFrame("Frame", nil, parent)
    tabBarFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    tabBarFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    tabBarFrame:SetHeight(40)
    SW.FillChrome(tabBarFrame, "tabBarBg")

    local sep = tabBarFrame:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(ST.FLAT)
    sep:SetVertexColor(unpack(C.border))
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", tabBarFrame, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", tabBarFrame, "BOTTOMRIGHT", 0, 0)

    local labels = { "Overview", "Echoes", "Bonus", "Automation" }
    tabState.tabs = {}
    local prev
    for i, label in ipairs(labels) do
        local btn = SW.CreateTabButton(tabBarFrame, label, i, tabState)
        btn:SetPoint("TOP", tabBarFrame, "TOP", 0, 0)
        if prev then
            btn:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else
            btn:SetPoint("LEFT", tabBarFrame, "LEFT", L.PAD, 0)
        end
        tabState.tabs[i] = btn
        prev = btn
    end
    SW.UpdateTabBar(tabState)
end

local function CreateContentArea(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT",     tabBarFrame, "BOTTOMLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", parent,      "BOTTOMRIGHT", 0, 44)
    SW.FillChrome(frame, "mainBg")
    SW.ThinBorder(frame, "borderSoft", 1)

    local inner = CreateFrame("Frame", nil, frame)
    inner:SetPoint("TOPLEFT",     frame, "TOPLEFT",     L.PAD, -L.PAD)
    inner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -L.PAD, L.PAD)
    return inner
end

local function BuildViewFrame()
    local f = CreateFrame("Frame", "EbonBuildsBuildTabs", UIParent)
    SW.FillChrome(f, "bg")

    CreateTabBar(f)
    contentArea = CreateContentArea(f)

    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(44)
    SW.FillChrome(footer, "tabBarBg")

    exportListBtn = SW.CreateOutlineButton(footer, "Export List", 100)
    exportListBtn:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", L.PAD, 8)
    exportListBtn:Hide()
    exportListBtn:SetScript("OnClick", function()
        local build = EbonBuilds.Build.GetActive()
        if not build and EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingBuild then
            build = EbonBuilds.BuildForm.GetEditingBuild()
        end
        if not build then
            if EbonBuilds.Toast then
                EbonBuilds.Toast.Show("No build selected.")
            end
            return
        end
        if EbonBuilds.Weights and EbonBuilds.Weights.ShowExportListDialog then
            EbonBuilds.Weights.ShowExportListDialog(build)
        elseif EbonBuilds.Toast then
            EbonBuilds.Toast.Show("Export is not available.")
        end
    end)

    exportBtn = SW.CreateOutlineButton(footer, "Export", 90)
    exportBtn:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", L.PAD, 8)
    exportBtn:SetScript("OnClick", function()
        local build = EbonBuilds.Build.GetActive()
        if build then
            EbonBuilds.ExportImport.ShowExportDialog(build)
        end
    end)

    cancelBtn = SW.CreateOutlineButton(footer, "Cancel", 90)
    cancelBtn:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", -(L.PAD + 96), 8)
    cancelBtn:SetScript("OnClick", function() EbonBuilds.BuildForm.Cancel() end)

    saveBtn = SW.CreateAccentButton(footer, "Save", function()
        EbonBuilds.BuildForm.Save()
    end)
    saveBtn:SetSize(90, 28)
    saveBtn:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", -L.PAD, 8)

    return f
end

function EbonBuilds.BuildTabs.EnableEchoesTab()
    -- All tabs always enabled in site-style bar.
end

local view = {}

function view.Show(container, context)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)

    state.context = context or { mode = "create" }

    UnmountAllTabs()
    EbonBuilds.BuildForm.Mount(contentArea, state.context)
    SelectTabVisual(1)
    viewFrame:Show()
end

function view.Hide()
    EbonBuildsDB._isEditingBuild = nil
    EbonBuildsDB.pendingWeights = nil
    EbonBuildsDB.pendingScannedAffixes = nil
    EbonBuildsDB._wizardPrefill = nil
    UnmountAllTabs()
    if viewFrame then viewFrame:Hide() end
end

function EbonBuilds.BuildTabs.Init()
    viewFrame = BuildViewFrame()
    viewFrame:Hide()
    EbonBuilds.ViewRouter.Register("buildTabs", view)
end
