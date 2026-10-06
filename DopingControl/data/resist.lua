if WDI_DOPING_SKIP then return end -- DopingControl data/resist.lua
-- Resistance-reconstruction tables for the RESIST tab: what GEAR tooltips
-- and RACE grant, mirroring data/hit.lua's split for the HIT tab (patterns
-- + constants here, the pure parser in scan/resist.lua).
--
-- WHY RECONSTRUCTION (measured, not assumed -- see scan/hit.lua's header
-- for the full story): the server does not transmit
-- UNIT_FIELD_RESISTANCES for foreign players at all (Player::
-- InitVisibleBits() never sets the bit for anyone but the owning client),
-- so UnitResistance/GetUnitField can NEVER answer for a foreign unit --
-- this is not a corner case scan/engine.lua's three read paths occasionally
-- miss, it is the only path that can ever ANSWER for one. The equipped
-- items' tooltips are readable for foreign units in range
-- (GameTooltip:SetInventoryItem), exactly like the HIT tab's +hit lines,
-- so the total is rebuilt from the same source: item stat text, plus the
-- racial bonus below (which no tooltip ever states).
--
-- DC.RESIST_SCHOOLS -- the five schools that carry a resistance stat, in
-- TOOLTIP capitalization ("Fire Resistance"), paired with the
-- UnitResistance() school index used throughout the addon (core/const.lua
-- DC.SLOTS_RESIST: 2 fire / 3 nature / 4 frost / 5 shadow / 6 arcane; 0
-- physical and 1 holy are never queried -- there is no "Holy Resistance"
-- item stat in 1.12, which is also why this list has no sixth entry).
-- Kept in sync with DC.SLOTS_RESIST BY HAND (self-contained, like
-- DC.HIT_SCHOOLS/DC.SLOTS_HIT in data/hit.lua and core/const.lua) --
-- test_resist.lua pins the two against each other so they cannot drift
-- apart silently.
DopingControl = DopingControl or {}
local DC = DopingControl

DC.RESIST_SCHOOLS = {
    { name = "Fire",   school = 2 },
    { name = "Nature", school = 3 },
    { name = "Frost",  school = 4 },
    { name = "Shadow", school = 5 },
    { name = "Arcane", school = 6 },
}

-- DC.RESIST_SCHOOL_NUM -- tooltip school name -> UnitResistance() index,
-- GENERATED from DC.RESIST_SCHOOLS so the two tables cannot drift apart
-- (same idea as DC.HIT_SCHOOL_KEY in data/hit.lua).
DC.RESIST_SCHOOL_NUM = {}
for i = 1, table.getn(DC.RESIST_SCHOOLS) do
    local e = DC.RESIST_SCHOOLS[i]
    DC.RESIST_SCHOOL_NUM[e.name] = e.school
end

-- ------------------------------------------------------------------
-- DC.RESIST_PATTERNS -- ARRAY (order matters, FIRST MATCH WINS), each
-- entry { pattern = <Lua 5.0 string.find pattern with ONE numeric
-- capture>, kind = <school name> | "all" }.
--
-- Measured tooltip forms (2026-08-02, own-character tooltip, English
-- client):
--   "+10 Arcane Resistance"          -- PLAIN stat line, no "Equip:"
--   "+10 Fire Resistance"            -- (item base stats print this way,
--   "+10 Nature Resistance"          --  unlike +hit which is always an
--   "+1 Fire Resistance"             --  "Equip:" trigger line)
--   "Equip: +8 All Resistances."     -- multi-school EQUIP trigger --
--                                       applies to ALL FIVE schools at
--                                       once; a parser keyed on the five
--                                       single-school patterns alone would
--                                       silently miss this line entirely
--                                       (the trap this table exists to
--                                       close, see scan/resist.lua
--                                       R.SumLines).
--
-- Both anchored at the LINE START (^): a stat line is the line's entire
-- content on this client, so anchoring guards against a flavor-text
-- sentence that happens to contain "Fire Resistance" mid-phrase. No
-- trailing anchor: the plain form has nothing after the number+word (WoW
-- classic tooltip text is fixed, so this cannot mismatch), and the Equip
-- form is allowed to keep trailing punctuation.
--
-- Extension point (mirrors DC.HIT_PATTERNS): a phrasing not listed here is
-- SILENTLY IGNORED, never guessed at. An "Equip: +N <School> Resistance."
-- single-school equip form is conceivable on this server but UNMEASURED --
-- it is deliberately absent until someone reads it off a real tooltip.
-- ------------------------------------------------------------------
DC.RESIST_PATTERNS = {}
for i = 1, table.getn(DC.RESIST_SCHOOLS) do
    local e = DC.RESIST_SCHOOLS[i]
    table.insert(DC.RESIST_PATTERNS, {
        pattern = "^%+(%d+) " .. e.name .. " Resistance",
        kind = e.name,
    })
end
table.insert(DC.RESIST_PATTERNS, {
    pattern = "^Equip: %+(%d+) All Resistances",
    kind = "all",
})

-- ------------------------------------------------------------------
-- DC.RACE_RESIST -- race -> { [UnitResistance school index] = bonus }.
-- INNATE racial resistance, granted by the race itself rather than any
-- item -- invisible to a tooltip scan, so it has to be added on top of the
-- gear sum by hand (scan/engine.lua's E.AssembleResists gear-fallback
-- path) or the reconstructed total would silently understate every member
-- of these five races by exactly this amount.
--
-- Keys: BOTH spellings for every race that has a bonus (display name and
-- file token), same reasoning as DC.RACE_WEAPON_SKILL in data/hit.lua --
-- scan/hit.lua's H.ReadUnit stores `token or display` as the race passed
-- through the store, so either spelling must resolve. Aliases point at the
-- SAME table (never a separate copy), so a race can never end up counted
-- with two different bonus tables that could drift apart.
--
-- Verified racial resistances (task brief, 2026-08-02):
--   Dwarf            +10 Frost
--   Gnome             +10 Arcane
--   Night Elf         +10 Nature
--   Tauren            +10 Nature
--   Undead/Forsaken   +10 Shadow
--   Human, Orc, Troll: none
--
-- WARNING -- NOT COVERED: TurtleWoW's two extra playable races, Goblin and
-- High Elf/Blood Elf. Their racial resistance (if they even have one) is
-- UNKNOWN -- it is not guessed here. Both are simply ABSENT from this
-- table, which is safe by construction: DC_Resist.RaceBonus (scan/
-- resist.lua) returns an empty bonus table for any race it does not
-- recognize, exactly the same degrade an unlisted/future race token gets.
-- Do not "fix" this by inventing a number -- add the real one once it is
-- measured, the same way the five below were.
-- ------------------------------------------------------------------
local DWARF_RESIST    = { [4] = 10 }  -- frost
local GNOME_RESIST    = { [6] = 10 }  -- arcane
local NIGHTELF_RESIST = { [3] = 10 }  -- nature
local TAUREN_RESIST   = { [3] = 10 }  -- nature
local UNDEAD_RESIST   = { [5] = 10 }  -- shadow

DC.RACE_RESIST = {
    ["Dwarf"]     = DWARF_RESIST,
    ["Gnome"]     = GNOME_RESIST,
    ["Night Elf"] = NIGHTELF_RESIST,
    ["NightElf"]  = NIGHTELF_RESIST,
    ["Tauren"]    = TAUREN_RESIST,
    ["Undead"]    = UNDEAD_RESIST,
    ["Scourge"]   = UNDEAD_RESIST,
}
