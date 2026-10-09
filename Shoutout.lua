--[[--------------------------------------------------------------------
	WhoDidIt - shout-outs: "Name & Shame" and "Big Them Up" awards built
	from a fight report, posted to a designated chat channel
----------------------------------------------------------------------]]

local W = WhoDidIt
local S = {}
W.Shout = S

local floor = math.floor
local getn = table.getn
local FmtNum = W.FmtNum
local FmtTime = W.FmtTime

S.CHANNELS = { "RAID", "RAID_WARNING", "PARTY", "GUILD", "OFFICER", "SAY", "YELL", "SELF" }
S.LABELS = {
	RAID = "Raid", RAID_WARNING = "Raid Warning", PARTY = "Party", GUILD = "Guild",
	OFFICER = "Officer", SAY = "Say", YELL = "Yell", SELF = "Only me",
}

local MAX_SHAME  = 7    -- header, top 3, up to 3 awards (chat stays readable)
local MAX_PRAISE = 6

-- every award has a few names; one is picked at random each post so the
-- shout-outs stay fresh. Letters, spaces, ' and & only (the title colouring
-- stops at anything else), 31 characters at most.
local TITLES = {
	-- name & shame
	junkie  = { "Threat Junkie", "Aggro Magnet", "Tank Wannabe", "Boss's New Best Friend", "Threat Meter Ignorer" },
	floor   = { "Floor Inspector", "Carpet Tester", "Dirt Nap Champion", "Spirit Healer's Regular", "Professional Corpse", "First Class to the Graveyard" },
	fire    = { "Fire Enthusiast", "Puddle Jumper", "Bad Stuff Connoisseur", "Floor Is Lava Champion", "Hot Tub Enjoyer" },
	bomb    = { "Bomb Squad", "Walking Disaster", "Human Grenade", "Friendly Fire Expert" },
	afk     = { "AFK Award", "Screensaver", "Statue of the Week", "Raid Decoration" },
	slacker = { "Consume Slacker", "Raiding Naked", "Buffless Wonder", "Too Cheap for Flasks" },
	trophy  = { "Participation Trophy", "Pacifist", "Gentle Soul", "Damage Optional" },
	thinice = { "Living on the Edge", "Thin Ice", "Threat Tightrope" },
	tankcos = { "Tank Cosplayer", "Off Tank Volunteer", "Boss Babysitter" },
	chewtoy = { "Chew Toy", "Punching Bag", "Boss's Favourite Snack" },
	hoarder = { "Potion Hoarder", "Died Rich", "Saving It for Later" },
	splat   = { "Splattered", "One Shot Wonder", "Flattened", "Pancake of the Day" },
	glass   = { "Glass Cannon", "All Gas No Brakes", "Pumped Then Dumped" },
	-- big them up
	life    = { "Lifesaver", "Guardian Angel", "Clutch God", "Raid Insurance" },
	dmg     = { "Damage King", "Big Pumper", "Meter Melter", "Top of the Charts" },
	heal    = { "Top Healer", "Green Machine", "Health Bar Hero", "Spirit Healer's Rival" },
	wall    = { "Iron Wall", "Unbreakable", "Brick Wall", "Boss's Worst Nightmare" },
	busy    = { "Never Stops", "Energizer Bunny", "Button Masher", "No Rest Days" },
	clean   = { "Flawless", "Clean Hands", "Not a Scratch" },
	bighit  = { "Biggest Hit", "One Punch", "Heavy Hitter" },
	bigheal = { "Biggest Heal", "Mega Heal", "Big Splash" },
	crit    = { "Crit Machine", "Lucky Dice", "Crit Happens" },
	bossdmg = { "Boss Specialist", "Eyes on the Prize", "Boss Hunter" },
	last    = { "Last One Standing", "Turned Off the Lights", "Final Boss of the Raid" },
	pharm   = { "Walking Pharmacy", "Potion Sommelier", "Came Prepared" },
	kick    = { "Kick Master", "Silencer", "Spell Thief" },
	cleanse = { "Cleanser", "Curse Janitor", "Dispel Machine" },
	tranq   = { "Tranq Sniper", "Frenzy Fixer", "Calm Bringer" },
}
S.TITLES = TITLES

local function title(key)
	local l = TITLES[key]
	return l[math.random(getn(l))]
end

local function shuffle(l)
	for i = getn(l), 2, -1 do
		local j = math.random(i)
		l[i], l[j] = l[j], l[i]
	end
end

-- the main awards first, then up to 2 extra ones picked at random, within max
local function fill(out, main, extra, max)
	shuffle(extra)
	local room = max - getn(out)
	local nExtra = math.min(getn(extra), 1, math.max(0, room))
	local nMain = math.min(getn(main), room - nExtra)
	for i = 1, nMain do tinsert(out, main[i]) end
	for i = 1, nExtra do tinsert(out, extra[i]) end
end

------------------------------------------------------------------ channel handling

function S:Channel()
	return WhoDidItDB.opts.shoutChannel or "RAID"
end

function S:ChannelLabel(ch)
	ch = ch or S:Channel()
	if string.sub(ch, 1, 1) == "#" then return string.sub(ch, 2) end
	return S.LABELS[ch] or ch
end

-- next channel (back = the previous one)
function S:CycleChannel(back)
	local list = {}
	for i = 1, getn(S.CHANNELS) do list[i] = S.CHANNELS[i] end
	if WhoDidItDB.opts.customChannel then tinsert(list, "#" .. WhoDidItDB.opts.customChannel) end
	local cur = S:Channel()
	local n = getn(list)
	local nxt = list[1]
	for i = 1, n do
		if list[i] == cur then
			if back then nxt = list[i - 1] or list[n] else nxt = list[i + 1] or list[1] end
		end
	end
	WhoDidItDB.opts.shoutChannel = nxt
	return nxt
end

-- accepts raid / rw / party / guild / officer / say / yell / self or a custom channel name
function S:SetChannel(arg)
	local a = strlower(arg or "")
	local map = {
		raid = "RAID", rw = "RAID_WARNING", warning = "RAID_WARNING", raidwarning = "RAID_WARNING",
		party = "PARTY", guild = "GUILD", officer = "OFFICER", say = "SAY", yell = "YELL",
		self = "SELF", me = "SELF",
	}
	if a == "" then return S:Channel() end
	if map[a] then
		WhoDidItDB.opts.shoutChannel = map[a]
	else
		WhoDidItDB.opts.customChannel = arg
		WhoDidItDB.opts.shoutChannel = "#" .. arg
	end
	return WhoDidItDB.opts.shoutChannel
end

local function clean(s)
	s = string.gsub(s or "", "|c%x%x%x%x%x%x%x%x", "")
	s = string.gsub(s, "|r", "")
	s = string.gsub(s, "|", "/")
	return s
end

------------------------------------------------------------------ chat colours

-- one palette for every post: tag red, titles gold, times light blue, numbers
-- white, players in class colour, and these for names in posts
S.PALETTE = { us = "#33ff33", guild = "#ff9966", realm = "#cc99ff", boss = "#ffd100" }

