--[[--------------------------------------------------------------------
	WhoDidIt - analyzer: turns a fight (live or finished) into a report:
	death causes, mistakes, blame points and a wipe verdict
----------------------------------------------------------------------]]

local W = WhoDidIt
local A = {}
W.Analyzer = A

local floor = math.floor
local getn = table.getn
local FmtTime = W.FmtTime
local FmtNum = W.FmtNum

local CAN_TANK = { WARRIOR = true, DRUID = true, PALADIN = true, SHAMAN = true }

local function topList(t, n)
	local list = {}
	for k, v in pairs(t) do tinsert(list, { k, v }) end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	while getn(list) > n do tremove(list) end
	return list
end

local function round1(v) return floor(v * 10 + 0.5) / 10 end

function A.AvoidRule(spell, role)
	local rule = W.Data.avoid[spell]
	if not rule and WhoDidItDB.avoid[spell] then rule = W.Data.customRule end
	if not rule or (rule.notTank and role == "tank") then return nil end
	return rule
end

-- mana fraction of a player at time t (samples are flat t,pct pairs)
local function manaAt(s, t)
	if not s then return nil end
	local v
	for i = 1, getn(s), 2 do
		if s[i] > t then break end
		v = s[i + 1]
	end
	return v
end

-- category of a used item: Mana / Protection / Health / Other
local function matchAny(name, patterns)
	for i = 1, getn(patterns) do
		if string.find(name, patterns[i], 1, true) then return true end
	end
end

function A.ItemCat(name)
	local D = W.Data
	if matchAny(name, D.manaItems) then return "Mana" end
	if matchAny(name, D.protItems) then return "Protection" end
	if matchAny(name, D.healthItems) then return "Health" end
	return "Other"
end

local BUFF_ORDER = { Flask = 1, Elixir = 2, Food = 3, Buff = 4, Protection = 5, Potion = 6 }
local USED_ORDER = { Mana = 1, Health = 2, Protection = 3, Other = 4 }

-- { name, category, firstSeen } sorted by category, for the Consumes tab
local function buffList(p)
	local out = {}
	for b, t in pairs(p.cbuffs or {}) do
		tinsert(out, { b, W.Data.consumeBuffs[b] or "Buff", t })
	end
	table.sort(out, function(a, b)
		local x, y = BUFF_ORDER[a[2]] or 9, BUFF_ORDER[b[2]] or 9
		if x ~= y then return x < y end
		return a[1] < b[1]
	end)
	return out
end

-- { item, count, category } sorted by category
local function usedList(p)
	local out = {}
	for item, c in pairs(p.consumes or {}) do
		tinsert(out, { item, c, A.ItemCat(item) })
	end
	table.sort(out, function(a, b)
		local x, y = USED_ORDER[a[3]] or 9, USED_ORDER[b[3]] or 9
		if x ~= y then return x < y end
		return a[1] < b[1]
	end)
	return out
end

------------------------------------------------------------------ build

