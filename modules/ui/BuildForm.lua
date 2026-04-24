-- EbonBuilds: modules/ui/BuildForm.lua
-- Responsibility: create/edit build form with class, spec, title, comments,
-- and 4 indicative permanent-echo slots. Declarative/widget-layout heavy:
-- template-file exception applies, so the 200-line hard limit is waived here.

EbonBuilds.BuildForm = {}

local CLASS_ORDER = {
    "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST",
    "DEATHKNIGHT","SHAMAN","MAGE","WARLOCK","DRUID",
}
local CLASS_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"
local QUALITY_COLOR = {
    [0]="ffffff",[1]="19ff19",[2]="0066ff",[3]="cc66ff",[4]="ff8000",
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
}
local classButtons = {}
local specButtons  = {}
local slotButtons  = {}
local titleBox, commentsBox, deleteBtn, cancelBtn, saveBtn

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
            state.class = token
            if state.spec > 3 then state.spec = 1 end
            RefreshClassSelection()
            RefreshSpecButtons()
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
        box:SetMaxLetters(120)
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
        btn:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                state.permanent[i] = nil
                btn.spellId = nil
                btn._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
                return
            end
            EbonBuilds.EchoPicker.Show(function(spellId)
                state.permanent[i] = spellId
                btn.spellId = spellId
                btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
            end)
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
        })
        state.mode = "edit"
        state.id   = b.id
        EbonBuilds.Build.SetActive(b.id)
    else
        EbonBuilds.Build.Save(state.id, {
            title = state.title, class = state.class, spec = state.spec,
            comments = state.comments, permanentEchoes = { unpack(state.permanent) },
        })
    end
    if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
        EbonBuilds.BuildList.Refresh()
    end
    deleteBtn:Show()
    cancelBtn:Hide()
end

local function OnCancel()
    if EbonBuilds.Build.GetActive() then
        EbonBuilds.ViewRouter.Show("weights")
    else
        viewFrame:Hide()
    end
end

local function OnDelete()
    if not state.id then return end
    EbonBuilds.Build.Delete(state.id)
    if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
        EbonBuilds.BuildList.Refresh()
    end
    if EbonBuilds.Build.GetActive() then
        EbonBuilds.ViewRouter.Show("weights")
    else
        EbonBuilds.ViewRouter.Show("buildForm", { mode = "create" })
    end
end

local function BuildFooter(parent)
    saveBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    saveBtn:SetSize(90, 22)
    saveBtn:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 10)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", OnSave)

    cancelBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    cancelBtn:SetSize(90, 22)
    cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -6, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", OnCancel)

    deleteBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    deleteBtn:SetSize(90, 22)
    deleteBtn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 10, 10)
    deleteBtn:SetText("Delete")
    deleteBtn:SetScript("OnClick", OnDelete)
end

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
        slotButtons[i].spellId = id
        if id then
            slotButtons[i]._icon:SetTexture(select(3, GetSpellInfo(id)))
        else
            slotButtons[i]._icon:SetTexture("Interface\\Buttons\\UI-EmptySlot")
        end
    end
end

local function LoadFromBuild(build)
    state.mode     = "edit"
    state.id       = build.id
    state.title    = build.title    or ""
    state.class    = build.class
    state.spec     = build.spec     or 1
    state.comments = build.comments or ""
    for i = 1, 4 do state.permanent[i] = build.permanentEchoes and build.permanentEchoes[i] or nil end
end

local function LoadDefaults()
    state.mode     = "create"
    state.id       = nil
    state.title    = ""
    state.class    = EbonBuilds.Build.PlayerClassToken()
    state.spec     = EbonBuilds.Build.PlayerTopTalentTab()
    state.comments = ""
    for i = 1, 4 do state.permanent[i] = nil end
end

------------------------------------------------------------------------
-- View interface
------------------------------------------------------------------------

local view = {}

function view.Show(container, context)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)

    context = context or {}
    if context.mode == "edit" and context.build then
        LoadFromBuild(context.build)
        deleteBtn:Show()
        cancelBtn:Hide()
    else
        LoadDefaults()
        deleteBtn:Hide()
        cancelBtn:Show()
    end
    ApplyStateToInputs()
    viewFrame:Show()
end

function view.Hide()
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
    BuildFooter(f)

    return f
end

function EbonBuilds.BuildForm.Init()
    viewFrame = BuildViewFrame()
    viewFrame:Hide()
    EbonBuilds.ViewRouter.Register("buildForm", view)
    InstallLinkHook()
end
