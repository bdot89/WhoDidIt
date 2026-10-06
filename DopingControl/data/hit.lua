if WDI_DOPING_SKIP then return end -- DopingControl data/hit.lua
-- Hit-chance tables for the HIT tab: what GEAR and AURAS contribute, plus
-- the caps every column is judged against. The third contributor,
-- TALENTS, lives in its own file (data/talenthit.lua) because it is a
-- different kind of source -- looked up by talent name and rank rather
-- than parsed out of a tooltip.
--
-- WHY TOOLTIP PARSING (measured, not assumed): this client family exposes
-- NO hit API at all -- GetHitModifier, GetSpellHitModifier and
-- GetCombatRating are all absent (verified on the live client). The only
-- readable source of a player's +hit is the text of the equipped items'
-- tooltips, which IS readable for foreign units in range via
-- GameTooltip:SetInventoryItem(unit, slot). Everything in this file exists
-- to turn those tooltip lines into a number and to bound that number
-- against the caps of the current patch.
--
-- WHAT CANNOT BE READ (in principle, not a missing feature): a foreign
-- player's WEAPON SKILL. The server never sends PLAYER_SKILL_INFO for
-- anyone but the own character and no inspect-skill channel exists, so
-- weapon skill is MEASURED for the own character (GetSkillLineInfo, see
-- scan/hit.lua) and ESTIMATED for everyone else -- base skill + racial
-- specialization + an optional per-player "weapon skill book" flag the
-- user sets in the options. Every consumer must present the foreign value
-- as an assumption, never as a measurement.
--
-- PATCH BASIS (current server patch): weapon-skill scaling was rewritten
-- to LINEAR, the old 305-skill breakpoint was removed and the hidden 1%
-- suppression was dropped. Consequences encoded below: the yellow melee
-- hit cap against a boss three levels above the player is 8% (it was 9%
-- before the rewrite) and the dual-wield WHITE cap is 27%. The spell hit
-- cap is 16%, derived from the server's own clamp (see DC.HIT_CAPS below)
-- rather than measured -- it is a single constant here so a later
-- correction changes one line.
--
-- English client assumed: both the tooltip patterns and the weapon-skill
-- names below are English strings. On a localized client nothing matches
-- and the hit columns simply read 0 rather than showing wrong numbers.
--
-- Pure Lua 5.0, no WoW API -- dofile-loadable offline.

DopingControl = DopingControl or {}
local DC = DopingControl

