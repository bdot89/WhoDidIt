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

local WIDTH, HEIGHT = 860, 540
local LEFTW = 230
local ROWH, NROWS = 16, 21
local FROWH, FROWS = 30, 12

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
			if d and d.click then d.click(d, arg1) end
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
				b.r:SetText(d.r or "")
				b.l:SetText(d.l or "")
				local rw = (d.r and d.r ~= "") and (b.r:GetStringWidth() + 12) or 0
				b.l:SetWidth(self.rowW - rw - 8)
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

function UI.RowEnter(b)
	local d = b.d
	if not d or not d.tip then return end
	GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
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
local TOP = -36
local RX = PAD + LEFTW + GAP
local RW = WIDTH - RX - PAD
local HEADH = 78
local SHOUTW = 120
local HEADW = RW - SHOUTW - 30
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

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 4, -10)
title:SetText("|cffff5555Who|cffffd100DidIt|r")

local version = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 4, 1)
version:SetText("v" .. W.version)

local envText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
envText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -12)
envText:SetJustifyH("RIGHT")

local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

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

local sep = left:CreateTexture(nil, "ARTWORK")
sep:SetTexture(1, 1, 1, 0.12)
sep:SetHeight(1)
sep:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 8, 84)
sep:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -8, 84)

-- 3 x 2 button grid
local function gridButton(text, row, col)
	local b = button(left, text, BW, 20)
	b:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 8 + (col - 1) * (BW + 6), 8 + (row - 1) * 24)
	return b
end

local delBtn   = gridButton("Delete", 3, 1)
local clearBtn = gridButton("Clear all", 3, 2)
local trashBtn = gridButton("Trash: off", 2, 1)
local annBtn   = gridButton("Announce: self", 2, 2)
local autoBtn  = gridButton("Auto: off", 1, 1)
local demoBtn  = gridButton("|cff33ccffDemo fight|r", 1, 2)

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
tooltip(delBtn, "Delete", { "Delete the selected fight." })

clearBtn:SetScript("OnClick", function() StaticPopup_Show("WHODIDIT_CLEAR") end)
tooltip(clearBtn, "Clear all", { "Delete every saved fight (asks first)." })

trashBtn:SetScript("OnClick", function()
	WhoDidItDB.opts.trackTrash = not WhoDidItDB.opts.trackTrash
	UI:Refresh()
end)
tooltip(trashBtn, "Track trash", { "on - elite trash pulls are recorded too", "off - raid bosses only" })

annBtn:SetScript("OnClick", function()
	WhoDidItDB.opts.announce = cycle({ "self", "channel", "off" }, WhoDidItDB.opts.announce)
	UI:Refresh()
end)
tooltip(annBtn, "Announce after each fight", function()
	return {
		"me - short summary in your own chat",
		"chan - short summary posted to the shout channel (" .. W.Shout:ChannelLabel() .. ")",
		"off - silent",
	}
end)

