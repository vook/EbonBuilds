-- EbonBuilds: modules/ui/EchoTableRows.lua
-- Responsibility: data preparation and row-frame factory for EchoTable.

EbonBuilds.EchoTableRows = {}

local COL_ICON   = 40
local COL_WEIGHT = 80
local ROW_HEIGHT = 36

------------------------------------------------------------------------
-- Data preparation
------------------------------------------------------------------------

-- Returns a map: comment -> { spellId, quality } keeping highest quality.
local function BuildBestByName()
    local best = {}
    for spellId, data in pairs(ProjectEbonhold.PerkDatabase) do
        local name = data.comment
        if name and name ~= "" then
            local existing = best[name]
            if not existing or data.quality > existing.quality then
                best[name] = { spellId = spellId, quality = data.quality }
            end
        end
    end
    return best
end

-- Returns a list sorted alphabetically: { { spellId, name, quality }, ... }.
function EbonBuilds.EchoTableRows.BuildSortedList()
    local best = BuildBestByName()
    local list = {}
    for name, entry in pairs(best) do
        list[#list + 1] = { spellId = entry.spellId, name = name, quality = entry.quality }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

------------------------------------------------------------------------
-- Icon cell
------------------------------------------------------------------------

local function CreateIconFrame(row)
    local frame = CreateFrame("Frame", nil, row)
    frame:SetWidth(COL_ICON)
    frame:SetHeight(ROW_HEIGHT)
    frame:SetPoint("LEFT", row, "LEFT", 4, 0)
    frame:EnableMouse(true)
    frame.spellId = 0

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetWidth(28)
    tex:SetHeight(28)
    tex:SetPoint("CENTER", frame, "CENTER")
    frame.icon = tex
    return frame
end

local function WireIconTooltip(iconFrame)
    iconFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpell(self.spellId, "BOOKTYPE_SPELL")
        GameTooltip:Show()
    end)
    iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

------------------------------------------------------------------------
-- Weight cell
------------------------------------------------------------------------

local function RestoreWeight(editBox)
    editBox:SetText(tostring(EbonBuilds.Weights.Get(editBox.echoName)))
end

local function CommitWeight(editBox)
    local raw = editBox:GetText()
    local num = tonumber(raw)
    if num and math.floor(num) == num and num >= 0 then
        EbonBuilds.Weights.Set(editBox.echoName, num)
        editBox:SetText(tostring(EbonBuilds.Weights.Get(editBox.echoName)))
    else
        RestoreWeight(editBox)
    end
end

local function WireWeightBox(editBox)
    editBox:SetScript("OnChar", function(self, char)
        if not char:match("%d") then
            local pos  = self:GetCursorPosition()
            local text = self:GetText()
            self:SetText(text:sub(1, pos - 1) .. text:sub(pos + 1))
            self:SetCursorPosition(pos - 1)
        end
    end)
    editBox:SetScript("OnEnterPressed", function(self)
        CommitWeight(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusLost",   function(self) CommitWeight(self) end)
    editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
end

local function CreateWeightBox(row)
    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetWidth(COL_WEIGHT - 8)
    box:SetHeight(20)
    box:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(9)
    WireWeightBox(box)
    return box
end

------------------------------------------------------------------------
-- Row factory
------------------------------------------------------------------------

local function AddBackground(row, index)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    if index % 2 == 0 then
        bg:SetTexture(0, 0, 0, 0.15)
    else
        bg:SetTexture(0, 0, 0, 0.05)
    end
end

-- Creates a single pooled row frame attached to parent.
function EbonBuilds.EchoTableRows.CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("LEFT",  parent, "LEFT",  0, 0)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    AddBackground(row, index)

    local iconFrame = CreateIconFrame(row)
    WireIconTooltip(iconFrame)

    local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("LEFT",  iconFrame, "RIGHT", 4, 0)
    nameLabel:SetPoint("RIGHT", row,       "RIGHT", -(COL_WEIGHT + 8), 0)
    nameLabel:SetJustifyH("LEFT")

    local weightBox = CreateWeightBox(row)

    row.iconFrame = iconFrame
    row.nameLabel = nameLabel
    row.weightBox = weightBox
    row:Hide()
    return row
end

-- Populates a row frame with data from an echo list entry.
function EbonBuilds.EchoTableRows.Populate(row, yOffset, entry)
    row:SetPoint("TOP", row:GetParent(), "TOP", 0, yOffset)
    row.iconFrame.spellId = entry.spellId
    row.iconFrame.icon:SetTexture(select(3, GetSpellInfo(entry.spellId)))
    row.nameLabel:SetText(entry.name)
    row.weightBox.echoName = entry.name
    row.weightBox:SetText(tostring(EbonBuilds.Weights.Get(entry.name)))
    row:Show()
end
