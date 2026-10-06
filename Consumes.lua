--[[--------------------------------------------------------------------
	WhoDidIt - consume check

	Reads a raider's consumable buffs and weapon oil / stone, and says what
	they're missing for their role (D.consumeNeeds). Used by the pull
	snapshot (Tracker), the Consumes tab, Name & Shame, and the ready-check
	scan. Ideas from DopingControl by ShempError (MIT):
	  - match buffs by spell ID as well as name
	  - a player who can't be read (out of range) is "unknown", never
	    "missing" - nobody is blamed on data we don't have
	  - weapon oils / stones of other players via SuperWoW
	    GetWeaponEnchantInfo(unit); no name + a readable main hand = none
	  - a scan on every ready check
----------------------------------------------------------------------]]

local W = WhoDidIt
local C = {}
W.Cons = C

local getn, tinsert = table.getn, table.insert

------------------------------------------------------------------ reading a unit

-- a buff's consumable name (or nil): by name, by spell ID, trimmed name
local function nameOf(id)
	local D = W.Data
	local name = W.SpellName(id)
	local only = D.consumeIdOnly[name]
	if only then return only[id] and name or nil end
	if D.consumeBuffs[name] then return name end
	local byId = D.consumeById[id]
	if byId then return byId end
	local trimmed = string.gsub(name or "", "^%s*(.-)%s*$", "%1")
	if D.consumeBuffs[trimmed] then return trimmed end
end

-- a spell's icon path (SuperWoW's SpellInfo, or ClassicAPI), or nil
local function spellIcon(id)
	local tex
	if SpellInfo then
		local ok, _, _, t = pcall(SpellInfo, id)
		if ok then tex = t end
	end
	if type(tex) ~= "string" and C_Spell and C_Spell.GetSpellTexture then
		local ok, t = pcall(C_Spell.GetSpellTexture, id)
		if ok then tex = t end
	end
	if type(tex) ~= "string" or tex == "" then return nil end
	if not string.find(tex, "\\", 1, true) then tex = "Interface\\Icons\\" .. tex end
	return tex
end

function C.BuffName(id)
	local b = nameOf(id)
	-- remember its icon by name (account-wide) for the Consumes grid
	if b and WhoDidItDB then
		local icons = WhoDidItDB.buffIcons
		if not icons then icons = {}; WhoDidItDB.buffIcons = icons end
		local had = icons[b]
		if had == nil or (had and string.sub(had, 1, 10) ~= "Interface\\") then icons[b] = spellIcon(id) or false end
	end
	return b
end

-- icons for consumables we haven't seen a spell ID for yet (old fights, the demo)
local I = "Interface\\Icons\\"
C.NAME_ICON = {
	["Flask of the Titans"] = I .. "INV_Potion_62", ["Flask of Supreme Power"] = I .. "INV_Potion_41",
	["Supreme Power"] = I .. "INV_Potion_41", ["Flask of Distilled Wisdom"] = I .. "INV_Potion_97",
	["Distilled Wisdom"] = I .. "INV_Potion_97", ["Elixir of the Mongoose"] = I .. "INV_Potion_32",
	["Greater Arcane Elixir"] = I .. "INV_Potion_25", ["Elixir of Giants"] = I .. "INV_Potion_61",
	["Elixir of the Giants"] = I .. "INV_Potion_61", ["Winterfall Firewater"] = I .. "INV_Potion_92",
	["Juju Power"] = I .. "INV_Misc_MonsterScales_11", ["Juju Might"] = I .. "INV_Misc_MonsterScales_07",
	["Spirit of Zanza"] = I .. "INV_Potion_30", ["Mageblood Potion"] = I .. "INV_Potion_45",
	["Shadow Power"] = I .. "INV_Potion_46", ["Elixir of Shadow Power"] = I .. "INV_Potion_46",
	["Greater Firepower"] = I .. "INV_Potion_60", ["Elixir of Greater Firepower"] = I .. "INV_Potion_60",
	["Elixir of Superior Defense"] = I .. "INV_Potion_66",
}
C.SLOT_ICON = {
	FLASK = I .. "INV_Potion_62", FOOD = I .. "Spell_Misc_Food", ALC = I .. "Spell_Misc_Food",
	AP = I .. "INV_Potion_92", STR = I .. "INV_Potion_61", AGI = I .. "INV_Potion_32", BL = I .. "INV_Potion_09",
	ZANZA = I .. "INV_Potion_30", GAE = I .. "INV_Potion_25", SCHOOL = I .. "INV_Potion_60", DREAMT = I .. "INV_Potion_25",
	SHARD = I .. "INV_Potion_25", MP5 = I .. "INV_Potion_45", ARM = I .. "INV_Potion_66", HPELX = I .. "INV_Potion_44",
	PROT = I .. "INV_Potion_24",
}

