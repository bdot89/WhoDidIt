--[[--------------------------------------------------------------------
	WhoDidIt - auto marker

	Puts raid marks on whole packs of mobs at once. Every mob has a fixed
	GUID, so a "pack" is just a list of GUIDs and the mark each one gets.
	Mark the pack under your mouse (Shift + Ctrl/Alt), your target's pack,
	or the next pack along the route, from a key or the Marks window.

	Packs come from two places:
	  - built in: PackData.lua (WDI_MARKDATA), shipped with WhoDidIt: the
	    raid packs collected by the AutoMarker addon (by Weird Vibes),
	    converted to WhoDidIt's format and credited there. Nothing is
	    downloaded and WhoDidIt doesn't need AutoMarker.
	  - yours: mark mobs in game, click "Save marks as pack", name it. Saved
	    in WhoDidItDB.marks.packs; a pack of yours with the same name as a
	    built-in one replaces it, and hiding a built-in one sticks.

	Smart marks handle what fixed GUIDs can't: adds that spawn with fresh
	GUIDs every pull (Razuvious, Anub'Rekhan, Domo, Skeram, Karazhan...),
	Buru eggs that respawn, the highest-health Core Hound, KT's soldiers,
	Solnius' adds by kill priority and more. Each can be switched off.

	Needs SuperWoW (GUID unit tokens, mark1..mark8, local marks when you
	aren't lead or assist). Nampower 2.39+ is used for its GUID events
	when it's there.
----------------------------------------------------------------------]]

local W = WhoDidIt
local M = {}
W.Marks = M

local getn, tinsert, tsort = table.getn, table.insert, table.sort
local sfind, ssub, slower = string.find, string.sub, string.lower
local floor = math.floor

M.NAMES  = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
M.COLORS = { "|cffffff33", "|cffff9933", "|cffdd66ff", "|cff33ff33", "|cffb8cce0", "|cff3399ff", "|cffff4444", "|cffffffff" }
M.ICONS  = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
M.SYNC   = "WDIMark"

-- the 4x4 icon sheet: mark 1..8 -> texture coordinates
function M.IconCoords(i)
	local c, r = math.mod(i - 1, 4), floor((i - 1) / 4)
	return c * 0.25, c * 0.25 + 0.25, r * 0.25, r * 0.25 + 0.25
end

function M.MarkText(i)
	if not i or i < 1 or i > 8 then return "|cff888888no mark|r" end
	return M.COLORS[i] .. M.NAMES[i] .. "|r"
end

-- 0xF130 003E68 0158F6 -> "003E68" (the NPC id, in hex)
local function npcHex(guid)
	if not guid or string.len(guid) < 12 or ssub(guid, 3, 3) ~= "F" then return nil end
	return ssub(guid, 7, 12)
end
M.NpcHex = npcHex

local function isMob(guid) return guid and ssub(guid, 3, 3) == "F" end

------------------------------------------------------------------ state

M.builtin = {}   -- [zone][name] = { mobs = { [guid] = mark }, names = { [guid] = name } }
M.order   = {}   -- [zone] = { built-in pack names in route order }
M.live    = {}   -- [zone][name] = pack remapped onto this pull's fresh GUIDs (smart marks)
M.index   = {}   -- [zone] = { [guid] = pack name }, rebuilt on change
M.seen    = {}   -- guid -> name of every mob seen this session (mark by name / type)
M.nseen   = 0
M.last    = {}   -- [zone] = name of the last pack marked (for "next pack")
M.zone    = ""

local function db() return WhoDidItDB and WhoDidItDB.marks end

function M:Opt(key)
	local o = db().opts
	return o[key]
end

-- standing down while the separate AutoMarker addon is still loaded
function M:Active()
	return not M.standDown and db() and db().opts.enabled
end

function M:SmartOn(key)
	return M:Active() and db().opts.smart and db().smart[key] ~= false
end

------------------------------------------------------------------ built-in packs

-- two sources, same format: WhoDidIt's own standard packs (DefaultPacks.lua,
-- shipped with the addon) and AutoMarker's (Marks\packs.lua, downloaded by
-- the sync helper when you run it). M.dataInfo is about AutoMarker's only.
function M:LoadBuiltin()
	M.builtin, M.order = {}, {}
	M.dataInfo, M.stdInfo = nil, nil
	local function add(data, info)
		for i = 1, getn(data.packs) do
			local p = data.packs[i]
			local zone, name, flat = p[1], p[2], p[3]
			if type(zone) == "string" and type(name) == "string" and type(flat) == "table" then
				M.builtin[zone] = M.builtin[zone] or {}
				M.order[zone] = M.order[zone] or {}
				if not M.builtin[zone][name] then tinsert(M.order[zone], name) end
				local pack = { mobs = {}, names = {} }
				for j = 1, getn(flat), 3 do
					pack.mobs[flat[j]] = flat[j + 1]
					if flat[j + 2] ~= "" then pack.names[flat[j]] = flat[j + 2] end
					info.mobs = info.mobs + 1
				end
				M.builtin[zone][name] = pack
			end
		end
	end
	local std = WDI_STDPACKS
	if type(std) == "table" and type(std.packs) == "table" and getn(std.packs) > 0 then
		M.stdInfo = { date = std.date, packs = getn(std.packs), mobs = 0 }
		add(std, M.stdInfo)
	end
	local data = WDI_MARKDATA
	if type(data) == "table" and type(data.packs) == "table" then
		M.dataInfo = { version = data.version, commit = data.commit, date = data.date, packs = getn(data.packs), mobs = 0 }
		add(data, M.dataInfo)
	end
	M:Changed()
end

------------------------------------------------------------------ packs: lookup

local function hiddenKey(zone, name) return zone .. "|" .. name end

-- the pack as it stands: yours > this pull's live remap > built in
-- returns pack, source ("yours" / "edited" / "live" / "builtin")
function M:Pack(zone, name)
	local mine = db().packs[zone] and db().packs[zone][name]
	local b = M.builtin[zone] and M.builtin[zone][name]
	if mine then return mine, b and "edited" or "yours" end
	if db().hidden[hiddenKey(zone, name)] then return nil, "hidden" end
	local live = M.live[zone] and M.live[zone][name]
	if live then return live, "live" end
	if b then return b, "builtin" end
	return nil
end

function M:IsHidden(zone, name) return db().hidden[hiddenKey(zone, name)] and true or false end

