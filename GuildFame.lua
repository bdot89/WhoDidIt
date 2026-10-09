--[[--------------------------------------------------------------------
	WhoDidIt - the guild's Hall of Fame

	Every fight a guild member records adds to one Hall of Fame the whole
	guild sees, also raids you weren't in. Nothing runs outside the game:
	the guild's WhoDidIt users swap fights on the hidden guild addon channel
	(WDIG) whenever they're online together.

	A fight goes out as a "card": who was there (class, deaths), hero and
	blame points by kind per player, the fight's MVP and most to blame,
	and its two best plays and two worst blunders. Each card is
	"recorder:number". Every WhoDidIt keeps, per recorder, how far it has
	them all ("have"), says so at login and when you click Share with guild
	(V), and the others send what it's missing (the recorder itself first;
	anyone else waits a little and skips what it hears someone send).
	  V~Name=12,Name=40,...          what I have, per recorder
	  C~id~part~parts~text           a card, in chunks
	  X~id~enc;at;dur                a card that doesn't count (see below)
	  F~recorder~number              nothing before this one is kept: skip it
	The same fight recorded by several members counts once: the card with the
	smallest id, the same on every PC, so everyone gets the same tally.
	Your own fights are only sent once you've said yes (asked once);
	receiving and showing the guild's is always on.

	Only your guild's members can send on the guild channel, and each card is
	checked: names, classes, points, sizes and its number (1 to 100000; what
	to send someone comes from the ids held, never a range of numbers). A card
	isn't tied to who sent it: a member can send one in someone else's name.
	Cards of a guild other than yours are ignored. Kept: 800 cards per guild
	(older ones are added up into a total and dropped), 3 guilds.
----------------------------------------------------------------------]]

local W = WhoDidIt
local G = {}
W.GuildFame = G

local getn, tinsert, tremove, floor = table.getn, table.insert, table.remove, math.floor
local PREFIX = "WDIG"
local MAX_CARDS, MAX_META, MAX_GUILDS = 800, 4000, 3
local PER_ANSWER = 40      -- cards sent for one request
local CHUNK = 200          -- characters of a card per message
local SEND_GAP = 0.4       -- seconds between messages
local MAX_TOP = 40         -- best plays / worst blunders kept
local TWIN_AT, TWIN_DUR = 300, 20   -- the same fight: started within 5 minutes, lasted within 20 seconds
-- the number in a card id comes from other players: 1 to MAX_ID, and nothing loops over
-- a range of them (answer() goes through the ids held). A card in your own name moves
-- your own count on by at most SELF_JUMP.
local MAX_ID, SELF_JUMP = 100000, 1000

local CLASS = { WARRIOR = "Wa", PALADIN = "Pa", HUNTER = "Hu", ROGUE = "Ro", PRIEST = "Pr",
	SHAMAN = "Sh", MAGE = "Ma", WARLOCK = "Wl", DRUID = "Dr" }
local CLASS_OF = {}
for k, v in pairs(CLASS) do CLASS_OF[v] = k end

local function me() return UnitName("player") or "?" end
function G.Guild() return (GetGuildInfo("player")) end
-- sending your own fights: nil = not asked yet, true / false = the answer
function G.On() return WhoDidItDB and WhoDidItDB.opts.gfame == true end

local function round1(v) return floor(v * 10 + 0.5) / 10 end
local function split(s, sep)
	local out = {}
	for part in string.gfind((s or "") .. sep, "([^" .. sep .. "]*)" .. sep) do tinsert(out, part) end
	return out
end
local function okName(n)
	return type(n) == "string" and string.len(n) >= 2 and string.len(n) <= 24 and not string.find(n, "[%c%d%p%s]") and true or false
end
-- text inside a card: none of its separators, no colour codes, not too long
local function cleanText(s, n)
	s = string.gsub(s or "", "[#&%^~|%c]", " ")
	if string.len(s) > n then s = string.sub(s, 1, n) end
	return s
