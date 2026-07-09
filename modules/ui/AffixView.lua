-- EbonBuilds: modules/ui/AffixView.lua
-- Affixes tab: scan inspected player gear and store affix names on the build.

EbonBuilds.AffixView = {}

local viewFrame
local sourceLabel, sourceDropdown
local scanBtn, scanMineBtn, clearBtn, deleteBtn, exportBtn, importBtn, applyBtn
local previewDialog
local pendingApplyPlan, pendingApplySummary
local pendingDeleteSource
local listScroll, listChild, listBar
local listWireWheel
local nameRows = {}

local overviewBuild

local function GetTargetBuild()
    if overviewBuild then return overviewBuild end
    if EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingBuild then
        return EbonBuilds.BuildForm.GetEditingBuild()
    end
    return nil
end

local function UsesPendingAffixStore()
    return not GetTargetBuild()
        and EbonBuildsDB
        and EbonBuildsDB._isEditingBuild
end

local function GetAffixStore()
    if UsesPendingAffixStore() then
        local store = EbonBuildsDB.pendingScannedAffixes
        if not store then
            local build = GetTargetBuild()
            if build then
                store = EbonBuilds.Build.GetScannedAffixStore(build)
            end
        end
        EbonBuildsDB.pendingScannedAffixes = EbonBuilds.Build.NormalizeScannedAffixes(store)
        return EbonBuildsDB.pendingScannedAffixes
    end
    local build = GetTargetBuild()
    if build then
        return EbonBuilds.Build.GetScannedAffixStore(build)
    end
    return nil
end

local function GetActiveAffixScan()
    local build = GetTargetBuild()
    if build then
        return EbonBuilds.Build.GetActiveAffixScan(build)
    end
    local store = GetAffixStore()
    if not store or not store.scans or not store.activeSource then return nil end
    return store.scans[store.activeSource]
end

local function UpsertAffixScan(scanRecord)
    if UsesPendingAffixStore() then
        local store = GetAffixStore() or { scans = {} }
        store.scans = store.scans or {}
        store.scans[scanRecord.source] = {
            source    = scanRecord.source,
            scannedAt = scanRecord.scannedAt,
            names     = EbonBuilds.Build.CoerceAffixNameList(scanRecord.names or {}),
        }
        store.activeSource = scanRecord.source
        EbonBuildsDB.pendingScannedAffixes = store
        return true
    end
    local build = GetTargetBuild()
    if build then
        return EbonBuilds.Build.UpsertAffixScan(build, scanRecord)
    end
    return false
end

local function SetActiveAffixSource(source)
    local build = GetTargetBuild()
    if build then
        return EbonBuilds.Build.SetActiveAffixSource(build, source)
    end
    local store = GetAffixStore()
    if store and source and store.scans[source] then
        store.activeSource = source
        return true
    end
    return false
end

local function RemoveAffixScanBySource(source)
    if not source then return false end
    local build = GetTargetBuild()
    if build then
        return EbonBuilds.Build.RemoveAffixScan(build, source)
    end
    if UsesPendingAffixStore() then
        local store = GetAffixStore()
        if not store or not store.scans[source] then return false end
        store.scans[source] = nil
        if not next(store.scans) then
            EbonBuildsDB.pendingScannedAffixes = nil
        elseif store.activeSource == source then
            local sources = EbonBuilds.Build.ListAffixScanSources({ scannedAffixes = store })
            store.activeSource = sources[1] and sources[1].source
        end
        return true
    end
    return false
end

local function PromptDeleteAffixScan(source)
    source = source or (GetAffixStore() and GetAffixStore().activeSource)
    if not source then return end
    pendingDeleteSource = source
    StaticPopupDialogs["EBONBUILDS_REMOVE_AFFIX_SCAN"].text =
        "Delete the affix scan from " .. source .. "?\n\nOther stored scans are kept."
    StaticPopup_Show("EBONBUILDS_REMOVE_AFFIX_SCAN")
end

local function ClearAllAffixScans()
    local build = GetTargetBuild()
    if build then
        return EbonBuilds.Build.ClearAffixScans(build)
    end
    if UsesPendingAffixStore() then
        EbonBuildsDB.pendingScannedAffixes = nil
        return true
    end
    return false
