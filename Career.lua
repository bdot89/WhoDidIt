--[[--------------------------------------------------------------------
	WhoDidIt - Hall of Fame (all-time tally)

	Every fight that's saved adds to a running tally per player: hero
	points and game-saving plays, blame points and mistakes, how often they
	were the fight's top hero (MVP) or most to blame, and the biggest single
	plays and blunders. Kept in WhoDidItDB.career, so it lasts after the
	fights themselves are pruned (only the last 25 are kept). Demo fights
	don't count. Each fight is only ever counted once.
----------------------------------------------------------------------]]

local W = WhoDidIt
local C = {}
W.Career = C

local getn, tinsert, tremove = table.getn, table.insert, table.remove
local floor = math.floor
local MAX_TOP = 40   -- biggest plays / blunders kept

local function db()
	local d = WhoDidItDB.career
	if not d then
		d = { since = date("%Y-%m-%d"), fights = 0, counted = {}, players = {}, moments = {}, blunders = {} }
		WhoDidItDB.career = d
	end
	return d
end
C.DB = db

function C.Key(rec)
	return (rec.date or "?") .. "|" .. (rec.enc or "?") .. "|" .. floor(rec.dur or 0)
end

-- the kind of a hero moment, from its text ("absorbed" -> Shield...)
function C.SaveType(text)
	local list = W.Data.saveTypes
	for i = 1, getn(list) do
		if string.find(text or "", list[i][1], 1, true) then return list[i][2] end
	end
	return "Save"
end

local function player(d, name, class)
	local p = d.players[name]
	if not p then
		p = { class = class, fights = 0, kills = 0, deaths = 0, hero = 0, saves = 0, mvp = 0,
			blame = 0, mistakes = 0, worst = 0, hk = {}, mk = {}, last = "" }
		d.players[name] = p
	end
	if class then p.class = class end
	return p
end

local function round1(v) return floor(v * 10 + 0.5) / 10 end

-- add to a "kind" counter: { [kind] = { n, pts } }
local function bump(t, kind, pts)
	local k = t[kind]
	if not k then k = { 0, 0 }; t[kind] = k end
	k[1] = k[1] + 1
	k[2] = round1(k[2] + pts)
end

-- keep the MAX_TOP biggest by points
local function keepTop(list, item)
	tinsert(list, item)
	table.sort(list, function(a, b) return a.pts > b.pts end)
	while getn(list) > MAX_TOP do tremove(list) end
end

-- count a saved fight (once)
function C:Add(rec)
	if not rec or rec.demo or rec.result == "LIVE" or not rec.players then return end
	local d = db()
	local key = C.Key(rec)
	if d.counted[key] then return end
	d.counted[key] = true
	d.fights = d.fights + 1
	local when = rec.date and string.sub(rec.date, 1, 10) or date("%Y-%m-%d")
	for name, rp in pairs(rec.players) do
		local p = player(d, name, rp.class)
		p.fights = p.fights + 1
		if rec.result == "KILL" then p.kills = p.kills + 1 end
		p.deaths = p.deaths + (rp.deaths or 0)
		p.last = when
	end
	-- mistakes (blame points)
	for i = 1, getn(rec.findings or {}) do
		local f = rec.findings[i]
		local rp = f.who and rec.players[f.who]
		if rp and (f.pts or 0) > 0 then
			local p = player(d, f.who, rp.class)
			p.blame = round1(p.blame + f.pts)
			p.mistakes = p.mistakes + 1
			bump(p.mk, f.cat or "Other", f.pts)
			keepTop(d.blunders, { pts = round1(f.pts), who = f.who, class = rp.class, text = f.text, enc = rec.enc, when = when, kind = f.cat })
		end
	end
	-- game-saving plays (hero points)
	for i = 1, getn(rec.saves or {}) do
		local s = rec.saves[i]
		local rp = s.who and rec.players[s.who]
		if rp and (s.pts or 0) > 0 then
			local p = player(d, s.who, rp.class)
			local kind = C.SaveType(s.text)
			p.hero = round1(p.hero + s.pts)
			p.saves = p.saves + 1
			bump(p.hk, kind, s.pts)
			keepTop(d.moments, { pts = round1(s.pts), who = s.who, class = rp.class, text = s.text, enc = rec.enc, when = when, kind = kind })
		end
	end
	-- the fight's top hero and most to blame
	local h, b = rec.heroes and rec.heroes[1], rec.blame and rec.blame[1]
	if h and (h.pts or 0) >= 2 and d.players[h.name] then d.players[h.name].mvp = d.players[h.name].mvp + 1 end
	if b and (b.pts or 0) >= 1 and d.players[b.name] then d.players[b.name].worst = d.players[b.name].worst + 1 end
end

-- count the saved fights that aren't counted yet (oldest first)
function C:Backfill()
	local fights = WhoDidItDB.fights or {}
	for i = getn(fights), 1, -1 do C:Add(fights[i]) end
end

function C:Reset()
	WhoDidItDB.career = nil
	db()
	W.Print("Hall of Fame tally cleared. Fights from now on are counted.")
