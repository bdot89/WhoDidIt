--[[--------------------------------------------------------------------
	WhoDidIt - learn packs (Auto Marker)

	Builds raid packs from what you see in game, so WhoDidIt has packs of
	its own: no data from anyone else.

	  1. Learn on (Auto Marker tab, or /wdi marks learn on): while you're in
	     a raid instance, every hostile mob that comes into view is noted
	     with where it stands (SuperWoW's UnitPosition, read while it's out
	     of combat, so it's its spawn spot), its name, whether it uses mana,
	     and its health. Bosses and critters are skipped.
	  2. Make packs (or /wdi marks build [yards]): mobs standing within 12
	     yards of each other (chained) become one pack, in the order you met
	     them. Marks follow WhoDidIt's own priority: mana users (healers,
	     casters) first, then the toughest; skull, cross, square, moon,
	     triangle, diamond, circle, star. They're saved as your own packs
	     ("Learned 01 - Molten Giant x2"), replacing earlier learned ones.
	     Change any mark by hand as usual.
	  3. Export (/wdi marks export) writes them, with any packs you saved
	     yourself, to CustomData\WhoDidIt_StdPacks.lua - the maintainer ships
	     that as DefaultPacks.lua, the packs everyone gets with the download.

	Raw sightings are kept in WhoDidItDB.marks.learned, so packs can be
	rebuilt with a different gap without walking the raid again.
----------------------------------------------------------------------]]

local W = WhoDidIt
local M = W.Marks
local L = {}
M.Learn = L

local getn, tinsert = table.getn, table.insert
local floor = math.floor
local MARKS = { 8, 7, 6, 5, 4, 3, 2, 1 }   -- skull first
local GAP = 12                               -- yards between mobs of one pack
local PREFIX = "Learned "

local function db() return WhoDidItDB and WhoDidItDB.marks end
local function isMob(guid) return type(guid) == "string" and string.sub(guid, 3, 3) == "F" end

local function store(zone)
	local d = db()
	d.learned = d.learned or {}
	d.learned[zone] = d.learned[zone] or {}
	return d.learned[zone]
end

function L:On() return db() and db().opts.learn and true or false end

function L:Set(on)
	db().opts.learn = on and true or nil
	if on then
		W.Print("Learning packs: |cff33ff33on|r. Walk through a raid (a normal clear does it) - every mob you see is noted with where it stands. Then click |cffffd100Make packs|r on the Auto Marker tab.")
		if not UnitPosition then W.Print("|cffff9933SuperWoW's UnitPosition isn't there, so positions can't be read and packs can't be built.|r") end
	else
		W.Print("Learning packs: off. What's noted so far is kept.")
	end
end

-- how many mobs are noted for a zone (with a position)
function L:Count(zone)
	local n, s = 0, db() and db().learned and db().learned[zone]
	for _, r in pairs(s or {}) do if r.x then n = n + 1 end end
	return n
end

local seq = 0
local function round(v) return v and floor(v * 10 + 0.5) / 10 end

