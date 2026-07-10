-- EbonBuilds: modules/ui/WelcomeView.lua
-- Responsibility: empty-state welcome screen with site-style action tiles.

EbonBuilds.WelcomeView = {}

local ST   = EbonBuilds.SiteTheme
local SW   = EbonBuilds.SiteWidgets
local C    = ST.C
local FLAT = ST.FLAT

local CONTENT_W = 640
local FOOTER_H  = 36
local WRAP_H    = 390

local viewFrame
local statsLabel
local heroStripe, heroGlow
local stepNumLabels = {}
local actionTiles = {}
local themeHooked = false

local ADDON_VERSION = GetAddOnMetadata and GetAddOnMetadata("EbonBuilds", "Version") or "1.0.0"

local QUICK_ACTIONS = {
    {
        title   = "New Build",
        desc    = "Start from scratch",
        icon    = "builds",
        variant = "accent",
        run = function()
            EbonBuilds.ViewRouter.Show("buildWizard")
        end,
    },
    {
        title   = "My Builds",
        desc    = "Select a saved build",
        icon    = "builds",
        variant = "default",
        run = function()
            if EbonBuilds.MainWindow and EbonBuilds.MainWindow.ShowBuildPicker then
                EbonBuilds.MainWindow.ShowBuildPicker()
            end
        end,
    },
    {
        title   = "Import Build",
        desc    = "Paste shared text",
        icon    = "import",
        variant = "default",
        run = function()
            if EbonBuilds.ExportImport and EbonBuilds.ExportImport.ShowImportDialog then
                EbonBuilds.ExportImport.ShowImportDialog()
            end
        end,
    },
    {
        title   = "Public Builds",
        desc    = "Browse community",
        icon    = "catalog",
        variant = "default",
        run = function()
            EbonBuilds.ViewRouter.Show("publicBuilds")
        end,
    },
    {
        title   = "Echo Journal",
        desc    = "Native /echoes browser",
        icon    = "external",
        variant = "default",
        run = function()
            if EbonBuilds.OpenEchoJournal then
                EbonBuilds.OpenEchoJournal()
            end
        end,
    },
}

local STEPS = {
    "Create or import a build, or open My Builds to select an existing one.",
    "Set echo weights, policies, and affix scans on your build.",
    "Enable automation during World of Echoes runs.",
}

local DANGER_COLOR = { 0.9, 0.25, 0.25 }

local function TileColors(variant)
    if variant == "accent" then
        return C.accentBg10, C.accentBg18, C.accentBorder35, C.accentBorder55, C.accent
    elseif variant == "danger" then
        local bg   = ST.BlendRgb(DANGER_COLOR, ST.Base.bg, 0.10)
        local bghv = ST.BlendRgb(DANGER_COLOR, ST.Base.bg, 0.18)
        local bd   = ST.BlendRgb(DANGER_COLOR, ST.Base.border, 0.30)
        local bdhv = ST.BlendRgb(DANGER_COLOR, ST.Base.border, 0.55)
        local tc   = { 0.95, 0.50, 0.50, 1 }
        return bg, bghv, bd, bdhv, tc
    else
        return C.elementBg, C.bgElevated, C.border, C.borderHover, C.text
    end
end

