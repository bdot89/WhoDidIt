--[[--------------------------------------------------------------------
	WhoDidIt - window
----------------------------------------------------------------------]]

local W = WhoDidIt
local UI = {}
W.UI = UI

local floor = math.floor
local getn = table.getn
local FmtTime = W.FmtTime
local FmtNum = W.FmtNum

local WIDTH, HEIGHT = 940, 562
local LEFTW = 230
local ROWH, NROWS = 16, 21
local FROWH, FROWS = 30, 10

UI.tab = "summary"
UI.meter = "dmg"
UI.selIdx = 1
UI.detail = nil; UI.cause = nil
UI.liveRec = nil

local RESULT = {
	KILL  = "|cff33ff33KILL|r",
	WIPE  = "|cffff3333WIPE|r",
	RESET = "|cffff9933RESET|r",
	LIVE  = "|cff33ccffLIVE|r",
}

local KIND_COLOR = {
	death = "|cffff4444", aggro = "|cffff9933", avoid = "|cffffff55", kill = "|cff33ff33",
	pull = "|cff33ccff", enrage = "|cffff55ff", mc = "|cffcc77ff", cast = "|cff999999",
	tranq = "|cffaad372", interrupt = "|cffff7755", fail = "|cffff5555", boss = "|cffcccccc",
	debuff = "|cffcc99ff", info = "|cff888888", wipe = "|cffff3333", taunt = "|cffffaa55",
	save = "|cff33ff33",
}


------------------------------------------------------------------ list widget

local function CreateList(parent, nrows, rowh, width)
	local L = CreateFrame("Frame", nil, parent)
	L:SetWidth(width)
	L:SetHeight(nrows * rowh)
	L.nrows, L.rowh, L.offset, L.data, L.rows = nrows, rowh, 0, {}, {}
	local rowW = width - 18
	L.rowW = rowW

	local function wheel()
		L:Scroll(arg1 > 0 and -3 or 3)
	end
	L:EnableMouseWheel(true)
	L:SetScript("OnMouseWheel", wheel)

	for i = 1, nrows do
		local b = CreateFrame("Button", nil, L)
		b:SetWidth(rowW)
		b:SetHeight(rowh)
		b:SetPoint("TOPLEFT", L, "TOPLEFT", 0, -(i - 1) * rowh)
		b:EnableMouseWheel(true)
		b:SetScript("OnMouseWheel", wheel)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

		b.stripe = b:CreateTexture(nil, "BACKGROUND")
		b.stripe:SetAllPoints(b)

		b.bar = b:CreateTexture(nil, "BORDER")
		b.bar:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
		b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -1)
		b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 1)
		b.bar:Hide()

		local hl = b:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints(b)
		hl:SetTexture(1, 1, 1, 0.08)

		b.r = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.r:SetPoint("RIGHT", b, "RIGHT", -4, 0)
		b.r:SetJustifyH("RIGHT")

		b.l = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.l:SetPoint("LEFT", b, "LEFT", 4, 0)
		b.l:SetJustifyH("LEFT")
		b.l:SetHeight(rowh)

		b:SetScript("OnEnter", function() UI.RowEnter(this) end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:SetScript("OnClick", function()
			local d = this.d
			if not (d and d.click) then return end
			-- x = where on the row it was clicked, so a row can tell its columns apart
			local cx = GetCursorPosition()
			local x = cx / this:GetEffectiveScale() - (this:GetLeft() or 0)
			d.click(d, arg1, x)
		end)
		L.rows[i] = b
	end

	local s = CreateFrame("Slider", nil, L)
	s:SetOrientation("VERTICAL")
	s:SetWidth(14)
	s:SetPoint("TOPRIGHT", L, "TOPRIGHT", 0, 0)
	s:SetPoint("BOTTOMRIGHT", L, "BOTTOMRIGHT", 0, 0)
	s:SetBackdrop({
		bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
		edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
		tile = true, tileSize = 8, edgeSize = 8,
		insets = { left = 3, right = 3, top = 6, bottom = 6 },
	})
	s:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
	s:SetMinMaxValues(0, 0)
	s:SetValueStep(1)
	s:SetValue(0)
	s:SetScript("OnValueChanged", function()
		if L.updating then return end
		L.offset = floor(this:GetValue() + 0.5)
		L:Refresh()
	end)
	L.slider = s

	function L:MaxOffset()
		return math.max(0, getn(self.data) - self.nrows)
	end

	function L:SetData(data, keepOffset)
		self.data = data or {}
		if not keepOffset then self.offset = 0 end
		if self.offset > self:MaxOffset() then self.offset = self:MaxOffset() end
		self:Refresh()
	end

	function L:Scroll(delta)
		local o = self.offset + delta
		if o < 0 then o = 0 end
		if o > self:MaxOffset() then o = self:MaxOffset() end
		self.offset = o
		self:Refresh()
	end

	function L:Refresh()
		local max = self:MaxOffset()
		self.updating = true
		self.slider:SetMinMaxValues(0, max)
		self.slider:SetValue(self.offset)
		self.updating = false
		if max == 0 then self.slider:Hide() else self.slider:Show() end
		for i = 1, self.nrows do
			local b = self.rows[i]
			local d = self.data[self.offset + i]
			b.d = d
			if d then
				b.c = b.c or {}
				local ncols = d.cols and getn(d.cols) or 0
				if ncols > 0 then
					-- table row: every cell on a fixed column
					b.l:SetText("")
					b.r:SetText("")
					for j = 1, ncols do
						local c = d.cols[j]
						local fs = b.c[j]
						if not fs then
							fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
							fs:SetHeight(self.rowh)
							b.c[j] = fs
						end
						fs:ClearAllPoints()
						fs:SetPoint("LEFT", b, "LEFT", c[1], 0)
						fs:SetWidth(c[2])
						fs:SetJustifyH(c[4] or "LEFT")
						fs:SetText(c[3] or "")
						fs:Show()
					end
				else
					b.r:SetText(d.r or "")
					b.l:SetText(d.l or "")
					local rw = (d.r and d.r ~= "") and (b.r:GetStringWidth() + 12) or 0
					b.l:SetWidth(self.rowW - rw - 8)
				end
				for j = ncols + 1, getn(b.c) do b.c[j]:Hide() end
				-- raid mark icons: d.icons = { { x, mark }, ... }
				b.ic = b.ic or {}
				local nic = d.icons and getn(d.icons) or 0
				for j = 1, nic do
					local tex = b.ic[j]
					if not tex then
						tex = b:CreateTexture(nil, "OVERLAY")
						tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
						tex:SetWidth(14)
						tex:SetHeight(14)
						b.ic[j] = tex
					end
					local m = d.icons[j][2]
					local cx, cy = math.mod(m - 1, 4), floor((m - 1) / 4)
					tex:SetTexCoord(cx * 0.25, cx * 0.25 + 0.25, cy * 0.25, cy * 0.25 + 0.25)
					tex:ClearAllPoints()
					tex:SetPoint("LEFT", b, "LEFT", d.icons[j][1], 0)
					tex:Show()
				end
				for j = nic + 1, getn(b.ic) do b.ic[j]:Hide() end
				-- icon cells (the Consumes grid): d.grid = { { x, state, icon, title, tip, text }, ... }
				b.g = b.g or {}
				local ng = d.grid and getn(d.grid) or 0
				for j = 1, ng do
					if not b.g[j] then b.g[j] = UI.GridCell(b, self.rowh - 4, wheel) end
					UI.SetGridCell(b.g[j], d.grid[j], b)
				end
				for j = ng + 1, getn(b.g) do b.g[j]:Hide() end
				if d.bar then
					b.bar:SetWidth(math.max(1, self.rowW * math.min(1, d.bar)))
					b.bar:SetVertexColor(d.cr or 0.5, d.cg or 0.5, d.cb or 0.5, d.ba or 0.45)
					b.bar:Show()
				else
					b.bar:Hide()
				end
				if d.sel then
					b.stripe:SetTexture(0.9, 0.7, 0.1, 0.22)
				elseif d.head then
					b.stripe:SetTexture(0.25, 0.25, 0.32, 0.55)
				elseif math.mod(self.offset + i, 2) == 0 then
					b.stripe:SetTexture(1, 1, 1, 0.035)
				else
					b.stripe:SetTexture(0, 0, 0, 0)
				end
				b:Show()
			else
				b:Hide()
			end
		end
	end

	return L
end

-- one icon cell of a grid row: coloured edge, icon, hover tooltip; a click
-- counts as a click on its row
UI.GRID_LOOK = {   -- edge r, g, b, a, then fill r, g, b
	ok   = { 0.25, 0.75, 0.3, 1,    0.06, 0.12, 0.06 },
	miss = { 0.85, 0.15, 0.15, 1,   0.32, 0.04, 0.04 },
	unk  = { 0.5, 0.5, 0.55, 1,     0.12, 0.12, 0.14 },
	na   = { 0.2, 0.2, 0.24, 0.8,   0.07, 0.07, 0.09 },
	ready = { 1, 0.82, 0, 1,        0.2, 0.16, 0.02 },   -- off cooldown when they died
}
function UI.GridCell(row, size, wheel)
	local c = CreateFrame("Button", nil, row)
	c:SetWidth(size)
	c:SetHeight(size)
	c.edge = c:CreateTexture(nil, "BACKGROUND")
	c.edge:SetAllPoints(c)
	c.fill = c:CreateTexture(nil, "BORDER")
	c.fill:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -1)
	c.fill:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
	-- same set-up as the raid-mark icons (fixed size, OVERLAY), which draw fine
	c.icon = c:CreateTexture(nil, "OVERLAY")
	c.icon:SetWidth(size - 4)
	c.icon:SetHeight(size - 4)
	c.icon:SetPoint("CENTER", c, "CENTER", 0, 0)
	-- the X / ? / - mark sits on its own layer above the icon
	c.top = CreateFrame("Frame", nil, c)
	c.top:SetAllPoints(c)
	c.txt = c.top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	c.txt:SetPoint("CENTER", c, "CENTER", 0, 0)
	c.num = c.top:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	c.num:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -1, 1)
	local hl = c:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(c)
	hl:SetTexture(1, 1, 1, 0.18)
	c:EnableMouseWheel(true)
	c:SetScript("OnMouseWheel", wheel)
	c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	c:SetScript("OnClick", function()
		local d = this:GetParent().d
		if d and d.click then d.click(d, arg1, 0) end
	end)
	c:SetScript("OnEnter", function()
		local g = this.g
		if not g then return end
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText(g[4] or "", 1, 0.82, 0)
		for i = 1, getn(g[5] or {}) do GameTooltip:AddLine(g[5][i], 0.9, 0.9, 0.9, 1) end
		GameTooltip:Show()
	end)
	c:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return c
end

function UI.SetGridCell(c, g, row)
	c.g = g
	local k = UI.GRID_LOOK[g[2]] or UI.GRID_LOOK.na
	c.edge:SetTexture(k[1], k[2], k[3], k[4])
	c.fill:SetTexture(k[5], k[6], k[7], 1)
	if g[3] then
		c.icon:SetTexture(g[3])
		c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		-- a missing one: the icon of what's needed, faded red under the X;
		-- off cooldown at death: faded under a yellow !
		if g[2] == "ready" then
			c.icon:SetVertexColor(1, 1, 0.6)
			c.icon:SetAlpha(0.45)
		elseif g[2] == "miss" then
			c.icon:SetVertexColor(1, 0.35, 0.35)
			c.icon:SetAlpha(0.5)
		else
			c.icon:SetVertexColor(1, 1, 1)
			c.icon:SetAlpha(1)
		end
		c.icon:Show()
	else
		c.icon:Hide()
	end
	c.txt:SetText(g[6] or "")
	c.num:SetText(g[7] and tostring(g[7]) or "")
	c:ClearAllPoints()
	c:SetPoint("LEFT", row, "LEFT", g[1], 0)
	c:Show()
end

function UI.RowEnter(b)
	local d = b.d
	if not d or not (d.tip or d.link) then return end
	GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
	if d.link then
		-- an item: its real tooltip, then our lines under it
		GameTooltip:SetHyperlink(d.link)
		for i = 1, getn(d.tip or {}) do
			if type(d.tip[i]) == "string" and d.tip[i] ~= "" then GameTooltip:AddLine(d.tip[i], 0.9, 0.9, 0.9, 1) end
		end
		GameTooltip:Show()
		return
	end
	GameTooltip:SetText(d.tipTitle or d.l or "", 1, 0.82, 0, 1)
	for i = 1, getn(d.tip) do
		local line = d.tip[i]
		if type(line) == "table" then
			GameTooltip:AddDoubleLine(line[1], line[2], 0.9, 0.9, 0.9, 1, 1, 1)
		elseif line and line ~= "" then
			GameTooltip:AddLine(line, 0.9, 0.9, 0.9, 1)
		end
	end
	GameTooltip:Show()
end

------------------------------------------------------------------ frame
--
--  +-------------------------------------------------------------+
--  | WhoDidIt  mods                                        [x]   |  title bar
--  | +-----------+ +-------------------------------+-----------+ |
--  | | Encounters| | title / info / verdict        | shout btns| |  header
--  | |  list     | +-------------------------------+-----------+ |
--  | |           | [tab][tab][tab][tab][tab][tab]                |  tabs
--  | |           | +-------------------------------------------+ |
--  | |           | |  content list                             | |  content
--  | | [btn][btn]| +-------------------------------------------+ |
--  | | [btn][btn]| [meter modes / hint]               [Report]   |  bottom bar
--  | +-----------+                                               |
--  +-------------------------------------------------------------+

local PAD, GAP = 10, 8
local TOP = -58   -- under the title bar's two rows
local RX = PAD + LEFTW + GAP
local RW = WIDTH - RX - PAD
local HEADH = 78
local HEADW = RW - 24
local TABY = TOP - HEADH - 6
local TABH = 22
local CONTY = TABY - TABH - 4
local CONTH = HEIGHT + CONTY - 38
local BW = floor((LEFTW - 22) / 2)

local f = CreateFrame("Frame", "WhoDidItFrame", UIParent)
f:SetWidth(WIDTH)
f:SetHeight(HEIGHT)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
f:SetFrameStrata("HIGH")
f:SetToplevel(true)
f:SetMovable(true)
f:EnableMouse(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", function() this:StartMoving() end)
f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
f:SetBackdrop({
	bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
f:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
f:SetBackdropBorderColor(0.55, 0.55, 0.6, 1)
f:Hide()
UI.frame = f
tinsert(UISpecialFrames, "WhoDidItFrame")

local titleBar = f:CreateTexture(nil, "ARTWORK")
titleBar:SetTexture(1, 1, 1, 0.06)
titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -5)
titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
titleBar:SetHeight(24)
-- the second row: auto-loot and the add-on lights, on the right
local statusBar = f:CreateTexture(nil, "ARTWORK")
statusBar:SetTexture(1, 1, 1, 0.03)
statusBar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -2)
statusBar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -2)
statusBar:SetHeight(20)

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 4, -10)
title:SetText("|cffff5555Who|cffffd100DidIt|r")

local version = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 4, 1)
version:SetText("v" .. W.version)

local envText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
envText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -36)
envText:SetJustifyH("RIGHT")

local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

-- auto master looting: on/off at a glance, click to pick who gets the loot
local amlBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
amlBtn:SetWidth(118)
amlBtn:SetHeight(18)
amlBtn:SetPoint("RIGHT", envText, "LEFT", -10, 0)
if amlBtn.SetTextFontObject then amlBtn:SetTextFontObject(GameFontNormalSmall) end
if amlBtn.SetHighlightFontObject then amlBtn:SetHighlightFontObject(GameFontHighlightSmall) end
amlBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
amlBtn:SetScript("OnClick", function()
	if not W.AutoML then W.Print(W.RESTART_MSG) return end
	if arg1 == "RightButton" then W.AutoML:SetOn(not W.AutoML:On()) else W.AutoML:TogglePanel(this) end
end)
amlBtn:SetScript("OnEnter", function()
	local A = W.AutoML
	GameTooltip:SetOwner(this, "ANCHOR_BOTTOMLEFT")
	GameTooltip:SetText("Auto master looting", 1, 0.82, 0)
	if not A then GameTooltip:AddLine("Restart WoW to load it.", 1, 0.5, 0.5) GameTooltip:Show() return end
	GameTooltip:AddLine(A:On() and "|cff33ff33On|r - while you're the master looter, greys, whites and greens are handed out as soon as you open a corpse."
		or "|cffff5555Off|r - loot is handed out by hand as normal.", 0.9, 0.9, 0.9, 1)
	GameTooltip:AddLine("Loot goes to: |cffffffff" .. A.Who(A:Target()) .. "|r", 0.9, 0.9, 0.9)
	GameTooltip:AddLine("If your bags are full: |cffffffff" .. (A:Backup() or "nobody") .. "|r", 0.9, 0.9, 0.9)
	GameTooltip:AddLine("Epics are never handed out - you get a warning and a sound.", 0.6, 0.6, 0.6, 1)
	GameTooltip:AddLine("Click: choose who gets the loot   Right-click: on / off", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end)
amlBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

function UI:UpdateAML()
	local A = W.AutoML
	if not A then amlBtn:SetText("|cff888888Auto-loot: ?|r") return end
	local who = A:Target()
	amlBtn:SetText(A:On() and ("Auto-loot: |cff33ff33ON|r" .. (who and ("|cffffffff > " .. string.sub(who, 1, 8) .. "|r") or "")) or "Auto-loot: |cff888888off|r")
end

local function panel(x, y, w, h)
	local p = CreateFrame("Frame", nil, f)
	p:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
	p:SetWidth(w)
	p:SetHeight(h)
	p:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	p:SetBackdropColor(1, 1, 1, 0.03)
	p:SetBackdropBorderColor(0.4, 0.4, 0.45, 0.8)
	return p
end

local function button(parent, text, w, h)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetWidth(w)
	b:SetHeight(h or 20)
	b:SetText(text)
	return b
end

-- tooltip on hover; lines may be a function returning lines
local function tooltip(b, titleText, lines, anchor)
	b:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, anchor or "ANCHOR_RIGHT")
		GameTooltip:SetText(titleText, 1, 0.82, 0)
		local l = (type(lines) == "function") and lines() or lines
		for i = 1, getn(l) do GameTooltip:AddLine(l[i], 0.9, 0.9, 0.9, 1) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- the add-on lights in the title bar: hover explains them, click = ClassicAPI guide
do
	local hover = CreateFrame("Button", nil, f)
	hover:SetPoint("TOPLEFT", envText, "TOPLEFT", -2, 3)
	hover:SetPoint("BOTTOMRIGHT", envText, "BOTTOMRIGHT", 2, -3)
	hover:SetScript("OnClick", function() W:ClassicApiInfo() end)
	tooltip(hover, "Add-ons WhoDidIt uses", function()
		local e = W.env
		local function st(v, yes, no) return v and ("|cff33ff33" .. yes .. "|r") or no end
		local l = {
			"Nampower: " .. st(e.nampower, "found", "|cffff5555missing - only deaths are tracked|r"),
			"SuperWoW: " .. st(e.superwow, "found", "|cffff5555missing - most tracking is off|r"),
			"Threat: " .. st(e.twthreat or WhoDidItDB.opts.queryThreat, "on", "|cffff5555off|r"),
			"ClassicAPI: " .. st(e.classicapi, "found", "|cff999999not installed (optional)|r"),
			" ",
		}
		if e.classicapi then
			tinsert(l, "|cff33ff33ClassicAPI adds:|r")
		else
			tinsert(l, "|cffffd100Optional - WhoDidIt works fine without it. ClassicAPI would add:|r")
		end
		for i = 1, getn(W.CAPI_PERKS) do tinsert(l, "|cff33ff33+|r " .. W.CAPI_PERKS[i]) end
		if not e.classicapi then
			tinsert(l, " ")
			tinsert(l, "|cffffd100To get it:|r exit WoW and double-click tools\\Install-ClassicAPI.cmd in the WhoDidIt folder.")
			tinsert(l, "|cff888888Click for the details in chat.|r")
		end
		return l
	end, "ANCHOR_BOTTOMLEFT")
end

local function cycle(list, cur)
	for i = 1, getn(list) do
		if list[i] == cur then return list[i + 1] or list[1] end
	end
	return list[1]
end

------------------------------------------------------------------ left: encounters

local left = panel(PAD, TOP, LEFTW, HEIGHT + TOP - PAD)

local leftHead = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
leftHead:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -9)
leftHead:SetText("Encounters")

local leftCount = left:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
leftCount:SetPoint("TOPRIGHT", left, "TOPRIGHT", -10, -11)
leftCount:SetJustifyH("RIGHT")

local fightList = CreateList(left, FROWS, FROWH, LEFTW - 12)
fightList:SetPoint("TOPLEFT", left, "TOPLEFT", 6, -28)

--[[ the panel under the list - the same on every tab:
	  [ Post to: Raid                ]   <- where WhoDidIt posts (every tab)
	  [ row 4 ]  [ row 4 ]               <- this tab's buttons (2 x 4 grid)
	  ...
	  [ row 1 ]  [ row 1 ]                                                    ]]
local sep = left:CreateTexture(nil, "ARTWORK")
sep:SetTexture(1, 1, 1, 0.12)
sep:SetHeight(1)
sep:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 8, 132)
sep:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -8, 132)

-- smaller text, so labels like "Auto shout-outs: smart" fit
local function smallText(b)
	if b.SetTextFontObject then b:SetTextFontObject(GameFontNormalSmall) end
	if b.SetHighlightFontObject then b:SetHighlightFontObject(GameFontHighlightSmall) end
	if b.SetDisabledFontObject then b:SetDisabledFontObject(GameFontDisableSmall) end
	return b
end

-- 2 x 4 button grid, row 1 at the bottom
local function gridButton(text, row, col)
	local b = smallText(button(left, text, BW, 20))
	b:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 8 + (col - 1) * (BW + 6), 8 + (row - 1) * 24)
	return b
end

-- where WhoDidIt posts: one selector, same place on every tab
local chanBtn = smallText(button(left, "Post to: Raid", BW * 2 + 6, 20))
chanBtn:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 8, 8 + 4 * 24)
chanBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
chanBtn:SetScript("OnClick", function()
	W.Shout:CycleChannel(arg1 == "RightButton")
	UI:Refresh()
end)
tooltip(chanBtn, "Post to", function()
	return {
		"Where everything WhoDidIt posts goes: fight summaries, Report, Name & Shame,",
		"Big Them Up, shout-outs, kill and clear banter, and the rival watch.",
		"Now: |cffffffff" .. W.Shout:ChannelLabel() .. "|r",
		"Click: next channel   Right-click: previous",
		"Raid, Raid Warning, Party, Guild, Officer, Say, Yell, Only me (a preview just for you).",
		"|cff888888A custom channel: /wdi channel <name>. If you're not in the group or guild it names, posts show only to you.|r",
	}
end)

-- Fights tab
local shameBtn  = gridButton("|cffff5555Name & Shame|r", 4, 1)
local praiseBtn = gridButton("|cff33ff33Big Them Up|r", 4, 2)
local annBtn    = gridButton("Auto summary: me", 3, 1)
local autoBtn   = gridButton("Auto shout-outs: off", 3, 2)
local trashBtn  = gridButton("Track trash: off", 2, 1)
local demoBtn   = gridButton("|cff33ccffDemo fight|r", 2, 2)
local delBtn    = gridButton("Delete fight", 1, 1)
local clearBtn  = gridButton("Clear all fights", 1, 2)

StaticPopupDialogs["WHODIDIT_CLEAR"] = {
	text = "Delete ALL saved WhoDidIt fights?",
	button1 = YES, button2 = NO,
	OnAccept = function()
		WhoDidItDB.fights = {}
		UI.selIdx = 1
		UI:Refresh()
	end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}

delBtn:SetScript("OnClick", function()
	if UI.selIdx and UI.selIdx > 0 and WhoDidItDB.fights[UI.selIdx] then
		tremove(WhoDidItDB.fights, UI.selIdx)
		if UI.selIdx > getn(WhoDidItDB.fights) then UI.selIdx = getn(WhoDidItDB.fights) end
		if UI.selIdx < 1 then UI.selIdx = 1 end
		UI.detail = nil; UI.cause = nil
		UI:Refresh()
	end
end)
tooltip(delBtn, "Delete fight", { "Delete the fight selected in the list above." })

clearBtn:SetScript("OnClick", function() StaticPopup_Show("WHODIDIT_CLEAR") end)
tooltip(clearBtn, "Clear all fights", { "Delete every saved fight. Asks first." })

trashBtn:SetScript("OnClick", function()
	WhoDidItDB.opts.trackTrash = not WhoDidItDB.opts.trackTrash
	UI:Refresh()
end)
tooltip(trashBtn, "Track trash", { "On: elite trash pulls are recorded and analysed too.", "Off: raid bosses only (recommended)." })

annBtn:SetScript("OnClick", function()
	WhoDidItDB.opts.announce = cycle({ "self", "channel", "off" }, WhoDidItDB.opts.announce)
	UI:Refresh()
end)
tooltip(annBtn, "Auto summary after each fight", function()
	return {
		"A short summary after every boss fight: kill or wipe, time, deaths, who's to blame.",
		"on - posted to " .. W.Shout:ChannelLabel() .. " (the Post to channel)",
		"me only - in your own chat, nobody else sees it",

		"off - nothing",
		"|cff888888Click to change. Report (bottom right) posts the full report any time.|r",
	}
end)

autoBtn:SetScript("OnClick", function()
	WhoDidItDB.opts.autoShout = cycle({ "off", "smart", "shame", "praise", "both" }, WhoDidItDB.opts.autoShout)
	UI:Refresh()
end)
tooltip(autoBtn, "Auto shout-outs after each fight", function()
	return {
		"Name & Shame or Big Them Up posted by themselves after each fight.",
		"off - never",
		"smart - Name & Shame after wipes, Big Them Up after kills",
		"shame / praise / both - that one (or both) after every fight",
		"|cff888888Posts to: " .. W.Shout:ChannelLabel() .. ". Demo fights only post to your own chat.|r",
	}
end)

demoBtn:SetScript("OnClick", function()
	if IsShiftKeyDown() then W.Demo:Live() else W.Demo:Instant() end
end)
tooltip(demoBtn, "Demo / test mode", {
	"Click: add two scripted sample fights (a messy wipe and a kill) that use every feature - deaths, aggro, mechanics, threat, meters, shout-outs.",
	"Shift-click: watch the wipe play out live at 4x speed.",
	"|cff888888Automatic posts after demo fights stay in your chat. Clicking Report / Name & Shame / Big Them Up posts for real, tagged DEMO. /wdi demo clear removes them.|r",
})

------------------------------------------------------------------ right: header

local header = panel(RX, TOP, RW, HEADH)

local rTitle = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
rTitle:SetPoint("TOPLEFT", header, "TOPLEFT", 10, -9)
rTitle:SetWidth(HEADW)
rTitle:SetHeight(18)
rTitle:SetJustifyH("LEFT")

local rInfo = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
rInfo:SetPoint("TOPLEFT", rTitle, "BOTTOMLEFT", 0, -3)
rInfo:SetWidth(HEADW)
rInfo:SetHeight(12)
rInfo:SetJustifyH("LEFT")

local rVerdict = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
rVerdict:SetPoint("TOPLEFT", rInfo, "BOTTOMLEFT", 0, -5)
rVerdict:SetWidth(HEADW)
rVerdict:SetHeight(28)
rVerdict:SetJustifyH("LEFT")
rVerdict:SetJustifyV("TOP")

-- SR MasterLoot: where soft-res sheets are made, with a copy box for the link
local SR_SITE = "https://raidres.fly.dev"
local srCopy = button(header, "Copy link", 84, 20)
srCopy:SetPoint("TOPRIGHT", header, "TOPRIGHT", -10, -10)
srCopy:SetScript("OnClick", function()
	W:CopyLink("Soft-res sheets", SR_SITE)
end)
tooltip(srCopy, "raidres.fly.dev", { "The website where you make the soft-res sheet: raiders pick their items there,",
	"then you use its RollFor export to import the sheet here.",
	"Click: copies the link (with ClassicAPI straight to your clipboard,", "otherwise a box opens with it selected - press Ctrl+C)." }, "ANCHOR_LEFT")