end

-- a player's biggest kind of play / mistake: "Heal x12"
function C.TopKind(t)
	local bk, bv
	for k, v in pairs(t or {}) do
		if not bv or v[2] > bv[2] then bk, bv = k, v end
	end
	return bk and (bk .. " x" .. bv[1]) or nil, bk
end

-- the board: { { name, p, v }, ... } sorted. kind = "hero" or "blame";
-- perFight = points per fight (players with fewer than minFights left out)
function C:Board(kind, perFight, minFights)
	local d = db()
	local out = {}
	for name, p in pairs(d.players) do
		local pts = (kind == "hero") and p.hero or p.blame
		if pts > 0 and (not perFight or p.fights >= (minFights or 3)) then
			local v = perFight and round1(pts / math.max(1, p.fights)) or pts
			tinsert(out, { name = name, p = p, v = v })
		end
	end
	table.sort(out, function(a, b)
		if a.v ~= b.v then return a.v > b.v end
		return a.name < b.name
	end)
	return out
end

------------------------------------------------------------------ posting

local function classes()
	local m = {}
	for name, p in pairs(db().players) do m[name] = p.class end
	return m
end
C.Classes = classes

function C:BoardLines(kind, perFight, n)
	local d = db()
	local list = C:Board(kind, perFight)
	local title = (kind == "hero") and "ALL TIME HEROES" or "ALL TIME HALL OF SHAME"
	local out = { "[WhoDidIt] " .. title .. ": since " .. d.since .. ", " .. d.fights .. " fights"
		.. (perFight and " (points per fight, 3+ fights)" or "") }
	if getn(list) == 0 then
		tinsert(out, "Nobody yet - fights are counted as they're saved.")
		return out
	end
	for i = 1, math.min(n or 5, getn(list)) do
		local it = list[i]
		local p = it.p
		local top = C.TopKind(kind == "hero" and p.hk or p.mk)
		if kind == "hero" then
			tinsert(out, i .. ". " .. it.name .. " " .. it.v .. " pts" .. (perFight and " a fight" or "") .. " - " .. p.saves .. " saves in "
				.. p.fights .. " fights" .. (top and (", mostly " .. top) or "") .. ((p.mvp > 0) and (", MVP " .. p.mvp .. "x") or ""))
		else
			tinsert(out, i .. ". " .. it.name .. " " .. it.v .. " pts" .. (perFight and " a fight" or "") .. " - " .. p.mistakes .. " mistakes in "
				.. p.fights .. " fights" .. (top and (", mostly " .. top) or "") .. ((p.worst > 0) and (", most to blame " .. p.worst .. "x") or ""))
		end
	end
	return out
end

function C:PlayerLines(name)
	local p = db().players[name]
	if not p then return { "[WhoDidIt] " .. name .. " has no all-time record yet." } end
	local hk, mk = C.TopKind(p.hk), C.TopKind(p.mk)
	local out = { "[WhoDidIt] ALL TIME: " .. name .. " - " .. p.fights .. " fights, " .. p.kills .. " kills, " .. p.deaths .. " deaths" }
	tinsert(out, "Hero: " .. p.hero .. " pts from " .. p.saves .. " saves" .. (hk and (", mostly " .. hk) or "") .. ((p.mvp > 0) and (", MVP " .. p.mvp .. "x") or ""))
	tinsert(out, "Shame: " .. p.blame .. " pts from " .. p.mistakes .. " mistakes" .. (mk and (", mostly " .. mk) or "") .. ((p.worst > 0) and (", most to blame " .. p.worst .. "x") or ""))
	return out
end

function C:MomentLine(m, rank, blunder)
	return "[WhoDidIt] " .. (blunder and "ALL TIME BLUNDER" or "ALL TIME PLAY") .. (rank and (" #" .. rank) or "") .. ": "
		.. (m.text or "?") .. " (" .. (blunder and "-" or "+") .. m.pts .. " pts, " .. (m.enc or "?") .. ", " .. (m.when or "?") .. ")"
end

function C:MomentLines(blunder, n)
	local d = db()
	local list = blunder and d.blunders or d.moments
	local out = { "[WhoDidIt] " .. (blunder and "ALL TIME WORST BLUNDERS" or "ALL TIME BEST PLAYS") .. ": since " .. d.since }
	for i = 1, math.min(n or 3, getn(list)) do
		local m = list[i]
		tinsert(out, i .. ". " .. (m.text or "?") .. " (" .. m.pts .. " pts, " .. (m.enc or "?") .. ", " .. (m.when or "?") .. ")")
	end
	if getn(list) == 0 then tinsert(out, "Nothing yet.") end
	return out
end

-- channel nil = the shout channel, "SELF" = only you
function C:Post(lines, channel)
	W:Send(lines, channel, classes())
end

-- saved fights from before this existed count too
W:On("PLAYER_ENTERING_WORLD", function()
	if WhoDidItDB and not C.filled then
		C.filled = true
		C:Backfill()
	end
end)
