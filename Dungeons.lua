--[[--------------------------------------------------------------------
	WhoDidIt - 5-man dungeon runs: timing, group names, the 5-man boards

	A run is timed from the group's first combat inside the dungeon to the
	death of its final boss (Data.lua D.DUNGEONS). Every boss on the way is a
	split; deaths are counted. When the final boss dies, every WhoDidIt user
	in the group says so on a hidden addon channel (WDI5, party / raid only):
	  C~key~optout~secs~leader~group name
	Six seconds later each of them works out the same answer:
	  - anyone opted out (/wdi 5man off): the run stays on their own PCs only
	  - the time is the longest anyone timed (the earliest first pull)
	  - the sharer is the group leader if they have WhoDidIt, else the first
	    name alphabetically. The sharer names the group (once; the name is
	    remembered for the same five players) and tells the group:
	  N~key~secs~group name
	The sharer then puts the run on the realm's hidden WhoDidIt channel
	(Board.lua's sender), so does every other member with sharing on once the
	sharer has named it, and members share their group's bests again when
	someone asks (Q), so the boards fill up across the realm:
	  WDIB1~D~key~group name~secs~date~deaths~faction~Name:Cl,...~i=secs;...~named
	A run is only taken from someone who was in it, and is sanity-checked.
	A member can withdraw a run the timer got wrong (withdrawing a run, below):
	  WDIB1~W~key~secs~Name,Name,...
	Group names and player names come from other players: they're checked and
	only ever shown in your own window, never posted to chat automatically.
----------------------------------------------------------------------]]

local W = WhoDidIt
local R = {}
W.Runs = R

local getn = table.getn
local floor = math.floor

local ADDON = "WDI5"
local VOTE_WAIT = 6       -- seconds to hear from the rest of the group
local NAME_WAIT = 90      -- seconds the sharer has to name the group
local FINAL_WAIT = 120    -- others: seconds to wait for the sharer's name
local MAX_GROUPS = 60     -- groups kept per dungeon per realm (yours always stay)
local MAX_MINE = 40       -- your own run history
local MAX_NAMES = 100     -- remembered group names
local MAX_FROM = 40       -- runs taken from one sender per session

-- class tokens in two letters (a run message has to fit in one chat line)
local CLASS = { WARRIOR = "Wa", PALADIN = "Pa", HUNTER = "Hu", ROGUE = "Ro", PRIEST = "Pr",
	SHAMAN = "Sh", MAGE = "Ma", WARLOCK = "Wl", DRUID = "Dr" }
local CLASS_OF = {}
for k, v in pairs(CLASS) do CLASS_OF[v] = k end
R.CLASS_OF = CLASS_OF

local function D() return W.Data end
local function me() return UnitName("player") or "?" end
local function realm() return W.Board and W.Board.Realm() or (GetRealmName() or "Unknown") end
local function faction() return UnitFactionGroup("player") or "Neutral" end

-- sharing 5-man runs (the default; /wdi 5man off)
function R.On() return WhoDidItDB and WhoDidItDB.opts and not WhoDidItDB.opts.no5man and true or false end

------------------------------------------------------------------ formatting / checks

-- 12:34 or 1:02:03
function R.Fmt(secs)
	if not secs then return "-" end
	secs = floor(secs + 0.5)
	if secs >= 3600 then
		return string.format("%d:%02d:%02d", floor(secs / 3600), floor(math.mod(secs, 3600) / 60), math.mod(secs, 60))
	end
	return string.format("%d:%02d", floor(secs / 60), math.mod(secs, 60))
end

local function trim(s)
	local _, _, v = string.find(s or "", "^%s*(.-)%s*$")
	return v or ""
end

-- a group name: 2-24 characters, no colour codes / links and none of the
-- characters the messages use as separators
function R.OkName(s)
	return type(s) == "string" and string.len(s) >= 2 and string.len(s) <= 24
		and not string.find(s, "[%c|~;,=:]") and string.find(s, "[^%s]") and true or false
end
function R.CleanName(s)
	s = trim(string.gsub(s or "", "[%c|~;,=:]", ""))
	s = string.gsub(s, "%s+", " ")
	if string.len(s) > 24 then s = trim(string.sub(s, 1, 24)) end
	return s
end

-- a character name (WoW allows accented letters: those bytes pass)
local function okPlayer(n)
	return type(n) == "string" and string.len(n) >= 2 and string.len(n) <= 24 and not string.find(n, "[%c%d%p%s]") and true or false
end

-- "Name:Wa,Name:Pr" -> { { n = "Name", c = "WARRIOR" }, ... }, the same text sorted,
-- and the group's key (the names sorted). nil if anything is off.
function R.Members(m)
	if type(m) ~= "string" or m == "" or string.len(m) > 200 then return nil end
	local list, seen = {}, {}
	for part in string.gfind(m .. ",", "([^,]*),") do
		local _, _, n, c = string.find(part, "^(.-):(%a%a)$")
		if not n or not okPlayer(n) or not CLASS_OF[c] or seen[n] then return nil end
		seen[n] = true
		tinsert(list, { n = n, c = CLASS_OF[c], code = c })
	end
	if getn(list) == 0 or getn(list) > 10 then return nil end
	table.sort(list, function(a, b) return a.n < b.n end)
	local txt, names = {}, {}
	for i = 1, getn(list) do
		tinsert(txt, list[i].n .. ":" .. list[i].code)
		tinsert(names, list[i].n)
	end
	return list, table.concat(txt, ","), table.concat(names, ",")
end

-- is this character in the run?
function R.HasMember(rec, name)
	return rec and rec.m and string.find("," .. rec.m, "," .. (name or me()) .. ":", 1, true) and true or false
end

-- rec.ok = "Name,Name": the members this PC saw share the group's runs themselves (their
-- own vote, or the run sent by them on the realm channel), so they have WhoDidIt with
-- sharing on. Only their names may go into the published download and the website
-- export. Never taken from what a message claims. true if the name was new.
local function addOk(rec, name)
	if not rec or not name or not R.HasMember(rec, name) then return false end
	if string.find("," .. (rec.ok or "") .. ",", "," .. name .. ",", 1, true) then return false end
	rec.ok = (rec.ok and rec.ok ~= "") and (rec.ok .. "," .. name) or name
	return true
end

