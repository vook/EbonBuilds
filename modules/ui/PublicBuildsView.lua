-- EbonBuilds: modules/ui/PublicBuildsView.lua
-- Responsibility: paginated browser for builds shared by other players.
-- Exposes Mount/Unmount. Registered as the "publicBuilds" view.

EbonBuilds.PublicBuildsView = {}

local SW = EbonBuilds.SiteWidgets
local ST = EbonBuilds.SiteTheme
local C  = ST.C
local L  = ST.Layout

local PAGE_SIZE  = 8
local CARD_MARGIN = 4
local CARD_HEIGHT = 74
local LOCKED_ICON_SIZE = 22

local viewFrame
local cardPool   = {}
local pageLabel, prevBtn, nextBtn
local scrollFrame, scrollChild, scrollBar
local noBuildsLabel
local state = { builds = {}, page = 1, totalPages = 1 }

local CLASS_DISPLAY = {
    WARRIOR     = "Warrior",
    PALADIN     = "Paladin",
    HUNTER      = "Hunter",
    ROGUE       = "Rogue",
    PRIEST      = "Priest",
    DEATHKNIGHT = "Death Knight",
    SHAMAN      = "Shaman",
    MAGE        = "Mage",
    WARLOCK     = "Warlock",
    DRUID       = "Druid",
}

local CLASS_TOKENS = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local classDropdown, specDropdown, refreshBtn
local filterClass, filterSpec

------------------------------------------------------------------------
-- Data source
------------------------------------------------------------------------

local function FetchPublicBuilds()
    return EbonBuilds.Build.ListPublic()
end

------------------------------------------------------------------------
-- Filter dropdowns
------------------------------------------------------------------------

local RefreshView, GetFilteredBuilds, StyleFilterDropdowns

local function StyleFilterDropdownsImpl()
    if not classDropdown or not specDropdown then return end
    SW.StyleUIDropDown(classDropdown, 130)
    SW.StyleUIDropDown(specDropdown, 130)
    SW.SyncDropDownLabel(classDropdown)
    SW.SyncDropDownLabel(specDropdown)
end
StyleFilterDropdowns = StyleFilterDropdownsImpl

local function InitSpecDropdown()
    UIDropDownMenu_Initialize(specDropdown, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "All Specs"
        info.value = nil
        info.func = function()
            UIDropDownMenu_SetSelectedValue(specDropdown, nil)
            filterSpec = nil
            UIDropDownMenu_SetText(specDropdown, "All Specs")
            RefreshView()
            StyleFilterDropdowns()
        end
        info.checked = (filterSpec == nil)
        UIDropDownMenu_AddButton(info)
        if filterClass then
            local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[filterClass] or {}
            for i, entry in pairs(specs) do
                if type(i) == "number" then
                    info.text = entry.name
                    info.value = i
                    info.func = function()
                        UIDropDownMenu_SetSelectedValue(specDropdown, i)
                        filterSpec = i
                        UIDropDownMenu_SetText(specDropdown, entry.name)
                        RefreshView()
                        StyleFilterDropdowns()
                    end
                    info.checked = (i == filterSpec)
                    UIDropDownMenu_AddButton(info)
                end
            end
        end
    end)
    if filterSpec then
        local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[filterClass] or {}
        local entry = specs[filterSpec]
        if entry then
            UIDropDownMenu_SetText(specDropdown, entry.name)
            UIDropDownMenu_SetSelectedValue(specDropdown, filterSpec)
        else
            UIDropDownMenu_SetText(specDropdown, "All Specs")
            UIDropDownMenu_SetSelectedValue(specDropdown, nil)
            filterSpec = nil
        end
    else
        UIDropDownMenu_SetText(specDropdown, "All Specs")
        UIDropDownMenu_SetSelectedValue(specDropdown, nil)
    end
end