autoBtn:SetScript("OnClick", function()
	WhoDidItDB.opts.autoShout = cycle({ "off", "smart", "shame", "praise", "both" }, WhoDidItDB.opts.autoShout)
	UI:Refresh()
end)
tooltip(autoBtn, "Auto shout-outs after each fight", function()
	return {
		"off - never",
		"smart - Name & Shame on wipes, Big Them Up on kills",
		"shame / praise / both - after every fight",
		"|cff888888Posted to: " .. W.Shout:ChannelLabel() .. "|r",
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

local function finishedRec()
	local rec = UI:Current()
	if not rec or rec.result == "LIVE" then W.Print("Pick a finished fight first.") return nil end
	return rec
end

local shameBtn = button(header, "|cffff5555Name & Shame|r", SHOUTW, 20)
shameBtn:SetPoint("TOPRIGHT", header, "TOPRIGHT", -8, -7)
shameBtn:SetScript("OnClick", function()
	local rec = finishedRec()
	if rec then W.Shout:Shame(rec) end
end)
tooltip(shameBtn, "Name & Shame", function()
	return {
		"Hall-of-shame awards for this fight: Most to blame, Threat Junkie, Floor Inspector, Fire Enthusiast, Bomb Squad, AFK Award, Participation Trophy.",
		"Shift-click any name in the window to shame just them.",
		"|cff888888Posts to: " .. W.Shout:ChannelLabel() .. "|r",
	}
end, "ANCHOR_LEFT")

local praiseBtn = button(header, "|cff33ff33Big Them Up|r", SHOUTW, 20)
praiseBtn:SetPoint("TOP", shameBtn, "BOTTOM", 0, -2)
praiseBtn:SetScript("OnClick", function()
	local rec = finishedRec()
	if rec then W.Shout:Praise(rec) end
end)
tooltip(praiseBtn, "Big Them Up", function()
	return {
		"Celebrates the stars of this fight: Damage King, Top Healer, Iron Wall, Kick Master, Cleanser, Tranq Sniper, Never Stops and everyone who played flawlessly.",
		"Alt-click any name in the window to big up just them.",
		"|cff888888Posts to: " .. W.Shout:ChannelLabel() .. "|r",
	}
end, "ANCHOR_LEFT")

local chanBtn = button(header, "To: Raid", SHOUTW, 20)
chanBtn:SetPoint("TOP", praiseBtn, "BOTTOM", 0, -2)
chanBtn:SetScript("OnClick", function()
	W.Shout:CycleChannel()
	UI:Refresh()
end)
tooltip(chanBtn, "Shout channel", {
	"Where Report and the shout-outs are posted. Click to cycle.",
	"|cff888888Custom channel: /wdi channel <name>|r",
}, "ANCHOR_LEFT")

------------------------------------------------------------------ right: tabs + content

local TABS = {
	{ id = "summary",  text = "Summary"  },
	{ id = "deaths",   text = "Deaths"   },
	{ id = "mistakes", text = "Mistakes" },
	{ id = "heroes",   text = "Heroes"   },
	{ id = "threat",   text = "Threat"   },
	{ id = "meters",   text = "Meters"   },
	{ id = "timeline", text = "Timeline" },
	{ id = "consumes", text = "Consumes" },
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
		UI:Refresh()
	end)
	UI.tabButtons[i] = b
end

local content = panel(RX, CONTY, RW, CONTH)
local mainList = CreateList(content, NROWS, ROWH, RW - 10)
mainList:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -6)

------------------------------------------------------------------ bottom bar

local METERS = {
	{ id = "dmg",   text = "Damage"   },
	{ id = "heal",  text = "Healing"  },
	{ id = "taken", text = "Taken"    },
	{ id = "act",   text = "Activity" },
	{ id = "util",  text = "Utility"  },
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
	UI.meterButtons[i] = b
end

-- per-tab post buttons in the bottom bar (they replace the hint line)
local ACTIONS = {
	consumes = {
		{ "Post summary", function(rec) W.Shout:Consumes(rec, "summary") end,
		  "Flask / food / elixir counts, protection potions, items used and the most prepared players." },
		{ "Post missing", function(rec) W.Shout:Consumes(rec, "missing") end,
		  "Who had no flask, no food buff and no elixirs." },
		{ "Post everyone", function(rec) W.Shout:Consumes(rec, "full") end,
		  "One line per player: every consumable buff they had and every item they used. Long!" },
	},
	heroes = {
		{ "Post heroes", function(rec) W.Shout:Heroes(rec) end,
		  "The hero board and the biggest game-saving plays." },
	},
}
UI.actionButtons = {}
for tab, list in pairs(ACTIONS) do
	UI.actionButtons[tab] = {}
	for i = 1, getn(list) do
		local a = list[i]
		local b = button(f, a[1], 112, 20)
		b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", RX + (i - 1) * 116, PAD)
		local fn = a[2]
		b:SetScript("OnClick", function()
			local rec = finishedRec()
			if rec then fn(rec) end
		end)
		tooltip(b, a[1], function()
			return { a[3], "|cff888888Posts to: " .. W.Shout:ChannelLabel() .. "  (coloured, like every WhoDidIt post)|r" }
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
	mistakes = "Sorted by blame points  -  hover for advice",
	threat   = "Threat % comes from the server for your target  -  keep the boss targeted",
	timeline = "Everything that happened, in order",
	consumes = "Buffs active during the fight, then items used  -  hover a player for the full list",
	heroes   = "Click a name to post their plays  -  hover a name for every click option",
}

------------------------------------------------------------------ data helpers

------------------------------------------------------------------ modes: Fights / Rankings / Logs

UI.mode = "fights"
UI.rk = { view = "kills" }   -- rankings state: view, realm, faction, inst, boss

local MODES = {
	{ id = "fights",   text = "Fights"   },
	{ id = "rankings", text = "Rankings" },
	{ id = "logs",     text = "Logs"     },
}
UI.modeButtons = {}
for i = 1, getn(MODES) do
	local m = MODES[i]
	local b = button(f, m.text, 78, 18)
	b:SetPoint("LEFT", version, "RIGHT", 18 + (i - 1) * 82, 0)
	b.id = m.id
	b:SetScript("OnClick", function() UI:SetMode(this.id) end)
	UI.modeButtons[i] = b
end
tooltip(UI.modeButtons[1], "Fights", { "Every recorded fight: why it went wrong, deaths, mistakes, heroes, meters, consumes." })
tooltip(UI.modeButtons[2], "Rankings", { "Boss kill times and full clears: yours, your guild's, and every guild on your realm that has a WhoDidIt user." })
tooltip(UI.modeButtons[3], "Logs", { "Chronicle combat logging: start, stop, save, archive and delete the log you upload to chronicleclassic.com." })

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
	{ "Kill times", function() UI.rk.view = "kills"; UI.rk.boss = nil; UI:Refresh() end,
	  { "Best kill time on every boss: you, your guild and the realm." } },
	{ "Full clears", function() UI.rk.view = "clears"; UI.rk.boss = nil; UI:Refresh() end,
	  { "Fastest full clear of the instance: first combat inside to the last boss.", "Optional bosses aren't required." } },
	{ "Realm", function()
		local list = W.Board:Realms()
		tinsert(list, 2, W.Board.ALL)   -- your realm, then all realms together, then the rest
		UI.rk.realm = cycleList(list, UI.rk.realm or W.Board.Realm())
		UI.rk.boss = nil
		UI:Refresh()
	  end, { "Your realm, then all realms together (compare against every guild), then each other realm." } },
	{ "Faction", function()
		local mine = W.Board.Faction()
		local other = (mine == "Horde") and "Alliance" or "Horde"
		UI.rk.faction = cycleList({ mine, "All", other }, UI.rk.faction or mine)
		UI:Refresh()
	  end, { "Your faction first, then everyone, then the other faction." } },
	{ "Sharing", function()
		WhoDidItDB.opts.shareBoard = not WhoDidItDB.opts.shareBoard
		if WhoDidItDB.opts.shareBoard then W.Board:Join() else W.Board:Leave() end
		UI:Refresh()
	  end, { "Share your guild's records with WhoDidIt users on this realm (and receive theirs).",
	         "Uses a hidden chat channel; records are self-reported." } },
	{ "Ask for times", function()
		if UI.rk.asked and GetTime() - UI.rk.asked < 60 then W.Print("Already asked - give people a minute to answer.") return end
		UI.rk.asked = GetTime()
		W.Board:Ask()
		W.Print("Asked WhoDidIt users on " .. W.Board.Realm() .. " for their guild's times.")
	  end, { "Ask everyone online with WhoDidIt for their guild's best times right now." } },
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

-- banter toggles take the place of the fight buttons while in Rankings
local banterKillBtn  = gridButton("Kill banter", 3, 1)
local banterClearBtn = gridButton("Clear banter", 3, 2)
local banterTestBtn  = gridButton("Test banter", 2, 1)
banterKillBtn:SetScript("OnClick", function()
	WhoDidItDB.opts.banterKills = not WhoDidItDB.opts.banterKills
	UI:Refresh()
end)
banterClearBtn:SetScript("OnClick", function()
	WhoDidItDB.opts.banterClears = not WhoDidItDB.opts.banterClears
	UI:Refresh()
end)
banterTestBtn:SetScript("OnClick", function() W.Board:BanterTest() end)
local function banterTip()
	return {
		"After every boss kill / full clear, post a fun line comparing our time with our best and with other guilds on the realm - trolling us when we're slow, bigging us up when we're fast.",
		"|cff888888Posts to: " .. W.Shout:ChannelLabel() .. "|r",
	}
end
tooltip(banterKillBtn, "Kill banter", banterTip)
tooltip(banterClearBtn, "Clear banter", banterTip)
tooltip(banterTestBtn, "Test banter", { "Show a random banter line for a made-up kill - in your own chat only." })
local rankOnly = { banterKillBtn, banterClearBtn, banterTestBtn }
for i = 1, getn(rankOnly) do rankOnly[i]:Hide() end

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
	local fightOnly = { shameBtn, praiseBtn, chanBtn, reportBtn, delBtn, clearBtn, trashBtn, annBtn, autoBtn, demoBtn }
	for i = 1, getn(fightOnly) do vis(fightOnly[i], fights) end
	for i = 1, getn(rankOnly) do vis(rankOnly[i], UI.mode == "rankings" and W.Board ~= nil) end
	local o = WhoDidItDB.opts
	banterKillBtn:SetText("Kill banter: " .. (o.banterKills and "|cff33ff33on|r" or "|cffff5555off|r"))
	banterClearBtn:SetText("Clear banter: " .. (o.banterClears and "|cff33ff33on|r" or "|cffff5555off|r"))
	if not fights then
		for i = 1, getn(UI.meterButtons) do UI.meterButtons[i]:Hide() end
		for _, list in pairs(UI.actionButtons) do
			for i = 1, getn(list) do list[i]:Hide() end
		end
	end
end

function UI:SetMode(mode)
	UI.mode = mode
	UI.rk.boss = nil
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

local function stripColors(s)
	s = string.gsub(s or "", "|c%x%x%x%x%x%x%x%x", "")
	s = string.gsub(s, "|r", "")
	return s
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
	for i = 1, getn(rec.blame) do
		local b = rec.blame[i]
		if shown >= 15 then break end
		shown = shown + 1
		local why = string.gsub(b.reasons[1] or "", "^" .. b.name .. " ", "")
		if getn(b.reasons) > 1 then why = why .. " (+" .. (getn(b.reasons) - 1) .. " more)" end
		tinsert(rows, row(
			i .. ". " .. W.CName(b.name, b.class) .. "  |cffaaaaaa" .. why .. "|r",
			string.format("%.1f", b.pts),
			{ bar = b.pts / maxPts, cr = 0.9, cg = 0.15, cb = 0.15,
			  tip = withLegend(b.reasons, "blame"), tipTitle = b.name .. " - " .. b.pts .. " blame points",
			  name = b.name, click = playerClick("blame") }))
	end
	if shown == 0 then tinsert(rows, row("|cff33ff33Nobody - well played.|r")) end

	if rec.heroes and getn(rec.heroes) > 0 then
		head(rows, "Heroes (see the Heroes tab)")
		for i = 1, math.min(3, getn(rec.heroes)) do
			local h = rec.heroes[i]
			local why = string.gsub(h.list[1] or "", "^" .. h.name .. " ", "")
			tinsert(rows, row(i .. ". " .. W.CName(h.name, h.class) .. "  |cffaaaaaa" .. why .. "|r",
				"|cff33ff33" .. string.format("%.1f", h.pts) .. "|r",
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
	tinsert(tip, "|cff888888Click for the full recap|r")
	return tip
end

function UI:DeathRows(rec)
	local rows = {}
	if UI.detail then
		local d = UI.detail
		tinsert(rows, row("|cffffd100<< Back to deaths|r", nil, { head = true, click = function() UI.detail = nil; UI:Refresh() end }))
		tinsert(rows, row(W.CName(d.name, d.class) .. " died at " .. FmtTime(d.t) .. " - " .. d.text, nil, { head = true }))
		for i = 1, getn(d.lines) do
			local l = d.lines[i]
			local dt = string.format("%5.1fs", l.t - d.t)
			local hpf = (l.hp and l.hm and l.hm > 0) and (l.hp / l.hm) or nil
			local left, right
			if l.k == "heal" then
				left = dt .. "   |cff33ff33" .. (l.sp or "") .. "|r from " .. (l.s or "?")
				right = "|cff33ff33+" .. FmtNum(l.a) .. (l.c and "*" or "") .. "|r"
			elseif l.k == "debuff" then
				left = dt .. "   |cffcc99ffgains " .. (l.sp or "") .. "|r"
				right = ""
			elseif l.k == "item" then
				left = dt .. "   |cff66ccffused " .. (l.sp or "") .. "|r"
				right = ""
			elseif l.k == "buff" then
				left = dt .. "   |cffffcc66gains " .. (l.sp or "") .. "|r"
				right = ""
			else
				left = dt .. "   |cffff7777" .. (l.sp or "") .. "|r from " .. (l.s or "?") .. (l.x == "crushing" and " |cffff9933(crushing)|r" or "")
				right = "|cffff5555-" .. FmtNum(l.a) .. (l.c and "*" or "") .. "|r"
			end
			if hpf then right = right .. "  |cffaaaaaa" .. pct(hpf) .. "|r" end
			tinsert(rows, row(left, right, { bar = hpf, cr = 0.1, cg = 0.75, cb = 0.1 }))
		end
		if getn(d.lines) == 0 then tinsert(rows, row("|cff888888No combat events recorded before this death.|r")) end
		return rows
	end

	if getn(rec.deaths) == 0 then
		tinsert(rows, row("|cff33ff33Nobody died.|r"))
		return rows
	end
	for i = 1, getn(rec.deaths) do
		local d = rec.deaths[i]
		local col = d.late and "|cff777777" or ((d.kind == "avoid" or d.kind == "aggro" or d.kind == "splash") and "|cffff7777" or "|cffffffff")
		local dd = d
		tinsert(rows, row(
			"|cff999999" .. FmtTime(d.t) .. "|r  " .. W.CName(d.name, d.class) .. "  " .. col .. d.text .. (d.late and " (after wipe)" or "") .. "|r",
			"|cffaaaaaa" .. (d.killer or "") .. (d.killAmt and (" " .. FmtNum(d.killAmt)) or "") .. "|r",
			{ tip = recapTip(d), tipTitle = d.name .. " died at " .. FmtTime(d.t),
			  click = function() UI.detail = dd; UI:Refresh() end }))
	end
	return rows
end

function UI:MistakeRows(rec)
	local rows = {}
	if getn(rec.findings) == 0 then
		tinsert(rows, row("|cff33ff33No mistakes found.|r"))
		return rows
	end
	for i = 1, getn(rec.findings) do
		local fd = rec.findings[i]
		local who = fd.who and rec.players[fd.who]
		local text = fd.text
		if fd.who and who then
			local s, e = string.find(text, fd.who, 1, true)
			if s then text = string.sub(text, 1, s - 1) .. W.CName(fd.who, who.class) .. string.sub(text, e + 1) end
		end
		tinsert(rows, row(
			(fd.t and ("|cff999999" .. FmtTime(fd.t) .. "|r  ") or "|cff999999 --  |r") .. "|cffffd100[" .. fd.cat .. "]|r " .. text,
			fd.pts > 0 and ("|cffff5555+" .. fd.pts .. "|r") or "|cff888888info|r",
			{ tip = fd.tip, tipTitle = stripColors(fd.text) }))
	end
	return rows
end

local VERDICT = {
	pulled   = "|cffff5555pulled aggro|r",
	pull     = "|cffff9933opened on boss|r",
	tank     = "|cff888888tank|r",
	inherit  = "|cff888888after holder died|r",
	mechanic = "|cff888888boss mechanic|r",
}

function UI:ThreatRows(rec)
	local rows = {}
	head(rows, "Who the boss attacked")
	if getn(rec.aggro) == 0 then
		tinsert(rows, row("|cff888888No boss target changes recorded (needs SuperWoW).|r"))
	end
	for i = 1, getn(rec.aggro) do
		local a = rec.aggro[i]
		tinsert(rows, row(
			"|cff999999" .. FmtTime(a.t) .. "|r  " .. a.boss .. " -> " .. W.CName(a.to, a.class) .. (a.from and ("  |cff888888(from " .. a.from .. ")|r") or ""),
			(a.perc and (a.perc .. "%  ") or "") .. (VERDICT[a.verdict] or ""),
			{ tip = { "Detected by: " .. (a.how == "melee" and "boss melee swing" or "boss target"), a.perc and ("Threat at the time: " .. a.perc .. "%") or "No threat reading at the time" } }))
	end

	head(rows, "Peak threat (% of the aggro holder)")
	local list = {}
	for name, t in pairs(rec.threat) do tinsert(list, { name, t }) end
	table.sort(list, function(a, b) return a[2].perc > b[2].perc end)
	if getn(list) == 0 then
		tinsert(rows, row("|cff888888No threat data. Target the boss during the fight - threat comes from the Turtle server for your target.|r"))
	end
	for i = 1, getn(list) do
		local name, t = list[i][1], list[i][2]
		local r, g, b = W.ClassRGB(t.class)
		local col = t.perc >= 100 and "|cffff5555" or (t.perc >= 90 and "|cffff9933" or "|cffffffff")
		tinsert(rows, row(
			i .. ". " .. W.CName(name, t.class),
			col .. t.perc .. "%|r  |cff888888at " .. FmtTime(t.t) .. "|r",
			{ bar = t.perc / 130, cr = r, cg = g, cb = b }))
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

	for i = 1, getn(list) do
		local it = list[i]
		local p = it.p
		local r, g, b = W.ClassRGB(p.class)
		local right, tip
		local alive = (p.alive and p.alive > 0) and p.alive or rec.dur
		if mode == "dmg" or mode == "heal" or mode == "taken" then
			right = FmtNum(it.v) .. "  |cffaaaaaa(" .. FmtNum(it.v / alive) .. "/s)|r"
			local src = (mode == "dmg" and p.ds) or (mode == "heal" and p.hs) or p.ts
			tip = {}
			for j = 1, getn(src or {}) do
				tinsert(tip, { src[j][1], FmtNum(src[j][2]) .. "  " .. pct(src[j][2] / it.v) })
			end
			if mode == "dmg" then tinsert(tip, { "Damage to bosses", FmtNum(p.boss) }) end
		elseif mode == "act" then
			right = pct(it.v)
			tip = { "Share of their time alive spent casting / swinging / healing.", "Alive: " .. FmtTime(alive) }
		else
			right = (p.kicks or 0) .. " kicks  " .. (p.dispels or 0) .. " dispels  " .. (p.tranqs or 0) .. " tranqs  " .. (p.cons or 0) .. " items"
			tip = {}
			for j = 1, getn(p.consList or {}) do tinsert(tip, { p.consList[j][1], p.consList[j][2] .. "x" }) end
		end
		tinsert(tip, " ")
		tinsert(tip, "Role: " .. (p.role or "?") .. (WhoDidItDB.tanks[it.name] and " (marked tank)" or "") .. "   Deaths: " .. (p.deaths or 0))
		if (p.aggro or 0) > 0 then tinsert(tip, "Held boss aggro for " .. FmtTime(p.aggro)) end
		tip = withLegend(tip, "stats")
		tinsert(rows, row(
			i .. ". " .. W.CName(it.name, p.class) .. (p.role == "tank" and " |cff888888(T)|r" or (p.role == "heal" and " |cff888888(H)|r" or "")),
			right,
			{ bar = it.v / max, cr = r, cg = g, cb = b, tip = tip, tipTitle = it.name, name = it.name, click = playerClick("stats") }))
	end
	return rows
end

local BUFF_COL = { Flask = "cc99ff", Elixir = "66ccff", Food = "ffcc66", Buff = "ff9933", Protection = "ff6666", Potion = "33ff33" }
local USED_COL = { Mana = "66aaff", Health = "33ff33", Protection = "ff6666", Other = "dddddd" }
local ROLE_ORDER = { tank = 1, heal = 2, dps = 3 }
local ROLE_TAG = { tank = "Tank", heal = "Healer", dps = "DPS" }

function UI:ConsumeRows(rec)
	local rows = {}
	local list = {}
	for name, p in pairs(rec.players) do tinsert(list, { name = name, p = p }) end
	table.sort(list, function(a, b)
		local x, y = ROLE_ORDER[a.p.role] or 9, ROLE_ORDER[b.p.role] or 9
		if x ~= y then return x < y end
		return a.name < b.name
	end)
	if getn(list) == 0 then
		tinsert(rows, row("|cff888888No players recorded.|r"))
		return rows
	end
	if not list[1].p.cbuffs then
		tinsert(rows, row("|cff888888This fight was recorded by an older version - only items used are available.|r"))
	end

	-- raid overview
	local n = getn(list)
	local flask, food, prot = {}, {}, {}
	local noFlask, noFood = {}, {}
	local usedTotals = { Mana = 0, Health = 0, Protection = 0, Other = 0 }
	for i = 1, n do
		local it = list[i]
		local has = {}
		for j = 1, getn(it.p.cbuffs or {}) do has[it.p.cbuffs[j][2]] = true end
		if has.Flask then tinsert(flask, it.name) else tinsert(noFlask, it.name) end
		if has.Food then tinsert(food, it.name) else tinsert(noFood, it.name) end
		if has.Protection then tinsert(prot, it.name) end
		for j = 1, getn(it.p.used or {}) do
			local u = it.p.used[j]
			usedTotals[u[3]] = (usedTotals[u[3]] or 0) + u[2]
		end
	end
	local function frac(have, total)
		return ((have == total) and "|cff33ff33" or "|cffff9933") .. have .. " / " .. total .. "|r"
	end
	head(rows, "Raid overview")
	tinsert(rows, row("Flasked", frac(getn(flask), n), { tip = getn(noFlask) > 0 and { "No flask: " .. table.concat(noFlask, ", ") } or nil, tipTitle = "Flasks" }))
	tinsert(rows, row("Food buff", frac(getn(food), n), { tip = getn(noFood) > 0 and { "No food buff: " .. table.concat(noFood, ", ") } or nil, tipTitle = "Food" }))
	tinsert(rows, row("Protection potion active", getn(prot) .. " player(s)", { tip = getn(prot) > 0 and { table.concat(prot, ", ") } or nil, tipTitle = "Protection potions" }))
	tinsert(rows, row("Items used",
		"|cff" .. USED_COL.Mana .. usedTotals.Mana .. " mana|r   |cff" .. USED_COL.Health .. usedTotals.Health .. " health|r   |cff"
		.. USED_COL.Protection .. usedTotals.Protection .. " protection|r   |cff" .. USED_COL.Other .. usedTotals.Other .. " other|r"))

	-- per player
	head(rows, "Players")
	for i = 1, n do
		local it = list[i]
		local p = it.p
		local cb = p.cbuffs or {}
		local used = p.used
		if not used then
			used = {}
			for j = 1, getn(p.consList or {}) do used[j] = { p.consList[j][1], p.consList[j][2], "Other" } end
		end

		local hasFlask = false
		local bparts, tip = {}, {}
		for j = 1, getn(cb) do
			local b = cb[j]
			if b[2] == "Flask" then hasFlask = true end
			tinsert(bparts, "|cff" .. (BUFF_COL[b[2]] or "ffffff") .. b[1] .. "|r")
			tinsert(tip, { "|cff" .. (BUFF_COL[b[2]] or "ffffff") .. b[1] .. "|r  |cff888888" .. b[2] .. "|r",
				(b[3] and b[3] > 0) and ("gained at " .. FmtTime(b[3])) or "before the pull" })
		end
		local uparts, nUsed = {}, 0
		if getn(used) > 0 then tinsert(tip, " ") end
		for j = 1, getn(used) do
			local u = used[j]
			nUsed = nUsed + u[2]
			local txt = u[1] .. ((u[2] > 1) and (" x" .. u[2]) or "")
			tinsert(uparts, "|cff" .. (USED_COL[u[3]] or "ffffff") .. txt .. "|r")
			tinsert(tip, { "used |cff" .. (USED_COL[u[3]] or "ffffff") .. u[1] .. "|r", u[2] .. "x  |cff888888" .. u[3] .. "|r" })
		end
		if getn(tip) == 0 then tip = { "No consumables seen." } end
		tip = withLegend(tip, "consumes")
		local click = playerClick("consumes")

		local summary = (hasFlask and "|cffcc99ffflask|r" or "|cffff5555no flask|r")
			.. "  |cffaaaaaa" .. getn(cb) .. " buffs, " .. nUsed .. " used|r"
		tinsert(rows, row(W.CName(it.name, p.class) .. "  |cff888888" .. (ROLE_TAG[p.role] or "") .. "|r", summary,
			{ tip = tip, tipTitle = it.name .. " - consumables", name = it.name, click = click }))
		tinsert(rows, row("      |cffaaaaaaBuffs:|r " .. (getn(bparts) > 0 and table.concat(bparts, ", ") or "|cffff5555none|r"),
			nil, { tip = tip, tipTitle = it.name .. " - consumables", name = it.name, click = click }))
		tinsert(rows, row("      |cffaaaaaaUsed:|r " .. (getn(uparts) > 0 and table.concat(uparts, ", ") or "|cff888888nothing|r"),
			nil, { tip = tip, tipTitle = it.name .. " - consumables", name = it.name, click = click }))
	end
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
	if getn(hs) == 0 then tinsert(rows, row("|cff888888No game-saving plays detected this fight.|r")) end
	for i = 1, getn(hs) do
		local h = hs[i]
		local why = string.gsub(h.list[1] or "", "^" .. h.name .. " ", "")
		if getn(h.list) > 1 then why = why .. " (+" .. (getn(h.list) - 1) .. " more)" end
		tinsert(rows, row(i .. ". " .. W.CName(h.name, h.class) .. "  |cffaaaaaa" .. why .. "|r",
			string.format("%.1f", h.pts),
			{ bar = h.pts / max, cr = 0.15, cg = 0.8, cb = 0.3, tip = withLegend(h.list, "hero"),
			  tipTitle = h.name .. " - " .. h.pts .. " hero points", name = h.name, click = playerClick("hero") }))
	end

	head(rows, "Game-saving moments")
	if getn(rec.saves) == 0 then tinsert(rows, row("|cff888888Nothing this time.|r")) end
	for i = 1, getn(rec.saves) do
		local s = rec.saves[i]
		tinsert(rows, row(
			(s.t and ("|cff999999" .. FmtTime(s.t) .. "|r  ") or "|cff999999 --  |r") .. colorNames(s.text, rec),
			"|cff33ff33+" .. s.pts .. "|r",
			{ tip = s.tip, tipTitle = "Save" }))
	end

	head(rows, "What counts")
	tinsert(rows, row("|cff888888Heals that land on someone under 20% who then lives, shields that soak a killing blow, taunts that|r"))
	tinsert(rows, row("|cff888888rescue a player from the boss, Lay on Hands / BoP, battle res, Innervate on a low-mana healer,|r"))
	tinsert(rows, row("|cff888888dispelling mind control, interrupts, fast tranqs and last-second potions or cooldowns.|r"))
	return rows
end

function UI:TimelineRows(rec)
	local rows = {}
	local tl = rec.timeline or {}
	for i = 1, getn(tl) do
		local l = tl[i]
		tinsert(rows, row("|cff999999" .. FmtTime(l.t) .. "|r  " .. (KIND_COLOR[l.k] or "|cffffffff") .. (l.x or "") .. "|r"))
	end
	if getn(rows) == 0 then tinsert(rows, row("|cff888888Nothing recorded.|r")) end
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

-- the ranked leaderboard for one boss or one instance's clears, every
-- time compared with your guild's ("1:38.6 faster" / "3:51.1 slower")
local function boardRows(rows, realm, faction, kind, key, myGuild)
	local B = W.Board
	local list = B:Board(realm, kind, key, faction)
	if getn(list) == 0 then
		tinsert(rows, row("|cff888888No times yet. They show up when you or a WhoDidIt user on your realm gets one,|r"))
		tinsert(rows, row("|cff888888or when tools\\WhoDidIt-Sync pulls them from Chronicle.|r"))
		return
	end
	local home = B.Realm()
	local mine = myGuild and B:GuildBest(home, kind, key, myGuild)
	local best = list[1][2].t
	local allRealms = (realm == B.ALL)
	for i = 1, getn(list) do
		local g, rec, rlm = list[i][1], list[i][2], list[i][3]
		local isMine = (g == myGuild and rlm == home)
		local name = (isMine and "|cffffd100" or "|cffffffff") .. g .. "|r"
		if allRealms then name = name .. "  |cff888888" .. rlm .. "|r" end
		local cmp
		if isMine then
			cmp = "|cffffd100<< you|r"
		elseif mine then
			local d = rec.t - mine.t
			cmp = (d < 0) and ("|cffff5555" .. B.Fmt(-d) .. " faster|r") or ("|cff33ff33" .. B.Fmt(d) .. " slower|r")
		elseif i > 1 then
			cmp = "|cff888888+" .. B.Fmt(rec.t - best) .. "|r"
		end
		local c = FAC_BAR[rec.f] or { 0.5, 0.5, 0.5 }
		tinsert(rows, row(
			rankTxt(i) .. "  " .. facTag(rec.f) .. "  " .. name .. "   |cff777777" .. B.Date(rec.d)
				.. ((rec.n and rec.n > 0) and (", " .. rec.n .. " players") or "") .. "|r",
			"|cffffffff" .. B.Fmt(rec.t) .. "|r" .. (cmp and ("    " .. cmp) or ""),
			{ sel = isMine, bar = best / rec.t, ba = 0.2, cr = c[1], cg = c[2], cb = c[3], tipTitle = g,
			  tip = rec.chron and {
			          "|cffffd100From Chronicle|r (chronicleclassic.com) - " .. B.Date(rec.d),
			          "Realm: " .. (rlm or "?") .. "   Faction: " .. (rec.f or "?") .. ((rec.f == "Mixed") and " (cross-faction raid)" or ""),
			          "Log: " .. (rec.slug or "?"),
			      } or {
			          "Recorded " .. B.Date(rec.d) .. (rec.by and (" by " .. rec.by) or "") .. "   Realm: " .. (rlm or "?"),
			          rec.net and "Shared by a WhoDidIt user (self-reported)" or "Recorded by your WhoDidIt",
			      } }))
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
			      "|cff888888The green bar is how close your guild is to #1.|r",
			  },
			  click = function() UI.rk.inst = zone; UI.rk.boss = nil; UI:Refresh() end }))
	end
	return rows
