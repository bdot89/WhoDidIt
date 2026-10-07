if WDI_DOPING_SKIP then return end -- DopingControl scan/hit.lua
-- Hit reading for one unit: the +hit percentages an equipped set of items
-- grants, plus the weapon information the hit CAPS depend on.
--
-- There is no hit API on this client family (see data/hit.lua) -- every
-- number here is summed from item TOOLTIP text. The read path is
-- GameTooltip:SetInventoryItem(unit, slot) on the SHARED hidden tooltip
-- (scan/aura.lua's DC_Aura.GetScanTip -- never a second frame under the
-- same global name), NOT SetHyperlink: SetInventoryItem shows the item as
-- it is actually worn (temporary weapon enchants included) and sidesteps
-- item-link edge cases entirely.
--
-- Performance (this is the expensive part of a scan -- one tooltip build
-- per equipped item per player):
--   * slots without an item link are skipped without touching the tooltip;
--   * nothing beyond the equipment slots is ever scanned;
--   * the parsed result of an item is CACHED by item id + enchant id, so
--     the second player wearing the same epic costs one table lookup. The
--     cache lives in memory only (never saved to disk), and a cap-safety
--     wipe keeps it bounded -- it is a pure accelerator, so a wipe only
--     costs one re-scan;
--   * the caller can hand in the item links scan/gear.lua already fetched
--     for this unit, which removes a second GetInventoryItemLink pass.
--
-- WHAT IS COUNTED, and how:
--   * PER ITEM: lines that start with the equip trigger ("Equip: Improves
--     your chance to hit by 1%").
--   * PER SET: set bonuses, counted ONCE for the whole set and only when
--     the piece threshold is met (H.CollectSet / H.SumSets). The set block
--     is printed on the tooltip of EVERY piece, which is why a per-item
--     sum would multiply it -- but the block also names the set, the worn
--     piece count and each bonus's threshold, so grouping by set is all
--     that is needed. The worn count comes from OUR OWN tally of the
--     player's pieces, never from a cached tooltip's "(x/y)": that number
--     belongs to whichever unit the tooltip was drawn for.
--
-- Store shape produced BY THIS MODULE'S ReadUnit (players[i].hit, before
-- scan/engine.lua's BuildPlayer augments it with hit-granting auras --
-- see AuraHit below and BuildPlayer's own header comment):
--   { melee = <number>,   -- generic physical hit % from GEAR (melee AND
--                         -- ranged); BuildPlayer folds DC.HIT_AURAS on top
--                         -- and turns this into the melee-column TOTAL
--     spell = <number>,   -- general spell hit % from GEAR; BuildPlayer
--                         -- folds auras on top the same way
--     schools = { [school] = <number> },  -- school-only spell hit extras
--     sources = { { item = <name|nil>, kind = , value = }, ... },
--     mainSub = <itemSubType|nil>,   -- main hand
--     offSub  = <itemSubType|nil>,   -- off hand
--     rangedSub = <itemSubType|nil>, -- ranged slot
--     skillName = <weapon skill of the main hand|nil>,
--     skill = <number|nil>,      -- main-hand weapon skill: MEASURED for
--                                -- the own character, otherwise the
--                                -- estimate H.ApplyEstimate filled in
--     skillExact = <true|nil>,   -- true only when `skill` was MEASURED
--     book = <bool|nil>,         -- a skill book was ASSUMED (never on a
--                                -- measured skill)
--     rangedSkill = <number|nil>,      -- same for the ranged weapon
--     rangedSkillExact = <true|nil>,
--     hitRead = <bool> }
-- Readability rule (mirrors scan/gear.lua): ANY slot returned a link =>
-- hitRead = true; ALL slots nil => hitRead = false (a failed read, not "a
-- naked player"). Unlike the aura/gear channels the table rides into the
-- store EVEN WHEN hitRead is false, because the flag lives inside it --
-- every consumer must test hit.hitRead before believing the zeros.
--
-- Weapon skill: MEASURED for the own character (H.ReadSelfSkill ->
-- hit.skill + hit.skillExact), ESTIMATED for everyone else -- foreign
-- weapon skill is unreadable in principle (no inspect-skill channel
-- exists). The estimate is deliberately NOT baked into the store: it
-- depends on the user's per-player weapon-skill-book flags, and baking it
-- in would freeze those flags until the next scan. Consumers resolve it at
-- display time:
--     local skill = hit.skillExact and hit.skill
--         or DC_Hit.SkillFor(hit.mainSub, player.race,
--                            db.skillBooks and db.skillBooks[player.name])
-- (player.race is the race token the scan stored alongside the hit table.)
--
-- TALENTS are the third source (gear, auras, talents). GetTalentInfo has
-- no unit parameter, so ranks come from two places that must produce the
-- SAME shape:
--   * H.TalentHit is PURE (class token + learned ranks -> the four
--     buckets and the school extras, see data/talenthit.lua) and is
--     offline-tested like the rest of the pure half;
--   * H.ReadSelfTalents (WoW glue) reads the ranks for the own character;
--   * for every other player scan/talents.lua asks over the server's own
--     inspect protocol and hands the same name->rank table to H.TalentHit.
--     Until a reply arrives that player keeps hit.talentsRead = false and
--     zeroed talent fields, and every consumer must say so -- their number
--     EXCLUDES talents, which for a hybrid or a mage is easily 3-10%.
-- The talent fields the engine adds on top of this module's store shape:
--   talentMelee / talentRanged / talentSpell / talentOffhand (numbers),
--   talentSchools ({ [lowercase school] = number }), talentsRead (bool).
--
-- Pure Lua 5.0, dofile-loadable offline: ParseHitLine / SumGear / AddSum /
-- IsHitSourceLine / SkillFor / MeleeCap / RangedCap / DualWield /
-- TalentHit / SchoolHit are pure (offline tested); ReadUnit,
-- ReadSelfSkill and ReadSelfTalents touch the WoW API and run in-game
-- only, pcall-wrapped.
--
-- RESIST-TAB REUSE (added 2026-08-02, see scan/resist.lua's header for the
-- full rationale): the server never transmits UNIT_FIELD_RESISTANCES for a
-- foreign player at all, so scan/engine.lua's three direct read paths can
-- NEVER answer for anyone but the own character -- reconstruction from
-- equipped-item tooltips is the only path that can. Rather than run a
-- second per-item tooltip scan for that, itemHit() below hands the SAME
-- tooltip lines it already fetched for +hit to DC_Resist.SumLines (pure,
-- scan/resist.lua) and caches the result alongside the hit sum; H.ReadUnit
-- accumulates it into hit.resistGear/hit.resistGearRead the same way it
-- accumulates hit.melee/hit.spell. Zero extra SetInventoryItem calls.
-- hit.resistGearRead is the STRICT honesty flag scan/engine.lua's
-- gear-reconstruction fallback requires: true only when at least one
-- equipped item's tooltip was ACTUALLY read (H.SumItemResists), never
-- merely "a link existed" (hit.hitRead's looser bar) -- a player whose
-- tooltips are wholly unreadable must keep showing "?" on RESIST, not a
-- reconstructed 0. DC_Resist is existence-guarded throughout, so this
-- module works unchanged without it (resistGearRead simply stays false).

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Hit = DC_Hit or {}
local H = DC_Hit

-- Equipment slots that can carry +hit, in inventory-slot order. This is
-- deliberately its OWN list and not DC_Gear.InvSlots(): the two lists
-- happen to agree today (both cover the waist, invSlot 6 -- see
-- data/enchants.lua's bug-history note), but this file must not assume
-- that stays true, so it keeps every hit-bearing slot spelled out here.
-- Shirt (4) and tabard (19) never carry stats and are left out.
H.SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

H.SLOT_MAIN   = 16
H.SLOT_OFF    = 17
H.SLOT_RANGED = 18

-- Hard cap for the per-item parse cache (in memory only, see header).
H.CACHE_CAP = 300

-- Hard cap for the per-player breakdown list (tooltip detail only -- no
-- realistic set of gear reaches it; the cap exists so a broken tooltip
-- cannot grow the store without bound).
H.SOURCE_CAP = 16

-- ==================================================================
-- Pure part
-- ==================================================================

-- round to one decimal (0.2 is not representable in binary floating point,
-- so 8 - 3*0.2 lands at 7.399999...; every cap leaves this function)
local function round1(v)
    return math.floor(v * 10 + 0.5) / 10
end

-- ParseHitLine(text) -> kind, value | nil
--   kind  : "melee" | "spell" | "both" | <school name> (see DC.HIT_PATTERNS)
--   value : the percentage as a number
-- Returns nil (a single value) when no pattern matches -- an unknown
-- phrasing is ignored, never guessed at.
function H.ParseHitLine(text)
    if type(text) ~= "string" then
        return nil
    end
    local pats = DC.HIT_PATTERNS
    if type(pats) ~= "table" then
        return nil
    end
    local n = table.getn(pats)
    for i = 1, n do
        local e = pats[i]
        local _, _, cap = string.find(text, e.pattern)
        if cap then
            local v = tonumber(cap)
            if v then
                return e.kind, v
            end
        end
    end
    return nil
end

-- IsHitSourceLine(text) -> bool
-- The gate that separates PER-ITEM hit from SET-BONUS hit: only a line
-- carrying the equip trigger is a per-item hit source. A set-bonus line
-- ("(2) Set: Improves your chance to hit by 2%") is printed on EVERY piece
-- of the set, so adding it per item would multiply it.
--
-- That is a reason to count set bonuses ONCE PER SET, not a reason to drop
-- them -- see H.CollectSet / H.SumSets below. The Devilsaur two-piece
-- bonus is +2% hit; leaving it out understates hit by more than most
-- enchants add.
function H.IsHitSourceLine(text)
    if type(text) ~= "string" then
        return false
    end
    if string.find(text, "^Equip:") then
        return true
    end
    return false
end

-- AddSum(dst, add) -> dst -- fold one hit sum into another (in place).
-- Only the three hit fields are touched, so it can be applied directly to
-- a store hit table that carries weapon/readability fields as well.
function H.AddSum(dst, add)
    if type(dst) ~= "table" or type(add) ~= "table" then
        return dst
    end
    dst.melee = (dst.melee or 0) + (add.melee or 0)
    dst.spell = (dst.spell or 0) + (add.spell or 0)
    if add.schools then
        dst.schools = dst.schools or {}
        for school, v in pairs(add.schools) do
            dst.schools[school] = (dst.schools[school] or 0) + v
        end
    end
    return dst
end

-- SumItemResists(items) -> resistGear, resistGearRead
--   items : array of the itemHit() cache entries collected while walking
--           H.SLOTS for ONE unit -- one entry per slot whose tooltip was
--           SUCCESSFULLY read (a slot with no item, or whose tooltip read
--           failed, contributes no entry at all -- see H.ReadUnit).
--   resistGear     : { [UnitResistance school index] = total } summed
--                     over every entry's .resist table (itself possibly
--                     {} for a plain item -- see DC_Resist.SumLines). A
--                     school with no contribution is simply absent, not
--                     zero -- callers default with `or 0`, same as every
--                     other resist table in this addon.
--   resistGearRead : true iff AT LEAST ONE entry carried a .resist table
--                     (i.e. its tooltip was actually read, whether or not
--                     that item happened to grant any resistance).
--                     FALSE means every equipped item's tooltip failed --
--                     the exact scan/hit.lua-documented failure mode
--                     (SetOwner missing on the scan tooltip, or the unit
--                     simply out of tooltip range) -- and the caller MUST
--                     show "?", never a reconstructed 0. This is the
--                     honesty gate scan/engine.lua's AssembleResists
--                     gear-fallback checks before trusting resistGear at
--                     all.
-- `.resist` being nil on every entry (DC_Resist not loaded, see the file
-- header) degrades the same way: nothing is ever marked read, so the
-- fallback simply never activates -- no module, no reconstruction, never a
-- guess.
function H.SumItemResists(items)
    local sum = {}
    local read = false
    items = items or {}
    local n = table.getn(items)
    for i = 1, n do
        local it = items[i]
        if it and it.resist then
            read = true
            for school, v in pairs(it.resist) do
                sum[school] = (sum[school] or 0) + v
            end
        end
    end
    return sum, read
end

-- SumGear(lines) -> sum, sources
--   lines : array of raw tooltip line strings (already gated by
--           IsHitSourceLine when they come from an item scan)
--   sum   : { melee = <number>, spell = <number>, schools = { ... } }
--   sources : array of { kind = , value = } in line order -- the
--           breakdown a tooltip shows; the caller attaches the item name.
-- Folding rules (see DC.HIT_PATTERNS): "both" counts into melee AND
-- spell; a school-specific line counts ONLY into schools[<school>], never
-- into the general spell number -- it buys hit against one school only.
-- Lines that parse to nothing are ignored.
function H.SumGear(lines)
    local sum = { melee = 0, spell = 0, schools = {} }
    local sources = {}
    lines = lines or {}
    local n = table.getn(lines)
    for i = 1, n do
        local kind, v = H.ParseHitLine(lines[i])
        if kind then
            if kind == "melee" then
                sum.melee = sum.melee + v
            elseif kind == "spell" then
                sum.spell = sum.spell + v
            elseif kind == "both" then
                sum.melee = sum.melee + v
                sum.spell = sum.spell + v
            else
                sum.schools[kind] = (sum.schools[kind] or 0) + v
            end
            table.insert(sources, { kind = kind, value = v })
        end
    end
    return sum, sources
end

-- ------------------------------------------------------------------
-- SET BONUSES
--
-- Shape of the set block in an item tooltip:
--
--   L10 gold  "Devilsaur Armor (0/2)"                      <- ITEM_SET_NAME
--   L11 grey  "  Devilsaur Leggings"                       <- piece list
--   L14 grey  "(2) Set: Improves your chance to hit by 2%." <- ITEM_SET_BONUS_GRAY
--
-- So the client states both halves itself: how many pieces are worn, and
-- what each bonus costs. The 1.12 GlobalStrings confirm the two forms --
-- ITEM_SET_BONUS_GRAY = "(%d) Set: %s" for a bonus that is NOT active and
-- ITEM_SET_BONUS = "Set: %s" for one that IS.
--
-- Counting rule: group by SET NAME, count each bonus at most ONCE, and
-- take it only when its piece threshold is met. The worn count is taken
-- from OUR OWN tally of the player's equipped pieces, never from the
-- "(x/y)" of a cached tooltip -- that number belongs to whichever unit was
-- scanned when the item entered the cache and would otherwise leak between
-- players.
-- ------------------------------------------------------------------

-- ParseSetHeader(text) -> name, worn, total | nil
-- The gold "<Set name> (x/y)" line that opens the set block.
function H.ParseSetHeader(text)
    if type(text) ~= "string" then
        return nil
    end
    local _, _, name, worn, total =
        string.find(text, "^(.+) %((%d+)/(%d+)%)%s*$")
    if not name then
        return nil
    end
    return name, tonumber(worn), tonumber(total)
end

-- ParseSetBonus(text) -> threshold|nil, body | nil
-- "(2) Set: <body>"  -> 2, <body>     (inactive form, ITEM_SET_BONUS_GRAY)
-- "Set: <body>"      -> nil, <body>   (ACTIVE form, ITEM_SET_BONUS)
-- Anything else      -> nil
-- A nil threshold with a body is NOT "no threshold" -- it means the client
-- already decided the bonus is active for the unit it drew the tooltip
-- for, which is why such an entry must not be cached across players.
function H.ParseSetBonus(text)
    if type(text) ~= "string" then
        return nil
    end
    local _, _, n, body = string.find(text, "^%((%d+)%) Set: (.+)$")
    if n then
        return tonumber(n), body
    end
    local _, _, body2 = string.find(text, "^Set: (.+)$")
    if body2 then
        return nil, body2
    end
    return nil
end

-- CollectSet(lines) -> { name, worn, total, bonuses = { {n=, text=} },
--                        contextual = <bool> } | nil
-- Reads the set block out of ONE item's tooltip lines. `contextual` marks
-- a block that carries at least one active-form line, i.e. one whose
-- meaning depends on the unit the tooltip was drawn for -- the caller must
-- not cache those.
function H.CollectSet(lines)
    if type(lines) ~= "table" then
        return nil
    end
    local set = nil
    for i = 1, table.getn(lines) do
        local text = lines[i]
        if not set then
            local name, worn, total = H.ParseSetHeader(text)
            if name then
                set = { name = name, worn = worn, total = total,
                        bonuses = {}, contextual = false }
            end
        else
            local n, body = H.ParseSetBonus(text)
            if body then
                if not n then
                    set.contextual = true
                end
                table.insert(set.bonuses, { n = n, text = body })
            end
        end
    end
    return set
end

-- SumSets(sets) -> sum, sources
--   sets : { [setName] = { pieces = <how many the player wears>,
--                          bonuses = { {n=, text=} } } }
-- Each bonus contributes AT MOST ONCE, and only when the player wears
-- enough pieces. A bonus with no threshold (active form) is taken as met:
-- the client only prints it that way once it applies.
function H.SumSets(sets)
    local sum = { melee = 0, spell = 0, schools = {} }
    local sources = {}
    if type(sets) ~= "table" then
        return sum, sources
    end
    -- deterministic order: sets are keyed by name, and two sets granting
    -- hit must not swap places in the tooltip between two scans
    local names = {}
    for name in pairs(sets) do
        table.insert(names, name)
    end
    table.sort(names)
    for i = 1, table.getn(names) do
        local name = names[i]
        local s = sets[name]
        local pieces = (s and s.pieces) or 0
        local bonuses = (s and s.bonuses) or {}
        local seen = {}
        for b = 1, table.getn(bonuses) do
            local bonus = bonuses[b]
            local met = (bonus.n == nil) or (pieces >= bonus.n)
            -- the same bonus text can arrive from several pieces of the
            -- set; key on it so it lands in the sum exactly once
            if met and not seen[bonus.text] then
                seen[bonus.text] = true
                local kind, v = H.ParseHitLine(bonus.text)
                if kind then
                    if kind == "melee" then
                        sum.melee = sum.melee + v
                    elseif kind == "spell" then
                        sum.spell = sum.spell + v
                    elseif kind == "both" then
                        sum.melee = sum.melee + v
                        sum.spell = sum.spell + v
                    else
                        sum.schools[kind] = (sum.schools[kind] or 0) + v
                    end
                    table.insert(sources, { kind = kind, value = v,
                        set = name, pieces = bonus.n or pieces })
                end
            end
        end
    end
    return sum, sources
end

-- SkillFor(subType, race, books) -> skill, skillName | nil
-- The ESTIMATE for a foreign player's weapon skill:
--   base (level-60 cap) + racial specialization + weapon skill book.
-- `books` is one player's opt-in flag table (db.skillBooks[playerName]),
-- keyed by weapon SKILL name; nil is fine. Returns nil when the subtype is
-- not a weapon at all (shield, totem, nothing equipped) -- the caller then
-- has no skill claim to make.
-- The own character never needs this: its skill is measured
-- (H.ReadSelfSkill) and a measured value already includes any book.
function H.SkillFor(subType, race, books)
    local map = DC.WEAPON_SKILL_OF_SUBTYPE
    local skillName = map and map[subType]
    if not skillName then
        return nil
    end
    local skill = DC.BASE_WEAPON_SKILL or 300
    local byRace = DC.RACE_WEAPON_SKILL
    local racial = race and byRace and byRace[race]
    if racial and racial[skillName] then
        skill = skill + racial[skillName]
    end
    if books and books[skillName] then
        skill = skill + (DC.SKILL_BOOK_BONUS or 0)
    end
    return skill, skillName
end

-- ApplyEstimate(hit, race, books) -> hit (in place)
-- Fills the weapon-skill fields a display layer needs for a player whose
-- skill could NOT be measured -- which is everyone except the own
-- character (foreign weapon skill is unreadable in principle):
--   hit.skill       main-hand weapon skill estimate (base + racial + book)
--   hit.book        true when a weapon skill book was ASSUMED for the
--                   main-hand skill (false whenever the skill is measured
--                   -- a measured value already contains the book)
--   hit.rangedSkill same estimate for the ranged weapon's own skill line
-- A MEASURED value (skillExact / rangedSkillExact) is never overwritten.
-- `books` is one player's flag table, db.skillBooks[playerName]; nil-safe.
--
-- Note for consumers: this is a SNAPSHOT taken when the unit was scanned.
-- Toggling a book flag afterwards does not travel back into the store, so
-- a display layer that wants the flag to take effect immediately should
-- recompute with H.SkillFor(hit.mainSub, player.race, books) whenever
-- hit.skillExact is not set.
function H.ApplyEstimate(hit, race, books)
    if type(hit) ~= "table" then
        return hit
    end
    if not hit.skillExact then
        local skill = H.SkillFor(hit.mainSub, race, books)
        if skill then
            hit.skill = skill
        end
        hit.book = (hit.skillName and books and books[hit.skillName] and true)
            or false
    else
        hit.book = false
    end
    if not hit.rangedSkillExact then
        local rskill = H.SkillFor(hit.rangedSub, race, books)
        if rskill then
            hit.rangedSkill = rskill
        end
    end
    return hit
end

-- AuraHit(auraNames) -> { melee = , ranged = , spell = }
-- The hit granted by AURAS (DC.HIT_AURAS, data/hit.lua) rather than gear.
-- auraNames : player.auras.names ({[name]=true,...}, nil-safe) -- the SAME
--   aura scan the class-buff tab already reads; no second scan needed.
-- Sums every DC.HIT_AURAS entry whose name is present in auraNames. A
-- hit-granting aura may bump any subset of the three columns (e.g. a
-- spell-only buff) -- absent fields on an entry default to 0, never nil,
-- so the caller can always add the result straight onto a gear sum.
function H.AuraHit(auraNames)
    local sum = { melee = 0, ranged = 0, spell = 0 }
    local auras = DC.HIT_AURAS
    if type(auraNames) ~= "table" or type(auras) ~= "table" then
        return sum
    end
    for name, entry in pairs(auras) do
        if auraNames[name] then
            sum.melee = sum.melee + (entry.melee or 0)
            sum.ranged = sum.ranged + (entry.ranged or 0)
            sum.spell = sum.spell + (entry.spell or 0)
        end
    end
    return sum
end

-- rankValue(arr, rank) -- the per-rank value of one talent bucket.
-- A rank ABOVE the listed count means the table is stale (a tree was
-- rebalanced and the talent gained a rank): it clamps to the highest
-- KNOWN value, which under-reports rather than extrapolating a number
-- nobody verified. Rank 0 / no such bucket contribute nothing.
local function rankValue(arr, rank)
    if type(arr) ~= "table" or not rank or rank < 1 then
        return 0
    end
    local n = table.getn(arr)
    if n < 1 then
        return 0
    end
    if rank > n then
        rank = n
    end
    return arr[rank] or 0
end

-- DualWield(mainSub, offSub) -> bool
-- Both hands hold something that maps to a WEAPON skill. A shield, totem,
-- idol, libram or held-in-off-hand item is not dual wielding -- that is
-- exactly what the gaps in DC.WEAPON_SKILL_OF_SUBTYPE encode.
function H.DualWield(mainSub, offSub)
    local map = DC.WEAPON_SKILL_OF_SUBTYPE or {}
    return (map[mainSub] ~= nil) and (map[offSub] ~= nil)
end

-- TalentHit(classToken, learnedRanks, dualWield)
--   -> { melee = , ranged = , spell = , offhand = , schools = { ... } }
--   classToken   : UnitClass file token ("MAGE", "WARRIOR", ...)
--   learnedRanks : { [talent name] = rank } -- what H.ReadSelfTalents
--                  returns; matching is BY NAME (see data/talenthit.lua)
--   dualWield    : true while two WEAPONS are equipped (H.DualWield) --
--                  gates the hunter's dual-wield-only extra
-- Every field is a number and `schools` is always a table, so the result
-- can be added onto a hit table without nil checks. An unknown class, a
-- nil rank table or a class with no hit talents all yield clean zeros --
-- which is also what a player whose talents have not arrived yet gets.
-- `offhand` is returned SEPARATELY and never folded into `melee`: it buys
-- hit for off-hand swings only.
function H.TalentHit(classToken, learnedRanks, dualWield)
    local sum = { melee = 0, ranged = 0, spell = 0, offhand = 0, schools = {} }
    local byClass = DC.TALENT_HIT
    if type(byClass) ~= "table" or type(learnedRanks) ~= "table" then
        return sum
    end
    local list = classToken and byClass[classToken]
    if type(list) ~= "table" then
        return sum
    end
    local n = table.getn(list)
    for i = 1, n do
        local t = list[i]
        local rank = nil
        if type(t) == "table" and t.name then
            rank = tonumber(learnedRanks[t.name])
        end
        if rank and rank > 0 then
            sum.melee = sum.melee + rankValue(t.melee, rank)
            sum.ranged = sum.ranged + rankValue(t.ranged, rank)
            sum.spell = sum.spell + rankValue(t.spell, rank)
            sum.offhand = sum.offhand + rankValue(t.offhand, rank)
            if dualWield then
                sum.melee = sum.melee + rankValue(t.dwExtra, rank)
            end
            if type(t.schools) == "table" then
                for school, arr in pairs(t.schools) do
                    sum.schools[school] = (sum.schools[school] or 0)
                        + rankValue(arr, rank)
                end
            end
        end
    end
    return sum
end

-- SchoolHit(hit, school) -> total, generic, specific
-- What ONE school column of the HIT tab is worth for this player:
--   generic  : spell hit that helps EVERY school (hit.spell -- gear, auras
--              and generic talents, already summed by the engine)
--   specific : what only THIS school gets -- the gear affix parsed from
--              tooltips plus the school-specific talents
--   total    : the number the column shows
-- `school` may be given in either spelling: the lowercase column id
-- ("fire", DC.SLOTS_HIT) or the capitalized tooltip word ("Fire",
-- DC.HIT_SCHOOLS). The two live side by side because they come from two
-- different sources; DC.HIT_SCHOOL_KEY bridges them (data/hit.lua).
-- Note the input: `hit` is a STORE hit table (after scan/engine.lua's
-- BuildPlayer folded auras and talents in). Handing in the raw table
-- scan/hit.lua's ReadUnit returns yields the gear-only picture, which is
-- correct but is not what a cell should display.
function H.SchoolHit(hit, school)
    if type(hit) ~= "table" then
        return 0, 0, 0
    end
    local generic = hit.spell or 0
    if type(school) ~= "string" then
        return generic, generic, 0
    end
    local lower = string.lower(school)
    local gearKey = (DC.HIT_SCHOOL_KEY and DC.HIT_SCHOOL_KEY[lower]) or school
    local specific = 0
    if type(hit.schools) == "table" then
        specific = specific + (hit.schools[gearKey] or 0)
    end
    if type(hit.talentSchools) == "table" then
        specific = specific + (hit.talentSchools[lower] or 0)
    end
    return generic + specific, generic, specific
end

-- capFor(base, skill) -- linear weapon-skill scaling: every point above
-- the base skill lowers the cap by DC.CAP_PER_SKILL, never below zero.
local function capFor(base, skill)
    local baseSkill = DC.BASE_WEAPON_SKILL or 300
    local extra = (skill or baseSkill) - baseSkill
    if extra < 0 then
        extra = 0
    end
    local v = (base or 0) - extra * (DC.CAP_PER_SKILL or 0)
    if v < 0 then
        v = 0
    end
    return round1(v)
end

-- MeleeCap(mainSub, offSub, skill, capTable)
--   -> { yellow = , white = , dualWield = , skillName = }
--   mainSub/offSub : GetItemInfo itemSubType of the two weapon slots
--   skill          : effective weapon skill (measured or estimated);
--                    nil falls back to the base skill
--   capTable       : DC.HIT_CAPS by default
-- yellow  = cap for special attacks.
-- white   = cap for auto attacks: the dual-wield cap while two WEAPONS are
--           held, otherwise identical to yellow (a single weapon's white
--           swings carry no dual-wield penalty).
-- dualWield = both hands hold something that maps to a weapon skill -- a
--           shield/totem/held-in-off-hand off hand is not dual wielding.
-- skillName = weapon skill of the MAIN hand, nil when it is unknown or
--           empty (bare fists are the caller's business, see ReadUnit).
function H.MeleeCap(mainSub, offSub, skill, capTable)
    capTable = capTable or DC.HIT_CAPS or {}
    local map = DC.WEAPON_SKILL_OF_SUBTYPE or {}
    local skillName = map[mainSub]
    local dualWield = H.DualWield(mainSub, offSub)
    local yellow = capFor(capTable.meleeYellow, skill)
    local white = yellow
    if dualWield then
        white = capFor(capTable.meleeWhiteDW, skill)
    end
    return { yellow = yellow, white = white, dualWield = dualWield,
        skillName = skillName }
end

-- RangedCap(rangedSub, skill, capTable) -> { cap = , skillName = } | nil
-- nil means "this player has no ranged hit question": nothing in the
-- ranged slot, or a relic/wand rather than a ranged ATTACK weapon (see
-- DC.RANGED_ATTACK_SUBTYPE -- wand mechanics are disputed, so wands never
-- drive this column).
-- `skill` is the skill of the RANGED weapon (bows/guns/crossbows/thrown
-- each have their own skill line), not the main hand's.
function H.RangedCap(rangedSub, skill, capTable)
    capTable = capTable or DC.HIT_CAPS or {}
    local ranged = DC.RANGED_ATTACK_SUBTYPE or {}
    if not rangedSub or not ranged[rangedSub] then
        return nil
    end
    local map = DC.WEAPON_SKILL_OF_SUBTYPE or {}
    return { cap = capFor(capTable.ranged, skill), skillName = map[rangedSub] }
end

-- ==================================================================
-- WoW part (runtime only; every call pcall-wrapped)
-- ==================================================================

-- The shared hidden tooltip's global name -- the line FontStrings are read
-- back as getglobal("<name>TextLeft<i>"), so the name must match the frame
-- created in scan/aura.lua.
local TIP_NAME = "DopingControlScanTip"

-- per-item parse cache, [itemId:enchantId] = { sum, sources, name }
local itemCache = {}
local itemCacheSize = 0

-- ClearCache() -- in-memory cache reset (cap safety, and a handy manual
-- reset when item tooltips changed under us).
function H.ClearCache()
    itemCache = {}
    itemCacheSize = 0
end

function H.CacheSize()
    return itemCacheSize
end

-- read all left-hand tooltip lines of one equipped item; nil on failure
local function scanItemLines(unit, slot)
    local tip = DC_Aura and DC_Aura.GetScanTip and DC_Aura.GetScanTip()
    if not tip then
        return nil
    end
    local ok = pcall(function()
        tip:ClearLines()
        tip:SetInventoryItem(unit, slot)
    end)
    if not ok then
        return nil
    end
    local n = 30
    if tip.NumLines then
        local ok2, v = pcall(tip.NumLines, tip)
        if ok2 and type(v) == "number" then
            n = v
        end
    end
    local lines = {}
    for i = 1, n do
        local obj = getglobal(TIP_NAME .. "TextLeft" .. i)
        if obj then
            local text = obj:GetText()
            if text then
                table.insert(lines, text)
            end
        end
    end
    return lines
end

-- parse ONE equipped item -> { sum, sources, name, set } (cached by item
-- id + enchant id). Random suffixes are not part of the key on purpose: no
-- 1.12 suffix grants hit, and a temporary weapon enchant cannot either --
-- the key stays cheap.
--
-- `set` is the item's set block (H.CollectSet). It is item data and caches
-- fine -- EXCEPT when it contains an active-form bonus line, which the
-- client only prints for a unit that already wears enough pieces. Such an
-- entry describes the unit, not the item, so it is returned but never
-- stored: the next player re-reads the tooltip and gets their own truth.
local function itemHit(unit, slot, itemId, enchantId)
    local key = tostring(itemId) .. ":" .. tostring(enchantId)
    local hitEntry = itemCache[key]
    if hitEntry then
        return hitEntry
    end
    local lines = scanItemLines(unit, slot)
    if not lines then
        return nil          -- unreadable tooltip: do NOT cache a zero
    end
    local keep = {}
    -- line 1 is the item name, never a stat line
    for i = 2, table.getn(lines) do
        if H.IsHitSourceLine(lines[i]) then
            table.insert(keep, lines[i])
        end
    end
    local sum, sources = H.SumGear(keep)
    local set = H.CollectSet(lines)
    -- RESIST tab reuse (see file header addendum): the FULL lines array
    -- this pass already fetched for +hit is handed to DC_Resist's pure
    -- parser for resistance stats -- one more in-memory table walk, no
    -- extra SetInventoryItem call. Resistance lines are plain stat text
    -- (no "Equip:" trigger, unlike +hit -- see data/resist.lua), so `lines`
    -- is passed unfiltered rather than `keep`. Existence-guarded: without
    -- scan/resist.lua loaded, `resist` stays nil and H.SumItemResists
    -- treats this item as "not scanned for resist" (never a guessed zero).
    local resist = nil
    if DC_Resist and DC_Resist.SumLines then
        resist = DC_Resist.SumLines(lines)
    end
    hitEntry = { sum = sum, sources = sources, name = lines[1], set = set,
        resist = resist }
    if set and set.contextual then
        return hitEntry     -- unit-specific: use it, never cache it
    end
    if itemCacheSize >= H.CACHE_CAP then
        -- cap-safety wipe: the cache is a pure accelerator, a reset only
        -- costs one re-scan (no correctness meaning, no eviction order)
        H.ClearCache()
    end
    itemCache[key] = hitEntry
    itemCacheSize = itemCacheSize + 1
    return hitEntry
end

-- ReadSelfSkill(skillName) -> effective, rank, modifier | nil
-- The own character's MEASURED weapon skill: rank (4th return of
-- GetSkillLineInfo) plus its modifier (6th return), which is how a
-- temporary or permanent skill bonus shows up.
-- Gotcha: a COLLAPSED skill category is not enumerated by
-- GetNumSkillLines/GetSkillLineInfo. We deliberately do NOT expand
-- categories (that would change the player's skill window); an
-- unenumerable skill simply comes back nil and the caller falls back to
-- the estimate.
function H.ReadSelfSkill(skillName)
    if not skillName or not GetNumSkillLines or not GetSkillLineInfo then
        return nil
    end
    local okN, n = pcall(GetNumSkillLines)
    if not okN or type(n) ~= "number" then
        return nil
    end
    for i = 1, n do
        local ok, name, isHeader, isExpanded, rank, numTemp, modifier =
            pcall(GetSkillLineInfo, i)
        if ok and not isHeader and name == skillName then
            local base = tonumber(rank) or 0
            local mod = tonumber(modifier) or 0
            return base + mod, base, mod
        end
    end
    return nil
end

-- ReadSelfTalents() -> { [talent name] = rank } | nil
-- The OWN character's learned talent ranks, walked as
-- GetNumTalentTabs -> GetNumTalents(tab) -> GetTalentInfo(tab, i).
-- GetTalentInfo takes no unit, so this function is only ever called for
-- the own character; other players' ranks arrive over the protocol in
-- scan/talents.lua and are handed to the same DC_Hit.TalentHit.
--
-- nil vs empty table is the load-bearing distinction:
--   nil   the API is absent or enumerated nothing at all (talent data not
--         available yet) -> the caller must report talents as UNREAD
--   {}    the enumeration worked and the character has spent no points ->
--         a MEASURED zero
-- Only ranks above 0 are stored, so the table stays small and a lookup
-- miss is indistinguishable from "not learned", which is what it means.
function H.ReadSelfTalents()
    if not GetNumTalentTabs or not GetNumTalents or not GetTalentInfo then
        return nil
    end
    local okT, tabs = pcall(GetNumTalentTabs)
    if not okT or type(tabs) ~= "number" then
        return nil
    end
    local ranks = {}
    local enumerated = false
    for tab = 1, tabs do
        local okN, n = pcall(GetNumTalents, tab)
        if okN and type(n) == "number" then
            for i = 1, n do
                -- 1.12: name, iconTexture, tier, column, rank, maxRank, ...
                local ok, name, _, _, _, rank = pcall(GetTalentInfo, tab, i)
                if ok and type(name) == "string" and name ~= "" then
                    enumerated = true
                    local r = tonumber(rank) or 0
                    if r > 0 then
                        ranks[name] = r
                    end
                end
            end
        end
    end
    if not enumerated then
        return nil
    end
    return ranks
end

-- ReadUnit(unit, rawLinks) -> hit, race
--   rawLinks : OPTIONAL { [invSlot] = link } that scan/gear.lua already
--              fetched for this unit. Slots it covers are taken from it
--              (no second GetInventoryItemLink pass); any slot H.SLOTS
--              needs that rawLinks did not cover is fetched here instead.
--   hit      : the store shape documented in the file header
--   race     : race token from UnitRace (2nd return, e.g. "NightElf");
--              needed for the racial weapon-skill estimate of foreign
--              players and stored next to the hit table by the engine.
function H.ReadUnit(unit, rawLinks)
    local hit = {
        melee = 0, spell = 0, schools = {}, sources = {},
        mainSub = nil, offSub = nil, rangedSub = nil,
        skillName = nil, hitRead = false,
        -- RESIST tab reuse (see file header addendum): resistGear starts
        -- empty and resistGearRead false so a caller that never reaches
        -- the accumulation below (e.g. an early return elsewhere) still
        -- sees a well-formed, honestly-unread pair rather than nil fields.
        resistGear = {}, resistGearRead = false,
    }

    local race = nil
    if UnitRace then
        -- 1.12 returns the display name first, the file token second
        local ok, display, token = pcall(UnitRace, unit)
        if ok then
            race = token or display
        end
    end

    -- which slots the caller's link table already covers
    local covered = {}
    if rawLinks and DC_Gear and DC_Gear.InvSlots then
        local gs = DC_Gear.InvSlots()
        for i = 1, table.getn(gs) do
            covered[gs[i]] = true
        end
    end

    local mainHasItem = false
    -- set pieces this unit wears, keyed by set name -- filled in the slot
    -- loop, folded into the sum ONCE after it (H.SumSets)
    local setsWorn = {}
    -- RESIST tab reuse: every itemHit() entry that came back non-nil this
    -- pass (tooltip actually read, whether cached or freshly scanned) --
    -- handed to H.SumItemResists after the loop, see that function's
    -- header for why "entry existed" is the correct bar here.
    local resistItems = {}
    local n = table.getn(H.SLOTS)
    for i = 1, n do
        local slot = H.SLOTS[i]
        local link = nil
        if rawLinks and covered[slot] then
            link = rawLinks[slot]
        elseif GetInventoryItemLink then
            local ok, l = pcall(GetInventoryItemLink, unit, slot)
            if ok then
                link = l
            end
        end
        if link then
            hit.hitRead = true      -- any link at all = the read worked
            local itemId, enchantId = nil, nil
            if DC_Gear and DC_Gear.ParseLink then
                itemId, enchantId = DC_Gear.ParseLink(link)
            end
            if slot == H.SLOT_MAIN then
                mainHasItem = true
            end
            if itemId then
                local entry = itemHit(unit, slot, itemId, enchantId or 0)
                if entry then
                    H.AddSum(hit, entry.sum)
                    table.insert(resistItems, entry)
                    local ns = table.getn(entry.sources)
                    for s = 1, ns do
                        if table.getn(hit.sources) < H.SOURCE_CAP then
                            table.insert(hit.sources, {
                                item = entry.name,
                                kind = entry.sources[s].kind,
                                value = entry.sources[s].value,
                            })
                        end
                    end
                    -- set membership: tally the pieces THIS unit wears per
                    -- set name. The bonus list comes from whichever piece
                    -- is seen first -- every piece of a set prints the same
                    -- list, which is exactly why it must be counted once.
                    if entry.set and entry.set.name then
                        local sname = entry.set.name
                        if not setsWorn[sname] then
                            setsWorn[sname] = { pieces = 0,
                                                bonuses = entry.set.bonuses }
                        end
                        setsWorn[sname].pieces = setsWorn[sname].pieces + 1
                    end
                end
                -- weapon subtypes drive the caps; only the three weapon
                -- slots need the extra item lookup
                if slot == H.SLOT_MAIN or slot == H.SLOT_OFF
                   or slot == H.SLOT_RANGED then
                    local sub = nil
                    if DC_Gear and DC_Gear.ItemInfo then
                        local _, _, s = DC_Gear.ItemInfo(itemId)
                        sub = s
                    end
                    if slot == H.SLOT_MAIN then
                        hit.mainSub = sub
                    elseif slot == H.SLOT_OFF then
                        hit.offSub = sub
                    else
                        hit.rangedSub = sub
                    end
                end
            end
        end
    end

    -- SET BONUSES, folded in ONCE per set (H.SumSets) now that the whole
    -- inventory has been walked and the piece count per set is known.
    -- Doing it here rather than per item is the entire fix: the bonus line
    -- is printed on every piece, so a per-item sum would multiply it by
    -- the number of pieces worn.
    local setSum, setSources = H.SumSets(setsWorn)
    H.AddSum(hit, setSum)
    -- kept SEPARATELY as well, so the tooltip can show the hit number as a
    -- plain addition (items + set bonuses + auras + talents) instead of one
    -- merged "from gear" figure. The totals above already contain it; these
    -- three fields only say how much of it came from sets.
    hit.setMelee = setSum.melee
    hit.setSpell = setSum.spell
    hit.setSchools = setSum.schools

    -- RESIST tab reuse (see file header addendum): fold every scanned
    -- item's resistance contribution into ONE sum, and record whether ANY
    -- item's tooltip was actually read (the honesty gate scan/engine.lua's
    -- gear-reconstruction fallback checks -- see H.SumItemResists).
    hit.resistGear, hit.resistGearRead = H.SumItemResists(resistItems)
    for s = 1, table.getn(setSources) do
        if table.getn(hit.sources) < H.SOURCE_CAP then
            local src = setSources[s]
            table.insert(hit.sources, {
                item = src.set .. " (" .. src.pieces .. " pieces)",
                kind = src.kind,
                value = src.value,
                set = src.set,
            })
        end
    end

    -- main-hand weapon skill name: bare fists run on Unarmed, but an item
    -- whose subtype could not be resolved stays UNKNOWN (nil) -- claiming
    -- "Unarmed" for a weapon we simply failed to identify would be a
    -- wrong assumption, not a missing one. A FAILED read claims nothing
    -- at all: "no main hand" is only meaningful once something was read.
    local map = DC.WEAPON_SKILL_OF_SUBTYPE or {}
    if hit.mainSub then
        hit.skillName = map[hit.mainSub]
    elseif hit.hitRead and not mainHasItem then
        hit.skillName = "Unarmed"
    end

    return hit, race
end
