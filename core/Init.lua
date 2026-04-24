-- EbonBuilds: core/Init.lua
-- Responsibility: addon bootstrap, saved-variable initialisation, module wiring.

EbonBuilds = EbonBuilds or {}

local eventFrame = CreateFrame("Frame")

local function OnAddonLoaded(addonName)
    if addonName ~= "EbonBuilds" then return end

    if not ProjectEbonhold then
        print("EbonBuilds: ProjectEbonhold not found. Aborting.")
        return
    end

    EbonBuildsDB = EbonBuildsDB or {
        builds        = {},
        activeBuildId = nil,
        minimapAngle  = 220,
    }
    EbonBuildsDB.minimapAngle = EbonBuildsDB.minimapAngle or 220

    EbonBuilds.Build.Migrate()
    EbonBuilds.Weights.Init()
    EbonBuilds.MinimapButton.Init()
    EbonBuilds.MainWindow.Init()
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(...)
    end
end)
