--[[--------------------------------------------------------------------
	WhoDidIt - auto invite

	/wdi inv (or /wdi inv on|off): while it's on, everyone who whispers you
	+ (any number of them, spaces allowed: "+", "+++", "+ ++") or types it
	in guild chat gets an invite. Solo, the first one to accept makes a
	party, and WhoDidIt turns it into a raid straight away; the rest are
	invited into the raid. Turning it on posts one line in guild chat
	(/wdi inv post posts it again). It's off at every login, and the first
	time it asks. Inviting needs the group leader (or a raid assistant).
----------------------------------------------------------------------]]

local W = WhoDidIt
local A = {}
W.AutoInv = A

local getn = table.getn
local RAID_MAX = 40
local AGAIN = 60   -- seconds before the same player is invited again
local WAIT = 60    -- seconds an invite waits for the party to become a raid
-- (sent text stays English, like everything WhoDidIt sends)
local GUILD_LINE = "[WhoDidIt] Raid invites are open: whisper me + for an invite."

A.on = false
local recent = {}    -- name -> GetTime() invited (dropped after AGAIN seconds)
local pending = {}   -- { name, at }: waiting for the party to become a raid (at most 40)
local told = {}      -- why someone wasn't invited, said once a session per reason

-- "+", "+++", "+ + +": only plus signs and spaces
local function isPlus(msg)
	return type(msg) == "string" and string.len(msg) <= 40 and string.find(msg, "^[%s%+]+$") and string.find(msg, "%+") and true or false
end

local function inGroup(name)
	for i = 1, GetNumRaidMembers() do
		if GetRaidRosterInfo(i) == name then return true end
	end
	for i = 1, GetNumPartyMembers() do
		if UnitName("party" .. i) == name then return true end
	end
	return false
end

local function once(why, text)
	if told[why] then return end
	told[why] = true
	W.Print(text)
end

local function canInvite()
	if GetNumRaidMembers() > 0 then return (IsRaidLeader() or (IsRaidOfficer and IsRaidOfficer())) and true or false end
	if GetNumPartyMembers() > 0 then return IsPartyLeader() and true or false end
	return true
end

-- a party becomes a raid (only its leader can)
local function toRaid()
	if A.on and GetNumRaidMembers() == 0 and GetNumPartyMembers() > 0 and IsPartyLeader() then ConvertToRaid() end
end

local function invite(name)
	if GetNumRaidMembers() >= RAID_MAX then
		once("full", W.LF("Auto invite: the raid is full (%s wasn't invited).", name))
		return
	end
	recent[name] = GetTime()
	W.Print(W.LF("Auto invite: inviting %s.", name))
	InviteByName(name)
end

-- someone asked for an invite
function A:Want(name)
	if not A.on or type(name) ~= "string" or name == "" or name == UnitName("player") or inGroup(name) then return end
	local now = GetTime()
	if recent[name] and now - recent[name] < AGAIN then return end
	if not canInvite() then
		once("lead", W.LF("Auto invite: only the group leader (or a raid assistant) can invite (%s wasn't invited).", name))
		return
	end
	-- in a party: it becomes a raid first, and the invite waits for that
	if GetNumRaidMembers() == 0 and GetNumPartyMembers() > 0 then
		toRaid()
		for i = 1, getn(pending) do
			if pending[i].name == name then return end
		end
		if getn(pending) < RAID_MAX then tinsert(pending, { name = name, at = now }) end
		return
	end
	invite(name)
end

StaticPopupDialogs["WHODIDIT_AUTOINV"] = {
	text = "Auto invite posts one line in guild chat (whisper me + for an invite) and invites everyone who whispers you + or types + in guild chat. A party becomes a raid by itself.\n\nTurn it on? (It's off again after every login.)",
	button1 = ACCEPT, button2 = CANCEL,
	OnAccept = function()
		WhoDidItDB.opts.autoInvAsked = true
		A:Set(true)
	end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}

function A:Post()
	W:Send({ GUILD_LINE }, "GUILD")
end

function A:Set(on)
	if on and not WhoDidItDB.opts.autoInvAsked then
		W.ShowPopup("WHODIDIT_AUTOINV")
		return
	end
	A.on = on and true or false
	pending = {}
	if A.on then
		W.Print("Auto invite |cff33ff33on|r: whisper + (or + in guild chat) gets a raid invite. |cffffd100/wdi inv off|r stops it.")
		A:Post()
		toRaid()
	else
		W.Print("Auto invite |cffff9933off|r.")
	end
end

function A:Slash(rest)
	rest = strlower(rest or "")
	if rest == "on" then A:Set(true)
	elseif rest == "off" then A:Set(false)
	elseif rest == "post" then
		if A.on then A:Post() else A:Set(true) end
	elseif rest == "" then A:Set(not A.on)
	else W.Print("Usage: /wdi inv on|off|post (post: the guild line again)") end
end

W:On("CHAT_MSG_WHISPER", function(msg, sender) if A.on and isPlus(msg) then A:Want(sender) end end)
W:On("CHAT_MSG_GUILD", function(msg, sender) if A.on and isPlus(msg) then A:Want(sender) end end)
W:On("PARTY_MEMBERS_CHANGED", toRaid)

W:Every(1, function()
	if not A.on then return end
	local now = GetTime()
	for n, t in pairs(recent) do
		if now - t > AGAIN then recent[n] = nil end
	end
	if GetNumRaidMembers() > 0 then
		-- the raid is there: everyone who was waiting
		while pending[1] do
			local p = tremove(pending, 1)
			if not inGroup(p.name) and canInvite() then invite(p.name) end
		end
	else
		for i = getn(pending), 1, -1 do
			if now - pending[i].at > WAIT then tremove(pending, i) end
		end
	end
end)
