--[[--------------------------------------------------------------------
	WhoDidIt - auto master looting

	While you're the master looter and it's switched on, every grey, white
	and green item (bind on pickup too) in a loot window is handed out
	straight away - to you, or to a raid member you pick - plus raid mats
	that are blue or purple (scraps, AQ idols, cores, Elementium). Epics
	are never given out: you get a warning and a sound instead.

	"If my bags are full": loot meant for you goes to a backup player
	once your bags run out of space. So someone else can collect all the
	trash loot, or you can collect it for them.

	The button in the title bar shows whether it's on; click it to pick
	who gets the loot. Same job as the AutoMasterLooter addon (by balake).
----------------------------------------------------------------------]]

local W = WhoDidIt
local A = {}
W.AutoML = A

local getn, tinsert = table.getn, table.insert

-- blue / purple items that are handed out anyway (raid mats)
A.ALWAYS = {
	"Wartorn Plate Scrap", "Wartorn Chain Scrap", "Wartorn Leather Scrap", "Wartorn Cloth Scrap",
	"Frozen Rune", "Elementium Ore", "Fiery Core", "Lava Core",
	"Idol of Death", "Idol of Life", "Idol of Night", "Idol of Rebirth",
	"Idol of Strife", "Idol of War", "Idol of the Sage", "Idol of the Sun",
}
-- greys / whites / greens that are left for you to hand out by hand
A.NEVER = {
	"Tome of Tranquilizing Shot", "Onyxia Hide Backpack", "Mr. Bigglesworth",
	"Hazza'rah's Dream Thread", "Gri'lek's Blood", "Wushoolay's Mane", "Renataki's Tooth",
	"Dream Frog", "Infinite Frog",
	"Blue Sack of Gems", "Gray Sack of Gems", "Green Sack of Gems", "Red Sack of Gems", "Yellow Sack of Gems",
}
local QUALITY = { [0] = "|cff9d9d9dgrey|r", "|cffffffffwhite|r", "|cff1eff00green|r", "|cff0070ddblue|r", "|cffa335eepurple|r" }

local function db()
	local d = WhoDidItDB.aml
	if type(d) ~= "table" then
		d = {}
		WhoDidItDB.aml = d
	end
	if d.maxQuality == nil then d.maxQuality = 2 end   -- up to green
	if type(d.always) ~= "table" then
		d.always = {}
		for i = 1, getn(A.ALWAYS) do d.always[A.ALWAYS[i]] = true end
	end
	if type(d.never) ~= "table" then
		d.never = {}
		for i = 1, getn(A.NEVER) do d.never[A.NEVER[i]] = true end
	end
	return d
end
A.DB = db

function A:On() return WhoDidItDB and db().on and true or false end
function A:Target() return WhoDidItDB and db().to end         -- nil = you
function A:Backup() return WhoDidItDB and db().backup end     -- nil = nobody

function A.Who(name)
	return name or "you"
end

local function changed()
	if W.UI and W.UI.UpdateAML then W.UI:UpdateAML() end
	if A.panel and A.panel:IsVisible() then A:RefreshPanel() end
end

function A:SetOn(on)
	db().on = on and true or false
	W.Print("Auto master looting " .. (db().on and ("|cff33ff33on|r - greys, whites and greens go to |cffffffff" .. A.Who(db().to) .. "|r") or "|cffff5555off|r") .. ".")
	changed()
end

function A:SetTarget(name)
	if name == UnitName("player") then name = nil end
	db().to = name
	if name and db().backup == name then db().backup = nil end
	changed()
end

function A:SetBackup(name)
	if name == UnitName("player") then name = nil end
	db().backup = name
	changed()
end

------------------------------------------------------------------ handing out

local function freeBagSlots()
	local free = 0
	for bag = 0, 4 do
		local n = GetContainerNumSlots(bag) or 0
		for slot = 1, n do
			if not GetContainerItemLink(bag, slot) then free = free + 1 end
		end
	end
	return free
end
A.FreeBagSlots = freeBagSlots

local warned = {}