local srSite = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
srSite:SetPoint("RIGHT", srCopy, "LEFT", -8, 0)
srSite:SetText("|cffaaaaaaSoft-res sheets:|r  |cffffd100raidres.fly.dev|r")
srCopy:Hide()
srSite:Hide()

local function finishedRec()
	local rec = UI:Current()
	if not rec or rec.result == "LIVE" then W.Print("Pick a finished fight first.") return nil end
	return rec
end

-- Name & Shame / Big Them Up live in the panel under the fight list
shameBtn:SetScript("OnClick", function()
	local rec = finishedRec()
	if rec then W.Shout:Shame(rec) end
end)
tooltip(shameBtn, "Name & Shame", function()
	return {
		"Post this fight's hall of shame: Most to blame, Threat Junkie, Floor Inspector,",
		"Fire Enthusiast, Bomb Squad, AFK Award, Participation Trophy.",
		"Shame one player: Shift-click their name anywhere in the window.",
		"|cff888888Posts to: " .. W.Shout:ChannelLabel() .. "|r",
	}
end)
praiseBtn:SetScript("OnClick", function()
	local rec = finishedRec()
	if rec then W.Shout:Praise(rec) end
end)
tooltip(praiseBtn, "Big Them Up", function()
	return {
		"Post this fight's stars: Damage King, Top Healer, Iron Wall, Kick Master,",
		"Cleanser, Tranq Sniper, Never Stops, and everyone who played flawlessly.",
		"Big up one player: Alt-click their name anywhere in the window.",
		"|cff888888Posts to: " .. W.Shout:ChannelLabel() .. "|r",
	}
end)

------------------------------------------------------------------ right: tabs + content

local TABS = {
	{ id = "summary",  text = "Summary",  tip = { "The short version: why the fight was lost (or how it was won),", "the main causes ranked, the blame board and the top heroes." } },
	{ id = "deaths",   text = "Deaths",   tip = { "Every death in order, with what killed them.", "Hover one for the last seconds before it, click it for the full recap." } },
	{ id = "mistakes", text = "Mistakes", tip = { "Everything WhoDidIt counted against someone: standing in fire,", "pulling aggro, missed interrupts... with the blame points for each." } },
	{ id = "heroes",   text = "Heroes",   tip = { "The plays that saved someone: clutch heals, shields, taunts,", "battle res, dispels and more." } },
	{ id = "threat",   text = "Threat",   tip = { "Every time the boss changed target, who it went for and their threat %,", "plus each player's highest threat. Keep the boss targeted to record it." } },
	{ id = "meters",   text = "Meters",   tip = { "Damage, healing, damage taken, activity and utility for the fight.", "Damage and healing also show crit % and the biggest hit.", "Hover a player for every spell: total, share, hits, crit % and biggest.", "Pick one with the buttons at the bottom." } },
	{ id = "timeline", text = "Timeline", tip = { "Everything that happened, second by second." } },
	{ id = "consumes", text = "Consumes", tip = { "Each player's flask, elixirs, food and protection potions,", "and every potion, rune and healthstone they used." } },
}
local TABW = floor((RW - (getn(TABS) - 1) * 4) / getn(TABS))
UI.tabButtons = {}
for i = 1, getn(TABS) do
	local t = TABS[i]
	local b = button(f, t.text, TABW, TABH)
	b:SetPoint("TOPLEFT", f, "TOPLEFT", RX + (i - 1) * (TABW + 4), TABY)
	b.id = t.id
	b:SetScript("OnClick", function()
		UI.tab = this.id
		UI.detail = nil; UI.cause = nil
		UI.tl = nil   -- the Timeline tab button shows everyone
		UI:Refresh()
	end)
	if t.tip then tooltip(b, t.text, t.tip) end
	UI.tabButtons[i] = b
end

local content = panel(RX, CONTY, RW, CONTH)
local mainList = CreateList(content, NROWS, ROWH, RW - 10)
mainList:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -6)

-- Consumes tab: a grid like DopingControl's - taller rows, a column per
-- consumable slot, and a column header that stays put while you scroll
UI.CG = {
	ROWH = 26, NAME = 6, ROLE = 120, X = 178, STEP = 30, READY = 540, USED = 588,
	COLS = {   -- label, name, slots (or "WPN"), what counts
		{ "FLK", "Flask", { FLASK = true }, "Titans, Supreme Power, Distilled Wisdom..." },
		{ "FOD", "Food", { FOOD = true, ALC = true }, "Well Fed and the other food buffs, drinks" },
		{ "AP", "Attack power", { AP = true }, "Juju Might, Winterfall Firewater" },
		{ "STR", "Strength", { STR = true }, "Elixir of Giants, Juju Power" },
		{ "AGI", "Agility", { AGI = true }, "Elixir of the Mongoose, Greater Agility" },
		{ "SP", "Spell power", { GAE = true, SCHOOL = true, DREAMT = true, SHARD = true }, "Greater Arcane Elixir, Firepower, Shadow / Frost Power, Dreamshard" },
		{ "MP5", "Mana regen", { MP5 = true }, "Mageblood" },
		{ "ARM", "Armor", { ARM = true }, "Elixir of Superior / Greater Defense" },
		{ "STA", "Stamina / health", { HPELX = true, ZANZA = true }, "Elixir of Fortitude, Spirit of Zanza" },
		{ "BLS", "Blasted Lands", { BL = true }, "R.O.I.D.S., Scorpok, Rage of Ages, Lung Juice, Cerebral Cortex..." },
		{ "PROT", "Protection potion", { PROT = true }, "Fire / Nature / Frost / Shadow / Arcane Protection" },
		{ "WPN", "Weapon", "WPN", "Oil or sharpening / weight stone; shamans: their weapon imbue" },
	},
}
local consList = CreateList(content, floor(NROWS * ROWH / UI.CG.ROWH) - 1, UI.CG.ROWH, RW - 10)
consList:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -6 - UI.CG.ROWH)
consList:Hide()
-- the grid's column header: fixed above the rows; its labels follow the
-- view (Buffs: a column per consumable slot, Used: a column per kind of item)
do
	local CG = UI.CG
	local h = CreateFrame("Frame", nil, content)
	h:SetWidth(RW - 28)
	h:SetHeight(CG.ROWH - 2)
	h:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -6)
	local bg = h:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(h)
	bg:SetTexture(0.25, 0.25, 0.32, 0.55)
	local function label(x, w)
		local b = CreateFrame("Button", nil, h)
		b:SetWidth(w)
		b:SetHeight(CG.ROWH - 2)
		b:SetPoint("LEFT", h, "LEFT", x, 0)
		b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		b.fs:SetAllPoints(b)
		b.fs:SetJustifyH("CENTER")
		b:SetScript("OnEnter", function()
			if not this.tipTitle then return end
			GameTooltip:SetOwner(this, "ANCHOR_TOP")
			GameTooltip:SetText(this.tipTitle, 1, 0.82, 0)
			for i = 1, getn(this.tip or {}) do GameTooltip:AddLine(this.tip[i], 0.9, 0.9, 0.9, 1) end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return b
	end
	-- Buffs / Used: which grid the tab shows
	local function toggle(x, text, view, tip)
		local b = smallText(button(h, text, 50, 18))
		b:SetPoint("LEFT", h, "LEFT", x, 0)
		b:SetScript("OnClick", function() UI.consView = view; UI:Refresh() end)
		tooltip(b, text, tip, "ANCHOR_TOP")
		return b
	end
	h.buffs = toggle(4, "Buffs", "buffs", { "Consumable buffs at the pull, per slot, and what each role was missing." })
	h.used = toggle(58, "Used", "used", { "Every potion, rune, tea, healthstone, bandage and bomb used during the fight." })
	h.role = label(CG.ROLE, 52)
	h.cols = {}
	for i = 1, 12 do h.cols[i] = label(CG.X + (i - 1) * CG.STEP, CG.STEP) end
	h.ready = label(CG.READY, 44)
	h.usedCol = label(CG.USED, 54)
	consList.head = h
	h:Hide()
end

-- fill the header for a view: cols = { { label, name, what }, ... }, then the two end columns
function UI.SetGridHead(cols, endA, endB)
	local h = consList.head
	local key = UI.consView or "buffs"
	if key == "used" then h.used:LockHighlight(); h.buffs:UnlockHighlight() else h.buffs:LockHighlight(); h.used:UnlockHighlight() end
	h.role.fs:SetText("ROLE")
	h.role.tipTitle, h.role.tip = "Role", { "Tank, healer, melee, ranged or caster - from what they did in the fight." }
	for i = 1, getn(h.cols) do
		local b, c = h.cols[i], cols[i]
		if c then
			b.fs:SetText(c[1])
			b.tipTitle, b.tip = c[2], c[3]
			b:Show()
		else
			b:Hide()
		end
	end
	h.ready.fs:SetText(endA[1]); h.ready.tipTitle, h.ready.tip = endA[2], endA[3]
	h.usedCol.fs:SetText(endB[1]); h.usedCol.tipTitle, h.usedCol.tip = endB[2], endB[3]
end

-- the Consumes grid replaces the normal list while that tab is open
function UI.ShowGrid(on)
	if on then
		mainList:Hide()
		consList:Show()
		consList.head:Show()
	else
		consList:Hide()
		consList.head:Hide()
		mainList:Show()
	end
end

------------------------------------------------------------------ bottom bar

local METERS = {
	{ id = "dmg",   text = "Damage",   tip = { "Damage done, per second and share of the raid's total." } },
	{ id = "heal",  text = "Healing",  tip = { "Healing done (without overhealing), per second and share." } },
	{ id = "taken", text = "Taken",    tip = { "Damage taken - who soaked the most." } },
	{ id = "act",   text = "Activity", tip = { "How much of their time alive each player spent casting, swinging or healing.", "Low activity = standing around." } },
	{ id = "util",  text = "Utility",  tip = { "Interrupts, dispels, tranquilizing shots and items used." } },
}
UI.meterButtons = {}
for i = 1, getn(METERS) do
	local m = METERS[i]
	local b = button(f, m.text, 78, 20)
	b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", RX + (i - 1) * 82, PAD)
	b.id = m.id
	b:SetScript("OnClick", function()
		UI.meter = this.id
		UI:Refresh()
	end)
	if m.tip then tooltip(b, m.text, m.tip) end
	UI.meterButtons[i] = b
end

-- per-tab post buttons in the bottom bar (they replace the hint line)
local ACTIONS = {
	consumes = {
		{ "Post summary", function(rec) W.Shout:Consumes(rec, "summary") end,
		  "Flask / food / elixir counts, protection potions, items used and the most prepared players." },
		{ "Post missing", function(rec) W.Shout:Consumes(rec, "missing") end,
		  "Who was missing what their role needs: flask, food, role elixir, weapon oil / stone." },
		{ "Post everyone", function(rec) W.Shout:Consumes(rec, "full") end,
		  "One line per player: every consumable buff they had and every item they used. Long!" },
		{ "Check raid now", function() W.Cons:Check(IsShiftKeyDown()) end,
		  "Scan everyone's buffs right now (before the pull) and list who's missing what their role needs. Only you see it - Shift-click to post it. Also runs by itself on every ready check.",
		  true },
		{ "Full check", function() W.Cons:OpenFull() end,
		  "DopingControl's full raid check: every consumable, class buff, debuff, resistance, hit cap and enchant, per player, with icons. Built in - also /dc.",
		  true, true },
	},
	mistakes = {
		{ "Post mistakes", function(rec) W.Shout:Mistakes(rec) end,
		  "The blame board and the biggest mistakes, with their times and points." },
		{ "Name & Shame", function(rec) W.Shout:Shame(rec) end,
		  "The hall of shame: the top 3 to blame and the awards (Threat Junkie, Floor Inspector...)." },
	},
	heroes = {
		{ "Post heroes", function(rec) W.Shout:Heroes(rec) end,
		  "The hero board and the biggest game-saving plays, with their times and points." },
		{ "Big Them Up", function(rec) W.Shout:Praise(rec) end,
		  "The stars of the fight: Damage King, Top Healer, Iron Wall, Kick Master..." },
	},
}
UI.actionButtons = {}
for tab, list in pairs(ACTIONS) do
	UI.actionButtons[tab] = {}
	for i = 1, getn(list) do
		local a = list[i]
		local b = button(f, a[1], 112, 20)
		b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", RX + (i - 1) * 116, PAD)
		local fn, live, nopost = a[2], a[4], a[5]
		b:SetScript("OnClick", function()
			if live then fn() return end   -- works on the raid right now, not a saved fight
			local rec = finishedRec()
			if rec then fn(rec) end
		end)
		tooltip(b, a[1], function()
			if nopost then return { a[3] } end
			return { a[3], "|cff888888" .. (live and "Shift-click posts to: " or "Posts to: ") .. W.Shout:ChannelLabel() .. "  (coloured, like every WhoDidIt post)|r" }
		end, "ANCHOR_TOP")
		b:Hide()
		tinsert(UI.actionButtons[tab], b)
	end
end

local hintText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hintText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", RX + 4, PAD + 6)
hintText:SetJustifyH("LEFT")

local reportBtn = button(f, "Report", 96, 20)
reportBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
reportBtn:SetScript("OnClick", function()
	local rec = finishedRec()
	if rec then W:Report(rec) end
end)
tooltip(reportBtn, "Report", function()
	return { "Post the fight summary, top causes and blame board.", "|cff888888Posts to: " .. W.Shout:ChannelLabel() .. "|r" }
end, "ANCHOR_LEFT")

local HINTS = {
	summary  = "Click a cause for details  -  click a name to post it (Ctrl preview, Shift shame, Alt praise)",
	deaths   = "Hover a death for its recap  -  click it for the full timeline",
	mistakes = "Click a mistake to post it (Ctrl-click: preview)  -  hover for advice",
	threat   = "Click a name to open their timeline at that moment  -  keep the boss targeted for threat %",
	timeline = "Everything that happened, in order  -  click a name for that player's timeline at that moment",
	consumes = "Buffs / Used (top left) switch the grid  -  hover a square for details  -  red X = their role needs it  -  click a group to fold it",
	heroes   = "Click a name or a game-saving moment to post it (Ctrl-click: preview)  -  hover for details",
}

------------------------------------------------------------------ data helpers

------------------------------------------------------------------ modes: Fights / Rankings / Logs

UI.mode = "fights"
UI.rk = { view = "kills" }   -- rankings state: view, realm, faction, inst, boss

local MODES = {
	{ id = "fights",   text = "Fights"   },
	{ id = "rankings", text = "Rankings" },
	{ id = "logs",     text = "Logging"       },
	{ id = "marks",    text = "Auto Marker"   },
	{ id = "loot",     text = "SR MasterLoot" },
	{ id = "fame",     text = "Hall of Fame" },
}
UI.modeButtons = {}
for i = 1, getn(MODES) do
	local m = MODES[i]
	-- sized to the label, one after another
	local b = CreateFrame("Button", "WhoDidItMode" .. i, f, "UIPanelButtonTemplate")
	b:SetHeight(18)
	b:SetText(m.text)
	local label = getglobal("WhoDidItMode" .. i .. "Text")
	local tw = label and label:GetStringWidth() or 0
	if not tw or tw < 10 then tw = string.len(m.text) * 7 end
	b.tw = tw
	b.id = m.id
	b:SetScript("OnClick", function() UI:SetMode(this.id) end)
	UI.modeButtons[i] = b
end
-- all the same width; Hall of Fame on its own at the far right, by the close button
do
	local n, w = getn(UI.modeButtons), 60
	for i = 1, n do w = math.max(w, floor(UI.modeButtons[i].tw + 24)) end
	local startX = PAD + 4 + title:GetStringWidth() + 4 + version:GetStringWidth() + 16
	local room = WIDTH - 36 - startX - 12 - (n - 1) * 4
	w = math.min(w, floor(room / n))
	for i = 1, n do
		local b = UI.modeButtons[i]
		b:SetWidth(w)
		if b.id == "fame" then
			b:SetPoint("RIGHT", close, "LEFT", -2, 0)
		elseif i == 1 then
			b:SetPoint("LEFT", version, "RIGHT", 16, 0)
		else
			b:SetPoint("LEFT", UI.modeButtons[i - 1], "RIGHT", 4, 0)
		end
	end
end
tooltip(UI.modeButtons[1], "Fights", { "Every recorded fight: why it went wrong, deaths, mistakes, heroes, meters, consumes." })
tooltip(UI.modeButtons[2], "Rankings", { "Boss kill times and full clears: yours, your guild's, and every guild on your realm that has a WhoDidIt user." })
tooltip(UI.modeButtons[3], "Logging", { "Chronicle combat logging (built in): start, stop, save, archive and delete", "the log you upload to chronicleclassic.com." })
tooltip(UI.modeButtons[4], "Auto Marker", { "Auto marking: every saved pack of mobs and the marks they get, smart marks for tricky fights,",
	"and quick save - mark mobs in game, click Save marks as pack." })
tooltip(UI.modeButtons[5], "SR MasterLoot", { "Soft-res master looting with RollFor (built in): import the soft-res sheet, roll and award items,",
	"see who won what, and a step-by-step guide." })
tooltip(UI.modeButtons[6], "Hall of Fame", { "Every fight adds up: the biggest heroes and the Hall of Shame of all time,",
	"with every clutch play and every mistake, their points, and the best plays and worst blunders ever." })

-- a row of buttons in the tab strip, used by Rankings and Logs
local function stripButtons(defs)
	local n = getn(defs)
	local w = floor((RW - (n - 1) * 4) / n)
	local list = {}
	for i = 1, n do
		local d = defs[i]
		local b = button(f, d[1], w, TABH)
		b:SetPoint("TOPLEFT", f, "TOPLEFT", RX + (i - 1) * (w + 4), TABY)
		b:SetScript("OnClick", d[2])
		if d[3] then tooltip(b, d[1], d[3]) end
		b:Hide()
		list[i] = b
	end
	return list
end

local function cycleList(list, cur)
	for i = 1, getn(list) do
		if list[i] == cur then return list[i + 1] or list[1] end
	end
	return list[1]
end

UI.rankButtons = stripButtons({
	{ "Kill times", function() UI.rk.view = "kills"; UI.rk.boss = nil; UI.rk.log = nil; UI:Refresh() end,
	  { "Best kill time on every boss: you, your guild and the realm." } },
	{ "Full clears", function() UI.rk.view = "clears"; UI.rk.boss = nil; UI.rk.log = nil; UI:Refresh() end,
	  { "Fastest full clear of the instance: first combat inside to the last boss.", "Optional bosses aren't required." } },
	{ "Realm", function()
		local list = W.Board:Realms()
		tinsert(list, 2, W.Board.ALL)   -- your realm, then all realms together, then the rest
		UI.rk.realm = cycleList(list, UI.rk.realm or W.Board.Realm())
		UI.rk.boss = nil; UI.rk.log = nil
		UI:Refresh()
	  end, { "Your realm, then all realms together (compare against every guild), then each other realm." } },
	{ "Faction", function()
		local mine = W.Board.Faction()
		local other = (mine == "Horde") and "Alliance" or "Horde"
		UI.rk.faction = cycleList({ mine, "All", other }, UI.rk.faction or mine)
		UI:Refresh()
	  end, { "Your faction first, then everyone, then the other faction." } },
})

UI.logButtons = stripButtons({
	{ "Start logging", function()
		if W.Logs:Enabled() then W.Logs:Stop() else W.Logs:Start() end
		UI:Refresh()
	  end, { "Start Chronicle combat logging, or stop it and save everything to the log file." } },
	{ "Save now", function() W.Logs:Save(); UI:Refresh() end,
	  { "Write everything logged so far to the log file (logging keeps going)." } },
	{ "Archive log", function() W.Logs:Archive(); UI:Refresh() end,
	  { "Save, then move the current log to a backup file and start a fresh one.", "Do this between raid lockouts." } },
	{ "|cffff5555Delete log|r", function() W.Logs:Delete() end,
	  { "Delete the current log file and anything unsaved (Chronicle asks first)." } },
})

UI.mk = {}   -- marks view state: zone, pack, showHidden

UI.markButtons = stripButtons({
	{ "|cff33ff33Save marks as pack|r", function() W.Marks:QuickSave() end,
	  { "Save the mobs that have raid marks right now as a pack - with their marks.",
	    "1. Mark the mobs in game (right-click a portrait > Raid Target Icon).",
	    "2. Click this and type a name (Enter saves).",
	    "Saving with an existing pack's name updates that pack.",
	    "|cff888888Keybind: Esc > Key Bindings > WhoDidIt|r" } },
	{ "Mark target's pack", function() W.Marks:MarkGroup(); UI:Refresh() end,
	  { "Mark every mob in the pack of the mob under your mouse (or your target).",
	    "Or hold Shift + Ctrl (or Alt) and move the mouse over a mob." } },
	{ "Mark next pack", function() W.Marks:MarkNext(); UI:Refresh() end,
	  { "Mark the next pack along the route in this zone (the order in the list)." } },
	{ "|cffff5555Clear marks|r", function() W.Marks:ClearMarks() end, { "Remove every raid mark." } },
	{ "Auto marking", function()
		local o = WhoDidItDB.marks.opts
		o.enabled = not o.enabled
		UI:Refresh()
	  end, { "Switch all auto marking on or off: mouseover marking and smart marks.", "Keys and buttons still work when it's off." } },
})

-- marks toggles take the place of the fight buttons while in Marks
local mouseBtn  = gridButton("Mouseover", 3, 1)
local smartBtn  = gridButton("Smart marks", 3, 2)
local hiddenBtn = gridButton("Hidden", 2, 1)
local findBtn   = gridButton("Find target", 2, 2)
local hereBtn   = gridButton("This zone", 1, 1)
local kindBtn   = gridButton("Mark same kind", 1, 2)
mouseBtn:SetScript("OnClick", function()
	local o = WhoDidItDB.marks.opts
	o.mouseover = not o.mouseover
	UI:Refresh()
end)
smartBtn:SetScript("OnClick", function()
	local o = WhoDidItDB.marks.opts
	o.smart = not o.smart
	UI:Refresh()
end)
hiddenBtn:SetScript("OnClick", function()
	UI.mk.showHidden = not UI.mk.showHidden
	UI:Refresh()
end)
findBtn:SetScript("OnClick", function()
	local ok, guid = UnitExists("target")
	local zone = GetRealZoneText()
	local name = ok and W.Marks:Find(zone, guid)
	if name then UI:ShowPack(zone, name) else W.Print("Your target isn't in a saved pack.") end
end)
hereBtn:SetScript("OnClick", function()
	UI.mk.zone = GetRealZoneText()
	UI.mk.pack = nil
	UI:Refresh()
end)
kindBtn:SetScript("OnClick", function() W.Marks:MarkType() end)
tooltip(mouseBtn, "Mouseover marking", { "Hold Shift + Ctrl (or Shift + Alt) and move the mouse over a mob to mark its whole pack." })
tooltip(smartBtn, "Smart marks", { "Automatic marks for fights where fixed packs can't work: adds that respawn with new",
	"GUIDs, Buru's eggs, the biggest Core Hound, KT's soldiers, Solnius' adds and more.",
	"Switch single ones off in the list under each zone." })
tooltip(hiddenBtn, "Hidden packs", { "Show the built-in packs you've hidden, so you can bring them back." })
tooltip(findBtn, "Find target's pack", { "Open the pack your target belongs to." })
tooltip(hereBtn, "This zone", { "Jump back to the zone you're in." })
tooltip(kindBtn, "Mark same kind", { "Mark every mob nearby of the same kind as your target, closest first (/wdi marks type)." })
local markOnly = { mouseBtn, smartBtn, hiddenBtn, findBtn, hereBtn, kindBtn }
for i = 1, getn(markOnly) do markOnly[i]:Hide() end

UI.lt = { section = "guide" }   -- loot view state

UI.lootButtons = stripButtons({
	{ "|cff33ff33Import soft-res|r", function() W.Loot:Key("softres_toggle") end,
	  { "Open RollFor's soft-res import window (/sr).",
	    "Paste the data from raidres.fly.dev > RollFor export > Copy RollFor data to clipboard, then click Import!" } },
	{ "Check soft-res", function() W.Loot:Run("SRC", ""); UI.lt.section = "softres"; UI:Refresh() end,
	  { "List who in the raid hasn't soft-reserved yet (/src).", "The Soft-res page shows everyone's items." } },
	{ "Winners", function() W.Loot:Key("winners_toggle") end,
	  { "RollFor's winners window: every item given out, with filters and sorting (/rfw)." } },
	{ "RollFor options", function() W.Loot:Key("options_toggle") end,
	  { "RollFor's own options window, with every setting (/rfo)." } },
	{ "Post how to roll", function() W.Loot:Run("HTR", "") end,
	  function() return { "Tell the raid how to roll (/htr):", W.Loot:HowToRoll(), "|cff888888Change the numbers on the Settings page.|r" } end },
})

-- Hall of Fame: the running tally of every fight
UI.fame = { view = "hero" }   -- view: hero / blame / plays / blunders; who = a player's page
UI.fameButtons = stripButtons({
	{ "|cff33ff33Heroes|r", function() UI.fame.view = "hero"; UI.fame.who = nil; UI:Refresh() end,
	  { "Everyone's hero points from every fight: clutch heals, shields, taunts,", "battle res, dispels, interrupts... and how often they were MVP." } },
	{ "|cffff5555Hall of Shame|r", function() UI.fame.view = "blame"; UI.fame.who = nil; UI:Refresh() end,
	  { "Everyone's blame points from every fight: standing in fire, pulling aggro,", "bombing the raid, idling... and how often they were most to blame." } },
	{ "Best plays", function() UI.fame.view = "plays"; UI.fame.who = nil; UI:Refresh() end,
	  { "The biggest single game-saving plays of all time." } },
	{ "Worst blunders", function() UI.fame.view = "blunders"; UI.fame.who = nil; UI:Refresh() end,
	  { "The most costly single mistakes of all time." } },
})

-- loot quick actions take the place of the fight buttons while in Loot
local finishBtn = gridButton("Finish roll", 3, 1)
local cancelBtn = gridButton("|cffff5555Cancel roll|r", 3, 2)
local srsBtn    = gridButton("SR items", 2, 1)
local sroBtn    = gridButton("Fix SR names", 2, 2)
local mlBtn     = gridButton("Auto ML", 1, 1)
local glBtn     = gridButton("Auto group", 1, 2)
finishBtn:SetScript("OnClick", function() W.Loot:Run("FR", "") end)
cancelBtn:SetScript("OnClick", function() W.Loot:Run("CR", "") end)
srsBtn:SetScript("OnClick", function() W.Loot:Run("SRS", "") end)
sroBtn:SetScript("OnClick", function() W.Loot:Run("SRO", "") end)
mlBtn:SetScript("OnClick", function() W.Loot:Toggle("auto-master-loot"); UI:Refresh() end)
glBtn:SetScript("OnClick", function() W.Loot:Toggle("auto-group-loot"); UI:Refresh() end)
tooltip(finishBtn, "Finish roll", { "End the current roll now instead of waiting for the timer (/fr)." })
tooltip(cancelBtn, "Cancel roll", { "Stop the current roll without a winner (/cr)." })
tooltip(srsBtn, "Soft-reserved items", { "List every soft-reserved item and who reserved it, in chat (/srs)." })
tooltip(sroBtn, "Fix soft-res names", { "Match players whose name on the soft-res sheet doesn't match their character (/sro).",
	"RollFor fixes simple typos by itself." })
tooltip(mlBtn, "Auto master loot", { "When you target a boss, the raid switches to master loot", "with you as the looter. You must be raid leader." })
tooltip(glBtn, "Auto group loot", { "When everything in the boss's loot has been given out,", "the raid switches back to group loot for the trash.", "Use it with Auto ML: master loot for bosses, group loot in between." })
local lootOnly = { finishBtn, cancelBtn, srsBtn, sroBtn, mlBtn, glBtn }
for i = 1, getn(lootOnly) do lootOnly[i]:Hide() end

-- Rankings tab: banter and rival watch take the place of the fight buttons
local banterKillBtn  = gridButton("Kill banter", 4, 1)
local banterClearBtn = gridButton("Clear banter", 4, 2)
local rivalBtn       = gridButton("Rival alerts", 3, 1)
local banterTestBtn  = gridButton("Test banter", 3, 2)
local postRivalBtn   = gridButton("Post rivals", 2, 1)
local postBoardBtn   = gridButton("Post standings", 2, 2)
banterKillBtn:SetScript("OnClick", function()
	WhoDidItDB.opts.banterKills = not WhoDidItDB.opts.banterKills
	UI:Refresh()
end)
banterClearBtn:SetScript("OnClick", function()
	WhoDidItDB.opts.banterClears = not WhoDidItDB.opts.banterClears
	UI:Refresh()
end)
rivalBtn:SetScript("OnClick", function()
	WhoDidItDB.opts.rivalAlerts = not WhoDidItDB.opts.rivalAlerts
	UI:Refresh()
end)
banterTestBtn:SetScript("OnClick", function() W.Board:BanterTest() end)
postRivalBtn:SetScript("OnClick", function() W.Board:PostRivals(UI.rk.inst) end)
postBoardBtn:SetScript("OnClick", function()
	local B = W.Board
	local realm, zone = UI.rk.realm or B.Realm(), UI.rk.inst
	local line
	if UI.rk.boss then line = B:TopLine("kills", UI.rk.boss, realm, UI.rk.faction)
	elseif UI.rk.view == "clears" then line = B:TopLine("clears", zone, realm, UI.rk.faction)
	else line = B:StandingsLine(zone, realm) end
	if line then W:Send({ line }, nil, B:ChatColours()) else W.Print("Nothing to post for this board yet.") end
end)
local function banterTip(what)
	return function()
		return {
			"After every " .. what .. ", post one fun line about our time. It picks from:",
			"- our own best (new record, or how much slower)",
			"- the other guilds on " .. W.Board.RealmLabel(W.Board.Realm()) .. " (passed them, still behind, #1)",
			"- the other realms' fastest (\"faster than anyone on N'Zoth (PvE)\")",
			"- anyone who recently beat us (revenge, or still chasing them)",
			"It mocks us when we're slow and bigs us up when we're fast.",
			"|cff888888Posts to: " .. W.Shout:ChannelLabel() .. ". With several WhoDidIt users in the raid only one posts.|r",
		}
	end
end
tooltip(banterKillBtn, "Kill banter", banterTip("boss kill"))
tooltip(banterClearBtn, "Clear banter", banterTip("full clear"))
tooltip(rivalBtn, "Rival alerts", function()
	return {
		"Watches for new times (from the Chronicle sync or WhoDidIt users) that beat",
		"our guild's best - on " .. W.Board.Realm() .. " or the fastest on another realm.",
		"On: when the raid enters that instance, post who beat us and taunt us to win it back.",
		"Off: they're still listed under Rival watch, but nothing is posted.",
		"|cff888888Posts to: " .. W.Shout:ChannelLabel() .. "|r",
	}
end)
tooltip(banterTestBtn, "Test banter", { "Show a random banter line for a made-up kill, in your own chat only." })
tooltip(postRivalBtn, "Post rivals", function()
	return { "Post who has beaten our times in " .. (UI.rk.inst or "this instance") .. " recently, with a taunt.",
		"|cff888888Posts to: " .. W.Shout:ChannelLabel() .. "|r" }
end)
tooltip(postBoardBtn, "Post standings", function()
	return { "Post what you're looking at:",
		"- a boss's leaderboard: its top 3 (and our place)",
		"- Full clears: the instance's top 3 clears",
		"- Kill times: on how many bosses we're #1, and who has the rest",
		"|cff888888Uses the Realm button: your realm, or All realms to compare across " .. W.Board.ServerName() .. ".|r",
		"|cff888888Posts to: " .. W.Shout:ChannelLabel() .. "|r" }
end)
-- Rankings: the sync helper's progress bar, and Sync now
local syncBar = CreateFrame("Button", nil, left)
syncBar:SetWidth(BW * 2 + 6)
syncBar:SetHeight(28)
syncBar:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 8, 8 + 5 * 24 + 2)
do
	local bg = syncBar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(syncBar)
	bg:SetTexture(0, 0, 0, 0.5)
	syncBar.fill = syncBar:CreateTexture(nil, "BORDER")
	syncBar.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
	syncBar.fill:SetPoint("TOPLEFT", syncBar, "TOPLEFT", 1, -1)
	syncBar.fill:SetPoint("BOTTOMLEFT", syncBar, "BOTTOMLEFT", 1, 1)
	syncBar.top = syncBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	syncBar.top:SetPoint("TOPLEFT", syncBar, "TOPLEFT", 5, -3)
	syncBar.top:SetPoint("TOPRIGHT", syncBar, "TOPRIGHT", -5, -3)
	syncBar.top:SetJustifyH("LEFT")
	syncBar.bot = syncBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	syncBar.bot:SetPoint("BOTTOMLEFT", syncBar, "BOTTOMLEFT", 5, 3)
	syncBar.bot:SetPoint("BOTTOMRIGHT", syncBar, "BOTTOMRIGHT", -5, 3)
	syncBar.bot:SetJustifyH("LEFT")
	local hl = syncBar:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(syncBar)
	hl:SetTexture(1, 1, 1, 0.08)
