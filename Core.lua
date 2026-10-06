--[[--------------------------------------------------------------------
	WhoDidIt - core: namespace, helpers, environment, roster, events,
	saved variables and slash commands
----------------------------------------------------------------------]]

WhoDidIt = {}
local W = WhoDidIt

W.version = GetAddOnMetadata("WhoDidIt", "Version") or "1.0.0"

-- WoW only reads an addon's file list at start-up, so files added by an
-- update stay missing after /reload until the game is restarted - except
-- with ClassicAPI (optional dll), where /reload picks up new files too
W.CAPI = (ClassicAPI ~= nil) or (CLASSIC_API_VERSION ~= nil)
W.RESTART_HINT = W.CAPI and "type /reload" or "exit WoW and start it again (a /reload isn't enough)"
W.RESTART_MSG = "|cffff5555WhoDidIt was updated with new files - " .. W.RESTART_HINT .. " to load them.|r"
W.env = {}

local floor = math.floor
local getn = table.getn

------------------------------------------------------------------ output / formatting

function W.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Who|cffffd100DidIt|r: " .. tostring(msg))
end

function W.FmtTime(s)
	s = floor(s or 0)
	if s < 0 then s = 0 end
	return string.format("%d:%02d", floor(s / 60), math.mod(s, 60))
end

function W.FmtNum(n)
	n = n or 0
	if n >= 1000000 then return string.format("%.2fM", n / 1000000) end
	if n >= 10000 then return string.format("%.1fk", n / 1000) end
	return tostring(floor(n + 0.5))
end

local FALLBACK_COLORS = {
	WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, ROGUE   = { r = 1.00, g = 0.96, b = 0.41 },
	MAGE    = { r = 0.41, g = 0.80, b = 0.94 }, WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
	HUNTER  = { r = 0.67, g = 0.83, b = 0.45 }, PRIEST  = { r = 1.00, g = 1.00, b = 1.00 },
	DRUID   = { r = 1.00, g = 0.49, b = 0.04 }, SHAMAN  = { r = 0.00, g = 0.44, b = 0.87 },
	PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
}

function W.ClassRGB(class)
	local c = (RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]) or (class and FALLBACK_COLORS[class])
	if not c then return 0.7, 0.7, 0.7 end
	return c.r, c.g, c.b
end

function W.CName(name, class)
	local r, g, b = W.ClassRGB(class)
	return string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, name or "?")
end

------------------------------------------------------------------ "type a value" popup

-- W:Prompt("Pack name", "Skull pack", function(text) ... end): one edit box, Enter or Accept saves
StaticPopupDialogs["WHODIDIT_PROMPT"] = {
	text = "%s",
	button1 = ACCEPT, button2 = CANCEL,
	hasEditBox = 1, maxLetters = 48,
	OnShow = function()
		W.popup = this
		local eb = getglobal(this:GetName() .. "EditBox")
		eb:SetText(W.prompt and W.prompt.default or "")
		eb:HighlightText()
		eb:SetFocus()
	end,
	OnAccept = function()
		local eb = W.popup and getglobal(W.popup:GetName() .. "EditBox")
		local p = W.prompt
		W.prompt = nil
		if eb and p then p.fn(eb:GetText()) end
	end,
	EditBoxOnEnterPressed = function()
		local p = W.prompt
		W.prompt = nil
		local text = this:GetText()
		this:GetParent():Hide()
		if p then p.fn(text) end
	end,
	EditBoxOnEscapePressed = function() this:GetParent():Hide() end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}

function W:Prompt(text, default, fn)
	W.prompt = { default = tostring(default or ""), fn = fn }
	StaticPopup_Show("WHODIDIT_PROMPT", text)
end

-- a link to copy: straight onto the clipboard with ClassicAPI, otherwise a
-- box with it selected for Ctrl+C
function W:CopyLink(what, url)
	if CopyToClipboard and pcall(CopyToClipboard, url) then
		W.Print(what .. " link copied - paste it with Ctrl+V: |cffffd100" .. url .. "|r")
		return
	end
	W:Prompt(what .. "\n|cffffd100" .. url .. "|r\n|cff888888Press Ctrl+C to copy the link, then Esc.|r", url, function() end)
end

------------------------------------------------------------------ environment

