if WDI_DOPING_SKIP then return end -- DopingControl data/talenthit.lua
-- The THIRD source of hit, next to gear and auras: TALENTS.
--
-- WHY ITS OWN FILE: gear hit is parsed from item tooltips, talent hit is
-- looked up by talent NAME and rank. The two arrive over completely
-- different paths -- GetTalentInfo for the own character, the server's
-- inspect protocol (scan/talents.lua) for everyone else -- and only meet
-- again in DC_Hit.TalentHit. Keeping the talent tables apart from
-- data/hit.lua keeps that split visible in the file layout instead of
-- hiding it inside one big table.
--
-- WHAT COUNTS AS SPELL HIT HERE: several talents are worded as "reduces
-- the chance that the opponent can resist your <school> spells by X%".
-- That is not a resistance mechanic -- it runs through the server's
-- resist-miss spell modifier, i.e. it IS spell hit for that school, and it
-- stacks with +hit from items. They are therefore modelled as
-- school-specific spell hit and not as anything resistance-shaped.
--
-- BUCKETS -- an entry is
--   { name    = <talent name, EXACTLY as GetTalentInfo returns it>,
--     tree    = <talent tab name; documentation only, never matched on>,
--     ranks   = <max rank; the per-rank arrays must have this length>,
--     melee   = { <per rank> },   -- generic physical hit (melee column)
--     ranged  = { <per rank> },   -- generic ranged hit (ranged column)
--     spell   = { <per rank> },   -- GENERIC spell hit: every school
--     offhand = { <per rank> },   -- OFF-HAND swings only, see below
--     dwExtra = { <per rank> },   -- extra melee hit while DUAL WIELDING
--     schools = { [<lowercase school id>] = { <per rank> } } }
-- Every bucket is optional; an absent bucket contributes nothing. School
-- ids are lowercase to match DC.SLOTS_HIT (core/const.lua); the
-- CAPITALIZED tooltip spelling that gear parsing produces is bridged by
-- DC.HIT_SCHOOL_KEY (data/hit.lua).
--
-- `offhand` is deliberately NOT part of the melee number. Off-hand hit
-- applies to off-hand swings only, so adding it to the melee column would
-- claim a main-hand hit chance the player does not have. It is carried so
-- the cell tooltip can mention it.
--
-- MATCHING IS BY NAME: the reader (DC_Hit.ReadSelfTalents) hands in
-- { [talent name] = rank }, because GetTalentInfo returns names, and
-- tab/index positions shift whenever a tree is rebalanced while names
-- almost never do. A talent this file does not list is ignored; a talent
-- listed here that no longer exists simply never matches. Both directions
-- degrade to "no talent hit counted", never to a wrong number.
--
-- English client assumed, like the tooltip patterns in data/hit.lua: on a
-- localized client no name matches and the talent contribution reads 0.
--
-- WHAT IS DELIBERATELY EXCLUDED (each one grants "hit" in its tooltip text
-- but not hit that belongs in any column of this tab):
--   * PET hit -- hunter "Bestial Precision", warlock "Demonic Precision".
--     They raise the PET's hit chance (and its weapon skill / inherited
--     ratios); the player's own swings and casts are untouched.
--   * ENEMY DEBUFFS -- rogue "Blinding Haze" LOWERS the hit chance of
--     targets hit by Distract. It is the opposite sign and lands on
--     someone else.
--   * SINGLE-SPELL hit -- paladin "Improved Hand of Reckoning" buys hit
--     for one ability only. A column that claimed it would overstate holy
--     hit for every other spell the paladin casts.
--   * WEAPON-TYPE hit -- mage "Wand Specialization" (wands) and priest
--     "Wand Specialization" (wands and bows). Wand and bow attacks are
--     neither generic spell hit nor -- for the priest -- the generic
--     ranged-attack hit this tab's ranged column measures (that column
--     only exists for a real ranged ATTACK weapon, see
--     DC.RANGED_ATTACK_SUBTYPE), so counting them would misplace them.
--   * TEMPORARY procs -- e.g. the second half of the shaman's Elemental
--     Devastation, which grants spell hit for 10 sec after a melee crit.
--     Only the permanent, always-on half is counted; a scan is a snapshot
--     and a proc that happens to be up would make one row incomparable
--     with the next.
--
-- Pure Lua 5.0, no WoW API -- dofile-loadable offline.

DopingControl = DopingControl or {}
local DC = DopingControl

