-- EbonBuilds: core/Init.lua
-- Responsibility: addon bootstrap, saved-variable initialisation, module wiring.

EbonBuilds = EbonBuilds or {}

local eventFrame = CreateFrame("Frame")

local function OnAddonLoaded(addonName)
    if addonName ~= "EbonBuilds" then return end

    if not ProjectEbonhold then
        return
    end

    EbonBuildsDB = EbonBuildsDB or {
        builds        = {},
        activeBuildId = nil,
        minimapAngle  = 220,
    }
    EbonBuildsDB.minimapAngle = EbonBuildsDB.minimapAngle or 220

    EbonBuilds.Build.Migrate()
    EbonBuilds.Session.Init()
    EbonBuilds.SessionHistory.Init()
    EbonBuilds.Weights.Init()
    EbonBuilds.Toast.Init()
    EbonBuilds.WelcomeView.Init()
    EbonBuilds.BonusView.Init()
    EbonBuilds.BuildWizard.Init()
    EbonBuilds.MinimapButton.Init()
    EbonBuilds.MainWindow.Init()
    EbonBuilds.Automation.Init()
    EbonBuilds.Sync.Init()
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(...)
    end
end)
