--[[--------------------------------------------------------------------
	WhoDidIt - demo / test mode

	Builds scripted sample fights (a messy wipe and a cleaner kill) with a
	fake 20-player raid, and feeds them through the real Analyzer, UI and
	shout-out code so every feature can be seen without raiding.

	/wdi demo        - add both sample fights instantly
	/wdi demo live   - play the wipe as a live fight (4x speed, ~48s)
	/wdi demo clear  - remove all demo fights

	Demo shout-outs and reports are only ever shown in your own chat.
----------------------------------------------------------------------]]

local W = WhoDidIt
local Demo = {}
W.Demo = Demo

local floor = math.floor
local getn = table.getn
local random = math.random

local BOSS = "Grand Demonstrator"
local BOSS_GUID = "0xF1300000DE40001"
local ADD = "Flamewaker Healer"
local LIVE_SPEED = 4
local TICK = 2

-- name, class, role, damage or healing per second, max health
local ROSTER = {
	{ "Tankenstein", "WARRIOR", "tank", 380, 9200 },
	{ "Bulwarkus",   "WARRIOR", "tank", 330, 8800 },
	{ "Mendalot",    "PRIEST",  "heal", 520, 4100 },
	{ "Leafy",       "DRUID",   "heal", 480, 4300 },
	{ "Holyroller",  "PALADIN", "heal", 560, 4600 },
	{ "Totemtim",    "SHAMAN",  "heal", 500, 4400 },
	{ "Stabbins",    "ROGUE",   "dps",  820, 4200 },
	{ "Backstabz",   "ROGUE",   "dps",  760, 4100 },
	{ "Pewpew",      "HUNTER",  "dps",  700, 4300 },
	{ "Petsmart",    "HUNTER",  "dps",  650, 4250 },
	{ "Frostyboi",   "MAGE",    "dps",  880, 3800 },
	{ "Pyromancy",   "MAGE",    "dps",  840, 3700 },
	{ "Dotsalot",    "WARLOCK", "dps",  800, 4500 },
	{ "Felbert",     "WARLOCK", "dps",  740, 4400 },
	{ "Axeman",      "WARRIOR", "dps",  780, 4900 },
	{ "Moonbeam",    "DRUID",   "dps",  560, 4000 },
	{ "Shockadin",   "PALADIN", "dps",  520, 4700 },
	{ "Afkerson",    "MAGE",    "dps",  140, 3600 },
	{ "Shadowpat",   "PRIEST",  "dps",  600, 3900 },
	{ "Windfury",    "SHAMAN",  "dps",  690, 4500 },
}

local DMG_SPELLS = {
	WARRIOR = { "Melee", "Heroic Strike", "Bloodthirst" },
	ROGUE   = { "Melee", "Sinister Strike", "Eviscerate" },
	HUNTER  = { "Auto Shot", "Aimed Shot", "Multi-Shot" },
	MAGE    = { "Fireball", "Scorch", "Fire Blast" },
	WARLOCK = { "Shadow Bolt", "Corruption", "Curse of Agony" },
	DRUID   = { "Starfire", "Moonfire", "Wrath" },
	PALADIN = { "Melee", "Seal of Command", "Judgement" },
	PRIEST  = { "Mind Blast", "Mind Flay", "Shadow Word: Pain" },
	SHAMAN  = { "Melee", "Stormstrike", "Earth Shock" },
}

local HEAL_SPELLS = {
	PRIEST  = { "Greater Heal", "Renew", "Flash Heal" },
	DRUID   = { "Healing Touch", "Rejuvenation", "Regrowth" },
	PALADIN = { "Holy Light", "Flash of Light", "Holy Light" },
	SHAMAN  = { "Chain Heal", "Healing Wave", "Lesser Healing Wave" },
}

