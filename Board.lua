--[[--------------------------------------------------------------------
	WhoDidIt - rankings board: boss kill times and full instance clears

	Records come from fights WhoDidIt records itself:
	  - kill time  = the boss fight's duration (first hit -> kill)
	  - clear time = first combat in the instance -> last required boss
	    (Data.lua D.clears) killed in the same run
	The guild of a record is the raid's majority guild (>= half the raid).

	Each guild's bests are shared with other WhoDidIt users on the same
	realm through a hidden chat channel, so the board fills up with every
	guild on the server that has at least one WhoDidIt user. Shared records
	are self-reported - they're sanity-checked but can't be verified.
----------------------------------------------------------------------]]

local W = WhoDidIt
local B = {}
W.Board = B

local getn = table.getn
local floor = math.floor

local CHANNEL = "WDIBoard"
local PROTO   = "WDIB1"
local SEP     = "~"

local KILL_MIN, KILL_MAX   = 5, 3600
local CHRON_KILL_MIN = 10   -- Chronicle logs with a boss "killed" faster than this are broken
local CLEAR_MIN, CLEAR_MAX = 120, 8 * 3600
local RUN_MAX = 6 * 3600   -- a run older than this can't become a clear

------------------------------------------------------------------ basics

function B.Realm() return GetRealmName() or "Unknown" end
function B.Faction() return UnitFactionGroup("player") or "Neutral" end
function B.MyGuild() return (GetGuildInfo("player")) end

local function charKey()
	return (UnitName("player") or "?") .. "-" .. B.Realm()
end

-- m:ss.s for kills, h:mm:ss for clears
function B.Fmt(secs)
	if not secs then return "-" end
	if secs >= 3600 then
		return string.format("%d:%02d:%02d", floor(secs / 3600), floor(math.mod(secs, 3600) / 60), floor(math.mod(secs, 60)))
	end
	return string.format("%d:%04.1f", floor(secs / 60), math.mod(secs, 60))
end

function B.Date(epoch)
	return epoch and date("%d %b %Y", epoch) or "?"
end

function B:DB(realm)
	if type(WhoDidItDB.board) ~= "table" then WhoDidItDB.board = {} end
	realm = realm or B.Realm()
	local r = WhoDidItDB.board[realm]
	if not r then
		r = { kills = {}, clears = {} }
		WhoDidItDB.board[realm] = r
	end
	return r
end

-- this character's personal bests
function B:PB()
	if type(WhoDidItDB.pb) ~= "table" then WhoDidItDB.pb = {} end
	local k = charKey()
	local p = WhoDidItDB.pb[k]
	if not p then
		p = { kills = {}, clears = {} }
		WhoDidItDB.pb[k] = p
	end
	return p
end

------------------------------------------------------------------ Chronicle data
-- tools/WhoDidIt-Sync.ps1 pulls Chronicle's public External API and writes
-- CustomData/WhoDidIt_Chronicle.txt; Nampower lets us read it while playing.
--   WDICHRON|1|<synced epoch>|<server>|<days>|<status>
--   C|realm|instance|guild|faction|secs|ended|players|slug       (full clear)
--   K|realm|instance|boss|guild|faction|secs|ended|players|slug  (boss kill)

local CHRON_FILE = "WhoDidIt_Chronicle.txt"
local CHRON_ZONE = { ["Temple of Ahn'Qiraj"] = "Ahn'Qiraj" }   -- Chronicle name -> WhoDidIt zone
B.chron = nil
local chronHead

local function splitBar(line)
	local out = {}
	for part in string.gfind(line .. "|", "(.-)|") do tinsert(out, part) end
	return out
end

-- (re)read the sync file; true if it changed
function B:LoadChronicle()
	-- the sync helper's file on this PC, or the master's feed (whichever is newer)
	local s, fromFile
	if ReadCustomFile then
		local ok, v = pcall(ReadCustomFile, CHRON_FILE)
		if ok and type(v) == "string" and v ~= "" then s, fromFile = v, true end
	end
	local f = WhoDidItDB and WhoDidItDB.feed
	if f and (f.synced or 0) > 0 and not (WhoDidItDB.opts and WhoDidItDB.opts.noFeed) then
		local _, _, a = string.find(s or "", "^WDICHRON|%d+|(%d+)")
		if not s or f.synced > (tonumber(a) or 0) then s, fromFile = B.FeedText(), false end
	end
	if not s then
		local had = B.chron ~= nil
		B.chron = nil
		chronHead = nil
		B.chronRaw, B.chronRawL, B.chronFeed = nil, nil, nil
		return had
	end
	local _, _, head = string.find(s, "^([^\n]*)")
	-- (a feed that grew by raid boss lists keeps its header: count those too)
	head = (head or "") .. (fromFile and "" or ("#" .. string.len(s)))
	if head == chronHead then return false end
	chronHead = head
	-- the master sends what's in its own file
	B.chronRaw = s
	B.chronRawL = {}
	B.chronFeed = not fromFile
	B.chronFrom = (not fromFile) and f and f.from or nil
	B.chronLines = 0

	local data = { realms = {}, bosses = {}, zones = {}, me = {}, logs = {} }
	for line in string.gfind(s, "[^\n]+") do
		local p = splitBar(line)
		local t = p[1]
		if t == "WDICHRON" then
			data.synced, data.server, data.days, data.status = tonumber(p[3]), p[4], tonumber(p[5]), p[6]
		elseif t == "L" then
			-- a whole raid: L|slug|realm|instance|guild|faction|ended|players|Boss=secs=into raid=wipes;...
			if B.chronRawL then B.chronRawL[p[2]] = line end
			local kills = {}
			for part in string.gfind((p[9] or "") .. ";", "(.-);") do
				local _, _, n, secs, at, w = string.find(part, "^(.-)=([%d%.]*)=([%d%.]*)=(%d*)$")
				if n and n ~= "" then tinsert(kills, { n = n, s = tonumber(secs), a = tonumber(at), w = tonumber(w) }) end
			end
			data.logs[p[2]] = { realm = p[3], zone = CHRON_ZONE[p[4]] or p[4], guild = p[5], f = p[6], d = tonumber(p[7]), n = tonumber(p[8]), kills = kills }
		elseif t == "PC" or t == "PK" then
			-- your characters' bests:  PC|realm|char|instance|secs|ended|guild|slug
			--                          PK|realm|char|instance|boss|secs|ended|guild|slug
			local realm, char = p[2], strlower(p[3] or "")
			data.me[realm] = data.me[realm] or {}
			local me = data.me[realm][char]
			if not me then
				me = { kills = {}, clears = {} }
				data.me[realm][char] = me
			end
			local zone = CHRON_ZONE[p[4]] or p[4]
			if t == "PC" then
				local secs = tonumber(p[5])
				if secs and secs >= CLEAR_MIN and secs <= CLEAR_MAX then me.clears[zone] = { t = secs, d = tonumber(p[6]), g = p[7], slug = p[8], chron = true } end
			else
				local secs = tonumber(p[6])
				if secs and secs >= CHRON_KILL_MIN and secs <= KILL_MAX then me.kills[p[5]] = { t = secs, d = tonumber(p[7]), g = p[8], slug = p[9], chron = true } end
			end
		elseif t == "C" or t == "K" then
			B.chronLines = B.chronLines + 1
			local realm = p[2]
			local zone = CHRON_ZONE[p[3]] or p[3]
			local kind, key, guild, fac, secs, d, n, slug
			if t == "C" then
				kind, key, guild, fac, secs, d, n, slug = "clears", zone, p[4], p[5], tonumber(p[6]), tonumber(p[7]), tonumber(p[8]), p[9]
			else
				kind, key, guild, fac, secs, d, n, slug = "kills", p[4], p[5], p[6], tonumber(p[7]), tonumber(p[8]), tonumber(p[9]), p[10]
				data.bosses[zone] = data.bosses[zone] or {}
				data.bosses[zone][key] = true
			end
			-- broken logs (a "clear" spanning days, a 4-second boss) would wreck the boards
			local maxSecs = (kind == "clears") and CLEAR_MAX or KILL_MAX
			local minSecs = (kind == "clears") and CLEAR_MIN or CHRON_KILL_MIN
			if realm ~= "" and guild and guild ~= "" and secs and secs >= minSecs and secs <= maxSecs then
				local r = data.realms[realm]
				if not r then
					r = { kills = {}, clears = {} }
					data.realms[realm] = r
				end
				local list = r[kind][key]
				if not list then
					list = {}
					r[kind][key] = list
				end
				local old = list[guild]
				if not old or secs < old.t then
					list[guild] = { t = secs, d = d, f = fac, n = n, slug = slug, chron = true }
				end
				data.zones[zone] = true
			end
		end
	end
	B.chron = data
	return true