-- the icon to show for a consumable buff
function C.Icon(name)
	local seen = WhoDidItDB and WhoDidItDB.buffIcons and WhoDidItDB.buffIcons[name]
	if seen and string.sub(seen, 1, 10) == "Interface\\" then return seen end
	if C.NAME_ICON[name] then return C.NAME_ICON[name] end
	local slot = W.Data.consumeSlot[name]
	return (slot and C.SLOT_ICON[slot]) or (I .. "INV_Misc_QuestionMark")
end

-- the icon of what a need asks for (shown faded in a missing cell)
function C.NeedIcon(need)
	local slots = need[2]
	if type(slots) == "table" then return C.SLOT_ICON[slots[1]] end
	if slots == "IMBUE" and need[4] then return C.WeaponIcon(need[4][1]) end
	if string.find(need[1] or "", "oil", 1, true) then return I .. "INV_Potion_101" end
	return I .. "INV_Stone_SharpeningStone_01"
end

-- the icon for what's on a main hand (a name, or true = something unnamed)
function C.WeaponIcon(wpn)
	if type(wpn) == "string" then
		if string.find(wpn, "Rockbiter", 1, true) then return I .. "Spell_Nature_RockBiter" end
		if string.find(wpn, "Windfury", 1, true) then return I .. "Spell_Nature_Cyclone" end
		if string.find(wpn, "Flametongue", 1, true) then return I .. "Spell_Fire_FlameTounge" end
		if string.find(wpn, "Frostbrand", 1, true) then return I .. "Spell_Frost_FrostBrand" end
	end
	return "Interface\\Buttons\\UI-CheckBox-Check"
end

-- main-hand oil / stone: a name or true = has one, false = has none,
-- nil = can't tell (out of range, or no SuperWoW)
function C.Weapon(unit)
	if not GetWeaponEnchantInfo then return nil end
	if UnitIsUnit(unit, "player") then
		-- SuperWoW gives our own enchant's name too (needed to tell Rockbiter
		-- from a stone); the plain call only says whether there is one
		if W.env.superwow then
			local ok, name = pcall(GetWeaponEnchantInfo, "player")
			if ok and type(name) == "string" and name ~= "" then return name end
		end
		local ok, has = pcall(GetWeaponEnchantInfo)
		if ok then return has and true or false end
		return nil
	end
	if not W.env.superwow then return nil end
	local ok, name = pcall(GetWeaponEnchantInfo, unit)
	if not ok then return nil end
	if type(name) == "string" and name ~= "" then return name end
	if name == nil then
		-- no imbue name: only a real "none" if we can see their main hand at all
		local lok, link = pcall(GetInventoryItemLink, unit, 16)
		if lok and link then return false end
	end
	return nil
end

-- is a main-hand enchant name one of these shaman imbues? ("Rockbiter 9" ...)
function C.IsImbue(name, kinds)
	for i = 1, getn(kinds) do
		if string.find(name, kinds[i], 1, true) then return true end
	end
	return false
end

-- every buff (spell ID) on a unit, or nil when it can't be read
function C.Auras(unit, guid)
	local ids = {}
	-- ClassicAPI (optional): every buff in one call, plus when each runs out
	-- (exp = { [spellId] = GetTime() it ends }, only for casts seen this session)
	if W.env.capiAuras then
		local ok, list = pcall(C_UnitAuras.GetUnitAuras, unit, "HELPFUL")
		if ok and type(list) == "table" then
			local exp = {}
			for i = 1, getn(list) do
				local a = list[i]
				if a and a.spellId and a.spellId > 0 then
					tinsert(ids, a.spellId)
					if a.expirationTime and a.expirationTime > 0 then exp[a.spellId] = a.expirationTime end
				end
			end
			if getn(ids) > 0 then return ids, exp end
		end
	end
	if GetUnitData and guid then
		local ok, ud = pcall(GetUnitData, guid)
		if ok and type(ud) == "table" and type(ud.aura) == "table" then
			for i = 1, 32 do
				local id = ud.aura[i]
				if id and id > 0 then tinsert(ids, id) end
			end
		end
	end
	if getn(ids) == 0 and W.env.superwow then
		for i = 1, 32 do
			local tex, _, id = UnitBuff(unit, i)
			if not tex then break end
			if id then tinsert(ids, id) end
		end
	end
	if getn(ids) == 0 then return nil end   -- everyone has some buff: none = not readable
	return ids
