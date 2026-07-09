-- EbonBuilds: modules/ui/EchoTableColumns.lua
-- Shared column geometry for the Echoes tab (headers + rows).
-- Column order (left to right): Icon | Name | Tome | Policy | Score | Weight

EbonBuilds.EchoTableColumns = {}

local C = EbonBuilds.EchoTableColumns

C.ICON_PAD             = 4
C.COL_ICON             = 40
C.COL_TOME             = 36
C.COL_SCORE            = 96
C.COL_POLICY           = 108
C.COL_WEIGHT           = 58
C.COL_GAP              = 4
C.COL_GAP_POLICY_SCORE = 16
-- UIDropDownMenuTemplate bleeds left of its frame; keep columns clear of policy.
C.COL_GAP_BEFORE_POLICY = 24
C.PAD_R                = 8

-- Left edge of the name column (matches icon frame + gap in rows).
C.NAME_LEFT            = C.ICON_PAD + C.COL_ICON + C.COL_GAP

-- Distance from the row's right edge to each column's right edge.
C.INSET_WEIGHT         = C.PAD_R
C.INSET_SCORE          = C.INSET_WEIGHT + C.COL_WEIGHT + C.COL_GAP
C.INSET_POLICY         = C.INSET_SCORE + C.COL_SCORE + C.COL_GAP_POLICY_SCORE
C.INSET_TOME           = C.INSET_POLICY + C.COL_POLICY + C.COL_GAP_BEFORE_POLICY
C.INSET_NAME           = C.INSET_TOME + C.COL_TOME + C.COL_GAP

function C.GetNameLeft()
    return C.NAME_LEFT
end

function C.GetNameRightInset()
    return C.INSET_NAME
end

function C.GetScoreRightInset()
    return C.INSET_SCORE
end

function C.GetPolicyRightInset()
    return C.INSET_POLICY
end

function C.GetTomeRightInset()
    return C.INSET_TOME
end

function C.GetWeightRightInset()
    return C.INSET_WEIGHT
end

-- Anchor a column's right edge; optional width for fixed-width cells.
function C.AnchorColumnRight(frame, row, inset, width)
    frame:ClearAllPoints()
    frame:SetPoint("RIGHT", row, "RIGHT", -inset, 0)
    if width then
        if frame.SetWidth then
            frame:SetWidth(width)
        elseif frame.SetSize then
            local h = frame:GetHeight()
            if not h or h == 0 then h = 18 end
            frame:SetSize(width, h)
        end
    end
end

-- Anchor both edges so text/controls stay inside the column.
function C.AnchorBoundedColumn(frame, row, inset, width)
    C.AnchorColumnRight(frame, row, inset, width)
    frame:SetPoint("LEFT", row, "RIGHT", -(inset + width), 0)
end