end

function EbonBuilds.AffixView.SetOverviewBuild(build)
    overviewBuild = build
end

local function GetBuildForApply()
    if overviewBuild then return overviewBuild end
    if EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingBuild then
        local build = EbonBuilds.BuildForm.GetEditingBuild()
        if build then return build end
    end
    if EbonBuilds.Build and EbonBuilds.Build.GetActive then
        return EbonBuilds.Build.GetActive()
    end
    return nil
end

local function PromoteSpecialFrame(frameName)
    if type(UISpecialFrames) ~= "table" or not frameName then return end
    for i, name in ipairs(UISpecialFrames) do
        if name == frameName then
            table.remove(UISpecialFrames, i)
            break
        end
    end
    table.insert(UISpecialFrames, frameName)
end

local function RefreshApplyButton()
    if not applyBtn then return end
    applyBtn._hint = nil
    local build = GetBuildForApply()
    if not build or not EbonBuilds.AffixApply then
        applyBtn:Disable()
        applyBtn._hint = "Open a build with stored affixes."
        return
    end
    local canPreview, hint = EbonBuilds.AffixApply.CanPreview(build)
    if canPreview then
        applyBtn:Enable()
        local canRun, runHint = EbonBuilds.AffixApply.CanRun(build)
        if not canRun and runHint then
            applyBtn._hint = runHint
        else
            applyBtn._hint = nil
        end
    else
        applyBtn:Disable()
        applyBtn._hint = hint or "Cannot preview affix changes right now."
    end
end

local function RefreshListScroll()
    if not listScroll or not listChild or not listBar then return end
    local overflow = math.max(0, listChild:GetHeight() - listScroll:GetHeight())
    if overflow <= 0 then
        listBar:Hide()
        listBar:SetMinMaxValues(0, 0)
        listChild:SetPoint("TOPLEFT", listScroll, "TOPLEFT", 0, 0)
    else
        listBar:Show()
        listBar:SetMinMaxValues(0, overflow)
    end
end

local function SortAffixNames(names)
    local sorted = {}
    for i = 1, #names do
        sorted[i] = names[i]
    end
    table.sort(sorted, function(a, b)
        return a:lower() < b:lower()
    end)
    return sorted
end

local function ListAffixSources()
    local build = GetTargetBuild()
    if build then
        return EbonBuilds.Build.ListAffixScanSources(build)
    end
    return EbonBuilds.Build.ListAffixScanSources({ scannedAffixes = GetAffixStore() })
end

local RefreshList
local RefreshSourceDropdown

RefreshSourceDropdown = function()
    if not sourceDropdown then return end
    UIDropDownMenu_Initialize(sourceDropdown, function(_, level)
        level = level or 1
        local sources = ListAffixSources()
        if #sources == 0 then
            if level == 1 then
                UIDropDownMenu_SetText(sourceDropdown, "No scans stored")
                UIDropDownMenu_SetSelectedValue(sourceDropdown, nil)
                if deleteBtn then deleteBtn:Disable() end
            end
            return
        end

        local activeSource = (GetAffixStore() or {}).activeSource

        if level == 1 then
            for _, entry in ipairs(sources) do
                local info = UIDropDownMenu_CreateInfo()
                local when = entry.scannedAt and (" — " .. entry.scannedAt) or ""
                info.text = entry.source .. when .. " (" .. entry.count .. ")"
                info.value = entry.source
                info.checked = entry.source == activeSource
                info.func = function()
                    SetActiveAffixSource(entry.source)
                    UIDropDownMenu_SetSelectedValue(sourceDropdown, entry.source)
                    UIDropDownMenu_SetText(sourceDropdown, entry.source)
                    RefreshList()
                end
                UIDropDownMenu_AddButton(info, level)
            end

            local divider = UIDropDownMenu_CreateInfo()
            divider.text = ""
            divider.isTitle = true
            divider.notCheckable = true
            divider.disabled = true
            UIDropDownMenu_AddButton(divider, level)

            local deleteMenu = UIDropDownMenu_CreateInfo()
            deleteMenu.text = "Delete scan..."
            deleteMenu.notCheckable = true
            deleteMenu.hasArrow = true
            deleteMenu.value = "delete"
            UIDropDownMenu_AddButton(deleteMenu, level)

            local active = activeSource or sources[1].source
            UIDropDownMenu_SetSelectedValue(sourceDropdown, active)
            UIDropDownMenu_SetText(sourceDropdown, active)
            if deleteBtn then deleteBtn:Enable() end
            return
        end

        if UIDROPDOWNMENU_MENU_VALUE == "delete" then
            for _, entry in ipairs(sources) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = "|cffff2020Delete " .. entry.source .. "|r"
                info.notCheckable = true
                info.arg1 = entry.source
                info.func = function(self)
                    CloseDropDownMenus()
                    PromptDeleteAffixScan(self.arg1)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end)
