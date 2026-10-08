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

-- RollFor's on/off settings shown in the Loot tab, in groups.
-- Each: { db key, /rf config command, label, one-line summary, { hover lines } }
L.SETTINGS = {
	{ title = "Switching the loot method for you",
	  intro = { "Target a boss: the raid switches to master loot, with you as the looter.",
	            "Give out everything in the boss's loot: it switches back to group loot for the trash." },
	  items = {
		{ "auto_master_loot", "auto-master-loot", "Auto master loot", "Target a boss and master loot (you) turns on.",
		  { "When you target a boss, the raid switches to master loot with you as the looter.",
		    "You have to be the raid leader. Default: on." } },
		{ "auto_group_loot", "auto-group-loot", "Auto group loot", "Boss looted empty and group loot comes back on.",
		  { "When everything in a boss's loot window has been given out, the raid switches back",
		    "to group loot, so trash is rolled as normal. (RollFor doesn't do this in Blackwing Lair.)",
		    "You have to be the raid leader. Default: off." } },
		{ "show_ml_warning", "ml", "Master loot warning", "Warns you if you loot a boss without master loot.",
		  { "Shows a warning when you open a boss's loot and master loot isn't on. Default: off." } },
	  } },
	{ title = "Rolling",
	  items = {
		{ "auto_raid_roll", "auto-rr", "Auto raid roll", "Nobody rolled? A random raider gets it.",
		  { "When nobody rolls on an item that isn't soft-reserved, RollFor raid-rolls it:",
		    "a random raider wins it. Default: off." } },
		{ "auto_class_announce", "auto-class-announce", "Name the classes that can roll", "For class-only items like tier tokens.",
		  { "For items only some classes can use (tier tokens, class books...), the roll message",
		    "names those classes instead of the plain \"roll for\" message. Default: off." } },
		{ "auto_tmog", "auto-tmog", "No transmog rolls on trash", "Trash drops only take main and off spec rolls.",
		  { "Items from trash mobs can't be rolled for transmog. Default: off." } },
		{ "show_player_roles", "show-player-roles", "Show specs in the roll window", "Each roller's spec from the soft-res sheet.",
		  { "Shows each roller's spec (from the soft-res sheet) next to their roll. Default: off." } },
		{ "raid_roll_again", "raid-roll-again", "Raid roll again button", "Raid-roll the same item again.",
		  { "Adds a button to raid-roll the same item again after a raid roll. Default: off." } },
		{ "handle_plus_ones", "Handle-plus-ones", "Track +1s", "Count each player's main-spec wins.",
		  { "Counts main-spec wins (+1) per player, so you can favour players who haven't won yet.", "Default: off." } },
		{ "plus_one_prompt", "plus-one-prompt", "Ask about +1 when awarding", "Choose per item whether it counts as a +1.",
		  { "When you award an item, asks whether it should count as a +1. Default: off." } },
	  } },
	{ title = "Looting",
	  items = {
		{ "auto_loot", "auto-loot", "RollFor's auto-loot list", "Items on RollFor's own list skip the roll.",
		  { "Items on RollFor's auto-loot list are looted straight away without a roll.",
		    "Manage the list with /rfal. Default: on." } },
		{ "auto_loot_announce", "auto-loot-announce", "Announce auto-looted items", "Says in raid what was auto-looted.",
		  { "Posts the auto-looted items to the raid. Default: on." } },
		{ "loot_frame_cursor", "loot-frame-cursor", "Loot window at the mouse", "Opens RollFor's loot window where your mouse is.",
		  { "Opens RollFor's loot window at your mouse instead of its saved spot. Default: off." } },
		{ "classic_look", "classic-look", "Classic look", "Blizzard-style windows (needs a /reload).",
		  { "Gives RollFor's windows the classic Blizzard look. Needs a /reload. Default: off." } },
	  } },
}

------------------------------------------------------------------ roll numbers

-- what raiders type: /roll (1-100) for main spec, /roll 99 for off spec...
L.ROLLS = {
	{ key = "ms_roll_threshold",   cmd = "ms",   label = "Main spec", default = 100 },
	{ key = "os_roll_threshold",   cmd = "os",   label = "Off spec",  default = 99 },
	{ key = "tmog_roll_threshold", cmd = "tmog", label = "Transmog",  default = 98 },
}

function L:RollNumber(r) return tonumber(config()[r.key]) or r.default end
function L.RollCommand(n) return (n == 100) and "/roll" or ("/roll " .. n) end
function L:TmogOn() return config().tmog_rolling_enabled ~= false end
function L:RollTime() return tonumber(config().default_rolling_time_seconds) or 8 end

-- "/roll = main spec, /roll 99 = off spec, /roll 98 = transmog"
function L:HowToRoll()
	local parts = {}
	for i = 1, getn(L.ROLLS) do
		local r = L.ROLLS[i]
		if r.cmd ~= "tmog" or L:TmogOn() then
			tinsert(parts, L.RollCommand(L:RollNumber(r)) .. " = " .. string.lower(r.label))
		end
	end
	return table.concat(parts, ", ")
end

-- change one roll number (asks first, checks it, then /rf config <ms|os|tmog> <n>)
function L:AskRollNumber(r)
	W:Prompt("Roll number for |cffffd100" .. r.label .. "|r\n|cff888888Raiders type /roll <number>. 100 = plain /roll.|r",
		L:RollNumber(r), function(text)
			local n = tonumber(text)
			if not n or n ~= math.floor(n) or n < 2 or n > 10000 then
				W.Print("A roll number is a whole number from 2 to 10000.")
				return
			end
			for i = 1, getn(L.ROLLS) do
				local o = L.ROLLS[i]
				if o ~= r and L:RollNumber(o) == n then
					W.Print(o.label .. " already uses " .. n .. " - each roll type needs its own number.")
					return
				end
			end
			L:Run("RF", "config " .. r.cmd .. " " .. n)
			if W.UI then W.UI:Refresh() end
		end)
end

function L:ResetRollNumbers()
	for i = 1, getn(L.ROLLS) do L:Run("RF", "config " .. L.ROLLS[i].cmd .. " " .. L.ROLLS[i].default) end
end

function L:ToggleTmog() L:Run("RF", "config tmog") end

function L:AskRollTime()
	W:Prompt("How long a roll lasts, in seconds\n|cff888888From 4 to 15. You can still end a roll early with Finish roll.|r",
		L:RollTime(), function(text)
			local n = tonumber(text)
			if not n or n < 4 or n > 15 then W.Print("Roll time is from 4 to 15 seconds.") return end
			L:Run("RF", "config default-rolling-time " .. math.floor(n))
			if W.UI then W.UI:Refresh() end
		end)
end

-- "item:19885:0:0:0" for the item tooltip (also asks the server for an item not seen yet)
function L.ItemLink(idOrLink)
	if type(idOrLink) == "number" then return "item:" .. idOrLink .. ":0:0:0" end
	if type(idOrLink) == "string" then
		local _, _, link = string.find(idOrLink, "|H(item:[%-%d:]+)|h")
		return link or (string.find(idOrLink, "^item:") and idOrLink) or nil
	end
end

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
	W:AskHandover("RollFor", "RollFor (v" .. WDI_ROLLFOR_VERSION .. ", the RollForML tab)")
end)
