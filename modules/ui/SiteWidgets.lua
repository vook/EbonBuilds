-- EbonBuilds: modules/ui/SiteWidgets.lua
-- Website-parity widget factories (lite). Use with SiteTheme.

EbonBuilds.SiteWidgets = EbonBuilds.SiteWidgets or {}

local SW = EbonBuilds.SiteWidgets
local ST = EbonBuilds.SiteTheme
local C  = ST.C
local L  = ST.Layout
local FLAT = ST.FLAT

local FONT_BY_WEIGHT = {
    regular  = ST.FONT.regular,
    medium   = ST.FONT.medium,
    semibold = ST.FONT.semibold,
}

local function ResolveColor(colorOrKey)
    if type(colorOrKey) == "string" then
        return C[colorOrKey] or C.bg
    end
    return colorOrKey
end

SW._themed = {}
SW._styledScrollBars = {}
SW._windowOpacity = 1
SW._opacityBackgrounds = {}

function SW.ApplyOpacityBackground(entry)
    if not entry or not entry.tex then return end
    local color = C[entry.colorKey]
    if not color then return end
    local baseAlpha = color[4] or 1
    entry.tex:SetVertexColor(color[1], color[2], color[3], baseAlpha * (SW._windowOpacity or 1))
end

function SW.RegisterOpacityBackground(tex, colorKey)
    if not tex or not colorKey then return end
    SW._opacityBackgrounds[#SW._opacityBackgrounds + 1] = {
        tex = tex,
        colorKey = colorKey,
    }
    SW.ApplyOpacityBackground(SW._opacityBackgrounds[#SW._opacityBackgrounds])
end

function SW.SetWindowOpacity(opacity)
    SW._windowOpacity = math.max(0.5, math.min(1, tonumber(opacity) or 1))
    for i = 1, #SW._opacityBackgrounds do
        SW.ApplyOpacityBackground(SW._opacityBackgrounds[i])
    end
end

function SW.FillChrome(parent, colorOrKey, layer)
    local key = type(colorOrKey) == "string" and colorOrKey or nil
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetTexture(FLAT)
    tex:SetAllPoints(parent)
    local function apply()
        local color = ResolveColor(key or colorOrKey)
        local baseAlpha = color[4] or 1
        tex:SetVertexColor(color[1], color[2], color[3], baseAlpha * (SW._windowOpacity or 1))
    end
    apply()
    SW.Track(apply)
    if key then
        SW.RegisterOpacityBackground(tex, key)
    end
    return tex
end

function SW.Track(repaintFn)
    if type(repaintFn) == "function" then
        SW._themed[#SW._themed + 1] = repaintFn
    end
end

function SW.RepaintTheme()
    for _, fn in ipairs(SW._themed) do
        fn()
    end
end

ST.OnThemeChanged(SW.RepaintTheme)

function SW.Fill(parent, colorOrKey, layer)
    local key = type(colorOrKey) == "string" and colorOrKey or nil
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND")
    tex:SetTexture(FLAT)
    tex:SetAllPoints(parent)
    local function apply()
        tex:SetVertexColor(unpack(ResolveColor(key or colorOrKey)))
    end
    apply()
    if key then SW.Track(apply) end
    return tex
end

function SW.ThinBorder(frame, colorOrKey, thickness)
    thickness = thickness or 1
    local key = type(colorOrKey) == "string" and colorOrKey or nil
    local borders = {}
    for _, spec in ipairs({
        { "TOPLEFT", "TOPRIGHT", "SetHeight", thickness },
        { "BOTTOMLEFT", "BOTTOMRIGHT", "SetHeight", thickness },
        { "TOPLEFT", "BOTTOMLEFT", "SetWidth", thickness },
        { "TOPRIGHT", "BOTTOMRIGHT", "SetWidth", thickness },
    }) do
        local tex = frame:CreateTexture(nil, "BORDER")
        tex:SetTexture(FLAT)
        tex:SetPoint(spec[1], frame, spec[1], 0, 0)
        tex:SetPoint(spec[2], frame, spec[2], 0, 0)
        tex[spec[3]](tex, spec[4])
        borders[#borders + 1] = tex
    end
    local function apply()
        SW.SetBorderColor(borders, ResolveColor(key or colorOrKey))
    end
    apply()
    if key then SW.Track(apply) end
    return borders
end

function SW.SetBorderColor(borders, color)
    if not borders then return end
    for _, tex in ipairs(borders) do
        tex:SetVertexColor(unpack(color))
    end
end

function SW.SetFont(fontString, size, weight, outline)
    local path = FONT_BY_WEIGHT[weight or "regular"] or ST.FONT.regular
    fontString:SetFont(path, size, outline and "OUTLINE" or "")
end

function SW.Label(parent, text, size, color, outline, weight)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    SW.SetFont(fs, size, weight, outline)
    fs:SetTextColor(unpack(color or C.text))
    if text then fs:SetText(text) end
    return fs
end

function SW.AttachPanelShadow(parent, offset)
    offset = offset or 4
    local shadow = CreateFrame("Frame", nil, parent)
    shadow:SetPoint("TOPLEFT", offset, -offset)
    shadow:SetPoint("BOTTOMRIGHT", -offset, offset)
    SW.FillChrome(shadow, "shadow")
    shadow:SetFrameLevel(math.max(0, parent:GetFrameLevel() - 1))
    parent._siteShadow = shadow
    return shadow
end

function SW.CreateSiteWindow(opts)
    opts = opts or {}
    local w = opts.width or L.WIN_W
    local h = opts.height or L.WIN_H

    local outer = CreateFrame("Frame", opts.name, UIParent)
    outer:SetSize(w, h)
    outer:SetPoint("CENTER")
    outer:SetMovable(true)
    outer:EnableMouse(true)
    outer:SetClampedToScreen(true)
    outer:SetFrameStrata(opts.strata or "DIALOG")
    if opts.toplevel then outer:SetToplevel(true) end
    outer:Hide()

    if opts.shadow ~= false then
        SW.AttachPanelShadow(outer, opts.shadowOffset or 4)
    end

    local panel = CreateFrame("Frame", nil, outer)
    panel:SetAllPoints(outer)
    panel._siteBg = SW.FillChrome(panel, "bg")
    SW.ThinBorder(panel, "border", 1)

    if opts.draggable ~= false then
        panel:EnableMouse(true)
        panel:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then outer:StartMoving() end
        end)
        panel:SetScript("OnMouseUp", function()
            outer:StopMovingOrSizing()
        end)
    end

    if opts.closable ~= false then
        local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -2, -2)
        closeBtn:SetFrameLevel(panel:GetFrameLevel() + 4)
        closeBtn:SetScript("OnClick", function()
            if opts.onClose then opts.onClose() else outer:Hide() end
        end)
        outer._closeBtn = closeBtn
    end

    local body = CreateFrame("Frame", nil, panel)
    body:SetAllPoints(panel)

    if opts.name then
        tinsert(UISpecialFrames, opts.name)
    end

    outer.panel = panel
    outer.body = body
    return outer
end

function SW.AttachAccentGlow(parent, width)
    width = width or 8
    local glow = parent:CreateTexture(nil, "BACKGROUND", nil, -1)
    glow:SetTexture(FLAT)
    glow:SetVertexColor(unpack(C.accentGlow))
    glow:SetWidth(width)
    glow:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    glow:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    return glow
end

function SW.SetClassIcon(tex, classToken)
    local coords = CLASS_ICON_TCOORDS[classToken]
    if coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    end
end

function SW.CreateClassIconHolder(parent, classToken, specNameOrIndex, iconSize)
    iconSize = iconSize or L.CLASS_ICON
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(iconSize, iconSize)

    local classIcon = holder:CreateTexture(nil, "ARTWORK")
    classIcon:SetSize(iconSize, iconSize)
    classIcon:SetPoint("TOPLEFT", 0, 0)
    SW.SetClassIcon(classIcon, classToken)
    holder._classIcon = classIcon

    if specNameOrIndex ~= nil then
        local _, specIconPath = ST.SpecDisplay(classToken, specNameOrIndex)
        if specIconPath then
            local specFrame = CreateFrame("Frame", nil, holder)
            specFrame:SetSize(L.SPEC_ICON, L.SPEC_ICON)
            specFrame:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 2, -2)
            specFrame:SetFrameLevel(holder:GetFrameLevel() + 2)
            SW.Fill(specFrame, "bg")
            SW.ThinBorder(specFrame, "border", 1)
            local specTex = specFrame:CreateTexture(nil, "ARTWORK")
            specTex:SetPoint("TOPLEFT", 1, -1)
            specTex:SetPoint("BOTTOMRIGHT", -1, 1)
            specTex:SetTexture(specIconPath)
            specTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            holder._specFrame = specFrame
            holder._specTex = specTex
        end
    end

    return holder
end

function SW.UpdateClassIconHolder(holder, classToken, spec)
    if not holder or not holder._classIcon then return end
    SW.SetClassIcon(holder._classIcon, classToken)
    local specIdx = ST.SpecIndex(classToken, spec)
    local _, specIconPath = ST.SpecDisplay(classToken, specIdx)
    if specIconPath then
        if not holder._specFrame then
            local specFrame = CreateFrame("Frame", nil, holder)
            specFrame:SetSize(L.SPEC_ICON, L.SPEC_ICON)
            specFrame:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 2, -2)
            specFrame:SetFrameLevel(holder:GetFrameLevel() + 2)
            SW.Fill(specFrame, "bg")
            SW.ThinBorder(specFrame, "border", 1)
            local specTex = specFrame:CreateTexture(nil, "ARTWORK")
            specTex:SetPoint("TOPLEFT", 1, -1)
            specTex:SetPoint("BOTTOMRIGHT", -1, 1)
            specTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            holder._specFrame = specFrame
            holder._specTex = specTex
        end
        holder._specTex:SetTexture(specIconPath)
        holder._specFrame:Show()
    elseif holder._specFrame then
        holder._specFrame:Hide()
    end