end

RefreshList = function()
    if not listChild then return end
    for _, row in ipairs(nameRows) do row:Hide() end

    local data = GetActiveAffixScan()
    local names = SortAffixNames(data and data.names or {})
    RefreshSourceDropdown()

    if sourceLabel then
        if data and data.source then
            local when = data.scannedAt and (" — " .. data.scannedAt) or ""
            sourceLabel:SetText(string.format(
                "Showing %d affix%s from %s%s",
                #names, #names == 1 and "" or "es", data.source, when
            ))
        else
            sourceLabel:SetText("Inspect a player, then scan — affixes save to your build for their class.")
        end
    end

    if #names == 0 then
        local empty = listChild._emptyLabel
        if not empty then
            empty = listChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            empty:SetPoint("TOPLEFT", listChild, "TOPLEFT", 4, -4)
            listChild._emptyLabel = empty
        end
        empty:SetText("No affixes stored yet.")
        empty:Show()
        listChild:SetHeight(24)
        RefreshListScroll()
        RefreshApplyButton()
        return
    end

    if listChild._emptyLabel then
        listChild._emptyLabel:Hide()
    end

    local y = 0
    for i, name in ipairs(names) do
        local row = nameRows[i]
        if not row then
            row = listChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row:SetPoint("LEFT", listChild, "LEFT", 4, 0)
            row:SetJustifyH("LEFT")
            nameRows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 4, -y)
        row:SetWidth(listChild:GetWidth() - 8)
        row:SetText("• " .. name)
        row:Show()
        y = y + (row:GetStringHeight() or 14) + 2
    end

    listChild:SetHeight(math.max(24, y + 4))
    RefreshListScroll()
    RefreshApplyButton()
end

local function OnExportClick()
    local data = GetActiveAffixScan()
    if not data or not data.names or #data.names == 0 then
        if EbonBuilds.Toast then
            EbonBuilds.Toast.Show("No affixes to share. Scan or import a list first.")
        end
        return
    end
    local build = GetTargetBuild()
    local classToken = build and build.class
    if EbonBuilds.ExportImport and EbonBuilds.ExportImport.ShowAffixExportDialog then
        EbonBuilds.ExportImport.ShowAffixExportDialog(data, classToken)
    end
end

