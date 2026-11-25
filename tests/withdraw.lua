-- Offline replay of withdrawing a wrong 5-man run (WhoDidIt 1.26.2) on DmorphOcto's LuaHost.
-- Every simulated PC loads the real Data.lua, Board.lua and Dungeons.lua in its own sandbox
-- (setfenv) with inline mocks of the 1.12 calls they use; they talk over one fake realm
-- channel (SendChatMessage -> bus -> every PC's CHAT_MSG_CHANNEL). Ludenlord runs 1.26.0
-- (git eaaa906) to show older clients ignore the new W record. The master's export goes through
-- a copy of tools\Publish-RaidTimes.ps1 (-NoPush) in a temp tree, and the RaidTimes.lua it
-- writes is seeded into fresh installs.
--   tests\run.ps1 runs this from the repository's folder (the addon's files are loaded from
--   there) and sets WDI_TMP (a scratch folder in %TEMP%) and WDI_OLD (the 1.26.0 files).
-- Lua 5.0 syntax (LuaCheck.ps1 passes): table.getn, math.mod, string.len, no "..." expressions.

local ADDON = ""   -- the repository's folder (the current directory)
local TMP = string.gsub(assert(os.getenv("WDI_TMP"), "WDI_TMP not set: run tests\\run.ps1"), "\\", "/")
local OLD = string.gsub(assert(os.getenv("WDI_OLD"), "WDI_OLD not set: run tests\\run.ps1"), "\\", "/")
local WOW = TMP .. "/wow"   -- temp tree: wow/CustomData, wow/Interface/AddOns/WhoDidIt/tools

math.randomseed(7)
local clock = 1792000000.0   -- (about 15 Oct 2026)
local UPTIME = 1791990000
local REALM = "Y'Shaarj"

local fails, passes = 0, 0
local function check(cond, what)
	if cond then passes = passes + 1 else fails = fails + 1; print("FAIL: " .. what) end
end

local bus = {}
local PCS = {}

local CLASS_TOKEN = { Shemp = "PRIEST", Ludenlord = "WARRIOR", Bystander = "MAGE", Pal = "PALADIN" }

