-- EbonBuilds: modules/ui/ScrollWheel.lua
-- Forward mouse-wheel events to a scrollbar from scroll frames and child widgets.

EbonBuilds.ScrollWheel = {}

function EbonBuilds.ScrollWheel.Apply(bar, delta, step)
    if not bar or not delta then return end
    step = step or 16
    local current = bar:GetValue()
    local min, max = bar:GetMinMaxValues()
    if max <= min then return end
    bar:SetValue(math.max(min, math.min(max, current - delta * step)))
end

function EbonBuilds.ScrollWheel.SetupBar(bar)
    if bar and bar.SetOrientation then
        bar:SetOrientation("VERTICAL")
    end
end

-- Returns wire(frame) to attach the same wheel handler to scroll children/rows.
function EbonBuilds.ScrollWheel.Bind(bar, step)
    local function onWheel(_, delta)
        EbonBuilds.ScrollWheel.Apply(bar, delta, step)
    end
    local function wire(frame)
        if not frame or frame._ebonScrollWheelWired then return end
        if not frame.EnableMouseWheel then return end
        frame._ebonScrollWheelWired = true
        frame:EnableMouseWheel(true)
        frame:SetScript("OnMouseWheel", onWheel)
    end
    return wire, onWheel
end

function EbonBuilds.ScrollWheel.WireFrame(frame, bar, step)
    local wire = select(1, EbonBuilds.ScrollWheel.Bind(bar, step))
    wire(frame)
end

-- Forward wheel events from nested widgets (sliders, labels, etc.) to a page scrollbar.
function EbonBuilds.ScrollWheel.WireDescendants(root, bar, step, shouldSkip)
    if not root or not bar then return end
    local wire = select(1, EbonBuilds.ScrollWheel.Bind(bar, step))
    local function visit(frame)
        if not frame or frame == bar then return end
        if shouldSkip and shouldSkip(frame) then return end
        wire(frame)
        if frame.GetNumChildren then
            for i = 1, frame:GetNumChildren() do
                visit(select(i, frame:GetChildren()))
            end
        end
    end
    visit(root)
end

function EbonBuilds.ScrollWheel.WireSliderScroll(scrollFrame, scrollChild, bar, step, opts)
    opts = opts or {}
    step = step or 20
    if not scrollFrame or not scrollChild or not bar then return end

    EbonBuilds.ScrollWheel.SetupBar(bar)
    local wire = select(1, EbonBuilds.ScrollWheel.Bind(bar, step))
    wire(scrollFrame)
    wire(scrollChild)

    bar:SetScript("OnValueChanged", function(self, value)
        scrollChild:ClearAllPoints()
        scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, value)
    end)

    EbonBuilds.ScrollWheel.WireDescendants(scrollChild, bar, step, opts.shouldSkip)

    if opts.onRangeChanged then
        opts.onRangeChanged()
    end
end