end
local syncBtn = gridButton("|cff33ff33Sync now|r", 1, 1)
local function syncNow()
	local B = W.Board
	local st = B:SyncStatus()
	if not (st and st.alive) then
		W.Print("Raid times come with the addon - update WhoDidIt to get the newest. "
			.. "|cff888888(Optional: the helper tools\\WhoDidIt-Sync.cmd keeps them fresher on your PC, and makes Sync now work.)|r")
		return
	end
	if st.state == "running" then W.Print("A sync is already running - see the bar on the Rankings tab.") return end
	if B:RequestSync() then
		W.Print("Asked the sync helper to sync now. The bar on the Rankings tab shows how it's going.")
	else
		W.Print("Couldn't ask the sync helper (needs Nampower's file access).")
	end
	UI:UpdateSync()
end
syncBtn:SetScript("OnClick", syncNow)
syncBar:SetScript("OnClick", syncNow)
local function syncTip()
	local l = { "Every guild's kill and clear times come from Chronicle (chronicleclassic.com).",
		"They come with the addon and are updated regularly, so updating WhoDidIt"
		"gets you the newest. Nothing runs on your PC and nothing about you is sent anywhere.",
		" ",
		"|cff888888Optional: the helper tools\\WhoDidIt-Sync.cmd fetches them on your PC every 10 minutes|r",
		"|cff888888instead, and makes |cffffd100Sync now|cff888888 work (it asks the helper to sync straight away).|r" }
	return l
end
tooltip(syncBtn, "Sync now", syncTip, "ANCHOR_TOP")
tooltip(syncBar, "Chronicle sync", syncTip, "ANCHOR_TOP")

-- fill the bar from the helper's status file
function UI:UpdateSync()
	local B = W.Board
	if not B then return end
	local st = B:SyncStatus()
	local c = B.chron
	local w = BW * 2 + 4
	local function bar(frac, r, g, b) syncBar.fill:SetWidth(math.max(1, w * math.min(1, frac))); syncBar.fill:SetVertexColor(r, g, b, 0.55) end
	local function ago(t) local m = floor((time() - t) / 60); return (m < 1) and "just now" or (m < 120 and (m .. " min ago") or (floor(m / 60) .. " h ago")) end
	if not ReadCustomFile then
		bar(1, 0.6, 0.15, 0.15)
		syncBar.top:SetText("|cffff7777Needs Nampower|r")
		syncBar.bot:SetText("to read the Chronicle times")
	elseif (not st or not st.alive) and c and B.chronBundled then
		-- the times that came with the addon (ChronicleData.lua)
		bar(1, 0.15, 0.55, 0.25)
		syncBar.top:SetText("|cff33ff33Raid times from " .. ago(c.synced or 0) .. "|r")
		syncBar.bot:SetText("came with the addon - update it for newer")
	elseif not st then
		bar(0, 0.6, 0.15, 0.15)
		syncBar.top:SetText(c and ("|cffffd100Synced " .. ago(c.synced or 0) .. "|r") or "|cffff7777No raid times yet|r")
		syncBar.bot:SetText("update the addon (or run the helper)")
	elseif not st.alive then
		bar(1, 0.35, 0.35, 0.35)
		syncBar.top:SetText("|cffff9933Sync helper isn't running|r")
		syncBar.bot:SetText((c and c.synced) and ("last sync " .. ago(c.synced) .. " - run WhoDidIt-Sync.cmd") or "run tools\\WhoDidIt-Sync.cmd")
	elseif st.state == "running" then
		local frac = (st.total > 0) and (st.done / st.total) or 0.05
		bar(frac, 0.2, 0.55, 1)
		syncBar.top:SetText("|cff66ccffSyncing|r " .. st.what .. ((st.total > 0) and (" " .. st.done .. "/" .. st.total) or ""))
		local left = (st.eta > 90) and ("about " .. floor(st.eta / 60 + 0.5) .. " min left") or ((st.eta > 0) and "less than 2 min left" or "working...")
		syncBar.bot:SetText("step " .. st.step .. " of " .. st.steps .. "  -  " .. left)
	elseif st.state == "error" then
		bar(1, 0.7, 0.15, 0.15)
		syncBar.top:SetText("|cffff7777Last sync failed|r - retries by itself")
		syncBar.bot:SetText(st.what)
	else
		bar(1, 0.15, 0.7, 0.2)
		local asked = B.asked and (time() - B.asked) < 30
		syncBar.top:SetText("|cff33ff33Up to date|r" .. ((c and c.synced) and (" - synced " .. ago(c.synced)) or ""))
		local nxt = st.next - time()
		syncBar.bot:SetText(asked and "starting a sync..." or ("next sync in " .. math.max(0, floor(nxt / 60 + 0.5)) .. " min - click to sync now"))
	end
	-- a sync just finished: load the new times now rather than within the minute
	if UI.syncState == "running" and st and st.state ~= "running" then
		B:LoadChronicle()
		if B.CheckRivals then B:CheckRivals() end
		UI.syncState = st.state
		UI:Refresh()
		return
	end
	UI.syncState = st and st.state
end
W:Every(3, function()
	if UI.mode == "rankings" and f:IsVisible() and syncBar:IsVisible() then UI:UpdateSync() end
end)

local rankOnly = { banterKillBtn, banterClearBtn, rivalBtn, banterTestBtn, postRivalBtn, postBoardBtn, syncBar, syncBtn }
for i = 1, getn(rankOnly) do rankOnly[i]:Hide() end

-- Hall of Fame: post what's on screen, points per fight, start over
local famePostBtn  = gridButton("Post this board", 4, 1)
local famePerBtn   = gridButton("Per fight: off", 4, 2)
local fameResetBtn = gridButton("|cffff5555Reset tally|r", 1, 2)
local fameTestBtn  = gridButton("Clear test data", 1, 1)
fameTestBtn:SetScript("OnClick", function()
	if W.Career and W.Career.HasTest() then W.Career:ClearTest(); UI:Refresh() end
end)
famePostBtn:SetScript("OnClick", function()
	local C, v = W.Career, UI.fame.view
	local ch = IsControlKeyDown() and "SELF" or nil
	if not C then return end
	if UI.fame.who then C:Post(C:PlayerLines(UI.fame.who), ch)
	elseif v == "plays" then C:Post(C:MomentLines(false, 3), ch)
	elseif v == "blunders" then C:Post(C:MomentLines(true, 3), ch)
	else C:Post(C:BoardLines(v, UI.fame.per, 5), ch) end
end)
famePerBtn:SetScript("OnClick", function() UI.fame.per = not UI.fame.per; UI:Refresh() end)
fameResetBtn:SetScript("OnClick", function()
	W:Prompt("Clear the whole Hall of Fame tally?\n|cff888888Every real player's points start again from zero. Type |cffffd100RESET|cff888888 to confirm.|r", "",
		function(text) if string.upper(text or "") == "RESET" then W.Career:Reset(); UI:Refresh() end end)
end)
tooltip(famePostBtn, "Post this board", function()
	return { "Post what you're looking at: the top 5 heroes or the Hall of Shame,", "the top 3 plays or blunders, or a player's record.",
		"|cff888888Ctrl-click: only you see it.  Posts to: " .. W.Shout:ChannelLabel() .. "|r" }
end)
tooltip(famePerBtn, "Per fight", { "Off: total points (rewards turning up).", "On: points per fight, so a raider with fewer fights can top it",
	"(only players with 3 or more fights are listed)." })
tooltip(fameResetBtn, "Reset tally", { "Clear every real player's Hall of Fame points and start again.", "Asks first. Test data is cleared separately." })
tooltip(fameTestBtn, "Clear test data", { "Demo fights add to the Hall of Fame as test data, marked |cff33ccff(test)|r,", "so you can try it out. This removes all of it; real fights stay." })
local fameOnly = { famePostBtn, famePerBtn, fameResetBtn, fameTestBtn }
for i = 1, getn(fameOnly) do fameOnly[i]:Hide() end

-- show the controls that belong to the current mode
function UI:ApplyMode()
	local fights = (UI.mode == "fights")
	local function vis(b, on) if on then b:Show() else b:Hide() end end
	for i = 1, getn(UI.modeButtons) do
		local b = UI.modeButtons[i]
		if b.id == UI.mode then b:LockHighlight() else b:UnlockHighlight() end
	end
	for i = 1, getn(UI.tabButtons) do vis(UI.tabButtons[i], fights) end
	for i = 1, getn(UI.rankButtons) do vis(UI.rankButtons[i], UI.mode == "rankings") end
	for i = 1, getn(UI.logButtons) do vis(UI.logButtons[i], UI.mode == "logs") end
	local marks = (UI.mode == "marks" and W.Marks ~= nil)
	for i = 1, getn(UI.markButtons) do vis(UI.markButtons[i], marks) end
	for i = 1, getn(markOnly) do vis(markOnly[i], marks) end
	local loot = (UI.mode == "loot" and W.Loot ~= nil)
	for i = 1, getn(UI.lootButtons) do vis(UI.lootButtons[i], loot) end
	for i = 1, getn(lootOnly) do vis(lootOnly[i], loot) end
	local fame = (UI.mode == "fame" and W.Career ~= nil)
	for i = 1, getn(UI.fameButtons) do vis(UI.fameButtons[i], fame) end
	for i = 1, getn(fameOnly) do vis(fameOnly[i], fame) end
	vis(srCopy, loot)
	vis(srSite, loot)
	local fightOnly = { shameBtn, praiseBtn, reportBtn, delBtn, clearBtn, trashBtn, annBtn, autoBtn, demoBtn }
	for i = 1, getn(fightOnly) do vis(fightOnly[i], fights) end
	for i = 1, getn(rankOnly) do vis(rankOnly[i], UI.mode == "rankings" and W.Board ~= nil) end
	local o = WhoDidItDB.opts
	banterKillBtn:SetText("Kill banter: " .. (o.banterKills and "|cff33ff33on|r" or "|cffff5555off|r"))
	banterClearBtn:SetText("Clear banter: " .. (o.banterClears and "|cff33ff33on|r" or "|cffff5555off|r"))
	rivalBtn:SetText("Rival alerts: " .. (o.rivalAlerts and "|cff33ff33on|r" or "|cffff5555off|r"))
	chanBtn:SetText("Post to: |cffffffff" .. W.Shout:ChannelLabel() .. "|r")
	if not fights then
		for i = 1, getn(UI.meterButtons) do UI.meterButtons[i]:Hide() end
		for _, list in pairs(UI.actionButtons) do
			for i = 1, getn(list) do list[i]:Hide() end
		end
	end
end

function UI:SetMode(mode)
	UI.mode = mode
	UI.rk.boss = nil; UI.rk.log = nil
	if mode == "rankings" and W.Board then W.Board:LoadChronicle() end
	UI:Open()
end

function UI:Current()
	if UI.selIdx == 0 then
		if W.Tracker.fight then
			if not UI.liveRec then UI.liveRec = W.Analyzer:Build(W.Tracker.fight, false) end
			return UI.liveRec
		end
		UI.selIdx = 1
	end
	return WhoDidItDB.fights[UI.selIdx]
end

local function row(l, r, extra)
	local d = extra or {}
	d.l = l
	d.r = r
	return d
end

local function head(rows, text)
	tinsert(rows, { l = "|cffffd100" .. text .. "|r", head = true })
end

local function pct(v) return floor((v or 0) * 100 + 0.5) .. "%" end

-- table rows: cells on fixed columns so everything lines up.
-- spec = { { width, "LEFT" | "RIGHT" | "CENTER" }, ... } (main list: ~570px)
local function cells(spec, values, extra)
	local d = extra or {}
	local c, x = {}, 4
	for i = 1, getn(spec) do
		c[i] = { x, spec[i][1], values[i] or "", spec[i][2] }
		x = x + spec[i][1] + 6
	end
	d.cols = c
	return d
end

-- the column titles row
local function colHead(rows, spec, titles)
	local v = {}
	for i = 1, getn(titles) do v[i] = "|cffffd100" .. titles[i] .. "|r" end
	tinsert(rows, cells(spec, v, { head = true }))
end

-- which column of a cells() row x falls in (x from a row click)
local function colAt(spec, x)
	local left = 4
	for i = 1, getn(spec) do
		local right = left + spec[i][1] + 6
		if x and x < right then return i end
		left = right
	end
	return getn(spec)
end

-- column layouts used by more than one tab (widths add up to ~566px)
local BLAME_SPEC = { { 24, "RIGHT" }, { 110, "LEFT" }, { 370, "LEFT" }, { 44, "RIGHT" } }        -- # / player / reason / points
local TIMED_SPEC = { { 40, "RIGHT" }, { 470, "LEFT" }, { 44, "RIGHT" } }                        -- time / text / points
local RECAP_SPEC = { { 44, "RIGHT" }, { 200, "LEFT" }, { 150, "LEFT" }, { 70, "RIGHT" }, { 60, "RIGHT" } }
local DEATH_SPEC = { { 40, "RIGHT" }, { 96, "LEFT" }, { 246, "LEFT" }, { 110, "LEFT" }, { 50, "RIGHT" } }
local MISTAKE_SPEC = { { 40, "RIGHT" }, { 78, "LEFT" }, { 390, "LEFT" }, { 40, "RIGHT" } }
local AGGRO_SPEC = { { 40, "RIGHT" }, { 130, "LEFT" }, { 100, "LEFT" }, { 100, "LEFT" }, { 46, "RIGHT" }, { 116, "RIGHT" } }
local PEAK_SPEC = { { 24, "RIGHT" }, { 150, "LEFT" }, { 80, "RIGHT" }, { 70, "RIGHT" } }
local METER_SPEC = { { 24, "RIGHT" }, { 140, "LEFT" }, { 50, "LEFT" }, { 80, "RIGHT" }, { 70, "RIGHT" }, { 60, "RIGHT" }, { 54, "RIGHT" }, { 74, "RIGHT" }, { 56, "RIGHT" } }
local ACT_SPEC = { { 24, "RIGHT" }, { 140, "LEFT" }, { 50, "LEFT" }, { 80, "RIGHT" }, { 70, "RIGHT" }, { 60, "RIGHT" } }
local UTIL_SPEC = { { 24, "RIGHT" }, { 140, "LEFT" }, { 50, "LEFT" }, { 60, "RIGHT" }, { 60, "RIGHT" }, { 60, "RIGHT" }, { 60, "RIGHT" } }
local ROLE_SHORT = { tank = "Tank", heal = "Healer", dps = "DPS" }
local TL_SPEC = { { 40, "RIGHT" }, { 520, "LEFT" } }

-- common column colours
local C_TIME  = "|cffffffff"   -- times / numbers
local C_DIM   = "|cff888888"   -- dates, secondary text
local C_YOU   = "|cff66ccff"
local C_GUILD = "|cff33ff33"

local function stripColors(s)
	s = string.gsub(s or "", "|c%x%x%x%x%x%x%x%x", "")
	s = string.gsub(s, "|r", "")
	return s
end

-- post one mistake / game-saving moment: click = the Post to channel,
-- Ctrl-click = a preview in your own chat
local function postMoment(rec, kind, t, text, pts)
	local lines = {
		W.Analyzer.ChatHeader(kind, rec),
		(t and (FmtTime(t) .. " - ") or "") .. stripColors(text) .. (pts and pts ~= 0 and ("  (" .. pts .. ")") or ""),
	}
	W:Send(lines, IsControlKeyDown() and "SELF" or nil, W.Shout.ClassMap(rec))
end

local function momentTip(tip, what)
	local out = {}
	for i = 1, getn(tip or {}) do out[i] = tip[i] end
	tinsert(out, " ")
	tinsert(out, "|cff33ff33Click: post this " .. what .. " to " .. W.Shout:ChannelLabel() .. "|r")
	tinsert(out, "|cff888888Ctrl-click: preview it in your own chat|r")
	return out
end

------------------------------------------------------------------ tab builders

function UI:FightRows()
	local rows = {}
	local live = W.Tracker.fight
	if live then
		tinsert(rows, row(
			"|cff33ccffLIVE|r  " .. live.enc .. "\n|cff888888" .. FmtTime(GetTime() - live.t0) .. " so far|r",
			"",
			{ sel = (UI.selIdx == 0), click = function() UI.selIdx = 0; UI.detail = nil; UI.cause = nil; UI.liveRec = nil; UI:Refresh() end }))
	end
	local fights = WhoDidItDB.fights
	for i = 1, getn(fights) do
		local rec = fights[i]
		local idx = i
		local nd = getn(rec.deaths or {})
		tinsert(rows, row(
			rec.enc .. "\n|cff888888" .. (rec.date or "") .. "  " .. FmtTime(rec.dur) .. "  " .. nd .. " dead|r",
			RESULT[rec.result] or rec.result,
			{ sel = (UI.selIdx == i), click = function() UI.selIdx = idx; UI.detail = nil; UI.cause = nil; UI:Refresh() end,
			  tip = { rec.zone or "", rec.verdict or "" }, tipTitle = rec.enc }))
	end
	if getn(rows) == 0 then
		tinsert(rows, row("|cff888888No fights recorded yet.\nPull a boss!|r"))
	end
	return rows
end

------------------------------------------------------------------ clicking a player's name

local POST_LABEL = {
	blame = "their blame breakdown", hero = "their game-saving plays",
	stats = "their stats", consumes = "their consumables",
}

local function toggleTank(name)
	if WhoDidItDB.tanks[name] then
		WhoDidItDB.tanks[name] = nil
		W.Print(name .. " is no longer marked as a tank.")
	else
		WhoDidItDB.tanks[name] = true
		W.Print(name .. " marked as a tank (applies to new fights).")
	end
	UI:Refresh()
end

-- the same on every player row: click posts, ctrl previews, shift shames,
-- alt praises, right-click toggles tank
local function playerClick(kind)
	return function(d, button)
		if not d.name then return end
		if button == "RightButton" then
			toggleTank(d.name)
			return
		end
		local rec = UI:Current()
		if not rec or rec.result == "LIVE" then
			W.Print("Wait for the fight to finish before posting.")
			return
		end
		if IsShiftKeyDown() then
			W.Shout:Shame(rec, d.name)
		elseif IsAltKeyDown() then
			W.Shout:Praise(rec, d.name)
		elseif IsControlKeyDown() then
			W.Shout:PlayerPost(rec, d.name, kind, "SELF")
		else
			W.Shout:PlayerPost(rec, d.name, kind)
		end
	end
end

-- copies a tooltip and appends the click legend
local function withLegend(lines, kind)
	local tip = {}
	for i = 1, getn(lines or {}) do tip[i] = lines[i] end
	tinsert(tip, " ")
	tinsert(tip, "|cffffd100Click|r  post " .. POST_LABEL[kind] .. " to " .. W.Shout:ChannelLabel())
	tinsert(tip, "|cffffd100Ctrl-click|r  preview it in your own chat first")
	tinsert(tip, "|cffffd100Shift-click|r  Name & Shame them")
	tinsert(tip, "|cffffd100Alt-click|r  Big them up")
	tinsert(tip, "|cffffd100Right-click|r  mark / unmark as a tank")
	return tip
end

function UI:SummaryRows(rec)
	local rows = {}
	head(rows, rec.result == "KILL" and "How did it go?" or (rec.result == "LIVE" and "So far" or "Why did it go wrong?"))
	if getn(rec.causes) == 0 then
		tinsert(rows, row("|cff888888No raid-wide problems detected.|r"))
	end
	for i = 1, math.min(7, getn(rec.causes)) do
		local c = rec.causes[i]
		local tip = {}
		for j = 1, getn(c.tip or {}) do tip[j] = c.tip[j] end
		tinsert(tip, "|cff888888Click for the full breakdown|r")
		local idx = i
		tinsert(rows, row((i == 1 and "|cffff5555" or "|cffff9933") .. c.text .. "|r",
			c.detail and "|cff888888details >|r" or nil,
			{ tip = tip, tipTitle = "Cause",
			  click = function() UI.cause = idx; UI:Refresh() end }))
	end

	head(rows, "Who did it? (blame points)")
	local maxPts = rec.blame[1] and rec.blame[1].pts or 1
	if maxPts <= 0 then maxPts = 1 end
	local shown = 0
	if getn(rec.blame) > 0 then colHead(rows, BLAME_SPEC, { "#", "Player", "Main reason", "Points" }) end
	for i = 1, getn(rec.blame) do
		local b = rec.blame[i]
		if shown >= 15 then break end
		shown = shown + 1
		local why = string.gsub(b.reasons[1] or "", "^" .. b.name .. " ", "")
		if getn(b.reasons) > 1 then why = why .. C_DIM .. "  (+" .. (getn(b.reasons) - 1) .. " more)|r" end
		tinsert(rows, cells(BLAME_SPEC,
			{ C_DIM .. i .. ".|r", W.CName(b.name, b.class), "|cffcccccc" .. why .. "|r", "|cffff7777" .. string.format("%.1f", b.pts) .. "|r" },
			{ bar = b.pts / maxPts, cr = 0.9, cg = 0.15, cb = 0.15, ba = 0.3,
			  tip = withLegend(b.reasons, "blame"), tipTitle = b.name .. " - " .. b.pts .. " blame points",
			  name = b.name, click = playerClick("blame") }))
	end
	if shown == 0 then tinsert(rows, row("|cff33ff33Nobody - well played.|r")) end

	if rec.heroes and getn(rec.heroes) > 0 then
		head(rows, "Heroes (see the Heroes tab)")
		for i = 1, math.min(3, getn(rec.heroes)) do
			local h = rec.heroes[i]
			local why = string.gsub(h.list[1] or "", "^" .. h.name .. " ", "")
			tinsert(rows, cells(BLAME_SPEC,
				{ C_DIM .. i .. ".|r", W.CName(h.name, h.class), "|cffcccccc" .. why .. "|r", C_GUILD .. string.format("%.1f", h.pts) .. "|r" },
				{ tip = withLegend(h.list, "hero"), tipTitle = h.name .. " - hero points",
				  name = h.name, click = playerClick("hero") }))
		end
	end

	if getn(rec.notes) > 0 then
		head(rows, "Raid notes")
		for i = 1, getn(rec.notes) do
			local n = rec.notes[i]
			tinsert(rows, row("|cffcccccc" .. n.text .. "|r", nil, { tip = n.tip, tipTitle = n.text }))
		end
	end

	head(rows, "Data sources")
	local e = rec.env or {}
	local function yn(v) return v and "|cff33ff33on|r" or "|cffff3333off|r" end
	tinsert(rows, row("Nampower " .. yn(e.nampower) .. "    SuperWoW " .. yn(e.superwow) .. "    Threat data " .. yn(e.threat)))
	local tanks = {}
	for n in pairs(WhoDidItDB.tanks) do tinsert(tanks, n) end
	tinsert(rows, row("|cff888888Tanks set: " .. (getn(tanks) > 0 and table.concat(tanks, ", ") or "auto-detect") .. "   (/wdi tank <name>, or right-click a name in Meters)|r"))
	return rows
end

-- click-through view for one "why did it go wrong" cause
function UI:CauseRows(rec, idx)
	local rows = {}
	local c = rec.causes[idx]
	tinsert(rows, row("|cffffd100<< Back to summary|r", nil, { head = true, click = function() UI.cause = nil; UI:Refresh() end }))
	if not c then return rows end
	tinsert(rows, row("|cffff7777" .. c.text .. "|r"))
	if not c.detail then
		tinsert(rows, row("|cff888888No breakdown stored for this fight (it was recorded by an older version).|r"))
		for j = 1, getn(c.tip or {}) do tinsert(rows, row(c.tip[j])) end
		return rows
	end
	for j = 1, getn(c.detail) do
		local src = c.detail[j]
		-- copy: saved rows must never get functions attached
		local d = { l = src.l, r = src.r, head = src.head }
		if src.death and rec.deaths[src.death] then
			local dd = rec.deaths[src.death]
			d.tip = { "Open " .. dd.name .. "'s death recap" }
			d.click = function()
				UI.tab = "deaths"
				UI.cause = nil
				UI.detail = dd
				UI:Refresh()
			end
		end
		tinsert(rows, d)
	end
	return rows