local function newPC(name, o)
	o = o or {}
	local pc = { name = name, handlers = {}, tickers = {}, printed = {}, errors = {}, popups = {}, joined = false }
	local env = setmetatable({}, { __index = _G })
	pc.env = env
	local W = { roster = { byName = {} }, env = {} }
	env.WhoDidIt = W
	function W:On(ev, fn) pc.handlers[ev] = pc.handlers[ev] or {}; table.insert(pc.handlers[ev], fn) end
	function W:Every(sec, fn) table.insert(pc.tickers, { i = sec, f = fn, a = 0 }) end
	function W:Oops(where, err) table.insert(pc.errors, where .. ": " .. tostring(err)) end
	W.Print = function(msg) table.insert(pc.printed, tostring(msg)) end
	W.L = function(s) return s end
	W.LF = function(fmt, a1, a2, a3, a4, a5, a6, a7, a8, a9) return string.format(fmt, a1, a2, a3, a4, a5, a6, a7, a8, a9) end
	W.LT = W.L
	W.LDate = function(fmt, t) return os.date(fmt, t) end
	W.ShowPopup = function(which, a1) table.insert(pc.popups, { which = which, a1 = a1 }); return {} end
	W.CName = function(n) return n end
	env.WhoDidItDB = o.db or {}
	env.WhoDidItDB.opts = env.WhoDidItDB.opts or { shareBoard = true }
	env.UnitName = function(u) if u == "player" then return name end end
	env.UnitClass = function(u) if u == "player" then return CLASS_TOKEN[name] or "MAGE", CLASS_TOKEN[name] or "MAGE" end end
	env.UnitExists = function(u) return u == "player" end
	env.GetRealmName = function() return REALM end
	env.UnitFactionGroup = function() return "Alliance" end
	env.time = function() return math.floor(clock) end
	env.GetTime = function() return clock - UPTIME end
	env.date = os.date
	env.tinsert, env.tremove, env.strlower = table.insert, table.remove, string.lower
	env.getglobal = function(n) return env[n] end
	env.GetNumRaidMembers = function() return 0 end
	env.GetNumPartyMembers = function() return 0 end
	env.IsRaidLeader = function() return false end
	env.IsPartyLeader = function() return false end
	env.GetRaidRosterInfo = function() end
	env.IsInInstance = function() return false end
	env.GetRealZoneText = function() return "Stormwind City" end
	env.GetGuildInfo = function() return nil end
	env.SendAddonMessage = function() end
	env.StaticPopupDialogs = {}
	env.StaticPopup_Show = function(which, a1) table.insert(pc.popups, { which = which, a1 = a1 }) end
	env.StaticPopup_Hide = function() end
	env.ACCEPT, env.CANCEL, env.YES, env.NO = "Accept", "Cancel", "Yes", "No"
	env.UNKNOWNOBJECT, env.UNITDIESSELF = "Unknown", "You die."
	env.UnitAffectingCombat = function() return false end
	env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(pc.printed, m) end }
	if o.master then
		env.WriteCustomFile = function(fname, text, mode)
			local f = assert(io.open(WOW .. "/CustomData/" .. fname, "wb"))
			f:write(text)
			f:close()
			pc.wrote = text
			return true
		end
	end
	env.GetChannelName = function() if pc.joined then return 5 end return 0 end
	env.JoinChannelByName = function() pc.joined = true end
	env.LeaveChannelByName = function() pc.joined = false end
	env.ChatFrame_RemoveChannel = function() end
	env.NUM_CHAT_WINDOWS = 0
	env.SendChatMessage = function(msg, chatType)
		if chatType == "CHANNEL" then table.insert(bus, { from = name, msg = msg }) end
	end
	env.WDI_RAIDTIMES = o.raidtimes
	local dir = o.old and (OLD .. "/") or ADDON
	for _, f in ipairs({ ADDON .. "Data.lua", dir .. "Board.lua", dir .. "Dungeons.lua" }) do
		local chunk = assert(loadfile(f))
		setfenv(chunk, env)
		chunk()
	end
	pc.R, pc.B = W.Runs, W.Board
	PCS[name] = pc
	return pc
end

local function fire(pc, ev, a1, a2, a3, a4, a5, a6, a7, a8, a9)
	for _, fn in ipairs(pc.handlers[ev] or {}) do
		local ok, err = pcall(fn, a1, a2, a3, a4, a5, a6, a7, a8, a9)
		if not ok then table.insert(pc.errors, ev .. ": " .. tostring(err)) end
	end
end

local function deliver()
	while table.getn(bus) > 0 do
		local m = table.remove(bus, 1)
		for _, pc in pairs(PCS) do
			if pc.joined then fire(pc, "CHAT_MSG_CHANNEL", m.msg, m.from, "", "5. WDIBoard", "", "", 0, 5, "WDIBoard") end
		end
		if m.log then m.log(m) end
		table.insert(bus.seen, m)
	end
end
bus.seen = {}

local function tick(secs)
	local steps = math.floor(secs / 0.2 + 0.5)
	for _ = 1, steps do
		clock = clock + 0.2
		for _, pc in pairs(PCS) do
			for _, t in ipairs(pc.tickers) do
				t.a = t.a + 0.2
				if t.a >= t.i - 1e-6 then
					t.a = 0
					local ok, err = pcall(t.f)
					if not ok then table.insert(pc.errors, "timer: " .. tostring(err)) end
				end
			end
		end
		deliver()
	end
end

local function sent(kind)
	local out = {}
	for _, m in ipairs(bus.seen) do
		if string.sub(m.msg, 1, 8) == "WDIB1~" .. kind .. "~" then table.insert(out, m) end
	end
	return out
end

local function inject(from, msg) table.insert(bus, { from = from, msg = msg }); deliver() end

local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
local function printedHas(pc, s)
	for _, l in ipairs(pc.printed) do if string.find(l, s, 1, true) then return true end end
	return false
end