end

------------------------------------------------------------------ roles and needs

local MELEE = { WARRIOR = true, ROGUE = true, PALADIN = true }
local CASTER = { MAGE = true, WARLOCK = true, PRIEST = true }

-- tank / healer / melee / ranged / caster (p = a report's player)
function C.Role(p)
	if not p then return nil end
	if p.role == "tank" then return "tank" end
	if p.role == "heal" then return "healer" end
	local c = p.class
	if c == "HUNTER" then return "ranged" end
	if MELEE[c] then return "melee" end
	if CASTER[c] then return "caster" end
	-- druids and shamans: melee if their top damage was melee swings
	if p.ds and p.ds[1] and p.ds[1][1] == "Melee" then return "melee" end
	if c == "DRUID" or c == "SHAMAN" then return "caster" end
	return nil
end

C.ROLE_TEXT = { tank = "Tank", healer = "Healer", melee = "Melee", ranged = "Ranged", caster = "Caster" }

-- every need of a player's role and whether it's met:
-- { { label, slots, met, extra }, ... } (slots: a list, "WPN" or "IMBUE");
-- nil when they couldn't be read. Flasks outside the big raids are left out.
function C.Needs(p, zone)
	if not p or p.read == false then return nil end
	local role = C.Role(p)
	local byClass = W.Data.consumeNeedsClass[p.class or ""]
	local needs = role and (byClass and byClass[role] or W.Data.consumeNeeds[role])
	if not needs then
		needs = { { "flask", { "FLASK" } }, { "food", { "FOOD" } } }
	end
	local have = {}
	for i = 1, getn(p.cbuffs or {}) do
		local slot = W.Data.consumeSlot[p.cbuffs[i][1]]
		if slot then have[slot] = true end
	end
	local out = {}
	for i = 1, getn(needs) do
		local label, slots = needs[i][1], needs[i][2]
		local met
		if slots == "WPN" then
			met = (p.wpn ~= false)
		elseif slots == "IMBUE" then
			-- none, or an oil / stone instead of the imbue (true = has one, name unknown)
			met = not (p.wpn == false or (type(p.wpn) == "string" and not C.IsImbue(p.wpn, needs[i][3])))
		elseif not (label == "flask" and zone and not W.Data.flaskZones[zone]) then
			met = false
			for j = 1, getn(slots) do if have[slots[j]] then met = true end end
		end
		if met ~= nil then tinsert(out, { label, slots, met, needs[i][3] }) end
	end
	return out
end

-- what a player is missing for their role: list of labels, or nil when
-- they couldn't be read (unknown)
function C.Missing(p, zone)
	local needs = C.Needs(p, zone)
	if not needs then return nil end
	local out = {}
	for i = 1, getn(needs) do
		if not needs[i][3] then tinsert(out, needs[i][1]) end
	end
	return out
end

-- players missing something: { { name, class, missing = {...} } }, most missing first;
-- plus how many couldn't be read
function C.Slackers(rec)
	local out, unknown = {}, 0
	for name, p in pairs(rec.players or {}) do
		local miss = C.Missing(p, rec.zone)
		if not miss then
			unknown = unknown + 1
		elseif getn(miss) > 0 then
			tinsert(out, { name = name, class = p.class, role = C.Role(p), missing = miss })
		end
	end
	table.sort(out, function(a, b)
		if getn(a.missing) ~= getn(b.missing) then return getn(a.missing) > getn(b.missing) end
		return a.name < b.name
	end)
	return out, unknown
end

-- "No flask: A, B   No food: C" groups for chat
function C.ByNeed(list)
	local order, groups = {}, {}
	for i = 1, getn(list) do
		for j = 1, getn(list[i].missing) do
			local m = list[i].missing[j]
			if not groups[m] then groups[m] = {}; tinsert(order, m) end
			tinsert(groups[m], list[i].name)
		end
	end
	return order, groups
end

------------------------------------------------------------------ ready-check scan

-- the latest role we saw each player in (from saved fights)
local function lastRoles()
	local roles = {}
	local fights = WhoDidItDB and WhoDidItDB.fights or {}
	for i = getn(fights), 1, -1 do
		for name, p in pairs(fights[i].players or {}) do roles[name] = p.role end
	end
	return roles
end

-- scan the raid right now: a fake "report" the checks above understand
function C:Scan()
	local roles = lastRoles()
	local rec = { players = {}, zone = GetRealZoneText(), enc = "Ready check" }
	for name, e in pairs(W.roster.byName) do
		local p = { class = e.class, role = roles[name], cbuffs = {} }
		local ids, exp = C.Auras(e.unit, e.guid)
		if ids then
			local now = GetTime()
			for i = 1, getn(ids) do
				local b = C.BuffName(ids[i])
				if b then
					tinsert(p.cbuffs, { b, W.Data.consumeBuffs[b], 0 })
					local ends = exp and exp[ids[i]]
					if ends and ends > now then
						p.ending = p.ending or {}
						tinsert(p.ending, { b, ends - now })
					end
				end
			end
		else
			p.read = false
		end
		p.wpn = C.Weapon(e.unit)
		-- healers / tanks we haven't seen yet only get the flask + food check
		if not p.role and (e.class == "PRIEST" or e.class == "DRUID" or e.class == "SHAMAN" or e.class == "PALADIN") then
			p.role = "unknown"
		end
		rec.players[name] = p
	end
	return rec
end

-- chat lines for a check: grouped by what's missing
function C:Lines(rec, title)
	local list, unknown = C.Slackers(rec)
	local n = 0
	for _ in pairs(rec.players) do n = n + 1 end
	local out = { "[WhoDidIt] " .. (title or "CONSUME CHECK") .. ": " .. (n - unknown - getn(list)) .. " of " .. n .. " ready"
		.. ((unknown > 0) and (", " .. unknown .. " out of range") or "") }
	local soon = C.EndingSoon(rec)
	if getn(list) == 0 then
		tinsert(out, "Everyone in range has their consumables. Nice.")
	else
		local order, groups = C.ByNeed(list)
		for i = 1, getn(order) do
			tinsert(out, "No " .. order[i] .. ": " .. table.concat(groups[order[i]], ", "))
		end
	end
	if getn(soon) > 0 then tinsert(out, "Running out in under 5 min: " .. table.concat(soon, ", ")) end
	return out
end

-- flasks / elixirs / food that end within 5 minutes (needs ClassicAPI):
-- { "Name (flask 3m)", ... }
local SOON_CAT = { Flask = "flask", Elixir = "elixir", Food = "food" }
function C.EndingSoon(rec)
	local out = {}
	for name, p in pairs(rec.players or {}) do
		local bits = {}
		for i = 1, getn(p.ending or {}) do
			local b, left = p.ending[i][1], p.ending[i][2]
			local cat = SOON_CAT[W.Data.consumeBuffs[b] or ""]
			if cat and left < 300 then tinsert(bits, cat .. " " .. math.ceil(left / 60) .. "m") end
		end
		if getn(bits) > 0 then tinsert(out, name .. " (" .. table.concat(bits, ", ") .. ")") end
	end
	table.sort(out)
	return out
end

-- /wdi check [post]: scan now, show (or post) who's missing what
function C:Check(post)
	if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then
		W.Print("Join a group first - the check looks at your raid.")
		return
	end
	W:UpdateRoster()
	local rec = C:Scan()
	local classes = {}
	for name, p in pairs(rec.players) do classes[name] = p.class end
	W:Send(C:Lines(rec, "READY CHECK - CONSUMES"), post and nil or "SELF", classes)
end

-- the full check: DopingControl's window (built in, or the separate addon)
function C:OpenFull()
	if DC_Matrix and DC_Matrix.Toggle then
		DC_Matrix.Toggle()
	else
		W.Print("DopingControl isn't installed yet: double-click tools\\WhoDidIt-Sync.cmd once (it downloads it), then " .. W.RESTART_HINT .. ".")
	end
end

-- a ready check: scan and show it to you (only you - nobody gets spammed)
W:On("READY_CHECK", function()
	if WhoDidItDB and WhoDidItDB.opts.readyCheckScan ~= false then C:Check(false) end
end)
