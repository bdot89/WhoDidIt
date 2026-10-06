if WDI_DOPING_SKIP then return end -- DopingControl scan/aura.lua
-- Buff reading for one unit, two independent paths, merged:
--   Path A (unit token): UnitBuff(unit, i), i = 1..32 -- buff NAME via a
--     hidden tooltip (DopingControlScanTip, the standard 1.12
--     hidden-tooltip scanner pattern), spell ID via the
--     4th return value (a SuperWoW extension; unverified on other client
--     builds -- covered by the probe battery).
--     UnitBuff compacts its list: stop at the first nil texture.
--   Path B (GUID): GetUnitField(guid, "aura") -- nampower descriptor table,
--     48 ONE-BASED slots of spell ids (1-32 buffs, 33-48 debuffs). The
--     table is SPARSE (in-game verified: e.g. slots
--     1,2,5,6 filled with 3,4 empty), so iterate all 32 buff slots and
--     skip empties instead of breaking at the first gap.
-- Both paths are pcall-wrapped per call (hard rule).
--
-- Merge (pure, offline-tested): union of the ID sets, names from path A.
-- Buff icons: auras.textures[name] = icon path (UnitBuff return 1) for
-- every path-A buff that yielded a name; ids without a name are OPTIONALLY
-- resolved via SuperWoW SpellInfo(id) (return 3 = icon) when the function
-- exists. textures is OPTIONAL/partial by design -- every consumer
-- nil-guards, nothing downstream may require it.
-- Buff EFFECT lines: auras.effects[name] = the tooltip's line 2 text
-- (same hidden-tooltip read as the name, TextLeft2) for every path-A buff
-- that yielded both a name and a non-empty line 2. This feeds the item
-- identification ladder for generic buff names ("Well Fed" -> which food,
-- via DC.ResolveItem's discrim patterns). effects is OPTIONAL/partial
-- exactly like textures -- every consumer nil-guards.
-- Disagreements between the two ID sets are counted (symmetric difference,
-- only when BOTH paths yielded at least one ID -- an absent path is missing
-- data, not a disagreement) and accumulated by the engine into
-- DC.probeStats. Zero USABLE auras (name- or id-carrying) from both paths
-- => aurasRead = false (a failed read, never "has nothing";
-- texture-only path-A rows carry no evidence and do not count).
--
-- Unknown auras are collected, never silently dropped:
-- an aura is unknown when neither its name is in DC.CONSUMABLES /
-- DC.CLASSBUFFS nor its spell ID in DC.SPELL_TO_SLOT. Path-B-only IDs
-- normally carry no name and are reported as "spell:<id>", UNLESS the
-- caller supplies idNames (see A.Assemble below): with a resolved name,
-- a path-B-only aura is judged the same way a path-A one is (known
-- consumable/class-buff name => not unknown at all) and, if still
-- unknown, is reported as that name instead of "spell:<id>" -- and only
-- once, even when the same aura also showed up unresolved via path A
-- (this is what keeps the same aura from being counted twice: once as a
-- name from path A, once as "spell:<id>" from path B, which used to
-- happen whenever path A never delivered a spell ID at all, making the
-- id-based dedup a no-op).
--
-- DEBUFFS:
-- ReadUnit additionally reads UnitDebuff(unit, i) 1..16 (same hidden
-- tooltip via SetUnitDebuff, texture = return 1, spell id = 4th return if
-- present) and the debuff half of the SAME GetUnitField "aura" fetch
-- (one-based slots 33-48). AssembleDebuffs merges them into the store
-- shape players[i].debuffs = { names, ids, textures } (sibling of auras).
-- Debuff READABILITY rides on the existing aurasRead flag -- zero debuffs
-- is a LEGITIMATE clean state (empty sets), NEVER a read failure, and it
-- never influences aurasRead. Debuff names are NOT collected into
-- DC.unknownSeen (that channel is consumable tracking);
-- nothing is silently dropped either way, because the DEBUFFS tab builds
-- its columns dynamically from exactly this data.
--
-- Pure Lua 5.0, dofile-loadable offline (WoW wiring only inside functions
-- that run in-game; tooltip frame is created lazily).

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Aura = DC_Aura or {}
local A = DC_Aura

-- ==================================================================
-- Pure part
-- ==================================================================

-- Assemble(rawA, rawB, idNames) -> auras, aurasRead, disagreements, unknown
--   rawA : array of { name = string|nil, id = number|nil,
--                     texture = string|nil, effect = string|nil }
--                     (path A; texture is the 1st UnitBuff return,
--                     effect the tooltip's line 2 -- both optional)
--   rawB : array of spell ids (numbers, path B)
--   idNames : OPTIONAL { [spellId] = "Buff Name" } for path-B ids,
--             filled by the WoW-side caller (SuperWoW SpellInfo lookup --
--             see A.ReadUnit). Omitted in tests/offline callers, in which
--             case unknown path-B ids are reported as "spell:<id>" exactly
--             as before (no behavior change without it).
-- Returns:
--   auras         : { names = { [name]=true }, ids = { [id]=true },
--                     textures = { [name]=iconPath },
--                     effects = { [name]=effectLine } }
--                   (store shape; textures AND effects may be empty/
--                   partial -- consumers nil-guard)
--   aurasRead     : bool -- true iff at least one USABLE aura arrived: a
--                   path-A entry carrying a name or an id, or a path-B id.
--                   Entries with NEITHER (UnitBuff texture present but the
--                   tooltip read failed and no 4th return) are information-
--                   free: counting them would flip a partially failed read
--                   from UNKNOWN to all-slots-MISSING -- exactly what the
--                   "zero auras => read failed" rule
--                   exists to prevent.
--   disagreements : number of ids present in exactly one of the two ID
--                   sets; 0 unless both sets are non-empty
--   unknown       : array of unknown-aura keys (name, or "spell:<id>")
-- trim(s) -> s with leading/trailing whitespace stripped. Lua-5.0-safe:
-- string.find with a captured "middle" group, no string-method syntax.
local function trim(s)
    local _, _, middle = string.find(s, "^%s*(.-)%s*$")
    return middle
end

-- isKnownAuraName(name, cons, cbuf) -> true if `name` is a recognized
-- consumable/class-buff key -- tried EXACT first, then (only if that
-- misses) its trimmed form. SpellInfo() aura names can carry stray
-- leading/trailing whitespace on this client (measured live:
-- SpellInfo(7254) = "Nature Protection " with a trailing space) that a
-- hand-authored table key never has; without this fallback such a name
-- never matches its own table entry. Exact-first matters because a
-- table key legitimately containing whitespace (should one ever exist)
-- must still win over a coincidental trimmed collision.
local function isKnownAuraName(name, cons, cbuf)
    if not name then
        return false
    end
    if cons[name] or cbuf[name] then
        return true
    end
    local trimmed = trim(name)
    if trimmed ~= name and (cons[trimmed] or cbuf[trimmed]) then
        return true
    end
    return false
end

function A.Assemble(rawA, rawB, idNames)
    rawA = rawA or {}
    rawB = rawB or {}
    idNames = idNames or {}
    local names = {}
    local ids = {}
    local idsA = {}
    local idsB = {}
    local textures = {}   -- [buffName] = icon path
    local effects = {}    -- [buffName] = tooltip effect line (line 2)
    local namedIds = {}   -- ids that arrived WITH a name (path A rows)
    local usable = 0   -- entries that carry actual evidence (see header)

    local nA = table.getn(rawA)
    for i = 1, nA do
        local e = rawA[i]
        local hasInfo = false
        if e.name then
            names[e.name] = true
            hasInfo = true
            if e.texture then
                textures[e.name] = e.texture
            end
            if type(e.effect) == "string" and e.effect ~= "" then
                effects[e.name] = e.effect
            end
        end
        if type(e.id) == "number" and e.id > 0 then
            idsA[e.id] = true
            ids[e.id] = true
            hasInfo = true
            if e.name then
                namedIds[e.id] = true
            end
        end
        if hasInfo then
            usable = usable + 1
        end
    end

    local nB = table.getn(rawB)
    for i = 1, nB do
        local id = rawB[i]
        if type(id) == "number" and id > 0 then
            idsB[id] = true
            ids[id] = true
            usable = usable + 1
        end
    end

    local aurasRead = usable > 0

    -- Optional icon resolution for ids that carried no name (path-B-only
    -- ids, or nameless path-A rows): SuperWoW SpellInfo(id) -> name, rank,
    -- icon (3rd return). Runtime-only enhancement -- SpellInfo is nil in
    -- offline tests and may be absent in-game (non-SuperWoW client);
    -- textures simply stays partial then. Path-A textures win (never
    -- overwritten): UnitBuff saw the actual aura, SpellInfo is a lookup.
    if SpellInfo then
        for id in pairs(ids) do
            if not namedIds[id] then
                local okSI, nm, _, icon = pcall(SpellInfo, id)
                if okSI and nm and icon and textures[nm] == nil then
                    textures[nm] = icon
                end
            end
        end
    end

    -- disagreement count: symmetric difference of the ID sets, but only
    -- when both paths actually delivered IDs (else it is path absence)
    local disagreements = 0
    if next(idsA) ~= nil and next(idsB) ~= nil then
        for id in pairs(idsA) do
            if not idsB[id] then
                disagreements = disagreements + 1
            end
        end
        for id in pairs(idsB) do
            if not idsA[id] then
                disagreements = disagreements + 1
            end
        end
    end

    -- unknown-aura collection (no silent discard)
    local unknown = {}
    local unknownNamesA = {}   -- names already added to `unknown` from path A
    local cons = DC.CONSUMABLES or {}
    local cbuf = DC.CLASSBUFFS or {}
    local s2s = DC.SPELL_TO_SLOT or {}
    for i = 1, nA do
        local e = rawA[i]
        -- name-known OR id-known -> known. Deliberately NOT an
        -- if/elseif chain gated on "no name": a row can carry a name
        -- that fails to match a table key exactly (SpellInfo() aura-
        -- name spelling vs. the hand-authored table key) while still
        -- carrying a correct spell id -- the id must be checked
        -- regardless of whether a name is present (belied a 26-man
        -- raid: a correctly ID-tracked consumable was discarded 38
        -- times because its live aura-name spelling did not match the
        -- table key it was filed under).
        local known = isKnownAuraName(e.name, cons, cbuf)
        if not known and type(e.id) == "number" and s2s[e.id] then
            known = true
        end
        if not known then
            if e.name then
                table.insert(unknown, e.name)
                unknownNamesA[e.name] = true
            elseif e.id then
                table.insert(unknown, "spell:" .. e.id)
            end
            -- entry with neither name nor id carries no information: skip
        end
    end
    -- path-B-only ids: with a resolved name (idNames, WoW-side SpellInfo
    -- lookup) an id is judged by name exactly like a path-A entry --
    -- known consumable/class-buff name is not unknown, and a name already
    -- reported from path A is not reported again (this is the dedup: on
    -- clients where UnitBuff never yields a spell ID, idsA stays empty
    -- and the id-based check below is a no-op, so the same aura would
    -- otherwise be counted once as a name and once as "spell:<id>").
    -- Without a resolved name, behavior is unchanged: "spell:<id>".
    for i = 1, nB do
        local id = rawB[i]
        if type(id) == "number" and id > 0 and not idsA[id] and not s2s[id] then
            local nm = idNames[id]
            if not nm then
                table.insert(unknown, "spell:" .. id)
            elseif isKnownAuraName(nm, cons, cbuf) then
                -- known by resolved name (exact or trimmed -- same rule
                -- as the path-A loop above): not unknown, nothing to add
            elseif unknownNamesA[nm] then
                -- already reported via path A under this name: skip
            else
                table.insert(unknown, nm)
            end
        end
    end

    return { names = names, ids = ids, textures = textures,
             effects = effects },
        aurasRead, disagreements, unknown
end

-- SplitAuraField(t) -> buffIds, debuffIds   (two arrays of spell ids)
-- Splits ONE GetUnitField(guid, "aura") descriptor table into its buff
-- half (one-based slots 1-32) and debuff half (slots 33-48). The table is
-- SPARSE (in-game verified, see header) -- every slot is visited, empties
-- and non-positive/non-number values are skipped, no break at gaps.
-- Pure -- offline-tested in test_scan_parse.lua.
function A.SplitAuraField(t)
    local buffs = {}
    local debuffs = {}
    if type(t) == "table" then
        for i = 1, 32 do
            local v = t[i]
            if type(v) == "number" and v > 0 then
                table.insert(buffs, v)
            end
        end
        for i = 33, 48 do
            local v = t[i]
            if type(v) == "number" and v > 0 then
                table.insert(debuffs, v)
            end
        end
    end
    return buffs, debuffs
end

-- AssembleDebuffs(rawDA, rawDB) -> debuffs
--   rawDA : array of { name = string|nil, id = number|nil,
--                      texture = string|nil } (UnitDebuff path, same row
--                      shape as the buff path A)
--   rawDB : array of spell ids (GetUnitField debuff half, slots 33-48)
-- Returns the store shape:
--   { names = { [name]=true }, ids = { [id]=true },
--     textures = { [name]=iconPath } }
-- Merge mirrors A.Assemble: union of the ID sets, names + textures from
-- the tooltip path, optional SpellInfo icon resolution for nameless ids.
-- NO read flag is derived here (readability = the existing aurasRead
-- flag; empty sets are a legitimate clean state) and NO unknown list is
-- returned (debuffs never feed DC.unknownSeen -- see header).
function A.AssembleDebuffs(rawDA, rawDB)
    rawDA = rawDA or {}
    rawDB = rawDB or {}
    local names = {}
    local ids = {}
    local textures = {}
    local namedIds = {}

    local nA = table.getn(rawDA)
    for i = 1, nA do
        local e = rawDA[i]
        if e.name then
            names[e.name] = true
            if e.texture then
                textures[e.name] = e.texture
            end
        end
        if type(e.id) == "number" and e.id > 0 then
            ids[e.id] = true
            if e.name then
                namedIds[e.id] = true
            end
        end
    end

    local nB = table.getn(rawDB)
    for i = 1, nB do
        local id = rawDB[i]
        if type(id) == "number" and id > 0 then
            ids[id] = true
        end
    end

    -- optional icon resolution for nameless ids (mirrors A.Assemble:
    -- SpellInfo is a SuperWoW runtime lookup, nil offline; tooltip-path
    -- textures are never overwritten)
    if SpellInfo then
        for id in pairs(ids) do
            if not namedIds[id] then
                local okSI, nm, _, icon = pcall(SpellInfo, id)
                if okSI and nm and icon and textures[nm] == nil then
                    textures[nm] = icon
                end
            end
        end
    end

    return { names = names, ids = ids, textures = textures }
end

-- ==================================================================
-- WoW part (runtime only; every call pcall-wrapped)
-- ==================================================================

-- Hidden tooltip scanner (standard 1.12 pattern).
-- The frame is NAMED, and the name is REQUIRED rather than cosmetic: the
-- line FontStrings are read back via getglobal("<name>TextLeft1").
local scanTip = nil

local function ensureTip()
    if not scanTip and CreateFrame then
        scanTip = CreateFrame("GameTooltip", "DopingControlScanTip",
            nil, "GameTooltipTemplate")
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return scanTip
end

-- shared accessor (core/probe.lua reuses the same hidden tooltip instead
-- of creating a second frame under the same global name)
function A.GetScanTip()
    return ensureTip()
end

-- Returns name (tooltip line 1) AND effect (tooltip line 2 -- the buff's
-- effect text, feeds the item identification ladder for generic names).
-- raises an error on bad units -> always called through pcall
local function tipBuffName(unit, buffIndex)
    scanTip:ClearLines()
    scanTip:SetUnitBuff(unit, buffIndex)
    local name, effect = nil, nil
    local textObj = getglobal("DopingControlScanTipTextLeft1")
    if textObj then
        name = textObj:GetText()
    end
    local effObj = getglobal("DopingControlScanTipTextLeft2")
    if effObj then
        effect = effObj:GetText()
    end
    return name, effect
end

-- debuff twin of tipBuffName (same hidden tooltip, SetUnitDebuff);
-- raises an error on bad units -> always called through pcall
local function tipDebuffName(unit, debuffIndex)
    scanTip:ClearLines()
    scanTip:SetUnitDebuff(unit, debuffIndex)
    local textObj = getglobal("DopingControlScanTipTextLeft1")
    if textObj then
        return textObj:GetText()
    end
    return nil
end

-- ReadUnit(unit, guid) -> rawA, rawB, rawDA, rawDB, idNames
--   rawA/rawB  : buff shapes as taken by A.Assemble
--   rawDA/rawDB: debuff shapes as taken by A.AssembleDebuffs (rawDA from
--                the UnitDebuff 1..16 loop, rawDB = debuff half slots
--                33-48 of the SAME GetUnitField fetch as rawB)
--   idNames    : { [spellId] = "Buff Name" } for the ids in rawB, resolved
--                via SuperWoW SpellInfo (same lookup A.Assemble already
--                uses for icons); taken by A.Assemble's optional 3rd
--                parameter. Extra return value -- existing callers that
--                only capture rawA..rawDB are unaffected.
function A.ReadUnit(unit, guid)
    local rawA = {}
    local rawDA = {}
    if UnitBuff then
        local tip = ensureTip()
        for i = 1, 32 do
            -- 4th return = SuperWoW spell id (unverified on other builds; probe Q1)
            local ok, texture, stacks, dtype, auraID = pcall(UnitBuff, unit, i)
            if not ok or not texture then
                break
            end
            local name, effect = nil, nil
            if tip then
                local ok2, nm, eff = pcall(tipBuffName, unit, i)
                if ok2 then
                    name = nm
                    effect = eff
                end
            end
            local id = nil
            if type(auraID) == "number" and auraID > 0 then
                id = auraID
            end
            -- texture (UnitBuff return 1) and the tooltip effect line ride
            -- along so Assemble can key them under the tooltip name
            -- (auras.textures / auras.effects)
            table.insert(rawA, { name = name, id = id, texture = texture,
                                 effect = effect })
        end
    end
    if UnitDebuff then
        -- mirror of the buff loop: 16 debuff slots on 1.12, list is
        -- compacted (stop at the first nil texture), name via the same
        -- hidden tooltip, spell id via 4th return if present
        local tip = ensureTip()
        for i = 1, 16 do
            local ok, texture, stacks, dtype, auraID = pcall(UnitDebuff, unit, i)
            if not ok or not texture then
                break
            end
            local name = nil
            if tip then
                local ok2, nm = pcall(tipDebuffName, unit, i)
                if ok2 then
                    name = nm
                end
            end
            local id = nil
            if type(auraID) == "number" and auraID > 0 then
                id = auraID
            end
            table.insert(rawDA, { name = name, id = id, texture = texture })
        end
    end

    local rawB = {}
    local rawDB = {}
    if GetUnitField and guid then
        local ok, t = pcall(GetUnitField, guid, "aura")
        if ok and type(t) == "table" then
            -- ONE fetch carries both halves (sparse 48-slot table):
            -- buffs 1-32, debuffs 33-48 -- split without extra API calls
            rawB, rawDB = A.SplitAuraField(t)
        end
    end

    -- name resolution for path-B ids (SuperWoW SpellInfo lookup, same
    -- pattern/guarding as the icon resolution in A.Assemble): path-B ids
    -- never carry a name of their own, so every id here is a candidate.
    -- Runtime-only, pcall-wrapped, nil-safe; stays empty offline/without
    -- SuperWoW, which leaves A.Assemble's unknown-aura reporting exactly
    -- as before ("spell:<id>").
    local idNames = {}
    if SpellInfo then
        local nB = table.getn(rawB)
        for i = 1, nB do
            local id = rawB[i]
            if type(id) == "number" and id > 0 then
                local okSI, nm = pcall(SpellInfo, id)
                if okSI and nm then
                    idNames[id] = nm
                end
            end
        end
    end

    return rawA, rawB, rawDA, rawDB, idNames
end
