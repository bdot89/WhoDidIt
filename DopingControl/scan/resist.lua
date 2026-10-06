if WDI_DOPING_SKIP then return end -- DopingControl scan/resist.lua
-- Pure resistance-reconstruction math: turn item TOOLTIP lines into a
-- per-school sum, and look up a race's innate bonus. Mirrors scan/hit.lua's
-- pure half (ParseHitLine/SumGear) one level down -- the constants live in
-- data/resist.lua, this file only turns them into behavior.
--
-- NO WoW-glue function lives here on purpose: unlike scan/hit.lua/scan/
-- gear.lua/scan/aura.lua, this module never calls SetInventoryItem itself.
-- The RESIST tab's numbers are reconstructed from tooltip lines
-- scan/hit.lua's item scan ALREADY fetched (see that file's itemHit()) --
-- one more table walk over data already in hand, not a second tooltip
-- operation per item. That is the entire point of hanging resistance
-- reconstruction off the HIT tab's existing per-item cache instead of
-- building an independent RESIST scan pass: 26 players x 19 slots would be
-- ~500 extra SetInventoryItem calls per scan, and scan/hit.lua already pays
-- that cost once per unique item.
--
-- Pure Lua 5.0, no WoW API, dofile-loadable offline: everything here is
-- offline-tested (test_resist.lua).

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Resist = DC_Resist or {}
local R = DC_Resist

-- ParseResistLine(text) -> kind, value | nil
--   kind  : a DC.RESIST_SCHOOLS name ("Fire", "Nature", ...) or "all"
--   value : the flat resistance amount as a number
-- Returns nil (a single value) when no pattern matches -- an unrecognized
-- phrasing is ignored, never guessed at (same contract as
-- DC_Hit.ParseHitLine).
function R.ParseResistLine(text)
    if type(text) ~= "string" then
        return nil
    end
    local pats = DC.RESIST_PATTERNS
    if type(pats) ~= "table" then
        return nil
    end
    local n = table.getn(pats)
    for i = 1, n do
        local e = pats[i]
        local _, _, cap = string.find(text, e.pattern)
        if cap then
            local v = tonumber(cap)
            if v then
                return e.kind, v
            end
        end
    end
    return nil
end

-- SumLines(lines) -> sum
--   lines : the FULL tooltip line array of ONE item, element 1 = item name
--           (same convention as scan/hit.lua's itemHit -- line 1 is never
--           a stat line, so the scan starts at 2; a caller that already
--           stripped the name may safely pass an array starting at the
--           real first stat line too, since no genuine item name matches
--           "^%+%d+ <School> Resistance" or "^Equip: %+%d+ All
--           Resistances" in the first place).
--   sum   : { [UnitResistance school index] = total } -- ONLY schools
--           that actually appeared; a plain item with no resistance stat
--           returns {} (empty, not nil) -- an empty sum is a real "this
--           item carries no resistance", exactly like SumGear's zero.
-- The "All Resistances" trap this table exists to close: a naive parser
-- keyed only on the five single-school patterns would silently skip
-- "Equip: +8 All Resistances." and undercount every one of the five
-- columns by that amount. Handled here by fanning ONE matched line out
-- over every entry of DC.RESIST_SCHOOLS.
function R.SumLines(lines)
    local sum = {}
    lines = lines or {}
    local n = table.getn(lines)
    for i = 2, n do
        local kind, v = R.ParseResistLine(lines[i])
        if kind then
            if kind == "all" then
                local schools = DC.RESIST_SCHOOLS or {}
                for s = 1, table.getn(schools) do
                    local school = schools[s].school
                    sum[school] = (sum[school] or 0) + v
                end
            else
                local num = DC.RESIST_SCHOOL_NUM and DC.RESIST_SCHOOL_NUM[kind]
                if num then
                    sum[num] = (sum[num] or 0) + v
                end
            end
        end
    end
    return sum
end

-- RaceBonus(race) -> { [UnitResistance school index] = bonus }
-- ALWAYS returns a table (empty for "no bonus", an unrecognized race
-- token/display name, or nil input) so callers can fold it onto a gear sum
-- without a nil check. The returned table is a FRESH COPY, never the
-- shared DC.RACE_RESIST entry itself -- DC.RACE_RESIST aliases two
-- spellings of the same race to ONE table object, so handing that
-- reference out would let a caller's in-place addition (E.AssembleResists
-- folds this straight onto the gear sum) corrupt the shared constant for
-- every future lookup of that race.
function R.RaceBonus(race)
    local out = {}
    local tbl = race and DC.RACE_RESIST and DC.RACE_RESIST[race]
    if tbl then
        for school, v in pairs(tbl) do
            out[school] = v
        end
    end
    return out
end