end
local function cleanKind(s) return cleanText(string.gsub(s or "Other", "[;,%.:/]", " "), 24) end

------------------------------------------------------------------ storage
-- WhoDidItDB.gfame[guild] = { cards = { [id] = text (the ones that count) },
--   meta = { [id] = "enc;at;dur" (every card held) }, nMeta, have = { [recorder] = n },
--   top = { [recorder] = highest n held }, base = the tally of cards added up and
--   dropped, foldAt = nothing older than this is taken, seen = when last looked at }

local function store(guild)
	if type(WhoDidItDB.gfame) ~= "table" then WhoDidItDB.gfame = {} end
	local all = WhoDidItDB.gfame
	local s = all[guild]
	if not s then
		s = { cards = {}, meta = {}, nMeta = 0, have = {}, top = {} }
		all[guild] = s
		local n, old, oldAt = 0, nil, nil
		for g, v in pairs(all) do
			n = n + 1
			if g ~= guild and (not oldAt or (v.seen or 0) < oldAt) then old, oldAt = g, v.seen or 0 end
		end
		if n > MAX_GUILDS and old then all[old] = nil end
	end
	s.seen = time()
	return s
end
G.Store = store

local function idParts(id)
	local _, _, r, n = string.find(id or "", "^(.+):(%d+)$")
	return r, tonumber(n)
end

------------------------------------------------------------------ cards

-- a saved fight as a card (nil: nothing to share)
function G.Encode(rec, guild)
	if not rec or not rec.players or rec.demo or rec.result == "LIVE" then return nil end
	local at = rec.at or (W.UI and W.UI.FightMinute and W.UI.FightMinute(rec) * 60)
	if not at or at <= 0 then return nil end
	local players, n = {}, 0
	for name, rp in pairs(rec.players) do
		if okName(name) and n < 40 then
			n = n + 1
			tinsert(players, name .. "." .. (CLASS[rp.class or ""] or "Wa") .. "." .. math.min(rp.deaths or 0, 20))
		end
	end
	if n == 0 then return nil end
	local hk, bk = {}, {}
	local function add(t, who, kind, pts)
		t[who] = t[who] or {}
		local k = t[who][kind]
		if not k then k = { 0, 0 }; t[who][kind] = k end
		k[1] = k[1] + 1
		k[2] = round1(k[2] + pts)
	end
	local saves, finds = {}, {}
	for i = 1, getn(rec.findings or {}) do
		local f = rec.findings[i]
		if f.who and rec.players[f.who] and (f.pts or 0) > 0 then
			add(bk, f.who, cleanKind(f.cat), f.pts)
			tinsert(finds, f)
		end
	end
	for i = 1, getn(rec.saves or {}) do
		local sv = rec.saves[i]
		if sv.who and rec.players[sv.who] and (sv.pts or 0) > 0 then
			add(hk, sv.who, cleanKind(W.Career.SaveType(sv.text)), sv.pts)
			tinsert(saves, sv)
		end
	end
	local function kinds(t)
		local out = {}
		for who, ks in pairs(t) do
			local parts = {}
			for kind, k in pairs(ks) do tinsert(parts, kind .. ":" .. k[1] .. ":" .. k[2]) end
			tinsert(out, who .. "." .. table.concat(parts, "/"))
		end
		return table.concat(out, ",")
	end
	local function best(list, blunder)
		table.sort(list, function(a, b) return a.pts > b.pts end)
		local out = {}
		for i = 1, math.min(2, getn(list)) do
			local m = list[i]
			local kind = blunder and (m.cat or "Other") or W.Career.SaveType(m.text)
			tinsert(out, round1(m.pts) .. "^" .. m.who .. "^" .. cleanKind(kind) .. "^" .. cleanText(m.text, 90))
		end
		return table.concat(out, "&")
	end
	local h, b = rec.heroes and rec.heroes[1], rec.blame and rec.blame[1]
	local mvp = (h and (h.pts or 0) >= 2 and rec.players[h.name]) and h.name or ""
	local worst = (b and (b.pts or 0) >= 1 and rec.players[b.name]) and b.name or ""
	return table.concat({
		"1;" .. guild .. ";" .. cleanKind(rec.enc or "?") .. ";" .. ((rec.result == "KILL") and "K" or "W") .. ";" .. floor(at) .. ";" .. floor(rec.dur or 0),
		table.concat(players, ","), kinds(hk), kinds(bk), mvp .. ";" .. worst, best(saves), best(finds, true),
	}, "#")