local function OnImportClick()
    if not EbonBuilds.ExportImport or not EbonBuilds.ExportImport.ShowAffixImportDialog then
        return
    end
    EbonBuilds.ExportImport.ShowAffixImportDialog(function(parsed)
        local source = parsed.source or "Imported"
        local scannedAt = parsed.scannedAt or date("%Y-%m-%d %H:%M")
        if not UpsertAffixScan({
            source    = source,
            scannedAt = scannedAt,
            names     = parsed.names,
        }) then
            if EbonBuilds.Toast then
                EbonBuilds.Toast.Show("Open a build to store imported affixes.")
            end
            return
        end
        if EbonBuilds.Toast then
            EbonBuilds.Toast.Show(string.format("Imported %d affix%s from shared text.", #parsed.names, #parsed.names == 1 and "" or "es"))
        end
        RefreshList()
    end)
end

local function EnsurePreviewDialog()
    if previewDialog then return end

    local f = CreateFrame("Frame", "EbonBuildsAffixPreviewDialog", UIParent)
    f:SetSize(440, 340)
    f:SetPoint("LEFT", UIParent, "CENTER", 24, 0)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 8, edgeSize = 32,
        insets   = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 1)
    f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    f:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        RefreshApplyButton()
    end)
    f:SetScript("OnShow", function(self)
        self:Raise()
        PromoteSpecialFrame(self:GetName())
    end)
    f:Hide()

    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, f:GetName())
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", f, "TOP", 0, -16)
    title:SetText("Apply Affixes Preview")

    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT",  f, "TOPLEFT",  0,   0)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -37, 0)
    drag:SetHeight(30)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    f._summary = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f._summary:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -40)
    f._summary:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -40)
    f._summary:SetJustifyH("LEFT")

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", f._summary, "BOTTOMLEFT", 0, -2)
    hint:SetPoint("TOPRIGHT", f._summary, "BOTTOMRIGHT", 0, -2)
    hint:SetJustifyH("LEFT")
    hint:SetText("Set coverage only — affixes may land on different slots than the reference build.")

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT",  hint, "BOTTOMLEFT",  0, -8)
    divider:SetPoint("TOPRIGHT", hint, "BOTTOMRIGHT", 0, -8)
    divider:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
    divider:SetVertexColor(0.5, 0.5, 0.5, 0.6)

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT",     divider, "BOTTOMLEFT",  0, -6)
    scroll:SetPoint("BOTTOMRIGHT", f,         "BOTTOMRIGHT", -28, 48)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(380)
    child:SetHeight(24)
    scroll:SetScrollChild(child)

    local scrollBar = CreateFrame("Slider", nil, scroll, "UIPanelScrollBarTemplate")
    scrollBar:SetPoint("TOPLEFT",    scroll, "TOPRIGHT",    -2, -4)
    scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -2,  4)
    scrollBar:SetValueStep(16)
    scrollBar:Hide()
    scrollBar:SetScript("OnValueChanged", function(_, value)
        child:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, value)
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta)
        if not scrollBar:IsShown() then return end
        local v = scrollBar:GetValue()
        local mn, mx = scrollBar:GetMinMaxValues()
        scrollBar:SetValue(math.max(mn, math.min(mx, v - delta * 16)))
    end)

    local applyConfirm = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    applyConfirm:SetSize(100, 22)
    applyConfirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
    applyConfirm:SetText("Apply")
    f._applyBtn = applyConfirm
    applyConfirm:SetScript("OnClick", function()
        if not pendingApplySummary or pendingApplySummary.applyCount < 1 then return end
        local build = GetBuildForApply()
        if EbonBuilds.AffixApply and build then
            local canRun, hint = EbonBuilds.AffixApply.CanRun(build)
            if not canRun then
                if EbonBuilds.Toast then EbonBuilds.Toast.Show(hint or "Cannot apply right now.") end
                return
            end
        end
        f:Hide()
        local costLine = ""
        if pendingApplySummary.totalCost > 0 and EbonBuilds.AffixApply then
            costLine = "\n\nEstimated cost: " .. EbonBuilds.AffixApply.FormatCost(pendingApplySummary.totalCost)
        end
        StaticPopupDialogs["EBONBUILDS_APPLY_AFFIXES"].text = string.format(
            "Apply %d affix change%s at the Enchanted Anvil?%s\n\nKeep the anvil open until finished.",
            pendingApplySummary.applyCount,
            pendingApplySummary.applyCount == 1 and "" or "s",
            costLine
        )
        StaticPopup_Show("EBONBUILDS_APPLY_AFFIXES")
    end)

    local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 22)
    cancelBtn:SetPoint("RIGHT", applyConfirm, "LEFT", -6, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    f._scroll       = scroll
    f._scrollChild  = child
    f._scrollBar    = scrollBar
    previewDialog = f
end

local function RefreshPreviewScroll()
    if not previewDialog or not previewDialog._scroll then return end
    local scroll = previewDialog._scroll
    local child  = previewDialog._scrollChild
    local bar    = previewDialog._scrollBar
    local contentWidth = math.max(200, scroll:GetWidth() - 8)
    child:SetWidth(contentWidth)
    if child._rows then
        for _, row in ipairs(child._rows) do
            if row:IsShown() then
                row:SetWidth(contentWidth - 8)
            end
        end
    end
    local overflow = math.max(0, child:GetHeight() - scroll:GetHeight())
    if overflow <= 0 then
        bar:Hide()
        bar:SetMinMaxValues(0, 0)
        child:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    else
        bar:Show()
        bar:SetMinMaxValues(0, overflow)
        bar:SetValue(0)
        child:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    end
end

local function ShowApplyPreview(plan, summary)
    EnsurePreviewDialog()
    local lines = {}
    for _, step in ipairs(plan) do
        lines[#lines + 1] = EbonBuilds.AffixApply.FormatPlanLine(step)
    end

    local summaryText
    if summary.applyCount > 0 then
        local costPart = summary.totalCost > 0
            and (" — est. " .. EbonBuilds.AffixApply.FormatCost(summary.totalCost))
            or ""
        summaryText = string.format("%d to apply, %d skipped%s", summary.applyCount, summary.skipCount, costPart)
    else
        summaryText = string.format("Nothing to apply (%d skipped)", summary.skipCount)
    end
    previewDialog._summary:SetText(summaryText)

    local child = previewDialog._scrollChild
    if child._rows then
        for _, row in ipairs(child._rows) do row:Hide() end
    else
        child._rows = {}
    end

    local y = 0
    for i, line in ipairs(lines) do
        local step = plan[i]
        local row = child._rows[i]
        if not row then
            row = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row:SetJustifyH("LEFT")
            child._rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
        row:SetWidth(360)
        if step and step.skipReason then
            row:SetText("|cff888888" .. line .. "|r")
        else
            row:SetText("|cffffffff" .. line .. "|r")
        end
        row:Show()
        y = y + (row:GetStringHeight() or 12) + 3
    end
    child:SetHeight(math.max(24, y + 4))
    if summary.applyCount > 0 then
        previewDialog._applyBtn:Enable()
    else
        previewDialog._applyBtn:Disable()
    end
    previewDialog:Show()
    RefreshPreviewScroll()
end

local function StartApplyFlow(build)
    build = build or GetBuildForApply()
    if not build then
        if EbonBuilds.Toast then EbonBuilds.Toast.Show("Open a build with stored affixes.") end
        return
    end
    if not EbonBuilds.Build.GetActiveAffixScan(build) then
        if EbonBuilds.Toast then EbonBuilds.Toast.Show("This build has no stored affixes.") end
        return
    end

    local function runPlan()
        local plan, summary = EbonBuilds.AffixApply.BuildPlan(build)
        pendingApplyPlan = plan
        pendingApplySummary = summary
        ShowApplyPreview(plan, summary)
    end

    if ExtractionService and ExtractionService.RequestLearnedAffixes then
        local affixes = ExtractionService.learnedAffixes
        if not affixes or #affixes == 0 then
            ExtractionService.RequestLearnedAffixes()
            C_Timer.After(0.5, runPlan)
            return
        end
    end
    runPlan()
end

function EbonBuilds.AffixView.StartApplyFlow(build)
    if EbonBuilds.AffixApply and EbonBuilds.AffixApply.IsRunning and EbonBuilds.AffixApply.IsRunning() then
        if EbonBuilds.Toast then EbonBuilds.Toast.Show("An apply queue is already running.") end
        return
    end
    StartApplyFlow(build)
end

local function OnApplyClick()
    EbonBuilds.AffixView.StartApplyFlow()
end

local function OnScanClick()
    EbonBuilds.Build.QuickScanInspectedAffixes()
end

local function OnScanMineClick()
    EbonBuilds.Build.QuickScanPlayerAffixes()
end

local function BuildViewFrame(parent)
    local f = CreateFrame("Frame", nil, parent)

    local header = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
    header:SetText("Inspected Gear Affixes")

    applyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    applyBtn:SetSize(110, 22)
    applyBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -34)
    applyBtn:SetText("Apply from Build")
    applyBtn:SetScript("OnClick", OnApplyClick)
    applyBtn:SetScript("OnEnter", function(self)
        if self._hint then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self._hint, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    applyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    importBtn:SetSize(60, 22)
    importBtn:SetPoint("LEFT", applyBtn, "RIGHT", 6, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", OnImportClick)

    exportBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    exportBtn:SetSize(60, 22)
    exportBtn:SetPoint("LEFT", importBtn, "RIGHT", 6, 0)
    exportBtn:SetText("Share")
    exportBtn:SetScript("OnClick", OnExportClick)
    exportBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Share Affixes")
        GameTooltip:AddLine("Copy a text list you can paste to friends or Discord.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    exportBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    scanMineBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    scanMineBtn:SetSize(80, 22)
    scanMineBtn:SetPoint("LEFT", exportBtn, "RIGHT", 6, 0)
    scanMineBtn:SetText("Scan Mine")
    scanMineBtn:SetScript("OnClick", OnScanMineClick)
    scanMineBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Scan Mine")
        GameTooltip:AddLine("Stores affixes from your equipped gear on your class build.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    scanMineBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    scanBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    scanBtn:SetSize(105, 22)
    scanBtn:SetPoint("LEFT", scanMineBtn, "RIGHT", 6, 0)
    scanBtn:SetText("Scan Inspect")
    scanBtn:SetScript("OnClick", OnScanClick)
    scanBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Scan Inspect")
        GameTooltip:AddLine("Stores affixes from the inspected player on your class build.", 1, 1, 1, true)
        GameTooltip:AddLine("Also: /ebb scan or Shift+click minimap (inspect window must be open).", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    scanBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    sourceLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sourceLabel:SetPoint("TOPLEFT",  f, "TOPLEFT",  10, -60)
    sourceLabel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -60)
    sourceLabel:SetJustifyH("LEFT")
    sourceLabel:SetText("Inspect a player, then scan — affixes save to your build for their class.")

    sourceDropdown = CreateFrame("Frame", "EbonBuildsAffixSourceDrop", f, "UIDropDownMenuTemplate")
    sourceDropdown:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -78)
    UIDropDownMenu_SetWidth(sourceDropdown, 180)

    deleteBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    deleteBtn:SetSize(60, 22)
    deleteBtn:SetPoint("LEFT", sourceDropdown, "RIGHT", 8, 2)
    deleteBtn:SetText("Delete")
    deleteBtn:SetScript("OnClick", function()
        PromptDeleteAffixScan()
    end)
    deleteBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Delete the selected scan", nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    deleteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(70, 22)
    clearBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 6, 0)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        StaticPopup_Show("EBONBUILDS_CLEAR_AFFIXES")
    end)

    listScroll = CreateFrame("ScrollFrame", nil, f)
    listScroll:SetPoint("TOPLEFT",     f, "TOPLEFT",     10, -108)
    listScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 10)

    listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetWidth(460)
    listChild:SetHeight(24)
    listScroll:SetScrollChild(listChild)

    listBar = CreateFrame("Slider", nil, listScroll, "UIPanelScrollBarTemplate")
    listBar:SetPoint("TOPLEFT",    listScroll, "TOPRIGHT",    -2, -4)
    listBar:SetPoint("BOTTOMLEFT", listScroll, "BOTTOMRIGHT", -2,  4)
    EbonBuilds.ScrollWheel.SetupBar(listBar)
    listBar:SetValueStep(1)
    listWireWheel = select(1, EbonBuilds.ScrollWheel.Bind(listBar, 16))
    listBar:SetScript("OnValueChanged", function(_, value)
        listChild:SetPoint("TOPLEFT", listScroll, "TOPLEFT", 0, value)
    end)
    listWireWheel(listScroll)
    listWireWheel(listChild)

    local refreshElapsed = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        refreshElapsed = refreshElapsed + elapsed
        if refreshElapsed >= 0.5 then
            refreshElapsed = 0
            RefreshApplyButton()
        end
    end)

    return f