end

-- a whole raid from Chronicle (every boss kill in order), by its log slug
function B:Log(slug)
	return slug and B.chron and B.chron.logs[slug]
end

function B.LogURL(slug)
	return "https://legacy.chronicleclassic.com/instances/" .. slug
end

-- where a time ranks on a realm's board (1 = fastest)
function B:Place(realm, kind, key, secs)
	local list = B:Board(realm, kind, key, "All")
	local place = 1
	for i = 1, getn(list) do
		if list[i][2].t < secs then place = place + 1 end
	end
	return place, getn(list)
end

-- Chronicle bosses seen for a zone (names as Chronicle writes them)
function B:ChronBosses(zone)
	local out = {}
	local set = B.chron and B.chron.bosses[zone]
	if set then
		for name in pairs(set) do tinsert(out, name) end
		table.sort(out)
	end
	return out
end

-- every zone with data: WhoDidIt's raids, then Chronicle-only ones (Karazhan towers...)
function B:Zones()
	local list, have = {}, {}
	for i = 1, getn(W.Data.clearOrder) do
		tinsert(list, W.Data.clearOrder[i])
		have[W.Data.clearOrder[i]] = true
	end
	if B.chron then
		local extra = {}
		for zone in pairs(B.chron.zones) do
			if not have[zone] then tinsert(extra, zone) end
		end
		table.sort(extra)
		for i = 1, getn(extra) do tinsert(list, extra[i]) end
	end
	return list
end

-- realms we have data for (current realm first)
function B:Realms()
	local list, have = { B.Realm() }, {}
	have[list[1]] = true
	for realm in pairs(WhoDidItDB.board or {}) do
		if not have[realm] then tinsert(list, realm); have[realm] = true end
	end
	if B.chron then
		for realm in pairs(B.chron.realms) do
			if not have[realm] then tinsert(list, realm); have[realm] = true end
		end
	end
	return list
end

-- the sync helper's progress (CustomData\WhoDidIt_SyncStatus.txt, rewritten
-- at least every 30 seconds while it runs):
--   WDISYNC|1|<now>|<state>|<step>|<steps>|<what>|<done>|<total>|<seconds left>|<next sync>
-- nil = it has never run here. alive = false: it was closed.
local SYNC_FILE, SYNC_ASK = "WhoDidIt_SyncStatus.txt", "WhoDidIt_SyncRequest.txt"
function B:SyncStatus()
	if not ReadCustomFile then return nil end
	local ok, s = pcall(ReadCustomFile, SYNC_FILE)
	if not ok or type(s) ~= "string" or s == "" then return nil end
	local p = splitBar((string.gsub(s, "[\r\n]", "")))
	if p[1] ~= "WDISYNC" then return nil end
	local st = { at = tonumber(p[3]) or 0, state = p[4] or "", step = tonumber(p[5]) or 0, steps = tonumber(p[6]) or 0,
		what = p[7] or "", done = tonumber(p[8]) or 0, total = tonumber(p[9]) or 0, eta = tonumber(p[10]) or 0, next = tonumber(p[11]) or 0 }
	st.alive = (st.state ~= "stopped") and (time() - st.at) < 120
	return st
end

-- Sync now: ask the helper (it checks every few seconds while it waits)
function B:RequestSync()
	if not WriteCustomFile then return false end
	local ok = pcall(WriteCustomFile, SYNC_ASK, tostring(time()), "w")
	if ok then B.asked = time() end
	return ok
end

-- re-read the sync file every minute; refresh the window when it changed
W:Every(60, function()
	if not WhoDidItDB then return end
	local changed = B:LoadChronicle()
	-- new times in: anyone who just beat us goes on the rival watch
	if (changed or B.rivalsDirty) and B.CheckRivals then
		B.rivalsDirty = nil
		B:CheckRivals()
		changed = true
	end
	if changed and W.UI and W.UI.mode == "rankings" then W.UI:Refresh() end
end)

-- keep a record if it's that guild's best; true if it improved
function B:Merge(kind, realm, key, guild, rec)
	local r = B:DB(realm)
	local list = r[kind][key]
	if not list then
		list = {}
		r[kind][key] = list
	end
	local old = list[guild]
	if old and old.t <= rec.t then return false end
	list[guild] = rec
	return true
end

B.ALL = "All realms"

-- guild -> best record on one realm, WhoDidIt and Chronicle merged
local function realmBoard(realm, kind, key)
	local merged = {}
	local mine = WhoDidItDB.board and WhoDidItDB.board[realm]
	for g, rec in pairs(mine and mine[kind][key] or {}) do merged[g] = rec end
	local c = B.chron and B.chron.realms[realm]
	if c and c[kind][key] then
		for g, rec in pairs(c[kind][key]) do
			local old = merged[g]
			if not old or rec.t < old.t then merged[g] = rec end
		end
	end
	return merged
end

-- sorted { guild, rec, realm } list. realm may be B.ALL; faction "All" or a
-- faction name. Cross-faction ("Mixed") guilds show in both faction views;
-- guilds of unknown faction only under "All".
function B:Board(realm, kind, key, faction)
	local realms = (realm == B.ALL) and B:Realms() or { realm }
	local list = {}
	for i = 1, getn(realms) do
		for g, rec in pairs(realmBoard(realms[i], kind, key)) do
			if faction == "All" or rec.f == faction or rec.f == "Mixed" then
				tinsert(list, { g, rec, realms[i] })
			end
		end
	end
	table.sort(list, function(a, b) return a[2].t < b[2].t end)
	return list
end

-- your current character's best: WhoDidIt's own record or Chronicle's
function B:MyBest(kind, key)
	local best = B:PB()[kind][key]
	local me = B.chron and B.chron.me[B.Realm()]
	me = me and me[strlower(UnitName("player") or "")]
	local cr = me and me[kind][key]
	if cr and (not best or cr.t < best.t) then best = cr end
	return best
end

-- your guild's best record for one board (WhoDidIt or Chronicle). Always
-- from your own realm, so viewing another realm compares against it.
function B:GuildBest(realm, kind, key, guild)
	realm = B.Realm()
	local best = B:DB(realm)[kind][key]
	best = best and best[guild]
	local c = B.chron and B.chron.realms[realm]
	local cr = c and c[kind][key] and c[kind][key][guild]
	if cr and (not best or cr.t < best.t) then best = cr end
	return best
end

-- rank (1-based) of a guild on a board, and how many guilds are on it
-- (on the all-realms board, your guild = the one on your realm)
function B:Rank(realm, kind, key, guild, faction)
	local list = B:Board(realm, kind, key, faction)
	local home = B.Realm()
	for i = 1, getn(list) do
		if list[i][1] == guild and (realm ~= B.ALL or list[i][3] == home) then return i, getn(list) end
	end
	return nil, getn(list)
end

------------------------------------------------------------------ recording

-- the raid's majority guild (>= half the raid) and raid size
local function raidGuild()
	local counts, n = {}, 0
	for _, e in pairs(W.roster.byName) do
		n = n + 1
		local g = GetGuildInfo(e.unit)
		if g then counts[g] = (counts[g] or 0) + 1 end
	end
	local best, bc = nil, 0
	for g, c in pairs(counts) do
		if c > bc then best, bc = g, c end
	end
	if best and bc * 2 >= n then return best, n end
	return nil, n
end

local function currentRun()
	if type(WhoDidItDB.runs) ~= "table" then WhoDidItDB.runs = {} end
	return WhoDidItDB.runs[charKey()]
end

local function setRun(r)
	if type(WhoDidItDB.runs) ~= "table" then WhoDidItDB.runs = {} end
	WhoDidItDB.runs[charKey()] = r
end

-- a run starts with the first combat inside a raid instance we can time
W:On("PLAYER_REGEN_DISABLED", function()
	if not WhoDidItDB then return end
	local inInst, typ = IsInInstance()
	if not inInst or typ ~= "raid" or GetNumRaidMembers() == 0 then return end
	local zone = GetRealZoneText()
	if not W.Data.clears[zone] then return end
	local r = currentRun()
	local now = time()
	if r and r.zone == zone and not r.done and now - r.start < RUN_MAX then return end
	setRun({ zone = zone, start = now, kills = {} })
end)

function B:CurrentRun()
	local r = currentRun()
	if r and not r.done and time() - r.start < RUN_MAX then return r end