end

-- frozen at the moment of death: what was off cooldown (could have saved
-- them) and what wasn't. {} for fights from before this was recorded.
function UI.ReadyLines(d)
	local out = {}
	if not d or not d.ready then return out end
	if getn(d.ready) > 0 then
		tinsert(out, "|cffffd100Off cooldown when they died - could have saved them:|r")
		for i = 1, getn(d.ready) do
			local r = d.ready[i]
			tinsert(out, "   |cffffff66" .. r[1] .. "|r" .. (r[3] and (" |cff888888(" .. r[3] .. ")|r") or ""))
		end
	end
	for i = 1, getn(d.cooling or {}) do
		local c = d.cooling[i]
		tinsert(out, "|cff888888On cooldown: " .. c[1] .. (c[3] and (" (used " .. c[3] .. ")") or "") .. ", " .. c[2] .. "s left|r")
	end
	if getn(out) > 0 then
		tinsert(out, "|cff888888Not seen used within its cooldown. They may not have had it with them.|r")
	end
	return out
end

local function recapTip(d)
	local tip = {}
	for i = 1, getn(d.lines) do
		local l = d.lines[i]
		local dt = string.format("%.1fs", l.t - d.t)
		local hp = (l.hp and l.hm and l.hm > 0) and (" |cff888888" .. floor(l.hp / l.hm * 100) .. "%|r") or ""
		local txt
		if l.k == "heal" then
			txt = "|cff33ff33+" .. FmtNum(l.a) .. "|r " .. (l.sp or "") .. " (" .. (l.s or "?") .. ")"
		elseif l.k == "debuff" then
			txt = "|cffcc99ffgains " .. (l.sp or "") .. ((l.a and l.a > 1) and (" (" .. l.a .. ")") or "") .. "|r"
		elseif l.k == "item" then
			txt = "|cff66ccffused " .. (l.sp or "") .. "|r"
		elseif l.k == "buff" then
			txt = "|cffffcc66gains " .. (l.sp or "") .. "|r"
		else
			txt = "|cffff5555-" .. FmtNum(l.a) .. (l.c and "*" or "") .. "|r " .. (l.sp or "") .. " (" .. (l.s or "?") .. ")" .. (l.x == "crushing" and " |cffff9933crushing|r" or "")
		end
		tinsert(tip, { dt .. "  " .. txt, hp })
	end
	tinsert(tip, " ")
	tinsert(tip, "5s before death: " .. FmtNum(d.dmg5) .. " taken, " .. FmtNum(d.heal5) .. " healed (" .. (d.nheal or 0) .. " heals)")
	if d.debuffs and getn(d.debuffs) > 0 then tinsert(tip, "Debuffs: " .. table.concat(d.debuffs, ", ")) end
	tinsert(tip, "Consumables/items used this fight: " .. (d.cons or 0))
	if d.hadAggro then tinsert(tip, "Had aggro on " .. d.hadAggro) end
	local rl = UI.ReadyLines(d)
	if getn(rl) > 0 then tinsert(tip, " ") end
	for i = 1, getn(rl) do tinsert(tip, rl[i]) end
	tinsert(tip, "|cff888888Click for the full recap|r")
	return tip
end

function UI:DeathRows(rec)
	local rows = {}
	if UI.detail then
		local d = UI.detail
		tinsert(rows, row("|cffffd100<< Back to deaths|r", nil, { head = true, click = function() UI.detail = nil; UI:Refresh() end }))
		tinsert(rows, row(W.CName(d.name, d.class) .. " died at " .. FmtTime(d.t) .. " - " .. d.text, nil, { head = true }))
		local rl = UI.ReadyLines(d)
		for i = 1, getn(rl) do tinsert(rows, row(rl[i])) end
		colHead(rows, RECAP_SPEC, { "Time", "What happened", "From", "Amount", "Health" })
		for i = 1, getn(d.lines) do
			local l = d.lines[i]
			local hpf = (l.hp and l.hm and l.hm > 0) and (l.hp / l.hm) or nil
			local what, from, amt = "", "", ""
			if l.k == "heal" then
				what = C_GUILD .. (l.sp or "") .. "|r"
				from = l.s or "?"
				amt = C_GUILD .. "+" .. FmtNum(l.a) .. (l.c and "*" or "") .. "|r"
			elseif l.k == "debuff" then
				what = "|cffcc99ffgains " .. (l.sp or "") .. ((l.a and l.a > 1) and (" (" .. l.a .. ")") or "") .. "|r"
			elseif l.k == "item" then
				what = C_YOU .. "used " .. (l.sp or "") .. "|r"
			elseif l.k == "buff" then
				what = "|cffffcc66gains " .. (l.sp or "") .. "|r"
			else
				what = "|cffff7777" .. (l.sp or "") .. "|r" .. (l.x == "crushing" and " |cffff9933crushing|r" or "")
				from = l.s or "?"
				amt = "|cffff5555-" .. FmtNum(l.a) .. (l.c and "*" or "") .. "|r"
			end
			tinsert(rows, cells(RECAP_SPEC,
				{ C_DIM .. string.format("%.1fs", l.t - d.t) .. "|r", what, "|cffcccccc" .. from .. "|r", amt, hpf and (C_TIME .. pct(hpf) .. "|r") or "" },
				{ bar = hpf, cr = 0.1, cg = 0.75, cb = 0.1, ba = 0.3 }))
		end
		if getn(d.lines) == 0 then tinsert(rows, row("|cff888888No combat events recorded before this death.|r")) end
		return rows
	end

	if getn(rec.deaths) == 0 then
		tinsert(rows, row("|cff33ff33Nobody died.|r"))
		return rows
	end
	colHead(rows, DEATH_SPEC, { "Time", "Player", "Cause", "Killing blow", "Amount" })
	for i = 1, getn(rec.deaths) do
		local d = rec.deaths[i]
		local col = d.late and "|cff777777" or ((d.kind == "avoid" or d.kind == "aggro" or d.kind == "splash") and "|cffff7777" or "|cffdddddd")
		local dd = d
		tinsert(rows, cells(DEATH_SPEC,
			{ C_DIM .. FmtTime(d.t) .. "|r",
			  W.CName(d.name, d.class),
			  col .. d.text .. (d.late and " (after wipe)" or "") .. "|r",
			  "|cffaaaaaa" .. (d.killer or "") .. "|r",
			  d.killAmt and ("|cffff5555" .. FmtNum(d.killAmt) .. "|r") or "" },
			{ tip = recapTip(d), tipTitle = d.name .. " died at " .. FmtTime(d.t),
			  click = function() UI.detail = dd; UI:Refresh() end }))
	end
	return rows
end

-- the same layout as the Heroes tab: a board with bars, then every moment, then what counts
function UI:MistakeRows(rec)
	local rows = {}

	head(rows, "Blame board")
	local bl = rec.blame or {}
	local max = bl[1] and bl[1].pts or 1
	if max <= 0 then max = 1 end
	if getn(bl) == 0 then
		tinsert(rows, row("|cff33ff33Nobody to blame - well played.|r"))
	else
		colHead(rows, BLAME_SPEC, { "#", "Player", "Worst mistake", "Points" })
	end
	for i = 1, getn(bl) do
		local b = bl[i]
		local why = string.gsub(b.reasons[1] or "", "^" .. b.name .. " ", "")
		if getn(b.reasons) > 1 then why = why .. C_DIM .. "  (+" .. (getn(b.reasons) - 1) .. " more)|r" end
		tinsert(rows, cells(BLAME_SPEC,
			{ C_DIM .. i .. ".|r", W.CName(b.name, b.class), "|cffdddddd" .. why .. "|r",
			  "|cffff7777" .. string.format("%.1f", b.pts) .. "|r" },
			{ bar = b.pts / max, cr = 0.9, cg = 0.15, cb = 0.15, ba = 0.25, tip = withLegend(b.reasons, "blame"),
			  tipTitle = b.name .. " - " .. b.pts .. " blame points", name = b.name, click = playerClick("blame") }))
	end

	head(rows, "Mistakes")
	if getn(rec.findings) == 0 then
		tinsert(rows, row("|cff33ff33No mistakes found.|r"))
	else
		colHead(rows, MISTAKE_SPEC, { "Time", "Type", "What happened", "Points" })
	end
	for i = 1, getn(rec.findings) do
		local fd = rec.findings[i]
		local who = fd.who and rec.players[fd.who]
		local text = "|cffdddddd" .. fd.text .. "|r"
		if fd.who and who then
			local s, e = string.find(text, fd.who, 1, true)
			if s then text = string.sub(text, 1, s - 1) .. W.CName(fd.who, who.class) .. "|cffdddddd" .. string.sub(text, e + 1) end
		end
		tinsert(rows, cells(MISTAKE_SPEC,
			{ fd.t and (C_DIM .. FmtTime(fd.t) .. "|r") or (C_DIM .. "-|r"),
			  "|cffffd100" .. fd.cat .. "|r",
			  text,
			  fd.pts > 0 and ("|cffff7777+" .. fd.pts .. "|r") or (C_DIM .. "info|r") },
			{ tip = momentTip(fd.tip, "mistake"), tipTitle = stripColors(fd.text),
			  click = function()
				postMoment(rec, "MISTAKE", fd.t, "[" .. fd.cat .. "] " .. fd.text, (fd.pts > 0) and ("+" .. fd.pts .. " blame points") or nil)
			  end }))
	end

	head(rows, "What counts")
	tinsert(rows, row("|cff888888Pulling aggro off the tank, standing in avoidable damage, bombing other raiders with a debuff,|r"))
	tinsert(rows, row("|cff888888dying to a mechanic, missing interrupts and dispels, low activity or DPS, and opening on the boss|r"))
	tinsert(rows, row("|cff888888before the tank. Hover a mistake for what to do instead.|r"))
	return rows
end

local VERDICT = {
	pulled   = "|cffff5555pulled aggro|r",
	pull     = "|cffff9933opened on boss|r",
	tank     = "|cff888888tank|r",
	taunt    = "|cff888888taunt / rescue|r",
	inherit  = "|cff888888after holder died|r",
	mechanic = "|cff888888boss mechanic|r",
}

function UI:ThreatRows(rec)
	local rows = {}
	head(rows, "Who the boss attacked")
	if getn(rec.aggro) == 0 then
		tinsert(rows, row("|cff888888No boss target changes recorded (needs SuperWoW).|r"))
	end
	if getn(rec.aggro) > 0 then colHead(rows, AGGRO_SPEC, { "Time", "Boss", "Attacked", "Took it from", "Threat", "Why" }) end
	for i = 1, getn(rec.aggro) do
		local a = rec.aggro[i]
		local from = a.from and rec.players[a.from]
		tinsert(rows, cells(AGGRO_SPEC,
			{ C_DIM .. FmtTime(a.t) .. "|r",
			  "|cffdddddd" .. a.boss .. "|r",
			  W.CName(a.to, a.class),
			  a.from and W.CName(a.from, from and from.class) or (C_DIM .. "-|r"),
			  a.perc and (((a.perc >= 100) and "|cffff5555" or C_TIME) .. math.floor(a.perc + 0.5) .. "%|r") or "",
			  VERDICT[a.verdict] or "" },
				{ tipTitle = a.boss .. " at " .. FmtTime(a.t),
			  tip = { "Detected by: " .. (a.how == "melee" and "boss melee swing" or "boss target"), a.perc and ("Threat at the time: " .. math.floor(a.perc + 0.5) .. "%") or "No threat reading at the time",
			          " ", "|cff33ff33Click a name: their timeline, at " .. FmtTime(a.t) .. "|r",
			          "|cff888888(Attacked = " .. a.to .. (a.from and (", Took it from = " .. a.from) or "") .. ")|r" },
			  click = function(d, btn, x)
				local col = colAt(AGGRO_SPEC, x)
				UI:ShowTimeline((col == 4 and a.from) or a.to, a.t)
			  end }))
	end

	head(rows, "Peak threat (% of the aggro holder)")
	local list = {}
	for name, t in pairs(rec.threat) do tinsert(list, { name, t }) end
	table.sort(list, function(a, b) return a[2].perc > b[2].perc end)
	if getn(list) == 0 then
		tinsert(rows, row("|cff888888No threat data. Target the boss during the fight - threat comes from the Turtle server for your target.|r"))
	end
	if getn(list) > 0 then colHead(rows, PEAK_SPEC, { "#", "Player", "Peak threat", "When" }) end
	for i = 1, getn(list) do
		local name, t = list[i][1], list[i][2]
		local r, g, b = W.ClassRGB(t.class)
		local col = t.perc >= 100 and "|cffff5555" or (t.perc >= 90 and "|cffff9933" or C_TIME)
		tinsert(rows, cells(PEAK_SPEC,
			{ C_DIM .. i .. ".|r", W.CName(name, t.class), col .. t.perc .. "%|r", C_DIM .. FmtTime(t.t) .. "|r" },
			{ bar = t.perc / 130, cr = r, cg = g, cb = b, ba = 0.3, tipTitle = name,
			  tip = { "Highest threat: " .. t.perc .. "% of the aggro holder, at " .. FmtTime(t.t), "|cff33ff33Click: " .. name .. "'s timeline at that moment|r" },
			  click = function() UI:ShowTimeline(name, t.t) end }))
	end
	return rows
end

function UI:MeterRows(rec)
	local rows = {}
	local mode = UI.meter
	local list = {}
	for name, p in pairs(rec.players) do
		local v
		if mode == "dmg" then v = p.dmg
		elseif mode == "heal" then v = p.heal
		elseif mode == "taken" then v = p.taken
		elseif mode == "act" then v = p.act or 0
		else v = (p.kicks or 0) + (p.dispels or 0) + (p.tranqs or 0) + (p.cons or 0) end
		if v and v > 0 then tinsert(list, { name = name, p = p, v = v }) end
	end
	table.sort(list, function(a, b) return a.v > b.v end)
	local max = list[1] and list[1].v or 1
	if mode == "act" then max = 1 end
	if getn(list) == 0 then tinsert(rows, row("|cff888888No data.|r")) end
	local total = 0
	for i = 1, getn(list) do total = total + list[i].v end
	if total <= 0 then total = 1 end
	local spec = (mode == "act") and ACT_SPEC or ((mode == "util") and UTIL_SPEC or METER_SPEC)
	if getn(list) > 0 then
		if mode == "act" then
			colHead(rows, spec, { "#", "Player", "Role", "Active", "Alive", "Deaths" })
		elseif mode == "util" then
			colHead(rows, spec, { "#", "Player", "Role", "Kicks", "Dispels", "Tranqs", "Items" })
		else
			colHead(rows, spec, { "#", "Player", "Role", "Total", "Per sec", "Share", "Crit", "Biggest", "Deaths" })
		end
	end

	for i = 1, getn(list) do
		local it = list[i]
		local p = it.p
		local r, g, b = W.ClassRGB(p.class)
		local tip
		local alive = (p.alive and p.alive > 0) and p.alive or rec.dur
		local role = C_DIM .. (ROLE_SHORT[p.role] or "") .. "|r"
		local deaths = ((p.deaths or 0) > 0) and ("|cffff5555" .. p.deaths .. "|r") or (C_DIM .. "-|r")
		local vals = { C_DIM .. i .. ".|r", W.CName(it.name, p.class), role }
		if mode == "dmg" or mode == "heal" or mode == "taken" then
			local vc = (mode == "heal") and C_GUILD or ((mode == "taken") and "|cffff7777" or C_TIME)
			tinsert(vals, vc .. FmtNum(it.v) .. "|r")
			tinsert(vals, C_TIME .. FmtNum(it.v / alive) .. "|r")
			tinsert(vals, "|cffaaaaaa" .. pct(it.v / total) .. "|r")
			-- crit rate and biggest single hit / heal (fights recorded from v1.4.1 on)
			local hits = (mode == "dmg" and p.dHits) or (mode == "heal" and p.hHits) or nil
			local big = (mode == "dmg" and p.dMax) or (mode == "heal" and p.hMax) or nil
			local crits = (mode == "dmg" and p.dCrits) or (mode == "heal" and p.hCrits) or 0
			tinsert(vals, (hits and hits > 0) and (C_TIME .. pct(crits / hits) .. "|r") or (C_DIM .. "-|r"))
			tinsert(vals, (big and big > 0) and ("|cffffffff" .. FmtNum(big) .. "|r") or (C_DIM .. "-|r"))
			tinsert(vals, deaths)
			local src = (mode == "dmg" and p.ds) or (mode == "heal" and p.hs) or p.ts
			tip = {}
			if src and src[1] and src[1][3] then
				tinsert(tip, { C_DIM .. "Spell|r", C_DIM .. "total   share   hits   crit   biggest|r" })
			end
			for j = 1, getn(src or {}) do
				local s = src[j]
				local right = FmtNum(s[2]) .. "  " .. pct(s[2] / it.v)
				if s[3] and s[3] > 0 then
					right = right .. C_DIM .. "   " .. s[3] .. "x   " .. pct((s[4] or 0) / s[3]) .. "   " .. FmtNum(s[5] or 0) .. "|r"
				end
				tinsert(tip, { s[1], right })
			end
			if big and big > 0 then
				local sp = (mode == "dmg") and p.dMaxSp or p.hMaxSp
				tinsert(tip, { "Biggest " .. (mode == "heal" and "heal" or "hit"), FmtNum(big) .. (sp and ("  (" .. sp .. ")") or "") })
			end
			if mode == "dmg" then tinsert(tip, { "Damage to bosses", FmtNum(p.boss) }) end
		elseif mode == "act" then
			local ac = (it.v >= 0.85) and C_GUILD or ((it.v >= 0.6) and C_TIME or "|cffff9933")
			tinsert(vals, ac .. pct(it.v) .. "|r")
			tinsert(vals, C_DIM .. FmtTime(alive) .. "|r")
			tinsert(vals, deaths)
			tip = { "Share of their time alive spent casting / swinging / healing.", "Alive: " .. FmtTime(alive) }
		else
			local function n(x, c) return ((x or 0) > 0) and (c .. x .. "|r") or (C_DIM .. "-|r") end
			tinsert(vals, n(p.kicks, C_TIME))
			tinsert(vals, n(p.dispels, C_TIME))
			tinsert(vals, n(p.tranqs, C_TIME))
			tinsert(vals, n(p.cons, C_YOU))
			tip = {}
			for j = 1, getn(p.consList or {}) do tinsert(tip, { p.consList[j][1], p.consList[j][2] .. "x" }) end
		end
		tinsert(tip, " ")
		tinsert(tip, "Role: " .. (p.role or "?") .. (WhoDidItDB.tanks[it.name] and " (marked tank)" or "") .. "   Deaths: " .. (p.deaths or 0))
		if (p.aggro or 0) > 0 then tinsert(tip, "Held boss aggro for " .. FmtTime(p.aggro)) end
		tip = withLegend(tip, "stats")
		tinsert(rows, cells(spec, vals,
			{ bar = it.v / max, cr = r, cg = g, cb = b, ba = 0.3, tip = tip, tipTitle = it.name, name = it.name, click = playerClick("stats") }))
	end
	return rows
end

local USED_COL = { Mana = "66aaff", Health = "33ff33", Protection = "ff6666", Other = "dddddd" }
-- role groups in the Consumes grid, top to bottom
local CONS_GROUPS = {
	{ "tank", "TANKS", "c79c6e" }, { "healer", "HEALERS", "33ff99" }, { "melee", "MELEE", "ff6666" },
	{ "ranged", "RANGED", "abd473" }, { "caster", "CASTERS", "69ccf0" }, { "other", "OTHERS", "aaaaaa" },
}

-- one grid cell: { x, state, icon, title, tip, text }
local function consCell(rec, p, name, c, ctx)
	local Cons, CG = W.Cons, UI.CG
	local col = CG.COLS[c]
	local x = CG.X + (c - 1) * CG.STEP + 4
	local title = col[2] .. " - " .. W.CName(name, p.class)
	local X = "|cffff4444X|r"
	local missing = ctx.missAt[c] and { "|cffff7777Missing|r - a " .. ctx.roleText .. " should have: " .. ctx.missAt[c] }
	if col[3] == "WPN" then
		-- the main hand: oil / stone / imbue (read separately from buffs)
		if p.wpn and ctx.missAt[c] then
			return { x, "miss", ctx.missIcon[c], title, { "|cffff7777Wrong one|r - a " .. ctx.roleText .. " should have: " .. ctx.missAt[c],
				"Has: " .. ((type(p.wpn) == "string") and p.wpn or "?") }, X }
		elseif p.wpn then
			return { x, "ok", Cons.WeaponIcon(p.wpn), title, { (type(p.wpn) == "string") and p.wpn or "Something on their main hand" } }
		elseif missing then
			return { x, "miss", ctx.missIcon[c], title, missing, X }
		elseif p.wpn == nil and ctx.expected[c] then
			return { x, "unk", nil, title, { "Couldn't see their weapon (out of range, or no SuperWoW)." }, "|cffcccccc?|r" }
		end
		return { x, "na", nil, title, { ctx.expected[c] and "Nothing on their main hand." or ("Not expected for a " .. ctx.roleText .. ".") }, C_DIM .. "-|r" }
	end
	local have = ctx.inCol[c]
	if have then
		local tip = {}
		for k = 1, getn(have) do
			local bf = have[k]
			tinsert(tip, "|cff33ff33" .. bf[1] .. "|r  " .. C_DIM .. ((bf[3] and bf[3] > 0) and ("gained " .. FmtTime(bf[3]) .. " into the fight") or "had it at the pull") .. "|r")
		end
		return { x, "ok", W.Cons.Icon(have[1][1]), title, tip }
	elseif ctx.unread then
		return { x, "unk", nil, title, { "Out of range at the pull - can't tell, so not counted." }, "|cffcccccc?|r" }
	elseif missing then
		return { x, "miss", ctx.missIcon[c], title, missing, X }
	end
	return { x, "na", nil, title, { ctx.expected[c] and "Not needed: they covered it with another buff." or ("Not expected for a " .. ctx.roleText .. ".") }, C_DIM .. "-|r" }
end

function UI:ConsumeRows(rec)
	local rows = {}
	if not W.Cons then
		tinsert(rows, row("|cffff7777To finish updating: " .. W.RESTART_HINT .. ".|r"))
		return rows
	end
	if UI.consView == "used" then return UI:UsedRows(rec) end
	local Cons, CG = W.Cons, UI.CG
	local nCols = getn(CG.COLS)
	do
		local hdr = {}
		for i = 1, getn(UI.CG.COLS) do
			local c = UI.CG.COLS[i]
			hdr[i] = { c[1], c[2], { c[4], " ", "|cff40bf4dGreen|r  they had it (hover for which one)",
				"|cffd92626Red X|r  their role needs it and they didn't have it", "|cff888888-|r  not expected for their role",
				"|cff888888?|r  out of range at the pull - not counted" } }
		end
		UI.SetGridHead(hdr, { "READY", "Ready", { "Must-haves they had, out of what their role needs.", "Green = everything. Flasks only count in the big raids." } },
			{ "USED", "Used", { "Items used during the fight - click Used (top left) for every item." } })
	end
	local slotCol = {}
	for i = 1, nCols do
		if type(CG.COLS[i][3]) == "table" then
			for s in pairs(CG.COLS[i][3]) do slotCol[s] = i end
		end
	end
	UI.consFold = UI.consFold or {}

	-- every player: grid cells, ready count, items used, tooltip
	local groups, missCount, nPlayers, anyBuffs = {}, {}, 0, false
	local usedTotals = { Mana = 0, Health = 0, Protection = 0, Other = 0 }
	for name, p in pairs(rec.players) do
		nPlayers = nPlayers + 1
		if p.cbuffs then anyBuffs = true end
		local role = Cons.Role(p) or "other"
		local needs = Cons.Needs(p, rec.zone)
		local ctx = { roleText = string.lower(Cons.ROLE_TEXT[role] or "raider"), unread = (needs == nil),
			inCol = {}, missAt = {}, missIcon = {}, expected = {} }
		local cb = p.cbuffs or {}
		for j = 1, getn(cb) do
			local c = slotCol[W.Data.consumeSlot[cb[j][1]] or ""]
			if c then
				ctx.inCol[c] = ctx.inCol[c] or {}
				tinsert(ctx.inCol[c], cb[j])
			end
		end
		-- an unmet need shows in the column of its first slot
		local met, total = 0, 0
		for j = 1, getn(needs or {}) do
			local nd = needs[j]
			local c = nCols
			if type(nd[2]) == "table" then
				c = slotCol[nd[2][1]]
				for k = 1, getn(nd[2]) do if slotCol[nd[2][k]] then ctx.expected[slotCol[nd[2][k]]] = true end end
			else
				ctx.expected[nCols] = true
			end
			total = total + 1
			if nd[3] then
				met = met + 1
			elseif c then
				ctx.missAt[c] = nd[1]
				ctx.missIcon[c] = Cons.NeedIcon(nd)
			end
		end
		local grid = {}
		for c = 1, nCols do
			local cell = consCell(rec, p, name, c, ctx)
			if cell[2] == "miss" then missCount[c] = (missCount[c] or 0) + 1 end
			tinsert(grid, cell)
		end

		-- items used, and the row tooltip
		local used = p.used
		if not used then
			used = {}
			for j = 1, getn(p.consList or {}) do used[j] = { p.consList[j][1], p.consList[j][2], "Other" } end
		end
		local nUsed, tip = 0, {}
		for j = 1, getn(used) do
			local u = used[j]
			nUsed = nUsed + u[2]
			usedTotals[u[3]] = (usedTotals[u[3]] or 0) + u[2]
			tinsert(tip, { "used |cff" .. (USED_COL[u[3]] or "ffffff") .. u[1] .. "|r", u[2] .. "x" })
		end
		if ctx.unread then
			tinsert(tip, 1, C_DIM .. "Out of range at the pull - can't say what they had, so they're not counted as missing anything.|r")
		elseif met < total then
			tinsert(tip, 1, "|cffff7777Missing for a " .. ctx.roleText .. ": " .. table.concat(Cons.Missing(p, rec.zone), ", ") .. "|r")
		else
			tinsert(tip, 1, "|cff33ff33Has everything a " .. ctx.roleText .. " needs.|r")
		end
		tip = withLegend(tip, "consumes")

		local ready
		if ctx.unread then ready = C_DIM .. "--|r"
		elseif total == 0 then ready = C_DIM .. "-|r"
		else ready = ((met == total) and "|cff33ff33" or "|cffff5555") .. met .. "/" .. total .. "|r" end
		local g = CONS_GROUPS[getn(CONS_GROUPS)]
		for j = 1, getn(CONS_GROUPS) do if CONS_GROUPS[j][1] == role then g = CONS_GROUPS[j] end end
		local grp = groups[g[1]]
		if not grp then
			grp = { n = 0, ready = 0, unread = 0, list = {} }
			groups[g[1]] = grp
		end
		grp.n = grp.n + 1
		if ctx.unread then grp.unread = grp.unread + 1 elseif met == total then grp.ready = grp.ready + 1 end
		tinsert(grp.list, {
			name = name, gaps = ctx.unread and -1 or (total - met),
			d = {
				cols = {
					{ CG.NAME, 110, W.CName(name, p.class), "LEFT" },
					{ CG.ROLE, 52, "|cff" .. g[3] .. string.upper(Cons.ROLE_TEXT[role] or "?") .. "|r", "CENTER" },
					{ CG.READY, 44, ready, "CENTER" },
					{ CG.USED, 54, (nUsed > 0) and (C_YOU .. nUsed .. "|r") or (C_DIM .. "0|r"), "CENTER" },
				},
				grid = grid, tip = tip, tipTitle = name .. " - consumables", name = name, click = playerClick("consumes"),
			},
		})
	end
	if nPlayers == 0 then
		tinsert(rows, row("|cff888888No players recorded.|r"))
		return rows
	end

	-- the slacker check (click to post) and items used
	local slack, unknown = Cons.Slackers(rec)
	local stip = { "Each role's must-haves: flask (big raids), food, the role's elixir and a weapon oil / stone",
		"(shamans: Rockbiter on tanks, Windfury on melee) - the red X cells below." }
	if getn(slack) > 0 then
		tinsert(stip, " ")
		local order, gr = Cons.ByNeed(slack)
		for i = 1, getn(order) do tinsert(stip, "|cffff7777No " .. order[i] .. ":|r " .. table.concat(gr[order[i]], ", ")) end
	end
	if unknown > 0 then tinsert(stip, C_DIM .. unknown .. " out of range at the pull - not counted|r") end
	tinsert(stip, "|cffffd100Click: post it (" .. W.Shout:ChannelLabel() .. ")|r")
	tinsert(rows, row("|cffffd100Missing something:|r  "
		.. ((getn(slack) == 0) and (C_GUILD .. "nobody|r") or ("|cffff7777" .. getn(slack) .. " of " .. nPlayers .. "|r"))
		.. ((unknown > 0) and (C_DIM .. "  (" .. unknown .. " out of range)|r") or "") .. C_DIM .. "  - click to post|r",
		"Used:  |cff" .. USED_COL.Mana .. usedTotals.Mana .. " mana|r   |cff" .. USED_COL.Health .. usedTotals.Health .. " health|r   |cff"
		.. USED_COL.Protection .. usedTotals.Protection .. " prot|r   |cff" .. USED_COL.Other .. usedTotals.Other .. " other|r",
		{ tipTitle = "Slacker check", tip = stip, click = function() W.Shout:Consumes(rec, "missing") end }))
	if not anyBuffs then
		tinsert(rows, row("|cff888888This fight was recorded by an older version - only items used are available.|r"))
	end

	-- role groups: gaps first, out of range last; click a group to fold it
	for gi = 1, getn(CONS_GROUPS) do
		local g = CONS_GROUPS[gi]
		local grp = groups[g[1]]
		if grp then
			local readable = grp.n - grp.unread
			local folded = UI.consFold[g[1]]
			tinsert(rows, { head = true,
				cols = { { CG.NAME, 600, (folded and "|cffaaaaaa+|r  " or "|cffaaaaaa-|r  ") .. "|cff" .. g[3] .. g[2] .. "|r   "
					.. ((grp.ready == readable) and "|cff33ff33" or "|cffff7777") .. grp.ready .. "/" .. readable .. " ready|r"
					.. ((grp.unread > 0) and (C_DIM .. "   - " .. grp.unread .. " out of range|r") or ""), "LEFT" } },
				tipTitle = g[2], tip = { "Click to " .. (folded and "show" or "hide") .. " this group." },
				click = function() UI.consFold[g[1]] = not UI.consFold[g[1]]; UI:Refresh() end })
			if not folded then
				table.sort(grp.list, function(a, b)
					if a.gaps ~= b.gaps then return a.gaps > b.gaps end
					return a.name < b.name
				end)
				for i = 1, getn(grp.list) do tinsert(rows, grp.list[i].d) end
			end
		end
	end

	-- how many were missing each slot
	local foot = { { CG.NAME, 160, C_DIM .. "Missing per slot|r", "LEFT" } }
	for c = 1, nCols do
		local n = missCount[c] or 0
		tinsert(foot, { CG.X + (c - 1) * CG.STEP, CG.STEP, (n > 0) and ("|cffff5555" .. n .. "|r") or (C_DIM .. "0|r"), "CENTER" })
	end
	tinsert(rows, { head = true, cols = foot, tipTitle = "Missing per slot", tip = { "How many players were missing their role's must-have in each column." } })
	return rows