-- pack names in a zone: built-in route order, then yours (oldest first)
function M:PackNames(zone, withHidden)
	local list, have = {}, {}
	local order = M.order[zone] or {}
	for i = 1, getn(order) do
		local n = order[i]
		if withHidden or M:Pack(zone, n) then tinsert(list, n) end
		have[n] = true
	end
	local mine = {}
	for n, p in pairs(db().packs[zone] or {}) do
		if not have[n] then tinsert(mine, { n, p.n or 0 }) end
	end
	tsort(mine, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
	for i = 1, getn(mine) do tinsert(list, mine[i][1]) end
	return list
end

-- every zone with packs, yours or built in
function M:Zones()
	local set = {}
	for z in pairs(M.builtin) do set[z] = true end
	for z, packs in pairs(db().packs) do
		if next(packs) then set[z] = true end
	end
	local list = {}
	for z in pairs(set) do tinsert(list, z) end
	tsort(list)
	return list
end

function M:Changed()
	M.index = {}
	if W.UI and W.UI.MarksChanged then W.UI:MarksChanged() end
end

local function buildIndex(zone)
	local idx = {}
	local names = M:PackNames(zone)
	-- built-in first, then yours, so a mob you saved wins over the built-in pack
	for pass = 1, 2 do
		for i = 1, getn(names) do
			local pack, src = M:Pack(zone, names[i])
			local isMine = (src == "yours" or src == "edited")
			if pack and ((pass == 1) ~= isMine) then
				for guid in pairs(pack.mobs) do idx[guid] = names[i] end
			end
		end
	end
	M.index[zone] = idx
	return idx
end

-- which pack is this mob in?  -> name, pack
function M:Find(zone, guid)
	if not guid then return nil end
	local idx = M.index[zone] or buildIndex(zone)
	local name = idx[guid]
	if name then return name, (M:Pack(zone, name)) end
end

function M:MobName(pack, guid)
	if UnitExists(guid) then
		local n = UnitName(guid)
		if n and n ~= "" and n ~= UNKNOWNOBJECT then return n end
	end
	return (pack and pack.names and pack.names[guid]) or M.seen[guid] or ("NPC " .. (npcHex(guid) or "?"))
end

------------------------------------------------------------------ marking

local function inGroup() return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0 end
M.InGroup = inGroup

function M:CanRaidMark()
	if GetNumRaidMembers() > 0 then return (IsRaidLeader() or IsRaidOfficer()) and true or false end
	if GetNumPartyMembers() > 0 then return IsPartyLeader() and true or false end
	return false
end

-- who sees the marks you put up
function M:MarkMode()
	if not W.env.superwow then return "nosuperwow" end
	if M:CanRaidMark() then return "raid" end
	if inGroup() then return "local" end
	return "solo"
end

-- the marks WhoDidIt put up itself (guid -> mark): any other mark was set by
-- someone (by hand, or another addon) and is left alone
M.mine = {}
local function guidOf(unit)
	if type(unit) == "string" and string.sub(unit, 1, 2) == "0x" then return unit end
	local ok, g = UnitExists(unit)
	if ok and type(g) == "string" and g ~= "" then return g end
end

local warnedLocal
function M:Set(unit, mark)
	local g = guidOf(unit)
	if g then M.mine[g] = (mark and mark > 0) and mark or nil end
	if M:CanRaidMark() then
		SetRaidTarget(unit, mark)
		return
	end
	if inGroup() and not warnedLocal then
		warnedLocal = true
		W.Print("|cffff9933You aren't raid lead or assist, so marks you set are only visible to you.|r")
	end
	SetRaidTarget(unit, mark, 1)   -- SuperWoW: a mark only you can see
end

-- may WhoDidIt put this mark on this mob by itself? Not when the mob carries a
-- mark someone else set (by hand, or another addon), and not when that icon is
-- on another living mob someone else put it on
local function mayMark(guid, mark)
	local cur = GetRaidTargetIndex(guid) or 0
	if cur == mark then return false end
	if cur > 0 and M.mine[guid] ~= cur then return false end
	local ok, holder = UnitExists("mark" .. mark)
	if mark > 0 and ok and holder and holder ~= guid and not UnitIsDead(holder) and M.mine[holder] ~= mark then return false end
	return true
end

-- every automatic mark (packs and smart rules) goes through this
function M:SetAuto(guid, mark)
	if mayMark(guid, mark) then M:Set(guid, mark) return true end
end

-- mark every mob of a pack that's here; mark 0 clears it from pack members
function M:MarkPack(pack)
	local n = 0
	for guid, mark in pairs(pack.mobs) do
		if UnitExists(guid) and (mark == 0 or not UnitIsDead(guid)) then
			M:SetAuto(guid, mark)
			if mark > 0 then n = n + 1 end
		end
	end
	return n
end

local function unitGuid(unit)
	local ok, guid = UnitExists(unit)
	if ok and guid and guid ~= "" then return guid end
end

-- mark the pack of the mob under the mouse, else of your target
function M:MarkGroup(quiet)
	if not W.env.superwow then W.Print("Auto marking needs SuperWoW.") return end
	local guid = unitGuid("mouseover") or unitGuid("target")
	if not guid or UnitIsDead(guid) or not isMob(guid) then
		if not quiet then W.Print("Mouse over or target a mob to mark its pack.") end
		return
	end
	local zone = GetRealZoneText()
	local name, pack = M:Find(zone, guid)
	if not pack then
		if not quiet then
			W.Print((UnitName(guid) or "That mob") .. " isn't in a saved pack. Mark the pack yourself, then click |cffffd100Save marks as pack|r in /wdi marks.")
		end
		return
	end
	M:MarkPack(pack)
	M.last[zone] = name
	return name
end

-- the next pack along the route (built-in order, then yours)
function M:MarkNext()
	local zone = GetRealZoneText()
	local names = M:PackNames(zone)
	if getn(names) == 0 then W.Print("No packs saved for " .. zone .. ".") return end
	local at = 0
	for i = 1, getn(names) do
		if names[i] == M.last[zone] then at = i end
	end
	local nxt = names[at + 1] or names[1]
	local pack = M:Pack(zone, nxt)
	local n = M:MarkPack(pack)
	M.last[zone] = nxt
	W.Print("Marking pack |cffffd100" .. nxt .. "|r (" .. (at + 1 > getn(names) and 1 or at + 1) .. " of " .. getn(names) .. ")"
		.. (n == 0 and " |cff888888- none of it is in range|r" or ""))
end

function M:ClearMarks()
	for i = 1, 8 do
		if UnitExists("mark" .. i) then M:Set("mark" .. i, 0) end
	end
end

-- the first mark not on a living unit (skull down, or star up)
function M:FreeMark(reverse)
	local a, b, s = 8, 1, -1
	if reverse then a, b, s = 1, 8, 1 end
	for i = a, b, s do
		local ok, g = UnitExists("mark" .. i)
		if not (ok and g and UnitExists(g) and not UnitIsDead(g)) then return i end
	end
end

function M:NextMark(guid, reverse)
	local i = M:FreeMark(reverse)
	if i then M:Set(guid, i) end
	return i
end

local function distance(guid)
	if UnitXP then
		local ok, d = pcall(UnitXP, "distanceBetween", "player", guid)
		if ok and d then return d end
	end
	return CheckInteractDistance(guid, 4) and 20 or 999
end

-- mark every living mob seen nearby whose name (or NPC id) matches, closest first
function M:MarkMatching(test, label)
	local list = {}
	for guid, name in pairs(M.seen) do
		if not UnitExists(guid) then
			M.seen[guid] = nil
			M.nseen = M.nseen - 1
		elseif not UnitIsDead(guid) and test(guid, name) then
			tinsert(list, { guid, distance(guid) })
		end
	end
	if getn(list) == 0 then W.Print(label .. " wasn't found nearby.") return end
	tsort(list, function(a, b) return a[2] < b[2] end)
	local n = 0
	for i = 1, getn(list) do
		if not GetRaidTargetIndex(list[i][1]) then
			if not M:NextMark(list[i][1]) then break end
			n = n + 1
		end
	end
	W.Print("Marked " .. n .. " x " .. label .. ".")
end

function M:MarkName(name)
	local want = slower(name)
	M:MarkMatching(function(_, n) return n and slower(n) == want end, name)
end

-- every mob of the same kind as your target
function M:MarkType()
	local guid = unitGuid("target")
	local id = npcHex(guid)
	if not id then W.Print("Target a mob first.") return end
	M:MarkMatching(function(g) return npcHex(g) == id end, UnitName("target") or "that mob")
end

------------------------------------------------------------------ saving your own packs

-- the mobs that have a raid mark right now: { { guid, mark, name }, ... }
function M:CurrentMarks()
	local list = {}
	for i = 8, 1, -1 do
		local ok, g = UnitExists("mark" .. i)
		if ok and g and isMob(g) and UnitExists(g) then
			tinsert(list, { g, i, UnitName(g) or "?" })
		end
	end
	return list
end

local function myPacks(zone)
	db().packs[zone] = db().packs[zone] or {}
	return db().packs[zone]
end

local function copyPack(p)
	local c = { mobs = {}, names = {} }
	for g, m in pairs(p.mobs) do c.mobs[g] = m end
	for g, n in pairs(p.names or {}) do c.names[g] = n end
	return c
end

-- the pack as yours, ready to change (a built-in one is copied first)
function M:Editable(zone, name)
	local mine = myPacks(zone)
	if not mine[name] then
		local p = M:Pack(zone, name)
		local c = p and copyPack(p) or { mobs = {}, names = {} }
		db().count = (db().count or 0) + 1
		c.n = db().count
		c.saved = date("%d %b %Y")
		mine[name] = c
	end
	return mine[name]
end

-- a name for a new pack: the pack these mobs are already in, else "<mob> pack"
function M:SuggestName(zone, list)
	local votes, best, bestN = {}, nil, 0
	for i = 1, getn(list) do
		local n = M:Find(zone, list[i][1])
		if n then
			votes[n] = (votes[n] or 0) + 1
			if votes[n] > bestN then best, bestN = n, votes[n] end
		end
	end
	if best then return best end
	local base = (list[1] and list[1][3] or "New") .. " pack"
	local name, i = base, 2
	while M:Pack(zone, name) or M:IsHidden(zone, name) do
		name = base .. " " .. i
		i = i + 1
	end
	return name
end

-- save marked mobs as a pack (adds to / updates it if the name exists)
function M:Save(zone, name, list)
	name = string.gsub(name or "", "^%s*(.-)%s*$", "%1")
	if name == "" then W.Print("A pack needs a name.") return end
	if getn(list) == 0 then W.Print("No marked mobs to save.") return end
	local isNew = (M:Pack(zone, name) == nil)
	local pack = M:Editable(zone, name)
	pack.saved = date("%d %b %Y")
	-- a mob belongs to one of your packs at a time
	for other, p in pairs(myPacks(zone)) do
		if other ~= name then
			for i = 1, getn(list) do p.mobs[list[i][1]] = nil end
		end
	end
	local parts = {}
	for i = 1, getn(list) do
		local g, m, who = list[i][1], list[i][2], list[i][3]
		pack.mobs[g] = m
		pack.names[g] = who
		tinsert(parts, M.MarkText(m) .. " " .. who)
	end
	db().hidden[hiddenKey(zone, name)] = nil
	M:Changed()
	W.Print((isNew and "Saved new pack " or "Updated pack ") .. "|cffffd100" .. name .. "|r in " .. zone .. ": " .. table.concat(parts, ", "))
	return true
end

function M:SetMobMark(zone, name, guid, mark)
	local pack = M:Editable(zone, name)
	pack.mobs[guid] = mark
	M:Changed()
end

-- a small bar of every mark at the mouse: click one to pick it
-- fn(mark) with 1..8, or 0 for no mark; removeFn = "take it out of the pack"
function M:PickMark(current, fn, removeFn, who)
	local p = M.picker
	if not p then
		p = CreateFrame("Frame", "WhoDidItMarkPicker", UIParent)
		p:SetFrameStrata("TOOLTIP")
		p:SetToplevel(true)
		p:EnableMouse(true)
		p:SetWidth(9 * 26 + 92)
		p:SetHeight(52)
		p:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 14,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		p:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
		p:SetBackdropBorderColor(0.6, 0.6, 0.65, 1)
		local fill = p:CreateTexture(nil, "BACKGROUND")
		fill:SetTexture(0.05, 0.05, 0.08, 1)
		fill:SetPoint("TOPLEFT", p, "TOPLEFT", 3, -3)
		fill:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -3, 3)
		p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -6)
		p.sel = p:CreateTexture(nil, "BORDER")
		p.sel:SetTexture(1, 0.82, 0, 0.35)
		p.sel:SetWidth(26)
		p.sel:SetHeight(26)
		p.btns = {}
		for k = 1, 9 do
			local mark = (k <= 8) and (9 - k) or 0   -- skull first, "none" last
			local b = CreateFrame("Button", nil, p)
			b:SetWidth(22)
			b:SetHeight(22)
			b:SetPoint("TOPLEFT", p, "TOPLEFT", 8 + (k - 1) * 26, -22)
			if mark > 0 then
				local t = b:CreateTexture(nil, "ARTWORK")
				t:SetAllPoints(b)
				t:SetTexture(M.ICONS)
				t:SetTexCoord(M.IconCoords(mark))
			else
				local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				fs:SetPoint("CENTER", b, "CENTER", 0, 0)
				fs:SetText("|cff999999none|r")
			end
			local hl = b:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints(b)
			hl:SetTexture(1, 1, 1, 0.25)
			b.mark = mark
			b:SetScript("OnClick", function()
				local f = M.picker.fn
				M.picker:Hide()
				if f then f(this.mark) end
			end)
			b:SetScript("OnEnter", function()
				GameTooltip:SetOwner(this, "ANCHOR_TOP")
				GameTooltip:SetText(this.mark > 0 and M.MarkText(this.mark) or "No mark (stays in the pack, unmarked)")
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function() GameTooltip:Hide() end)
			p.btns[k] = b
		end
		p.rem = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
		if W.UI and W.UI.Skin then W.UI.Skin(p.rem) end
		p.rem:SetWidth(78)
		p.rem:SetHeight(20)
		p.rem:SetPoint("TOPLEFT", p, "TOPLEFT", 8 + 9 * 26 + 2, -23)
		p.rem:SetText("|cffff7777Take out|r")
		if p.rem.SetTextFontObject then p.rem:SetTextFontObject(GameFontNormalSmall) end
		p.rem:SetScript("OnClick", function()
			local f = M.picker.removeFn
			M.picker:Hide()
			if f then f() end
		end)
		-- X in the top-right corner closes it without changing anything
		local x = CreateFrame("Button", nil, p, "UIPanelCloseButton")
		x:SetWidth(24)
		x:SetHeight(24)
		x:SetPoint("TOPRIGHT", p, "TOPRIGHT", 2, 2)
		x:SetScript("OnClick", function() M.picker:Hide() end)
		tinsert(UISpecialFrames, "WhoDidItMarkPicker")
		M.picker = p
	end
	p.fn, p.removeFn = fn, removeFn
	p.title:SetText("Mark for |cffffffff" .. (who or "this mob") .. "|r  |cff888888(X or Esc to close)|r")
	-- highlight the current mark
	p.sel:ClearAllPoints()
	local k = (current and current > 0) and (9 - current) or 9
	p.sel:SetPoint("CENTER", p.btns[k], "CENTER", 0, 0)
	if removeFn then p.rem:Show() else p.rem:Hide() end
	-- at the mouse
	local x, y = GetCursorPosition()
	local s = UIParent:GetEffectiveScale()
	p:ClearAllPoints()
	p:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s - 30, y / s + 8)
	p:Show()