end

local function announce(text)
	W.Print("|cff33ccffRankings:|r " .. text)
end

------------------------------------------------------------------ realms

-- "N'Zoth (PvE)" - realm types are set in Data.lua
function B.RealmLabel(realm)
	local t = W.Data.realmTypes and W.Data.realmTypes[realm]
	return t and (realm .. " (" .. t .. ")") or (realm or "?")
end

function B.ServerName()
	return (B.chron and B.chron.server) or "the server"
end

-- the fastest guild on every other realm for one board: { guild, rec, realm }, fastest first
function B:OtherRealms(kind, key, home)
	local out = {}
	local realms = B:Realms()
	for i = 1, getn(realms) do
		local realm = realms[i]
		if realm ~= home then
			local best
			for g, rec in pairs(realmBoard(realm, kind, key)) do
				if not best or rec.t < best[2].t then best = { g, rec, realm } end
			end
			if best then tinsert(out, best) end
		end
	end
	table.sort(out, function(a, b) return a[2].t < b[2].t end)
	return out
end

local function ago(epoch)
	if not epoch then return "recently" end
	local s = time() - epoch
	if s < 3600 then return "within the hour" end
	if s < 86400 then return floor(s / 3600) .. "h ago" end
	local d = floor(s / 86400)
	return (d == 1) and "yesterday" or (d .. " days ago")
end
B.Ago = ago

local function boardTitle(kind, key)
	if kind == "clears" then return (W.Data.instanceTitle[key] or key) .. " clear" end
	return key
end

------------------------------------------------------------------ posting once per raid
-- Every WhoDidIt user in the raid sees the same kill. Before an automatic
-- post (banter, rival watch) each one claims it on a hidden addon channel;
-- after two seconds only the first name alphabetically posts.

local CLAIM = "WDIPost"
local claims = {}

function B:Claim(tag, fn)
	local inRaid = GetNumRaidMembers() > 0
	if W.Shout:Channel() == "SELF" or (not inRaid and GetNumPartyMembers() == 0) then fn() return end
	local c = claims[tag] or { names = {} }
	c.at, c.fn = GetTime(), fn
	c.names[UnitName("player")] = true
	claims[tag] = c
	SendAddonMessage(CLAIM, tag, inRaid and "RAID" or "PARTY")
end

W:On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
	if prefix ~= CLAIM or not msg or not sender then return end
	local c = claims[msg]
	if not c then
		c = { names = {}, at = GetTime() }
		claims[msg] = c
	end
	c.names[sender] = true
end)

W:Every(0.5, function()
	local now = GetTime()
	for tag, c in pairs(claims) do
		if now - c.at > 2 then
			if c.fn then
				local first
				for n in pairs(c.names) do
					if not first or n < first then first = n end
				end
				if first == UnitName("player") then c.fn() end
			end
			claims[tag] = nil
		end
	end
end)

------------------------------------------------------------------ rival watch
-- A time that beats our guild's best and was set *after* it - from the
-- Chronicle sync or a WhoDidIt user on the realm - goes on the rival watch.
-- Other realms count when their fastest guild gets below our time. Rivals
-- show in Rankings, get posted when the raid enters that instance, and the
-- next kill of that boss gets a revenge (or "still behind") banter.

local RIVAL_DAYS = 21

local function rivalDB()
	if type(WhoDidItDB.rivals) ~= "table" then WhoDidItDB.rivals = {} end
	local r = WhoDidItDB.rivals
	r.seen = r.seen or {}
	r.list = r.list or {}
	return r
end

-- the instance a board key belongs to
function B:KeyZone(kind, key)
	if kind == "clears" then return key end
	local def = W.Data.encounters[key]
	if def then return def.zone end
	if B.chron then
		for zone, set in pairs(B.chron.bosses) do
			if set[key] then return zone end
		end
	end
end

local function allKeys(kind)
	local set = {}
	for _, r in pairs(WhoDidItDB.board or {}) do
		if type(r) == "table" and type(r[kind]) == "table" then
			for k in pairs(r[kind]) do set[k] = true end
		end
	end
	if B.chron then
		for _, r in pairs(B.chron.realms) do
			for k in pairs(r[kind]) do set[k] = true end
		end
	end
	return set
end

-- look for new times that beat ours; returns how many were found
function B:CheckRivals()
	local guild = B.MyGuild()
	if not guild or not WhoDidItDB then B.rivalsDirty = true return 0 end   -- guild info can lag at login
	local db = rivalDB()
	local home, now = B.Realm(), time()
	local first = not db.ready
	local found = 0
	local kinds = { "kills", "clears" }
	for k = 1, 2 do
		local kind = kinds[k]
		for key in pairs(allKeys(kind)) do
			local ours = B:GuildBest(home, kind, key, guild)
			if ours and ours.d then
				local cands = B:OtherRealms(kind, key, home)
				for g, rec in pairs(realmBoard(home, kind, key)) do
					if g ~= guild then tinsert(cands, { g, rec, home }) end
				end
				for i = 1, getn(cands) do
					local g, rec, realm = cands[i][1], cands[i][2], cands[i][3]
					if rec.t < ours.t and rec.d and rec.d > ours.d and now - rec.d < RIVAL_DAYS * 86400 then
						local id = kind .. "|" .. key .. "|" .. realm .. "|" .. g .. "|" .. rec.t
						if not db.seen[id] then
							db.seen[id] = true
							tinsert(db.list, { kind = kind, key = key, zone = B:KeyZone(kind, key), g = g, realm = realm, t = rec.t, d = rec.d, ours = ours.t })
							found = found + 1
						end
					end
				end
			end
		end
	end
	-- newest first; drop old ones
	local keep = {}
	for i = 1, getn(db.list) do
		if now - (db.list[i].d or 0) < RIVAL_DAYS * 86400 then tinsert(keep, db.list[i]) end
	end
	table.sort(keep, function(a, b) return (a.d or 0) > (b.d or 0) end)
	while getn(keep) > 40 do table.remove(keep) end
	db.list = keep
	db.ready = true
	if found > 0 then
		W.Print("|cffff7777Rival watch:|r " .. found .. " time" .. (found == 1 and "" or "s") .. " that beat " .. guild .. "'s best "
			.. (first and "in the last " .. RIVAL_DAYS .. " days" or "just came in") .. " - see Rankings.")
	end
	return found
end

-- rivals still ahead of us: optionally one instance, or one board (kind + key)
function B:Rivals(zone, kind, key)
	local out = {}
	local guild = B.MyGuild()
	if not guild or not WhoDidItDB then return out end
	local db = rivalDB()
	local now, home = time(), B.Realm()
	for i = 1, getn(db.list) do
		local e = db.list[i]
		local sane = e.t >= ((e.kind == "clears") and CLEAR_MIN or CHRON_KILL_MIN)   -- not a broken log
		if sane and now - (e.d or 0) < RIVAL_DAYS * 86400 and (not zone or e.zone == zone) and (not key or (e.kind == kind and e.key == key)) then
			local ours = B:GuildBest(home, e.kind, e.key, guild)
			if not ours or e.t < ours.t then
				e.cur = ours and ours.t or e.ours
				tinsert(out, e)
			end
		end
	end
	return out
end

-- "Care Bears" / "Pumpers of N'Zoth (PvE)"
function B:RivalName(e)
	return e.g .. ((e.realm ~= B.Realm()) and (" of " .. B.RealmLabel(e.realm)) or "")
end

function B:RivalText(e)
	return B:RivalName(e) .. " beat our " .. boardTitle(e.kind, e.key) .. " " .. ago(e.d) .. " (" .. B.Fmt(e.t) .. " vs our " .. B.Fmt(e.cur or e.ours) .. ")"
end

------------------------------------------------------------------ colours for chat posts
-- W:Send colours names from this map: our guild green, other guilds
-- orange, realms purple, bosses and instances gold (plus raid members in
-- their class colour). Multi-word names and "N'Zoth (PvE)" work too.

