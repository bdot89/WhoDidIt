--[[--------------------------------------------------------------------
	WhoDidIt - auto invite

	/wdi inv or the Invite button opens the panel (on / off, which guild ranks);
	/wdi inv on|off switches it. While it's on, everyone who whispers you
	+ (any number of them, spaces allowed: "+", "+++", "+ ++") or types it
	in guild chat gets an invite. Solo, the first one to accept makes a
	party, and WhoDidIt turns it into a raid straight away; the rest are
	invited into the raid. Turning it on posts one line in guild chat
	(/wdi inv post posts it again). It's off at every login, and the first
	time it asks. Inviting needs the group leader (or a raid assistant).
	A guild rank can be required: that rank and every one above it.
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
local GUILD_LINE_RANK = "[WhoDidIt] Raid invites are open for %s and above: whisper me + for an invite."

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

------------------------------------------------------------------ guild ranks
-- From the guild roster (GetGuildRosterInfo: name, rank name, rank index; 0 = guild master),
-- read again on every GUILD_ROSTER_UPDATE, so it always matches the guild's own ranks.
-- WhoDidItDB.opts.autoInvRank = the lowest rank index invited (that rank and every one
-- above it), nil = anyone who asks, guild or not.
local ranks, rankOf = {}, {}   -- index -> rank name; member -> index (the whole roster, rebuilt each time)
local waitRank = {}            -- name -> GetTime(): asked while the roster didn't know them yet (30 s)

local function readRoster()
	local r, m = {}, {}
	for i = 1, (GetNumGuildMembers(1) or 0) do
		local name, rank, idx = GetGuildRosterInfo(i)
		if name and idx then
			m[name] = idx
			if rank then r[idx] = rank end
		end
	end
	ranks, rankOf = r, m
end
function A.Ranks() return ranks end
function A.MinRank() return WhoDidItDB and WhoDidItDB.opts.autoInvRank end
function A.RankName(idx) return ranks[idx] or ("#" .. ((idx or 0) + 1)) end

-- someone asked for an invite (checked: the roster was read again after they asked)
function A:Want(name, checked)
	if not A.on or type(name) ~= "string" or name == "" or name == UnitName("player") or inGroup(name) then return end
	local now = GetTime()
	if recent[name] and now - recent[name] < AGAIN then return end
	if not canInvite() then
		once("lead", W.LF("Auto invite: only the group leader (or a raid assistant) can invite (%s wasn't invited).", name))
		return
	end
	local min = A.MinRank()
	if min then
		local idx = rankOf[name]
		if not idx and not checked and IsInGuild() then
			-- not in the list we have: ask the server for a fresh one, then decide
			if not waitRank[name] then waitRank[name] = now end
			if GuildRoster then GuildRoster() end
			return
		end
		if not idx or idx > min then
			recent[name] = now   -- (said once a minute at most)
			W.Print(W.LF("Auto invite: %s isn't %s or above in the guild (not invited).", name, A.RankName(min)))
			return
		end
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
	local min = A.MinRank()
	W:Send({ min and string.format(GUILD_LINE_RANK, A.RankName(min)) or GUILD_LINE }, "GUILD")
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
		if IsInGuild() and GuildRoster then GuildRoster() end
		A:Post()
		toRaid()
	else
		W.Print("Auto invite |cffff9933off|r.")
	end
	A:Update()
end

-- the lowest guild rank invited (nil: anyone)
function A:SetRank(idx)
	WhoDidItDB.opts.autoInvRank = idx
	A:Update()
end

function A:Slash(rest)
	rest = strlower(rest or "")
	if rest == "on" then A:Set(true)
	elseif rest == "off" then A:Set(false)
	elseif rest == "post" then
		if A.on then A:Post() else A:Set(true) end
	elseif rest == "" then A:TogglePanel()
	else W.Print("Usage: /wdi inv on|off|post (post: the guild line again)") end
end

W:On("GUILD_ROSTER_UPDATE", function()
	readRoster()
	-- the ones who asked while the roster didn't know them yet
	local list = waitRank
	waitRank = {}
	local now = GetTime()
	for n, t in pairs(list) do
		if now - t < 30 then A:Want(n, true) end
	end
	if A.panel and A.panel:IsVisible() then A:Refresh() end
end)

------------------------------------------------------------------ the panel
-- /wdi inv or the Invite button in the window's header: on / off at a glance, the guild
-- line again, and which guild ranks are invited (a rank lets in every rank above it).

local MAX_ROWS = 11   -- "anyone" + up to 10 guild ranks

local function button(parent, w, h)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	if W.UI and W.UI.Skin then W.UI.Skin(b) end
	b:SetWidth(w)
	b:SetHeight(h)
	if W.UI and W.UI.BtnFont then
		W.UI.BtnFont(b, 2)
	else
		if b.SetTextFontObject then b:SetTextFontObject(W.FontO("GameFontNormalSmall")) end
		if b.SetHighlightFontObject then b:SetHighlightFontObject(W.FontO("GameFontHighlightSmall")) end
	end
	return b
end

function A:BuildPanel()
	local p = CreateFrame("Frame", "WhoDidItAutoInvitePanel", UIParent)
	p:SetWidth(260)
	p:SetHeight(120 + MAX_ROWS * 20)
	p:SetFrameStrata("DIALOG")
	p:SetToplevel(true)
	p:EnableMouse(true)
	p:SetMovable(true)
	p:RegisterForDrag("LeftButton")
	p:SetScript("OnDragStart", function() this:StartMoving() end)
	p:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
	-- the window's flat look (UI.lua); the tooltip frame without it
	local UI = W.UI
	if UI and UI.Flat then
		UI.Flat(p, UI.COL.frame, UI.COL.frameEdge)
	else
		p:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		p:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
		p:SetBackdropBorderColor(0.55, 0.55, 0.6, 1)
	end
	p:Hide()
	tinsert(UISpecialFrames, "WhoDidItAutoInvitePanel")

	local title = p:CreateFontString(nil, "OVERLAY", W.FontT("GameFontNormal"))
	title:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -12)
	title:SetText(W.L("Auto invite"))
	if UI and UI.CloseButton then
		UI.CloseButton(p)
	else
		local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
		close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -2, -2)
	end

	p.onBtn = button(p, 236, 22)
	p.onBtn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	p.onBtn:SetScript("OnClick", function() A:Set(not A.on) end)

	p.postBtn = button(p, 236, 20)
	p.postBtn:SetPoint("TOPLEFT", p.onBtn, "BOTTOMLEFT", 0, -4)
	p.postBtn:SetScript("OnClick", function() A:Slash("post") end)

	p.head = p:CreateFontString(nil, "OVERLAY", W.FontT("GameFontNormalSmall"))
	p.head:SetPoint("TOPLEFT", p.postBtn, "BOTTOMLEFT", 0, -10)
	p.head:SetText(W.L("Who gets invited:"))

	p.rows = {}
	for i = 1, MAX_ROWS do
		local r = button(p, 236, 18)
		r:SetPoint("TOPLEFT", p.head, "BOTTOMLEFT", 0, -4 - (i - 1) * 20)
		r:SetScript("OnClick", function() A:SetRank(this.idx) end)
		r:Hide()
		p.rows[i] = r
	end

	p.foot = p:CreateFontString(nil, "OVERLAY", W.FontT("GameFontDisableSmall"))
	p.foot:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 12, 10)
	p.foot:SetWidth(236)
	p.foot:SetJustifyH("LEFT")
	A.panel = p
	return p
