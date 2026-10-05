--[[--------------------------------------------------------------------
	WhoDidIt - tracker: turns Nampower / SuperWoW / threat events into a
	live fight record (W.Tracker.fight). The Analyzer reads it.
----------------------------------------------------------------------]]

local W = WhoDidIt
local T = {}
W.Tracker = T

local floor = math.floor
local getn = table.getn

local RECAP_SIZE    = 30    -- events remembered per player
local RECAP_WINDOW  = 15    -- seconds of history kept for a death recap
local AGGRO_CONFIRM = 2.0   -- boss must hold a (non-melee) target this long
local TIMELINE_CAP  = 400

local HIT_CRIT     = 128     -- 0x80
local HIT_CRUSHING = 32768   -- 0x8000

local ENV = {
	[0] = "Fatigue", [1] = "Drowning", [2] = "Falling", [3] = "Lava",
	[4] = "Slime", [5] = "Burning ground", [6] = "Fell off the edge",
}

local F              -- the live fight, same table as T.fight
local isBoss = {}    -- guid -> bool

local function hasFlag(v, flag)
	if not v or not bit or not bit.band then return false end
	return bit.band(v, flag) ~= 0
end

------------------------------------------------------------------ helpers

function T:Line(kind, text, who)
	if not F or getn(F.timeline) >= TIMELINE_CAP then return nil end
	local l = { t = GetTime() - F.t0, k = kind, x = text, w = who }
	tinsert(F.timeline, l)
	return l
end

function T.IsBoss(guid)
	if not guid then return false end
	local c = isBoss[guid]
	if c ~= nil then return c end
	if W.roster.byGuid[guid] or W.roster.pets[guid] then
		isBoss[guid] = false
		return false
	end
	local name = UnitName(guid)
	if not name or name == "" or name == UNKNOWNOBJECT then return false end
	local b = false
	if UnitCanAttack("player", guid) then
		local cls = UnitClassification(guid)
		if W.Data.bosses[name] or cls == "worldboss" then
			b = true
		elseif WhoDidItDB.opts.trackTrash and (cls == "elite" or cls == "rareelite") then
			b = true
		end
	end
	isBoss[guid] = b
	return b
end

-- empty player / fight records (also used by the demo)
function T.NewPlayer(name, class)
	return {
		name = name, class = class or "WARRIOR",
		dmg = 0, bossDmg = 0, heal = 0, taken = 0,
		ds = {}, hs = {}, ts = {},
		act = {}, nAct = 0,
		deadTotal = 0, aggroTime = 0, bossSwings = 0, crush = 0,
		consumes = {}, nCons = 0, kicks = 0, dispels = 0, tranqs = 0,
		cbuffs = {},  -- consumable buff name -> fight time first seen (0 = before the pull)
		recap = {}, rhead = 0,
	}
end

function T.NewFight(t0, enc)
	return {
		t0 = t0, date = date("%Y-%m-%d %H:%M"), zone = GetRealZoneText(),
		enc = enc,
		bosses = {}, nBoss = 0,
		players = {}, deaths = {}, timeline = {}, aggro = {},
		avoid = {}, carry = {}, stacks = {},
		interrupts = {}, casting = {}, lastKick = {},
		dispelTimes = {}, activeDebuffs = {}, mc = {},
		frenzyOn = {}, frenzies = {}, bossDebuffs = {}, raidFails = {},
		threat = {}, threatPeak = {}, ffire = {}, taunts = {}, castLines = {},
		buffs = {},
		saves = {}, shields = {}, tauntCasts = {},
		env = {
			nampower = W.env.nampower, superwow = W.env.superwow,
			threat = W.env.twthreat or WhoDidItDB.opts.queryThreat,
		},
	}
end

function T:P(name)
	local p = F.players[name]
	if p then return p end
	local e = W.roster.byName[name]
	p = T.NewPlayer(name, e and e.class)
	F.players[name] = p
	return p
end

-- mark a player as "doing something" for every second in [t1, t2]
local function mark(p, t1, t2)
	local a = floor(t1 - F.t0)
	local b = floor((t2 or t1) - F.t0)
	if b > a + 10 then b = a + 10 end
	for s = a, b do
		if not p.act[s] then
			p.act[s] = true
			p.nAct = p.nAct + 1
		end
	end
end

-- death recap ring buffer
local function push(p, kind, src, spell, amt, crit, extra)
	local h = p.rhead + 1
	if h > RECAP_SIZE then h = 1 end
	p.rhead = h
	local r = p.recap[h]
	if not r then r = {}; p.recap[h] = r end
	r.t = GetTime(); r.k = kind; r.src = src; r.sp = spell; r.a = amt; r.c = crit; r.x = extra
	local e = W.roster.byName[p.name]
	if e then
		r.hp = UnitHealth(e.unit)
		r.hpm = UnitHealthMax(e.unit)
		if r.hpm and r.hpm > 0 then p.hpFrac = r.hp / r.hpm end
	else
		r.hp = nil; r.hpm = nil
	end
end

