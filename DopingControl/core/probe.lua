if WDI_DOPING_SKIP then return end -- DopingControl core/probe.lua
-- Feasibility probe: dumps RAW API returns to dc_probe.txt (in the WoW
-- client's Imports folder) via SuperWoW ExportFile so raw facts can be read
-- from disk instead of retyped from chat lines.
--
-- Entry points (core/init.lua wires the slash command):
--   DC_Probe.HandleSlash(rest) -- rest = text after "probe":
--       ""             -> Battery()          (part 2, near-range questions)
--       "range <name>" -> RangeStart(name) / RangeStop() toggle (part 1)
--   DC_Probe.Battery()
--   DC_Probe.RangeStart(playerName) / DC_Probe.RangeStop()
--   DC_Probe.IsRangeRunning()
--
-- Part 1 (range run): a raid member with known buffs walks away; a 1 Hz
-- poller writes one line per tick:
--   dist | UnitExists | UnitIsVisible | nA=count(UnitBuff) | 4th-return |
--   nB=count(GetUnitField) | UnitPosition
-- The unit token is RE-RESOLVED from the name every tick (raid indices are
-- volatile after roster changes).
--
-- Part 2 (battery) answers five open client-behavior questions with raw data:
--   Q1 does UnitBuff(unit, i) return a 4th value ~= nil (spell id)?
--   Q2 does GetUnitField(guid,"aura") match the tooltip names; is the
--      slot split really 1-32 buffs / 33-48 debuffs?
--   Q3 does GetWeaponEnchantInfo(unit) name a foreign temp enchant?
--   Q4 does GetInventoryItemLink(unit, slot) serve out-of-sight units?
--   Q5 is the ENCHANT field in foreign item links filled (~= 0)?
--
-- File mechanics: ExportFile appends ".txt" ITSELF -- the name is passed
-- WITHOUT extension ("dc_probe", never "dc_probe.txt"). ExportFile is a
-- whole-file overwrite, so the probe keeps an in-memory ring of lines and
-- rewrites the complete file on every flush.
--
-- Pure Lua 5.0, dofile-loadable offline (all WoW usage inside functions /
-- existence-checked; the poller frame is created lazily in-game).

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Probe = DC_Probe or {}
local P = DC_Probe

P.RING_CAP = 2000          -- max lines kept; oldest dropped first
P.EXPORT_NAME = "dc_probe" -- NO extension (ExportFile appends .txt)
P.BATTERY_UNIT_CAP = 8     -- full detail for at most N foreign units

local ring = {}

-- ------------------------------------------------------------------
-- ring + flush
-- ------------------------------------------------------------------
function P.Clear()
    ring = {}
end

function P.Push(line)
    table.insert(ring, line)
    while table.getn(ring) > P.RING_CAP do
        table.remove(ring, 1)
    end
end

function P.Text()
    return table.concat(ring, "\n")
end

local function say(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffe6c87eDopingControl|r probe: " .. msg)
    end
end

function P.Flush()
    if ExportFile then
        -- name WITHOUT extension -- ExportFile appends .txt itself.
        -- pcall: optional-DLL call -- a DLL-side I/O error
        -- must not escape into the slash handler or the 1 Hz range ticker.
        local ok = pcall(ExportFile, P.EXPORT_NAME, P.Text())
        if not ok then
            say("ExportFile failed - dump not written")
            return false
        end
        return true
    end
    say("ExportFile missing (SuperWoW required) - dump not written")
    return false
end

-- ------------------------------------------------------------------
-- formatting helpers
-- ------------------------------------------------------------------
local function fmt(v)
    if v == nil then
        return "nil"
    end
    if v == true then
        return "true"
    end
    if v == false then
        return "false"
    end
    if type(v) == "number" then
        return tostring(v)
    end
    if type(v) == "string" then
        return v
    end
    return type(v)
end

local function gtype(name)
    local v = getglobal and getglobal(name)
    if v == nil then
        return "nil"
    end
    return type(v)
end

local function nowStamp()
    if date then
        return date("%Y-%m-%d %H:%M:%S")
    end
    return "?"
end

local function header(kind)
    P.Push("=== DopingControl probe " .. kind .. " " .. nowStamp() .. " ===")
    P.Push("client: TURTLE_WOW_VERSION=" .. fmt(TURTLE_WOW_VERSION)
        .. " SUPERWOW_VERSION=" .. fmt(SUPERWOW_VERSION))
    P.Push("dll-surface: UnitXP=" .. gtype("UnitXP")
        .. " GetUnitField=" .. gtype("GetUnitField")
        .. " ExportFile=" .. gtype("ExportFile")
        .. " UnitPosition=" .. gtype("UnitPosition"))
end

-- resolve a roster unit token by player name; nil if not in group.
-- Re-run every use: raid indices are volatile.
local function resolveUnit(name)
    if not UnitName then
        return nil
    end
    local lower = string.lower(name)
    local nraid = (GetNumRaidMembers and GetNumRaidMembers()) or 0
    if nraid > 0 then
        for i = 1, nraid do
            local ok, nm = pcall(UnitName, "raid" .. i)
            if ok and nm and string.lower(nm) == lower then
                return "raid" .. i
            end
        end
        return nil
    end
    for i = 1, 4 do
        local ok, nm = pcall(UnitName, "party" .. i)
        if ok and nm and string.lower(nm) == lower then
            return "party" .. i
        end
    end
    return nil
end

local function unitGuid(unit)
    if not UnitExists then
        return nil
    end
    local ok, ex, g = pcall(UnitExists, unit)
    if ok and ex and g then
        return g
    end
    return nil
end

-- count UnitBuff entries + first non-nil 4th return
local function pathACounts(unit)
    local n = 0
    local firstId = nil
    local idCount = 0
    if UnitBuff then
        for i = 1, 32 do
            local ok, tex, stacks, dtype, id4 = pcall(UnitBuff, unit, i)
            if not ok or not tex then
                break
            end
            n = n + 1
            if type(id4) == "number" and id4 > 0 then
                idCount = idCount + 1
                if not firstId then
                    firstId = id4
                end
            end
        end
    end
    return n, firstId, idCount
end

-- GetUnitField(guid,"aura") -> comma list for a slot range (sparse table)
local function pathBList(guid, from, to)
    if not GetUnitField or not guid then
        return nil, 0
    end
    local ok, t = pcall(GetUnitField, guid, "aura")
    if not ok then
        return "ERR", 0
    end
    if type(t) ~= "table" then
        return "type=" .. type(t), 0
    end
    local parts = {}
    local n = 0
    for i = from, to do
        local v = t[i]
        if type(v) == "number" and v > 0 then
            n = n + 1
            table.insert(parts, i .. ":" .. v)
        end
    end
    if n == 0 then
        return "-", 0
    end
    return table.concat(parts, ","), n
end

-- ------------------------------------------------------------------
-- Part 2: the battery (/dc probe)
-- ------------------------------------------------------------------
function P.Battery()
    if not UnitName then
        say("no client APIs (offline?) - battery skipped")
        return false
    end
    P.Clear()
    header("battery")

    local roster = (DC_Scan and DC_Scan.BuildRoster and DC_Scan.BuildRoster()) or {}
    local total = table.getn(roster)
    P.Push("roster: " .. total .. " units; full detail for the first "
        .. P.BATTERY_UNIT_CAP .. " foreign units")
    P.Push("")

    -- self weapon enchant baseline (vanilla 6-return form)
    if GetWeaponEnchantInfo then
        local ok, r1, r2, r3, r4, r5, r6 = pcall(GetWeaponEnchantInfo)
        P.Push("self GetWeaponEnchantInfo(): ok=" .. fmt(ok)
            .. " hasMain=" .. fmt(r1) .. " mainExp=" .. fmt(r2)
            .. " mainCharges=" .. fmt(r3) .. " hasOff=" .. fmt(r4)
            .. " offExp=" .. fmt(r5) .. " offCharges=" .. fmt(r6))
    else
        P.Push("self GetWeaponEnchantInfo(): API missing")
    end
    P.Push("")

    local detailed = 0
    for r = 1, total do
        local e = roster[r]
        local isSelf = false
        if UnitIsUnit then
            local ok, v = pcall(UnitIsUnit, e.unit, "player")
            isSelf = (ok and v) and true or false
        end
        if not isSelf and detailed < P.BATTERY_UNIT_CAP then
            detailed = detailed + 1
            local guid = unitGuid(e.unit)
            local online, dist = DC_Reach.ReadUnit(e.unit)
            P.Push("--- " .. e.unit .. " name=" .. fmt(e.name)
                .. " class=" .. fmt(e.class) .. " online=" .. fmt(online)
                .. " dist=" .. fmt(dist) .. " guid=" .. fmt(guid))

            -- Q1: UnitBuff rows with 4th return + tooltip name
            if UnitBuff then
                local rows = 0
                for i = 1, 32 do
                    local ok, tex, stacks, dtype, id4 = pcall(UnitBuff, e.unit, i)
                    if not ok or not tex then
                        break
                    end
                    rows = rows + 1
                    local tipName = nil
                    -- same hidden tooltip as scan/aura.lua (shared accessor,
                    -- never a second frame under the same global name)
                    local tip = DC_Aura and DC_Aura.GetScanTip
                        and DC_Aura.GetScanTip()
                    if tip then
                        local ok2 = pcall(function()
                            tip:ClearLines()
                            tip:SetUnitBuff(e.unit, i)
                        end)
                        if ok2 then
                            local obj = getglobal("DopingControlScanTipTextLeft1")
                            if obj then
                                tipName = obj:GetText()
                            end
                        end
                    end
                    P.Push("Q1 UnitBuff i=" .. i .. " tex=" .. fmt(tex)
                        .. " stacks=" .. fmt(stacks) .. " dtype=" .. fmt(dtype)
                        .. " id4=" .. fmt(id4) .. " tipName=" .. fmt(tipName))
                end
                local nA, firstId, idCount = pathACounts(e.unit)
                P.Push("Q1 summary: buffs=" .. nA .. " id4nonNil=" .. idCount
                    .. " (id4 ~= nil answers Q1)")
            else
                P.Push("Q1 UnitBuff: API missing")
            end

            -- Q2: descriptor list, buff and debuff halves separately
            local buffList = pathBList(guid, 1, 32)
            local debuffList = pathBList(guid, 33, 48)
            P.Push("Q2 GetUnitField(guid,\"aura\") slots1-32=" .. fmt(buffList))
            P.Push("Q2 GetUnitField(guid,\"aura\") slots33-48=" .. fmt(debuffList)
                .. " (compare vs UnitBuff names above -> slot-split check)")

            -- Q3: foreign weapon enchant name
            if GetWeaponEnchantInfo then
                local ok, w1, w2 = pcall(GetWeaponEnchantInfo, e.unit)
                P.Push("Q3 GetWeaponEnchantInfo(unit): ok=" .. fmt(ok)
                    .. " r1=" .. fmt(w1) .. " r2=" .. fmt(w2))
            end

            -- Q4/Q5: inventory links, raw + parsed enchant field.
            -- subType (GetItemInfo return 6, de-shifted by DC_Gear.ItemInfo)
            -- is dumped per slot to verify the DC.ENCH_EXEMPT [ASSUMPTION]
            -- strings against reality (data/enchants.lua).
            local slots = DC_Gear.InvSlots()
            local linkCount = 0
            for s = 1, table.getn(slots) do
                local inv = slots[s]
                local ok, link = pcall(GetInventoryItemLink, e.unit, inv)
                if ok and link then
                    linkCount = linkCount + 1
                    local id, ench = DC_Gear.ParseLink(link)
                    local subType = nil
                    if id then
                        local _, _, st = DC_Gear.ItemInfo(id)
                        subType = st
                    end
                    P.Push("Q4/Q5 slot" .. inv .. " link=" .. fmt(link)
                        .. " -> id=" .. fmt(id) .. " ench=" .. fmt(ench)
                        .. " subType=" .. fmt(subType))
                end
            end
            P.Push("Q4 summary: " .. linkCount .. "/" .. table.getn(slots)
                .. " slots returned a link (0 for an out-of-sight unit"
                .. " answers Q4 negatively)")
            P.Push("Q5b: subType above checks the ENCH_EXEMPT assumption"
                .. " strings - expected \"Wands\"/\"Thrown\" (slot 18) and"
                .. " \"Miscellaneous\" (slot 17), data/enchants.lua")

            -- Q6: resistance read paths (RESIST tab, scan/engine.lua
            -- readResists) -- school 2 (Fire) as a representative probe,
            -- all three paths dumped raw: does UnitResistance answer for a
            -- foreign unit token, does it also accept the GUID directly,
            -- and does GetUnitField(guid,"resistances") carry a usable
            -- table at all -- or does a foreign read silently return 0?
            if UnitResistance then
                local ok1, base1, total1 = pcall(UnitResistance, e.unit, 2)
                P.Push("Q6 UnitResistance(unit,2): ok=" .. fmt(ok1)
                    .. " base=" .. fmt(base1) .. " total=" .. fmt(total1))
                if guid then
                    local ok2, base2, total2 = pcall(UnitResistance, guid, 2)
                    P.Push("Q6 UnitResistance(guid,2): ok=" .. fmt(ok2)
                        .. " base=" .. fmt(base2) .. " total=" .. fmt(total2))
                end
            else
                P.Push("Q6 UnitResistance: API missing")
            end
            if guid and GetUnitField then
                local ok3, t = pcall(GetUnitField, guid, "resistances")
                if ok3 and type(t) == "table" then
                    P.Push("Q6 GetUnitField(guid,\"resistances\"): [1]="
                        .. fmt(t[1]) .. " [2]=" .. fmt(t[2]) .. " [3]="
                        .. fmt(t[3]) .. " [4]=" .. fmt(t[4]) .. " [5]="
                        .. fmt(t[5]) .. " [6]=" .. fmt(t[6]) .. " [7]="
                        .. fmt(t[7]))
                else
                    P.Push("Q6 GetUnitField(guid,\"resistances\"): ok="
                        .. fmt(ok3) .. " type=" .. type(t))
                end
            end
            P.Push("")
        end
    end
    if detailed == 0 then
        P.Push("no foreign units in group - battery needs a party/raid")
    end

    local written = P.Flush()
    if written then
        say("battery done (" .. detailed .. " foreign units) -> "
            .. P.EXPORT_NAME .. ".txt")
    end
    return written
end

-- ------------------------------------------------------------------
-- Part 1: the 1 Hz range run (/dc probe range <name>)
-- ------------------------------------------------------------------
local rangeFrame = nil
local rangeName = nil
local rangeRunning = false
local rangeAcc = 0
local rangeT0 = 0

local function rangeTick()
    local t = (GetTime and GetTime()) or 0
    local rel = math.floor(t - rangeT0 + 0.5)
    local unit = resolveUnit(rangeName)
    if not unit then
        P.Push("t=" .. rel .. "s target '" .. rangeName .. "' not in roster")
        P.Flush()
        return
    end
    local guid = unitGuid(unit)

    local dist = nil
    if UnitXP then
        local ok, d = pcall(UnitXP, "distanceBetween", "player", unit)
        if ok and type(d) == "number" then
            dist = d
        end
    end
    local exists = nil
    if UnitExists then
        local ok, ex = pcall(UnitExists, unit)
        if ok then
            exists = ex
        end
    end
    local visible = nil
    if UnitIsVisible then
        local ok, v = pcall(UnitIsVisible, unit)
        if ok then
            visible = v
        end
    end
    local nA, firstId = pathACounts(unit)
    local _, nB = pathBList(guid, 1, 32)
    local pos = "nil"
    if UnitPosition and guid then
        local ok, x, y = pcall(UnitPosition, guid)
        if ok and type(x) == "number" then
            pos = "ok(" .. string.format("%.1f", x) .. ","
                .. string.format("%.1f", y or 0) .. ")"
        end
    end

    -- part-1 column order (matches the header line written by RangeStart)
    P.Push("t=" .. rel .. "s unit=" .. unit
        .. " dist=" .. fmt(dist)
        .. " exists=" .. fmt(exists)
        .. " visible=" .. fmt(visible)
        .. " nA=" .. nA
        .. " id4first=" .. fmt(firstId)
        .. " nB=" .. nB
        .. " pos=" .. pos)
    P.Flush()
end

function P.IsRangeRunning()
    return rangeRunning
end

function P.RangeStart(name)
    if not CreateFrame then
        say("no client (offline) - range run unavailable")
        return false
    end
    if rangeRunning then
        say("range run already active for " .. fmt(rangeName)
            .. " - stop it first (/dc probe range)")
        return false
    end
    rangeName = name
    rangeRunning = true
    rangeAcc = 0
    rangeT0 = (GetTime and GetTime()) or 0
    P.Clear()
    header("range-run target=" .. name)
    P.Push("columns: t | unit | dist | exists | visible | nA=count(UnitBuff) |"
        .. " id4first | nB=count(GetUnitField slots 1-32) | pos=UnitPosition")
    if not rangeFrame then
        rangeFrame = CreateFrame("Frame", "DopingControlProbeFrame")
    end
    rangeFrame:SetScript("OnUpdate", function()
        rangeAcc = rangeAcc + (arg1 or 0)
        if rangeAcc >= 1.0 then
            rangeAcc = 0
            rangeTick()
        end
    end)
    say("range run started, target " .. name .. ", 1 Hz -> "
        .. P.EXPORT_NAME .. ".txt (stop: /dc probe range " .. name .. ")")
    return true
end

function P.RangeStop()
    if rangeFrame then
        rangeFrame:SetScript("OnUpdate", nil)
    end
    if rangeRunning then
        rangeRunning = false
        P.Push("=== range run stopped " .. nowStamp() .. " ===")
        P.Flush()
        say("range run stopped, " .. table.getn(ring) .. " lines in "
            .. P.EXPORT_NAME .. ".txt")
    end
    rangeName = nil
end

-- ------------------------------------------------------------------
-- slash glue: rest of the line after "probe"
-- ------------------------------------------------------------------
function P.HandleSlash(rest)
    rest = rest or ""
    rest = string.gsub(rest, "^%s+", "")
    rest = string.gsub(rest, "%s+$", "")
    if rest == "" then
        return P.Battery()
    end
    local _, _, word = string.find(rest, "^(%S+)")
    if word and string.lower(word) == "range" then
        if rangeRunning then
            P.RangeStop()
            return true
        end
        local _, _, name = string.find(rest, "^%S+%s+(.+)$")
        if name then
            return P.RangeStart(name)
        end
        say("usage: /dc probe range <playername>")
        return false
    end
    say("usage: /dc probe  |  /dc probe range <playername>")
    return false
end