-- ------------------------------------------------------------------
-- Magic schools that can carry a school-specific spell-hit line.
-- Order is display order for tooltip detail lines.
--
-- The CAPITALIZED spelling is load-bearing twice over: it is the word that
-- appears in the item tooltip ("Improves your chance to hit with Fire
-- spells by 1%"), so it is both the generated pattern text below and the
-- key of the parsed `schools` table.
-- ------------------------------------------------------------------
DC.HIT_SCHOOLS = { "Arcane", "Fire", "Frost", "Holy", "Nature", "Shadow" }

-- ------------------------------------------------------------------
-- DC.HIT_SCHOOL_KEY -- lowercase school id -> the CAPITALIZED key used by
-- everything that came out of a tooltip.
--
-- Two spellings exist because two sources exist and neither may be bent to
-- the other: tooltip text dictates "Fire", while the column definitions
-- (DC.SLOTS_HIT, core/const.lua) and the talent tables
-- (DC.TALENT_HIT, data/talenthit.lua) are hand-written data that follows
-- the file-wide lowercase-id convention. This table is GENERATED from
-- DC.HIT_SCHOOLS so the two can never drift apart, and DC_Hit.SchoolHit
-- (scan/hit.lua) is the one function callers should use instead of
-- indexing either table by hand.
-- ------------------------------------------------------------------
DC.HIT_SCHOOL_KEY = {}
for i = 1, table.getn(DC.HIT_SCHOOLS) do
    local school = DC.HIT_SCHOOLS[i]
    DC.HIT_SCHOOL_KEY[string.lower(school)] = school
end

-- ------------------------------------------------------------------
-- DC.HIT_PATTERNS -- ARRAY (order matters, FIRST MATCH WINS), each entry
--   { pattern = <Lua 5.0 string.find pattern with ONE numeric capture>,
--     kind    = "melee" | "spell" | "both" | <school name> }
--
-- kind semantics (folded by DC_Hit.SumGear):
--   "melee"  generic physical hit. 1.12 has no separate ranged-hit affix:
--            the same "chance to hit" line applies to melee AND ranged
--            attacks, so the MELEE bucket feeds both hit columns.
--   "spell"  spell hit against every school.
--   "both"   "spells and attacks": adds to melee AND spell.
--   <school> school-specific spell hit (e.g. "Fire"): it does NOT raise
--            the general spell-hit number, it is carried separately and
--            shown as an extra, because it only helps that one school.
--
-- Ordering rule: the more specific phrasings come first. The four
-- phrasings do not actually overlap as literals ("hit with spells and
-- attacks by", "hit with Fire spells by", "hit with spells by", "hit by"),
-- but the order keeps that from becoming load-bearing if a pattern is ever
-- widened.
--
-- Extension point: a phrasing that is not listed here is SILENTLY IGNORED
-- (never guessed at). Server-custom item text that grants hit therefore
-- needs its pattern added here -- this table is the single place.
-- ------------------------------------------------------------------
DC.HIT_PATTERNS = {
    -- combined affix ("spells and attacks")
    { pattern = "Improves your chance to hit with spells and attacks by (%d+)%%",
      kind = "both" },
}

-- school-specific spell hit, generated so the school list stays the single
-- source of truth ("Improves your chance to hit with Fire spells by 1%")
for i = 1, table.getn(DC.HIT_SCHOOLS) do
    local school = DC.HIT_SCHOOLS[i]
    table.insert(DC.HIT_PATTERNS, {
        pattern = "Improves your chance to hit with " .. school
            .. " spells by (%d+)%%",
        kind = school,
    })
end

-- general spell hit, then the generic (melee + ranged) hit line
table.insert(DC.HIT_PATTERNS,
    { pattern = "Improves your chance to hit with spells by (%d+)%%",
      kind = "spell" })
table.insert(DC.HIT_PATTERNS,
    { pattern = "Improves your chance to hit by (%d+)%%",
      kind = "melee" })

-- ------------------------------------------------------------------
-- DC.WEAPON_SKILL_OF_SUBTYPE -- GetItemInfo itemSubType -> weapon SKILL
-- name (the string GetSkillLineInfo reports for that weapon).
--
-- Absent key = "not a weapon" and that is load-bearing: off-hand items
-- whose subtype is missing here (shields, held-in-off-hand items, totems,
-- idols, librams, fishing poles) are what tells the caller that the player
-- is NOT dual-wielding.
--
-- Verified live on this client: "One-Handed Maces" (plus the non-weapon
-- subtypes "Shields" and "Totems", deliberately absent). The remaining
-- strings follow the standard 1.12 weapon subclass naming and are
-- UNVERIFIED -- each one is only a lookup key, so a wrong string degrades
-- to "unknown weapon" (no skill assumption, no dual-wield claim), never to
-- a wrong number.
--
-- Two mappings are worth calling out:
--   "Fist Weapons" -> "Unarmed": fist weapons run on the Unarmed skill
--     line, they have no skill of their own.
--   "Wands" -> "Wands": the skill line exists, but whether wand attacks
--     obey weapon skill or spell hit is DISPUTED on this patch. The
--     mapping only names the skill line; the ranged hit column
--     deliberately ignores wands (see DC.RANGED_ATTACK_SUBTYPE).
-- ------------------------------------------------------------------
DC.WEAPON_SKILL_OF_SUBTYPE = {
    ["One-Handed Axes"]   = "Axes",
    ["Two-Handed Axes"]   = "Two-Handed Axes",
    ["One-Handed Maces"]  = "Maces",              -- verified live
    ["Two-Handed Maces"]  = "Two-Handed Maces",
    ["One-Handed Swords"] = "Swords",
    ["Two-Handed Swords"] = "Two-Handed Swords",
    ["Daggers"]           = "Daggers",
    ["Fist Weapons"]      = "Unarmed",            -- see header
    ["Polearms"]          = "Polearms",
    ["Staves"]            = "Staves",
    ["Bows"]              = "Bows",
    ["Crossbows"]         = "Crossbows",
    ["Guns"]              = "Guns",
    ["Thrown"]            = "Thrown",
    ["Wands"]             = "Wands",              -- see header
}

-- Subtypes that make the RANGED hit question meaningful, i.e. things that
-- actually swing as a ranged ATTACK. Wands are excluded on purpose (their
-- hit mechanic is disputed, see above) and so is every non-weapon relic;
-- a player without one of these gets no ranged hit column value at all.
DC.RANGED_ATTACK_SUBTYPE = {
    ["Bows"]      = true,
    ["Crossbows"] = true,
    ["Guns"]      = true,
    ["Thrown"]    = true,
}

-- ------------------------------------------------------------------
-- DC.CLASS_WEAPON_SKILLS -- class token -> ordered array of the weapon
-- skills that class can train (Vanilla 1.12 base list). Every name here is
-- a VALUE of DC.WEAPON_SKILL_OF_SUBTYPE above, same spelling -- the
-- options editor's Skill books tab (ui/options.lua, O.SkillBookRows)
-- writes db.skillBooks[player][skill] keyed by these exact strings, so a
-- typo here would silently create a book entry the hit calc never reads.
--
-- This server can diverge from the Vanilla baseline (extra or missing
-- trainable weapons for a class). If a player is seen wielding a skill
-- that is not in their class's list here, the Skill books tab still
-- offers it -- a WORN skill always rides along regardless of the class
-- list (see O.SkillBookRows) -- but if that turns out to be the NORMAL
-- case for a class rather than a one-off exception, extend the list below
-- rather than leaning on the worn-skill fallback forever.
-- ------------------------------------------------------------------
DC.CLASS_WEAPON_SKILLS = {
    WARRIOR = { "Axes", "Two-Handed Axes", "Maces", "Two-Handed Maces",
                "Swords", "Two-Handed Swords", "Daggers", "Unarmed",
                "Polearms", "Staves", "Bows", "Crossbows", "Guns",
                "Thrown" },
    PALADIN = { "Axes", "Two-Handed Axes", "Maces", "Two-Handed Maces",
                "Swords", "Two-Handed Swords", "Polearms" },
    HUNTER  = { "Axes", "Two-Handed Axes", "Swords", "Two-Handed Swords",
                "Daggers", "Unarmed", "Polearms", "Staves", "Bows",
                "Crossbows", "Guns", "Thrown" },
    ROGUE   = { "Daggers", "Unarmed", "Maces", "Swords", "Bows",
                "Crossbows", "Guns", "Thrown" },
    PRIEST  = { "Daggers", "Maces", "Staves", "Wands" },
    SHAMAN  = { "Axes", "Two-Handed Axes", "Maces", "Two-Handed Maces",
                "Daggers", "Unarmed", "Staves" },
    MAGE    = { "Daggers", "Swords", "Staves", "Wands" },
    WARLOCK = { "Daggers", "Swords", "Staves", "Wands" },
    DRUID   = { "Maces", "Two-Handed Maces", "Daggers", "Unarmed",
                "Staves", "Polearms" },
}

-- ------------------------------------------------------------------
-- Weapon skill baseline and modifiers.
--
-- DC.BASE_WEAPON_SKILL: a level-60 character caps every weapon skill at
--   300 (5 x level). This tool is a raid tool, so 60 is assumed for the
--   estimate of FOREIGN players; the own character is measured and never
--   uses this number.
--
-- DC.RACIAL_SKILL_BONUS: the racial weapon specialization bonus. The value
--   is DISPUTED -- the classic value is +5, and a server-side change to +3
--   has been reported but is UNVERIFIED. It is ONE constant on purpose:
--   changing this single line changes every racial bonus and every derived
--   cap.
--
-- DC.SKILL_BOOK_BONUS: a quest weapon-skill book grants +3 skill. It is
--   invisible on other players (see the header), which is why it is an
--   opt-in per-player checkbox in the options rather than a scan result.
-- ------------------------------------------------------------------
DC.BASE_WEAPON_SKILL = 300
DC.RACIAL_SKILL_BONUS = 5
DC.SKILL_BOOK_BONUS = 3

-- ------------------------------------------------------------------
-- DC.RACE_WEAPON_SKILL -- race -> { [weapon skill name] = bonus }.
--
-- Keys: BOTH spellings are listed for every race that has a bonus -- the
-- display name ("Night Elf") and the file token ("NightElf", "Scourge"),
-- because the race string reaches us from UnitRace, whose two returns are
-- exactly those two spellings. Aliases point at the SAME table, so a race
-- is never counted twice.
--
-- Races without a weapon specialization (night elves, tauren, undead) are
-- deliberately absent: an absent race resolves to "no bonus", which is
-- also what an unknown/newer race token resolves to (nil-safe by design).
-- ------------------------------------------------------------------
local B = DC.RACIAL_SKILL_BONUS

local HUMAN_SKILLS = {
    ["Swords"] = B, ["Two-Handed Swords"] = B,
    ["Maces"]  = B, ["Two-Handed Maces"]  = B,
}
local ORC_SKILLS = {
    ["Axes"] = B, ["Two-Handed Axes"] = B,
}
local DWARF_SKILLS = { ["Guns"] = B }
local TROLL_SKILLS = { ["Bows"] = B, ["Thrown"] = B }
local GNOME_SKILLS = { ["Daggers"] = B, ["Swords"] = B }
-- races without a weapon specialization share ONE empty table
local NO_SKILLS = {}

DC.RACE_WEAPON_SKILL = {
    ["Human"]     = HUMAN_SKILLS,
    ["Orc"]       = ORC_SKILLS,
    ["Dwarf"]     = DWARF_SKILLS,
    ["Troll"]     = TROLL_SKILLS,
    ["Gnome"]     = GNOME_SKILLS,
    -- no weapon specialization; listed for readability, empty on purpose
    ["Night Elf"] = NO_SKILLS,
    ["NightElf"]  = NO_SKILLS,
    ["Tauren"]    = NO_SKILLS,
    ["Undead"]    = NO_SKILLS,
    ["Scourge"]   = NO_SKILLS,
}

-- ------------------------------------------------------------------
-- DC.HIT_CAPS -- hit percentages needed against a boss THREE LEVELS above
-- the player on the current patch, at base weapon skill (300):
--   meleeYellow  8  -- special attacks / abilities ("yellow" swings)
--   meleeWhiteDW 27 -- auto attacks while DUAL WIELDING (the 19% dual-
--                     wield penalty rides on top); a single weapon's white
--                     swings share the yellow cap
--   ranged       8  -- ranged attacks behave like yellow melee here
--   spell        16 -- the server clamps spell hit chance to 99%, so 1%
--                     miss can never be removed: base miss vs a +3-level
--                     boss is 17%, which makes 16% the effective cap
--
-- DC.CAP_PER_SKILL: every weapon skill point ABOVE 300 lowers the melee/
-- ranged cap by 0.2 percentage points (linear scaling, see header). A
-- racial specialization (+5 skill) therefore lowers the yellow cap from
-- 8.0 to 7.0, and a weapon skill book (+3) is worth about 0.6% hit.
-- ------------------------------------------------------------------
DC.HIT_CAPS = {
    meleeYellow  = 8,
    meleeWhiteDW = 27,
    ranged       = 8,
    spell        = 16,
}

DC.CAP_PER_SKILL = 0.2

-- ------------------------------------------------------------------
-- DC.HIT_AURAS -- hit granted by AURAS rather than gear, folded on top of
-- the gear sum by scan/engine.lua's BuildPlayer (no extra scan: the buff
-- names are already in the store from the same aura read the class-buff
-- tab uses). Keys are buff NAMES (matched against player.auras.names);
-- values are { melee=, ranged=, spell= } percentages -- every field is
-- OPTIONAL, since a hit-granting aura need not touch all three columns.
-- ------------------------------------------------------------------
DC.HIT_AURAS = {
    -- raid-wide druid buff: +1% SPELL hit only (also grants movement
    -- speed and casting mana regen, which do not concern this addon) --
    -- verified against the in-game tooltip text, so this is deliberately
    -- NOT a melee/ranged entry; add further hit-granting auras here (a
    -- food buff with hit would be the likeliest addition)
    ["Emerald Blessing"] = { spell = 1 },
}