function W:DetectEnv()
	local e = W.env
	e.superwow = (SUPERWOW_VERSION ~= nil) or (SpellInfo ~= nil)
	e.nampower = (GetNampowerVersion ~= nil)
	e.unitxp   = (UnitXP ~= nil)
	e.twthreat = IsAddOnLoaded("TWThreat") and true or false
	e.unitdata = (GetUnitData ~= nil)
	-- ClassicAPI (optional dll): newer WoW API added to the 1.12 client
	e.classicapi = W.CAPI
	e.capiAuras = W.CAPI and C_UnitAuras ~= nil and C_UnitAuras.GetUnitAuras ~= nil
end

-- Nampower only raises some events when these CVars are on
local NP_CVARS = { "NP_EnableAutoAttackEvents", "NP_EnableSpellHealEvents", "NP_EnableSpellGoEvents" }

function W:EnableNampowerEvents()
	if not W.env.nampower then return end
	for i = 1, getn(NP_CVARS) do
		pcall(SetCVar, NP_CVARS[i], "1")
	end
end

------------------------------------------------------------------ guids, names, spells

local NULL_GUID = "0x0000000000000000"

function W.Guid(unit)
	if not W.env.superwow or not unit then return nil end
	local exists, guid = UnitExists(unit)
	if exists and guid and guid ~= NULL_GUID then return guid end
	return nil
end

local spellCache = {}
function W.SpellName(id)
	id = tonumber(id)
	if not id or id <= 0 then return "Unknown" end
	local n = spellCache[id]
	if n then return n end
	if SpellInfo then
		local ok, v = pcall(SpellInfo, id)
		if ok then n = v end
	end
	if (not n or n == "") and GetSpellRecField then
		local ok, v = pcall(GetSpellRecField, id, "name")
		if ok then n = v end
	end
	if not n or n == "" then n = "Spell #" .. id end
	spellCache[id] = n
	return n
end

local nameCache = {}
function W.GuidName(guid)
	if not guid then return "Unknown" end
	local r = W.roster.byGuid[guid]
	if r then return r.name end
	local n = nameCache[guid]
	if n then return n end
	n = UnitName(guid)
	if n and n ~= "" and n ~= UNKNOWNOBJECT then
		nameCache[guid] = n
		return n
	end
	return "Unknown"
end

------------------------------------------------------------------ roster

W.roster = { byGuid = {}, byName = {}, pets = {}, n = 0 }
local ownerCache = {}

function W:UpdateRoster()
	local R = { byGuid = {}, byName = {}, pets = {}, n = 0 }
	local function add(unit, petUnit)
		if not UnitExists(unit) then return end
		local name = UnitName(unit)
		if not name or name == UNKNOWNOBJECT then return end
		local _, class = UnitClass(unit)
		local e = { name = name, class = class or "WARRIOR", unit = unit, guid = W.Guid(unit) }
		R.byName[name] = e
		if e.guid then R.byGuid[e.guid] = e end
		R.n = R.n + 1
		local pg = W.Guid(petUnit)
		if pg then R.pets[pg] = name end
	end
	local nr = GetNumRaidMembers()
	if nr > 0 then
		for i = 1, nr do add("raid" .. i, "raidpet" .. i) end
	else
		add("player", "pet")
		for i = 1, GetNumPartyMembers() do add("party" .. i, "partypet" .. i) end
	end
	W.roster = R
	ownerCache = {}
end

-- Returns the raid member a guid belongs to (the player, or the owner of a
-- pet/totem/guardian) and whether it was a pet. nil for everything else.
function W.Owner(guid)
	if not guid or guid == NULL_GUID then return nil end
	local R = W.roster
	local e = R.byGuid[guid]
	if e then return e.name, false end
	local o = R.pets[guid]
	if o then return o, true end
	local c = ownerCache[guid]
	if c == nil then
		c = false
		if W.env.superwow then
			local ok, ex, og = pcall(UnitExists, guid .. "owner")
			if ok and ex and og then
				local oe = R.byGuid[og]
				if oe then c = oe.name end
			end
		end
		ownerCache[guid] = c
	end
	if c then return c, true end
	return nil
end

function W.ResetCaches()
	ownerCache = {}
end

------------------------------------------------------------------ event bus / timers

local frame = CreateFrame("Frame", "WhoDidItEventFrame")
W.frame = frame
local handlers = {}

function W:On(ev, fn)
	if not handlers[ev] then
		handlers[ev] = {}
		pcall(frame.RegisterEvent, frame, ev)
	end
	tinsert(handlers[ev], fn)
end