local function InitClassDropdown()
    UIDropDownMenu_Initialize(classDropdown, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "All Classes"
        info.value = nil
        info.func = function()
            UIDropDownMenu_SetSelectedValue(classDropdown, nil)
            filterClass = nil
            filterSpec = nil
            UIDropDownMenu_SetText(classDropdown, "All Classes")
            InitSpecDropdown()
            RefreshView()
            StyleFilterDropdowns()
        end
        info.checked = (filterClass == nil)
        UIDropDownMenu_AddButton(info)
        for _, token in ipairs(CLASS_TOKENS) do
            info.text = CLASS_DISPLAY[token]
            info.value = token
            info.func = function()
                UIDropDownMenu_SetSelectedValue(classDropdown, token)
                filterClass = token
                filterSpec = nil
                UIDropDownMenu_SetText(classDropdown, CLASS_DISPLAY[token])
                InitSpecDropdown()
                RefreshView()
                StyleFilterDropdowns()
            end
            info.checked = (token == filterClass)
            UIDropDownMenu_AddButton(info)
        end
    end)
    if filterClass then
        UIDropDownMenu_SetSelectedValue(classDropdown, filterClass)
        UIDropDownMenu_SetText(classDropdown, CLASS_DISPLAY[filterClass])
    else
        UIDropDownMenu_SetSelectedValue(classDropdown, nil)
        UIDropDownMenu_SetText(classDropdown, "All Classes")
    end
end

------------------------------------------------------------------------
-- Card factory
------------------------------------------------------------------------

local function SetClassIcon(tex, classToken)
    local coords = CLASS_ICON_TCOORDS[classToken]
    if coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    else
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        tex:SetTexCoord(0, 1, 0, 1)
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

