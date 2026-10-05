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
	if not ReadCustomFile then return false end
	local ok, s = pcall(ReadCustomFile, CHRON_FILE)
	if not ok or type(s) ~= "string" or s == "" then
		local had = B.chron ~= nil
		B.chron = nil
		chronHead = nil
		return had
	end
	local _, _, head = string.find(s, "^([^\n]*)")
	if head == chronHead then return false end
	chronHead = head

	local data = { realms = {}, bosses = {}, zones = {}, me = {} }
	for line in string.gfind(s, "[^\n]+") do
		local p = splitBar(line)
		local t = p[1]
		if t == "WDICHRON" then
			data.synced, data.server, data.days, data.status = tonumber(p[3]), p[4], tonumber(p[5]), p[6]
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
				if secs and secs <= CLEAR_MAX then me.clears[zone] = { t = secs, d = tonumber(p[6]), g = p[7], slug = p[8], chron = true } end
			else
				local secs = tonumber(p[6])
				if secs and secs <= KILL_MAX then me.kills[p[5]] = { t = secs, d = tonumber(p[7]), g = p[8], slug = p[9], chron = true } end
			end
		elseif t == "C" or t == "K" then
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
			-- broken logs (a "clear" spanning days) would wreck the boards
			local maxSecs = (kind == "clears") and CLEAR_MAX or KILL_MAX
			if realm ~= "" and guild and guild ~= "" and secs and secs <= maxSecs then
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

-- re-read the sync file every minute; refresh the window when it changed
W:Every(60, function()
	if not WhoDidItDB then return end
	if B:LoadChronicle() and W.UI and W.UI.mode == "rankings" then W.UI:Refresh() end
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

------------------------------------------------------------------ banter
-- A fun line in the shout channel after every boss kill and full clear:
-- our time against our own best and against the other guilds on the realm,
-- mocking us or bigging us up. Placeholders: {what} boss / instance,
-- {time} our time, {d} the difference, {prev} our old best, {g} the other
-- guild, {rank} / {of} our place on the realm.

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
		"{what} in {time} - #1 on the realm! Bow down.",
		"Fastest {what} on the server: {time}. Everyone else is playing for second.",
		"{time} on {what}. #1 out of {of}. Somebody call the server.",
		"Realm record on {what}: {time}. Put it on the guild banner.",
	},
	rank = {
		"{what} in {time} puts us #{rank} of {of} on the realm.",
		"#{rank} of {of} on {what} with {time}. Climbing.",
		"{what}: {time}, #{rank} of {of}. {g} is next on the hit list.",
		"{time} on {what} - #{rank} of {of}. Not bad, not legendary.",
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

-- kind "kill" or "clear"; key = board key; old = our guild's best before this one
function B:BanterLine(kind, key, what, secs, old, realm, guild)
	local board = B:Board(realm, (kind == "kill") and "kills" or "clears", key, "All")
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

	local improved = (not old) or secs < old.t
	local cats, total = {}, 0
	local function add(c, w) tinsert(cats, { c, w }); total = total + w end
	if not old then add("first", 2) end
	if old and improved then add("pb", 3) end
	if not improved then add("slower", 3) end
	if rank == 1 and of > 1 then add("top", 5) end
	if passed then add("beat", 4) elseif behind then add("beat", 1) end
	if ahead then add("behind", improved and 1 or 3) end
	if of > 2 then add("rank", 1) end

	local roll, cat = math.random() * total, cats[1][1]
	for i = 1, getn(cats) do
		roll = roll - cats[i][2]
		if roll <= 0 then cat = cats[i][1]; break end
	end

	local other = passed or behind
	local v = {
		what = what, time = B.Fmt(secs), prev = old and B.Fmt(old.t) or "-",
		rank = tostring(rank), of = tostring(of), g = ahead and ahead[1] or (other and other[1]) or "the next guild",
	}
	if cat == "pb" then v.d = B.Fmt(old.t - secs)
	elseif cat == "slower" then v.d = B.Fmt(secs - old.t)
	elseif cat == "beat" then v.g = other[1]; v.d = B.Fmt(other[2].t - secs)
	elseif cat == "behind" then v.g = ahead[1]; v.d = B.Fmt(secs - ahead[2].t)
	else v.d = "" end

	local line = string.gsub(pick(cat), "{(%w+)}", function(k) return v[k] or "" end)
	return ((kind == "clear") and "[WhoDidIt] CLEAR: " or "[WhoDidIt] ") .. line
end

function B:Banter(kind, key, what, secs, old, realm, guild, channel)
	local line = B:BanterLine(kind, key, what, secs, old, realm, guild)
	W:Send({ line }, channel, {})   -- {} = colour times and numbers
end

-- a made-up kill so you can preview the banter (your own chat only)
function B:BanterTest()
	local bosses = { "Ragnaros", "Nefarian", "Onyxia", "Hakkar", "Patchwerk", "C'Thun" }
	local what = bosses[math.random(getn(bosses))]
	local secs = 60 + math.random(240)
	local old = (math.random(4) > 1) and { t = secs + math.random(-40, 40) } or nil
	W:Send({ B:BanterLine("kill", what, what, secs, old, B.Realm(), B.MyGuild() or "Your Guild") }, "SELF", {})
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

	-- guild best (and the banter, which compares against the best *before* this kill)
	local oldKill = guild and B:GuildBest(realm, "kills", rec.enc, guild)
	if guild and B:Merge("kills", realm, rec.enc, guild, { t = secs, d = now, f = fac, n = size, by = me }) then
		local rank, of = B:Rank(realm, "kills", rec.enc, guild, "All")
		announce("new " .. guild .. " best on " .. rec.enc .. ": |cffffffff" .. B.Fmt(secs) .. "|r (#" .. rank .. " of " .. of .. " on " .. realm .. ")")
		B:Share("K", guild, fac, rec.enc, secs, now, size)
	end
	if guild and WhoDidItDB.opts.banterKills then
		B:Banter("kill", rec.enc, rec.enc, secs, oldKill, realm, guild)
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
	if guild and WhoDidItDB.opts.banterClears then
		B:Banter("clear", r.zone, title, cs, oldClear, realm, guild)
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
	B:Merge(kind == "K" and "kills" or "clears", B.Realm(), key, guild,
		{ t = secs, d = d, f = fac, n = n, by = sender, net = true })
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