frame:SetScript("OnEvent", function()
	local list = handlers[event]
	if not list then return end
	for i = 1, getn(list) do
		list[i](arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
	end
end)

local tickers = {}
function W:Every(interval, fn)
	tinsert(tickers, { i = interval, f = fn, a = 0 })
end

frame:SetScript("OnUpdate", function()
	local e = arg1
	for i = 1, getn(tickers) do
		local t = tickers[i]
		t.a = t.a + e
		if t.a >= t.i then
			t.a = 0
			t.f()
		end
	end
end)

------------------------------------------------------------------ saved variables

local DEFAULTS = {
	maxFights   = 25,
	trackTrash  = false,
	announce    = "self",   -- self / channel (the shout channel) / off
	queryThreat = true,     -- ask the server for threat when TWThreat isn't loaded
	minDuration = 8,
	shoutChannel = "RAID",  -- designated channel for reports & shout-outs ("#name" = custom channel)
	autoShout   = "off",    -- off / smart (shame wipes, praise kills) / shame / praise / both
	chatColors  = true,     -- colour names, times and numbers in posted messages
	shareBoard  = true,     -- share guild kill/clear records with WhoDidIt users on the realm
	chronStartOnPull = true,  -- start Chronicle logging when a boss is pulled
	chronSaveOnFight = true,  -- save the Chronicle log after every boss fight
	banterKills  = true,    -- fun line in the shout channel after every boss kill
	banterClears = true,    -- ...and after every full clear
	rivalAlerts  = true,    -- post the rival watch when the raid enters an instance
	readyCheckScan = true,  -- consume check (your chat only) on every ready check
}

W:On("ADDON_LOADED", function(name)
	if name ~= "WhoDidIt" then return end
	if type(WhoDidItDB) ~= "table" then WhoDidItDB = {} end
	local db = WhoDidItDB
	db.fights = db.fights or {}
	db.tanks  = db.tanks or {}
	db.avoid  = db.avoid or {}
	db.opts   = db.opts or {}
	for k, v in pairs(DEFAULTS) do
		if db.opts[k] == nil then db.opts[k] = v end
	end
	-- "raid" announce used to ignore the shout channel; it now follows it
	if db.opts.announce == "raid" then db.opts.announce = "channel" end
	-- colours used to switch off for every chat after one missed line; now it's
	-- per chat (opts.plainKinds), so turn them back on once
	-- (2: the first per-chat check wrongly turned guild chat plain)
	if (db.opts.colorsPerChat or 0) ~= 2 then
		db.opts.colorsPerChat = 2
		db.opts.chatColors = true
		db.opts.plainKinds = {}
	end
end)

W:On("PLAYER_ENTERING_WORLD", function()
	W:DetectEnv()
	W:EnableNampowerEvents()
	W:UpdateRoster()
	-- one friendly tip per account about the optional ClassicAPI
	local o = WhoDidItDB and WhoDidItDB.opts
	if o and not W.env.classicapi and not o.capiTipped then
		o.capiTipped = true
		W.Print("Tip: the free, optional |cffffd100ClassicAPI|r add-on makes WhoDidIt quicker and adds a few extras. Type |cffffd100/wdi classicapi|r to see what it does and how to get it.")
	end
end)

W:On("RAID_ROSTER_UPDATE", function() W:UpdateRoster() end)
W:On("PARTY_MEMBERS_CHANGED", function() W:UpdateRoster() end)
W:On("UNIT_PET", function() W:UpdateRoster() end)

W:DetectEnv()

------------------------------------------------------------------ saving / announcing fights

function W:SaveFight(rec)
	local db = WhoDidItDB
	tinsert(db.fights, 1, rec)
	while getn(db.fights) > (db.opts.maxFights or 25) do tremove(db.fights) end

	local mode = db.opts.announce
	if mode ~= "off" then
		local lines = W.Analyzer:ReportLines(rec, 3)
		-- automatic posts for demo fights stay in your own chat
		W:Send(lines, (mode == "channel" and not rec.demo) and nil or "SELF", W.Shout.ClassMap(rec))
		W.Print("Type |cffffd100/wdi|r for the full breakdown.")
	end
	W.Shout:Auto(rec)
	-- (missing until the game is restarted after an update adds new files)
	if W.Board then W.Board:OnFight(rec) end
	if W.Logs then W.Logs:OnFightEnd(rec) end
	if W.UI then W.UI:OnFightEnd() end
end

-- channel: nil = the designated shout channel
function W:Report(rec, channel)
	if not rec then W.Print("Nothing to report.") return end
	W:Send(W.Analyzer:ReportLines(rec, 5), channel, W.Shout.ClassMap(rec))
end

------------------------------------------------------------------ slash commands

local function trim(s)
	local _, _, v = string.find(s or "", "^%s*(.-)%s*$")
	return v or ""
end

local function setToList(t)
	local l = {}
	for k in pairs(t) do tinsert(l, k) end
	table.sort(l)
	return table.concat(l, ", ")
end

------------------------------------------------------------------ ClassicAPI (optional)

-- ClassicAPI (github.com/brues-code/ClassicAPI) is an optional client dll.
-- WhoDidIt works the same without it; with it these get better. Every use
-- checks W.env first and falls back to the plain 1.12 way.
W.CAPI_URL = "https://github.com/brues-code/ClassicAPI"
W.CAPI_PERKS = {
	"Copy link buttons put the link straight on your clipboard (no Ctrl+C box).",
	"Consume checks read each raider's buffs in one go - quicker ready checks and pull snapshots.",
	"Ready checks also warn when someone's flask, elixir or food runs out in under 5 minutes.",
	"WhoDidIt updates load with /reload - no full game restart.",
}

function W:ClassicApiInfo()
	local add = function(s) DEFAULT_CHAT_FRAME:AddMessage(s) end
	if W.env.classicapi then
		W.Print("ClassicAPI " .. (CLASSIC_API_VERSION and ("v" .. tostring(CLASSIC_API_VERSION) .. " ") or "") .. "is installed. What it adds to WhoDidIt:")
	else
		W.Print("ClassicAPI isn't installed. It's |cffffd100optional|r - WhoDidIt works fine without it. With it:")
	end
	for i = 1, getn(W.CAPI_PERKS) do add("  |cff33ff33+|r " .. W.CAPI_PERKS[i]) end
	if not W.env.classicapi then
		add("  |cffffd100To get it:|r exit WoW, then double-click |cffffd100Interface\\AddOns\\WhoDidIt\\tools\\Install-ClassicAPI.cmd|r")
		add("  |cff888888It downloads ClassicAPI.dll from " .. W.CAPI_URL .. ", checks it, copies it into your WoW folder and adds it to dlls.txt (backed up first). Then start WoW as usual. It needs VanillaFixes, which most Turtle / OctoWoW launchers already use.|r")
	end
end

local function help()
	W.Print("v" .. W.version .. " commands:")
	local c = "|cffffd100"
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi|r - open / close the window")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi tank <name>|r, " .. c .. "/wdi untank <name>|r, " .. c .. "/wdi tanks|r - main tank list (tanks aren't blamed for boss aggro)")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi avoid <spell>|r, " .. c .. "/wdi unavoid <spell>|r, " .. c .. "/wdi avoids|r - your own 'don't stand in it' spells")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi report|r - post the latest fight summary to the shout channel")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi shame [name]|r - Name & Shame the worst offenders (or one player)")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi bigup [name]|r - Big up the best performers (or one player)")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi channel raid|rw|party|guild|officer|say|yell|self|<custom channel>|r - designated shout channel")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi colors on|off|r - coloured names, times and numbers in posted messages")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi autoshout off|smart|shame|praise|both|r - shout automatically after fights (smart = shame wipes, praise kills)")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi announce self|channel|off|r - post a summary after each fight (channel = the shout channel)")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi trash on|off|r - also track elite trash pulls")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi threat on|off|r - query server threat when TWThreat isn't loaded")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi rankings|r - kill times & clears,  " .. c .. "/wdi share on|off|r - share them with WhoDidIt users on your realm")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi banter kills|clears [on|off]|r - fun kill / clear time announcements,  " .. c .. "/wdi banter test|r - preview one")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi logs|r - Chronicle log controls,  " .. c .. "/wdi log start|stop|save|r")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi loot|r - master looting with RollFor (built in): soft-res, rolls, winners and a step-by-step guide")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi check|r - who's missing consumables for their role right now (" .. c .. "/wdi check post|r to post it),  " .. c .. "/wdi readycheck on|off|r - run it on every ready check")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi aml|r - auto master looting on/off (or the Auto-loot button),  " .. c .. "/wdi aml to <name>|r,  " .. c .. "/wdi aml backup <name>|r,  " .. c .. "/wdi aml list|r")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi marks|r - auto marking: saved packs and quick save,  " .. c .. "/wdi mark|r - mark the pack under your mouse,  " .. c .. "/wdi marks help|r - all marking commands")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi demo|r - add two sample fights to try every feature, " .. c .. "/wdi demo live|r - watch one play out live, " .. c .. "/wdi demo clear|r")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi start|r / " .. c .. "/wdi stop|r - manually track your target / end tracking")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi status|r, " .. c .. "/wdi clear|r")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi classicapi|r - what the optional ClassicAPI add-on improves, and how to get it")
end

