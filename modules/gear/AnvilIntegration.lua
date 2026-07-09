-- EbonBuilds: modules/gear/AnvilIntegration.lua
-- Adds Apply from Build to the Enchanted Anvil UI (ProjectEbonhold ExtractionUI).

EbonBuilds.AnvilIntegration = {}

local applyBtn
local actionStrip
local hookedFrame
local toggleHooked = false
local eventFrame
local EnsureAnvilButton

local STRIP_HEIGHT = 24
local GAP_BELOW_TITLE = 6

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
    if ExtractionUI and ExtractionUI.IsOpen and ExtractionUI.IsOpen() then
        return true
    end
    local frame = GetAnvilFrame()
    return frame and frame.IsShown and frame:IsShown()
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

local function IsNativeAnvilReady()
    if ExtractionUI and ExtractionUI._actionsLoaded then
        return true
    end
    return _G.EbonholdExtractionExtractBtn ~= nil and _G.EbonholdExtractionApplyBtn ~= nil
end

local function GetAnvilTitleAnchor(frame)
    if not frame then return nil end
    for _, key in ipairs({ "title", "Title", "titleText", "TitleText", "header" }) do
        local region = frame[key]
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            return region
        end
    end
    return nil
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
    if not frame or not actionStrip or not applyBtn then return end

    local titleAnchor = GetAnvilTitleAnchor(frame)
    actionStrip:ClearAllPoints()
    if titleAnchor then
        actionStrip:SetPoint("TOP", titleAnchor, "BOTTOM", 0, -GAP_BELOW_TITLE)
    else
        actionStrip:SetPoint("TOP", frame, "TOP", 0, -34)
    end
    actionStrip:SetWidth(132)
    actionStrip:SetHeight(STRIP_HEIGHT)

    applyBtn:ClearAllPoints()
    applyBtn:SetSize(130, 20)
    applyBtn:SetPoint("CENTER", actionStrip, "CENTER", 0, 0)
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

function EbonBuilds.AnvilIntegration.RefreshButton()
    EnsureAnvilButton()
    RefreshAnvilApplyButton()
end

local function HookFrameShowHide(frame)
    if hookedFrame == frame then return end
    hookedFrame = frame

    local priorShow = frame:GetScript("OnShow")
    frame:SetScript("OnShow", function(self, ...)
        EnsureAnvilButton()
        LayoutAnvilButton(self)
        RefreshAnvilApplyButton()
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

local function CreateActionStrip(frame)
    if frame._ebonBuildsActionStrip then
        actionStrip = frame._ebonBuildsActionStrip
        applyBtn = frame._ebonBuildsApplyBtn
        return
    end

    if frame._ebonBuildsApplyBtn then
        frame._ebonBuildsApplyBtn:Hide()
        frame._ebonBuildsApplyBtn = nil
    end

    local strip = CreateFrame("Frame", nil, frame)
    strip:SetFrameStrata(frame:GetFrameStrata() or "DIALOG")
    strip:SetFrameLevel((frame:GetFrameLevel() or 100) + 40)

    local btn = CreateFrame("Button", "EbonBuildsAnvilApplyBtn", strip, "UIPanelButtonTemplate")
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

    frame._ebonBuildsActionStrip = strip
    frame._ebonBuildsApplyBtn = btn
    actionStrip = strip
    applyBtn = btn
end

EnsureAnvilButton = function()
    local frame = GetAnvilFrame()
    if not frame then return false end

    RegisterBagDeferral(frame)
    ResetLegacyFrameHeight(frame)
    CreateActionStrip(frame)
    LayoutAnvilButton(frame)
    HookFrameShowHide(frame)
    applyBtn:Show()
    actionStrip:Show()
    RefreshAnvilApplyButton()
    return true
end

local function HookExtractionToggle()
    if toggleHooked or not ExtractionUI or not ExtractionUI.Toggle then return end
    toggleHooked = true
    if hooksecurefunc then
        hooksecurefunc(ExtractionUI, "Toggle", function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.05, function()
                    EnsureAnvilButton()
                    local frame = GetAnvilFrame()
                    if frame then LayoutAnvilButton(frame) end
                    RefreshAnvilApplyButton()
                end)
            else
                EnsureAnvilButton()
                RefreshAnvilApplyButton()
            end
        end)
    else
        local origToggle = ExtractionUI.Toggle
        ExtractionUI.Toggle = function(...)
            origToggle(...)
            EnsureAnvilButton()
            RefreshAnvilApplyButton()
        end
    end
end

local function OnAnvilMaybeOpened()
    local frame = GetAnvilFrame()
    if frame and frame:IsShown() then
        EnsureAnvilButton()
        LayoutAnvilButton(frame)
        RefreshAnvilApplyButton()
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
    EnsureAnvilButton()

    local waiter = CreateFrame("Frame")
    local elapsed = 0
    waiter:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if GetAnvilFrame() and EnsureAnvilButton() then
            self:SetScript("OnUpdate", nil)
            return
        end
        if elapsed >= 120 then
            self:SetScript("OnUpdate", nil)
        end
    end)
end
