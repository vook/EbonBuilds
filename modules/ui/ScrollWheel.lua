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