end

function SW.CreateIcon(parent, name, size, color)
    size = size or 16
    color = color or C.textDim
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)

    local tex = holder:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(holder)
    local path = EbonBuilds.SiteIcons and EbonBuilds.SiteIcons.Path(name)
    if path then
        tex:SetTexture(path)
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    tex:SetVertexColor(unpack(color))
    holder._tex = tex

    holder.SetColor = function(self, rgb)
        self._tex:SetVertexColor(unpack(rgb))
    end

    return holder
end

function SW.CreateNavActionButton(parent, opts)
    opts = opts or {}
    local variant = opts.variant or "default"
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(28)

    local bgColor, textColor, borderColor
    if variant == "accent" then
        bgColor, textColor, borderColor = "accentBg10", C.accent, "accentBorder35"
    elseif variant == "danger" then
        local d = { 0.9, 0.25, 0.25 }
        bgColor = ST.BlendRgb(d, ST.Base.bg, 0.12)
        textColor = { 0.95, 0.45, 0.45, 1 }
        borderColor = ST.BlendRgb(d, ST.Base.border, 0.35)
    else
        bgColor, textColor, borderColor = C.elementBg, C.textDim, C.border
    end

    if variant == "accent" then
        btn._bg = SW.Fill(btn, "accentBg10")
        btn._border = SW.ThinBorder(btn, "accentBorder35", 1)
    elseif variant == "danger" then
        btn._bg = SW.Fill(btn, bgColor)
        btn._border = SW.ThinBorder(btn, borderColor, 1)
    else
        btn._bg = SW.Fill(btn, "elementBg")
        btn._border = SW.ThinBorder(btn, "border", 1)
    end
    btn._bgColor = bgColor
    btn._textColor = textColor
    btn._borderColor = borderColor
    btn._variant = variant

    local padL = 10
    if opts.icon and EbonBuilds.SiteIcons and EbonBuilds.SiteIcons.Exists(opts.icon) then
        btn._icon = SW.CreateIcon(btn, opts.icon, 13, textColor)
        btn._icon:SetPoint("LEFT", padL, 0)
        btn._icon:SetPoint("TOP", btn, "TOP", 0, -8)
        padL = padL + 13 + 5
    end

    btn._label = SW.Label(btn, opts.label or "", 11, textColor, false, "medium")
    btn._label:SetPoint("LEFT", padL, 0)
    btn._label:SetPoint("TOP", btn, "TOP", 0, -9)
    btn:SetWidth(math.max(72, btn._label:GetStringWidth() + padL + 10))

    local function SetHover(hover)
        if variant == "accent" then
            btn._bg:SetVertexColor(unpack(hover and C.accentBg18 or C.accentBg10))
            SW.SetBorderColor(btn._border, hover and C.accentBorder55 or C.accentBorder35)
            local tc = hover and C.text or C.accent
            btn._label:SetTextColor(unpack(tc))
            if btn._icon then btn._icon:SetColor(tc) end
        elseif variant == "danger" then
            local d = { 0.9, 0.25, 0.25 }
            btn._bg:SetVertexColor(unpack(hover and ST.BlendRgb(d, ST.Base.bg, 0.18) or bgColor))
            SW.SetBorderColor(btn._border, hover and ST.BlendRgb(d, ST.Base.border, 0.55) or borderColor)
            local tc = hover and C.text or textColor
            btn._label:SetTextColor(unpack(tc))
            if btn._icon then btn._icon:SetColor(tc) end
        else
            btn._bg:SetVertexColor(unpack(hover and C.bgElevated or C.elementBg))
            SW.SetBorderColor(btn._border, hover and C.borderHover or C.border)
            btn._label:SetTextColor(unpack(hover and C.text or C.textDim))
            if btn._icon then btn._icon:SetColor(hover and C.text or C.textDim) end
        end
    end

    btn:SetScript("OnEnter", function() SetHover(true) end)
    btn:SetScript("OnLeave", function() SetHover(false) end)
    btn:SetScript("OnClick", function()
        if opts.onClick then opts.onClick() end
    end)

    if variant == "accent" then
        SW.Track(function()
            if not btn:IsMouseOver() then
                btn._bg:SetVertexColor(unpack(C.accentBg10))
                SW.SetBorderColor(btn._border, C.accentBorder35)
                btn._label:SetTextColor(unpack(C.accent))
                if btn._icon then btn._icon:SetColor(C.accent) end
            end
        end)
    end

    return btn
end

function SW.CreateCloseButton(parent, onClick, size)
    return SW.CreateNavIconButton(parent, "close", onClick, { size = size or 28 })
end

function SW.CreateNavLink(parent, item, navState)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(L.NAV_H)
    btn._id = item.id

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(FLAT)
    bg:SetAllPoints(btn)
    bg:Hide()
    btn._bg = bg

    local padL = 10
    if item.icon and EbonBuilds.SiteIcons and EbonBuilds.SiteIcons.Exists(item.icon) then
        btn._icon = SW.CreateIcon(btn, item.icon, 14, C.textDim)
        btn._icon:SetPoint("LEFT", padL, 0)
        padL = padL + 14 + 6
    end

    local label = SW.Label(btn, item.label, 13, C.textDim, false, "medium")
    label:SetPoint("LEFT", padL, 0)
    btn._label = label

    local function ApplyState()
        local active = (navState.activeId == item.id)
        local textColor = active and C.accent or C.textDim
        if active then
            bg:Show()
            bg:SetVertexColor(unpack(C.accentBg12))
        else
            bg:Hide()
        end
        label:SetTextColor(unpack(textColor))
        if btn._icon then btn._icon:SetColor(textColor) end
    end
    btn.ApplyState = ApplyState

    btn:SetScript("OnClick", function()
        navState.activeId = item.id
        if navState.onSelect then navState.onSelect(item.id, item.label) end
        if navState.registry then
            for _, link in pairs(navState.registry) do
                if link.ApplyState then link.ApplyState() end
            end
        end
    end)
    btn:SetScript("OnEnter", function()
        if navState.activeId ~= item.id then
            bg:Show()
            bg:SetVertexColor(unpack(C.elementBg))
            label:SetTextColor(unpack(C.text))
            if btn._icon then btn._icon:SetColor(C.text) end
        end
    end)
    btn:SetScript("OnLeave", ApplyState)

    local w = label:GetStringWidth() + padL + 12
    btn:SetWidth(w)
    ApplyState()
    return btn
end

