--[[--------------------------------------------------------------------
	WhoDidIt - master looting (the Loot tab)

	Drives RollFor, the master-loot roller built into WhoDidIt (see
	RollForLoader.lua): soft-res import and check, rolls, winners, its
	settings, plus a step-by-step guide. RollFor does the rolling itself -
	its loot window, roll popup and award buttons - so this file only
	reads its saved data (RollForCharDb) and runs its slash commands.
	The separate RollFor addon works here too.
----------------------------------------------------------------------]]

local W = WhoDidIt
local L = {}
W.Loot = L

local getn, tinsert = table.getn, table.insert

BINDING_NAME_WHODIDIT_LOOT = "Open the Loot tab (master looting)"

function L:Available()
	return RollFor ~= nil and RollFor.key_bindings ~= nil and SlashCmdList and SlashCmdList["RF"] ~= nil
end

-- "builtin" (WhoDidIt's RollFor\ copy), "standalone" (the separate addon) or nil
function L:Source()
	if not L:Available() then return nil end
	if not WDI_ROLLFOR_SKIP and WDI_ROLLFOR_VERSION then return "builtin" end
	return "standalone"
end

function L:Version()
	if L:Source() == "builtin" then return WDI_ROLLFOR_VERSION end
	return GetAddOnMetadata("RollFor", "Version")
end

------------------------------------------------------------------ RollFor's commands and settings

-- run one of RollFor's slash commands, e.g. L:Run("SRS") = /srs
function L:Run(cmd, args)
	local f = SlashCmdList and SlashCmdList[cmd]
	if not f then W.Print("RollFor isn't loaded - see the Loot tab.") return end
	f(args or "")
end

function L:Key(name)
	local kb = RollFor and RollFor.key_bindings
	if kb and kb[name] then kb[name]() else W.Print("RollFor isn't loaded - see the Loot tab.") end
end

local function config()
	return RollForCharDb and RollForCharDb.config or {}
end

function L:Setting(key) return config()[key] end

-- /rf config <command>: RollFor flips it, prints it and tells its windows
function L:Toggle(cmd) L:Run("RF", "config " .. cmd) end

-- RollFor's settings shown in the Loot tab: { db key, /rf config command, label, what it does }
L.SETTINGS = {
	{ "auto_master_loot", "auto-master-loot", "Auto master loot",
	  "Switch the raid to master loot (you as looter) when you target a boss. You need to be raid leader." },
	{ "show_ml_warning", "ml", "Master loot warning",
	  "Warn you when you open a boss's loot and master loot isn't on." },
	{ "auto_raid_roll", "auto-rr", "Auto raid roll",
	  "When nobody rolls on an item that isn't soft-reserved, raid-roll it (a random raider gets it)." },
	{ "auto_loot", "auto-loot", "Auto-loot",
	  "Hand out items on RollFor's auto-loot list without rolling (manage the list with /rfal)." },
	{ "auto_loot_announce", "auto-loot-announce", "Announce auto-looted items", "Say in raid what was auto-looted." },
	{ "auto_class_announce", "auto-class-announce", "Announce class restrictions",
	  "For class-only items (tier tokens and the like) the roll message names the classes that can roll." },
	{ "auto_tmog", "auto-tmog", "No transmog rolls on trash", "Trash loot only takes main-spec and off-spec rolls." },
	{ "raid_roll_again", "raid-roll-again", "Raid roll again button", "Show a button to raid-roll the same item again." },
	{ "show_player_roles", "show-player-roles", "Show roles while rolling", "Show each roller's spec from the soft-res sheet in the roll window." },
	{ "handle_plus_ones", "Handle-plus-ones", "Track +1s", "Count main-spec wins (+1) per player for the rest of the raid." },
	{ "plus_one_prompt", "plus-one-prompt", "Ask about +1 on award", "Ask whether each award should count as a +1." },
	{ "loot_frame_cursor", "loot-frame-cursor", "Loot window at the mouse", "Open RollFor's loot window where your mouse is." },
	{ "classic_look", "classic-look", "Classic look", "Blizzard-style look for RollFor's windows (needs a /reload)." },
}

-- the roll window raiders with RollFor see when you start a roll
L.POPUP = { "Off", "Eligible", "Always" }
function L:RollPopup() return config().client_show_roll_popup or "Off" end
function L:CycleRollPopup()
	local cur, nxt = L:RollPopup(), "Off"
	for i = 1, getn(L.POPUP) do
		if L.POPUP[i] == cur then nxt = L.POPUP[i + 1] or L.POPUP[1] end
	end
	L:Run("RF", "config client show-roll " .. nxt)
end

------------------------------------------------------------------ the soft-res sheet

-- decoded from RollFor's saved copy: { id, instances, players = { { name, role, items = { ids } } }, items }
function L:SoftRes()
	local sr = RollForCharDb and RollForCharDb.softres
	local raw = sr and sr.data
	if type(raw) ~= "string" or raw == "" then return nil end
	if L.srCache and L.srCache.raw == raw then return L.srCache end
	local ok, data = pcall(function()
		local json = LibStub and LibStub("Json-0.1.2", true)
		if not json or not RollFor.decode_base64 then return nil end
		return json.decode(RollFor.decode_base64(raw))
	end)
	if not ok or type(data) ~= "table" then return nil end
	local meta = data.metadata or {}
	local out = { raw = raw, id = meta.id, instances = meta.instances or {}, players = {}, items = 0 }
	local list = data.softreserves or {}
	for i = 1, getn(list) do
		local p = list[i]
		local items = {}
		for j = 1, getn(p.items or {}) do
			tinsert(items, p.items[j].id)
			out.items = out.items + 1
		end
		tinsert(out.players, { name = p.name or "?", role = p.role or "", items = items })
	end
	table.sort(out.players, function(a, b) return a.name < b.name end)
	L.srCache = out
	return out
end

-- RollFor's role names ("WarriorArms") -> "Arms Warrior"
function L.RoleText(role)
	local _, _, class, spec = string.find(role or "", "^(%u%l+)(%u.*)$")
	if not class then return role or "" end
	return spec .. " " .. class
end

-- who's in the raid now: lowercase name -> { name, class }
function L:Roster()
	local r = {}
	local n = GetNumRaidMembers()
	if n > 0 then
		for i = 1, n do
			local name, _, _, _, _, class = GetRaidRosterInfo(i)
			if name then r[string.lower(name)] = { name = name, class = class } end
		end
	else
		local me = UnitName("player")
		local _, class = UnitClass("player")
		r[string.lower(me)] = { name = me, class = class }
		for i = 1, GetNumPartyMembers() do
			local name = UnitName("party" .. i)
			local _, c = UnitClass("party" .. i)
			if name then r[string.lower(name)] = { name = name, class = c } end
		end
	end
	return r
end

------------------------------------------------------------------ loot given + loot method

-- RollFor's award log, newest first
function L:Awarded()
	local a = RollForCharDb and RollForCharDb.awarded_loot and RollForCharDb.awarded_loot.awarded_items
	local out = {}
	if type(a) ~= "table" then return out end
	for i = getn(a), 1, -1 do tinsert(out, a[i]) end
	return out
end

-- "master" (you / someone) or another loot method, plus the looter's name
function L:LootMethod()
	local method, partyMaster, raidMaster = GetLootMethod()
	local looter
	if method == "master" then
		if raidMaster then
			looter = GetRaidRosterInfo(raidMaster)
		elseif partyMaster == 0 then
			looter = UnitName("player")
		elseif partyMaster then
			looter = UnitName("party" .. partyMaster)
		end
	end
	return method, looter
end

function L:IsLeader()
	if GetNumRaidMembers() > 0 then return IsRaidLeader() and true or false end
	return IsPartyLeader() and true or false
end

------------------------------------------------------------------ hand-over from the separate addon

-- The separate RollFor is still switched on next to the built-in copy: it
-- keeps running this session and is switched off from the next /reload.
-- Both declare RollFor's saved variables, so its settings, soft-res sheet
-- and winners are saved with WhoDidIt's on the way out.
local handedOver
W:On("PLAYER_ENTERING_WORLD", function()
	if handedOver or not (WDI_ROLLFOR_SKIP and WDI_ROLLFOR_VERSION) then return end
	handedOver = true
	DisableAddOn("RollFor")
	W.Print("WhoDidIt now has RollFor built in (v" .. WDI_ROLLFOR_VERSION .. ", the |cffffd100Loot|r tab), so the separate |cffffd100RollFor|r addon has been switched off on this character.")
	W.Print("It keeps working until your next /reload, then WhoDidIt's copy takes over with your RollFor settings, soft-res and winners. Once you've done this on every character you loot with, you can delete Interface\\AddOns\\RollFor.")
end)