local COL = { tag = "ff5555", title = "ffd100", time = "66ccff", num = "ffffff" }
local RESULT_COL = { WIPE = "ff4444", KILL = "33ff33", RESET = "ff9933" }

local function hex(class)
	local r, g, b = W.ClassRGB(class)
	return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function wrap(h, s) return "|cff" .. h .. s .. "|r" end

-- a colour map value: a class ("MAGE") or a colour ("#ff8866")
local function colourOf(v)
	if string.sub(v, 1, 1) == "#" then return string.sub(v, 2) end
	return hex(v)
end

-- phrases from the colour map that the word matcher can't find on its own
-- (several words, or an apostrophe: "Care Bears", "N'Zoth (PvE)"), by first
-- character, longest first so "N'Zoth (PvE)" wins over "N'Zoth"
local function phraseIndex(map)
	local idx = {}
	for k in pairs(map) do
		if string.find(k, "[^%w]") then
			local c = string.sub(k, 1, 1)
			idx[c] = idx[c] or {}
			tinsert(idx[c], k)
		end
	end
	for _, list in pairs(idx) do
		table.sort(list, function(a, b) return string.len(a) > string.len(b) end)
	end
	return idx
end

local function phraseAt(s, i, idx)
	local list = idx[string.sub(s, i, i)]
	if not list then return nil end
	for j = 1, getn(list) do
		local p = list[j]
		local e = i + string.len(p) - 1
		if string.sub(s, i, e) == p and not string.find(string.sub(s, e + 1, e + 1), "^%w") then return p, e end
	end
end

-- One left-to-right pass so colour codes never get coloured again:
-- [WhoDidIt] tag, "Award Title:" at the start, times, numbers, WIPE/KILL,
-- and raid members' names in their class colour. namesOnly = names only.
local function colorize(s, classes, namesOnly)
	local out = {}
	local i, n = 1, string.len(s)
	local _, e = string.find(s, "^%[WhoDidIt[^%]]*%]")
	if e then
		tinsert(out, wrap(COL.tag, string.sub(s, 1, e)))
		i = e + 1
		-- the post's kind right after the tag: "NAME & SHAME", "BIG UPS", "CONSUMES"...
		local a, b = string.find(s, "^ %u[%u &]*%u[ :]", i)
		if a then
			b = b - 1  -- leave the space / colon after the kind
			tinsert(out, " " .. (namesOnly and string.sub(s, a + 1, b) or wrap(COL.title, string.sub(s, a + 1, b))))
			i = b + 1
		end
	else
		local _, e2 = string.find(s, "^%a[%a '&]*:")
		if e2 and e2 <= 32 then
			local title = string.sub(s, 1, e2 - 1)
			if classes[title] then
				tinsert(out, wrap(colourOf(classes[title]), title) .. ":")
			elseif not namesOnly then
				tinsert(out, wrap(COL.title, title .. ":"))
			else
				tinsert(out, title .. ":")
			end
			i = e2 + 1
		end
	end
	local idx = phraseIndex(classes)
	while i <= n do
		local phrase, pe = phraseAt(s, i, idx)
		local a, b = string.find(s, "^%d+:%d%d", i)
		if phrase then
			tinsert(out, wrap(colourOf(classes[phrase]), phrase))
			i = pe + 1
		elseif a then
			local tok = string.sub(s, a, b)
			tinsert(out, namesOnly and tok or wrap(COL.time, tok))
			i = b + 1
		else
			a, b = string.find(s, "^%d+[%.]?%d*[%%kM]?", i)
			if a then
				local tok = string.sub(s, a, b)
				tinsert(out, namesOnly and tok or wrap(COL.num, tok))
				i = b + 1
			else
				a, b = string.find(s, "^[^%s%p%d]+", i)
				if a then
					local w = string.sub(s, a, b)
					if classes[w] then
						tinsert(out, wrap(colourOf(classes[w]), w))
					elseif RESULT_COL[w] and not namesOnly then
						tinsert(out, wrap(RESULT_COL[w], w))
					else
						tinsert(out, w)
					end
					i = b + 1
				else
					tinsert(out, string.sub(s, i, i))
					i = i + 1
				end
			end
		end
	end
	return table.concat(out)
end

-- splits s near position max at the last "; ", ", " or " " before it
local SEPS = { "; ", ", ", " " }
local function splitAt(s, max)
	for i = 1, getn(SEPS) do
		local sep = SEPS[i]
		local last
		local pos = 1
		while true do
			local a = string.find(s, sep, pos, true)
			if not a or a > max then break end
			last = a
			pos = a + 1
		end
		if last and last > max * 0.4 then
			return string.sub(s, 1, last - 1), string.sub(s, last + string.len(sep))
		end
	end
	return string.sub(s, 1, max), string.sub(s, max + 1)
end

-- One plain line -> one or more chat messages { coloured, plain }. A line
-- that's too long once coloured is split in two (recursively) instead of
-- losing its colours or being cut off. Chat messages max out at 255 bytes.
local function render(plain, classes, out)
	if classes then
		local c = colorize(plain, classes)
		if string.len(c) <= 255 then
			tinsert(out, { c, plain })
			return
		end
	elseif string.len(plain) <= 255 then
		tinsert(out, { nil, plain })
		return
	end
	if string.len(plain) > 50 then
		local head, tail = splitAt(plain, math.floor(string.len(plain) * 0.55))
		render(head, classes, out)
		render("   " .. tail, classes, out)
		return
	end
	-- short but still too long coloured: names only, else plain
	local c = colorize(plain, classes, true)
	tinsert(out, { (string.len(c) <= 255) and c or nil, plain })
end

-- name -> class for a fight report (used to colour names)
function S.ClassMap(rec)
	local m = {}
	for name, p in pairs(rec and rec.players or {}) do m[name] = p.class end
	-- the boss stands out from the players in every post about the fight
	if rec and rec.enc and not m[rec.enc] then m[rec.enc] = S.PALETTE.boss end
	return m
end

------------------------------------------------------------------ sending

local queue = {}
-- Colour check, per channel: every line we post (coloured or not) waits for
-- its echo - our own message showing up in that chat. If a coloured line
-- never shows up, or comes back with the colours stripped, that channel
-- gets plain text from then on (WhoDidItDB.opts.plainKinds) and the lost
-- lines are sent again in plain text. Other channels stay coloured.
local waiting = {}   -- { at, kind, colored, plain, target }, oldest first
local lastSlow   -- when the last say / yell / channel line went out

-- can this channel take coloured text?
local function colorsOK(kind)
	local o = WhoDidItDB.opts
	return o.chatColors and not (o.plainKinds and o.plainKinds[kind])
end

-- a chat that has shown one of our coloured lines takes colours: a line
-- that goes missing there later was dropped (spam limit), not uncoloured
local function confirmed(kind)
	local ok = WhoDidItDB.opts.colorsSeen
	return ok and ok[kind]
