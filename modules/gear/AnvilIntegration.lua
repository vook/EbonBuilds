-- EbonBuilds: modules/gear/AnvilIntegration.lua
-- Adds Apply from Build to the Enchanted Anvil UI (ProjectEbonhold ExtractionUI).

EbonBuilds.AnvilIntegration = {}

local applyBtn
local hookedFrame
local toggleHooked = false
local eventFrame
local refreshFrame
local EnsureAnvilButton

local GAP_BELOW_TITLE = 4

local function GetAnvilFrame()
    if _G.EbonholdExtractionFrame then
        return _G.EbonholdExtractionFrame
    end
    if ExtractionUI and ExtractionUI._frame then
        return ExtractionUI._frame
    end
    return nil
end

function EbonBuilds.AnvilIntegration.IsOpen()
    local frame = GetAnvilFrame()
    if frame and frame.IsShown and frame:IsShown() then
        return true
    end
    if ExtractionUI and ExtractionUI.IsOpen then
        return ExtractionUI.IsOpen()
    end
    return false
end

function EbonBuilds.AnvilIntegration.EnsureOpen()
    if EbonBuilds.AnvilIntegration.IsOpen() then
        return true
    end
    if ExtractionUI and ExtractionUI.Toggle then
        ExtractionUI.Toggle()
    end
    return EbonBuilds.AnvilIntegration.IsOpen()
end

