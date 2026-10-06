if WDI_DOPING_SKIP then return end -- DopingControl data/expectations.lua
-- Default expectation matrix DC.DEFAULT_EXPECT[role][slotId] = true.
-- One flat slot-id namespace across all three tabs (ids are unique).
--
-- This table STAYS the role x slot
-- SEED. The saved/live shape is per class --
-- db.expectations[role][class][slotId] -- materialized from these lines
-- by core/config.lua (DC.EnsureExpectations) for every class that can
-- perform the role (DC_Roles.ROLE_CLASSES). Class-differentiated
-- DEFAULTS are deliberately NOT shipped; the one
-- motivating example lives here as a comment only:
--     a TANK-confirmed SHAMAN wants AI = true (Arcane Intellect for the
--     mana-fed tank kit) while a TANK WARRIOR does not -- the user flips
--     expectations.TANK.SHAMAN.AI in the options grid. AI stays
--     a CASTER/HEALER role default for every performing class.
--
-- Role-line choices:
--   Consumables: the four role sets of the KG stacking-rules atom
--                (data-tables/consumable-stacking-rules, TurtleWoW
--                1.17.2 -- melee / caster / tank / healer, each "all
--                active simultaneously") ARE the defaults now; see the
--                spec 2026-08-11-slot-model-item-icons-design.md. RANGED
--                has no KG set of its own and is derived from the melee
--                line (no STR -- ranged AP scales off AGI -- and no
--                FLASK). FR stays situational for all five roles
--                (enable/disable per boss via the expectation matrix),
--                WPN as before. The other school protection slots
--                (FrR/NR/SR/HR/AR, added 2026-08-11) carry NO seed entry
--                at all: default off for every role, so the dynamic-
--                column rule hides them until someone enables them per
--                role/class for a matching boss (same treatment as EMB
--                and T1/T2 below) -- unlike FR, which ships seeded true.
--   Class buffs: SOUL only HEALER, AI only CASTER/HEALER, SPROT situational
--                for all five -- like FR. EMB (Emerald Blessing) has NO
--                seed entry: the buff comes from a raid questline and most
--                druids do not have it. The column therefore stays hidden
--                until someone enables it per role/class in the options
--                grid; the dynamic-column rule makes an unexpected slot
--                disappear entirely (same treatment as T1/T2 below).
--   Equipment:   ALL armor enchant slots for ALL roles, WAIST included
--                (owner decision, 2026-08-30: every role wears a belt,
--                and it is enchantable on this server via the Belt
--                Buckle item line -- so it is worn equipment like any
--                other slot, not an optional extra like neck/rings);
--                per-item exemptions (wand/holdable) are handled at
--                classify time via DC.ENCH_EXEMPT, not here.
--                NECK/R1/R2 (also enchantable on this server, a custom
--                feature beyond vanilla) stay OFF by default for every
--                role: unlike WAIST, a neck/ring enchant is not assumed
--                baseline raid gear -- enable it per role/class in the
--                options grid when it matters. T1/T2 (trinket item tiles)
--                carry NO seed entry at all -- the model ignores
--                expectations for tile-kind slots entirely (item
--                present/absent decides, always shown, never gated).
--
-- Known debatable rows -- documented deliberately, the shipped defaults
-- win:
--   * TANK+AP / MELEE+FLASK: the OLD defaults deliberately excluded them;
--                   the KG role sets include them (tank runs Winterfall
--                   Firewater, melee runs Flask of the Titans), so both
--                   flipped to true with the v6 slot model.
--   * RANGED line:  derived, not KG-covered (see above) -- BL is included
--                   (Ground Scorpok Assay is +25 AGI), STR/FLASK are not.
--   * HEALER+HPELX: the KG healer set carries no Elixir of Fortitude, so
--                   HPELX defaults off for HEALER while ALC (Kreeg's
--                   Stout Beatdown + Medivh's Merlot Blue) is on.
--   * ZANZA:        expected for every role (all four KG sets carry it).
--   * Equipment:    an alternative default would differentiate per role
--                   (OFFH only TANK/MELEE, RNGD only RANGED,
--                   casters/healers neither); deliberately flattened to
--                   all-roles + ENCH_EXEMPT item checks.
--
-- This table is the pristine seed: core/config.lua materializes it into
-- db.expectations (per class, deep copies) on first load; the options
-- editor mutates only the materialized copies, never this table.
-- Pure Lua 5.0, no WoW API -- dofile-loadable offline.

DopingControl = DopingControl or {}
local DC = DopingControl

DC.DEFAULT_EXPECT = {
    TANK = {
        -- consumables (KG tank set: Mongoose, Firewater, Juju Power,
        -- R.O.I.D.S., Zanza, Superior Defense, Fortitude, Titans, food,
        -- Merlot + Rumsey, sharpening stone; Gift of Arthas has no column)
        FLASK = true, FOOD = true, AP = true, STR = true, AGI = true,
        BL = true, ZANZA = true, ARM = true, HPELX = true, ALC = true,
        FR = true, WPN = true,
        -- class buffs
        MOTW = true, PWF = true, SPROT = true,
        -- equipment (RNGD default only for RANGED:
        -- scopes only matter for hunters; flip in the options
        -- expectation matrix anytime)
        HEAD = true, SHLD = true, BACK = true, CHST = true, WRST = true,
        HAND = true, LEGS = true, FEET = true, MAIN = true, OFFH = true,
        WAIST = true,
    },
    MELEE = {
        -- consumables (KG melee set: Mongoose, Firewater/Juju Might,
        -- Juju Power/Giants, R.O.I.D.S./Scorpok, Zanza, Titans, food,
        -- sharpening stone; Juju Flurry has no column)
        FLASK = true, FOOD = true, AP = true, STR = true, AGI = true,
        BL = true, ZANZA = true,
        FR = true, WPN = true,
        -- class buffs
        MOTW = true, PWF = true, SPROT = true,
        -- equipment
        HEAD = true, SHLD = true, BACK = true, CHST = true, WRST = true,
        HAND = true, LEGS = true, FEET = true, MAIN = true, OFFH = true,
        WAIST = true,
    },
    RANGED = {
        -- consumables (derived from the melee line -- no KG set; no STR,
        -- no FLASK, see "Known debatable rows")
        FOOD = true, AP = true, AGI = true, BL = true, ZANZA = true,
        FR = true, WPN = true,
        -- class buffs
        MOTW = true, PWF = true, SPROT = true,
        -- equipment
        HEAD = true, SHLD = true, BACK = true, CHST = true, WRST = true,
        HAND = true, LEGS = true, FEET = true, MAIN = true, OFFH = true,
        WAIST = true,
        RNGD = true,
    },
    -- CASTER/HEALER: RNGD also dropped by role default (their classes are
    -- additionally exempt via ENCH_CLASS_EXEMPT - belt and suspenders)
    CASTER = {
        -- consumables (KG caster set: Dreamshard, GAE, school elixir,
        -- Dreamtonic, Mageblood, wizard oil, Zanza, Supreme Power, food)
        FLASK = true, FOOD = true, GAE = true, SCHOOL = true,
        DREAMT = true, SHARD = true, MP5 = true, ZANZA = true,
        FR = true, WPN = true,
        -- class buffs
        AI = true, MOTW = true, PWF = true, SPROT = true,
        -- equipment
        HEAD = true, SHLD = true, BACK = true, CHST = true, WRST = true,
        HAND = true, LEGS = true, FEET = true, MAIN = true, OFFH = true,
        WAIST = true,
    },
    HEALER = {
        -- consumables (KG healer set: Dreamshard, Mageblood, mana oil,
        -- Zanza, Distilled Wisdom, food, Kreeg's + Merlot Blue)
        FLASK = true, FOOD = true, MP5 = true, SHARD = true, ZANZA = true,
        ALC = true,
        FR = true, WPN = true,
        -- class buffs (SOUL: expected ONLY here)
        AI = true, MOTW = true, PWF = true, SPROT = true, SOUL = true,
        -- equipment
        HEAD = true, SHLD = true, BACK = true, CHST = true, WRST = true,
        HAND = true, LEGS = true, FEET = true, MAIN = true, OFFH = true,
        WAIST = true,
    },
}