local function CreateActionTile(parent, action, w, h)
    local bgNorm, bgHov, bdNorm, bdHov, textColor = TileColors(action.variant)
    local iconColor = action.variant == "default" and C.textDim or textColor

    local tile = CreateFrame("Button", nil, parent)
    tile:SetSize(w, h)

    local bg     = SW.Fill(tile, bgNorm)
    local border = SW.ThinBorder(tile, bdNorm)

    local ICON_SIZE = 18
    local PAD_L     = 16
    local TEXT_OFF  = PAD_L + ICON_SIZE + 10

    if action.icon and EbonBuilds.SiteIcons and EbonBuilds.SiteIcons.Exists(action.icon) then
        local ic = SW.CreateIcon(tile, action.icon, ICON_SIZE, iconColor)
        ic:SetPoint("LEFT", tile, "LEFT", PAD_L, 3)
        tile._icon = ic
    end

    local titleLbl = SW.Label(tile, action.title, 13, textColor, false, "semibold")
    titleLbl:SetPoint("TOPLEFT", tile, "TOPLEFT", TEXT_OFF, -12)
    titleLbl:SetJustifyH("LEFT")

    local descLbl = SW.Label(tile, action.desc, 10, C.textDim)
    descLbl:SetPoint("TOPLEFT", titleLbl, "BOTTOMLEFT", 0, -3)
    descLbl:SetJustifyH("LEFT")

    tile:SetScript("OnEnter", function()
        local bgNorm, bgHov, bdNorm, bdHov, textColor = TileColors(tile._variant)
        tile._bg:SetVertexColor(unpack(bgHov))
        SW.SetBorderColor(tile._border, bdHov)
        tile._titleLbl:SetTextColor(unpack(tile._variant == "default" and C.accent or textColor))
        if tile._icon then tile._icon:SetColor(tile._variant == "default" and C.accent or textColor) end
    end)
    tile:SetScript("OnLeave", function()
        local bgNorm, _, bdNorm, _, textColor = TileColors(tile._variant)
        tile._iconColor = tile._variant == "default" and C.textDim or textColor
        tile._bg:SetVertexColor(unpack(bgNorm))
        SW.SetBorderColor(tile._border, bdNorm)
        tile._titleLbl:SetTextColor(unpack(textColor))
        if tile._icon then tile._icon:SetColor(tile._iconColor) end
    end)
    tile:SetScript("OnClick", action.run)

    tile._variant = action.variant
    tile._bg = bg
    tile._border = border
    tile._titleLbl = titleLbl
    tile._iconColor = iconColor
    actionTiles[#actionTiles + 1] = tile

    return tile
end

local function RepaintActionTile(tile)
    if not tile or not tile._bg then return end
    local bgNorm, bgHov, bdNorm, bdHov, textColor = TileColors(tile._variant)
    tile._iconColor = tile._variant == "default" and C.textDim or textColor
    if not tile:IsMouseOver() then
        tile._bg:SetVertexColor(unpack(bgNorm))
        SW.SetBorderColor(tile._border, bdNorm)
        tile._titleLbl:SetTextColor(unpack(textColor))
        if tile._icon then tile._icon:SetColor(tile._iconColor) end
    end
end

local function RepaintWelcomeTheme()
    if heroStripe then heroStripe:SetVertexColor(unpack(C.accent)) end
    if heroGlow then heroGlow:SetVertexColor(unpack(C.accentBg10)) end
    if statsLabel then statsLabel:SetTextColor(unpack(C.accent)) end
    for _, num in ipairs(stepNumLabels) do
        num:SetTextColor(unpack(C.accent))
    end
    for _, tile in ipairs(actionTiles) do
        RepaintActionTile(tile)
    end
end

local function FormatStats()
    local myCount = #(EbonBuilds.Build.List and EbonBuilds.Build.List() or {})
    return string.format("%d saved build%s", myCount, myCount == 1 and "" or "s")
end

local function RefreshContent()
    if statsLabel then statsLabel:SetText(FormatStats()) end
end

local function BuildFooter(parent)
    local footer = CreateFrame("Frame", nil, parent)
    footer:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  0, 0)
    footer:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    footer:SetHeight(FOOTER_H)
    SW.FillChrome(footer, "navBg")

    local topLine = footer:CreateTexture(nil, "ARTWORK")
    topLine:SetTexture(FLAT)
    topLine:SetVertexColor(unpack(C.border))
    topLine:SetPoint("TOPLEFT",  footer, "TOPLEFT",  0, 0)
    topLine:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    topLine:SetHeight(1)

    local versionLbl = SW.Label(footer, "v" .. ADDON_VERSION, 10, C.textMuted)
    versionLbl:SetPoint("LEFT", footer, "LEFT", 16, 0)

    return footer
end