-- consumable buffs each demo player has at the pull (on top of flasks by role)
local DEMO_BUFFS = {
	Tankenstein = { "Greater Armor", "Health II", "Well Fed", "Rumsey Rum Black Label", "Fire Protection" },
	Bulwarkus   = { "Greater Armor", "Well Fed" },
	Mendalot    = { "Mana Regeneration", "Greater Intellect", "Well Fed" },
	Leafy       = { "Well Fed" },
	Holyroller  = { "Mana Regeneration", "Increased Intellect" },
	Stabbins    = { "Elixir of the Mongoose", "Juju Power", "Winterfall Firewater", "Spirit of Zanza", "Well Fed" },
	Backstabz   = { "Elixir of the Mongoose", "Well Fed" },
	Pewpew      = { "Elixir of the Mongoose", "Increased Agility" },
	Petsmart    = { "Elixir of the Mongoose" },
	Frostyboi   = { "Greater Arcane Elixir", "Frost Power", "Well Fed" },
	Pyromancy   = { "Greater Arcane Elixir", "Greater Firepower", "Well Fed" },
	Dotsalot    = { "Greater Arcane Elixir", "Shadow Power", "Spirit of Zanza", "Well Fed" },
	Felbert     = { "Shadow Power" },
	Axeman      = { "Elixir of the Giants", "Juju Power", "Juju Might", "Well Fed" },
	Moonbeam    = { "Greater Arcane Elixir" },
	Shadowpat   = { "Shadow Power", "Well Fed" },
	Windfury    = { "Elixir of the Mongoose", "Juju Might", "Well Fed" },
}

local ACT_RATE ={ tank = 0.97, heal = 0.75, dps = 0.93 }

------------------------------------------------------------------ fight helpers

local F, DUR, ops, opIdx

local function addTo(t, k, v) t[k] = (t[k] or 0) + v end

local function line(s, kind, text, who)
	tinsert(F.timeline, { t = s, k = kind, x = text, w = who })
end

local function P(name) return F.players[name] end

local function op(s, fn) tinsert(ops, { s, fn }) end

local function mark(p, s, s2)
	for i = floor(s), floor(s2) do
		if not p.act[i] then
			p.act[i] = true
			p.nAct = p.nAct + 1
		end
	end
end

local function split(t, spells, amt)
	addTo(t, spells[1], amt * 0.5)
	addTo(t, spells[2], amt * 0.3)
	addTo(t, spells[3], amt * 0.2)
end

local function aggro(s, to, from, perc, how)
	local p = P(to)
	local fp = from and P(from)
	tinsert(F.aggro, {
		t = s, boss = BOSS, to = to, class = p.class, from = from, perc = perc,
		how = how or "target", oldDead = (fp and fp.deadAt) and true or nil,
	})
	if not F.firstHolder then F.firstHolder = to end
	F.demoHolder = to
	line(s, "aggro", BOSS .. " -> " .. to .. (perc and (" (" .. perc .. "% threat)") or ""), to)
end

local function threat(s, name, perc)
	F.threat[name] = { perc = perc, t = F.t0 + s, tank = false }
	local pk = F.threatPeak[name]
	if not pk or perc > pk.perc then F.threatPeak[name] = { perc = perc, t = s, boss = BOSS } end
end

local function avoidHit(s, name, spell, amt)
	local p = P(name)
	p.taken = p.taken + amt
	addTo(p.ts, spell, amt)
	local a = F.avoid[name]
	if not a then a = {}; F.avoid[name] = a end
	local r = a[spell]
	if not r then r = { hits = 0, dmg = 0, inst = 0, last = -999, first = s }; a[spell] = r end
	r.hits = r.hits + 1
	r.dmg = r.dmg + amt
	if s - r.last > 4 then
		r.inst = r.inst + 1
		line(s, "avoid", name .. " hit by " .. spell .. " (" .. W.FmtNum(amt) .. ")", name)
	end
	r.last = s
end

-- lines: { secondsBeforeDeath, kind, source, spell, amount, hpFraction, crit, extra }
local function die(s, name, lines, debuffs, hadAggro)
	local p = P(name)
	p.deadAt = F.t0 + s
	local d = { name = name, class = p.class, t = s, at = F.t0 + s, lines = {}, debuffs = debuffs or {}, cons = p.nCons, hadAggro = hadAggro }
	for i = 1, getn(lines) do
		local l = lines[i]
		tinsert(d.lines, { t = s + l[1], k = l[2], s = l[3], sp = l[4], a = l[5], hp = floor(l[6] * p.maxhp), hm = p.maxhp, c = l[7], x = l[8] })
	end
	tinsert(F.deaths, d)
	line(s, "death", name .. " died", name)