-- note a mob where it stands (out of combat, so it's where it spawned)
function L:Note(guid)
	if not L:On() or not isMob(guid) or not UnitExists(guid) then return end
	local inInst, typ = IsInInstance()
	if not inInst or typ ~= "raid" then return end
	if UnitIsDead(guid) or not UnitCanAttack("player", guid) or UnitAffectingCombat(guid) then return end
	local cls = UnitClassification(guid)
	if cls == "worldboss" or UnitCreatureType(guid) == "Critter" then return end
	local s = store(GetRealZoneText())
	local old = s[guid]
	if old and old.x then return end
	local x, y, z
	if UnitPosition then
		local ok, a, b, c = pcall(UnitPosition, guid)
		if ok then x, y, z = a, b, c end
	end
	seq = seq + 1
	s[guid] = {
		n = UnitName(guid), x = round(x), y = round(y), z = round(z),
		m = ((UnitPowerType(guid) == 0) and (UnitManaMax(guid) or 0) > 0) and 1 or nil,
		hp = UnitHealthMax(guid), t = time() * 1000 + math.mod(seq, 1000),
	}
end

-- group the noted mobs of a zone into packs and save them as yours
function L:Build(zone, gap)
	zone = zone or GetRealZoneText()
	gap = tonumber(gap) or GAP
	local s = db() and db().learned and db().learned[zone]
	local list = {}
	for g, r in pairs(s or {}) do if r.x then tinsert(list, { g = g, r = r }) end end
	local n = getn(list)
	if n == 0 then
		W.Print("No mobs noted in " .. zone .. " yet. Switch Learn on and walk through the raid first.")
		return 0
	end
	table.sort(list, function(a, b) return a.r.t < b.r.t end)   -- the order you met them
	-- chain mobs within "gap" yards of each other into one pack
	local g2, pack, packs = gap * gap, {}, {}
	for i = 1, n do
		if not pack[i] then
			local members, queue, qi = { i }, { i }, 1
			pack[i] = true
			while queue[qi] do
				local a = list[queue[qi]].r
				qi = qi + 1
				for j = 1, n do
					if not pack[j] then
						local b = list[j].r
						local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
						if dx * dx + dy * dy + dz * dz <= g2 then
							pack[j] = true
							tinsert(queue, j)
							tinsert(members, j)
						end
					end
				end
			end
			tinsert(packs, members)
		end
	end
	-- replace the learned packs of this zone, keep everything else of yours
	local d = db()
	d.packs[zone] = d.packs[zone] or {}
	for name, p in pairs(d.packs[zone]) do
		if p.learned then d.packs[zone][name] = nil end
	end
	for k = 1, getn(packs) do
		local mobs = {}
		for i = 1, getn(packs[k]) do tinsert(mobs, list[packs[k][i]]) end
		-- healers / casters first, then the toughest
		table.sort(mobs, function(a, b)
			if (a.r.m or 0) ~= (b.r.m or 0) then return (a.r.m or 0) > (b.r.m or 0) end
			return (a.r.hp or 0) > (b.r.hp or 0)
		end)
		-- named after its most common mob
		local count, top, topN = {}, nil, 0
		for i = 1, getn(mobs) do
			local nm = mobs[i].r.n or "?"
			count[nm] = (count[nm] or 0) + 1
			if count[nm] > topN then top, topN = nm, count[nm] end
		end
		local name = PREFIX .. string.format("%02d", k) .. " - " .. (top or "?") .. ((getn(mobs) > 1) and (" x" .. getn(mobs)) or "")
		local p = { mobs = {}, names = {}, learned = true }
		for i = 1, getn(mobs) do
			p.mobs[mobs[i].g] = MARKS[i] or 0
			p.names[mobs[i].g] = mobs[i].r.n
		end
		d.packs[zone][name] = p
	end
	if M.Changed then M:Changed() end
	W.Print("Made " .. getn(packs) .. " packs from " .. n .. " mobs in " .. zone .. " (" .. gap .. " yard gap). They're saved as your own packs - change any mark by hand.")
	return getn(packs)
end

-- a Lua string literal
local function q(s) return string.format("%q", s or "") end

-- write your own packs (learned and saved) to CustomData\WhoDidIt_StdPacks.lua,
-- the file the maintainer ships as DefaultPacks.lua
function L:Export()
	if not WriteCustomFile then W.Print("Exporting needs Nampower's file access.") return end
	local d = db()
	local fromAutoMarker = {}
	local amd = WDI_MARKDATA and WDI_MARKDATA.packs or {}
	for i = 1, getn(amd) do fromAutoMarker[amd[i][1] .. "|" .. amd[i][2]] = true end
	local out = {
		"-- WhoDidIt's standard raid packs: learned and saved in game by the WhoDidIt maintainer",
		"-- (/wdi marks learn, build, export). Generated - do not edit; your own packs are saved in game.",
		"WDI_STDPACKS = { date = " .. q(date("%Y-%m-%d")) .. ", packs = {",
	}
	local packs, mobs, skipped = 0, 0, 0
	local zones = {}
	for zone in pairs(d.packs) do tinsert(zones, zone) end
	table.sort(zones)
	for z = 1, getn(zones) do
		local zone = zones[z]
		local names = {}
		for name in pairs(d.packs[zone]) do tinsert(names, name) end
		table.sort(names)
		for i = 1, getn(names) do
			local name, p = names[i], d.packs[zone][names[i]]
			-- an edited copy of an AutoMarker pack is theirs, not ours to ship
			if fromAutoMarker[zone .. "|" .. name] then
				skipped = skipped + 1
			elseif p.mobs and next(p.mobs) then
				local flat = {}
				for g, mark in pairs(p.mobs) do
					tinsert(flat, q(g) .. ", " .. (tonumber(mark) or 0) .. ", " .. q(p.names and p.names[g] or ""))
					mobs = mobs + 1
				end
				tinsert(out, "\t{ " .. q(zone) .. ", " .. q(name) .. ", { " .. table.concat(flat, ", ") .. " } },")
				packs = packs + 1
			end
		end
	end
	tinsert(out, "} }")
	local ok, err = pcall(WriteCustomFile, "WhoDidIt_StdPacks.lua", table.concat(out, "\n") .. "\n", "w")
	if not ok then W.Print("Couldn't write the file: " .. tostring(err)) return end
	W.Print("Exported " .. packs .. " packs (" .. mobs .. " mobs) to CustomData\\WhoDidIt_StdPacks.lua"
		.. ((skipped > 0) and (" - left out " .. skipped .. " edited AutoMarker pack" .. ((skipped == 1) and "" or "s")) or "") .. ".")
end

-- see mobs as they come into view, under the mouse, or targeted
local npMajor, npMinor = 0, 0
if GetNampowerVersion then npMajor, npMinor = GetNampowerVersion() end
if (npMajor or 0) > 2 or ((npMajor or 0) == 2 and (npMinor or 0) >= 39) then
	W:On("UNIT_MODEL_CHANGED_GUID", function(guid) L:Note(guid) end)
else
	W:On("UNIT_MODEL_CHANGED", function(guid) L:Note(guid) end)
end
local function noteUnit(unit)
	local ok, g = UnitExists(unit)
	if ok and type(g) == "string" then L:Note(g) end
end
W:On("UPDATE_MOUSEOVER_UNIT", function() noteUnit("mouseover") end)
W:On("PLAYER_TARGET_CHANGED", function() noteUnit("target") end)