-- "3=125;7=610" (boss number = seconds into the run) -> checked text, or ""
local function okSplits(s, dg, t)
	if type(s) ~= "string" or s == "" then return "" end
	local out = {}
	for part in string.gfind(s .. ";", "([^;]*);") do
		local _, _, i, at = string.find(part, "^(%d+)=(%d+)$")
		i, at = tonumber(i), tonumber(at)
		if i and at and dg.bosses[i] and at <= (t or 0) then tinsert(out, i .. "=" .. at) end
	end
	return table.concat(out, ";")
end

-- a run's splits: { { name, at }, ... } in the order they died
function R.Splits(rec, key)
	local dg = D().DUNGEON[key]
	local out = {}
	if not dg or not rec or not rec.s then return out end
	for part in string.gfind(rec.s .. ";", "([^;]*);") do
		local _, _, i, at = string.find(part, "^(%d+)=(%d+)$")
		i, at = tonumber(i), tonumber(at)
		if i and dg.bosses[i] then tinsert(out, { name = dg.bosses[i], at = at }) end
	end
	table.sort(out, function(a, b) return a.at < b.at end)
	return out
end

------------------------------------------------------------------ storage
-- WhoDidItDB.dungeons[realm][key][group key] = { g = group name, t = secs,
--   d = date, x = deaths, f = faction, n = size, m = members, s = splits,
--   nt = when it was named, by = who shared it, net = from the channel,
--   priv = never shared (someone in the group opted out), ok = members seen sharing it }
-- WhoDidItDB.myRuns = your runs, newest first (every one, not only bests; wd = withdrawn)
-- WhoDidItDB.groupNames[group key] = { n = name, at = when }
-- WhoDidItDB.runsWithdrawn[realm]["key~group key~secs"] = withdrawn runs (see withdrawing a run)

function R:DB(rlm)
	if type(WhoDidItDB.dungeons) ~= "table" then WhoDidItDB.dungeons = {} end
	rlm = rlm or realm()
	local r = WhoDidItDB.dungeons[rlm]
	if not r then
		r = {}
		WhoDidItDB.dungeons[rlm] = r
	end
	return r
end

function R:MyRuns()
	if type(WhoDidItDB.myRuns) ~= "table" then WhoDidItDB.myRuns = {} end
	return WhoDidItDB.myRuns
end

function R:GroupName(gk)
	local g = type(WhoDidItDB.groupNames) == "table" and WhoDidItDB.groupNames[gk]
	return g and g.n
end

local function rememberName(gk, name)
	if type(WhoDidItDB.groupNames) ~= "table" then WhoDidItDB.groupNames = {} end
	local t = WhoDidItDB.groupNames
	t[gk] = { n = name, at = time() }
	local n, oldest, oldAt = 0, nil, nil
	for k, v in pairs(t) do
		n = n + 1
		if not oldAt or (v.at or 0) < oldAt then oldest, oldAt = k, v.at or 0 end
	end
	if n > MAX_NAMES and oldest then t[oldest] = nil end
end