end
local function confirm(kind)
	local o = WhoDidItDB.opts
	o.colorsSeen = o.colorsSeen or {}
	o.colorsSeen[kind] = true
	if kind == "RAID_WARNING" then o.colorsSeen.RAID = true elseif kind == "RAID" then o.colorsSeen.RAID_WARNING = true end
end

local function goPlain(kind, why)
	local o = WhoDidItDB.opts
	o.plainKinds = o.plainKinds or {}
	if o.plainKinds[kind] then return end
	if confirmed(kind) then return end
	o.plainKinds[kind] = true
	W.Print("|cffff9933" .. (S.LABELS[kind] or string.lower(kind)) .. " chat " .. why
		.. ", so WhoDidIt posts plain text there from now on. Every other chat stays coloured.|r  |cff888888(/wdi colors on to try again)|r")
end

-- Sends lines to a channel (default: the designated shout channel), one
-- every 0.3s so a burst of lines doesn't trip the chat flood protection.
-- classes (optional, name -> class) turns on coloured text.
function W:Send(lines, channel, classes)
	channel = channel or S:Channel()
	local kind, target = channel, nil
	local inRaid = GetNumRaidMembers() > 0
	local inParty = GetNumPartyMembers() > 0

	if string.sub(channel, 1, 1) == "#" then
		local name = string.sub(channel, 2)
		local id = GetChannelName(name)
		if not id or id == 0 then
			W.Print("You aren't in the channel '" .. name .. "'. Type /join " .. name .. " first.")
			return
		end
		kind, target = "CHANNEL", id
	elseif kind == "RAID_WARNING" then
		local canWarn = inRaid and (IsRaidLeader() or (IsRaidOfficer and IsRaidOfficer()))
		if not canWarn then kind = "RAID" end
	end
	-- in a raid only the leader and assistants post (W.CanLead); anyone else sees it themselves
	if kind ~= "SELF" and inRaid and not W.CanLead() then
		W.LeadOnly()
		kind = "SELF"
	end
	if kind == "RAID" and not inRaid then kind = inParty and "PARTY" or "SELF" end
	if kind == "PARTY" and not inParty then kind = "SELF" end
	if (kind == "GUILD" or kind == "OFFICER") and not IsInGuild() then kind = "SELF" end

	for i = 1, getn(lines) do
		local pieces = {}
		render(clean(lines[i]), classes, pieces)
		for j = 1, getn(pieces) do
			local col, plain = pieces[j][1], pieces[j][2]
			if kind == "SELF" then
				W.Print(col or plain)
			else
				tinsert(queue, { col, plain, kind, target })
			end
		end
	end
end

W:Every(0.3, function()
	-- a coloured line that never showed up: that chat drops colour codes.
	-- Send what was lost again, in plain text.
	local now = GetTime()
	while waiting[1] and now - waiting[1].at > 8 do
		local w = tremove(waiting, 1)
		if w.colored and confirmed(w.kind) then
			-- colours work here, so the server dropped it: send it once more
			if not w.retry then tinsert(queue, 1, { w.sent, w.plain, w.kind, w.target, true }) end
		elseif w.colored then
			goPlain(w.kind, "didn't show coloured text")
			tinsert(queue, 1, { nil, w.plain, w.kind, w.target, true })
		end
	end
	local q = queue[1]
	if not q then return end
	-- say / yell / channels have a stricter spam limit: one line a second
	if (q[3] == "SAY" or q[3] == "YELL" or q[3] == "CHANNEL") and now - (lastSlow or 0) < 1 then return end
	tremove(queue, 1)
	if q[3] == "SAY" or q[3] == "YELL" or q[3] == "CHANNEL" then lastSlow = now end
	local colored = q[1] and colorsOK(q[3])
	local text = colored and q[1] or q[2]
	SendChatMessage(text, q[3], nil, q[4])
	tinsert(waiting, { at = now, kind = q[3], colored = colored, sent = text, plain = q[2], target = q[4], retry = q[5] })
end)

-- our own messages come back through these events: the line made it
local ECHO_EVENTS = {
	CHAT_MSG_GUILD = "GUILD", CHAT_MSG_OFFICER = "OFFICER", CHAT_MSG_RAID = "RAID", CHAT_MSG_RAID_LEADER = "RAID",
	CHAT_MSG_RAID_WARNING = "RAID_WARNING", CHAT_MSG_PARTY = "PARTY", CHAT_MSG_SAY = "SAY", CHAT_MSG_YELL = "YELL",
	CHAT_MSG_CHANNEL = "CHANNEL",
}
-- chat drops leading / trailing / doubled spaces, so compare without any spaces
local function squash(s) return (string.gsub(s or "", "%s+", "")) end

local function sameChat(w, k)
	-- a raid warning can come back as raid, and the other way round
	return w.kind == k or (k == "RAID" and w.kind == "RAID_WARNING") or (k == "RAID_WARNING" and w.kind == "RAID")
end

for ev, kind in pairs(ECHO_EVENTS) do
	local k = kind
	W:On(ev, function(msg, sender)
		if sender ~= UnitName("player") or not msg then return end
		local m = squash(msg)
		-- 1) our own line, word for word (not something you typed, or the rankings channel)
		for i = 1, getn(waiting) do
			local w = waiting[i]
			if sameChat(w, k) then
				if m == squash(w.sent) then
					if w.colored then confirm(w.kind) end
					tremove(waiting, i)
					return
				elseif w.colored and m == squash(w.plain) and not string.find(msg, "|c", 1, true) then
					tremove(waiting, i)
					goPlain(w.kind, "strips colours")
					return
				end
			end
		end
		-- 2) anything coloured we posted came through: colours work in this chat
		if string.find(msg, "|c", 1, true) then
			for i = 1, getn(waiting) do
				if sameChat(waiting[i], k) and waiting[i].colored then
					confirm(waiting[i].kind)
					tremove(waiting, i)
					return
				end
			end
		end
	end)
end

------------------------------------------------------------------ data helpers

local function pct(v) return floor((v or 0) * 100 + 0.5) .. "%" end

local function alive(rec, p)
	return (p.alive and p.alive > 0) and p.alive or rec.dur
end

local function dps(rec, p) return (p.dmg or 0) / alive(rec, p) end

-- name, player, value of the player with the highest score(p) (> 0)
local function best(rec, score)
	local bn, bp, bv
	for name, p in pairs(rec.players) do
		local v = score(p, name)
		if v and v > 0 and (not bv or v > bv) then bn, bp, bv = name, p, v end
	end
	return bn, bp, bv
end

local function totals(rec)
	local dmg, heal = 0, 0
	for _, p in pairs(rec.players) do
		dmg = dmg + (p.dmg or 0)
		heal = heal + (p.heal or 0)
	end
	return dmg, heal
end

local function medianDps(rec)
	local l = {}
	for _, p in pairs(rec.players) do
		if p.role == "dps" and (p.alive or 0) >= 30 then tinsert(l, dps(rec, p)) end
	end
	if getn(l) < 4 then return nil end
	table.sort(l)
	return l[math.ceil(getn(l) / 2)]
end

