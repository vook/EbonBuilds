-- EbonBuilds: modules/ui/MainNav.lua
-- Site-style top navigation bar — floats above the main panel.

EbonBuilds.MainNav = EbonBuilds.MainNav or {}

local MN  = EbonBuilds.MainNav
local ST  = EbonBuilds.SiteTheme
local SW  = EbonBuilds.SiteWidgets
local C   = ST.C
local L   = ST.Layout

local navFrame
local anchorFrame
local navState = { activeId = "myBuild", registry = {} }
local accentStripe, navGlow, logoText
local themeHooked = false

local NAV_LAYOUT_V = 1

local ACTION_BTN_H = 28
local ACTION_BTN_TOP = -math.floor((L.NAV_H - ACTION_BTN_H) / 2)

local function AccentHex()
    local a = C.accent
    return string.format("%02x%02x%02x", a[1] * 255, a[2] * 255, a[3] * 255)
end

local function RepaintNavTheme()
    if accentStripe then
        accentStripe:SetVertexColor(unpack(C.accent))
    end
    if navGlow then
        navGlow:SetVertexColor(unpack(C.accentGlow))
    end
    if logoText then
        logoText:SetText("|cffebebf0Ebon|r|cff" .. AccentHex() .. "Builds|r")
    end
    for _, link in pairs(navState.registry) do
        if link.ApplyState then link.ApplyState() end
    end
end

local function DestroyNavFrame()
    if navFrame then
        navFrame:Hide()
        navFrame = nil
    end
    if _G.EbonBuildsMainNav then
        _G.EbonBuildsMainNav:Hide()
        _G.EbonBuildsMainNav = nil
    end
    navState.registry = {}
    accentStripe = nil
    navGlow = nil
    logoText = nil
end

local NAV_ROUTES = {
    publicBuilds = "publicBuilds",
    myBuild      = "buildOverview",
}

local NAV_ITEMS = {
    { id = "myBuild", label = "My Build", icon = "builds" },
    { id = "publicBuilds", label = "Public Builds", icon = "catalog" },
}

local ACTION_ITEMS = {
    { id = "newBuild", label = "New Build", icon = "builds", accent = true },
}

local function PositionNav()
    if navFrame and anchorFrame and anchorFrame:IsShown() then
        navFrame:ClearAllPoints()
        navFrame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 6)
    end
end

local function RunAction(item)
    if item.id == "newBuild" then
        EbonBuilds.ViewRouter.Show("buildWizard")
    end
end

local function CreateActionButton(parent, item)
    local variant = item.accent and "accent" or "default"
    return SW.CreateNavActionButton(parent, {
        label   = item.label,
        icon    = item.icon,
        variant = variant,
        onClick = function() RunAction(item) end,
    })
end

function MN.SetActiveId(navId)
    navState.activeId = navId or "myBuild"
    if navState.registry then
        for _, link in pairs(navState.registry) do
            if link.ApplyState then link.ApplyState() end
        end
    end
end

function MN.Position()
    PositionNav()
end

function MN.Show()
    if navFrame then
        navFrame:Show()
        PositionNav()
    end
end

function MN.SetOpacity(opacity)
    if navFrame then
        navFrame:SetAlpha(1)
    end
    if SW.SetWindowOpacity then
        SW.SetWindowOpacity(opacity or 1)
    end
end

function MN.Hide()
    if navFrame then navFrame:Hide() end
end