end

-- a card back into a table, checked (nil: something's wrong with it)
function G.Decode(raw)
	if type(raw) ~= "string" or string.len(raw) > 6000 then return nil end
	local sec = split(raw, "#")
	if getn(sec) ~= 7 then return nil end
	local h = split(sec[1], ";")
	local at, dur = tonumber(h[5]), tonumber(h[6])
	if h[1] ~= "1" or not W.Board or not W.Board.OkGuild(h[2]) or (h[3] or "") == "" or string.len(h[3]) > 24
		or (h[4] ~= "K" and h[4] ~= "W") or not at or not dur or at < 1600000000 or at > time() + 86400 or dur < 0 or dur > 7200 then return nil end
	local c = { guild = h[2], enc = h[3], kill = (h[4] == "K"), at = at, dur = dur, players = {}, hero = {}, blame = {}, mom = {}, blu = {} }
	local n = 0
	for part in string.gfind(sec[2] .. ",", "([^,]*),") do
		local _, _, name, cl, d = string.find(part, "^(.-)%.(%a%a)%.(%d+)$")
		if not name or not okName(name) or not CLASS_OF[cl] or c.players[name] then return nil end
		c.players[name] = { class = CLASS_OF[cl], deaths = math.min(tonumber(d), 20) }
		n = n + 1
	end
	if n == 0 or n > 40 then return nil end
	for si, key in ipairs({ "hero", "blame" }) do
		local txt = sec[2 + si]
		if txt ~= "" then
			for part in string.gfind(txt .. ",", "([^,]*),") do
				local _, _, who, rest = string.find(part, "^(.-)%.(.*)$")
				if not who or not c.players[who] or c[key][who] then return nil end
				local ks = {}
				for kp in string.gfind(rest .. "/", "([^/]*)/") do
					local _, _, kind, kn, pts = string.find(kp, "^(.-):(%d+):([%d%.]+)$")
					kn, pts = tonumber(kn), tonumber(pts)
					if not kind or kind == "" or not kn or not pts or kn > 60 or pts > 300 then return nil end
					ks[kind] = { kn, pts }
				end
				c[key][who] = ks
			end
		end
	end
	local mw = split(sec[5], ";")
	c.mvp = (mw[1] ~= "" and c.players[mw[1]]) and mw[1] or nil
	c.worst = (mw[2] and mw[2] ~= "" and c.players[mw[2]]) and mw[2] or nil
	for si, key in ipairs({ "mom", "blu" }) do
		local txt = sec[5 + si]
		if txt ~= "" then
			for part in string.gfind(txt .. "&", "([^&]*)&") do
				local _, _, pts, who, kind, text = string.find(part, "^([%d%.]+)%^(.-)%^(.-)%^(.*)$")
				pts = tonumber(pts)
				if pts and c.players[who] and pts <= 100 and getn(c[key]) < 2 then
					tinsert(c[key], { pts = pts, who = who, kind = kind, text = text })
				end
			end
		end
	end
	return c
end

------------------------------------------------------------------ the tally

local function newTally() return { fights = 0, players = {}, moments = {}, blunders = {} } end

local function player(v, name, class)
	local p = v.players[name]
	if not p then
		p = { class = class, fights = 0, kills = 0, deaths = 0, hero = 0, saves = 0, mvp = 0,
			blame = 0, mistakes = 0, worst = 0, hk = {}, mk = {}, last = "" }
		v.players[name] = p
	end
	return p
end

local function trim(list)
	table.sort(list, function(a, b) return a.pts > b.pts end)
	while getn(list) > MAX_TOP do tremove(list) end
end

-- add one card to a tally
local function account(v, c)
	v.fights = v.fights + 1
	local when = date("%Y-%m-%d", c.at)
	if not v.since or when < v.since then v.since = when end
	for name, cp in pairs(c.players) do
		local p = player(v, name, cp.class)
		p.fights = p.fights + 1
		if c.kill then p.kills = p.kills + 1 end
		p.deaths = p.deaths + cp.deaths
		if when > p.last then p.last = when end
	end
	for _, side in ipairs({ { c.hero, "hero", "saves", "hk" }, { c.blame, "blame", "mistakes", "mk" } }) do
		for who, ks in pairs(side[1]) do
			local p = v.players[who]
			for kind, k in pairs(ks) do
				p[side[2]] = round1(p[side[2]] + k[2])
				p[side[3]] = p[side[3]] + k[1]
				local t = p[side[4]][kind]
				if not t then t = { 0, 0 }; p[side[4]][kind] = t end
				t[1] = t[1] + k[1]
				t[2] = round1(t[2] + k[2])
			end
		end
	end
	if c.mvp then v.players[c.mvp].mvp = v.players[c.mvp].mvp + 1 end
	if c.worst then v.players[c.worst].worst = v.players[c.worst].worst + 1 end
	for _, side in ipairs({ { c.mom, v.moments }, { c.blu, v.blunders } }) do
		for i = 1, getn(side[1]) do
			local m = side[1][i]
			tinsert(side[2], { pts = m.pts, who = m.who, class = v.players[m.who].class, text = m.text, enc = c.enc, when = when, kind = m.kind })
		end
	end
end

local function copyTally(t)
	local v = newTally()
	if not t then return v end
	v.fights, v.since = t.fights or 0, t.since
	for name, p in pairs(t.players or {}) do
		local q = {}
		for k, x in pairs(p) do q[k] = x end
		q.hk, q.mk = {}, {}
		for k, x in pairs(p.hk or {}) do q.hk[k] = { x[1], x[2] } end
		for k, x in pairs(p.mk or {}) do q.mk[k] = { x[1], x[2] } end
		v.players[name] = q
	end
	for i = 1, getn(t.moments or {}) do tinsert(v.moments, t.moments[i]) end
	for i = 1, getn(t.blunders or {}) do tinsert(v.blunders, t.blunders[i]) end
	return v
end

local cache = {}   -- guild -> the tally, until something changes

-- the guild's tally, shaped like Career's View (the Hall of Fame shows either)
function G:View(guild)
	guild = guild or G.Guild()
	if not guild then return nil end
	local s = store(guild)
	if cache[guild] and not s.dirty then return cache[guild] end
	local v = copyTally(s.base)
	local recorders = {}
	for id, raw in pairs(s.cards) do
		local c = G.Decode(raw)
		if c then
			account(v, c)
			recorders[(idParts(id))] = true
		end
	end
	trim(v.moments)
	trim(v.blunders)
	v.since = v.since or date("%Y-%m-%d")
	v.testFights = 0
	v.guild = guild
	local nr = 0
	for _ in pairs(recorders) do nr = nr + 1 end
	v.recorders = nr
	s.dirty = nil
	cache[guild] = v
	return v
end

------------------------------------------------------------------ taking cards in

local function meta(s, id)
	local m = s.meta[id]
	if not m then return nil end
	local _, _, enc, at, dur = string.find(m, "^(.*);(%d+);(%d+)$")
	return enc, tonumber(at), tonumber(dur)
end

-- the next ones in a row from a recorder: move "have" on
local function advance(s, rec)
	local n = s.have[rec] or 0
	while s.meta[rec .. ":" .. (n + 1)] do n = n + 1 end
	s.have[rec] = n
end

-- too many cards: the oldest are added up into "base" and dropped
local function fold(s)
	local n = 0
	for _ in pairs(s.cards) do n = n + 1 end
	while n > MAX_CARDS do
		local oldest, oldAt
		for id in pairs(s.cards) do
			local _, at = meta(s, id)
			if at and (not oldAt or at < oldAt) then oldest, oldAt = id, at end
		end
		if not oldest then break end
		local c = G.Decode(s.cards[oldest])
		s.base = s.base or newTally()
		if c then account(s.base, c); trim(s.base.moments); trim(s.base.blunders) end
		s.cards[oldest] = nil
		s.foldAt = math.max(s.foldAt or 0, oldAt)
		n = n - 1
	end
	-- and the list of everything held stays bounded too
	while (s.nMeta or 0) > MAX_META do
		local oldest, oldAt
		for id in pairs(s.meta) do
			if not s.cards[id] then
				local _, at = meta(s, id)
				if at and (not oldAt or at < oldAt) then oldest, oldAt = id, at end
			end
		end
		if not oldest then break end
		s.meta[oldest] = nil
		s.nMeta = s.nMeta - 1
		s.foldAt = math.max(s.foldAt or 0, oldAt)
	end
end

-- a card (raw = nil: one that doesn't count) into the guild's store; true if new
function G:Take(guild, id, enc, at, dur, raw)
	local rec, n = idParts(id)
	if not rec or not okName(rec) or not n or n < 1 or n > MAX_ID then return false end
	local s = store(guild)
	if s.meta[id] then return false end
	-- at most 300 recorders per guild (a guild's members with WhoDidIt)
	if not s.top[rec] then
		local nr = 0
		for _ in pairs(s.top) do nr = nr + 1 end
		if nr >= 300 then return false end
	end
	local seq = WhoDidItDB.gfameSeq or 0
	if rec == me() and n > seq and n <= seq + SELF_JUMP then WhoDidItDB.gfameSeq = n end
	if s.foldAt and at <= s.foldAt then
		-- too old to keep: only moves "have" on
		if n == (s.have[rec] or 0) + 1 then s.have[rec] = n; advance(s, rec) end
		return false
	end
	s.meta[id] = enc .. ";" .. at .. ";" .. dur
	s.nMeta = (s.nMeta or 0) + 1
	if n > (s.top[rec] or 0) then s.top[rec] = n end
	if raw then
		-- the same fight from another recorder: the smallest id counts, on every PC
		local keep = true
		for oid in pairs(s.cards) do
			local e, a, d = meta(s, oid)
			if e == enc and math.abs(a - at) <= TWIN_AT and math.abs(d - dur) <= TWIN_DUR then
				if oid < id then keep = false else s.cards[oid] = nil end
			end
		end
		if keep then s.cards[id] = raw end
	end
	advance(s, rec)
	fold(s)
	s.dirty = true
	return true
end

------------------------------------------------------------------ sending

local outq = {}
local lastSend = 0
local heard = {}      -- id -> GetTime() someone sent it (others skip it)
local function queue(msg)
	if getn(outq) < 400 then tinsert(outq, msg) end
end

local function sendCard(s, id)
	heard[id] = GetTime()
	local raw = s.cards[id]
	if not raw then
		queue("X~" .. id .. "~" .. s.meta[id])
		return
	end
	local parts = math.ceil(string.len(raw) / CHUNK)
	for i = 1, parts do
		queue("C~" .. id .. "~" .. i .. "~" .. parts .. "~" .. string.sub(raw, (i - 1) * CHUNK + 1, i * CHUNK))
	end
end

-- what I have, per recorder (in as many messages as it takes)
local lastV = -1000
function G:SendHave(force)
	local guild = G.Guild()
	if not guild or not WhoDidItDB then return false end
	if not force and GetTime() - lastV < 90 then return false end
	if GetTime() - lastV < 20 then return false end
	lastV = GetTime()
	local s = store(guild)
	local parts, line = {}, ""
	for rec, n in pairs(s.have) do
		local e = rec .. "=" .. n
		if string.len(line) + string.len(e) > 220 then tinsert(parts, line); line = "" end
		line = (line == "") and e or (line .. "," .. e)
	end
	tinsert(parts, line)
	for i = 1, getn(parts) do queue("V~" .. parts[i]) end
	return true
end

-- a fight you just recorded: into the guild's tally, and out to whoever's online
function G:OnFight(rec)
	local guild = G.Guild()
	if not guild or not rec or rec.demo or rec.gcard or rec.guild ~= guild then return end
	if WhoDidItDB.opts.gfame == nil then G:Ask() end
	if not G.On() then return end
	local raw = G.Encode(rec, guild)
	if not raw then return end
	local seq = (WhoDidItDB.gfameSeq or 0) + 1
	if seq > MAX_ID then return end
	WhoDidItDB.gfameSeq = seq
	local id = me() .. ":" .. seq
	local c = G.Decode(raw)
	if not c then return end
	rec.gcard = id
	G:Take(guild, id, c.enc, c.at, c.dur, raw)
	sendCard(store(guild), id)
	G.Changed()
end

-- your saved fights from before (the last 25) go in once, if they were your guild's
local function guildShare(rec, guild)
	if rec.guild then return rec.guild == guild end
	-- older fights don't say: at least half of them in your guild's roster
	local roster = {}
	for i = 1, GetNumGuildMembers() do
		local n = GetGuildRosterInfo(i)
		if n then roster[n] = true end
	end
	local n, mine = 0, 0
	for name in pairs(rec.players or {}) do
		n = n + 1
		if roster[name] then mine = mine + 1 end
	end
	return n > 0 and mine * 2 >= n
end
function G:Backfill()
	local guild = G.Guild()
	if not guild or not G.On() then return end
	local fights = WhoDidItDB.fights or {}
	for i = getn(fights), 1, -1 do
		local rec = fights[i]
		if not rec.gcard and not rec.demo and rec.result ~= "LIVE" and guildShare(rec, guild) then
			rec.guild = guild
			G:OnFight(rec)
		end
	end
end

------------------------------------------------------------------ the question

StaticPopupDialogs["WHODIDIT_GFAME"] = {
	text = "%s",
	button1 = "Yes, share", button2 = "No",
	OnAccept = function()
		WhoDidItDB.opts.gfame = true
		W.Print("Hall of Fame: your fights now add to your guild's, and you see the whole guild's. Nothing shows in chat.")
		G.backfilled = nil
		G:Backfill()
		G:SendHave(true)
		G.Changed()
	end,
	OnCancel = function()
		WhoDidItDB.opts.gfame = false
		W.Print("Hall of Fame: your fights stay on your PC. You still see the guild's. Share with guild (Hall of Fame) asks again.")
		G.Changed()
	end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}
function G:Ask()
	local guild = G.Guild()
	if not guild then return end
	StaticPopup_Show("WHODIDIT_GFAME", "Share your Hall of Fame with |cff33ff33" .. guild .. "|r?\n\n"
		.. "Every fight you record then adds to your guild's Hall of Fame (who was there, their hero and blame points, "
		.. "the best plays and blunders), and you see the whole guild's - also raids you weren't in.\n\n"
		.. "|cff888888It goes to guild members with WhoDidIt on a hidden addon channel; nothing shows in chat.|r")
end

-- the button: ask once, then send what's new and ask the others for theirs
function G:Share()
	local guild = G.Guild()
	if not guild then W.Print("Hall of Fame: you're not in a guild.") return end
	if not G.On() then G:Ask() return end
	G:Backfill()
	if G:SendHave(true) then
		W.Print("Hall of Fame: comparing with the guild members online - their fights arrive in the next minute or two.")
	else
		W.Print("Hall of Fame: just compared - give it a minute.")
	end
end

------------------------------------------------------------------ receiving

local parts, nParts = {}, 0   -- id -> { n, got, p = {}, at } cards coming in (at most 100)
local answered = {}     -- sender -> GetTime() I last answered them
local pending = {}      -- { at, ids } answers waiting (others may answer first)

local function answer(sender, list)
	local guild = G.Guild()
	if not guild or not G.On() then return end   -- (said no: this PC sends nothing)
	local now = GetTime()
	if answered[sender] and now - answered[sender] < 120 then return end
	answered[sender] = now
	local s = store(guild)
	local theirs = {}
	for e in string.gfind(list .. ",", "([^,]*),") do
		local _, _, rec, n = string.find(e, "^(.-)=(%d+)$")
		if rec and okName(rec) then theirs[rec] = tonumber(n) end
	end
	local behind = false
	-- what they're missing, from the ids held here (never a loop over a range of numbers
	-- someone sent: one card with a made-up number would freeze this PC)
	local miss = {}
	for id in pairs(s.meta) do
		local rec, n = idParts(id)
		if rec and n and n > (theirs[rec] or 0) then
			if not miss[rec] then miss[rec] = {} end
			tinsert(miss[rec], n)
		end
	end
	local ids, mineFirst = {}, {}
	for rec, list in pairs(miss) do
		if getn(ids) < PER_ANSWER then
			table.sort(list)
			-- the first ones aren't kept here any more: tell them to skip those
			if list[1] > (theirs[rec] or 0) + 1 then queue("F~" .. rec .. "~" .. list[1]) end
			for i = 1, getn(list) do
				if getn(ids) >= PER_ANSWER then break end
				local id = rec .. ":" .. list[i]
				tinsert(ids, id)
				if rec == me() then mineFirst[id] = true end
			end
		end
	end
	for rec, n in pairs(theirs) do
		if n > (s.have[rec] or 0) then behind = true end
	end
	if getn(ids) > 0 then
		local mine, other = {}, {}
		for i = 1, getn(ids) do
			if mineFirst[ids[i]] then tinsert(mine, ids[i]) else tinsert(other, ids[i]) end
		end
		-- your own fights at once; anyone else's after a while, unless someone sent them
		if getn(mine) > 0 then tinsert(pending, { at = now + 1 + math.random(2), made = now, ids = mine }) end
		if getn(other) > 0 then tinsert(pending, { at = now + 6 + math.random(14), made = now, ids = other }) end
	end
	if behind then G:SendHave(false) end
	-- (answered[] is cleared every minute)
end

local function onCard(sender, id, raw)
	local guild = G.Guild()
	local c = G.Decode(raw)
	if not guild or not c or c.guild ~= guild then return end
	if G:Take(guild, id, c.enc, c.at, c.dur, raw) then G.Changed() end
end

W:On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
	if prefix ~= PREFIX or channel ~= "GUILD" or not msg or not sender or not WhoDidItDB then return end
	if sender == me() or not G.Guild() then return end
	local _, _, kind, rest = string.find(msg, "^(%a)~(.*)$")
	if kind == "V" then
		answer(sender, rest)
	elseif kind == "C" then
		local _, _, id, i, n, text = string.find(rest, "^(.-)~(%d+)~(%d+)~(.*)$")
		i, n = tonumber(i), tonumber(n)
		if not id or not i or not n or n > 30 or i < 1 or i > n then return end
		heard[id] = GetTime()
		local s = store(G.Guild())
		if s.meta[id] then return end
		local p = parts[id]
		if not p then
			if nParts >= 100 then return end   -- (cleared every minute)
			nParts = nParts + 1
			p = { n = n, got = 0, p = {}, at = GetTime() }
			parts[id] = p
		end
		if p.n ~= n or p.p[i] then return end
		p.p[i] = text
		p.got = p.got + 1
		if p.got == n then
			parts[id] = nil
			nParts = nParts - 1
			onCard(sender, id, table.concat(p.p))
		end
	elseif kind == "X" then
		local _, _, id, enc, at, dur = string.find(rest, "^(.-)~(.-);(%d+);(%d+)$")
		at, dur = tonumber(at), tonumber(dur)
		if not id or not at or not dur or string.len(enc) > 24 or at > time() + 86400 then return end
		heard[id] = GetTime()
		if G:Take(G.Guild(), id, enc, at, dur, nil) then G.Changed() end
	elseif kind == "F" then
		local _, _, rec, n = string.find(rest, "^(.-)~(%d+)$")
		n = tonumber(n)
		if not rec or not okName(rec) or not n or n > MAX_ID then return end
		local s = store(G.Guild())
		if (s.have[rec] or 0) < n - 1 then
			s.have[rec] = n - 1
			advance(s, rec)
		end
	end
end)

------------------------------------------------------------------ timers

-- refresh an open Hall of Fame at most every 2 seconds
local changed
function G.Changed()
	changed = true
	local guild = G.Guild()
	if guild then cache[guild] = nil end
end

W:Every(SEND_GAP, function()
	if not WhoDidItDB then return end
	local now = GetTime()
	if getn(outq) > 0 and now - lastSend >= SEND_GAP and IsInGuild() then
		lastSend = now
		SendAddonMessage(PREFIX, tremove(outq, 1), "GUILD")
	end
	for i = getn(pending), 1, -1 do
		local a = pending[i]
		if now >= a.at then
			tremove(pending, i)
			local guild = G.Guild()
			if guild then
				local s = store(guild)
				for j = 1, getn(a.ids) do
					local id = a.ids[j]
					-- (skipped if someone sent it since this was asked for)
					if s.meta[id] and not (heard[id] and heard[id] >= a.made) then sendCard(s, id) end
				end
			end
		end
	end
end)

local loginAt
W:Every(2, function()
	if not WhoDidItDB then return end
	if changed and W.UI and W.UI.mode == "fame" then
		changed = nil
		W.UI:Refresh()
	end
	local now = GetTime()
	-- a little after login: your old fights (once), then compare with the guild
	if loginAt and now >= loginAt and G.Guild() then
		loginAt = nil
		if G.On() and not G.backfilled then G.backfilled = true; G:Backfill() end
		G:SendHave(true)
	end
end)

W:Every(60, function()
	local now = GetTime()
	local nh = 0
	for id, t in pairs(heard) do
		if now - t > 120 then heard[id] = nil else nh = nh + 1 end
	end
	if nh > 2000 then heard = {} end
	for id, p in pairs(parts) do if now - p.at > 90 then parts[id] = nil; nParts = nParts - 1 end end
	for n, t in pairs(answered) do if now - t > 120 then answered[n] = nil end end
end)

-- numbers a made-up card id could have saved before 1.24.2 (it froze every PC that
-- answered): drop such ids, and put each recorder's highest number back to what's held
local function heal()
	if not WhoDidItDB or type(WhoDidItDB.gfame) ~= "table" then return end
	local mine = 0
	for _, s in pairs(WhoDidItDB.gfame) do
		if type(s) == "table" and type(s.meta) == "table" and type(s.top) == "table" and type(s.have) == "table" then
			local high = {}
			for id in pairs(s.meta) do
				local rec, n = idParts(id)
				if not rec or not n or n < 1 or n > MAX_ID then
					s.meta[id] = nil
					if s.cards then s.cards[id] = nil end
					s.nMeta = math.max((s.nMeta or 1) - 1, 0)
					s.dirty = true
				elseif n > (high[rec] or 0) then
					high[rec] = n
				end
			end
			for rec, n in pairs(s.top) do
				if n > (high[rec] or 0) then s.top[rec] = high[rec] end
			end
			for rec, n in pairs(s.have) do
				if n > MAX_ID then s.have[rec] = 0; advance(s, rec) end
			end
			if (high[me()] or 0) > mine then mine = high[me()] end
		end
	end
	if (WhoDidItDB.gfameSeq or 0) > MAX_ID then WhoDidItDB.gfameSeq = mine end
end

W:On("PLAYER_ENTERING_WORLD", function()
	if not loginAt and not G.loggedIn then
		G.loggedIn = true
		heal()
		loginAt = GetTime() + 20 + math.random(20)
		if IsInGuild() and GuildRoster then GuildRoster() end
	end
end)
