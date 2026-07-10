-- EbonBuilds: modules/ui/SiteTheme.lua
-- Website design tokens — single source for SiteWidgets and site-styled views.

EbonBuilds.SiteTheme = EbonBuilds.SiteTheme or {}

local ST = EbonBuilds.SiteTheme

ST.FLAT = "Interface\\Buttons\\WHITE8X8"

ST.FONT = {
    regular  = "Fonts\\FRIZQT__.TTF",
    medium   = "Fonts\\FRIZQT__.TTF",
    semibold = "Fonts\\FRIZQT__.TTF",
    fallback = "Fonts\\FRIZQT__.TTF",
}

ST.Layout = {
    PAD          = 16,
    NAV_H        = 48,
    CHIP_H       = 24,
    SIDEBAR_W    = 248,
    MAIN_W       = 780,
    WIN_W        = 1040,
    WIN_H        = 720,
    ICON_TIER    = 32,
    ICON_LOCKED  = 36,
    ICON_GAP     = 6,
    TIER_LABEL_W = 32,
    CLASS_ICON   = 44,
    SPEC_ICON    = 18,
}

ST.Base = {
    bg          = { 29/255,  31/255,  41/255 },
    bgElevated  = { 34/255,  37/255,  47/255 },
    bgHeader    = { 37/255,  40/255,  51/255 },
    border      = { 46/255,  46/255,  56/255 },
    borderHover = { 61/255,  61/255,  74/255 },
    accent      = { 77/255, 191/255, 242/255 },
    text        = {235/255, 235/255, 240/255 },
    textDim     = {140/255, 140/255, 153/255 },
    textMuted   = {110/255, 110/255, 122/255 },
    elementBg   = { 31/255,  31/255,  38/255 },
}

function ST.BlendRgb(fg, bg, alpha)
    local inv = 1 - alpha
    return {
        fg[1] * alpha + bg[1] * inv,
        fg[2] * alpha + bg[2] * inv,
        fg[3] * alpha + bg[3] * inv,
        1.00,
    }
end

local function Opaque(rgb)
    return { rgb[1], rgb[2], rgb[3], 1.00 }
end

local B = ST.Base

ST.C = {
    bg            = Opaque(B.bg),
    bgElevated    = Opaque(B.bgElevated),
    bgHeader      = Opaque(B.bgHeader),
    border        = Opaque(B.border),
    borderHover   = Opaque(B.borderHover),
    borderSoft    = ST.BlendRgb(B.border, B.bg, 0.70),
    accent        = Opaque(B.accent),
    accentLight   = ST.BlendRgb(B.accent, { 1, 1, 1 }, 0.35),
    text          = Opaque(B.text),
    textDim       = Opaque(B.textDim),
    textMuted     = Opaque(B.textMuted),
    elementBg     = Opaque(B.elementBg),
    navBg         = ST.BlendRgb(B.bgHeader, B.bg, 0.85),
    sidebarBg     = ST.BlendRgb(B.bgElevated, B.bg, 0.40),
    mainBg        = ST.BlendRgb(B.bg, B.bg, 0.20),
    tabBarBg      = ST.BlendRgb(B.bgElevated, B.bg, 0.20),
    tierRowBg     = ST.BlendRgb(B.bg, B.bg, 0.40),
    statCellBg    = ST.BlendRgb(B.bg, ST.BlendRgb(B.bgElevated, B.bg, 0.40), 0.80),
    accentBg10    = ST.BlendRgb(B.accent, B.bg, 0.10),
    accentBg12    = ST.BlendRgb(B.accent, B.bg, 0.12),
    accentBg18    = ST.BlendRgb(B.accent, B.bg, 0.18),
    accentBorder30  = ST.BlendRgb(B.accent, B.border, 0.30),
    accentBorder35  = ST.BlendRgb(B.accent, B.border, 0.35),
    accentBorder55  = ST.BlendRgb(B.accent, B.border, 0.55),
    emptySlotBg   = ST.BlendRgb(B.bg, ST.BlendRgb(B.bgElevated, B.bg, 0.40), 0.60),
    chipBg        = ST.BlendRgb(B.bgHeader, B.bg, 0.92),
    accentGlow    = ST.BlendRgb(B.accent, B.bg, 0.45),
    shadow        = { 0, 0, 0, 0.35 },
    success       = { 74/255, 222/255, 128/255 },
    successBg10   = ST.BlendRgb({ 74/255, 222/255, 128/255 }, B.bg, 0.10),
    successBorder30 = ST.BlendRgb({ 74/255, 222/255, 128/255 }, B.border, 0.30),
}

ST.CLASS_DISPLAY = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", DEATHKNIGHT = "Death Knight", SHAMAN = "Shaman",
    MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