end

function UI:RankKillRows(realm, faction, zone)
	local B = W.Board
	local rows = {}
	local guild = B.MyGuild()
	head(rows, "Boss kill times  |cff888888(click a boss for its full leaderboard)|r")
	local bosses = instBosses(zone)
	for i = 1, getn(bosses) do
		local enc = bosses[i]
		local top = B:Board(realm, "kills", enc, faction)[1]
		local mine = B:MyBest("kills", enc)
		local g = guild and B:GuildBest(realm, "kills", enc, guild)
		local rank = g and B:Rank(realm, "kills", enc, guild, faction)
		local gap = ""
		if g and top and top[2] ~= g then gap = "  |cffff7777+" .. B.Fmt(g.t - top[2].t) .. "|r" end
		tinsert(rows, row("|cffffffff" .. enc .. "|r",
			"|cff66ccffyou|r " .. (mine and B.Fmt(mine.t) or "-")
				.. "    |cff33ff33guild|r " .. (g and (B.Fmt(g.t) .. (rank and (" " .. rankTxt(rank)) or "") .. gap) or "-")
				.. "    |cffffd100#1|r " .. (top and (B.Fmt(top[2].t) .. " |cffffffff" .. top[1] .. "|r") or "-"),
			{ click = function() UI.rk.boss = enc; UI:Refresh() end,
			  bar = (g and top) and (top[2].t / g.t) or nil, ba = 0.2, cr = 0.15, cg = 0.75, cb = 0.3,
			  tip = { "you = your best kill (WhoDidIt or Chronicle)",
			          "guild = your guild's best, its rank and how far behind #1 it is",
			          "#1 = the fastest guild (" .. realm .. ", " .. faction .. ")",
			          "|cff888888Click for the full leaderboard.|r" },
			  tipTitle = enc }))
	end
	return rows
