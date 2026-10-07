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

-- a fresh random sequence each login, so clients don't all wait the same time
-- before asking on the channel and award titles don't repeat in the same order
if math.randomseed then pcall(math.randomseed, time() + floor(math.mod(GetTime() * 1000, 100000))) end

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

-- an error in one handler is reported once and the others still run
-- (in a raid, combat events arrive hundreds of times a second)
local seenErr, nSeen = {}, 0
function W:Oops(where, err)
	err = tostring(err)
	-- keyed by where + the start of the message, so an error with a changing
	-- number or name in it counts once; and never more than 50 kept
	local key = tostring(where) .. ":" .. string.sub(err, 1, 60)
	if seenErr[key] then return end
	if nSeen >= 50 then return end
	seenErr[key] = true
	nSeen = nSeen + 1
	W.Print("|cffff5555error|r in " .. tostring(where) .. ": " .. err .. "  |cff888888(saved for bug reports: /wdi errors)|r")
	if not WhoDidItDB then return end
	WhoDidItDB.errors = WhoDidItDB.errors or {}
	tinsert(WhoDidItDB.errors, 1, date("%m-%d %H:%M ") .. tostring(where) .. ": " .. err)
	while getn(WhoDidItDB.errors) > 20 do tremove(WhoDidItDB.errors) end
end