local function onLoot()
	if not A:On() or IsAddOnLoaded("AutoMasterLooter") then return end
	local method, partyML = GetLootMethod()
	if method ~= "master" or partyML ~= 0 then return end   -- only when you're the master looter
	local d = db()
	local me = UnitName("player")
	-- who can receive loot from this corpse: name -> candidate index
	local cand = {}
	for i = 1, 40 do
		local n = GetMasterLootCandidate(i)
		if n then cand[n] = i end
	end
	local to = d.to or me
	if not cand[to] then
		if d.to and not warned[d.to] then
			warned[d.to] = true
			W.Print("|cffff9933" .. d.to .. " can't receive this loot (not here or too far away) - it goes to you instead.|r")
		end
		to = me
	end
	local backup = d.backup and cand[d.backup] and d.backup
	local free = (to == me) and freeBagSlots() or 99
	local epics = {}
	for slot = 1, GetNumLootItems() do
		if LootSlotIsItem(slot) then
			local _, name, _, quality = GetLootSlotInfo(slot)
			if name and quality then
				local give = (quality <= d.maxQuality and not d.never[name]) or d.always[name]
				if give then
					local who = to
					if who == me and free <= 0 and backup then who = backup end
					if cand[who] then
						GiveMasterLoot(slot, cand[who])
						if who == me then free = free - 1 end
					end
				elseif quality >= 4 then
					tinsert(epics, name)
				end
			end
		end
	end
	if getn(epics) > 0 then
		W.Print("|cffa335eeEpic inside!|r " .. table.concat(epics, ", "))
		PlaySound("AuctionWindowClose")
	end
	if to == me and free <= 0 and not backup and d.backup == nil and not warned.bags then
		warned.bags = true
		W.Print("|cffff9933Your bags are full.|r Pick someone under \"If my bags are full\" (title bar button) to send the loot to them instead.")
	end
end

W:On("LOOT_OPENED", onLoot)

------------------------------------------------------------------ picker panel

local function roster()
	local list = {}
	local n = GetNumRaidMembers()
	if n > 0 then
		for i = 1, n do
			local name, _, _, _, _, class = GetRaidRosterInfo(i)
			if name then tinsert(list, { name, class }) end
		end
	else
		for i = 1, GetNumPartyMembers() do
			local name = UnitName("party" .. i)
			local _, class = UnitClass("party" .. i)
			if name then tinsert(list, { name, class }) end
		end
	end
	table.sort(list, function(a, b) return a[1] < b[1] end)
	return list
end

local COLS, ROWS, CW, CH = 4, 11, 92, 18

local function makeButton(parent, text, w, h)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	if W.UI and W.UI.Skin then W.UI.Skin(b) end
	b:SetWidth(w)
	b:SetHeight(h)
	b:SetText(text)
	if b.SetTextFontObject then b:SetTextFontObject(GameFontNormalSmall) end
	if b.SetHighlightFontObject then b:SetHighlightFontObject(GameFontHighlightSmall) end
	return b
end