----------------------------------------------------------------- the state Shemp reported
local GK = "Ludenlord,Shemp"
local RUN_D = math.floor(clock) - 20 * 3600
local function badRec(by)
	return { g = "Spire Sprinters", t = 2798, d = RUN_D, x = 3, f = "Alliance", n = 2, m = "Ludenlord:Wa,Shemp:Pr",
		s = "1=420;5=1800;9=2798", nt = RUN_D, by = by, ok = "Shemp,Ludenlord" }
end
local function memberDB(name)
	local older = { k = "lbrs", gk = GK, realm = REALM, g = "Spire Sprinters", t = 5400, d = RUN_D - 7 * 86400, x = 1,
		f = "Alliance", n = 2, m = "Ludenlord:Wa,Shemp:Pr", s = "" }
	local bad = { k = "lbrs", gk = GK, realm = REALM, g = "Spire Sprinters", t = 2798, d = RUN_D, x = 3, f = "Alliance",
		n = 2, m = "Ludenlord:Wa,Shemp:Pr", s = "1=420;5=1800;9=2798" }
	return { opts = { shareBoard = true }, dungeons = { [REALM] = { lbrs = { [GK] = badRec(name) } } }, myRuns = { bad, older } }
end

local shemp = newPC("Shemp", { db = memberDB("Shemp") })
local luden = newPC("Ludenlord", { db = memberDB("Ludenlord"), old = true })
local bysDB = { opts = { shareBoard = true }, dungeons = { [REALM] = { brd = { ["Bystander,Pal"] = { g = "Dark Irons", t = 3000,
	d = RUN_D, x = 0, f = "Alliance", n = 2, m = "Bystander:Ma,Pal:Pa", s = "", nt = RUN_D, by = "Bystander" } } } },
	myRuns = { { k = "brd", gk = "Bystander,Pal", realm = REALM, g = "Dark Irons", t = 3000, d = RUN_D, x = 0, f = "Alliance", n = 2,
	m = "Bystander:Ma,Pal:Pa", s = "" } } }
local bys = newPC("Bystander", { db = bysDB })
local master = newPC("Upsilon", { master = true })

local function board(pc, key, gk) local r = pc.env.WhoDidItDB.dungeons and pc.env.WhoDidItDB.dungeons[REALM]; return r and r[key] and r[key][gk] end
local function outs(pc) return pc.env.WhoDidItDB.runsWithdrawn and pc.env.WhoDidItDB.runsWithdrawn[REALM] or {} end
local function out(pc) return outs(pc)["lbrs~" .. GK .. "~2798"] end

----------------------------------------------------------------- P0: the bad run spreads (as it did)
for _, pc in pairs(PCS) do fire(pc, "PLAYER_ENTERING_WORLD") end
tick(20)
-- when the run finished, every member with sharing on sent it (finish -> R:Share)
shemp.R:Share("lbrs", board(shemp, "lbrs", GK))
luden.R:Share("lbrs", board(luden, "lbrs", GK))
tick(70)
check(board(bys, "lbrs", GK) and board(bys, "lbrs", GK).t == 2798, "P0 Bystander got the bad 46:38 run from the channel")
check(board(master, "lbrs", GK) and board(master, "lbrs", GK).t == 2798, "P0 master got the bad run")
check(board(master, "brd", "Bystander,Pal") ~= nil, "P0 master got Bystander's legit BRD run")
local okM = board(master, "lbrs", GK) and board(master, "lbrs", GK).ok or ""
check(string.find(okM, "Shemp", 1, true) and string.find(okM, "Ludenlord", 1, true), "P0 master saw both members share it (ok=" .. okM .. ")")
master.R:WriteFile()
check(master.wrote and string.find(master.wrote, "\nR5|" .. REALM .. "|lbrs|Spire Sprinters|2798|", 1, true), "P0 master's export has the bad run (R5)")
check(shemp.R:MyBest("lbrs").t == 2798, "P0 Shemp's best LBRS is the bad 46:38")