-- ------------------------------------------------------------------
-- DC.TALENT_HIT -- [class token (UnitClass file token, e.g. "MAGE")] =
-- array of talent entries. Classes with no hit talent at all are absent.
-- ------------------------------------------------------------------
DC.TALENT_HIT = {

    -- Generic hit: melee AND every spell school, from ONE talent. The
    -- three entries below are the only talents in the game that raise
    -- both halves at once, which is why hybrids can be capped on both
    -- sides without spending a single item budget on it.
    DRUID = {
        { name = "Natural Weapons", tree = "Balance", ranks = 3,
          melee = { 1, 2, 3 }, spell = { 1, 2, 3 } },
    },

    PALADIN = {
        { name = "Precision", tree = "Protection", ranks = 3,
          melee = { 1, 2, 3 }, spell = { 1, 2, 3 } },
    },

    SHAMAN = {
        -- the talent's second half (melee crits grant 3/6/9% spell hit
        -- for 10 sec) is a TEMPORARY proc and is not counted -- see the
        -- exclusion list in the header
        { name = "Elemental Devastation", tree = "Elemental", ranks = 3,
          melee = { 1, 2, 3 }, spell = { 1, 2, 3 } },
    },

    -- Melee only.
    ROGUE = {
        -- "with melee weapons": no ranged half, even though rogues can
        -- carry a thrown weapon
        { name = "Precision", tree = "Combat", ranks = 5,
          melee = { 1, 2, 3, 4, 5 } },
    },

    HUNTER = {
        -- the talent says "hit chance" without naming a weapon, so the
        -- base half feeds the melee AND the ranged column.
        --
        -- dwExtra is the "and by an additional X% while dual wielding"
        -- half. The wording does not say which swings the EXTRA applies
        -- to; a dual-wield condition is a melee-build condition, so it is
        -- counted for MELEE ONLY. That is the reading that cannot
        -- overstate a hunter's ranged hit -- the number that decides
        -- whether the player is capped where it matters. Should the extra
        -- turn out to be generic, this under-reports ranged by up to 3%,
        -- which is the safe direction (same trade-off as the uncounted
        -- set bonuses in scan/hit.lua).
        { name = "Surefooted", tree = "Survival", ranks = 3,
          melee = { 1, 2, 3 }, ranged = { 1, 2, 3 },
          dwExtra = { 1, 2, 3 } },
    },

    -- Off-hand only.
    WARRIOR = {
        -- off-hand swings only: NOT added to the melee column, carried
        -- for the tooltip (see the `offhand` note in the header)
        { name = "Dual Wield Specialization", tree = "Fury", ranks = 5,
          offhand = { 2, 4, 6, 8, 10 } },
    },

    -- School-specific spell hit.
    MAGE = {
        { name = "Arcane Focus", tree = "Arcane", ranks = 5,
          schools = { arcane = { 2, 4, 6, 8, 10 } } },
        -- one talent, two schools, full value in each: it is not split
        { name = "Elemental Precision", tree = "Frost", ranks = 3,
          schools = { frost = { 2, 4, 6 }, fire = { 2, 4, 6 } } },
    },

    PRIEST = {
        { name = "Shadow Focus", tree = "Shadow", ranks = 5,
          schools = { shadow = { 2, 4, 6, 8, 10 } } },
        -- "your Holy and Discipline spells": Discipline is a SPELL LINE,
        -- not a magic school -- its damaging spells are holy school
        -- anyway, so the whole talent maps onto holy. There is no
        -- "discipline" column to put the other half in, and inventing one
        -- would be a school this client's damage model does not have.
        { name = "Piercing Light", tree = "Discipline", ranks = 3,
          schools = { holy = { 2, 4, 6 } } },
    },

    WARLOCK = {
        -- "your Affliction spells": another SPELL-LINE talent rather than
        -- a school talent. Affliction spells (Corruption, Curse of Agony,
        -- Drain Life, Siphon Life, Death Coil, ...) are shadow school, so
        -- the talent is mapped onto shadow. A warlock's fire spells
        -- (Immolate, Shadowburn's destruction siblings) get nothing from
        -- it, which is exactly why the fire and shadow columns of this tab
        -- can differ by 10% for the same character.
        { name = "Suppression", tree = "Affliction", ranks = 5,
          schools = { shadow = { 2, 4, 6, 8, 10 } } },
    },
}
