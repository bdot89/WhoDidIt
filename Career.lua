--[[--------------------------------------------------------------------
	WhoDidIt - Hall of Fame (all-time tally)

	Every fight that's saved adds to a running tally per player: hero
	points and game-saving plays, blame points and mistakes, how often they
	were the fight's top hero (MVP) or most to blame, and the biggest single
	plays and blunders. Kept in WhoDidItDB.career, so it lasts after the
	fights themselves are pruned (only the last 25 are kept). Demo fights
	go into a separate test tally (WhoDidItDB.careerTest): shown marked
	"(test)" and cleared with Clear test data. Each fight counts once.
----------------------------------------------------------------------]]

local W = WhoDidIt
local C = {}
W.Career = C

local getn, tinsert, tremove = table.getn, table.insert, table.remove
local floor = math.floor
local MAX_TOP = 40   -- biggest plays / blunders kept

-- the real tally, or (test = true) the one demo fights go into
local function db(test)
	local key = test and "careerTest" or "career"
	local d = WhoDidItDB[key]
	if not d then
		d = { since = date("%Y-%m-%d"), fights = 0, counted = {}, players = {}, moments = {}, blunders = {}, isTest = test and true or nil }
		WhoDidItDB[key] = d
	end
	return d
end
C.DB = db

local function hasTest() return WhoDidItDB.careerTest ~= nil and WhoDidItDB.careerTest.fights > 0 end
C.HasTest = hasTest

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
			blame = 0, mistakes = 0, worst = 0, hk = {}, mk = {}, last = "", test = d.isTest, roles = {} }
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
	if not rec or rec.result == "LIVE" or not rec.players then return end
	local d = db(rec.demo)
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
		if rp.role then
			p.roles = p.roles or {}
			p.roles[rp.role] = (p.roles[rp.role] or 0) + 1
		end
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
			keepTop(d.blunders, { pts = round1(f.pts), who = f.who, class = rp.class, text = f.text, enc = rec.enc, when = when, kind = f.cat, test = d.isTest })
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
			-- (a damage award isn't a play: the best plays stay the clutch ones)
			if kind ~= "Damage" then
				keepTop(d.moments, { pts = round1(s.pts), who = s.who, class = rp.class, text = s.text, enc = rec.enc, when = when, kind = kind, test = d.isTest })
			end
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

-- remove everything the demo fights added
function C:ClearTest()
	WhoDidItDB.careerTest = nil
	W.Print("Hall of Fame test data (from demo fights) cleared.")
end

-- the real tally and the test one together, for showing and posting:
-- { since, fights, testFights, players, moments, blunders }
function C.View()
	-- the guild's Hall of Fame (GuildFame.lua), when that's what's shown
	if C.scope == "guild" and W.GuildFame and W.GuildFame.Guild() then return W.GuildFame:View() end
	local real, test = db(), WhoDidItDB.careerTest
	local v = { since = real.since, fights = real.fights, testFights = test and test.fights or 0, players = {}, moments = {}, blunders = {} }
	for n, p in pairs(real.players) do v.players[n] = p end
	for _, key in ipairs({ "moments", "blunders" }) do
		for i = 1, getn(real[key]) do tinsert(v[key], real[key][i]) end
		if test then for i = 1, getn(test[key]) do tinsert(v[key], test[key][i]) end end
		table.sort(v[key], function(a, b) return a.pts > b.pts end)
	end
	if test then
		for n, p in pairs(test.players) do if not v.players[n] then v.players[n] = p end end
	end
	return v
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
-- the role a player plays most ("tank", "heal", "dps"); nil if not known yet
function C.MainRole(p)
	local best, bn
	for r, n in pairs(p.roles or {}) do
		if not bn or n > bn then best, bn = r, n end
	end
	return best
end
C.ROLE_LABEL = { tank = "tanks", heal = "healers", dps = "DPS" }

-- role (optional): only players who mostly play it
function C:Board(kind, perFight, minFights, role)
	local d = C.View()
	local out = {}
	for name, p in pairs(d.players) do
		local pts = (kind == "hero") and p.hero or p.blame
		if pts > 0 and (not perFight or p.fights >= (minFights or 3)) and (not role or C.MainRole(p) == role) then
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
	for name, p in pairs(C.View().players) do m[name] = p.class end
	return m
end
C.Classes = classes

function C:BoardLines(kind, perFight, n, role)
	local d = C.View()
	local list = C:Board(kind, perFight, nil, role)
	local title = ((kind == "hero") and "HALL OF FAME HEROES" or "HALL OF SHAME") .. (role and (" - " .. string.upper(C.ROLE_LABEL[role] or role)) or "")
		.. (d.guild and (" of " .. d.guild) or "")
	local out = { "[WhoDidIt] " .. title .. ": since " .. d.since .. ", " .. d.fights .. " fights" .. ((d.testFights > 0) and (" + " .. d.testFights .. " test") or "")
		.. (perFight and " (points per fight, 3+ fights)" or "") }
	if getn(list) == 0 then
		tinsert(out, "Nobody yet - fights are counted as they're saved.")
		return out
	end
	for i = 1, math.min(n or 5, getn(list)) do
		local it = list[i]
		local p = it.p
		local top = C.TopKind(kind == "hero" and p.hk or p.mk)
		local nm = it.name .. (p.test and " (test)" or "")
		if kind == "hero" then
			tinsert(out, i .. ". " .. nm .. " " .. it.v .. " pts" .. (perFight and " a fight" or "") .. " - " .. p.saves .. " saves in "
				.. p.fights .. " fights" .. (top and (", mostly " .. top) or "") .. ((p.mvp > 0) and (", MVP " .. p.mvp .. "x") or ""))
		else
			tinsert(out, i .. ". " .. nm .. " " .. it.v .. " pts" .. (perFight and " a fight" or "") .. " - " .. p.mistakes .. " mistakes in "
				.. p.fights .. " fights" .. (top and (", mostly " .. top) or "") .. ((p.worst > 0) and (", most to blame " .. p.worst .. "x") or ""))
		end
	end
	return out
end

function C:PlayerLines(name)
	local p = C.View().players[name]
	if not p then return { "[WhoDidIt] " .. name .. " has no all-time record yet." } end
	local hk, mk = C.TopKind(p.hk), C.TopKind(p.mk)
	local out = { "[WhoDidIt] HALL OF FAME: " .. name .. (p.test and " (test)" or "") .. " - " .. p.fights .. " fights, " .. p.kills .. " kills, " .. p.deaths .. " deaths" }
	tinsert(out, "Hero: " .. p.hero .. " pts from " .. p.saves .. " saves" .. (hk and (", mostly " .. hk) or "") .. ((p.mvp > 0) and (", MVP " .. p.mvp .. "x") or ""))
	tinsert(out, "Shame: " .. p.blame .. " pts from " .. p.mistakes .. " mistakes" .. (mk and (", mostly " .. mk) or "") .. ((p.worst > 0) and (", most to blame " .. p.worst .. "x") or ""))
	return out
end

function C:MomentLine(m, rank, blunder)
	return "[WhoDidIt] " .. (blunder and "WORST BLUNDER" or "BEST PLAY") .. (rank and (" #" .. rank) or "") .. ": "
		.. (m.text or "?") .. " (" .. (blunder and "-" or "+") .. m.pts .. " pts, " .. (m.enc or "?") .. ", " .. (m.when or "?") .. (m.test and ", test" or "") .. ")"
end

function C:MomentLines(blunder, n)
	local d = C.View()
	local list = blunder and d.blunders or d.moments
	local out = { "[WhoDidIt] " .. (blunder and "HALL OF SHAME WORST BLUNDERS" or "HALL OF FAME BEST PLAYS") .. ": since " .. d.since }
	for i = 1, math.min(n or 3, getn(list)) do
		local m = list[i]
		tinsert(out, i .. ". " .. (m.text or "?") .. " (" .. m.pts .. " pts, " .. (m.enc or "?") .. ", " .. (m.when or "?") .. (m.test and ", test" or "") .. ")")
	end
	if getn(list) == 0 then tinsert(out, "Nothing yet.") end
	return out
end

-- channel nil = the shout channel, "SELF" = only you
function C:Post(lines, channel)
	W:Send(lines, channel, classes())
end

-- saved fights from before this existed count too
-- once (1.25.0): hero points recorded with the old weights (taunts 3, saving heals 2...)
-- are scaled to the new ones, so the board is fair straight away, not only from now on
local function rescale()
	if WhoDidItDB.heroWeights == 2 then return end
	WhoDidItDB.heroWeights = 2
	local f = W.Data.heroRescale or {}
	local changed = false
	for _, key in ipairs({ "career", "careerTest" }) do
		local d = WhoDidItDB[key]
		if d then
			for _, p in pairs(d.players or {}) do
				local total = 0
				for kind, k in pairs(p.hk or {}) do
					k[2] = round1(k[2] * (f[kind] or 1))
					total = total + k[2]
				end
				if p.hero ~= round1(total) then changed = true end
				p.hero = round1(total)
			end
			for _, m in ipairs(d.moments or {}) do m.pts = round1(m.pts * (f[m.kind] or 1)) end
			table.sort(d.moments or {}, function(a, b) return a.pts > b.pts end)
		end
	end
	if changed then
		W.Print("Hall of Fame: hero points now count routine taunts and heals for less, and the top damage dealers in each fight earn points too. Your totals were rescaled to match.")
	end
end

W:On("PLAYER_ENTERING_WORLD", function()
	if WhoDidItDB and not C.filled then
		C.filled = true
		rescale()
		C:Backfill()
	end
end)
