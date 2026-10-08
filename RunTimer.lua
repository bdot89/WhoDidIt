--[[--------------------------------------------------------------------
	WhoDidIt - the run timer

	A small window on screen while a run is on: from the first pull inside a
	timed raid (Board.lua's run) or a level-60 dungeon (Dungeons.lua's run)
	to the last boss - the official time, the way the rankings count it.
	While it runs: the time, bosses down, and the pace to beat (your guild's
	best, the realm's #1). At the end: the final time and where it would rank
	on your realm's board if it were uploaded. It stays for 10 minutes after
	the last boss, while you're still inside.

	Drag it to move it. Right-click hides it (/wdi timer on brings it back).
----------------------------------------------------------------------]]

local W = WhoDidIt
local RT = {}
W.RunTimer = RT

local getn = table.getn
local floor = math.floor
local SHOW_AFTER = 600   -- seconds the final time stays up

local function on() return WhoDidItDB and WhoDidItDB.opts.runTimer ~= false end

local function clock(secs)
	secs = floor(secs or 0)
	if secs >= 3600 then
		return string.format("%d:%02d:%02d", floor(secs / 3600), floor(math.mod(secs, 3600) / 60), math.mod(secs, 60))
	end
	return string.format("%d:%02d", floor(secs / 60), math.mod(secs, 60))
end

-- what to show, or nil: { title, start, cs (final secs), n, of, kind, key }
local function current()
	local zone = GetRealZoneText()
	local B = W.Board
	-- a timed raid (both Karazhan towers say "Tower of Karazhan": the run knows which it is)
	if B and B.LastRun and (W.Data.clears[zone] or W.Data.sharedZones[zone]) then
		local r = B:LastRun()
		local need = r and W.Data.clears[r.zone]
		if need and (r.real or r.zone) == zone then
			local n = 0
			for i = 1, getn(need) do if r.kills[need[i]] then n = n + 1 end end
			return { title = W.Data.instanceTitle[r.zone] or r.zone, start = r.start, cs = r.cs, doneAt = r.doneAt,
				n = n, of = getn(need), kind = "clears", key = r.zone }
		end
		return nil
	end
	-- a dungeon
	local R = W.Runs
	if R and R.Current then
		local r = R:Current()
		if r and r.zone == zone then
			local n = 0
			for _ in pairs(r.k or {}) do n = n + 1 end
			local dg = r.key and W.Data.DUNGEON[r.key]
			return { title = dg and dg.title or zone, start = r.at, cs = r.cs, doneAt = r.cs and (r.at + r.cs),
				n = n, kind = "runs", key = r.key }
		end
	end
end

------------------------------------------------------------------ the window

local f
local function build()
	f = CreateFrame("Button", "WhoDidItRunTimer", UIParent)
	f:SetWidth(220)
	f:SetHeight(62)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:RegisterForClicks("RightButtonUp")
	if W.UI and W.UI.Flat and W.UI.COL then
		W.UI.Flat(f, W.UI.COL.panel, W.UI.COL.panelEdge)
	else
		f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
		f:SetBackdropColor(0, 0, 0, 0.8)
	end
	local pos = WhoDidItDB.opts.runTimerPos
	if pos then
		f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
	else
		f:SetPoint("TOP", UIParent, "TOP", 0, -120)
	end
	f:SetScript("OnDragStart", function() this:StartMoving() end)
	f:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
		local point, _, _, x, y = this:GetPoint()
		WhoDidItDB.opts.runTimerPos = { point or "TOP", floor((x or 0) + 0.5), floor((y or 0) + 0.5) }
	end)
	f:SetScript("OnClick", function()
		WhoDidItDB.opts.runTimer = false
		this:Hide()
		W.Print("Run timer hidden. |cffffd100/wdi timer on|r brings it back.")
	end)
	f:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Run timer", 1, 0.82, 0)
		GameTooltip:AddLine("The official time: from the first pull inside to the last boss,", 0.9, 0.9, 0.9)
		GameTooltip:AddLine("the way the rankings count it.", 0.9, 0.9, 0.9)
		GameTooltip:AddLine("Drag to move.  Right-click to hide (/wdi timer on).", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)

	local function text(font, size, point, x, y, justify)
		local fs = f:CreateFontString(nil, "OVERLAY")
		fs:SetFont(font, size, "OUTLINE")
		fs:SetPoint(point, f, point, x, y)
		fs:SetJustifyH(justify or "LEFT")
		return fs
	end
	local reg = W.UI and W.UI.FONT or "Fonts\\FRIZQT__.TTF"
	local bold = W.UI and W.UI.FONT_BOLD or "Fonts\\FRIZQT__.TTF"
	f.title = text(bold, 13, "TOPLEFT", 9, -7)
	f.count = text(bold, 13, "TOPRIGHT", -9, -7, "RIGHT")
	f.time = text(bold, 24, "LEFT", 8, -3)
	f.note = text(reg, 12, "BOTTOMLEFT", 9, 7)
	f.note:SetWidth(204)
	f:Hide()
