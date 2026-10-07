if WDI_DOPING_SKIP then return end -- DopingControl data/consumables.lua
-- Consumables tab: slot definitions + buff->entry table + spellID->slot map
-- + the pure item-identification ladder (DC.ResolveItem).
-- Pure Lua 5.0, no WoW API -- dofile-loadable offline.
--
-- SLOT MODEL (v6, 22 slots -- the 17-slot base design plus the five school
-- protection-potion columns FrR/NR/SR/HR/AR added 2026-08-11):
-- One column = one thing that can be active independently of every other
-- column; items competing INSIDE a column are the "pick one" alternatives.
-- Source: community-sourced TurtleWoW 1.17.2 consumable-stacking rules,
-- trust external -- vanilla 1.12 slot rules, no TBC
-- Battle/Guardian categories. The old 11-slot model conflated four
-- independent slots into SP (GAE / school elixir / Dreamtonic / Dreamshard
-- are simultaneously active in the caster set) and two into HP (Fortitude
-- + stamina alcohol stack), and lacked BL/ZANZA entirely.
--
-- Deliberate compromises (documented, not hidden):
--   * ALC is ONE column although different alcohol types stack (Merlot +
--     Rumsey Black Label at once; same types do not): modelled as one
--     column showing the strongest active, detail in tooltip. The
--     slot-collision tests exempt exactly this column.
--   * Gift of Arthas and Juju Flurry get NO column (defense elixirs all
--     stack; Flurry lasts 20 s).
--   * UNVERIFIED gaps (community source does not cover them; marked
--     `unverified = true` on the slot/entries, upgrade via dev/raiddump
--     evidence next raid): (1) WPN main-hand/off-hand coexistence (oil on
--     MH + stone on OH), (2) protection-potion slot rules (all six school
--     columns FR/FrR/NR/SR/HR/AR -- cross-school stacking is NOT
--     evidenced, so each school gets its own column but every one stays
--     flagged unverified), (3) world-buff interactions (no world-buff
--     columns at all).
--
-- Entry fields (DC.CONSUMABLES[buffName]):
--   slot     : slot id (column) the buff fills
--   spellID  : aura spell id; 0 = "match by name only" (no known ID)
--   item     : the consumable's display name (whisper/tooltip/cell)
--   icon     : BARE icon texture name (no "Interface\Icons\" prefix, no
--              extension -- prefix is added at render time); nil when the
--              icon could not be sourced (the matrix fallback ladder
--              handles nil: slot-generic icon, then the green check)
--   discrim  : optional Lua 5.0 string.find pattern matched against the
--              buff tooltip's EFFECT line (scan/aura.lua auras.effects) --
--              only where the buff NAME is generic
--   variants : optional ARRAY of { item, icon, discrim } for generic buff
--              names ("Well Fed") that many different items produce; the
--              identification ladder walks them in order, FIRST match wins
--   unverified : optional true -- see the honesty gaps above
--
-- Icon provenance (2026-08-11, never guessed): wowhead classic tooltip
-- API for the vanilla items, octowow.st/db + wowauctions for TurtleWoW
-- customs; icon = nil where no source confirmed one. Two lookalike
-- collisions are GENUINE, not typos: Dragonbreath Chili and Danonzo's
-- Delight share inv_drink_17 with Nightfin Soup; Gordok Green Grog
-- shares inv_drink_03 with Rumsey Rum; Cerebral Cortex Compound shares
-- inv_potion_32 with the Mongoose elixir.
--
-- Separator decision (once for all data files): items strings are
-- tooltip/FontString-only, so they may use the middle-dot list separator
-- "\194\183" (UTF-8 middle dot renders fine in own FontStrings; the group
-- headers already use the same glyph). Em dashes stay ASCII "-" (that
-- glyph is unproven in the 1.12 font). SENT chat lines remain pure ASCII
-- -- they never use these strings.

DopingControl = DopingControl or {}
local DC = DopingControl