frame:SetScript("OnEvent", function()
	local list = handlers[event]
	if not list then return end
	for i = 1, getn(list) do
		local ok, err = pcall(list[i], arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
		if not ok then W:Oops(event, err) end
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
			local ok, err = pcall(t.f)
			if not ok then W:Oops("timer", err) end
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
	banterKills  = false,   -- fun line in the shout channel after every boss kill (the raid leader switches it on)
	banterClears = false,   -- ...and after every full clear
	rivalAlerts  = false,   -- show the rival watch in your own chat when the raid enters an instance
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
	-- (2: the first per-chat check wrongly turned guild chat plain;
	--  3: a line the server dropped for spam wrongly turned say chat plain)
	if (db.opts.colorsPerChat or 0) ~= 3 then
		db.opts.colorsPerChat = 3
		db.opts.chatColors = true
		db.opts.plainKinds = {}
	end
	-- banter used to be on out of the box: ask once whether to keep it
	if not db.opts.chatAsked then
		db.opts.chatAsked = true
		if db.opts.banterKills or db.opts.banterClears then W.askBanter = true end
		db.opts.rivalAlerts = false   -- now only ever shown in your own chat; on again from Rankings
	end
end)

StaticPopupDialogs["WHODIDIT_BANTER"] = {
	text = "WhoDidIt can post a fun line about your kill and clear times in raid chat (Kill / Clear banter).\n\nKeep that on? Most raids leave it to the raid leader.",
	button1 = "Keep on", button2 = "Turn off",
	OnCancel = function()
		WhoDidItDB.opts.banterKills = false
		WhoDidItDB.opts.banterClears = false
		W.Print("Banter is off. The raid leader can switch it on in Rankings (bottom left).")
	end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}
W:Every(10, function()
	if W.askBanter then
		W.askBanter = nil
		StaticPopup_Show("WHODIDIT_BANTER")
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

-- the parts that ship in the WhoDidIt folder: missing only if files were lost
-- (raid times aren't here: they come in game from the master feed)
function W.MissingExtras()
	local miss = {}
	if W.Marks and not W.Marks.dataInfo then tinsert(miss, "the Auto Marker's raid packs") end
	if not WDI_CHRON_VERSION then tinsert(miss, "the Chronicle logger") end
	if not WDI_ROLLFOR_VERSION then tinsert(miss, "RollFor") end
	if not WDI_DOPING_VERSION then tinsert(miss, "DopingControl") end
	return miss
end
W.SYNC_HOWTO = "download WhoDidIt again and replace the WhoDidIt folder (they're part of it)"

-- first run: say what's missing and how to get it, once a session
local extrasTold
W:Every(12, function()
	if extrasTold or not WhoDidItDB then return end
	extrasTold = true
	local miss = W.MissingExtras()
	if getn(miss) == 0 then return end
	W.Print("|cffff9933Missing from your WhoDidIt folder:|r " .. table.concat(miss, ", ") .. ". To fix it, " .. W.SYNC_HOWTO
		.. ", then " .. W.RESTART_HINT .. ".")
end)

W:On("RAID_ROSTER_UPDATE", function() W:UpdateRoster() end)
W:On("PARTY_MEMBERS_CHANGED", function() W:UpdateRoster() end)
W:On("UNIT_PET", function() W:UpdateRoster() end)

W:DetectEnv()

------------------------------------------------------------------ crash backup
-- WoW writes addon data to disk only at logout or /reload, so a crash loses
-- everything since: a whole raid. So after each change to the fights or the
-- Hall of Fame tally (checked every 20 seconds, written out of combat only)
-- WhoDidIt also writes them to its own file in CustomData through Nampower.
-- At login, a backup newer than what WoW saved means the game crashed: the
-- backup is put back. Each account has its own file (several accounts can
-- share a PC); WoW's own save keeps the matching number, so normally nothing
-- is restored.
local BACKUP_EVERY = 20

-- a Lua table constructor for v (strings, numbers, booleans, tables)
local function ser(v, out, depth)
	local t = type(v)
	if t == "string" then tinsert(out, string.format("%q", v))
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then tinsert(out, "0") else tinsert(out, tostring(v)) end
	elseif t == "boolean" then tinsert(out, v and "true" or "false")
	elseif t == "table" and depth < 30 then
		tinsert(out, "{")
		for k, x in pairs(v) do
			local kt, xt = type(k), type(x)
			if (kt == "string" or kt == "number") and (xt == "string" or xt == "number" or xt == "boolean" or xt == "table") then
				tinsert(out, "[")
				ser(k, out, depth + 1)
				tinsert(out, "]=")
				ser(x, out, depth + 1)
				tinsert(out, ",")
			end
		end
		tinsert(out, "}")
	else tinsert(out, "nil") end
end

local function backupFile(db) return "WhoDidIt_Backup_" .. db.backupId .. ".txt" end

-- what's worth a backup changed? (fights saved or deleted, the tally)
local function backupKey(db)
	local f = db.fights or {}
	local first, last = f[1], f[getn(f)]
	local function key(r) return r and (tostring(r.date) .. tostring(r.enc) .. tostring(r.dur)) or "-" end
	return getn(f) .. "|" .. key(first) .. "|" .. key(last) .. "|" .. tostring(db.career and db.career.fights)
		.. "|" .. tostring(db.careerTest and db.careerTest.fights)
end

local lastBackup
function W:Backup(force)
	local db = WhoDidItDB
	if not db or not WriteCustomFile then return end
	if not db.backupId then
		-- the account name WoW remembers (so even a crash in the first session can be undone), else a random id
		local acct = string.gsub(strlower(GetCVar and GetCVar("accountName") or ""), "[^%w]", "")
		db.backupId = (acct ~= "") and acct or string.format("%08x", math.random(1, 2147483646))
	end
	local k = backupKey(db)
	if not force and k == lastBackup then return end
	db.backupSeq = (db.backupSeq or 0) + 1
	-- each fight (and each other part) in a function of its own: Lua 5.0 allows
	-- about 262,000 different constants per function, and 25 fights could pass that
	local out = { "return { seq = " .. db.backupSeq .. ", at = " .. time() .. ", fights = {" }
	for i = 1, getn(db.fights or {}) do
		tinsert(out, "(function() return ")
		ser(db.fights[i], out, 0)
		tinsert(out, " end)(),")
	end
	tinsert(out, "}")
	for _, part in ipairs({ "career", "careerTest", "board" }) do
		if type(db[part]) == "table" then
			tinsert(out, ", " .. part .. " = (function() return ")
			ser(db[part], out, 0)
			tinsert(out, " end)()")
		end
	end
	tinsert(out, " }")
	local ok = pcall(WriteCustomFile, backupFile(db), table.concat(out), "w")
	if ok then lastBackup = k end
end

-- at login: put back what a crash lost
W:On("ADDON_LOADED", function(name)
	if name ~= "WhoDidIt" then return end
	local db = WhoDidItDB
	if not db or not ReadCustomFile then return end
	if not db.backupId then
		local acct = string.gsub(strlower(GetCVar and GetCVar("accountName") or ""), "[^%w]", "")
		if acct == "" then return end
		db.backupId = acct
	end
	local ok, text = pcall(ReadCustomFile, backupFile(db))
	if not ok or type(text) ~= "string" or text == "" then return end
	local fn = loadstring(text)
	if not fn then return end
	setfenv(fn, {})   -- data only: the file can't reach anything
	local ok2, data = pcall(fn)
	if not ok2 or type(data) ~= "table" or type(data.fights) ~= "table" then return end
	if (tonumber(data.seq) or 0) <= (db.backupSeq or 0) then return end   -- WoW saved normally
	local lost = getn(data.fights) - getn(db.fights)
	db.fights = data.fights
	db.career, db.careerTest = data.career, data.careerTest
	if type(data.board) == "table" then db.board = data.board end
	db.backupSeq = data.seq
	lastBackup = backupKey(db)
	W.restoredNote = "WoW didn't save last time (it crashed), so your fights and Hall of Fame were put back from WhoDidIt's backup ("
		.. date("%d %b %H:%M", data.at or time()) .. ")" .. ((lost > 0) and (": " .. lost .. " fight" .. ((lost == 1) and "" or "s") .. " recovered") or "") .. "."
end)
W:On("PLAYER_ENTERING_WORLD", function()
	if W.restoredNote then W.Print("|cff33ff33" .. W.restoredNote .. "|r") W.restoredNote = nil end
end)
W:Every(BACKUP_EVERY, function()
	if UnitAffectingCombat("player") then return end
	W:Backup()
end)

------------------------------------------------------------------ other addons: ask first

-- Switching off an addon someone installed is their decision. When WhoDidIt
-- has its own copy of something that's also installed separately, it asks
-- once per addon (one question at a time). Yes: the separate one is switched
-- off from the next login. No: both stay, and WhoDidIt's copy stands by.
W.handoverQueue = {}
StaticPopupDialogs["WHODIDIT_HANDOVER"] = {
	text = "%s",
	button1 = YES, button2 = NO,
	OnAccept = function()
		local h = W.handoverNow
		W.handoverNow = nil
		if not h then return end
		DisableAddOn(h.addon)
		if h.yes then h.yes() end
		W.Print("The separate |cffffd100" .. h.addon .. "|r addon is switched off from your next login (/reload). WhoDidIt's copy takes over then.")
	end,
	OnCancel = function()
		local h = W.handoverNow
		W.handoverNow = nil
		if not h then return end
		WhoDidItDB.opts.keepSeparate = WhoDidItDB.opts.keepSeparate or {}
		WhoDidItDB.opts.keepSeparate[h.addon] = true
		W.Print("Keeping the separate |cffffd100" .. h.addon .. "|r addon; WhoDidIt's copy stands by. (/wdi handover " .. h.addon .. " asks again.)")
	end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}
-- addon: its folder name; what: what WhoDidIt does instead; yes: run after "Yes"
function W:AskHandover(addon, what, yes)
	local keep = WhoDidItDB and WhoDidItDB.opts.keepSeparate
	if keep and keep[addon] then return end
	for i = 1, getn(W.handoverQueue) do if W.handoverQueue[i].addon == addon then return end end
	tinsert(W.handoverQueue, { addon = addon, what = what, yes = yes })
end
-- did the player choose to keep the separate addon?
function W:KeepsSeparate(addon)
	local keep = WhoDidItDB and WhoDidItDB.opts.keepSeparate
	return keep and keep[addon] and IsAddOnLoaded(addon) and true or false
end
W:Every(3, function()
	if W.handoverNow or getn(W.handoverQueue) == 0 or UnitAffectingCombat("player") then return end
	local h = tremove(W.handoverQueue, 1)
	W.handoverNow = h
	StaticPopup_Show("WHODIDIT_HANDOVER", "WhoDidIt has " .. h.what .. " built in.\n\nSwitch the separate |cffffd100" .. h.addon
		.. "|r addon off from your next login?\n\n|cff888888No keeps it: it carries on as now and WhoDidIt's copy stands by.|r")
end)

------------------------------------------------------------------ posting other people's text

-- Lines with names other people chose (other guilds' names from Chronicle
-- or the WDIBoard channel) are never posted by themselves: the exact text is
-- shown first and only goes out when you click Post. Anyone can upload a log
-- under any guild name, and whatever WhoDidIt posts is said in your name.
StaticPopupDialogs["WHODIDIT_CONFIRMPOST"] = {
	text = "Post this to %s?\n\n%s",
	button1 = "Post", button2 = CANCEL,
	OnAccept = function()
		local p = W.pendingPost
		W.pendingPost = nil
		if p then W:Send(p.lines, p.channel, p.colours) end
	end,
	OnCancel = function() W.pendingPost = nil end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}
function W:ConfirmSend(lines, channel, colours)
	if channel == "SELF" then W:Send(lines, channel, colours) return end
	local plain = {}
	for i = 1, getn(lines) do
		local s = string.gsub(string.gsub(lines[i], "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
		tinsert(plain, s)
	end
	local text = table.concat(plain, "\n")
	if string.len(text) > 600 then text = string.sub(text, 1, 600) .. " ..." end
	W.pendingPost = { lines = lines, channel = channel, colours = colours }
	StaticPopup_Show("WHODIDIT_CONFIRMPOST", (W.Shout and W.Shout.ChannelLabel and W.Shout:ChannelLabel()) or "chat", text)
end

------------------------------------------------------------------ saving / announcing fights

function W:SaveFight(rec)
	local db = WhoDidItDB
	tinsert(db.fights, 1, rec)
	-- an older fight selected in the window: it moved down one place
	-- (1 means "the newest": with the window closed it follows the new fight, with it
	-- open the fight being read stays on screen; 0 is the live view)
	local shown = W.UI and W.UI.frame and W.UI.frame:IsVisible()
	if W.UI and W.UI.selIdx and (W.UI.selIdx > 1 or (W.UI.selIdx == 1 and shown)) then W.UI.selIdx = W.UI.selIdx + 1 end
	-- over the limit: drop the oldest demo fight first, so the demo never costs real fights
	while getn(db.fights) > (db.opts.maxFights or 25) do
		local drop = getn(db.fights)
		for i = getn(db.fights), 1, -1 do
			if db.fights[i].demo then drop = i; break end
		end
		tremove(db.fights, drop)
	end
	if W.UI and W.UI.selIdx and W.UI.selIdx > getn(db.fights) then W.UI.selIdx = getn(db.fights) end
	-- the all-time Hall of Fame tally (missing until a restart after the update)
	if W.Career then W.Career:Add(rec) end

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
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi fame|r - Hall of Fame: the biggest heroes and the Hall of Shame over every fight, best plays and worst blunders")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi rankings|r - kill times & clears,  " .. c .. "/wdi share on|off|r - share them with WhoDidIt users on your realm")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi master on|off|r - (maintainer only) feed the Chronicle raid times to every WhoDidIt user on the realm,  " .. c .. "/wdi feed on|off|r - use the master's feed")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi banter kills|clears [on|off]|r - fun kill / clear time announcements,  " .. c .. "/wdi banter test|r - preview one")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi logs|r - Chronicle log controls,  " .. c .. "/wdi log start|stop|save|r")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi loot|r - master looting with RollFor (built in): soft-res, rolls, winners and a step-by-step guide")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi check|r - who's missing consumables for their role right now (" .. c .. "/wdi check post|r to post it),  " .. c .. "/wdi readycheck on|off|r - run it on every ready check")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi aml|r - auto master looting on/off (or the Auto-loot button),  " .. c .. "/wdi aml to <name>|r,  " .. c .. "/wdi aml backup <name>|r,  " .. c .. "/wdi aml list|r")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi marks|r - auto marking: saved packs and quick save,  " .. c .. "/wdi mark|r - mark the pack under your mouse,  " .. c .. "/wdi marks help|r - all marking commands")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi demo|r - add two sample fights to try every feature, " .. c .. "/wdi demo live|r - watch one play out live, " .. c .. "/wdi demo clear|r")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi start|r / " .. c .. "/wdi stop|r - manually track your target / end tracking")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi idleblame on|off|r - give blame points for low activity / low DPS (off: shown, worth 0)")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi status|r, " .. c .. "/wdi clear|r, " .. c .. "/wdi errors|r - errors WhoDidIt caught (for bug reports)")
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
	elseif cmd == "master" and W.Board and W.Board.SetMaster and string.find(rest, "^%a+") then
		-- add / remove / list: anyone's own list of who to take the feed from
		local _, _, sub, who = string.find(rest, "^(%a+)%s*(%S*)")
		if sub == "add" or sub == "remove" then W.Board.SetMaster(who, sub == "add")
		elseif sub == "list" then
			local l = W.Board.MasterList()
			W.Print("Raid times are taken from: " .. ((getn(l) > 0) and table.concat(l, ", ") or "nobody on this realm") .. " (" .. W.Board.Realm() .. ")")
		elseif not W.Board.CanMaster() then
			W.Print("Usage: /wdi master list | add <name> | remove <name>")
		elseif sub == "on" or sub == "off" then
			db.opts.master = (sub == "on")
			W.Print("Master feed: " .. (db.opts.master and "|cff33ff33on|r - while you're online, every WhoDidIt user on your realm gets your Chronicle raid times (needs the sync helper running on this PC)" or "off"))
			if W.UI then W.UI:Refresh() end
		end
	elseif cmd == "master" and not (W.Board and W.Board.CanMaster and W.Board.CanMaster()) then
		W.Print("Only the WhoDidIt maintainer's characters can be the master. You get the raid times from them automatically while they're online. /wdi master list shows who they are.")
	elseif cmd == "master" then
		db.opts.master = (rest == "on") or (rest == "" and not db.opts.master)
		if rest == "off" then db.opts.master = false end
		W.Print("Master feed: " .. (db.opts.master and "|cff33ff33on|r - while you're online, every WhoDidIt user on your realm gets your Chronicle raid times (needs the sync helper running on this PC)" or "off"))
		if W.UI then W.UI:Refresh() end

	elseif cmd == "feed" then
		db.opts.noFeed = (rest == "off")
		W.Print("Raid times from a master's feed: " .. (db.opts.noFeed and "off (ignored)" or "|cff33ff33on|r"))
		if W.Board then W.Board:LoadChronicle() end
		if W.UI then W.UI:Refresh() end
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
	elseif cmd == "fame" or cmd == "alltime" or cmd == "hof" then
		if not W.Career then W.Print(W.RESTART_MSG) return end
		W.UI:SetMode("fame")
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
		StaticPopup_Show("WHODIDIT_CLEAR")
	elseif cmd == "handover" then
		local keep = db.opts.keepSeparate or {}
		keep[rest] = nil
		db.opts.keepSeparate = keep
		W.Print("WhoDidIt will ask about " .. (rest ~= "" and rest or "?") .. " again at your next login.")
	elseif cmd == "idleblame" then
		db.opts.idleBlame = (rest == "on")
		W.Print("Blame points for low activity / low DPS: " .. (db.opts.idleBlame and "|cffff7777on|r" or "|cff33ff33off|r (still shown, worth 0)")
			.. " - applies to fights recorded from now on")
	elseif cmd == "art" then
		if W.UI and W.UI.ArtProbe then W.UI.ArtProbe() end
	elseif cmd == "errors" then
		local list = db.errors or {}
		if getn(list) == 0 then W.Print("No errors recorded.") end
		for i = 1, getn(list) do DEFAULT_CHAT_FRAME:AddMessage("  " .. list[i]) end
	else
		help()
	end
end

SLASH_WHODIDIT1 = "/whodidit"
SLASH_WHODIDIT2 = "/wdi"
SlashCmdList["WHODIDIT"] = slash