local function rankOf(rec, name, field)
	local l = {}
	for n, p in pairs(rec.players) do tinsert(l, { n, p[field] or 0 }) end
	table.sort(l, function(a, b) return a[2] > b[2] end)
	for i = 1, getn(l) do
		if l[i][1] == name then return i, getn(l) end
	end
end

local function blameOf(rec, name)
	for i = 1, getn(rec.blame) do
		if rec.blame[i].name == name then return rec.blame[i], i end
	end
end

-- "pulled aggro on Lucifron 2x, stood in Fire Nova (+1 more)": repeats grouped,
-- "... from Jaker" dropped so the same mistake counts once
local function groupedReasons(b, n)
	local order, count = {}, {}
	local prefix = b.name .. " "
	for i = 1, getn(b.reasons) do
		local r = b.reasons[i]
		if string.sub(r, 1, string.len(prefix)) == prefix then r = string.sub(r, string.len(prefix) + 1) end
		r = string.gsub(r, " from %S+$", "")
		if not count[r] then count[r] = 0; tinsert(order, r) end
		count[r] = count[r] + 1
	end
	local out = {}
	for i = 1, math.min(n, getn(order)) do
		local r = order[i]
		tinsert(out, r .. ((count[r] > 1) and (" " .. count[r] .. "x") or ""))
	end
	local more = getn(order) - n
	return table.concat(out, ", ") .. ((more > 0) and (" (+" .. more .. " more)") or "")
end

local function shortReasons(b, n)
	local out = {}
	for i = 1, math.min(n, getn(b.reasons)) do
		tinsert(out, (string.gsub(b.reasons[i], "^" .. b.name .. " ", "")))
	end
	return table.concat(out, "; ")
end

function S:FindPlayer(rec, name)
	if not name or name == "" then return nil end
	local low = strlower(name)
	for n in pairs(rec.players) do
		if strlower(n) == low then return n end
	end
end

local function header(kind, rec)
	return W.Analyzer.ChatHeader(kind, rec)
end

------------------------------------------------------------------ name & shame

function S:ShameLines(rec, who)
	local P = rec.players
	local out = {}

	if who then
		local p = P[who]
		local b, rank = blameOf(rec, who)
		local bits = {}
		if b and b.pts > 0 then tinsert(bits, b.pts .. " blame points (#" .. rank .. " in the raid)") end
		if (p.pulls or 0) > 0 then tinsert(bits, "pulled aggro " .. p.pulls .. "x") end
		if (p.avoidHits or 0) > 0 then
			tinsert(bits, "stood in " .. (p.worstSpell or "bad stuff") .. " - " .. p.avoidHits .. " hits, " .. FmtNum(p.avoidDmg) .. " avoidable damage")
		end
		if (p.splash or 0) > 0 then tinsert(bits, "blew up " .. p.splash .. " raider(s) with their debuff") end
		for i = 1, getn(rec.deaths) do
			local d = rec.deaths[i]
			if d.name == who then tinsert(bits, "died at " .. FmtTime(d.t) .. " (" .. d.text .. ")") break end
		end
		if p.act and p.act < 0.6 then tinsert(bits, "only active " .. pct(p.act) .. " of the fight") end
		local miss = W.Cons and W.Cons.Missing(p, rec.zone)
		if miss and getn(miss) > 0 then tinsert(bits, "no " .. table.concat(miss, ", no ")) end
		local med = medianDps(rec)
		if p.role == "dps" and med and dps(rec, p) < med * 0.6 then
			tinsert(bits, floor(dps(rec, p)) .. " DPS vs a raid median of " .. floor(med))
		end
		tinsert(out, header("NAME & SHAME: " .. who, rec))
		if getn(bits) == 0 then
			tinsert(out, who .. " was spotless this time. Nothing to shame... yet.")
		else
			-- split over two lines if it gets long
			local line = who .. ": " .. table.concat(bits, ", ")
			tinsert(out, line)
		end
		return out
	end

	tinsert(out, header("NAME & SHAME", rec))

	-- the top 3 of the blame board, each with their main reasons (repeats grouped)
	local PODIUM = { "Most to blame", "Second place", "Third place" }
	local shown = 0
	for i = 1, getn(rec.blame) do
		local b = rec.blame[i]
		if shown >= 3 or b.pts < 1 then break end
		shown = shown + 1
		tinsert(out, PODIUM[shown] .. ": " .. b.name .. " - " .. b.pts .. " pts - " .. groupedReasons(b, 2))
	end

	local main, extra = {}, {}

	local n, p, v = best(rec, function(p) return p.pulls end)
	local junkie = n
	if n then
		tinsert(main, title("junkie") .. ": " .. n .. " - ripped aggro off the tank " .. v .. "x")
	else
		local tn, tv
		for name, t in pairs(rec.threat or {}) do
			local tp = P[name]
			if tp and tp.role ~= "tank" and t.perc >= 100 and (not tv or t.perc > tv) then tn, tv = name, t.perc end
		end
		if tn then tinsert(main, title("junkie") .. ": " .. tn .. " - hit " .. tv .. "% threat, living dangerously") end
		junkie = tn
	end

	-- the deaths that were somebody's own doing (not mind control, not the mechanic, not the wipe)
	local real = {}
	for i = 1, getn(rec.deaths) do
		local d = rec.deaths[i]
		if not d.late and d.kind ~= "mc" and d.kind ~= "expected" then tinsert(real, d) end
	end
	if real[1] then
		tinsert(main, title("floor") .. ": " .. real[1].name .. " - first to die, at " .. FmtTime(real[1].t) .. " (" .. real[1].text .. ")")
	end

	n, p, v = best(rec, function(p) return p.avoidDmg end)
	if n then
		tinsert(main, title("fire") .. ": " .. n .. " - soaked " .. FmtNum(v) .. " avoidable damage (" .. (p.worstSpell or "?") .. " x" .. (p.worstHits or p.avoidHits or 0) .. ")")
	end

	n, p, v = best(rec, function(p) return p.splash end)
	if n then tinsert(main, title("bomb") .. ": " .. n .. " - took " .. v .. " raider(s) with them") end

	n, p, v = best(rec, function(p)
		if p.role ~= "tank" and p.act and p.act < 0.6 then return 1 - p.act end
	end)
	if n then tinsert(main, title("afk") .. ": " .. n .. " - only doing something " .. pct(p.act) .. " of the time") end

	local slack = W.Cons and W.Cons.Slackers(rec)
	if slack and slack[1] and getn(slack[1].missing) >= 2 then
		tinsert(main, title("slacker") .. ": " .. slack[1].name .. " - turned up without " .. table.concat(slack[1].missing, ", "))
	end

	local med = medianDps(rec)
	if med and med > 0 then
		n, p, v = best(rec, function(p)
			if p.role == "dps" and (p.alive or 0) >= 30 and dps(rec, p) < med * 0.5 then return med - dps(rec, p) end
		end)
		if n then tinsert(main, title("trophy") .. ": " .. n .. " - " .. floor(dps(rec, p)) .. " DPS (raid median " .. floor(med) .. ")") end
	end

	-- extras: two of these, picked at random, when there's room

	-- close to pulling, but didn't
	local tn, tv
	for name, t in pairs(rec.threat or {}) do
		local tp = P[name]
		if tp and tp.role ~= "tank" and name ~= junkie and t.perc >= 90 and t.perc < 100 and (not tv or t.perc > tv) then tn, tv = name, t.perc end
	end
	if tn then tinsert(extra, title("thinice") .. ": " .. tn .. " - peaked at " .. tv .. "% threat and lived to tell the tale") end

	n, p, v = best(rec, function(p) if p.role ~= "tank" and (p.aggro or 0) >= 3 then return p.aggro end end)
	if n then tinsert(extra, title("tankcos") .. ": " .. n .. " - had the boss's attention for " .. floor(v) .. " seconds") end

	n, p, v = best(rec, function(p) if p.role ~= "tank" then return p.taken end end)
	if n and v >= 5000 then tinsert(extra, title("chewtoy") .. ": " .. n .. " - took " .. FmtNum(v) .. " damage without being a tank") end

	-- died with their potion or healthstone off cooldown (not used within its cooldown)
	for i = 1, getn(real) do
		local d, item = real[i], nil
		for j = 1, getn(d.ready or {}) do
			local r = d.ready[j]
			if r[2] == "potion" then item = "their potion"
			elseif r[2] == "healthstone" and not item then item = "a healthstone" end
		end
		if item then
			tinsert(extra, title("hoarder") .. ": " .. d.name .. " - died at " .. FmtTime(d.t) .. " with " .. item .. " off cooldown")
			break
		end
	end

	local big
	for i = 1, getn(real) do
		if (real[i].killAmt or 0) >= 3000 and (not big or real[i].killAmt > big.killAmt) then big = real[i] end
	end
	if big then tinsert(extra, title("splat") .. ": " .. big.name .. " - one hit of " .. FmtNum(big.killAmt) .. " from " .. (big.killer or "something big")) end

	for i = 1, getn(real) do
		local r = rankOf(rec, real[i].name, "dmg")
		if r and r <= 3 and P[real[i].name] and P[real[i].name].role == "dps" then
			tinsert(extra, title("glass") .. ": " .. real[i].name .. " - #" .. r .. " on damage, then died at " .. FmtTime(real[i].t))
			break
		end
	end

	fill(out, main, extra, MAX_SHAME)
	if getn(out) == 1 then tinsert(out, "Nobody to shame - clean fight. Suspicious.") end
	return out
