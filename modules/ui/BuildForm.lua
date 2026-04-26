-- EbonBuilds: modules/ui/BuildForm.lua
-- Responsibility: create/edit build form with class, spec, title, comments,
-- and 4 indicative permanent-echo slots. Declarative/widget-layout heavy:
-- template-file exception applies, so the 200-line hard limit is waived here.

EbonBuilds.BuildForm = {}

local classChangeCallbacks = {}

local function NotifyClassChange()
    for i = 1, #classChangeCallbacks do classChangeCallbacks[i]() end
end

function EbonBuilds.BuildForm.OnClassChanged(fn)
    classChangeCallbacks[#classChangeCallbacks + 1] = fn
end

local CLASS_ORDER = {
    "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST",
    "DEATHKNIGHT","SHAMAN","MAGE","WARLOCK","DRUID",
}
local CLASS_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"
local QUALITY_COLOR = {
    [0]="ffffff",[1]="19ff19",[2]="0066ff",[3]="cc66ff",[4]="ff8000",
}
local QUALITY_BORDER_COLORS = {
    [0] = { 1.0, 1.0, 1.0 },
    [1] = { 30/255, 1.0, 0.0 },
    [2] = { 0.0, 112/255, 221/255 },
    [3] = { 163/255, 53/255, 238/255 },
    [4] = { 1.0, 128/255, 0.0 },
}

local viewFrame
local state = {
    mode     = "create",
    id       = nil,
    title    = "",
    class    = nil,
    spec     = 1,
    comments = "",
    permanent = { nil, nil, nil, nil },
    settings  = nil,
}
function EbonBuilds.BuildForm.GetEditingClass()
    return state.class
end
function EbonBuilds.BuildForm.GetEditingSettings()
    if not state.settings then
        state.settings = EbonBuilds.Build.DefaultSettings()
    end
    return state.settings
end

function EbonBuilds.BuildForm.GetEditingPermanentEchoes()
    if not state.mode then return nil end
    return state.permanent
end

local classButtons = {}
local specButtons  = {}
local slotButtons  = {}
local titleBox, commentsBox

-- Global single-install hook: shift-click links go into the comments editbox
-- when it is focused. Guarded so we never install twice.
local _linkHookInstalled = false

local function InstallLinkHook()
    if _linkHookInstalled then return end
    _linkHookInstalled = true
    if not ChatEdit_InsertLink then return end
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if not link then return end
        local focus = GetCurrentKeyBoardFocus()
        if focus and focus == commentsBox then
            commentsBox:Insert(link)
        end
    end)
end

------------------------------------------------------------------------
-- Widget helpers
------------------------------------------------------------------------

local function SetClassIcon(tex, classToken)
    local coords = CLASS_ICON_TCOORDS[classToken]
    tex:SetTexture(CLASS_TEXTURE)
    if coords then tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
end

local function HighlightBorder(btn, on)
    if not btn._border then
        local b = btn:CreateTexture(nil, "OVERLAY")
        b:SetAllPoints(btn)
        b:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        b:SetBlendMode("ADD")
        b:Hide()
        btn._border = b
    end
    if on then btn._border:Show() else btn._border:Hide() end
end

local function RefreshClassSelection()
    for token, btn in pairs(classButtons) do
        HighlightBorder(btn, token == state.class)
    end
end

local function RefreshSpecButtons()
    local specs = state.class and EbonBuilds.SpecData and EbonBuilds.SpecData[state.class]
    for i = 1, 3 do
        local btn = specButtons[i]
        local entry = specs and specs[i]
        local icon  = entry and entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
        local name  = entry and entry.name or ("Spec " .. i)
        if btn._icon then btn._icon:SetTexture(icon) end
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(name)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        HighlightBorder(btn, i == state.spec)
    end
end

local function CreateIconButton(parent, size)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetWidth(size)
    btn:SetHeight(size)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn._icon = icon
    return btn
end

------------------------------------------------------------------------
-- Class grid
------------------------------------------------------------------------

