if WDI_DOPING_SKIP then return end -- DopingControl core/sim.lua
-- Test mode: deterministic simulated raid.
-- DC_Sim.buildStore() returns a store in EXACTLY the shape the real scan
-- produces (source="sim") -- model, aggregation and
-- rendering run unchanged on it, so test mode exercises the real pipeline.
--
-- Fixed synthetic roster: 40 players (a FULL raid -- this server's raid
-- cap is 40, eight subgroups of five), all 9 classes, role distribution
-- TANK 4 / MELEE 11 / RANGED 6 / CASTER 11 / HEALER 8. No randomness --
-- every run looks the same, screenshots are comparable. All names start
-- with "Sim" so no synthetic name can be mistaken for (or whispered to) a
-- real player; chat outputs are dead in test mode anyway. Every player
-- also carries subgroup 1..8 (five each, real raid-group shape) so the
-- full-raid layout -- scroll behavior, group headers, column widths, the
-- render cost of forty rows -- is exercised at MAXIMUM occupancy.
--
-- Coverage built into the roster (every feature is showcased):
--   * every cell state in every tab (HAS / MISSING / UNKNOWN / NOTEXP)
--   * TANK group all readable with 0 gaps in all three tabs (green pill)
--   * exactly 3 offline + 2 read-failed players (5 of 40 unreadable); the
--     read-failed carry distance values (87 / 203) as diagnosis. All 5
--     unreadable players share subgroup 8 -- a raid subgroup that is
--     ENTIRELY unreadable, the opposite pill extreme from the all-green
--     TANK group above (both a fully-clean and a fully-blank group must
--     render correctly).
--   * 2 unconfirmed roles (Simfury, Simshade -> suggestion badges)
--   * trinkets: epic (quality 4), rare (quality 3), one EMPTY slot 14
--   * enchant gaps (enchant==0), EMPTY off hand (fury warrior), wand
--     wearer (ranged enchant NOTEXP), holdable off hand (NOTEXP)
--   * HAS via spell-ID match for some players (names empty) and via
--     name match for others (ids empty) -- both model paths are exercised
--   * whisper-eligible rows (readable + gaps) in every tab
--   * FULL icon coverage: every HAS-producing
--     aura name has a real-looking vanilla icon path in auras.textures
--     (built programmatically below, so id-matched and name-matched
--     players are both covered), and every gear entry TABLE carries
--     texture + name + quality -- test mode showcases the icon feature.
--   * SCHOOL PROTECTION carriers, one per school, ALL by spell ID:
--     Simtank SR (17548), Simsteel FrR (17544), Simsham NR (17546),
--     Simheala HR (7245), Simmage AR (17549) -- plus the seeded FR
--     carriers. Their columns stay hidden under the shipped defaults; demo
--     mode (core/demo.lua) switches all six on at once and these five are
--     what makes that view show HAS cells rather than an empty block. Held
--     by ID on purpose: "Shadow Protection" is ALSO the priest class buff
--     (data/consumables.lua:312), so a name-based carrier would fake an SR
--     fulfillment the moment the column is visible.
--   * v6 SLOT MODEL (17 active default columns of the 22-slot table --
--     the five school protection slots FrR/NR/SR/HR/AR default off and
--     stay hidden) + identification-ladder showcase: the
--     four TANKs run the full KG tank set (green pill across all 17
--     columns); every new column (BL/ZANZA/GAE/SCHOOL/DREAMT/SHARD/ALC)
--     has HAS, MISSING and NOTEXP cells somewhere in the roster. Generic
--     "Well Fed" carriers split three ways for the matrix ladder:
--     effect line resolving to an ICON-carrying item (Simwall Dumplings,
--     Simrogue Squid, Simmage Danonzo's Delight), effect line resolving
--     to an item WITHOUT a sourced icon (Simheala Herbal Salad ->
--     slot-generic icon, tooltip names the item), and no effects table
--     at all (Simsteel and others -> "item unknown" fallback).
--   * DEBUFFS tab: exactly 3 afflicted players
--     -- Simrogue + Simtree share "Resurrection Sickness" (afflicted=2 =>
--     first column, count sorting testable), Simfrost carries "Curse of
--     Recklessness" + "Weakened Soul" (two columns from ONE player) =>
--     3 columns total, count-desc then alpha: RS, CoR, WS. Every other
--     READABLE player gets an EMPTY debuffs table (legitimate clean state
--     = HAS cells); the 5 unreadable players keep debuffs nil (UNKNOWN).
--   * far flag: 2 READABLE players beyond DC.FAR_LIMIT=40
--     (Simhuntara 55, Simfrost 120) => coverage.far == 2; Simbow keeps
--     distance 31 (near), the read-failed distances 87/203 stay pure
--     diagnosis and never count as far.
--   * weapon enchant names: two players carry
--     weaponMainName -- Simtank "Dense Sharpening Stone", Simmage
--     "Brilliant Wizard Oil" (WPN HAS detail = the name); Simwall and
--     every one of the 40-man fill-in players below stay weaponMain=true
--     WITHOUT a name (generic detail path) -- exactly two named enchants
--     in the whole roster, deliberately.
--   * last-known showcase: Simblade (offline) carries
--     lastAuras + lastGear (At = now-540) so all three aura/equipment
--     tabs show dimmed last-known cells (HAS and MISSING both reachable;
--     the cached EMPTY off hand classifies NOTEXP => that cell stays a
--     plain "?"). Simhuntara is THE cross-continent case: online and
--     aura-readable but gearRead=false + gear nil, with lastGear
--     (At = now-1200) -- EQUIPMENT renders the "out of range" row note
--     plus dimmed tiles. IRON RULE: all of it is display-only, the cells
--     stay UNKNOWN in every count.
--   * deterministic clock: all At offsets and scanAt hang
--     off ONE base `now` -- GetTime() when the client provides it (test
--     mode shows plausible live ages), a FIXED 1000 offline so buildStore
--     stays byte-deterministic under the test harness.
--   * RESIST tab: every readable player carries resistsRead=true + a
--     resists table -- the 3 tanks fire 315/240/180 (a visible spread),
--     Simhuntara nature 120 (resist reads work even with gearRead=false --
--     an independent channel), Simmage frost 85 + arcane 45 (the two-
--     school showcase), everyone else a small deterministic per-school
--     formula (0s occur -- a legitimate resistance, distinct from the 4
--     unreadable players who carry no resist data at all -> UNKNOWN
--     cells). Simtank also carries a real NECK enchant (>0) -- neck/ring
--     enchants are a server-custom feature (data/enchants.lua) whose
--     expectation defaults to OFF, so this doubles as the "not expected,
--     item still shown" showcase.
--   * HIT tab (its own tab, eight columns: melee, ranged and one per
--     magic school): every showcase of the feature is in the roster --
--     MEASURED skill Simtank (skillExact 305 => +1.0% hit on the
--     player's side: melee 8 gear -> 9.0 against the flat 8.0 yellow
--     cap), ESTIMATED racial skill Simwall/Simsteel/Simrogue
--     (human/orc/gnome specializations), BOOK candidate Simsteel (ticking
--     "Axes" in the options adds +3 skill, worth +1.6 on his value, on
--     the next refresh -- the cap stays flat at 8.0 because skill counts
--     on the player's side, and the flag lives in the DB, never in this
--     store), AT CAP
--     Simtank/Simsteel/Simbow (melee + ranged), BELOW CAP Simwall (6)
--     and Simfrost (spell 8 of 16), DUAL WIELD Simrogue (dagger + sword:
--     yellow cap 8.0 met by 10, white cap 27.0), NO RANGED WEAPON
--     Simfrost (empty ranged slot) and every wand user (wands are a
--     spell-hit question) => NOTEXP cells, UNREADABLE Simhuntara
--     (hit = { hitRead = false } -- the item tooltips of an out-of-range
--     unit cannot be scanned, exactly like her gear) plus the offline/
--     read-failed players, who carry no hit table at all.
--   * PER-SCHOOL spread, the reason the tab exists: Simmage is a frost
--     mage with Arcane Focus 5/5 and Elemental Precision 3/3, so her
--     eight columns are NOT one number -- arcane 20.0 (10 generic + 10
--     talent), fire and frost 16.0 (10 + 6), holy/nature/shadow 10.0.
--     Simlock carries the GEAR side of the same idea: a +3% shadow item
--     line, so his shadow column reads 3 above his other schools.
--   * TALENT READABILITY: a foreign player's talents arrive over the
--     inspect protocol (scan/talents.lua) and may simply not be in yet,
--     which is why hit.talentsRead exists and why a tooltip without them
--     says the number excludes talents for now. Test mode deliberately
--     marks a HANDFUL of players talent-readable (Simtank, Simrogue,
--     Simmage) and leaves the rest false, so both tooltip states are
--     visible side by side in one screenshot -- it is simulated data, not
--     a claim that foreign talents are readable. Those three carry a
--     MEASURED weapon skill as well, because live both facts have the
--     same single source: being the own character.
--     Everyone else gets a deterministic filler pass (per-class main
--     weapon, ranged subtype from their equipped ranged item, small
--     per-index numbers, no race => plain base skill, talentsRead false).
--     All of it is display-only: a hit cell is never a gap, so pills stay
--     untouched.
--   * FULL-RAID FILL-IN (the fifteen players that take the roster from the
--     original 25-player sample to the 40-man cap, one per open role
--     slot): each is deliberately "clean" -- full consumables/class buffs
--     via one canonical name list (unexpected slots simply ignore names
--     they do not need, never a gap), default gearWith() (every enchant
--     slot filled, both trinkets present), weaponMain=true without a
--     name. They ride the SAME index-based filler passes below as every
--     other filler player in the original 25 for resist/hit/debuffs, so
--     their exact numbers are deliberately UNPINNED (only their existence
--     and readability matter) -- every pinned showcase value above still
--     lives on the unchanged original 25. Two of them (Simarrow,
--     Simscout) carry a real ranged weapon so the RANGED group's HIT tab
--     is not entirely NOTEXP; Simveil is the 3rd offline case. Column-
--     width stress: Simox is the shortest name in the roster (5
--     characters), Simthornweaver and Simshadowmender the longest
--     (14 / 15).
-- Pure Lua 5.0, no WoW API -- dofile-loadable offline.

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Sim = DC_Sim or {}

-- ------------------------------------------------------------------
-- Built-in role confirmations. Everyone EXCEPT Simfury and Simshade --
-- those two stay unconfirmed so the suggestion flow (dashed badge, ?-mark,
-- reason tooltip) is visible in test mode. Copied into DC.simRoles by
-- buildStore(); NEVER into db.roles.
-- Simsham is a confirmed MELEE (enhancement) although the class heuristic
-- suggests HEALER -- showcases confirmed-beats-suggested.
-- ------------------------------------------------------------------
DC_Sim.ROLES = {
    Simtank    = "TANK",   Simwall   = "TANK",   Simsteel = "TANK",
    Simrogue   = "MELEE",  Simblade  = "MELEE",  Simstab  = "MELEE",
    Simkitty   = "MELEE",  Simsham   = "MELEE",
    Simhuntara = "RANGED", Simbow    = "RANGED", Simtrue  = "RANGED",
    Simmage    = "CASTER", Simfrost  = "CASTER", Simzap   = "CASTER",
    Simlock    = "CASTER", Simafflic = "CASTER", Simboom  = "CASTER",
    Simheala   = "HEALER", Simlight  = "HEALER", Simtree  = "HEALER",
    Simchain   = "HEALER", Simholy   = "HEALER", Simglow  = "HEALER",
    -- Simfury, Simshade intentionally absent -> suggestion badges

    -- Full-raid fill-in (25 -> 40): one open role slot each, all
    -- confirmed (no additional suggestion badges beyond the two above).
    Simblock   = "TANK",
    Simgrit    = "MELEE",  Simslash  = "MELEE",  Simox    = "MELEE",
    Simjolt    = "MELEE",  Simzeal   = "MELEE",
    Simarrow   = "RANGED", Simscout  = "RANGED", Simveil  = "RANGED",
    Simember   = "CASTER", Simdread  = "CASTER", Simvoid  = "CASTER",
    Simthornweaver  = "CASTER",
    Simshadowmender = "HEALER", Simbloom = "HEALER",
}

-- ------------------------------------------------------------------
-- Small builders (fresh tables on every call -- the store must never share
-- table references between builds or players).
-- ------------------------------------------------------------------

-- list -> set
local function set(list)
    local t = {}
    for i = 1, table.getn(list) do
        t[list[i]] = true
    end
    return t
end

-- ------------------------------------------------------------------
-- Canonical "clean" aura set for the 40-man fill-in players (see the
-- header): one name per consumable/class-buff slot, always paired with
-- a working ICONS entry (icon coverage stays satisfied). A slot the
-- player's role/class does not expect simply ignores its name -- an
-- unexpected slot is NOTEXP regardless of what auras are present -- so
-- one shared list is safe to reuse across every role and class.
-- cleanAuras() returns a FRESH table on every call (set() already builds
-- a new table each time); the source list itself is read-only.
--
-- SPROT is filled by "Prayer of Shadow Protection" and NEVER by the bare
-- "Shadow Protection": that bare name belongs to BOTH the priest buff
-- (data/classbuffs.lua SPROT) and the lesser SR potion aura
-- (data/consumables.lua:312, spell 7242). These players carry no aura IDs
-- at all (ids = {}), so the model's ID-before-name rule cannot fire
-- (core/model.lua: haveIds == false) and the bare name would satisfy the
-- SR POTION column as well. Live that stays invisible because SR ships
-- default-off -- but demo mode (core/demo.lua) switches SR on for
-- everyone, which is exactly where the false HAS would show up. The
-- Prayer variant maps to SPROT only (classbuffs.lua:51, ids {27683}) and
-- is the raid-wide form anyway, so the class-buff showcase is unchanged
-- while the SR column stays honest.
-- ------------------------------------------------------------------
local CLEAN_AURA_NAMES = {
    "Flask of the Titans", "Well Fed", "Juju Might", "Juju Power",
    "Elixir of the Mongoose", "R.O.I.D.S.", "Spirit of Zanza",
    "Greater Arcane Elixir", "Elixir of Shadow Power", "Dreamtonic",
    "Dreamshard Elixir", "Mageblood Potion",
    "Elixir of Superior Defense", "Elixir of Fortitude", "Medivh's Merlot",
    "Greater Fire Protection", "Mark of the Wild", "Power Word: Fortitude",
    "Prayer of Shadow Protection", "Arcane Intellect",
    "Soulstone Resurrection",
}

local function cleanAuras()
    return { names = set(CLEAN_AURA_NAMES), ids = {} }
end

-- ------------------------------------------------------------------
-- Aura icons: plausible vanilla icon paths for every
-- buff name the sim can turn into a HAS cell. Cosmetic sim data -- paths
-- only have to LOOK real, the client never loads them offline.
-- ------------------------------------------------------------------
local ICONS = {
    -- FLASK
    ["Flask of the Titans"]        = "Interface\\Icons\\INV_Potion_62",
    ["Flask of Supreme Power"]     = "Interface\\Icons\\INV_Potion_41",
    ["Flask of Distilled Wisdom"]  = "Interface\\Icons\\INV_Potion_97",
    ["Flask of Chromatic Resistance"] = "Interface\\Icons\\INV_Potion_48",
    -- FOOD
    ["Well Fed"]                   = "Interface\\Icons\\Spell_Misc_Food",
    ["Dragonbreath Chili"]         = "Interface\\Icons\\INV_Drink_17",
    -- AP
    ["Winterfall Firewater"]       = "Interface\\Icons\\INV_Potion_92",
    ["Juju Might"]                 = "Interface\\Icons\\INV_Misc_MonsterScales_07",
    -- STR (aura-name variants share the item icon, as for Mageblood below)
    ["Juju Power"]                 = "Interface\\Icons\\INV_Misc_MonsterScales_11",
    ["Elixir of Giants"]           = "Interface\\Icons\\INV_Potion_61",
    ["Elixir of the Giants"]       = "Interface\\Icons\\INV_Potion_61",
    -- AGI
    ["Elixir of the Mongoose"]     = "Interface\\Icons\\INV_Potion_32",
    ["Elixir of Greater Agility"]  = "Interface\\Icons\\INV_Potion_94",
    ["Greater Agility"]            = "Interface\\Icons\\INV_Potion_94",
    -- BL (aura names + item-alias keys, like the data table)
    ["Rage of Ages"]               = "Interface\\Icons\\INV_Stone_15",
    ["R.O.I.D.S."]                 = "Interface\\Icons\\INV_Stone_15",
    ["Strike of the Scorpok"]      = "Interface\\Icons\\INV_Misc_Dust_02",
    ["Ground Scorpok Assay"]       = "Interface\\Icons\\INV_Misc_Dust_02",
    ["Spirit of Boar"]             = "Interface\\Icons\\INV_Drink_12",
    ["Lung Juice Cocktail"]        = "Interface\\Icons\\INV_Drink_12",
    ["Infallible Mind"]            = "Interface\\Icons\\INV_Potion_32",
    ["Spiritual Domination"]       = "Interface\\Icons\\INV_Misc_Food_30",
    ["Gizzard Gum"]                = "Interface\\Icons\\INV_Misc_Food_30",
    -- ZANZA
    ["Spirit of Zanza"]            = "Interface\\Icons\\INV_Potion_30",
    -- GAE / SCHOOL / DREAMT / SHARD (split out of the old SP column)
    ["Greater Arcane Elixir"]      = "Interface\\Icons\\INV_Potion_25",
    ["Arcane Elixir"]              = "Interface\\Icons\\INV_Potion_30",
    ["Elixir of Shadow Power"]     = "Interface\\Icons\\INV_Potion_46",
    ["Elixir of Frost Power"]      = "Interface\\Icons\\INV_Potion_03",
    ["Greater Frost Power"]        = "Interface\\Icons\\INV_Potion_13",
    ["Dreamtonic"]                 = "Interface\\Icons\\INV_Potion_10",
    ["Dreamshard Elixir"]          = "Interface\\Icons\\INV_Potion_12",
    -- MP5 (both TWoW name variants share the item icon)
    ["Mageblood Potion"]           = "Interface\\Icons\\INV_Potion_45",
    ["Mageblood"]                  = "Interface\\Icons\\INV_Potion_45",
    -- ARM
    ["Elixir of Superior Defense"] = "Interface\\Icons\\INV_Potion_66",
    ["Elixir of Greater Defense"]  = "Interface\\Icons\\INV_Potion_43",
    -- HPELX
    ["Elixir of Fortitude"]        = "Interface\\Icons\\INV_Potion_44",
    ["Health II"]                  = "Interface\\Icons\\INV_Potion_44",
    -- ALC (alcohol column, split out of the old HP column)
    ["Rumsey Rum Black Label"]     = "Interface\\Icons\\INV_Drink_04",
    ["Rumsey Rum"]                 = "Interface\\Icons\\INV_Drink_08",
    ["Medivh's Merlot"]            = "Interface\\Icons\\INV_Drink_Waterskin_05",
    ["Medivh's Merlot Blue"]       = "Interface\\Icons\\INV_Drink_Waterskin_01",
    ["Medivh's Merlot Blue Label"] = "Interface\\Icons\\INV_Drink_Waterskin_01",
    ["Kreeg's Stout Beatdown"]     = "Interface\\Icons\\INV_Drink_05",
    -- FR
    ["Greater Fire Protection"]    = "Interface\\Icons\\INV_Potion_24",
    ["Fire Protection"]            = "Interface\\Icons\\INV_Potion_16",
    -- FrR/NR/SR/HR/AR (school protection showcase -- these columns are
    -- hidden until their expectation is enabled per role/class, and demo
    -- mode switches all six on at once; the carriers hold their potion by
    -- SPELL ID, never by name -- "Shadow Protection" is also the priest
    -- class buff, so a name-based carrier would fake an SR fulfillment)
    ["Greater Shadow Protection"]  = "Interface\\Icons\\INV_Potion_23",
    ["Greater Frost Protection"]   = "Interface\\Icons\\INV_Potion_20",
    ["Greater Nature Protection"]  = "Interface\\Icons\\INV_Potion_22",
    ["Holy Protection"]            = "Interface\\Icons\\INV_Potion_09",
    ["Greater Arcane Protection"]  = "Interface\\Icons\\INV_Potion_83",
    -- class buffs
    ["Arcane Intellect"]           = "Interface\\Icons\\Spell_Holy_MagicalSentry",
    ["Arcane Brilliance"]          = "Interface\\Icons\\Spell_Holy_ArcaneIntellect",
    ["Mark of the Wild"]           = "Interface\\Icons\\Spell_Nature_Regeneration",
    ["Gift of the Wild"]           = "Interface\\Icons\\Spell_Nature_GiftoftheWild",
    ["Power Word: Fortitude"]      = "Interface\\Icons\\Spell_Holy_WordFortitude",
    ["Prayer of Fortitude"]        = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude",
    -- the bare name stays: ID-bearing SPROT carriers resolve through
    -- idToName (976/10957/10958 -> "Shadow Protection") and texturesFor
    -- looks the icon up under THAT name. Name-only players use the Prayer
    -- variant instead (see CLEAN_AURA_NAMES).
    -- both spellings share the vanilla Shadow Protection art (the same
    -- alias convention the AP/STR/MP5 entries above use). Deliberately NOT
    -- a "Spell_Holy_PrayerofShadowProtection" path: the Prayer rank is not
    -- a stock 1.12 spell, so that texture cannot be assumed to exist in
    -- the client, and a missing path renders an empty icon.
    ["Shadow Protection"]          = "Interface\\Icons\\Spell_Shadow_AntiShadow",
    ["Prayer of Shadow Protection"] = "Interface\\Icons\\Spell_Shadow_AntiShadow",
    ["Soulstone Resurrection"]     = "Interface\\Icons\\Spell_Shadow_SoulGem",
}

-- Debuff cosmetics. Resurrection Sickness and Weakened Soul genuinely
-- share one icon on 1.12 (both use
-- Spell_Holy_AshesToAshes -- realism over showcase variety).
local DEBUFF_ICONS = {
    ["Resurrection Sickness"]  = "Interface\\Icons\\Spell_Holy_AshesToAshes",
    ["Curse of Recklessness"]  = "Interface\\Icons\\Spell_Shadow_UnholyStrength",
    ["Weakened Soul"]          = "Interface\\Icons\\Spell_Holy_AshesToAshes",
}

-- debuff literal builder: names + ids given, textures from DEBUFF_ICONS
-- (fresh tables per call -- store builds must never share references)
local function debuffsOf(namesList, idsList)
    local d = { names = {}, ids = {}, textures = {} }
    for i = 1, table.getn(namesList) do
        local nm = namesList[i]
        d.names[nm] = true
        if DEBUFF_ICONS[nm] then
            d.textures[nm] = DEBUFF_ICONS[nm]
        end
    end
    for i = 1, table.getn(idsList) do
        d.ids[idsList[i]] = true
    end
    return d
end

-- auras -> textures table (store shape: auras.textures[name] = icon path).
-- Names are taken directly; ids are resolved against the REAL data tables
-- (every table name that carries one of the player's ids gets its icon),
-- so whatever alias DC_Model's id->name index picks, the texture is there.
local function texturesFor(auras)
    local t = {}
    for name in pairs(auras.names) do
        if ICONS[name] then
            t[name] = ICONS[name]
        end
    end
    if DC.CONSUMABLES then
        for name, def in pairs(DC.CONSUMABLES) do
            if def.spellID and def.spellID > 0 and auras.ids[def.spellID]
               and ICONS[name] then
                t[name] = ICONS[name]
            end
        end
    end
    if DC.CLASSBUFFS then
        for name, def in pairs(DC.CLASSBUFFS) do
            if def.ids then
                for i = 1, table.getn(def.ids) do
                    if auras.ids[def.ids[i]] and ICONS[name] then
                        t[name] = ICONS[name]
                    end
                end
            end
        end
    end
    return t
end

-- Main-hand item subtype per class for the hit filler pass below (the
-- weapon skill the melee-hit cap is derived from). Plausible vanilla
-- choices, nothing more -- the showcase players carry explicit literals.
local HIT_MAIN_SUB = {
    WARRIOR = "One-Handed Swords",
    PALADIN = "Two-Handed Maces",
    HUNTER  = "Polearms",
    ROGUE   = "Daggers",
    PRIEST  = "Staves",
    SHAMAN  = "One-Handed Maces",
    MAGE    = "Staves",
    WARLOCK = "Staves",
    DRUID   = "Staves",
}

-- All 17 equipment slots the scan reads (12 armor enchant, WAIST
-- included -- 2026-08-30 owner decision, WAIST is worn equipment like
-- any other slot now -- + neck + 2 rings + 2 trinket invSlots).
local INV_SLOTS = { 1, 2, 3, 15, 5, 6, 9, 10, 7, 8, 16, 17, 18, 11, 12, 13, 14 }

-- Per-slot base item cosmetics: EVERY gear entry table carries texture,
-- name and quality (the UI renders item icons).
local SLOT_BASE = {
    [1]  = { name = "Simulated Faceguard",   quality = 3, texture = "Interface\\Icons\\INV_Helmet_09" },
    [2]  = { name = "Simulated Choker",      quality = 3, texture = "Interface\\Icons\\INV_Jewelry_Necklace_07" },
    [3]  = { name = "Simulated Spaulders",   quality = 3, texture = "Interface\\Icons\\INV_Shoulder_01" },
    [15] = { name = "Simulated Drape",       quality = 3, texture = "Interface\\Icons\\INV_Misc_Cape_16" },
    [5]  = { name = "Simulated Breastplate", quality = 4, texture = "Interface\\Icons\\INV_Chest_Plate04" },
    [6]  = { name = "Simulated Girdle",      quality = 3, texture = "Interface\\Icons\\INV_Belt_03" },
    [9]  = { name = "Simulated Bracers",     quality = 3, texture = "Interface\\Icons\\INV_Bracer_13" },
    [10] = { name = "Simulated Gauntlets",   quality = 3, texture = "Interface\\Icons\\INV_Gauntlets_28" },
    [7]  = { name = "Simulated Legplates",   quality = 4, texture = "Interface\\Icons\\INV_Pants_04" },
    [8]  = { name = "Simulated Sabatons",    quality = 3, texture = "Interface\\Icons\\INV_Boots_Plate_06" },
    [16] = { name = "Simulated Edge",        quality = 4, texture = "Interface\\Icons\\INV_Sword_39" },
    [17] = { name = "Simulated Barrier",     quality = 3, texture = "Interface\\Icons\\INV_Shield_06" },
    [18] = { name = "Simulated Repeater",    quality = 2, texture = "Interface\\Icons\\INV_Weapon_Crossbow_02" },
    [11] = { name = "Simulated Signet",      quality = 3, texture = "Interface\\Icons\\INV_Jewelry_Ring_21" },
    [12] = { name = "Simulated Band",        quality = 2, texture = "Interface\\Icons\\INV_Jewelry_Ring_14" },
    [13] = { name = "Simulated Charm",       quality = 2, texture = "Interface\\Icons\\INV_Misc_OrnateBox" },
    [14] = { name = "Simulated Insignia",    quality = 3, texture = "Interface\\Icons\\INV_Jewelry_Talisman_07" },
}

-- Base gear: every slot filled and enchanted (enchant 900+invSlot except
-- neck/rings/trinkets), every entry with name/quality/texture from
-- SLOT_BASE. Table overrides are MERGED with the slot cosmetics (missing
-- name/quality/texture filled in from SLOT_BASE, everything else -- id,
-- enchant, subType, own cosmetics -- kept); "EMPTY" stays "EMPTY".
-- WAIST (6) is treated like the plain armor slots here -- always
-- enchanted in the base gear, expected by default for every role -- NOT
-- grouped with the enchant-free neck/rings/trinkets below.
-- Neck/rings (2/11/12) default to enchant=0 like trinkets -- but unlike
-- trinkets they ARE enchantable on this server (data/enchants.lua, kind
-- "ench"), so Simtank's override below demonstrates a real neck enchant
-- (their expectation defaults to OFF, so by default this renders the new
-- "not expected, item still shown" tile -- see core/model.lua).
local function gearWith(over)
    local g = {}
    for i = 1, table.getn(INV_SLOTS) do
        local inv = INV_SLOTS[i]
        local base = SLOT_BASE[inv]
        local e = { id = 5000 + inv, enchant = 900 + inv,
                    quality = base.quality, name = base.name,
                    texture = base.texture }
        if inv == 2 or inv == 11 or inv == 12 or inv == 13 or inv == 14 then
            e.enchant = 0   -- neck/rings/trinkets: enchant-free baseline
        end
        g[inv] = e
    end
    if over then
        for inv, v in pairs(over) do
            if type(v) == "table" then
                local base = SLOT_BASE[inv]
                if v.name == nil then
                    v.name = base.name
                end
                if v.quality == nil then
                    v.quality = base.quality
                end
                if v.texture == nil then
                    v.texture = base.texture
                end
            end
            g[inv] = v
        end
    end
    return g
end

-- ------------------------------------------------------------------
-- The roster. Deterministic literals only.
-- ------------------------------------------------------------------
function DC_Sim.buildStore()
    -- deterministic clock (see header): base for scanAt
    -- and the last-known At offsets below
    local now = 1000
    if type(GetTime) == "function" then
        now = GetTime()
    end

    -- reset transient sim confirmations to the built-in set (fresh copy)
    DC.simRoles = {}
    for name, role in pairs(DC_Sim.ROLES) do
        DC.simRoles[name] = role
    end

    local players = {}
    local function add(p)
        table.insert(players, p)
    end

    -- ================= TANKS (3) -- all readable, 0 gaps in every tab ====

    -- Simtank: spell-ID-only auras (names empty) -> proves the ID match
    -- path alone. Thrown weapon -> ranged enchant NOTEXP. Epic + rare
    -- trinkets (WoW quality: 4 = epic, 3 = rare). Neck enchant demo (D6):
    -- a real neck enchant>0 -- NECK's expectation defaults to OFF, so this
    -- shows the "not expected, item still shown, bright, no marker" tile
    -- by default; enabling the checkbox for TANK/WARRIOR would flip it to
    -- HAS with a green corner marker (same data, no sim change needed).
    -- Fire resistance 315 -- highest of the three tanks (showcase spread).
    add{ name = "Simtank", class = "WARRIOR", online = true,
        guid = "0xF530000000000001", subgroup = 1,
        aurasRead = true,
        auras = { names = {}, ids = set({ 17626, 15852, 17038, 16323,
            17538, 10667, 24382, 11348, 3593, 25804, 17543, 17548,
            9885, 10938, 10958 }) },
        -- FLASK Titans, FOOD Chili, AP Firewater, STR JujuPower,
        -- AGI Mongoose, BL RageOfAges(ROIDS), ZANZA, ARM SupDef,
        -- HPELX Fortitude, ALC RumseyBlack, FR GFPP, SR GSPP (shadow-boss
        -- prep -- NOTEXP/hidden until the SR expectation is enabled, then
        -- the column lights up green for him), MOTW r7, PWF r6,
        -- SPROT r3 -- the full KG tank set, 0 gaps (green pill)
        weaponMain = true, weaponMainName = "Dense Sharpening Stone",
        gearRead = true,
        resistsRead = true, resists = { [2] = 315 },
        -- hit: the MEASURED-skill showcase (what the own character looks
        -- like) -- skillExact means the 305 came from the skill window,
        -- which lowers the yellow cap to 7.0; melee 8 sits above it.
        -- talentsRead with NO talent numbers is its own state and a real
        -- one: a protection warrior has no hit talent at all, so this is
        -- a VERIFIED zero rather than the "not received yet" case below.
        race = "Human",
        hit = { melee = 8, spell = 0, schools = {}, hitRead = true,
                mainSub = "One-Handed Maces", offSub = "Shields",
                rangedSub = "Thrown", skillName = "Maces",
                skill = 305, skillExact = true, talentsRead = true },
        gear = gearWith({
            [17] = { id = 5117, enchant = 917, subType = "Shields", quality = 3 },
            [18] = { id = 5118, enchant = 0, subType = "Thrown",
                     name = "Simulated Throwing Axe" },
            [2]  = { id = 5299, enchant = 950, name = "Simulated Neck Chain" },
            [13] = { id = 5213, enchant = 0, quality = 4, name = "Simulated Drake Talisman",
                     texture = "Interface\\Icons\\INV_Misc_Bone_10" },
            [14] = { id = 5214, enchant = 0, quality = 3, name = "Simulated Hand of Justice",
                     texture = "Interface\\Icons\\INV_Jewelry_Talisman_01" },
        }) }

    -- Simwall: name-only auras (ids empty = sparse) -> proves the name
    -- fallback path alone. Gun with scope (enchant>0) -> ranged HAS.
    -- Deliberately weaponMain=true WITHOUT weaponMainName (so
    -- the generic "main hand temp enchant" detail path stays exercised).
    -- Fire resistance 240.
    add{ name = "Simwall", class = "WARRIOR", online = true,
        guid = "0xF530000000000002", subgroup = 1,
        aurasRead = true,
        auras = { names = set({ "Flask of the Titans", "Well Fed",
            "Winterfall Firewater", "Juju Power", "Elixir of the Mongoose",
            "R.O.I.D.S.", "Spirit of Zanza",
            "Elixir of Superior Defense", "Elixir of Fortitude",
            "Medivh's Merlot", "Greater Fire Protection",
            "Mark of the Wild", "Power Word: Fortitude",
            -- Prayer variant, not the bare name: see CLEAN_AURA_NAMES
            "Prayer of Shadow Protection" }), ids = {},
            -- effect line for the generic "Well Fed": the identification
            -- ladder resolves it to Smoked Desert Dumplings in the matrix
            effects = { ["Well Fed"] = "Increases Strength by 20." } },
        weaponMain = true, gearRead = true,
        resistsRead = true, resists = { [2] = 240 },
        -- hit: the BELOW-cap showcase -- a human swordsman, so the racial
        -- specialization is ESTIMATED into the skill (300 + 5 => cap 7.0)
        -- and 6 still falls short of it
        race = "Human",
        hit = { melee = 6, spell = 0, schools = {}, hitRead = true,
                talentsRead = false,
                mainSub = "One-Handed Swords", offSub = "Shields",
                rangedSub = "Guns" },
        gear = gearWith({
            [17] = { id = 5127, enchant = 917, subType = "Shields", quality = 3 },
            [18] = { id = 5128, enchant = 33, subType = "Guns",
                     name = "Simulated Blunderbuss" },
        }) }

    -- Simsteel: mixed matching -- ids for everything with a known spell ID,
    -- "Well Fed" (id-less entry) by name. NOTE the model's strict rule: once
    -- a player has ANY ids, names of id-bearing entries no longer count, so
    -- a "mixed" player may only name-match id-less entries. Bow with scope.
    -- Fire resistance 180 -- lowest of the three tanks.
    add{ name = "Simsteel", class = "WARRIOR", online = true,
        guid = "0xF530000000000003", subgroup = 1,
        aurasRead = true,
        auras = { names = set({ "Well Fed" }),
            ids = set({ 17629, 16329, 11405, 11334, 10669, 24382,
                11349, 3593, 25804, 7233, 17544, 21849, 21562, 10957 }) },
        -- FLASK ChromRes, AP JujuMight, STR Giants, AGI GreaterAgi,
        -- BL Scorpok, ZANZA, ARM GreaterDef, HPELX Fortitude(HealthII),
        -- ALC RumseyBlack, FR FireProt, FrR GFrPP (17544 -- the frost
        -- carrier of the six-school demo view, hidden by default),
        -- MOTW Gift, PWF Prayer, SPROT r2.
        -- NO effects table: his "Well Fed" stays unresolvable -- the
        -- matrix ladder's slot-generic-icon floor ("item unknown")
        weaponMain = true, gearRead = true,
        resistsRead = true, resists = { [2] = 180 },
        -- hit: the BOOK showcase -- an orc axeman (racial +5 => cap 7.0);
        -- ticking "Axes" for this player in the options adds another +3
        -- skill and drops the cap to 6.4 on the very next refresh (the
        -- book flag lives in the DB, never in the store)
        race = "Orc",
        hit = { melee = 8, spell = 0, schools = {}, hitRead = true,
                talentsRead = false,
                mainSub = "One-Handed Axes", offSub = "Shields",
                rangedSub = "Bows" },
        gear = gearWith({
            [17] = { id = 5137, enchant = 917, subType = "Shields", quality = 3 },
            [18] = { id = 5138, enchant = 33, subType = "Bows",
                     name = "Simulated Longbow" },
        }) }

    -- ================= MELEE (6) =========================================

    -- Simfury: UNCONFIRMED -> heuristic suggests MELEE ("class default";
    -- no shield). EMPTY off hand (fury with a 2H habit) -> NOTEXP under the
    -- model's exemption resolution (no item on an exemptable slot = nothing
    -- to enchant). Missing HP + FR consumables, missing PWF + SPROT class
    -- buffs, head enchant missing -> whisper-eligible in every tab.
    add{ name = "Simfury", class = "WARRIOR", online = true,
        guid = "0xF530000000000004", subgroup = 1,
        aurasRead = true,
        auras = { names = set({ "Well Fed", "Juju Might", "Juju Power",
            "Elixir of the Mongoose", "Mark of the Wild" }), ids = {} },
        weaponMain = true, gearRead = true,
        gear = gearWith({
            [1]  = { id = 5141, enchant = 0 },   -- head enchant missing
            [17] = "EMPTY",                       -- empty off hand -> gap
            [18] = { id = 5148, enchant = 0, subType = "Thrown" },
        }) }

    -- Simrogue: ID matches for everything id-bearing, "Well Fed" by name.
    -- EMPTY trinket slot 14 (the one empty trinket of the roster).
    -- FR + SPROT missing. Afflicted 1/3: Resurrection Sickness (shared
    -- with Simtree -> RS afflicted=2 = first debuff column).
    add{ name = "Simrogue", class = "ROGUE", online = true,
        guid = "0xF530000000000005", subgroup = 2,
        aurasRead = true,
        auras = { names = set({ "Well Fed" }),
            ids = set({ 17626, 16329, 17538, 16323, 10692, 24382,
                3593, 9885, 10938 }),
            -- +10 Agility resolves to Grilled Squid through the ladder
            effects = { ["Well Fed"] = "Increases Agility by 10." } },
        -- FLASK Titans, AP JujuMight, AGI Mongoose, STR JujuPower,
        -- BL Cortex(InfallibleMind), ZANZA, HPELX Fortitude (NOTEXP for
        -- MELEE, harmless), MOTW r7, PWF r6
        debuffs = debuffsOf({ "Resurrection Sickness" }, { 15007 }),
        weaponMain = true, gearRead = true,
        -- hit: the DUAL-WIELD showcase -- two weapon subtypes, so the cell
        -- carries the yellow cap (gnome dagger racial => 7.0, met by 9)
        -- AND the white dual-wield cap (26.0) in its tooltip.
        -- Also the TALENT showcase on the melee side: the 9 is 4 from
        -- gear plus 5 from the rogue's 5/5 melee-hit talent, and the
        -- tooltip names both parts instead of one lump sum.
        race = "Gnome",
        hit = { melee = 9, gearMelee = 4, talentMelee = 5,
                talentsRead = true,
                -- measured skill goes WITH the read talents: both come
                -- from the own character in the live client, so a
                -- talent-readable sim player carries a measured skill
                -- too (305 is what the gnome dagger racial estimates
                -- anyway, so the cap is the same either way)
                skill = 305, skillExact = true, skillName = "Daggers",
                spell = 0, schools = {}, hitRead = true,
                mainSub = "Daggers", offSub = "One-Handed Swords",
                rangedSub = "Thrown" },
        gear = gearWith({
            [18] = { id = 5158, enchant = 0, subType = "Thrown" },
            [12] = "EMPTY",                       -- empty ring 2 -> gap
            [14] = "EMPTY",                       -- empty trinket -> gap
        }) }

    -- Simblade: OFFLINE (auras/gear nil, weaponMain nil, no distance --
    -- a disconnected unit cannot be measured). Carries the
    -- runtime cache's LAST-KNOWN snapshot from before the disconnect --
    -- lastAuras (HP/FR consumables + SPROT class buff absent => dimmed
    -- MISSING reachable, the rest dimmed HAS) and lastGear (wrist
    -- enchant 0 => dimmed MISSING; EMPTY off hand => cached classify
    -- NOTEXP => NO cell.last, the plain "?" stays). No lastWeaponMain:
    -- the WPN cell shows what a channel WITHOUT cache looks like.
    -- IRON RULE: display-only -- Simblade stays UNKNOWN in every count.
    local bladeAuras = { names = set({ "Well Fed", "Juju Might",
        "Juju Power", "Elixir of the Mongoose", "Mark of the Wild",
        "Power Word: Fortitude" }), ids = {} }
    bladeAuras.textures = texturesFor(bladeAuras)
    add{ name = "Simblade", class = "ROGUE", online = false,
        guid = "0xF530000000000006", subgroup = 8,
        aurasRead = false, gearRead = false,
        unreadableReason = "offline",
        lastAuras = bladeAuras, lastAurasAt = now - 540,
        lastGear = gearWith({
            [9]  = { id = 5162, enchant = 0 },   -- wrist: dimmed MISSING
            [17] = "EMPTY",                      -- cached NOTEXP -> no .last
            [18] = { id = 5163, enchant = 0, subType = "Thrown" },
        }),
        lastGearAt = now - 540 }

    -- Simstab: name matching, only gap on consumables = no temp weapon
    -- enchant; class buffs complete; two enchant gaps.
    add{ name = "Simstab", class = "ROGUE", online = true,
        guid = "0xF530000000000007", subgroup = 2,
        aurasRead = true,
        auras = { names = set({ "Flask of the Titans", "Well Fed",
            "Juju Might", "Juju Power", "Elixir of Greater Agility",
            "Lung Juice Cocktail", "Spirit of Zanza",
            "Elixir of Fortitude", "Fire Protection", "Mark of the Wild",
            "Power Word: Fortitude",
            "Prayer of Shadow Protection" }), ids = {} },
        weaponMain = false, gearRead = true,
        gear = gearWith({
            [9] = { id = 5169, enchant = 0 },    -- wrist enchant missing
            [7] = { id = 5167, enchant = 0 },    -- legs enchant missing
            [18] = { id = 5168, enchant = 0, subType = "Thrown" },
        }) }

    -- Simkitty: druid in Cat Form (confirmed MELEE anyway). AP/AGI/MOTW via
    -- spell ID, FOOD + form by name; STR/HP/FR/WPN missing; druid: EMPTY
    -- ranged + EMPTY off hand (staff) -> NOTEXP (exemptable slots).
    add{ name = "Simkitty", class = "DRUID", online = true,
        guid = "0xF530000000000008", subgroup = 2,
        aurasRead = true,
        auras = { names = set({ "Cat Form", "Well Fed" }),
            ids = set({ 16329, 17538, 9885 }) },
        weaponMain = false, gearRead = true,
        gear = gearWith({
            [17] = "EMPTY",
            [18] = "EMPTY",
        }) }

    -- Simsham: enhancement -- CONFIRMED MELEE although the heuristic would
    -- say HEALER. Full consumables/class buffs (ids + "Well Fed" by name);
    -- shaman: EMPTY ranged slot -> NOTEXP.
    -- Note (roles stay as-is, no
    -- shipped default changes): a shaman is also the per-class
    -- expectation poster child -- a TANK-confirmed shaman would get
    -- expectations.TANK.SHAMAN.AI = true (INT for the mana-fed tank kit)
    -- flipped by the user in the options grid; AI ships as the CASTER/HEALER
    -- role default for every performing class.
    add{ name = "Simsham", class = "SHAMAN", online = true,
        guid = "0xF530000000000009", subgroup = 2,
        aurasRead = true,
        auras = { names = set({ "Well Fed" }),
            ids = set({ 17626, 17038, 11405, 17538, 10693, 24382,
                25804, 17543, 17546, 9885, 10938, 10958 }) },
        -- FLASK Titans, AP Firewater, STR Giants, AGI Mongoose,
        -- BL Gizzard(SpiritualDomination), ZANZA, ALC RumseyBlack
        -- (NOTEXP for MELEE, harmless), FR GFPP, NR GNPP (17546 -- the
        -- nature carrier of the six-school demo view), MOTW r7, PWF r6,
        -- SPROT r3 (the priest buff by ID -- he holds no SR potion, which
        -- is exactly the name-collision case the demo view must not
        -- mistake for a fulfilled SR column)
        weaponMain = true, gearRead = true,
        gear = gearWith({
            [17] = { id = 5197, enchant = 917, subType = "Shields", quality = 3 },
            [18] = "EMPTY",
        }) }

    -- ================= RANGED (3) ========================================

    -- Simhuntara: AP/AGI/MOTW via spell ID; HP/FR + PWF/SPROT missing.
    -- Far case 1/2: readable at distance 55 (>= FAR_LIMIT 40).
    -- THE cross-continent case -- the aura paths reach
    -- anywhere, gear inspection does not: gearRead=false + gear nil on an
    -- ONLINE, aura-readable player, with the runtime cache's lastGear
    -- attached (a 20-minutes-old snapshot). EQUIPMENT renders the
    -- "out of range" row note + dimmed tiles; nothing counts (IRON RULE).
    -- Nature resistance 120 -- resist reads are their OWN channel,
    -- independent of gearRead=false above (a resistance read is neither
    -- an aura nor a gear read).
    add{ name = "Simhuntara", class = "HUNTER", online = true,
        guid = "0xF53000000000000A", subgroup = 4, distance = 55,
        aurasRead = true,
        auras = { names = set({ "Well Fed" }),
            ids = set({ 16329, 17538, 9885 }) },
        weaponMain = true, gearRead = false,
        resistsRead = true, resists = { [3] = 120 },
        -- hit: THE unreadable showcase -- hit is summed from item
        -- tooltips, so it dies with the same range limit as the gear read
        -- (resistances survive it, they are their own channel)
        hit = { hitRead = false },
        lastGear = gearWith({
            [18] = { id = 5178, enchant = 33, subType = "Guns",
                     name = "Simulated Rifle" },
        }),
        lastGearAt = now - 1200 }

    -- Simbow: fully clean row (green contrast inside a non-green group).
    add{ name = "Simbow", class = "HUNTER", online = true,
        guid = "0xF53000000000000B", subgroup = 3, distance = 31,
        aurasRead = true,
        auras = { names = set({ "Well Fed", "Juju Might",
            "Elixir of Greater Agility", "Ground Scorpok Assay",
            "Spirit of Zanza", "Rumsey Rum",
            "Greater Fire Protection", "Mark of the Wild",
            "Power Word: Fortitude",
            "Prayer of Shadow Protection" }), ids = {} },
        -- ALC (Rumsey Rum) is NOTEXP for RANGED -- harmless extra
        weaponMain = true, gearRead = true,
        -- hit: the RANGED showcase -- a real bow, so the ranged column is
        -- a question at all; 8 meets its 8.0 cap (a dwarf's racial is on
        -- guns, not bows, so nothing lowers this one)
        race = "Dwarf",
        hit = { melee = 8, spell = 0, schools = {}, hitRead = true,
                talentsRead = false,
                mainSub = "Polearms", rangedSub = "Bows" },
        gear = gearWith({
            [18] = { id = 5188, enchant = 33, subType = "Bows",
                     name = "Simulated Warbow" },
        }) }

    -- Simtrue: READ FAILED (online, but the aura path returned zero auras).
    -- distance recorded as diagnosis, never as filter.
    add{ name = "Simtrue", class = "HUNTER", online = true,
        guid = "0xF53000000000000C", subgroup = 8, distance = 203,
        aurasRead = false, gearRead = false,
        unreadableReason = "read failed" }

    -- ================= CASTERS (7) =======================================

    -- Simmage: everything id-bearing via spell ID, FOOD by name; FR
    -- missing. Wand -> ranged NOTEXP, holdable frill -> off hand NOTEXP.
    -- Frost 85 + arcane 45 -- the two-school showcase (every other
    -- resist-carrying player below has only one school set explicitly).
    add{ name = "Simmage", class = "MAGE", online = true,
        guid = "0xF53000000000000D", subgroup = 4,
        aurasRead = true,
        auras = { names = set({ "Well Fed" }),
            ids = set({ 17628, 23028, 17539, 21920, 45489, 45427, 24382,
                24363, 17549, 9885, 10938, 10958 }),
            -- +22 spell damage -> Danonzo's Tel'Abim Delight (ladder)
            effects = { ["Well Fed"] =
                "Increases spell damage by up to 22." } },
        -- FLASK Supreme, AI Brilliance, GAE, SCHOOL FrostPower,
        -- DREAMT, SHARD, ZANZA, MP5 Mageblood, AR GAPP (17549 -- the
        -- arcane carrier of the six-school demo view), MOTW, PWF, SPROT --
        -- the full KG caster set except FR (her designed gap)
        weaponMain = true, weaponMainName = "Brilliant Wizard Oil",
        gearRead = true,
        resistsRead = true, resists = { [4] = 85, [6] = 45 },
        -- hit: THE per-school showcase and the reason the tab has eight
        -- columns. 10% generic spell hit from gear, and a frost mage's
        -- two school talents on top: Arcane Focus 5/5 (+10 arcane) and
        -- Elemental Precision 3/3 (+6 frost AND fire). Her columns
        -- therefore read arcane 20.0, fire 16.0, frost 16.0, everything
        -- else 10.0 -- three different numbers on ONE caster, which no
        -- single spell-hit column could ever show. The wand makes the
        -- ranged column NOTEXP and the orb in the off hand is not a
        -- weapon, so no dual-wield note either.
        race = "Gnome",
        hit = { melee = 0, spell = 10, gearSpell = 10, schools = {},
                talentsRead = true, talentSpell = 0,
                talentSchools = { arcane = 10, fire = 6, frost = 6 },
                -- measured skill rides along with the read talents (see
                -- Simrogue): a staff has no racial, so 300 is also what
                -- the estimate would have produced
                skill = 300, skillExact = true, skillName = "Staves",
                hitRead = true, mainSub = "Staves",
                offSub = "Miscellaneous", rangedSub = "Wands" },
        gear = gearWith({
            [17] = { id = 5207, enchant = 0, subType = "Miscellaneous",
                     name = "Simulated Orb" },
            [18] = { id = 5208, enchant = 0, subType = "Wands",
                     name = "Simulated Wand" },
        }) }

    -- Simfrost: name-only, several gaps (MP5/FR/WPN missing; MOTW/PWF/SPROT
    -- missing; head+shoulder enchants missing; EMPTY ranged on a mage --
    -- forgot the wand). Afflicted 2/3: Curse of Recklessness + Weakened
    -- Soul (TWO debuff columns from one player). Far case 2/2: readable
    -- at distance 120.
    add{ name = "Simfrost", class = "MAGE", online = true,
        guid = "0xF53000000000000E", subgroup = 4, distance = 120,
        aurasRead = true,
        auras = { names = set({ "Flask of Supreme Power", "Well Fed",
            "Arcane Elixir", "Arcane Intellect" }), ids = {} },
        debuffs = debuffsOf({ "Curse of Recklessness", "Weakened Soul" },
            { 11717, 6788 }),
        weaponMain = false, gearRead = true,
        -- hit: BELOW the spell cap (8 of 16) and an EMPTY ranged slot --
        -- the second NOTEXP path (no ranged item at all, not just a wand)
        race = "Undead",
        hit = { melee = 0, spell = 8, schools = {}, hitRead = true,
                talentsRead = false, mainSub = "Staves" },
        gear = gearWith({
            [1] = { id = 5211, enchant = 0 },
            [3] = { id = 5212, enchant = 0 },
            [18] = "EMPTY",
        }) }

    -- Simzap: OFFLINE.
    add{ name = "Simzap", class = "MAGE", online = false,
        guid = "0xF53000000000000F", subgroup = 8,
        aurasRead = false, gearRead = false,
        unreadableReason = "offline" }

    -- Simlock: THE wand warlock (ranged enchant NOTEXP via subtype).
    -- Name-only reader (ids empty) so the "Mageblood" TWoW alias entry is
    -- exercised via the name fallback. One gap: SPROT.
    add{ name = "Simlock", class = "WARLOCK", online = true,
        guid = "0xF530000000000010", subgroup = 5,
        aurasRead = true,
        auras = { names = set({ "Well Fed", "Flask of Supreme Power",
            "Greater Arcane Elixir", "Elixir of Shadow Power",
            "Dreamtonic", "Dreamshard Elixir", "Spirit of Zanza",
            "Mageblood", "Fire Protection",
            "Arcane Intellect", "Mark of the Wild",
            "Power Word: Fortitude" }),
            ids = {} },
        weaponMain = true, gearRead = true,
        -- hit: the school-specific GEAR showcase, and the counterpart to
        -- Simmage's talents -- an item line worth +3% shadow spell hit
        -- lifts his shadow column to 9.0 while every other school reads
        -- 6.0. talentsRead stays false: this fixture models a player whose
        -- inspect reply (scan/talents.lua) has not arrived yet, so the
        -- number is honestly
        -- gear-only and every tooltip on this row says so (a warlock
        -- would realistically add shadow talents on top of this).
        hit = { melee = 0, spell = 6, gearSpell = 6,
                schools = { Shadow = 3 },
                talentsRead = false,
                hitRead = true, mainSub = "Staves", rangedSub = "Wands" },
        gear = gearWith({
            [18] = { id = 5218, enchant = 0, subType = "Wands",
                     name = "Simulated Ghastly Wand" },
        }) }

    -- Simafflic: many consumable gaps; Soulstone on a CASTER -> SOUL cell
    -- is NOTEXP although the aura is present (expectation wins).
    add{ name = "Simafflic", class = "WARLOCK", online = true,
        guid = "0xF530000000000011", subgroup = 5,
        aurasRead = true,
        auras = { names = set({ "Well Fed", "Soulstone Resurrection" }),
            ids = {} },
        weaponMain = false, gearRead = true,
        gear = gearWith({
            [8]  = { id = 5228, enchant = 0 },   -- feet enchant missing
            [15] = { id = 5225, enchant = 0 },   -- back enchant missing
            [18] = { id = 5229, enchant = 0, subType = "Wands" },
        }) }

    -- Simshade: UNCONFIRMED shadow priest -> heuristic suggests CASTER
    -- ("Shadowform at scan time"). Otherwise a completely clean row:
    -- a suggestion badge is not a gap.
    add{ name = "Simshade", class = "PRIEST", online = true,
        guid = "0xF530000000000012", subgroup = 5,
        aurasRead = true,
        auras = { names = set({ "Shadowform", "Flask of Supreme Power",
            "Well Fed", "Greater Arcane Elixir", "Elixir of Shadow Power",
            "Dreamtonic", "Dreamshard Elixir", "Spirit of Zanza",
            "Mageblood Potion",
            "Greater Fire Protection", "Arcane Intellect",
            "Mark of the Wild", "Power Word: Fortitude",
            "Prayer of Shadow Protection" }), ids = {} },
        weaponMain = true, gearRead = true,
        gear = gearWith({
            [18] = { id = 5238, enchant = 0, subType = "Wands" },
        }) }

    -- Simboom: moonkin (confirmed CASTER). FLASK/MP5/FR/WPN missing,
    -- MOTW/PWF/SPROT missing, wrist enchant missing, EMPTY ranged.
    add{ name = "Simboom", class = "DRUID", online = true,
        guid = "0xF530000000000013", subgroup = 6,
        aurasRead = true,
        auras = { names = set({ "Moonkin Form", "Well Fed",
            "Greater Arcane Elixir", "Arcane Intellect" }), ids = {} },
        weaponMain = false, gearRead = true,
        gear = gearWith({
            [9] = { id = 5249, enchant = 0 },
            [18] = "EMPTY",
        }) }

    -- ================= HEALERS (6) =======================================

    -- Simheala: complete healer, all id-bearing buffs via spell ID (epic
    -- trinket, holdable off hand -> NOTEXP). Clean row.
    add{ name = "Simheala", class = "PRIEST", online = true,
        guid = "0xF530000000000014", subgroup = 6,
        aurasRead = true,
        auras = { names = set({ "Well Fed" }),
            ids = set({ 17627, 20765, 24363, 45427, 24382, 22790,
                3593, 7233, 7245, 10157, 9885, 10938, 10958 }),
            -- mid-ladder showcase: Le Fishe Au Chocolat resolves by its
            -- dodge effect line but has NO sourced icon in the data (icon
            -- is a questionmark placeholder even upstream) -> the matrix
            -- shows the slot-generic FOOD icon while the tooltip still
            -- names the item. (Herbal Salad carried this showcase until
            -- its icon was sourced on 2026-08-11.)
            effects = { ["Well Fed"] =
                "Increases your chance to dodge by 1% and Defense by 4." } },
        -- FLASK Wisdom, SOUL r5, MP5 Mageblood, SHARD, ZANZA,
        -- ALC Kreeg's, HPELX Fortitude (NOTEXP for HEALER, harmless),
        -- FR FireProt, HR HPP (7245 -- the holy carrier of the six-school
        -- demo view; no Greater tier exists for holy), AI r5, MOTW r7,
        -- PWF r6, SPROT r3
        weaponMain = true, gearRead = true,
        gear = gearWith({
            [17] = { id = 5257, enchant = 0, subType = "Miscellaneous",
                     name = "Simulated Prayer Book" },
            [18] = { id = 5258, enchant = 0, subType = "Wands" },
            [13] = { id = 5263, enchant = 0, quality = 4, name = "Simulated Eye of the Naga",
                     texture = "Interface\\Icons\\INV_Jewelry_Talisman_06" },
        }) }

    -- Simlight: READ FAILED, distance 87.
    add{ name = "Simlight", class = "PRIEST", online = true,
        guid = "0xF530000000000015", subgroup = 8, distance = 87,
        aurasRead = false, gearRead = false,
        unreadableReason = "read failed" }

    -- Simtree: HP/FR/WPN missing, SOUL missing, hands enchant missing,
    -- EMPTY ranged. "Mageblood" alias again on the MP5 slot. Afflicted
    -- 3/3: shares Resurrection Sickness with Simrogue (RS afflicted=2).
    add{ name = "Simtree", class = "DRUID", online = true,
        guid = "0xF530000000000016", subgroup = 6,
        aurasRead = true,
        auras = { names = set({ "Flask of Distilled Wisdom", "Well Fed",
            "Mageblood", "Arcane Intellect", "Mark of the Wild",
            "Power Word: Fortitude",
            "Prayer of Shadow Protection" }), ids = {} },
        debuffs = debuffsOf({ "Resurrection Sickness" }, { 15007 }),
        weaponMain = false, gearRead = true,
        gear = gearWith({
            [10] = { id = 5270, enchant = 0 },
            [18] = "EMPTY",
        }) }

    -- Simchain: resto shaman, SPROT + SOUL missing, EMPTY ranged -> NOTEXP.
    add{ name = "Simchain", class = "SHAMAN", online = true,
        guid = "0xF530000000000017", subgroup = 7,
        aurasRead = true,
        auras = { names = set({ "Well Fed" }),
            ids = set({ 17627, 24363, 45427, 24382, 25804, 7233,
                10156, 9885, 10938 }) },
        -- FLASK Wisdom, MP5 Mageblood, SHARD, ZANZA, ALC RumseyBlack,
        -- FR FireProt, AI r4, MOTW r7, PWF r6
        weaponMain = true, gearRead = true,
        gear = gearWith({
            [17] = { id = 5277, enchant = 917, subType = "Shields", quality = 3 },
            [18] = "EMPTY",
        }) }

    -- Simholy: name-only healer, complete on auras incl. SOUL; chest
    -- enchant missing, EMPTY ranged (paladin), holdable off hand NOTEXP.
    add{ name = "Simholy", class = "PALADIN", online = true,
        guid = "0xF530000000000018", subgroup = 7,
        aurasRead = true,
        auras = { names = set({ "Flask of Distilled Wisdom", "Well Fed",
            "Mageblood Potion", "Dreamshard Elixir", "Spirit of Zanza",
            "Kreeg's Stout Beatdown", "Elixir of Fortitude",
            "Greater Fire Protection", "Arcane Intellect",
            "Mark of the Wild", "Power Word: Fortitude",
            "Prayer of Shadow Protection",
            "Soulstone Resurrection" }), ids = {} },
        weaponMain = true, gearRead = true,
        gear = gearWith({
            [5] = { id = 5285, enchant = 0 },
            [17] = { id = 5287, enchant = 0, subType = "Miscellaneous",
                     name = "Simulated Libram of Hope" },
            [18] = "EMPTY",
        }) }

    -- Simglow: ALC via the id-less "Medivh's Merlot Blue" name entry
    -- (spellID 0) WHILE ids are present -- exercises exactly the model
    -- rule that id-less names still count for players with ids.
    -- SPROT missing, EMPTY ranged.
    add{ name = "Simglow", class = "PALADIN", online = true,
        guid = "0xF530000000000019", subgroup = 7,
        aurasRead = true,
        auras = { names = set({ "Well Fed", "Medivh's Merlot Blue" }),
            ids = set({ 17627, 21850, 21564, 24363, 45427, 24382,
                7233, 1461, 20762 }) },
        -- FLASK Wisdom, MOTW Gift, PWF Prayer, MP5 Mageblood, SHARD,
        -- ZANZA, FR FireProt, AI r3, SOUL r2
        weaponMain = true, gearRead = true,
        gear = gearWith({
            [17] = { id = 5297, enchant = 917, subType = "Shields", quality = 3 },
            [18] = "EMPTY",
        }) }

    -- ================= FULL-RAID FILL-IN (25 -> 40, see header) =========
    -- Every player below is deliberately "clean": cleanAuras() covers
    -- every consumable/class-buff slot any role could expect, default
    -- gearWith() leaves every enchant slot filled and both trinkets
    -- present, weaponMain=true carries no name (the generic WPN detail
    -- path, like Simwall -- keeps the "exactly two named enchants" count
    -- unchanged). Resist/hit/debuffs come from the index-based filler
    -- passes below, exactly like every other filler player in the
    -- original 25 -- their numbers are deliberately unpinned.

    -- Simblock: the 4th tank (protection paladin) -- keeps the TANK group
    -- entirely readable with 0 gaps (the green-pill case stays a green
    -- pill at 4 members). RNGD is class-exempt for paladins either way.
    add{ name = "Simblock", class = "PALADIN", online = true,
        guid = "0xF53000000000001A", subgroup = 1,
        aurasRead = true, auras = cleanAuras(),
        weaponMain = true, gearRead = true, gear = gearWith() }

    add{ name = "Simgrit", class = "WARRIOR", online = true,
        guid = "0xF53000000000001B", subgroup = 2,
        aurasRead = true, auras = cleanAuras(),
        weaponMain = true, gearRead = true, gear = gearWith() }

    add{ name = "Simslash", class = "ROGUE", online = true,
        guid = "0xF53000000000001C", subgroup = 3,
        aurasRead = true, auras = cleanAuras(),
        weaponMain = true, gearRead = true, gear = gearWith() }

    -- Simox: melee-spec hunter (a real TWoW spec, see DC_Roles.CLASS_ROLES)
    -- and the column-width showcase: the shortest name in the roster.
    add{ name = "Simox", class = "HUNTER", online = true,
        guid = "0xF53000000000001D", subgroup = 3,
        aurasRead = true, auras = cleanAuras(),
        weaponMain = true, gearRead = true, gear = gearWith() }

    add{ name = "Simjolt", class = "SHAMAN", online = true,
        guid = "0xF53000000000001E", subgroup = 3,
        aurasRead = true, auras = cleanAuras(),
        weaponMain = true, gearRead = true, gear = gearWith() }

    add{ name = "Simzeal", class = "PALADIN", online = true,
        guid = "0xF53000000000001F", subgroup = 3,
        aurasRead = true, auras = cleanAuras(),
        weaponMain = true, gearRead = true, gear = gearWith() }

    -- Simarrow/Simscout: real ranged weapons (unlike the other fill-in
    -- players' default ranged slot) so the RANGED group's HIT tab is not
    -- entirely NOTEXP -- the hit filler pass below reads gear[18].subType.
    add{ name = "Simarrow", class = "HUNTER", online = true,
        guid = "0xF530000000000020", subgroup = 4,
        aurasRead = true, auras = cleanAuras(),
        weaponMain = true, gearRead = true,
        gear = gearWith({
            [18] = { id = 5426, enchant = 33, subType = "Bows",
                     name = "Simulated Huntsbow" },
        }) }

    add{ name = "Simscout", class = "HUNTER", online = true,
        guid = "0xF530000000000021", subgroup = 4,
        aurasRead = true, auras = cleanAuras(),
        weaponMain = true, gearRead = true,
        gear = gearWith({
            [18] = { id = 5427, enchant = 33, subType = "Guns",
                     name = "Simulated Scattergun" },
        }) }

    -- Simveil: the 3rd offline case (with Simblade/Simzap: 3 offline + 2
    -- read-failed = 5 of 40 unreadable). Deliberately in subgroup 8 with
    -- the other 4 unreadable players -- a raid subgroup that is entirely
    -- unreadable, the stress case from the header.
    add{ name = "Simveil", class = "HUNTER", online = false,
        guid = "0xF530000000000022", subgroup = 8,
        aurasRead = false, gearRead = false,
        unreadableReason = "offline" }

    add{ name = "Simember", class = "MAGE", online = true,
        guid = "0xF530000000000023", subgroup = 5,
        aurasRead = true, auras = cleanAuras(),
        weaponMain = true, gearRead = true, gear = gearWith() }

    add{ name = "Simdread", class = "WARLOCK", online = true,
        guid = "0xF530000000000024", subgroup = 5,
        aurasRead = true, auras = cleanAuras(),
        weaponMain = true, gearRead = true, gear = gearWith() }

    add{ name = "Simvoid", class = "PRIEST", online = true,
        guid = "0xF530000000000025", subgroup = 6,
        aurasRead = true, auras = cleanAuras(),
        weaponMain = true, gearRead = true, gear = gearWith() }

    -- Simthornweaver: moonkin druid and one of the two long-name
    -- column-width showcases (14 characters).
    add{ name = "Simthornweaver", class = "DRUID", online = true,
        guid = "0xF530000000000026", subgroup = 6,
        aurasRead = true, auras = cleanAuras(),
        weaponMain = true, gearRead = true, gear = gearWith() }

    -- Simshadowmender: resto shaman and the other long-name showcase
    -- (15 characters, the longest name in the roster).
    add{ name = "Simshadowmender", class = "SHAMAN", online = true,
        guid = "0xF530000000000027", subgroup = 7,
        aurasRead = true, auras = cleanAuras(),
        weaponMain = true, gearRead = true, gear = gearWith() }

    add{ name = "Simbloom", class = "DRUID", online = true,
        guid = "0xF530000000000028", subgroup = 7,
        aurasRead = true, auras = cleanAuras(),
        weaponMain = true, gearRead = true, gear = gearWith() }

    -- Icon coverage pass: give every readable player
    -- a textures table covering all of their HAS-producing buff names --
    -- derived programmatically from names + ids, so both model match paths
    -- deliver an icon. Deterministic (pure function of the literals above).
    -- Debuff pass: every READABLE player without a debuff
    -- literal gets the EMPTY debuffs shape -- zero debuffs is a legitimate
    -- clean state (HAS cells), only the 5 unreadable players stay nil
    -- (UNKNOWN cells).
    -- Resist filler pass: every readable player who did NOT get an
    -- explicit resists literal above (the 3 tanks + Simhuntara + Simmage)
    -- gets small, deterministic, per-school-varied values -- a pure
    -- function of the player's roster index so re-builds stay
    -- byte-identical. Small mod bases (7/8/9/10/11) guarantee zeros show
    -- up repeatedly across the roster (a legitimate 0 resistance, not a
    -- read failure -- resistsRead is what carries that distinction). The 5
    -- unreadable players (Simblade/Simzap/Simveil offline, Simtrue/
    -- Simlight read failed) never get resistsRead/resists at all --
    -- UNKNOWN cells.
    for i = 1, table.getn(players) do
        local p = players[i]
        if p.auras then
            p.auras.textures = texturesFor(p.auras)
        end
        if p.aurasRead and p.debuffs == nil then
            p.debuffs = { names = {}, ids = {}, textures = {} }
        end
        if p.online ~= false and p.aurasRead and p.resistsRead == nil then
            p.resistsRead = true
            p.resists = {
                [2] = math.mod(i * 3, 7),
                [3] = math.mod(i * 3 + 2, 8),
                [4] = math.mod(i * 3 + 4, 9),
                [5] = math.mod(i * 3 + 6, 10),
                [6] = math.mod(i * 3 + 8, 11),
            }
        end
        -- Hit filler pass: every readable player WITHOUT an explicit hit
        -- literal above gets a deterministic set (pure function of the
        -- roster index, so re-builds stay byte-identical). Small mod
        -- bases put a few players on the melee cap (8) and leave everyone
        -- below the spell cap (17) -- the players AT the spell cap are
        -- the explicit ones. The ranged subtype comes from the player's
        -- own equipped ranged item, so a wand user stays NOTEXP and a
        -- thrown-weapon user gets a real ranged column. The 5 unreadable
        -- players keep no hit table at all -> UNKNOWN cells.
        if p.online ~= false and p.aurasRead and p.hit == nil then
            local rangedSub = nil
            local rangedItem = p.gear and p.gear[18]
            if type(rangedItem) == "table" then
                rangedSub = rangedItem.subType
            end
            p.hit = {
                melee = math.mod(i * 2, 9),
                spell = math.mod(i * 3, 12),
                schools = {},
                hitRead = true,
                mainSub = HIT_MAIN_SUB[p.class],
                rangedSub = rangedSub,
                -- the live starting state for everyone but the own
                -- character: no inspect reply has arrived yet
                -- (scan/talents.lua), so the numbers above are gear-only
                -- and every tooltip on these rows says so

                talentsRead = false,
            }
            -- no race token: the estimate then lands on the plain base
            -- skill, which is exactly what an unknown/new race token does
            -- in the live path too
        end
    end

    return { scanAt = now, source = "sim", players = players }
end