end

function M:RemoveMob(zone, name, guid)
	local pack = M:Editable(zone, name)
	pack.mobs[guid] = nil
	M:Changed()
end

-- add your target with its current mark (or none)
function M:AddTarget(zone, name)
	local guid = unitGuid("target")
	if not isMob(guid) then W.Print("Target the mob you want to add.") return end
	local pack = M:Editable(zone, name)
	pack.mobs[guid] = GetRaidTargetIndex("target") or 0
	pack.names[guid] = UnitName("target")
	M:Changed()
	W.Print("Added " .. (UnitName("target") or "?") .. " (" .. M.MarkText(pack.mobs[guid]) .. ") to |cffffd100" .. name .. "|r.")
end

function M:Rename(zone, old, new)
	new = string.gsub(new or "", "^%s*(.-)%s*$", "%1")
	if new == "" or new == old then return end
	if M:Pack(zone, new) then W.Print("There's already a pack called " .. new .. ".") return end
	local pack = M:Editable(zone, old)
	local mine = myPacks(zone)
	mine[new] = pack
	mine[old] = nil
	if M.builtin[zone] and M.builtin[zone][old] then db().hidden[hiddenKey(zone, old)] = true end
	M:Changed()
	return true
end

-- yours: deleted (a built-in one of the same name comes back); built in: hidden
function M:Delete(zone, name)
	local mine = myPacks(zone)
	if mine[name] then
		mine[name] = nil
		if not next(mine) then db().packs[zone] = nil end
	elseif M.builtin[zone] and M.builtin[zone][name] then
		db().hidden[hiddenKey(zone, name)] = true
	end
	M:Changed()
