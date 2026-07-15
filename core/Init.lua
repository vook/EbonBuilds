-- EbonBuilds: core/Init.lua
-- Responsibility: addon bootstrap, saved-variable initialisation, module wiring.

EbonBuilds = EbonBuilds or {}

function EbonBuilds.OpenEchoJournal()
    local function IsLikelyEchoFrame(frame)
        if not frame then return false end
        local name = frame.GetName and frame:GetName() or ""
        if type(name) ~= "string" then return false end
        local lower = string.lower(name)
        return lower:find("projectebonhold", 1, true)
            or lower:find("perk", 1, true)
            or lower:find("echo", 1, true)
    end

    local function RaiseFrame(frame)
        if not frame or not frame.Show then return false end
        frame:Show()
        if frame.SetFrameStrata then frame:SetFrameStrata("FULLSCREEN_DIALOG") end
        if frame.SetToplevel then frame:SetToplevel(true) end
        if frame.Raise then frame:Raise() end
        if ShowUIPanel then pcall(ShowUIPanel, frame) end
        return true
    end

    local function FindRuntimeEchoFrame()
        if not UIParent or not UIParent.GetChildren then return nil end
        local children = { UIParent:GetChildren() }
        for i = #children, 1, -1 do
            local frame = children[i]
            if frame and frame.IsShown and frame:IsShown() and IsLikelyEchoFrame(frame) then
                return frame
            end
        end
        return nil
    end

    local function FocusEchoJournalFrame()
        local perkUI = ProjectEbonhold and ProjectEbonhold.PerkUI
        local candidates = {
            perkUI and perkUI.frame,
            perkUI and perkUI.Frame,
            perkUI and perkUI.window,
            perkUI and perkUI.Window,
            perkUI and perkUI.root,
            perkUI and perkUI.Root,
            _G.ProjectEbonholdPerkUIFrame,
            _G.ProjectEbonholdEchoesFrame,
            _G.ProjectEbonholdMyEchoesFrame,
            _G.ProjectEbonholdEchoJournalFrame,
            _G.PerkUIFrame,
            _G.EchoJournalFrame,
            _G.EchoesFrame,
        }

        for i = 1, #candidates do
            local frame = candidates[i]
            if RaiseFrame(frame) then return true end
        end

        local runtimeFrame = FindRuntimeEchoFrame()
        if RaiseFrame(runtimeFrame) then return true end
        return false
    end

    local msg = "/echoes"
    if ChatFrame_OpenChat then
        ChatFrame_OpenChat(msg)
    end
    local editBox = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox
    if editBox and ChatEdit_SendText then
        editBox:SetText(msg)
        ChatEdit_SendText(editBox)
    end

    -- /echoes can create/show its frame asynchronously.
    if not FocusEchoJournalFrame() and C_Timer and C_Timer.After then
        C_Timer.After(0, FocusEchoJournalFrame)
        C_Timer.After(0.05, FocusEchoJournalFrame)
        C_Timer.After(0.15, FocusEchoJournalFrame)
        C_Timer.After(0.35, FocusEchoJournalFrame)
    end
end

local PE_ADDONS = {
    ProjectEbonhold = true,
    ProjectEbonholdEnhanced = true,
}

local initialized = false
local unavailableMessageShown = false

local function PrintUnavailableMessage()
    if unavailableMessageShown then return end
    unavailableMessageShown = true
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffB048F8[EbonBuilds]|r Project Ebonhold is not available. "
                .. "Enable the server addon or Project Ebonhold Enhanced to use /ebb.",
            1, 0.82, 0
        )
    end
end

local function TryInit()
    if initialized then return true end
    if not ProjectEbonhold then return false end

    initialized = true

    EbonBuildsDB = EbonBuildsDB or {
        builds        = {},
        minimapAngle  = 220,
        globalSettings = {
            evalDelay     = 2,
            toastDuration = 3,
        },
    }
    EbonBuildsDB.minimapAngle = EbonBuildsDB.minimapAngle or 220
    EbonBuildsDB.globalSettings = EbonBuildsDB.globalSettings or {}
    EbonBuildsDB.globalSettings.evalDelay     = EbonBuildsDB.globalSettings.evalDelay     or 2
    EbonBuildsDB.globalSettings.toastDuration = EbonBuildsDB.globalSettings.toastDuration or 3

    EbonBuildsCharDB = EbonBuildsCharDB or {
        activeBuildId = nil,
    }

    EbonBuilds.Build.Migrate()
    EbonBuilds.Session.Init()
    EbonBuilds.SessionHistory.Init()
    EbonBuilds.Weights.Init()
    EbonBuilds.Toast.Init()
    EbonBuilds.WelcomeView.Init()
    EbonBuilds.BonusView.Init()
    EbonBuilds.AffixApply.Init()
    EbonBuilds.AffixScan.Init()
    EbonBuilds.AffixView.Init()
    if EbonBuilds.AnvilIntegration and EbonBuilds.AnvilIntegration.Init then
        EbonBuilds.AnvilIntegration.Init()
    end
    EbonBuilds.BuildWizard.Init()
    EbonBuilds.MinimapButton.Init()
    EbonBuilds.MainWindow.Init()
    EbonBuilds.Automation.Init()
    EbonBuilds.Sync.Init()
    if EbonBuilds.EchoOwnership and EbonBuilds.EchoOwnership.Init then
        EbonBuilds.EchoOwnership.Init()
    end
    if EbonBuilds.EchoSearch and EbonBuilds.EchoSearch.StartPrewarm then
        C_Timer.After(1, EbonBuilds.EchoSearch.StartPrewarm)
    end

    return true
end

function EbonBuilds.EnsureInitialized()
    return TryInit()
end

function EbonBuilds.OpenMainWindow()
    if not TryInit() then return false end
    if EbonBuilds.MainWindow and EbonBuilds.MainWindow.Toggle then
        EbonBuilds.MainWindow.Toggle()
        return true
    end
    return false
end

local function ScheduleUnavailableCheck()
    if not (C_Timer and C_Timer.After) then return end
    C_Timer.After(2, function()
        if not TryInit() then
            PrintUnavailableMessage()
        end
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName == "EbonBuilds" or PE_ADDONS[addonName] then
            TryInit()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        TryInit()
        ScheduleUnavailableCheck()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        TryInit()
    end
end)

SLASH_EbonBuilds1 = "/ebb"
SLASH_EbonBuilds2 = "/ebonbuilds"
SlashCmdList["EbonBuilds"] = function()
    EbonBuilds.OpenMainWindow()
end