-- keep a run if it's that group's best there (or the same time, newly named);
-- true if it changed the board
function R:Merge(rlm, key, gk, rec)
	local r = R:DB(rlm)
	local list = r[key]
	if not list then
		list = {}
		r[key] = list
	end
	-- (a run a member withdrew never comes back: from the channel, the download or your own PC)
	local out = R:Withdrawn(rlm, key, gk, rec.t)
	if out then
		out.hit = true
		return false
	end
	local old = list[gk]
	if old and (rec.t > old.t or (rec.t == old.t and (rec.nt or 0) <= (old.nt or 0))) then return false end
	if old and old.priv and rec.t == old.t then rec.priv = true end
	-- (the same players: who's been seen sharing stays known)
	if old and old.ok then
		for n in string.gfind(old.ok, "[^,]+") do addOk(rec, n) end
	end
	list[gk] = rec
	-- the 60 fastest groups per dungeon; groups you were in always stay
	local n, slowest, slowT = 0, nil, -1
	for k, r2 in pairs(list) do
		n = n + 1
		if r2.t > slowT and not R.HasMember(r2) then slowest, slowT = k, r2.t end
	end
	if n > MAX_GROUPS and slowest then
		list[slowest] = nil
		if slowest == gk then return false end
	end
	return true
end

-- realms with 5-man data (yours first)
function R:Realms()
	local list, have = { realm() }, {}
	have[list[1]] = true
	for rl in pairs(WhoDidItDB.dungeons or {}) do
		if not have[rl] then tinsert(list, rl); have[rl] = true end
	end
	return list
end

-- sorted { gk, rec, realm } for one dungeon. rlm may be W.Board.ALL;
-- fac "All" or a faction
function R:Board(rlm, key, fac)
	local realms = (W.Board and rlm == W.Board.ALL) and R:Realms() or { rlm or realm() }
	local out = {}
	for i = 1, getn(realms) do
		local r = WhoDidItDB.dungeons and WhoDidItDB.dungeons[realms[i]]
		for gk, rec in pairs(r and r[key] or {}) do
			if fac == "All" or not fac or rec.f == fac then tinsert(out, { gk, rec, realms[i] }) end
		end
	end
	table.sort(out, function(a, b) return a[2].t < b[2].t end)
	return out
end

-- your best run in a dungeon (any group you were in), from your history or the board
function R:MyBest(key)
	local best
	local mine = R:MyRuns()
	for i = 1, getn(mine) do
		local e = mine[i]
		if e.k == key and not e.wd and (not best or e.t < best.t) then best = e end
	end
	return best
end

-- where a time ranks on a dungeon's board
function R:Place(rlm, key, secs, fac)
	local list = R:Board(rlm, key, fac or "All")
	local place = 1
	for i = 1, getn(list) do
		if list[i][2].t < secs then place = place + 1 end
	end
	return place, getn(list)
end

-- one chat line: a dungeon's three fastest groups (posted only through W:ConfirmSend)
function R:TopLine(key, rlm, fac)
	local dg = key and D().DUNGEON[key]
	if not dg then return nil end
	local list = R:Board(rlm, key, fac or "All")
	if getn(list) == 0 then return nil end
	local all = W.Board and rlm == W.Board.ALL
	local parts = {}
	for i = 1, math.min(3, getn(list)) do
		tinsert(parts, "#" .. i .. " " .. list[i][2].g .. (all and (" (" .. list[i][3] .. ")") or "") .. " " .. R.Fmt(list[i][2].t))
	end
	local where = all and "every realm" or (W.Board and W.Board.RealmLabel(rlm) or rlm)
	return "[WhoDidIt] fastest " .. dg.title .. " groups on " .. where .. ": " .. table.concat(parts, ", ")
end

------------------------------------------------------------------ the group

local function groupUnits()
	local out = {}
	local nr = GetNumRaidMembers()
	if nr > 0 then
		for i = 1, nr do tinsert(out, "raid" .. i) end
	else
		tinsert(out, "player")
		for i = 1, GetNumPartyMembers() do tinsert(out, "party" .. i) end
	end
	return out
end

-- the group right now: members text ("Name:Cl,..." sorted), group key, size
function R.Group()
	local parts = {}
	local units = groupUnits()
	for i = 1, getn(units) do
		local u = units[i]
		local n = UnitExists(u) and UnitName(u)
		local _, c = UnitClass(u)
		if n and n ~= UNKNOWNOBJECT and CLASS[c or ""] then tinsert(parts, n .. ":" .. CLASS[c]) end
	end
	local list, m, gk = R.Members(table.concat(parts, ","))
	return m, gk, list and getn(list) or 0
end

local function groupChannel()
	if GetNumRaidMembers() > 0 then return "RAID" end
	if GetNumPartyMembers() > 0 then return "PARTY" end
end

local function amLeader()
	if GetNumRaidMembers() > 0 then return IsRaidLeader() and true or false end
	if GetNumPartyMembers() > 0 then return IsPartyLeader() and true or false end
	return true
end

------------------------------------------------------------------ recording

local function charKey() return me() .. "-" .. realm() end

-- the run in progress (saved, so a /reload inside keeps it)
local function cur()
	if type(WhoDidItDB.run5) ~= "table" then WhoDidItDB.run5 = {} end
	local r = WhoDidItDB.run5[charKey()]
	if r and time() - (r.at or 0) > D().RUN_MAX then
		WhoDidItDB.run5[charKey()] = nil
		return nil
	end
	return r
end
local function setCur(r)
	if type(WhoDidItDB.run5) ~= "table" then WhoDidItDB.run5 = {} end
	WhoDidItDB.run5[charKey()] = r
end

-- in a dungeon (any instance that isn't one of the timed raids, Karazhan's towers or
-- a battleground: Spy checks "pvp" the same way on this client)
local function dungeonZone()
	local inInst, typ = IsInInstance()
	if not inInst or typ == "pvp" or typ == "arena" then return nil end
	local zone = GetRealZoneText()
	if not zone or zone == "" or W.Data.clears[zone] or W.Data.sharedZones[zone] then return nil end
	return zone
end

function R:Current()
	if not WhoDidItDB then return nil end
	local r = cur()
	if r and r.at then return r end
end

local function say(text) W.Print("|cff33ccff5-man:|r " .. text) end

-- A loading screen arms a new run: the next pull inside starts it, unless it's
-- the same dungeon as an unfinished run (died and ran back, a /reload). After a
-- final boss, the next zone-in is a new run (Dire Maul's wings, a reset instance).
-- The zone text can lag behind a loading screen (Shemp's LBRS run, 14 Oct 2026:
-- "Blackrock Mountain" for a while after running back in as a ghost), so arming
-- doesn't look at it, it's read again every second, and one reading never throws
-- a run away:
--  - the zone can't change without a loading screen, so once a run is known to be
--    the one we're in (it started here, or its zone showed since the last loading
--    screen), it takes any other name the zone shows
--  - a run started while another hadn't finished keeps that one (prev) until the
--    next loading screen: if the zone turns out to be its zone after all, the old
--    run carries on, with the bosses and deaths since
local armed   -- a loading screen since the last run started
local here    -- the run we're in, known since the last loading screen

local function settle()
	local r = cur()
	local zone = dungeonZone()
	if not r or not zone then return end
	local p = r.prev
	if p and not r.fin and zone == p.zone and zone ~= r.zone then
		for name, at in pairs(r.k) do
			if not p.k[name] then p.k[name] = r.at + at - p.at end
		end
		p.x = (p.x or 0) + (r.x or 0)
		setCur(p)
		armed, here = nil, p
		say("the zone name was lagging behind the loading screen - your " .. zone .. " run carries on ("
			.. R.Fmt(time() - p.at) .. " since its first pull).")
		return
	end
	if r.fin then return end
	if zone == r.zone then
		armed, here = nil, r   -- carrying on: the next pull isn't a new run
	elseif r == here then
		r.zone = zone
	end
end

W:On("PLAYER_ENTERING_WORLD", function()
	if not WhoDidItDB then return end
	local r = cur()
	if r then r.prev = nil end
	armed, here = true, nil
	settle()
end)
W:On("ZONE_CHANGED_NEW_AREA", function() if WhoDidItDB then settle() end end)
W:Every(1, function() if WhoDidItDB then settle() end end)

W:On("PLAYER_REGEN_DISABLED", function()
	if not WhoDidItDB then return end
	settle()
	local zone = dungeonZone()
	local r = cur()
	if not zone or (r and r.zone == zone and not r.fin) or not armed then return end
	armed = nil
	local new = { zone = zone, at = time(), k = {}, x = 0 }
	if r and not r.fin then
		r.prev = nil
		new.prev = r
		say("the run timer started again: a new run in " .. zone .. " (your " .. r.zone .. " run hadn't finished, "
			.. R.Fmt(time() - r.at) .. " in).")
	end
	here = new
	setCur(new)
end)

local complete   -- (below)

local function bossDied(name)
	if not name or not WhoDidItDB or not D().DUNGEON_BOSS[name] then return end
	settle()
	local r = R:Current()
	if not r or r.zone ~= dungeonZone() then return end
	if r.k[name] then
		-- the same boss twice: a new instance. The time starts again at the next zone-in.
		setCur(nil)
		W.Print("|cff33ccff5-man:|r " .. name .. " died twice - a new instance? The run timer starts again when you next zone in.")
		return
	end
	r.k[name] = time() - r.at
	local key = D().DUNGEON_FINAL[name]
	if key and not (r.done and r.done[key]) then
		r.done = r.done or {}
		r.done[key] = true
		r.fin = true
		complete(key, r, name)
	end
end

W:On("CHAT_MSG_COMBAT_HOSTILE_DEATH", function(msg)
	if not msg then return end
	local _, _, name = string.find(msg, "^(.+) dies%.$")
	if not name then _, _, name = string.find(msg, "^You have slain (.+)!$") end
	if not name then _, _, name = string.find(msg, "^(.+) is destroyed%.$") end
	bossDied(name)
end)

W:On("CHAT_MSG_COMBAT_FRIENDLY_DEATH", function(msg)
	if not msg or not WhoDidItDB then return end
	settle()
	local r = R:Current()
	if not r or r.zone ~= dungeonZone() then return end
	local _, _, name = string.find(msg, "^(.+) dies%.$")
	if msg == UNITDIESSELF then name = me() end
	if name and W.roster.byName[name] then r.x = (r.x or 0) + 1 end
end)

------------------------------------------------------------------ finishing a run

local pend           -- the run being agreed on: { key, gk, m, n, s, x, secs, votes, t0, ... }
local early = {}     -- votes heard before our own final-boss message: sender -> { key, ..., at }

complete = function(key, r, boss)
	local dg = D().DUNGEON[key]
	local secs = r.k[boss] or (time() - r.at)
	r.cs, r.key = secs, key   -- (the run timer shows the final time)
	local m, gk, n = R.Group()
	local tail = " |cff888888(" .. boss .. " ended it)|r"
	if not m then return end
	if n > (dg.max or D().GROUP_MAX) then
		say(dg.title .. " done in " .. R.Fmt(secs) .. " - not ranked: a group of " .. n .. tail)
		return
	end
	if secs < D().RUN_MIN then
		say(dg.title .. " done in " .. R.Fmt(secs) .. " - not ranked: the timer started mid-run (it starts at the first pull after zoning in)" .. tail)
		return
	end
	local splits = {}
	for i = 1, getn(dg.bosses) do
		local at = r.k[dg.bosses[i]]
		if at then tinsert(splits, i .. "=" .. at) end
	end
	pend = { key = key, gk = gk, m = m, n = n, s = table.concat(splits, ";"), x = r.x or 0,
		secs = secs, votes = {}, t0 = GetTime(), boss = boss }
	pend.votes[me()] = { opt = not R.On(), secs = secs, lead = amLeader(), name = R:GroupName(gk) }
	local ch = groupChannel()
	if ch then
		for who, v in pairs(early) do
			if v.key == key and GetTime() - v.at < 15 then pend.votes[who] = v end
		end
		early = {}
		SendAddonMessage(ADDON, table.concat({ "C", key, R.On() and "0" or "1", tostring(secs), amLeader() and "1" or "0",
			R:GroupName(gk) or "" }, "~"), ch)
		say(dg.title .. " done in |cffffffff" .. R.Fmt(secs) .. "|r" .. tail .. " - checking with the group...")
	else
		pend.t0 = GetTime() - VOTE_WAIT   -- on your own: nobody to wait for
		say(dg.title .. " done in |cffffffff" .. R.Fmt(secs) .. "|r" .. tail)
	end
end

-- a finished run goes on your boards and history; the sharer also sends it out
local function finish(name, secs, share)
	local p = pend
	pend = nil
	if not p then return end
	local dg = D().DUNGEON[p.key]
	if not R.OkName(name) then name = me() .. "'s group" end
	rememberName(p.gk, name)
	local rec = { g = name, t = secs, d = time(), x = p.x, f = faction(), n = p.n, m = p.m, s = p.s, nt = time(),
		by = me(), priv = p.priv or nil }
	local rl = realm()
	local old = R:Board(rl, p.key, "All")
	local was
	for i = 1, getn(old) do if old[i][1] == p.gk then was = old[i][2].t end end
	local better = R:Merge(rl, p.key, p.gk, rec)
	-- the members who said in their own vote that they share (sharing on)
	local stored = R:DB(rl)[p.key] and R:DB(rl)[p.key][p.gk]
	if stored and not p.priv then
		for who, v in pairs(p.votes or {}) do
			if not v.opt then addOk(stored, who) end
		end
	end
	local mine = R:MyRuns()
	tinsert(mine, 1, { k = p.key, gk = p.gk, realm = rl, g = name, t = secs, d = rec.d, x = rec.x, f = rec.f, n = rec.n, m = rec.m, s = rec.s })
	while getn(mine) > MAX_MINE do tremove(mine) end
	local place, of = R:Place(rl, p.key, secs)
	say("|cffffd100" .. name .. "|r: " .. dg.title .. " in |cffffffff" .. R.Fmt(secs) .. "|r, " .. p.x .. " death" .. (p.x == 1 and "" or "s")
		.. " - #" .. place .. " of " .. of .. " on " .. rl
		.. ((was and better) and (" |cff33ff33(group best, was " .. R.Fmt(was) .. ")|r") or "")
		.. (p.priv and " |cff888888(kept on your PC: someone in the group has 5-man sharing off)|r" or ""))
	if share and better and not p.priv and R.On() then R:Share(p.key, rec) end
	R.dirty = true
	if W.UI and W.UI.mode == "rankings" then W.UI:Refresh() end
end

-- the sharer names the group (once: the name is remembered for these players)
StaticPopupDialogs["WHODIDIT_GROUPNAME"] = {
	text = "%s",
	button1 = ACCEPT, button2 = CANCEL,
	hasEditBox = 1, maxLetters = 24,
	OnShow = function()
		local eb = getglobal(this:GetName() .. "EditBox")
		eb:SetText(R.nameDefault or "")
		eb:HighlightText()
		eb:SetFocus()
		R.namePopup = this
	end,
	OnAccept = function()
		local eb = R.namePopup and getglobal(R.namePopup:GetName() .. "EditBox")
		if eb then R:Named(eb:GetText()) end
	end,
	OnCancel = function() R:Named(nil) end,
	EditBoxOnEnterPressed = function()
		local text = this:GetText()
		this:GetParent():Hide()
		R:Named(text)
	end,
	EditBoxOnEscapePressed = function() this:GetParent():Hide() end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}

-- the sharer's name for the group (nil: the default)
function R:Named(text)
	local p = pend
	if not p or not p.naming then return end
	p.naming = nil
	local name = R.CleanName(text or "")
	if not R.OkName(name) then name = R.nameDefault end
	local ch = groupChannel()
	if ch then SendAddonMessage(ADDON, table.concat({ "N", p.key, tostring(p.final), name }, "~"), ch) end
	finish(name, p.final, true)
end

-- six seconds after the final boss: everyone works out the same answer
local function decide()
	local p = pend
	p.decided = true
	local names, secs, opt, lead = {}, p.secs, false, nil
	for who, v in pairs(p.votes) do
		tinsert(names, who)
		if v.opt then opt = true end
		if v.secs and v.secs > secs and v.secs <= D().RUN_MAX then secs = v.secs end
		if v.lead then lead = who end
	end
	table.sort(names)
	p.final, p.priv = secs, opt or nil
	p.sharer = lead or names[1]
	if p.sharer ~= me() then
		p.waitUntil = GetTime() + FINAL_WAIT
		return
	end
	-- I'm the sharer: a name we already have, or ask
	local name = R:GroupName(p.gk)
	if not name then
		for i = 1, getn(names) do
			local v = p.votes[names[i]]
			if v.name and R.OkName(v.name) then name = v.name break end
		end
	end
	if name then
		p.naming = true
		R:Named(name)
		return
	end
	p.naming = true
	p.nameBy = GetTime() + NAME_WAIT
	R.nameDefault = me() .. "'s group"
	local dg = D().DUNGEON[p.key]
	local list = R.Members(p.m) or {}
	local who = {}
	for i = 1, getn(list) do tinsert(who, W.CName(list[i].n, list[i].c)) end
	StaticPopup_Show("WHODIDIT_GROUPNAME", "|cffffd100" .. dg.title .. "|r in |cffffffff" .. R.Fmt(secs) .. "|r\n" .. table.concat(who, ", ")
		.. "\n\nName your group for the 5-man rankings:\n|cff888888(remembered for these players; rename it any time in Rankings > 5-mans)|r")
end

W:On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
	if prefix ~= ADDON or not msg or not sender or not WhoDidItDB then return end
	if channel ~= "PARTY" and channel ~= "RAID" then return end
	if sender == me() then return end
	if not W.roster.byName[sender] then return end   -- only from someone in the group
	local p = {}
	for part in string.gfind(msg .. "~", "([^~]*)~") do tinsert(p, part) end
	if p[1] == "C" then
		local v = { key = p[2], opt = (p[3] == "1"), secs = tonumber(p[4]), lead = (p[5] == "1"),
			name = R.OkName(p[6]) and p[6] or nil, at = GetTime() }
		if not D().DUNGEON[v.key or ""] then return end
		if pend and pend.key == v.key and not pend.decided then pend.votes[sender] = v
		elseif not pend then early[sender] = v end
	elseif p[1] == "N" and pend and pend.decided and pend.key == p[2] and sender == pend.sharer then
		local secs = tonumber(p[3])
		if not secs or secs < D().RUN_MIN or secs > D().RUN_MAX then secs = pend.final end
		-- every member with sharing on sends it too, so the maintainer's WhoDidIt hears from
		-- each of them (only then can their name go into the published download)
		finish(R.OkName(p[4]) and p[4] or (sender .. "'s group"), secs, true)
	end
end)

