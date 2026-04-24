-- EbonBuilds: modules/ui/WeightsView.lua
-- Responsibility: host the Filters bar + EchoTable inside the ViewRouter right
-- panel. Keeps a single view container that is re-shown on demand.

EbonBuilds.WeightsView = {}

local viewFrame
local initialised = false

local function BuildViewFrame(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)

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
    initialised = true
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

local view = {}

function view.Show(container, _context)
    EnsureBuilt(container)
    viewFrame:SetParent(container)
    viewFrame:ClearAllPoints()
    viewFrame:SetAllPoints(container)
    RefreshHeader()
    viewFrame:Show()
end

function view.Hide()
    if viewFrame then viewFrame:Hide() end
end

function EbonBuilds.WeightsView.Init()
    EbonBuilds.ViewRouter.Register("weights", view)
    if EbonBuilds.Build and EbonBuilds.Build.OnActiveChanged then
        EbonBuilds.Build.OnActiveChanged(RefreshHeader)
    end
end
