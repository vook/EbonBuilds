-- EbonBuilds: modules/build/ExportImport.lua
-- Responsibility: serialise a build to base64-encoded JSON for sharing,
-- and deserialise an imported string back into a new build.

EbonBuilds.ExportImport = {}

------------------------------------------------------------------------
-- Base64
------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local BASE64_CHUNK = 2000
local function Base64Encode(data)
	local out = {}
	local len = #data
	for i = 1, len, 3 do
		local a, b, c = data:byte(i, i + 2)
		a, b, c = a or 0, b or 0, c or 0
		local n = a * 65536 + b * 256 + c
		out[#out + 1] = B64:byte(math.floor(n / 262144) + 1)
		out[#out + 1] = B64:byte(math.floor((n % 262144) / 4096) + 1)
		out[#out + 1] = i + 1 <= len and B64:byte(math.floor((n % 4096) / 64) + 1) or 61
		out[#out + 1] = i + 2 <= len and B64:byte(math.floor(n % 64) + 1) or 61
	end
	local chunks = {}
	for i = 1, #out, BASE64_CHUNK do
		chunks[#chunks + 1] = string.char(unpack(out, i, math.min(i + BASE64_CHUNK - 1, #out)))
	end
	return table.concat(chunks)
end

local function Base64Decode(s)
	local rev = {}
	for i = 1, #B64 do rev[B64:byte(i)] = i - 1 end
	rev[61] = 0
	local out = {}
	local len = #s
	for i = 1, len, 4 do
		local a = rev[s:byte(i)] or 0
		local b = rev[s:byte(i + 1)] or 0
		local c = rev[s:byte(i + 2)] or 0
		local d = rev[s:byte(i + 3)] or 0
		local n = a * 262144 + b * 4096 + c * 64 + d
		out[#out + 1] = string.char(math.floor(n / 65536))
		if s:byte(i + 2) ~= 61 then
			out[#out + 1] = string.char(math.floor((n % 65536) / 256))
		end
		if s:byte(i + 3) ~= 61 then
			out[#out + 1] = string.char(math.floor(n % 256))
		end
	end
	return table.concat(out)
end

------------------------------------------------------------------------
-- Minimal JSON encoder (handles the build data structure)
------------------------------------------------------------------------

local function IsArray(tbl)
	if type(tbl) ~= "table" then return false end
	local count, maxIdx = 0, 0
	for k in pairs(tbl) do
		if type(k) ~= "number" or k < 1 then return false end
		count = count + 1
		if k > maxIdx then maxIdx = k end
	end
	return count == maxIdx
end

EbonBuilds.ExportImport.JSONEncode = function(value)
	local t = type(value)
	if t == "nil" then return "null"
	elseif t == "boolean" then return value and "true" or "false"
	elseif t == "number" then
		if value ~= value then return "null" end -- NaN
		if value == math.huge or value == -math.huge then return "null" end
		return tostring(value)
	elseif t == "string" then
		local escaped = value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
		return '"' .. escaped .. '"'
	elseif t == "table" then
		local parts = {}
		if IsArray(value) then
			for i = 1, #value do parts[#parts + 1] = JSONEncode(value[i]) end
			return "[" .. table.concat(parts, ",") .. "]"
		else
			for k, v in pairs(value) do
				if v ~= nil then
					parts[#parts + 1] = JSONEncode(tostring(k)) .. ":" .. JSONEncode(v)
				end
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
	end
	return "null"
end

------------------------------------------------------------------------
-- Minimal JSON decoder
------------------------------------------------------------------------

local function SkipWhitespace(s, pos)
	while pos <= #s do
		local c = s:byte(pos)
		if c ~= 32 and c ~= 9 and c ~= 10 and c ~= 13 then break end
		pos = pos + 1
	end
	return pos
end

local function ParseValue(s, pos)
	pos = SkipWhitespace(s, pos)
	if pos > #s then return nil, pos end
	local c = s:byte(pos)
	if c == 110 then -- null
		return nil, pos + 4
	elseif c == 116 then -- true
		return true, pos + 4
	elseif c == 102 then -- false
		return false, pos + 5
	elseif c == 34 then -- string
		local out = {}
		pos = pos + 1
		while pos <= #s do
			local cc = s:byte(pos)
			if cc == 34 then
				return table.concat(out), pos + 1
			elseif cc == 92 then -- backslash
				pos = pos + 1
				local ec = s:byte(pos)
				if ec == 110 then out[#out + 1] = "\n"
				elseif ec == 114 then out[#out + 1] = "\r"
				elseif ec == 116 then out[#out + 1] = "\t"
				elseif ec == 92 then out[#out + 1] = "\\"
				elseif ec == 34 then out[#out + 1] = '"'
				else out[#out + 1] = s:sub(pos, pos) end
			else
				out[#out + 1] = s:sub(pos, pos)
			end
			pos = pos + 1
		end
		return table.concat(out), pos
	elseif c == 91 then -- array
		local arr = {}
		pos = pos + 1
		pos = SkipWhitespace(s, pos)
		if s:byte(pos) == 93 then return arr, pos + 1 end
		while true do
			local val
			val, pos = ParseValue(s, pos)
			arr[#arr + 1] = val
			pos = SkipWhitespace(s, pos)
			if s:byte(pos) == 93 then return arr, pos + 1 end
			pos = pos + 1 -- skip comma
		end
	elseif c == 123 then -- object
		local obj = {}
		pos = pos + 1
		pos = SkipWhitespace(s, pos)
		if s:byte(pos) == 125 then return obj, pos + 1 end
		while true do
			local key
			key, pos = ParseValue(s, pos)
			pos = SkipWhitespace(s, pos)
			pos = pos + 1 -- skip colon
			local val
			val, pos = ParseValue(s, pos)
			if key ~= nil then obj[key] = val end
			pos = SkipWhitespace(s, pos)
			if s:byte(pos) == 125 then return obj, pos + 1 end
			pos = pos + 1 -- skip comma
		end
	else -- number
		local startPos = pos
		if c == 45 then pos = pos + 1 end -- negative sign
		while pos <= #s do
			local nc = s:byte(pos)
			if nc >= 48 and nc <= 57 or nc == 46 or nc == 101 or nc == 69 or nc == 43 then
				pos = pos + 1
			else
				break
			end
		end
		return tonumber(s:sub(startPos, pos - 1)), pos
	end
end

EbonBuilds.ExportImport.JSONDecode = function(s)
	if not s or s == "" then return nil end
	local val = ParseValue(s, 1)
	return val
end

------------------------------------------------------------------------
-- Export / Import logic
------------------------------------------------------------------------

local EXPORT_VERSION = 1

local function BuildExportData(build)
	local filteredWeights = {}
	if build.echoWeights then
		for name, weight in pairs(build.echoWeights) do
			if type(weight) == "number" and weight > 0 then
				filteredWeights[name] = weight
			end
		end
	end

	return {
		v = EXPORT_VERSION,
		title = build.title,
		class = build.class,
		spec = build.spec,
		comments = build.comments,
		lockedEchoes = build.lockedEchoes or { nil, nil, nil, nil },
		echoWeights = filteredWeights,
		settings = build.settings,
		automationEnabled = build.automationEnabled,
		isPublic = build.isPublic or false,
		validated = build.validated or false,
		author = build.author,
		lastModified = build.lastModified,
		copiedFrom = build.copiedFrom or nil,
	}
end

function EbonBuilds.ExportImport.ExportBuild(build)
	if not build then return nil end
	local data = BuildExportData(build)
	local json = EbonBuilds.ExportImport.JSONEncode(data)
	return Base64Encode(json)
end

function EbonBuilds.ExportImport.DecodeBuild(b64String)
	if not b64String or b64String == "" then return nil end
	local json = Base64Decode(b64String)
	if not json or json == "" then return nil end
	local data = EbonBuilds.ExportImport.JSONDecode(json)
	if not data or type(data) ~= "table" then return nil end

	local locked = data.lockedEchoes or {}
	for i = 1, 4 do locked[i] = locked[i] or nil end

	local echoWeights = nil
	if data.echoWeights and next(data.echoWeights) then
		echoWeights = {}
		for name, weight in pairs(data.echoWeights) do
			echoWeights[name] = weight
		end
	end

	local build = EbonBuilds.Build.NewObject({
		title       = data.title    or "Imported Build",
		class       = data.class    or EbonBuilds.Build.PlayerClassToken(),
		spec        = data.spec     or 1,
		comments    = data.comments or "",
		lockedEchoes = locked,
		echoWeights = echoWeights,
		settings    = data.settings or EbonBuilds.Build.DefaultSettings(),
		automationEnabled = data.automationEnabled,
		isPublic    = data.isPublic or false,
		validated   = data.validated or false,
		author      = data.author,
		lastModified = data.lastModified,
		copiedFrom  = data.copiedFrom or nil,
	})
	EbonBuilds.Build.EnsureSettings(build)
	return build
end

function EbonBuilds.ExportImport.ImportBuild(b64String)
	local build = EbonBuilds.ExportImport.DecodeBuild(b64String)
	if not build then return nil end
	EbonBuildsDB.builds[build.id] = build
	EbonBuilds.Build.SetActive(build.id)
	return build
end

------------------------------------------------------------------------
-- Export dialog
------------------------------------------------------------------------

local exportDialog

local function CreateExportDialog()
	local f = CreateFrame("Frame", "EbonBuildsExportBuildDialog", UIParent)
	f:SetSize(700, 420)
	f:SetPoint("CENTER")
	f:SetBackdrop({
		bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 16, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	f:SetBackdropColor(0, 0, 0, 0.9)
	f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then self:StartMoving() end
	end)
	f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", f, "TOP", 0, -12)
	title:SetText("Export Build")

	local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	close:SetSize(80, 22)
	close:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
	close:SetText("Close")
	close:SetScript("OnClick", function() f:Hide() end)

	local scroll = CreateFrame("ScrollFrame", "EbonBuildsExportScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOP",    title, "BOTTOM", 0, -8)
	scroll:SetPoint("BOTTOM", close, "TOP",     0,  8)
	scroll:SetPoint("LEFT",   f,     "LEFT",   14,  0)
	scroll:SetPoint("RIGHT",  f,     "RIGHT", -14,  0)

	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetMaxLetters(0)
	box:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
	box:SetWidth(640)
	box:SetAutoFocus(false)
	box:SetScript("OnEscapePressed", function() f:Hide() end)
	scroll:SetScrollChild(box)

	f._editBox = box
	exportDialog = f
end

function EbonBuilds.ExportImport.ShowExportDialog(build)
	if not exportDialog then CreateExportDialog() end
	local b64 = EbonBuilds.ExportImport.ExportBuild(build)
	if not b64 then return end
	exportDialog._editBox:SetText(b64)
	exportDialog._editBox:HighlightText()
	exportDialog:Show()
end

------------------------------------------------------------------------
-- Import dialog
------------------------------------------------------------------------

local importDialog

local function CreateImportDialog()
	local f = CreateFrame("Frame", "EbonBuildsImportBuildDialog", UIParent)
	f:SetSize(700, 420)
	f:SetPoint("CENTER")
	f:SetBackdrop({
		bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 16, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	f:SetBackdropColor(0, 0, 0, 0.9)
	f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" then self:StartMoving() end
	end)
	f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", f, "TOP", 0, -12)
	title:SetText("Import Build")

	local import = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	import:SetSize(80, 22)
	import:SetPoint("BOTTOM", f, "BOTTOM", -50, 12)
	import:SetText("Import")
	import:SetScript("OnClick", function()
		local text = f._editBox:GetText() or ""
		local build = EbonBuilds.ExportImport.ImportBuild(text)
		if build then
			f:Hide()
			if EbonBuilds.BuildList and EbonBuilds.BuildList.Refresh then
				EbonBuilds.BuildList.Refresh()
			end
			EbonBuilds.ViewRouter.Show("buildOverview", { build = build })
		else
			f._error:Show()
		end
	end)

	local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	cancel:SetSize(80, 22)
	cancel:SetPoint("BOTTOM", f, "BOTTOM", 50, 12)
	cancel:SetText("Cancel")
	cancel:SetScript("OnClick", function() f:Hide() end)

	local scroll = CreateFrame("ScrollFrame", "EbonBuildsImportScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOP",    title,  "BOTTOM", 0, -8)
	scroll:SetPoint("BOTTOM", import, "TOP",     0,  8)
	scroll:SetPoint("LEFT",   f,      "LEFT",   14,  0)
	scroll:SetPoint("RIGHT",  f,      "RIGHT", -14,  0)

	local box = CreateFrame("EditBox", nil, scroll)
	box:SetMultiLine(true)
	box:SetMaxLetters(0)
	box:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
	box:SetWidth(640)
	box:SetAutoFocus(false)
	box:SetScript("OnEscapePressed", function() f:Hide() end)
	scroll:SetScrollChild(box)

	local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	hint:SetPoint("TOPLEFT",  box, "TOPLEFT",  2, -2)
	hint:SetPoint("TOPRIGHT", box, "TOPRIGHT", -2, -2)
	hint:SetJustifyH("LEFT")
	hint:SetJustifyV("TOP")
	hint:SetTextColor(0.5, 0.5, 0.5, 1)
	hint:SetText("Paste the exported build string here and click Import.")

	box:SetScript("OnEditFocusGained", function() hint:Hide() end)
	box:SetScript("OnEditFocusLost", function()
		if (box:GetText() or "") == "" then hint:Show() end
	end)
	box:SetScript("OnTextChanged", function()
		if box:HasFocus() then hint:Hide()
		elseif (box:GetText() or "") == "" then hint:Show()
		else hint:Hide() end
	end)

	local error = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	error:SetPoint("BOTTOM", import, "TOP", 0, 4)
	error:SetTextColor(1, 0.3, 0.3, 1)
	error:SetText("Invalid import string. Please check and try again.")
	error:Hide()
	f._error = error

	f._editBox = box
	importDialog = f
end

function EbonBuilds.ExportImport.ShowImportDialog()
	if not importDialog then CreateImportDialog() end
	importDialog._editBox:SetText("")
	importDialog._error:Hide()
	importDialog:Show()
	importDialog._editBox:SetFocus()
end