W:Every(1, function()
	local p = pend
	if not p then return end
	local now = GetTime()
	if not p.decided then
		if now - p.t0 >= VOTE_WAIT then decide() end
	elseif p.naming and p.nameBy and now > p.nameBy then
		StaticPopup_Hide("WHODIDIT_GROUPNAME")
		if pend == p and p.naming then R:Named(nil) end
	elseif p.waitUntil and now > p.waitUntil then
		-- the sharer never said: keep it here with the name we know
		finish(R:GroupName(p.gk) or (p.sharer .. "'s group"), p.final, false)
	end
end)

------------------------------------------------------------------ renaming

-- rename a group you're in: every board, your history, and shared again
function R:Rename(gk, name)
	name = R.CleanName(name)
	if not R.OkName(name) then
		W.Print("A group name is 2-24 characters, without | ~ ; , = or :")
		return false
	end
	rememberName(gk, name)
	local now = time()
	for rl, r in pairs(WhoDidItDB.dungeons or {}) do
		for key, list in pairs(r) do
			local rec = list[gk]
			if rec and R.HasMember(rec) then
				rec.g, rec.nt = name, now
				if rl == realm() and not rec.priv and R.On() then R:Share(key, rec) end
			end
		end
	end
	local mine = R:MyRuns()
	for i = 1, getn(mine) do
		if mine[i].gk == gk then mine[i].g = name end
	end
	R.dirty = true
	W.Print("Your group is now called |cffffd100" .. name .. "|r.")
	if W.UI then W.UI:Refresh() end
	return true