-- ------------------------------------------------------------------
-- Slot definitions (array, order = column order).
-- Fields: id (stable key, used by DEFAULT_EXPECT / model / UI),
--         label (column tile abbrev), sub (tile sub-label), full (long
--         name, used in whisper/report), kind ("aura" | "weapon"),
--         items (tooltip example text, optional), unverified (optional,
--         see header),
--         icon (BARE slot-generic icon texture name -- same bare-name
--         rule as the entry icons above; the matrix HAS-cell fallback
--         ladder renders it when the ITEM behind a buff cannot be
--         resolved: resolved item icon -> this slot icon -> green check.
--         A representative member item's icon by design -- the cell must
--         read as "this column", not as a question mark).
-- ------------------------------------------------------------------
DC.SLOTS_CONSUMABLES = {
    { id = "FLASK",  label = "FLK", sub = "Flask",   full = "Flask",              kind = "aura",
      icon = "inv_potion_62",
      items = "Flask of the Titans \194\183 Distilled Wisdom \194\183 Supreme Power" },
    { id = "FOOD",   label = "FOD", sub = "Food",    full = "Food buff",          kind = "aura",
      icon = "inv_misc_food_15",
      items = "one food buff at a time - e.g. Smoked Desert Dumplings \194\183 Danonzo's Tel'Abim foods" },
    { id = "AP",     label = "AP",  sub = "Attack",  full = "Attack power",       kind = "aura",
      icon = "inv_potion_92",
      items = "Winterfall Firewater \194\183 Juju Might" },
    { id = "STR",    label = "STR", sub = "Str.",    full = "Strength",           kind = "aura",
      icon = "inv_potion_61",
      items = "Juju Power \194\183 Elixir of Giants" },
    { id = "AGI",    label = "AGI", sub = "Agi.",    full = "Agility",            kind = "aura",
      icon = "inv_potion_32",
      items = "Elixir of the Mongoose - free-stacker, own column" },
    { id = "BL",     label = "BL",  sub = "Blasted", full = "Blasted Lands buff", kind = "aura",
      icon = "inv_stone_15",
      items = "R.O.I.D.S. \194\183 Ground Scorpok Assay \194\183 Lung Juice Cocktail \194\183 Cortex Compound \194\183 Gizzard Gum" },
    { id = "ZANZA",  label = "ZAN", sub = "Zanza",   full = "Spirit of Zanza",    kind = "aura",
      icon = "inv_potion_30",
      items = "Spirit of Zanza - free-stacker, one Zanza effect at a time" },
    { id = "GAE",    label = "GAE", sub = "Arcane",  full = "Greater Arcane Elixir", kind = "aura",
      icon = "inv_potion_25",
      items = "Greater Arcane Elixir \194\183 Arcane Elixir" },
    { id = "SCHOOL", label = "SCH", sub = "School",  full = "School elixir",      kind = "aura",
      icon = "inv_potion_46",
      items = "Shadow Power \194\183 Frost Power \194\183 Greater Firepower - one per school slot" },
    { id = "DREAMT", label = "DRT", sub = "Dreamt.", full = "Dreamtonic",         kind = "aura",
      icon = "inv_potion_10",
      items = "Dreamtonic (TurtleWoW custom)" },
    { id = "SHARD",  label = "SHD", sub = "Shard",   full = "Dreamshard Elixir",  kind = "aura",
      icon = "inv_potion_12",
      items = "Dreamshard Elixir (TurtleWoW custom)" },
    { id = "MP5",    label = "MP5", sub = "Mana",    full = "Mana regen",         kind = "aura",
      icon = "inv_potion_45",
      items = "Mageblood Potion - Nightfin Soup is a FOOD buff, not this column" },
    { id = "ARM",    label = "ARM", sub = "Armor",   full = "Armor",              kind = "aura",
      icon = "inv_potion_66",
      items = "Elixir of Superior Defense" },
    { id = "HPELX",  label = "FRT", sub = "Fort.",   full = "Elixir of Fortitude", kind = "aura",
      icon = "inv_potion_43",
      items = "Elixir of Fortitude - stacks with the alcohol column" },
    { id = "ALC",    label = "ALC", sub = "Alcohol", full = "Alcohol buff",       kind = "aura",
      icon = "inv_drink_04",
      items = "Medivh's Merlot \194\183 Rumsey Rum Black Label \194\183 Kreeg's Stout Beatdown - different types stack, same type does not; one column, strongest shown" },
    { id = "FR",     label = "FR",  sub = "fire",    full = "Fire protection",    kind = "aura",  unverified = true,
      icon = "inv_potion_24",
      items = "Greater Fire Protection Potion - situational per boss; enable/disable via the expectation matrix" },
    -- The remaining school protection columns follow the FR pattern (one
    -- column per school, cross-school stacking unverified -- see header).
    -- Unlike FR they carry NO seed entry in data/expectations.lua: the
    -- dynamic-column rule keeps them hidden until enabled per role/class.
    { id = "FrR",    label = "FrR", sub = "frost",   full = "Frost protection",   kind = "aura",  unverified = true,
      icon = "inv_potion_20",
      items = "Greater Frost Protection Potion - situational per boss; enable/disable via the expectation matrix" },
    { id = "NR",     label = "NR",  sub = "nature",  full = "Nature protection",  kind = "aura",  unverified = true,
      icon = "inv_potion_22",
      items = "Greater Nature Protection Potion - situational per boss; enable/disable via the expectation matrix" },
    { id = "SR",     label = "SR",  sub = "shadow",  full = "Shadow protection",  kind = "aura",  unverified = true,
      icon = "inv_potion_23",
      items = "Greater Shadow Protection Potion - situational per boss; enable/disable via the expectation matrix" },
    { id = "HR",     label = "HR",  sub = "holy",    full = "Holy protection",    kind = "aura",  unverified = true,
      icon = "inv_potion_09",
      items = "Holy Protection Potion - situational per boss; enable/disable via the expectation matrix" },
    { id = "AR",     label = "AR",  sub = "arcane",  full = "Arcane protection",  kind = "aura",  unverified = true,
      icon = "inv_potion_83",
      items = "Greater Arcane Protection Potion - situational per boss; enable/disable via the expectation matrix" },
    { id = "WPN",    label = "WPN", sub = "temp.",   full = "Weapon (temporary)", kind = "weapon", unverified = true,  -- NOT an aura slot; MH/OH split unverified
      icon = "inv_stone_sharpeningstone_01",
      items = "Elemental/Dense Sharpening Stone \194\183 Brilliant Wizard/Mana Oil - permanent enchant: Equipment tab" },
}

