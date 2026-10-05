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

local MAX_SHAME  = 6
local MAX_PRAISE = 8

------------------------------------------------------------------ channel handling

function S:Channel()
	return WhoDidItDB.opts.shoutChannel or "RAID"
end

function S:ChannelLabel(ch)
	ch = ch or S:Channel()
	if string.sub(ch, 1, 1) == "#" then return string.sub(ch, 2) end
	return S.LABELS[ch] or ch
end

function S:CycleChannel()
	local list = {}
	for i = 1, getn(S.CHANNELS) do list[i] = S.CHANNELS[i] end
	if WhoDidItDB.opts.customChannel then tinsert(list, "#" .. WhoDidItDB.opts.customChannel) end
	local cur = S:Channel()
	local nxt = list[1]
	for i = 1, getn(list) do
		if list[i] == cur then nxt = list[i + 1] or list[1] end
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

local COL = { tag = "ff5555", title = "ffd100", time = "66ccff", num = "ffffff" }
local RESULT_COL = { WIPE = "ff4444", KILL = "33ff33", RESET = "ff9933" }

local function hex(class)
	local r, g, b = W.ClassRGB(class)
	return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function wrap(h, s) return "|cff" .. h .. s .. "|r" end

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
				tinsert(out, wrap(hex(classes[title]), title) .. ":")
			elseif not namesOnly then
				tinsert(out, wrap(COL.title, title .. ":"))
			else
				tinsert(out, title .. ":")
			end
			i = e2 + 1
		end
	end
	while i <= n do
		local a, b = string.find(s, "^%d+:%d%d", i)
		if a then
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
						tinsert(out, wrap(hex(classes[w]), w))
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
	return m
end

------------------------------------------------------------------ sending

local queue = {}
local echo  -- first coloured line waiting to show up in chat

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
	-- a coloured line never appeared in chat: the server blocks colour codes
	if echo and GetTime() - echo > 5 then
		echo = nil
		WhoDidItDB.opts.chatColors = false
		W.Print("Your server didn't accept coloured chat, so WhoDidIt switched to plain text. Post again to resend. (/wdi colors on to retry)")
	end
	local q = tremove(queue, 1)
	if not q then return end
	local msg = q[2]
	if q[1] and WhoDidItDB.opts.chatColors then
		msg = q[1]
		if not echo then echo = GetTime() end
	end
	SendChatMessage(msg, q[3], nil, q[4])
end)

-- our own messages echo back through these events: a coloured line made it
local function onEcho(msg, sender)
	if echo and sender == UnitName("player") then echo = nil end