function B:ChatColours()
	local P = W.Shout.PALETTE   -- the same colours as every other post
	local CHAT_US, CHAT_THEM, CHAT_REALM, CHAT_BOSS = P.us, P.guild, P.realm, P.boss
	local m = {}
	for enc in pairs(W.Data.encounters) do m[enc] = CHAT_BOSS end
	for zone in pairs(W.Data.clears) do
		m[zone] = CHAT_BOSS
		if W.Data.instanceTitle[zone] then m[W.Data.instanceTitle[zone]] = CHAT_BOSS end
	end
	local realms = B:Realms()
	for i = 1, getn(realms) do
		local r = realms[i]
		local label = B.RealmLabel(r)
		m[label] = CHAT_REALM
		-- "C'Thun" alone is also a boss: plain realm names only when they have no type
		if label == r then m[r] = CHAT_REALM end
		local kinds = { "kills", "clears" }
		for k = 1, 2 do
			local boards = {}
			local mine = WhoDidItDB.board and WhoDidItDB.board[r]
			if type(mine) == "table" and type(mine[kinds[k]]) == "table" then tinsert(boards, mine[kinds[k]]) end
			local c = B.chron and B.chron.realms[r]
			if c then tinsert(boards, c[kinds[k]]) end
			for j = 1, getn(boards) do
				for key, list in pairs(boards[j]) do
					if kinds[k] == "kills" and not m[key] then m[key] = CHAT_BOSS end
					for g in pairs(list) do
						if string.len(g) >= 3 then m[g] = CHAT_THEM end
					end
				end
			end
		end
	end
	m[B.ServerName()] = CHAT_REALM
	for name, e in pairs(W.roster and W.roster.byName or {}) do
		if e.class then m[name] = e.class end
	end
	local guild = B.MyGuild()
	if guild then m[guild] = CHAT_US end
	return m
end

------------------------------------------------------------------ rival watch posts

local TAUNT = {
	"Are we really letting that slide?",
	"Time to take them back.",
	"Revenge is on the menu tonight.",
	"Let's remind them whose times these are.",
	"Pump harder.",
	"Somebody's been sleeping on their consumables.",
}

-- "Hell Fire of C'Thun (Hardcore) - Majordomo Executus 1:24.7 (ours 1:29.2, yesterday)"
function B:RivalShort(e)
	local what = (e.kind == "clears") and ((W.Data.instanceTitle[e.key] or e.key) .. " clear") or e.key
	return B:RivalName(e) .. " - " .. what .. " " .. B.Fmt(e.t) .. " (ours " .. B.Fmt(e.cur or e.ours) .. ", " .. ago(e.d) .. ")"
end

-- a heading line, then one line per rival (our realm first, newest first), at most 3
function B:RivalLines(zone, list)
	list = list or B:Rivals(zone)
	local n = getn(list)
	if n == 0 then return nil end
	local home = B.Realm()
	local sorted = {}
	for i = 1, n do sorted[i] = list[i] end
	table.sort(sorted, function(a, b)
		local ha, hb = (a.realm == home), (b.realm == home)
		if ha ~= hb then return ha end
		return (a.d or 0) > (b.d or 0)
	end)
	local title = W.Data.instanceTitle[zone or ""] or zone or "the raid"
	local lines = { "[WhoDidIt] RIVAL WATCH: " .. title .. " - " .. n .. " of our time" .. (n == 1 and " was" or "s were")
		.. " beaten. " .. TAUNT[math.random(getn(TAUNT))] }
	for i = 1, math.min(3, n) do tinsert(lines, i .. ") " .. B:RivalShort(sorted[i])) end
	if n > 3 then tinsert(lines, "...and " .. (n - 3) .. " more. All of them: /wdi rankings") end
	return lines
end

function B:PostRivals(zone, list)
	local lines = B:RivalLines(zone, list)
	if not lines then
		W.Print("Nobody has beaten our " .. (W.Data.instanceTitle[zone or ""] or zone or "") .. " times in the last " .. RIVAL_DAYS .. " days.")
		return
	end
	for _, e in ipairs(list or B:Rivals(zone)) do e.posted = true end
	W:Send(lines, nil, B:ChatColours())
end

-- entering a raid instance: post its rivals once (rival alerts on)
local lastWatch = {}
function B:OnZone()
	if not WhoDidItDB or not WhoDidItDB.opts.rivalAlerts then return end
	local inInst, typ = IsInInstance()
	if not inInst or typ ~= "raid" or GetNumRaidMembers() == 0 then return end
	local zone = GetRealZoneText()
	if lastWatch[zone] and GetTime() - lastWatch[zone] < 1800 then return end
	local fresh = {}
	local all = B:Rivals(zone)
	for i = 1, getn(all) do if not all[i].posted then tinsert(fresh, all[i]) end end
	if getn(fresh) == 0 then return end
	lastWatch[zone] = GetTime()
	B:Claim("R:" .. zone, function() B:PostRivals(zone, fresh) end)
end

W:On("ZONE_CHANGED_NEW_AREA", function() B:OnZone() end)

------------------------------------------------------------------ banter
-- A fun line in the shout channel after every boss kill and full clear:
-- our time against our own best, the other guilds on our realm, the best
-- of the other realms, and anyone who recently beat us - mocking us or
-- bigging us up. Placeholders: {what} boss / instance, {time} our time,
-- {d} the difference, {prev} our old best, {g} the other guild, {rank} /
-- {of} our place on {realm}; {og} / {orealm} the other realm's best guild
-- and realm; {their} / {ago} the rival's time and when they set it.

local BANTER = {
	first = {
		"First {what} on the books: {time}. Every speedrun starts somewhere.",
		"{what} down for the very first time in {time}. Somebody frame it.",
		"New record unlocked: {what} in {time}. Admittedly it's our only record.",
		"{what} in {time}. Our best ever, our worst ever, our only ever.",
	},
	pb = {
		"{what} in {time} - {d} faster than our old best. Who even are we?!",
		"New guild best on {what}: {time}. {d} shaved off. Barbers are jealous.",
		"{d} faster than ever on {what} ({time}). Somebody check if the boss was AFK.",
		"{what} at {time}, our best ever by {d}. The grind is paying off.",
		"PB! {what} in {time}, {d} quicker than last time. Screenshot it before we wipe again.",
		"{what} melted in {time}. That's {d} off our record. Pump it.",
	},
	slower = {
		"{what} in {time}. Our best is {prev}, so that was {d} of sightseeing.",
		"{what} down in {time} - only {d} slower than our record. Only.",
		"{time} on {what}. {d} off our best. Did someone stop for a snack?",
		"{what} took {time}. Our record is {prev}. We'll pretend this one didn't happen.",
		"{d} slower than our best on {what}. The boss must have eaten its vegetables today.",
		"{what} in {time}. {d} slower than we've done it. Consumables are not decorations, people.",
	},
	beat = {
		"{what} in {time} - {d} faster than {g}. Sorry not sorry, {g}.",
		"{time} on {what}. {g} took {d} longer. Somebody tell {g}.",
		"We just out-killed {g} on {what} by {d}. Respectfully.",
		"{what} in {time}: {g}, you've been passed. By {d}.",
		"{d} quicker than {g} on {what}. Get those parses up, {g}.",
		"{g} called, they want their {what} time back. It's {d} slower than ours.",
	},
	behind = {
		"{what} in {time}. {g} still did it {d} faster. Pain.",
		"{g} beat us on {what} by {d}. We'll get them next week. Probably.",
		"{d} behind {g} on {what}. So close, yet so far.",
		"{what} at {time}. {g} is {d} ahead and laughing at us right now.",
		"Only {d} slower than {g} on {what}. Only. {d}.",
		"{g} would like us to know they did {what} {d} faster. Thanks, {g}.",
	},
	top = {
		"{what} in {time} - #1 on {realm}! Bow down.",
		"Fastest {what} on {realm}: {time}. Everyone else is playing for second.",
		"{time} on {what}. #1 out of {of} on {realm}. Somebody call the server.",
		"{realm} record on {what}: {time}. Put it on the guild banner.",
	},
	rank = {
		"{what} in {time} puts us #{rank} of {of} on {realm}.",
		"#{rank} of {of} on {realm} for {what} with {time}. Climbing.",
		"{what}: {time}, #{rank} of {of} on {realm}. {g} is next on the hit list.",
		"{time} on {what} - #{rank} of {of} on {realm}. Not bad, not legendary.",
	},
	servertop = {
		"{what} in {time} - fastest on ALL of {server}. {orealm}, take notes.",
		"Nobody on any {server} realm has done {what} faster than our {time}. Not even {orealm}.",
		"{time} on {what}: the record across every realm. {og} of {orealm} is {d} behind us.",
	},
	realmbeat = {
		"{time} on {what} - faster than anyone on {orealm}. Their best, {og}, is {d} slower.",
		"{what} in {time}. The whole of {orealm} can't match it: {og} is {d} slower.",
		"Realm pride: {what} in {time}, {d} quicker than {orealm}'s fastest ({og}).",
	},
	realmbehind = {
		"{what} in {time}, but {og} over on {orealm} did it {d} faster. The other realm says hi.",
		"{og} of {orealm} would like a word: their {what} is {d} faster than our {time}.",
		"{time} on {what}. Meanwhile on {orealm}, {og} is {d} ahead. Cross-realm shame.",
	},
	revenge = {
		"Took {what} back from {g}! {time} - {d} faster than the {their} they set {ago}.",
		"{g} had {what} for about five minutes. {time} now, {d} under their {their}. Revenge served.",
		"Remember {g} beating our {what} {ago}? {time}, {d} faster. Remember that instead.",
	},
	chase = {
		"{g} beat our {what} {ago} ({their}) and still own it by {d}. Again. Faster.",
		"{what} in {time} - still {d} behind the {their} {g} set {ago}. They're laughing.",
		"{g}'s {their} on {what} from {ago} still stands. {d} to find. Who's slacking?",
	},
}
B.BANTER = BANTER