ST.CLASS_COLORS = {
    WARRIOR     = { 0.78, 0.61, 0.43 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    ROGUE       = { 1.0,  0.96, 0.41 },
    PRIEST      = { 1.0,  1.0,  1.0  },
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN      = { 0.0,  0.44, 0.87 },
    MAGE        = { 0.41, 0.8,  0.94 },
    WARLOCK     = { 0.58, 0.51, 0.79 },
    DRUID       = { 1.0,  0.49, 0.04 },
}

ST.QUALITY_BORDER = {
    [0] = { 1.0, 1.0, 1.0 },
    [1] = { 25/255, 1.0, 25/255 },
    [2] = { 0.0, 102/255, 1.0 },
    [3] = { 204/255, 102/255, 1.0 },
    [4] = { 1.0, 128/255, 0.0 },
}

function ST.ClassTint(classColor, alpha, baseRgb)
    baseRgb = baseRgb or B.bg
    return ST.BlendRgb(classColor, baseRgb, alpha)
end

function ST.ApplyClassBackgroundGradient(tex, classColor, baseRgb)
    baseRgb = baseRgb or B.bg
    local top = ST.ClassTint(classColor, 0.14, baseRgb)
    local bottom = { baseRgb[1], baseRgb[2], baseRgb[3], 1.00 }
    tex:SetTexture(ST.FLAT)
    tex:SetGradientAlpha("VERTICAL",
        top[1], top[2], top[3], 1.00,
        bottom[1], bottom[2], bottom[3], 1.00)
end

function ST.ApplyClassStripe(tex, classColor)
    tex:SetTexture(ST.FLAT)
    tex:SetVertexColor(classColor[1], classColor[2], classColor[3], 1.00)
end

function ST.SpecIndex(classToken, specNameOrIndex)
    if type(specNameOrIndex) == "number" then return specNameOrIndex end
    local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[classToken]
    if not specs then return 1 end
    for i, entry in ipairs(specs) do
        if entry.name == specNameOrIndex then return i end
    end
    return 1
end

function ST.SpecDisplay(classToken, specNameOrIndex)
    local idx = ST.SpecIndex(classToken, specNameOrIndex)
    local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[classToken]
    local entry = specs and specs[idx]
    return entry and entry.name or "", entry and entry.icon
end

------------------------------------------------------------------------
-- Dynamic accent palette (class-color driven)
------------------------------------------------------------------------

ST._themeListeners = {}
ST._accentClassToken = nil

local SURFACE_TINT = {
    bg          = 0.14,
    bgElevated  = 0.16,
    bgHeader    = 0.16,
    elementBg   = 0.14,
    border      = 0.12,
    borderHover = 0.14,
}

local function TintSurface(classColor, base, alpha)
    return ST.BlendRgb(classColor, base, alpha)
end

local function RecomputeClassPalette(classColor)
    local C = ST.C

    local bg          = TintSurface(classColor, B.bg, SURFACE_TINT.bg)
    local bgElevated  = TintSurface(classColor, B.bgElevated, SURFACE_TINT.bgElevated)
    local bgHeader    = TintSurface(classColor, B.bgHeader, SURFACE_TINT.bgHeader)
    local elementBg   = TintSurface(classColor, B.elementBg, SURFACE_TINT.elementBg)
    local border      = TintSurface(classColor, B.border, SURFACE_TINT.border)
    local borderHover = TintSurface(classColor, B.borderHover, SURFACE_TINT.borderHover)
    local sidebarMix  = ST.BlendRgb(bgElevated, bg, 0.40)

    C.bg            = Opaque(bg)
    C.bgElevated    = Opaque(bgElevated)
    C.bgHeader      = Opaque(bgHeader)
    C.elementBg     = Opaque(elementBg)
    C.border        = Opaque(border)
    C.borderHover   = Opaque(borderHover)
    C.borderSoft    = ST.BlendRgb(border, bg, 0.70)
    C.navBg         = ST.BlendRgb(bgHeader, bg, 0.85)
    C.sidebarBg     = sidebarMix
    C.mainBg        = ST.BlendRgb(bg, bg, 0.20)
    C.tabBarBg      = ST.BlendRgb(bgElevated, bg, 0.20)
    C.tierRowBg     = ST.BlendRgb(bg, bg, 0.40)
    C.statCellBg    = ST.BlendRgb(bg, sidebarMix, 0.80)
    C.emptySlotBg   = ST.BlendRgb(bg, sidebarMix, 0.60)
    C.chipBg        = ST.BlendRgb(bgHeader, bg, 0.92)

    C.accent          = Opaque(classColor)
    C.accentLight     = ST.BlendRgb(classColor, { 1, 1, 1 }, 0.35)
    C.accentBg10      = ST.BlendRgb(classColor, bg, 0.10)
    C.accentBg12      = ST.BlendRgb(classColor, bg, 0.12)
    C.accentBg18      = ST.BlendRgb(classColor, bg, 0.18)
    C.accentBorder30  = ST.BlendRgb(classColor, border, 0.30)
    C.accentBorder35  = ST.BlendRgb(classColor, border, 0.35)
    C.accentBorder55  = ST.BlendRgb(classColor, border, 0.55)
    C.accentGlow      = ST.BlendRgb(classColor, bg, 0.45)
end

function ST.OnThemeChanged(fn)
    if type(fn) ~= "function" then return end
    ST._themeListeners[#ST._themeListeners + 1] = fn
end

function ST.SetAccentClass(classToken)
    if classToken == ST._accentClassToken then return end
    ST._accentClassToken = classToken
    local classColor = (classToken and ST.CLASS_COLORS[classToken]) or B.accent
    RecomputeClassPalette(classColor)
    for _, fn in ipairs(ST._themeListeners) do
        fn()
    end
end

function ST.GetAccentClass()
    return ST._accentClassToken
end