----------------------------------------------------------------- the maintainer publishes (download v1, run included)
local function publish(synced, tag)
	local f = assert(io.open(WOW .. "/CustomData/WhoDidIt_Chronicle.txt", "wb"))
	f:write("WDICHRON|1|" .. synced .. "|OctoWoW|0|ok\nC|" .. REALM .. "|Molten Core|Test Guild|Alliance|3600|" .. synced .. "|40|\n")
	f:close()
	local cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' .. WOW .. '/Interface/AddOns/WhoDidIt/tools/Publish-RaidTimes.ps1" -NoPush -Force > "' .. TMP .. '/publish-' .. tag .. '.log" 2>&1'
	local rc = os.execute(cmd)
	local lf = io.open(TMP .. "/publish-" .. tag .. ".log", "rb")
	local log = lf and lf:read("*a") or ""
	if lf then lf:close() end
	print("  publish " .. tag .. ": " .. (string.gsub(log, "%s+$", "")))
	local env = {}
	local chunk = assert(loadfile(WOW .. "/Interface/AddOns/WhoDidIt/RaidTimes.lua"))
	setfenv(chunk, env)
	chunk()
	return env.WDI_RAIDTIMES, rc
end
local rt1 = publish(1792000100, "v1")
check(rt1 and string.find(rt1.text, "R5|" .. REALM .. "|lbrs|Spire Sprinters|2798|", 1, true), "P1 download v1 carries the bad run (both members in ok)")

-- a player installs v1: the bad run arrives with the download
local early = newPC("Early", { raidtimes = rt1 })
fire(early, "PLAYER_ENTERING_WORLD")
tick(20)   -- (joins the channel; nobody answers its Q: they answered under 10 minutes ago)
check(board(early, "lbrs", GK) and board(early, "lbrs", GK).t == 2798, "P1 a v1 install seeds the bad run from the download")