function SW.CreateTabButton(parent, text, index, tabState)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(36)
    local label = SW.Label(btn, text, 13, C.textMuted, false, "medium")
    label:SetPoint("CENTER")
    local underline = btn:CreateTexture(nil, "OVERLAY")
    underline:SetTexture(FLAT)
    underline:SetVertexColor(unpack(C.accent))
    underline:SetHeight(2)
    underline:SetPoint("BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", 0, 0)
    underline:Hide()
    btn._label = label
    btn._underline = underline
    btn._index = index

    btn:SetScript("OnClick", function()
        if tabState.SelectTab then tabState.SelectTab(index) end
    end)
    btn:SetScript("OnEnter", function()
        if tabState.selectedIndex ~= index then
            label:SetTextColor(unpack(C.text))
        end
    end)
    btn:SetScript("OnLeave", function()
        if tabState.selectedIndex ~= index then
            label:SetTextColor(unpack(C.textMuted))
        end
    end)

    SW.Track(function()
        underline:SetVertexColor(unpack(C.accent))
        if tabState and tabState.selectedIndex == index then
            label:SetTextColor(unpack(C.accent))
        end
    end)

    return btn
end

function SW.UpdateTabBar(tabState)
    for i, btn in ipairs(tabState.tabs or {}) do
        local active = (tabState.selectedIndex == i)
        if active then btn._underline:Show() else btn._underline:Hide() end
        btn._label:SetTextColor(unpack(active and C.accent or C.textMuted))
        local w = btn._label:GetStringWidth() + 20
        btn:SetWidth(w)
    end
end

function SW.CreateSidebarBlock(parent, title)
    local block = CreateFrame("Frame", nil, parent)
    block:SetPoint("LEFT", 0, 0)
    block:SetPoint("RIGHT", 0, 0)

    local sep = block:CreateTexture(nil, "ARTWORK")
    sep:SetTexture(FLAT)
    sep:SetVertexColor(unpack(C.borderSoft))
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", 0, 0)

    local titleLabel = SW.Label(block, string.upper(title or ""), 11, C.textMuted, false, "semibold")
    titleLabel:SetPoint("TOPLEFT", L.PAD, -L.PAD)
    block._title = titleLabel
    block._contentTop = -L.PAD - 18
    return block
end

function SW.CreatePlainScroll(parent, childWidth)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    scroll:EnableMouseWheel(true)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(childWidth or L.MAIN_W - L.PAD * 2)
    child:SetHeight(1)
    scroll:SetScrollChild(child)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = child:GetHeight() - self:GetHeight()
        if range <= 0 then return end
        local pos = self:GetVerticalScroll() - delta * 30
        self:SetVerticalScroll(math.max(0, math.min(range, pos)))
    end)

    return scroll, child
end

local function HideSliderPart(obj)
    if not obj then return end
    if obj.Hide then obj:Hide() end
    if obj.SetAlpha then obj:SetAlpha(0) end
    if obj.EnableMouse then obj:EnableMouse(false) end
    if obj.SetSize then obj:SetSize(0.001, 0.001) end
end

local function HideScrollBarTemplateParts(bar)
    if not bar then return end
    local barName = bar.GetName and bar:GetName()
    if barName then
        for _, suffix in ipairs({
            "ScrollUpButton", "ScrollDownButton", "Border",
        }) do
            HideSliderPart(_G[barName .. suffix])
        end
    end
    HideSliderPart(bar.ScrollUpButton)
    HideSliderPart(bar.ScrollDownButton)
    if bar.GetChildren then
        for i = 1, bar:GetNumChildren() do
            local child = select(i, bar:GetChildren())
            if child and child.IsObjectType and child:IsObjectType("Button") then
                local childName = (child.GetName and child:GetName()) or ""
                if childName:find("ScrollUp", 1, true) or childName:find("ScrollDown", 1, true)
                    or childName:find("UpButton", 1, true) or childName:find("DownButton", 1, true) then
                    HideSliderPart(child)
                else
                    local w, h = child:GetWidth() or 0, child:GetHeight() or 0
                    if w > 0 and w <= 18 and h > 0 and h <= 18 then
                        HideSliderPart(child)
                    end
                end
            end
        end
    end
end

local function GetScrollFrameBar(scrollFrame)
    if not scrollFrame then return nil end
    local name = scrollFrame.GetName and scrollFrame:GetName()
    if name and _G[name .. "ScrollBar"] then
        return _G[name .. "ScrollBar"]
    end
    return nil
end

function SW.RepaintVerticalScrollBar(bar)
    if not bar or not bar._siteScrollStyled then return end
    local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
    if thumb then
        thumb:SetTexture(FLAT)
        thumb:SetVertexColor(unpack(C.accentBorder55))
        thumb:SetWidth(6)
        thumb:Show()
        if thumb.SetAlpha then thumb:SetAlpha(1) end
    end
    if bar._siteTrack then
        bar._siteTrack:SetVertexColor(unpack(C.elementBg))
        bar._siteTrack:Show()
        if bar._siteTrack.SetAlpha then bar._siteTrack:SetAlpha(1) end
    end
    if bar.SetAlpha then bar:SetAlpha(1) end
end

function SW.StyleVerticalScrollBar(bar)
    if not bar then return end
    if not bar._siteScrollStyled then
        bar._siteScrollStyled = true
        SW._styledScrollBars[#SW._styledScrollBars + 1] = bar
        if EbonBuilds.ScrollWheel and EbonBuilds.ScrollWheel.SetupBar then
            EbonBuilds.ScrollWheel.SetupBar(bar)
        end
        bar:SetWidth(8)
        HideScrollBarTemplateParts(bar)
        if not bar._siteTrack then
            bar._siteTrack = SW.Fill(bar, "elementBg")
            bar._siteTrack:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            bar._siteTrack:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
        end
        if bar.HookScript and not bar._ebonScrollArrowHooked then
            bar._ebonScrollArrowHooked = true
            bar:HookScript("OnShow", function()
                HideScrollBarTemplateParts(bar)
                SW.RepaintVerticalScrollBar(bar)
            end)
        end
    end
    HideScrollBarTemplateParts(bar)
    SW.RepaintVerticalScrollBar(bar)
end

ST.OnThemeChanged(function()
    for _, bar in ipairs(SW._styledScrollBars) do
        SW.RepaintVerticalScrollBar(bar)
    end
end)

-- Updates range, child offset, and shows the bar only when content overflows.
function SW.UpdateVerticalScroll(scrollFrame, scrollChild, bar)
    if not scrollFrame or not scrollChild or not bar then return false end

    local visible = scrollFrame:GetHeight() or 0
    local content = scrollChild:GetHeight() or 0
    local overflow = math.max(0, content - visible)

    if overflow <= 0 then
        bar:Hide()
        if bar._siteTrack then bar._siteTrack:Hide() end
        bar:SetMinMaxValues(0, 0)
        bar:SetValue(0)
        if scrollFrame._fixedScrollChild then
            scrollChild:ClearAllPoints()
            scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
        elseif scrollFrame.SetVerticalScroll then
            scrollFrame:SetVerticalScroll(0)
        else
            scrollChild:ClearAllPoints()
            scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
        end
        return false
    end

    bar:Show()
    if bar._siteTrack then bar._siteTrack:Show() end
    if bar.SetFrameLevel and scrollFrame.GetFrameLevel then
        bar:SetFrameLevel((scrollFrame:GetFrameLevel() or 0) + 10)
    end
    HideScrollBarTemplateParts(bar)
    bar:SetMinMaxValues(0, overflow)
    local value = bar:GetValue() or 0
    if value > overflow then value = overflow end
    if math.abs((bar:GetValue() or 0) - value) > 0.01 then
        bar:SetValue(value)
    end
    SW.RepaintVerticalScrollBar(bar)
    if scrollFrame._fixedScrollChild then
        scrollChild:ClearAllPoints()
        scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    elseif scrollFrame.SetVerticalScroll then
        scrollFrame:SetVerticalScroll(bar:GetValue())
    else
        scrollChild:ClearAllPoints()
        scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, bar:GetValue())
    end
    return true
end

function SW.ScheduleVerticalScroll(scrollFrame, scrollChild, bar)
    SW.UpdateVerticalScroll(scrollFrame, scrollChild, bar)
    if not C_Timer or not C_Timer.After then return end
    for _, delay in ipairs({ 0, 0.05, 0.15, 0.35 }) do
        C_Timer.After(delay, function()
            if scrollFrame and scrollFrame.IsShown and scrollFrame:IsShown() then
                SW.UpdateVerticalScroll(scrollFrame, scrollChild, bar)
            end
        end)
    end