end

------------------------------------------------------------------ big them up

function S:PraiseLines(rec, who)
	local P = rec.players
	local out = {}
	local tDmg, tHeal = totals(rec)

	if who then
		local p = P[who]
		local bits = {}
		local r, of = rankOf(rec, who, "dmg")
		if (p.dmg or 0) > 0 and p.role ~= "heal" then
			tinsert(bits, "#" .. r .. " damage with " .. floor(dps(rec, p)) .. " DPS (" .. pct(p.dmg / math.max(1, tDmg)) .. " of the raid's damage)")
		end
		r, of = rankOf(rec, who, "heal")
		if (p.heal or 0) > 0 and (p.role == "heal" or r <= 5) then
			tinsert(bits, "#" .. r .. " healing with " .. FmtNum(p.heal) .. " healed (" .. pct(p.heal / math.max(1, tHeal)) .. ")")
		end
		if p.role == "tank" then tinsert(bits, "tanked " .. FmtNum(p.taken) .. " damage") end
		if (p.saves or 0) > 0 then tinsert(bits, p.saves .. " game-saving play(s)") end
		if (p.deaths or 0) == 0 then tinsert(bits, "never died") end
		if (p.avoidHits or 0) == 0 and (p.pulls or 0) == 0 then tinsert(bits, "zero mechanic fails") end
		if (p.kicks or 0) > 0 then tinsert(bits, p.kicks .. " interrupts") end
		if (p.dispels or 0) > 0 then tinsert(bits, p.dispels .. " dispels") end
		if (p.tranqs or 0) > 0 then tinsert(bits, p.tranqs .. " tranqs") end
		if p.act and p.act >= 0.85 then tinsert(bits, pct(p.act) .. " active") end
		tinsert(out, header("BIG UP " .. who, rec))
		if getn(bits) == 0 then
			tinsert(out, who .. " showed up. That counts for something!")
		else
			tinsert(out, who .. ": " .. table.concat(bits, ", ") .. ". Legend!")
		end
		return out
	end

	tinsert(out, header("BIG UPS", rec))

	local main, extra = {}, {}

	local h = rec.heroes and rec.heroes[1]
	if h and h.pts >= 2 then
		local what = string.gsub(h.list[1] or "", "^" .. h.name .. " ", "")
		tinsert(main, title("life") .. ": " .. h.name .. " - " .. getn(h.list) .. " game-saving play(s), e.g. " .. what)
	end

	local n, p, v = best(rec, function(p) return p.dmg end)
	local king = n
	if n then
		tinsert(main, title("dmg") .. ": " .. n .. " - " .. floor(dps(rec, p)) .. " DPS, " .. pct(v / math.max(1, tDmg)) .. " of the raid's damage")
	end

	n, p, v = best(rec, function(p) return p.heal end)
	if n then
		tinsert(main, title("heal") .. ": " .. n .. " - " .. FmtNum(v) .. " healed (" .. pct(v / math.max(1, tHeal)) .. " of all healing)")
	end

	n, p, v = best(rec, function(p) if p.role == "tank" and (p.deaths or 0) == 0 then return p.taken end end)
	if n then tinsert(main, title("wall") .. ": " .. n .. " took " .. FmtNum(v) .. " damage and never went down") end

	local util = {}
	n, p, v = best(rec, function(p) return p.kicks end)
	if n and v >= 2 then tinsert(util, title("kick") .. " " .. n .. " (" .. v .. " interrupts)") end
	n, p, v = best(rec, function(p) return p.dispels end)
	if n and v >= 3 then tinsert(util, title("cleanse") .. " " .. n .. " (" .. v .. " dispels)") end
	n, p, v = best(rec, function(p) return p.tranqs end)
	if n then tinsert(util, title("tranq") .. " " .. n .. " (" .. v .. ")") end
	if getn(util) > 0 then tinsert(main, table.concat(util, "  -  ")) end

	n, p, v = best(rec, function(p) if p.role ~= "tank" and (p.alive or 0) >= 30 then return p.act end end)
	if n and v >= 0.85 then tinsert(main, title("busy") .. ": " .. n .. " was active " .. pct(v) .. " of the fight") end

	local spotless = {}
	for name, p in pairs(P) do
		if (p.deaths or 0) == 0 and (p.avoidHits or 0) == 0 and (p.pulls or 0) == 0 and (p.blame or 0) <= 0 then
			tinsert(spotless, name)
		end
	end
	table.sort(spotless)
	-- a handful of names, or just how many (40 names is a wall of chat)
	if getn(spotless) > 0 and getn(spotless) <= 4 then
		tinsert(main, title("clean") .. ": " .. table.concat(spotless, ", ") .. " - no deaths, no fire, no aggro pulls")
	elseif getn(spotless) > 4 then
		local all = 0
		for _ in pairs(P) do all = all + 1 end
		tinsert(main, title("clean") .. ": " .. getn(spotless) .. " of " .. all .. " raiders - no deaths, no fire, no aggro pulls")
	end

	-- extras: two of these, picked at random, when there's room
	n, p, v = best(rec, function(p) return p.dMax end)
	if n and v >= 1000 then tinsert(extra, title("bighit") .. ": " .. n .. " - " .. FmtNum(v) .. (p.dMaxSp and (" with " .. p.dMaxSp) or "") .. " in one hit") end

	n, p, v = best(rec, function(p) return p.hMax end)
	if n and v >= 1000 then tinsert(extra, title("bigheal") .. ": " .. n .. " - " .. FmtNum(v) .. (p.hMaxSp and (" with " .. p.hMaxSp) or "") .. " in one heal") end

	n, p, v = best(rec, function(p) if (p.dHits or 0) >= 20 then return (p.dCrits or 0) / p.dHits end end)
	if n and v >= 0.25 then tinsert(extra, title("crit") .. ": " .. n .. " - crit " .. pct(v) .. " of the time (" .. p.dCrits .. " of " .. p.dHits .. ")") end

	local tBoss = 0
	for _, q in pairs(P) do tBoss = tBoss + (q.boss or 0) end
	n, p, v = best(rec, function(p) return p.boss end)
	if n and n ~= king and tBoss > 0 then tinsert(extra, title("bossdmg") .. ": " .. n .. " - " .. pct(v / tBoss) .. " of all the damage on the boss") end

	-- a wipe: whoever was still up at the end, or the last one to fall
	if rec.result ~= "KILL" and rec.result ~= "LIVE" and getn(rec.deaths) > 0 then
		local up = {}
		for name, q in pairs(P) do if (q.deaths or 0) == 0 then tinsert(up, name) end end
		if getn(up) == 1 then
			tinsert(extra, title("last") .. ": " .. up[1] .. " - still standing when the raid went down")
		elseif getn(up) == 0 then
			local d = rec.deaths[getn(rec.deaths)]
			tinsert(extra, title("last") .. ": " .. d.name .. " - the last to fall, at " .. FmtTime(d.t))
		end
	end

	n, p, v = best(rec, function(p)
		local c = 0
		for i = 1, getn(p.used or {}) do c = c + (p.used[i][2] or 0) end
		return c
	end)
	if n and v >= 3 then tinsert(extra, title("pharm") .. ": " .. n .. " - " .. v .. " consumables used in the fight") end

	fill(out, main, extra, MAX_PRAISE)
	if getn(out) == 1 then tinsert(out, "Everyone tried their best. Probably.") end
	return out