function MN.Create(panelFrame, opts)
    opts = opts or {}
    anchorFrame = panelFrame

    if navFrame and navFrame._navLayoutV == NAV_LAYOUT_V then
        anchorFrame = panelFrame
        if navFrame:GetParent() ~= panelFrame then
            navFrame:SetParent(panelFrame)
        end
        PositionNav()
        return navFrame
    end
    DestroyNavFrame()

    navState.onSelect = function(id)
        local route = NAV_ROUTES[id]
        if not route then return end
        if route == "buildOverview" then
            if EbonBuilds.MainWindow and EbonBuilds.MainWindow.ShowMyBuildView then
                EbonBuilds.MainWindow.ShowMyBuildView()
            else
                EbonBuilds.ViewRouter.Show("welcome")
            end
        else
            EbonBuilds.ViewRouter.Show(route)
        end
        MN.SetActiveId(id)
    end

    navFrame = CreateFrame("Frame", "EbonBuildsMainNav", panelFrame)
    navFrame:SetSize(L.WIN_W, L.NAV_H)
    navFrame:SetFrameStrata(panelFrame:GetFrameStrata())
    navFrame:SetFrameLevel(panelFrame:GetFrameLevel() + 20)
    navFrame:Hide()

    SW.FillChrome(navFrame, "navBg")
    SW.ThinBorder(navFrame, "border", 1)

    local accentStripeTex = navFrame:CreateTexture(nil, "ARTWORK")
    accentStripeTex:SetTexture(ST.FLAT)
    accentStripeTex:SetVertexColor(unpack(C.accent))
    accentStripeTex:SetWidth(4)
    accentStripeTex:SetPoint("TOPLEFT", 0, 0)
    accentStripeTex:SetPoint("BOTTOMLEFT", 0, 0)
    accentStripe = accentStripeTex

    local glowParent = CreateFrame("Frame", nil, navFrame)
    glowParent:SetPoint("TOPLEFT", 0, 0)
    glowParent:SetPoint("BOTTOMLEFT", 0, 0)
    glowParent:SetWidth(10)
    navGlow = SW.AttachAccentGlow(glowParent, 10)

    if not themeHooked then
        ST.OnThemeChanged(RepaintNavTheme)
        themeHooked = true
    end

    local logoArea = CreateFrame("Frame", nil, navFrame)
    logoArea:SetPoint("LEFT", accentStripeTex, "RIGHT", 10, 0)
    logoArea:SetSize(150, L.NAV_H)
    logoArea:EnableMouse(true)
    logoArea:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and anchorFrame then
            anchorFrame:StartMoving()
        end
    end)
    logoArea:SetScript("OnMouseUp", function()
        if anchorFrame then anchorFrame:StopMovingOrSizing() end
    end)

    logoText = SW.Label(logoArea, "|cffebebf0Ebon|r|cff" .. AccentHex() .. "Builds|r", 14, C.text, false, "semibold")
    logoText:SetPoint("LEFT", 0, 0)

    local navRow = CreateFrame("Frame", nil, navFrame)
    navRow:SetPoint("LEFT", logoArea, "RIGHT", 12, 0)
    navRow:SetPoint("RIGHT", navFrame, "RIGHT", -200, 0)
    navRow:SetHeight(L.NAV_H)
    navRow:SetFrameLevel(navFrame:GetFrameLevel() + 2)

    navState.registry = {}
    local prev
    for _, item in ipairs(NAV_ITEMS) do
        local link = SW.CreateNavLink(navRow, item, navState)
        link:SetPoint("TOP", navRow, "TOP", 0, 0)
        if prev then
            link:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else
            link:SetPoint("LEFT", navRow, "LEFT", 0, 0)
        end
        prev = link
        navState.registry[item.id] = link
    end

    local utility = CreateFrame("Frame", nil, navFrame)
    utility:SetHeight(L.NAV_H)
    utility:SetFrameLevel(navFrame:GetFrameLevel() + 2)

    local xOffset = 0
    if opts.onClose then
        local closeBtn = SW.CreateNavIconButton(utility, "close", opts.onClose)
        closeBtn:SetPoint("RIGHT", utility, "RIGHT", xOffset, 0)
        closeBtn:SetPoint("TOP", utility, "TOP", 0, ACTION_BTN_TOP)
        xOffset = xOffset - ACTION_BTN_H
    end

    if opts.onSettings then
        if xOffset ~= 0 then xOffset = xOffset - 6 end
        local settingsBtn = SW.CreateNavIconButton(utility, "settings", opts.onSettings)
        settingsBtn:SetPoint("RIGHT", utility, "RIGHT", xOffset, 0)
        settingsBtn:SetPoint("TOP", utility, "TOP", 0, ACTION_BTN_TOP)
        xOffset = xOffset - ACTION_BTN_H
    end

    utility:SetWidth(math.max(0, -xOffset))
    utility:SetPoint("RIGHT", navFrame, "RIGHT", -10, 0)

    local actions = CreateFrame("Frame", nil, navFrame)
    actions:SetPoint("RIGHT", utility, "LEFT", -8, 0)
    actions:SetPoint("TOP", navFrame, "TOP", 0, 0)
    actions:SetHeight(L.NAV_H)
    actions:SetFrameLevel(navFrame:GetFrameLevel() + 2)

    prev = nil
    for i = #ACTION_ITEMS, 1, -1 do
        local item = ACTION_ITEMS[i]
        local btn = CreateActionButton(actions, item)
        btn:SetPoint("TOP", actions, "TOP", 0, ACTION_BTN_TOP)
        if prev then
            btn:SetPoint("RIGHT", prev, "LEFT", -6, 0)
        else
            btn:SetPoint("RIGHT", actions, "RIGHT", 0, 0)
        end
        prev = btn
    end

    panelFrame:HookScript("OnShow", function()
        PositionNav()
        MN.Show()
    end)
    panelFrame:HookScript("OnHide", function()
        if navFrame then navFrame:Hide() end
    end)

    navFrame._navLayoutV = NAV_LAYOUT_V
    MN.SetActiveId(navState.activeId)

    return navFrame
end