local function BuildClassGrid(parent, xAnchor, yAnchor)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", xAnchor, yAnchor)
    label:SetText("Class:")
    for i, token in ipairs(CLASS_ORDER) do
        local btn = CreateIconButton(parent, 28)
        SetClassIcon(btn._icon, token)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xAnchor + 56 + (i - 1) * 30, yAnchor + 6)
        btn:SetScript("OnClick", function()
            if state.class == token then return end
            state.class = token
            if state.spec > 3 then state.spec = 1 end
            RefreshClassSelection()
            RefreshSpecButtons()
            NotifyClassChange()
        end)
        classButtons[token] = btn
    end
end

local function BuildSpecGrid(parent, xAnchor, yAnchor)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", xAnchor, yAnchor)
    label:SetText("Spec:")
    for i = 1, 3 do
        local btn = CreateIconButton(parent, 36)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xAnchor + 56 + (i - 1) * 40, yAnchor + 6)
        btn:SetScript("OnClick", function()
            state.spec = i
            RefreshSpecButtons()
        end)
        specButtons[i] = btn
    end
end

------------------------------------------------------------------------
-- Title + Comments + Permanent Echoes
------------------------------------------------------------------------

local function CreateBackdropEditBox(parent, width, height, multi)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(width, height)
    c:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    c:SetBackdropColor(0, 0, 0, 0.6)
    c:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local box = CreateFrame("EditBox", nil, c)
    box:SetPoint("TOPLEFT",     c, "TOPLEFT",     4,  -4)
    box:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -4,  4)
    box:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    box:SetTextColor(1, 1, 1, 1)
    box:SetAutoFocus(false)
    if multi then
        box:SetMultiLine(true)
        box:SetMaxLetters(0)
        box:EnableMouse(true)
    else
        box:SetMaxLetters(40)
    end
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box, c
end

local function BuildTitleField(parent, x, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lbl:SetText("Title:")
    local box = CreateBackdropEditBox(parent, 300, 22, false)
    box:GetParent():SetPoint("TOPLEFT", parent, "TOPLEFT", x + 56, y + 6)
    titleBox = box
end

local function BuildPermanentSlots(parent, x, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lbl:SetText("Permanent Echoes:")
    for i = 1, 4 do
        local btn = CreateIconButton(parent, 36)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 140 + (i - 1) * 44, y + 6)
        btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
        btn.spellId = nil
        btn:EnableMouse(true)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        EbonBuilds.EchoTableRows.WireIconTooltip(btn)

        local border = btn:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -2,  2)
        border:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  2, -2)
        border:Hide()
        btn._qualityBorder = border

        btn:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                state.permanent[i] = nil
                btn.spellId = nil
                btn._quality = nil
                btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
                btn._qualityBorder:Hide()
                return
            end
            local settings = EbonBuilds.BuildForm.GetEditingSettings()
            local banList = settings and settings.echoBanList or {}
            local allList = EbonBuilds.EchoTableRows.BuildAllQualitiesList()
            local filtered = {}
            for _, entry in ipairs(allList) do
                if not banList[entry.spellId] then
                    filtered[#filtered + 1] = entry
                end
            end
            EbonBuilds.EchoPicker.Show(function(spellId, quality, name)
                state.permanent[i] = spellId
                btn.spellId = spellId
                btn._quality = quality
                btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
                local bc = QUALITY_BORDER_COLORS[quality] or QUALITY_BORDER_COLORS[0]
                btn._qualityBorder:SetTexture(bc[1], bc[2], bc[3])
                btn._qualityBorder:Show()
            end, filtered)
        end)
        slotButtons[i] = btn
    end
end

local descriptionPlaceholder

local function RefreshDescriptionPlaceholder()
    if not descriptionPlaceholder or not commentsBox then return end
    if commentsBox:HasFocus() then
        descriptionPlaceholder:Hide()
        return
    end
    if (commentsBox:GetText() or "") == "" then
        descriptionPlaceholder:Show()
    else
        descriptionPlaceholder:Hide()
    end
end