end
local ECHO_EVENTS = {
	"CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING", "CHAT_MSG_PARTY", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL",
}
for i = 1, getn(ECHO_EVENTS) do W:On(ECHO_EVENTS[i], onEcho) end

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

	local b = rec.blame[1]
	if b and b.pts >= 1 then
		tinsert(out, "Most to blame: " .. b.name .. " with " .. b.pts .. " pts - " .. shortReasons(b, 2))
	end

	local n, p, v = best(rec, function(p) return p.pulls end)
	if n then
		tinsert(out, "Threat Junkie: " .. n .. " ripped aggro off the tank " .. v .. "x")
	else
		local tn, tv
		for name, t in pairs(rec.threat or {}) do
			local tp = P[name]
			if tp and tp.role ~= "tank" and t.perc >= 100 and (not tv or t.perc > tv) then tn, tv = name, t.perc end
		end
		if tn then tinsert(out, "Threat Junkie: " .. tn .. " hit " .. tv .. "% threat - living dangerously") end
	end

	for i = 1, getn(rec.deaths) do
		local d = rec.deaths[i]
		if not d.late and d.kind ~= "mc" and d.kind ~= "expected" then
			tinsert(out, "Floor Inspector: " .. d.name .. " died first at " .. FmtTime(d.t) .. " - " .. d.text)
			break
		end
	end

	n, p, v = best(rec, function(p) return p.avoidDmg end)
	if n then
		tinsert(out, "Fire Enthusiast: " .. n .. " soaked " .. FmtNum(v) .. " avoidable damage (" .. (p.worstSpell or "?") .. " x" .. (p.worstHits or p.avoidHits or 0) .. ")")
	end

	n, p, v = best(rec, function(p) return p.splash end)
	if n then tinsert(out, "Bomb Squad: " .. n .. " took " .. v .. " raider(s) with them") end

	n, p, v = best(rec, function(p)
		if p.role ~= "tank" and p.act and p.act < 0.6 then return 1 - p.act end
	end)
	if n then tinsert(out, "AFK Award: " .. n .. " was only doing something " .. pct(p.act) .. " of the time") end

	local med = medianDps(rec)
	if med and med > 0 then
		n, p, v = best(rec, function(p)
			if p.role == "dps" and (p.alive or 0) >= 30 and dps(rec, p) < med * 0.5 then return med - dps(rec, p) end
		end)
		if n then tinsert(out, "Participation Trophy: " .. n .. " - " .. floor(dps(rec, p)) .. " DPS (raid median " .. floor(med) .. ")") end
	end

	if getn(out) == 1 then tinsert(out, "Nobody to shame - clean fight. Suspicious.") end
	while getn(out) > MAX_SHAME do tremove(out) end
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

	local h = rec.heroes and rec.heroes[1]
	if h and h.pts >= 2 then
		local what = string.gsub(h.list[1] or "", "^" .. h.name .. " ", "")
		tinsert(out, "Lifesaver: " .. h.name .. " - " .. getn(h.list) .. " game-saving play(s), e.g. " .. what)
	end

	local n, p, v = best(rec, function(p) return p.dmg end)
	if n then
		tinsert(out, "Damage King: " .. n .. " - " .. floor(dps(rec, p)) .. " DPS, " .. pct(v / math.max(1, tDmg)) .. " of the raid's damage")
	end

	n, p, v = best(rec, function(p) return p.heal end)
	if n then
		tinsert(out, "Top Healer: " .. n .. " - " .. FmtNum(v) .. " healed (" .. pct(v / math.max(1, tHeal)) .. " of all healing)")
	end

	n, p, v = best(rec, function(p) if p.role == "tank" and (p.deaths or 0) == 0 then return p.taken end end)
	if n then tinsert(out, "Iron Wall: " .. n .. " took " .. FmtNum(v) .. " damage and never went down") end

	local util = {}
	n, p, v = best(rec, function(p) return p.kicks end)
	if n and v >= 2 then tinsert(util, "Kick Master " .. n .. " (" .. v .. " interrupts)") end
	n, p, v = best(rec, function(p) return p.dispels end)
	if n and v >= 3 then tinsert(util, "Cleanser " .. n .. " (" .. v .. " dispels)") end
	n, p, v = best(rec, function(p) return p.tranqs end)
	if n then tinsert(util, "Tranq Sniper " .. n .. " (" .. v .. ")") end
	if getn(util) > 0 then tinsert(out, table.concat(util, "  -  ")) end

	n, p, v = best(rec, function(p) if p.role ~= "tank" and (p.alive or 0) >= 30 then return p.act end end)
	if n and v >= 0.85 then tinsert(out, "Never Stops: " .. n .. " was active " .. pct(v) .. " of the fight") end

	local spotless = {}
	for name, p in pairs(P) do
		if (p.deaths or 0) == 0 and (p.avoidHits or 0) == 0 and (p.pulls or 0) == 0 and (p.blame or 0) <= 0 then
			tinsert(spotless, name)
		end
	end
	table.sort(spotless)
	if getn(spotless) > 0 then
		tinsert(out, "Flawless (" .. getn(spotless) .. "): " .. table.concat(spotless, ", "))
	end

	if getn(out) == 1 then tinsert(out, "Everyone tried their best. Probably.") end
	while getn(out) > MAX_PRAISE do tremove(out) end
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

	if mode == "missing" then
		tinsert(out, header("CONSUMES CHECK", rec))
		addList(out, "No flask", noFlask, "everyone was flasked!")
		addList(out, "No food buff", noFood, "everyone ate!")
		addList(out, "No elixirs", noElixir, "everyone had elixirs!")
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
	for i = 1, math.min(4, getn(hs)) do tinsert(board, i .. ". " .. hs[i].name .. " " .. hs[i].pts .. "pt") end
	tinsert(out, "Hero board: " .. table.concat(board, "  "))
	local shown = 0
	for i = 1, getn(rec.saves or {}) do
		local s = rec.saves[i]
		if s.t and s.pts >= 1.5 and shown < 4 then
			tinsert(out, FmtTime(s.t) .. " " .. s.text)
			shown = shown + 1
		end
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

-- automatic shout-outs after a fight (opts.autoShout)
function S:Auto(rec)
	local mode = WhoDidItDB.opts.autoShout or "off"
	if mode == "off" then return end
	local wipe = rec.result ~= "KILL"
	if mode == "both" or mode == "shame" or (mode == "smart" and wipe) then S:Shame(rec, nil, nil, true) end
	if mode == "both" or mode == "praise" or (mode == "smart" and not wipe) then S:Praise(rec, nil, nil, true) end
end
