--[[--------------------------------------------------------------------
	WhoDidIt - Chronicle log controls

	Drives the Chronicle logger (ChronicleCompanion, which writes the combat
	logs you upload to chronicleclassic.com) from the WhoDidIt window. It is
	built in (see ChronicleLoader.lua); the separate addon works too: start/stop
	logging, save, archive, delete and its auto-logging settings, plus two
	WhoDidIt extras - start logging on a boss pull and save after every
	boss fight. Uploading has to be done on the website: addons can't
	reach the internet.
----------------------------------------------------------------------]]

local W = WhoDidIt
local L = {}
W.Logs = L

L.savedLines = 0
L.lastSave = nil
L.history = {}   -- this session's saves, newest first: { time, lines, what }

function L:Available()
	return ChronicleLog ~= nil and ChronicleLog.Enable ~= nil and ChronicleLog.FlushToFile ~= nil
end

-- which logger is running: "builtin" (WhoDidIt's Chronicle\ copy),
-- "standalone" (the separate ChronicleCompanion addon) or nil
function L:Source()
	if not L:Available() then return nil end
	if not WDI_CHRON_SKIP and WDI_CHRON_VERSION then return "builtin" end
	return "standalone"
end

function L:Version()
	if L:Source() == "builtin" then return WDI_CHRON_VERSION end
	return GetAddOnMetadata("ChronicleCompanion", "Version")
end

function L:Enabled()
	return L:Available() and ChronicleLog:IsEnabled() and true or false
end

function L:File()
	if not L:Available() then return nil end
	return ChronicleLog:GetLogFilename()
end

function L:Unsaved()
	if not L:Available() then return 0 end
	return ChronicleLog:GetBufferSize() or 0
end

local function noted(n, what)
	if n and n > 0 then
		L.savedLines = L.savedLines + n
		L.lastSave = date("%H:%M:%S")
		tinsert(L.history, 1, { L.lastSave, n, what or "Saved" })
	end
end

-- the built-in copy logs only once the player has said yes (asked the first
-- time they enter a raid); the separate addon is the player's own choice
local AUTO = { autoEnableInRaid = true, autoEnableInDungeon = true, showLogReminder = true }
function L:Allowed()
	return L:Source() ~= "builtin" or WhoDidItDB.opts.chronUse == true
end
local function quiet()
	if not (L:Available() and L:Source() == "builtin") then return end
	for k in pairs(AUTO) do ChronicleLog:SetSetting(k, false) end
	if ChronicleLog:IsEnabled() then ChronicleLog:Disable() end
end
function L:Use(on)
	WhoDidItDB.opts.chronUse = on and true or false
	if not L:Available() then return end
	if on then
		for k, v in pairs(AUTO) do ChronicleLog:SetSetting(k, v) end
	else
		quiet()
	end
end

-- (25 Nov 2026, Javelin: "Auto-enable in Raids" ticked in Chronicle's own options was off again after a relog) a
-- player who switches one of the automatic settings on in Chronicle's own window has said yes too: quiet() at
-- the next login only runs for someone who never did
local function watchSettings()
	if not (L:Available() and L:Source() == "builtin") or ChronicleLog.wdiWatched then return end
	ChronicleLog.wdiWatched = true
	local set = ChronicleLog.SetSetting
	ChronicleLog.SetSetting = function(self, key, value)
		if AUTO[key] and value == true and WhoDidItDB and WhoDidItDB.opts then WhoDidItDB.opts.chronUse = true end
		return set(self, key, value)
	end
end

W:On("ADDON_LOADED", function(name)
	if name ~= "WhoDidIt" then return end
	watchSettings()
	if WhoDidItDB.opts.chronUse ~= true then quiet() end
end)

StaticPopupDialogs["WHODIDIT_CHRONLOG"] = {
	text = "WhoDidIt has Chronicle's logger built in. It records your raids to a log file that you can upload to chronicleclassic.com (for the Rankings and your guild's logs).\n\nLog your raids?",
	button1 = "Yes, log them", button2 = "No",
	OnAccept = function()
		L:Use(true)
		L:Start()
		W.Print("Chronicle logging is |cff33ff33on|r: it starts by itself in raids. The Logging tab has the details and switches.")
	end,
	OnCancel = function()
		L:Use(false)
		W.Print("Chronicle logging stays |cffff5555off|r. Switch it on any time on the Logging tab.")
	end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}
local askedLog
local function askLog()
	if askedLog or not WhoDidItDB or WhoDidItDB.opts.chronUse ~= nil or L:Source() ~= "builtin" then return end
	if L:SplitOn() then return end   -- (every raid asks with its own log file: below)
	local inInst, typ = IsInInstance()
	if not inInst or typ ~= "raid" then return end
	askedLog = true
	StaticPopup_Show("WHODIDIT_CHRONLOG")
end
W:On("ZONE_CHANGED_NEW_AREA", askLog)
W:On("PLAYER_ENTERING_WORLD", askLog)

function L:Start()
	if not L:Available() then return end
	-- starting it by hand is a yes
	if L:Source() == "builtin" and WhoDidItDB.opts.chronUse ~= true then L:Use(true) end
	if L.cur then L.cur.skip = nil end
	if not ChronicleLog:IsEnabled() then
		ChronicleLog:Enable()
		W.Print("Chronicle logging |cff33ff33started|r.")
	end
end

function L:Stop()
	if not L:Available() or not ChronicleLog:IsEnabled() then return end
	local n = ChronicleLog:Disable() or 0
	noted(n, "Stopped & saved")
	W.Print("Chronicle logging |cffff5555stopped|r - saved " .. n .. " lines to " .. (L:File() or "?") .. ".")
end

function L:Save(quiet)
	if not L:Available() then return 0 end
	local n = ChronicleLog:FlushToFile() or 0
	noted(n, quiet and "Auto-saved" or "Saved")
	if not quiet then
		W.Print(n > 0 and ("Saved " .. n .. " lines to " .. (L:File() or "?") .. ".") or "Nothing new to save.")
	end
	return n
end

function L:Archive()
	if not L:Available() or not ChronicleLog.ArchiveLogs then return end
	L:Save(true)
	ChronicleLog:ArchiveLogs("backup")
end

-- Chronicle's own "are you sure" popup
function L:Delete()
	if not L:Available() then return end
	if StaticPopupDialogs["CHRONICLELOG_CLEAR_CONFIRM"] then
		StaticPopup_Show("CHRONICLELOG_CLEAR_CONFIRM")
	else
		ChronicleLog:DeleteLogs()
	end
end

function L:Setting(key)
	if not L:Available() then return nil end
	return ChronicleLog:GetSetting(key)
end

function L:ToggleSetting(key)
	if not L:Available() then return end
	ChronicleLog:SetSetting(key, not ChronicleLog:GetSetting(key))
end

------------------------------------------------------------------ hand-over from the separate addon

-- The separate ChronicleCompanion is still switched on next to the built-in
-- copy: it keeps logging this session (the built-in one stood down) and is
-- switched off from the next /reload. Both declare Chronicle's saved
-- variables, so its settings are saved with WhoDidIt's on the way out.
local handedOver
W:On("PLAYER_ENTERING_WORLD", function()
	if handedOver or not (WDI_CHRON_SKIP and WDI_CHRON_VERSION) or not IsAddOnLoaded("ChronicleCompanion") then return end
	handedOver = true
	W:AskHandover("ChronicleCompanion", "the Chronicle logger (v" .. WDI_CHRON_VERSION .. ", the Logging tab)")
end)

------------------------------------------------------------------ one log file per raid / 5-man run
-- Chronicle writes everything into one file per character (Chronicle_<Name>.txt) and, on
-- a new raid lockout, offers to move it to Chronicle_<Name>_backup_<unix time>.txt.
-- Players couldn't find their raids (MC, 15 Oct 2026: the night's log went into a backup
-- mid-evening, the dungeon after it into the main file). With opts.chronSplit (default on,
-- built-in logger only) every raid run and every 5-man run gets its own numbered file,
-- Chronicle_<Name>[_<Realm>]_<NNN>_<Zone>.txt, and the open world and battlegrounds keep
-- Chronicle's own file. Entering a raid shows which file (and asks, if logging is off).
-- Which run a zone-in belongs to:
--   raid:  the same zone, unless both lockouts are known (GetSavedInstanceInfo) and differ;
--          an unknown lockout (0: not saved yet, or not loaded after a relog) never starts
--          a new file - that's what made Chronicle's own "previous instance" pop-up fire
--          mid-raid. Nothing written for 6 hours: a new file.
--   5-man: the same zone, written to within 2 hours.
-- The zone text can lag behind a loading screen (CLAUDE.md), so the file is picked once it
-- settles: a known raid name, 5 seconds, or the first pull. A file picked on a name that
-- then changes, before anything was written to it, takes the new name.

local RAID_GAP, RUN_GAP, SETTLE, SETTLE_MAX = 6 * 3600, 2 * 3600, 5, 20
local MAX_RECENT = 20
L.target = nil       -- the file Chronicle writes to now (nil: its own)
L.cur = nil          -- the run's file record (in store().recent)
local origName       -- Chronicle's own GetLogFilename
local loadAt, picked, pulled, fresh = 0, true, false, nil

function L:SplitOn()
	return WhoDidItDB and WhoDidItDB.opts.chronSplit ~= false and L:Source() == "builtin" and true or false
end

-- this character's log files: { n = last number, curN = the run's number, recent = { newest
-- first } } (the run is found in recent by its number: SavedVariables would write one table
-- kept in two places as two copies)
local function store()
	if type(WhoDidItDB.chronFiles) ~= "table" then WhoDidItDB.chronFiles = {} end
	local k = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
	local s = WhoDidItDB.chronFiles[k]
	if type(s) ~= "table" then
		s = { n = 0, recent = {} }
		WhoDidItDB.chronFiles[k] = s
	end
	return s