local function tip(b, title, lines)
	b:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 0.82, 0)
		local l = (type(lines) == "function") and lines() or lines
		for i = 1, getn(l) do GameTooltip:AddLine(l[i], 0.9, 0.9, 0.9, 1) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function A:BuildPanel()
	local p = CreateFrame("Frame", "WhoDidItAutoLootPanel", UIParent)
	p:SetWidth(COLS * (CW + 4) + 20)
	p:SetHeight(ROWS * (CH + 2) + 132)
	p:SetFrameStrata("DIALOG")
	p:SetToplevel(true)
	p:EnableMouse(true)
	p:SetMovable(true)
	p:RegisterForDrag("LeftButton")
	p:SetScript("OnDragStart", function() this:StartMoving() end)
	p:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
	p:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	p:SetBackdropColor(0.04, 0.04, 0.06, 0.97)
	p:SetBackdropBorderColor(0.55, 0.55, 0.6, 1)
	p:Hide()
	-- a solid fill, so nothing behind shows through
	local fill = p:CreateTexture(nil, "BACKGROUND")
	fill:SetTexture(0.04, 0.04, 0.06, 1)
	fill:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -4)
	fill:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -4, 4)
	tinsert(UISpecialFrames, "WhoDidItAutoLootPanel")

	local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -12)
	title:SetText("Auto master looting")
	local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -2, -2)

	p.status = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	p.status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	p.status:SetWidth(COLS * (CW + 4) - 4)
	p.status:SetJustifyH("LEFT")

	-- on / off, then which list the names below set
	p.onBtn = makeButton(p, "Turn on", 110, 20)
	p.onBtn:SetPoint("TOPLEFT", p.status, "BOTTOMLEFT", 0, -8)
	p.onBtn:SetScript("OnClick", function() A:SetOn(not A:On()) end)
	tip(p.onBtn, "On / off", { "On: while you're the master looter, greys, whites and greens", "(and the raid mats below) are handed out as soon as you open a corpse.", "Off: nothing happens - loot as normal." })

	p.toBtn = makeButton(p, "Loot goes to", 120, 20)
	p.toBtn:SetPoint("LEFT", p.onBtn, "RIGHT", 6, 0)
	p.toBtn:SetScript("OnClick", function() A.mode = "to"; A:RefreshPanel() end)
	tip(p.toBtn, "Loot goes to", { "Pick who receives the auto-looted items: you, or anyone in the raid.", "They need to be close enough to the corpse to receive loot." })

	p.bkBtn = makeButton(p, "If my bags are full", 140, 20)
	p.bkBtn:SetPoint("LEFT", p.toBtn, "RIGHT", 6, 0)
	p.bkBtn:SetScript("OnClick", function() A.mode = "backup"; A:RefreshPanel() end)
	tip(p.bkBtn, "If my bags are full", { "When the loot goes to you and your bags run out of space,", "it goes to this player instead. Nobody = it stays on the corpse." })

	p.hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	p.hint:SetPoint("TOPLEFT", p.onBtn, "BOTTOMLEFT", 0, -8)
	p.hint:SetJustifyH("LEFT")

	p.cells = {}
	for i = 1, COLS * ROWS do
		local c = makeButton(p, "", CW, CH)
		local col, row = math.mod(i - 1, COLS), math.floor((i - 1) / COLS)
		c:SetPoint("TOPLEFT", p.hint, "BOTTOMLEFT", col * (CW + 4), -6 - row * (CH + 2))
		c:SetScript("OnClick", function()
			if A.mode == "backup" then A:SetBackup(this.who) else A:SetTarget(this.who) end
		end)
		c:Hide()
		p.cells[i] = c
	end

	p.foot = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	p.foot:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 12, 10)
	p.foot:SetWidth(COLS * (CW + 4) - 4)
	p.foot:SetJustifyH("LEFT")
	p.foot:SetText("Only works while you're the master looter. Epics are never handed out - you get a warning.\n"
		.. "Always / never lists: /wdi aml always <item>, /wdi aml never <item>, /wdi aml list")

	A.panel = p
	A.mode = "to"
	return p
end

function A:RefreshPanel()
	local p = A.panel
	if not p then return end
	local d = db()
	p.status:SetText(d.on
		and ("|cff33ff33On.|r Greys, whites and greens go to |cffffffff" .. A.Who(d.to) .. "|r"
			.. (d.backup and ("; when your bags are full, to |cffffffff" .. d.backup .. "|r") or "") .. ".")
		or "|cffff5555Off.|r Turn it on to hand out trash loot automatically while you're the master looter.")
	p.onBtn:SetText(d.on and "|cffff5555Turn off|r" or "|cff33ff33Turn on|r")
	if A.mode == "backup" then p.bkBtn:LockHighlight(); p.toBtn:UnlockHighlight() else p.toBtn:LockHighlight(); p.bkBtn:UnlockHighlight() end
	p.hint:SetText(A.mode == "backup" and "Click who gets the loot when your bags are full:" or "Click who gets the auto-looted items:")

	local list = roster()
	local me = UnitName("player")
	local cur = (A.mode == "backup") and d.backup or d.to
	local entries = { { nil, nil, (A.mode == "backup") and "Nobody" or "Me" } }
	for i = 1, getn(list) do
		if list[i][1] ~= me then tinsert(entries, { list[i][1], list[i][2] }) end
	end
	for i = 1, getn(p.cells) do
		local c, e = p.cells[i], entries[i]
		if e then
			c.who = e[1]
			c:SetText(e[3] or W.CName(e[1], e[2]))
			if (cur == e[1]) then c:LockHighlight() else c:UnlockHighlight() end
			c:Show()
		else
			c:Hide()
		end
	end
	if getn(list) == 0 then p.hint:SetText(p.hint:GetText() .. "  |cff888888(join a group to see raid members)|r") end