local function CreateCard(parent)
    local card = CreateFrame("Button", nil, parent)
    card:SetHeight(CARD_HEIGHT)
    card:RegisterForClicks("LeftButtonUp")

    -- Class-colored border via backdrop
    card:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    card:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Inner background
    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT",     card, "TOPLEFT",     4, -4)
    bg:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -4,  4)
    bg:SetTexture(0, 0, 0, 0.20)
    card._bg = bg

    -- Left accent stripe
    local stripe = card:CreateTexture(nil, "BACKGROUND")
    stripe:SetPoint("TOPLEFT",    card, "TOPLEFT",    4, -4)
    stripe:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 4,  4)
    stripe:SetWidth(4)
    card._stripe = stripe

    -- Class icon (top-left, 28x28)
    local classIcon = card:CreateTexture(nil, "ARTWORK")
    classIcon:SetWidth(28)
    classIcon:SetHeight(28)
    classIcon:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -10)
    classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card._classIcon = classIcon

    -- Title (to the right of class icon)
    local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", classIcon, "TOPRIGHT", 8, -4)
    title:SetPoint("RIGHT",   card,      "RIGHT",   -90, 0)
    title:SetJustifyH("LEFT")
    card._titleLabel = title

    -- Author + spec + date (below title)
    local meta = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    meta:SetPoint("RIGHT",   card,  "RIGHT",     -90, 0)
    meta:SetJustifyH("LEFT")
    card._metaLabel = meta

    -- Spec icon (bottom-left of class icon)
    local specIcon = card:CreateTexture(nil, "ARTWORK")
    specIcon:SetWidth(14)
    specIcon:SetHeight(14)
    specIcon:SetPoint("TOPLEFT", classIcon, "BOTTOMLEFT", 0, -2)
    specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    card._specIcon = specIcon

    -- Locked echo icons (below meta)
    card._lockedBtns = {}
    local maxSlots = (EbonBuilds.Build and EbonBuilds.Build.MAX_LOCKED_SLOTS) or 6
    for i = 1, maxSlots do
        local btn = CreateIconButton(card, LOCKED_ICON_SIZE)
        btn:SetPoint("TOPLEFT", meta, "BOTTOMLEFT", (i - 1) * (LOCKED_ICON_SIZE + 4), -4)
        btn:Hide()
        btn:SetScript("OnEnter", function(self)
            if not self._spellId then return end
            local spellName = GetSpellInfo(self._spellId)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            if spellName then GameTooltip:AddLine(spellName, 1, 0.82, 0) end
            if utils and utils.GetSpellDescription then
                local desc = utils.GetSpellDescription(self._spellId, 500, 1)
                if desc and desc ~= "" then GameTooltip:AddLine(desc, 1, 1, 1, true) end
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        card._lockedBtns[i] = btn
    end

    -- Import button (right side, vertically centered)
    local importBtn = SW.CreateOutlineButton(card, "Import", 76)
    importBtn:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    card._importBtn = importBtn

    return card
end

------------------------------------------------------------------------
-- Import logic
------------------------------------------------------------------------

local function FindImportedCopy(publicBuildId)
    for _, b in pairs(EbonBuildsDB.builds) do
        if b.importedFrom == publicBuildId then
            return b
        end
    end
    return nil
end

local function ImportBuild(build)
    local settings = EbonBuilds.Build.CloneSettings(build.settings or EbonBuilds.Build.DefaultSettings())
    local data = {
        title    = (build.title or "Imported") .. " (imported)",
        class    = build.class,
        spec     = build.spec or 1,
        comments = build.comments or "",
        lockedEchoes = EbonBuilds.Build.NormalizeLockedEchoes(build.lockedEchoes),
        settings = settings,
        isPublic = false,
    }
    local newBuild = EbonBuilds.Build.Create(data)
    newBuild.importedFrom = build.id
    newBuild._importedAt = build.lastModified
    if build.echoWeights and next(build.echoWeights) then
        newBuild.echoWeights = {}
        for name, weight in pairs(build.echoWeights) do
            newBuild.echoWeights[name] = weight
        end
    end
    newBuild._checksum = EbonBuilds.Build.Checksum(newBuild)
    EbonBuilds.Build.EnsureSettings(newBuild)
    -- Remove from remote builds since we now have a local copy
    if EbonBuildsDB.remoteBuilds then
        EbonBuildsDB.remoteBuilds[build.id] = nil
    end
    EbonBuilds.Build.SetActive(newBuild.id)
    if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
        EbonBuilds.BuildList.Refresh()
    end
    EbonBuilds.ViewRouter.Show("buildOverview", { build = newBuild })
end

local function UpdateLocalBuild(localBuild, publicBuild)
    EbonBuilds.Build.UpdateFromPublic(localBuild, publicBuild)
    EbonBuilds.Build.SetActive(localBuild.id)
    if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
        EbonBuilds.BuildList.Refresh()
    end
    EbonBuilds.ViewRouter.Show("buildOverview", { build = localBuild })
end

------------------------------------------------------------------------
-- Render
------------------------------------------------------------------------

local function PopulateCard(card, build)
    local cc = ST.CLASS_COLORS[build.class] or { 0.5, 0.5, 0.5 }

    -- Border and stripe color by class
    card:SetBackdropBorderColor(cc[1], cc[2], cc[3], 0.8)
    card._stripe:SetTexture(cc[1], cc[2], cc[3], 0.8)
    card._bg:SetTexture(cc[1], cc[2], cc[3], 0.06)

    SetClassIcon(card._classIcon, build.class)

    card._titleLabel:SetText(build.title or "Untitled")
    card._titleLabel:SetTextColor(cc[1], cc[2], cc[3], 1)

    local specName = ""
    local specs = EbonBuilds.SpecData and EbonBuilds.SpecData[build.class]
    local specEntry = specs and specs[build.spec or 1]
    if specEntry then
        specName = specEntry.name
        card._specIcon:SetTexture(specEntry.icon)
        card._specIcon:Show()
    else
        card._specIcon:Hide()
    end

    local author = build.author or "Unknown"
    local modified = build.lastModified or ""
    card._metaLabel:SetText(string.format("by %s | %s | %s", author, specName, modified))

    -- Locked echo icons
    local lockeds = build.lockedEchoes
    local slotCount = (EbonBuilds.Build and EbonBuilds.Build.GetLockedSlotCount and EbonBuilds.Build.GetLockedSlotCount()) or 5
    for i = 1, #card._lockedBtns do
        local btn = card._lockedBtns[i]
        if i > slotCount then
            btn:Hide()
            btn._spellId = nil
        else
            btn:Show()
        end
        local spellId = lockeds and lockeds[i]
        if spellId then
            btn._icon:SetTexture(select(3, GetSpellInfo(spellId)))
            btn._spellId = spellId
            btn:Show()
        else
            btn:Hide()
        end
    end

    -- Import / Update button (builds already loaded and up-to-date are hidden by GetFilteredBuilds)
    local localCopy = FindImportedCopy(build.id)
    if localCopy and build.lastModified ~= localCopy._importedAt then
        card._importBtn._label:SetText("Update")
        card._importBtn:Enable()
        card._importBtn:SetAlpha(1)
        card._importBtn:SetScript("OnClick", function()
            UpdateLocalBuild(localCopy, build)
        end)
    else
        card._importBtn._label:SetText("Import")
        card._importBtn:Enable()
        card._importBtn:SetAlpha(1)
        card._importBtn:SetScript("OnClick", function()
            ImportBuild(build)
        end)
    end
end

local function SetOutlineEnabled(btn, enabled)
    if not btn then return end
    if enabled then
        btn:Enable()
        btn:SetAlpha(1)
    else
        btn:Disable()
        btn:SetAlpha(0.55)
    end
end

local function RefreshPaginationControls()
    SetOutlineEnabled(prevBtn, state.page > 1)
    SetOutlineEnabled(nextBtn, state.page < state.totalPages)
    pageLabel:SetText(string.format("Page %d of %d", state.page, state.totalPages))
end

local function Render()
    local all = state.builds or {}
    if #all == 0 then
        for _, card in ipairs(cardPool) do card:Hide() end
        scrollChild:SetHeight(1)
        scrollBar:SetMinMaxValues(0, 0)
        scrollBar:SetValue(0)
        pageLabel:SetText("Page 1 of 1")
        SetOutlineEnabled(prevBtn, false)
        SetOutlineEnabled(nextBtn, false)
        if noBuildsLabel then noBuildsLabel:Show() end
        return
    end
    if noBuildsLabel then noBuildsLabel:Hide() end

    local startIdx = (state.page - 1) * PAGE_SIZE + 1
    local endIdx   = math.min(startIdx + PAGE_SIZE - 1, #all)

    local totalHeight = 0
    for i = startIdx, endIdx do
        local poolIdx = i - startIdx + 1
        if not cardPool[poolIdx] then
            cardPool[poolIdx] = CreateCard(scrollChild)
        end
        local card = cardPool[poolIdx]
        PopulateCard(card, all[i])
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -totalHeight)
        card:SetPoint("RIGHT",   scrollChild, "RIGHT",   0, 0)
        card:Show()
        totalHeight = totalHeight + CARD_HEIGHT + CARD_MARGIN
    end
    for i = endIdx - startIdx + 2, #cardPool do
        cardPool[i]:Hide()
    end
    scrollChild:SetHeight(math.max(1, totalHeight))

    local visibleHeight = scrollFrame:GetHeight()
    local maxOffset = math.max(0, totalHeight - visibleHeight)
    scrollBar:SetMinMaxValues(0, maxOffset)
    if scrollBar:GetValue() > maxOffset then scrollBar:SetValue(maxOffset) end

    RefreshPaginationControls()
end

GetFilteredBuilds = function()
    local all = FetchPublicBuilds()
    local filtered = {}
    for _, build in ipairs(all) do
        if filterClass and build.class ~= filterClass then
        elseif filterSpec and build.spec ~= filterSpec then
        else
            local ownBuild = EbonBuildsDB.builds[build.id]
            if ownBuild then
                -- User owns this build by UUID: already in collection, hide
            else
                local localCopy = FindImportedCopy(build.id)
                if localCopy and build.lastModified == localCopy._importedAt then
                    -- Imported copy is up-to-date: hide
                else
                    filtered[#filtered + 1] = build
                end
            end
        end
    end
    return filtered
end

RefreshView = function()
    state.builds     = GetFilteredBuilds()
    state.page       = 1
    state.totalPages = math.max(1, math.ceil(#state.builds / PAGE_SIZE))
    scrollBar:SetValue(0)
    Render()
end

------------------------------------------------------------------------
-- Scrollbar wiring
------------------------------------------------------------------------

local function WireScrollBar()
    scrollBar:SetScript("OnValueChanged", function()
        local offset = scrollBar:GetValue()
        scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, offset)
    end)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local v = scrollBar:GetValue()
        local mn, mx = scrollBar:GetMinMaxValues()
        scrollBar:SetValue(math.max(mn, math.min(mx, v - delta * 40)))
    end)
end

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------

local function BuildViewFrame(parent)
    local f = CreateFrame("Frame", nil, parent)

    local header = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
    header:SetText("Public Builds")

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    sub:SetText("Browse builds shared by other players.")

    noBuildsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    noBuildsLabel:SetPoint("CENTER", f, "CENTER", 0, 0)
    noBuildsLabel:SetText("No public builds available.")
    noBuildsLabel:Hide()

    -- Bottom bar: pagination controls
    local bottomBar = CreateFrame("Frame", nil, f)
    bottomBar:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  L.PAD, L.PAD)
    bottomBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -L.PAD, L.PAD)
    bottomBar:SetHeight(36)

    prevBtn = SW.CreateOutlineButton(bottomBar, "Previous", 88)
    prevBtn:SetPoint("LEFT", bottomBar, "LEFT", 0, 0)
    prevBtn:SetScript("OnClick", function()
        if state.page > 1 then
            state.page = state.page - 1
            scrollBar:SetValue(0)
            Render()
        end
    end)

    nextBtn = SW.CreateOutlineButton(bottomBar, "Next", 72)
    nextBtn:SetPoint("RIGHT", bottomBar, "RIGHT", 0, 0)
    nextBtn:SetScript("OnClick", function()
        if state.page < state.totalPages then
            state.page = state.page + 1
            scrollBar:SetValue(0)
            Render()
        end
    end)

    pageLabel = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pageLabel:SetPoint("CENTER", bottomBar, "CENTER", 0, 0)
    pageLabel:SetText("Page 1 of 1")

    -- Filter bar: class dropdown, spec dropdown, refresh button
    local filterBar = CreateFrame("Frame", nil, f)
    filterBar:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -10)
    filterBar:SetPoint("RIGHT",   f,   "RIGHT",     -L.PAD, 0)
    filterBar:SetHeight(32)

    classDropdown = CreateFrame("Frame", "EbonBuildsPubClassDrop", filterBar, "UIDropDownMenuTemplate")
    classDropdown:SetPoint("LEFT", filterBar, "LEFT", 0, 0)

    specDropdown = CreateFrame("Frame", "EbonBuildsPubSpecDrop", filterBar, "UIDropDownMenuTemplate")
    specDropdown:SetPoint("LEFT", classDropdown, "RIGHT", 8, 0)

    filterClass = EbonBuilds.Build.PlayerClassToken()
    filterSpec = nil
    InitClassDropdown()
    InitSpecDropdown()
    StyleFilterDropdowns()

    refreshBtn = SW.CreateOutlineButton(filterBar, "Reload", 88)
    refreshBtn:SetPoint("LEFT", specDropdown, "RIGHT", 12, 0)
    refreshBtn:SetScript("OnClick", function()
        if refreshBtn:IsEnabled() then
            EbonBuilds.Sync.RequestSync()
        end
    end)
    refreshBtn:SetScript("OnUpdate", function()
        if not f:IsVisible() then return end
        local remaining = EbonBuilds.Sync.GetCooldownRemaining()
        if remaining > 0 then
            refreshBtn:Disable()
            refreshBtn:SetAlpha(0.55)
            refreshBtn._label:SetText("Wait " .. remaining .. "s")
        else
            refreshBtn:Enable()
            refreshBtn:SetAlpha(1)
            refreshBtn._label:SetText("Reload")
        end
    end)

    -- Scroll area
    scrollFrame = CreateFrame("ScrollFrame", nil, f)
    scrollFrame:SetPoint("TOPLEFT",     filterBar, "BOTTOMLEFT",  0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", bottomBar, "TOPRIGHT",    0,  8)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(1)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Keep scrollChild width in sync with scrollFrame
    scrollFrame:SetScript("OnSizeChanged", function()
        local w = scrollFrame:GetWidth()
        if w and w > 0 then
            scrollChild:SetWidth(w)
            Render()
        end
    end)

    scrollBar = CreateFrame("Slider", nil, scrollFrame, "UIPanelScrollBarTemplate")
    scrollBar:SetPoint("TOPLEFT",    scrollFrame, "TOPRIGHT",    -2, -4)
    scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", -2,  4)
    scrollBar:SetValueStep(20)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValue(0)
    SW.StyleVerticalScrollBar(scrollBar)

    WireScrollBar()
    return f
end

local function EnsureBuilt(container)
    if viewFrame then return end
    viewFrame = BuildViewFrame(container)
end

function EbonBuilds.PublicBuildsView.Mount(container)
    EnsureBuilt(container)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)

    -- Ensure scrollChild has proper width before rendering
    local w = viewFrame:GetWidth()
    if w and w > 0 then scrollChild:SetWidth(w - 24) end

    StyleFilterDropdowns()

    state.builds     = GetFilteredBuilds()
    state.page       = 1
    state.totalPages = math.max(1, math.ceil(#state.builds / PAGE_SIZE))
    scrollBar:SetValue(0)
    Render()
    viewFrame:Show()
end

function EbonBuilds.PublicBuildsView.Unmount()
    if viewFrame then viewFrame:Hide() end
end

function EbonBuilds.PublicBuildsView.RefreshIfMounted()
    if viewFrame and viewFrame:IsVisible() then
        state.builds     = GetFilteredBuilds()
        state.page       = 1
        state.totalPages = math.max(1, math.ceil(#state.builds / PAGE_SIZE))
        scrollBar:SetValue(0)
        Render()
    end
end

function EbonBuilds.PublicBuildsView.Init()
end