end

------------------------------------------------------------------ the automatic post

-- The one post after a fight (Auto summary on and / or shout-outs): two short
-- lines, the point first. A kill: time, deaths, then MVP, top damage and healing
-- and how many were flawless. A wipe: when, deaths and why, then the top 3 to
-- blame with one short reason each. The buttons post the longer versions.
-- a cause's first clause: "Tank Bob died at 0:40 - 2719 taken vs 402 healed in 5s" -> "Tank Bob died at 0:40"
local function firstClause(s)
	s = s or ""
	local _, _, head = string.find(s, "^(.-)%s+%- ")
	s = head or s
	local _, _, h2 = string.find(s, "^(.-)%s+%(")
	return h2 or s
end
-- a few words for why someone is to blame, from their main reason
local function blameTag(b)
	local r = string.gsub(b.reasons and b.reasons[1] or "", "^" .. b.name .. "%s*", "")
	local _, _, sp, n = string.find(r, "hit by (.-) (%d+)x")
	if sp then return sp .. " " .. n .. "x" end
	if string.find(r, "had aggro") then return "died with aggro" end
	_, _, sp = string.find(r, "^died: Stood in (.+)$")
	if sp then return "died in " .. sp end
	_, _, sp = string.find(r, "^died: Died to (.-)%s*%(") ; if not sp then _, _, sp = string.find(r, "^died: Died to (.+)$") end
	if sp then return "died to " .. sp end
	if string.find(r, "^died: Tank died") then return "tank died" end
	if string.find(r, "^died") then return "died" end
	local v
	_, _, v, sp = string.find(r, "^Killed (%S+) with (.+)$")
	if v then return sp .. " killed " .. v end
	_, _, sp = string.find(r, "^'s (.-) hit %d+")
	if sp then return sp .. " hit others" end
	if string.find(r, "pulled aggro") then return "pulled aggro" end
	if string.find(r, "first aggro") then return "pulled early" end
	_, _, n, sp = string.find(r, "reached (%d+) stacks of (.+)$")
	if n then return n .. " stacks of " .. sp end
	if string.find(r, "DPS") then return "low DPS" end
	if string.find(r, "threat") then return "high threat" end
	return "mistakes"
end
function S:AutoLines(rec)
	local P = rec.players
	local deaths = getn(rec.deaths or {})
	local tag = rec.demo and "[WhoDidIt DEMO] " or "[WhoDidIt] "
	local dead = deaths .. " death" .. ((deaths == 1) and "" or "s")
	local out = {}
	if rec.result == "KILL" then
		tinsert(out, tag .. rec.enc .. " down in " .. FmtTime(rec.dur) .. " - " .. dead)
		local bits = {}
		local h = rec.heroes and rec.heroes[1]
		if h and h.pts >= 2 then tinsert(bits, "MVP " .. h.name .. " (" .. h.pts .. " pts)") end
		local tDmg, tHeal = totals(rec)
		local n, p = best(rec, function(q) return q.dmg end)
		if n then tinsert(bits, "Top DPS " .. n .. " " .. floor(dps(rec, p))) end
		local hn, hp, hv = best(rec, function(q) return q.heal end)
		if hn then tinsert(bits, "Top heals " .. hn .. " " .. pct(hv / math.max(1, tHeal))) end
		local clean, all = 0, 0
		for _, q in pairs(P) do
			all = all + 1
			if (q.deaths or 0) == 0 and (q.avoidHits or 0) == 0 and (q.pulls or 0) == 0 and (q.blame or 0) <= 0 then clean = clean + 1 end
		end
		if all > 0 then tinsert(bits, "Flawless " .. clean .. "/" .. all) end
		if getn(bits) > 0 then tinsert(out, table.concat(bits, "  -  ")) end
	else
		-- the cause in a few words ("Tank Bob died at 0:40"), not its whole explanation
		local why = rec.verdict and firstClause(rec.verdict)
		if why and string.find(why, "^No single cause") then why = nil end
		tinsert(out, tag .. rec.enc .. " WIPE at " .. FmtTime(rec.dur) .. " - " .. dead .. (why and (" - " .. why) or ""))
		-- the top 3 to blame, each with points and a few words; short enough for one chat line
		local parts = {}
		for i = 1, math.min(3, getn(rec.blame or {})) do
			local b = rec.blame[i]
			if b.pts >= 1 then
				local p = b.name .. " " .. b.pts .. " (" .. blameTag(b) .. ")"
				if string.len("Blame: " .. table.concat(parts, ", ") .. p) > 150 then break end
				tinsert(parts, p)
			end
		end
		if getn(parts) > 0 then tinsert(out, "Blame: " .. table.concat(parts, ", ")) end
	end
	return out