end

local function generic(s, name)
	die(s, name, {
		{ -3.2, "dmg", BOSS, "Flame Wave", 1300, 0.55 },
		{ -1.9, "dmg", BOSS, "Flame Wave", 1250, 0.25 },
		{ -0.2, "dmg", BOSS, "Flame Wave", 1400, 0 },
	})
end

local function bomb(s, name)
	F.carry["Living Bomb"] = F.carry["Living Bomb"] or {}
	tinsert(F.carry["Living Bomb"], { name = name, t = F.t0 + s, win = 10, hits = 0, victims = {}, nv = 0 })
	line(s, "debuff", name .. " has Living Bomb", name)
end

local function splash(s, victim, amt)
	local list = F.carry["Living Bomb"]
	local c = list[getn(list)]
	c.hits = c.hits + 1
	if not c.victims[victim] then c.victims[victim] = 0; c.nv = c.nv + 1 end
	c.victims[victim] = c.victims[victim] + amt
	local p = P(victim)
	p.taken = p.taken + amt
	addTo(p.ts, "Living Bomb", amt)
end

local function darkMending(s, kicker)
	local st = F.interrupts["Dark Mending"]
	if not st then st = { casts = 0, kicked = 0, done = 0, by = {} }; F.interrupts["Dark Mending"] = st end
	st.casts = st.casts + 1
	line(s, "cast", ADD .. " begins casting Dark Mending")
	if kicker then
		st.kicked = st.kicked + 1
		addTo(st.by, kicker, 1)
		P(kicker).kicks = P(kicker).kicks + 1
		line(s + 0.4, "info", kicker .. " interrupted Dark Mending", kicker)
	else
		st.done = st.done + 1
		line(s + 2, "interrupt", "Dark Mending was not interrupted (" .. ADD .. ")")
	end
end

local function frenzy(s, len, by)
	op(s, function()
		F.frenzyOn[BOSS_GUID] = F.t0 + s
		line(s, "boss", BOSS .. " gains Frenzy")
	end)
	op(s + len, function()
		F.frenzyOn[BOSS_GUID] = nil
		tinsert(F.frenzies, { t = s, dur = len, by = by, boss = BOSS })
		if by then P(by).tranqs = P(by).tranqs + 1 end
		line(s + len, "tranq", by and (by .. " tranquilized " .. BOSS) or ("Frenzy faded from " .. BOSS), by)
	end)
end

local function save(s, kind, who, target, sp, amt, pre, text)
	tinsert(F.saves, { t = s, kind = kind, who = who, target = target, sp = sp, amt = amt, pre = pre })
	if text then line(s, "save", text, who) end
end

local function consume(name, spell, n)
	local p = P(name)
	addTo(p.consumes, spell, n or 1)
	p.nCons = p.nCons + (n or 1)
end

------------------------------------------------------------------ the fight script

local function newFight(t0, wipe)
	F = W.Tracker.NewFight(t0, BOSS)
	F.demo = true
	F.zone = "Demo - " .. (wipe and "wipe" or "kill")
	F.env = { nampower = true, superwow = true, threat = true }
	F.bosses[BOSS_GUID] = { name = BOSS, dead = false }
	F.nBoss = 1
	F.mainBoss = BOSS_GUID
	F.buffsOk = true
	for i = 1, getn(ROSTER) do
		local r = ROSTER[i]
		local p = W.Tracker.NewPlayer(r[1], r[2])
		p.demoRole, p.demoRate, p.maxhp = r[3], r[4], r[5]
		F.players[r[1]] = p
		local buffs = { ["Power Word: Fortitude"] = true, ["Mark of the Wild"] = true }
		if W.Data.manaClasses[r[2]] then buffs["Arcane Intellect"] = true end
		if r[3] == "tank" then buffs["Flask of the Titans"] = true end
		if r[3] == "heal" then buffs["Distilled Wisdom"] = true end
		if r[1] == "Frostyboi" or r[1] == "Dotsalot" then buffs["Supreme Power"] = true end
		if r[1] == "Axeman" then buffs["Mark of the Wild"] = nil end
		if r[1] == "Afkerson" then buffs = {} end
		local extra = DEMO_BUFFS[r[1]] or {}
		for j = 1, getn(extra) do buffs[extra[j]] = true end
		F.buffs[r[1]] = buffs
		for b in pairs(buffs) do
			if W.Data.consumeBuffs[b] then p.cbuffs[b] = 0 end
		end
	end
	F.bossDebuffs = {
		["Sunder Armor"] = { total = 0, max = 5, rate = 0.95 },
		["Curse of Recklessness"] = { total = 0, max = 1, rate = wipe and 0.62 or 0.9 },
		["Curse of the Elements"] = { total = 0, max = 1, rate = 0.88 },
		["Faerie Fire"] = { total = 0, max = 1, rate = wipe and 0.41 or 0.8 },
	}