end

-- open / close the picker under the title bar button
function A:TogglePanel(anchor)
	local p = A.panel or A:BuildPanel()
	if p:IsVisible() then p:Hide() return end
	p:ClearAllPoints()
	if anchor then p:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4) else p:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
	A:RefreshPanel()
	p:Show()
end

W:On("RAID_ROSTER_UPDATE", function() if A.panel and A.panel:IsVisible() then A:RefreshPanel() end end)
W:On("PARTY_MEMBERS_CHANGED", function() if A.panel and A.panel:IsVisible() then A:RefreshPanel() end end)

------------------------------------------------------------------ commands + hand-over

function A:Slash(rest)
	local _, _, cmd, arg = string.find(rest or "", "^(%S*)%s*(.-)%s*$")
	cmd = string.lower(cmd or "")
	local d = db()
	if cmd == "" then
		A:SetOn(not d.on)
	elseif cmd == "on" or cmd == "off" then
		A:SetOn(cmd == "on")
	elseif cmd == "to" then
		A:SetTarget(arg ~= "" and string.lower(arg) ~= "me" and arg or nil)
		W.Print("Auto-looted items go to |cffffffff" .. A.Who(d.to) .. "|r.")
	elseif cmd == "backup" then
		A:SetBackup(arg ~= "" and string.lower(arg) ~= "none" and arg or nil)
		W.Print("When your bags are full, loot goes to |cffffffff" .. (d.backup or "nobody") .. "|r.")
	elseif cmd == "always" or cmd == "never" then
		if arg == "" then W.Print("Usage: /wdi aml " .. cmd .. " <exact item name>") return end
		local other = (cmd == "always") and "never" or "always"
		if d[cmd][arg] then d[cmd][arg] = nil else d[cmd][arg] = true; d[other][arg] = nil end
		W.Print(arg .. (d[cmd][arg] and (" will " .. ((cmd == "always") and "always be handed out" or "never be handed out")) or (" removed from the " .. cmd .. " list")) .. ".")
	elseif cmd == "list" then
		local function keys(t) local l = {}; for k in pairs(t) do tinsert(l, k) end; table.sort(l); return table.concat(l, ", ") end
		W.Print("Handed out: everything up to " .. QUALITY[d.maxQuality] .. ", except the never list.")
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ff33Always:|r " .. keys(d.always))
		DEFAULT_CHAT_FRAME:AddMessage("|cffff7777Never:|r " .. keys(d.never))
	else
		W.Print("/wdi aml - on/off,  /wdi aml to <name|me>,  /wdi aml backup <name|none>,  /wdi aml always|never <item>,  /wdi aml list")
	end
	changed()
end

-- /automl for anyone used to AutoMasterLooter (not while it's still loaded)
if not IsAddOnLoaded("AutoMasterLooter") then
	SLASH_WHODIDITAML1 = "/automl"
	SLASH_WHODIDITAML2 = "/automasterlooter"
	SlashCmdList["WHODIDITAML"] = function(msg) A:Slash(msg) end
end

local handedOver
W:On("PLAYER_ENTERING_WORLD", function()
	if handedOver or not IsAddOnLoaded("AutoMasterLooter") then return end
	handedOver = true
	W:AskHandover("AutoMasterLooter", "auto master looting (the Auto-loot button in its title bar)")
end)