end

function SW.StyleScrollFrame(scrollFrame)
    if not scrollFrame then return end
    local bar = GetScrollFrameBar(scrollFrame)
    if bar then
        SW.StyleVerticalScrollBar(bar)
    end
end

function SW.CreateBuildHeader(parent, opts)
    opts = opts or {}
    local classToken = opts.class or "MAGE"
    local classColor = ST.CLASS_COLORS[classToken] or C.text
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(opts.height or 200)

    if opts.draggable then
        header:EnableMouse(true)
        header:SetScript("OnMouseDown", function() opts.draggable:StartMoving() end)
        header:SetScript("OnMouseUp", function() opts.draggable:StopMovingOrSizing() end)
    end

    local grad = header:CreateTexture(nil, "BACKGROUND")
    ST.ApplyClassBackgroundGradient(grad, classColor, {
        C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3],
    })
    grad:SetAllPoints(header)
    header._grad = grad

    local headerSep = header:CreateTexture(nil, "ARTWORK")
    headerSep:SetTexture(FLAT)
    headerSep:SetVertexColor(unpack(C.border))
    headerSep:SetHeight(1)
    headerSep:SetPoint("BOTTOMLEFT", 0, 0)
    headerSep:SetPoint("BOTTOMRIGHT", 0, 0)

    local classStripe = header:CreateTexture(nil, "ARTWORK")
    classStripe:SetWidth(4)
    classStripe:SetPoint("TOPLEFT", 0, 0)
    classStripe:SetPoint("BOTTOMLEFT", 0, 0)
    ST.ApplyClassStripe(classStripe, classColor)
    header._classStripe = classStripe

    local iconHolder = SW.CreateClassIconHolder(header, classToken, opts.spec, L.CLASS_ICON)
    iconHolder:SetPoint("TOPLEFT", L.PAD + 6, -L.PAD)

    local title = SW.Label(header, opts.title or "", 16, classColor, false, "semibold")
    title:SetPoint("TOPLEFT", iconHolder, "TOPRIGHT", 10, -2)
    title:SetWidth(L.SIDEBAR_W - L.PAD * 2 - 60)
    title:SetJustifyH("LEFT")

    if opts.subtitle ~= nil then
        local subtitle = SW.Label(header, opts.subtitle, 11, C.textDim)
        subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        subtitle:SetWidth(L.SIDEBAR_W - L.PAD * 2 - 58)
        subtitle:SetJustifyH("LEFT")
        subtitle:SetWordWrap(true)
        header._subtitle = subtitle
    end

    header._title = title
    header._iconHolder = iconHolder
    header._classToken = classToken
    header._spec = opts.spec

    header.SetClass = function(self, token, spec)
        self._classToken = token
        self._spec = spec
        classColor = ST.CLASS_COLORS[token] or C.text
        ST.ApplyClassBackgroundGradient(self._grad, classColor, {
            C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3],
        })
        ST.ApplyClassStripe(self._classStripe, classColor)
        SW.UpdateClassIconHolder(self._iconHolder, token, spec)

        self._title:SetTextColor(unpack(classColor))
    end
    return header
end

function SW.CreateStatCell(parent, statLabel, value)
    local cell = CreateFrame("Frame", nil, parent)
    SW.Fill(cell, "statCellBg")
    SW.ThinBorder(cell, "border", 1)
    cell:SetHeight(44)
    local lbl = SW.Label(cell, string.upper(statLabel or ""), 9, C.textMuted)
    lbl:SetPoint("TOP", 0, -6)
    local val = SW.Label(cell, value, 13, C.text, false, "semibold")
    val:SetPoint("TOP", lbl, "BOTTOM", 0, -2)
    cell._valueLabel = val
    return cell
end

function SW.CreateBadge(parent, text, variant)
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetHeight(16)
    local bgColor, textColor, borderColor
    if variant == "accent" then
        bgColor, textColor, borderColor = C.accentBg10, C.accent, C.accentBorder30
    elseif variant == "success" then
        bgColor, textColor, borderColor = C.successBg10, C.success, C.successBorder30
    else
        bgColor, textColor, borderColor = C.elementBg, C.textDim, C.border
    end
    SW.Fill(badge, bgColor)
    SW.ThinBorder(badge, borderColor, 1)
    local label = SW.Label(badge, string.upper(text or ""), 10, textColor, false, "medium")
    label:SetPoint("LEFT", 8, 0)
    label:SetPoint("RIGHT", -8, 0)
    badge:SetWidth(label:GetStringWidth() + 16)
    badge._label = label
    return badge
end

function SW.CreateAccentButton(parent, text, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(32)
    btn._bg = SW.Fill(btn, "accentBg10")
    btn._border = SW.ThinBorder(btn, "accentBorder35", 1)
    btn._label = SW.Label(btn, text, 11, C.accent, false, "medium")
    btn._label:SetPoint("CENTER")
    btn._defaultText = text

    btn.SetCopied = function(self, copied)
        self._label:SetText(copied and "Copied!" or self._defaultText)
    end

    local function SetHover(hover)
        btn._bg:SetVertexColor(unpack(hover and C.accentBg18 or C.accentBg10))
        SW.SetBorderColor(btn._border, hover and C.accentBorder55 or C.accentBorder35)
    end

    btn:SetScript("OnEnter", function() SetHover(true) end)
    btn:SetScript("OnLeave", function() SetHover(false) end)
    btn:SetScript("OnClick", function(self)
        if onClick then onClick(self) end
    end)

    SW.Track(function()
        if not btn:IsMouseOver() then
            btn._bg:SetVertexColor(unpack(C.accentBg10))
            SW.SetBorderColor(btn._border, C.accentBorder35)
            btn._label:SetTextColor(unpack(C.accent))
        end
    end)

    return btn
end

function SW.CreateOutlineButton(parent, text, width)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 72, 28)
    btn._bg = SW.Fill(btn, "elementBg")
    btn._border = SW.ThinBorder(btn, "border", 1)
    btn._label = SW.Label(btn, text, 12, C.text, false, "medium")
    btn._label:SetPoint("CENTER")
    btn:SetScript("OnEnter", function(self)
        SW.SetBorderColor(self._border, C.borderHover)
    end)
    btn:SetScript("OnLeave", function(self)
        SW.SetBorderColor(self._border, C.border)
    end)
    return btn
end

function SW.CreateEchoIcon(parent, opts)
    opts = opts or {}
    local size = opts.size or L.ICON_TIER
    local spellId = opts.spellId
    local quality = opts.quality or 2
    local name = opts.name

    if name and not spellId then
        spellId = GetSpellInfo(name)
    end

    local qColor = ST.QUALITY_BORDER[quality] or ST.QUALITY_BORDER[2]
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)

    SW.Fill(btn, "elementBg")
    btn._border = SW.ThinBorder(btn, qColor, opts.borderThickness or 2)

    local inset = opts.iconInset or 2
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", inset, -inset)
    icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if spellId then
        local _, _, tex = GetSpellInfo(spellId)
        if tex then icon:SetTexture(tex) end
    else
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    btn.icon = icon
    btn._name = name
    btn._score = opts.score

    if name then
        btn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetText(name, 1, 1, 1)
            if btn._score then
                GameTooltip:AddLine(string.format("Score: %.0f", btn._score), 0.7, 0.7, 0.7)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return btn
end

function SW.CreateListRow(parent, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(height or 28)
    SW.Fill(row, "elementBg")
    row._border = SW.ThinBorder(row, "borderSoft", 1)
    return row
end

function SW.CreateToolbarIcon(parent, iconName, onClick, size)
    size = size or 20
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size + 8, size + 8)
    btn._icon = SW.CreateIcon(btn, iconName, size, C.textDim)
    btn._icon:SetPoint("CENTER")
    btn:SetScript("OnEnter", function(self)
        self._icon:SetColor(C.text)
    end)
    btn:SetScript("OnLeave", function(self)
        self._icon:SetColor(C.textDim)
    end)
    btn:SetScript("OnClick", function()
        if onClick then onClick() end
    end)
    return btn
end