end

local function tick(s, wipe)
	local dt = TICK
	for name, p in pairs(F.players) do
		if not p.deadAt then
			local spells = DMG_SPELLS[p.class]
			local active = (name == "Afkerson") and 0.3 or ACT_RATE[p.demoRole]
			local swing = 0.8 + random() * 0.4
			if p.demoRole == "heal" then
				local amt = p.demoRate * dt * swing
				p.heal = p.heal + amt
				split(p.hs, HEAL_SPELLS[p.class], amt)
				p.dmg = p.dmg + 20 * dt
				p.bossDmg = p.bossDmg + 20 * dt
				addTo(p.ds, spells[1], 20 * dt)
				if random() < 0.15 then p.dispels = p.dispels + 1 end
			else
				local amt = p.demoRate * dt * swing
				if name == "Petsmart" or name == "Pewpew" then
					addTo(p.ds, "Pet: Claw", amt * 0.2)
					amt = amt * 0.8
				end
				p.dmg = p.dmg + amt
				p.bossDmg = p.bossDmg + amt
				split(p.ds, spells, amt)
				if name == "Moonbeam" and random() < 0.2 then p.dispels = p.dispels + 1 end
			end
			for sec = floor(s), floor(s + dt) - 1 do
				if random() < active then mark(p, sec, sec) end
			end
			if p.demoRole == "tank" and F.demoHolder == name then
				local amt = 700 * dt * swing
				p.taken = p.taken + amt
				addTo(p.ts, "Melee", amt)
				p.bossSwings = p.bossSwings + 1
				if random() < 0.2 then p.crush = p.crush + 1 end
			end
			local nova = 25 * dt * swing
			p.taken = p.taken + nova
			addTo(p.ts, "Fire Nova", nova)
			if W.Data.manaClasses[p.class] then
				p.mana = p.mana or {}
				local frac
				if p.demoRole == "heal" then
					frac = wipe and math.max(0.04, 1 - s / 175) or math.max(0.32, 1 - s / 230)
				else
					frac = math.max(0.2, 1 - s / 400)
				end
				tinsert(p.mana, s)
				tinsert(p.mana, frac)
			end
		end
	end
	if F.demoHolder then
		local h = P(F.demoHolder)
		if h then h.aggroTime = h.aggroTime + dt end
	end
	for _, u in pairs(F.bossDebuffs) do
		u.total = u.total + dt * (u.rate or 1)
	end
end