local function BuildDescriptionField(parent, x, y, height)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    lbl:SetText("Description:")

    local insertBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    insertBtn:SetWidth(110)
    insertBtn:SetHeight(20)
    insertBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 90, y + 2)
    insertBtn:SetText("+ Insert Echo")
    insertBtn:SetScript("OnClick", function()
        EbonBuilds.EchoPicker.Show(function(spellId, quality, name)
            local color = QUALITY_COLOR[quality] or "ffffff"
            local link  = "|cff" .. color .. "|Hecho:" .. spellId .. "|h[" .. name .. "]|h|r"
            if commentsBox:HasFocus() then
                commentsBox:Insert(link)
            else
                commentsBox:SetText((commentsBox:GetText() or "") .. link)
            end
        end)
    end)

    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT",     parent, "TOPLEFT",     x,   y - 24)
    container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -30, 50)
    container:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    container:SetBackdropColor(0, 0, 0, 0.6)
    container:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local scroll = CreateFrame("ScrollFrame", "EbonBuildsBuildFormDescriptionSF", container, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     container, "TOPLEFT",      4, -4)
    scroll:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -4,  4)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetMaxLetters(0)
    box:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    box:SetWidth(420)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(box)
    commentsBox = box

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    hint:SetPoint("TOPLEFT",  box, "TOPLEFT",   2, -2)
    hint:SetPoint("TOPRIGHT", box, "TOPRIGHT", -2, -2)
    hint:SetJustifyH("LEFT")
    hint:SetJustifyV("TOP")
    hint:SetTextColor(0.5, 0.5, 0.5, 1)
    hint:SetText("Describe your build here: items, skills, rotation priorities, glyphs, etc.")
    descriptionPlaceholder = hint

    box:SetScript("OnEditFocusGained", function() descriptionPlaceholder:Hide() end)
    box:SetScript("OnEditFocusLost", function(self)
        if (self:GetText() or "") == "" then descriptionPlaceholder:Show() end
    end)
    box:SetScript("OnTextChanged", function(self)
        if self:HasFocus() then
            descriptionPlaceholder:Hide()
        else
            if (self:GetText() or "") == "" then
                descriptionPlaceholder:Show()
            else
                descriptionPlaceholder:Hide()
            end
        end
    end)
end

------------------------------------------------------------------------
-- Footer
------------------------------------------------------------------------

local function CollectFromInputs()
    state.title    = titleBox:GetText() or ""
    state.comments = commentsBox:GetText() or ""
end

local function OnSave()
    CollectFromInputs()
    if state.title == "" then return end
    if state.mode == "create" then
        local b = EbonBuilds.Build.Create({
            title = state.title, class = state.class, spec = state.spec,
            comments = state.comments, permanentEchoes = { unpack(state.permanent) },
            settings = state.settings,
        })
        state.mode = "edit"
        state.id   = b.id
        EbonBuilds.Build.SetActive(b.id)
    else
        EbonBuilds.Build.Save(state.id, {
            title = state.title, class = state.class, spec = state.spec,
            comments = state.comments, permanentEchoes = { unpack(state.permanent) },
            settings = state.settings,
        })
    end
    if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
        EbonBuilds.BuildList.Refresh()
    end
    if EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.OnBuildSaved then
        EbonBuilds.BuildTabs.OnBuildSaved()
    end
    if EbonBuilds.BuildTabs and EbonBuilds.BuildTabs.EnableEchoesTab then
        EbonBuilds.BuildTabs.EnableEchoesTab()
    end
end

local function OnCancel()
    local active = EbonBuilds.Build.GetActive()
    if active then
        EbonBuilds.ViewRouter.Show("buildOverview", { build = active })
    else
        EbonBuilds.ViewRouter.Show("welcome")
    end
end

local function OnDelete()
    if not state.id then return end
    EbonBuilds.Build.Delete(state.id)
    if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
        EbonBuilds.BuildList.Refresh()
    end
    local active = EbonBuilds.Build.GetActive()
    if active then
        EbonBuilds.ViewRouter.Show("buildTabs", { mode = "edit", build = active })
    else
        EbonBuilds.ViewRouter.Show("buildTabs", { mode = "create" })
    end