end

------------------------------------------------------------------ the realm channel

local PROTO, SEP = "WDIB1", "~"
local seen, nSeen = {}, 0   -- "key~gk" -> GetTime() last seen on the channel (forgotten past 2000)
local from, nFrom = {}, 0   -- sender -> runs taken this session (forgotten past 500 senders)
local function saw(id)
	if not seen[id] then
		nSeen = nSeen + 1
		if nSeen > 2000 then seen, nSeen = {}, 1 end
	end
	seen[id] = GetTime()
end

function R.Line(key, rec)
	local parts = { PROTO, "D", key, rec.g, tostring(rec.t), tostring(rec.d), tostring(rec.x or 0), rec.f or "?", rec.m, rec.s or "", tostring(rec.nt or rec.d) }
	local s = table.concat(parts, SEP)
	if string.len(s) > 250 then
		parts[10] = ""   -- too long for one chat line: the splits stay home
		s = table.concat(parts, SEP)
	end
	return s
end

function R:Share(key, rec)
	if not R.On() or not W.Board or not W.Board.QueueOut or rec.priv then return end
	local _, _, gk = R.Members(rec.m)
	if not gk then return end
	W.Board.QueueOut(R.Line(key, rec))
	saw(key .. SEP .. gk)
end

-- someone asked (Q): our groups' withdrawals and bests, unless someone just sent them
function R:Answer()
	if not R.On() then return end
	local r = WhoDidItDB.dungeons and WhoDidItDB.dungeons[realm()]
	local now, sent = GetTime(), R:AnswerOut()
	for key, list in pairs(r or {}) do
		for gk, rec in pairs(list) do
			local id = key .. SEP .. gk
			if sent < 8 and not rec.priv and R.HasMember(rec) and not (seen[id] and now - seen[id] < 300) then
				R:Share(key, rec)
				sent = sent + 1
			end
		end
	end