end

function UI:RankBossRows(realm, faction, enc)
	local B = W.Board
	local rows = {}
	local guild = B.MyGuild()
	tinsert(rows, row("|cffffd100<< Back to all bosses|r", nil, { head = true, click = function() UI.rk.boss = nil; UI:Refresh() end }))
	head(rows, enc .. " on " .. realm .. "  |cff888888(" .. faction .. ")|r")
	local mine = B:MyBest("kills", enc)
	tinsert(rows, row("|cff66ccffYour best kill|r", mine and ("|cffffffff" .. B.Fmt(mine.t) .. "|r  |cff888888" .. B.Date(mine.d) .. "|r") or "|cff888888none yet|r"))
	if guild then
		local g = B:GuildBest(realm, "kills", enc, guild)
		local rank, of = B:Rank(realm, "kills", enc, guild, faction)
		tinsert(rows, row("|cff33ff33" .. guild .. "|r", g and ("|cffffffff" .. B.Fmt(g.t) .. "|r  "
			.. (rank and (rankTxt(rank) .. " of " .. of) or ("|cff888888on " .. B.Realm() .. "|r"))) or "|cff888888no kill yet|r"))
	end
	head(rows, "Leaderboard")
	boardRows(rows, realm, faction, "kills", enc, guild)
	return rows