----------------------------------------------------------------- P2: Shemp withdraws it (Rankings > 5-mans > the run's page)
local before = table.getn(bus.seen)
shemp.R:AskWithdraw(REALM, "lbrs", GK, board(shemp, "lbrs", GK))
local pop = shemp.popups[table.getn(shemp.popups)]
check(pop and pop.which == "WHODIDIT_WITHDRAW5" and string.find(pop.a1, "46:38", 1, true), "P2 asks first (popup shows the run, 46:38)")
check(board(shemp, "lbrs", GK) ~= nil and not out(shemp), "P2 nothing changes before the answer")
-- (No: the popup closes, nothing happens - OnAccept isn't called)
tick(5)
check(board(shemp, "lbrs", GK) ~= nil and table.getn(sent("W")) == 0, "P2 'No' leaves it alone, nothing sent")
-- Yes
shemp.env.StaticPopupDialogs.WHODIDIT_WITHDRAW5.OnAccept()
check(board(shemp, "lbrs", GK) == nil, "P2 the run is off Shemp's board")
check(out(shemp) and out(shemp).by == "Shemp", "P2 Shemp keeps the withdrawal")
check(shemp.env.WhoDidItDB.myRuns[1].wd == true and not shemp.env.WhoDidItDB.myRuns[2].wd, "P2 Your runs marks only that run withdrawn")
check(shemp.R:MyBest("lbrs") and shemp.R:MyBest("lbrs").t == 5400, "P2 Shemp's best LBRS falls back to the 1:30:00 run")
check(printedHas(shemp, "withdrawn: |cffffd100Spire Sprinters|r, Lower Blackrock Spire in 46:38. It's off your boards, and"), "P2 chat says it's withdrawn and the realm is told")
tick(5)
local w = sent("W")
check(table.getn(w) == 1 and w[1].from == "Shemp" and w[1].msg == "WDIB1~W~lbrs~2798~Ludenlord,Shemp", "P2 one W record on the channel: " .. tostring(w[1] and w[1].msg))
check(board(bys, "lbrs", GK) == nil and out(bys) and out(bys).by == "Shemp", "P2 Bystander dropped it (from a member)")
check(board(master, "lbrs", GK) == nil and out(master), "P2 master dropped it")
check(board(early, "lbrs", GK) == nil, "P2 the v1 install dropped it too")
check(board(bys, "brd", "Bystander,Pal") ~= nil, "P2 other runs untouched")
check(board(luden, "lbrs", GK) ~= nil and table.getn(luden.errors) == 0, "P2 1.26.0 (Ludenlord) ignores W without an error")
check(not printedHas(bys, "withdrew your group"), "P2 Bystander isn't told (not in the group)")
master.R:WriteFile()
check(not string.find(master.wrote, "R5|" .. REALM .. "|lbrs|Spire Sprinters|2798|", 1, true), "P2 master's export drops the run")
local _, _, w5 = string.find(master.wrote, "\n(W5|[^\n]*)")
check(w5 and string.find(w5, "W5|" .. REALM .. "|lbrs|2798|" .. GK .. "|", 1, true), "P2 master's export has the withdrawal: " .. tostring(w5))
check(string.find(master.wrote, "R5|" .. REALM .. "|brd|Dark Irons|3000|", 1, true), "P2 master's export keeps the other runs")

----------------------------------------------------------------- P3: the old client shares it again; nobody takes it back
clock = clock + 700   -- (answers are once per 10 minutes)
local late = newPC("Newcomer")
fire(late, "PLAYER_ENTERING_WORLD")
local dBefore = table.getn(sent("D"))
tick(80)
local dFromLuden = 0
for i = dBefore + 1, table.getn(sent("D")) do if sent("D")[i].from == "Ludenlord" and string.find(sent("D")[i].msg, "~lbrs~", 1, true) then dFromLuden = dFromLuden + 1 end end
check(dFromLuden >= 1, "P3 Ludenlord's 1.26.0 shares the bad run again on a Q (" .. dFromLuden .. "x)")
local wFromShemp = 0
for _, m in ipairs(sent("W")) do if m.from == "Shemp" then wFromShemp = wFromShemp + 1 end end
check(wFromShemp >= 2, "P3 Shemp's WhoDidIt sends the withdrawal again in its answer")
check(board(late, "lbrs", GK) == nil and out(late), "P3 the newcomer ends without the run (D and W in any order)")
check(board(bys, "lbrs", GK) == nil and board(master, "lbrs", GK) == nil, "P3 Bystander / master don't take it back")
check(board(shemp, "lbrs", GK) == nil, "P3 Shemp's own PC doesn't take it back from Ludenlord")
check(board(early, "lbrs", GK) == nil, "P3 the v1 install doesn't take it back")

----------------------------------------------------------------- P3b: Ludenlord updates: hears it from Shemp, stops sharing it
local ldb = luden.env.WhoDidItDB
PCS.Ludenlord = nil
luden = newPC("Ludenlord", { db = ldb })
fire(luden, "PLAYER_ENTERING_WORLD")
clock = clock + 700
tick(80)
check(board(luden, "lbrs", GK) == nil and out(luden) and out(luden).by == "Shemp", "P3b updated Ludenlord drops it on Shemp's W")
check(printedHas(luden, "Shemp withdrew your group's run: Lower Blackrock Spire in 46:38."), "P3b Ludenlord's chat says Shemp withdrew it")
check(ldb.myRuns[1].wd == true and luden.R:MyBest("lbrs").t == 5400, "P3b Ludenlord's history marks it too")
local dAfter = table.getn(sent("D"))
clock = clock + 700
local late2 = newPC("Latecomer")
fire(late2, "PLAYER_ENTERING_WORLD")
tick(80)
local again = 0
for i = dAfter + 1, table.getn(sent("D")) do if string.find(sent("D")[i].msg, "~lbrs~Spire Sprinters~2798~", 1, true) then again = again + 1 end end
check(again == 0, "P3b nobody shares the bad run any more")
check(board(late2, "lbrs", GK) == nil and out(late2), "P3b a latecomer still hears the withdrawal (members re-send it)")

----------------------------------------------------------------- P4: who may withdraw, malformed records, rationing
local nb = count(outs(bys))
inject("Evil", "WDIB1~W~brd~3000~Bystander,Pal")
check(board(bys, "brd", "Bystander,Pal") ~= nil and board(master, "brd", "Bystander,Pal") ~= nil, "P4 a non-member can't withdraw a run")
for _, bad in ipairs({ "WDIB1~W", "WDIB1~W~nope~2798~Evil,Xa", "WDIB1~W~lbrs~abc~Evil,Xa", "WDIB1~W~lbrs~50~Evil,Xa",
	"WDIB1~W~lbrs~1000.5~Evil,Xa", "WDIB1~W~lbrs~99999~Evil,Xa", "WDIB1~W~lbrs~2000~Evil,Evil", "WDIB1~W~lbrs~2000~Evil,X|cff",
	"WDIB1~W~lbrs~2000~Evil,Xb,Xc,Xd,Xe,Xf", "WDIB1~W~lbrs~2000~", "WDIB1~W~lbrs~2000~Evil,", "WDIB1~W~lbrs~2000~Evil,X1" }) do
	inject("Evil", bad)
end
check(count(outs(bys)) == nb and table.getn(bys.errors) == 0, "P4 malformed W records are ignored without errors (" .. count(outs(bys)) - nb .. " stored)")
inject("Evil", "WDIB1~W~ubrs~2000~Evil,Xb,Xc,Xd,Xe,Xf")   -- (UBRS allows 10)
check(count(outs(bys)) == nb + 1, "P4 UBRS takes a 6-name group")
for i = 1, 7 do inject("Evil", "WDIB1~W~lbrs~" .. (1000 + i) .. "~Evil,Grunt") end
check(count(outs(bys)) == nb + 5, "P4 rationed: 5 per sender per 10 minutes (" .. count(outs(bys)) - nb .. ")")
clock = clock + 601
inject("Evil", "WDIB1~W~lbrs~1100~Evil,Grunt")
check(count(outs(bys)) == nb + 6, "P4 the next window takes one more")
check(table.getn(late2.errors) == 0, "P4 no errors")
-- taking a withdrawal never makes anyone send
local before4 = table.getn(bus.seen)
inject("Evil", "WDIB1~W~lbrs~1200~Evil,Grunt")
tick(10)
local sentAfter = 0
for i = before4 + 2, table.getn(bus.seen) do if bus.seen[i].from ~= "Evil" and string.find(bus.seen[i].msg, "~W~", 1, true) then sentAfter = sentAfter + 1 end end
check(sentAfter == 0, "P4 receiving a W makes nobody send")

----------------------------------------------------------------- P5: eviction keeps your own groups' withdrawals
for s = 1, 45 do
	for i = 1, 5 do inject("Spam" .. string.char(64 + math.floor(s / 26) + 1, 97 + math.mod(s, 26)), "WDIB1~W~stratud~" .. (2000 + s * 10 + i) .. "~Spam" .. string.char(64 + math.floor(s / 26) + 1, 97 + math.mod(s, 26)) .. ",Zed") end
end
check(count(outs(shemp)) <= 200, "P5 at most 200 withdrawals kept per realm (" .. count(outs(shemp)) .. ")")
check(out(shemp) ~= nil, "P5 your own group's withdrawal is never evicted")
check(count(outs(shemp)) == 200, "P5 the cap is reached exactly")
check(count(outs(master)) == 200 and out(master) ~= nil and out(bys) ~= nil,
	"P5 a flood of made-up withdrawals doesn't push out one that took a run off (master, Bystander)")
-- (the latecomer never had the run: its copy can go in a flood; members send it again on the next Q)
print("  latecomer kept its withdrawal through the flood: " .. tostring(out(late2) ~= nil))
local evilLeft = 0
for _, w in pairs(outs(master)) do if string.find(w.gk, "Evil", 1, true) then evilLeft = evilLeft + 1 end end
check(evilLeft == 0, "P5 the oldest made-up ones went first (" .. evilLeft .. " of Evil's left)")

----------------------------------------------------------------- P6: the download takes it off PCs that got it from v1
master.R:WriteFile()
local rt2 = publish(1792000200, "v2")
check(rt2 and not string.find(rt2.text, "R5|" .. REALM .. "|lbrs|Spire Sprinters|2798|", 1, true), "P6 download v2 leaves the run out")
check(rt2 and string.find(rt2.text, "\nW5|" .. REALM .. "|lbrs|2798|" .. GK .. "\n", 1, true), "P6 download v2 carries the withdrawal (W5, no ok)")
check(rt2 and string.find(rt2.text, "R5|" .. REALM .. "|brd|Dark Irons|3000|", 1, true) == nil, "P6 (Bystander's run stays out: Pal never seen sharing)")
-- an offline v1 install (never heard the W) updates to v2
local off = newPC("Offline", { raidtimes = rt1 })
fire(off, "PLAYER_ENTERING_WORLD")
off.joined = false
check(board(off, "lbrs", GK) ~= nil, "P6 offline v1 install has the bad run")
off.env.WDI_RAIDTIMES = rt2
fire(off, "PLAYER_ENTERING_WORLD")
check(board(off, "lbrs", GK) == nil and out(off) and out(off).by == "the WhoDidIt download", "P6 updating to v2 takes it off")
-- a fresh v2 install never gets it, even from the 1.26.0 client
local fresh = newPC("Fresh", { raidtimes = rt2 })
fire(fresh, "PLAYER_ENTERING_WORLD")
fresh.joined = true
inject("Ludenlord", "WDIB1~D~lbrs~Spire Sprinters~2798~" .. RUN_D .. "~3~Alliance~Ludenlord:Wa,Shemp:Pr~1=420;5=1800;9=2798~" .. RUN_D)
check(board(fresh, "lbrs", GK) == nil, "P6 a fresh v2 install refuses the run from an old client")
check(table.getn(fresh.errors) == 0 and table.getn(off.errors) == 0, "P6 no errors")

----------------------------------------------------------------- P7: what stays home
-- a private run (someone in the group had 5-man sharing off): withdrawn locally, never sent
local pdb = { opts = { shareBoard = true }, dungeons = { [REALM] = { scholo = { ["Bystander,Pal"] = { g = "Quiet Ones", t = 2500, d = RUN_D,
	x = 0, f = "Alliance", n = 2, m = "Bystander:Ma,Pal:Pa", s = "", nt = RUN_D, by = "Bystander", priv = true } } } }, myRuns = {} }
PCS.Bystander = nil
local priv = newPC("Bystander", { db = pdb })
local nW = table.getn(sent("W"))
priv.R:Withdraw(REALM, "scholo", "Bystander,Pal", 2500)
tick(5)
check(board(priv, "scholo", "Bystander,Pal") == nil and table.getn(sent("W")) == nW, "P7 a private run is withdrawn locally, nothing sent")
check(printedHas(priv, "It's off your boards only"), "P7 chat says it stayed on this PC")
-- 5-man sharing off: local only
priv.env.WhoDidItDB.opts.no5man = true
priv.env.WhoDidItDB.dungeons[REALM].brd = { ["Bystander,Pal"] = { g = "Dark Irons", t = 3100, d = RUN_D, x = 0, f = "Alliance", n = 2,
	m = "Bystander:Ma,Pal:Pa", s = "", nt = RUN_D, by = "Bystander" } }
priv.R:Withdraw(REALM, "brd", "Bystander,Pal", 3100)
tick(5)
check(board(priv, "brd", "Bystander,Pal") == nil and table.getn(sent("W")) == nW, "P7 sharing off: withdrawn locally, nothing sent")
-- not your group: refused
local n0 = count(outs(shemp))
shemp.R:Withdraw(REALM, "brd", "Bystander,Pal", 3000)
check(count(outs(shemp)) == n0 and printedHas(shemp, "Only a member of the group can withdraw its run."), "P7 a non-member's withdraw is refused")
-- the same run can't come back on the withdrawer's own PC either (R:Merge)
check(shemp.R:Merge(REALM, "lbrs", GK, badRec("Shemp")) == false and board(shemp, "lbrs", GK) == nil, "P7 R:Merge refuses a withdrawn run")
check(string.len(sent("W")[1].msg) <= 255, "P7 the W record fits a chat line")

----------------------------------------------------------------- R: the masters' relay (1.31.0)
-- The master's save holds an N'Zoth run, a Horde run on this realm (its channel is Alliance) and an N'Zoth withdrawal:
-- it passes those on; this channel's own runs (Alliance, Y'Shaarj) are not sent again; nobody else can relay.
do
	local mdb = master.env.WhoDidItDB
	mdb.dungeons = mdb.dungeons or {}
	mdb.dungeons["N'Zoth"] = { stratud = { ["Far,Away"] = { g = "Northern Lights", t = 2400, d = RUN_D, x = 0, f = "Horde", n = 2,
		m = "Far:Wa,Away:Pr", s = "", nt = RUN_D, by = "Far" } } }
	mdb.dungeons[REALM] = mdb.dungeons[REALM] or {}
	mdb.dungeons[REALM].scholo = { ["Hordey,Orcy"] = { g = "Red Team", t = 2600, d = RUN_D, x = 1, f = "Horde", n = 2,
		m = "Hordey:Wa,Orcy:Sh", s = "", nt = RUN_D, by = "Hordey" } }
	mdb.dungeons[REALM].ubrs = { ["Allie,Ance"] = { g = "Blue Team", t = 3100, d = RUN_D, x = 0, f = "Alliance", n = 2,
		m = "Allie:Wa,Ance:Pr", s = "", nt = RUN_D, by = "Allie" } }
	mdb.runsWithdrawn = mdb.runsWithdrawn or {}
	mdb.runsWithdrawn["N'Zoth"] = { ["dme~Gone,Wrong~1500"] = { k = "dme", gk = "Gone,Wrong", t = 1500, at = math.floor(clock), hit = true } }
	local before, xBefore = table.getn(sent("M")), table.getn(sent("X"))
	-- (Shemp listens: a player on the master's channel)
	local bys = shemp
	tick(31)
	tick(30)   -- (the lines go out one every 1.6 s)
	local nz = bys.env.WhoDidItDB.dungeons["N'Zoth"]
	check(nz and nz.stratud and nz.stratud["Away,Far"] and nz.stratud["Away,Far"].relay and nz.stratud["Away,Far"].t == 2400,
		"R1 another realm's run reaches a player through the master")
	local here = bys.env.WhoDidItDB.dungeons[REALM]
	check(here and here.scholo and here.scholo["Hordey,Orcy"] and here.scholo["Hordey,Orcy"].f == "Horde",
		"R2 the other faction's run on this realm reaches the Alliance channel")
	check(not (here and here.ubrs and here.ubrs["Allie,Ance"]), "R3 this channel's own runs are not sent again")
	local w = bys.env.WhoDidItDB.runsWithdrawn and bys.env.WhoDidItDB.runsWithdrawn["N'Zoth"]
	check(w and w["dme~Gone,Wrong~1500"], "R4 a withdrawal on another realm is passed on too")
	check(table.getn(sent("X")) - xBefore == 1, "R4 only withdrawals that took a run off are passed on (the made-up flood is not)")
	local n1 = table.getn(sent("M"))
	tick(31)
	check(n1 > before and table.getn(sent("M")) == n1, "R5 each run is relayed once (" .. (n1 - before) .. " sent)")
	-- anyone who is not a master: ignored
	inject("Shemp", "WDIB1~M~N'Zoth~ubrs~Fake Fast~200~" .. RUN_D .. "~0~Horde~Shemp:Pr,Ludenlord:Wa~~" .. RUN_D)
	local nzu = bys.env.WhoDidItDB.dungeons["N'Zoth"] and bys.env.WhoDidItDB.dungeons["N'Zoth"].ubrs
	check(not nzu, "R6 a relay from someone not on the master list is ignored")
	-- someone logs in and asks: what was relayed half an hour ago goes out again
	clock = clock + 1900
	inject("Bystander", "WDIB1~Q")
	tick(31)
	check(table.getn(sent("M")) > n1, "R7 after someone asks, older relays go out again")
	for _, m in ipairs(sent("M")) do check(string.len(m.msg) <= 255, "R8 an M record fits a chat line") end
end

----------------------------------------------------------------- errors anywhere
for name, pc in pairs(PCS) do
	for _, e in ipairs(pc.errors) do print("  error on " .. name .. ": " .. e) end
end
local errs = 0
for _, pc in pairs(PCS) do errs = errs + table.getn(pc.errors) end
check(errs == 0, "no handler or timer raised an error")

print(string.format("%d passed, %d failed", passes, fails))
if fails > 0 then error("withdraw test failed") end