function A:Build(F, final)
	local D = W.Data
	local db = WhoDidItDB
	local now = final and F.tEnd or GetTime()
	local dur = now - F.t0
	if dur < 1 then dur = 1 end

	local rec = {
		enc = F.enc, zone = F.zone, date = F.date, dur = dur,
		result = final and F.result or "LIVE",
		env = F.env, findings = {}, causes = {}, deaths = {}, blame = {},
		players = {}, aggro = {}, notes = {}, threat = {},
		timeline = F.timeline,
	}

	------------------------------------------------ blame bookkeeping
	local blame = {}
	local function addBlame(name, pts, reason)
		if not name or not pts or pts <= 0 then return end
		local b = blame[name]
		if not b then b = { pts = 0, reasons = {} }; blame[name] = b end
		b.pts = b.pts + pts
		tinsert(b.reasons, reason)
	end
	local function find(t, who, cat, pts, text, tip)
		tinsert(rec.findings, { t = t, who = who, cat = cat, pts = pts or 0, text = text, tip = tip })
		addBlame(who, pts, text)
	end
	-- fn (optional) builds the click-through detail rows; it runs at the very
	-- end so everything (activity, roles, mana) is known
	local function cause(score, text, tip, fn)
		tinsert(rec.causes, { s = score, text = text, tip = tip, fn = fn })
	end
	-- per-player mistake counters (used by the shout-outs)
	local tally = {}
	local function tal(name)
		local t = tally[name]
		if not t then
			t = { avoidDmg = 0, avoidHits = 0, pulls = 0, splash = 0 }
			tally[name] = t
		end
		return t
	end

	------------------------------------------------ roles & participation
	local players = F.players
	local nPart = 0
	for name, p in pairs(players) do
		local dead = (p.deadTotal or 0) + (p.deadAt and math.max(0, now - p.deadAt) or 0)
		p._alive = math.max(0, dur - dead)
		p._part = (p.nAct > 0 or p.taken > 0 or p.dmg > 0 or p.heal > 0 or p.deadAt ~= nil or p.deadTotal > 0)
		if p._part then nPart = nPart + 1 end
		local role = "dps"
		if db.tanks[name] then
			role = "tank"
		elseif CAN_TANK[p.class] and p.aggroTime >= math.max(8, dur * 0.15) then
			role = "tank"
		elseif p.heal > 0 and p.heal >= p.dmg then
			role = "heal"
		elseif CAN_TANK[p.class] and F.firstHolder == name and p.aggroTime >= 4 then
			role = "tank"
		end
		p._role = role
	end
	if nPart == 0 then nPart = 1 end

	local tanks = {}
	for name, p in pairs(players) do
		if p._role == "tank" then tinsert(tanks, name) end
	end

	------------------------------------------------ deaths
	local deaths = {}
	for i = 1, getn(F.deaths) do
		if not F.deaths[i].fd then tinsert(deaths, F.deaths[i]) end
	end
	table.sort(deaths, function(a, b) return a.t < b.t end)

	local wipeT = dur
	if rec.result ~= "KILL" and rec.result ~= "LIVE" then
		local need = math.max(1, math.ceil(nPart * 0.4))
		if deaths[need] then wipeT = deaths[need].t end
		rec.wipeT = wipeT
	end

	local bossNames = {}
	for _, b in pairs(F.bosses) do bossNames[b.name] = true end
	local noAggro = F.encDef and F.encDef.noAggro

	-- carrier that splashed a given victim around time t
	local function carrierFor(victim, t)
		for debuff, list in pairs(F.carry) do
			for i = 1, getn(list) do
				local c = list[i]
				local ct = c.t - F.t0
				if c.victims[victim] and t >= ct - 1 and t <= ct + c.win + 6 then return c.name, debuff end
			end
		end
	end

	local mechDeaths, aggroDeaths, tankDeaths, healDeaths = {}, {}, {}, {}
	for i = 1, getn(deaths) do
		local d = deaths[i]
		local p = players[d.name]
		local role = p and p._role or "dps"
		local late = rec.wipeT and d.t > wipeT + 0.05
		local mult = late and 0.25 or 1

		local dmg5, heal5, nheal, crush, avoidDmg = 0, 0, 0, 0, 0
		local top, avoidTop = {}, {}
		local killer, splashLine
		for j = 1, getn(d.lines) do
			local l = d.lines[j]
			local isDmg = (l.k == "dmg" or l.k == "melee" or l.k == "env")
			if d.t - l.t <= 5 then
				if l.k == "heal" then
					heal5 = heal5 + (l.a or 0)
					nheal = nheal + 1
				elseif isDmg then
					dmg5 = dmg5 + (l.a or 0)
					local key = (l.sp or "?") .. " (" .. (l.s or "?") .. ")"
					top[key] = (top[key] or 0) + (l.a or 0)
					if l.x == "crushing" then crush = crush + 1 end
					if A.AvoidRule(l.sp, role) then
						avoidDmg = avoidDmg + (l.a or 0)
						avoidTop[l.sp] = (avoidTop[l.sp] or 0) + (l.a or 0)
					end
					if D.splashIdx[l.sp] then splashLine = l end
				end
			end
			if isDmg then killer = l end
		end
		local biggest, biggestAmt = nil, 0
		for k, v in pairs(top) do
			if v > biggestAmt then biggest = k; biggestAmt = v end
		end

		local expected
		for j = 1, getn(d.debuffs) do
			if D.expectedDeath[d.debuffs[j]] then expected = d.debuffs[j] end
		end

		local ksp = killer and killer.sp
		local ksrc = killer and killer.s
		local carrier, carrierDebuff
		if splashLine then carrier, carrierDebuff = carrierFor(d.name, d.t) end

		local kind, text, faultWho, faultPts
		if ksrc and string.find(ksrc, "(mind controlled)", 1, true) then
			kind, text = "mc", "Killed by " .. ksrc
		elseif expected then
			kind, text = "expected", "Died to " .. expected .. " (part of the mechanic)"
		elseif killer and killer.k == "env" then
			kind, text = "avoid", "Died to " .. ksp
			faultWho, faultPts = d.name, 3
		elseif carrier and carrier ~= d.name then
			kind, text = "splash", "Killed by " .. carrier .. "'s " .. carrierDebuff
			faultWho, faultPts = carrier, 3
		elseif (ksp and A.AvoidRule(ksp, role)) or (dmg5 > 0 and avoidDmg / dmg5 >= 0.4) then
			local sp = (ksp and A.AvoidRule(ksp, role)) and ksp
			if not sp then
				local best = 0
				for s, v in pairs(avoidTop) do if v > best then best = v; sp = s end end
			end
			kind, text = "avoid", "Stood in " .. (sp or "avoidable damage")
			faultWho, faultPts = d.name, 3
			d.avoidSpell = sp
		elseif role ~= "tank" and killer and killer.k == "melee" and bossNames[ksrc or ""] then
			kind, text = "aggro", "Meleed to death by " .. ksrc .. " - had aggro"
			faultWho, faultPts = d.name, 2
		elseif role == "tank" then
			kind = "tank"
			if nheal == 0 then
				text = "Tank died - received no heals in the last 5s"
			elseif crush >= 2 then
				text = "Tank died - " .. crush .. " crushing blows, " .. FmtNum(dmg5) .. " taken in 5s"
			else
				text = "Tank died - " .. FmtNum(dmg5) .. " taken vs " .. FmtNum(heal5) .. " healed in 5s"
			end
		elseif ksrc and players[ksrc] and ksrc ~= d.name then
			kind, text = "ff", "Killed by " .. ksrc .. "'s " .. (ksp or "attack")
		else
			kind = "overwhelmed"
			text = "Overwhelmed - " .. FmtNum(dmg5) .. " dmg in 5s" .. (biggest and (", mostly " .. biggest) or "") .. ", healed " .. FmtNum(heal5)
		end

		local base = (kind == "mc" or kind == "expected") and 0 or (late and 0.25 or 1)
		local own = (faultWho == d.name) and (faultPts * mult) or 0
		find(d.t, d.name, "Death", base + own, d.name .. " died: " .. text)
		if faultWho and faultWho ~= d.name then
			addBlame(faultWho, faultPts * mult, "Killed " .. d.name .. " with " .. (carrierDebuff or ksp or "?"))
		end

		tinsert(rec.deaths, {
			name = d.name, class = d.class, t = d.t, role = role, late = late,
			kind = kind, text = text, lines = d.lines, debuffs = d.debuffs, cons = d.cons,
			killer = killer and ((ksp or "?") .. (ksrc and (" (" .. ksrc .. ")") or "")) or "Unknown",
			killAmt = killer and killer.a, dmg5 = dmg5, heal5 = heal5, nheal = nheal, crush = crush,
			hadAggro = d.hadAggro,
		})
		local ri = getn(rec.deaths)

		if not late then
			if kind == "tank" then tinsert(tankDeaths, { d = d, text = text, ri = ri }) end
			if kind == "aggro" then tinsert(aggroDeaths, { name = d.name, ri = ri }) end
			if kind == "avoid" or kind == "splash" then
				local key = d.avoidSpell or carrierDebuff or ksp or "mechanics"
				mechDeaths[key] = mechDeaths[key] or {}
				tinsert(mechDeaths[key], { name = d.name, ri = ri })
			end
			if role == "heal" then tinsert(healDeaths, { name = d.name, ri = ri }) end
		end
	end

	------------------------------------------------ cause detail helpers
	local function R(l, r, x)
		local t = x or {}
		t.l = l
		t.r = r
		return t
	end
	local function H(text) return { l = "|cffffd100" .. text .. "|r", head = true } end
	local function nameC(n)
		local p = players[n]
		return W.CName(n, p and p.class)
	end
	local function pctS(v) return v and (floor(v * 100 + 0.5) .. "%") or "?" end
	local function manaCol(m)
		if not m then return "|cff888888?|r" end
		local c = (m < 0.15 and "|cffff5555") or (m < 0.35 and "|cffff9933") or "|cff33ff33"
		return c .. floor(m * 100) .. "%|r"
	end
	local function names(list)
		local out = {}
		for i = 1, getn(list) do out[i] = list[i].name end
		return table.concat(out, ", ")
	end
	-- consumables a player used whose name contains one of the patterns
	local function itemsUsed(p, patterns)
		local out = {}
		for item, c in pairs(p and p.consumes or {}) do
			for i = 1, getn(patterns) do
				if string.find(item, patterns[i], 1, true) then
					tinsert(out, item .. ((c > 1) and (" x" .. c) or ""))
					break
				end
			end
		end
		table.sort(out)
		return out
	end
	-- index (in rec.deaths) of name's latest death at or before t
	local function deathOf(name, t)
		local found
		for i = 1, getn(rec.deaths) do
			local d = rec.deaths[i]
			if d.name == name and d.t <= t + 0.01 then found = i end
		end
		return found
	end
	local function deathLink(i, label)
		local d = rec.deaths[i]
		return R("|cff33ccff> " .. (label or (d.name .. " died at " .. FmtTime(d.t) .. " - " .. d.text)) .. "|r", nil, { death = i })
	end

	-- who healed / hit someone in their last 5 seconds
	local function deathRows(rows, i)
		local d = rec.deaths[i]
		tinsert(rows, H(d.name .. " died at " .. FmtTime(d.t) .. "  (" .. (d.role or "?") .. ")"))
		tinsert(rows, R(d.text))
		tinsert(rows, R("Killing blow: " .. (d.killer or "?"), d.killAmt and ("|cffff5555-" .. FmtNum(d.killAmt) .. "|r")))
		local heals, spells, hits = {}, {}, {}
		for j = 1, getn(d.lines) do
			local l = d.lines[j]
			if d.t - l.t <= 5 then
				if l.k == "heal" then
					local who = l.s or "?"
					heals[who] = (heals[who] or 0) + (l.a or 0)
					spells[who] = spells[who] or {}
					spells[who][l.sp or "?"] = true
				elseif l.k == "dmg" or l.k == "melee" or l.k == "env" then
					local key = (l.sp or "?") .. " from " .. (l.s or "?")
					hits[key] = (hits[key] or 0) + (l.a or 0)
				end
			end
		end
		tinsert(rows, H("Heals received in the last 5 seconds"))
		local hl = topList(heals, 10)
		if getn(hl) == 0 then tinsert(rows, R("|cffff5555Nobody healed " .. d.name .. "|r")) end
		for j = 1, getn(hl) do
			local sp = {}
			for s in pairs(spells[hl[j][1]]) do tinsert(sp, s) end
			tinsert(rows, R(nameC(hl[j][1]) .. "  |cffaaaaaa" .. table.concat(sp, ", ") .. "|r", "|cff33ff33+" .. FmtNum(hl[j][2]) .. "|r"))
		end
		tinsert(rows, H("Damage taken in the last 5 seconds"))
		local dl = topList(hits, 8)
		for j = 1, getn(dl) do tinsert(rows, R(dl[j][1], "|cffff5555-" .. FmtNum(dl[j][2]) .. "|r")) end
		if (d.crush or 0) > 0 then tinsert(rows, R("|cffff9933" .. d.crush .. " crushing blow(s)|r")) end
		local hp = itemsUsed(players[d.name], D.healthItems)
		tinsert(rows, R("Health consumables used this fight: " .. (getn(hp) > 0 and table.concat(hp, ", ") or "|cffff5555none|r")))
		if d.debuffs and getn(d.debuffs) > 0 then tinsert(rows, R("Debuffs at death: " .. table.concat(d.debuffs, ", "))) end
		tinsert(rows, deathLink(i, "Open the full death recap"))
	end

	-- every healer's state at time t: alive/dead, mana, healing, mana consumables
	local function healerRows(rows, t, title)
		tinsert(rows, H(title))
		local list = {}
		for name, p in pairs(players) do
			if p._role == "heal" then tinsert(list, name) end
		end
		table.sort(list, function(a, b) return players[a].heal > players[b].heal end)
		if getn(list) == 0 then tinsert(rows, R("|cff888888No healers detected.|r")) end
		for i = 1, getn(list) do
			local name = list[i]
			local p = players[name]
			local di = deathOf(name, t)
			local state
			if di then
				state = "|cff888888dead since " .. FmtTime(rec.deaths[di].t) .. "|r"
			else
				state = "mana " .. manaCol(manaAt(p.mana, t))
			end
			tinsert(rows, R(nameC(name) .. "  " .. state,
				FmtNum(p.heal) .. " healed  |cffaaaaaa(" .. FmtNum(p.heal / math.max(1, p._alive)) .. "/s)|r"))
			local mi = itemsUsed(p, D.manaItems)
			tinsert(rows, R("      |cffaaaaaaMana consumables:|r " .. (getn(mi) > 0 and ("|cff33ff33" .. table.concat(mi, ", ") .. "|r") or "|cffff5555none used|r")))
		end
	end

	------------------------------------------------ aggro
	local function diedSoon(name, t)
		for i = 1, getn(deaths) do
			local d = deaths[i]
			if d.name == name and d.t >= t and d.t <= t + 10 then return true end
		end
	end
	for i = 1, getn(F.aggro) do
		local a = F.aggro[i]
		local p = players[a.to]
		local role = p and p._role
		local verdict
		if role == "tank" then
			verdict = "tank"
		elseif a.oldDead then
			verdict = "inherit"
		elseif not a.from and a.t < 6 then
			verdict = "pull"
			-- hunters pull and Feign Death on purpose
			local pts = (a.class == "HUNTER" and 0) or ((rec.result == "KILL") and 1 or 3)
			find(a.t, a.to, "Pull", pts, a.to .. " had first aggro on " .. a.boss .. " (pulled before the tank)")
		elseif noAggro and not (a.perc and a.perc >= 100) then
			verdict = "mechanic"
		else
			verdict = "pulled"
			tal(a.to).pulls = tal(a.to).pulls + 1
			local died = diedSoon(a.to, a.t)
			find(a.t, a.to, "Aggro", died and 6 or 4,
				a.to .. " pulled aggro on " .. a.boss .. (a.from and (" from " .. a.from) or "")
				.. (a.perc and (" at " .. a.perc .. "% threat") or "") .. (died and " and died" or ""))
		end
		tinsert(rec.aggro, { t = a.t, boss = a.boss, to = a.to, class = a.class, from = a.from, perc = a.perc, how = a.how, verdict = verdict })
	end

	------------------------------------------------ avoidable damage
	for name, list in pairs(F.avoid) do
		local p = players[name]
		local role = p and p._role
		for spell, r in pairs(list) do
			local rule = A.AvoidRule(spell, role)
			if rule then
				local tl = tal(name)
				tl.avoidDmg = tl.avoidDmg + r.dmg
				tl.avoidHits = tl.avoidHits + r.hits
				if r.hits > (tl.worstHits or 0) then
					tl.worstHits = r.hits
					tl.worstSpell = spell
				end
				local pts = math.min(6, r.inst * (rule.w or 1))
				find(r.first, name, "Mechanic", round1(pts),
					name .. " hit by " .. spell .. " " .. r.hits .. "x (" .. FmtNum(r.dmg) .. " dmg)",
					{ rule.tip, r.inst .. " separate time(s)" })
			end
		end
	end

	------------------------------------------------ carriers
	for debuff, list in pairs(F.carry) do
		local rule = D.carriers[debuff]
		for i = 1, getn(list) do
			local c = list[i]
			if c.nv > 0 then
				tal(c.name).splash = tal(c.name).splash + c.nv
				local names = {}
				for v, amt in pairs(c.victims) do tinsert(names, v .. " (" .. FmtNum(amt) .. ")") end
				find(c.t - F.t0, c.name, "Mechanic", math.min(8, 2 + c.nv),
					c.name .. "'s " .. debuff .. " hit " .. c.nv .. " other player(s)",
					{ rule and rule.tip or "", "Hit: " .. table.concat(names, ", ") })
				local cc, cd, cr = c, debuff, rule
				cause(15 * c.nv, debuff .. " on " .. c.name .. " hit " .. c.nv .. " player(s)", nil, function()
					local ct = cc.t - F.t0
					local rows = { H(cd .. " on " .. cc.name .. " at " .. FmtTime(ct)) }
					if cr then tinsert(rows, R(cr.tip)) end
					tinsert(rows, R("Carrier: " .. nameC(cc.name), cc.hits .. " hit(s) on others"))
					tinsert(rows, H("Players caught in the explosion"))
					for v, amt in pairs(cc.victims) do
						local di = deathOf(v, ct + cc.win + 8)
						local died = di and rec.deaths[di].t >= ct
						tinsert(rows, R(nameC(v) .. (died and ("  |cffff5555died at " .. FmtTime(rec.deaths[di].t) .. " (click)|r") or ""),
							"|cffff5555-" .. FmtNum(amt) .. "|r", died and { death = di } or nil))
					end
					return rows
				end)
			end
		end
	end

	------------------------------------------------ stacks
	for name, s in pairs(F.stacks) do
		local p = players[name]
		for sp, n in pairs(s) do
			local r = D.stacks[sp]
			if r and n >= r.max and not (r.notTank and p and p._role == "tank") then
				find(nil, name, "Mechanic", 2, name .. " reached " .. n .. " stacks of " .. sp, { r.tip })
			end
		end
	end

	------------------------------------------------ interrupts / dispels / tranq / raid fails
	for sp, st in pairs(F.interrupts) do
		if st.done > 0 then
			local tip = {}
			for n, c in pairs(st.by) do tinsert(tip, n .. ": " .. c .. " interrupt(s)") end
			if getn(tip) == 0 then tip = { "Nobody interrupted it." } end
			find(nil, nil, "Interrupt", 0, sp .. " went through " .. st.done .. " of " .. st.casts .. " times", tip)
			local isp, ist = sp, st
			cause(12 * st.done, sp .. " was not interrupted (" .. st.done .. "x)", tip, function()
				local rows = {
					H(isp),
					R("Cast " .. ist.casts .. " times", "interrupted " .. ist.kicked .. "   |cffff5555went through " .. ist.done .. "|r"),
					H("Interrupts landed"),
				}
				local kl = topList(ist.by, 10)
				if getn(kl) == 0 then tinsert(rows, R("|cffff5555Nobody interrupted it|r")) end
				for i = 1, getn(kl) do tinsert(rows, R(nameC(kl[i][1]), kl[i][2] .. "x")) end
				tinsert(rows, H("Players with an interrupt who never used one"))
				local idle = {}
				for name, p in pairs(players) do
					if p._part and D.kickClasses[p.class] and p.kicks == 0 then tinsert(idle, nameC(name)) end
				end
				table.sort(idle)
				tinsert(rows, R(getn(idle) > 0 and table.concat(idle, ", ") or "|cff33ff33Everyone with an interrupt used it|r"))
				return rows
			end)
		end
	end

	for sp, d in pairs(F.dispelTimes) do
		local avg = d.total / d.n
		if avg > (D.dispelSlow or 6) then
			local tip = {
				string.format("Longest: %.1fs on %s", d.max, d.maxWho or "?"),
				"Applied and removed " .. d.n .. " time(s)",
			}
			find(nil, nil, "Dispel", 0, string.format("%s (%s) stayed on players %.1fs on average", sp, D.dispel[sp] or "?", avg), tip)
			local dsp, dd, davg = sp, d, avg
			cause(4 * d.n, "Slow removal of " .. sp .. string.format(" (avg %.1fs)", avg), tip, function()
				local typ = D.dispel[dsp] or "?"
				local rows = {
					H(dsp .. " (" .. typ .. ")"),
					R("Average time on a player", string.format("%.1fs", davg)),
					R("Longest", string.format("%.1fs on %s", dd.max, dd.maxWho or "?")),
					R("Times it was removed", tostring(dd.n)),
					H("Who can remove " .. typ .. " effects (dispels this fight)"),
				}
				local can = D.dispellers[typ] or {}
				local list = {}
				for name, p in pairs(players) do
					if p._part and can[p.class] then tinsert(list, { name, p.dispels }) end
				end
				table.sort(list, function(a, b) return a[2] > b[2] end)
				if getn(list) == 0 then tinsert(rows, R("|cffff5555Nobody in the raid can remove it|r")) end
				for i = 1, getn(list) do
					tinsert(rows, R(nameC(list[i][1]), (list[i][2] == 0 and "|cffff5555" or "") .. list[i][2] .. " dispels|r"))
				end
				return rows
			end)
		end
	end

	local hunterTip = {}
	for name, p in pairs(players) do
		if p.class == "HUNTER" and p._part then tinsert(hunterTip, name .. ": " .. p.tranqs .. " Tranquilizing Shot(s)") end
	end
	local frenzies = {}
	for i = 1, getn(F.frenzies) do frenzies[i] = F.frenzies[i] end
	for guid, st in pairs(F.frenzyOn) do
		local b = F.bosses[guid]
		tinsert(frenzies, { t = st - F.t0, dur = now - st, boss = b and b.name or "Boss", open = true })
	end
	for i = 1, getn(frenzies) do
		local fz = frenzies[i]
		if fz.dur > 4 then
			find(fz.t, nil, "Tranq", 0, fz.boss .. "'s Frenzy lasted " .. floor(fz.dur) .. "s" .. (fz.by and "" or " (not tranquilized)"), hunterTip)
			local ffz = fz
			cause(10, fz.boss .. " stayed frenzied for " .. floor(fz.dur) .. "s", hunterTip, function()
				local rows = {
					H(ffz.boss .. " - Frenzy at " .. FmtTime(ffz.t)),
					R("Lasted", floor(ffz.dur) .. "s"),
					R("Removed by", ffz.by and nameC(ffz.by) or "|cffff5555nobody - it ran out|r"),
					H("Hunters (Tranquilizing Shots this fight)"),
				}
				local any = false
				for name, p in pairs(players) do
					if p.class == "HUNTER" and p._part then
						any = true
						tinsert(rows, R(nameC(name), (p.tranqs == 0 and "|cffff5555" or "") .. p.tranqs .. "|r"))
					end
				end
				if not any then tinsert(rows, R("|cffff5555No hunters in the raid|r")) end
				return rows
			end)
		end
	end

	for sp, n in pairs(F.raidFails) do
		local r = D.raidFail[sp]
		find(nil, nil, "Tanking", 0, r.tip .. " (" .. n .. "x)")
		local rsp, rr, rn = sp, r, n
		cause(25 * n, r.tip, nil, function()
			local rows = { H(rsp), R(rr.tip), R("Times cast", tostring(rn)), H("Tanks") }
			for i = 1, getn(tanks) do
				local p = players[tanks[i]]
				local di = deathOf(tanks[i], dur)
				tinsert(rows, R(nameC(tanks[i]) .. (di and ("  |cff888888died " .. FmtTime(rec.deaths[di].t) .. "|r") or ""),
					"held aggro " .. FmtTime(p.aggroTime)))
			end
			return rows
		end)
		if r.blame == "tank" then
			for i = 1, getn(tanks) do addBlame(tanks[i], math.min(4, n), sp .. " cast " .. n .. "x") end
		end
	end

	for name, n in pairs(F.taunts) do
		find(nil, nil, "Tanking", 0, name .. " had " .. n .. " taunt(s) resisted")
	end

	------------------------------------------------ activity & damage
	if F.env.superwow then
		for name, p in pairs(players) do
			if p._part and p._alive >= 20 and p._role ~= "tank" then
				local pct = math.min(1, p.nAct / p._alive)
				p._act = pct
				local lim = (p._role == "heal") and 0.35 or 0.6
				if pct < lim then
					find(nil, name, "Activity", (pct < lim * 0.6) and 3 or 1.5,
						name .. " was only doing something " .. floor(pct * 100) .. "% of their time alive",
						{ "Measured from casts, swings, damage and heals in 1s buckets.", "Alive for " .. FmtTime(p._alive) })
				end
			end
		end
	end

	local dpsList = {}
	for name, p in pairs(players) do
		if p._part and p._role == "dps" and p._alive >= 30 then
			p._dps = p.dmg / p._alive
			tinsert(dpsList, p._dps)
		end
	end
	if getn(dpsList) >= 4 then
		table.sort(dpsList)
		local med = dpsList[math.ceil(getn(dpsList) / 2)]
		for name, p in pairs(players) do
			if p._dps and med > 0 and p._dps < med * 0.4 then
				find(nil, name, "DPS", 1.5, name .. " did " .. floor(p._dps) .. " DPS (raid median " .. floor(med) .. ")")
			end
		end
	end

	for name, amt in pairs(F.ffire) do
		if amt >= 1000 then find(nil, name, "Friendly fire", 0, name .. " dealt " .. FmtNum(amt) .. " damage to the raid") end
	end

	------------------------------------------------ threat peaks
	for name, pk in pairs(F.threatPeak) do
		local p = players[name]
		rec.threat[name] = { perc = pk.perc, t = pk.t, boss = pk.boss, class = p and p.class }
		if p and p._role ~= "tank" and pk.perc >= 105 then
			find(pk.t, name, "Threat", 0.5, name .. " hit " .. pk.perc .. "% threat on " .. pk.boss)
		end
	end

	------------------------------------------------ boss enrage, mana
	if F.enraged then
		find(F.enraged, nil, "Enrage", 0, (F.enrageBoss or "Boss") .. " went berserk at " .. FmtTime(F.enraged))
		cause(90, (F.enrageBoss or "Boss") .. " went berserk at " .. FmtTime(F.enraged) .. " - not enough damage", nil, function()
			local et = F.enraged
			local total = 0
			for _, p in pairs(players) do total = total + p.bossDmg end
			local lost, nd = 0, 0
			for i = 1, getn(rec.deaths) do
				if rec.deaths[i].t < et then
					lost = lost + (et - rec.deaths[i].t)
					nd = nd + 1
				end
			end
			local rows = {
				H("Damage check"),
				R("Boss enraged at", FmtTime(et)),
				R("Raid damage on bosses", FmtNum(total) .. "  |cffaaaaaa(" .. FmtNum(total / dur) .. " raid DPS)|r"),
				R("Uptime lost to deaths before the enrage", nd .. " death(s), " .. FmtTime(lost) .. " of dead time"),
			}
			local list = {}
			for name, p in pairs(players) do
				if p._part and p._role == "dps" then tinsert(list, { name, p.dmg / math.max(1, p._alive), p }) end
			end
			table.sort(list, function(a, b) return a[2] < b[2] end)
			tinsert(rows, H("Lowest damage (DPS players)"))
			for i = 1, math.min(6, getn(list)) do
				local x = list[i]
				tinsert(rows, R(nameC(x[1]) .. "  |cffaaaaaaactive " .. pctS(x[3]._act) .. ", " .. x[3].nCons .. " consumables|r", floor(x[2]) .. " DPS"))
			end
			tinsert(rows, H("Top damage"))
			for i = getn(list), math.max(1, getn(list) - 4), -1 do
				local x = list[i]
				tinsert(rows, R(nameC(x[1]), floor(x[2]) .. " DPS"))
			end
			return rows
		end)
	end

	if rec.wipeT then
		local sum, n = 0, 0
		for name, p in pairs(players) do
			if p._role == "heal" and p.mana and not (p.deadAt and (p.deadAt - F.t0) < wipeT) then
				local v = manaAt(p.mana, wipeT)
				if v then sum = sum + v; n = n + 1 end
			end
		end
		if n > 0 then
			rec.healMana = sum / n
			if rec.healMana < 0.15 then
				cause(60, "Healers were out of mana (" .. floor(rec.healMana * 100) .. "% average when the wipe started)", nil, function()
					local rows = {
						H("Healer mana"),
						R("Average mana of living healers when the wipe started", manaCol(rec.healMana)),
						R("|cffaaaaaaMana potions and runes are on a 2 minute cooldown - a " .. FmtTime(dur) .. " fight allows about " .. (floor(dur / 120) + 1) .. " of each per healer.|r"),
					}
					healerRows(rows, wipeT, "Healers when the wipe started (" .. FmtTime(wipeT) .. ")")
					return rows
				end)
			end
		end
	end

	------------------------------------------------ heroes (game-saving moments)
	rec.saves, rec.heroes = {}, {}
	local hero = {}
	local function survived(name, t, win)
		for i = 1, getn(rec.deaths) do
			local d = rec.deaths[i]
			if d.name == name and d.t > t and d.t <= t + win then return false end
		end
		return true
	end
	local function hsave(t, who, pts, text, tip)
		if not who or not players[who] then return end
		tinsert(rec.saves, { t = t, who = who, pts = pts, text = text, tip = tip })
		local h = hero[who]
		if not h then h = { pts = 0, list = {} }; hero[who] = h end
		h.pts = h.pts + pts
		tinsert(h.list, text)
	end

	for i = 1, getn(F.saves or {}) do
		local s = F.saves[i]
		local k = s.kind
		if k == "heal" and survived(s.target, s.t, 8) then
			hsave(s.t, s.who, 2, s.who .. " healed " .. s.target .. " from " .. pctS(s.pre) .. " health with " .. s.sp .. " (+" .. FmtNum(s.amt) .. ")",
				{ s.target .. " was about to die - the heal landed and they survived." })
		elseif k == "shield" and survived(s.target, s.t, 5) then
			hsave(s.t, s.who, 3, s.who .. "'s " .. s.sp .. " absorbed a killing blow on " .. s.target .. " (" .. FmtNum(s.amt) .. " absorbed)",
				{ "Without the shield that hit would have killed " .. s.target .. "." })
		elseif k == "cooldown" and survived(s.target, s.t, 8) then
			hsave(s.t, s.who, 3, s.who .. " used " .. s.sp .. " on " .. s.target .. " at " .. pctS(s.pre) .. " health",
				{ s.target .. " survived thanks to it." })
		elseif k == "rez" then
			hsave(s.t, s.who, 3, s.who .. " battle-rezzed " .. s.target .. " with " .. s.sp, { "Got a dead raider back into the fight." })
		elseif k == "innervate" then
			hsave(s.t, s.who, 1.5, s.who .. " innervated " .. s.target .. " at " .. pctS(s.pre) .. " mana", { "Kept a healer going." })
		elseif k == "freed" then
			hsave(s.t, s.who, 2, s.who .. " dispelled " .. s.sp .. " from " .. s.target, { "Freed a mind-controlled raider before they could do more damage." })
		elseif (k == "self" or k == "potion") and survived(s.target, s.t, 8) then
			hsave(s.t, s.who, 1, s.who .. " survived on " .. pctS(s.pre) .. " health with " .. s.sp, { "Saved themselves with a last-second " .. (k == "potion" and "consumable" or "cooldown") .. "." })
		end
	end

	-- tanks taking the boss back off someone who pulled it (and who then lived)
	for i = 1, getn(F.aggro) do
		local a = F.aggro[i]
		local tp, fp = players[a.to], a.from and players[a.from]
		if tp and fp and tp._role == "tank" and fp._role ~= "tank" and not a.oldDead and survived(a.from, a.t, 5) then
			local taunted = false
			for j = 1, getn(F.tauntCasts or {}) do
				local tc = F.tauntCasts[j]
				if tc.who == a.to and tc.t <= a.t + 0.5 and tc.t >= a.t - 3 then taunted = true end
			end
			if taunted then
				hsave(a.t, a.to, 3, a.to .. " taunted " .. a.boss .. " off " .. a.from, { a.from .. " had the boss and survived because of the taunt." })
			else
				hsave(a.t, a.to, 1.5, a.to .. " pulled " .. a.boss .. " back off " .. a.from, { a.from .. " had the boss and survived." })
			end
		end
	end

	for sp, st in pairs(F.interrupts) do
		for name, c in pairs(st.by) do
			hsave(nil, name, math.min(3, 0.5 * c), name .. " interrupted " .. sp .. " " .. c .. "x", { "Stopped a dangerous cast." })
		end
	end

	for i = 1, getn(F.frenzies) do
		local fz = F.frenzies[i]
		if fz.by and fz.dur <= 3 then
			hsave(fz.t, fz.by, 1, fz.by .. " tranquilized " .. fz.boss .. "'s Frenzy in " .. string.format("%.1f", fz.dur) .. "s", { "Removed the Frenzy before it hurt the tanks." })
		end
	end

	table.sort(rec.saves, function(a, b) return (a.t or 9999) < (b.t or 9999) end)
	for name, h in pairs(hero) do
		tinsert(rec.heroes, { name = name, class = players[name].class, pts = round1(h.pts), list = h.list })
	end
	table.sort(rec.heroes, function(a, b) return a.pts > b.pts end)

	------------------------------------------------ wipe causes
	if rec.result ~= "KILL" then
		for i = 1, getn(tankDeaths) do
			local td = tankDeaths[i]
			cause(i == 1 and 80 or 60, "Tank " .. td.d.name .. " died at " .. FmtTime(td.d.t) .. " - " .. string.gsub(td.text, "^Tank died %- ", ""), nil, function()
				local rows = {}
				deathRows(rows, td.ri)
				healerRows(rows, td.d.t, "Healers at " .. FmtTime(td.d.t) .. " (where were the heals?)")
				return rows
			end)
		end
		for sp, list in pairs(mechDeaths) do
			local msp, ml = sp, list
			cause(25 * getn(list), getn(list) .. " died to " .. sp .. ": " .. names(list), nil, function()
				local rule = A.AvoidRule(msp, "dps")
				local rows = { H("Deaths to " .. msp) }
				if rule then tinsert(rows, R("|cffaaaaaa" .. rule.tip .. "|r")) end
				for i = 1, getn(ml) do
					tinsert(rows, deathLink(ml[i].ri))
					local a = F.avoid[ml[i].name] and F.avoid[ml[i].name][msp]
					if a then
						tinsert(rows, R("      |cffaaaaaahit " .. a.hits .. "x for " .. FmtNum(a.dmg) .. " this fight, " .. a.inst .. " separate time(s)|r"))
					end
				end
				return rows
			end)
		end
		if getn(aggroDeaths) > 0 then
			cause(35 * getn(aggroDeaths), "Pulled aggro and died: " .. names(aggroDeaths), nil, function()
				local rows = {}
				for i = 1, getn(aggroDeaths) do
					local who = aggroDeaths[i].name
					tinsert(rows, H(who))
					for j = 1, getn(F.aggro) do
						local a = F.aggro[j]
						if a.to == who then
							tinsert(rows, R(FmtTime(a.t) .. "  took aggro" .. (a.from and (" from " .. nameC(a.from)) or ""),
								a.perc and (a.perc .. "% threat") or "|cff888888no threat reading|r"))
						end
					end
					local pk = F.threatPeak[who]
					if pk then tinsert(rows, R("Peak threat this fight", pk.perc .. "% at " .. FmtTime(pk.t))) end
					tinsert(rows, deathLink(aggroDeaths[i].ri))
				end
				return rows
			end)
		end
		if getn(healDeaths) > 0 then
			cause(20 * getn(healDeaths), "Healer(s) died early: " .. names(healDeaths), nil, function()
				local rows = { H("Healer deaths") }
				local last = 0
				for i = 1, getn(healDeaths) do
					tinsert(rows, deathLink(healDeaths[i].ri))
					last = math.max(last, rec.deaths[healDeaths[i].ri].t)
				end
				healerRows(rows, last, "Healers after the last healer death (" .. FmtTime(last) .. ")")
				return rows
			end)
		end
		if deaths[1] then
			local d1 = rec.deaths[1]
			cause(8, "First death: " .. d1.name .. " at " .. FmtTime(d1.t) .. " - " .. d1.text, nil, function()
				local rows = {}
				deathRows(rows, 1)
				return rows
			end)
		end
	end
	table.sort(rec.causes, function(a, b) return a.s > b.s end)
	-- build the click-through details now that everything is known (plain
	-- tables only - functions can't go into SavedVariables)
	for i = 1, getn(rec.causes) do
		local c = rec.causes[i]
		if c.fn then
			c.detail = c.fn()
			c.fn = nil
		end
	end

	------------------------------------------------ raid notes
	if F.buffsOk then
		local classes = {}
		for _, p in pairs(players) do classes[p.class] = true end
		for i = 1, getn(D.buffGroups) do
			local g = D.buffGroups[i]
			if classes[g.from] then
				local miss = {}
				for name, set in pairs(F.buffs) do
					local p = players[name]
					if p and p._part and (not g.mana or D.manaClasses[p.class]) then
						local has = false
						for j = 1, getn(g.names) do if set[g.names[j]] then has = true end end
						if not has then tinsert(miss, name) end
					end
				end
				if getn(miss) > 0 then
					tinsert(rec.notes, { text = "Missing " .. g.label .. " at pull: " .. getn(miss) .. " player(s)", tip = miss })
				end
			end
		end
		local noFlask = {}
		for name, set in pairs(F.buffs) do
			local p = players[name]
			if p and p._part then
				local has = false
				for b in pairs(set) do if D.flasks[b] then has = true end end
				if not has then tinsert(noFlask, name) end
			end
		end
		if getn(noFlask) > 0 then
			tinsert(rec.notes, { text = "No flask at pull: " .. getn(noFlask) .. " player(s)", tip = noFlask })
		end
	end

	local mainName = F.mainBoss and F.bosses[F.mainBoss] and F.bosses[F.mainBoss].name or "boss"
	local up = {}
	for sp, u in pairs(F.bossDebuffs) do
		local tot = u.total + (u.since and (now - u.since) or 0)
		tinsert(up, { sp, tot / dur })
	end
	table.sort(up, function(a, b) return a[2] > b[2] end)
	for i = 1, getn(up) do
		tinsert(rec.notes, { text = up[i][1] .. " uptime on " .. mainName .. ": " .. floor(math.min(1, up[i][2]) * 100) .. "%" })
	end

	local idle = {}
	for name, p in pairs(players) do
		if not p._part then tinsert(idle, name) end
	end
	if getn(idle) > 0 then
		tinsert(rec.notes, { text = "Not engaged at all: " .. getn(idle) .. " player(s)", tip = idle })
	end

	------------------------------------------------ verdict
	local nd = getn(rec.deaths)
	if rec.result == "KILL" then
		rec.verdict = (nd == 0) and "Clean kill - nobody died!" or ("Killed with " .. nd .. " death(s)")
	elseif rec.result == "LIVE" then
		rec.verdict = "In progress - " .. nd .. " death(s) so far"
	elseif rec.causes[1] then
		rec.verdict = rec.causes[1].text
	else
		rec.verdict = "No single cause found - check the Deaths tab"
	end

	------------------------------------------------ blame board
	for name, b in pairs(blame) do
		local p = players[name]
		tinsert(rec.blame, { name = name, class = p and p.class or "WARRIOR", pts = round1(b.pts), reasons = b.reasons })
	end
	table.sort(rec.blame, function(a, b) return a.pts > b.pts end)
	if rec.blame[1] and rec.blame[1].pts >= 3 then rec.culprit = rec.blame[1].name end

	table.sort(rec.findings, function(a, b)
		if a.pts ~= b.pts then return a.pts > b.pts end
		return (a.t or 9999) < (b.t or 9999)
	end)

	------------------------------------------------ per player summary
	for name, p in pairs(players) do
		if p._part then
			local pk = F.threatPeak[name]
			local deathsN = 0
			for i = 1, getn(rec.deaths) do if rec.deaths[i].name == name then deathsN = deathsN + 1 end end
			local tl = tally[name] or {}
			rec.players[name] = {
				avoidDmg = tl.avoidDmg or 0, avoidHits = tl.avoidHits or 0,
				worstSpell = tl.worstSpell, worstHits = tl.worstHits,
				pulls = tl.pulls or 0, splash = tl.splash or 0,
				blame = blame[name] and round1(blame[name].pts) or 0,
				class = p.class, role = p._role, dmg = p.dmg, boss = p.bossDmg, heal = p.heal, taken = p.taken,
				alive = p._alive, act = p._act, deaths = deathsN,
				kicks = p.kicks, dispels = p.dispels, tranqs = p.tranqs,
				cons = p.nCons, consList = topList(p.consumes, 10),
				cbuffs = buffList(p), used = usedList(p),
				hero = hero[name] and round1(hero[name].pts) or 0,
				saves = hero[name] and getn(hero[name].list) or 0,
				ds = topList(p.ds, 8), hs = topList(p.hs, 8), ts = topList(p.ts, 8),
				aggro = p.aggroTime, swings = p.bossSwings, crush = p.crush,
				threat = pk and pk.perc,
			}
		end
	end

	return rec
end

------------------------------------------------------------------ chat report

function A:ReportLines(rec, n)
	local out = {}
	-- long lines are split into several messages (with colours) when sent
	local function add(s) tinsert(out, s) end
	add(A.ChatHeader("REPORT", rec))
	add("Verdict: " .. (rec.verdict or ""))
	local c = 0
	for i = 2, getn(rec.causes) do
		if c >= 2 then break end
		add("Also: " .. rec.causes[i].text)
		c = c + 1
	end
	local parts = {}
	for i = 1, math.min(n or 3, getn(rec.blame)) do
		local b = rec.blame[i]
		if b.pts >= 1 then
			local why = b.reasons[1] or ""
			why = string.gsub(why, "^" .. b.name .. " ", "")
			tinsert(parts, i .. ". " .. b.name .. " " .. b.pts .. "pt (" .. why .. ")")
		end
	end
	if getn(parts) > 0 then add("Blame: " .. table.concat(parts, "; ")) end
	local h = rec.heroes and rec.heroes[1]
	if h and h.pts >= 2 then
		add("Hero: " .. h.name .. " " .. h.pts .. "pt (" .. (string.gsub(h.list[1] or "", "^" .. h.name .. " ", "")) .. ")")
	end
	return out
end

-- first line of every chat post: [WhoDidIt] KIND - Boss RESULT (m:ss)
function A.ChatHeader(kind, rec)
	return (rec.demo and "[WhoDidIt DEMO] " or "[WhoDidIt] ") .. kind .. " - " .. rec.enc .. " " .. rec.result .. " (" .. FmtTime(rec.dur) .. ")"
end