end

function UI:RankClearRows(realm, faction, zone)
	local B = W.Board
	local rows = {}
	local guild = B.MyGuild()
	local need = W.Data.clears[zone] or {}
	head(rows, "Full clears of " .. instTitle(zone))
	local mine = B:MyBest("clears", zone)
	tinsert(rows, row("|cff66ccffYour best clear|r", mine and ("|cffffffff" .. B.Fmt(mine.t) .. "|r  |cff888888" .. B.Date(mine.d) .. "|r") or "|cff888888none yet|r"))
	if guild then
		local g = B:GuildBest(realm, "clears", zone, guild)
		local rank, of = B:Rank(realm, "clears", zone, guild, faction)
		tinsert(rows, row("|cff33ff33" .. guild .. "|r", g and ("|cffffffff" .. B.Fmt(g.t) .. "|r  "
			.. (rank and (rankTxt(rank) .. " of " .. of) or ("|cff888888on " .. B.Realm() .. "|r"))) or "|cff888888no clear yet|r"))
	end
	local run = B:CurrentRun()
	if run and run.zone == zone then
		local done = 0
		for i = 1, getn(need) do if run.kills[need[i]] then done = done + 1 end end
		tinsert(rows, row("|cff33ccffRun in progress|r  " .. done .. " / " .. getn(need) .. " bosses", "|cffffffff" .. B.Fmt(time() - run.start) .. "|r so far"))
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
	UI.rankButtons[5]:SetText("Sharing: " .. (WhoDidItDB.opts.shareBoard and "|cff33ff33on|r" or "|cffff5555off|r"))
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
	if c and c.synced then
		local mins = floor((time() - c.synced) / 60)
		chron = "Chronicle " .. ((c.status ~= "ok") and ("|cffffd100" .. (c.status or "") .. "|r") or (mins < 2 and "just synced" or (mins .. " min ago")))
	else
		chron = "Chronicle not synced"
	end
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
	if UI.rk.boss then rows = UI:RankBossRows(realm, faction, UI.rk.boss)
	elseif UI.rk.view == "kills" then rows = UI:RankKillRows(realm, faction, zone)
	else rows = UI:RankClearRows(realm, faction, zone) end

	hintText:SetText("Kills: pull to kill.  Clears: first combat inside to the last boss.  Shared times are self-reported.")
	hintText:Show()
	local key = "rk" .. realm .. faction .. zone .. UI.rk.view .. tostring(UI.rk.boss)
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
		head(rows, "ChronicleCompanion isn't loaded")
		tinsert(rows, row("WhoDidIt drives the |cffffd100ChronicleCompanion|r addon, which writes the logs you upload to chronicleclassic.com."))
		tinsert(rows, row("Install it in Interface/AddOns (it needs Nampower for file access), then /reload."))
		return rows
	end
	local opts = WhoDidItDB.opts
	local file = L:File() or "?"
	head(rows, "Status")
	tinsert(rows, row("Chronicle logging", L:Enabled() and "|cff33ff33ON|r" or "|cffff5555OFF|r"))
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
		rTitle:SetText("Chronicle logs  " .. (L:Enabled() and "|cff33ff33LOGGING|r" or "|cffff5555OFF|r"))
		rInfo:SetText("|cffaaaaaaCustomData\\" .. (L:File() or "?") .. "   |   " .. FmtNum(L:Unsaved()) .. " unsaved lines|r")
	else
		rTitle:SetText("Chronicle logs  |cffff5555not found|r")
		rInfo:SetText("|cffaaaaaaChronicleCompanion addon not loaded|r")
	end
	rVerdict:SetText("Upload the log at |cffffd100chronicleclassic.com|r after your raid.\n|cff888888Addons can't reach the internet, so uploading happens on the website.|r")
	hintText:SetText("Click an option to switch it on or off.  Hover the buttons for details.")
	hintText:Show()
	local key = "logs"
	mainList:SetData(UI:LogRows(), key == lastModeKey)
	lastModeKey = key