local function script(wipe)
	ops, opIdx = {}, 1
	DUR = wipe and 190 or 160

	for s = 0, DUR - TICK, TICK do
		local ss = s
		op(ss + 0.01, function() tick(ss, wipe) end)
	end

	op(0, function()
		line(0, "pull", "Stabbins pulled " .. BOSS, "Stabbins")
		aggro(0.5, "Stabbins", nil, nil, "melee")
		consume("Tankenstein", "Greater Stoneshield", 1)
		consume("Tankenstein", "Elixir of Fortitude", 1)
		consume("Frostyboi", "Mageblood Potion", 1)
		consume("Dotsalot", "Greater Arcane Elixir", 1)
		consume("Stabbins", "Juju Power", 1)
		consume("Axeman", "Elixir of the Mongoose", 1)
		consume("Tankenstein", "Greater Fire Protection Potion", 1)
	end)
	op(60.5, function()
		consume("Pyromancy", "Greater Fire Protection Potion", 1)
		P("Pyromancy").cbuffs["Fire Protection"] = 60.5
		line(60.5, "info", "Pyromancy drinks a Greater Fire Protection Potion", "Pyromancy")
	end)
	op(100.5, function()
		consume("Frostyboi", "Mana Ruby", 1)
		consume("Shadowpat", "Major Mana Potion", 1)
		consume("Windfury", "Healthstone", 1)
	end)
	op(150.5, function()
		consume("Petsmart", "Major Healing Potion", 1)
		consume("Stabbins", "Major Healing Potion", 1)
		consume("Holyroller", "Major Healing Potion", 1)
	end)
	op(3, function() aggro(3, "Tankenstein", "Stabbins", nil, "target") end)
	op(10, function() threat(10, "Stabbins", 74); threat(10, "Frostyboi", 68); threat(10, "Pyromancy", 61) end)

	op(12, function()
		line(12, "debuff", "Lucifron's Curse hits 6 players")
		F.dispelTimes["Lucifron's Curse"] = wipe and { n = 6, total = 84, max = 21, maxWho = "Moonbeam" }
			or { n = 6, total = 22, max = 6, maxWho = "Felbert" }
	end)

	op(20, function() avoidHit(20, "Axeman", "Void Zone", 1100) end)
	op(25, function() darkMending(25, "Stabbins") end)
	op(28, function()
		consume("Mendalot", "Major Mana Potion", 1)
		consume("Holyroller", "Major Mana Potion", 1)
		consume("Leafy", "Nordanaar Herbal Tea", 1)
		consume("Bulwarkus", "Healthstone", 1)
	end)
	op(125, function()
		consume("Mendalot", "Demonic Rune", 1)
		if not wipe then
			consume("Totemtim", "Major Mana Potion", 1)
			consume("Holyroller", "Dark Rune", 1)
		end
	end)

	op(30, function() bomb(30, "Dotsalot") end)
	if wipe then
		op(38, function()
			splash(38, "Leafy", 3200)
			splash(38, "Pewpew", 3200)
			splash(38, "Moonbeam", 3100)
			line(38, "info", "Living Bomb explodes in the raid")
		end)
		op(38.5, function()
			die(38.5, "Leafy", {
				{ -5.0, "dmg", BOSS, "Fire Nova", 150, 0.97 },
				{ -3.0, "debuff", nil, "Lucifron's Curse", nil, 0.97 },
				{ -2.1, "heal", "Totemtim", "Healing Wave", 600, 1 },
				{ -0.5, "dmg", BOSS, "Living Bomb", 3200, 0 },
			}, { "Lucifron's Curse" })
		end)
		op(40, function() threat(40, "Frostyboi", 96) end)
		op(44, function() threat(44, "Frostyboi", 112) end)
		op(45, function() aggro(45, "Frostyboi", "Tankenstein", 112, "target") end)
		op(48.5, function()
			die(48.5, "Frostyboi", {
				{ -6.0, "dmg", BOSS, "Fire Nova", 180, 0.96 },
				{ -3.4, "melee", BOSS, "Melee", 2650, 0.30 },
				{ -2.2, "heal", "Mendalot", "Flash Heal", 900, 0.54 },
				{ -1.0, "melee", BOSS, "Melee", 2890, 0, true },
			}, nil, BOSS)
		end)
		op(49.5, function() aggro(49.5, "Tankenstein", "Frostyboi", nil, "melee") end)
	end

	op(50, function()
		F.stacks["Shockadin"] = { ["Mark of Korth'azz"] = wipe and 5 or 3 }
		line(50, "debuff", "Shockadin has " .. (wipe and 5 or 3) .. " stacks of Mark of Korth'azz", "Shockadin")
	end)
	op(55, function() darkMending(55, "Backstabz") end)
	op(60, function()
		threat(60, "Stabbins", wipe and 104 or 92)
		threat(60, "Pyromancy", 97)
		threat(60, "Dotsalot", 88)
		threat(60, "Axeman", 93)
		threat(60, "Pewpew", 79)
		avoidHit(60, "Axeman", "Void Zone", 1100)
	end)
	op(61, function() avoidHit(61, "Axeman", "Void Zone", 1150) end)
	op(75, function() save(75, "heal", "Mendalot", "Stabbins", "Greater Heal", 2800, 0.12, "Mendalot saves Stabbins at 12% with Greater Heal") end)

	if wipe then
		op(62, function() threat(62, "Pyromancy", 108); aggro(62, "Pyromancy", "Tankenstein", 108, "target") end)
		op(63.2, function()
			tinsert(F.tauntCasts, { t = 63.2, who = "Tankenstein" })
			line(63.2, "taunt", "Tankenstein casts Taunt", "Tankenstein")
		end)
		op(63.5, function() aggro(63.5, "Tankenstein", "Pyromancy", nil, "target") end)
		op(88, function() save(88, "shield", "Mendalot", "Holyroller", "Power Word: Shield", 1150, 0.18, "Mendalot's shield soaks a killing blow on Holyroller") end)
		op(95.5, function() save(95.5, "self", "Tankenstein", "Tankenstein", "Last Stand", nil, 0.21, "Tankenstein pops Last Stand at 21%") end)
		op(100.5, function() save(100.5, "innervate", "Moonbeam", "Holyroller", "Innervate", nil, 0.22, "Moonbeam innervates Holyroller at 22% mana") end)
		op(118, function() save(118, "cooldown", "Holyroller", "Pewpew", "Blessing of Protection", nil, 0.24, "Holyroller bubbles Pewpew at 24%") end)
		op(150.6, function() save(150.6, "potion", "Stabbins", "Stabbins", "Major Healing Potion", nil, 0.19, "Stabbins chugs a Major Healing Potion at 19%") end)
		op(168, function() save(168, "self", "Bulwarkus", "Bulwarkus", "Shield Wall", nil, 0.15, "Bulwarkus pops Shield Wall at 15%") end)
	else
		op(97.5, function() save(97.5, "heal", "Leafy", "Windfury", "Regrowth", 1900, 0.15, "Leafy saves Windfury at 15% with Regrowth") end)
		op(110, function()
			local p = P("Afkerson")
			if p.deadAt then
				p.deadTotal = p.deadTotal + (F.t0 + 110 - p.deadAt)
				p.deadAt = nil
			end
			save(110, "rez", "Moonbeam", "Afkerson", "Rebirth", nil, nil, "Moonbeam battle-rezzes Afkerson")
		end)
	end

	frenzy(70, wipe and 9 or 1.5, (not wipe) and "Pewpew" or nil)
	op(80, function() darkMending(80, (not wipe) and "Axeman" or nil) end)

	op(90, function() aggro(90, "Bulwarkus", "Tankenstein", nil, "target"); line(90, "info", "Tank swap") end)
	op(95, function() avoidHit(95, "Axeman", "Void Zone", 1100) end)
	if wipe then
		op(96, function() avoidHit(96, "Windfury", "Void Zone", 1050) end)
		op(100, function() line(100, "mc", "Shadowpat is mind controlled (Dominate Mind)", "Shadowpat") end)
		op(104, function()
			die(104, "Windfury", {
				{ -4.0, "dmg", "Shadowpat (mind controlled)", "Mind Blast", 1450, 0.68 },
				{ -2.5, "heal", "Holyroller", "Flash of Light", 450, 0.78 },
				{ -1.2, "dmg", "Shadowpat (mind controlled)", "Mind Blast", 1600, 0.42 },
				{ -0.1, "dmg", "Shadowpat (mind controlled)", "Mind Flay", 1900, 0 },
			})
		end)
		op(110, function()
			P("Holyroller").dispels = P("Holyroller").dispels + 1
			save(110, "freed", "Holyroller", "Shadowpat", "Dominate Mind", nil, nil, "Holyroller dispels Dominate Mind from Shadowpat")
		end)
	else
		op(93, function() avoidHit(93, "Afkerson", "Void Zone", 1050) end)
		op(94, function() avoidHit(94, "Afkerson", "Void Zone", 1050) end)
		op(95, function()
			avoidHit(95, "Afkerson", "Void Zone", 1100)
			die(95, "Afkerson", {
				{ -2.1, "dmg", BOSS, "Void Zone", 1050, 0.71 },
				{ -1.1, "dmg", BOSS, "Void Zone", 1050, 0.42 },
				{ -0.1, "dmg", BOSS, "Void Zone", 1100, 0 },
			})
		end)
		op(97, function() avoidHit(97, "Windfury", "Void Zone", 1050) end)
	end
	op(110, function() darkMending(110, "Stabbins") end)
	op(120, function() aggro(120, "Tankenstein", "Bulwarkus", nil, "target"); line(120, "info", "Tank swap") end)
	frenzy(124, 1.5, "Petsmart")

	if not wipe then
		op(140, function() darkMending(140, "Backstabz") end)
		op(159, function()
			F.bosses[BOSS_GUID].dead = true
			line(159, "kill", BOSS .. " dies")
		end)
		return
	end

	-- the wipe
	op(127, function() avoidHit(127, "Axeman", "Void Zone", 1100) end)
	op(128, function() avoidHit(128, "Axeman", "Void Zone", 1150) end)
	op(129, function() avoidHit(129, "Axeman", "Void Zone", 1200) end)
	op(130, function()
		die(130, "Axeman", {
			{ -3.0, "dmg", BOSS, "Void Zone", 1100, 0.66 },
			{ -2.0, "dmg", BOSS, "Void Zone", 1150, 0.43 },
			{ -1.5, "heal", "Totemtim", "Chain Heal", 500, 0.53 },
			{ -1.0, "dmg", BOSS, "Void Zone", 1200, 0.28 },
			{ -0.2, "dmg", BOSS, "Void Zone", 1250, 0 },
		})
	end)
	op(136, function() avoidHit(136, "Mendalot", "Rain of Fire", 700) end)
	op(137, function() avoidHit(137, "Mendalot", "Rain of Fire", 720) end)
	op(138, function() avoidHit(138, "Mendalot", "Rain of Fire", 700) end)
	op(140, function()
		darkMending(140, nil)
		avoidHit(140, "Mendalot", "Rain of Fire", 760)
		die(140, "Mendalot", {
			{ -4.0, "dmg", BOSS, "Rain of Fire", 700, 0.80 },
			{ -3.0, "dmg", BOSS, "Rain of Fire", 720, 0.62 },
			{ -2.0, "dmg", BOSS, "Rain of Fire", 700, 0.45 },
			{ -1.4, "item", "Mendalot", "Healthstone", 0, 0.45 },
			{ -1.0, "dmg", BOSS, "Rain of Fire", 760, 0.20 },
			{ -0.1, "dmg", BOSS, "Rain of Fire", 790, 0 },
		})
	end)
	op(150, function()
		F.raidFails["Magma Blast"] = 1
		line(150, "fail", W.Data.raidFail["Magma Blast"].tip)
	end)
	op(152, function()
		F.taunts["Bulwarkus"] = 1
		line(152, "taunt", "Bulwarkus's Taunt was resisted", "Bulwarkus")
	end)
	op(165, function()
		die(165, "Tankenstein", {
			{ -8.0, "heal", "Holyroller", "Holy Light", 2400, 0.90 },
			{ -4.8, "melee", BOSS, "Melee", 2100, 0.70, nil, "crushing" },
			{ -3.6, "melee", BOSS, "Melee", 2300, 0.45, nil, "crushing" },
			{ -2.4, "dmg", BOSS, "Fire Nova", 300, 0.42 },
			{ -1.2, "melee", BOSS, "Melee", 2200, 0.18, nil, "crushing" },
			{ -0.1, "melee", BOSS, "Melee", 1650, 0, true },
		}, nil, BOSS)
	end)
	op(166, function() aggro(166, "Bulwarkus", "Tankenstein", nil, "melee") end)
	op(170, function()
		F.enraged = 170
		F.enrageBoss = BOSS
		line(170, "enrage", BOSS .. " goes Berserk at 31% health")
	end)
	op(172, function()
		die(172, "Bulwarkus", {
			{ -3.5, "melee", BOSS, "Melee", 3100, 0.55, true },
			{ -2.0, "heal", "Totemtim", "Lesser Healing Wave", 700, 0.63 },
			{ -1.2, "melee", BOSS, "Melee", 3300, 0.25, true },
			{ -0.1, "melee", BOSS, "Melee", 2400, 0 },
		}, nil, BOSS)
	end)
	local cascade = { "Holyroller", "Totemtim", "Stabbins", "Pewpew", "Pyromancy", "Felbert", "Backstabz", "Dotsalot", "Moonbeam", "Shadowpat" }
	for i = 1, getn(cascade) do
		local s, n = 172 + i * 1.6, cascade[i]
		op(s, function() generic(s, n) end)
	end
	op(189, function() line(189, "info", "Petsmart feigned death") end)