end

-- a run from the channel (p = the message split on ~)
function R:Receive(p, sender)
	if not sender or not WhoDidItDB then return end
	local key, g, secs, d, x, fac, m, s, nt = p[3], p[4], tonumber(p[5]), tonumber(p[6]), tonumber(p[7]), p[8], p[9], p[10], tonumber(p[11])
	local dg = key and D().DUNGEON[key]
	if not dg or not R.OkName(g) or not secs or not d or not x then return end
	if secs < D().RUN_MIN or secs > D().RUN_MAX or d > time() + 86400 or d < 1700000000 or x < 0 or x > 99 then return end
	if fac ~= "Alliance" and fac ~= "Horde" then return end
	local list, mt, gk = R.Members(m)
	if not list or getn(list) > (dg.max or D().GROUP_MAX) then return end
	-- only someone who was in the group can share its run
	local inIt
	for i = 1, getn(list) do if list[i].n == sender then inIt = true end end
	if not inIt then return end
	-- a withdrawn run (an older WhoDidIt of a member still shares it): not taken
	local out = R:Withdrawn(realm(), key, gk, secs)
	if out then
		out.hit = true
		return
	end
	if not from[sender] then
		nFrom = nFrom + 1
		if nFrom > 500 then from, nFrom = {}, 1 end
	end
	from[sender] = (from[sender] or 0) + 1
	if from[sender] > MAX_FROM then return end
	if not nt or nt > time() + 86400 or nt < d then nt = d end
	saw(key .. SEP .. gk)
	local rec = { g = g, t = secs, d = d, x = x, f = fac, n = getn(list), m = mt, s = okSplits(s, dg, secs), nt = nt, by = sender, net = true }
	if R:Merge(realm(), key, gk, rec) then
		R.dirty = true
		if W.UI and W.UI.mode == "rankings" then W.UI:Refresh() end
	end
	-- the sender shares this group's runs themselves (the server says who sent it)
	local stored = R:DB(realm())[key]
	stored = stored and stored[gk]
	if stored and addOk(stored, sender) then R.dirty = true end
end

------------------------------------------------------------------ withdrawing a run
-- A member of a group can take one of its runs off the boards: a time the timer got
-- wrong (Shemp's LBRS run, 14 Oct 2026: v1.26.0 saved 46:38 of a 1:54:00 run). A run
-- is known by its dungeon, its group and its time to the second. The withdrawal is
-- kept, so the run doesn't come back (R:Merge refuses it) from the group's other PCs,
-- older WhoDidIt versions that still share it, or the download:
--   WhoDidItDB.runsWithdrawn[realm]["key~group key~secs"] = { k = key, gk = group key,
--     t = secs, at = when, by = who withdrew it, ok = members seen sharing it, priv = never shared,
--     hit = it mattered here (see keepOut), sentAt = when this PC last sent it }
-- It goes out on the realm channel (older versions ignore W):
--   WDIB1~W~key~secs~Name,Name,...
-- and is only taken from a member of that group (the server says who sent it), at
-- most OUT_MAX per sender in OUT_WINDOW seconds. Taking one never makes anyone send:
-- the members' WhoDidIts send theirs again when someone asks (Q), with their bests,
-- so PCs that were offline hear it too. Masters write them to WhoDidIt_Runs.txt as
-- W5 lines; the download takes the run off PCs that got it from an earlier download.

local MAX_OUT = 200                  -- withdrawals kept per realm (your groups' always stay)
local OUT_MAX, OUT_WINDOW = 5, 600   -- taken from one sender per 10 minutes
local OUT_RESEND = 3                 -- sent again per answer (Q)
local outFrom, nOutFrom = {}, 0      -- sender -> { since, n } (forgotten past 500 senders)

local function outId(key, gk, secs) return key .. SEP .. gk .. SEP .. secs end
local function inGroup(gk, name) return string.find("," .. gk .. ",", "," .. name .. ",", 1, true) and true or false end

-- "Name,Name" from a message or the download -> this PC's group key (the names sorted,
-- as R.Members sorts them) and how many; nil if anything is off
local function okGroup(s)
	if type(s) ~= "string" or s == "" or string.len(s) > 250 then return nil end
	local list, dup = {}, {}
	for n in string.gfind(s .. ",", "([^,]*),") do
		if not okPlayer(n) or dup[n] then return nil end
		dup[n] = true
		tinsert(list, n)
	end
	if getn(list) > 10 then return nil end
	table.sort(list)
	return table.concat(list, ","), getn(list)
end

function R:OutDB(rlm)
	if type(WhoDidItDB.runsWithdrawn) ~= "table" then WhoDidItDB.runsWithdrawn = {} end
	rlm = rlm or realm()
	local t = WhoDidItDB.runsWithdrawn[rlm]
	if not t then
		t = {}
		WhoDidItDB.runsWithdrawn[rlm] = t
	end
	return t
end

-- the withdrawal of this run, or nil
function R:Withdrawn(rlm, key, gk, secs)
	local all = WhoDidItDB and WhoDidItDB.runsWithdrawn
	local t = type(all) == "table" and all[rlm or realm()]
	if not t or not key or not gk or not secs then return nil end
	return t[outId(key, gk, secs)]
end

-- take a withdrawn run off a realm's board and mark it in your history;
-- returns the board's copy, if it was there
local function takeOff(rlm, key, gk, secs)
	local r = WhoDidItDB.dungeons and WhoDidItDB.dungeons[rlm]
	local list = r and r[key]
	local rec = list and list[gk]
	if rec and rec.t == secs then list[gk] = nil else rec = nil end
	local mine = R:MyRuns()
	for i = 1, getn(mine) do
		local e = mine[i]
		if e.k == key and e.gk == gk and e.t == secs and (e.realm or rlm) == rlm then e.wd = true end
	end
	R.dirty = true
	return rec
end

-- keep a withdrawal (true if it's new). hit: it took a run off this PC (rec, the board's copy),
-- came with the download (sure) or later stopped a run coming back. Past MAX_OUT one goes:
-- never one of your groups', and ones that never hit first (a flood of made-up withdrawals,
-- each from a member of its own made-up group, can't push out the ones that matter), oldest first
local function keepOut(rlm, key, gk, secs, by, rec, sure)
	local t = R:OutDB(rlm)
	local id = outId(key, gk, secs)
	if t[id] then
		if rec and rec.ok and not t[id].ok then t[id].ok = rec.ok end
		if rec or sure then t[id].hit = true end
		return false
	end
	t[id] = { k = key, gk = gk, t = secs, at = time(), by = by, ok = rec and rec.ok, priv = rec and rec.priv, hit = (rec or sure) and true or nil }
	local n, drop, dropHit, dropAt = 0, nil, nil, nil
	for i, w in pairs(t) do
		n = n + 1
		if not inGroup(w.gk or "", me()) then
			local h = w.hit and 1 or 0
			if not drop or h < dropHit or (h == dropHit and (w.at or 0) < dropAt) then drop, dropHit, dropAt = i, h, w.at or 0 end
		end
	end
	if n > MAX_OUT and drop then t[drop] = nil end
	return true
end

-- out on the realm channel (5-man sharing and the channel on); true if it went
local function sendOut(key, gk, secs)
	if not R.On() or not W.Board or not W.Board.QueueOut or not WhoDidItDB.opts.shareBoard then return false end
	W.Board.QueueOut(table.concat({ PROTO, "W", key, tostring(secs), gk }, SEP))
	saw("W" .. SEP .. outId(key, gk, secs))
	return true
end

-- withdraw a run of a group you're in (Rankings > 5-mans, the run's page, after asking):
-- off your boards and best times, and the WhoDidIt users on the realm are told
function R:Withdraw(rlm, key, gk, secs, name)
	rlm = rlm or realm()
	local dg = D().DUNGEON[key or ""]
	if not dg or not gk or not secs or not inGroup(gk, me()) then
		W.Print("Only a member of the group can withdraw its run.")
		return false
	end
	local board = R:DB(rlm)[key]
	name = name or (board and board[gk] and board[gk].g) or R:GroupName(gk) or gk
	local rec = takeOff(rlm, key, gk, secs)
	keepOut(rlm, key, gk, secs, me(), rec)
	local w = R:Withdrawn(rlm, key, gk, secs)
	local told = rlm == realm() and w and not w.priv and sendOut(key, gk, secs)
	if told then w.sentAt = time() end
	say(W.LF(told and "withdrawn: %s, %s in %s. It's off your boards, and the WhoDidIt users on the realm are told to drop it."
		or "withdrawn: %s, %s in %s. It's off your boards only: 5-man sharing or the hidden channel is off, or the run was never shared there.",
		"|cffffd100" .. name .. "|r", dg.title, R.Fmt(secs)))
	if W.UI and W.UI.mode == "rankings" then W.UI:Refresh() end
	return true
