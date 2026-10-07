if WDI_DOPING_SKIP then return end -- DopingControl data/classbuffs.lua
-- Class-buffs tab:
-- slot definitions + buff name -> slot table with rank spell IDs.
--
-- [ASSUMPTION] Rank IDs below are from vanilla 1.12 knowledge and are
-- not individually verified in-game. Verify via
-- the probe dump before trusting ID matching; TWoW may add extra ranks.
-- Name-based detection alone is sufficient for tab purposes EXCEPT the
-- "Shadow Protection" name collision: the priest buff and the old
-- protection-potion aura (7242) share the name -> ID-before-name matching
-- is mandatory once both tabs are live.
-- Pure Lua 5.0, no WoW API -- dofile-loadable offline.

DopingControl = DopingControl or {}
local DC = DopingControl

-- ------------------------------------------------------------------
-- Slot definitions (array, order = column order). Same field shape as
-- DC.SLOTS_CONSUMABLES. Slot ids: AI/MOTW/PWF/SPROT/EMB/SOUL;
-- tile labels/sub-labels: INT/MTW/FRT/SP/EMB/SST. EMB (Emerald Blessing)
-- carries NO seed entry in data/expectations.lua -- see that file's
-- header for why -- so it starts as an inactive dynamic column, exactly
-- like the equipment tab's T1/T2.
-- ------------------------------------------------------------------
DC.SLOTS_CLASSBUFFS = {
    { id = "AI",    label = "INT", sub = "Arcane",  full = "Arcane Intellect",      kind = "aura",
      items = "Arcane Intellect / Brilliance (mage)" },
    { id = "MOTW",  label = "MTW", sub = "Wild",    full = "Mark of the Wild",      kind = "aura",
      items = "Mark / Gift of the Wild (druid)" },
    { id = "PWF",   label = "FRT", sub = "Priest",  full = "Power Word: Fortitude", kind = "aura",
      items = "Power Word / Prayer of Fortitude (priest)" },
    { id = "SPROT", label = "SP",  sub = "situat.", full = "Shadow Protection",     kind = "aura",
      items = "Shadow Protection (priest) - situational per boss" },
    { id = "EMB",   label = "EMB", sub = "hit",     full = "Emerald Blessing",      kind = "aura",
      items = "Emerald Blessing (druid, Emerald Sanctum questline) - also grants +1% spell hit, see Resistances" },
    { id = "SOUL",  label = "SST", sub = "healers", full = "Soulstone",             kind = "aura",
      items = "Soulstone (warlock) - expected only for healers" },
}

-- ------------------------------------------------------------------
-- Buff name -> slot + rank IDs ([ASSUMPTION], see header).
-- ------------------------------------------------------------------
DC.CLASSBUFFS = {
    ["Arcane Intellect"]            = { slot = "AI",    ids = { 1459, 1460, 1461, 10156, 10157 } },
    ["Arcane Brilliance"]           = { slot = "AI",    ids = { 23028 } },
    ["Mark of the Wild"]            = { slot = "MOTW",  ids = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 } },
    ["Gift of the Wild"]            = { slot = "MOTW",  ids = { 21849, 21850 } },
    ["Power Word: Fortitude"]       = { slot = "PWF",   ids = { 1243, 1244, 1245, 2791, 10937, 10938 } },
    ["Prayer of Fortitude"]         = { slot = "PWF",   ids = { 21562, 21564 } },
    ["Shadow Protection"]           = { slot = "SPROT", ids = { 976, 10957, 10958 } },  -- name collides with potion aura 7242
    ["Prayer of Shadow Protection"] = { slot = "SPROT", ids = { 27683 } },
    -- raid-wide druid buff on this server; both spell ids seen for it
    ["Emerald Blessing"]            = { slot = "EMB",   ids = { 57108, 57109 } },
    ["Soulstone Resurrection"]      = { slot = "SOUL",  ids = { 20707, 20762, 20763, 20764, 20765, 20766 } },
}

-- ------------------------------------------------------------------
-- Merge rank IDs into the global spellID -> slotId map started by
-- data/consumables.lua (slot ids are unique across tabs -> no ambiguity;
-- the ID sets are disjoint, test_data.lua asserts this).
-- ------------------------------------------------------------------
DC.SPELL_TO_SLOT = DC.SPELL_TO_SLOT or {}
for name, def in pairs(DC.CLASSBUFFS) do
    local n = table.getn(def.ids)
    for i = 1, n do
        DC.SPELL_TO_SLOT[def.ids[i]] = def.slot
    end
end

-- ------------------------------------------------------------------
-- Name-only aura collisions with CONSUMABLE slots (decision 2026-08-15):
-- a name-only aura match (no spell ID at all for that scan) must NEVER
-- satisfy a CONSUMABLE slot when the matched display name is also a class
-- buff name -- the scan cannot tell the two apart, and defaulting to HAS
-- would hide a missing consumable behind someone else's class buff. Such
-- a slot classifies UNKNOWN instead (core/model.lua's aura name-fallback
-- branch consults this table; core/const.lua's Iron Rule: UNKNOWN is
-- never collapsed into HAS or MISSING).
--
-- Scope is deliberately ONE-SIDED: only the CONSUMABLE slot side of the
-- collision is affected. The class-buff slot (e.g. SPROT) keeps the
-- existing name-fallback behavior unchanged -- the ambiguity here means
-- "we can't prove the CONSUMABLE was used", not "we can't prove the class
-- buff is missing". Do not widen this into "name-only never counts"; that
-- would make every ID-less scan MISSING/UNKNOWN across the whole matrix.
--
-- Keyed by buff display name (a key shared by DC.CONSUMABLES and
-- DC.CLASSBUFFS). test_data.lua asserts every entry here is a key in BOTH
-- tables, so a stale or speculative entry cannot ship silently.
--   "Shadow Protection" -- DC.CONSUMABLES["Shadow Protection"] (SR slot,
--   Shadow Protection Potion, spell 7242, data/consumables.lua) vs.
--   DC.CLASSBUFFS["Shadow Protection"] above (SPROT slot, priest buff,
--   ids 976/10957/10958) -- identical display name, already flagged as a
--   collision at both definitions and wowhead-confirmed 2026-08-11 (see
--   the SR entry's comment in data/consumables.lua). This is the ONLY
--   name shared between DC.CONSUMABLES and DC.CLASSBUFFS (checked against
--   every key in both tables) -- no other entry is added without the same
--   level of evidence.
-- ------------------------------------------------------------------
DC.CONSUMABLE_CLASSBUFF_NAME_COLLISION = {
    ["Shadow Protection"] = true,
}
