-- EbonBuilds: modules/gear/AnvilIntegration.lua
-- Adds Apply from Build to the Enchanted Anvil UI (ProjectEbonhold ExtractionUI).

EbonBuilds.AnvilIntegration = {}

local applyBtn
local actionStrip
local hookedFrame
local toggleHooked = false
local eventFrame
local EnsureAnvilButton

local STRIP_HEIGHT = 28
local GAP_ABOVE_PE = 2
local GAP_ABOVE_HINT = 1

local anvilWantsVisible = false

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

local function GetPeButtonSpan()
    local peExtract = _G.EbonholdExtractionExtractBtn
    local peApply = _G.EbonholdExtractionApplyBtn
    if peExtract and peApply and peExtract.IsShown and peApply.IsShown
        and peExtract:IsShown() and peApply:IsShown() then
        return peExtract, peApply
    end
    return nil, nil
end

local function IsCharacterPanelOpen()
    return CharacterFrame and CharacterFrame.IsShown and CharacterFrame:IsShown()
end

local function SaveAnvilFrameStrata(frame)
    if frame and not frame._ebonBuildsSavedStrata then
        frame._ebonBuildsSavedStrata = frame:GetFrameStrata()
        frame._ebonBuildsSavedLevel = frame:GetFrameLevel()
    end
end

local function RestoreAnvilFrameVisibility(frame)
    frame = frame or GetAnvilFrame()
    if not frame or not frame.IsShown or not frame:IsShown() then
        return
    end

    if frame._ebonBuildsSavedStrata then
        frame:SetFrameStrata(frame._ebonBuildsSavedStrata)
        frame:SetFrameLevel(frame._ebonBuildsSavedLevel or 100)
    else
        frame:SetFrameStrata("DIALOG")
        frame:SetFrameLevel(100)
    end

    if frame.Raise then
        frame:Raise()
    end
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

local function MarkAnvilClosedByUser()
    anvilWantsVisible = false
end

local function FindCloseButton(frame)
    if not frame then return nil end
    local closeBtn = frame.closeButton
    if closeBtn and closeBtn.GetObjectType and closeBtn:GetObjectType() == "Button" then
        return closeBtn
    end
    return _G.EbonholdExtractionFrameClose
end

local function BindCloseButton(frame)
    local closeBtn = FindCloseButton(frame)
    if not closeBtn or closeBtn._ebonBuildsCloseBound then
        return
    end
    closeBtn._ebonBuildsCloseBound = true
    if closeBtn.HookScript then
        closeBtn:HookScript("OnClick", MarkAnvilClosedByUser)
    end
end

local function LayoutAnvilButton(frame)
    if not frame or not actionStrip or not applyBtn then return end

    local leftBtn, rightBtn = GetPeButtonSpan()
    actionStrip:ClearAllPoints()
    if leftBtn and rightBtn then
        actionStrip:SetPoint("BOTTOMLEFT", leftBtn, "TOPLEFT", 0, GAP_ABOVE_PE)
        actionStrip:SetPoint("BOTTOMRIGHT", rightBtn, "TOPRIGHT", 0, GAP_ABOVE_PE)
        actionStrip:SetHeight(STRIP_HEIGHT)
    else
        local title = GetAnvilTitleAnchor(frame)
        local hint = frame.hintText or frame.statusText
        actionStrip:SetWidth(132)
        actionStrip:SetHeight(STRIP_HEIGHT)
        if hint and hint.IsShown and hint:IsShown() then
            actionStrip:SetPoint("BOTTOM", hint, "TOP", 0, GAP_ABOVE_HINT)
        elseif title then
            actionStrip:SetPoint("TOP", title, "BOTTOM", 0, -12)
        elseif frame.bottomBar then
            actionStrip:SetPoint("BOTTOMLEFT", frame.bottomBar, "TOPLEFT", 0, GAP_ABOVE_PE)
            actionStrip:SetPoint("BOTTOMRIGHT", frame.bottomBar, "TOPRIGHT", 0, GAP_ABOVE_PE)
        else
            actionStrip:SetPoint("BOTTOM", frame, "BOTTOM", 0, 44)
            actionStrip:SetWidth(288)
        end
    end

    actionStrip:Show()
    applyBtn:Show()