------------------------------------------------------------------ fight lifecycle

function T:AddBoss(guid)
	if F.bosses[guid] then return end
	local name = W.GuidName(guid)
	F.bosses[guid] = { name = name, dead = false }
	F.nBoss = F.nBoss + 1
	if not F.mainBoss then F.mainBoss = guid end
	local enc = W.Data.bosses[name]
	if enc and not F.encKnown then
		F.enc = enc
		F.encKnown = true
		F.encDef = W.Data.encounters[enc]
	end
	if F.started then T:Line("boss", name .. " joins the fight") end
end

function T:Start(guid, puller, how)
	F = T.NewFight(GetTime(), W.GuidName(guid))
	F.puller = puller
	F.pullHow = how
	T.fight = F
	T:AddBoss(guid)
	for name in pairs(W.roster.byName) do T:P(name) end
	F.started = true
	T:SnapshotBuffs()
	local bname = W.GuidName(guid)
	if puller then
		T:Line("pull", how == "aggro" and (bname .. " attacked " .. puller) or (puller .. " pulled " .. bname), puller)
	else
		T:Line("pull", bname .. " engaged")
	end
	if F.encKnown or UnitClassification(guid) == "worldboss" then
		W.Print("Tracking |cffffd100" .. F.enc .. "|r.")
	end
	W.Logs:OnFightStart()
	if W.UI then W.UI:OnFightStart() end
end

function T:Finish(result)
	if not F then return end
	local now = GetTime()
	F.tEnd = F.killedAt or F.idleSince or now
	for _, b in pairs(F.bosses) do T:Accrue(b, now) end
	F.result = result
	T:Line(result == "KILL" and "kill" or "wipe", result == "KILL" and "Encounter won" or (result == "WIPE" and "Wipe" or "Fight reset"))
	local fight = F
	F = nil
	T.fight = nil
	isBoss = {}
	W.ResetCaches()
	local dur = fight.tEnd - fight.t0
	if result ~= "KILL" and dur < (WhoDidItDB.opts.minDuration or 8) then
		if W.UI then W.UI:OnFightEnd() end
		return
	end
	W:SaveFight(W.Analyzer:Build(fight, true))
end

function T:CheckKill()
	local def = F.encDef
	if def and def.final then
		for _, b in pairs(F.bosses) do
			if b.name == def.final and b.dead then F.killedAt = GetTime() end
		end
		return
	end
	for _, b in pairs(F.bosses) do
		if not b.dead then return end
	end
	F.killedAt = GetTime()
end