function SW.CreateNavIconButton(parent, iconName, onClick, opts)
    opts = opts or {}
    local size = opts.size or 28
    local iconSize = opts.iconSize or (iconName == "close" and 22 or 22)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)

    btn._bg = SW.Fill(btn, "bgElevated")
    btn._bg:SetAlpha(0)

    local function SetMarkColor(rgb)
        if btn._glyph then
            btn._glyph:SetTextColor(unpack(rgb))
        elseif btn._icon then
            btn._icon:SetColor(rgb)
        end
    end

    local function SetIdle()
        btn._bg:SetAlpha(0)
        SetMarkColor(C.textDim)
    end

    local function SetHover()
        btn._bg:SetAlpha(1)
        btn._bg:SetVertexColor(unpack(C.bgElevated))
        SetMarkColor(C.text)
    end

    if iconName == "close" then
        btn._glyph = SW.Label(btn, "×", iconSize, C.textDim, false, "regular")
        btn._glyph:SetPoint("CENTER", 0, 0)
    else
        btn._icon = SW.CreateIcon(btn, iconName, iconSize, C.textDim)
        btn._icon:SetPoint("CENTER")
    end

    btn:SetScript("OnEnter", SetHover)
    btn:SetScript("OnLeave", SetIdle)
    btn:SetScript("OnClick", function()
        if onClick then onClick() end
    end)

    SW.Track(function()
        if btn:IsMouseOver() then SetHover() else SetIdle() end
    end)

    return btn
end

local function HideDropDownChrome(name)
    for _, part in ipairs({ "Left", "Middle", "Right", "Icon" }) do
        local tex = _G[name .. part]
        if tex then tex:Hide() end
    end
end

local function HideButtonStateTextures(btn)
    if not btn then return end
    local normal = btn:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
    local pushed = btn:GetPushedTexture()
    if pushed then pushed:SetAlpha(0) end
    local disabled = btn:GetDisabledTexture()
    if disabled then disabled:SetAlpha(0) end
    local highlight = btn:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
end

function SW.SyncDropDownLabel(dropdown)
    if not dropdown or not dropdown._ebonSiteDropDown then return end
    local name = dropdown:GetName()
    if not name then return end
    local btn = _G[name .. "Button"]
    if not btn or not btn._siteLabel then return end
    local blizz = _G[name .. "Text"] or _G[name .. "ButtonText"]
    local txt = blizz and blizz:GetText() or ""
    btn._siteLabel:SetText(txt)
    if blizz then blizz:Hide() end
end

local dropDownListSkinned = false
local LIST_BTN_H_DEFAULT = 16
local LIST_BTN_H_SITE = 24

local function IsEbonDropDown(dropdown)
    return dropdown and dropdown._ebonSiteDropDown == true
end

local function restoreListButton(btn)
    if not btn or not btn._siteListStyled then return end
    btn._siteListStyled = nil
    btn:SetHeight(LIST_BTN_H_DEFAULT)
    local normal = btn:GetNormalTexture()
    if normal then normal:SetAlpha(1) end
    local highlight = btn:GetHighlightTexture()
    if highlight then highlight:SetAlpha(1) end
    if btn._siteHi then btn._siteHi:Hide() end
    local check = _G[btn:GetName() .. "Check"]
    if check then
        check:SetVertexColor(1, 1, 1, 1)
    end
    local nameText = _G[btn:GetName() .. "NormalText"]
    if nameText then
        nameText:SetFontObject("GameFontHighlightSmall")
        if btn._siteOrigTextColor then
            nameText:SetTextColor(unpack(btn._siteOrigTextColor))
        end
    end
end

local function styleListButton(btn)
    if not btn or not IsEbonDropDown(UIDROPDOWNMENU_OPEN_MENU) then return end
    btn:SetHeight(LIST_BTN_H_SITE)
    local normal = btn:GetNormalTexture()
    if normal then normal:SetAlpha(0) end
    local highlight = btn:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end

    if not btn._siteHi then
        btn._siteHi = btn:CreateTexture(nil, "BACKGROUND")
        btn._siteHi:SetTexture(FLAT)
        btn._siteHi:SetVertexColor(unpack(C.accentBg12))
        btn._siteHi:Hide()

        btn:HookScript("OnEnter", function(self)
            if not IsEbonDropDown(UIDROPDOWNMENU_OPEN_MENU) then return end
            local nameText = _G[self:GetName() .. "NormalText"]
            if self._siteHi and nameText then
                self._siteHi:ClearAllPoints()
                self._siteHi:SetPoint("TOPLEFT", nameText, "TOPLEFT", -6, -1)
                self._siteHi:SetPoint("BOTTOMRIGHT", nameText, "BOTTOMRIGHT", 6, 1)
                self._siteHi:Show()
            end
        end)
        btn:HookScript("OnLeave", function(self)
            if self._siteHi then self._siteHi:Hide() end
        end)
    else
        btn._siteHi:SetVertexColor(unpack(C.accentBg12))
    end

    local check = _G[btn:GetName() .. "Check"]
    if check then
        check:SetVertexColor(unpack(C.accent))
    end

    local nameText = _G[btn:GetName() .. "NormalText"]
    if nameText then
        if not btn._siteOrigTextColor then
            local r, g, b = nameText:GetTextColor()
            btn._siteOrigTextColor = { r, g, b }
        end
        SW.SetFont(nameText, 11, "regular")
        nameText:SetTextColor(unpack(C.text))
    end

    btn._siteListStyled = true
end

local function setListBorderVisible(borders, visible)
    if not borders then return end
    for _, tex in ipairs(borders) do
        if visible then tex:Show() else tex:Hide() end
    end
end

local function applyListChrome(list, enabled)
    if not list then return end
    if enabled then
        if not list._siteBg then
            list._siteBg = SW.Fill(list, "bgElevated")
            list._siteBorder = SW.ThinBorder(list, "border", 1)
        end
        list._siteBg:Show()
        setListBorderVisible(list._siteBorder, true)
    else
        if list._siteBg then list._siteBg:Hide() end
        setListBorderVisible(list._siteBorder, false)
    end
end

local function restoreList(list)
    if not list then return end
    applyListChrome(list, false)
    local listName = list:GetName()
    if not listName then return end
    for j = 1, (UIDROPDOWNMENU_MAXBUTTONS or 32) do
        local btn = _G[listName .. "Button" .. j]
        if btn then btn:SetHeight(LIST_BTN_H_DEFAULT) end
        restoreListButton(btn)
    end
end

local function refreshOpenDropDownList(list)
    if not list or not list:IsShown() then return end
    if not IsEbonDropDown(UIDROPDOWNMENU_OPEN_MENU) then return end
    list._ebonListWasStyled = true
    applyListChrome(list, true)
    local listName = list:GetName()
    if not listName then return end
    for j = 1, (UIDROPDOWNMENU_MAXBUTTONS or 32) do
        styleListButton(_G[listName .. "Button" .. j])
    end
end

local function refreshOpenDropDownLists()
    for i = 1, (UIDROPDOWNMENU_MAXLEVELS or 2) do
        refreshOpenDropDownList(_G["DropDownList" .. i])
    end
end

function SW.EnsureDropDownListSkin()
    if dropDownListSkinned then return end
    dropDownListSkinned = true

    for i = 1, (UIDROPDOWNMENU_MAXLEVELS or 2) do
        local list = _G["DropDownList" .. i]
        if list and not list._ebonSkinHook then
            list._ebonSkinHook = true
            list:HookScript("OnShow", function(self)
                if IsEbonDropDown(UIDROPDOWNMENU_OPEN_MENU) then
                    refreshOpenDropDownList(self)
                else
                    restoreList(self)
                end
            end)
            list:HookScript("OnHide", function(self)
                restoreList(self)
                self._ebonListWasStyled = nil
            end)
        end
    end

    ST.OnThemeChanged(refreshOpenDropDownLists)
end

if not SW._dropDownSetTextHooked and hooksecurefunc then
    SW._dropDownSetTextHooked = true
    hooksecurefunc("UIDropDownMenu_SetText", function(dropdown)
        SW.SyncDropDownLabel(dropdown)
    end)
end

local CHEVRON_IMPL = 3