end

function EbonBuilds.AffixView.Mount(container, opts)
    opts = opts or {}
    if opts.build then
        overviewBuild = opts.build
    elseif not overviewBuild and EbonBuilds.BuildForm and EbonBuilds.BuildForm.GetEditingBuild then
        overviewBuild = EbonBuilds.BuildForm.GetEditingBuild()
    end
    if not viewFrame then
        viewFrame = BuildViewFrame(container)
    end
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)
    if scanBtn then scanBtn:Show() end
    if scanMineBtn then scanMineBtn:Show() end
    if clearBtn then clearBtn:Show() end
    if deleteBtn then deleteBtn:Show() end
    if exportBtn then exportBtn:Show() end
    if importBtn then importBtn:Show() end
    if applyBtn then applyBtn:Show() end
    RefreshList()
    viewFrame:Show()
end

function EbonBuilds.AffixView.HidePopups()
    if previewDialog and previewDialog:IsShown() then
        previewDialog:Hide()
    end
    if EbonBuilds.AffixApply and EbonBuilds.AffixApply.CancelQueue then
        EbonBuilds.AffixApply.CancelQueue()
    end
    RefreshApplyButton()
end

function EbonBuilds.AffixView.RefreshIfMounted(build)
    if not viewFrame or not viewFrame:IsShown() then return end
    if build then
        local current = GetTargetBuild()
        if current and current.id ~= build.id then return end
    end
    RefreshList()