end

-- Board.lua / Logs.lua didn't load (the game wasn't restarted after an update)
function UI:RefreshMissing()
	for i = 1, getn(UI.rankButtons) do UI.rankButtons[i]:Hide() end
	for i = 1, getn(UI.logButtons) do UI.logButtons[i]:Hide() end
	leftHead:SetText(UI.mode == "logs" and "Logs" or "Rankings")
	leftCount:SetText("")
	fightList:SetData({})
	rTitle:SetText("Restart WoW to finish updating")
	rInfo:SetText("|cffaaaaaaNew WhoDidIt files aren't loaded yet|r")
	rVerdict:SetText("|cffff7777Exit the game completely and start it again.|r\n|cff888888A /reload isn't enough: WoW only picks up new addon files at start-up.|r")
	hintText:SetText("")
	local rows = {}
	head(rows, "Why")
	tinsert(rows, row("This update added Rankings (Board.lua) and Chronicle log controls (Logs.lua)."))
	tinsert(rows, row("WoW reads each addon's file list once, when the game starts - /reload only re-runs files it already knows."))
	tinsert(rows, row("Fights still work normally until then: click |cffffd100Fights|r in the title bar."))
	lastModeKey = nil
	mainList:SetData(rows)
end

local lastTab
function UI:Refresh()
	if not f:IsVisible() then return end
	local db = WhoDidItDB

	local e = W.env
	local function yn(v, n) return (v and "|cff33ff33" or "|cffff3333") .. n .. "|r" end
	envText:SetText(yn(e.nampower, "Nampower") .. "  " .. yn(e.superwow, "SuperWoW") .. "  " .. yn(e.twthreat or db.opts.queryThreat, "Threat"))

	UI:ApplyMode()
	if UI.mode ~= "fights" and not (W.Board and W.Logs) then return UI:RefreshMissing() end
	if UI.mode == "rankings" then return UI:RefreshRankings() end
	if UI.mode == "logs" then return UI:RefreshLogs() end
	lastModeKey = nil
	leftHead:SetText("Encounters")

	trashBtn:SetText("Trash: " .. (db.opts.trackTrash and "on" or "off"))
	local ann = db.opts.announce
	annBtn:SetText("Announce: " .. (ann == "channel" and "chan" or (ann == "self" and "me" or ann)))
	autoBtn:SetText("Auto: " .. (db.opts.autoShout or "off"))
	chanBtn:SetText("To: " .. W.Shout:ChannelLabel())
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
	mainList:SetData(rows, key == lastTab)
	lastTab = key
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
	if UI.mode == "logs" then
		UI:Refresh()   -- unsaved line count
	elseif UI.mode == "fights" and W.Tracker.fight then
		if UI.selIdx == 0 then UI.liveRec = W.Analyzer:Build(W.Tracker.fight, false) end
		UI:Refresh()
	end
end)
