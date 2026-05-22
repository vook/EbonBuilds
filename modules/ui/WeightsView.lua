-- EbonBuilds: modules/ui/WeightsView.lua
-- Responsibility: host the Filters bar + EchoTable. Exposes Mount/Unmount so
-- any container (e.g. a tab page) can embed it on demand.

EbonBuilds.WeightsView = {}

local viewFrame

local function BuildViewFrame(parent)
    local f = CreateFrame("Frame", nil, parent)

    local header = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
    header:SetText("Echo Weights")
    f._header = header
    return f
end

local function EnsureBuilt(container)
    if viewFrame then return end
    viewFrame = BuildViewFrame(container)
    EbonBuilds.Filters.Init(viewFrame)
    EbonBuilds.EchoTable.Init(viewFrame)
end

local function RefreshHeader()
    if not viewFrame then return end
    local build = EbonBuilds.Build.GetActive()
    if build then
        viewFrame._header:SetText("Echo Weights - " .. (build.title or ""))
    else
        viewFrame._header:SetText("Echo Weights")
    end
end

function EbonBuilds.WeightsView.Mount(container)
    EnsureBuilt(container)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)
    RefreshHeader()
    viewFrame:Show()
    EbonBuilds.Filters.FocusSearch()
end

function EbonBuilds.WeightsView.Unmount()
    if viewFrame then viewFrame:Hide() end
end

function EbonBuilds.WeightsView.Init()
    if EbonBuilds.Build and EbonBuilds.Build.OnActiveChanged then
        EbonBuilds.Build.OnActiveChanged(RefreshHeader)
    end
end