local function CreateDropdownChevron(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(10, 6)
    frame._siteChevronImpl = CHEVRON_IMPL
    frame._bars = {}

    local px = 1.6
    local rows = {
        { -3.2, -1.6, 0, 1.6, 3.2 },
        { -1.6, 0, 1.6 },
        { 0 },
    }
    local y = 2
    for r = 1, #rows do
        local cols = rows[r]
        for c = 1, #cols do
            local dot = frame:CreateTexture(nil, "OVERLAY")
            dot:SetTexture(FLAT)
            dot:SetSize(px, px)
            dot:SetPoint("CENTER", frame, "CENTER", cols[c], y)
            frame._bars[#frame._bars + 1] = dot
        end
        y = y - 2
    end

    return frame
end

local function RepaintDropdownChevron(chevron)
    if not chevron or not chevron._bars then return end
    local r, g, b = unpack(C.textMuted)
    for i = 1, #chevron._bars do
        chevron._bars[i]:SetVertexColor(r, g, b)
    end
end

function SW.AttachDropdownChevron(parent, label, opts)
    opts = opts or {}
    local inset = opts.inset or 10
    local gap = opts.gap or 6
    local chevron = parent._siteChevron
    if chevron and chevron._siteChevronImpl ~= CHEVRON_IMPL then
        if chevron.Hide then chevron:Hide() end
        chevron = nil
        parent._siteChevron = nil
    end
    if not chevron then
        chevron = CreateDropdownChevron(parent)
        parent._siteChevron = chevron
        SW.Track(function() RepaintDropdownChevron(parent._siteChevron) end)
    end
    RepaintDropdownChevron(chevron)
    chevron:Show()
    chevron:ClearAllPoints()
    chevron:SetPoint("RIGHT", parent, "RIGHT", -inset, 0)
    if label then
        label:ClearAllPoints()
        label:SetPoint("LEFT", parent, "LEFT", inset, 0)
        label:SetPoint("RIGHT", chevron, "LEFT", -gap, 0)
        if not opts.keepLabelAlign then
            label:SetJustifyH("LEFT")
        end
    end
    return chevron
end

function SW.StyleUIDropDown(dropdown, width)
    if not dropdown then return end
    dropdown._ebonSiteDropDown = true
    width = width or 120
    UIDropDownMenu_SetWidth(dropdown, width)
    dropdown:SetHeight(28)
    local name = dropdown:GetName()
    if not name then return end

    SW.EnsureDropDownListSkin()
    HideDropDownChrome(name)

    local btn = _G[name .. "Button"]
    local text = _G[name .. "Text"] or _G[name .. "ButtonText"]
    if btn then
        HideDropDownChrome(name .. "Button")
        local btnIcon = _G[name .. "ButtonIcon"]
        if btnIcon then btnIcon:Hide() end

        btn:SetHeight(28)
        btn:SetWidth(width)
        HideButtonStateTextures(btn)

        if not btn._siteStyled then
            btn._siteBg = SW.Fill(btn, "elementBg")
            btn._siteBorder = SW.ThinBorder(btn, "border", 1)
            btn._siteLabel = SW.Label(btn, "", 11, C.text)
            SW.AttachDropdownChevron(btn, btn._siteLabel)
            btn:SetScript("OnEnter", function(self)
                SW.SetBorderColor(self._siteBorder, C.borderHover)
                self._siteBg:SetVertexColor(unpack(C.bgElevated))
            end)
            btn:SetScript("OnLeave", function(self)
                SW.SetBorderColor(self._siteBorder, C.border)
                self._siteBg:SetVertexColor(unpack(C.elementBg))
            end)
            btn._siteStyled = true
        end
    end

    if text then
        SW.SetFont(text, 11, "regular")
        text:SetTextColor(unpack(C.text))
        text:Hide()
    end

    SW.SyncDropDownLabel(dropdown)
end

------------------------------------------------------------------------
-- Site-styled popup menus (policy-like; not Blizzard DropDownList)
------------------------------------------------------------------------

local siteMenuPopup
local siteMenuOpenFor
local siteMenuSpec

local MENU_PAD_X = 10
local MENU_PAD_Y = 6
local MENU_ROW_H = 22
local MENU_ROW_H_DESC = 32
local MENU_ROW_GAP = 2
local MENU_HI_PAD_X = 6
local MENU_HI_PAD_Y = 2

local function FindMenuWindowFrame(anchor)
    local p = anchor
    while p do
        if p.GetName and p:GetName() == "EbonBuildsMainWindow" then
            return p
        end
        p = p:GetParent()
    end
    if EbonBuilds.MainWindow and EbonBuilds.MainWindow._frame then
        return EbonBuilds.MainWindow._frame
    end
    return UIParent
end

local function AnchorMenuHighlight(hi, topAnchor, bottomAnchor)
    hi:ClearAllPoints()
    hi:SetPoint("TOPLEFT", topAnchor, "TOPLEFT", -MENU_HI_PAD_X, MENU_HI_PAD_Y)
    hi:SetPoint("BOTTOMRIGHT", bottomAnchor, "BOTTOMRIGHT", MENU_HI_PAD_X, -MENU_HI_PAD_Y)
end

function SW.HideSiteMenuPopup()
    if not siteMenuPopup then return end
    if siteMenuPopup._root then
        siteMenuPopup._root:Hide()
    end
    siteMenuOpenFor = nil
    siteMenuSpec = nil
end

local function AcquireMenuRow(parent, index)
    local popup = siteMenuPopup
    if not popup._rows[index] then
        local row = CreateFrame("Button", nil, parent)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row._highlight = row:CreateTexture(nil, "BACKGROUND")
        row._highlight:SetTexture(FLAT)
        row._highlight:SetVertexColor(unpack(C.accentBg12))
        row._highlight:Hide()

        row._label = SW.Label(row, "", 11, C.text)
        row._label:SetPoint("LEFT", row, "LEFT", MENU_PAD_X, 0)
        row._label:SetJustifyH("LEFT")

        row._desc = SW.Label(row, "", 10, C.textMuted)
        row._desc:SetPoint("TOPLEFT", row._label, "BOTTOMLEFT", 0, -1)
        row._desc:SetPoint("RIGHT", row, "RIGHT", -MENU_PAD_X, 0)
        row._desc:SetJustifyH("LEFT")
        row._desc:Hide()

        row._check = SW.Label(row, "✓", 11, C.accent)
        row._check:SetPoint("RIGHT", row, "RIGHT", -MENU_PAD_X, 0)
        row._check:Hide()

        popup._rows[index] = row
    end
    return popup._rows[index]
end

local function LayoutSiteMenuPopup(spec)
    local popup = siteMenuPopup
    local rows = spec.rows or {}
    local width = spec.width or 160
    popup:SetWidth(width)

    local y = -MENU_PAD_Y
    local visible = 0
    for i = 1, #rows do
        local def = rows[i]
        local row = AcquireMenuRow(popup, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, y)
        row._rowDef = def
        row._desc:Hide()
        row._check:Hide()
        row:EnableMouse(def.kind ~= "header")
        row._highlight:Hide()

        if def.kind == "header" then
            row:SetHeight(18)
            row._label:SetText(def.text or "")
            row._label:SetTextColor(unpack(C.textMuted))
            row._label:SetPoint("LEFT", row, "LEFT", MENU_PAD_X, 0)
            AnchorMenuHighlight(row._highlight, row._label, row._label)
        elseif def.desc and def.desc ~= "" then
            row:SetHeight(MENU_ROW_H_DESC)
            row._label:SetText(def.text or "")
            row._label:SetTextColor(unpack(C.text))
            row._label:SetPoint("TOPLEFT", row, "TOPLEFT", MENU_PAD_X, -4)
            row._label:SetPoint("RIGHT", row, "RIGHT", -MENU_PAD_X, 0)
            row._desc:SetText(def.desc)
            row._desc:Show()
            AnchorMenuHighlight(row._highlight, row._label, row._desc)
        else
            row:SetHeight(MENU_ROW_H)
            row._label:SetText(def.text or "")
            row._label:SetTextColor(unpack(C.text))
            row._label:SetPoint("LEFT", row, "LEFT", MENU_PAD_X, 0)
            row._label:SetPoint("RIGHT", row, "RIGHT", -(MENU_PAD_X + 14), 0)
            if def.checked then
                row._check:Show()
            end
            AnchorMenuHighlight(row._highlight, row._label, row._label)
        end

        row:SetScript("OnEnter", function(self)
            if self._rowDef and self._rowDef.kind ~= "header" then
                self._highlight:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            self._highlight:Hide()
        end)
        row:SetScript("OnClick", function(self, button)
            if button ~= "LeftButton" then return end
            local d = self._rowDef
            if not d or d.kind == "header" or not d.onClick then return end
            d.onClick()
            if siteMenuOpenFor and siteMenuSpec and not siteMenuSpec.keepOpen then
                SW.HideSiteMenuPopup()
            elseif siteMenuOpenFor and siteMenuSpec then
                siteMenuSpec.rows = siteMenuSpec.buildRows and siteMenuSpec.buildRows() or siteMenuSpec.rows
                LayoutSiteMenuPopup(siteMenuSpec)
            end
        end)

        row:Show()
        visible = visible + 1
        local rowH = row:GetHeight()
        y = y - rowH - MENU_ROW_GAP
    end

    for j = visible + 1, #(popup._rows or {}) do
        if popup._rows[j] then popup._rows[j]:Hide() end
    end

    local height = MENU_PAD_Y + math.abs(y) - MENU_ROW_GAP + MENU_PAD_Y
    popup:SetHeight(math.max(1, height))
end

local function EnsureSiteMenuPopup()
    if siteMenuPopup and siteMenuPopup._siteStyled then
        return siteMenuPopup
    end

    local root = CreateFrame("Frame", "EbonBuildsSiteMenuRoot", UIParent)
    root:SetFrameStrata("DIALOG")
    root:SetToplevel(true)
    root:Hide()

    local backdrop = CreateFrame("Button", nil, root)
    backdrop:SetFrameLevel(1)
    backdrop:SetAllPoints(root)
    backdrop:RegisterForClicks("AnyUp")
    backdrop:SetScript("OnClick", SW.HideSiteMenuPopup)

    local panel = CreateFrame("Frame", "EbonBuildsSiteMenuPopup", root)
    panel:SetFrameLevel(10)
    panel:EnableMouse(true)
    SW.Fill(panel, "bgElevated")
    panel._border = SW.ThinBorder(panel, "border", 1)
    panel:SetScript("OnMouseDown", function() end)
    panel._root = root
    panel._backdrop = backdrop
    panel._rows = {}
    panel._siteStyled = true
    siteMenuPopup = panel
    return panel
end

function SW.ShowSiteMenuPopup(anchor, spec)
    if not anchor or not spec then return end
    local popup = EnsureSiteMenuPopup()
    local root = popup._root
    siteMenuOpenFor = anchor
    siteMenuSpec = spec

    local win = FindMenuWindowFrame(anchor)
    root:SetParent(win)
    root:ClearAllPoints()
    root:SetAllPoints(win)
    root:SetFrameLevel((win.GetFrameLevel and win:GetFrameLevel() or 0) + 50)

    if spec.buildRows then
        spec.rows = spec.buildRows()
    end
    LayoutSiteMenuPopup(spec)

    popup:ClearAllPoints()
    popup:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)

    root:Show()
    popup._backdrop:Show()
    popup:Show()
    if popup.Raise then popup:Raise() end
end

function SW.CreateSiteMenu(parent, opts)
    opts = opts or {}
    local width = opts.width or 120
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, 28)

    local btn = CreateFrame("Button", nil, frame)
    btn:SetAllPoints(frame)
    btn._siteBg = SW.Fill(btn, "elementBg")
    btn._siteBorder = SW.ThinBorder(btn, "border", 1)
    btn._siteLabel = SW.Label(btn, opts.defaultLabel or "", 11, C.text)
    SW.AttachDropdownChevron(btn, btn._siteLabel)
    btn:SetScript("OnEnter", function(self)
        SW.SetBorderColor(self._siteBorder, C.borderHover)
        self._siteBg:SetVertexColor(unpack(C.bgElevated))
    end)
    btn:SetScript("OnLeave", function(self)
        SW.SetBorderColor(self._siteBorder, C.border)
        self._siteBg:SetVertexColor(unpack(C.elementBg))
    end)

    function frame:SetMenuLabel(text)
        btn._siteLabel:SetText(text or "")
    end

    function frame:RefreshLabel()
        if opts.getLabel then
            frame:SetMenuLabel(opts.getLabel())
        end
    end

    btn:SetScript("OnClick", function()
        if siteMenuOpenFor == frame then
            SW.HideSiteMenuPopup()
            return
        end
        SW.HideSiteMenuPopup()
        SW.ShowSiteMenuPopup(frame, {
            width = opts.menuWidth or width,
            keepOpen = opts.keepOpen,
            buildRows = opts.buildRows,
            rows = opts.rows,
        })
    end)

    frame._siteMenuBtn = btn
    frame:RefreshLabel()
    return frame