local function status()
	local e = W.env
	local function yn(v) return v and "|cff33ff33yes|r" or "|cffff3333no|r" end
	W.Print("v" .. W.version)
	DEFAULT_CHAT_FRAME:AddMessage("  Nampower: " .. yn(e.nampower) .. "   SuperWoW: " .. yn(e.superwow) .. "   UnitXP: " .. yn(e.unitxp) .. "   TWThreat: " .. yn(e.twthreat)
		.. "   ClassicAPI: " .. yn(e.classicapi) .. " |cff888888(optional)|r")
	if not e.classicapi then DEFAULT_CHAT_FRAME:AddMessage("  |cff888888ClassicAPI is optional - /wdi classicapi shows what it adds and how to get it.|r") end
	if not e.nampower then DEFAULT_CHAT_FRAME:AddMessage("  |cffff9933Without Nampower only deaths are tracked.|r") end
	if not e.superwow then DEFAULT_CHAT_FRAME:AddMessage("  |cffff9933Without SuperWoW, GUIDs can't be resolved - most tracking is disabled.|r") end
	local f = W.Tracker.fight
	DEFAULT_CHAT_FRAME:AddMessage("  Tracking: " .. (f and ("|cff33ccff" .. f.enc .. "|r") or "idle") .. "   Saved fights: " .. getn(WhoDidItDB.fights))
	DEFAULT_CHAT_FRAME:AddMessage("  Tanks: " .. (next(WhoDidItDB.tanks) and setToList(WhoDidItDB.tanks) or "auto-detect only"))
	DEFAULT_CHAT_FRAME:AddMessage("  Shout channel: " .. W.Shout:ChannelLabel() .. "   Auto shout-outs: " .. WhoDidItDB.opts.autoShout)