end

-- the line under the time: the pace to beat, or where the final time ranks
local function noteFor(s, secs)
	local B = W.Board
	local realm = B and B.Realm()
	if s.kind == "clears" and B then
		if s.cs then
			local p2, of2 = B:WouldRank("clears", s.key, s.cs)
			if p2 and of2 > 0 then return "|cffffd100#" .. p2 .. " of " .. of2 .. "|r|cffaaaaaa on " .. realm .. " if uploaded|r" end
			return "|cffaaaaaaofficial clear time|r"
		end
		local parts = {}
		local guild = B.MyGuild()
		local g = guild and B:GuildBest(realm, "clears+", s.key, guild)
		if g then tinsert(parts, "|cff33ff33guild " .. clock(g.t) .. "|r") end
		local top = B:Board(realm, "clears+", s.key, "All")[1]
		if top then tinsert(parts, "|cffaaaaaa#1 " .. clock(top[2].t) .. "|r") end
		return table.concat(parts, "|cff666666  -  |r")
	elseif s.kind == "runs" and W.Runs then
		if s.cs and s.key then
			local place, of = W.Runs:Place(realm, s.key, s.cs)
			return "|cffffd100#" .. place .. " of " .. of .. "|r|cffaaaaaa on the 5-man board|r"
		end
		return "|cffaaaaaafirst pull to the last boss|r"
	end
	return ""
end

local last = -1
function RT.Update()
	if not WhoDidItDB then return end
	local s = on() and current()
	local now = time()
	if s and s.cs and s.doneAt and now - s.doneAt > SHOW_AFTER then s = nil end
	if not s then
		if f and f:IsShown() then f:Hide() end
		return
	end
	if not f then build() end
	local secs = s.cs or (now - (s.start or now))
	if not f:IsShown() then f:Show(); last = -1 end
	if secs == last and not s.cs then return end
	last = secs
	f.title:SetText("|cffffd100" .. s.title .. "|r")
	f.count:SetText(s.of and (((s.n >= s.of) and "|cff33ff33" or "|cffffffff") .. s.n .. "/" .. s.of .. "|r") or ("|cffffffff" .. s.n .. "|r|cffaaaaaa bosses|r"))
	f.time:SetText((s.cs and "|cff33ff33" or "|cffffffff") .. clock(secs) .. "|r" .. (s.cs and "  |cff33ff33done|r" or ""))
	f.note:SetText(noteFor(s, secs))
end
W:Every(0.25, RT.Update)

function RT:Slash(rest)
	if rest == "on" or rest == "off" then
		WhoDidItDB.opts.runTimer = (rest == "on")
	elseif rest == "reset" then
		WhoDidItDB.opts.runTimerPos = nil
		if f then f:ClearAllPoints(); f:SetPoint("TOP", UIParent, "TOP", 0, -120) end
	end
	W.Print("Run timer: " .. (on() and "|cff33ff33on|r - it shows in timed raids and level-60 dungeons while a run is on" or "|cffff9933off|r")
		.. "   |cff888888(/wdi timer on|off|reset)|r")
	RT.Update()
end