end

------------------------------------------------------------------ running

local function applyUntil(v)
	while ops[opIdx] and ops[opIdx][1] <= v do
		ops[opIdx][2]()
		opIdx = opIdx + 1
	end
end

local function finishRec(wipe)
	F.tEnd = F.t0 + DUR
	F.result = wipe and "WIPE" or "KILL"
	if not wipe then F.killedAt = F.t0 + DUR end
	line(DUR, wipe and "wipe" or "kill", wipe and "Wipe" or "Encounter won")
	local rec = W.Analyzer:Build(F, true)
	rec.demo = true
	rec.zone = F.zone
	return rec
end

local function sortOps()
	table.sort(ops, function(a, b) return a[1] < b[1] end)
end

-- moves the fight clock (and every absolute timestamp in it) by delta
local function shift(delta)
	F.t0 = F.t0 + delta
	for _, p in pairs(F.players) do if p.deadAt then p.deadAt = p.deadAt + delta end end
	for _, list in pairs(F.carry) do for i = 1, getn(list) do list[i].t = list[i].t + delta end end
	for g, v in pairs(F.frenzyOn) do F.frenzyOn[g] = v + delta end
	for i = 1, getn(F.deaths) do F.deaths[i].at = F.deaths[i].at + delta end
end

local live

local function buildInstant(wipe)
	newFight(0, wipe)
	script(wipe)
	sortOps()
	applyUntil(DUR)
	-- the script ran on a clock starting at 0: make it end right now
	shift(GetTime() - DUR)
	return finishRec(wipe)