end

local function slash(msg)
	msg = trim(msg)
	local _, _, cmd, rest = string.find(msg, "^(%S*)%s*(.-)$")
	cmd = strlower(cmd or "")
	rest = trim(rest)
	local db = WhoDidItDB

	if cmd == "" then
		W.UI:Toggle()
	elseif cmd == "help" or cmd == "?" then
		help()
	elseif cmd == "status" then
		status()
	elseif cmd == "classicapi" or cmd == "capi" then
		W:ClassicApiInfo()
	elseif cmd == "tank" then
		if rest == "" then rest = UnitName("target") or "" end
		if rest == "" then W.Print("Usage: /wdi tank <name> (or target them)") return end
		db.tanks[rest] = true
		W.Print(rest .. " added as a tank.")
	elseif cmd == "untank" then
		if rest == "" then rest = UnitName("target") or "" end
		db.tanks[rest] = nil
		W.Print(rest .. " removed from tanks.")
	elseif cmd == "tanks" then
		if rest == "clear" then db.tanks = {} end
		W.Print("Tanks: " .. (next(db.tanks) and setToList(db.tanks) or "none set (auto-detect)"))
	elseif cmd == "avoid" then
		if rest == "" then W.Print("Usage: /wdi avoid <exact spell name>") return end
		db.avoid[rest] = true
		W.Print("'" .. rest .. "' now counts as avoidable damage.")
	elseif cmd == "unavoid" then
		db.avoid[rest] = nil
		W.Print("'" .. rest .. "' removed.")
	elseif cmd == "avoids" then
		W.Print("Custom avoidable spells: " .. (next(db.avoid) and setToList(db.avoid) or "none"))
	elseif cmd == "report" then
		W:Report(db.fights[1])
	elseif cmd == "shame" then
		W.Shout:Shame(db.fights[1], rest)
	elseif cmd == "bigup" or cmd == "praise" then
		W.Shout:Praise(db.fights[1], rest)
	elseif cmd == "channel" then
		W.Shout:SetChannel(rest)
		W.Print("Shout channel: " .. W.Shout:ChannelLabel())
		W.UI:Refresh()
	elseif cmd == "colors" or cmd == "colours" then
		if rest == "on" or rest == "off" then
			db.opts.chatColors = (rest == "on")
			if rest == "on" then db.opts.plainKinds = {} end   -- try every chat again
		end
		local plain = {}
		for k in pairs(db.opts.plainKinds or {}) do tinsert(plain, W.Shout.LABELS[k] or k) end
		W.Print("Coloured chat posts: " .. (db.opts.chatColors and "on" or "off")
			.. ((db.opts.chatColors and getn(plain) > 0) and (" (plain text in: " .. table.concat(plain, ", ") .. ")") or ""))
	elseif cmd == "autoshout" then
		if rest == "off" or rest == "smart" or rest == "shame" or rest == "praise" or rest == "both" then
			db.opts.autoShout = rest
		end
		W.Print("Auto shout-outs: " .. db.opts.autoShout)
		W.UI:Refresh()
	elseif cmd == "announce" then
		if rest == "raid" then rest = "channel" end
		if rest == "self" or rest == "channel" or rest == "off" then db.opts.announce = rest end
		W.Print("Announce after fights: " .. db.opts.announce)
	elseif cmd == "trash" then
		db.opts.trackTrash = (rest == "on")
		W.Print("Trash tracking: " .. (db.opts.trackTrash and "on" or "off"))
	elseif cmd == "threat" then
		db.opts.queryThreat = (rest ~= "off")
		W.Print("Threat queries: " .. (db.opts.queryThreat and "on" or "off"))
	elseif (cmd == "log" or cmd == "share" or cmd == "banter") and not (W.Board and W.Logs) then
		W.Print(W.RESTART_MSG)
	elseif cmd == "banter" then
		local _, _, what, onoff = string.find(rest, "^(%a+)%s*(%a*)$")
		if what == "test" then
			W.Board:BanterTest()
		elseif what == "kills" or what == "clears" then
			local key = (what == "kills") and "banterKills" or "banterClears"
			if onoff == "on" or onoff == "off" then db.opts[key] = (onoff == "on") else db.opts[key] = not db.opts[key] end
			W.Print("Banter after " .. (what == "kills" and "boss kills" or "full clears") .. ": " .. (db.opts[key] and "on" or "off") .. " (posts to " .. W.Shout:ChannelLabel() .. ")")
		else
			W.Print("Usage: /wdi banter kills|clears [on|off]  or  /wdi banter test")
		end
	elseif cmd == "check" then
		if not W.Cons then W.Print(W.RESTART_MSG) return end
		W.Cons:Check(rest == "post")
	elseif cmd == "readycheck" then
		db.opts.readyCheckScan = (rest ~= "off")
		W.Print("Consume check on every ready check: " .. (db.opts.readyCheckScan and "on" or "off") .. " (only you see it)")
	elseif cmd == "aml" or cmd == "automl" then
		if not W.AutoML then W.Print(W.RESTART_MSG) return end
		W.AutoML:Slash(rest)
	elseif cmd == "loot" or cmd == "ml" then
		if not W.Loot then W.Print(W.RESTART_MSG) return end
		W.UI:SetMode("loot")
	elseif (cmd == "marks" or cmd == "mark") and not W.Marks then
		W.Print(W.RESTART_MSG)
	elseif cmd == "marks" then
		W.Marks:Slash(rest)
	elseif cmd == "mark" then
		W.Marks:MarkGroup()
	elseif cmd == "rankings" or cmd == "ranks" then
		W.UI:SetMode("rankings")
	elseif cmd == "logs" then
		W.UI:SetMode("logs")
	elseif cmd == "log" then
		if rest == "start" then W.Logs:Start()
		elseif rest == "stop" then W.Logs:Stop()
		elseif rest == "save" then W.Logs:Save()
		else W.Print("Usage: /wdi log start|stop|save") end
	elseif cmd == "share" then
		db.opts.shareBoard = (rest ~= "off")
		if db.opts.shareBoard then W.Board:Join() else W.Board:Leave() end
		W.Print("Sharing kill times with WhoDidIt users on this realm: " .. (db.opts.shareBoard and "on" or "off"))
	elseif cmd == "demo" or cmd == "test" then
		W.Demo:Run(rest)
	elseif cmd == "start" then
		W.Tracker:ManualStart()
	elseif cmd == "stop" then
		W.Tracker:ManualStop()
	elseif cmd == "clear" then
		db.fights = {}
		W.Print("All saved fights deleted.")
		W.UI:OnFightEnd()
	else
		help()
	end
end

SLASH_WHODIDIT1 = "/whodidit"
SLASH_WHODIDIT2 = "/wdi"
SlashCmdList["WHODIDIT"] = slash
