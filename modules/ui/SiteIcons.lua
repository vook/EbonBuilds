-- EbonBuilds: modules/ui/SiteIcons.lua
-- Maps logical icon names to WoW stock textures (no custom media required).

EbonBuilds.SiteIcons = EbonBuilds.SiteIcons or {}

local ICONS = {
    builds   = "Interface\\Icons\\INV_Misc_Book_09",
    catalog  = "Interface\\Icons\\INV_Misc_GroupLooking",
    import   = "Interface\\Icons\\INV_Misc_Note_01",
    external = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",
    close    = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    report   = "Interface\\Icons\\INV_Letter_15",
    download = "Interface\\Icons\\INV_Misc_EngGizmos_19",
    settings = "Interface\\Icons\\INV_Misc_Gear_01",
}

function EbonBuilds.SiteIcons.Path(name)
    return ICONS[name]
end

function EbonBuilds.SiteIcons.Exists(name)
    return ICONS[name] ~= nil
end