local lastBanter = {}

local function pick(cat)
	local list = BANTER[cat]
	local n = getn(list)
	local i = math.random(n)
	if n > 1 and i == lastBanter[cat] then i = math.mod(i, n) + 1 end
	lastBanter[cat] = i
	return list[i]
end

-- kind "kill" or "clear"; key = board key; old = our guild's best before this one;
-- rival = a rival-watch entry for this board (from before this kill was saved)
function B:BanterLine(kind, key, what, secs, old, realm, guild, rival)
	local bkind = (kind == "kill") and "kills" or "clears"
	local board = B:Board(realm, bkind, key, "All")
	local ahead, behind, passed
	local rank, of = 1, 1
	for i = 1, getn(board) do
		local g, r = board[i][1], board[i][2]
		if g ~= guild then
			of = of + 1
			if r.t < secs then
				ahead = board[i]
				rank = rank + 1
			elseif not behind then
				behind = board[i]
			end
			if old and r.t > secs and r.t < old.t and not passed then passed = board[i] end
		end
	end
	-- the other realms' fastest guilds
	local others = B:OtherRealms(bkind, key, realm)
	local fasterOther, slowerOther = others[1], nil
	if fasterOther and fasterOther[2].t >= secs then fasterOther = nil end
	for i = 1, getn(others) do
		if others[i][2].t > secs then slowerOther = others[i]; break end
	end

	local improved = (not old) or secs < old.t
	local cats, total = {}, 0
	local function add(c, w) tinsert(cats, { c, w }); total = total + w end
	if not old then add("first", 2) end
	if old and improved then add("pb", 3) end
	if not improved then add("slower", 3) end
	if rank == 1 and of > 1 then add("top", 3) end
	if passed then add("beat", 4) elseif behind then add("beat", 1) end
	if ahead then add("behind", improved and 1 or 3) end
	if of > 2 then add("rank", 1) end
	if rank == 1 and getn(others) > 0 and not fasterOther then add("servertop", 6)
	elseif slowerOther then add("realmbeat", 2) end
	if fasterOther then add("realmbehind", improved and 2 or 3) end
	if rival then
		if secs < rival.t then add("revenge", 12) else add("chase", 6) end
	end

	local roll, cat = math.random() * total, cats[1][1]
	for i = 1, getn(cats) do
		roll = roll - cats[i][2]
		if roll <= 0 then cat = cats[i][1]; break end
	end

	local other = passed or behind
	local orow = fasterOther or slowerOther or others[1]
	local v = {
		what = what, time = B.Fmt(secs), prev = old and B.Fmt(old.t) or "-",
		rank = tostring(rank), of = tostring(of), g = ahead and ahead[1] or (other and other[1]) or "the next guild",
		realm = B.RealmLabel(realm), server = B.ServerName(),
		og = orow and orow[1] or "", orealm = orow and B.RealmLabel(orow[3]) or "the other realms",
	}
	if cat == "pb" then v.d = B.Fmt(old.t - secs)
	elseif cat == "slower" then v.d = B.Fmt(secs - old.t)
	elseif cat == "beat" then v.g = other[1]; v.d = B.Fmt(other[2].t - secs)
	elseif cat == "behind" then v.g = ahead[1]; v.d = B.Fmt(secs - ahead[2].t)
	elseif cat == "servertop" then
		v.og, v.orealm, v.d = others[1][1], B.RealmLabel(others[1][3]), B.Fmt(others[1][2].t - secs)
	elseif cat == "realmbeat" then
		v.og, v.orealm, v.d = slowerOther[1], B.RealmLabel(slowerOther[3]), B.Fmt(slowerOther[2].t - secs)
	elseif cat == "realmbehind" then
		v.og, v.orealm, v.d = fasterOther[1], B.RealmLabel(fasterOther[3]), B.Fmt(secs - fasterOther[2].t)
	elseif cat == "revenge" or cat == "chase" then
		v.g, v.their, v.ago = B:RivalName(rival), B.Fmt(rival.t), ago(rival.d)
		v.d = B.Fmt(math.abs(secs - rival.t))
	else v.d = "" end

	local line = string.gsub(pick(cat), "{(%w+)}", function(k) return v[k] or "" end)
	return ((kind == "clear") and "[WhoDidIt] CLEAR: " or "[WhoDidIt] ") .. line
end

function B:Banter(kind, key, what, secs, old, realm, guild, rival)
	local line = B:BanterLine(kind, key, what, secs, old, realm, guild, rival)
	B:Claim(((kind == "clear") and "C:" or "K:") .. key, function()
		W:Send({ line }, nil, B:ChatColours())   -- guilds, realms, bosses, times in colour
	end)
end

-- a made-up kill so you can preview the banter (your own chat only)
function B:BanterTest()
	local bosses = { "Ragnaros", "Nefarian", "Onyxia", "Hakkar", "Patchwerk", "C'Thun" }
	local what = bosses[math.random(getn(bosses))]
	local secs = 60 + math.random(240)
	local old = (math.random(4) > 1) and { t = secs + math.random(-40, 40) } or nil
	local rival
	if math.random(3) == 1 then
		rival = { g = "Care Bears", realm = B.Realm(), t = secs + math.random(-30, 30), d = time() - math.random(3) * 86400 }
	end
	local colours = B:ChatColours()
	colours["Care Bears"] = colours["Care Bears"] or "#ff9966"
	colours["Your Guild"] = "#33ff33"
	W:Send({ B:BanterLine("kill", what, what, secs, old, B.Realm(), B.MyGuild() or "Your Guild", rival) }, "SELF", colours)
end

------------------------------------------------------------------ posting the boards

-- "#1 Care Bears 1:17.7, #2 ERROR 1:22.7, #3 ..." for one board
function B:TopLine(kind, key, realm, faction)
	local list = B:Board(realm, kind, key, faction or "All")
	if getn(list) == 0 then return nil end
	local all = (realm == B.ALL)
	local parts = {}
	for i = 1, math.min(3, getn(list)) do
		tinsert(parts, "#" .. i .. " " .. list[i][1] .. (all and (" (" .. list[i][3] .. ")") or "") .. " " .. B.Fmt(list[i][2].t))
	end
	local guild = B.MyGuild()
	local rank = guild and B:Rank(realm, kind, key, guild, faction or "All")
	local tail = ""
	if rank and rank > 3 then
		local g = B:GuildBest(realm, kind, key, guild)
		tail = " ... #" .. rank .. " " .. guild .. (g and (" " .. B.Fmt(g.t)) or "")
	end
	local where = all and ("every " .. B.ServerName() .. " realm") or B.RealmLabel(realm)
	return "[WhoDidIt] " .. boardTitle(kind, key) .. " on " .. where .. ": " .. table.concat(parts, ", ") .. tail
end

-- how our guild stands on every boss of an instance
function B:StandingsLine(zone, realm)
	local guild = B.MyGuild()
	if not guild then return nil end
	local keys, have = {}, {}
	local need = W.Data.clears[zone] or {}
	for i = 1, getn(need) do tinsert(keys, need[i]); have[need[i]] = true end
	local chron = B:ChronBosses(zone)
	for i = 1, getn(chron) do if not have[chron[i]] then tinsert(keys, chron[i]); have[chron[i]] = true end end
	local first, killed, notYet = 0, 0, {}
	for i = 1, getn(keys) do
		local g = B:GuildBest(realm, "kills", keys[i], guild)
		if g then
			killed = killed + 1
			local rank = B:Rank(realm, "kills", keys[i], guild, "All")
			if rank == 1 then
				first = first + 1
			else
				local top = B:Board(realm, "kills", keys[i], "All")[1]
				if top then tinsert(notYet, keys[i] .. " (" .. top[1] .. ", " .. B.Fmt(g.t - top[2].t) .. " faster)") end
			end
		end
	end
	if killed == 0 then return nil end
	local where = (realm == B.ALL) and ("every " .. B.ServerName() .. " realm") or B.RealmLabel(realm)
	local line = "[WhoDidIt] " .. (W.Data.instanceTitle[zone] or zone) .. " kill times on " .. where .. ": " .. guild
		.. " is #1 on " .. first .. " of " .. killed .. " bosses."
	if getn(notYet) > 0 then
		local shown = {}
		for i = 1, math.min(3, getn(notYet)) do tinsert(shown, notYet[i]) end
		line = line .. " Still to take: " .. table.concat(shown, ", ") .. ((getn(notYet) > 3) and (" +" .. (getn(notYet) - 3) .. " more") or "") .. "."
	end
	return line