end
function L:Recent() return WhoDidItDB and store().recent or {} end

local function savedId(zone)
	local z = strlower(zone or "")
	for i = 1, (GetNumSavedInstances and GetNumSavedInstances() or 0) do
		local name, id = GetSavedInstanceInfo(i)
		if name and strlower(name) == z then return tonumber(id) or 0 end
	end
	return 0
end

local function fileName(n, zone)
	local base = string.gsub(origName(ChronicleLog), "%.txt$", "")
	local z = string.gsub(zone or "", "[^%w]", "")
	if z == "" then z = "Instance" end
	return base .. "_" .. string.format("%03d", n) .. "_" .. z .. ".txt"
end

-- does a zone-in belong to this earlier run?
local function sameRun(c, kind, zone, id, now)
	if type(c) ~= "table" or c.kind ~= kind or c.zone ~= zone then return false end
	if kind == "raid" then
		if (c.id or 0) ~= 0 and id ~= 0 and c.id ~= id then return false end
		return now - (c.last or c.at or 0) <= RAID_GAP
	end
	return now - (c.last or c.at or 0) <= RUN_GAP
end

-- the run this zone-in belongs to (an earlier one: back in the raid after a 5-man), or a
-- new numbered file
local function pick(kind, zone)
	local s = store()
	local now = time()
	local id = (kind == "raid") and savedId(zone) or 0
	for i = 1, table.getn(s.recent) do
		local c = s.recent[i]
		if sameRun(c, kind, zone, id, now) then
			if (c.id or 0) == 0 and id ~= 0 then c.id = id end
			c.last = now
			s.curN = c.n
			return c, false
		end
	end
	local c
	s.n = (s.n or 0) + 1
	c = { n = s.n, kind = kind, zone = zone, id = id, at = now, last = now, lines = 0, file = fileName(s.n, zone) }
	s.curN = c.n
	tinsert(s.recent, 1, c)
	while table.getn(s.recent) > MAX_RECENT do tremove(s.recent) end
	return c, true