function T:CheckEnd()
	local now = GetTime()
	if F.killedAt then
		if now - F.killedAt > 1.5 then T:Finish("KILL") end
		return
	end
	local anyCombat, dead, total = false, 0, 0
	for _, e in pairs(W.roster.byName) do
		total = total + 1
		if UnitIsDeadOrGhost(e.unit) then
			dead = dead + 1
		elseif UnitAffectingCombat(e.unit) then
			anyCombat = true
		end
	end
	if anyCombat then
		F.idleSince = nil
		return
	end
	F.idleSince = F.idleSince or now
	local def = F.encDef
	local wiped = total > 0 and dead / total >= 0.5
	-- some encounters drop combat between phases (Thaddius, C'Thun)
	local grace = (not wiped and def and def.idleGrace) or 3
	if now - F.idleSince < grace then return end
	if wiped then
		T:Finish("WIPE")
	elseif def and def.noDeath then
		T:Finish("KILL")
	else
		T:Finish("RESET")
	end
end

function T:ManualStart()
	if F then W.Print("Already tracking " .. F.enc .. ".") return end
	local g = W.Guid("target")
	if not g or not UnitCanAttack("player", "target") then
		W.Print("Target a hostile unit first (needs SuperWoW).")
		return
	end
	isBoss[g] = true
	T:Start(g, UnitName("player"), "manual")
end

function T:ManualStop()
	if not F then W.Print("Not tracking anything.") return end
	F.idleSince = GetTime()
	T:Finish("RESET")
end

------------------------------------------------------------------ pull buff snapshot

function T:SnapshotBuffs()
	F.buffs = {}
	for name, e in pairs(W.roster.byName) do
		local set = {}
		if GetUnitData and e.guid then
			local ok, ud = pcall(GetUnitData, e.guid)
			if ok and type(ud) == "table" and type(ud.aura) == "table" then
				for i = 1, 32 do
					local id = ud.aura[i]
					if id and id > 0 then
						set[W.SpellName(id)] = true
						F.buffsOk = true
					end
				end
			end
		elseif W.env.superwow then
			for i = 1, 32 do
				local tex, _, id = UnitBuff(e.unit, i)
				if not tex then break end
				if id then
					set[W.SpellName(id)] = true
					F.buffsOk = true
				end
			end
		end
		F.buffs[name] = set
		local p = T:P(name)
		for b in pairs(set) do
			if W.Data.consumeBuffs[b] then p.cbuffs[b] = 0 end
		end
	end
end

-- a raid member gained a buff: remember consumables (protection potions etc.)
function T:RaidBuff(guid, spellId)
	local e = W.roster.byGuid[guid]
	if not e then return end
	local sp = W.SpellName(spellId)
	if not W.Data.consumeBuffs[sp] then return end
	local p = T:P(e.name)
	if not p.cbuffs[sp] then
		p.cbuffs[sp] = GetTime() - F.t0
		push(p, "buff", nil, sp)
	end
end

------------------------------------------------------------------ damage / healing

function T:Damage(src, dst, spell, amt, crit, swing, hitInfo, absorb)
	if not src or not dst then return end
	local srcN, srcPet = W.Owner(src)
	local dstN, dstPet = W.Owner(dst)
	if not F then
		if srcN and not dstN and T.IsBoss(dst) then
			T:Start(dst, srcN, "hit")
		elseif dstN and not srcN and not dstPet and T.IsBoss(src) then
			T:Start(src, dstN, "aggro")
		else
			return
		end
	end
	local now = GetTime()

	-- raid -> enemy
	if srcN and not dstN then
		if not F.bosses[dst] and T.IsBoss(dst) then T:AddBoss(dst) end
		local p = T:P(srcN)
		p.dmg = p.dmg + amt
		local key = srcPet and ("Pet: " .. spell) or spell
		p.ds[key] = (p.ds[key] or 0) + amt
		if F.bosses[dst] then p.bossDmg = p.bossDmg + amt end
		if not srcPet then mark(p, now, swing and (now + 1.5) or now) end
		return
	end

	if not dstN or dstPet then return end
	local p = T:P(dstN)

	-- raid -> raid (mind control, friendly fire)
	if srcN then
		if amt <= 0 then return end
		p.taken = p.taken + amt
		local mc = F.mc[src]
		push(p, "dmg", mc and (srcN .. " (mind controlled)") or srcN, spell, amt, crit)
		if not mc and not F.mc[dst] and srcN ~= dstN then
			F.ffire[srcN] = (F.ffire[srcN] or 0) + amt
		end
		return
	end

	-- enemy -> raid
	if not F.bosses[src] and T.IsBoss(src) then T:AddBoss(src) end
	local crushing = swing and hasFlag(hitInfo, HIT_CRUSHING)
	if swing and F.bosses[src] then
		T:BossSwing(src, dst, p, now)
		if crushing then p.crush = p.crush + 1 end
	end
	if absorb and absorb > 0 then T:CheckShield(dst, p, absorb) end
	if amt <= 0 then return end
	p.taken = p.taken + amt
	p.ts[spell] = (p.ts[spell] or 0) + amt
	push(p, swing and "melee" or "dmg", W.GuidName(src), spell, amt, crit, crushing and "crushing" or nil)
	if not swing then
		T:CheckAvoid(p, spell, amt, now)
		T:CheckSplash(p, spell, amt, now)
	end
end

function T:Env(guid, typ, dmg)
	if not F then return end
	local e = W.roster.byGuid[guid]
	if not e then return end
	local p = T:P(e.name)
	local sp = ENV[tonumber(typ) or -1] or "Environment"
	dmg = tonumber(dmg) or 0
	p.taken = p.taken + dmg
	p.ts[sp] = (p.ts[sp] or 0) + dmg
	push(p, "env", "Environment", sp, dmg)
	T:CheckAvoid(p, sp, dmg, GetTime())
end

function T:Heal(targetGuid, casterGuid, spellId, amount, crit, periodic)
	if not F then return end
	amount = tonumber(amount) or 0
	local now = GetTime()
	local sp = W.SpellName(spellId)
	local cn, cpet = W.Owner(casterGuid)
	if cn then
		local p = T:P(cn)
		p.heal = p.heal + amount
		p.hs[sp] = (p.hs[sp] or 0) + amount
		if not cpet and tonumber(periodic) ~= 1 then mark(p, now) end
	end
	local te = W.roster.byGuid[targetGuid]
	if te then
		local q = T:P(te.name)
		-- clutch heal: target was under 20% (last known health) and it was a real heal
		local pre = q.hpFrac
		local mx = UnitHealthMax(te.unit) or 0
		if cn and pre and pre < 0.2 and mx > 0 and amount >= mx * 0.1 and not UnitIsDeadOrGhost(te.unit) then
			T:Save("heal", cn, te.name, sp, amount, pre)
		end
		push(q, "heal", cn or W.GuidName(casterGuid), sp, amount, tonumber(crit) == 1)
	end
end

------------------------------------------------------------------ heroes

-- a possible game-saving moment; the Analyzer confirms it (e.g. they survived)
function T:Save(kind, who, target, sp, amt, pre)
	local now = GetTime() - F.t0
	if kind == "heal" then
		-- one clutch heal per target per 3s (the first one that landed)
		for i = getn(F.saves), 1, -1 do
			local s = F.saves[i]
			if now - s.t > 3 then break end
			if s.kind == "heal" and s.target == target then return end
		end
	end
	tinsert(F.saves, { t = now, kind = kind, who = who, target = target, sp = sp, amt = amt, pre = pre })
end

local function liveFrac(unit, mana)
	if mana then
		local mx = UnitManaMax(unit) or 0
		return mx > 0 and (UnitMana(unit) / mx) or nil
	end
	local mx = UnitHealthMax(unit) or 0
	return mx > 0 and (UnitHealth(unit) / mx) or nil
end

-- an absorb shield took a hit bigger than the health its target had left
function T:CheckShield(guid, p, absorb)
	local sh = F.shields[guid]
	if not sh or sh.saved or GetTime() - sh.t > 30 then return end
	local e = W.roster.byGuid[guid]
	if not e then return end
	local hp = UnitHealth(e.unit) or 0
	if hp > 0 and hp <= absorb then
		sh.saved = true
		T:Save(sh.by == p.name and "self" or "shield", sh.by, p.name, sh.sp, absorb, p.hpFrac)
	end
end

------------------------------------------------------------------ mechanics

function T:CheckAvoid(p, spell, amt, now)
	local rule = W.Data.avoid[spell]
	if not rule and WhoDidItDB.avoid[spell] then rule = W.Data.customRule end
	if not rule then return end
	local a = F.avoid[p.name]
	if not a then a = {}; F.avoid[p.name] = a end
	local r = a[spell]
	if not r then
		r = { hits = 0, dmg = 0, inst = 0, last = -999, first = now - F.t0 }
		a[spell] = r
	end
	r.hits = r.hits + 1
	r.dmg = r.dmg + amt
	if now - r.last > 4 then
		r.inst = r.inst + 1
		if r.inst <= 3 then
			T:Line("avoid", p.name .. " hit by " .. spell .. " (" .. W.FmtNum(amt) .. ")", p.name)
		end
	end
	r.last = now
end

function T:CheckSplash(p, spell, amt, now)
	local srcs = W.Data.splashIdx[spell]
	if not srcs then return end
	for i = 1, getn(srcs) do
		local list = F.carry[srcs[i]]
		if list then
			for j = getn(list), 1, -1 do
				local c = list[j]
				if now - c.t <= c.win + 1 then
					if c.name ~= p.name then
						c.hits = c.hits + 1
						if not c.victims[p.name] then
							c.victims[p.name] = 0
							c.nv = c.nv + 1
						end
						c.victims[p.name] = c.victims[p.name] + amt
					end
					return
				end
			end
		end
	end
end

function T:Debuff(guid, spellId, stacks)
	if not F then return end
	local now = GetTime()
	local sp = W.SpellName(spellId)
	local D = W.Data
	stacks = tonumber(stacks)

	if F.bosses[guid] then
		if guid == F.mainBoss and D.raidDebuffs[sp] then
			local u = F.bossDebuffs[sp]
			if not u then u = { total = 0, max = 0 }; F.bossDebuffs[sp] = u end
			if not u.since then u.since = now end
			if stacks and stacks > u.max then u.max = stacks end
		end
		return
	end

	local e = W.roster.byGuid[guid]
	if not e or D.ignoreDebuffs[sp] then return end
	local p = T:P(e.name)
	local ad = F.activeDebuffs[guid]
	if not ad then ad = {}; F.activeDebuffs[guid] = ad end
	if not ad[sp] then
		ad[sp] = now
		push(p, "debuff", nil, sp, stacks)
		if D.mc[sp] then
			F.mc[guid] = now
			T:Line("mc", e.name .. " is mind controlled (" .. sp .. ")", e.name)
		end
		local cr = D.carriers[sp]
		if cr then
			local list = F.carry[sp]
			if not list then list = {}; F.carry[sp] = list end
			tinsert(list, { name = e.name, t = now, win = cr.win or 10, hits = 0, victims = {}, nv = 0 })
			T:Line("debuff", e.name .. " has " .. sp, e.name)
		end
	end
	if stacks and D.stacks[sp] then
		local s = F.stacks[e.name]
		if not s then s = {}; F.stacks[e.name] = s end
		if stacks > (s[sp] or 0) then s[sp] = stacks end
	end
end

function T:DebuffRemoved(guid, spellId, state)
	if not F or tonumber(state) ~= 1 then return end
	local now = GetTime()
	local sp = W.SpellName(spellId)

	if F.bosses[guid] then
		local u = F.bossDebuffs[sp]
		if u and u.since and guid == F.mainBoss then
			u.total = u.total + (now - u.since)
			u.since = nil
		end
		return
	end

	local ad = F.activeDebuffs[guid]
	if not ad or not ad[sp] then return end
	local t0 = ad[sp]
	ad[sp] = nil
	if W.Data.mc[sp] then F.mc[guid] = nil end
	local e = W.roster.byGuid[guid]
	if W.Data.dispel[sp] and e and not UnitIsDeadOrGhost(e.unit) then
		local d = F.dispelTimes[sp]
		if not d then d = { n = 0, total = 0, max = 0 }; F.dispelTimes[sp] = d end
		local dt = now - t0
		d.n = d.n + 1
		d.total = d.total + dt
		if dt > d.max then d.max = dt; d.maxWho = e.name end
	end
end

function T:BossBuff(guid, spellId, added)
	if not F then return end
	local b = F.bosses[guid]
	if not b then return end
	local sp = W.SpellName(spellId)
	local now = GetTime()
	if W.Data.frenzy[sp] then
		if added then
			if not F.frenzyOn[guid] then
				F.frenzyOn[guid] = now
				T:Line("boss", b.name .. " gains " .. sp)
			end
		elseif F.frenzyOn[guid] then
			local st = F.frenzyOn[guid]
			F.frenzyOn[guid] = nil
			local lt = F.lastTranq
			local by = lt and (now - lt.t) < 2 and lt.name or nil
			tinsert(F.frenzies, { t = st - F.t0, dur = now - st, by = by, boss = b.name })
			T:Line("tranq", by and (by .. " tranquilized " .. b.name) or (sp .. " faded from " .. b.name), by)
		end
	elseif added and W.Data.berserk[sp] then
		local mx = UnitHealthMax(guid) or 0
		local pct = mx > 0 and ((UnitHealth(guid) or 0) / mx) or 1
		if pct > 0.25 then
			if not F.enraged then
				F.enraged = now - F.t0
				F.enrageBoss = b.name
			end
			T:Line("enrage", b.name .. " goes " .. sp .. " at " .. floor(pct * 100) .. "% health")
		else
			T:Line("boss", b.name .. " goes " .. sp .. " (low health)")
		end
	end
end

------------------------------------------------------------------ deaths

function T:Died(guid)
	if not F then return end
	local b = F.bosses[guid]
	if b then
		if not b.dead then
			b.dead = true
			b.diedAt = GetTime() - F.t0
			T:Line("kill", b.name .. " dies")
			T:CheckKill()
		end
		return
	end
	local e = W.roster.byGuid[guid]
	if e then T:Death(e, guid) end
end

function T:Death(e, guid)
	local p = T:P(e.name)
	if p.deadAt then return end
	local now = GetTime()
	p.deadAt = now
	local d = {
		name = e.name, class = e.class, t = now - F.t0, at = now,
		lines = {}, debuffs = {}, verify = now + 1.5,
	}
	local h = p.rhead
	for i = 0, RECAP_SIZE - 1 do
		local idx = h - i
		if idx < 1 then idx = idx + RECAP_SIZE end
		local r = p.recap[idx]
		if not r or not r.t or now - r.t > RECAP_WINDOW or r.t < F.t0 or r.t <= (p.lastDeathAt or 0) then break end
		tinsert(d.lines, 1, {
			t = r.t - F.t0, k = r.k, s = r.src, sp = r.sp, a = r.a, c = r.c,
			hp = r.hp, hm = r.hpm, x = r.x,
		})
	end
	p.lastDeathAt = now
	local ad = guid and F.activeDebuffs[guid]
	if ad then
		for sp in pairs(ad) do tinsert(d.debuffs, sp) end
	end
	d.cons = p.nCons
	for _, b in pairs(F.bosses) do
		if guid and b.holder == guid then d.hadAggro = b.name end
	end
	tinsert(F.deaths, d)
	d.line = T:Line("death", e.name .. " died", e.name)
end

-- feign death check + resurrections
function T:CheckLiving()
	local now = GetTime()
	for i = 1, getn(F.deaths) do
		local d = F.deaths[i]
		if d.verify and now >= d.verify then
			d.verify = nil
			local e = W.roster.byName[d.name]
			if e and UnitHealth(e.unit) > 0 and not UnitIsGhost(e.unit) then
				d.fd = true
				local p = F.players[d.name]
				if p then p.deadAt = nil end
				if d.line then d.line.k = "info"; d.line.x = d.name .. " feigned death" end
			end
		end
	end
	for name, p in pairs(F.players) do
		if p.deadAt and now - p.deadAt > 3 then
			local e = W.roster.byName[name]
			if e and not UnitIsDeadOrGhost(e.unit) and UnitHealth(e.unit) > 0 then
				p.deadTotal = p.deadTotal + (now - p.deadAt)
				p.deadAt = nil
				T:Line("info", name .. " is back up", name)
			end
		end
	end
end

------------------------------------------------------------------ aggro

function T:Accrue(b, now)
	if b.holder and b.lastAcc then
		local e = W.roster.byGuid[b.holder]
		if e then
			local p = F.players[e.name]
			if p then p.aggroTime = p.aggroTime + (now - b.lastAcc) end
		end
	end
	b.lastAcc = now
end

function T:AggroChange(bguid, b, g, now, how)
	T:Accrue(b, now)
	local old = b.holder
	b.holder = g
	b.cand = g
	b.candSince = now
	local e = W.roster.byGuid[g]
	if not e then return end
	local oe = old and W.roster.byGuid[old]
	local th = F.threat[e.name]
	local perc = th and (now - th.t) < 5 and th.perc or nil
	local op = oe and F.players[oe.name]
	local oldDead = op and op.deadAt and (now - op.deadAt) < 8
	tinsert(F.aggro, {
		t = now - F.t0, boss = b.name, to = e.name, class = e.class,
		from = oe and oe.name, perc = perc, how = how, oldDead = oldDead and true or nil,
	})
	if not F.firstHolder then F.firstHolder = e.name end
	T:Line("aggro", b.name .. " -> " .. e.name .. (perc and (" (" .. perc .. "% threat)") or ""), e.name)
end

function T:BossSwing(bguid, vguid, p, now)
	local b = F.bosses[bguid]
	p.bossSwings = p.bossSwings + 1
	if b.holder ~= vguid then T:AggroChange(bguid, b, vguid, now, "melee") end
end

function T:PollTargets()
	local now = GetTime()
	for guid, b in pairs(F.bosses) do
		if not b.dead then
			T:Accrue(b, now)
			local tg = W.Guid(guid .. "target")
			if tg ~= b.cand then
				b.cand = tg
				b.candSince = now
			end
			if b.cand and b.cand ~= b.holder and now - b.candSince >= AGGRO_CONFIRM
				and (not b.castUntil or now > b.castUntil) then
				T:AggroChange(guid, b, b.cand, now, "target")
			end
		end
	end
end

------------------------------------------------------------------ casts (SuperWoW)

function T:CastEvent(caster, target, evt, spellId, dur)
	if not F then return end
	local now = GetTime()
	local n, isPet = W.Owner(caster)
	dur = (tonumber(dur) or 0) / 1000

	if n then
		local p = T:P(n)
		if not isPet then
			if evt == "START" or evt == "CHANNEL" then
				mark(p, now, now + dur)
			elseif evt == "CAST" then
				mark(p, now, now + 1)
			elseif evt == "MAINHAND" or evt == "OFFHAND" then
				mark(p, now, now + 1.5)
			end
		end
		if evt == "CAST" then
			local D = W.Data
			local sp = W.SpellName(spellId)
			if D.kickSpells[sp] then
				p.kicks = p.kicks + 1
				if target then F.lastKick[target] = { name = n, t = now } end
			elseif sp == "Tranquilizing Shot" then
				p.tranqs = p.tranqs + 1
				F.lastTranq = { name = n, t = now }
			end
			local te = target and W.roster.byGuid[target]
			if D.absorbSpells[sp] then
				F.shields[te and target or caster] = { by = n, t = now, sp = sp }
			end
			if D.taunts[sp] then
				tinsert(F.tauntCasts, { t = now - F.t0, who = n })
			end
			local kind = D.saveCasts[sp]
			if kind and te and te.name ~= n then
				if kind == "rez" then
					if UnitIsDeadOrGhost(te.unit) then T:Save("rez", n, te.name, sp) end
				elseif kind == "mana" then
					local m = liveFrac(te.unit, true)
					if m and m < 0.3 then T:Save("innervate", n, te.name, sp, nil, m) end
				else
					local hp = liveFrac(te.unit)
					local hadAggro = false
					for _, b in pairs(F.bosses) do
						if b.holder == target then hadAggro = true end
					end
					if hp and (hp < 0.35 or (hadAggro and sp == "Blessing of Protection")) then
						T:Save("cooldown", n, te.name, sp, nil, hp)
					end
				end
			end
			if D.selfSaves[sp] and not isPet then
				local me = W.roster.byName[n]
				local hp = me and liveFrac(me.unit)
				if hp and hp < 0.3 then T:Save("self", n, n, sp, nil, hp) end
			end
		end
		return
	end

	if evt == "MAINHAND" or evt == "OFFHAND" then return end
	local sp = W.SpellName(spellId)
	local b = F.bosses[caster]
	if b then
		if evt == "START" or evt == "CHANNEL" then
			b.castUntil = now + dur + 0.5
		else
			b.castUntil = now + 0.5
		end
		if evt == "START" or (evt == "CAST" and not F.casting[caster]) then
			local last = F.castLines[sp]
			if not last or now - last > 5 then
				F.castLines[sp] = now
				T:Line("cast", b.name .. (evt == "START" and " begins casting " or " casts ") .. sp)
			end
		end
	end

	if W.Data.interrupts[sp] then
		local st = F.interrupts[sp]
		if not st then st = { casts = 0, kicked = 0, done = 0, by = {} }; F.interrupts[sp] = st end
		if evt == "START" then
			st.casts = st.casts + 1
			F.casting[caster] = { sp = sp, t = now }
		elseif evt == "FAIL" then
			local c = F.casting[caster]
			if c and c.sp == sp then
				st.kicked = st.kicked + 1
				local k = F.lastKick[caster]
				if k and now - k.t < 1.5 then st.by[k.name] = (st.by[k.name] or 0) + 1 end
				F.casting[caster] = nil
			end
		elseif evt == "CAST" then
			local c = F.casting[caster]
			if c and c.sp == sp then
				st.done = st.done + 1
				F.casting[caster] = nil
				T:Line("interrupt", sp .. " was not interrupted (" .. W.GuidName(caster) .. ")")
			end
		end
	elseif evt == "CAST" then
		F.casting[caster] = nil
	end

	if evt == "CAST" and W.Data.raidFail[sp] then
		F.raidFails[sp] = (F.raidFails[sp] or 0) + 1
		T:Line("fail", W.Data.raidFail[sp].tip)
	end
end

function T:SpellGo(itemId, spellId, casterGuid)
	if not F then return end
	itemId = tonumber(itemId)
	if not itemId or itemId == 0 then return end
	local e = W.roster.byGuid[casterGuid]
	if not e then return end
	local p = T:P(e.name)
	-- prefer the item's name ("Major Mana Potion") over its spell ("Restore Mana")
	local sp = GetItemInfo(itemId) or W.SpellName(spellId)
	p.consumes[sp] = (p.consumes[sp] or 0) + 1
	p.nCons = p.nCons + 1
	-- last-second health potion / healthstone
	local D = W.Data
	for i = 1, getn(D.healthItems) do
		if string.find(sp, D.healthItems[i], 1, true) then
			local hp = liveFrac(e.unit)
			if hp and hp < 0.3 then T:Save("potion", e.name, e.name, sp, nil, hp) end
			break
		end
	end
	push(p, "item", e.name, sp, 0)
end

function T:SpellMiss(casterGuid, targetGuid, spellId, missInfo)
	if not F or not F.bosses[targetGuid] then return end
	local sp = W.SpellName(spellId)
	if not W.Data.taunts[sp] then return end
	local n = W.Owner(casterGuid)
	if not n then return end
	F.taunts[n] = (F.taunts[n] or 0) + 1
	T:Line("taunt", n .. "'s " .. sp .. " was resisted", n)
end

function T:Dispel(casterGuid, targetGuid, spellId)
	if not F then return end
	local n = W.Owner(casterGuid)
	if n then
		local p = T:P(n)
		p.dispels = p.dispels + 1
		-- freeing someone from mind control is a save
		local te = targetGuid and W.roster.byGuid[targetGuid]
		local sp = spellId and W.SpellName(spellId)
		if te and sp and W.Data.mc[sp] then T:Save("freed", n, te.name, sp) end
	end
end

------------------------------------------------------------------ threat (Turtle WoW server API, same packets TWThreat uses)

function T:ThreatPacket(msg)
	if not F or not msg then return end
	local s = string.find(msg, "TWTv4=", 1, true)
	if not s then return end
	local tg = W.Guid("target")
	if not tg or not F.bosses[tg] then return end
	local bname = F.bosses[tg].name
	local data = string.sub(msg, s + 6)
	local hash = string.find(data, "#", 1, true)
	if hash then data = string.sub(data, 1, hash - 1) end
	local now = GetTime()
	for entry in string.gfind(data, "[^;]+") do
		local _, _, name, tank, threat, perc = string.find(entry, "^([^:]+):([^:]*):([^:]*):([^:]*)")
		perc = tonumber(perc)
		if name and perc then
			F.threat[name] = { perc = perc, threat = tonumber(threat), t = now, tank = (tank == "1") }
			local pk = F.threatPeak[name]
			if tank ~= "1" and (not pk or perc > pk.perc) then
				F.threatPeak[name] = { perc = perc, t = now - F.t0, boss = bname }
			end
		end
	end
end

function T:QueryThreat()
	if not WhoDidItDB.opts.queryThreat or W.env.twthreat then return end
	local tg = W.Guid("target")
	if not tg or not F.bosses[tg] then return end
	local ch
	if GetNumRaidMembers() > 0 then ch = "RAID" elseif GetNumPartyMembers() > 0 then ch = "PARTY" end
	if ch then SendAddonMessage("TWT_UDTSv4", "limit=10", ch) end
end

------------------------------------------------------------------ mana

function T:SampleMana()
	local t = GetTime() - F.t0
	for name, e in pairs(W.roster.byName) do
		if UnitPowerType(e.unit) == 0 and not UnitIsDeadOrGhost(e.unit) then
			local mx = UnitManaMax(e.unit)
			if mx and mx > 0 then
				local p = T:P(name)
				local s = p.mana
				if not s then s = {}; p.mana = s end
				if getn(s) < 1200 then
					tinsert(s, t)
					tinsert(s, UnitMana(e.unit) / mx)
				end
			end
		end
	end
end

------------------------------------------------------------------ event wiring

local function num(v) return tonumber(v) or 0 end

-- Nampower
local function onSpellDamage(targetGuid, casterGuid, spellId, amount, mitigation, hitInfo)
	-- mitigation is "absorb,block,resist"
	local _, _, absorb = string.find(mitigation or "", "^(%d+)")
	T:Damage(casterGuid, targetGuid, W.SpellName(spellId), num(amount), num(hitInfo) == 2, false, nil, num(absorb))
end
local function onSwing(attackerGuid, targetGuid, totalDamage, hitInfo, victimState, subDamageCount, blocked, totalAbsorb)
	hitInfo = num(hitInfo)
	T:Damage(attackerGuid, targetGuid, "Melee", num(totalDamage), hasFlag(hitInfo, HIT_CRIT), true, hitInfo, num(totalAbsorb))
end
local function onHeal(targetGuid, casterGuid, spellId, amount, crit, periodic)
	T:Heal(targetGuid, casterGuid, spellId, amount, crit, periodic)
end
local function onEnv(guid, typ, dmg) T:Env(guid, typ, dmg) end
local function onDebuffAdd(guid, luaSlot, spellId, stacks) T:Debuff(guid, spellId, stacks) end
local function onDebuffRem(guid, luaSlot, spellId, stacks, auraLevel, auraSlot, state) T:DebuffRemoved(guid, spellId, state) end
local function onBuffAdd(guid, luaSlot, spellId, stacks, auraLevel, auraSlot, state)
	if not F or num(state) == 2 then return end
	if F.bosses[guid] then
		T:BossBuff(guid, spellId, true)
	else
		T:RaidBuff(guid, spellId)
	end
end
local function onBuffRem(guid, luaSlot, spellId, stacks, auraLevel, auraSlot, state)
	if num(state) == 1 then T:BossBuff(guid, spellId, false) end
end
local function onGo(itemId, spellId, casterGuid) T:SpellGo(itemId, spellId, casterGuid) end
local function onMiss(casterGuid, targetGuid, spellId, missInfo) T:SpellMiss(casterGuid, targetGuid, spellId, missInfo) end
local function onDispel(casterGuid, targetGuid, spellId) T:Dispel(casterGuid, targetGuid, spellId) end

W:On("SPELL_DAMAGE_EVENT_SELF", onSpellDamage)
W:On("SPELL_DAMAGE_EVENT_OTHER", onSpellDamage)
W:On("AUTO_ATTACK_SELF", onSwing)
W:On("AUTO_ATTACK_OTHER", onSwing)
W:On("SPELL_HEAL_BY_SELF", onHeal)
W:On("SPELL_HEAL_BY_OTHER", onHeal)
W:On("ENVIRONMENTAL_DMG_SELF", onEnv)
W:On("ENVIRONMENTAL_DMG_OTHER", onEnv)
W:On("DEBUFF_ADDED_SELF", onDebuffAdd)
W:On("DEBUFF_ADDED_OTHER", onDebuffAdd)
W:On("DEBUFF_REMOVED_SELF", onDebuffRem)
W:On("DEBUFF_REMOVED_OTHER", onDebuffRem)
W:On("BUFF_ADDED_SELF", onBuffAdd)
W:On("BUFF_ADDED_OTHER", onBuffAdd)
W:On("BUFF_REMOVED_OTHER", onBuffRem)
W:On("SPELL_GO_SELF", onGo)
W:On("SPELL_GO_OTHER", onGo)
W:On("SPELL_MISS_SELF", onMiss)
W:On("SPELL_MISS_OTHER", onMiss)
W:On("SPELL_DISPEL_BY_SELF", onDispel)
W:On("SPELL_DISPEL_BY_OTHER", onDispel)
W:On("UNIT_DIED", function(guid) T:Died(guid) end)

-- SuperWoW
W:On("UNIT_CASTEVENT", function(caster, target, evt, spellId, dur)
	T:CastEvent(caster, target, evt, spellId, dur)
end)

-- Turtle threat API
W:On("CHAT_MSG_ADDON", function(prefix, msg)
	if F then T:ThreatPacket(msg) end
end)

-- Fallbacks when Nampower isn't installed: plain combat log death messages
W:On("CHAT_MSG_COMBAT_FRIENDLY_DEATH", function(msg)
	if W.env.nampower or not F or not msg then return end
	local _, _, name = string.find(msg, "^(.+) dies%.$")
	if msg == UNITDIESSELF then name = UnitName("player") end
	local e = name and W.roster.byName[name]
	if e then T:Death(e, e.guid) end
end)

W:On("CHAT_MSG_COMBAT_HOSTILE_DEATH", function(msg)
	if W.env.nampower or not F or not msg then return end
	local _, _, name = string.find(msg, "^(.+) dies%.$")
	if not name then return end
	for g, b in pairs(F.bosses) do
		if b.name == name and not b.dead then T:Died(g) return end
	end
end)

-- leaving the world mid-fight: keep what we have
W:On("PLAYER_LEAVING_WORLD", function()
	if F then T:Finish("RESET") end
end)

------------------------------------------------------------------ timers

W:Every(0.2, function()
	if F then T:PollTargets() end
end)

W:Every(0.5, function()
	if F then
		T:CheckLiving()
		T:CheckEnd()
	elseif UnitAffectingCombat("player") and W.env.superwow then
		-- backup start trigger: your own target is a boss already in combat
		local g = W.Guid("target")
		if g and UnitAffectingCombat("target") and T.IsBoss(g) then T:Start(g, nil, "combat") end
	end
end)

W:Every(1, function()
	if F then T:QueryThreat() end
end)

W:Every(2, function()
	if F then T:SampleMana() end
end)
