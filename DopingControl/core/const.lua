if WDI_DOPING_SKIP then return end -- DopingControl core/const.lua
-- Shared constants: roles, states, tabs, color palette, quality colors.
-- Pure Lua 5.0, no WoW API -- dofile-loadable offline.

DopingControl = DopingControl or {}
local DC = DopingControl

-- ------------------------------------------------------------------
-- Roles (array order = display order) and labels
-- ------------------------------------------------------------------
DC.ROLES = { "TANK", "MELEE", "RANGED", "CASTER", "HEALER" }

DC.ROLE_LABEL = {
    TANK   = "Tanks",
    MELEE  = "Melee",
    RANGED = "Ranged",
    CASTER = "Casters",
    HEALER = "Healers",
}

-- ------------------------------------------------------------------
-- Cell/data states. Hard rule: UNKNOWN is NEVER condensed to MISSING --
-- an unreadable player is "no data", not "has nothing".
-- ------------------------------------------------------------------
DC.STATE = {
    HAS     = "HAS",
    MISSING = "MISSING",
    UNKNOWN = "UNKNOWN",
    NOTEXP  = "NOTEXP",
}

-- ------------------------------------------------------------------
-- Tabs (order = display order). DEBUFFS' columns are built DYNAMICALLY
-- from the store (no data/slot table); every other tab has a static slot
-- table. DEBUFFS, RESIST and HIT are pure DISPLAY tabs -- no expectations,
-- no gaps, no sums, no whisper (see the slot tables below and
-- core/model.lua's per-tab branches). HIT sits between RESIST and
-- EQUIPMENT because it answers the same "how is this player set up"
-- question as the resistances, only for the attack side.
-- ------------------------------------------------------------------
DC.TABS = { "CONSUMABLES", "CLASSBUFFS", "DEBUFFS", "RESIST", "HIT", "EQUIPMENT" }

DC.TAB_LABEL = {
    CONSUMABLES = "Consumables",
    CLASSBUFFS  = "Class buffs",
    DEBUFFS     = "Debuffs",
    RESIST      = "Resistances",
    HIT         = "Hit",
    EQUIPMENT   = "Equipment",
}

-- ------------------------------------------------------------------
-- RESIST tab slot table (static, unlike DEBUFFS' dynamic columns --
-- resistances are always the same five schools). All columns are ALWAYS
-- active; expectations are never consulted on this tab (display only, see
-- core/model.lua).
--
-- `school` is the UnitResistance() school index (0 = physical, 1 = holy --
-- both never queried here; 2..6 below).
-- ------------------------------------------------------------------
DC.SLOTS_RESIST = {
    { id = "RFIRE",  label = "FIR", sub = "fire",   full = "Fire resistance",   kind = "resist", school = 2 },
    { id = "RNAT",   label = "NAT", sub = "nature", full = "Nature resistance", kind = "resist", school = 3 },
    { id = "RFROST", label = "FRO", sub = "frost",  full = "Frost resistance",  kind = "resist", school = 4 },
    { id = "RSHAD",  label = "SHA", sub = "shadow", full = "Shadow resistance", kind = "resist", school = 5 },
    { id = "RARC",   label = "ARC", sub = "arcane", full = "Arcane resistance", kind = "resist", school = 6 },
}

-- ------------------------------------------------------------------
-- HIT tab slot table (static). Same display-only rules as RESIST: every
-- column is always active, expectations are never consulted, nothing is
-- ever MISSING and nothing is whispered -- a hit number below its cap is
-- information, not a gap to nag about.
--
-- The numbers behind these columns are read from item TOOLTIPS (per-item
-- lines plus set bonuses, counted once per set), from hit-granting AURAS,
-- and from TALENTS -- the own character's via GetTalentInfo, everyone
-- else's via this server's inspect protocol (scan/talents.lua). There is
-- no hit API on this client at all -- see data/hit.lua and
-- data/talenthit.lua. `hitKind` selects which number a column shows:
--   "melee"  -- generic physical hit vs the yellow (special attack) cap
--   "ranged" -- the same generic gear hit against the RANGED cap, and only
--               for a player who actually carries a ranged attack weapon
--   "spell"  -- spell hit vs the spell cap
--
-- WHY SIX SPELL COLUMNS INSTEAD OF ONE: spell hit is not one number. A
-- column's value is the GENERIC spell hit plus everything that only helps
-- THAT school -- school-specific item affixes and school-specific talents
-- (a mage's Arcane Focus, a priest's Shadow Focus, ...). Two casters of
-- the same class routinely differ per school, which is exactly what the
-- tab exists to show; folding them into one "spell hit" column would hide
-- the difference that decides whether a caster is capped.
--
-- `school` on a spell column is the LOWERCASE school id, shared with the
-- talent tables (data/talenthit.lua). Gear-parsed school extras are keyed
-- by the CAPITALIZED tooltip spelling instead ("Fire"), because they come
-- straight out of the tooltip text -- DC.HIT_SCHOOL_KEY (data/hit.lua)
-- bridges the two and DC_Hit.SchoolHit does the lookup for callers.
-- ------------------------------------------------------------------
DC.SLOTS_HIT = {
    { id = "MHIT", label = "MHT", sub = "melee",  full = "Melee hit",   kind = "hit", hitKind = "melee" },
    { id = "RHIT", label = "RNG", sub = "ranged", full = "Ranged hit",  kind = "hit", hitKind = "ranged" },
    { id = "HARC", label = "ARC", sub = "arcane", full = "Arcane hit",  kind = "hit", hitKind = "spell", school = "arcane" },
    { id = "HFIR", label = "FIR", sub = "fire",   full = "Fire hit",    kind = "hit", hitKind = "spell", school = "fire" },
    { id = "HFRO", label = "FRO", sub = "frost",  full = "Frost hit",   kind = "hit", hitKind = "spell", school = "frost" },
    { id = "HHOL", label = "HOL", sub = "holy",   full = "Holy hit",    kind = "hit", hitKind = "spell", school = "holy" },
    { id = "HNAT", label = "NAT", sub = "nature", full = "Nature hit",  kind = "hit", hitKind = "spell", school = "nature" },
    { id = "HSHA", label = "SHA", sub = "shadow", full = "Shadow hit",  kind = "hit", hitKind = "spell", school = "shadow" },
}

-- ------------------------------------------------------------------
-- Out-of-range threshold in yards:
-- a READABLE player with distance >= FAR_LIMIT gets rowVM.far = true and
-- counts into vm.coverage.far. Purely diagnostic -- far never changes any
-- cell state, sum, gap or pill (distance is never a filter).
-- ------------------------------------------------------------------
DC.FAR_LIMIT = 40

-- ------------------------------------------------------------------
-- Alternating-row wash ("zebra"): the alpha of DC.COLORS.zebra on every
-- SECOND data row of a table, so the eye can hold a line across a wide
-- grid. It has to stay well under the washes that carry MEANING -- the
-- unreadable-row wash sits at 0.25 -- or a striped row would read as a
-- state. One number, used by every table (matrix rows, both options
-- grids), so the whole tool stripes at the same strength.
-- ------------------------------------------------------------------
DC.ZEBRA_ALPHA = 0.035

-- ------------------------------------------------------------------
-- Color palette
-- Every entry is { r=<0..1>, g=<0..1>, b=<0..1> } (WoW SetTextColor /
-- SetVertexColor convention). Hex source noted per line.
-- ------------------------------------------------------------------
local function hexrgb(hex)
    return {
        r = tonumber(string.sub(hex, 1, 2), 16) / 255,
        g = tonumber(string.sub(hex, 3, 4), 16) / 255,
        b = tonumber(string.sub(hex, 5, 6), 16) / 255,
    }
end

DC.COLORS = {
    -- state colors (cell glyph / cell background / cell border)
    hat          = hexrgb("3fae5c"),  -- HAS green
    hatBg        = hexrgb("152b1c"),
    hatBorder    = hexrgb("2b5e3a"),
    fehlt        = hexrgb("d05252"),  -- MISSING red
    fehltBg      = hexrgb("341a1a"),
    fehltBorder  = hexrgb("6e3030"),
    unbek        = hexrgb("8b93a0"),  -- UNKNOWN gray
    unbekBg      = hexrgb("22262e"),
    unbekBorder  = hexrgb("3b424e"),
    skip         = hexrgb("14181f"),  -- not-expected cell bg
    skipBorder   = hexrgb("1d222b"),
    skipGlyph    = hexrgb("3a404c"),

    -- gold family
    gold         = hexrgb("8f7440"),  -- hover border gold
    goldHi       = hexrgb("e6c87e"),  -- title / highlight gold
    goldSoft     = hexrgb("54462a"),  -- frame accent borders
    goldDim      = hexrgb("a98f57"),  -- secondary gold, links

    -- panels / lines
    panel        = hexrgb("11141a"),  -- frame bg
    panel2       = hexrgb("171b23"),  -- popover bg
    panel3       = hexrgb("1d222c"),  -- reserved
    line         = hexrgb("262c37"),  -- standard borders
    theadBg      = hexrgb("141821"),  -- sticky head/foot bg
    void         = hexrgb("0a0c10"),  -- page background
    -- alternating-row wash ("zebra"): the COLOR is plain white, the
    -- subtlety lives entirely in DC.ZEBRA_ALPHA below -- a tinted stripe
    -- would shift the hue of every cell it sits under.
    zebra        = hexrgb("ffffff"),

    -- text
    ink          = hexrgb("c9cdd4"),  -- body text
    dim          = hexrgb("868d99"),  -- secondary text
    faint        = hexrgb("5b6270"),  -- tertiary / hints
    parch        = hexrgb("d6cdb8"),  -- parchment text
    parchDim     = hexrgb("9d9482"),  -- parchment dim (tooltip detail)

    -- role group colors
    roleTANK     = hexrgb("8fb3dd"),
    roleMELEE    = hexrgb("e2a75e"),
    roleRANGED   = hexrgb("7fcabe"),
    roleCASTER   = hexrgb("bd9ce8"),
    roleHEALER   = hexrgb("8fd6a0"),

    -- role badge border colors
    roleBorderTANK   = hexrgb("3c5877"),
    roleBorderMELEE  = hexrgb("7a5c33"),
    roleBorderRANGED = hexrgb("3a6b63"),
    roleBorderCASTER = hexrgb("5e4a80"),
    roleBorderHEALER = hexrgb("3c6c4a"),

    -- class colors: OWN table -- RAID_CLASS_COLORS does NOT exist on 1.12.
    -- Standard vanilla class colors, all 9 classes (the sim roster covers
    -- all of them).
    classWARRIOR = hexrgb("c79c6e"),
    classPALADIN = hexrgb("f58cba"),
    classHUNTER  = hexrgb("abd473"),
    classROGUE   = hexrgb("fff569"),
    classPRIEST  = hexrgb("ffffff"),
    classSHAMAN  = hexrgb("0070de"),
    classMAGE    = hexrgb("69ccf0"),
    classWARLOCK = hexrgb("9482c9"),
    classDRUID   = hexrgb("ff7d0a"),

    -- trinket tile quality accents (WoW rare/3 and epic/4)
    rareText     = hexrgb("4aa3ff"),
    rareBorder   = hexrgb("1d5a9e"),
    epicText     = hexrgb("b06cf0"),
    epicBorder   = hexrgb("6a3f8f"),

    -- green button / pill family + banners
    btnGreenText   = hexrgb("cfe0a8"),
    btnGreenBg     = hexrgb("26311e"),
    btnGreenBorder = hexrgb("4c6236"),
    bannerYellowBg     = hexrgb("2b2413"),
    bannerYellowBorder = hexrgb("6e5a26"),
    bannerYellowText   = hexrgb("e0c98a"),
    bannerGreenBg      = hexrgb("16240f"),
}

-- ------------------------------------------------------------------
-- Item quality colors, indices 0..6 as returned by GetItemQualityColor.
-- Own table so pure-Lua tests can run offline (GetItemQualityColor exists
-- in-game but not under lua50). Values = 1.12 FrameXML ITEM_QUALITY_COLORS.
-- ------------------------------------------------------------------
DC.QUALITY = {
    [0] = { r = 0.65, g = 0.65, b = 0.65 },  -- poor (gray)
    [1] = { r = 1.00, g = 1.00, b = 1.00 },  -- common (white)
    [2] = { r = 0.10, g = 1.00, b = 0.00 },  -- uncommon (green)
    [3] = { r = 0.00, g = 0.44, b = 0.87 },  -- rare (blue)
    [4] = { r = 0.64, g = 0.21, b = 0.93 },  -- epic (purple)
    [5] = { r = 1.00, g = 0.50, b = 0.00 },  -- legendary (orange)
    [6] = { r = 0.90, g = 0.80, b = 0.50 },  -- artifact
}