end

-- Consumes tab, "Used" view: every item used in the fight, a column per kind
-- (first match wins, so the more specific kinds come first)
local IC = "Interface\\Icons\\"
UI.USED_COLS = {
	{ "PROT", "Protection potions", { "Protection" }, IC .. "INV_Potion_24" },
	{ "HS", "Healthstones", { "Healthstone" }, IC .. "INV_Stone_04" },
	{ "HP", "Healing potions", { "Healing Potion", "Healing Draught", "Rejuvenation", "Whipper Root" }, IC .. "INV_Potion_54" },
	{ "GEM", "Mana gems", { "Mana Gem", "Mana Jade", "Mana Citrine", "Mana Ruby", "Mana Agate" }, IC .. "INV_Misc_Gem_Ruby_01" },
	{ "MANA", "Mana potions", { "Mana Potion", "Restore Mana" }, IC .. "INV_Potion_76" },
	{ "RUNE", "Runes", { "Demonic Rune", "Dark Rune", "Rune of" }, IC .. "INV_Misc_Rune_04" },
	{ "TEA", "Tea", { "Tea" }, IC .. "INV_Drink_Milk_05" },
	{ "BAND", "Bandages", { "Bandage", "First Aid" }, IC .. "INV_Misc_Bandage_12" },
	{ "BOOM", "Explosives", { "Sapper", "Dynamite", "Grenade", "Bomb", "Explosive" }, IC .. "Spell_Fire_SelfDestruct" },
	{ "UTIL", "Other potions", { "Free Action", "Living Action", "Invulnerability", "Restorative", "Stoneshield", "Mighty Rage", "Swiftness", "Potion" }, IC .. "INV_Potion_04" },
	{ "OTH", "Everything else", nil, IC .. "INV_Misc_Bag_10" },
}

local function usedCol(item)
	local cols = UI.USED_COLS
	for i = 1, getn(cols) - 1 do
		for j = 1, getn(cols[i][3]) do
			if string.find(item, cols[i][3][j], 1, true) then return i end
		end
	end
	return getn(cols)
end

function UI:UsedRows(rec)
	local rows = {}
	local Cons, CG, cols = W.Cons, UI.CG, UI.USED_COLS
	UI.consFold = UI.consFold or {}
	local n = getn(cols)
	local hdr = {}
	for i = 1, n do
		local pats = cols[i][3] and table.concat(cols[i][3], ", ") or "anything not in the other columns"
		hdr[i] = { cols[i][1], cols[i][2], { "Items whose name has: " .. pats, " ", "The number is how many they used. Hover a square for the items." } }
	end
	UI.SetGridHead(hdr, { "TOTAL", "Total", { "Every item they used during the fight." } },
		{ "DIED", "Died", { "When they died. The row is frozen at that moment: a |cffffd100yellow !|r square was",
			"off cooldown and unused - it could have saved them. Hover the name for their class cooldowns too." } })
	-- each player's first death (the frozen snapshot), and the columns it lights up
	local deathOf = {}
	for i = 1, getn(rec.deaths or {}) do
		local d = rec.deaths[i]
		if not d.late and not deathOf[d.name] then deathOf[d.name] = d end
	end
	local readyCol = {}
	for i = 1, n do
		if cols[i][1] == "HP" then readyCol[i] = "potion" elseif cols[i][1] == "HS" then readyCol[i] = "healthstone" end
	end
	local groups, totals, nPlayers, all = {}, {}, 0, 0
	for name, p in pairs(rec.players) do
		nPlayers = nPlayers + 1
		local role = Cons.Role(p) or "other"
		local used = p.used
		if not used then
			used = {}
			for j = 1, getn(p.consList or {}) do used[j] = { p.consList[j][1], p.consList[j][2], "Other" } end
		end
		local per, sum = {}, 0
		local tip = {}
		for j = 1, getn(used) do
			local u = used[j]
			local c = usedCol(u[1])
			per[c] = per[c] or { n = 0, items = {} }
			per[c].n = per[c].n + u[2]
			tinsert(per[c].items, u[1] .. "  |cffffffffx" .. u[2] .. "|r")
			sum = sum + u[2]
			tinsert(tip, { u[1], "x" .. u[2] })
		end
		all = all + sum
		if getn(tip) == 0 then tip = { C_DIM .. "Used nothing this fight.|r" } end
		local dd = deathOf[name]
		local readyKind, nReady = {}, 0
		if dd then
			tinsert(tip, 1, "|cffff5555Died at " .. FmtTime(dd.t) .. "|r - " .. (dd.text or ""))
			local rl = UI.ReadyLines(dd)
			for j = 1, getn(rl) do tinsert(tip, 1 + j, rl[j]) end
			for j = 1, getn(dd.ready or {}) do
				readyKind[dd.ready[j][2]] = dd.ready[j][1]
				nReady = nReady + 1
			end
		end
		tip = withLegend(tip, "consumes")
		local grid = {}
		for c = 1, n do
			local x = CG.X + (c - 1) * CG.STEP + 4
			local title = cols[c][2] .. " - " .. W.CName(name, p.class)
			local rk = readyCol[c] and readyKind[readyCol[c]]
			if per[c] then
				totals[c] = (totals[c] or 0) + per[c].n
				local items = per[c].items
				if rk then
					items = { unpack(items) }
					tinsert(items, "|cffffd100Off cooldown again when they died at " .. FmtTime(dd.t) .. ".|r")
				end
				tinsert(grid, { x, "ok", cols[c][4], title, items, nil, per[c].n })
			elseif rk then
				tinsert(grid, { x, "ready", cols[c][4], title, { "|cffffd100Off cooldown when they died at " .. FmtTime(dd.t) .. "|r",
					(readyCol[c] == "potion") and "No potion used in the 2 minutes before - a healing or protection potion could have saved them."
						or "No healthstone used in the 2 minutes before - it could have saved them.",
					C_DIM .. "They may not have had one with them.|r" }, "|cffffd100!|r" })
			else
				tinsert(grid, { x, "na", nil, title, { "None used." }, C_DIM .. "-|r" })
			end
		end
		local g = CONS_GROUPS[getn(CONS_GROUPS)]
		for j = 1, getn(CONS_GROUPS) do if CONS_GROUPS[j][1] == role then g = CONS_GROUPS[j] end end
		local grp = groups[g[1]]
		if not grp then
			grp = { n = 0, sum = 0, list = {} }
			groups[g[1]] = grp
		end
		grp.n = grp.n + 1
		grp.sum = grp.sum + sum
		tinsert(grp.list, { name = name, sum = sum, d = {
			cols = {
				{ CG.NAME, 110, W.CName(name, p.class), "LEFT" },
				{ CG.ROLE, 52, "|cff" .. g[3] .. string.upper(Cons.ROLE_TEXT[role] or "?") .. "|r", "CENTER" },
				{ CG.READY, 44, (sum > 0) and (C_YOU .. sum .. "|r") or (C_DIM .. "0|r"), "CENTER" },
				{ CG.USED, 54, dd and ("|cffff5555" .. FmtTime(dd.t) .. "|r" .. ((nReady > 0) and " |cffffd100!|r" or "")) or "", "CENTER" },
			},
			grid = grid, tip = tip, tipTitle = name .. " - used in the fight" .. (dd and " (frozen at death)" or ""), name = name, click = playerClick("consumes"),
		} })
	end
	if nPlayers == 0 then
		tinsert(rows, row("|cff888888No players recorded.|r"))
		return rows
	end

	-- one line with the raid's totals (click to post the consumes summary)
	local bits = {}
	for c = 1, n do
		if totals[c] then tinsert(bits, "|cffffffff" .. totals[c] .. "|r " .. string.lower(cols[c][2])) end
	end
	tinsert(rows, row("|cffffd100Used in the fight:|r  " .. ((all > 0) and table.concat(bits, C_DIM .. ",|r  ") or (C_DIM .. "nothing|r")),
		C_DIM .. "click to post|r", { tipTitle = "Items used", tip = { "Every potion, rune, tea, healthstone, bandage and bomb the raid used.",
			"|cffffd100Click: post the consumes summary (" .. W.Shout:ChannelLabel() .. ")|r" },
			click = function() W.Shout:Consumes(rec, "summary") end }))

	for gi = 1, getn(CONS_GROUPS) do
		local g = CONS_GROUPS[gi]
		local grp = groups[g[1]]
		if grp then
			local folded = UI.consFold[g[1]]
			tinsert(rows, { head = true,
				cols = { { CG.NAME, 600, (folded and "|cffaaaaaa+|r  " or "|cffaaaaaa-|r  ") .. "|cff" .. g[3] .. g[2] .. "|r   "
					.. C_YOU .. grp.sum .. "|r" .. C_DIM .. " items used by " .. grp.n .. "|r", "LEFT" } },
				tipTitle = g[2], tip = { "Click to " .. (folded and "show" or "hide") .. " this group." },
				click = function() UI.consFold[g[1]] = not UI.consFold[g[1]]; UI:Refresh() end })
			if not folded then
				table.sort(grp.list, function(a, b)
					if a.sum ~= b.sum then return a.sum > b.sum end
					return a.name < b.name
				end)
				for i = 1, getn(grp.list) do tinsert(rows, grp.list[i].d) end
			end
		end
	end

	local foot = { { CG.NAME, 160, C_DIM .. "Raid total|r", "LEFT" } }
	for c = 1, n do
		local t = totals[c] or 0
		tinsert(foot, { CG.X + (c - 1) * CG.STEP, CG.STEP, (t > 0) and ("|cffffffff" .. t .. "|r") or (C_DIM .. "0|r"), "CENTER" })
	end
	tinsert(foot, { CG.READY, 44, C_YOU .. all .. "|r", "CENTER" })
	tinsert(rows, { head = true, cols = foot, tipTitle = "Raid total", tip = { "How many of each the whole raid used." } })
	return rows
end

-- class-colour every raid member's name inside a sentence
local function colorNames(text, rec)
	return (string.gsub(text or "", "([^%s%p%d]+)", function(w)
		local p = rec.players[w]
		if p then return W.CName(w, p.class) end
		-- Lua 5.0 replaces the match with "" when the callback returns nil
		return w
	end))
end
UI.ColorNames = colorNames

-- colour a sentence, picking the colour back up after every coloured name
local function tint(text, col)
	return col .. (string.gsub(text, "|r", "|r" .. col)) .. "|r"
end

-- a game-saving moment's kind, from how it's worded (the Type column)
local SAVE_TYPES = W.Data.saveTypes
local function saveType(text)
	for i = 1, getn(SAVE_TYPES) do
		if string.find(text or "", SAVE_TYPES[i][1], 1, true) then return SAVE_TYPES[i][2] end
	end
	return "Save"
end

function UI:HeroRows(rec)
	local rows = {}
	if not rec.saves then
		tinsert(rows, row("|cff888888This fight was recorded by an older version - no hero data.|r"))
		return rows
	end
	head(rows, "Hero board")
	local hs = rec.heroes or {}
	local max = hs[1] and hs[1].pts or 1
	if max <= 0 then max = 1 end
	if getn(hs) == 0 then
		tinsert(rows, row("|cff888888No game-saving plays detected this fight.|r"))
	else
		colHead(rows, BLAME_SPEC, { "#", "Player", "Best moment", "Points" })
	end
	for i = 1, getn(hs) do
		local h = hs[i]
		local why = string.gsub(h.list[1] or "", "^" .. h.name .. " ", "")
		if getn(h.list) > 1 then why = why .. C_DIM .. "  (+" .. (getn(h.list) - 1) .. " more)|r" end
		tinsert(rows, cells(BLAME_SPEC,
			{ C_DIM .. i .. ".|r", W.CName(h.name, h.class), tint(colorNames(why, rec), "|cffdddddd"),
			  C_GUILD .. string.format("%.1f", h.pts) .. "|r" },
			{ bar = h.pts / max, cr = 0.15, cg = 0.8, cb = 0.3, ba = 0.25, tip = withLegend(h.list, "hero"),
			  tipTitle = h.name .. " - " .. h.pts .. " hero points", name = h.name, click = playerClick("hero") }))
	end

	head(rows, "Game-saving moments")
	if getn(rec.saves) == 0 then
		tinsert(rows, row("|cff888888Nothing this time.|r"))
	else
		colHead(rows, MISTAKE_SPEC, { "Time", "Type", "What happened", "Points" })
	end
	for i = 1, getn(rec.saves) do
		local s = rec.saves[i]
		tinsert(rows, cells(MISTAKE_SPEC,
			{ s.t and (C_DIM .. FmtTime(s.t) .. "|r") or (C_DIM .. "-|r"),
			  C_GUILD .. saveType(s.text) .. "|r",
			  tint(colorNames(s.text, rec), "|cffdddddd"),
			  C_GUILD .. "+" .. s.pts .. "|r" },
			{ tip = momentTip(s.tip, "game-saving moment"), tipTitle = "Game-saving moment",
			  click = function() postMoment(rec, "HERO MOMENT", s.t, s.text, "+" .. s.pts .. " hero points") end }))
	end

	head(rows, "What counts")
	tinsert(rows, row("|cff888888Heals that land on someone under 20% who then lives, shields that soak a killing blow, taunts that|r"))
	tinsert(rows, row("|cff888888rescue a player from the boss, Lay on Hands / BoP, battle res, Innervate on a low-mana healer,|r"))
	tinsert(rows, row("|cff888888dispelling mind control, interrupts, fast tranqs and last-second potions or cooldowns.|r"))
	return rows
end

-- open the Timeline on one player, scrolled to a moment (from Threat and elsewhere)
function UI:ShowTimeline(who, t)
	UI.tab = "timeline"
	UI.detail = nil; UI.cause = nil
	UI.tl = { who = who, t = t, fight = UI.selIdx, scroll = true }
	UI:Refresh()
end

-- does a timeline line mention this player (as a whole word)?
local function mentions(text, name)
	local s, e = string.find(text or "", name, 1, true)
	while s do
		local before, after = string.sub(text, s - 1, s - 1), string.sub(text, e + 1, e + 1)
		if not string.find(before, "%a") and not string.find(after, "%a") then return true end
		s, e = string.find(text, name, e + 1, true)
	end
	return false
end

-- which player's name in a timeline line was clicked: the names in the line
-- (in order), measured with a hidden font string in the row's font
local measure
local function nameAt(text, rec, x)
	local found = {}
	for name in pairs(rec.players) do
		local s, e = string.find(text, name, 1, true)
		while s do
			local before, after = string.sub(text, s - 1, s - 1), string.sub(text, e + 1, e + 1)
			if not string.find(before, "%a") and not string.find(after, "%a") then
				tinsert(found, { name, s, e })
				break
			end
			s, e = string.find(text, name, e + 1, true)
		end
	end
	if getn(found) == 0 then return nil end
	table.sort(found, function(a, b) return a[2] < b[2] end)
	if not measure then
		measure = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		measure:Hide()
	end
	local function width(s)
		measure:SetText(s)
		return measure:GetStringWidth() or 0
	end
	if x then
		for i = 1, getn(found) do
			local n = found[i]
			local left = width(string.sub(text, 1, n[2] - 1))
			local right = width(string.sub(text, 1, n[3]))
			if x >= left - 3 and x <= right + 3 then return n[1] end
		end
	end
	return found[1][1]   -- not on a name: the first player in the line
end

function UI:TimelineRows(rec)
	local rows = {}
	local tl = rec.timeline or {}
	if getn(tl) == 0 then
		tinsert(rows, row("|cff888888Nothing recorded.|r"))
		return rows
	end
	local focus = UI.tl
	if focus and focus.fight ~= UI.selIdx then focus = nil; UI.tl = nil end
	local who = focus and focus.who
	if focus then
		local p = who and rec.players[who]
		local title = who and ("Timeline for " .. W.CName(who, p and p.class) .. (focus.t and (C_DIM .. "  - focused on " .. FmtTime(focus.t) .. "|r") or ""))
			or ("Everyone" .. (focus.t and (C_DIM .. "  - focused on " .. FmtTime(focus.t) .. "|r") or ""))
		tinsert(rows, row("|cffffd100" .. title .. "|r", "|cffffd100" .. (who and "show everyone  >" or "show everything, unfocused  >") .. "|r",
			{ head = true, click = function()
				if UI.tl and UI.tl.who then UI.tl.who = nil; UI.tl.scroll = true else UI.tl = nil end
				UI:Refresh()
			  end }))
	end
	colHead(rows, TL_SPEC, { "Time", "Event" })
	local best, bestGap
	for i = 1, getn(tl) do
		local l = tl[i]
		if not who or mentions(l.x, who) then
			local line, t = l.x or "", l.t
			tinsert(rows, cells(TL_SPEC, { C_DIM .. FmtTime(l.t) .. "|r", tint(colorNames(line, rec), KIND_COLOR[l.k] or "|cffffffff") },
				{ tipTitle = FmtTime(l.t), tip = { line, " ", "|cff33ff33Click a name: that player's full timeline, at " .. FmtTime(l.t) .. "|r" },
				  click = function(d, btn, x)
					-- the text column starts after the time column (4 + 40 + 6)
					local name = nameAt(line, rec, x and (x - 50))
					if name then UI:ShowTimeline(name, t) end
				  end }))
			if focus and focus.t then
				local gap = math.abs((l.t or 0) - focus.t)
				if not bestGap or gap < bestGap then best, bestGap = getn(rows), gap end
			end
		end
	end
	if who and best == nil and getn(rows) <= 2 then
		tinsert(rows, row(C_DIM .. "Nothing on the timeline mentions " .. who .. ". Click \"show everyone\" above.|r"))
	end
	-- the moment you came for: highlighted, and scrolled into view once
	if best then
		rows[best].sel = true
		if focus.scroll then UI.tlScrollTo = best end
		focus.scroll = nil
	end
	return rows
end

------------------------------------------------------------------ refresh

------------------------------------------------------------------ Rankings view

local lastModeKey
local FAC_COL = { Alliance = "|cff3399ff", Horde = "|cffff4444", Mixed = "|cffcc77ff" }
local FAC_TAG = { Alliance = "A", Horde = "H", Mixed = "M" }

local function facTag(fac)
	return (FAC_COL[fac] or "|cffaaaaaa") .. (FAC_TAG[fac] or "?") .. "|r"
end
local function rkRealm() return UI.rk.realm or W.Board.Realm() end
local function rkFaction() return UI.rk.faction or W.Board.Faction() end
local function instTitle(zone) return W.Data.instanceTitle[zone] or zone end