end

function M:Restore(zone, name)
	db().hidden[hiddenKey(zone, name)] = nil
	local mine = db().packs[zone]
	if mine and mine[name] and M.builtin[zone] and M.builtin[zone][name] then mine[name] = nil end
	M:Changed()
end

-- the quick-save / rename popup (W:Prompt in Core.lua: one edit box, Enter saves)
function M:Prompt(text, default, fn) W:Prompt(text, default, fn) end

-- "Save marks as pack": capture the marks now, then ask for a name
function M:QuickSave(packName)
	local zone = GetRealZoneText()
	local list = M:CurrentMarks()
	if getn(list) == 0 then
		W.Print("Put raid marks on the mobs first (right-click their portrait), then save them as a pack.")
		return
	end
	if packName and packName ~= "" then return M:Save(zone, packName, list) end
	local suggest = M:SuggestName(zone, list)
	M:Prompt("Save " .. getn(list) .. " marked mob" .. (getn(list) == 1 and "" or "s") .. " as a pack in |cffffd100" .. zone .. "|r\n"
		.. "|cff888888(the name of an existing pack updates it)|r",
		suggest, function(name)
			if M:Save(zone, name, list) and W.UI and W.UI.ShowPack then W.UI:ShowPack(zone, name) end
		end)
end

------------------------------------------------------------------ smart marks