end

-- called for every finished fight
function B:OnFight(rec)
	if rec.demo or rec.result ~= "KILL" then return end
	local def = W.Data.encounters[rec.enc]
	if not def or GetNumRaidMembers() == 0 then return end

	local realm, fac, me = B.Realm(), B.Faction(), UnitName("player")
	local guild, size = raidGuild()
	local secs = floor(rec.dur * 10 + 0.5) / 10
	local now = time()

	-- personal best
	local pb = B:PB()
	local old = pb.kills[rec.enc]
	if not old or secs < old.t then
		pb.kills[rec.enc] = { t = secs, d = now, g = guild, n = size }
		announce("new personal best on " .. rec.enc .. ": |cffffffff" .. B.Fmt(secs) .. "|r" .. (old and (" (was " .. B.Fmt(old.t) .. ")") or ""))
	end

	-- guild best (and the banter, which compares against the best *before* this kill,
	-- and against anyone who recently beat it)
	local oldKill = guild and B:GuildBest(realm, "kills", rec.enc, guild)
	local rival = guild and B:Rivals(nil, "kills", rec.enc)[1]
	if guild and B:Merge("kills", realm, rec.enc, guild, { t = secs, d = now, f = fac, n = size, by = me }) then
		local rank, of = B:Rank(realm, "kills", rec.enc, guild, "All")
		announce("new " .. guild .. " best on " .. rec.enc .. ": |cffffffff" .. B.Fmt(secs) .. "|r (#" .. rank .. " of " .. of .. " on " .. realm .. ")")
		B:Share("K", guild, fac, rec.enc, secs, now, size)
	end
	if guild and WhoDidItDB.opts.banterKills then
		B:Banter("kill", rec.enc, rec.enc, secs, oldKill, realm, guild, rival)
	end

	-- full clear?
	local r = B:CurrentRun()
	if not r or r.zone ~= def.zone then return end
	r.kills[rec.enc] = true
	r.last = now
	local need = W.Data.clears[r.zone]
	for i = 1, getn(need) do
		if not r.kills[need[i]] then return end
	end
	r.done = true
	local cs = now - r.start
	local title = W.Data.instanceTitle[r.zone] or r.zone
	local oc = pb.clears[r.zone]
	if not oc or cs < oc.t then
		pb.clears[r.zone] = { t = cs, d = now, g = guild, n = size }
	end
	announce(title .. " cleared in |cffffffff" .. B.Fmt(cs) .. "|r" .. ((oc and cs < oc.t) and " - new personal best!" or ""))
	local oldClear = guild and B:GuildBest(realm, "clears", r.zone, guild)
	local clearRival = guild and B:Rivals(nil, "clears", r.zone)[1]
	if guild and WhoDidItDB.opts.banterClears then
		B:Banter("clear", r.zone, title, cs, oldClear, realm, guild, clearRival)
	end
	if guild and B:Merge("clears", realm, r.zone, guild, { t = cs, d = now, f = fac, n = size, by = me }) then
		local rank, of = B:Rank(realm, "clears", r.zone, guild, "All")
		announce("new " .. guild .. " clear record: #" .. rank .. " of " .. of .. " on " .. realm)
		B:Share("C", guild, fac, r.zone, cs, now, size)
	end
end

------------------------------------------------------------------ sharing (hidden realm channel)

local outq = {}
local seen = {}        -- "K~guild~key" -> GetTime() last seen on the channel
local respondAt, lastAnswer, asked

local function chanId()
	local id = GetChannelName(CHANNEL)
	if id and id > 0 then return id end
end

-- join the channel and keep it out of every chat window
function B:Join()
	if not WhoDidItDB.opts.shareBoard then return end
	if not chanId() then JoinChannelByName(CHANNEL) end
	for i = 1, NUM_CHAT_WINDOWS or 7 do
		local cf = getglobal("ChatFrame" .. i)
		if cf and ChatFrame_RemoveChannel then
			ChatFrame_RemoveChannel(cf, CHANNEL)
		elseif RemoveChatWindowChannel then
			RemoveChatWindowChannel(i, CHANNEL)
		end
	end
end

function B:Leave()
	if chanId() then LeaveChannelByName(CHANNEL) end
	outq = {}
end

function B:Share(kind, guild, fac, key, secs, d, n)
	if not WhoDidItDB.opts.shareBoard then return end
	tinsert(outq, table.concat({ PROTO, kind, guild, fac, key, tostring(secs), tostring(d), tostring(n or 0) }, SEP))
	seen[kind .. SEP .. guild .. SEP .. key] = GetTime()
end

-- ask everyone online for their guild's records
function B:Ask()
	if not WhoDidItDB.opts.shareBoard then return end
	tinsert(outq, PROTO .. SEP .. "Q")
	asked = GetTime()
end

-- answer a query: our own guild's records, unless a guildmate just sent them
local function answer()
	local guild = B.MyGuild()
	if not guild then return end
	local r = B:DB()
	local now = GetTime()
	local sent = 0
	for _, kind in ipairs({ "kills", "clears" }) do
		local k = (kind == "kills") and "K" or "C"
		for key, list in pairs(r[kind]) do
			local rec = list[guild]
			local id = k .. SEP .. guild .. SEP .. key
			if rec and sent < 40 and not (seen[id] and now - seen[id] < 300) then
				B:Share(k, guild, rec.f or B.Faction(), key, rec.t, rec.d, rec.n)
				sent = sent + 1
			end
		end
	end
end

local function split(msg)
	local out = {}
	for part in string.gfind(msg .. SEP, "(.-)" .. SEP) do tinsert(out, part) end
	return out
end

function B:Receive(msg, sender)
	local p = split(msg)
	local kind = p[2]
	if kind == "Q" then
		if sender ~= UnitName("player") and (not lastAnswer or GetTime() - lastAnswer > 600) and not respondAt then
			respondAt = GetTime() + 10 + math.random(30)
		end
		return
	end
	if kind ~= "K" and kind ~= "C" then return end
	local guild, fac, key = p[3], p[4], p[5]
	local secs, d, n = tonumber(p[6]), tonumber(p[7]), tonumber(p[8])
	if not guild or guild == "" or string.len(guild) > 40 or not secs or not d then return end
	if fac ~= "Alliance" and fac ~= "Horde" then return end
	if d > time() + 86400 then return end
	if kind == "K" then
		if not W.Data.encounters[key] or secs < KILL_MIN or secs > KILL_MAX then return end
	else
		if not W.Data.clears[key] or secs < CLEAR_MIN or secs > CLEAR_MAX then return end
	end
	seen[kind .. SEP .. guild .. SEP .. key] = GetTime()
	if B:Merge(kind == "K" and "kills" or "clears", B.Realm(), key, guild,
		{ t = secs, d = d, f = fac, n = n, by = sender, net = true }) then B.rivalsDirty = true end
	if W.UI and W.UI.mode == "rankings" then W.UI:Refresh() end
end

W:On("CHAT_MSG_CHANNEL", function(msg, sender, lang, chanFull, target, flags, zoneId, chanNum, chanName)
	if not msg or string.sub(msg, 1, string.len(PROTO) + 1) ~= PROTO .. SEP then return end
	local name = strlower(chanName or "")
	if name ~= strlower(CHANNEL) and not string.find(strlower(chanFull or ""), strlower(CHANNEL), 1, true) then return end
	B:Receive(msg, sender)
end)

-- one message every 2s; join late so the default channels keep their numbers
local joinAt
W:On("PLAYER_ENTERING_WORLD", function()
	if not joinAt then joinAt = GetTime() + 15 end
	B:LoadChronicle()
	B.rivalsDirty = true
	B:OnZone()
end)