-- an instance's encounters: the clear list first, then optional ones
local function instBosses(zone)
	local list, have = {}, {}
	local need = W.Data.clears[zone] or {}
	for i = 1, getn(need) do
		tinsert(list, need[i])
		have[need[i]] = true
	end
	local extra = {}
	for enc, def in pairs(W.Data.encounters) do
		if def.zone == zone and not have[enc] then tinsert(extra, enc) end
	end
	-- bosses only Chronicle knows (Turtle's custom ones, Karazhan...)
	local chron = W.Board:ChronBosses(zone)
	for i = 1, getn(chron) do
		if not have[chron[i]] then tinsert(extra, chron[i]) end
	end
	table.sort(extra)
	for i = 1, getn(extra) do
		if not have[extra[i]] then
			tinsert(list, extra[i])
			have[extra[i]] = true
		end
	end
	return list
end

local RANK_COL = { "|cffffd100", "|cffd0d0d0", "|cffe08a3c" }   -- gold, silver, bronze
local FAC_BAR = { Alliance = { 0.2, 0.5, 1 }, Horde = { 0.9, 0.2, 0.2 }, Mixed = { 0.65, 0.35, 0.9 } }

local function rankTxt(i, suffix)
	return (RANK_COL[i] or "|cffaaaaaa") .. "#" .. i .. "|r" .. (suffix or "")
end

-- guild names in their faction's colour
local function facName(g, fac, mine)
	if mine then return "|cffffd100" .. g .. "|r" end
	return (FAC_COL[fac] or "|cffdddddd") .. g .. "|r"
end

local KILL_SPEC = { { 150, "LEFT" }, { 58, "RIGHT" }, { 58, "RIGHT" }, { 34, "RIGHT" }, { 62, "RIGHT" }, { 58, "RIGHT" }, { 104, "LEFT" } }
local LB_SPEC = { { 28, "RIGHT" }, { 14, "CENTER" }, { 176, "LEFT" }, { 86, "LEFT" }, { 50, "RIGHT" }, { 70, "RIGHT" }, { 104, "RIGHT" } }
local LB_SPEC_ALL = { { 28, "RIGHT" }, { 14, "CENTER" }, { 120, "LEFT" }, { 76, "LEFT" }, { 70, "LEFT" }, { 40, "RIGHT" }, { 70, "RIGHT" }, { 100, "RIGHT" } }

-- the ranked leaderboard for one boss or one instance's clears, every
-- time compared with your guild's ("1:38.6 faster" / "3:51.1 slower")
local function boardRows(rows, realm, faction, kind, key, myGuild)
	local B = W.Board
	local list = B:Board(realm, kind, key, faction)
	if getn(list) == 0 then
		tinsert(rows, row(C_DIM .. "No times yet. They show up when you or a WhoDidIt user on your realm gets one,|r"))
		tinsert(rows, row(C_DIM .. "or when tools\\WhoDidIt-Sync pulls them from Chronicle.|r"))
		return
	end
	local home = B.Realm()
	local mine = myGuild and B:GuildBest(home, kind, key, myGuild)
	local best = list[1][2].t
	local allRealms = (realm == B.ALL)
	local spec = allRealms and LB_SPEC_ALL or LB_SPEC
	if allRealms then
		colHead(rows, spec, { "#", "", "Guild", "Realm", "Date", "Raid", "Time", "vs your guild" })
	else
		colHead(rows, spec, { "#", "", "Guild", "Date", "Raid", "Time", "vs your guild" })
	end
	for i = 1, getn(list) do
		local g, rec, rlm = list[i][1], list[i][2], list[i][3]
		local isMine = (g == myGuild and rlm == home)
		local cmp = ""
		if isMine then
			cmp = "|cffffd100your guild|r"
		elseif mine then
			local d = rec.t - mine.t
			cmp = (d < 0) and ("|cffff5555" .. B.Fmt(-d) .. " faster|r") or ("|cff33ff33" .. B.Fmt(d) .. " slower|r")
		elseif i > 1 then
			cmp = C_DIM .. "+" .. B.Fmt(rec.t - best) .. "|r"
		end
		local vals = { rankTxt(i), facTag(rec.f), facName(g, rec.f, isMine) }
		if allRealms then tinsert(vals, C_DIM .. rlm .. "|r") end
		tinsert(vals, C_DIM .. B.Date(rec.d) .. "|r")
		tinsert(vals, (rec.n and rec.n > 0) and (C_DIM .. rec.n .. "|r") or "")
		tinsert(vals, C_TIME .. B.Fmt(rec.t) .. "|r")
		tinsert(vals, cmp)
		local c = FAC_BAR[rec.f] or { 0.5, 0.5, 0.5 }
		tinsert(rows, cells(spec, vals,
			{ sel = isMine, bar = best / rec.t, ba = 0.16, cr = c[1], cg = c[2], cb = c[3], tipTitle = g,
			  tip = rec.chron and {
			          "|cffffd100From Chronicle|r (chronicleclassic.com) - " .. B.Date(rec.d),
			          "Realm: " .. B.RealmLabel(rlm) .. "   Faction: " .. (rec.f or "?") .. ((rec.f == "Mixed") and " (cross-faction raid)" or ""),
			          "|cff33ff33Click: open this raid - every boss kill, wipes, and the Chronicle link|r",
			      } or {
			          "Recorded " .. B.Date(rec.d) .. (rec.by and (" by " .. rec.by) or "") .. "   Realm: " .. (rlm or "?"),
			          rec.net and "Shared by a WhoDidIt user (self-reported)" or "Recorded by your WhoDidIt",
			          "|cff888888Click: what's known about this time|r",
			      },
			  click = function()
				UI.rk.log = { slug = rec.slug, guild = g, realm = rlm, rec = rec, kind = kind, key = key }
				UI:Refresh()
			  end }))
	end
end

-- "your best" / "your guild" rows above a leaderboard
local PIN_SPEC = { { 180, "LEFT" }, { 70, "RIGHT" }, { 80, "LEFT" }, { 222, "LEFT" } }

local function pinRows(rows, realm, faction, kind, key, guild)
	local B = W.Board
	local mine = B:MyBest(kind, key)
	tinsert(rows, cells(PIN_SPEC, {
		C_YOU .. "Your best " .. ((kind == "kills") and "kill" or "clear") .. "|r",
		mine and (C_TIME .. B.Fmt(mine.t) .. "|r") or (C_DIM .. "-|r"),
		"",
		mine and (C_DIM .. B.Date(mine.d) .. ((mine.g and mine.g ~= "") and ("  with " .. mine.g) or "") .. "|r") or (C_DIM .. "none yet|r"),
	}, mine and mine.slug and {
		tipTitle = "Your best", tip = { "Click: open that raid" },
		click = function() UI.rk.log = { slug = mine.slug, guild = mine.g or "?", realm = B.Realm(), rec = mine, kind = kind, key = key }; UI:Refresh() end } or nil))
	if guild then
		local g = B:GuildBest(realm, kind, key, guild)
		local rank, of = B:Rank(realm, kind, key, guild, faction)
		local top = B:Board(realm, kind, key, faction)[1]
		local note = ""
		if g and top and top[2] ~= g then
			note = "|cffff7777" .. B.Fmt(g.t - top[2].t) .. " behind|r " .. facName(top[1], top[2].f)
		elseif g and rank == 1 then
			note = "|cffffd100fastest on the board|r"
		end
		tinsert(rows, cells(PIN_SPEC, {
			C_GUILD .. guild .. "|r",
			g and (C_TIME .. B.Fmt(g.t) .. "|r") or (C_DIM .. "-|r"),
			rank and (rankTxt(rank) .. C_DIM .. " of " .. of .. "|r") or (g and (C_DIM .. B.Realm() .. "|r") or ""),
			g and note or (C_DIM .. "no " .. ((kind == "kills") and "kill" or "clear") .. " yet|r"),
		}, g and {
			tipTitle = guild, tip = { "Click: open the raid this time came from" },
			click = function() UI.rk.log = { slug = g.slug, guild = guild, realm = B.Realm(), rec = g, kind = kind, key = key }; UI:Refresh() end } or nil))
	end
end

-- "Rival watch": who recently beat our times here (click one to taunt the raid with it)
local function rivalRows(rows, zone, kind, key)
	local B = W.Board
	if not B.Rivals then return end
	local list = B:Rivals(zone, kind, key)
	head(rows, "Rival watch  " .. C_DIM .. "(beat our time in the last 3 weeks - click one to post a taunt)|r")
	if getn(list) == 0 then
		tinsert(rows, row(C_DIM .. "Nobody has beaten our times here recently. New Chronicle times are checked every minute.|r"))
		return
	end
	for i = 1, getn(list) do
		local e = list[i]
		local who = facName(e.g, nil) .. ((e.realm ~= B.Realm()) and (C_DIM .. " of " .. B.RealmLabel(e.realm) .. "|r") or "")
		local what = (e.kind == "clears") and "the clear" or e.key
		tinsert(rows, row(who .. "  |cffdddddd" .. what .. "|r  " .. C_TIME .. B.Fmt(e.t) .. "|r  " .. C_DIM .. "vs our|r " .. C_GUILD .. B.Fmt(e.cur or e.ours) .. "|r",
			C_DIM .. B.Ago(e.d) .. "|r  |cffffd100taunt >|r",
			{ tipTitle = "Rival watch", tip = { B:RivalText(e), " ", "Click: post this with a taunt to " .. W.Shout:ChannelLabel() .. "." },
			  click = function() B:PostRivals(zone, { e }) end }))
	end
end

function UI:RankNavRows(realm)
	local B = W.Board
	local rows = {}
	local guild = B.MyGuild()
	local run = B:CurrentRun()
	local zones = B:Zones()
	local home = B.Realm()
	for i = 1, getn(zones) do
		local zone = zones[i]
		local me = B:MyBest("clears", zone)
		local g = guild and B:GuildBest(home, "clears", zone, guild)
		local top = B:Board(realm, "clears", zone, "All")[1]
		local rank, of
		if g then rank, of = B:Rank(realm, "clears", zone, guild, "All") end
		local right = ""
		if run and run.zone == zone then
			right = "|cff33ccffrun|r"
		elseif rank then
			right = rankTxt(rank, "|cff777777/" .. of .. "|r")
		end
		local nRivals = B.Rivals and getn(B:Rivals(zone)) or 0
		if nRivals > 0 then right = "|cffff5555! |r" .. right end
		local line2
		if g then
			line2 = "|cff33ff33" .. B.Fmt(g.t) .. "|r"
			if top and top[2] ~= g then line2 = line2 .. "  |cff888888#1 " .. B.Fmt(top[2].t) .. "|r" end
		elseif top then
			line2 = "|cff888888#1 " .. B.Fmt(top[2].t) .. "  " .. top[1] .. "|r"
		else
			line2 = "|cff555555no times yet|r"
		end
		tinsert(rows, row("|cffffffff" .. instTitle(zone) .. "|r\n" .. line2, right,
			{ sel = (UI.rk.inst == zone),
			  bar = (g and top) and (top[2].t / g.t) or nil, ba = 0.28, cr = 0.15, cg = 0.75, cb = 0.3,
			  tipTitle = instTitle(zone),
			  tip = {
			      "Your guild: " .. (g and (B.Fmt(g.t) .. (rank and ("  #" .. rank .. " of " .. of) or ("  (on " .. home .. ")"))) or "no clear yet"),
			      "You: " .. (me and B.Fmt(me.t) or "no clear yet"),
			      "#1: " .. (top and (B.Fmt(top[2].t) .. "  " .. top[1]) or "-"),
			      (nRivals > 0) and ("|cffff5555! " .. nRivals .. " recent time" .. (nRivals == 1 and "" or "s") .. " beat ours here - see Rival watch|r") or " ",
			      "|cff888888The green bar is how close your guild is to #1.|r",
			  },
			  click = function() UI.rk.inst = zone; UI.rk.boss = nil; UI.rk.log = nil; UI:Refresh() end }))
	end
	return rows
end

function UI:RankKillRows(realm, faction, zone)
	local B = W.Board
	local rows = {}
	local guild = B.MyGuild()
	local spec = KILL_SPEC
	colHead(rows, spec, { "Boss", "You", "Guild", "Rank", "Gap to #1", "#1", "Held by" })
	local bosses = instBosses(zone)
	for i = 1, getn(bosses) do
		local enc = bosses[i]
		local top = B:Board(realm, "kills", enc, faction)[1]
		local mine = B:MyBest("kills", enc)
		local g = guild and B:GuildBest(realm, "kills", enc, guild)
		local rank = g and B:Rank(realm, "kills", enc, guild, faction)
		local gap = ""
		if g and top and top[2] ~= g then
			gap = "|cffff7777+" .. B.Fmt(g.t - top[2].t) .. "|r"
		elseif g and rank == 1 then
			gap = "|cffffd100fastest|r"
		end
		local beaten = B.Rivals and B:Rivals(nil, "kills", enc)[1]
		tinsert(rows, cells(spec, {
				(beaten and "|cffff5555! |r" or "") .. "|cffffffff" .. enc .. "|r",
				mine and (C_YOU .. B.Fmt(mine.t) .. "|r") or (C_DIM .. "-|r"),
				g and (C_GUILD .. B.Fmt(g.t) .. "|r") or (C_DIM .. "-|r"),
				rank and rankTxt(rank) or "",
				gap,
				top and (C_TIME .. B.Fmt(top[2].t) .. "|r") or (C_DIM .. "-|r"),
				top and facName(top[1], top[2].f, top[1] == guild and top[3] == B.Realm()) or "",
			},
			{ click = function()
				-- Shift-click: straight to the #1's raid
				if IsShiftKeyDown() and top then
					UI.rk.log = { slug = top[2].slug, guild = top[1], realm = top[3], rec = top[2], kind = "kills", key = enc }
				else
					UI.rk.boss = enc
				end
				UI:Refresh()
			  end,
			  bar = (g and top) and (top[2].t / g.t) or nil, ba = 0.2, cr = 0.15, cg = 0.75, cb = 0.3,
			  tip = { "you = your best kill (WhoDidIt or Chronicle)",
			          "guild = your guild's best, its rank and how far behind #1 it is",
			          "#1 = the fastest guild (" .. realm .. ", " .. faction .. ")",
			          beaten and ("|cffff5555! " .. B:RivalText(beaten) .. "|r") or " ",
			          "|cff888888Click: the full leaderboard (click a guild there to open its raid)|r",
			          "|cff888888Shift-click: open the #1 guild's raid|r" },
			  tipTitle = enc }))
	end
	rivalRows(rows, zone)
	return rows
end

function UI:RankBossRows(realm, faction, enc)
	local B = W.Board
	local rows = {}
	local guild = B.MyGuild()
	tinsert(rows, row("|cffffd100<< Back to all bosses|r", nil, { head = true, click = function() UI.rk.boss = nil; UI.rk.log = nil; UI:Refresh() end }))
	head(rows, enc .. " on " .. realm .. "  |cff888888(" .. faction .. ")|r")
	pinRows(rows, realm, faction, "kills", enc, guild)
	head(rows, "Leaderboard")
	boardRows(rows, realm, faction, "kills", enc, guild)
	rivalRows(rows, nil, "kills", enc)
	return rows
end

function UI:RankClearRows(realm, faction, zone)
	local B = W.Board
	local rows = {}
	local guild = B.MyGuild()
	local need = W.Data.clears[zone] or {}
	head(rows, "Full clears of " .. instTitle(zone))
	pinRows(rows, realm, faction, "clears", zone, guild)
	local run = B:CurrentRun()
	if run and run.zone == zone then
		local done = 0
		for i = 1, getn(need) do if run.kills[need[i]] then done = done + 1 end end
		tinsert(rows, cells(PIN_SPEC, {
			"|cff33ccffRun in progress|r",
			C_TIME .. B.Fmt(time() - run.start) .. "|r",
			C_TIME .. done .. "|r" .. C_DIM .. " / " .. getn(need) .. "|r",
			C_DIM .. "bosses down so far|r",
		}))
	end
	head(rows, "Leaderboard")
	boardRows(rows, realm, faction, "clears", zone, guild)
	head(rows, "Counts as a full clear")
	local parts = {}
	for i = 1, getn(need) do
		local killed = run and run.zone == zone and run.kills[need[i]]
		tinsert(parts, (killed and "|cff33ff33" or "|cffaaaaaa") .. need[i] .. "|r")
	end
	local line = {}
	for i = 1, getn(parts) do
		tinsert(line, parts[i])
		if getn(line) == 4 or i == getn(parts) then
			tinsert(rows, row(table.concat(line, ", ")))
			line = {}
		end
	end
	rivalRows(rows, nil, "clears", zone)
	return rows
end

-- one guild's raid: every boss kill from its Chronicle log, against our times
local LOG_SPEC = { { 20, "RIGHT" }, { 168, "LEFT" }, { 64, "RIGHT" }, { 66, "RIGHT" }, { 40, "RIGHT" }, { 100, "RIGHT" }, { 70, "RIGHT" } }

local function clock(secs)
	if not secs then return "-" end
	secs = floor(secs)
	if secs >= 3600 then return string.format("%d:%02d:%02d", floor(secs / 3600), floor(math.mod(secs, 3600) / 60), math.mod(secs, 60)) end
	return string.format("%d:%02d", floor(secs / 60), math.mod(secs, 60))
end

function UI:RankLogRows()
	local B = W.Board
	local L = UI.rk.log
	local rec = L.rec or {}
	local rows = {}
	local back = UI.rk.boss and ("<< Back to the " .. UI.rk.boss .. " leaderboard") or "<< Back to the leaderboard"
	tinsert(rows, row("|cffffd100" .. back .. "|r", nil, { head = true, click = function() UI.rk.log = nil; UI:Refresh() end }))
	local log = B:Log(L.slug)
	local guild = B.MyGuild()
	local home = B.Realm()
	local mine = (L.guild == guild and L.realm == home)
	local zone = (log and log.zone) or B:KeyZone(L.kind, L.key) or UI.rk.inst

	head(rows, facName(L.guild, rec.f, mine) .. "  |cffffffff" .. instTitle(zone) .. "|r  " .. C_DIM .. B.Date(rec.d) .. "|r")
	tinsert(rows, row("Realm", "|cffcc99ff" .. B.RealmLabel(L.realm) .. "|r"))
	tinsert(rows, row("Faction  /  raid size", "|cffffffff" .. (rec.f or "?") .. "|r" .. C_DIM .. "  /  |r" .. C_TIME .. ((log and log.n) or rec.n or "?") .. "|r players"))
	local place, of = B:Place(L.realm, L.kind, L.key, rec.t or 0)
	tinsert(rows, row((L.kind == "clears") and "Full clear" or (L.key .. " kill"),
		C_TIME .. B.Fmt(rec.t) .. "|r  " .. rankTxt(place) .. C_DIM .. " of " .. of .. " on " .. L.realm .. "|r"))
	if L.slug then
		local url = B.LogURL(L.slug)
		tinsert(rows, row("Chronicle log  " .. C_DIM .. url .. "|r", "|cffffd100copy link  >|r",
			{ tipTitle = "Chronicle log", tip = { "Opens a box with the link selected: press Ctrl+C, then paste it in your browser." },
			  click = function() W:CopyLink("Chronicle log for " .. L.guild, url) end }))
	end

	if not log then
		head(rows, "Boss kills in this raid")
		if L.slug then
			tinsert(rows, row(C_DIM .. "This raid's boss list isn't downloaded yet. tools\\WhoDidIt-Sync fetches it on its next sync.|r"))
		else
			tinsert(rows, row(C_DIM .. (rec.net and ("Shared by a WhoDidIt user" .. (rec.by and (" (" .. rec.by .. ")") or "") .. " - there's no Chronicle log for it.")
				or "Recorded by your WhoDidIt - there's no Chronicle log for it.") .. "|r"))
		end
		return rows
	end

	local total, wipes = 0, 0
	for i = 1, getn(log.kills) do wipes = wipes + (log.kills[i].w or 0) end
	local last = log.kills[getn(log.kills)]
	head(rows, "Boss kills in this raid  " .. C_DIM .. "(" .. getn(log.kills) .. " kills" .. ((wipes > 0) and (", " .. wipes .. " wipes") or "")
		.. ((last and last.a) and (", " .. clock(last.a) .. " start to last kill") or "") .. " - click a boss for its leaderboard)|r")
	colHead(rows, LOG_SPEC, { "#", "Boss", "Kill", "Into raid", "Wipes", mine and "vs our best" or "vs our guild", "Rank" })
	for i = 1, getn(log.kills) do
		local k = log.kills[i]
		local ours = guild and B:GuildBest(home, "kills", k.n, guild)
		local cmp = C_DIM .. "-|r"
		if ours and k.s then
			local d = k.s - ours.t
			if math.abs(d) < 0.05 then cmp = "|cffffd100our best|r"
			elseif d < 0 then cmp = "|cffff7777" .. B.Fmt(-d) .. " faster|r"
			else cmp = C_GUILD .. B.Fmt(d) .. " slower|r" end
		end
		local kp, kof = B:Place(log.realm or L.realm, "kills", k.n, k.s or 0)
		local isKey = (L.kind == "kills" and k.n == L.key)
		local boss = k.n
		tinsert(rows, cells(LOG_SPEC,
			{ C_DIM .. i .. ".|r", (isKey and "|cffffd100" or "|cffffffff") .. k.n .. "|r", C_TIME .. B.Fmt(k.s) .. "|r",
			  k.a and (C_DIM .. clock(k.a) .. "|r") or (C_DIM .. "-|r"),
			  (k.w and k.w > 0) and ("|cffff7777" .. k.w .. "|r") or (C_DIM .. "-|r"),
			  cmp, rankTxt(kp) .. C_DIM .. "/" .. kof .. "|r" },
			{ sel = isKey, tipTitle = k.n,
			  tip = { "Killed in " .. B.Fmt(k.s) .. (k.a and (", " .. clock(k.a) .. " into the raid") or "")
			            .. ((k.w and k.w > 0) and (" after " .. k.w .. " wipe" .. (k.w == 1 and "" or "s")) or ""),
			          ours and ("Our guild's best: " .. B.Fmt(ours.t)) or "Our guild has no kill yet",
			          "That time would be #" .. kp .. " of " .. kof .. " on " .. (log.realm or L.realm),
			          "|cff888888Click: " .. k.n .. "'s leaderboard|r" },
			  click = function() UI.rk.log = nil; UI.rk.boss = boss; UI:Refresh() end }))
	end
	return rows
end

function UI:RefreshRankings()
	local B = W.Board
	local realm, faction = rkRealm(), rkFaction()
	if not UI.rk.inst then
		local z = GetRealZoneText()
		UI.rk.inst = W.Data.clears[z] and z or W.Data.clearOrder[1]
	end
	local zone = UI.rk.inst
	leftHead:SetText("Instances")
	leftCount:SetText(realm)
	fightList:SetData(UI:RankNavRows(realm), true)

	UI.rankButtons[3]:SetText("Realm: " .. realm)
	UI.rankButtons[4]:SetText("Faction: " .. faction)
	if UI.rk.view == "kills" then
		UI.rankButtons[1]:LockHighlight(); UI.rankButtons[2]:UnlockHighlight()
	else
		UI.rankButtons[2]:LockHighlight(); UI.rankButtons[1]:UnlockHighlight()
	end

	local guilds = {}
	local all = B:Board(realm, "clears", zone, "All")
	for i = 1, getn(all) do guilds[all[i][1]] = true end
	local bosses = instBosses(zone)
	for i = 1, getn(bosses) do
		all = B:Board(realm, "kills", bosses[i], "All")
		for j = 1, getn(all) do guilds[all[j][1]] = true end
	end
	local ng = 0
	for _ in pairs(guilds) do ng = ng + 1 end

	local c = B.chron
	local chron
	local st = B.SyncStatus and B:SyncStatus()
	if st and st.alive and st.state == "running" then
		chron = "|cff66ccffChronicle syncing (see the bar, bottom left)|r"
	elseif c and c.synced then
		local mins = floor((time() - c.synced) / 60)
		chron = "Chronicle " .. ((c.status ~= "ok") and ("|cffffd100" .. (c.status or "") .. "|r") or (mins < 2 and "just synced" or (mins .. " min ago")))
	else
		chron = "|cffff9933No raid times yet - update WhoDidIt|r"
	end
	UI:UpdateSync()
	rTitle:SetText(instTitle(zone) .. "  |cff888888" .. (UI.rk.view == "kills" and "kill times" or "full clears") .. "|r")
	rInfo:SetText("|cffaaaaaa" .. realm .. "   |   " .. faction .. "   |   " .. ng .. " guild(s)   |   " .. chron
		.. "   |   sharing " .. (WhoDidItDB.opts.shareBoard and "on" or "off") .. "|r")
	local guild = B.MyGuild()
	local verdict
	if guild then
		local g = B:GuildBest(realm, "clears", zone, guild)
		if g then
			local rank, of = B:Rank(realm, "clears", zone, guild, "All")
			local top = B:Board(realm, "clears", zone, "All")[1]
			verdict = "|cff33ff33" .. guild .. "|r best clear |cffffffff" .. B.Fmt(g.t) .. "|r  "
			if rank then
				verdict = verdict .. rankTxt(rank) .. " of " .. of .. ((realm == B.ALL) and " on all realms" or (" on " .. realm))
			else
				verdict = verdict .. "|cff888888(on " .. B.Realm() .. ")|r"
			end
			if top and top[2] ~= g then
				verdict = verdict .. "  |cffff7777" .. B.Fmt(g.t - top[2].t) .. " behind|r |cffffffff" .. top[1] .. "|r"
			end
		else
			verdict = "|cff33ff33" .. guild .. "|r has no full clear recorded here yet."
		end
	else
		verdict = "You're not in a guild - your own times still count as personal bests."
	end
	local pbc = B:MyBest("clears", zone)
	verdict = verdict .. "\n|cff66ccffYour best clear:|r " .. (pbc and B.Fmt(pbc.t) or "none yet")
	rVerdict:SetText(verdict)

	local rows
	if UI.rk.log then rows = UI:RankLogRows()
	elseif UI.rk.boss then rows = UI:RankBossRows(realm, faction, UI.rk.boss)
	elseif UI.rk.view == "kills" then rows = UI:RankKillRows(realm, faction, zone)
	else rows = UI:RankClearRows(realm, faction, zone) end

	hintText:SetText("Click a guild's time to open their raid.  Clears: first combat to the last boss.  |cffff5555!|r = beaten recently.")
	hintText:Show()
	local key = "rk" .. realm .. faction .. zone .. UI.rk.view .. tostring(UI.rk.boss) .. (UI.rk.log and (UI.rk.log.guild .. tostring(UI.rk.log.slug)) or "")
	mainList:SetData(rows, key == lastModeKey)
	lastModeKey = key
end

------------------------------------------------------------------ Logs view

local function onOff(v) return v and "|cff33ff33on|r" or "|cff888888off|r" end

function UI:LogNavRows()
	local rows = {}
	local hist = W.Logs.history
	if getn(hist) == 0 then
		tinsert(rows, row("|cff888888Nothing saved yet\nthis session.|r"))
	end
	for i = 1, math.min(12, getn(hist)) do
		local h = hist[i]
		tinsert(rows, row(h[3] .. "\n|cff888888" .. h[1] .. "|r", "|cffffffff" .. FmtNum(h[2]) .. "|r lines"))
	end
	return rows
end

function UI:LogRows()
	local L = W.Logs
	local rows = {}
	if not L:Available() then
		head(rows, "The Chronicle logger isn't installed yet")
		tinsert(rows, row("WhoDidIt has Chronicle's logger (|cffffd100ChronicleCompanion|r) built in - it writes the logs you upload to chronicleclassic.com."))
		tinsert(rows, row("It's downloaded from the official source by the helper: run |cffffd100tools\\WhoDidIt-Sync.cmd|r once,"))
		tinsert(rows, row("then " .. W.RESTART_HINT .. ". The helper keeps it up to date from then on."))
		if WDI_CHRON_VERSION then
			tinsert(rows, row("|cffff7777v" .. WDI_CHRON_VERSION .. " is downloaded but didn't load - " .. W.RESTART_HINT .. ".|r"))
		end
		return rows
	end
	local opts = WhoDidItDB.opts
	local file = L:File() or "?"
	local src = L:Source()
	head(rows, "Status")
	tinsert(rows, row("Chronicle logging", L:Enabled() and "|cff33ff33ON|r" or "|cffff5555OFF|r"))
	if src == "builtin" then
		tinsert(rows, row("Logger", "|cff33ff33built into WhoDidIt|r  |cffffffffv" .. (L:Version() or "?") .. "|r"
			.. (WDI_CHRON_DATE and ("  |cff888888" .. WDI_CHRON_DATE .. "|r") or ""),
			{ tipTitle = "Built-in Chronicle logger", tip = {
				"ChronicleCompanion by Emyrk, from github.com/Emyrk/ChronicleCompanion.",
				"tools\\WhoDidIt-Sync checks for a new version every hour and installs it when WoW is closed.",
				"Commit: " .. string.sub(WDI_CHRON_COMMIT or "?", 1, 7) } }))
	elseif WDI_CHRON_VERSION then
		tinsert(rows, row("Logger", "|cffffd100ChronicleCompanion addon|r  |cffffffffv" .. (L:Version() or "?") .. "|r  |cff888888built-in v" .. WDI_CHRON_VERSION .. " takes over after /reload|r"))
	else
		tinsert(rows, row("Logger", "|cffffd100ChronicleCompanion addon|r  |cffffffffv" .. (L:Version() or "?") .. "|r  |cff888888run tools\\WhoDidIt-Sync to build it in|r"))
	end
	tinsert(rows, row("Log file", "|cffffffffWoW folder\\CustomData\\" .. file .. "|r"))
	tinsert(rows, row("Lines logged but not saved yet", "|cffffffff" .. FmtNum(L:Unsaved()) .. "|r"))
	tinsert(rows, row("Saved by WhoDidIt this session",
		"|cffffffff" .. FmtNum(L.savedLines) .. "|r lines" .. (L.lastSave and ("  |cff888888last " .. L.lastSave .. "|r") or "")))
	tinsert(rows, row("File access (Nampower)", WriteCustomFile and "|cff33ff33ok|r" or "|cffff5555missing - logs can't be written|r"))

	head(rows, "Automatic logging  |cff888888(click to switch on / off)|r")
	local function toggle(label, value, fn, tip)
		tinsert(rows, row(label, onOff(value), { click = function() fn(); UI:Refresh() end, tip = { tip }, tipTitle = label }))
	end
	toggle("Start logging when I enter a raid", L:Setting("autoEnableInRaid"),
		function() L:ToggleSetting("autoEnableInRaid") end, "Chronicle setting.")
	toggle("Start logging when I enter a dungeon", L:Setting("autoEnableInDungeon"),
		function() L:ToggleSetting("autoEnableInDungeon") end, "Chronicle setting.")
	toggle("Save after every combat", L:Setting("autoCombatSave"),
		function() L:ToggleSetting("autoCombatSave") end, "Chronicle setting: writes the log to disk whenever you leave combat.")
	toggle("Start logging when a boss is pulled", opts.chronStartOnPull,
		function() opts.chronStartOnPull = not opts.chronStartOnPull end, "WhoDidIt: a safety net in case logging was off when the boss was pulled.")
	toggle("Save after every boss fight", opts.chronSaveOnFight,
		function() opts.chronSaveOnFight = not opts.chronSaveOnFight end, "WhoDidIt: writes the log to disk after every kill or wipe.")
	toggle("One log file per realm", L:Setting("includeRealmInFilename"),
		function() L:ToggleSetting("includeRealmInFilename") end, "Chronicle setting: adds the realm to the file name.")

	head(rows, "Uploading to Chronicle")
	tinsert(rows, row("1.  After the raid click |cffffd100Stop & save|r (or |cffffd100Save now|r)."))
	tinsert(rows, row("2.  Open |cffffd100chronicleclassic.com|r and click |cffffd100Upload|r."))
	tinsert(rows, row("3.  Choose |cffffffffWoW folder\\CustomData\\" .. file .. "|r."))
	tinsert(rows, row("4.  Before your next lockout, |cffffd100Archive log|r or |cffffd100Delete log|r so raids don't mix."))
	tinsert(rows, row("|cff888888Addons can't reach the internet, so the upload itself is done on the website.|r"))
	return rows
end

function UI:RefreshLogs()
	local L = W.Logs
	leftHead:SetText("Saved this session")
	leftCount:SetText("")
	fightList:SetData(UI:LogNavRows(), true)
	UI.logButtons[1]:SetText(L:Enabled() and "|cffff5555Stop & save|r" or "|cff33ff33Start logging|r")
	if L:Available() then
		rTitle:SetText("Logging  " .. (L:Enabled() and "|cff33ff33ON - logging|r" or "|cffff5555OFF|r"))
		rInfo:SetText("|cffaaaaaaCustomData\\" .. (L:File() or "?") .. "   |   " .. FmtNum(L:Unsaved()) .. " unsaved lines|r")
	else
		rTitle:SetText("Logging  |cffff5555Chronicle logger not found|r")
		rInfo:SetText("|cffaaaaaaRun tools\\WhoDidIt-Sync.cmd once to install the Chronicle logger|r")
	end
	rVerdict:SetText("Upload the log at |cffffd100chronicleclassic.com|r after your raid.\n|cff888888Addons can't reach the internet, so uploading happens on the website.|r")
	hintText:SetText("Click an option to switch it on or off.  Hover the buttons for details.")
	hintText:Show()
	local key = "logs"
	mainList:SetData(UI:LogRows(), key == lastModeKey)
	lastModeKey = key
end

------------------------------------------------------------------ Marks view

local PACK_SPEC = { { 176, "LEFT" }, { 118, "LEFT" }, { 40, "RIGHT" }, { 60, "RIGHT" }, { 124, "LEFT" } }
local MOB_SPEC  = { { 16, "LEFT" }, { 62, "LEFT" }, { 170, "LEFT" }, { 58, "RIGHT" }, { 70, "RIGHT" }, { 150, "LEFT" } }
local CUR_SPEC  = { { 120, "LEFT" }, { 440, "LEFT" } }
local SRC_TEXT  = {
	builtin = "|cff888888built in|r", yours = "|cff33ff33yours|r", edited = "|cffffd100yours (edited)|r",
	live = "|cff66ccffbuilt in, this pull|r", hidden = "|cff666666hidden|r",
}

-- distinct marks (skull first), mob count, mobs alive in range
local function packInfo(pack)
	local marks, have, total, near = {}, {}, 0, 0
	for g, m in pairs(pack.mobs) do
		total = total + 1
		if m > 0 and not have[m] then have[m] = true; tinsert(marks, m) end
		if UnitExists(g) and not UnitIsDead(g) then near = near + 1 end
	end
	table.sort(marks, function(a, b) return a > b end)
	return marks, total, near
end

function UI:ShowPack(zone, name)
	UI.mk.zone, UI.mk.pack = zone, name
	UI:SetMode("marks")
end

function UI:MarksChanged()
	if f:IsVisible() and UI.mode == "marks" then UI:Refresh() end
end

-- left column: the zone you're in, zones with your packs, then the rest
function UI:MarkNavRows()
	local M = W.Marks
	local here = GetRealZoneText()
	local mine = WhoDidItDB.marks.packs
	local list = { here }
	local zones = M:Zones()
	for pass = 1, 2 do
		for i = 1, getn(zones) do
			local z = zones[i]
			if z ~= here and ((pass == 1) == (mine[z] ~= nil)) then tinsert(list, z) end
		end
	end
	local rows = {}
	for i = 1, getn(list) do
		local z = list[i]
		local n, yours = getn(M:PackNames(z)), 0
		for _ in pairs(mine[z] or {}) do yours = yours + 1 end
		local zz = z
		tinsert(rows, row(
			"|cffffffff" .. z .. "|r" .. (z == here and "  |cff33ff33(here)|r" or "")
				.. "\n" .. C_DIM .. n .. " pack" .. (n == 1 and "" or "s") .. "|r" .. (yours > 0 and ("  " .. C_GUILD .. yours .. " yours|r") or ""),
			nil,
			{ sel = (z == UI.mk.zone), click = function() UI.mk.zone = zz; UI.mk.pack = nil; UI:Refresh() end }))
	end
	return rows
end

-- a zone: what's marked now (quick save), its packs, its smart marks
function UI:ZoneRows(zone)
	local M = W.Marks
	local rows = {}
	if zone == GetRealZoneText() then
		local cur = M:CurrentMarks()
		head(rows, "Marked right now")
		if getn(cur) == 0 then
			tinsert(rows, row(C_DIM .. "No mobs marked. Mark a pack in game (right-click a portrait > Raid Target Icon), then save it here.|r"))
		else
			local icons, parts = {}, {}
			for i = 1, getn(cur) do
				tinsert(icons, { 4 + (i - 1) * 15, cur[i][2] })
				tinsert(parts, cur[i][3])
			end
			tinsert(rows, cells(CUR_SPEC, { "", C_GUILD .. "Click to save these " .. getn(cur) .. " as a pack|r  " .. C_DIM .. table.concat(parts, ", ") .. "|r" },
				{ icons = icons, sel = true, click = function() M:QuickSave() end,
				  tipTitle = "Save as a pack", tip = { "Saves these mobs with their marks. You'll be asked for a name.", "Use an existing pack's name to update it." } }))
		end
	end

	local names = M:PackNames(zone)
	head(rows, "Packs in " .. zone .. "  " .. C_DIM .. "(click to open  -  Shift-click to mark it now)|r")
	if getn(names) == 0 then
		tinsert(rows, row(C_DIM .. "No packs here yet. Mark the mobs of a pack, then click Save marks as pack.|r"))
	else
		colHead(rows, PACK_SPEC, { "Pack", "Marks", "Mobs", "In range", "Source" })
	end
	for i = 1, getn(names) do
		local name = names[i]
		local pack, src = M:Pack(zone, name)
		local marks, total, near = packInfo(pack)
		local icons = {}
		for k = 1, math.min(8, getn(marks)) do tinsert(icons, { 186 + (k - 1) * 15, marks[k] }) end
		local isLast = (M.last[zone] == name)
		tinsert(rows, cells(PACK_SPEC,
			{ (isLast and "|cffffd100>|r " or "") .. "|cffffffff" .. name .. "|r",
			  (getn(marks) == 0) and (C_DIM .. "no marks|r") or "",
			  C_TIME .. total .. "|r",
			  near > 0 and (C_GUILD .. near .. " / " .. total .. "|r") or (C_DIM .. "-|r"),
			  SRC_TEXT[src] or "" },
			{ icons = icons, bar = (near > 0) and (near / total) or nil, cr = 0.2, cg = 0.8, cb = 0.2, ba = 0.14,
			  tipTitle = name, tip = { "Click: open the pack  -  see every mob and edit it", "Shift-click: mark it now",
			    (near > 0) and (near .. " of its " .. total .. " mobs are in range") or "None of its mobs are in range" },
			  click = function()
				if IsShiftKeyDown() then
					M:MarkPack(pack)
					M.last[zone] = name
				else
					UI.mk.pack = name
				end
				UI:Refresh()
			  end }))
	end

	if UI.mk.showHidden then
		head(rows, "Hidden built-in packs  " .. C_DIM .. "(click to bring one back)|r")
		local all, n = M:PackNames(zone, true), 0
		for i = 1, getn(all) do
			local name = all[i]
			if M:IsHidden(zone, name) then
				n = n + 1
				tinsert(rows, row(C_DIM .. name .. "|r", C_GUILD .. "restore|r", { click = function() M:Restore(zone, name); UI:Refresh() end }))
			end
		end
		if n == 0 then tinsert(rows, row(C_DIM .. "None hidden here.|r")) end
	end

	local rules = M:RulesFor(zone)
	local o = WhoDidItDB.marks.opts
	head(rows, "Smart marks  " .. C_DIM .. "(click to switch on / off)|r" .. ((o.smart and o.enabled) and "" or "  |cffff5555all off|r"))
	if getn(rules) == 0 then
		tinsert(rows, row(C_DIM .. "None in this zone. They run in Naxx, AQ, MC, BWL, ZG, Onyxia, Emerald Sanctum, Karazhan, Timbermaw, BRD, DM and UBRS.|r"))
	end
	for i = 1, getn(rules) do
		local r = rules[i]
		local key = r.key
		tinsert(rows, row("|cffffffff" .. r.label .. "|r  " .. C_DIM .. r.desc .. "|r", onOff(WhoDidItDB.marks.smart[key] ~= false),
			{ tipTitle = r.label, tip = { r.desc }, click = function() M:ToggleRule(key); UI:Refresh() end }))
	end

	head(rows, "Built-in packs")
	local info = M.dataInfo
	if info then
		tinsert(rows, row("From |cffffd100AutoMarker|r " .. (info.version or "?") .. "  " .. C_DIM .. "(by Weird Vibes, github.com/MarcelineVQ/AutoMarker)|r",
			C_TIME .. info.packs .. "|r packs, " .. C_TIME .. info.mobs .. "|r mobs  " .. C_DIM .. (info.date or "") .. "|r",
			{ tipTitle = "Built-in packs", tip = { "tools\\WhoDidIt-Sync downloads them and checks for new ones every hour.", "Your own packs are saved separately and never overwritten." } }))
	else
		tinsert(rows, row("|cffff7777Not installed.|r Double-click |cffffd100tools\\WhoDidIt-Sync.cmd|r (in the WhoDidIt folder) once, then " .. W.RESTART_HINT .. ".  " .. C_DIM .. "Your own packs work without them.|r"))
	end
	return rows
end

-- one pack: actions, then every mob with its mark
function UI:PackRows(zone, name)
	local M = W.Marks
	local rows = {}
	tinsert(rows, row("|cff66ccff<  Back to all packs in " .. zone .. "|r", nil, { click = function() UI.mk.pack = nil; UI:Refresh() end }))
	local pack, src = M:Pack(zone, name)
	if not pack then
		tinsert(rows, row(C_DIM .. "This pack doesn't exist any more.|r"))
		return rows
	end
	local here = (zone == GetRealZoneText())
	head(rows, name .. "   " .. (SRC_TEXT[src] or ""))
	local function action(label, hint, fn)
		tinsert(rows, row(label, C_DIM .. hint .. "|r", { click = function() fn(); UI:Refresh() end }))
	end
	action(C_GUILD .. "Mark this pack now|r", "every mob of it that's in range", function()
		M:MarkPack(pack)
		M.last[zone] = name
	end)
	action("|cffffd100Save my current marks into this pack|r", "adds the mobs you've marked, or updates their marks", function()
		if not here then W.Print("Go to " .. zone .. " first.") return end
		M:Save(zone, name, M:CurrentMarks())
	end)
	action("|cffffd100Add my target|r", "with the mark it has now (or none)", function()
		if not here then W.Print("Go to " .. zone .. " first.") return end
		M:AddTarget(zone, name)
	end)
	action("|cffffffffRename|r", "", function()
		M:Prompt("Rename pack |cffffd100" .. name .. "|r", name, function(new)
			if M:Rename(zone, name, new) then UI:ShowPack(zone, string.gsub(new, "^%s*(.-)%s*$", "%1")) end
		end)
	end)
	if src == "edited" then
		action("|cffff9933Restore the built-in version|r", "drops your changes to it", function() M:Restore(zone, name) end)
	elseif src == "builtin" or src == "live" then
		action("|cffff5555Hide this pack|r", "it's built in: bring it back with Hidden", function() M:Delete(zone, name); UI.mk.pack = nil end)
	else
		action("|cffff5555Delete this pack|r", "", function() M:Delete(zone, name); UI.mk.pack = nil end)
	end

	head(rows, "Mobs  " .. C_DIM .. "(click a mob to pick its mark, right-click to take it out)|r")
	colHead(rows, MOB_SPEC, { "", "Mark", "Mob", "NPC", "Status", "GUID" })
	local list = {}
	for g, m in pairs(pack.mobs) do tinsert(list, { g, m, M:MobName(pack, g) }) end
	-- a fixed order (by name), so rows never jump while you change marks
	table.sort(list, function(a, b)
		if a[3] ~= b[3] then return a[3] < b[3] end
		return a[1] < b[1]
	end)
	for i = 1, getn(list) do
		local g, m, who = list[i][1], list[i][2], list[i][3]
		local status
		if not UnitExists(g) then status = C_DIM .. "not here|r"
		elseif UnitIsDead(g) then status = "|cffaa6666dead|r"
		elseif m > 0 and GetRaidTargetIndex(g) == m then status = C_GUILD .. "marked|r"
		else status = "|cff66ccffin range|r" end
		local tip = { "Click: pick its mark from all eight (or none)", "Right-click: take it out of the pack" }
		if src == "builtin" or src == "live" then tinsert(tip, C_DIM .. "Changing a built-in pack saves your own copy of it.|r") end
		tinsert(rows, cells(MOB_SPEC,
			{ "", m > 0 and M.MarkText(m) or (C_DIM .. "none|r"), "|cffffffff" .. who .. "|r", C_DIM .. (M.NpcHex(g) or "") .. "|r", status, C_DIM .. g .. "|r" },
			{ icons = (m > 0) and { { 5, m } } or nil, tipTitle = who, tip = tip,
			  click = function(d, btn)
				if btn == "RightButton" then
					M:RemoveMob(zone, name, g)
					UI:Refresh()
				else
					M:PickMark(m, function(nm) M:SetMobMark(zone, name, g, nm); UI:Refresh() end,
						function() M:RemoveMob(zone, name, g); UI:Refresh() end, who)
				end
			  end }))
	end
	if getn(list) == 0 then tinsert(rows, row(C_DIM .. "No mobs in this pack.|r")) end
	return rows
end

local MODE_TEXT = {
	raid = "|cff33ff33Everyone sees your marks|r (you're lead / assist)",
	["local"] = "|cffff9933Only you see your marks|r - you aren't lead or assist",
	solo = "|cffaaaaaaSolo: your marks are only visible to you|r",
	nosuperwow = "|cffff5555SuperWoW isn't loaded - marking can't work|r",
}

function UI:RefreshMarks()
	local M = W.Marks
	local here = GetRealZoneText()
	UI.mk.zone = UI.mk.zone or here
	local zone = UI.mk.zone
	local o = WhoDidItDB.marks.opts

	leftHead:SetText("Zones")
	leftCount:SetText("")
	fightList:SetData(UI:MarkNavRows(), true)
	UI.markButtons[5]:SetText("Auto marking: " .. (o.enabled and "|cff33ff33on|r" or "|cffff5555off|r"))
	mouseBtn:SetText("Mouseover: " .. (o.mouseover and "|cff33ff33on|r" or "|cffff5555off|r"))
	smartBtn:SetText("Smart: " .. (o.smart and "|cff33ff33on|r" or "|cffff5555off|r"))
	hiddenBtn:SetText("Hidden: " .. (UI.mk.showHidden and "shown" or "off"))

	local names = M:PackNames(zone)
	local yours = 0
	for _ in pairs(WhoDidItDB.marks.packs[zone] or {}) do yours = yours + 1 end
	rTitle:SetText("Auto Marker  |cffffffff" .. zone .. "|r")
	rInfo:SetText((MODE_TEXT[M:MarkMode()] or "") .. "   |cff888888|   " .. getn(names) .. " packs" .. (yours > 0 and (", " .. yours .. " yours") or "") .. "|r")
	if M.standDown then
		rVerdict:SetText(M.dataInfo and "|cffff9933The separate AutoMarker addon is still loaded, so WhoDidIt is standing by.|r\n|cff888888It has been switched off - /reload and WhoDidIt takes over.|r"
			or "|cffff9933The separate AutoMarker addon is doing the marking|r (it has the raid packs).\n|cff888888WhoDidIt leaves it on, since its own raid packs aren't installed.|r")
	else
		rVerdict:SetText("|cffffd100Quick save:|r mark the mobs in game, click |cff33ff33Save marks as pack|r, type a name, Enter.\n"
			.. "|cffffd100Mark a pack:|r hold Shift + Ctrl over a mob, or click |cffffd100Mark target's pack|r.")
	end
	hintText:SetText(UI.mk.pack and "Click a mob to pick its mark  -  right-click to take it out" or "Click a pack to open it  -  Shift-click a pack to mark it now")
	hintText:Show()
	local rows = UI.mk.pack and UI:PackRows(zone, UI.mk.pack) or UI:ZoneRows(zone)
	local key = "marks|" .. zone .. "|" .. (UI.mk.pack or "")
	mainList:SetData(rows, key == lastModeKey)
	lastModeKey = key
end

------------------------------------------------------------------ Loot view

local SR_SPEC    = { { 120, "LEFT" }, { 110, "LEFT" }, { 254, "LEFT" }, { 60, "RIGHT" } }
local AWARD_SPEC = { { 24, "RIGHT" }, { 226, "LEFT" }, { 120, "LEFT" }, { 110, "LEFT" }, { 60, "RIGHT" } }
local CMD_SPEC   = { { 130, "LEFT" }, { 430, "LEFT" } }
local QUALITY_COL = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000" }
local ROLL_TEXT = { MainSpec = "main spec", OffSpec = "off spec", Transmog = "transmog", SoftRes = "soft-res",
	RR = "raid roll", RaidRoll = "raid roll", InstaRaidRoll = "raid roll" }

local function itemText(id)
	local name, _, quality = GetItemInfo(id or 0)
	if not name then return C_DIM .. "item " .. tostring(id) .. "|r" end
	return (QUALITY_COL[quality] or "|cffffffff") .. name .. "|r"
end

-- one step of the guide: a number, its lines (rows clip, so lines stay short), and optionally something to click
local function step(rows, n, lines, click, hint)
	local d = click and function() click(); UI:Refresh() end
	for i = 1, getn(lines) do
		local first = (i == 1)
		tinsert(rows, row((first and ("|cffffd100" .. n .. ".|r  ") or "      ") .. lines[i],
			(first and hint) and (C_GUILD .. hint .. "  >|r") or nil,
			d and { click = d, tipTitle = "Step " .. n, tip = { "Click to " .. hint .. "." } } or nil))
	end
end

function UI:LootGuideRows()
	local Lt = W.Loot
	local rows = {}
	head(rows, "Before the raid: soft-res")
	step(rows, 1, { "Make a soft-res sheet at |cffffd100raidres.fly.dev|r and share the link.",
		"Raiders pick the items they want." },
		function() W:CopyLink("Soft-res sheets", "https://raidres.fly.dev") end, "copy link")
	step(rows, 2, { "Lock the sheet, click |cffffd100RollFor export|r, then |cffffd100Copy RollFor data to clipboard|r." })
	step(rows, 3, { "Click |cff33ff33Import soft-res|r, paste with Ctrl+V, click |cffffd100Import!|r" },
		function() Lt:Key("softres_toggle") end, "open it")
	step(rows, 4, { "See who hasn't soft-reserved on the |cffffd100Soft-res|r page." },
		function() UI.lt.section = "softres" end, "show it")
	step(rows, 5, { "A name on the sheet doesn't match a character? Fix it here." },
		function() Lt:Run("SRO", "") end, "fix names")

	head(rows, "In the raid")
	step(rows, 6, { "Be raid leader. With |cffffd100Auto ML|r on, targeting a boss turns on master loot (you).",
		"With |cffffd100Auto group|r on, it goes back to group loot once the boss is looted empty." },
		function() UI.lt.section = "settings" end, "settings")
	step(rows, 7, { "Tell the raid how to roll: |cffffffff" .. Lt:HowToRoll() .. "|r" },
		function() Lt:Run("HTR", "") end, "post it")
	step(rows, 8, { "Want different numbers, e.g. transmog on |cffffffff/roll 69|r? Change them in Settings." },
		function() UI.lt.section = "settings" end, "settings")

	head(rows, "When loot drops")
	step(rows, 9, { "Loot the boss. RollFor's loot window lists every item and who reserved it." })
	step(rows, 10, { "Click an item, then |cffffd100Roll|r. Soft-reserved: only those players roll.",
		"Not reserved: everyone rolls, and main spec beats off spec." })
	step(rows, 11, { "Ties re-roll by themselves. When it's done, click |cffffd100Award|r next to",
		"the winner and confirm - the item goes straight to them." })
	step(rows, 12, { "Two of the same item? Both are rolled together; the top two rolls win." })
	step(rows, 13, { "Trash and greens: |cffffd100Raid roll|r gives the item to a random raider." })
	step(rows, 14, { "Gave it to the wrong person? Trade it on - RollFor updates its winners." })
	step(rows, 15, { "Everything given out is on the |cffffd100Loot given|r page." },
		function() UI.lt.section = "given" end, "show it")

	head(rows, "Commands  " .. C_DIM .. "(shift-click an item into chat after the command)|r")
	local cmds = {
		{ "/rf <item> [secs]", "roll an item (from the loot window or your bags)" },
		{ "/rf 2x<item>", "roll two of the same item - the top two rolls win" },
		{ "/arf <item>", "everyone may roll, even if it's soft-reserved" },
		{ "/rr  /irr <item>", "raid roll an item  /  instant raid roll" },
		{ "/fr  /cr", "finish the roll early  /  cancel it" },
		{ "/srs  /src  /sro", "reserved items  /  who hasn't reserved  /  fix names" },
		{ "/sr  /rfw  /rfo", "import window  /  winners window  /  RollFor options" },
		{ "/rf config", "every RollFor setting (/rf config help explains them)" },
	}
	for i = 1, getn(cmds) do tinsert(rows, cells(CMD_SPEC, { "|cffffd100" .. cmds[i][1] .. "|r", "|cffdddddd" .. cmds[i][2] .. "|r" })) end
	tinsert(rows, row(C_DIM .. "Keys for RollFor's windows: Esc > Key Bindings > RollFor.|r"))
	return rows
end

function UI:LootSoftResRows()
	local Lt = W.Loot
	local rows = {}
	local sr = Lt:SoftRes()
	if not sr then
		head(rows, "No soft-res sheet imported")
		tinsert(rows, row("Click |cff33ff33Import soft-res|r at the top and paste the data from raidres.fly.dev.",
			C_GUILD .. "open it  >|r", { click = function() Lt:Key("softres_toggle") end }))
		tinsert(rows, row(C_DIM .. "The How it works page explains each step.|r"))
		return rows
	end
	local roster = Lt:Roster()
	local inGroup = GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
	local reserved = {}
	head(rows, "Soft-res sheet " .. (sr.id and ("|cffffffff" .. sr.id .. "|r ") or "") .. C_DIM .. "(" .. table.concat(sr.instances, ", ") .. ")|r   "
		.. C_TIME .. getn(sr.players) .. "|r players, " .. C_TIME .. sr.items .. "|r items")
	colHead(rows, SR_SPEC, { "Player", "Spec", "Reserved", "In raid" })
	for i = 1, getn(sr.players) do
		local p = sr.players[i]
		local here = roster[string.lower(p.name)]
		reserved[string.lower(p.name)] = true
		local names, tip = {}, {}
		for j = 1, getn(p.items) do tinsert(names, itemText(p.items[j])) end
		tinsert(tip, " ")
		tinsert(tip, "Reserved by |cffffffff" .. p.name .. "|r" .. (p.role ~= "" and (" (" .. Lt.RoleText(p.role) .. ")") or ""))
		if getn(p.items) > 1 then tinsert(tip, "Also: " .. table.concat(names, ", ", 2)) end
		tinsert(rows, cells(SR_SPEC,
			{ here and W.CName(here.name, here.class) or ("|cffdddddd" .. p.name .. "|r"),
			  C_DIM .. Lt.RoleText(p.role) .. "|r",
			  table.concat(names, ", "),
			  here and (C_GUILD .. "yes|r") or (inGroup and "|cffff7777not here|r" or C_DIM .. "-|r") },
			{ tipTitle = p.name, tip = tip, link = Lt.ItemLink(p.items[1]) }))
	end
	if inGroup then
		local missing = {}
		for key, who in pairs(roster) do
			if not reserved[key] then tinsert(missing, W.CName(who.name, who.class)) end
		end
		table.sort(missing)
		head(rows, "In the raid without a soft-res  " .. C_DIM .. "(" .. getn(missing) .. ")|r")
		if getn(missing) == 0 then
			tinsert(rows, row(C_GUILD .. "Everyone has soft-reserved.|r"))
		else
			-- six names a row: rows clip rather than wrap
			for i = 1, getn(missing), 6 do
				local part = {}
				for j = i, math.min(i + 5, getn(missing)) do tinsert(part, missing[j]) end
				tinsert(rows, row(table.concat(part, ", ")))
			end
			tinsert(rows, row("|cffffd100Post the missing players and the sheet link to the raid|r", C_GUILD .. "post it  >|r",
				{ click = function() Lt:Run("SRC", "a") end, tipTitle = "Post to raid", tip = { "/src a" } }))
		end
	end
	tinsert(rows, row(C_DIM .. "Names that don't match a character: Fix SR names (/sro).|r"))
	tinsert(rows, row(C_DIM .. "Importing a new sheet replaces this one.|r"))
	return rows
end

function UI:LootGivenRows()
	local Lt = W.Loot
	local rows = {}
	local list = Lt:Awarded()
	head(rows, "Loot given  " .. C_DIM .. "(newest first, from RollFor - the Winners window has filters)|r")
	if getn(list) == 0 then
		tinsert(rows, row(C_DIM .. "Nothing awarded yet. Items you award with RollFor show up here.|r"))
		return rows
	end
	colHead(rows, AWARD_SPEC, { "#", "Item", "Winner", "How", "Roll" })
	for i = 1, getn(list) do
		local a = list[i]
		local name, _, quality = GetItemInfo(a.item_id or 0)
		local item = name and ((QUALITY_COL[quality or a.quality] or "|cffffffff") .. name .. "|r") or (a.item_link or itemText(a.item_id))
		tinsert(rows, cells(AWARD_SPEC,
			{ C_DIM .. i .. ".|r", item, W.CName(a.player_name or "?", a.player_class),
			  "|cffdddddd" .. (ROLL_TEXT[a.roll_type or ""] or ROLL_TEXT[a.rolling_strategy or ""] or (a.roll_type or "awarded")) .. "|r"
			    .. ((a.plus_one and (" " .. C_GUILD .. "+1|r")) or ""),
			  a.winning_roll and (C_TIME .. a.winning_roll .. "|r") or (C_DIM .. "-|r") },
			{ link = Lt.ItemLink(a.item_link) or Lt.ItemLink(a.item_id), tip = { " ", "Given to |cffffffff" .. (a.player_name or "?") .. "|r" } }))
	end
	return rows
end

function UI:LootSettingsRows()
	local Lt = W.Loot
	local rows = {}
	local function add(label, value, summary, tipTitle, tip, click)
		local extra = { tipTitle = tipTitle, tip = tip, click = function() click(); UI:Refresh() end }
		tinsert(rows, row("|cffffffff" .. label .. "|r", value, extra))
		if summary then
			tinsert(rows, row("      " .. C_DIM .. summary .. "|r", nil, { tipTitle = tipTitle, tip = tip, click = extra.click }))
		end
	end

	-- the numbers raiders type
	head(rows, "Roll numbers  " .. C_DIM .. "(click one to change it)|r")
	for i = 1, getn(Lt.ROLLS) do
		local r = Lt.ROLLS[i]
		local n = Lt:RollNumber(r)
		local off = (r.cmd == "tmog" and not Lt:TmogOn())
		add(r.label .. " roll", off and (C_DIM .. "off|r") or ("|cffffd100" .. Lt.RollCommand(n) .. "|r"),
			"Raiders type " .. Lt.RollCommand(n) .. " (1 to " .. n .. ")" .. (n ~= r.default and ("  -  normally " .. Lt.RollCommand(r.default)) or ""),
			r.label .. " roll", { "The number raiders roll to " .. string.lower(r.label) .. ": they type " .. Lt.RollCommand(n) .. ".",
				"Click to change it, e.g. transmog on /roll 69.", "Each roll type needs its own number.",
				C_DIM .. "/rf config " .. r.cmd .. " <number>|r" },
			function() Lt:AskRollNumber(r) end)
	end
	add("Transmog rolls", onOff(Lt:TmogOn()), "Let raiders roll for transmog as well as main and off spec.",
		"Transmog rolls", { "On: raiders can roll for an item's look (lowest priority).", "Off: only main spec and off spec rolls.",
			C_DIM .. "/rf config tmog|r" }, function() Lt:ToggleTmog() end)
	add("Roll time", "|cffffd100" .. Lt:RollTime() .. " sec|r", "How long raiders get to roll (4 to 15 seconds).",
		"Roll time", { "How long each roll stays open. You can always end it early with Finish roll.",
			C_DIM .. "/rf config default-rolling-time <seconds>|r" }, function() Lt:AskRollTime() end)
	tinsert(rows, row(C_DIM .. "Raiders see: " .. Lt:HowToRoll() .. "|r", "|cffffd100reset to 100 / 99 / 98  >|r",
		{ tipTitle = "Reset roll numbers", tip = { "Back to /roll for main spec, /roll 99 off spec, /roll 98 transmog." },
		  click = function() Lt:ResetRollNumbers(); UI:Refresh() end }))

	-- on / off settings, in groups
	for g = 1, getn(Lt.SETTINGS) do
		local group = Lt.SETTINGS[g]
		head(rows, group.title .. "  " .. C_DIM .. "(click to switch on / off)|r")
		for i = 1, getn(group.intro or {}) do tinsert(rows, row("|cffdddddd" .. group.intro[i] .. "|r")) end
		for i = 1, getn(group.items) do
			local s = group.items[i]
			local cmd = s[2]
			local tip = {}
			for j = 1, getn(s[5]) do tinsert(tip, s[5][j]) end
			tinsert(tip, C_DIM .. "/rf config " .. cmd .. "|r")
			add(s[3], onOff(Lt:Setting(s[1])), s[4], s[3], tip, function() Lt:Toggle(cmd) end)
		end
	end

	head(rows, "For your raiders")
	local ptip = { "When you start a roll, raiders with RollFor (or WhoDidIt) get a window to roll from.",
		"Off - nobody gets it", "Eligible - only players who may roll on the item", "Always - everyone", C_DIM .. "Click to change.|r" }
	add("Roll window for raiders", "|cffffd100" .. Lt:RollPopup() .. "|r", "Raiders with RollFor or WhoDidIt get a window to roll from.",
		"Roll window for raiders", ptip, function() Lt:CycleRollPopup() end)
	add("Who has RollFor?", "|cffffd100check  >|r", "Ask the raid who has RollFor or WhoDidIt, and which version.",
		"Who has RollFor", { "Lists everyone in the raid with RollFor (or WhoDidIt) and their version, in chat." },
		function() Lt:Run("RF", "versioncheck") end)

	head(rows, "More")
	add("RollFor's own options window", "|cffffd100open  >|r", "Every RollFor setting, including quick award keys and winners filters.",
		"RollFor options", { "RollFor's own options window (/rfo). Hover each option there for what it does." },
		function() Lt:Key("options_toggle") end)
	add("Every setting in chat", "|cffffd100print  >|r", nil, "Print settings", { "Prints all of RollFor's settings in chat (/rf config)." },
		function() Lt:Run("RF", "config") end)
	return rows
end

local LOOT_SECTIONS = {
	{ "guide",    "How it works",  "Start here: step by step" },
	{ "softres",  "Soft-res",      nil },
	{ "given",    "Loot given",    nil },
	{ "settings", "Settings",      "Roll numbers and every option" },
}

function UI:LootNavRows()
	local Lt = W.Loot
	local rows = {}
	local sr = Lt:SoftRes()
	local given = getn(Lt:Awarded())
	for i = 1, getn(LOOT_SECTIONS) do
		local s = LOOT_SECTIONS[i]
		local sub = s[3]
		if s[1] == "softres" then
			sub = sr and (getn(sr.players) .. " players, " .. sr.items .. " items") or "nothing imported yet"
		elseif s[1] == "given" then
			sub = given .. " item" .. (given == 1 and "" or "s") .. " awarded"
		end
		local id = s[1]
		tinsert(rows, row("|cffffffff" .. s[2] .. "|r\n" .. C_DIM .. sub .. "|r", nil,
			{ sel = (UI.lt.section == id), click = function() UI.lt.section = id; UI:Refresh() end }))
	end
	return rows
end

local METHOD_TEXT = { freeforall = "Free for all", roundrobin = "Round robin", group = "Group loot", needbeforegreed = "Need before greed" }

function UI:RefreshLoot()
	local Lt = W.Loot
	leftHead:SetText("SR MasterLoot")
	leftCount:SetText("")
	fightList:SetData(UI:LootNavRows(), true)
	mlBtn:SetText("Auto ML: " .. (Lt:Setting("auto_master_loot") ~= false and "|cff33ff33on|r" or "|cffff5555off|r"))
	glBtn:SetText("Auto group: " .. (Lt:Setting("auto_group_loot") and "|cff33ff33on|r" or "|cffff5555off|r"))

	local src = Lt:Source()
	if not src then
		rTitle:SetText("SR MasterLoot  |cffff5555RollFor isn't installed yet|r")
		rInfo:SetText("|cffaaaaaaRun tools\\WhoDidIt-Sync.cmd once, then " .. W.RESTART_HINT .. "|r")
		rVerdict:SetText("RollFor is built in - the helper downloads it from its official source.\n"
			.. (WDI_ROLLFOR_VERSION and ("|cffff7777v" .. WDI_ROLLFOR_VERSION .. " is downloaded: " .. W.RESTART_HINT .. ".|r") or "|cff888888The guide below works without it.|r"))
	else
		rTitle:SetText("SR MasterLoot  |cffffffffRollFor v" .. (Lt:Version() or "?") .. "|r  "
			.. (src == "builtin" and "|cff33ff33built in|r" or "|cffffd100separate addon|r"))
		local inGroup = GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
		local method, looter = Lt:LootMethod()
		local me = UnitName("player")
		local info
		if not inGroup then
			info = "|cffaaaaaaNot in a group|r"
		elseif method == "master" then
			info = "Master loot: " .. ((looter == me) and "|cff33ff33you|r" or ("|cffffffff" .. (looter or "?") .. "|r"))
		else
			info = "|cffff9933" .. (METHOD_TEXT[method or ""] or (method or "?")) .. "|r - not master loot"
		end
		local sr = Lt:SoftRes()
		info = info .. "   |cff888888|   soft-res: " .. (sr and (getn(sr.players) .. " players") or "none") .. "|r"
		rInfo:SetText(info)
		local nextStep
		if WDI_ROLLFOR_SKIP then
			nextStep = "|cffff9933The separate RollFor is still running - /reload and WhoDidIt takes over.|r"
		elseif not sr then
			nextStep = "|cffffd100Next:|r import the soft-res sheet - click |cff33ff33Import soft-res|r."
		elseif not inGroup then
			nextStep = "|cffffd100Next:|r form the raid - the soft-res sheet is ready."
		elseif method ~= "master" then
			nextStep = Lt:IsLeader() and "|cffffd100Next:|r target a boss - Auto master loot turns master loot on."
				or "|cffffd100Next:|r ask the raid leader for master loot, with you as looter."
		elseif looter ~= me then
			nextStep = "|cffaaaaaa" .. (looter or "Someone") .. " is master looter - you roll from the roll window.|r"
		else
			nextStep = "|cff33ff33Ready.|r Loot a boss - RollFor's loot window does the rest."
		end
		rVerdict:SetText(nextStep .. "\n|cff888888Raiders roll: " .. Lt:HowToRoll() .. ".|r")
	end
	hintText:SetText("Hover anything to see what it does  -  click gold lines and values to use or change them")
	hintText:Show()

	local s = UI.lt.section
	local rows
	if s == "softres" then rows = UI:LootSoftResRows()
	elseif s == "given" then rows = UI:LootGivenRows()
	elseif s == "settings" then rows = UI:LootSettingsRows()
	else rows = UI:LootGuideRows() end
	local key = "loot|" .. s
	mainList:SetData(rows, key == lastModeKey)
	lastModeKey = key
end

-- Board.lua / Logs.lua didn't load (the game wasn't restarted after an update)
function UI:RefreshMissing()
	for i = 1, getn(UI.rankButtons) do UI.rankButtons[i]:Hide() end
	for i = 1, getn(UI.logButtons) do UI.logButtons[i]:Hide() end
	for i = 1, getn(UI.markButtons) do UI.markButtons[i]:Hide() end
	for i = 1, getn(markOnly) do markOnly[i]:Hide() end
	srCopy:Hide()
	srSite:Hide()
	for i = 1, getn(UI.lootButtons) do UI.lootButtons[i]:Hide() end
	for i = 1, getn(lootOnly) do lootOnly[i]:Hide() end
	local titles = { logs = "Logging", marks = "Auto Marker", loot = "SR MasterLoot", fame = "Hall of Fame" }
	leftHead:SetText(titles[UI.mode] or "Rankings")
	leftCount:SetText("")
	fightList:SetData({})
	rTitle:SetText("Restart WoW to finish updating")
	rInfo:SetText("|cffaaaaaaNew WhoDidIt files aren't loaded yet|r")
	rVerdict:SetText(W.CAPI and "|cffff7777Type /reload to load the new files.|r\n|cff888888ClassicAPI is installed, so a /reload picks up new addon files.|r"
		or "|cffff7777Exit the game completely and start it again.|r\n|cff888888A /reload isn't enough: WoW only picks up new addon files at start-up.|r")
	hintText:SetText("")
	local rows = {}
	head(rows, "Why")
	tinsert(rows, row("This update added new parts of WhoDidIt (Rankings, Chronicle logs, auto marking, master looting)."))
	tinsert(rows, row("WoW reads each addon's file list once, when the game starts - /reload only re-runs files it already knows."))
	tinsert(rows, row("Fights still work normally until then: click |cffffd100Fights|r in the title bar."))
	lastModeKey = nil
	mainList:SetData(rows)