--[[ kinds:
	spawn  adds that get fresh GUIDs each pull: when `count` of them have
	       loaded, they take the marks of `pack` (matched by GUID order)
	next   mark each one with the next free mark as it spawns
	fixed  always this mark
	watch  keep marking them while the condition holds (polled)
	eggs   Buru eggs: an egg that dies hands its mark to the next one to respawn
	hounds the Core Hound with the most health gets skull
	aggro  mark the whole pack when one of them is pulled
	solnius Solnius' adds by kill priority
	alert  a warning when a rare mob is in the instance
]]
M.RULES = {
	{ key = "razuvious",   zone = "Naxxramas", kind = "spawn", names = { "Deathknight Understudy" }, count = 4, pack = "military_razuvious",
	  label = "Razuvious' Understudies", desc = "Re-marks the Understudies every pull (they respawn with new GUIDs)." },
	{ key = "anubrekhan",  zone = "Naxxramas", kind = "spawn", names = { "Crypt Guard" }, count = 2, pack = "spider_anubrekhan",
	  label = "Anub'Rekhan's Crypt Guards", desc = "Marks the Crypt Guards, which are new every reset." },
	{ key = "faerlina",    zone = "Naxxramas", kind = "spawn", names = { "Naxxramas Follower", "Naxxramas Worshipper" }, count = 6, pack = "spider_faerlina",
	  label = "Faerlina's Followers and Worshippers", desc = "Re-marks her adds after a reset." },
	{ key = "gargoyles",   zone = "Naxxramas", kind = "aggro", ids = { "003F28" },
	  label = "Plague Quarter gargoyles", desc = "Marks a gargoyle's pack the moment it wakes up." },
	{ key = "soldiers",    zone = "The Upper Necropolis", kind = "watch", names = { "Soldier of the Frozen Wastes" }, combat = true, near = true,
	  label = "Kel'Thuzad's Soldiers", desc = "Puts spare marks on soldiers that get close during the fight." },
	{ key = "domo",        zone = "Molten Core", kind = "spawn", ids = { "002D8F", "002D90" }, count = 8, pack = "domo", reverse = true,
	  label = "Majordomo's Flamewakers", desc = "Marks the healers and elites around Majordomo." },
	{ key = "hounds",      zone = "Molten Core", kind = "hounds", names = { "Core Hound" },
	  label = "Core Hound packs", desc = "Skull on the Core Hound with the most health (shared with other WhoDidIt markers)." },
	{ key = "nefarius",    zone = "Blackwing Lair", kind = "fixed", names = { "Lord Victor Nefarius" }, mark = 2,
	  label = "Lord Victor Nefarius", desc = "Circle on Nefarius." },
	{ key = "skeram",      zone = "Ahn'Qiraj", kind = "spawn", names = { "The Prophet Skeram" }, count = 3, pack = "skeram", live = true,
	  label = "Skeram's images", desc = "Marks the real Skeram and his images after every split." },
	{ key = "fankriss",    zone = "Ahn'Qiraj", kind = "next", names = { "Spawn of Fankriss" },
	  label = "Fankriss' worms", desc = "Marks each Spawn of Fankriss as it appears." },
	{ key = "buru",        zone = "Ruins of Ahn'Qiraj", kind = "eggs", ids = { "003C9A" },
	  label = "Buru's eggs", desc = "An egg that's killed passes its mark to the next egg that respawns." },
	{ key = "arlokk",      zone = "Zul'Gurub", kind = "spawn", names = { "High Priestess Arlokk" }, count = 1, pack = "arlokk", live = true,
	  label = "Arlokk", desc = "Re-marks Arlokk when she reappears." },
	{ key = "solnius",     zone = "Emerald Sanctum", kind = "solnius",
	  prio = { "Sanctum Supressor", "Sanctum Dragonkin", "Sanctum Wyrmkin", "Sanctum Scalebane" },
	  label = "Solnius' adds", desc = "Marks his adds in kill order: Supressor, Dragonkin, Wyrmkin, Scalebane." },
	{ key = "hatchers",    zone = "Onyxia's Lair", kind = "spawn", ids = { "00C3E0" }, count = 2, pack = "onyxia_hatchers", live = true,
	  label = "Onyxian Hatchers", desc = "Marks the hatchers as they come out." },
	{ key = "owls",        zone = "Tower of Karazhan", kind = "spawn", ids = { "00EA5E", "00EA5D" }, count = 4, pack = "gnarlmoon_owls", live = true, reverse = true,
	  label = "Gnarlmoon's owls", desc = "Marks the red and blue owls." },
	{ key = "seekers",     zone = "Tower of Karazhan", kind = "spawn", ids = { "00EA55" }, count = 4, pack = "incantagos_seekers", reverse = true,
	  label = "Incantagos' Ley-Seekers", desc = "Marks the Manascale Ley-Seekers." },
	{ key = "affinity",    zones = { "Tower of Karazhan", "The Rock of Desolation" }, kind = "fixed", mark = 8,
	  ids = { "00EA4E", "00EA4F", "00EA50", "00EA51", "00EA52", "00EA53" },
	  label = "Incantagos' affinities", desc = "Skull on each affinity as it spawns." },
	{ key = "sanv",        zones = { "Tower of Karazhan", "The Rock of Desolation" }, kind = "next", ids = { "00EA48" },
	  label = "Sanv Tas'dal's Riftstalkers", desc = "Next free mark (from skull down) on each Riftstalker." },
	{ key = "sanvnether",  zones = { "Tower of Karazhan", "The Rock of Desolation" }, kind = "next", ids = { "00EA4A" }, reverse = true,
	  label = "Sanv Tas'dal's Netherwalkers", desc = "Next free mark from star up, keeping skull and cross for the stalkers." },
	{ key = "fragments",   zone = "The Rock of Desolation", kind = "spawn", ids = { "00EA35" }, count = 3, pack = "rupturan_fragments", live = true,
	  label = "Rupturan's Fragments", desc = "Marks the Fragments of Rupturan." },
	{ key = "exiles",      zone = "The Rock of Desolation", kind = "spawn", ids = { "00EA38" }, count = 4, pack = "rupturan_exile", reverse = true,
	  label = "Rupturan's Crumbling Exiles", desc = "Marks the Crumbling Exiles." },
	{ key = "mounds",      zones = { "Tower of Karazhan", "The Rock of Desolation" }, kind = "fixed", ids = { "00EA34" }, mark = 4,
	  label = "Rupturan's dirt mounds", desc = "Triangle on each dirt mound." },
	{ key = "doomguards",  zone = "The Rock of Desolation", kind = "spawn", ids = { "016C98" }, count = 2, pack = "mephistroth", live = true,
	  label = "Mephistroth's Hellfire Doomguards", desc = "Marks the doomguard pairs as they spawn." },
	{ key = "kodiak",      zone = "Timbermaw Hold", kind = "spawn", ids = { "00F5D9" }, count = 1, pack = "rotgrowl",
	  label = "Rotgrowl's Kodiak", desc = "Marks the Kodiak with Rotgrowl's pack." },
	{ key = "illuminators", zone = "Timbermaw Hold", kind = "spawn", ids = { "00F5DE" }, count = 2, pack = "chieftain_illuminators",
	  label = "Withermaw Illuminators", desc = "Marks the Illuminators at the chieftain." },
	{ key = "shadowkeepers", zone = "Timbermaw Hold", kind = "spawn", ids = { "00F5DF" }, count = 2, pack = "chieftain_shadowkeepers", live = true,
	  label = "Withermaw Shadowkeepers", desc = "Marks the Shadowkeepers as they arrive." },
	{ key = "corrupters",  zone = "Timbermaw Hold", kind = "spawn", ids = { "007328" }, count = 2, pack = "ursol_corrupters", reverse = true,
	  label = "Ursol's Withermaw Corrupters", desc = "Marks the Corrupters at Ursol." },
	{ key = "keepers",     zone = "Blackrock Depths", kind = "watch", names = { "Shadowforge Flame Keeper" }, subzone = "The Lyceum",
	  label = "Flame Keepers (Lyceum)", desc = "Marks the Shadowforge Flame Keepers in the Lyceum." },
	{ key = "protectors",  zone = "Dire Maul", kind = "watch", names = { "Ironbark Protector" }, subzone = "Capital Gardens",
	  label = "Ironbark Protectors", desc = "Marks the Ironbark Protectors in the Capital Gardens." },
	{ key = "jed",         zone = "Blackrock Spire", kind = "alert", guid = "0xF13000290D104DD6",
	  label = "Jed Runewatcher alert", desc = "Warns you when the rare Jed Runewatcher is in your Blackrock Spire." },
}

