-- EbonBuilds: modules/gear/AnvilIntegration.lua
-- Adds Apply from Build to the Enchanted Anvil UI (ProjectEbonhold ExtractionUI).

EbonBuilds.AnvilIntegration = {}

local applyBtn
local actionStrip
local hookedFrame
local toggleHooked = false
local eventFrame
local EnsureAnvilButton

local STRIP_HEIGHT = 30
local GAP_ABOVE_PE = 10

local function GetAnvilFrame()
    if _G.EbonholdExtractionFrame then
        return _G.EbonholdExtractionFrame
    end
    if ExtractionUI and ExtractionUI._frame then
        return ExtractionUI._frame
    end
    return nil
end

local function GetPeButtonSpan()
    local peApply = _G.EbonholdExtractionApplyBtn
    local peExtract = _G.EbonholdExtractionExtractBtn
    if peApply and peExtract then
        return peExtract, peApply
    end
    return nil, nil
end

local function LayoutAnvilButton(frame)
    if not frame or not actionStrip or not applyBtn then return end

    local leftBtn, rightBtn = GetPeButtonSpan()
    actionStrip:ClearAllPoints()
    if leftBtn and rightBtn then
        actionStrip:SetPoint("BOTTOMLEFT", leftBtn, "TOPLEFT", 0, GAP_ABOVE_PE)
        actionStrip:SetPoint("BOTTOMRIGHT", rightBtn, "TOPRIGHT", 0, GAP_ABOVE_PE)
    elseif frame.bottomBar then
        actionStrip:SetPoint("BOTTOMLEFT", frame.bottomBar, "TOPLEFT", 0, GAP_ABOVE_PE)
        actionStrip:SetPoint("BOTTOMRIGHT", frame.bottomBar, "TOPRIGHT", 0, GAP_ABOVE_PE)
    else
        actionStrip:SetPoint("BOTTOM", frame, "BOTTOM", 0, 52)
        actionStrip:SetWidth(288)
    end
    actionStrip:SetHeight(STRIP_HEIGHT)
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
        local canRun, runHint = EbonBuilds.AffixApply.CanRun(build)
        if not canRun and runHint then
            applyBtn._hint = runHint
        else
            applyBtn._hint = "Build: " .. (build.title or "Untitled")
        end
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

    local divider = strip:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", strip, "TOPLEFT", 2, 0)
    divider:SetPoint("TOPRIGHT", strip, "TOPRIGHT", -2, 0)
    divider:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
    divider:SetVertexColor(0.55, 0.55, 0.55, 0.55)

    local btn = CreateFrame("Button", "EbonBuildsAnvilApplyBtn", strip, "UIPanelButtonTemplate")
    btn:SetHeight(22)
    btn:SetPoint("TOPLEFT", strip, "TOPLEFT", 0, -5)
    btn:SetPoint("TOPRIGHT", strip, "TOPRIGHT", 0, -5)
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
    local origToggle = ExtractionUI.Toggle
    ExtractionUI.Toggle = function(...)
        origToggle(...)
        EnsureAnvilButton()
        RefreshAnvilApplyButton()
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
        if EnsureAnvilButton() then
            self:SetScript("OnUpdate", nil)
            return
        end
        if elapsed >= 120 then
            self:SetScript("OnUpdate", nil)
        end
    end)
end