end

------------------------------------------------------------------ Hall of Fame

-- # / player / points / plays or mistakes / fights / mostly / MVP or worst / last seen
local FAME_SPEC = { { 22, "RIGHT" }, { 112, "LEFT" }, { 58, "RIGHT" }, { 50, "RIGHT" }, { 44, "RIGHT" }, { 140, "LEFT" }, { 52, "RIGHT" }, { 70, "RIGHT" } }
-- # / points / player / what / boss and date
local MOMENT_SPEC = { { 22, "RIGHT" }, { 40, "RIGHT" }, { 96, "LEFT" }, { 300, "LEFT" }, { 120, "LEFT" } }

-- "Heal x12 (31 pts)" lines for a tooltip, biggest first
local function kindLines(t, colour)
	local list = {}
	for k, v in pairs(t or {}) do tinsert(list, { k, v[1], v[2] }) end
	table.sort(list, function(a, b) return a[3] > b[3] end)
	local out = {}
	for i = 1, getn(list) do
		tinsert(out, { colour .. list[i][1] .. "|r", list[i][2] .. "x   " .. list[i][3] .. " pts" })
	end
	return out
end

-- a moment without its player's name in front ("healed X..." not "Bob healed X...")
local function momentText(m)
	return (string.gsub(m.text or "", "^" .. (m.who or "") .. " ", ""))