M.byId, M.byName, M.ruleKey = {}, {}, {}
for i = 1, getn(M.RULES) do
	local r = M.RULES[i]
	r.zoneSet = {}
	if r.zone then r.zoneSet[r.zone] = true end
	for j = 1, getn(r.zones or {}) do r.zoneSet[r.zones[j]] = true end
	for j = 1, getn(r.ids or {}) do M.byId[r.ids[j]] = r end
	for j = 1, getn(r.names or {}) do M.byName[r.names[j]] = r end
	for j = 1, getn(r.prio or {}) do M.byName[r.prio[j]] = r end
	r.queue, r.nqueue, r.watch = {}, 0, {}
	M.ruleKey[r.key] = r
end

-- smart marks for a zone (for the window)
function M:RulesFor(zone)
	local list = {}
	for i = 1, getn(M.RULES) do
		if M.RULES[i].zoneSet[zone] then tinsert(list, M.RULES[i]) end
	end
	return list
end

function M:ToggleRule(key)
	db().smart[key] = (db().smart[key] == false) and nil or false
	M:Changed()
end

-- "spawn": map this pull's GUIDs onto the pack's marks, in GUID order
local function remap(r)
	local zone = r.zone
	local template = M.builtin[zone] and M.builtin[zone][r.pack]
	local mine = db().packs[zone] and db().packs[zone][r.pack]
	template = mine or template
	if not template then return end
	local function cmp(a, b) if r.reverse then return a < b end return a > b end
	local keys, fresh = {}, {}
	for g in pairs(template.mobs) do tinsert(keys, g) end
	for g in pairs(r.queue) do tinsert(fresh, g) end
	tsort(keys, cmp)
	tsort(fresh, cmp)
	local pack = { mobs = {}, names = {} }
	for i = 1, getn(keys) do
		local g = fresh[i] or keys[i]
		pack.mobs[g] = template.mobs[keys[i]]
		pack.names[g] = (template.names or {})[keys[i]]
	end
	M.live[zone] = M.live[zone] or {}
	M.live[zone][r.pack] = pack
	M:Changed()
	if r.live then M:MarkPack(pack) end
end

local function resetQueue(r) r.queue, r.nqueue = {}, 0 end

local solnius = { started = false, adds = {}, n = 0 }
local eggMarks = {}
local woken = {}       -- gargoyles already pulled
local houndWait = 0    -- seconds until we may re-skull a hound

-- a mob's model loaded (it's now in range): the smart-mark trigger
function M:OnModel(guid)
	if not isMob(guid) or not M:Active() then return end
	local name = UnitName(guid)
	if name and not M.seen[guid] then
		M.seen[guid] = name
		M.nseen = M.nseen + 1
		if M.nseen > 3000 then M.seen, M.nseen = {}, 0 end
	end
	if not db().opts.smart then return end
	local zone = M.zone
	local r = M.byId[npcHex(guid)] or M.byName[name or ""]
	if not r or not r.zoneSet[zone] or db().smart[r.key] == false then return end
	local k = r.kind
	if k == "spawn" then
		if not r.queue[guid] then
			r.queue[guid] = true
			r.nqueue = r.nqueue + 1
			M.checkSpawns = true
		end
	elseif k == "next" then
		if not GetRaidTargetIndex(guid) then M:NextMark(guid, r.reverse) end
	elseif k == "fixed" then
		if GetRaidTargetIndex(guid) ~= r.mark then M:SetAuto(guid, r.mark) end
	elseif k == "watch" or k == "hounds" then
		r.watch[guid] = true
		M.checkWatch = true
	elseif k == "eggs" then
		local mark = table.remove(eggMarks, 1)
		-- someone else's mark there: the icon goes back for the next egg
		if mark and not M:SetAuto(guid, mark) then table.insert(eggMarks, 1, mark) end
	elseif k == "solnius" then
		if name == "Solnius" then
			if UnitAffectingCombat(guid) then solnius.started = true end
		elseif solnius.started then
			solnius.adds[name] = solnius.adds[name] or {}
			tinsert(solnius.adds[name], guid)
			solnius.n = solnius.n + 1
			if solnius.n >= 3 then
				local mark = 8
				for i = 1, getn(r.prio) do
					local l = solnius.adds[r.prio[i]] or {}
					for j = 1, getn(l) do
						if mark >= 1 then M:SetAuto(l[j], mark) end
						mark = mark - 1
					end
				end
				solnius.adds, solnius.n, solnius.started = {}, 0, false
			end
		end
	end
end

-- unit flags changed: pulls (gargoyles) and deaths (Buru eggs)
function M:OnFlags(guid)
	if not M.watchFlags or not isMob(guid) or not M:Active() or not db().opts.smart then return end
	local r = M.byId[npcHex(guid)]
	if not r or not r.zoneSet[M.zone] or db().smart[r.key] == false then return end
	if r.kind == "aggro" then
		if not woken[guid] and UnitAffectingCombat(guid) and UnitCanAttack("player", guid) then
			woken[guid] = true
			local _, pack = M:Find(M.zone, guid)
			if pack then M:MarkPack(pack) end
		end
	elseif r.kind == "eggs" then
		if UnitIsDead(guid) then
			local mark = GetRaidTargetIndex(guid)
			if mark then tinsert(eggMarks, mark) end
		end
	end
end

local function pollSpawns()
	M.checkSpawns = false
	for i = 1, getn(M.RULES) do
		local r = M.RULES[i]
		if r.kind == "spawn" and r.nqueue > 0 then
			if r.zone ~= GetRealZoneText() then
				resetQueue(r)
			elseif r.nqueue >= r.count then
				remap(r)
				resetQueue(r)
			else
				M.checkSpawns = true
			end
		end
	end
end