end

StaticPopupDialogs["WHODIDIT_WITHDRAW5"] = {
	text = "Withdraw this run from the 5-man boards?\n\n%s\n\nIt goes off your boards and best times, and the WhoDidIt users on your realm are told to drop it. It can't be undone.",
	button1 = YES, button2 = NO,
	OnAccept = function()
		local a = R.asked
		R.asked = nil
		if a then R:Withdraw(a.rlm, a.key, a.gk, a.t, a.g) end
	end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}

-- the run's page: ask before withdrawing it
function R:AskWithdraw(rlm, key, gk, rec)
	local dg = D().DUNGEON[key or ""]
	if not dg or not gk or not rec or not rec.t then return end
	R.asked = { rlm = rlm, key = key, gk = gk, t = rec.t, g = R.OkName(rec.g) and rec.g or nil }
	W.ShowPopup("WHODIDIT_WITHDRAW5", "|cffffd100" .. (rec.g or "?") .. "|r  " .. dg.title .. "  |cffffffff" .. R.Fmt(rec.t) .. "|r  "
		.. W.LDate("%d %b %Y", rec.d or time()))
end

-- a withdrawal from the channel (p = the message split on ~)
function R:ReceiveOut(p, sender)
	if not sender or not WhoDidItDB then return end
	local key, secs = p[3], tonumber(p[4])
	local dg = key and D().DUNGEON[key]
	if not dg or not secs or secs ~= floor(secs) or secs < D().RUN_MIN or secs > D().RUN_MAX then return end
	local gk, n = okGroup(p[5])
	-- only someone who was in the group can withdraw its run
	if not gk or n > (dg.max or D().GROUP_MAX) or not inGroup(gk, sender) then return end
	local rl = realm()
	saw("W" .. SEP .. outId(key, gk, secs))
	if R:Withdrawn(rl, key, gk, secs) then return end
	-- rationed: OUT_MAX per sender every OUT_WINDOW seconds
	local now = GetTime()
	local q = outFrom[sender]
	if not q or now - q.since > OUT_WINDOW then
		if not q then
			nOutFrom = nOutFrom + 1
			if nOutFrom > 500 then outFrom, nOutFrom = {}, 1 end
		end
		q = { since = now, n = 0 }
		outFrom[sender] = q
	end
	if q.n >= OUT_MAX then return end
	q.n = q.n + 1
	keepOut(rl, key, gk, secs, sender, takeOff(rl, key, gk, secs))
	if inGroup(gk, me()) and sender ~= me() then
		say(W.LF("%s withdrew your group's run: %s in %s. It's off your boards.", sender, dg.title, R.Fmt(secs)))
	end
	if W.UI and W.UI.mode == "rankings" then W.UI:Refresh() end
end

-- someone asked (Q): withdrawals of groups you're in go out again (a few, the longest
-- unsent first, unless someone just sent them), so PCs that were offline hear them too
function R:AnswerOut()
	local t = WhoDidItDB.runsWithdrawn and WhoDidItDB.runsWithdrawn[realm()]
	if not t then return 0 end
	local list, now = {}, GetTime()
	for id, w in pairs(t) do
		local s = seen["W" .. SEP .. id]
		if not w.priv and w.k and w.gk and w.t and inGroup(w.gk, me()) and not (s and now - s < 300) then tinsert(list, w) end
	end
	table.sort(list, function(a, b) return (a.sentAt or 0) < (b.sentAt or 0) end)
	local sent = 0
	for i = 1, math.min(getn(list), OUT_RESEND) do
		if sendOut(list[i].k, list[i].gk, list[i].t) then
			list[i].sentAt = time()
			sent = sent + 1
		end
	end
	return sent