end

function SW.CreateSearchBox(parent, placeholder, onChange)
    local box = CreateFrame("Frame", nil, parent)
    box:SetHeight(28)
    SW.Fill(box, "elementBg")
    box._border = SW.ThinBorder(box, "border", 1)

    local edit = CreateFrame("EditBox", nil, box)
    edit:SetHeight(20)
    edit:SetPoint("LEFT", box, "LEFT", 8, 0)
    edit:SetPoint("RIGHT", box, "RIGHT", -8, 0)
    edit:SetFont(ST.FONT.regular, 11, "")
    edit:SetTextColor(unpack(C.text))
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(60)
    if placeholder then
        edit:SetText(placeholder)
        edit:SetTextColor(unpack(C.textMuted))
    end
    edit:SetScript("OnEditFocusGained", function(self)
        if placeholder and self:GetText() == placeholder then
            self:SetText("")
            self:SetTextColor(unpack(C.text))
        end
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        if placeholder and self:GetText() == "" then
            self:SetText(placeholder)
            self:SetTextColor(unpack(C.textMuted))
        end
    end)
    edit:SetScript("OnTextChanged", function(self)
        local t = self:GetText()
        if placeholder and t == placeholder then t = "" end
        if onChange then onChange(t) end
    end)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box._edit = edit
    return box, edit
end

function SW.CreateNumericEditBox(parent, opts)
    opts = opts or {}
    local width = opts.width or 42
    local height = opts.height or 22

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, height)
    container._bg = SW.Fill(container, "elementBg")
    container._border = SW.ThinBorder(container, "border", 1)

    local edit = CreateFrame("EditBox", nil, container)
    edit:SetHeight(math.max(16, height - 4))
    edit:SetPoint("LEFT", container, "LEFT", 4, 0)
    edit:SetPoint("RIGHT", container, "RIGHT", -4, 0)
    SW.SetFont(edit, 11, "regular")
    edit:SetTextColor(unpack(C.text))
    edit:SetJustifyH(opts.justifyH or "CENTER")
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(opts.maxLetters or 6)
    if opts.numeric then
        edit:SetNumeric(true)
    end

    local allowNegative = opts.allowNegative
    local allowDecimal = opts.allowDecimal
    if allowNegative or allowDecimal then
        edit:SetScript("OnChar", function(self, char)
            if char == "\127" or char == "\008" or char == "" then return end
            local valid = (char >= "0" and char <= "9")
            if allowDecimal and char == "." then
                local text = self:GetText()
                if not text:find("%.") then valid = true end
            end
            if allowNegative and char == "-" then
                if self:GetCursorPosition() == 0 then valid = true end
            end
            if not valid then
                local pos = self:GetCursorPosition()
                local text = self:GetText()
                self:SetText(string.sub(text, 1, pos) .. string.sub(text, pos + 2))
                self:SetCursorPosition(pos)
            end
        end)
    end

    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    if opts.onEnterPressed then
        edit:SetScript("OnEnterPressed", opts.onEnterPressed)
    else
        edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    end
    if opts.onFocusLost then
        edit:SetScript("OnEditFocusLost", opts.onFocusLost)
    end

    container._edit = edit
    return container, edit
end