end

local function ScheduleLayoutRetries(frame)
    if not frame or not C_Timer or not C_Timer.After then return end
    for _, delay in ipairs({ 0.05, 0.15, 0.35, 0.75 }) do
        C_Timer.After(delay, function()
            if frame:IsShown() then
                LayoutAnvilButton(frame)
            end
        end)
    end
end

local function RefreshAnvilApplyButton()
    if not applyBtn then return end
    applyBtn._hint = nil

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

local function RestoreAnvilForCharacterPanel()
    if not anvilWantsVisible or not IsCharacterPanelOpen() then
        return
    end
    local frame = GetAnvilFrame()
    if not frame then return end
    if not frame:IsShown() then
        frame:Show()
    end
    RestoreAnvilFrameVisibility(frame)
    LayoutAnvilButton(frame)
    RefreshAnvilApplyButton()
end

local function HookCharacterPanel()
    if not CharacterFrame or not CharacterFrame.HookScript
        or CharacterFrame._ebonBuildsAnvilHooked then
        return
    end
    CharacterFrame._ebonBuildsAnvilHooked = true
    CharacterFrame:HookScript("OnShow", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, RestoreAnvilForCharacterPanel)
        else
            RestoreAnvilForCharacterPanel()
        end
    end)
end

function EbonBuilds.AnvilIntegration.RefreshButton()
    local frame = GetAnvilFrame()
    if frame then
        LayoutAnvilButton(frame)
    end
    RefreshAnvilApplyButton()
end

local function HookFrameShowHide(frame)
    if hookedFrame == frame then return end
    hookedFrame = frame

    if not frame.HookScript then return end

    frame:HookScript("OnShow", function(self)
        anvilWantsVisible = true
        SaveAnvilFrameStrata(self)
        RegisterBagDeferral(self)
        BindCloseButton(self)
        EnsureAnvilButton()
        LayoutAnvilButton(self)
        ScheduleLayoutRetries(self)
        RefreshAnvilApplyButton()
    end)

    frame:HookScript("OnHide", function(self)
        if EbonBuilds.AffixView and EbonBuilds.AffixView.HidePopups then
            EbonBuilds.AffixView.HidePopups()
        end
        if not IsCharacterPanelOpen() then
            MarkAnvilClosedByUser()
        end
    end)
end

local function CreateActionStrip(frame)
    if frame._ebonBuildsActionStrip then
        actionStrip = frame._ebonBuildsActionStrip
        applyBtn = frame._ebonBuildsApplyBtn
        return
    end

    if frame._ebonBuildsApplyBtn and not frame._ebonBuildsActionStrip then
        frame._ebonBuildsApplyBtn:Hide()
        frame._ebonBuildsApplyBtn = nil
    end

    local strip = CreateFrame("Frame", nil, frame)
    strip:SetFrameStrata(frame:GetFrameStrata() or "DIALOG")
    strip:SetFrameLevel((frame:GetFrameLevel() or 1) + 8)

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
    RegisterBagDeferral(frame)
    BindCloseButton(frame)
    HookFrameShowHide(frame)
    LayoutAnvilButton(frame)
    RefreshAnvilApplyButton()
    return true
end

local function OnAnvilOpened()
    local frame = GetAnvilFrame()
    if frame and frame:IsShown() then
        EnsureAnvilButton()
        LayoutAnvilButton(frame)
        ScheduleLayoutRetries(frame)
        RefreshAnvilApplyButton()
    end
end

local function HookExtractionToggle()
    if toggleHooked or not ExtractionUI or not ExtractionUI.Toggle then return end
    toggleHooked = true

    local origToggle = ExtractionUI.Toggle
    ExtractionUI.Toggle = function(...)
        local frame = GetAnvilFrame()
        local wasOpen = frame and frame.IsShown and frame:IsShown()
        local result = origToggle(...)
        if wasOpen and frame and frame.IsShown and not frame:IsShown()
            and not IsCharacterPanelOpen() then
            MarkAnvilClosedByUser()
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, OnAnvilOpened)
        else
            OnAnvilOpened()
        end
        return result
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
                        C_Timer.After(0.05, OnAnvilOpened)
                    else
                        OnAnvilOpened()
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
    HookCharacterPanel()
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