end

function A:Refresh()
	local p = A.panel
	if not p then return end
	p.onBtn:SetText(A.on and W.L("Auto invite: |cff33ff33ON|r") or W.L("Auto invite: |cffff5555OFF|r"))
	p.postBtn:SetText(W.L("Post the invite line in guild chat"))
	local min = A.MinRank()
	local list = {}   -- rows: nil = anyone, then the guild's ranks from the top
	local top = -1
	for idx in pairs(ranks) do if idx > top then top = idx end end
	for idx = 0, top do
		if ranks[idx] and getn(list) < MAX_ROWS - 1 then tinsert(list, idx) end
	end
	for i = 1, MAX_ROWS do
		local r = p.rows[i]
		if i == 1 then
			r.idx = nil
			r:SetText(((min == nil) and "|cff33ff33> " or "|cffaaaaaa") .. W.L("Anyone who asks (guild or not)") .. "|r")
			r:Show()
		elseif list[i - 1] then
			local idx = list[i - 1]
			r.idx = idx
			local on = (min ~= nil and idx <= min)
			r:SetText(((min == idx) and "|cff33ff33> " or (on and "|cffffffff" or "|cffaaaaaa")) .. W.LF("%s and above", ranks[idx]) .. "|r")
			r:Show()
		else
			r:Hide()
		end
	end
	if top < 0 then
		p.foot:SetText(W.L("No guild ranks yet: the guild list is still loading (or you're not in a guild)."))
	else
		p.foot:SetText(W.L("The ranks come from your guild. A rank lets in every rank above it too; anyone below it, or outside the guild, isn't invited."))
	end
end

function A:TogglePanel(anchor)
	local p = A.panel or A:BuildPanel()
	if p:IsVisible() then p:Hide() return end
	if IsInGuild() and GuildRoster then GuildRoster() end
	readRoster()
	p:ClearAllPoints()
	if anchor then p:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4) else p:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
	A:Refresh()
	p:Show()
end

-- the Invite button in WhoDidIt's header (left of the language flags): on / off at a glance
local function headerButton()
	local UI = W.UI
	if A.btn or not (UI and UI.frame) then return end
	local b = button(UI.frame, 100, 18)
	b.wdiLevel = 2
	if UI.flagBar then b:SetPoint("RIGHT", UI.flagBar, "LEFT", -150, 0)
	else b:SetPoint("TOPRIGHT", UI.frame, "TOPRIGHT", -150, -34) end
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function()
		if arg1 == "RightButton" then A:Set(not A.on) else A:TogglePanel(this) end
	end)
	b:SetScript("OnEnter", function()
		W.TT:SetOwner(this, "ANCHOR_BOTTOMLEFT")
		W.TT:SetText(W.L("Auto invite"), 1, 0.82, 0)
		W.TT:AddLine(W.L("Whisper + (or + in guild chat) gets a raid invite."), 0.9, 0.9, 0.9, 1)
		local min = A.MinRank()
		W.TT:AddLine(min and W.LF("Invited: %s and above", A.RankName(min)) or W.L("Invited: anyone who asks"), 0.9, 0.9, 0.9)
		W.TT:AddLine(W.L("Click: the auto invite panel   Right-click: on / off"), 0.6, 0.6, 0.6)
		W.TT:Show()
	end)
	b:SetScript("OnLeave", function() W.TT:Hide() end)
	A.btn = b
end

function A:Update()
	headerButton()
	if A.btn then A.btn:SetText(A.on and W.L("Invite: |cff33ff33ON|r") or W.L("Invite: |cff888888off|r")) end
	if A.panel and A.panel:IsVisible() then A:Refresh() end
end
W:On("PLAYER_ENTERING_WORLD", function()
	A:Update()
	if IsInGuild() and GuildRoster then GuildRoster() end
end)

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