function SW.CreateModeToggleButton(parent, opts)
    opts = opts or {}
    local size = opts.size or 22
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    if opts.x ~= nil and opts.y ~= nil then
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.x, opts.y)
    end

    btn._bg = SW.Fill(btn, "elementBg")
    btn._border = SW.ThinBorder(btn, "border", 1)
    btn._label = SW.Label(btn, "+", 11, C.textDim, false, "medium")
    btn._label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.modeLabel = btn._label
    btn.multiplicative = false

    local function Repaint()
        if btn.multiplicative then
            btn._bg:SetVertexColor(unpack(C.accentBg12))
            SW.SetBorderColor(btn._border, C.accentBorder35)
            btn._label:SetText("x")
            btn._label:SetTextColor(unpack(C.accent))
        else
            btn._bg:SetVertexColor(unpack(C.elementBg))
            SW.SetBorderColor(btn._border, C.border)
            btn._label:SetText("+")
            btn._label:SetTextColor(unpack(C.textDim))
        end
    end

    function btn:SetMultiplicative(on)
        self.multiplicative = on and true or false
        Repaint()
    end

    btn:SetScript("OnEnter", function(self)
        if self.multiplicative then
            SW.SetBorderColor(self._border, C.accentBorder55)
            self._bg:SetVertexColor(unpack(C.accentBg18))
        else
            SW.SetBorderColor(self._border, C.borderHover)
            self._bg:SetVertexColor(unpack(C.bgElevated))
            self._label:SetTextColor(unpack(C.text))
        end
    end)
    btn:SetScript("OnLeave", function(self)
        Repaint()
    end)
    btn:SetScript("OnClick", function(self)
        self.multiplicative = not self.multiplicative
        Repaint()
        if self.onToggle then self.onToggle() end
    end)

    SW.Track(Repaint)
    Repaint()
    return btn
end

function SW.CreateCheckbox(parent, opts)
    opts = opts or {}
    local size = opts.size or 16
    local displayOnly = opts.displayOnly == true

    local box
    if displayOnly then
        box = CreateFrame("Frame", nil, parent)
    else
        box = CreateFrame("Button", nil, parent)
    end
    box:SetSize(size, size)

    box._bg = SW.Fill(box, "elementBg")
    box._border = SW.ThinBorder(box, "border", 1)

    local markSize = opts.markSize or math.max(9, math.floor(size * 0.75))
    box._mark = box:CreateTexture(nil, "OVERLAY")
    box._mark:SetSize(markSize, markSize)
    box._mark:SetPoint("CENTER", 0, 0)
    box._mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    box._mark:Hide()

    box._checked = false
    box._markColor = C.accent

    local function repaint()
        if box._checked then
            box._mark:Show()
            box._mark:SetVertexColor(unpack(box._markColor))
            box._bg:SetVertexColor(unpack(C.accentBg12))
            SW.SetBorderColor(box._border, C.accentBorder35)
        else
            box._mark:Hide()
            box._bg:SetVertexColor(unpack(C.elementBg))
            SW.SetBorderColor(box._border, C.border)
        end
    end

    function box:SetChecked(checked)
        self._checked = checked and true or false
        repaint()
    end

    function box:GetChecked()
        return self._checked
    end

    function box:SetMarkColor(color)
        if type(color) == "table" then
            self._markColor = color
        end
        if self._checked then
            repaint()
        end
    end

    if not displayOnly then
        box:SetScript("OnClick", function(self)
            self:SetChecked(not self:GetChecked())
            if opts.onChange then
                opts.onChange(self, self:GetChecked())
            end
        end)
        box:SetScript("OnEnter", function(self)
            SW.SetBorderColor(self._border, C.borderHover)
            if not self._checked then
                self._bg:SetVertexColor(unpack(C.bgElevated))
            end
        end)
        box:SetScript("OnLeave", function(self)
            repaint()
        end)
    end

    SW.Track(repaint)

    if opts.checked then
        box:SetChecked(true)
    end
    if opts.markColor then
        box:SetMarkColor(opts.markColor)
    end

    return box
end

function SW.CreateLabeledCheckbox(parent, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(opts.height or 20)

    local box = SW.CreateCheckbox(row, {
        size = opts.size or 16,
        displayOnly = opts.displayOnly,
        checked = opts.checked,
        markColor = opts.markColor,
        onChange = opts.onChange,
    })
    box:SetPoint("LEFT", row, "LEFT", 0, 0)
    row._checkbox = box

    if opts.label then
        local lbl = SW.Label(row, opts.label, opts.labelSize or 11, opts.labelColor or C.textDim)
        lbl:SetPoint("LEFT", box, "RIGHT", opts.gap or 6, 0)
        lbl:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        lbl:SetJustifyH("LEFT")
        row._label = lbl
    end

    function row:SetChecked(checked)
        self._checkbox:SetChecked(checked)
    end

    function row:GetChecked()
        return self._checkbox:GetChecked()
    end

    function row:SetMarkColor(color)
        self._checkbox:SetMarkColor(color)
    end

    return row
end

function SW.CreateFilterChip(parent, text)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(24)
    btn._bg = SW.Fill(btn, "elementBg")
    btn._border = SW.ThinBorder(btn, "border", 1)
    btn._label = SW.Label(btn, text or "", 10, C.textDim, false, "medium")
    btn._label:SetPoint("LEFT", 8, 0)
    btn._label:SetPoint("RIGHT", -8, 0)
    btn:SetWidth(btn._label:GetStringWidth() + 16)

    function btn:SetChipActive(active)
        self._active = active
        if active then
            self._bg:SetVertexColor(unpack(C.accentBg12))
            SW.SetBorderColor(self._border, C.accentBorder35)
            self._label:SetTextColor(unpack(C.accent))
        else
            self._bg:SetVertexColor(unpack(C.elementBg))
            SW.SetBorderColor(self._border, C.border)
            self._label:SetTextColor(unpack(C.textDim))
        end
    end

    btn:SetScript("OnEnter", function(self)
        if not self._active then
            SW.SetBorderColor(self._border, C.borderHover)
            self._label:SetTextColor(unpack(C.text))
        end
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetChipActive(self._active)
    end)

    SW.Track(function()
        btn:SetChipActive(btn._active)
    end)

    return btn
end

local triStateChipMeasureFS

local CHIP_INSET_LEFT  = 8
local CHIP_CHECK_W     = 12
local CHIP_GAP         = 6
local CHIP_INSET_RIGHT = 10
local CHIP_LABEL_PAD   = CHIP_INSET_LEFT + CHIP_CHECK_W + CHIP_GAP + CHIP_INSET_RIGHT + 8

local function MeasureTriStateChipWidth(labelVariants)
    if not triStateChipMeasureFS then
        triStateChipMeasureFS = UIParent:CreateFontString(nil, "ARTWORK")
        SW.SetFont(triStateChipMeasureFS, 10, "medium")
    end
    triStateChipMeasureFS:Show()
    local maxW = 0
    for _, text in ipairs(labelVariants) do
        triStateChipMeasureFS:SetText(text)
        maxW = math.max(maxW, triStateChipMeasureFS:GetStringWidth() or 0)
    end
    triStateChipMeasureFS:Hide()
    return math.max(120, math.ceil(maxW) + CHIP_LABEL_PAD)
end

function SW.CreateTriStateFilterChip(parent, defaultLabel, onClick, tooltipTitle, tooltipFn, labelVariants)
    local chip = CreateFrame("Button", nil, parent)
    chip:SetHeight(26)
    chip._bg = SW.Fill(chip, "elementBg")
    chip._border = SW.ThinBorder(chip, "border", 1)

    local markBox = SW.CreateCheckbox(chip, { size = CHIP_CHECK_W, displayOnly = true })
    markBox:SetPoint("LEFT", chip, "LEFT", CHIP_INSET_LEFT, 0)
    chip._checkbox = markBox

    local lbl = SW.Label(chip, defaultLabel, 10, C.textDim)
    lbl:SetPoint("CENTER", chip, "CENTER", 0, 0)
    lbl:SetJustifyH("CENTER")
    if lbl.SetWordWrap then lbl:SetWordWrap(false) end
    if lbl.SetMaxLines then lbl:SetMaxLines(1) end
    chip._label = lbl

    local variants = labelVariants or { defaultLabel }
    chip._fixedWidth = MeasureTriStateChipWidth(variants)

    chip:SetScript("OnClick", onClick)
    chip:SetScript("OnEnter", function(self)
        SW.SetBorderColor(self._border, C.borderHover)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tooltipTitle, 1, 0.82, 0)
        if tooltipFn then tooltipFn() end
        GameTooltip:AddLine("Click to cycle filter.", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    chip:SetScript("OnLeave", function(self)
        SW.SetBorderColor(self._border, C.border)
        GameTooltip:Hide()
    end)

    function chip:SetChipWidth()
        self:SetWidth(self._fixedWidth)
    end
    chip:SetChipWidth()
    return chip
end

function SW.WrapContentCard(parent, inset)
    inset = inset or 0
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
    card:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, inset)
    SW.Fill(card, "mainBg")
    SW.ThinBorder(card, "borderSoft", 1)
    return card
end