W:Every(2, function()
	if not WhoDidItDB or not WhoDidItDB.opts.shareBoard then return end
	local now = GetTime()
	if joinAt and now >= joinAt then
		joinAt = nil
		B:Join()
		if not asked then B:Ask() end
	end
	if respondAt and now >= respondAt then
		respondAt = nil
		lastAnswer = now
		answer()
	end
	if getn(outq) == 0 then return end
	local id = chanId()
	if not id then
		B:Join()
		return
	end
	SendChatMessage(tremove(outq, 1), "CHANNEL", nil, id)
end)

------------------------------------------------------------------ master feed
-- One WhoDidIt user who runs the sync helper can be the "master" (/wdi master
-- on): while they're online, their WhoDidIt feeds every other WhoDidIt user on
-- the realm with Chronicle's raid times over the hidden channel, so nobody
-- else needs anything but the addon. Every minute the master says how fresh
-- its times are; anyone behind asks, and the master streams the raw lines
-- (all of them once, then only what changed) packed into chat messages. One
-- stream serves everyone listening. A raid's boss list is only sent when
-- someone opens that raid. What arrives is saved, so it's there next login.
--   H~synced~lines~server~m            what I have (every minute; m 1 = the master)
-- Only the maintainer's characters (B.MASTERS) can be the master: every copy
-- of WhoDidIt ignores feed messages from anyone else. Character names are
-- unique per realm and the channel only reaches the sender's own realm, so
-- nobody can send as them. Someone editing their own copy only fools
-- themselves. To feed a realm, log into that realm's master character.
--   A~since                             player: please send what's new since
--   B~sid~synced~since~total~server     stream start (total D + R messages)
--   D~sid~idx=text;idx=text;...         names (realm, raid, boss, guild)
--   R~sid~rec;rec;...                   records (idx refer to D)
--   E~sid~total                         stream end
--   Q~slug / L~slug~i~n~part            a raid's boss list, asked / sent in parts
local FEED = "WDIF1"
local FEED_MARGIN = 14 * 86400   -- re-send records this much older than "since" (late uploads)
local feedq = {}
local feedSent, feedTotal = 0, 0    -- master: the stream going out
local pendingSince                   -- master: a stream to start (lowest "since" asked)
local lastStream = 0
local want                           -- player: { at, since } when to ask
local recv = {}                      -- player: streams coming in, by sid
local logParts = {}                  -- player: raid boss lists coming in, by slug
local askedLog = {}
local DIG = "0123456789abcdefghijklmnopqrstuvwxyz"

local function b36(n)
	n = floor(tonumber(n) or 0)
	if n <= 0 then return "0" end
	local s = ""
	while n > 0 do
		local d = math.mod(n, 36)
		s = string.sub(DIG, d + 1, d + 1) .. s
		n = floor(n / 36)
	end
	return s
end
local function unb36(s) return tonumber(s or "", 36) end
local function clean(s) return (string.gsub(s or "", "[~;,|=\n]", " ")) end

local function opts() return WhoDidItDB and WhoDidItDB.opts or {} end
-- the characters allowed to be the master, per realm
B.MASTERS = {
	["Y'Shaarj"] = { Upsilon = true },
	["C'Thun"]   = { Upsy = true },
	["N'Zoth"]   = { Upsi = true },
}
local function trusted(name)
	local list = B.MASTERS[B.Realm()]
	return name and list and list[name] and true or false
end
B.Trusted = trusted
function B.CanMaster() return trusted(UnitName("player")) end
-- the master: one of those characters, /wdi master on, with the sync helper's own file on this PC
function B.IsMaster() return opts().master and B.CanMaster() and B.chronRaw ~= nil and not B.chronFeed end
local function canServe() return B.IsMaster() end
local servers = {}   -- other servers heard lately: name -> { name, synced, master, at }
local function better(a, b)
	if (a.master and 1 or 0) ~= (b.master and 1 or 0) then return a.master end
	if a.synced ~= b.synced then return a.synced > b.synced end
	return a.name < b.name
end
-- am I the one who talks on this realm right now?
local function isLead()
	if not canServe() then return false end
	local me = { name = UnitName("player"), synced = B.chron and B.chron.synced or 0, master = B.IsMaster() }
	local now = GetTime()
	for _, s in pairs(servers) do
		if now - s.at < 75 and better(s, me) then return false end
	end
	return true
end
B.IsLead = isLead
local function feedOn() return opts().shareBoard and not opts().noFeed end

local function feedSend(msg)
	tinsert(feedq, FEED .. "~" .. msg)
end

-- the saved feed (players): raw lines by identity, and raid boss lists
local function store()
	local f = WhoDidItDB.feed
	if not f then
		f = { synced = 0, lines = {}, logs = {} }
		WhoDidItDB.feed = f
	end
	return f
end

-- the feed as the same text the sync file has, for LoadChronicle
function B.FeedText()
	local f = WhoDidItDB and WhoDidItDB.feed
	if not f or not f.synced or f.synced == 0 then return nil end
	if f.text and not f.dirty then return f.text end
	local out = { "WDICHRON|2|" .. f.synced .. "|" .. (f.server or "?") .. "|90|ok" }
	for _, line in pairs(f.lines) do tinsert(out, line) end
	for _, line in pairs(f.logs) do tinsert(out, line) end
	f.text = table.concat(out, "\n") .. "\n"
	f.dirty = nil
	return f.text
end

------------------------------------------------------------------ master side

-- pack the master's lines newer than "since" into a stream
local function buildStream(since)
	local raw = B.chronRaw
	if not raw then return end
	local sid = b36(time())
	local dict, n, out, buf, names = {}, 0, {}, {}, {}
	local recs = 0
	-- new names wait in "names" and go out (packed) just before the records using them
	local function idx(s)
		s = clean(s)
		if not dict[s] then
			n = n + 1
			dict[s] = b36(n)
			tinsert(names, dict[s] .. "=" .. s)
		end
		return dict[s]
	end
	local blen = 0
	local function flush()
		local pack, plen = {}, 0
		for i = 1, getn(names) do
			if plen + string.len(names[i]) + 1 > 220 then
				tinsert(out, "D~" .. sid .. "~" .. table.concat(pack, ";"))
				pack, plen = {}, 0
			end
			tinsert(pack, names[i])
			plen = plen + string.len(names[i]) + 1
		end
		if getn(pack) > 0 then tinsert(out, "D~" .. sid .. "~" .. table.concat(pack, ";")) end
		names = {}
		if getn(buf) > 0 then tinsert(out, "R~" .. sid .. "~" .. table.concat(buf, ";")) end
		buf, blen = {}, 0
	end
	for line in string.gfind(raw, "[^\n]+") do
		local t = string.sub(line, 1, 2)
		if t == "C|" or t == "K|" then
			local p = {}
			for part in string.gfind(line .. "|", "(.-)|") do tinsert(p, part) end
			local ended = tonumber(t == "C|" and p[7] or p[8]) or 0
			if since == 0 or ended >= since - FEED_MARGIN then
				local rec
				if t == "C|" then
					-- C|realm|instance|guild|faction|secs|ended|players|slug
					rec = "C" .. idx(p[2]) .. "," .. idx(p[3]) .. "," .. idx(p[4]) .. "," .. string.sub(p[5] or "?", 1, 1) .. ","
						.. (p[6] or "") .. "," .. b36(p[7]) .. "," .. b36(p[8]) .. "," .. clean(p[9])
				else
					-- K|realm|instance|boss|guild|faction|secs|ended|players|slug
					rec = "K" .. idx(p[2]) .. "," .. idx(p[3]) .. "," .. idx(p[4]) .. "," .. idx(p[5]) .. "," .. string.sub(p[6] or "?", 1, 1) .. ","
						.. (p[7] or "") .. "," .. b36(p[8]) .. "," .. b36(p[9]) .. "," .. clean(p[10])
				end
				if blen + string.len(rec) + 1 > 220 then flush() end
				tinsert(buf, rec)
				blen = blen + string.len(rec) + 1
				recs = recs + 1
			end
		end
	end
	flush()
	local c = B.chron
	feedSend("B~" .. sid .. "~" .. (c and c.synced or 0) .. "~" .. since .. "~" .. getn(out) .. "~" .. clean(c and c.server or "?"))
	for i = 1, getn(out) do feedSend(out[i]) end
	feedSend("E~" .. sid .. "~" .. getn(out))
	feedSent, feedTotal = 0, getn(out) + 2
	lastStream = GetTime()
	return recs
end