end

local function where(c) return W.LF("Log %d: WoW folder\\CustomData\\%s", c.n, c.file) end

StaticPopupDialogs["WHODIDIT_CHRONRAID_ON"] = {
	text = "Chronicle is logging %s.\n\n%s\n\nUpload this file at chronicleclassic.com after the raid.",
	button1 = "OK", button2 = "Don't log this raid",
	OnCancel = function()
		if L.cur then L.cur.skip = true end
		L:Stop()
	end,
	-- (no hideOnEscape: in 1.12 Escape is the second button, and that one stops logging)
	timeout = 0, whileDead = 1,
}
StaticPopupDialogs["WHODIDIT_CHRONRAID_ASK"] = {
	text = "WhoDidIt has Chronicle's logger built in. Log %s for chronicleclassic.com?\n\n%s",
	button1 = "Yes, log it", button2 = "No",
	OnAccept = function() L:Start() end,
	OnCancel = function()
		if WhoDidItDB.opts.chronUse == nil then L:Use(false) end
		if L.cur then L.cur.skip = true end
	end,
	timeout = 0, whileDead = 1,
}

-- a run's file was picked: say which (raids: a pop-up for a new one)
local function announce(c, new)
	if c.kind == "raid" then
		if c.skip then
			if ChronicleLog:IsEnabled() then ChronicleLog:Disable() end   -- (Chronicle's auto start)
			return
		end
		if new then
			W.ShowPopup(L:Enabled() and "WHODIDIT_CHRONRAID_ON" or "WHODIDIT_CHRONRAID_ASK", c.zone, where(c))
		elseif L:Enabled() then
			W.Print(W.LF("Chronicle: still writing %s.", where(c)))
		end
	elseif L:Enabled() then
		W.Print(W.LF("Chronicle: this 5-man goes into its own file. %s", where(c)))
	end
end

local function settleFile()
	if not L:SplitOn() then
		L.target, L.cur = nil, nil
		return
	end
	local inInst, typ = ChronicleLog:IsInInstance()   -- (battlegrounds count as the open world)
	local zone = GetRealZoneText() or ""
	if not inInst or (typ ~= "raid" and typ ~= "party") then
		if not picked then picked, L.target, L.cur = true, nil, nil end
		return
	end
	if picked then
		-- a name that changed before anything was written: the lagging one
		local c = fresh
		if c and c == L.cur and c.kind == typ and zone ~= "" and zone ~= c.zone and (c.lines or 0) == 0 then
			c.zone, c.file = zone, fileName(c.n, zone)
			L.target = c.file
		end
		return
	end
	local waited = GetTime() - loadAt
	if not pulled then
		if typ == "raid" and not (W.Data.clears[zone] or W.Data.sharedZones[zone]) and waited < SETTLE_MAX then return end
		if typ == "party" and waited < SETTLE then return end
	end
	if zone == "" then return end
	picked = true
	local c, new = pick(typ, zone)
	L.cur, L.target = c, c.file
	fresh = new and c or nil
	announce(c, new)
end

local hooked
local function hook()
	if hooked or not L:Available() then return end
	hooked = true
	origName = ChronicleLog.GetLogFilename
	ChronicleLog.GetLogFilename = function(self)
		if L.target and L:SplitOn() then return L.target end
		return origName(self)
	end
	-- lines written per file (a file nothing went into yet can still be renamed)
	local flush = ChronicleLog.FlushToFile
	ChronicleLog.FlushToFile = function(self)
		local c = L.target and L.cur
		local n = flush(self)
		if c and n and n > 0 then
			c.lines = (c.lines or 0) + n
			c.last = time()
		end
		return n
	end
	-- each lockout has its own file: Chronicle's "previous instance ID" pop-up isn't needed
	local zoneInfo = ChronicleLog.WriteZoneInfo
	ChronicleLog.WriteZoneInfo = function(self, force)
		if L:SplitOn() and ChronicleCompanionCharDB then ChronicleCompanionCharDB.lastInstanceIds = {} end
		return zoneInfo(self, force)
	end
end
W:On("ADDON_LOADED", function(name) if name == "WhoDidIt" then hook() end end)

-- a loading screen: the next settled zone picks the file (Chronicle has flushed what came
-- before into the old one)
W:On("PLAYER_ENTERING_WORLD", function()
	if not WhoDidItDB then return end
	hook()
	loadAt, picked, pulled, fresh = GetTime(), false, false, nil
end)
W:On("PLAYER_REGEN_DISABLED", function()
	if not WhoDidItDB or picked then return end
	pulled = true
	settleFile()
end)
W:Every(1, function() if WhoDidItDB and hooked then settleFile() end end)

------------------------------------------------------------------ hooks from the tracker

-- a boss was pulled (only in a raid or a 5-man: training dummies count as world bosses, and
-- one in a city started logging the open world, 16 Oct 2026)
function L:OnFightStart()
	if L.cur and L.cur.skip and L.target == L.cur.file then return end   -- "Don't log this raid"
	local inInst, typ = IsInInstance()
	if not inInst or (typ ~= "raid" and typ ~= "party") then return end
	if WhoDidItDB.opts.chronStartOnPull and L:Available() and L:Allowed() and not ChronicleLog:IsEnabled() then
		ChronicleLog:Enable()
		W.Print("Chronicle logging |cff33ff33started|r for the pull.")
	end
end

-- a boss fight ended (rec = the saved report)
function L:OnFightEnd(rec)
	if WhoDidItDB.opts.chronSaveOnFight and L:Enabled() and not rec.demo then
		L:Save(true)
	end
end