local function VisitFontStrings(frame, visit, depth)
    if not frame or depth > 4 then return false end
    depth = depth or 0

    local numRegions = frame.GetNumRegions and frame:GetNumRegions() or 0
    for i = 1, numRegions do
        local region = select(i, frame:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            if visit(region) then return true end
        end
    end

    local numChildren = frame.GetNumChildren and frame:GetNumChildren() or 0
    for i = 1, numChildren do
        local child = select(i, frame:GetChildren())
        if child and VisitFontStrings(child, visit, depth + 1) then
            return true
        end
    end
    return false
end

local function FindAnvilTitle(frame)
    if not frame then return nil end

    for _, key in ipairs({ "title", "Title", "titleText", "TitleText", "header" }) do
        local region = frame[key]
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            return region
        end
    end

    local found
    VisitFontStrings(frame, function(region)
        local text = region.GetText and region:GetText()
        if text and text:find("Enchanted Anvil", 1, true) then
            found = region
            return true
        end
        return false
    end)
    return found
end

local function RegisterBagDeferral(frame)
    if not frame or frame._ebonBuildsBagDeferRegistered then
        return
    end
    local utils = ProjectEbonhold and ProjectEbonhold.utils
    if utils and utils.RegisterFrameBelowBagsWhenOpen then
        utils.RegisterFrameBelowBagsWhenOpen(frame)
        frame._ebonBuildsBagDeferRegistered = true
    end
end

local function ResetLegacyFrameHeight(frame)
    if frame and frame._ebonBuildsHeightExpanded and frame._ebonBuildsBaseHeight then
        frame:SetHeight(frame._ebonBuildsBaseHeight)
        frame._ebonBuildsHeightExpanded = nil
        frame._ebonBuildsBaseHeight = nil
    end
end

local function LayoutAnvilButton(frame)
    if not frame or not applyBtn then return end

    local titleAnchor = FindAnvilTitle(frame)
    applyBtn:ClearAllPoints()
    if titleAnchor then
        applyBtn:SetPoint("TOP", titleAnchor, "BOTTOM", 0, -GAP_BELOW_TITLE)
    else
        applyBtn:SetPoint("TOP", frame, "TOP", 0, -30)
    end
    applyBtn:SetSize(130, 20)
    applyBtn:SetFrameStrata(frame:GetFrameStrata() or "DIALOG")
    applyBtn:SetFrameLevel((frame:GetFrameLevel() or 1) + 30)
end

local function RefreshAnvilApplyButton()
    if not applyBtn then return end
    applyBtn._hint = nil
    applyBtn:Show()

    local build = EbonBuilds.Build.GetAffixSourceForCurrentClass()
    if not build then
        applyBtn:Disable()
        applyBtn._hint = "No build with scanned affixes for your class."
        return
    end

    if not EbonBuilds.AffixApply then
        applyBtn:Disable()
        return
    end

    local canPreview, hint = EbonBuilds.AffixApply.CanPreview(build)
    if canPreview then
        applyBtn:Enable()
        applyBtn._hint = "Build: " .. (build.title or "Untitled")
    else
        applyBtn:Disable()
        applyBtn._hint = hint or "Cannot apply affixes right now."
    end
end

local function RefreshAnvilUI(frame)
    frame = frame or GetAnvilFrame()
    if not frame or not frame:IsShown() then return end
    if not EnsureAnvilButton() then return end
    LayoutAnvilButton(frame)
    RefreshAnvilApplyButton()
end

function EbonBuilds.AnvilIntegration.RefreshButton()
    RefreshAnvilUI(GetAnvilFrame())
end

local function ScheduleAnvilRefresh(frame)
    if not frame or not C_Timer or not C_Timer.After then
        RefreshAnvilUI(frame)
        return
    end
    local delays = { 0, 0.05, 0.15, 0.35, 0.75, 1.5 }
    for _, delay in ipairs(delays) do
        C_Timer.After(delay, function()
            if frame.IsShown and frame:IsShown() then
                RefreshAnvilUI(frame)
            end
        end)
    end
end

local function HookFrameShowHide(frame)
    if hookedFrame == frame then return end
    hookedFrame = frame

    local priorShow = frame:GetScript("OnShow")
    frame:SetScript("OnShow", function(self, ...)
        ScheduleAnvilRefresh(self)
        if priorShow then priorShow(self, ...) end
    end)

    local priorHide = frame:GetScript("OnHide")
    frame:SetScript("OnHide", function(self, ...)
        if EbonBuilds.AffixView and EbonBuilds.AffixView.HidePopups then
            EbonBuilds.AffixView.HidePopups()
        end
        if priorHide then priorHide(self, ...) end
    end)
end

local function CreateApplyButton(frame)
    if frame._ebonBuildsApplyBtn then
        applyBtn = frame._ebonBuildsApplyBtn
        return
    end

    if frame._ebonBuildsActionStrip then
        frame._ebonBuildsActionStrip:Hide()
        frame._ebonBuildsActionStrip = nil
    end

    local btn = CreateFrame("Button", "EbonBuildsAnvilApplyBtn", frame, "UIPanelButtonTemplate")
    btn:SetText("Apply from Build")
    btn:SetScript("OnClick", function()
        local build = EbonBuilds.Build.GetAffixSourceForCurrentClass()
        if not build then
            if EbonBuilds.Toast then
                EbonBuilds.Toast.Show("No build with scanned affixes for your class.")
            end
            return
        end
        EbonBuilds.AffixView.StartApplyFlow(build)
    end)
    btn:SetScript("OnEnter", function(self)
        if self._hint then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self._hint, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame._ebonBuildsApplyBtn = btn
    applyBtn = btn
end

EnsureAnvilButton = function()
    local frame = GetAnvilFrame()
    if not frame then return false end

    RegisterBagDeferral(frame)
    ResetLegacyFrameHeight(frame)
    CreateApplyButton(frame)
    HookFrameShowHide(frame)
    LayoutAnvilButton(frame)
    applyBtn:Show()
    RefreshAnvilApplyButton()
    return true
end

local function StartRefreshPoll()
    if refreshFrame then return end
    refreshFrame = CreateFrame("Frame")
    local elapsed = 0
    refreshFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0

        local frame = GetAnvilFrame()
        if frame and frame:IsShown() then
            RefreshAnvilUI(frame)
        end
    end)
end

local function HookExtractionToggle()
    if toggleHooked or not ExtractionUI or not ExtractionUI.Toggle then return end
    toggleHooked = true
    if hooksecurefunc then
        hooksecurefunc(ExtractionUI, "Toggle", function()
            ScheduleAnvilRefresh(GetAnvilFrame())
        end)
    else
        local origToggle = ExtractionUI.Toggle
        ExtractionUI.Toggle = function(...)
            origToggle(...)
            ScheduleAnvilRefresh(GetAnvilFrame())
        end
    end
end

local function OnAnvilMaybeOpened()
    local frame = GetAnvilFrame()
    if frame and frame:IsShown() then
        ScheduleAnvilRefresh(frame)
    end
end

local function RegisterEventHooks()
    if eventFrame then return end
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GOSSIP_SHOW")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "GOSSIP_SHOW" then
            if GossipFrameNpcNameText then
                local npcName = GossipFrameNpcNameText:GetText()
                if npcName == "Enchanted Anvil" then
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0.05, OnAnvilMaybeOpened)
                    else
                        OnAnvilMaybeOpened()
                    end
                end
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            EnsureAnvilButton()
        end
    end)
end

function EbonBuilds.AnvilIntegration.Init()
    RegisterEventHooks()
    HookExtractionToggle()
    StartRefreshPoll()
    EnsureAnvilButton()

    local waiter = CreateFrame("Frame")
    local elapsed = 0
    waiter:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if GetAnvilFrame() then
            EnsureAnvilButton()
            if elapsed >= 1 then
                self:SetScript("OnUpdate", nil)
            end
            return
        end
        if elapsed >= 120 then
            self:SetScript("OnUpdate", nil)
        end
    end)
end