end

------------------------------------------------------------------ consumes & heroes posts

local ROLE_ORDER = { tank = 1, heal = 2, dps = 3 }

local function sortedPlayers(rec)
	local list = {}
	for name, p in pairs(rec.players) do tinsert(list, { name = name, p = p }) end
	table.sort(list, function(a, b)
		local x, y = ROLE_ORDER[a.p.role] or 9, ROLE_ORDER[b.p.role] or 9
		if x ~= y then return x < y end
		return a.name < b.name
	end)
	return list
end

-- "Title: a, b, c" split over several lines so each still fits with colours
local function addList(out, title, names, empty)
	if getn(names) == 0 then
		if empty then tinsert(out, title .. ": " .. empty) end
		return
	end
	local line
	for i = 1, getn(names) do
		if not line then
			line = title .. ": " .. names[i]
		elseif string.len(line) + string.len(names[i]) > 110 then
			tinsert(out, line)
			line = title .. ": " .. names[i]
		else
			line = line .. ", " .. names[i]
		end
	end
	tinsert(out, line)
end

-- mode: "summary" (default), "missing" or "full"
function S:ConsumeLines(rec, mode)
	local out = {}
	local list = sortedPlayers(rec)
	local n = getn(list)
	if n == 0 or not list[1].p.cbuffs then
		tinsert(out, header("CONSUMES", rec))
		tinsert(out, "Consumable buffs weren't recorded for this fight.")
		return out
	end

	local flask, noFlask, noFood, noElixir, prot = {}, {}, {}, {}, {}
	local nFood, nElixir = 0, 0
	local used = { Mana = 0, Health = 0, Protection = 0, Other = 0 }
	local prep = {}
	for i = 1, n do
		local it = list[i]
		local has = {}
		for j = 1, getn(it.p.cbuffs) do has[it.p.cbuffs[j][2]] = true end
		if has.Flask then tinsert(flask, it.name) else tinsert(noFlask, it.name) end
		if has.Food then nFood = nFood + 1 else tinsert(noFood, it.name) end
		if has.Elixir then nElixir = nElixir + 1 else tinsert(noElixir, it.name) end
		if has.Protection then tinsert(prot, it.name) end
		local nu = 0
		for j = 1, getn(it.p.used or {}) do
			local u = it.p.used[j]
			used[u[3]] = (used[u[3]] or 0) + u[2]
			nu = nu + u[2]
		end
		tinsert(prep, { it.name, getn(it.p.cbuffs), nu })
	end

	if mode == "missing" and not W.Cons then
		tinsert(out, header("CONSUMES CHECK", rec))
		tinsert(out, "Restart WoW to load the consume check.")
		return out
	end
	if mode == "missing" then
		-- what each player's role needs (flask, food, role elixir, weapon oil/stone)
		tinsert(out, header("CONSUMES CHECK", rec))
		local slack, unknown = W.Cons.Slackers(rec)
		if getn(slack) == 0 then
			tinsert(out, "Everyone had the consumables their role needs!")
		else
			local order, groups = W.Cons.ByNeed(slack)
			for i = 1, getn(order) do addList(out, "No " .. order[i], groups[order[i]], "") end
		end
		if unknown > 0 then tinsert(out, unknown .. " player(s) were out of range at the pull, so they aren't counted.") end
	elseif mode == "full" then
		tinsert(out, header("CONSUMES", rec))
		for i = 1, n do
			local it = list[i]
			local b = {}
			for j = 1, getn(it.p.cbuffs) do tinsert(b, it.p.cbuffs[j][1]) end
			local u = {}
			for j = 1, getn(it.p.used or {}) do
				local x = it.p.used[j]
				tinsert(u, x[1] .. ((x[2] > 1) and (" x" .. x[2]) or ""))
			end
			local buffs = getn(b) > 0 and table.concat(b, ", ") or "no consumable buffs"
			local line = it.name .. ": " .. buffs .. (getn(u) > 0 and (" - used " .. table.concat(u, ", ")) or "")
			if string.len(line) > 200 then
				tinsert(out, it.name .. ": " .. buffs)
				if getn(u) > 0 then tinsert(out, it.name .. ": used " .. table.concat(u, ", ")) end
			else
				tinsert(out, line)
			end
		end
	else
		tinsert(out, header("CONSUMES", rec))
		tinsert(out, "Flasks: " .. getn(flask) .. "/" .. n .. "   Food: " .. nFood .. "/" .. n .. "   Elixirs: " .. nElixir .. "/" .. n)
		addList(out, "Protection potions", prot, "none")
		tinsert(out, "Items used: " .. used.Mana .. " mana, " .. used.Health .. " health, " .. used.Protection .. " protection, " .. used.Other .. " other")
		table.sort(prep, function(a, b) return (a[2] + a[3]) > (b[2] + b[3]) end)
		local top = {}
		for i = 1, math.min(3, getn(prep)) do
			tinsert(top, prep[i][1] .. " (" .. prep[i][2] .. " buffs, " .. prep[i][3] .. " items)")
		end
		tinsert(out, "Most prepared: " .. table.concat(top, ", "))
		addList(out, "No flask", noFlask, nil)
	end
	return out
end

function S:HeroLines(rec)
	local out = { header("HEROES", rec) }
	local hs = rec.heroes or {}
	if getn(hs) == 0 then
		tinsert(out, "No game-saving plays this time.")
		return out
	end
	local board = {}
	for i = 1, math.min(4, getn(hs)) do tinsert(board, i .. ". " .. hs[i].name .. " " .. hs[i].pts .. " pts") end
	tinsert(out, "Hero board: " .. table.concat(board, ", "))
	local shown = 0
	for i = 1, getn(rec.saves or {}) do
		local s = rec.saves[i]
		if s.t and s.pts >= 1.5 and shown < 4 then
			tinsert(out, FmtTime(s.t) .. " - " .. s.text .. " (+" .. s.pts .. ")")
			shown = shown + 1
		end
	end
	return out
end

-- the same shape as the hero post: the board, then the biggest moments
function S:MistakeLines(rec)
	local out = { header("MISTAKES", rec) }
	local bl = rec.blame or {}
	if getn(bl) == 0 then
		tinsert(out, "No mistakes this time. Suspicious.")
		return out
	end
	local board = {}
	for i = 1, math.min(4, getn(bl)) do tinsert(board, i .. ". " .. bl[i].name .. " " .. bl[i].pts .. " pts") end
	tinsert(out, "Blame board: " .. table.concat(board, ", "))
	local list = {}
	for i = 1, getn(rec.findings or {}) do
		if (rec.findings[i].pts or 0) >= 2 then tinsert(list, rec.findings[i]) end
	end
	table.sort(list, function(a, b) return a.pts > b.pts end)
	for i = 1, math.min(4, getn(list)) do
		local fd = list[i]
		tinsert(out, (fd.t and (FmtTime(fd.t) .. " - ") or "") .. fd.text .. " (+" .. fd.pts .. ")")
	end
	return out