local function pollHounds(r, dt)
	houndWait = houndWait - dt
	if houndWait > 0 then return true end
	houndWait = 3
	-- leave skull alone if it's on something else that's alive (a pull target)
	local ok, sk = UnitExists("mark8")
	if ok and sk and not UnitIsDead(sk) and UnitName(sk) ~= "Core Hound" then return true end
	local list = {}
	for g in pairs(r.watch) do
		if not UnitExists(g) then r.watch[g] = nil
		elseif UnitAffectingCombat(g) and not UnitIsDead(g) then tinsert(list, g) end
	end
	if not next(r.watch) then return false end
	tsort(list, function(a, b)
		local ha, hb = UnitHealth(a), UnitHealth(b)
		if ha == hb then return a < b end
		return ha > hb
	end)
	if list[1] and GetRaidTargetIndex(list[1]) ~= 8 then
		-- (straight M:Set: the skull moves between Core Hounds, also from another
		-- WhoDidIt marker's hound; a skull on anything else was respected above)
		M:Set(list[1], 8)
		if GetNumRaidMembers() > 0 then SendAddonMessage(M.SYNC, "HOUND", "RAID") end
	end
	return true
end

local function pollWatch(dt)
	local more = false
	for i = 1, getn(M.RULES) do
		local r = M.RULES[i]
		if (r.kind == "watch" or r.kind == "hounds") and next(r.watch) then
			if not r.zoneSet[GetRealZoneText()] then
				r.watch = {}
			elseif r.kind == "hounds" then
				if pollHounds(r, dt) then more = true end
			else
				more = true
				if not r.subzone or GetSubZoneText() == r.subzone then
					for g in pairs(r.watch) do
						if not UnitExists(g) or UnitIsDead(g) then
							r.watch[g] = nil
						elseif not GetRaidTargetIndex(g)
							and (not r.combat or UnitAffectingCombat(g))
							and (not r.near or CheckInteractDistance(g, 4)) then
							M:NextMark(g)
						end
					end
				end
			end
		end
	end
	M.checkWatch = more
end


W:Every(0.25, function()
	if not M.checkSpawns and not M.checkWatch then return end
	if not M:Active() then return end
	if M.checkSpawns then pollSpawns() end
	if M.checkWatch then pollWatch(0.25) end
end)

-- after combat: forget this fight's half-finished queues
local function clearTemps()
	M.mine = {}
	for i = 1, getn(M.RULES) do
		local r = M.RULES[i]
		if r.kind == "spawn" then
			for g in pairs(r.queue) do
				if UnitExists(g) and UnitAffectingCombat(g) then resetQueue(r) break end
			end
		else
			r.watch = {}
		end
	end
	solnius.adds, solnius.n, solnius.started = {}, 0, false
	eggMarks = {}
	woken = {}
end

------------------------------------------------------------------ events

local npMajor, npMinor = 0, 0
if GetNampowerVersion then npMajor, npMinor = GetNampowerVersion() end
local npGuids = (npMajor or 0) > 2 or ((npMajor or 0) == 2 and (npMinor or 0) >= 39)

if npGuids then
	W:On("UNIT_MODEL_CHANGED_GUID", function(guid) M:OnModel(guid) end)
	W:On("UNIT_FLAGS_GUID", function(guid) M:OnFlags(guid) end)
else
	W:On("UNIT_MODEL_CHANGED", function(guid) M:OnModel(guid) end)
	W:On("UNIT_FLAGS", function(guid) M:OnFlags(guid) end)
end

W:On("UPDATE_MOUSEOVER_UNIT", function()
	if not M:Active() then return end
	local guid = unitGuid("mouseover")
	if isMob(guid) and not M.seen[guid] then
		M.seen[guid] = UnitName("mouseover")
		M.nseen = M.nseen + 1
	end
	if db().opts.mouseover and IsShiftKeyDown() and (IsControlKeyDown() or IsAltKeyDown()) then
		M:MarkGroup(true)
	end
end)

local function onZone()
	M.zone = GetRealZoneText()
	M.watchFlags = (M.zone == "Naxxramas" or M.zone == "Ruins of Ahn'Qiraj")
	clearTemps()
	local jed = M.ruleKey.jed
	if M:Active() and db().smart.jed ~= false and db().opts.smart and jed.zoneSet[M.zone] and IsInInstance() and UnitExists(jed.guid) then
		UIErrorsFrame:AddMessage("Jed Runewatcher is in the instance!", 0, 1, 0)
		W.Print("|cff33ff33Jed Runewatcher is in this Blackrock Spire.|r")
	end
	if W.UI and W.UI.MarksChanged then W.UI:MarksChanged() end
end

W:On("ZONE_CHANGED_NEW_AREA", onZone)
W:On("PLAYER_REGEN_ENABLED", clearTemps)

-- another WhoDidIt marker just skulled a hound: let theirs stand
W:On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
	if prefix == M.SYNC and msg == "HOUND" and sender ~= UnitName("player") then houndWait = 3 end
end)

------------------------------------------------------------------ marking while solo / not lead

-- the raid-icon entries in unit menus are hidden unless you can raid-mark;
-- show them anyway and set a local mark (SuperWoW) when you can't
local origHide = UnitPopup_HideButtons
if origHide then
	UnitPopup_HideButtons = function(a1, a2, a3, a4)
		origHide(a1, a2, a3, a4)
		if not W.env.superwow or M:CanRaidMark() or not UnitPopupMenus or not UIDROPDOWNMENU_INIT_MENU then return end
		local menu = getglobal(UIDROPDOWNMENU_INIT_MENU)
		local list = menu and UnitPopupMenus[menu.which]
		if not list then return end
		for i, value in ipairs(list) do
			if ssub(value, 1, 12) == "RAID_TARGET_" then
				local shown = UnitPopupShown[UIDROPDOWNMENU_MENU_LEVEL or 1]
				if type(shown) == "table" then shown[i] = 1 else UnitPopupShown[i] = 1 end
			end
		end
	end
end
local origClick = UnitPopup_OnClick
if origClick then
	UnitPopup_OnClick = function(a1, a2, a3, a4)
		origClick(a1, a2, a3, a4)
		local value = this and this.value
		if not W.env.superwow or M:CanRaidMark() or type(value) ~= "string" then return end
		if ssub(value, 1, 12) == "RAID_TARGET_" and value ~= "RAID_TARGET_ICON" then
			local menu = getglobal(UIDROPDOWNMENU_INIT_MENU)
			local idx = ssub(value, 13)
			if menu and menu.unit then M:Set(menu.unit, idx == "NONE" and 0 or tonumber(idx)) end
		end
	end
end

------------------------------------------------------------------ setup + hand-over from AutoMarker

W:On("ADDON_LOADED", function(name)
	if name ~= "WhoDidIt" then return end
	local d = WhoDidItDB.marks
	if type(d) ~= "table" then d = {}; WhoDidItDB.marks = d end
	d.packs  = d.packs or {}
	d.hidden = d.hidden or {}
	d.smart  = d.smart or {}
	d.opts   = d.opts or {}
	if d.opts.enabled == nil then d.opts.enabled = true end
	if d.opts.mouseover == nil then d.opts.mouseover = false end
	-- smart marks put marks up by themselves, so they're off until you say yes
	-- (asked the first time you enter a raid; installs from before ask too)
	if not d.opts.smartAsked then d.opts.smart = false end
	M.standDown = IsAddOnLoaded("AutoMarker") and true or nil
	M:LoadBuiltin()
end)

StaticPopupDialogs["WHODIDIT_SMARTMARKS"] = {
	text = "WhoDidIt can mark known adds for you in raids (smart marks): Razuvious' Understudies, Buru's eggs, the biggest Core Hound, Skeram's images and more.\n\nAs raid lead or assist the raid sees them, otherwise only you do. Marks someone else set are left alone.\n\nUse smart marks?",
	button1 = "Yes", button2 = "No",
	OnAccept = function()
		WhoDidItDB.marks.opts.smart, WhoDidItDB.marks.opts.smartAsked = true, true
		W.Print("Smart marks: |cff33ff33on|r. Switch them off on the Auto Marker tab (Smart), or single ones under each zone.")
		if W.UI then W.UI:Refresh() end
	end,
	OnCancel = function()
		WhoDidItDB.marks.opts.smart, WhoDidItDB.marks.opts.smartAsked = false, true
		W.Print("Smart marks: off. Switch them on any time on the Auto Marker tab (Smart).")
		if W.UI then W.UI:Refresh() end
	end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}