local function BuildViewFrame(parent)
    local f = CreateFrame("Frame", nil, parent)

    BuildFooter(f)

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT",     f, "TOPLEFT",     0,  0)
    body:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    0,  0)
    body:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0,  FOOTER_H)
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,  FOOTER_H)

    local wrap = CreateFrame("Frame", nil, body)
    wrap:SetSize(CONTENT_W, WRAP_H)
    wrap:SetPoint("CENTER", body, "CENTER", 0, 0)

    local hero = CreateFrame("Frame", nil, wrap)
    hero:SetSize(CONTENT_W, 86)
    hero:SetPoint("TOP", wrap, "TOP", 0, 0)
    SW.FillChrome(hero, "bgElevated")
    SW.ThinBorder(hero, "border")

    local stripe = hero:CreateTexture(nil, "OVERLAY")
    stripe:SetTexture(FLAT)
    stripe:SetVertexColor(unpack(C.accent))
    stripe:SetPoint("TOPLEFT",    hero, "TOPLEFT",    0, 0)
    stripe:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", 0, 0)
    stripe:SetWidth(3)
    heroStripe = stripe

    local glow = hero:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(FLAT)
    glow:SetVertexColor(unpack(C.accentBg10))
    glow:SetPoint("TOPLEFT",    hero, "TOPLEFT",    3, 0)
    glow:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", 3, 0)
    glow:SetWidth(90)
    heroGlow = glow

    local addonIcon = hero:CreateTexture(nil, "ARTWORK")
    addonIcon:SetSize(44, 44)
    addonIcon:SetPoint("LEFT", hero, "LEFT", 22, 0)
    addonIcon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    addonIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local titleLbl = SW.Label(hero, "EbonBuilds", 17, C.text, false, "semibold")
    titleLbl:SetPoint("TOPLEFT", addonIcon, "TOPRIGHT", 14, 0)
    titleLbl:SetJustifyH("LEFT")

    local taglineLbl = SW.Label(hero, "Echo automation, weights & P2P builds for Project Ebonhold", 11, C.textDim)
    taglineLbl:SetPoint("TOPLEFT", titleLbl, "BOTTOMLEFT", 0, -4)
    taglineLbl:SetWidth(420)
    taglineLbl:SetJustifyH("LEFT")

    statsLabel = SW.Label(hero, "", 10, C.accent)
    statsLabel:SetPoint("TOPLEFT", taglineLbl, "BOTTOMLEFT", 0, -4)
    statsLabel:SetJustifyH("LEFT")

    local TILE_GAP = 8
    local TILE_W   = math.floor((CONTENT_W - TILE_GAP) / 2)
    local TILE_H   = 58
    local ACT_PAD  = 10
    local actRows  = math.ceil(#QUICK_ACTIONS / 2)
    local actWrap  = CreateFrame("Frame", nil, wrap)
    actWrap:SetPoint("TOP", hero, "BOTTOM", 0, -10)
    actWrap:SetSize(CONTENT_W, ACT_PAD + actRows * TILE_H + (actRows - 1) * TILE_GAP + ACT_PAD)

    for i, action in ipairs(QUICK_ACTIONS) do
        local col = (i % 2 == 1) and 0 or (TILE_W + TILE_GAP)
        local rowIdx = math.floor((i - 1) / 2)
        local row = -(ACT_PAD + rowIdx * (TILE_H + TILE_GAP))
        local tile = CreateActionTile(actWrap, action, TILE_W, TILE_H)
        tile:SetPoint("TOPLEFT", actWrap, "TOPLEFT", col, row)
    end

    local stepsPanel = CreateFrame("Frame", nil, wrap)
    stepsPanel:SetPoint("TOP", actWrap, "BOTTOM", 0, -10)
    stepsPanel:SetSize(CONTENT_W, 74)
    SW.FillChrome(stepsPanel, "bgElevated")
    SW.ThinBorder(stepsPanel, "border")

    local stepTitle = SW.Label(stepsPanel, "GETTING STARTED", 9, C.textMuted, false, "medium")
    stepTitle:SetPoint("TOPLEFT", stepsPanel, "TOPLEFT", 14, -9)

    local ROW_H = 16
    for i, text in ipairs(STEPS) do
        local y = -24 - (i - 1) * (ROW_H + 2)
        local num = SW.Label(stepsPanel, tostring(i) .. ".", 11, C.accent, false, "semibold")
        num:SetPoint("TOPLEFT", stepsPanel, "TOPLEFT", 14, y)
        num:SetWidth(14)
        num:SetJustifyH("RIGHT")
        stepNumLabels[#stepNumLabels + 1] = num

        local line = SW.Label(stepsPanel, text, 11, C.textDim)
        line:SetPoint("TOPLEFT", stepsPanel, "TOPLEFT", 32, y)
        line:SetWidth(CONTENT_W - 46)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
    end

    return f
end

local function EnsureBuilt(container)
    if viewFrame and viewFrame._welcomeV1 then return end
    if viewFrame then
        viewFrame:Hide()
        viewFrame:SetParent(nil)
        viewFrame = nil
    end
    stepNumLabels = {}
    actionTiles = {}
    heroStripe = nil
    heroGlow = nil
    viewFrame = BuildViewFrame(container)
    viewFrame._welcomeV1 = true
    if not themeHooked then
        ST.OnThemeChanged(RepaintWelcomeTheme)
        themeHooked = true
    end
end

function EbonBuilds.WelcomeView.Mount(container)
    EnsureBuilt(container)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)
    RefreshContent()
    viewFrame:Show()
end

function EbonBuilds.WelcomeView.Unmount()
    if not viewFrame then return end
    viewFrame:Hide()
end

function EbonBuilds.WelcomeView.Init()
end
