if WDI_DOPING_SKIP then return end -- DopingControl core/model.lua
-- Pure view-model layer: classify cells, build the matrix view-model,
-- format whisper/report strings. NO WoW API, NO frames -- offline-testable
-- under real Lua 5.0.
--
-- Covers: cell states, ready pill, chat formats (whisper/report separators
-- are pure ASCII: "-" and "|", no middle dots).
--
-- Hard rules implemented here:
--   * UNKNOWN is NEVER condensed into MISSING -- not in cells, not in sums,
--     not in pills, not in footer, not in the report.
--     Concretely: UNKNOWN cells count neither as ready nor as gap; they are
--     excluded from BOTH sum numbers (sumHas/sumExpected count only
--     determinate = HAS/MISSING cells).
--   * Sums only for readable players (sumHas/sumExpected nil otherwise).
--   * Footer and report count only readable players.
--   * Report lines <= M.MAX_LINE (240) chars, overflow continues on
--     "  ... continued:" lines (chat hard limit is 255).
--   * Whisper/report strings are pure ASCII.
--   * Aura identity: spell-ID before name (different buffs can collide on
--     one display name, e.g. "Shadow Protection" the buff vs. the potion
--     effect). When the scan delivered ANY aura IDs
--     for a player, a bare name match no longer counts for table entries
--     that have known IDs (the aura carrying that name would have matched
--     by ID if it really were that buff). Names stay authoritative for
--     entries without known IDs (e.g. "Well Fed") and for ID-less scans.
--
-- Deliberate resolutions (edge cases decided here, documented so they
-- stay deliberate):
--   * ench + EMPTY slot: an item property, not an expectation --
--     independent of the expectation checkbox. Slots that HAVE an
--     exemption table (OFFH/RNGD) treat an EMPTY slot as NOTEXP "no item"
--     (nothing to enchant; 2H users have no off hand, casters may have no
--     ranged weapon). EVERY OTHER empty ench slot -- armor AND the
--     enchantable neck/ring slots -- is ALWAYS a gap: MISSING with detail
--     "<full> empty", regardless of whether the slot is expected. Empty
--     gear is a problem the expectation grid cannot suppress; the grid
--     only governs the ENCHANT question for a slot that has an item (see
--     the ench branch below). Trinket-kind tiles (T1/T2) mirror this:
--     EMPTY is always MISSING "<full> empty"; the expectation parameter
--     is not even read for them.
--   * Gear entries may carry an optional subType field (itemSubType,
--     GetItemInfo return 6) -- required by the ENCH_EXEMPT check. Absent
--     subType = no exemption.
--   * Row "ready" = readable AND gaps==0 AND unknowns==0 ("verified
--     complete" -- an unverified (UNKNOWN) cell can never be
--     part of a green pill).
--   * Trinket HAS detail is the gear entry TABLE (quality/name/texture for
--     the tile + tooltip) and hit HAS detail is the breakdown table; all
--     other details are strings or nil.
--   * Footer name lists and the "Not readable" list are sorted
--     alphabetically (deterministic across scans).
--
-- Cell shape:
--   aura/weapon cells:  { state, detail, icon = texturePath|nil }
--     icon ONLY when state==HAS; aura kind = texture of the matched buff
--     name from player.auras.textures (optional store field -- nil-guarded,
--     absent/partial textures => icon nil); weapon kind = always nil for
--     now. For ID matches the matched name is idToName[id]; when that is
--     nil the icon stays nil.
--   ench/trinket cells: { state, detail, item = gearEntry|nil }
--     item = the gear entry TABLE BY REFERENCE (model is read-only over
--     the store, no copy) whenever the entry is a real item table -- HAS,
--     enchant missing, subtype-exempt NOTEXP, and (ench kind only) the
--     not-expected NOTEXP case (the item still rides along so the tile
--     keeps rendering -- see the ench branch below); nil for "EMPTY" and
--     unknown (gear is not consulted, or the slot never held an item).
--   resist cells: { state, detail, value = number|nil } -- RESIST tab
--     only (see below); value is the resistance total, set on HAS, nil on
--     UNKNOWN.
--   hit cells: { state, detail, value, cap, capMet } -- HIT tab only;
--     value/cap are percentages with one decimal (set on HAS, nil
--     otherwise), detail is the breakdown TABLE on HAS and a plain reason
--     string on NOTEXP/UNKNOWN.
--   classify() accordingly returns (state, detail, icon, item, value) --
--   the trailing returns are nil for callers/kinds that do not use them.
--   `value` is used ONLY by kind=="resist" (build() copies it onto
--   cell.value); every other kind returns it as nil.
--
-- DEBUFFS tab, class exemptions, out-of-range flag:
--   * DEBUFFS tab: vm.slots is built DYNAMICALLY from the store
--     -- one column per distinct debuff name across READABLE players,
--     sorted by afflicted count desc then alpha, capped at M.DEBUFF_CAP
--     (10) columns; slot entries { id=name, label=nil, full=name,
--     kind="debuff", icon=texture|nil }. Cell semantics: afflicted =>
--     MISSING (detail "Afflicted: <name>", icon = debuff texture -- the
--     ONE kind whose icon rides on a non-HAS state); clean => HAS (icon
--     nil); unreadable (aurasRead false) => UNKNOWN. Zero debuffs is a
--     LEGITIMATE clean state -- an absent/empty player.debuffs on a
--     readable player is HAS, never a read failure. Expectations are NOT
--     consulted (every column applies to every role); whisperEligible is
--     ALWAYS false on DEBUFFS; ready pill formula unchanged (readable, 0
--     gaps, 0 unknowns = "clean players"); footer/report machinery
--     unchanged (afflicted counts per debuff). More than DEBUFF_CAP
--     distinct debuffs: columns stay capped, vm.debuffMore carries the
--     overflow and reportLines appends "+N more debuff types".
--   * Class-based enchant exemption: DC.ENCH_CLASS_EXEMPT
--     [slotId][class] => NOTEXP (detail "no ranged enchant for this
--     class"), checked FIRST in the ench branch -- before gearRead/
--     UNKNOWN, before EMPTY, before the expectation -- so it wins over
--     every other equipment outcome, readable or not.
--   * Out-of-range flag: rowVM.far = true iff readable and
--     player.distance and player.distance >= DC.FAR_LIMIT;
--     vm.coverage.far = count. Diagnostic ONLY -- far changes no state,
--     no sum, no pill.
--
-- RESIST and HIT tabs (display only, no gaps):
--   * Two static-column tabs share ONE set of rules. vm.slots is
--     DC.SLOTS_RESIST (the five resistance schools) resp. DC.SLOTS_HIT
--     (the eight hit columns), always ALL of them, unconditionally --
--     unlike the equipment/consumable tabs, nothing here is gated by
--     expectations, there are none to consult.
--   * classify() kind=="resist": not player.resistsRead => UNKNOWN (same
--     unreadableReason convention as every other kind); otherwise ALWAYS
--     HAS, value = player.resists[slotdef.school] or 0 (0 is a legitimate
--     resistance, not a read failure), detail = "<full>: <value>".
--     NEVER MISSING, NEVER NOTEXP -- a display tab has no gaps.
--   * Row/group aggregates on BOTH tabs: sumHas/sumExpected stay nil
--     (mirrors DEBUFFS); whisperEligible is ALWAYS false; gaps stay 0
--     (nothing can produce MISSING here), so the ready pill is vacuously
--     "all clean" and not rendered as a readiness claim by the UI.
--   * vm.colAvg = { [slotId] = the column's average over the players who
--     DELIVER that column } -- resistance columns average over
--     player.resistsRead == true, hit columns over the players whose hit
--     cell came out HAS. Computed straight off store.players (independent
--     of row.readable, which tracks aura/online status, not resistance or
--     hit readability).
--   * vm.colCount = { [slotId] = the DENOMINATOR that column's average
--     was divided by }. Anything that PRINTS a population (the report)
--     must take it from here: the ranged hit column drops every player
--     without a ranged weapon, so its denominator differs from any
--     channel-wide reader count. Those channel counts are
--     vm.resistReadable (resistsRead) and vm.hitReadable (hit.hitRead).
--   * vm.resistAvg / vm.resistCount are kept as ALIASES of colAvg/
--     colCount (the same tables, not copies) so readers written when the
--     resistances were the only display tab keep working.
--
-- Hit columns (HIT tab, kind=="hit"):
--   * DC.SLOTS_HIT carries EIGHT columns: melee and ranged hit
--     (slotdef.hitKind "melee"/"ranged"), then one column per magic
--     school (hitKind "spell" plus slotdef.school = "arcane" / "fire" /
--     "frost" / "holy" / "nature" / "shadow"). A school column shows the
--     generic spell hit PLUS that school's own bonuses -- which is the
--     entire point of the tab: two casters of the same class can sit at
--     different numbers per school.
--   * They ride on the SAME display-only rules as the resistances:
--     expectations are never consulted, row sums stay nil, no cell can
--     become a gap, no whisper.
--   * Readability is its own flag again: player.hit.hitRead. No hit table
--     or hitRead == false => UNKNOWN. There is no hit API on this client
--     (no GetHitModifier / GetSpellHitModifier / GetCombatRating), so the
--     numbers are summed from item tooltips by the scan -- an unreadable
--     unit yields no hit at all, never a 0.
--   * Otherwise HAS with cell.value = the hit percentage (one decimal),
--     cell.cap = the cap that applies to THIS player, cell.capMet =
--     value >= cap, and cell.detail = the breakdown TABLE below (the
--     second kind after trinket HAS whose detail is a table, not a
--     string).
--   * ONE exception to "readable => HAS": the ranged column is NOTEXP for
--     a player without a physical ranged weapon (bow/gun/crossbow/thrown)
--     -- a caster holding a wand has no ranged-hit question. NOTEXP needs
--     readable data, so an unreadable player stays UNKNOWN (unlike the
--     expectation kinds, where NOTEXP wins over UNKNOWN).
--   * Melee and ranged caps shrink with weapon skill (the linear scaling
--     of the current patch); the spell cap does not. The cap arithmetic
--     itself is NOT reimplemented here -- DC_Hit.MeleeCap/RangedCap
--     (scan/hit.lua, pure) own it, DC.HIT_CAPS (data/hit.lua) owns the
--     constants, and every call is existence-guarded: without that module
--     the cells show their numbers and make no cap claim.
--   * The weapon skill behind a melee/ranged cap is resolved HERE, per
--     build: the own character's MEASURED skill (hit.skillExact) wins,
--     everyone else gets DC_Hit.SkillFor's estimate = base + racial
--     specialization (player.race) + weapon-skill book. The book flags
--     are the build() `books` param (db.skillBooks), so ticking one in
--     the options changes the cap on the next REFRESH -- the scan
--     deliberately does not bake it in, and re-deriving the estimate here
--     is idempotent (a book is never added twice). Each column resolves
--     its OWN skill line: a bow has nothing to do with the measured
--     main-hand skill.
--   * There is no separate ranged-hit item stat in 1.12: the generic
--     "+N% chance to hit" line covers melee AND ranged, so both columns
--     read the same summed gear number and differ only in cap and weapon
--     skill.
--   * THREE contributions per column, kept apart end to end so the cell
--     tooltip can name each one instead of showing one unlabeled number:
--       gear    hit.gearMelee / hit.gearSpell, summed from item tooltips
--               by scan/hit.lua. Falls back to the pre-split totals
--               hit.melee / hit.spell when the split fields are absent,
--               so a hand-built or older store still classifies right.
--       auras   hit.auraMelee / auraRanged / auraSpell, folded on top by
--               scan/engine.lua's BuildPlayer from DC.HIT_AURAS.
--               hit.aurasRead == false means the aura contribution is
--               UNKNOWN, not a verified zero (the tooltip says so).
--       talents hit.talentMelee / talentRanged / talentSpell, plus
--               hit.talentSchools per school and hit.talentOffhand (the
--               warrior off-hand talent -- deliberately NOT part of the
--               melee number, it only rides in the tooltip).
--     hit.melee / hit.spell stay the TOTAL for backward compatibility.
--   * TALENTS ARE GATED BY hit.talentsRead, read STRICTLY (== true):
--     GetTalentInfo has no foreign-unit channel, so other players' ranks
--     arrive over this server's inspect protocol (scan/talents.lua) and
--     land in the same fields via the same DC_Hit.TalentHit. Anything but
--     true means no plausible reply has arrived YET (a "not yet", not an
--     "impossible"), so the number EXCLUDES talents and every tooltip
--     says exactly that. Reading the
--     flag strictly is what keeps the number and that sentence from ever
--     contradicting each other -- an absent flag never invents a bonus.
--   * Per-school value = generic spell hit (gear + aura + talent) + that
--     school's GEAR bonus (hit.schools, the school-only item lines) +
--     that school's TALENT bonus (hit.talentSchools). School keys arrive
--     in TWO spellings -- the gear table uses the DC.HIT_SCHOOLS display
--     names ("Frost"), slots and talents the lower-case token ("frost") --
--     and are resolved case-insensitively with FIRST MATCH ONLY, never a
--     sum, so a table carrying both spellings cannot double-count.
--   * cell.detail (hit breakdown table): { kind, value, cap, capBase,
--     capMet, gear, aura, aurasRead, talent, talentsRead, talentOffhand,
--     generic, school, gearSchool, talentSchool, skill, skillBase,
--     skillExact, skillName, book, dualWield, capWhite, mainSub, offSub,
--     rangedSub, schools }. Everything the cell tooltip needs -- capBase
--     is the unadjusted cap and skillBase the unmodified weapon skill, so
--     the tooltip can show the derivation; the UI never recomputes hit
--     math. `generic` is the school-independent part of a spell column,
--     `schools` rides along on a school-LESS spell column only (on the
--     HIT tab every school has its own column, so listing the others in a
--     column's tooltip would be noise). The spell cap carries no
--     capUnverified flag any more: it is derived from the server's own
--     99%-hit clamp (data/hit.lua DC.HIT_CAPS header), not a
--     quoted-but-unmeasured number.
--   * vm.colAvg holds one entry per hit column (average over the players
--     whose hit cell is HAS, one decimal -- a NOTEXP ranged cell is left
--     out instead of counted as 0) and vm.hitReadable is the channel's
--     reader count.
--
-- Weapon temp-enchant name:
--   * weaponMainName: weapon-kind HAS detail = player.weaponMainName (the
--     temp-enchant NAME the scan delivered) when set, else the generic
--     "main hand temp enchant". States are untouched -- the name never
--     influences HAS/MISSING/UNKNOWN (that stays weaponMain's job).
--
-- Last-known display layer:
--   THE IRON RULE: last-known data is DISPLAY-ONLY. It never counts as
--   HAS/MISSING in gaps, ready pills, sums, footer or report -- those keep
--   treating the cell as UNKNOWN. A flask seen 20 minutes ago is not
--   verified preparation.
--   * build() gains an OPTIONAL 5th param `now` (number|nil; nil => no
--     ages computed). Matrix passes GetTime(); report/offline callers may
--     omit it.
--   * For every cell whose state is UNKNOWN, when the player carries
--     matching last* data (p.lastAuras/p.lastGear/p.lastWeaponMain --
--     attached by scan/engine.lua from the runtime cache, or by core/sim),
--     THAT data is classified with the SAME classify() rules via a light
--     synthetic player view (no duplicated state machine) and the result
--     rides as cell.last = { state, detail, icon, item, age } (age =
--     now - <At> when both known). last.state can be HAS or MISSING --
--     purely informational; a cached UNKNOWN/NOTEXP outcome attaches
--     nothing (the plain gray "?" stays). Debuff cells have no last-known
--     channel.
--   * rowVM.gearUnreadable = (tab=="EQUIPMENT" and readable and not
--     player.gearRead) -- the cross-continent inspect-limit case.
--     rowVM.unreadNote = "offline" for offline rows, an "items not
--     readable" observation for
--     gearUnreadable rows, nil otherwise.
--
-- Per-class expectations + DEBUFFS warning semantics:
--   * Expectations are PER (role, class): expect[role][class][slotId].
--     build() resolves each row's line via (row role, player.class); an
--     UNKNOWN combination -- role or class line missing -- falls back to
--     the DC.DEFAULT_EXPECT role line. classify()'s
--     signature is unchanged: the CALLER resolves `expected`.
--     Dynamic columns: a slot column is active when ANY (role,
--     performing class) resolves to expected -- the domain is
--     DC_Roles.ROLE_CLASSES, and uncovered combos contribute their
--     fallback line. Corollary: a legacy role x slot table passed as
--     `expect` behaves exactly like before (every combo falls back to
--     its role line).
--   * DEBUFFS = WARNING SIGNAL, not expectation fulfillment:
--     rowVM.sumHas/sumExpected stay NIL on DEBUFFS (no x/y); instead
--     rowVM.debuffCount = TOTAL count of distinct debuff names on the
--     player (player.debuffs.names -- INCLUDING names beyond the
--     DEBUFF_CAP columns), nil when the row is not readable; and
--     group.debuffTotal = sum of debuffCount over the group's readable
--     rows. Gap semantics stay unchanged INTERNALLY: afflicted cells
--     keep driving row sort weight, footer, report and the ready pill.
--     (debuffCount/debuffTotal are computed on every tab -- they are
--     player properties -- the UI reads them on DEBUFFS.)
--   * reportLines section header: the DEBUFFS tab says
--     "Debuffs:", every other tab keeps "Missing per slot:".

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Model = DC_Model or {}
local M = DC_Model

-- Max report line length; the client chat limit is 255, we stay below.
M.MAX_LINE = 240

-- Max dynamic debuff columns on the DEBUFFS tab.
M.DEBUFF_CAP = 10

-- ==================================================================
-- Hit columns (HIT tab).
-- The hit ARITHMETIC lives in scan/hit.lua (DC_Hit.SkillFor / MeleeCap /
-- RangedCap / TalentHit, all pure) and the constants in data/hit.lua and
-- data/talenthit.lua -- this layer only resolves which number a cell
-- shows and whether the cap is met, so there is exactly ONE
-- implementation of the cap math in the addon.
-- Every DC_Hit call is existence-guarded: without that module the cells
-- still show their percentages, they just make no cap claim (a degraded
-- claim is worse than none). Without data/hit.lua the ranged column
-- cannot tell a bow from a wand either and stays NOTEXP throughout --
-- again silence rather than a guess.
-- ==================================================================

-- Percentages are carried with ONE decimal everywhere (cells, caps,
-- averages, report) -- rounding once keeps display and capMet comparison
-- consistent (a 7.96 that renders as "8.0" must also count as capped).
-- One-decimal text for a hit percentage, without the sign or unit --
-- shared by the whisper text so a whispered number reads exactly like the
-- one in the cell the player is being told about.
-- ------------------------------------------------------------------
-- Which hit columns a player is actually asked about.
--
-- Every player HAS all eight hit columns -- a warrior's shadow hit is a
-- real number, it is simply 0. Telling that warrior "shadow 0.0/16.0" is
-- noise, so the whisper (and the below-cap counter that offers it) only
-- looks at the columns that match the ROLE's attack kind. Heals cannot
-- miss, so healers are asked about nothing at all.
--
-- This governs WHISPERING only. Every column stays visible and keeps its
-- own cap marking on the tab -- the display never hides a number because
-- a role "should not care" about it.
-- ------------------------------------------------------------------
M.HIT_ROLE_KINDS = {
    TANK   = { melee = true },
    MELEE  = { melee = true },
    RANGED = { melee = true, ranged = true },
    CASTER = { spell = true },
    HEALER = {},
}

function M.HitRelevant(role, slotdef)
    local kinds = role and M.HIT_ROLE_KINDS[role]
    if not kinds or not slotdef then
        return false
    end
    return kinds[slotdef.hitKind] == true
end

function M.HitNum(v)
    return string.format("%.1f", M.RoundTenth(v or 0))
end

function M.RoundTenth(v)
    if type(v) ~= "number" then
        return nil
    end
    return math.floor(v * 10 + 0.5) / 10
end

-- Display text for a hit percentage: always one decimal ("8.0", "12.5"),
-- so a column of hit numbers stays visually aligned. The UI and
-- reportLines both go through this.
function M.HitText(v)
    if type(v) ~= "number" then
        return "?"
    end
    return string.format("%.1f", v)
end

-- One talent contribution, gated by the read flag. An unread talent tree
-- contributes NOTHING -- never a guess -- which is exactly what keeps the
-- displayed number and the tooltip's "excludes talents" sentence from
-- contradicting each other.
local function talentValue(v, talentsRead)
    if not talentsRead then
        return 0
    end
    return tonumber(v) or 0
end

-- One school's bonus out of ONE source table.
-- The same school reaches this layer in two spellings, because two
-- sources do: gear extras are keyed by the capitalized tooltip word
-- ("Frost"), slot definitions and talent tables by the lower-case id
-- ("frost"). DC.HIT_SCHOOL_KEY (data/hit.lua) is the bridge and is
-- consulted first; the case-insensitive fallbacks below keep this pure
-- layer working when that table is absent (offline tests, partial load).
-- The FIRST match wins -- never a sum -- so a table that happens to carry
-- both spellings can not double-count. Missing table, missing key or a
-- non-numeric value all read as 0.
-- Why not DC_Hit.SchoolHit (scan/hit.lua): that helper answers "what is
-- this school worth in total", while the cell tooltip has to name each
-- SOURCE apart (gear vs talents), so the two amounts are looked up
-- separately here and only summed for display.
local function schoolAmount(tbl, school)
    if type(tbl) ~= "table" or type(school) ~= "string" or school == "" then
        return 0
    end
    local v = tbl[school]
    if type(v) == "number" then
        return v
    end
    local lower = string.lower(school)
    local bridged = DC.HIT_SCHOOL_KEY and DC.HIT_SCHOOL_KEY[lower]
    if bridged then
        v = tbl[bridged]
        if type(v) == "number" then
            return v
        end
    end
    v = tbl[lower]
    if type(v) == "number" then
        return v
    end
    v = tbl[string.upper(string.sub(school, 1, 1))
        .. string.lower(string.sub(school, 2))]
    if type(v) == "number" then
        return v
    end
    for k, n in pairs(tbl) do
        if type(k) == "string" and type(n) == "number"
           and string.lower(k) == lower then
            return n
        end
    end
    return 0
end

-- Effective weapon skill for a hit column, resolved at DISPLAY time:
--   * a MEASURED skill wins (only the own character has one -- scan/hit
--     .lua reads it from the skill window and sets the exact flag),
--   * everyone else gets DC_Hit.SkillFor's estimate = base + racial
--     specialization + weapon-skill book.
-- Resolving here rather than trusting a value the scan wrote is
-- deliberate: the book flags are user input, so a checkbox click must
-- take effect on the next refresh, not on the next scan. Re-deriving the
-- estimate is also idempotent -- it never adds a book twice, whatever the
-- scan already filled in.
-- Each column passes its OWN measured triple (the main hand's skill has
-- no bearing on a bow) and its own subtype.
-- Returns skill, exact(bool), skillName -- all nil/false when the subtype
-- is no weapon at all (nothing equipped, shield, relic): no skill claim.
-- `books` is ONE player's flag table (db.skillBooks[playerName]).
local function effectiveSkill(player, subType, books, measured, measuredExact,
                              measuredName)
    if measuredExact and measured then
        return measured, true, measuredName
    end
    if DC_Hit and DC_Hit.SkillFor then
        local skill, skillName = DC_Hit.SkillFor(subType, player.race, books)
        if skill then
            return skill, false, skillName
        end
    end
    return nil, false, nil
end

-- ==================================================================
-- Data indices, built lazily from DC.CONSUMABLES / DC.CLASSBUFFS
-- (data/*.lua load before first use; call M.RebuildIndex() after
-- mutating the data tables, e.g. in tests).
-- ==================================================================
local indexBuilt = false
local nameHasIds = {}   -- [buffName] = true when the table entry has known spell IDs
local idToName   = {}   -- [spellID]  = buffName (for HAS detail on ID match)

function M.RebuildIndex()
    nameHasIds = {}
    idToName = {}
    if DC.CONSUMABLES then
        for name, def in pairs(DC.CONSUMABLES) do
            if def.spellID and def.spellID > 0 then
                nameHasIds[name] = true
                idToName[def.spellID] = name
            end
        end
    end
    if DC.CLASSBUFFS then
        for name, def in pairs(DC.CLASSBUFFS) do
            if def.ids and table.getn(def.ids) > 0 then
                nameHasIds[name] = true
                local n = table.getn(def.ids)
                for i = 1, n do
                    idToName[def.ids[i]] = name
                end
            end
        end
    end
    indexBuilt = true
end

local function ensureIndex()
    if not indexBuilt then
        M.RebuildIndex()
    end
end

local function nameMapsToSlot(name, slotId)
    local c = DC.CONSUMABLES and DC.CONSUMABLES[name]
    if c and c.slot == slotId then
        return true
    end
    local b = DC.CLASSBUFFS and DC.CLASSBUFFS[name]
    if b and b.slot == slotId then
        return true
    end
    return false
end

-- ==================================================================
-- classify(player, slotdef, expected, books)
--   -> state, detail, icon, item, value
-- State machine per slotdef.kind (icon/item/value extra returns per the
-- cell shape documented in the header).
-- `books` is ONE player's weapon-skill-book flags
-- (db.skillBooks[playerName]) and is read by the hit kind ONLY -- every
-- other kind ignores it, so three-argument callers keep working.
-- NOTEXP takes precedence over UNKNOWN (an unexpected slot is "not
-- expected" even for an unreadable player) for the KINDS that consult
-- `expected` at all -- debuff/resist ignore it outright (see their
-- branches), and ench/trinket consult it LATER than every other kind
-- (see the ench/trinket branch below: gear facts -- readability, class
-- exemption, EMPTY -- are resolved FIRST, `expected` only ever decides
-- the narrower "is this item enchanted" question).
-- ==================================================================
function M.classify(player, slotdef, expected, books)
    local S = DC.STATE
    local kind = slotdef.kind

    if kind == "debuff" then
        -- Expectations are NOT consulted on debuff columns
        -- (every column applies to every role) -- the `expected` param
        -- is deliberately ignored, so this branch sits BEFORE the
        -- expected-check. Readability = the existing aurasRead flag.
        if not player.aurasRead then
            return S.UNKNOWN, player.unreadableReason or "no data"
        end
        local d = player.debuffs
        if d and d.names and d.names[slotdef.id] then
            -- afflicted: icon = debuff texture (player's own entry wins,
            -- column icon as fallback); the ONE non-HAS icon case
            local icon = slotdef.icon
            if d.textures and d.textures[slotdef.id] then
                icon = d.textures[slotdef.id]
            end
            return S.MISSING, "Afflicted: " .. slotdef.full, icon
        end
        -- zero debuffs / absent debuffs field on a readable player is a
        -- LEGITIMATE clean state -- never read failure
        return S.HAS, nil
    end

    if kind == "resist" then
        -- RESIST tab: display only, expectations are NEVER consulted (the
        -- `expected` param is deliberately ignored, like debuff above).
        -- Readability rides on its OWN flag (player.resistsRead) -- fully
        -- independent of aurasRead/gearRead, since a foreign
        -- UnitResistance read is neither an aura nor a gear read.
        if not player.resistsRead then
            return S.UNKNOWN, player.unreadableReason or "no data"
        end
        local v = (player.resists and player.resists[slotdef.school]) or 0
        -- NEVER MISSING, NEVER NOTEXP -- a display tab has no gaps; the
        -- resistance total rides as the 5th return (value), copied onto
        -- cell.value by build() (see the cell shape doc in the header).
        --
        -- Provenance suffix (binding honesty rule, see scan/engine.lua's
        -- AssembleResists header): a RECONSTRUCTED number is not the same
        -- kind of fact as a MEASURED one. player.resistsSource == "gear"
        -- means this total came from item tooltips + the racial bonus, not
        -- from UnitResistance/GetUnitField -- the detail string says so
        -- rather than presenting a rebuilt number as an unqualified
        -- reading. Every other source ("token"/"guid"/"field", or nil for
        -- the always-measured own character) prints unchanged.
        local detail = slotdef.full .. ": " .. v
        if player.resistsSource == "gear" then
            detail = detail .. " (from gear)"
        end
        return S.HAS, detail, nil, nil, v
    end

    if kind == "hit" then
        -- HIT tab, display only: expectations are NEVER consulted (the
        -- `expected` param is ignored, like debuff/resist above), and no
        -- outcome can ever be MISSING -- a hit number below its cap is
        -- information, not a gap the addon nags about.
        local h = player.hit
        if not (h and h.hitRead) then
            -- no hit API exists on this client; without readable item
            -- tooltips there is no number at all (never a 0)
            return S.UNKNOWN, player.unreadableReason or "no data"
        end
        local caps = DC.HIT_CAPS or {}
        local hitKind = slotdef.hitKind or "melee"
        -- Talents: readable for the OWN character only, so the flag is
        -- read strictly (see the header). Anything but true keeps every
        -- talent contribution at 0 AND makes the tooltip say the number
        -- excludes talents -- one flag drives both.
        local talentsRead = (h.talentsRead == true)
        local b = {
            kind = hitKind,
            skillBase = DC.BASE_WEAPON_SKILL or 300,
            mainSub = h.mainSub,
            offSub = h.offSub,
            -- hit-granting auras (DC.HIT_AURAS, data/hit.lua) are folded
            -- into hit.gearX/hit.auraX at scan time (scan/engine.lua
            -- BuildPlayer) -- b.aura carries just the AURA portion so the
            -- tooltip can show "from gear" and "from auras" apart. A
            -- missing aurasRead flag (older/hand-built stores) reads as
            -- true: the aura contribution is a known zero, not unknown.
            aurasRead = (h.aurasRead ~= false),
            talentsRead = talentsRead,
        }
        if hitKind == "spell" then
            b.gear = h.gearSpell or h.spell or 0
            -- SET bonuses are their own addend: scan/engine.lua already
            -- took them OUT of gearSpell, so adding them here counts them
            -- exactly once and lets the tooltip list them on their own line
            b.set = h.setSpell or 0
            b.aura = h.auraSpell or 0
            b.talent = talentValue(h.talentSpell, talentsRead)
            -- the school-INDEPENDENT part: what every school column has in
            -- common, printed as its own tooltip line there
            b.generic = M.RoundTenth(b.gear + b.set + b.aura + b.talent)
            -- spell hit knows no weapon skill: base cap, unadjusted. The
            -- cap itself is DERIVED from the server's 99% hit clamp (data/
            -- hit.lua DC.HIT_CAPS header), not a measured value, but that
            -- is no longer flagged as "unverified" -- see the header note.
            b.capBase = M.RoundTenth(caps.spell)
            b.cap = b.capBase
            if slotdef.school then
                -- School column: generic spell hit + this school's gear
                -- bonus + this school's talent bonus. That sum is the
                -- whole reason the tab exists -- two casters of one class
                -- differ per school. b.schools stays nil here: every
                -- other school has its own column.
                b.school = slotdef.school
                -- h.schools is the TOTAL per school (items + set bonuses),
                -- so the set part is split out here too -- otherwise a
                -- school-specific set bonus would land in both lines
                b.setSchool = schoolAmount(h.setSchools, slotdef.school)
                b.gearSchool = schoolAmount(h.schools, slotdef.school)
                    - b.setSchool
                b.talentSchool = 0
                if talentsRead then
                    b.talentSchool = schoolAmount(h.talentSchools,
                        slotdef.school)
                end
                b.value = M.RoundTenth(b.generic + b.gearSchool
                    + b.setSchool + b.talentSchool)
            else
                -- Generic spell column (no school on the slot): a
                -- school-specific bonus counts against that school ONLY,
                -- so it never enters the value; the whole table rides
                -- along for the tooltip (by reference, the model never
                -- copies store tables).
                b.value = b.generic
                b.schools = h.schools
            end
        else
            -- one gear number for melee AND ranged: this client has no
            -- separate ranged-hit item stat
            b.gear = h.gearMelee or h.melee or 0
            b.set = h.setMelee or 0
            if hitKind == "ranged" then
                local ranged = DC.RANGED_ATTACK_SUBTYPE or {}
                if not (h.rangedSub and ranged[h.rangedSub]) then
                    -- Readable, but there is no ranged-hit question to
                    -- ask. The two causes get their OWN reason, because
                    -- the wand sentence is a non-sequitur for a player
                    -- who simply carries nothing there -- and this string
                    -- is what the cell tooltip prints verbatim.
                    if h.rangedSub then
                        return S.NOTEXP,
                            "a wand or relic is not a ranged attack weapon"
                    end
                    return S.NOTEXP, "nothing in the ranged slot"
                end
                b.aura = h.auraRanged or 0
                b.talent = talentValue(h.talentRanged, talentsRead)
                b.value = M.RoundTenth(b.gear + b.set + b.aura + b.talent)
                b.rangedSub = h.rangedSub
                -- the ranged skill is its OWN skill line (bows/guns/...),
                -- so the measured MAIN-HAND skill must not leak into it
                b.skill, b.skillExact, b.skillName =
                    effectiveSkill(player, h.rangedSub, books,
                        h.rangedSkill, h.rangedSkillExact, nil)
                b.capBase = M.RoundTenth(caps.ranged)
                if DC_Hit and DC_Hit.RangedCap then
                    local rc = DC_Hit.RangedCap(h.rangedSub, b.skill, caps)
                    if rc then
                        b.cap = rc.cap
                        b.skillName = b.skillName or rc.skillName
                    end
                end
            else
                b.aura = h.auraMelee or 0
                b.talent = talentValue(h.talentMelee, talentsRead)
                -- Off-hand hit talent (the warrior dual-wield talent):
                -- it raises OFF-HAND swings only, so it is deliberately
                -- NOT added to the melee number -- the tooltip mentions
                -- it while the player actually holds two weapons.
                b.talentOffhand = talentValue(h.talentOffhand, talentsRead)
                b.value = M.RoundTenth(b.gear + b.set + b.aura + b.talent)
                b.skill, b.skillExact, b.skillName =
                    effectiveSkill(player, h.mainSub, books,
                        h.skill, h.skillExact, h.skillName)
                b.skillName = b.skillName or h.skillName
                b.capBase = M.RoundTenth(caps.meleeYellow)
                if DC_Hit and DC_Hit.MeleeCap then
                    local mc = DC_Hit.MeleeCap(h.mainSub, h.offSub,
                        b.skill, caps)
                    b.cap = mc.yellow
                    b.dualWield = mc.dualWield
                    if mc.dualWield then
                        -- white swings keep their own, much higher cap.
                        -- Stated at its BASE too (see the skill note
                        -- below): the boss's floor does not move.
                        b.capWhite = M.RoundTenth(caps.meleeWhiteDW)
                    end
                    b.skillName = b.skillName or mc.skillName
                end
            end
            -- did a ticked book go into this column's skill? (a MEASURED
            -- skill already contains it, the tooltip says so instead)
            b.book = (books and b.skillName and books[b.skillName])
                and true or false
        end
        -- WEAPON SKILL counts on the PLAYER's side of the comparison, not
        -- as a discount on the boss's requirement. The two readings are
        -- arithmetically identical --
        --     value >= cap - d   <=>   value + d >= cap
        -- -- but a +3-level boss's miss floor is a property of the BOSS and
        -- does not move because the attacker trained a weapon; skill is
        -- something the player brings, exactly like gear or a talent. So
        -- the skill-derived part becomes an addend of the value and the cap
        -- is reported at its base. b.skillHit carries it so the tooltip can
        -- show it as its own row of the addition.
        if b.cap and b.capBase then
            b.skillHit = M.RoundTenth(b.capBase - b.cap)
            if b.skillHit ~= 0 then
                b.value = M.RoundTenth(b.value + b.skillHit)
            end
            b.cap = b.capBase
        else
            b.skillHit = 0
        end
        if b.cap == nil then
            -- no cap claim without the hit module (see the section
            -- header) -- the number itself is still shown
            b.capMet = false
        else
            b.capMet = b.value >= b.cap
        end
        return S.HAS, b, nil, nil, b.value
    end

    if kind == "ench" or kind == "trinket" then
        -- Equipment: gaps are shaped by what is EQUIPPED, not by the
        -- expectation grid. Order: class exemption (ench only, wins over
        -- everything -- e.g. a shaman never has a ranged enchant slot,
        -- readable or not), then gearRead/UNKNOWN, then whether the slot
        -- is EMPTY (always MISSING except the legitimately-empty
        -- exemptable case -- see the header). `expected` is consulted
        -- LAST and ONLY for the ench-kind "is this item enchanted"
        -- question; trinket-kind tiles never read `expected` at all --
        -- an equipped item is HAS, an empty tile is MISSING, always.
        if kind == "ench" then
            local classExempt = DC.ENCH_CLASS_EXEMPT
                and DC.ENCH_CLASS_EXEMPT[slotdef.id]
            if classExempt and player.class and classExempt[player.class] then
                return S.NOTEXP, "no ranged enchant for this class"
            end
        end
        if not player.gearRead then
            return S.UNKNOWN, player.unreadableReason or "no data"
        end
        local entry = player.gear and player.gear[slotdef.invSlot]
        if entry == nil then
            return S.UNKNOWN, "no data"
        end
        local exempt = DC.ENCH_EXEMPT and DC.ENCH_EXEMPT[slotdef.id]
        if entry == "EMPTY" then
            if kind == "ench" and exempt then
                -- exemptable slot (off hand / ranged) with no item:
                -- nothing to enchant, and the item itself would have been
                -- exempt anyway -- legitimately empty, not a gap
                return S.NOTEXP, "no item"
            end
            -- every other empty slot -- armor, the enchantable neck/ring
            -- slots, and the trinket tiles -- is ALWAYS a gap, no matter
            -- what the expectation grid says (see the header)
            return S.MISSING, slotdef.full .. " empty"
        end
        -- entry is a table from here on -> it rides along as cell.item
        -- (by reference; the model never copies gear entries)
        if kind == "trinket" then
            -- tiles ignore `expected` entirely: an equipped item is HAS
            return S.HAS, entry, nil, entry
        end
        if exempt and entry.subType and exempt[entry.subType] then
            return S.NOTEXP, entry.subType .. " - not enchantable", nil, entry
        end
        if not expected then
            -- enchant not expected for this role/class: the item is real
            -- (not empty), so the tile still renders -- NOTEXP carries
            -- the item, counts nowhere, no green/red marker (ui/matrix.lua)
            return S.NOTEXP, nil, nil, entry
        end
        if entry.enchant and entry.enchant > 0 then
            return S.HAS, entry.name, nil, entry
        end
        return S.MISSING, "no enchant", nil, entry
    end

    if not expected then
        return S.NOTEXP, nil
    end

    if kind == "aura" then
        if not player.aurasRead then
            return S.UNKNOWN, player.unreadableReason or "no data"
        end
        ensureIndex()
        local auras = player.auras or {}
        local ids = auras.ids or {}
        local names = auras.names or {}
        local textures = auras.textures   -- optional store field, nil-safe
        local spellToSlot = DC.SPELL_TO_SLOT or {}
        -- ID pass: spell ID is the primary identity
        for id in pairs(ids) do
            if spellToSlot[id] == slotdef.id then
                local nm = idToName[id]
                if nm then
                    local icon = nil
                    if textures then
                        icon = textures[nm]
                    end
                    return S.HAS, nm .. " (spell " .. id .. ")", icon
                end
                -- no name carried the id -> icon stays nil (by design)
                return S.HAS, "spell " .. id
            end
        end
        -- Name fallback: when IDs were readable, only names WITHOUT known
        -- IDs still count (name-collision rule: the Shadow Protection
        -- potion aura must not satisfy the SPROT class-buff slot).
        local haveIds = (next(ids) ~= nil)
        for name in pairs(names) do
            if nameMapsToSlot(name, slotdef.id) then
                if not (haveIds and nameHasIds[name]) then
                    -- Consumable/class-buff name collision (decision
                    -- 2026-08-15, data/classbuffs.lua
                    -- DC.CONSUMABLE_CLASSBUFF_NAME_COLLISION): a
                    -- name-only match (this branch only runs when no
                    -- spell ID resolved the buff) can never satisfy a
                    -- CONSUMABLE slot when the name is also a class buff
                    -- name -- UNKNOWN, not HAS. One-sided: the class-buff
                    -- slot side of the same name is unaffected (see the
                    -- constant's comment for why).
                    local cdef = DC.CONSUMABLES and DC.CONSUMABLES[name]
                    local collide = DC.CONSUMABLE_CLASSBUFF_NAME_COLLISION
                    if cdef and cdef.slot == slotdef.id
                       and collide and collide[name] then
                        return S.UNKNOWN,
                            "name-only, ambiguous with class buff: " .. name
                    end
                    local icon = nil
                    if textures then
                        icon = textures[name]
                    end
                    return S.HAS, name, icon
                end
            end
        end
        return S.MISSING, nil

    elseif kind == "weapon" then
        if player.weaponMain == nil then
            return S.UNKNOWN, player.unreadableReason or "no data"
        end
        if player.weaponMain then
            -- enchant name when the scan delivered one
            if player.weaponMainName then
                return S.HAS, player.weaponMainName
            end
            return S.HAS, "main hand temp enchant"
        end
        return S.MISSING, nil
    end

    return S.UNKNOWN, "unknown slot kind"
end

-- ==================================================================
-- Gap label for chat output (whisper + report):
-- consumables/class buffs -> full slot name; enchant -> "Enchant <Slot>";
-- trinket -> "Trinket N empty".
-- ==================================================================
function M.gapLabel(slotdef)
    if slotdef.kind == "ench" then
        return "Enchant " .. slotdef.full
    elseif slotdef.kind == "trinket" then
        return slotdef.full .. " empty"
    end
    return slotdef.full
end

-- ==================================================================
-- build(store, roleOf, expect, tab, now, books) -> vm
--   roleOf(playerEntry) -> role, suggested(bool), reason(string|nil)
--   expect = per-class expectation table from db:
--            expect[role][class][slotId] = true|nil; unknown (role,
--            class) combos fall back to the DC.DEFAULT_EXPECT role line
--   tab    = "CONSUMABLES" | "CLASSBUFFS" | "DEBUFFS" | "RESIST" |
--            "HIT" | "EQUIPMENT"
--   now    = optional clock (GetTime seconds) for cell.last.age -- nil
--            => no ages computed
--   books  = optional db.skillBooks (weapon-skill-book flags per player
--            NAME, then per weapon skill). Read by the hit columns only;
--            nil => nobody owns a book. Passed in rather than read from a
--            global so the model stays offline-testable, and resolved on
--            every build so a checkbox click shows up on the next refresh
--            instead of the next scan.
--   vm.unassigned = { count = n, names = sorted array } -- players whose
--     role is only a heuristic suggestion (suggested==true), i.e. no
--     confirmed assignment. Counts ALL players, readable or not: role
--     assignment is independent of readability.
-- ==================================================================
local function tabSlots(tab)
    if tab == "CLASSBUFFS" then
        return DC.SLOTS_CLASSBUFFS
    elseif tab == "EQUIPMENT" then
        return DC.SLOTS_EQUIPMENT
    end
    return DC.SLOTS_CONSUMABLES
end

-- DISPLAY tabs: static columns, no expectations, no gaps, no sums, no
-- whisper, a per-column average instead of a missing count. Named once so
-- the four places that implement those rules cannot drift apart when a
-- third display tab appears.
function M.IsDisplayTab(tab)
    return tab == "RESIST" or tab == "HIT"
end

-- ==================================================================
-- ChannelRead(player, tab) -> bool
-- Did the read channel THIS TAB DRAWS FROM succeed for this player?
-- Row readability (and every cell state) rides on the aura channel,
-- which is raid-wide; gear and hit are near-range only, and foreign
-- resistances are not transmitted at all, so one global count
-- over-reports on every tab that is not aura-backed. Measured in a
-- 26-man raid: auras 26/26, gear 15/26, resistances 1/26 while the
-- pill said 26/26 everywhere.
-- The offline gate comes first on purpose: a player who dropped out
-- keeps whatever flags the last successful scan left behind, and those
-- must not re-inflate the number that exists to stay honest.
-- Deliberately NOT wired into row.readable -- that flag decides cell
-- states and sums, and turning it per-tab would silently rewrite what
-- UNKNOWN means on three tabs. This is the reporting number only.
-- ==================================================================
function M.ChannelRead(p, tab)
    if p.online == false then
        return false
    end
    if tab == "RESIST" then
        return p.resistsRead and true or false
    elseif tab == "HIT" then
        return (p.hit and p.hit.hitRead) and true or false
    elseif tab == "EQUIPMENT" then
        return p.gearRead and true or false
    end
    return p.aurasRead and true or false
end

-- ==================================================================
-- CoverageLabel(tab) -> string
-- The noun behind the coverage number. "readable" used to sit on the
-- pill AND (as "AVERAGE (READABLE)") in the footer while meaning two
-- different populations; naming the channel on the pill removes the
-- collision instead of papering over it, and says in-game which read
-- the number is about. Plain ASCII -- the 1.12 chat/UI font.
-- ==================================================================
function M.CoverageLabel(tab)
    if tab == "RESIST" then
        return "resist read"
    elseif tab == "HIT" then
        return "hit read"
    elseif tab == "EQUIPMENT" then
        return "gear read"
    end
    return "readable"
end

-- ------------------------------------------------------------------
-- Per-(role,class) expectation resolution.
-- expect[role][class] is the explicit line; a missing role or class
-- line falls back to the DC.DEFAULT_EXPECT role line, so
-- saved tables that predate a class/role addition keep sane behavior.
-- classify() stays untouched: these helpers run in the CALLER.
-- ------------------------------------------------------------------
local EMPTY_LINE = {}

local function expectLine(expect, role, class)
    local byClass = expect and expect[role]
    if byClass and class then
        local line = byClass[class]
        if type(line) == "table" then
            return line
        end
    end
    local def = DC.DEFAULT_EXPECT and DC.DEFAULT_EXPECT[role]
    return def or EMPTY_LINE
end

-- A slot column is active when ANY (role, performing class) resolves to
-- expected. The domain is role x DC_Roles.ROLE_CLASSES
-- [role] -- resolved with the same fallback as row cells, so uncovered
-- combos keep their default columns visible.
local function anyClassExpects(expect, slotId)
    local nRoles = table.getn(DC.ROLES)
    for r = 1, nRoles do
        local role = DC.ROLES[r]
        local classes = DC_Roles and DC_Roles.ROLE_CLASSES
            and DC_Roles.ROLE_CLASSES[role]
        if classes then
            for c = 1, table.getn(classes) do
                if expectLine(expect, role, classes[c])[slotId] then
                    return true
                end
            end
        else
            -- defensive: without DC_Roles fall back to the role line
            if expectLine(expect, role, nil)[slotId] then
                return true
            end
        end
    end
    return false
end

-- Dynamic DEBUFFS columns: one column per distinct
-- debuff name across READABLE players (same readability rule as the row
-- loop), sorted by afflicted count desc then alpha, capped at
-- M.DEBUFF_CAP. Returns slots array + overflow count (distinct beyond
-- the cap; the report appends "+N more debuff types" from it).
local function buildDebuffSlots(store)
    local counts = {}
    local icons = {}
    local names = {}
    local players = (store and store.players) or {}
    local nPlayers = table.getn(players)
    for i = 1, nPlayers do
        local p = players[i]
        -- readability rule: offline / aurasRead==false
        -- players contribute no columns
        if p.online ~= false and p.aurasRead
           and p.debuffs and p.debuffs.names then
            for nm in pairs(p.debuffs.names) do
                if counts[nm] == nil then
                    counts[nm] = 0
                    table.insert(names, nm)
                end
                counts[nm] = counts[nm] + 1
                if icons[nm] == nil and p.debuffs.textures then
                    icons[nm] = p.debuffs.textures[nm]
                end
            end
        end
    end
    table.sort(names, function(a, b)
        if counts[a] ~= counts[b] then
            return counts[a] > counts[b]
        end
        return a < b
    end)
    local total = table.getn(names)
    local keep = total
    if keep > M.DEBUFF_CAP then
        keep = M.DEBUFF_CAP
    end
    local slots = {}
    for i = 1, keep do
        local nm = names[i]
        table.insert(slots, {
            id = nm, label = nil, full = nm,
            kind = "debuff", icon = icons[nm],
        })
    end
    return slots, total - keep
end

-- Group-internal sort: gaps first (gaps desc), then unreadable, then
-- complete; ties stable by name (table.sort is NOT stable in Lua 5.0,
-- so name is an explicit final tiebreaker -> total deterministic order).
local function rowLess(a, b)
    if a.sortBucket ~= b.sortBucket then
        return a.sortBucket < b.sortBucket
    end
    if a.sortBucket == 1 and a.gaps ~= b.gaps then
        return a.gaps > b.gaps
    end
    return a.player.name < b.player.name
end

function M.build(store, roleOf, expect, tab, now, books)
    local S = DC.STATE
    local slots
    local debuffMore = 0

    if tab == "DEBUFFS" then
        -- columns come from the STORE, not from a data table, and
        -- expectations play no part
        slots, debuffMore = buildDebuffSlots(store)
    elseif tab == "RESIST" then
        -- static columns, always all 5, expectations play no part
        -- (display-only tab -- see the header)
        slots = DC.SLOTS_RESIST or {}
    elseif tab == "HIT" then
        -- static columns, always all 8 (melee, ranged, six schools) --
        -- the second display-only tab, same rules throughout
        slots = DC.SLOTS_HIT or {}
    else
        local allSlots = tabSlots(tab)
        -- Dynamic columns: a slot is active
        -- iff at least one (role, performing class) expects it; trinkets
        -- are ALWAYS active on EQUIPMENT.
        slots = {}
        local nAll = table.getn(allSlots)
        for i = 1, nAll do
            local sd = allSlots[i]
            local active = false
            if sd.kind == "trinket" then
                active = true
            else
                active = anyClassExpects(expect, sd.id)
            end
            if active then
                table.insert(slots, sd)
            end
        end
    end
    local nSlots = table.getn(slots)

    -- Groups: always all five, fixed order.
    local groups = {}
    local groupsByRole = {}
    local nRoles = table.getn(DC.ROLES)
    for r = 1, nRoles do
        local role = DC.ROLES[r]
        local g = {
            role = role,
            label = DC.ROLE_LABEL[role],
            rows = {},
            total = 0,
            readable = 0,
            unreadable = 0,
            gaps = 0,
            ready = 0,
            -- sum of debuffCount over readable rows
            debuffTotal = 0,
        }
        table.insert(groups, g)
        groupsByRole[role] = g
    end

    -- Footer: one entry per ACTIVE slot (count 0 included).
    local footer = {}
    for i = 1, nSlots do
        footer[slots[i].id] = { count = 0, names = {} }
    end

    -- readable = the aura-channel/row-readability count (unchanged, it
    -- backs the cell states); channelReadable = what THIS tab's own read
    -- channel actually covers -- see M.ChannelRead
    local coverage = { readable = 0, total = 0, offline = 0,
                       readfailed = 0, far = 0, channelReadable = 0 }
    local unreadableNames = {}
    local unassignedNames = {}

    local players = store.players or {}
    local nPlayers = table.getn(players)
    coverage.total = nPlayers

    for i = 1, nPlayers do
        local p = players[i]

        -- Readability rule (binding): online==false =>
        -- offline; otherwise aurasRead==false => read failed. Distance is
        -- diagnosis only, never a filter.
        local readable, urReason
        if p.online == false then
            readable = false
            urReason = p.unreadableReason or "offline"
            coverage.offline = coverage.offline + 1
        elseif not p.aurasRead then
            readable = false
            urReason = p.unreadableReason or "read failed"
            coverage.readfailed = coverage.readfailed + 1
        else
            readable = true
        end
        if readable then
            coverage.readable = coverage.readable + 1
        else
            table.insert(unreadableNames, p.name)
        end
        if M.ChannelRead(p, tab) then
            coverage.channelReadable = coverage.channelReadable + 1
        end

        -- Out-of-range flag: diagnostic ONLY -- far
        -- changes no cell state, no sum, no pill. Unreadable players are
        -- never "far" (their distance is already pure diagnosis).
        local far = false
        if readable and p.distance and DC.FAR_LIMIT
           and p.distance >= DC.FAR_LIMIT then
            far = true
            coverage.far = coverage.far + 1
        end

        local role, suggested, roleReason = roleOf(p)
        if not groupsByRole[role] then
            role = DC.ROLES[1]  -- defensive: roleOf must always return a known role
        end
        -- Unassigned aggregate: suggested == the role is only a heuristic
        -- proposal, not a confirmed assignment. EVERY such player counts,
        -- unreadable ones too (assignment is independent of readability).
        if suggested then
            table.insert(unassignedNames, p.name)
        end
        -- per-class expectation line: explicit
        -- expect[role][player.class] when present, else the
        -- DC.DEFAULT_EXPECT role line (default fallback)
        local rexp = expectLine(expect, role, p.class)
        -- this player's weapon-skill-book flags (hit columns only)
        local pBooks = books and books[p.name] or nil

        -- Last-known display layer: synthetic read-only
        -- player views over the cached tables, built ONCE per row, so the
        -- SAME classify() state machine below can re-run on the cached
        -- data (no duplicated rules). IRON RULE: results only decorate
        -- UNKNOWN cells as cell.last -- no counter below ever reads them.
        local lastAuraView, lastGearView, lastWeaponView
        if p.lastAuras then
            lastAuraView = { name = p.name, class = p.class, online = true,
                aurasRead = true, auras = p.lastAuras }
        end
        if p.lastGear then
            lastGearView = { name = p.name, class = p.class, online = true,
                gearRead = true, gear = p.lastGear }
        end
        if p.lastWeaponMain ~= nil then
            lastWeaponView = { name = p.name, class = p.class, online = true,
                weaponMain = p.lastWeaponMain,
                weaponMainName = p.lastWeaponMainName }
        end

        local cells = {}
        local gaps, unknowns, has = 0, 0, 0
        -- HIT tab only: columns that are SHORT OF THEIR CAP. The hit
        -- tab produces no MISSING cells (a number below its cap is
        -- information, not an unfilled slot), so it needs its own
        -- counter to answer "is there anything to tell this player".
        local belowCap = 0
        for si = 1, nSlots do
            local sd = slots[si]
            local expd = false
            if sd.kind == "debuff" or sd.kind == "resist"
               or sd.kind == "hit" then
                -- expectations are NOT consulted on debuff/resist/hit
                -- columns; classify ignores the flag anyway
                expd = true
            elseif rexp[sd.id] then
                expd = true
            end
            local state, detail, icon, item, value =
                M.classify(p, sd, expd, pBooks)
            cells[sd.id] = { state = state, detail = detail,
                             icon = icon, item = item }
            if sd.kind == "resist" then
                cells[sd.id].value = value
            elseif sd.kind == "hit" then
                -- value/cap/capMet are lifted out of the breakdown table
                -- so the UI can paint a cell without unpacking it; they
                -- stay nil on NOTEXP/UNKNOWN (detail is a string there)
                cells[sd.id].value = value
                if type(detail) == "table" then
                    cells[sd.id].cap = detail.cap
                    cells[sd.id].capMet = detail.capMet
                    -- BELOW-CAP counter -- the hit tab's equivalent of a
                    -- gap, and the only thing that makes a hit row worth
                    -- whispering about. A column with NO cap known makes
                    -- no claim (capMet is false there too), so the cap
                    -- itself has to be present before this counts.
                    if detail.cap and detail.capMet == false
                       and M.HitRelevant(role, sd) then
                        belowCap = belowCap + 1
                    end
                end
            end
            if state == S.MISSING then
                gaps = gaps + 1
                if readable then
                    local f = footer[sd.id]
                    f.count = f.count + 1
                    table.insert(f.names, p.name)
                end
            elseif state == S.UNKNOWN then
                unknowns = unknowns + 1
                -- cell.last: classify the cached data with
                -- the same rules; attach only determinate outcomes (a
                -- cached UNKNOWN/NOTEXP keeps the plain gray "?"). Debuff
                -- kind has no last-known channel (no view is ever built).
                local view, at
                if sd.kind == "aura" then
                    view = lastAuraView
                    at = p.lastAurasAt
                elseif sd.kind == "weapon" then
                    view = lastWeaponView
                    at = p.lastWeaponAt
                elseif sd.kind == "ench" or sd.kind == "trinket" then
                    view = lastGearView
                    at = p.lastGearAt
                end
                if view then
                    local ls, ld, li, lit = M.classify(view, sd, expd)
                    if ls == S.HAS or ls == S.MISSING then
                        local age = nil
                        if now and at then
                            age = now - at
                        end
                        cells[sd.id].last = { state = ls, detail = ld,
                            icon = li, item = lit, age = age }
                    end
                end
            elseif state == S.HAS then
                has = has + 1
            end
        end

        -- total count of DISTINCT debuff names on the
        -- player -- straight off player.debuffs.names, so it INCLUDES
        -- names beyond the DEBUFF_CAP columns (warning signal, not
        -- column arithmetic). nil when the row is not readable; zero
        -- debuffs on a readable player is the verified-clean case.
        local debuffCount = nil
        if readable then
            debuffCount = 0
            if p.debuffs and p.debuffs.names then
                for _ in pairs(p.debuffs.names) do
                    debuffCount = debuffCount + 1
                end
            end
        end

        local row = {
            player = p,
            tab = tab,
            role = role,
            suggested = suggested and true or false,
            reason = roleReason,
            readable = readable,
            unreadableReason = urReason,
            cells = cells,
            gaps = gaps,
            unknowns = unknowns,
            far = far,
            debuffCount = debuffCount,
            -- Class buffs are the BUFFER's duty, not the recipient's:
            -- whispering the player who lacks Arcane Intellect is
            -- pointless. Gaps on that tab go to the raid report,
            -- which already names slot + affected players. Debuffs are
            -- nobody's shopping list either: whisperEligible is ALWAYS
            -- false on DEBUFFS. The display tabs never produce gaps at
            -- all (gaps stays 0 there), but they are excluded explicitly
            -- too -- belt and suspenders, a display tab is never whisper
            -- bait.
            -- HIT is the one display tab a player CAN act on: being
            -- short of the hit cap is fixable by that player (gear,
            -- enchants, a weapon-skill book), unlike a resistance total.
            -- So it gets the whisper button, driven by belowCap instead
            -- of gaps -- RESIST stays silent.
            belowCap = belowCap,
            whisperEligible = readable
                and ((tab == "HIT" and belowCap > 0)
                     or (gaps > 0 and tab ~= "CLASSBUFFS"
                         and tab ~= "DEBUFFS"
                         and not M.IsDisplayTab(tab))),
        }
        -- last-known row flags: an EQUIPMENT row that is readable by
        -- the aura rule but whose gear could not be read (cross-continent
        -- inspect limit) -- the UI renders a row-spanning note instead of
        -- 13 bare "?" cells.
        --
        -- unreadNote states the OBSERVATION, not a guessed cause. It used
        -- to say "out of range", which named one possible reason as if it
        -- were measured: gearRead is false whenever not one of the 16
        -- inventory slots returned a link, and distance is only one way
        -- that happens (no SuperWoW, a failed inspect, a different
        -- continent). The measured distance is printed separately by the
        -- UI, so a reader still gets the range hypothesis -- as a number
        -- they can judge, not as a verdict.
        row.gearUnreadable = false
        if tab == "EQUIPMENT" and readable and not p.gearRead then
            row.gearUnreadable = true
        end
        if p.online == false then
            row.unreadNote = "offline"
        elseif row.gearUnreadable then
            -- SHORT on purpose: this lands in the small status chip next
            -- to the player's name, which has room for a few words. The
            -- reason it is not "out of range" is that distance is only
            -- ONE way the gear read comes back empty -- the full sentence
            -- lives in the row-spanning message and the cell tooltip,
            -- where there is space for it.
            row.unreadNote = "items not readable"
        end
        if readable and tab ~= "DEBUFFS" and not M.IsDisplayTab(tab) then
            -- Sums over determinate cells only: UNKNOWN is excluded from
            -- BOTH numbers (never condensed into sums).
            -- On DEBUFFS and the display tabs the sums stay NIL even for
            -- readable rows (warning signal / display tab, no x/y -- the
            -- sum column renders debuffCount or nothing instead).
            row.sumHas = has
            row.sumExpected = has + gaps
        end
        if not readable then
            row.sortBucket = 2
        elseif gaps > 0 then
            row.sortBucket = 1
        else
            row.sortBucket = 3
        end

        local g = groupsByRole[role]
        table.insert(g.rows, row)
        g.total = g.total + 1
        if readable then
            g.readable = g.readable + 1
            g.gaps = g.gaps + gaps
            g.debuffTotal = g.debuffTotal + (debuffCount or 0)
            -- ready = verified complete: readable, 0 gaps, 0 unknowns
            -- (an UNKNOWN cell never counts toward a green pill)
            if gaps == 0 and unknowns == 0 then
                g.ready = g.ready + 1
            end
        else
            g.unreadable = g.unreadable + 1
        end
    end

    for r = 1, nRoles do
        table.sort(groups[r].rows, rowLess)
    end
    for i = 1, nSlots do
        table.sort(footer[slots[i].id].names)
    end
    table.sort(unreadableNames)
    table.sort(unassignedNames)

    -- Display-tab averages (RESIST + HIT): computed straight off
    -- store.players, independent of row.readable (which tracks aura/
    -- online status -- resistance and hit readability are their own
    -- flags, player.resistsRead and player.hit.hitRead). nil on every
    -- other tab.
    -- Hit columns bring their own denominator per column: a cell that is
    -- not HAS -- an unreadable player, or the ranged column of a player
    -- without a ranged weapon -- is left OUT of the average instead of
    -- being counted as 0. classify() is re-run for those columns so the
    -- average can never drift away from the rendered cells (same trick as
    -- the last-known layer: one state machine).
    local colAvg, colCount, resistReadable, hitReadable
    if M.IsDisplayTab(tab) then
        colAvg = {}
        resistReadable = 0
        hitReadable = 0
        local sums, counts = {}, {}
        -- the DENOMINATOR each average was actually divided by, per
        -- column: it equals resistReadable for the five resistances, but
        -- the ranged hit column skips every NOTEXP player, so a report
        -- that printed hitReadable next to it would name a population the
        -- average never covered
        colCount = counts
        for i = 1, nPlayers do
            local p = players[i]
            if p.resistsRead then
                resistReadable = resistReadable + 1
            end
            local hitRead = (p.hit and p.hit.hitRead) and true or false
            if hitRead then
                hitReadable = hitReadable + 1
            end
            for si = 1, nSlots do
                local sd = slots[si]
                if sd.kind == "hit" then
                    if hitRead then
                        local hs, _, _, _, hv = M.classify(p, sd, true,
                            books and books[p.name] or nil)
                        if hs == S.HAS and hv then
                            sums[sd.id] = (sums[sd.id] or 0) + hv
                            counts[sd.id] = (counts[sd.id] or 0) + 1
                        end
                    end
                elseif p.resistsRead then
                    local v = (p.resists and p.resists[sd.school]) or 0
                    sums[sd.id] = (sums[sd.id] or 0) + v
                    counts[sd.id] = (counts[sd.id] or 0) + 1
                end
            end
        end
        for si = 1, nSlots do
            local sd = slots[si]
            local n = counts[sd.id] or 0
            if n <= 0 then
                colAvg[sd.id] = 0
            elseif sd.kind == "hit" then
                colAvg[sd.id] = M.RoundTenth((sums[sd.id] or 0) / n)
            else
                colAvg[sd.id] = math.floor((sums[sd.id] or 0) / n + 0.5)
            end
        end
    end

    return {
        coverage = coverage,
        slots = slots,
        groups = groups,
        footer = footer,
        unreadable = {
            count = coverage.offline + coverage.readfailed,
            names = unreadableNames,
        },
        unassigned = {
            count = table.getn(unassignedNames),
            names = unassignedNames,
        },
        -- distinct debuff names beyond the DEBUFF_CAP columns (0 outside
        -- the DEBUFFS tab); reportLines appends "+N more debuff types"
        debuffMore = debuffMore,
        -- DISPLAY tabs only (nil elsewhere): rounded average per column
        -- over the players who deliver that column -- resistance readers
        -- for the five schools, hit readers with a HAS cell for the hit
        -- columns -- plus the per-column denominator behind it and the
        -- two channel reader counts.
        colAvg = colAvg,
        colCount = colCount,
        -- aliases (the SAME tables, not copies) for readers written when
        -- the resistances were the only display tab
        resistAvg = colAvg,
        resistCount = colCount,
        resistReadable = resistReadable,
        hitReadable = hitReadable,
        tab = tab,
    }
end

-- ==================================================================
-- whisperText(rowVM, tabLabel, slots) -> string
-- Pure ASCII, plain "-" separator (not an
-- em dash): "DopingControl - missing before pull: Flask, Stamina/HP".
-- Slot order = column order. tabLabel is part of the fixed signature
-- but not of the output string (gap labels are self-explanatory).
-- ==================================================================
function M.whisperText(rowVM, tabLabel, slots)
    local parts = {}
    local n = table.getn(slots)
    -- HIT has no MISSING cells at all -- a number below its cap is
    -- information, not an unfilled slot. So it whispers the SHORTFALL,
    -- with both numbers: "Melee 5.0/8.0" says what to fix and how far,
    -- which a bare slot name could not.
    if rowVM.tab == "HIT" then
        for i = 1, n do
            local sd = slots[i]
            local c = rowVM.cells[sd.id]
            if c and c.cap and c.capMet == false and c.value
               and M.HitRelevant(rowVM.role, sd) then
                table.insert(parts, M.gapLabel(sd) .. " "
                    .. M.HitNum(c.value) .. "/" .. M.HitNum(c.cap))
            end
        end
        return "DopingControl - below the hit cap: "
            .. table.concat(parts, ", ")
    end
    for i = 1, n do
        local sd = slots[i]
        local c = rowVM.cells[sd.id]
        if c and c.state == DC.STATE.MISSING then
            table.insert(parts, M.gapLabel(sd))
        end
    end
    return "DopingControl - missing before pull: " .. table.concat(parts, ", ")
end

-- ==================================================================
-- reportLines(vm, tabLabel, timeStr) -> array of strings
-- Each line <= M.MAX_LINE chars; long name lists continue on
-- "  ... continued:" lines. Pure ASCII ("|" separators --
-- chat output never uses middle dots).
-- ==================================================================
local CONT_PREFIX = "  ... continued: "

local function emitNameList(lines, prefix, names)
    local cur = prefix
    local first = true
    local n = table.getn(names)
    for i = 1, n do
        local nm = names[i]
        if not first and
           string.len(cur) + 2 + string.len(nm) > M.MAX_LINE then
            table.insert(lines, cur)
            cur = CONT_PREFIX .. nm
        elseif first then
            cur = cur .. nm
            first = false
        else
            cur = cur .. ", " .. nm
        end
    end
    table.insert(lines, cur)
end

function M.reportLines(vm, tabLabel, timeStr)
    local lines = {}
    -- the tab's own channel count, not the aura one: the header names a
    -- tab, so the number behind it has to be that tab's (see
    -- M.ChannelRead). Falls back for hand-built vms from older callers.
    table.insert(lines, "DopingControl | " .. timeStr .. " | " .. tabLabel
        .. " | coverage "
        .. (vm.coverage.channelReadable or vm.coverage.readable)
        .. "/" .. vm.coverage.total)

    -- The display tabs are no expectation check -- no missing lists at
    -- all, one average line per column instead. Early return: the
    -- gap-oriented machinery below (order/footer/debuffMore) does not
    -- apply here.
    if M.IsDisplayTab(vm.tab) then
        if vm.tab == "HIT" then
            table.insert(lines, "Hit (average, readable players):")
        else
            table.insert(lines, "Resistances (average, readable players):")
        end
        local nSlots = table.getn(vm.slots)
        for i = 1, nSlots do
            local sd = vm.slots[i]
            local avg = (vm.colAvg and vm.colAvg[sd.id]) or 0
            -- hit columns print percent with one decimal; resistances
            -- print a plain integer
            local avgTxt
            if sd.kind == "hit" then
                avgTxt = M.HitText(avg) .. "%"
            else
                avgTxt = tostring(avg)
            end
            -- The count named here is the population the average was
            -- actually taken over, NOT the channel's reader count: the
            -- ranged hit column drops every player without a ranged
            -- weapon, so quoting the reader count would overstate it.
            local readers
            if vm.colCount and vm.colCount[sd.id] then
                readers = vm.colCount[sd.id]
            elseif sd.kind == "hit" then
                readers = vm.hitReadable or 0
            else
                readers = vm.resistReadable or 0
            end
            local noun = (readers == 1) and " player)" or " players)"
            table.insert(lines, "  " .. sd.full .. ": avg " .. avgTxt
                .. " (" .. readers .. noun)
        end
        if vm.unreadable and vm.unreadable.count > 0 then
            emitNameList(lines,
                "Not readable (" .. vm.unreadable.count .. "): ",
                vm.unreadable.names)
        end
        return lines
    end

    -- DEBUFFS is a warning list, not an expectation check
    -- -- its section header word is "Debuffs:"; the per-debuff name lists
    -- below stay exactly as they are. Expectation tabs keep the pinned
    -- "Missing per slot:".
    if vm.tab == "DEBUFFS" then
        table.insert(lines, "Debuffs:")
    else
        table.insert(lines, "Missing per slot:")
    end

    -- slots with gaps, sorted by count desc; ties keep column order
    local order = {}
    local nSlots = table.getn(vm.slots)
    for i = 1, nSlots do
        local sd = vm.slots[i]
        local f = vm.footer[sd.id]
        if f and f.count > 0 then
            table.insert(order, { sd = sd, f = f, idx = i })
        end
    end
    table.sort(order, function(a, b)
        if a.f.count ~= b.f.count then
            return a.f.count > b.f.count
        end
        return a.idx < b.idx
    end)

    local nOrder = table.getn(order)
    if nOrder == 0 then
        table.insert(lines, "  none")
    end
    for i = 1, nOrder do
        local e = order[i]
        emitNameList(lines,
            "  " .. M.gapLabel(e.sd) .. " (" .. e.f.count .. "): ", e.f.names)
    end

    -- "Not readable" is its OWN line; unreadable players never appear in
    -- the missing lists above (UNKNOWN is never counted as MISSING).
    if vm.unreadable and vm.unreadable.count > 0 then
        emitNameList(lines,
            "Not readable (" .. vm.unreadable.count .. "): ",
            vm.unreadable.names)
    end
    -- DEBUFFS column-cap overflow: the report's slot
    -- lines cover the capped columns; the overflow is appended as one
    -- line so the report never silently hides debuff types.
    if vm.debuffMore and vm.debuffMore > 0 then
        table.insert(lines, "+" .. vm.debuffMore .. " more debuff types")
    end
    return lines
end

-- ==================================================================
-- unknownBuffs(store) -> { [buffName] = count }
-- Aura names no data table knows (no silent discard);
-- count = number of readable players carrying the aura.
-- ==================================================================
function M.unknownBuffs(store)
    local out = {}
    local players = (store and store.players) or {}
    local n = table.getn(players)
    for i = 1, n do
        local p = players[i]
        if p.aurasRead and p.auras and p.auras.names then
            for name in pairs(p.auras.names) do
                local known = (DC.CONSUMABLES and DC.CONSUMABLES[name])
                    or (DC.CLASSBUFFS and DC.CLASSBUFFS[name])
                if not known then
                    out[name] = (out[name] or 0) + 1
                end
            end
        end
    end
    return out
end
