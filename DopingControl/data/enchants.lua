if WDI_DOPING_SKIP then return end -- DopingControl data/enchants.lua
-- Equipment tab: 15 enchant slots + 2 item-tile slots (both trinkets), in
-- paperdoll order, with 1.12 inventory slot IDs.
-- Enchant columns are checked present/missing only (enchant ID in the item
-- link ~= 0); an EMPTY enchant slot is always a gap (core/model.lua), so it
-- is never gated by the expectation checkbox -- only the "has an enchant"
-- question is. Item-tile slots (trinkets) show the equipped item and
-- ignore expectations entirely; only an EMPTY slot counts as a gap there.
--
-- Server note: neck, both rings AND the waist ARE enchantable on this
-- server (a server-custom feature beyond vanilla WoW, where none of them
-- take an enchant) -- NECK/R1/R2/WAIST are therefore kind="ench" like any
-- armor slot, not item tiles. The waist enchant is a "Belt Buckle" item
-- (Copper/Bronze/Thorium/Dreamsteel/Bloody Belt Buckle),
-- the same custom itemization line as the neck/ring gems. Their
-- expectation defaults to OFF (data/expectations.lua): unlike the ARMOR
-- enchant slots, a neck/ring/waist enchant is not assumed baseline raid
-- gear, so the columns only track it once a role/class opts in via the
-- options grid.
--
-- Bug history (2026-08-30): the waist (invSlot 6) was missing from this
-- table entirely -- not a deliberate exclusion, an oversight that predates
-- the Belt Buckle KG lookup above. Because scan/gear.lua's G.InvSlots()
-- derives the full GetInventoryItemLink read list from THIS table, the
-- omission silently dropped the waist from every equipment read: no raid
-- dump ever carried a ";6=" entry, and the HIT tab under-counted any
-- +hit/+resist on a belt (scan/hit.lua's H.SLOTS already listed 6 and
-- expected scan/gear.lua's rawLinks to cover it -- see that file's
-- ReadUnit comment). Adding WAIST here fixes both at the source.
-- Pure Lua 5.0, no WoW API -- dofile-loadable offline.

DopingControl = DopingControl or {}
local DC = DopingControl

-- ------------------------------------------------------------------
-- Slot definitions (array, order = column order). Same field shape as the
-- other tabs plus invSlot (GetInventoryItemLink slot number). Ids
-- HEAD/SHLD/... with tile labels HEA/SHO/...
-- ------------------------------------------------------------------
DC.SLOTS_EQUIPMENT = {
    { id = "HEAD", label = "HEA", sub = "slot 1",  full = "Head",       kind = "ench",    invSlot = 1 },
    { id = "NECK", label = "NCK", sub = "slot 2",  full = "Neck",       kind = "ench",    invSlot = 2 },  -- enchantable on this server (custom, unlike vanilla)
    { id = "SHLD", label = "SHO", sub = "slot 3",  full = "Shoulders",  kind = "ench",    invSlot = 3 },
    { id = "BACK", label = "BCK", sub = "slot 15", full = "Back",       kind = "ench",    invSlot = 15 },
    { id = "CHST", label = "CHE", sub = "slot 5",  full = "Chest",      kind = "ench",    invSlot = 5 },
    { id = "WAIST", label = "WAI", sub = "slot 6", full = "Waist",      kind = "ench",    invSlot = 6 },  -- enchantable on this server (custom Belt Buckle line, unlike vanilla)
    { id = "WRST", label = "WRI", sub = "slot 9",  full = "Wrist",      kind = "ench",    invSlot = 9 },
    { id = "HAND", label = "HND", sub = "slot 10", full = "Hands",      kind = "ench",    invSlot = 10 },
    { id = "LEGS", label = "LEG", sub = "slot 7",  full = "Legs",       kind = "ench",    invSlot = 7 },
    { id = "FEET", label = "FEE", sub = "slot 8",  full = "Feet",       kind = "ench",    invSlot = 8 },
    { id = "MAIN", label = "MH",  sub = "slot 16", full = "Main hand",  kind = "ench",    invSlot = 16 },
    { id = "OFFH", label = "OH",  sub = "slot 17", full = "Off hand",   kind = "ench",    invSlot = 17 },
    { id = "RNGD", label = "RNG", sub = "slot 18", full = "Ranged (scope)", kind = "ench", invSlot = 18 },  -- scope counts as the enchant
    { id = "R1",   label = "R1",  sub = "slot 11", full = "Ring 1",     kind = "ench",    invSlot = 11 },  -- enchantable on this server (custom, unlike vanilla)
    { id = "R2",   label = "R2",  sub = "slot 12", full = "Ring 2",     kind = "ench",    invSlot = 12 },  -- enchantable on this server (custom, unlike vanilla)
    { id = "T1",   label = "T1",  sub = "slot 13", full = "Trinket 1",  kind = "trinket", invSlot = 13 },
    { id = "T2",   label = "T2",  sub = "slot 14", full = "Trinket 2",  kind = "trinket", invSlot = 14 },
}

-- ------------------------------------------------------------------
-- Item-subtype exemptions: whether an enchant applies at all is a
-- property of the equipped ITEM, not of the role. If the equipped item's
-- itemSubType (GetItemInfo return 6 on TWoW 1.18.1)
-- is listed for the slot, the cell classifies as NOTEXP instead
-- of MISSING.
--
-- Shape: DC.ENCH_EXEMPT[slotId][itemSubType] = true
--
-- [ASSUMPTION] English-client subtype strings: wands = "Wands", off-hand
-- frills/holdables = "Miscellaneous", thrown = "Thrown" (thrown weapons
-- cannot take a scope -- same item-property principle as wands; "Thrown"
-- is a deliberate extension --
-- kept because dropping it would show thrown users a
-- false MISSING scope). All three strings are on the probe checklist:
-- the /dc probe battery dumps GetItemInfo subType (return 6) for every
-- equipped slot ("Q5b" lines, core/probe.lua) -- a mismatch means the
-- exemption silently never fires and must be corrected here.
-- ------------------------------------------------------------------
DC.ENCH_EXEMPT = {
    RNGD = { ["Wands"] = true, ["Thrown"] = true },  -- Wands: no scope; Thrown: no scope [ASSUMPTION]
    OFFH = { ["Miscellaneous"] = true },             -- held-in-off-hand frills: not enchantable
}

-- ------------------------------------------------------------------
-- Class-based enchant exemptions:
-- whole CLASSES for which an ench slot never applies,
-- regardless of what (if anything) is equipped. DC_Model.classify checks
-- this FIRST, before gearRead/EMPTY/expectation logic, and returns
-- NOTEXP (detail "no ranged enchant for this class").
--
-- Shape: DC.ENCH_CLASS_EXEMPT[slotId][classToken] = true
--        (classToken = english GetRaidRosterInfo return-6 token)
--
-- RNGD: shamans/druids/priests/mages/warlocks carry wands/totems/idols/
-- relics or nothing there -- no scope ever applies.
-- PALADIN added: vanilla paladins have a permanently EMPTY ranged
-- slot (no ranged/relic item exists for them on 1.12), so a scope can
-- never apply either.
-- ------------------------------------------------------------------
DC.ENCH_CLASS_EXEMPT = {
    RNGD = {
        SHAMAN  = true,
        DRUID   = true,
        PRIEST  = true,
        MAGE    = true,
        WARLOCK = true,
        PALADIN = true,  -- permanently empty ranged slot in vanilla
    },
}