-- ------------------------------------------------------------------
-- Buff name -> entry table.
-- spellID = 0 means "match by name only" (no known aura spell ID).
-- ------------------------------------------------------------------
DC.CONSUMABLES = {
    -- FLASK
    ["Flask of the Titans"]           = { slot = "FLASK", spellID = 17626, item = "Flask of the Titans",           icon = "inv_potion_62" },
    ["Flask of Supreme Power"]        = { slot = "FLASK", spellID = 17628, item = "Flask of Supreme Power",        icon = "inv_potion_41" },
    ["Flask of Distilled Wisdom"]     = { slot = "FLASK", spellID = 17627, item = "Flask of Distilled Wisdom",     icon = "inv_potion_97" },
    ["Flask of Chromatic Resistance"] = { slot = "FLASK", spellID = 17629, item = "Flask of Chromatic Resistance", icon = "inv_potion_48" },
    ["Flask of Petrification"]        = { slot = "FLASK", spellID = 17624, item = "Flask of Petrification",        icon = "inv_potion_26" },  -- NOT inv_potion_98 (a often-repeated wrong guess) -- wowhead-confirmed

    -- FOOD (buff names, not item names).
    -- "Well Fed" is the generic food aura: the ITEM is identified through
    -- the tooltip EFFECT line (scan/aura.lua auras.effects) against the
    -- per-variant discrim patterns below -- first match wins, no match =
    -- nil = the matrix falls back to the slot-generic icon ("food buff,
    -- unknown which"). The variant list is the food set of the KG
    -- stacking-rules atom plus the classic raid staples; the discrim
    -- patterns are best-effort data (recorded-tooltip verification via
    -- dev/raiddump pending) -- a wrong one is a one-line fix.
    -- ["Food"] (the eating tick) deliberately REMOVED: it is the
    -- sit-and-eat channel aura, not a food buff -- it made the FOOD cell
    -- green for anyone currently chewing (field-tested). Only lasting
    -- food buffs count.
    ["Well Fed"] = { slot = "FOOD", spellID = 0, item = "food buff", icon = nil,
        variants = {
            -- ORDER MATTERS: first match wins, so specific effect lines
            -- (crit, ranged AP, spell damage) sit ABOVE the generic stat
            -- words they could otherwise be swallowed by.
            -- Several Turtle customs SHARE their aura spell with a classic
            -- staple (icon research 2026-08-11: Power Mushroom = 24800 =
            -- Dumplings, Sour Mountain Berry = 18230 = Grilled Squid,
            -- Juicy Striped Melon = 22731 = Runn Tum Tuber) -- those pairs
            -- are indistinguishable by effect line; the listed-first item
            -- is shown as the representative. Same slot, so harmless.
            { item = "Danonzo's Tel'Abim Delight",    icon = "inv_drink_17",         discrim = "[Ss]pell [Dd]amage" },
            { item = "Danonzo's Tel'Abim Medley",     icon = "inv_misc_food_08",     discrim = "[Hh]aste" },
            { item = "Danonzo's Tel'Abim Surprise",   icon = "inv_misc_food_09",     discrim = "[Rr]anged [Aa]ttack [Pp]ower" },
            { item = "Gurubashi Gumbo",               icon = "inv_misc_food_64",     discrim = "[Cc]rit" },
            { item = "Le Fishe Au Chocolat",          icon = nil,                    discrim = "[Dd]odge" },  -- icon: questionmark placeholder even upstream (octowow + wowauctions), stays nil
            { item = "Empowering Herbal Salad",       icon = "inv_misc_food_salad",  discrim = "[Hh]ealing" },
            { item = "Nightfin Soup",                 icon = "inv_drink_17",         discrim = "8 [Mm]ana" },
            { item = "Sagefish Delight",              icon = "inv_misc_fish_21",     discrim = "6 [Mm]ana" },
            -- +20 Strength: Dumplings and Power Mushroom, same spell 24800
            { item = "Smoked Desert Dumplings",       icon = "inv_misc_food_64",     discrim = "[Ss]trength" },
            { item = "Power Mushroom",                icon = "inv_mushroom_11",      discrim = "[Ss]trength" },  -- NOT "+10 all stats" (dead pattern until 2026-08-11); tooltip-verified +20 STR
            -- +10 Agility: Grilled Squid and Sour Mountain Berry, same spell 18230
            { item = "Grilled Squid",                 icon = "inv_misc_fish_13",     discrim = "[Aa]gility" },
            { item = "Sour Mountain Berry",           icon = "inv_misc_food_40",     discrim = "[Aa]gility" },
            -- +10 Intellect: classic Tuber and Turtle Melon, same spell 22731
            { item = "Runn Tum Tuber Surprise",       icon = "inv_misc_food_63",     discrim = "[Ii]ntellect" },
            { item = "Juicy Striped Melon",           icon = "inv_misc_food_22",     discrim = "[Ii]ntellect" },
            -- generic stamina LAST: Gumbo's line also contains Stamina and
            -- must be caught by its crit pattern above, never by this one
            { item = "Hardened Mushroom",             icon = "inv_mushroom_11",      discrim = "[Ss]tamina" },  -- NOT "+armor" (dead pattern until 2026-08-11); tooltip-verified +25 STA, spell 25660
        } },
    ["Increased Stamina"]             = { slot = "FOOD", spellID = 0,     item = "stamina food",       icon = nil },
    ["Dragonbreath Chili"]            = { slot = "FOOD", spellID = 15852, item = "Dragonbreath Chili", icon = "inv_drink_17" },  -- yes, the chili really uses a drink icon (wowhead-confirmed via og:image)

    -- AP
    ["Winterfall Firewater"]          = { slot = "AP", spellID = 17038, item = "Winterfall Firewater", icon = "inv_potion_92" },
    ["Juju Might"]                    = { slot = "AP", spellID = 16329, item = "Juju Might",           icon = "inv_misc_monsterscales_07" },

    -- STR
    ["Juju Power"]                    = { slot = "STR", spellID = 16323, item = "Juju Power",            icon = "inv_misc_monsterscales_11" },
    ["Elixir of Giants"]              = { slot = "STR", spellID = 11405, item = "Elixir of Giants",      icon = "inv_potion_61" },
    ["Elixir of the Giants"]          = { slot = "STR", spellID = 11405, item = "Elixir of Giants",      icon = "inv_potion_61" },  -- AURA name on this client (measured live: SpellInfo(11405) = "Elixir of the Giants"); the item is named without "the", and matching runs on the aura name first
    ["Elixir of Brute Force"]         = { slot = "STR", spellID = 17537, item = "Elixir of Brute Force", icon = "inv_potion_40" },

    -- AGI
    ["Elixir of the Mongoose"]        = { slot = "AGI", spellID = 17538, item = "Elixir of the Mongoose",    icon = "inv_potion_32" },
    ["Elixir of Greater Agility"]     = { slot = "AGI", spellID = 11334, item = "Elixir of Greater Agility", icon = "inv_potion_94" },
    ["Greater Agility"]               = { slot = "AGI", spellID = 11334, item = "Elixir of Greater Agility", icon = "inv_potion_94" },  -- AURA name (the item name never appears as a buff); was tallied as unknown 14x
    ["Elixir of Agility"]             = { slot = "AGI", spellID = 11328, item = "Elixir of Agility",         icon = "inv_potion_93" },

    -- BL (Blasted Lands buff slot -- one at a time, pick one; the five
    -- items were split across STR/nowhere in the old model).
    -- Aura names + spell ids wowhead-confirmed 2026-08-11 ("Strike of the
    -- Scorpok" additionally measured live in a 26-man raid). The item
    -- names ride along as alias keys (spellID 0) because the Turtle
    -- client may surface the permanent aura under the item name (KG
    -- note); a key that never matches is harmless.
    ["Rage of Ages"]                  = { slot = "BL", spellID = 10667, item = "R.O.I.D.S.",               icon = "inv_stone_15" },
    ["R.O.I.D.S."]                    = { slot = "BL", spellID = 0,     item = "R.O.I.D.S.",               icon = "inv_stone_15" },
    ["Strike of the Scorpok"]         = { slot = "BL", spellID = 10669, item = "Ground Scorpok Assay",     icon = "inv_misc_dust_02" },  -- old model filed it under STR with the aura name as item -- both wrong (it is +25 AGI, and the item is the Assay)
    ["Ground Scorpok Assay"]          = { slot = "BL", spellID = 0,     item = "Ground Scorpok Assay",     icon = "inv_misc_dust_02" },
    ["Spirit of Boar"]                = { slot = "BL", spellID = 10668, item = "Lung Juice Cocktail",      icon = "inv_drink_12" },
    ["Lung Juice Cocktail"]           = { slot = "BL", spellID = 0,     item = "Lung Juice Cocktail",      icon = "inv_drink_12" },
    ["Infallible Mind"]               = { slot = "BL", spellID = 10692, item = "Cerebral Cortex Compound", icon = "inv_potion_32" },  -- same icon as the Mongoose elixir -- genuine, wowhead-confirmed
    ["Cerebral Cortex Compound"]      = { slot = "BL", spellID = 0,     item = "Cerebral Cortex Compound", icon = "inv_potion_32" },
    ["Spiritual Domination"]          = { slot = "BL", spellID = 10693, item = "Gizzard Gum",              icon = "inv_misc_food_30" },
    ["Gizzard Gum"]                   = { slot = "BL", spellID = 0,     item = "Gizzard Gum",              icon = "inv_misc_food_30" },

    -- ZANZA (free-stacker; only one Zanza-potion effect at a time; buff
    -- name = item name, wowhead-confirmed)
    ["Spirit of Zanza"]               = { slot = "ZANZA", spellID = 24382, item = "Spirit of Zanza", icon = "inv_potion_30" },

    -- GAE (split out of the old SP column)
    ["Greater Arcane Elixir"]         = { slot = "GAE", spellID = 17539, item = "Greater Arcane Elixir", icon = "inv_potion_25" },
    ["Arcane Elixir"]                 = { slot = "GAE", spellID = 11390, item = "Arcane Elixir",         icon = "inv_potion_30" },

    -- SCHOOL (split out of the old SP column; one school elixir at a time)
    ["Elixir of Shadow Power"]        = { slot = "SCHOOL", spellID = 11474, item = "Elixir of Shadow Power",        icon = "inv_potion_46" },
    ["Elixir of Frost Power"]         = { slot = "SCHOOL", spellID = 21920, item = "Elixir of Frost Power",         icon = "inv_potion_03" },
    ["Greater Frost Power"]           = { slot = "SCHOOL", spellID = 56544, item = "Elixir of Greater Frost Power", icon = "inv_potion_13" },  -- AURA name (TurtleWoW-added). NOT measured in-game: taken from a TurtleWoW spell database (56544 = "Greater Frost Power") plus the item name in pfQuest-turtle's item DB; the aura drops "Elixir of" the same way Giants/Agility above do
    ["Elixir of Greater Firepower"]   = { slot = "SCHOOL", spellID = 26276, item = "Elixir of Greater Firepower",   icon = "inv_potion_60" },
    ["Elixir of Firepower"]           = { slot = "SCHOOL", spellID = 7844,  item = "Elixir of Firepower",           icon = "inv_potion_33" },

    -- DREAMT (TurtleWoW custom; own slot -- simultaneously active with
    -- GAE, SCHOOL and SHARD in the caster set)
    ["Dreamtonic"]                    = { slot = "DREAMT", spellID = 45489, item = "Dreamtonic", icon = "inv_potion_10" },  -- use-spell ID; the aura's own ID is unverified

    -- SHARD (TurtleWoW custom; own slot)
    ["Dreamshard Elixir"]             = { slot = "SHARD", spellID = 45427, item = "Dreamshard Elixir", icon = "inv_potion_12" },  -- use-spell ID; the aura's own ID is unverified

    -- MP5 (narrowed: Nightfin Soup is a FOOD buff and lives there now)
    ["Mageblood Potion"]              = { slot = "MP5", spellID = 24363, item = "Mageblood Potion", icon = "inv_potion_45" },
    ["Mageblood"]                     = { slot = "MP5", spellID = 24363, item = "Mageblood Potion", icon = "inv_potion_45" },  -- TWoW buff-name variant (old Data.lua kept both)

    -- ARM
    ["Elixir of Superior Defense"]    = { slot = "ARM", spellID = 11348, item = "Elixir of Superior Defense", icon = "inv_potion_66" },
    ["Elixir of Greater Defense"]     = { slot = "ARM", spellID = 11349, item = "Elixir of Greater Defense",  icon = "inv_potion_65" },

    -- HPELX (alcohol split out into ALC; Fortitude stacks with it)
    ["Elixir of Fortitude"]           = { slot = "HPELX", spellID = 3593, item = "Elixir of Fortitude", icon = "inv_potion_43" },
    ["Health II"]                     = { slot = "HPELX", spellID = 3593, item = "Elixir of Fortitude", icon = "inv_potion_43" },  -- AURA name on this client (measured live: SpellInfo(3593) = "Health II")

    -- ALC (alcohol buffs -- ONE column by design although different
    -- types stack; see the header compromise note). Buff names and spell
    -- ids wowhead/octowow-confirmed 2026-08-11; the "Blue Label" aura
    -- name differs from the Blue item name, both keys are kept.
    ["Medivh's Merlot"]               = { slot = "ALC", spellID = 57106, item = "Medivh's Merlot",        icon = "inv_drink_waterskin_05" },  -- use-spell ID; the aura's own ID is unverified
    ["Medivh's Merlot Blue"]          = { slot = "ALC", spellID = 0,     item = "Medivh's Merlot Blue",   icon = "inv_drink_waterskin_01" },
    ["Medivh's Merlot Blue Label"]    = { slot = "ALC", spellID = 57107, item = "Medivh's Merlot Blue",   icon = "inv_drink_waterskin_01" },  -- the AURA name (octowow: spell 57107 "Medivh's Merlot Blue Label")
    ["Rumsey Rum Black Label"]        = { slot = "ALC", spellID = 25804, item = "Rumsey Rum Black Label", icon = "inv_drink_04" },
    ["Rumsey Rum"]                    = { slot = "ALC", spellID = 20875, item = "Rumsey Rum",             icon = "inv_drink_03" },
    ["Rumsey Rum Light"]              = { slot = "ALC", spellID = 25037, item = "Rumsey Rum Light",       icon = "inv_drink_08" },
    ["Gordok Green Grog"]             = { slot = "ALC", spellID = 22789, item = "Gordok Green Grog",      icon = "inv_drink_03" },  -- same icon as Rumsey Rum -- genuine, wowhead-confirmed
    ["Kreeg's Stout Beatdown"]        = { slot = "ALC", spellID = 22790, item = "Kreeg's Stout Beatdown", icon = "inv_drink_05" },  -- +25 Spirit/-5 Int -- the healer set's alcohol, not a stamina drink

    -- FR (protection-potion slot rules are an UNVERIFIED gap, see header)
    ["Greater Fire Protection"]       = { slot = "FR", spellID = 17543, item = "Greater Fire Protection Potion", icon = "inv_potion_24", unverified = true },
    ["Fire Protection"]               = { slot = "FR", spellID = 7233,  item = "Fire Protection Potion",         icon = "inv_potion_16", unverified = true },

    -- FrR/NR/SR/HR/AR (same UNVERIFIED protection-potion gap as FR).
    -- Use-effect spell IDs + item icons wowhead-confirmed 2026-08-11.
    -- Tier coverage is asymmetric by design: no Lesser Arcane potion and
    -- no Greater Holy potion exist in vanilla 1.12. The aura on the
    -- client likely drops the "Greater" (wowhead names both tiers
    -- "<School> Protection"); the greater keys mirror the FR convention
    -- and the ID match carries them regardless of the live aura name.
    ["Greater Frost Protection"]      = { slot = "FrR", spellID = 17544, item = "Greater Frost Protection Potion",  icon = "inv_potion_20", unverified = true },
    ["Frost Protection"]              = { slot = "FrR", spellID = 7239,  item = "Frost Protection Potion",          icon = "inv_potion_13", unverified = true },
    ["Greater Nature Protection"]     = { slot = "NR",  spellID = 17546, item = "Greater Nature Protection Potion", icon = "inv_potion_22", unverified = true },
    ["Nature Protection"]             = { slot = "NR",  spellID = 7254,  item = "Nature Protection Potion",         icon = "inv_potion_06", unverified = true },  -- live aura name carries a trailing space (SpellInfo(7254)); scan/aura.lua's trimmed retry covers it
    ["Greater Shadow Protection"]     = { slot = "SR",  spellID = 17548, item = "Greater Shadow Protection Potion", icon = "inv_potion_23", unverified = true },
    ["Shadow Protection"]             = { slot = "SR",  spellID = 7242,  item = "Shadow Protection Potion",         icon = "inv_potion_44", unverified = true },  -- NAME collides with the priest buff (data/classbuffs.lua SPROT, ids 976/10957/10958): ID-before-name keeps them apart; a name-only scan cannot tell the two, which SR's default-off expectation mitigates
    ["Holy Protection"]               = { slot = "HR",  spellID = 7245,  item = "Holy Protection Potion",           icon = "inv_potion_09", unverified = true },
    ["Greater Arcane Protection"]     = { slot = "AR",  spellID = 17549, item = "Greater Arcane Protection Potion", icon = "inv_potion_83", unverified = true },

    -- WPN: intentionally NO aura entries - temp enchant is not a buff
}

-- ------------------------------------------------------------------
-- DC.ResolveItem(buffName, effectText) -> item, icon
-- The PURE identification ladder (spec: "Identification ladder"):
--   1. unique buff name          -> item/icon straight from the entry
--   2. generic buff name         -> match effectText against the entry's
--      variant discrim patterns (plain Lua 5.0 string.find, first match
--      wins) -> that variant's item/icon
--   3. no match / no effect text -> nil, nil (the caller falls back to
--      the slot-generic icon: "slot filled, item unknown")
-- An entry-level discrim (no variants) gates rule 1 the same way: the
-- item only resolves when the effect line matches. Offline-testable --
-- no WoW API, no upvalues beyond the data table.
-- ------------------------------------------------------------------
function DC.ResolveItem(buffName, effectText)
    local def = DC.CONSUMABLES[buffName]
    if not def then
        return nil, nil
    end
    if def.variants then
        if type(effectText) == "string" then
            local n = table.getn(def.variants)
            for i = 1, n do
                local v = def.variants[i]
                if v.discrim and string.find(effectText, v.discrim) then
                    return v.item, v.icon
                end
            end
        end
        return nil, nil
    end
    if def.discrim then
        if type(effectText) == "string"
           and string.find(effectText, def.discrim) then
            return def.item, def.icon
        end
        return nil, nil
    end
    return def.item, def.icon
end

-- ------------------------------------------------------------------
-- spellID -> slotId map, generated from DC.CONSUMABLES (spellID > 0).
-- Collision rule: at classify time an ID match beats a
-- name match. data/classbuffs.lua later MERGES its rank IDs into this same
-- map (slot ids are unique across tabs, so one flat map is safe).
-- ------------------------------------------------------------------
DC.SPELL_TO_SLOT = {}
for name, def in pairs(DC.CONSUMABLES) do
    if def.spellID and def.spellID > 0 then
        DC.SPELL_TO_SLOT[def.spellID] = def.slot
    end
end