end

------------------------------------------------------------------ the download's runs, the master's file
-- RaidTimes.lua (the maintainer's publish) carries the realms' 5-man runs as
--   R5|realm|key|group|secs|date|deaths|faction|members|splits|named
-- and they go on the boards once per publish. The master's WhoDidIt writes its
-- boards to CustomData\WhoDidIt_Runs.txt, the same lines plus |ok (rec.ok: the
-- members it saw share the run themselves). Names are only published for those:
-- tools\Publish-RaidTimes.ps1 takes a run only when every member is in ok, and
-- tools\Website-Export.ps1 shows the others by class only. A withdrawn run isn't
-- written; its withdrawal is, so the download takes it off the PCs that have it:
--   W5|realm|key|secs|Name,Name,...|ok   (published without ok, when every member is in it)

local function splitBar(line)
	local out = {}
	for part in string.gfind(line .. "|", "([^|]*)|") do tinsert(out, part) end
	return out
end

function R:Seed()
	local s = WDI_RAIDTIMES
	if type(s) ~= "table" or type(s.text) ~= "string" or not tonumber(s.synced) then return end
	if (WhoDidItDB.runSeed or 0) >= s.synced then return end
	WhoDidItDB.runSeed = s.synced
	for line in string.gfind(s.text, "[^\r\n]+") do
		if string.sub(line, 1, 3) == "R5|" then
			local p = splitBar(line)
			local dg = D().DUNGEON[p[3] or ""]
			local list, mt, gk = R.Members(p[9])
			local secs, d = tonumber(p[5]), tonumber(p[6])
			if dg and list and getn(list) <= (dg.max or D().GROUP_MAX) and R.OkName(p[4]) and secs and d and p[2] ~= ""
				and secs >= D().RUN_MIN and secs <= D().RUN_MAX and (p[8] == "Alliance" or p[8] == "Horde") then
				R:Merge(p[2], p[3], gk, { g = p[4], t = secs, d = d, x = tonumber(p[7]) or 0, f = p[8], n = getn(list), m = mt,
					s = okSplits(p[10], dg, secs), nt = tonumber(p[11]) or d, net = true, by = "the WhoDidIt download" })
				-- (runs from the download: the maintainer's published boards)
				local stored = R:DB(p[2])[p[3]]
				stored = stored and stored[gk]
				if stored then
					for i = 1, getn(list) do addOk(stored, list[i].n) end
				end
			end
		elseif string.sub(line, 1, 3) == "W5|" then
			local p = splitBar(line)
			local dg = D().DUNGEON[p[3] or ""]
			local gk, n = okGroup(p[5])
			local secs = tonumber(p[4])
			if dg and gk and n <= (dg.max or D().GROUP_MAX) and secs and p[2] ~= "" then
				keepOut(p[2], p[3], gk, secs, "the WhoDidIt download", takeOff(p[2], p[3], gk, secs), true)
			end
		end
	end
end
W:On("PLAYER_ENTERING_WORLD", function() if WhoDidItDB then R:Seed() end end)

-- the master's boards, out to CustomData for the publish and the website export
function R:WriteFile()
	if not WriteCustomFile or not (W.Board and W.Board.CanMaster and W.Board.CanMaster()) then return end
	local out = { "WDIRUNS|1|" .. time() }
	for rl, r in pairs(WhoDidItDB.dungeons or {}) do
		for key, list in pairs(r) do
			for gk, rec in pairs(list) do
				if not rec.priv and R.OkName(rec.g) and D().DUNGEON[key] and not R:Withdrawn(rl, key, gk, rec.t) then
					tinsert(out, table.concat({ "R5", rl, key, rec.g, tostring(rec.t), tostring(rec.d), tostring(rec.x or 0),
						rec.f or "?", rec.m or "", rec.s or "", tostring(rec.nt or rec.d), rec.ok or "" }, "|"))
				end
			end
		end
	end
	for rl, t in pairs(WhoDidItDB.runsWithdrawn or {}) do
		for _, w in pairs(t) do
			if not w.priv and w.gk and w.t and D().DUNGEON[w.k or ""] then
				tinsert(out, table.concat({ "W5", rl, w.k, tostring(w.t), w.gk, w.ok or "" }, "|"))
			end
		end
	end
	pcall(WriteCustomFile, "WhoDidIt_Runs.txt", table.concat(out, "\n") .. "\n", "w")
end
W:Every(300, function()
	if R.dirty and WhoDidItDB and not UnitAffectingCombat("player") then
		R.dirty = nil
		R:WriteFile()
	end
end)

------------------------------------------------------------------ /wdi 5man

function R:Slash(rest)
	local _, _, sub, arg = string.find(rest or "", "^(%S*)%s*(.-)$")
	sub = strlower(sub or "")
	local o = WhoDidItDB.opts
	if sub == "on" or sub == "off" then
		o.no5man = (sub == "off") or nil
		W.Print("Sharing your 5-man runs (group name, members and classes, time, deaths) with WhoDidIt users on the realm: "
			.. (R.On() and "|cff33ff33on|r" or "|cffff9933off|r - and when you're in the group, nobody's WhoDidIt shares that run"))
		if W.UI then W.UI:Refresh() end
	elseif sub == "name" then
		local _, gk, n = R.Group()
		if not gk or n < 2 then W.Print("Be in a group to name it: /wdi 5man name <group name>") return end
		R:Rename(gk, arg)
	else
		local r = R:Current()
		W.Print("5-man runs: sharing " .. (R.On() and "|cff33ff33on|r" or "|cffff9933off|r")
			.. (r and ("   |cff33ccffrun in progress:|r " .. r.zone .. " " .. R.Fmt(time() - r.at)) or ""))
		DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/wdi 5man on|off|r - share your group's runs   |cffffd100/wdi 5man name <name>|r - name your current group")
		if W.UI then W.UI.rk.five = true; W.UI:SetMode("rankings") end
	end
end