end

function Demo:Instant()
	if live then W.Print("Wait for the live demo to finish.") return end
	local kill = buildInstant(false)
	tinsert(WhoDidItDB.fights, 1, kill)
	local wipe = buildInstant(true)
	W.Print("|cff33ccffDemo:|r added two sample fights (a wipe and a kill). Click Name & Shame / Big Them Up to post them (tagged DEMO) to " .. W.Shout:ChannelLabel() .. ".")
	W:SaveFight(wipe)
	W.UI:ShowFight(1)
end

-- live: the fight clock runs LIVE_SPEED times faster than real time. Every
-- update moves t0 (and every absolute timestamp) back so GetTime() - t0
-- equals the virtual fight time, exactly like a real fight seen by the UI.
function Demo:Live()
	if W.Tracker.fight then W.Print("A fight is already being tracked.") return end
	newFight(GetTime(), true)
	script(true)
	sortOps()
	live = { start = GetTime(), fight = F }
	W.Tracker.fight = F
	W.Print("|cff33ccffDemo:|r playing a live wipe at " .. LIVE_SPEED .. "x speed (~" .. floor(DUR / LIVE_SPEED) .. "s). Watch the LIVE entry.")
	W.UI.selIdx = 0
	W.UI.liveRec = nil
	W.UI.detail = nil
	W.UI.tab = "summary"
	W.UI:Open()
end

W:Every(0.1, function()
	if not live then return end
	if W.Tracker.fight ~= live.fight then
		live = nil
		W.Print("|cff33ccffDemo:|r stopped (a real fight started).")
		return
	end
	F = live.fight
	local v = (GetTime() - live.start) * LIVE_SPEED
	shift((GetTime() - v) - F.t0)
	applyUntil(math.min(v, DUR))
	if v >= DUR then
		live = nil
		W.Tracker.fight = nil
		shift((GetTime() - DUR) - F.t0)
		W:SaveFight(finishRec(true))
	end
end)

function Demo:Clear()
	local fights = WhoDidItDB.fights
	for i = getn(fights), 1, -1 do
		if fights[i].demo then tremove(fights, i) end
	end
	W.Print("Demo fights removed.")
	W.UI:OnFightEnd()
end

function Demo:Run(arg)
	arg = strlower(arg or "")
	if arg == "live" then Demo:Live()
	elseif arg == "clear" then Demo:Clear()
	else Demo:Instant() end
end