local askedSmart
local function askSmart()
	local d = WhoDidItDB and WhoDidItDB.marks
	if askedSmart or not d or d.opts.smartAsked or not d.opts.enabled or M.standDown then return end
	local inInst, typ = IsInInstance()
	if not inInst or typ ~= "raid" then return end
	askedSmart = true
	StaticPopup_Show("WHODIDIT_SMARTMARKS")
end
W:On("ZONE_CHANGED_NEW_AREA", askSmart)
W:On("PLAYER_ENTERING_WORLD", askSmart)

local handedOver
W:On("PLAYER_ENTERING_WORLD", function()
	onZone()
	if handedOver or not M.standDown then return end
	handedOver = true
	-- bring over packs saved in AutoMarker (/am add), then switch it off
	local n = 0
	local custom = AutoMarkerDB and AutoMarkerDB.customNpcsToMark
	if type(custom) == "table" then
		local cache = AutoMarkerDB.unitCache or {}
		for zone, packs in pairs(custom) do
			for pname, mobs in pairs(packs) do
				if type(mobs) == "table" and next(mobs) and not (db().packs[zone] and db().packs[zone][pname]) then
					local pack = M:Editable(zone, pname)
					pack.mobs, pack.names = {}, {}
					for g, m in pairs(mobs) do
						pack.mobs[g] = m
						pack.names[g] = cache[g]
					end
					n = n + 1
				end
			end
		end
	end
	M:Changed()
	if n > 0 then W.Print("Your " .. n .. " saved AutoMarker pack" .. (n == 1 and "" or "s") .. " came across to WhoDidIt (|cffffd100/wdi marks|r).") end
	W:AskHandover("AutoMarker", "auto marking (the Auto Marker tab)")
end)

------------------------------------------------------------------ keys + commands

BINDING_HEADER_WHODIDIT        = "WhoDidIt"
BINDING_NAME_WHODIDIT_TOGGLE   = "Open / close the WhoDidIt window"
BINDING_NAME_WHODIDIT_MARKPACK = "Mark the pack under the mouse (or target)"
BINDING_NAME_WHODIDIT_MARKNEXT = "Mark the next pack along the route"
BINDING_NAME_WHODIDIT_SAVEMARKS = "Save the current marks as a pack"
BINDING_NAME_WHODIDIT_CLEARMARKS = "Clear all raid marks"

function WhoDidIt_MarkPack() if M.standDown then return end M:MarkGroup() end
function WhoDidIt_MarkNext() if M.standDown then return end M:MarkNext() end
function WhoDidIt_SaveMarks() M:QuickSave() end
function WhoDidIt_ClearMarks() M:ClearMarks() end

function M:Help()
	local c = "|cffffd100"
	W.Print("auto marking:")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi marks|r - the Marks window: every saved pack, and quick save")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi mark|r - mark the pack under your mouse or your target's pack  (or hold Shift + Ctrl/Alt over a mob)")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi marks next|r - mark the next pack,  " .. c .. "/wdi marks clear|r - remove all marks")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi marks save [name]|r - save the marked mobs as a pack,  " .. c .. "/wdi marks add <pack>|r - add your target to a pack")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi marks name <mob name>|r - mark every mob with that name nearby,  " .. c .. "/wdi marks type|r - every mob like your target")
	DEFAULT_CHAT_FRAME:AddMessage(c .. "/wdi marks on|off|r - auto marking on / off,  " .. c .. "/wdi marks info|r - which pack your target is in")
	DEFAULT_CHAT_FRAME:AddMessage("Keybinds: Esc > Key Bindings > WhoDidIt.  |cff888888(/am works too)|r")
end

function M:Slash(rest)
	local _, _, cmd, arg = sfind(rest or "", "^(%S*)%s*(.-)%s*$")
	cmd = slower(cmd or "")
	local zone = GetRealZoneText()
	if cmd == "" then
		W.UI:SetMode("marks")
	elseif cmd == "learn" then
		if not M.Learn then W.Print(W.RESTART_MSG) return end
		if arg == "clear" then M.Learn:Clear(zone) return end
		M.Learn:Set(arg == "on" or (arg == "" and not M.Learn:On()))
		if W.UI and W.UI.Refresh then W.UI:Refresh() end
	elseif cmd == "build" then
		if not M.Learn then W.Print(W.RESTART_MSG) return end
		M.Learn:Build(zone, arg ~= "" and arg or nil)
		if W.UI and W.UI.Refresh then W.UI:Refresh() end
	elseif cmd == "export" then
		if not M.Learn then W.Print(W.RESTART_MSG) return end
		M.Learn:Export()
	elseif cmd == "mark" or cmd == "pack" then
		M:MarkGroup()
	elseif cmd == "next" then
		M:MarkNext()
	elseif cmd == "clear" or cmd == "clearmarks" then
		M:ClearMarks()
	elseif cmd == "save" then
		M:QuickSave(arg)
	elseif cmd == "add" or cmd == "a" then
		if arg == "" then W.Print("Usage: /wdi marks add <pack name>") return end
		M:AddTarget(zone, arg)
	elseif cmd == "name" or cmd == "markname" then
		if arg == "" then M:MarkType() else M:MarkName(arg) end
	elseif cmd == "type" then
		M:MarkType()
	elseif cmd == "info" or cmd == "get" or cmd == "g" then
		local guid = unitGuid("target")
		if not isMob(guid) then W.Print("Target a mob.") return end
		local name, pack = M:Find(zone, guid)
		if name then
			W.Print((UnitName("target") or "?") .. " is " .. M.MarkText(pack.mobs[guid]) .. " in pack |cffffd100" .. name .. "|r (" .. zone .. ").")
		else
			W.Print((UnitName("target") or "?") .. " isn't in any pack.  |cff888888NPC " .. (npcHex(guid) or "?") .. ", " .. guid .. "|r")
		end
	elseif cmd == "on" or cmd == "off" or cmd == "enabled" then
		if cmd == "enabled" then db().opts.enabled = not db().opts.enabled else db().opts.enabled = (cmd == "on") end
		W.Print("Auto marking: " .. (db().opts.enabled and "|cff33ff33on|r" or "|cffff5555off|r"))
		M:Changed()
	else
		M:Help()
	end
end

-- /am, for anyone used to AutoMarker (not while it's still loaded)
if not IsAddOnLoaded("AutoMarker") then
	SLASH_WHODIDITMARKS1 = "/am"
	SLASH_WHODIDITMARKS2 = "/automarker"
	SlashCmdList["WHODIDITMARKS"] = function(msg) M:Slash(msg) end
end