end

------------------------------------------------------------------ single-player overviews (clicking a name)

local function stripName(text, name)
	return (string.gsub(text or "", "^" .. name .. " ", ""))
end

function S:BlameLines(rec, who)
	local out = { header("BLAME: " .. who, rec) }
	local b, rank = blameOf(rec, who)
	if not b or b.pts <= 0 then
		tinsert(out, who .. " has no blame points this fight. Clean!")
		return out
	end
	tinsert(out, who .. ": " .. b.pts .. " blame points (#" .. rank .. " of " .. getn(rec.blame) .. ")")
	for i = 1, math.min(5, getn(b.reasons)) do
		tinsert(out, "Reason: " .. stripName(b.reasons[i], who))
	end
	if getn(b.reasons) > 5 then tinsert(out, "...and " .. (getn(b.reasons) - 5) .. " more") end
	return out
end

function S:HeroPlayerLines(rec, who)
	local out = { header("HERO: " .. who, rec) }
	local h, rank
	for i = 1, getn(rec.heroes or {}) do
		if rec.heroes[i].name == who then h, rank = rec.heroes[i], i end
	end
	if not h then
		tinsert(out, who .. " had no game-saving plays this fight.")
		return out
	end
	tinsert(out, who .. ": " .. h.pts .. " hero points (#" .. rank .. " of " .. getn(rec.heroes) .. ")")
	for i = 1, math.min(5, getn(h.list)) do
		tinsert(out, "Play: " .. stripName(h.list[i], who))
	end
	return out
end

function S:StatLines(rec, who)
	local p = rec.players[who]
	local out = { header("STATS: " .. who, rec) }
	local tDmg, tHeal = totals(rec)
	local r1, n1 = rankOf(rec, who, "dmg")
	local r2 = rankOf(rec, who, "heal")
	local bits = {
		"Damage " .. FmtNum(p.dmg) .. " (" .. floor(dps(rec, p)) .. " DPS, #" .. r1 .. ", " .. pct(p.dmg / math.max(1, tDmg)) .. ")",
	}
	if (p.heal or 0) > 0 then
		tinsert(bits, "Healing " .. FmtNum(p.heal) .. " (#" .. r2 .. ", " .. pct(p.heal / math.max(1, tHeal)) .. ")")
	end
	tinsert(bits, "Taken " .. FmtNum(p.taken))
	tinsert(out, who .. ": " .. table.concat(bits, ", "))
	local top = {}
	local src = (p.role == "heal") and p.hs or p.ds
	local tot = (p.role == "heal") and p.heal or p.dmg
	for i = 1, math.min(3, getn(src or {})) do
		tinsert(top, src[i][1] .. " " .. pct(src[i][2] / math.max(1, tot)))
	end
	if getn(top) > 0 then tinsert(out, "Top spells: " .. table.concat(top, ", ")) end
	tinsert(out, "Activity: " .. (p.act and pct(p.act) or "?") .. ", deaths " .. (p.deaths or 0) .. ", interrupts " .. (p.kicks or 0)
		.. ", dispels " .. (p.dispels or 0) .. ", items " .. (p.cons or 0))
	return out
end

function S:ConsumePlayerLines(rec, who)
	local p = rec.players[who]
	local out = { header("CONSUMES: " .. who, rec) }
	local b, u = {}, {}
	for i = 1, getn(p.cbuffs or {}) do tinsert(b, p.cbuffs[i][1]) end
	for i = 1, getn(p.used or {}) do
		local x = p.used[i]
		tinsert(u, x[1] .. ((x[2] > 1) and (" x" .. x[2]) or ""))
	end
	addList(out, "Buffs", b, "none")
	addList(out, "Used", u, "nothing")
	return out
end

------------------------------------------------------------------ entry points

local function resolve(rec, who)
	if not rec then W.Print("No finished fight to shout about yet.") return end
	if rec.result == "LIVE" then W.Print("Wait for the fight to finish first.") return end
	if who and who ~= "" then
		local n = S:FindPlayer(rec, who)
		if not n then W.Print(who .. " wasn't in " .. rec.enc .. ".") return end
		return rec, n
	end
	return rec, nil
end

-- automatic shout-outs for demo fights stay in your own chat; clicking the
-- buttons posts them for real (tagged DEMO)
local function demoChannel(rec, channel, auto)
	if rec.demo and auto then
		W.Print("|cff33ccff(demo fight - auto shout-out shown only to you. Click the button to post it to " .. S:ChannelLabel(channel) .. ")|r")
		return "SELF"
	end
	return channel
end

function S:Shame(rec, who, channel, auto)
	local r, n = resolve(rec, who)
	if not r then return end
	W:Send(S:ShameLines(r, n), demoChannel(r, channel, auto), S.ClassMap(r))
end

function S:Praise(rec, who, channel, auto)
	local r, n = resolve(rec, who)
	if not r then return end
	W:Send(S:PraiseLines(r, n), demoChannel(r, channel, auto), S.ClassMap(r))
end

-- clicking a name. kind: blame / hero / stats / consumes; channel "SELF" = preview
function S:PlayerPost(rec, who, kind, channel)
	local r, n = resolve(rec, who)
	if not r or not n then return end
	local lines
	if kind == "blame" then lines = S:BlameLines(r, n)
	elseif kind == "hero" then lines = S:HeroPlayerLines(r, n)
	elseif kind == "consumes" then lines = S:ConsumePlayerLines(r, n)
	else lines = S:StatLines(r, n) end
	W:Send(lines, channel, S.ClassMap(r))
end

function S:Consumes(rec, mode, channel)
	local r = resolve(rec)
	if not r then return end
	W:Send(S:ConsumeLines(r, mode), channel, S.ClassMap(r))
end

function S:Heroes(rec, channel)
	local r = resolve(rec)
	if not r then return end
	W:Send(S:HeroLines(r), channel, S.ClassMap(r))
end

function S:Mistakes(rec, channel)
	local r = resolve(rec)
	if not r then return end
	W:Send(S:MistakeLines(r), channel, S.ClassMap(r))
end

-- automatic shout-outs after a fight (opts.autoShout)
-- After a fight: at most ONE short post (S:AutoLines), whether it's the auto summary
-- (summary = true), the shout-outs, or both. smart / both: every fight (blame on a
-- wipe, the highlights on a kill); shame: wipes only; praise: kills only.
function S:Auto(rec, summary)
	local mode = WhoDidItDB.opts.autoShout or "off"
	local wipe = rec.result ~= "KILL"
	local post = summary or mode == "smart" or mode == "both" or (mode == "shame" and wipe) or (mode == "praise" and not wipe)
	if not post then return end
	W:Send(S:AutoLines(rec), demoChannel(rec, nil, true), S.ClassMap(rec))
end