end

EbonBuilds.BuildForm.Save   = OnSave
EbonBuilds.BuildForm.Cancel = OnCancel
EbonBuilds.BuildForm.Delete = OnDelete

------------------------------------------------------------------------
-- Load/Reset state
------------------------------------------------------------------------

local function ApplyStateToInputs()
    titleBox:SetText(state.title or "")
    commentsBox:SetText(state.comments or "")
    RefreshDescriptionPlaceholder()
    RefreshClassSelection()
    RefreshSpecButtons()
    for i = 1, 4 do
        local id = state.permanent[i]
        local btn = slotButtons[i]
        btn.spellId = id
        if id then
            btn._icon:SetTexture(select(3, GetSpellInfo(id)))
            local data = ProjectEbonhold.PerkDatabase[id]
            local quality = data and data.quality or 0
            btn._quality = quality
            local bc = QUALITY_BORDER_COLORS[quality] or QUALITY_BORDER_COLORS[0]
            btn._qualityBorder:SetTexture(bc[1], bc[2], bc[3])
            btn._qualityBorder:Show()
        else
            btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
            btn._quality = nil
            btn._qualityBorder:Hide()
        end
    end
end

local function CloneSettings(src)
    local dst = EbonBuilds.Build.DefaultSettings()
    if not src then return dst end
    for k, v in pairs(src) do
        if type(v) == "table" then
            dst[k] = dst[k] or {}
            for k2, v2 in pairs(v) do dst[k][k2] = v2 end
        else
            dst[k] = v
        end
    end
    return dst
end

local function LoadFromBuild(build)
    state.mode     = "edit"
    state.id       = build.id
    state.title    = build.title    or ""
    state.class    = build.class
    state.spec     = build.spec     or 1
    state.comments = build.comments or ""
    state.settings = CloneSettings(build.settings)
    for i = 1, 4 do state.permanent[i] = build.permanentEchoes and build.permanentEchoes[i] or nil end
end

local function LoadDefaults()
    state.mode     = "create"
    state.id       = nil
    state.title    = ""
    state.class    = EbonBuilds.Build.PlayerClassToken()
    state.spec     = EbonBuilds.Build.PlayerTopTalentTab()
    state.comments = ""
    state.settings = EbonBuilds.Build.DefaultSettings()
    for i = 1, 4 do state.permanent[i] = nil end
    EbonBuildsDB.pendingWeights = {}
end

------------------------------------------------------------------------
-- Public Mount/Unmount
------------------------------------------------------------------------

local function TargetMatchesState(context)
    if context.mode == "edit" and context.build then
        return state.mode == "edit" and state.id == context.build.id
    end
    return false
end

function EbonBuilds.BuildForm.Mount(container, context)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)

    context = context or {}
    local keepState = TargetMatchesState(context)
    if not keepState then
        if context.mode == "edit" and context.build then
            LoadFromBuild(context.build)
        else
            LoadDefaults()
        end
    end

    ApplyStateToInputs()
    NotifyClassChange()
    viewFrame:Show()
end

function EbonBuilds.BuildForm.Unmount()
    if viewFrame and titleBox and commentsBox then
        state.title    = titleBox:GetText() or state.title
        state.comments = commentsBox:GetText() or state.comments
    end
    if viewFrame then viewFrame:Hide() end
end

------------------------------------------------------------------------
-- Build view frame (deferred until Init so parent is known)
------------------------------------------------------------------------

local function BuildViewFrame()
    local f = CreateFrame("Frame", nil, UIParent)

    local header = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
    header:SetText("Build")

    BuildClassGrid(f, 10, -36)
    BuildSpecGrid(f, 10, -76)
    BuildTitleField(f, 10, -124)
    BuildPermanentSlots(f, 10, -160)
    BuildDescriptionField(f, 10, -210, 180)
    return f
end

function EbonBuilds.BuildForm.Init()
    viewFrame = BuildViewFrame()
    viewFrame:Hide()
    InstallLinkHook()
end
