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

-- realms we have data for (current realm first)
function B:Realms()
	local list = { B.Realm() }
	for realm in pairs(WhoDidItDB.board or {}) do
		if realm ~= list[1] then tinsert(list, realm) end
	end
	return list
end

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

-- sorted { guild, rec } list, faction "All" or a faction name
function B:Board(realm, kind, key, faction)
	local r = B:DB(realm)
	local list = {}
	for g, rec in pairs(r[kind][key] or {}) do
		if faction == "All" or rec.f == faction then tinsert(list, { g, rec }) end
	end
	table.sort(list, function(a, b) return a[2].t < b[2].t end)
	return list
end

-- rank (1-based) of a guild on a board, and how many guilds are on it
function B:Rank(realm, kind, key, guild, faction)
	local list = B:Board(realm, kind, key, faction)
	for i = 1, getn(list) do
		if list[i][1] == guild then return i, getn(list) end
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

	-- guild best
	if guild and B:Merge("kills", realm, rec.enc, guild, { t = secs, d = now, f = fac, n = size, by = me }) then
		local rank, of = B:Rank(realm, "kills", rec.enc, guild, "All")
		announce("new " .. guild .. " best on " .. rec.enc .. ": |cffffffff" .. B.Fmt(secs) .. "|r (#" .. rank .. " of " .. of .. " on " .. realm .. ")")
		B:Share("K", guild, fac, rec.enc, secs, now, size)
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