end

local function momentRows(rows, list, blunder, who)
	local C = W.Career
	local shown = 0
	colHead(rows, MOMENT_SPEC, { "#", "Pts", "Player", blunder and "Blunder" or "Play", "Boss / date" })
	for i = 1, getn(list) do
		local m = list[i]
		if not who or m.who == who then
			shown = shown + 1
			local col = blunder and "|cffff7777" or "|cff33ff33"
			tinsert(rows, cells(MOMENT_SPEC,
				{ C_DIM .. shown .. ".|r", col .. (blunder and "-" or "+") .. m.pts .. "|r", W.CName(m.who or "?", m.class) .. (m.test and " |cff33ccff(test)|r" or ""),
				  momentText(m), "|cffffd100" .. (m.enc or "?") .. "|r " .. C_DIM .. (m.when or "") .. "|r" },
				{ tipTitle = (blunder and "Blunder" or "Play") .. ": " .. (m.kind or ""), tip = { m.text or "", " ",
					(m.enc or "?") .. ", " .. (m.when or "?"), "|cffffd100Click|r  post it   |cffffd100Ctrl-click|r  only you see it",
					"|cffffd100Right-click|r  " .. (m.who or "their") .. "'s record" },
				  click = function(d, button)
					if button == "RightButton" then UI.fame.who = m.who; UI:Refresh() return end
					C:Post({ C:MomentLine(m, nil, blunder) }, IsControlKeyDown() and "SELF" or nil)
				  end }))
			if who and shown >= 5 then break end
		end
	end
	if shown == 0 then tinsert(rows, row(C_DIM .. "Nothing yet.|r")) end
end

function UI:FameBoardRows(kind)
	local C = W.Career
	local d = C.View()
	local rows = {}
	local hero = (kind == "hero")
	local list = C:Board(kind, UI.fame.per)
	head(rows, (hero and "Hall of Fame - the biggest heroes" or "Hall of Shame - the biggest liabilities") .. (UI.fame.per and "  (points per fight, 3+ fights)" or ""))
	if getn(list) == 0 then
		tinsert(rows, row(C_DIM .. ((d.fights + d.testFights) == 0 and "Nothing counted yet. Every fight you save adds to it (demo fights too, marked test)."
			or "Nobody has " .. (hero and "hero" or "blame") .. " points yet" .. (UI.fame.per and " with 3 or more fights" or "") .. ".") .. "|r"))
		return rows
	end
	colHead(rows, FAME_SPEC, { "#", "Player", "Points", hero and "Plays" or "Errors", "Fights", "Mostly", hero and "MVP" or "Worst", "Last seen" })
	local max = list[1].v > 0 and list[1].v or 1
	local pc = hero and C_GUILD or "|cffff7777"
	for i = 1, getn(list) do
		local it, p = list[i], list[i].p
		local r, g, b = W.ClassRGB(p.class)
		local top = C.TopKind(hero and p.hk or p.mk)
		local tip = {
			{ "Fights", p.fights .. "  (" .. p.kills .. " kills, " .. p.deaths .. " deaths)" },
			{ "Hero", p.hero .. " pts from " .. p.saves .. " plays" .. ((p.mvp > 0) and (", MVP " .. p.mvp .. "x") or "") },
			{ "Shame", p.blame .. " pts from " .. p.mistakes .. " mistakes" .. ((p.worst > 0) and (", most to blame " .. p.worst .. "x") or "") },
			" ",
			"|cffffd100" .. (hero and "Plays" or "Mistakes") .. " by kind|r",
		}
		local kl = kindLines(hero and p.hk or p.mk, hero and "|cff33ff33" or "|cffff7777")
		for j = 1, getn(kl) do tinsert(tip, kl[j]) end
		tinsert(tip, " ")
		tinsert(tip, "|cffffd100Click|r  post their record   |cffffd100Ctrl-click|r  only you see it")
		tinsert(tip, "|cffffd100Right-click|r  open their record")
		local name = it.name
		tinsert(rows, cells(FAME_SPEC,
			{ C_DIM .. i .. ".|r", W.CName(name, p.class) .. (p.test and " |cff33ccff(test)|r" or ""), pc .. it.v .. "|r",
			  C_TIME .. (hero and p.saves or p.mistakes) .. "|r", C_DIM .. p.fights .. "|r",
			  top and ("|cffcccccc" .. top .. "|r") or (C_DIM .. "-|r"),
			  ((hero and p.mvp or p.worst) > 0) and (C_YOU .. (hero and p.mvp or p.worst) .. "x|r") or (C_DIM .. "-|r"),
			  C_DIM .. (p.last or "") .. "|r" },
			{ bar = it.v / max, cr = r, cg = g, cb = b, ba = 0.3, tip = tip, tipTitle = name .. (p.test and " (test - from a demo fight)" or "") .. " - Hall of Fame", name = name,
			  click = function(dd, button)
				if button == "RightButton" then UI.fame.who = name; UI:Refresh() return end
				C:Post(C:PlayerLines(name), IsControlKeyDown() and "SELF" or nil)
			  end }))
	end
	return rows
end

function UI:FamePlayerRows(name)
	local C = W.Career
	local d = C.View()
	local p = d.players[name]
	local rows = {}
	tinsert(rows, row("|cffffd100< Back to the board|r", nil, { click = function() UI.fame.who = nil; UI:Refresh() end }))
	if not p then
		tinsert(rows, row(C_DIM .. name .. " has no all-time record yet.|r"))
		return rows
	end
	local function per(v) return floor(v / math.max(1, p.fights) * 10 + 0.5) / 10 end
	head(rows, W.CName(name, p.class) .. (p.test and " |cff33ccff(test)|r" or "") .. "|cffffd100's record  -  " .. p.fights .. " fights, " .. p.kills .. " kills, " .. p.deaths .. " deaths|r")
	tinsert(rows, row(C_GUILD .. "Hero|r   " .. p.hero .. " pts from " .. p.saves .. " plays" .. ((p.mvp > 0) and ("   - MVP of " .. p.mvp .. " fights") or ""),
		C_DIM .. per(p.hero) .. " a fight|r", { tipTitle = "Hero", tip = { "Points for game-saving plays: clutch heals, shields, taunts,", "battle res, dispels, interrupts, surviving..." } }))
	tinsert(rows, row("|cffff7777Shame|r   " .. p.blame .. " pts from " .. p.mistakes .. " mistakes" .. ((p.worst > 0) and ("   - most to blame in " .. p.worst .. " fights") or ""),
		C_DIM .. per(p.blame) .. " a fight|r", { tipTitle = "Shame", tip = { "Points for mistakes: standing in fire, pulling aggro,", "bombing the raid, idling, low DPS..." } }))
	tinsert(rows, row("|cffffd100Click here to post this record|r " .. C_DIM .. "(Ctrl-click: only you see it)|r", nil,
		{ click = function() C:Post(C:PlayerLines(name), IsControlKeyDown() and "SELF" or nil) end }))
	head(rows, "Plays by kind")
	local hk = kindLines(p.hk, "|cff33ff33")
	if getn(hk) == 0 then tinsert(rows, row(C_DIM .. "None yet.|r")) end
	for i = 1, getn(hk) do tinsert(rows, row(hk[i][1], hk[i][2])) end
	head(rows, "Mistakes by kind")
	local mk = kindLines(p.mk, "|cffff7777")
	if getn(mk) == 0 then tinsert(rows, row(C_DIM .. "None yet.|r")) end
	for i = 1, getn(mk) do tinsert(rows, row(mk[i][1], mk[i][2])) end
	head(rows, "Their best plays")
	momentRows(rows, d.moments, false, name)
	head(rows, "Their worst blunders")
	momentRows(rows, d.blunders, true, name)
	return rows
end

function UI:RefreshFame()
	local C = W.Career
	local d = C.View()
	local v = UI.fame.view
	-- left: everyone in the tally, click for their record
	local names = {}
	for name in pairs(d.players) do tinsert(names, name) end
	table.sort(names)
	leftHead:SetText("Raiders")
	leftCount:SetText(getn(names) .. "")
	local left = {}
	for i = 1, getn(names) do
		local name, p = names[i], d.players[names[i]]
		tinsert(left, { l = W.CName(name, p.class) .. (p.test and " |cff33ccff(test)|r" or ""), r = C_GUILD .. p.hero .. "|r " .. C_DIM .. "/|r |cffff7777" .. p.blame .. "|r",
			sel = (UI.fame.who == name), tipTitle = name, tip = { "Hero " .. p.hero .. " pts  /  Shame " .. p.blame .. " pts", "Click: open their record" },
			click = function() UI.fame.who = name; UI:Refresh() end })
	end
	if getn(left) == 0 then left = { { l = C_DIM .. "Nobody yet|r" } } end
	fightList:SetData(left, true)

	for i = 1, getn(UI.fameButtons) do
		local b = UI.fameButtons[i]
		local on = (not UI.fame.who) and ((i == 1 and v == "hero") or (i == 2 and v == "blame") or (i == 3 and v == "plays") or (i == 4 and v == "blunders"))
		if on then b:LockHighlight() else b:UnlockHighlight() end
	end
	famePerBtn:SetText("Per fight: " .. (UI.fame.per and "|cff33ff33on|r" or "off"))
	fameTestBtn:SetText(C.HasTest() and "|cff33ccffClear test data|r" or "|cff777777No test data|r")

	local titles = { hero = "|cff33ff33Heroes|r", blame = "|cffff5555Hall of Shame|r", plays = "Best plays", blunders = "Worst blunders" }
	rTitle:SetText("Hall of Fame  " .. (UI.fame.who and W.CName(UI.fame.who, d.players[UI.fame.who] and d.players[UI.fame.who].class) or titles[v]))
	rInfo:SetText("|cffaaaaaaSince " .. d.since .. "   |   " .. d.fights .. " fights counted"
		.. ((d.testFights > 0) and ("  |cff33ccff+ " .. d.testFights .. " test|cffaaaaaa") or "") .. "   |   " .. getn(names) .. " raiders|r")
	rVerdict:SetText("Every saved fight adds its hero and blame points here, for good - even after the fight itself is deleted.\n|cff888888Demo fights count as |cff33ccfftest|cff888888 data - |cffffd100Clear test data|cff888888 (bottom left) removes them. Click any line to post it.|r")
	hintText:SetText("Click a line to post it  -  Ctrl-click: only you see it  -  right-click a player for their record")
	hintText:Show()

	local rows
	if UI.fame.who then rows = UI:FamePlayerRows(UI.fame.who)
	elseif v == "plays" or v == "blunders" then
		rows = {}
		head(rows, (v == "plays") and "The biggest game-saving plays of all time" or "The most costly mistakes of all time")
		momentRows(rows, (v == "plays") and d.moments or d.blunders, v == "blunders")
	else rows = UI:FameBoardRows(v) end
	local key = "fame" .. v .. tostring(UI.fame.who) .. tostring(UI.fame.per)
	mainList:SetData(rows, key == lastModeKey)
	lastModeKey = key
end

local lastTab
function UI:Refresh()
	if not f:IsVisible() then return end
	UI.ShowGrid(false)   -- only the Consumes tab uses the grid
	local db = WhoDidItDB

	local e = W.env
	local function yn(v, n) return (v and "|cff33ff33" or "|cffff3333") .. n .. "|r" end
	envText:SetText(yn(e.nampower, "Nampower") .. "  " .. yn(e.superwow, "SuperWoW") .. "  " .. yn(e.twthreat or db.opts.queryThreat, "Threat")
		.. "  " .. (e.classicapi and "|cff33ff33ClassicAPI|r" or "|cff777777ClassicAPI?|r"))
	UI:UpdateAML()

	UI:ApplyMode()
	if UI.mode == "fame" then
		if W.Career then return UI:RefreshFame() end
		return UI:RefreshMissing()
	end
	if UI.mode ~= "fights" and not (W.Board and W.Logs and W.Marks and W.Loot) then return UI:RefreshMissing() end
	if UI.mode == "rankings" then return UI:RefreshRankings() end
	if UI.mode == "logs" then return UI:RefreshLogs() end
	if UI.mode == "marks" then return UI:RefreshMarks() end
	if UI.mode == "loot" then return UI:RefreshLoot() end
	lastModeKey = nil
	leftHead:SetText("Encounters")

	trashBtn:SetText("Track trash: " .. (db.opts.trackTrash and "|cff33ff33on|r" or "off"))
	local ann = db.opts.announce
	annBtn:SetText("Auto summary: " .. (ann == "channel" and "|cff33ff33on|r" or (ann == "self" and "me only" or "off")))
	autoBtn:SetText("Auto shout-outs: " .. ((db.opts.autoShout or "off") == "off" and "off" or ("|cff33ff33" .. db.opts.autoShout .. "|r")))
	local n = getn(db.fights)
	leftCount:SetText(n .. " saved")

	fightList:SetData(UI:FightRows(), true)

	for i = 1, getn(UI.tabButtons) do
		local b = UI.tabButtons[i]
		if b.id == UI.tab then b:LockHighlight() else b:UnlockHighlight() end
	end
	for i = 1, getn(UI.meterButtons) do
		local b = UI.meterButtons[i]
		if UI.tab == "meters" then b:Show() else b:Hide() end
		if b.id == UI.meter then b:LockHighlight() else b:UnlockHighlight() end
	end
	for tab, list in pairs(UI.actionButtons) do
		for i = 1, getn(list) do
			if tab == UI.tab then list[i]:Show() else list[i]:Hide() end
		end
	end
	if UI.tab == "meters" or UI.actionButtons[UI.tab] then
		hintText:Hide()
	else
		hintText:SetText(HINTS[UI.tab] or "")
		hintText:Show()
	end

	local rec = UI:Current()
	if not rec then
		rTitle:SetText("No fight selected")
		rInfo:SetText("|cffaaaaaaNothing recorded yet|r")
		rVerdict:SetText("|cff888888Pull a raid boss, or click |cff33ccffDemo fight|cff888888 (bottom-left) to try every feature.|r")
		mainList:SetData(UI:EmptyRows())
		return
	end

	rTitle:SetText(rec.enc .. "  " .. (RESULT[rec.result] or rec.result) .. (rec.demo and "  |cff33ccff(demo)|r" or ""))
	local info = { rec.zone or "", rec.date or "", "Duration " .. FmtTime(rec.dur), "Deaths " .. getn(rec.deaths) }
	if rec.healMana then tinsert(info, "Healer mana at wipe " .. pct(rec.healMana)) end
	rInfo:SetText("|cffaaaaaa" .. table.concat(info, "   |   ") .. "|r")
	local culprit = ""
	if rec.culprit then
		local b = rec.blame[1]
		culprit = "\n|cffffd100Most to blame:|r " .. W.CName(b.name, b.class) .. " |cffaaaaaa(" .. b.pts .. " pts)|r"
	end
	rVerdict:SetText((rec.result == "KILL" and "|cff33ff33" or "|cffff7777") .. (rec.verdict or "") .. "|r" .. culprit)

	local rows
	if UI.tab == "summary" and UI.cause then rows = UI:CauseRows(rec, UI.cause)
	elseif UI.tab == "summary" then rows = UI:SummaryRows(rec)
	elseif UI.tab == "deaths" then rows = UI:DeathRows(rec)
	elseif UI.tab == "mistakes" then rows = UI:MistakeRows(rec)
	elseif UI.tab == "threat" then rows = UI:ThreatRows(rec)
	elseif UI.tab == "meters" then rows = UI:MeterRows(rec)
	elseif UI.tab == "consumes" then rows = UI:ConsumeRows(rec)
	elseif UI.tab == "heroes" then rows = UI:HeroRows(rec)
	else rows = UI:TimelineRows(rec) end

	local key = UI.tab .. (UI.tab == "meters" and UI.meter or "") .. tostring(UI.selIdx) .. tostring(UI.detail) .. tostring(UI.cause)
		.. ((UI.tab == "timeline" and UI.tl) and (tostring(UI.tl.who) .. tostring(UI.tl.t)) or "")
	if UI.tab == "consumes" then
		UI.ShowGrid(true)
		consList:SetData(rows, key == lastTab)
	else
		mainList:SetData(rows, key == lastTab)
	end
	lastTab = key
	-- a focused timeline: put the moment a few rows from the top
	if UI.tlScrollTo then
		local off = math.max(0, math.min(mainList:MaxOffset(), UI.tlScrollTo - 4))
		UI.tlScrollTo = nil
		mainList.offset = off
		mainList:Refresh()
	end
end

------------------------------------------------------------------ hooks from the tracker

function UI:Toggle()
	if f:IsVisible() then
		f:Hide()
	else
		if W.Tracker.fight then UI.selIdx = 0 end
		UI.liveRec = nil
		f:Show()
		UI:Refresh()
	end
end

function UI:Open()
	if not f:IsVisible() then f:Show() end
	UI:Refresh()
end

function UI:ShowFight(idx)
	UI.selIdx = idx
	UI.detail = nil; UI.cause = nil
	UI.tab = "summary"
	UI:Open()
end

function UI:EmptyRows()
	local rows = {}
	head(rows, "Getting started")
	tinsert(rows, row("Fights are recorded automatically when your group engages a raid boss."))
	tinsert(rows, row("|cff33ccffDemo fight|r (bottom-left) adds two sample fights so you can try every tab right now."))
	tinsert(rows, row("Shift-click |cff33ccffDemo fight|r to watch a fight being analysed live."))
	tinsert(rows, row(" "))
	head(rows, "Before your first raid")
	tinsert(rows, row("Mark your main tanks:  |cffffd100/wdi tank <name>|r  (or right-click a name in Meters)"))
	tinsert(rows, row("Pick where shout-outs go with the |cffffd100To:|r button (top-right), or |cffffd100/wdi channel <name>|r"))
	tinsert(rows, row("Keep the boss targeted during the fight so threat % gets recorded."))
	tinsert(rows, row(" "))
	head(rows, "Your setup")
	local e = W.env
	local function yn(v) return v and "|cff33ff33found|r" or "|cffff3333missing|r" end
	tinsert(rows, row("Nampower: " .. yn(e.nampower) .. "     SuperWoW: " .. yn(e.superwow) .. "     TWThreat: " .. (e.twthreat and "|cff33ff33found|r" or "|cff888888not loaded (server queries used)|r")))
	local miss = W.MissingExtras()
	if getn(miss) > 0 then
		tinsert(rows, row("|cffffd100Optional extras not installed:|r " .. table.concat(miss, ", ")))
		tinsert(rows, row("   To use them, " .. W.SYNC_HOWTO .. ", then " .. W.RESTART_HINT .. "."))
	else
		tinsert(rows, row("Optional extras (raid packs, logger, RollFor): |cff33ff33all installed|r"))
	end
	tinsert(rows, row("ClassicAPI: " .. (e.classicapi and "|cff33ff33found|r" or "|cff999999not installed - optional extra, /wdi classicapi shows what it adds and how to get it|r"),
		nil, { click = function() W:ClassicApiInfo() end }))
	tinsert(rows, row("|cff888888All commands: /wdi help|r"))
	return rows
end

function UI:OnFightStart()
	if f:IsVisible() then
		UI.selIdx = 0
		UI.liveRec = nil
		UI:Refresh()
	end
end

function UI:OnFightEnd()
	UI.liveRec = nil
	if UI.selIdx == 0 then UI.selIdx = 1 end
	if not f:IsVisible() then return end
	UI.detail = nil; UI.cause = nil
	UI:Refresh()
end

f:SetScript("OnShow", function() UI:Refresh() end)

-- live view: rebuild the in-progress report every 1.5s while it's on screen
W:Every(1.5, function()
	if not f:IsVisible() then return end
	if UI.mode == "logs" or UI.mode == "marks" or UI.mode == "loot" then
		UI:Refresh()   -- unsaved line count / mobs in range and current marks
	elseif UI.mode == "fights" and W.Tracker.fight then
		if UI.selIdx == 0 then UI.liveRec = W.Analyzer:Build(W.Tracker.fight, false) end
		UI:Refresh()
	end
end)
