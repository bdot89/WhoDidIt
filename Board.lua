--[[--------------------------------------------------------------------
	WhoDidIt - rankings board: boss kill times and full instance clears

	Records come from fights WhoDidIt records itself:
	  - kill time  = the boss fight's duration (first hit -> kill)
	  - clear time = first combat in the instance -> last required boss
	    (Data.lua D.clears) killed in the same run
	The guild of a record is the raid's majority guild (>= half the raid).

	Every guild's times on the boards come only from the maintainer's master
	feed and the download (Chronicle's logs). A time your own WhoDidIt
	records is kept on your PC (your own board and personal bests); players
	don't share raid times with each other.
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

-- a guild name as WoW allows it: letters and spaces, 24 characters at most.
-- Anything else (links, colour codes, digits, symbols) is dropped on arrival.
local function okGuild(g)
	return g and g ~= "" and string.len(g) <= 24 and not string.find(g, "[%c%d%p]") and true or false
end
B.OkGuild = okGuild

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
	if f and B.FeedSynced() > 0 and not (WhoDidItDB.opts and WhoDidItDB.opts.noFeed) then
		local _, _, a = string.find(s or "", "^WDICHRON|%d+|(%d+)")
		if not s or B.FeedSynced() > (tonumber(a) or 0) then s, fromFile = B.FeedText(), false end
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
		elseif t == "C" or t == "K" or t == "C2" or t == "K2" then
			-- C2 / K2: a guild's best since the raid scaling change, on the "+" boards
			local post = (t == "C2" or t == "K2")
			if not post then B.chronLines = B.chronLines + 1 end
			local realm = p[2]
			local zone = CHRON_ZONE[p[3]] or p[3]
			local kind, key, guild, fac, secs, d, n, slug
			if t == "C" or t == "C2" then
				kind, key, guild, fac, secs, d, n, slug = "clears", zone, p[4], p[5], tonumber(p[6]), tonumber(p[7]), tonumber(p[8]), p[9]
			else
				kind, key, guild, fac, secs, d, n, slug = "kills", p[4], p[5], p[6], tonumber(p[7]), tonumber(p[8]), tonumber(p[9]), p[10]
				data.bosses[zone] = data.bosses[zone] or {}
				data.bosses[zone][key] = true
			end
			-- broken logs (a "clear" spanning days, a 4-second boss) would wreck the boards
			local maxSecs = (kind == "clears") and CLEAR_MAX or KILL_MAX
			local minSecs = (kind == "clears") and CLEAR_MIN or CHRON_KILL_MIN
			if realm ~= "" and okGuild(guild) and secs and secs >= minSecs and secs <= maxSecs then
				local r = data.realms[realm]
				if not r then
					r = { kills = {}, clears = {} }
					data.realms[realm] = r
				end
				-- the all-time board, and the "since the scaling change" one: C2 / K2
				-- lines, and any all-time best that's itself from since then
				local kinds = post and { kind .. "+" } or { kind }
				if not post and d and W.Data.SCALING and d >= W.Data.SCALING.at then tinsert(kinds, kind .. "+") end
				for ki = 1, getn(kinds) do
					local k = kinds[ki]
					r[k] = r[k] or {}
					local list = r[k][key]
					if not list then
						list = {}
						r[k][key] = list
					end
					local old = list[guild]
					if not old or secs < old.t then
						list[guild] = { t = secs, d = d, f = fac, n = n, slug = slug, chron = true }
					end
				end
				data.zones[zone] = true
			end
		end
	end
	B.chron = data
	-- the master notes which times are new or changed, so updates send only those
	if fromFile and B.NoteMasterLines then B.NoteMasterLines(s, data.synced) end
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
	-- a time since the raid scaling change also goes on the "since" board
	local s = W.Data.SCALING
	if s and string.sub(kind, -1) ~= "+" and rec.d and rec.d >= s.at then
		B:Merge(kind .. "+", realm, key, guild, rec)
	end
	r[kind] = r[kind] or {}
	local list = r[kind][key]
	if not list then
		list = {}
		r[kind][key] = list
	end
	local old = list[guild]
	if old and old.t <= rec.t then return false end
	list[guild] = rec
	-- keep the 60 fastest guilds per board, so the saved boards can't grow forever
	local n, slowest, slowT, mine = 0, nil, -1, B.MyGuild()
	for g, r2 in pairs(list) do
		n = n + 1
		if g ~= mine and r2.t > slowT then slowest, slowT = g, r2.t end
	end
	if n > 60 and slowest then
		list[slowest] = nil
		if slowest == guild then return false end
	end
	return true
end

B.ALL = "All realms"

-- before the raid scaling change (Data.lua D.SCALING)? Rankings marks those times.
-- Every board has a twin with only the times since: kind .. "+" ("kills+", "clears+").
function B.PrePatch(rec)
	local s = W.Data.SCALING
	return s and rec and rec.d and rec.d > 0 and rec.d < s.at and true or false
end
function B.PostKind(kind) return kind .. "+" end

-- once: raid times other players' WhoDidIt sent before 1.23.1 go, so the boards
-- hold only the master's (Chronicle) times and your own
function B:PurgeShared()
	if not WhoDidItDB or WhoDidItDB.sharedPurged then return end
	for _, r in pairs(WhoDidItDB.board or {}) do
		if type(r) == "table" then
			for kind, keys in pairs(r) do
				if type(keys) == "table" and (kind == "kills" or kind == "clears" or kind == "kills+" or kind == "clears+") then
					for _, list in pairs(keys) do
						for g, rec in pairs(list) do
							if type(rec) == "table" and rec.net then list[g] = nil end
						end
					end
				end
			end
		end
	end
	WhoDidItDB.sharedPurged = true
end

-- once: times recorded before this version that are from since the change
-- go on the "since" boards too
function B:SplitEra()
	local s = W.Data.SCALING
	if not s or not WhoDidItDB or WhoDidItDB.eraSplit == s.at then return end
	for realm, r in pairs(WhoDidItDB.board or {}) do
		if type(r) == "table" then
			for _, kind in ipairs({ "kills", "clears" }) do
				for key, list in pairs(r[kind] or {}) do
					for g, rec in pairs(list) do
						if rec.d and rec.d >= s.at then B:Merge(kind .. "+", realm, key, g, rec) end
					end
				end
			end
		end
	end
	WhoDidItDB.eraSplit = s.at
end

-- guild -> best record on one realm, WhoDidIt and Chronicle merged
local function realmBoard(realm, kind, key)
	local merged = {}
	local mine = WhoDidItDB.board and WhoDidItDB.board[realm]
	for g, rec in pairs(mine and mine[kind] and mine[kind][key] or {}) do merged[g] = rec end
	local c = B.chron and B.chron.realms[realm]
	if c and c[kind] and c[kind][key] then
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

-- (the guild's Hall of Fame: which guild a fight belongs to)
function B.RaidGuild() return (raidGuild()) end

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
	-- (raiders who aren't lead or assist don't take part: theirs shows in their own chat)
	if W.Shout:Channel() == "SELF" or (not inRaid and GetNumPartyMembers() == 0) or not W.CanLead() then fn() return end
	local c = claims[tag] or { names = {} }
	c.at, c.fn = GetTime(), fn
	c.names[UnitName("player")] = true
	claims[tag] = c
	SendAddonMessage(CLAIM, tag, inRaid and "RAID" or "PARTY")
end

W:On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
	if prefix ~= CLAIM or not msg or not sender or not W.CanLead(sender) then return end
	local c = claims[msg]
	if not c then
		c = { names = {}, at = GetTime() }
		claims[msg] = c
	end
	c.names[sender] = true
end)

-- whoever won a claim has a few seconds to really post it; if nothing from
-- them shows up (a modified client, a disconnect), the next one in line posts
local waiting = {}   -- { fn, at }: at = when to post if nobody else has
local function heardPost(msg, sender)
	if not sender or sender == UnitName("player") or not msg or not string.find(msg, "WhoDidIt]", 1, true) then return end
	waiting = {}
end
for _, ev in ipairs({ "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_PARTY",
	"CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL" }) do
	W:On(ev, heardPost)
end

W:Every(0.5, function()
	local now = GetTime()
	for tag, c in pairs(claims) do
		if now - c.at > 2 then
			if c.fn then
				local first, mine = nil, 0
				local me = UnitName("player")
				for n in pairs(c.names) do
					if not first or n < first then first = n end
					if n < me then mine = mine + 1 end
				end
				-- second in line waits 6s, third 12s...
				if first == me then c.fn()
				elseif first then tinsert(waiting, { fn = c.fn, at = now + 6 * mine }) end
			end
			claims[tag] = nil
		end
	end
	for i = getn(waiting), 1, -1 do
		if now >= waiting[i].at then
			local fn = waiting[i].fn
			tremove(waiting, i)
			fn()
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
							db.seen[id] = rec.d
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
	for id, d in pairs(db.seen) do
		if d == true or now - (tonumber(d) or 0) > RIVAL_DAYS * 86400 then db.seen[id] = nil end
	end
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

-- channel: nil = the Post to channel, "SELF" = only you
function B:PostRivals(zone, list, channel)
	local lines = B:RivalLines(zone, list)
	if not lines then
		W.Print("Nobody has beaten our " .. (W.Data.instanceTitle[zone or ""] or zone or "") .. " times in the last " .. RIVAL_DAYS .. " days.")
		return
	end
	for _, e in ipairs(list or B:Rivals(zone)) do e.posted = true end
	W:ConfirmSend(lines, channel, B:ChatColours())   -- other guilds' names: you see it before it's posted
end

-- entering a raid instance: show its rivals once, in your own chat only
-- (rival alerts on). Names in it come from other people, so they're never
-- posted by themselves: Post rivals (Rankings) does that on purpose.
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
	B:PostRivals(zone, fresh, "SELF")
	W.Print("|cff888888(Only you see this. Post rivals on the Rankings tab posts it to " .. W.Shout:ChannelLabel() .. ".)|r")
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
		"{time} on {what}. Write it down, it's the number to beat now.",
		"Our first {what} on record: {time}. The only way is down. The time, that is.",
		"{what} logged at {time}. Day one of the speedrun era.",
		"{time} for {what}. A personal best and a personal worst at the same time. Efficient.",
	},
	pb = {
		"{what} in {time} - {d} faster than our old best. Who even are we?!",
		"New guild best on {what}: {time}. {d} shaved off. Barbers are jealous.",
		"{d} faster than ever on {what} ({time}). Somebody check if the boss was AFK.",
		"{what} at {time}, our best ever by {d}. The grind is paying off.",
		"PB! {what} in {time}, {d} quicker than last time. Screenshot it before we wipe again.",
		"{what} melted in {time}. That's {d} off our record. Pump it.",
		"{what} in {time}. {d} faster than ever. Whoever brought the flasks: thank you.",
		"New best on {what}! {time}, beating our old {prev} by {d}. Raid leader is crying happy tears.",
		"{time} on {what}. {d} off our best. Someone tell the healers they can blink now.",
		"{what} never stood a chance: {time}, {d} faster than our {prev}.",
		"Record broken: {what} in {time}. Our old {prev} has been retired with honours.",
		"{d} faster on {what} ({time}). Same raid, new legends.",
	},
	pbtiny = {
		"{what} in {time}. A new best... by {d}. We'll take it.",
		"New record on {what}! By {d}. Don't blink or you'll miss the improvement.",
		"{time} on {what}, {d} under our best. Photo finish.",
		"{d} faster on {what}. Every tenth counts. Probably.",
		"{what}: {time}. Beat our {prev} by a whisker ({d}). Whisker included.",
	},
	pbhuge = {
		"{what} in {time}. That's {d} off our best. What happened? Who are you people?",
		"{d} faster than our old {what} record. Did we skip a phase?",
		"{what} in {time}, {d} under our {prev}. That's not an improvement, that's a rebuild.",
		"Our {what} record just dropped by {d}. The boss has filed a complaint.",
		"{time} on {what}. Old best {prev}. Someone's been reading guides.",
	},
	slower = {
		"{what} in {time}. Our best is {prev}, so that was {d} of sightseeing.",
		"{what} down in {time} - only {d} slower than our record. Only.",
		"{time} on {what}. {d} off our best. Did someone stop for a snack?",
		"{what} took {time}. Our record is {prev}. We'll pretend this one didn't happen.",
		"{d} slower than our best on {what}. The boss must have eaten its vegetables today.",
		"{what} in {time}. {d} slower than we've done it. Consumables are not decorations, people.",
		"{what} in {time}. {d} off our best. Somebody left the oven on?",
		"{time} on {what}. Our record {prev} is safe for another week.",
		"{what} down, {d} slower than our best. At least it's down.",
		"{d} slower on {what}. The repair bill says we tried our best.",
		"{what} in {time}. Not a record, but nobody released early. Growth.",
		"{time} for {what}. Our {prev} is still on the wall, untouched and smug.",
	},
	nearmiss = {
		"{what} in {time}. {d} off our best. SO close.",
		"{d} short of our {what} record. Somebody's /sit is to blame.",
		"{time} on {what}, missed our {prev} by {d}. Pain in its purest form.",
		"{what}: {d} slower than our best. One more global and it was ours.",
		"Missed the {what} record by {d}. Whoever went to pee: we know.",
	},
	disaster = {
		"{what} in {time}. That's {d} slower than our best. Were we fighting it or babysitting it?",
		"{time} on {what}. Our best is {prev}. Let's never speak of this.",
		"{what} took {d} longer than usual. Somebody check the boss for extra health.",
		"{what} in {time}. {d} slower. Hope the scenery was nice.",
		"{d} over our {what} record. The boss had time to make a cup of tea.",
	},
	speedy = {
		"{what} in {time}. Blink and you missed it.",
		"{time} on {what}. The boss barely finished its opening line.",
		"{what} was over in {time}. Loading screen took longer.",
		"{what} down in {time}. Somebody check it actually spawned.",
	},
	beat = {
		"{what} in {time} - {d} faster than {g}. Sorry not sorry, {g}.",
		"{time} on {what}. {g} took {d} longer. Somebody tell {g}.",
		"We just out-killed {g} on {what} by {d}. Respectfully.",
		"{what} in {time}: {g}, you've been passed. By {d}.",
		"{d} quicker than {g} on {what}. Get those parses up, {g}.",
		"{g} called, they want their {what} time back. It's {d} slower than ours.",
		"{what} in {time}, {d} ahead of {g}. Nothing personal.",
		"Moved past {g} on {what} by {d}. Wave as we go by.",
		"{time} on {what}. That's {d} better than {g}. Sorry, the leaderboard doesn't do participation trophies.",
		"Overtook {g} on {what}, {d} clear. Mind the gap.",
	},
	behind = {
		"{what} in {time}. {g} still did it {d} faster. Pain.",
		"{g} beat us on {what} by {d}. We'll get them next week. Probably.",
		"{d} behind {g} on {what}. So close, yet so far.",
		"{what} at {time}. {g} is {d} ahead and laughing at us right now.",
		"Only {d} slower than {g} on {what}. Only. {d}.",
		"{g} would like us to know they did {what} {d} faster. Thanks, {g}.",
		"{what} in {time}. Still {d} behind {g}. The chase continues.",
		"{d} between us and {g} on {what}. Consumes next week, everyone.",
		"{time} on {what}. Not quite {g} pace yet ({d} behind). Yet.",
		"We see you, {g}. {d} on {what}. We're coming.",
	},
	top = {
		"{what} in {time} - #1 on {realm}! Bow down.",
		"Fastest {what} on {realm}: {time}. Everyone else is playing for second.",
		"{time} on {what}. #1 out of {of} on {realm}. Somebody call the server.",
		"{realm} record on {what}: {time}. Put it on the guild banner.",
		"#1 on {realm} for {what}. {time}. The view from up here is lovely.",
		"{what} in {time}, nobody on {realm} has done it faster. Not one guild.",
		"Top of {realm} on {what} with {time}. Everybody else: the bar is right here.",
		"{time} on {what}. #1 of {of} on {realm}. Somebody update the history books.",
	},
	rank = {
		"{what} in {time} puts us #{rank} of {of} on {realm}.",
		"#{rank} of {of} on {realm} for {what} with {time}. Climbing.",
		"{what}: {time}, #{rank} of {of} on {realm}. {g} is next on the hit list.",
		"{time} on {what} - #{rank} of {of} on {realm}. Not bad, not legendary.",
		"{what} in {time}. #{rank} of {of} on {realm}, and climbing.",
		"#{rank} of {of} for {what} on {realm}. The podium can hear us coming.",
		"{time} on {what}: #{rank} on {realm}. Plenty of guilds behind us, a few to catch.",
	},
	servertop = {
		"{what} in {time} - fastest on ALL of {server}. {orealm}, take notes.",
		"Nobody on any {server} realm has done {what} faster than our {time}. Not even {orealm}.",
		"{time} on {what}: the record across every realm. {og} of {orealm} is {d} behind us.",
		"{what} in {time}. Every realm, every guild, nobody faster. Server record.",
		"The fastest {what} anywhere on {server}: {time}. Ours.",
		"{time} on {what}. #1 on every {server} realm. Someone pin this.",
	},
	realmbeat = {
		"{time} on {what} - faster than anyone on {orealm}. Their best, {og}, is {d} slower.",
		"{what} in {time}. The whole of {orealm} can't match it: {og} is {d} slower.",
		"Realm pride: {what} in {time}, {d} quicker than {orealm}'s fastest ({og}).",
		"{orealm} called. Their best {what} is {d} slower than our {time}.",
		"{what} in {time}. Good luck matching that on {orealm}: their best is {d} behind.",
		"{time} on {what}. {orealm}'s fastest is {d} slower. Cross-realm bragging rights claimed.",
	},
	realmbehind = {
		"{what} in {time}, but {og} over on {orealm} did it {d} faster. The other realm says hi.",
		"{og} of {orealm} would like a word: their {what} is {d} faster than our {time}.",
		"{time} on {what}. Meanwhile on {orealm}, {og} is {d} ahead. Cross-realm shame.",
		"{what} in {time}. {orealm}'s best is still {d} faster. They're probably bragging.",
		"{d} behind the best on {orealm} for {what}. A new target has appeared.",
		"{what} in {time}. Over on {orealm} it's {d} faster. Not that we're counting.",
	},
	revenge = {
		"Took {what} back from {g}! {time} - {d} faster than the {their} they set {ago}.",
		"{g} had {what} for about five minutes. {time} now, {d} under their {their}. Revenge served.",
		"Remember {g} beating our {what} {ago}? {time}, {d} faster. Remember that instead.",
		"{what} is ours again: {time}, {d} under the {their} {g} set {ago}.",
		"Back on top of {what}. {g} held it since {ago}. That's over now ({time}).",
		"Revenge on {what}: {time}, beating {g}'s {their} by {d}. Enjoyed that.",
	},
	chase = {
		"{g} beat our {what} {ago} ({their}) and still own it by {d}. Again. Faster.",
		"{what} in {time} - still {d} behind the {their} {g} set {ago}. They're laughing.",
		"{g}'s {their} on {what} from {ago} still stands. {d} to find. Who's slacking?",
		"{what} in {time}. {g}'s {their} from {ago} lives another day. {d} to go.",
		"Still {d} off the {their} {g} set {ago} on {what}. Next week it's ours.",
		"{g} still owns {what} ({their}, {ago}). We're {d} away. Flasks on, everyone.",
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
-- anon: for the automatic post - other guilds become "another guild" (their
-- names come from anyone's uploads; the line is said in your name)
function B:BanterLine(kind, key, what, secs, old, realm, guild, rival, anon)
	local bkind = (kind == "kill") and "kills" or "clears"
	-- other guilds: only their times since the raid scaling change (a kill today
	-- isn't measured against times set under the old scaling); our own best stays all-time
	local board = B:Board(realm, bkind .. "+", key, "All")
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
	local others = B:OtherRealms(bkind .. "+", key, realm)
	local fasterOther, slowerOther = others[1], nil
	if fasterOther and fasterOther[2].t >= secs then fasterOther = nil end
	for i = 1, getn(others) do
		if others[i][2].t > secs then slowerOther = others[i]; break end
	end

	local improved = (not old) or secs < old.t
	local cats, total = {}, 0
	local function add(c, w) tinsert(cats, { c, w }); total = total + w end
	if not old then add("first", 2) end
	if old and improved then
		add("pb", 3)
		if old.t - secs < 2 then add("pbtiny", 4) end
		if old.t - secs >= old.t * 0.15 then add("pbhuge", 4) end
	end
	if not improved then
		add("slower", 3)
		if secs - old.t < 3 then add("nearmiss", 4) end
		if secs - old.t > old.t * 0.3 then add("disaster", 3) end
	end
	if kind == "kill" and secs < 60 then add("speedy", 2) end
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
	if cat == "pb" or cat == "pbtiny" or cat == "pbhuge" then v.d = B.Fmt(old.t - secs)
	elseif cat == "slower" or cat == "nearmiss" or cat == "disaster" then v.d = B.Fmt(secs - old.t)
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

	if anon then
		v.g = "another guild"
		v.og = "the fastest guild"
	end
	local line = string.gsub(pick(cat), "{(%w+)}", function(k) return v[k] or "" end)
	return ((kind == "clear") and "[WhoDidIt] CLEAR: " or "[WhoDidIt] ") .. line
end

function B:Banter(kind, key, what, secs, old, realm, guild, rival)
	local line = B:BanterLine(kind, key, what, secs, old, realm, guild, rival, true)
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
	end
end

------------------------------------------------------------------ sharing (hidden realm channel)

local outq = {}
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


-- a ready-made message for the channel (Dungeons.lua's 5-man runs)
function B.QueueOut(msg)
	if not WhoDidItDB.opts.shareBoard then return end
	tinsert(outq, msg)
end

-- ask everyone online for their 5-man groups' runs
function B:Ask()
	if not WhoDidItDB.opts.shareBoard then return end
	tinsert(outq, PROTO .. SEP .. "Q")
	asked = GetTime()
end

-- answer a query: our 5-man groups' bests (Dungeons.lua). Raid times only
-- come from the master, so those aren't sent.
local function answer()
	if W.Runs then W.Runs:Answer() end
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
	-- a 5-man run: only taken from someone in that group (Dungeons.lua checks it)
	if kind == "D" then
		if W.Runs then W.Runs:Receive(p, sender) end
		return
	end
	-- K / C (a guild's kill / clear time) from older versions: ignored. Raid
	-- times only come from the master feed.
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
	B:PurgeShared()
	B:SplitEra()
	B:SeedSnapshot()
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
	-- (outq is sent by the channel sender at the end of the file, paced with the feed)
end)

------------------------------------------------------------------ master feed
-- The maintainer's character, running the sync helper, is the "master" (/wdi
-- master on): while it's online, its WhoDidIt feeds every other WhoDidIt user
-- on the realm with Chronicle's raid times over the hidden channel, so nobody
-- else needs anything but the addon. Only a master ever sends times (there
-- are no relays). Every minute the master says how fresh its times are;
-- anyone behind asks, and the master streams the raw lines (all of them once,
-- then only what changed) packed into chat messages. One stream serves
-- everyone listening. A raid's boss list is only sent when someone opens that
-- raid. What arrives is saved, so it's there next login.
--   H~synced~lines~server~m            what I have (every minute; m is always 1)
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
local pendingSince                   -- master: an update stream to start (lowest "since" asked)
local pendingFull                    -- master: someone needs a full copy
local lastStream, lastFull = 0, -1000
-- updates (only what changed) go out at most once an hour; a full copy at most every 30 min
local lastUpdate, UPDATE_GAP = -10000, 3600
local curSince                       -- master: "since" of the stream going out
-- Anyone may ask (A, Q), and asking makes the master talk, so asking is
-- rationed: per character one ask every 5 minutes and 6 boss lists every 10
-- minutes; streams at least a minute apart; a full copy (asked from scratch,
-- or from more than 2 days back) at most every 30 minutes, however many
-- characters ask; boss lists on their own queue of at most 40 messages.
local A_EVERY, Q_MAX, Q_WINDOW = 300, 6, 600
local STREAM_GAP, FULL_GAP, FULL_AGE, LOGQ_MAX = 60, 1800, 21 * 86400, 40
local askedA, askedQ = {}, {}        -- master: sender -> last A / { since, n } of Q
local logq, logSent = {}, {}         -- master: boss list parts to send / slug -> when
local lastAsk = -1000                -- player: when I last asked for a stream
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
-- the characters allowed to be the master, per realm: only the maintainer's.
-- A player can stop trusting one (/wdi master remove Name) - if one of these is
-- ever deleted or renamed and someone else takes the name - and trust it again
-- (/wdi master add Name), but can't add anyone else. Custom channels are split
-- by faction, so a master only feeds its own faction.
B.MASTERS = {
	["Y'Shaarj"] = { Upsilon = true },
	["C'Thun"]   = { Upsy = true },
	["N'Zoth"]   = { Upsi = true },
}
local function myMasters(realm)
	local m = WhoDidItDB and WhoDidItDB.masters
	return m and m[realm or B.Realm()]
end
local function trusted(name)
	if not name then return false end
	local list = B.MASTERS[B.Realm()]
	if not (list and list[name]) then return false end   -- only the maintainer's characters, ever
	local mine = myMasters()
	return not (mine and mine[name] == false)            -- unless you removed it
end
-- /wdi master add|remove Name: your own list of who to take the feed from
function B.SetMaster(name, on)
	name = name and string.gsub(name, "^%l", string.upper)
	if not name or name == "" or string.find(name, "[^%a]") then
		W.Print("Usage: /wdi master add|remove <character name> (on this realm)")
		return
	end
	WhoDidItDB.masters = WhoDidItDB.masters or {}
	local m = WhoDidItDB.masters[B.Realm()] or {}
	WhoDidItDB.masters[B.Realm()] = m
	local builtIn = B.MASTERS[B.Realm()] and B.MASTERS[B.Realm()][name]
	if not builtIn then
		m[name] = nil
		W.Print("Only the WhoDidIt maintainer's master characters can feed raid times: |cffffd100" .. name .. "|r can't be added. (/wdi master list shows who they are.)")
		return
	end
	m[name] = (not on) and false or nil
	W.Print(name .. (on and " |cff33ff33is trusted|r for raid times on " or " |cffff9933is no longer trusted|r for raid times on ") .. B.Realm() .. ".")
end
function B.MasterList()
	local out = {}
	for n in pairs(B.MASTERS[B.Realm()] or {}) do
		if trusted(n) then tinsert(out, n) end
	end
	table.sort(out)
	return out
end
B.Trusted = trusted
-- Being the master (sending) is only for the maintainer's characters built in
-- above; nobody else's WhoDidIt takes the feed from anyone else.
function B.CanMaster()
	local me = UnitName("player")
	local list = B.MASTERS[B.Realm()]
	return (list and me and list[me] and trusted(me)) and true or false
end
-- the master: one of those characters, /wdi master on, with the sync helper's own file on this PC
function B.IsMaster() return opts().master and B.CanMaster() and B.chronRaw ~= nil and not B.chronFeed end

local servers = {}   -- other servers heard lately: name -> { name, synced, master, at }
local function better(a, b)
	if (a.master and 1 or 0) ~= (b.master and 1 or 0) then return a.master end
	if a.synced ~= b.synced then return a.synced > b.synced end
	return a.name < b.name
end
-- am I the one who talks on this realm right now? (two master characters
-- online at once: the freshest one)
local function isLead()
	if not B.IsMaster() then return false end
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

-- The raid times that ship with WhoDidIt (RaidTimes.lua, WDI_RAIDTIMES: the
-- maintainer's last sync, published with tools\Publish-RaidTimes.cmd). On a
-- fresh install, or when they're newer than what this PC has, they go into
-- the saved feed as if a full copy had just arrived: Rankings is full at once,
-- even with the master offline, and the master feed only sends what's newer.
function B:SeedSnapshot()
	local s = WDI_RAIDTIMES
	if type(s) ~= "table" or type(s.text) ~= "string" or not tonumber(s.synced) then return end
	if not WhoDidItDB or B.FeedSynced() >= s.synced then return end
	local f = store()
	f.logAt = f.logAt or {}
	local n = 0
	for line in string.gfind(s.text, "[^\n]+") do
		local p = splitBar(line)
		local t, key = p[1], nil
		if t == "C" or t == "C2" then key = t .. "|" .. (p[2] or "") .. "|" .. (p[3] or "") .. "|" .. (p[4] or "")
		elseif t == "K" or t == "K2" then key = t .. "|" .. (p[2] or "") .. "|" .. (p[3] or "") .. "|" .. (p[4] or "") .. "|" .. (p[5] or "")
		elseif t == "L" and p[2] then
			f.logs[p[2]] = line
			f.logAt[p[2]] = s.synced
		end
		if key then f.lines[key] = line; n = n + 1 end
	end
	f.synced, f.part = s.synced, nil
	f.server = s.server or f.server
	f.from = f.from or "the WhoDidIt download"
	f.dirty = true
	B.seeded = n
end

-- how fresh the saved feed is (a stream that missed a message still counts)
function B.FeedSynced()
	local f = WhoDidItDB and WhoDidItDB.feed
	if not f then return 0 end
	return math.max(f.synced or 0, f.part or 0)
end

-- the feed as the same text the sync file has, for LoadChronicle (built when
-- it changes, kept in memory only: the lines themselves are what's saved)
local feedText
function B.FeedText()
	local f = WhoDidItDB and WhoDidItDB.feed
	local synced = B.FeedSynced()
	if not f or synced == 0 then return nil end
	f.text = nil   -- older versions saved this copy too
	if feedText and not f.dirty then return feedText end
	local out = { "WDICHRON|2|" .. synced .. "|" .. (f.server or "?") .. "|90|ok" }
	for _, line in pairs(f.lines) do tinsert(out, line) end
	for _, line in pairs(f.logs) do tinsert(out, line) end
	feedText = table.concat(out, "\n") .. "\n"
	f.dirty = nil
	return feedText
end

------------------------------------------------------------------ master side

-- a time line's identity and what can change in it: C|realm|instance|guild|...,
-- K|realm|instance|boss|guild|... (C2 / K2 the same, since the raid scaling change)
local function lineKey(line)
	local p = splitBar(line)
	local t = p[1]
	if t == "C" or t == "C2" then
		return t .. "|" .. (p[2] or "") .. "|" .. (p[3] or "") .. "|" .. (p[4] or ""), (p[6] or "") .. "|" .. (p[7] or "") .. "|" .. (p[9] or ""), tonumber(p[7]) or 0
	elseif t == "K" or t == "K2" then
		return t .. "|" .. (p[2] or "") .. "|" .. (p[3] or "") .. "|" .. (p[4] or "") .. "|" .. (p[5] or ""), (p[7] or "") .. "|" .. (p[8] or "") .. "|" .. (p[10] or ""), tonumber(p[8]) or 0
	end
end

-- The master remembers when it first saw each time (the helper's sync it came
-- in with), so an update sends only what's new or changed since the asker's copy,
-- not everything from the last two weeks. The first time, a line counts from its
-- raid's date. Only on the master's characters; lines that went away are dropped.
function B.NoteMasterLines(text, synced)
	if not (B.CanMaster and B.CanMaster()) or not WhoDidItDB or not synced then return end
	local first = (WhoDidItDB.masterSeen == nil)
	local ms = WhoDidItDB.masterSeen or { sig = {}, at = {} }
	WhoDidItDB.masterSeen = ms
	local present = {}
	for line in string.gfind(text, "[^\n]+") do
		local key, sig, ended = lineKey(line)
		if key then
			present[key] = true
			if ms.sig[key] ~= sig then
				ms.at[key] = first and ended or synced
				ms.sig[key] = sig
			end
		end
	end
	for k in pairs(ms.sig) do
		if not present[k] then ms.sig[k] = nil; ms.at[k] = nil end
	end
end

-- pack the master's lines newer than "since" into a stream
local function buildStream(since)
	local raw = B.chronRaw
	if not raw then return end
	local ms = WhoDidItDB and WhoDidItDB.masterSeen
	local sid = b36(time())
	local dict, n, out, buf, names = {}, 0, {}, {}, {}
	local recs = 0
	-- new names wait in "names" and go out (packed) just before the records using them
	local function idx(s)
		s = string.sub(clean(s), 1, 100)   -- no single entry can outgrow a chat message
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
		-- C2 / K2 (bests since the raid scaling change) go out as "c!," / "k!,": a
		-- WhoDidIt from before them reads "!" as an unknown name and skips them
		local post = (string.sub(line, 1, 3) == "C2|" or string.sub(line, 1, 3) == "K2|")
		if post then t = string.sub(line, 1, 1) .. "|" end
		if t == "C|" or t == "K|" then
			local p = {}
			for part in string.gfind(line .. "|", "(.-)|") do tinsert(p, part) end
			local ended = tonumber(t == "C|" and p[7] or p[8]) or 0
			-- what changed since the asker's copy (when the master noted it), else by raid date
			local key = lineKey(line)
			local seen = key and ms and ms.at[key]
			if since == 0 or (seen and seen > since) or (not seen and ended >= since - FEED_MARGIN) then
				local rec
				if t == "C|" then
					-- C|realm|instance|guild|faction|secs|ended|players|slug
					rec = (post and "c!," or "C") .. idx(p[2]) .. "," .. idx(p[3]) .. "," .. idx(p[4]) .. "," .. string.sub(p[5] or "?", 1, 1) .. ","
						.. (p[6] or "") .. "," .. b36(p[7]) .. "," .. b36(p[8]) .. "," .. string.sub(clean(p[9]), 1, 60)
				else
					-- K|realm|instance|boss|guild|faction|secs|ended|players|slug
					rec = (post and "k!," or "K") .. idx(p[2]) .. "," .. idx(p[3]) .. "," .. idx(p[4]) .. "," .. idx(p[5]) .. "," .. string.sub(p[6] or "?", 1, 1) .. ","
						.. (p[7] or "") .. "," .. b36(p[8]) .. "," .. b36(p[9]) .. "," .. string.sub(clean(p[10]), 1, 60)
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
	curSince = since
	if since < (c and c.synced or 0) - FULL_AGE then lastFull = lastStream end
	return recs
end

-- a raid's boss list, in parts that fit a chat message (on its own short queue)
local function sendLog(slug)
	local line = B.chronRawL and B.chronRawL[slug]
	if not line then return end
	local now = GetTime()
	if logSent[slug] and now - logSent[slug] < 30 then return end   -- just sent: everyone asking got it
	if getn(logq) + floor(string.len(line) / 200) + 1 > LOGQ_MAX then return end
	logSent[slug] = now
	local parts = {}
	local i = 1
	while i <= string.len(line) do
		tinsert(parts, string.sub(line, i, i + 199))
		i = i + 200
	end
	for k = 1, getn(parts) do
		-- chat treats | as the start of a colour / link code: send it as ^
		local part = string.gsub(string.gsub(parts[k], "~", " "), "|", "^")
		tinsert(logq, FEED .. "~L~" .. clean(slug) .. "~" .. k .. "~" .. getn(parts) .. "~" .. part)
	end
end

------------------------------------------------------------------ player side

-- a raid time's date: C|realm|instance|guild|faction|secs|ended|... / K|...|boss|...|ended|...
local function lineEnded(line)
	local p, i = {}, 0
	for part in string.gfind(line .. "|", "(.-)|") do
		i = i + 1
		p[i] = part
		if i >= 9 then break end
	end
	return tonumber((p[1] == "C" or p[1] == "C2") and p[7] or p[8]) or 0
end

-- partial: some messages went missing. Records are merged one by one, so
-- what did arrive is kept, but "synced" stays where it was and the next ask
-- starts from the same point.
local function applyStream(s, sender, partial)
	local f = store()
	local first = (f.synced or 0) == 0 and not partial
	for key, line in pairs(s.lines) do f.lines[key] = line end
	-- times older than half a year drop off (the helper reads 90 days)
	local old = time() - 180 * 86400
	for key, line in pairs(f.lines) do
		if lineEnded(line) < old then f.lines[key] = nil end
	end
	f.server, f.from, f.dirty = s.server, sender, true
	if partial then f.part = math.max(f.part or 0, s.synced) else f.synced = s.synced end
	if first then
		local n = 0
		for _ in pairs(s.lines) do n = n + 1 end
		W.Print("Raid times are in: |cffffffff" .. n .. "|r guild records from " .. sender .. ". Open |cffffd100Rankings|r to see them; they stay up to date while " .. sender .. " is online.")
	end
	if B:LoadChronicle() then
		B.rivalsDirty = true
		if W.UI and W.UI.mode == "rankings" then W.UI:Refresh() end
	end
end

local function decode(s, rec)
	local p = {}
	-- "c!," / "k!,": a best since the raid scaling change (a C2 / K2 line)
	local first = string.sub(rec, 1, 1)
	local post = (first == "c" or first == "k")
	for part in string.gfind(string.sub(rec, post and 4 or 2) .. ",", "(.-),") do tinsert(p, part) end
	local tag = string.upper(first) .. (post and "2" or "")
	local d = s.dict
	local fac = { A = "Alliance", H = "Horde", M = "Mixed", U = "Unknown" }
	if first == "C" or first == "c" then
		local realm, inst, guild = d[p[1]], d[p[2]], d[p[3]]
		if not (realm and inst and guild) then return end
		s.lines[tag .. "|" .. realm .. "|" .. inst .. "|" .. guild] = tag .. "|" .. realm .. "|" .. inst .. "|" .. guild .. "|" .. (fac[p[4]] or "Unknown")
			.. "|" .. (p[5] or "") .. "|" .. (unb36(p[6]) or 0) .. "|" .. (unb36(p[7]) or 0) .. "|" .. (p[8] or "")
	else
		local realm, inst, boss, guild = d[p[1]], d[p[2]], d[p[3]], d[p[4]]
		if not (realm and inst and boss and guild) then return end
		s.lines[tag .. "|" .. realm .. "|" .. inst .. "|" .. boss .. "|" .. guild] = tag .. "|" .. realm .. "|" .. inst .. "|" .. boss .. "|" .. guild .. "|" .. (fac[p[5]] or "Unknown")
			.. "|" .. (p[6] or "") .. "|" .. (unb36(p[7]) or 0) .. "|" .. (unb36(p[8]) or 0) .. "|" .. (p[9] or "")
	end
end

-- ask the master for one raid's boss list (when someone opens it)
function B:AskLog(slug)
	-- asked in the last minute: the answer is on its way (or never coming; then ask again)
	if not slug or not B.master or (askedLog[slug] and GetTime() - askedLog[slug] < 60) then return false end
	askedLog[slug] = GetTime()
	feedSend("Q~" .. clean(slug))
	return true
end

-- what's happening, for the Rankings bar: { from, got, total } while receiving
function B:FeedStatus()
	for _, s in pairs(recv) do
		if GetTime() - s.at < 60 then return { from = s.from, got = s.got, total = s.total, t0 = s.t0 } end
	end
	if feedTotal > 0 and feedSent < feedTotal then return { master = true, got = feedSent, total = feedTotal } end
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
		if not isLead() then return end
		local now = GetTime()
		if askedA[sender] and now - askedA[sender] < A_EVERY then return end
		if since >= (B.chron and B.chron.synced or 0) then return end            -- nothing newer to send
		if curSince and getn(feedq) > 0 and since >= curSince then return end   -- the stream going out covers it
		askedA[sender] = now
		if since < (B.chron and B.chron.synced or 0) - FULL_AGE then pendingFull = true
		else pendingSince = math.min(pendingSince or since, since) end
	elseif kind == "Q" then
		if not isLead() or not p[3] or not (B.chronRawL and B.chronRawL[p[3]]) then return end
		local now = GetTime()
		local q = askedQ[sender]
		if not q or now - q.since > Q_WINDOW then q = { since = now, n = 0 }; askedQ[sender] = q end
		if q.n >= Q_MAX then return end
		q.n = q.n + 1
		sendLog(p[3])
	elseif kind == "B" then
		if not feedOn() or B.IsMaster() then return end
		local since, synced = tonumber(p[5]) or 0, tonumber(p[4]) or 0
		local mine = WhoDidItDB.feed and WhoDidItDB.feed.synced or 0
		-- only useful if it starts where we are (or from scratch) and is newer
		if synced <= mine or (since > 0 and since > mine) then return end
		recv[p[3]] = { since = since, synced = synced, total = tonumber(p[6]) or 0, server = p[7], got = 0, dict = {}, lines = {}, from = sender, at = GetTime(), t0 = GetTime() }
		want = nil
		-- the first copy takes a while: say so (once)
		if mine == 0 and not B.toldFeed then
			B.toldFeed = true
			W.Print("Getting every guild's raid times from |cffffd100" .. sender .. "|r (about " .. math.max(1, floor((tonumber(p[6]) or 0) * 1.6 / 60 + 0.5))
				.. " min, in the background). Rankings shows the progress and how the sharing works.")
		end
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
		-- a missed message: keep what arrived, ask again from the same point later
		if s then applyStream(s, sender, s.got < s.total) end
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
			f.logAt = f.logAt or {}
			f.logAt[slug] = time()
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

-- the lead's "what I have" every minute, and streams to start (the channel sender at the end sends)
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
		-- start a stream someone asked for: one at a time, a minute apart, a full
		-- copy (which also covers every update asked) at most every 30 minutes
		if getn(feedq) == 0 and now - lastStream > STREAM_GAP then
			if pendingFull and now - lastFull > FULL_GAP then
				pendingFull, pendingSince = nil, nil
				buildStream(0)
			elseif pendingSince and now - lastUpdate > UPDATE_GAP then
				local since = pendingSince
				pendingSince = nil
				lastUpdate = now
				buildStream(since)
			end
		end
	elseif want and now >= want.at then
		local mine = WhoDidItDB.feed and WhoDidItDB.feed.synced or 0
		want = nil
		-- the master answers one ask per 10 minutes: don't ask more than every 5
		-- the master sends updates once an hour: asking every 20 minutes is plenty
		if B.master and B.master.synced > mine and now - lastAsk > 1200 then
			lastAsk = now
			feedSend("A~" .. mine)
		end
	end

	-- (feedq and logq are sent by the channel sender below, paced with the board)
end)

-- forget askers after their window (every table keyed by a name needs eviction),
-- streams whose end never came (keep what arrived), unanswered boss list asks,
-- and keep at most 200 saved boss lists
W:Every(60, function()
	local now = GetTime()
	for sid, s in pairs(recv) do
		if now - s.at > 120 then
			recv[sid] = nil
			if s.got > 0 then applyStream(s, s.from, true) end
		end
	end
	for slug, t in pairs(askedLog) do
		if now - t > 60 then askedLog[slug] = nil; logParts[slug] = nil end
	end
	local f = WhoDidItDB and WhoDidItDB.feed
	if f and f.logs then
		local n, oldest, oldT = 0, nil, nil
		for slug in pairs(f.logs) do
			n = n + 1
			local t = f.logAt and f.logAt[slug] or 0
			if not oldT or t < oldT then oldest, oldT = slug, t end
		end
		if n > 200 and oldest then
			f.logs[oldest] = nil
			if f.logAt then f.logAt[oldest] = nil end
			f.dirty = true
		end
	end
	for n, t in pairs(askedA) do if now - t > A_EVERY then askedA[n] = nil end end
	for n, q in pairs(askedQ) do if now - q.since > Q_WINDOW then askedQ[n] = nil end end
	for s, t in pairs(logSent) do if now - t > 30 then logSent[s] = nil end end
end)

------------------------------------------------------------------ the channel sender
-- Everything WhoDidIt says on the hidden channel goes out here, one message
-- at a time: boss lists first (someone is looking at that raid), then guild
-- times, then the feed. The server has a chat limit ("You must wait 7 Seconds
-- before speaking again"), and a message sent while it applies is dropped. So
-- messages go out at most every 1.6 seconds; if the limit still hits, the
-- sender waits as long as the server says, sends the dropped message again,
-- and from then on keeps 0.4 seconds more between messages (saved, up to 4).
-- That red warning is hidden when it's about WhoDidIt's own message.
local lastChan, pauseUntil, lastThrottle, lastJoin = -100, 0, -100, -100
local lastMsg                         -- { msg, q, at }: the last message sent
local function chanGap() return WhoDidItDB and WhoDidItDB.opts.chanGap or 1.6 end
B.ChanGap = chanGap

W:Every(0.2, function()
	if not WhoDidItDB or not WhoDidItDB.opts.shareBoard then return end
	local now = GetTime()
	if now < pauseUntil or now - lastChan < chanGap() then return end
	local q = (getn(logq) > 0 and logq) or (getn(outq) > 0 and outq) or (getn(feedq) > 0 and feedq)
	if not q then return end
	local id = chanId()
	if not id then
		if now - lastJoin > 5 then lastJoin = now; B:Join() end
		return
	end
	local msg = tremove(q, 1)
	lastChan = now
	lastMsg = { msg = msg, q = q, at = now }
	SendChatMessage(msg, "CHANNEL", nil, id)
	if q == feedq and feedSent < feedTotal then feedSent = feedSent + 1 end
end)

-- "You must wait 7 Seconds before speaking again": ours if we just sent something
local toldLimit
local function throttled(text)
	local _, _, n = string.find(text or "", "wait (%d+) [Ss]econds? before speaking")
	if not n then return false end
	local now = GetTime()
	if now - lastChan > 3 then return false end   -- not after one of ours: leave it alone
	if now - lastThrottle < 2 then return true end -- the same one, seen twice
	lastThrottle = now
	pauseUntil = now + tonumber(n) + 1
	local o = WhoDidItDB.opts
	o.chanGap = math.min(4, chanGap() + 0.4)
	-- the message that hit the limit was dropped: send it again
	if lastMsg and now - lastMsg.at < 3 then
		tinsert(lastMsg.q, 1, lastMsg.msg)
		if lastMsg.q == feedq and feedSent > 0 then feedSent = feedSent - 1 end
		lastMsg = nil
	end
	if not toldLimit then
		toldLimit = true
		W.Print("The server's chat limit kicked in, so WhoDidIt now sends on its hidden channel every "
			.. o.chanGap .. " seconds. Nothing to do; it remembers this.")
	end
	return true
end
if UIErrorsFrame and UIErrorsFrame.AddMessage then
	local orig = UIErrorsFrame.AddMessage
	UIErrorsFrame.AddMessage = function(self, text, a1, a2, a3, a4, a5)
		if throttled(text) then return end
		return orig(self, text, a1, a2, a3, a4, a5)
	end
end
W:On("CHAT_MSG_SYSTEM", function(text) throttled(text) end)