end

function EbonBuilds.AffixView.Unmount()
    overviewBuild = nil
    if viewFrame then viewFrame:Hide() end
    RefreshApplyButton()
end

function EbonBuilds.AffixView.Init()
    StaticPopupDialogs["EBONBUILDS_CLEAR_AFFIXES"] = {
        text = "Clear all stored affix scans for this build?\n\nThis cannot be undone.",
        button1 = "Clear All",
        button2 = "Cancel",
        OnAccept = function()
            ClearAllAffixScans()
            RefreshList()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["EBONBUILDS_REMOVE_AFFIX_SCAN"] = {
        text = "Delete the selected affix scan from this build?",
        button1 = "Delete",
        button2 = "Cancel",
        OnAccept = function()
            local source = pendingDeleteSource
            pendingDeleteSource = nil
            if source then
                RemoveAffixScanBySource(source)
                if EbonBuilds.Toast then
                    EbonBuilds.Toast.Show("Deleted affix scan from " .. source .. ".")
                end
            end
            RefreshList()
        end,
        OnCancel = function()
            pendingDeleteSource = nil
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["EBONBUILDS_APPLY_AFFIXES"] = {
        text = "Apply affix changes from this build at the Enchanted Anvil?\n\nKeep the anvil open until finished.",
        button1 = "Apply",
        button2 = "Cancel",
        OnAccept = function()
            if not pendingApplyPlan or not EbonBuilds.AffixApply then return end
            local steps = {}
            for _, step in ipairs(pendingApplyPlan) do
                if not step.skipReason then
                    steps[#steps + 1] = step
                end
            end
            if #steps == 0 then
                if EbonBuilds.Toast then EbonBuilds.Toast.Show("Nothing to apply.") end
                return
            end
            local costText = ""
            if pendingApplySummary and pendingApplySummary.totalCost > 0 then
                costText = string.format(" (~%dg est.)", math.floor(pendingApplySummary.totalCost / 10000))
            end
            if EbonBuilds.Toast then
                EbonBuilds.Toast.Show(string.format("Applying %d affix change%s%s…", #steps, #steps == 1 and "" or "s", costText))
            end
            EbonBuilds.AffixApply.RunPlan(pendingApplyPlan, function(idx, total, step)
                if EbonBuilds.Toast and step then
                    EbonBuilds.Toast.Show(string.format("Applying %d/%d: %s", idx, total, step.toAffix))
                end
            end, function()
                RefreshList()
                RefreshApplyButton()
                if EbonBuilds.AnvilIntegration and EbonBuilds.AnvilIntegration.RefreshButton then
                    EbonBuilds.AnvilIntegration.RefreshButton()
                end
            end)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end