-- a raid's boss list, in parts that fit a chat message
local function sendLog(slug)
	local line = B.chronRawL and B.chronRawL[slug]
	if not line then return end
	local parts = {}
	local i = 1
	while i <= string.len(line) do
		tinsert(parts, string.sub(line, i, i + 199))
		i = i + 200
	end
	for k = 1, getn(parts) do
		-- chat treats | as the start of a colour / link code: send it as ^
		local part = string.gsub(string.gsub(parts[k], "~", " "), "|", "^")
		feedSend("L~" .. clean(slug) .. "~" .. k .. "~" .. getn(parts) .. "~" .. part)
	end
end

------------------------------------------------------------------ player side

local function applyStream(s, sender)
	local f = store()
	for key, line in pairs(s.lines) do f.lines[key] = line end
	f.synced, f.server, f.from, f.dirty = s.synced, s.server, sender, true
	if B:LoadChronicle() then
		B.rivalsDirty = true
		if W.UI and W.UI.mode == "rankings" then W.UI:Refresh() end
	end
end

local function decode(s, rec)
	local p = {}
	for part in string.gfind(string.sub(rec, 2) .. ",", "(.-),") do tinsert(p, part) end
	local d = s.dict
	local fac = { A = "Alliance", H = "Horde", M = "Mixed", U = "Unknown" }
	if string.sub(rec, 1, 1) == "C" then
		local realm, inst, guild = d[p[1]], d[p[2]], d[p[3]]
		if not (realm and inst and guild) then return end
		s.lines["C|" .. realm .. "|" .. inst .. "|" .. guild] = "C|" .. realm .. "|" .. inst .. "|" .. guild .. "|" .. (fac[p[4]] or "Unknown")
			.. "|" .. (p[5] or "") .. "|" .. (unb36(p[6]) or 0) .. "|" .. (unb36(p[7]) or 0) .. "|" .. (p[8] or "")
	else
		local realm, inst, boss, guild = d[p[1]], d[p[2]], d[p[3]], d[p[4]]
		if not (realm and inst and boss and guild) then return end
		s.lines["K|" .. realm .. "|" .. inst .. "|" .. boss .. "|" .. guild] = "K|" .. realm .. "|" .. inst .. "|" .. boss .. "|" .. guild .. "|" .. (fac[p[5]] or "Unknown")
			.. "|" .. (p[6] or "") .. "|" .. (unb36(p[7]) or 0) .. "|" .. (unb36(p[8]) or 0) .. "|" .. (p[9] or "")
	end
end

-- ask the master for one raid's boss list (when someone opens it)
function B:AskLog(slug)
	if not slug or not B.master or askedLog[slug] then return false end
	askedLog[slug] = GetTime()
	feedSend("Q~" .. clean(slug))
	return true
end

-- what's happening, for the Rankings bar: { from, got, total } while receiving
function B:FeedStatus()
	for _, s in pairs(recv) do
		if GetTime() - s.at < 60 then return { from = s.from, got = s.got, total = s.total } end
	end
	if feedTotal > 0 and feedSent < feedTotal then return { master = true, relay = not B.IsMaster(), got = feedSent, total = feedTotal } end
end

function B:FeedReceive(msg, sender)
	local p = {}
	for part in string.gfind(msg .. "~", "(.-)~") do tinsert(p, part) end
	local kind = p[2]
	local me = UnitName("player")
	if sender == me then return end
	-- times only ever come from the master's characters; anyone may ask (A, Q)
	if kind ~= "A" and kind ~= "Q" and not trusted(sender) then return end
	if kind == "H" then
		local s = { name = sender, synced = tonumber(p[3]) or 0, n = tonumber(p[4]) or 0, master = (p[6] == "1"), at = GetTime() }
		servers[sender] = s
		-- B.master: the best server heard lately (shown in Rankings, asked for raid details)
		if not B.master or GetTime() - B.master.at > 75 or B.master.name == sender or better(s, B.master) then B.master = s end
		if not feedOn() or B.IsMaster() then return end
		local mine = WhoDidItDB.feed and WhoDidItDB.feed.synced or 0
		-- the helper's own file counts too: no need to ask if it's as fresh
		local c = B.chron
		if c and not B.chronFeed and (c.synced or 0) >= s.synced then return end
		if s.synced > mine and not want then want = { at = GetTime() + 3 + math.random(12), since = mine } end
	elseif kind == "A" then
		local since = tonumber(p[3]) or 0
		if want and since <= want.since then want = nil end   -- their stream will cover us
		if isLead() then pendingSince = math.min(pendingSince or since, since) end
	elseif kind == "Q" then
		if isLead() and p[3] then sendLog(p[3]) end
	elseif kind == "B" then
		if not feedOn() or B.IsMaster() then return end
		local since, synced = tonumber(p[5]) or 0, tonumber(p[4]) or 0
		local mine = WhoDidItDB.feed and WhoDidItDB.feed.synced or 0
		-- only useful if it starts where we are (or from scratch) and is newer
		if synced <= mine or (since > 0 and since > mine) then return end
		recv[p[3]] = { since = since, synced = synced, total = tonumber(p[6]) or 0, server = p[7], got = 0, dict = {}, lines = {}, from = sender, at = GetTime() }
		want = nil
	elseif kind == "D" then
		local s = recv[p[3]]
		if s then
			for entry in string.gfind((p[4] or "") .. ";", "(.-);") do
				local _, _, k, v = string.find(entry, "^([^=]+)=(.*)$")
				if k then s.dict[k] = v end
			end
			s.got = s.got + 1
			s.at = GetTime()
		end
	elseif kind == "R" then
		local s = recv[p[3]]
		if s then
			for rec in string.gfind((p[4] or "") .. ";", "(.-);") do
				if rec ~= "" then decode(s, rec) end
			end
			s.got = s.got + 1
			s.at = GetTime()
		end
	elseif kind == "E" then
		local s = recv[p[3]]
		recv[p[3]] = nil
		-- a missed message means a gap: don't trust it, ask again next minute
		if s and s.got == s.total then applyStream(s, sender) end
	elseif kind == "L" then
		local slug, i, n = p[3], tonumber(p[4]), tonumber(p[5])
		if not (slug and i and n) or not askedLog[slug] then return end
		local parts = logParts[slug] or {}
		logParts[slug] = parts
		parts[i] = p[6] or ""
		for k = 1, n do if not parts[k] then return end end
		local line = string.gsub(table.concat(parts, "", 1, n), "%^", "|")
		logParts[slug] = nil
		if string.sub(line, 1, 2) == "L|" then
			local f = store()
			f.logs[slug] = line
			f.dirty = true
			if B:LoadChronicle() and W.UI and W.UI.mode == "rankings" then W.UI:Refresh() end
		end
	end
end

W:On("CHAT_MSG_CHANNEL", function(msg, sender, lang, chanFull, target, flags, zoneId, chanNum, chanName)
	if not msg or string.sub(msg, 1, string.len(FEED) + 1) ~= FEED .. "~" then return end
	local name = strlower(chanName or "")
	if name ~= strlower(CHANNEL) and not string.find(strlower(chanFull or ""), strlower(CHANNEL), 1, true) then return end
	if not WhoDidItDB then return end
	B:FeedReceive(msg, sender)
end)

-- one feed message a second; the lead's "what I have" every minute
-- (first one 20-40s after login, so a better server can be heard first)
local lastHello
W:Every(1, function()
	if not WhoDidItDB or not opts().shareBoard then return end
	local now = GetTime()
	if not lastHello then lastHello = now - 40 + math.random(20) end
	if isLead() then
		if now - lastHello > 60 and chanId() then
			lastHello = now
			local c = B.chron
			feedSend("H~" .. (c and c.synced or 0) .. "~" .. (B.chronLines or 0) .. "~" .. clean(c and c.server or "?") .. "~" .. (B.IsMaster() and "1" or "0"))
		end
		-- start a stream someone asked for (one at a time, not more than every 20s)
		if pendingSince and getn(feedq) == 0 and now - lastStream > 20 then
			local since = pendingSince
			pendingSince = nil
			buildStream(since)
		end
	elseif want and now >= want.at then
		local mine = WhoDidItDB.feed and WhoDidItDB.feed.synced or 0
		want = nil
		if B.master and B.master.synced > mine then feedSend("A~" .. mine) end
	end
	if getn(feedq) == 0 then return end
	local id = chanId()
	if not id then B:Join() return end
	SendChatMessage(tremove(feedq, 1), "CHANNEL", nil, id)
	if feedSent < feedTotal then feedSent = feedSent + 1 end
end)
