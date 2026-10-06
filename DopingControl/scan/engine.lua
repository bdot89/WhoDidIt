if WDI_DOPING_SKIP then return end -- DopingControl scan/engine.lua
-- Scan orchestration: roster snapshot, per-unit reads (reach/aura/gear/
-- weapon), OnUpdate batching (5 units per frame), store
-- assembly and the DC.OnStoreUpdated() completion hook
-- (wired by core/init.lua).
--
-- Triggers:
--   * manual: DC_Scan.Start(force)
--   * READY_CHECK: registered DEFENSIVELY via pcall (unverified as a
--     native client event on 1.12; if the
--     registration throws, the feature silently does not exist). Honors
--     db.readyCheckScan and never fires in test mode (sim store).
--   * roster change (RAID_ROSTER_UPDATE / PARTY_MEMBERS_CHANGED): raid
--     indices are VOLATILE after these events,
--     so a running scan is restarted with a fresh roster snapshot; a
--     finished store is flagged stale via DC.storeInvalid.
-- No UNIT_AURA registration at all: UNIT_AURA is unreliable for raidN
-- tokens on 1.12 -- we scan on demand instead.
--
-- Diagnostics filled here:
--   DC.probeStats  = { scans, unitsPathA, unitsPathB, unitsBoth,
--                      idDisagreements, lastScan = { unitsA, unitsB, both,
--                      disagreements } }
--                    -- cumulative A/B aura-path coverage + ID-set
--                    disagreement counts (scan/aura.lua merge)
--   DC.unknownSeen = { [nameOrSpellKey] = count } -- auras no table knows
--                    (no silent discard, dumped by /dc unknown)
--
-- Last-known cache: DC.lastKnown -- see the
-- "Last-known cache" block below. THE IRON RULE: cached data is DISPLAY-ONLY;
-- it never counts as HAS/MISSING in gaps, ready pills, sums, footer or
-- report. A flask seen 20 minutes ago is not verified preparation.
--
-- RESIST tab data: resistances are read via THREE DIRECT fallback paths
-- (unit token, GUID, GetUnitField descriptor -- see readResists/
-- AssembleResists below), independent of the aura/gear reads, plus a
-- FOURTH gear-reconstruction path for foreign players (added 2026-08-02):
-- the server never transmits UNIT_FIELD_RESISTANCES for anyone but the
-- owning client, so the three direct paths can only ever answer for the
-- own character -- every foreign player's resistances are rebuilt from
-- equipped-item tooltips (scan/hit.lua's per-item cache, scan/resist.lua's
-- pure parser) plus the racial bonus (data/resist.lua DC.RACE_RESIST). All
-- four ride into the store as p.resists/p.resistsRead/p.resistsSource
-- ("token"|"guid"|"field"|"gear"|nil for self).
--
-- HIT tab data: scan/hit.lua sums the +hit of the equipped items from
-- their tooltips -- there is no hit API on this client -- and rides into
-- the store as p.hit (its own hitRead flag lives INSIDE that table) plus
-- p.race, which the display layer needs for the racial weapon-skill
-- estimate of foreign players. The hit read reuses the item links the gear
-- read already fetched, so it costs one extra link call (the waist, which
-- has no enchant column) plus one tooltip build per item that is not in
-- scan/hit.lua's per-item cache. This SAME read now also produces
-- hit.resistGear/resistGearRead (see above), which is why scanOne runs the
-- hit read BEFORE the resist read despite RESIST sitting before HIT on the
-- tab bar.
--
-- WEAPON SKILL is readable for the OWN CHARACTER ONLY, and is stated as
-- such rather than guessed for everyone else: MEASURED via
-- GetSkillLineInfo and stored as hit.skill/hit.skillExact, while foreign
-- weapon skill has no channel and stays an estimate made at display time.
--
-- TALENT HIT (data/talenthit.lua) has TWO sources that meet in the same
-- fields: GetTalentInfo for the own character, and this server's inspect
-- protocol (scan/talents.lua) for everyone else. Both fill
-- hit.talentMelee/talentRanged/talentSpell/talentOffhand/talentSchools
-- with hit.talentsRead = true. A player whose reply has not arrived yet
-- keeps talentsRead = false and zeroed talent fields, and their displayed
-- number EXCLUDES talents until it does.
--
-- Pure Lua 5.0, dofile-loadable offline: NormalizeWeapon /
-- NormalizeWeaponName / AssembleResists / BuildPlayer / NewStore /
-- UpdateLastKnown / SweepLastKnown are pure (offline-tested); everything
-- that touches frames or the WoW API sits behind `if CreateFrame then`.

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Scan = DC_Scan or {}
local E = DC_Scan

E.BATCH = 5  -- units processed per OnUpdate frame

DC.probeStats = DC.probeStats or {
    scans = 0, unitsPathA = 0, unitsPathB = 0, unitsBoth = 0,
    idDisagreements = 0,
    lastScan = { unitsA = 0, unitsB = 0, both = 0, disagreements = 0 },
}
DC.unknownSeen = DC.unknownSeen or {}

-- ==================================================================
-- Pure part
-- ==================================================================

-- NormalizeWeapon(isSelf, v, readable) -> weaponMain (true|false|nil, store shape)
--   self   : v = 1st return of GetWeaponEnchantInfo() (hasMainEnchant);
--            the own unit is always readable => never nil
--   foreign: v = 1st return of GetWeaponEnchantInfo(unit) (SuperWoW): a name
--            string => true. `readable` says whether the unit's main hand
--            could be read at all and is what makes nil decidable.
--
-- Measured 2026-08-02 across a 26-man raid, every unit with a readable main
-- hand: nil came back 14 times, a name 11 times, the empty string NEVER. So
-- the old ""-means-no-imbue contract (documented here as "unverified") is
-- dead code, and nil carries BOTH real cases at once: "carries no imbue" and
-- "we could not read this unit". Treating nil as unknown -- as this function
-- did -- meant the WPN column could never report a gap: all 14 players
-- without a weapon buff showed a grey "?" and were counted as unreadable, so
-- they never reached the gap tally, the footer or a whisper. That is the one
-- thing a raid buff checker exists to say.
--
-- `readable` separates the two: a unit whose main-hand item link resolves is
-- readable, so nil from the enchant call means there is genuinely no imbue
-- (=> false, a real gap). Without the hint the old behaviour stands (nil),
-- which keeps every existing caller and the self path untouched.
function E.NormalizeWeapon(isSelf, v, readable)
    if isSelf then
        if v then
            return true
        end
        return false
    end
    -- Stock 1.12 GetWeaponEnchantInfo takes NO arguments: on a client without
    -- SuperWoW the extra unit is ignored and the first return is the PLAYER's
    -- hasMainHandEnchant (1|nil). Only the SuperWoW name channel answers about
    -- the foreign unit, and it is always string-or-nil (measured: 11 names,
    -- 14 nils, "" never). A non-string therefore says nothing about this unit
    -- => not readable, never "has an imbue".
    if v ~= nil and type(v) ~= "string" then
        return nil
    end
    if v == nil then
        if readable == true then
            return false
        end
        return nil
    end
    if v == "" then
        return false
    end
    return true
end

-- NormalizeWeaponName(v) -> weaponMainName (string|nil, store shape).
-- v = 1st return of GetWeaponEnchantInfo(unit)
-- (SuperWoW name path): non-empty string => the temp-enchant name;
-- anything else => nil (measured in-game: nil at cross-continent
-- distance -- acceptable, the weapon cell stays UNKNOWN per the existing
-- weaponMain rules).
function E.NormalizeWeaponName(v)
    if type(v) == "string" and v ~= "" then
        return v
    end
    return nil
end

-- BuildPlayer(base, online, distance, auraRes, gearRes, weaponMain,
--             weaponMainName, resRes)
--   base    : { name, class (english token), guid|nil, subgroup|nil }
--   online  : bool (roster-first, reach fallback -- merged by the caller)
--   auraRes : nil | { read = bool, auras = { names={}, ids={} },
--             debuffs = nil | { names={}, ids={}, textures={} } }
--             (readability rides on
--             read/aurasRead -- empty debuff sets are a legitimate clean
--             state, never a failure)
--   gearRes : nil | { read = bool, gear = table|nil }
--   weaponMainName : string|nil -- main-hand temp-enchant NAME
--             (self: tooltip scan via
--             DC_Gear.ReadSelfWeaponEnchantName, foreign: SuperWoW
--             GetWeaponEnchantInfo(unit) name); rides into the store as
--             p.weaponMainName -- DC_Model uses it as the weapon HAS
--             detail when set
--   resRes  : nil | { read = bool, resists = table|nil, source = string|nil }
--             (E.AssembleResists' three returns, same read/wrapper
--             convention as auraRes/gearRes) -- rides into the store as
--             p.resists/p.resistsRead/p.resistsSource; independent of
--             aurasRead/gearRead (a resistance read is neither an aura
--             nor a gear read)
--   hitRes  : nil | { hit = table|nil, race = string|nil } (DC_Hit.ReadUnit's
--             two returns). DELIBERATELY SHAPED DIFFERENTLY from the
--             wrappers above: there is no `read` key, because the hit
--             table carries its OWN hitRead flag and rides into the store
--             EVEN WHEN the read failed (p.hit.hitRead == false). Every
--             consumer must therefore test p.hit and p.hit.hitRead --
--             the zeros in a failed read are not a measurement. `race` is
--             the race token, stored as p.race: the display layer needs it
--             to estimate a FOREIGN player's weapon skill (racial
--             specialization), which no API can read.
--
--             Hit-granting AURAS (DC.HIT_AURAS, data/hit.lua) are folded
--             in RIGHT HERE, not inside scan/hit.lua's ReadUnit -- that
--             module only ever sees item tooltips, never the aura scan.
--             No extra client call: p.auras was already assembled above
--             by the SAME scan. The split is kept so the cell tooltip can
--             show every source apart: hit.gearMelee/hit.gearSpell are the
--             tooltip-parsed sums (unchanged from scan/hit.lua),
--             hit.auraMelee/hit.auraRanged/hit.auraSpell are the aura
--             sums, hit.talentMelee/talentRanged/talentSpell/
--             talentOffhand/talentSchools are the TALENT sums the scan
--             filled in for the own character (normalized to zeros here
--             for everyone else, with hit.talentsRead saying which it
--             was), and hit.melee/hit.spell become the TOTAL -- the field
--             every existing display-layer caller already reads.
--             hit.aurasRead mirrors p.aurasRead at the moment this ran, so
--             a failed aura channel shows as "aura sources unknown"
--             (ui/matrix.lua) instead of a silent zero; hit.talentsRead
--             does the same job for talents.
--             Deliberately independent of any expectation/role table --
--             BuildPlayer never sees one -- so a hit-granting aura counts
--             here even when its class-buff column (e.g. EMB) is not
--             expected/active for this player at all.
-- -> one store player entry. Readability rule
-- (binding): online==false => "offline"; else aurasRead==false
-- (aura paths yielded ZERO auras) => "read failed"; else nil.
function E.BuildPlayer(base, online, distance, auraRes, gearRes, weaponMain,
                       weaponMainName, resRes, hitRes)
    local p = {
        name = base.name,
        class = base.class,
        online = (online and true) or false,
        guid = base.guid,
        subgroup = base.subgroup,
        distance = distance,
        aurasRead = false,
        auras = nil,
        weaponMain = weaponMain,
        weaponMainName = weaponMainName,
        gearRead = false,
        gear = nil,
        resistsRead = false,
        resists = nil,
        resistsSource = nil,
        hit = nil,
        race = nil,
        unreadableReason = nil,
    }
    if auraRes and auraRes.read then
        p.aurasRead = true
        p.auras = auraRes.auras
        p.debuffs = auraRes.debuffs
    end
    if gearRes and gearRes.read then
        p.gearRead = true
        p.gear = gearRes.gear
    end
    if resRes and resRes.read then
        p.resistsRead = true
        p.resists = resRes.resists
        p.resistsSource = resRes.source
    end
    -- hit: attached WHATEVER the outcome (see the hitRes doc above) --
    -- readability lives in p.hit.hitRead, not in a wrapper flag
    if hitRes then
        p.hit = hitRes.hit
        p.race = hitRes.race
    end
    -- hit-granting auras (DC.HIT_AURAS, data/hit.lua) folded on top of the
    -- gear sum -- see the hitRes doc above for the field split and why
    -- this runs here rather than in scan/hit.lua
    if p.hit then
        -- SET bonuses are part of the scanned totals but are reported
        -- separately, so the tooltip can print the number as an addition
        -- (items + set bonuses + auras + talents) rather than one merged
        -- figure. "gear" therefore means ITEMS ONLY from here on: the set
        -- part is subtracted out, never counted twice.
        p.hit.setMelee = p.hit.setMelee or 0
        p.hit.setSpell = p.hit.setSpell or 0
        p.hit.setSchools = p.hit.setSchools or {}
        p.hit.gearMelee = (p.hit.melee or 0) - p.hit.setMelee
        p.hit.gearSpell = (p.hit.spell or 0) - p.hit.setSpell
        p.hit.aurasRead = p.aurasRead
        -- TALENTS (data/talenthit.lua): filled from GetTalentInfo for the
        -- own character and from this server's inspect protocol
        -- (scan/talents.lua) for everyone else. Whoever has not answered
        -- YET keeps talentsRead = false and clean zeros. They are
        -- normalized HERE so no consumer has to nil-check them and so a
        -- hand-built or older store (sim, tests) folds identically.
        if p.hit.talentsRead == nil then
            p.hit.talentsRead = false
        end
        p.hit.talentMelee = p.hit.talentMelee or 0
        p.hit.talentRanged = p.hit.talentRanged or 0
        p.hit.talentSpell = p.hit.talentSpell or 0
        p.hit.talentOffhand = p.hit.talentOffhand or 0
        p.hit.talentSchools = p.hit.talentSchools or {}
        -- the aura half only exists when the aura channel worked: a FAILED
        -- read must not leave a zero that reads like a measurement, which
        -- is why auraMelee/auraRanged/auraSpell stay nil there (the cell
        -- tooltip tells "no aura present" from "aura sources unknown" by
        -- exactly this)
        local auraMelee, auraSpell = 0, 0
        if p.aurasRead and DC_Hit and DC_Hit.AuraHit then
            local a = DC_Hit.AuraHit(p.auras and p.auras.names)
            p.hit.auraMelee = a.melee
            p.hit.auraRanged = a.ranged
            p.hit.auraSpell = a.spell
            auraMelee = a.melee
            auraSpell = a.spell
        end
        -- the TOTALS every display-layer caller reads. The ranged column
        -- has no total of its own on purpose: it shares the melee GEAR
        -- number (this client has no separate ranged-hit item stat) but
        -- has its own aura and talent halves, so it is composed as
        -- gearMelee + auraRanged + talentRanged where it is shown.
        p.hit.melee = p.hit.gearMelee + auraMelee + p.hit.talentMelee
        p.hit.spell = p.hit.gearSpell + auraSpell + p.hit.talentSpell
    end
    if not p.online then
        p.unreadableReason = "offline"
    elseif not p.aurasRead then
        p.unreadableReason = "read failed"
    end
    return p
end

-- AssembleResists(isSelf, tokenRows, guidRows, fieldRows, gearFallback)
--   -> resists (table|nil), resistsRead (bool), source (string|nil)
--
-- Three DIRECT read paths, tried in priority order (token > guid > field);
-- each row array may be empty (the WoW-only caller skips a path once an
-- earlier one already delivered usable data -- see scanOne below):
--   tokenRows/guidRows : { school = 2..6, ok = bool, total = number|nil }
--                         (raw pcall(UnitResistance, unitOrGuid, school)
--                         results -- `total` is UnitResistance's 2nd
--                         return; base/bonus/minus are not used here)
--   fieldRows          : { school = 2..6, val = number|nil } (raw
--                         GetUnitField(guid, "resistances") readout,
--                         already split into rows by the caller)
--
-- A path counts as USABLE when at least one of its rows has ok==true (or,
-- for fieldRows, a numeric val) -- the first usable path wins outright,
-- its rows become `resists` (missing schools simply absent from the
-- table; classify() defaults an absent school to 0). Field-path values
-- are trusted ONLY when positive (a lone unverified foreign zero is not
-- accepted from that path -- see the honesty rule below); token/guid
-- values are trusted at face value, including legitimate zeros.
--
-- Honesty rule (binding): resistsRead = true only when
-- isSelf, OR the assembled `resists` contains at least one total > 0. A
-- foreign UnitResistance call can silently return 0 for an out-of-sight/
-- out-of-range unit -- a LONE zero from a foreign read is not trusted (it
-- could be a real 0 resistance or a failed read that happens to default
-- to 0); a MIX with at least one real positive value is. `source` names
-- the path that won ("token"|"guid"|"field") for foreign reads, and is
-- always nil for the self read (self is unconditionally trusted, so the
-- specific path is not interesting -- it is always "token" in practice,
-- UnitResistance("player", school)).
--
-- FOURTH path -- gear reconstruction (added 2026-08-02, see
-- scan/resist.lua and data/resist.lua's headers for the full rationale):
-- the server never transmits UNIT_FIELD_RESISTANCES for a foreign player
-- at all (Player::InitVisibleBits() only sets the bit for the owning
-- client), so paths 1-3 above are not merely "the usual case" for a
-- foreign unit -- they can NEVER succeed for one. This is the only path
-- that can ever answer for a foreign player, tried only once none of the
-- three DIRECT paths produced anything trustworthy.
--   gearFallback : nil, or { resistGear = { [school]=total },
--                  resistGearRead = bool, race = string|nil } -- exactly
--                  DC_Hit.ReadUnit's hit.resistGear/hit.resistGearRead
--                  plus its race return, so the WoW-only caller can just
--                  hand its `hit`/`race` locals through unpacked.
-- Gated on resistGearRead, NOT on "did any school come back positive": a
-- tooltip-based read has no silent-zero ambiguity the way UnitResistance
-- does for an out-of-range foreign unit (a GameTooltip:SetInventoryItem
-- call either returns real lines or it visibly fails, see
-- scan/hit.lua's header) -- once resistGearRead is true, an all-zero
-- gear+racial total is a GENUINE verified zero, not a guess.
-- NEVER taken for the own character (`not isSelf`): the own character's
-- token path is always usable (see the honesty rule above) and must keep
-- priority over any reconstruction, per the addon's binding rule that a
-- MEASURED value always outranks a rebuilt one.
-- Racial bonus (DC_Resist.RaceBonus, data/resist.lua's DC.RACE_RESIST) is
-- added on top here rather than inside scan/hit.lua: it is not a gear
-- fact, and scan/hit.lua's job stops at "what the equipped items say".
-- Existence-guarded like every other DC_Resist call -- without that
-- module this path simply never activates.
function E.AssembleResists(isSelf, tokenRows, guidRows, fieldRows, gearFallback)
    -- `any` decides which path WINS, so it has to mean "this path carried
    -- evidence". For a foreign unit an all-zero row set is not evidence
    -- (see readResists): it would otherwise beat a descriptor path that
    -- actually has the numbers. Zeros are still kept in `out` -- a mixed
    -- read (0 fire, 24 nature) is legitimate and complete.
    local function usableRows(rows)
        local out = {}
        local any = false
        rows = rows or {}
        for i = 1, table.getn(rows) do
            local r = rows[i]
            if r.ok and type(r.total) == "number" then
                out[r.school] = r.total
                if isSelf or r.total > 0 then
                    any = true
                end
            end
        end
        return out, any
    end

    local resists, source
    local tok, tokAny = usableRows(tokenRows)
    if tokAny then
        resists, source = tok, "token"
    else
        local gid, gidAny = usableRows(guidRows)
        if gidAny then
            resists, source = gid, "guid"
        else
            local fld = {}
            local fldAny = false
            local rows = fieldRows or {}
            for i = 1, table.getn(rows) do
                local r = rows[i]
                -- field path: positive values only (see header) --
                -- a zero/nil field entry carries no evidence
                if type(r.val) == "number" and r.val > 0 then
                    fld[r.school] = r.val
                    fldAny = true
                end
            end
            if fldAny then
                resists, source = fld, "field"
            end
        end
    end

    if resists ~= nil then
        local anyPositive = false
        for _, v in pairs(resists) do
            if v > 0 then
                anyPositive = true
            end
        end
        if isSelf or anyPositive then
            if isSelf then
                source = nil
            end
            return resists, true, source
        end
        -- all-zero foreign read from a direct path: falls through to the
        -- gear fallback below exactly like "no direct path answered at
        -- all" -- an untrusted all-zero carries no more evidence than no
        -- read at all (see the honesty rule above)
    end

    -- FOURTH path: gear reconstruction (see the header addendum above) --
    -- never for the own character, and only once resistGearRead proves at
    -- least one item tooltip was actually read this scan.
    if not isSelf and gearFallback and gearFallback.resistGearRead then
        local g = {}
        for school, v in pairs(gearFallback.resistGear or {}) do
            g[school] = v
        end
        if DC_Resist and DC_Resist.RaceBonus then
            local racial = DC_Resist.RaceBonus(gearFallback.race)
            for school, v in pairs(racial) do
                g[school] = (g[school] or 0) + v
            end
        end
        return g, true, "gear"
    end

    return nil, false, nil
end

-- NewStore(players, scanAt) -> store (source = "scan")
function E.NewStore(players, scanAt)
    return {
        scanAt = scanAt,
        source = "scan",
        players = players or {},
    }
end

-- ==================================================================
-- Last-known cache
-- ==================================================================
-- DC.lastKnown[name] = { auras=<auras table>, aurasAt=<GetTime()>,
--   debuffs=, debuffsAt=, gear=<gear table>, gearAt=, weaponMain=,
--   weaponMainName=, weaponAt= }
-- Runtime-only: lives on DC, NEVER in DopingControlDB/SavedVariables.
-- Holds REFERENCES to the store tables (every scan builds fresh tables,
-- so a cache entry never aliases a live player's current data).

DC.lastKnown = DC.lastKnown or {}

-- Hard entry cap for the cap-safety sweep.
E.CACHE_CAP = 80

-- UpdateLastKnown(cache, p, now) -- both halves of the cache rule:
--   * successful channels overwrite the cache channel + its At stamp:
--     aurasRead=true (debuffs ride on the aura read -- they share its
--     success and its stamp), gearRead=true, weaponMain non-nil (false
--     included: a verified "no temp enchant" IS a successful read, and it
--     clears any stale cached name);
--   * failed channels attach the cached references onto the store player:
--     p.lastAuras/p.lastAurasAt, p.lastGear/p.lastGearAt,
--     p.lastWeaponMain/p.lastWeaponMainName/p.lastWeaponAt -- nil when no
--     cache. (No lastDebuffs: the DEBUFFS tab has no last-known channel
--     -- live afflictions only.)
-- Failure never erases an older cache entry, and a failed read never
-- CREATES an entry.
function E.UpdateLastKnown(cache, p, now)
    if not p.name then
        return
    end
    local entry = cache[p.name]
    if p.aurasRead or p.gearRead or p.weaponMain ~= nil then
        if not entry then
            entry = {}
            cache[p.name] = entry
        end
    end
    if p.aurasRead then
        entry.auras = p.auras
        entry.aurasAt = now
        entry.debuffs = p.debuffs
        entry.debuffsAt = now
    end
    if p.gearRead then
        entry.gear = p.gear
        entry.gearAt = now
    end
    if p.weaponMain ~= nil then
        entry.weaponMain = p.weaponMain
        entry.weaponMainName = p.weaponMainName
        entry.weaponAt = now
    end
    if not entry then
        return
    end
    if not p.aurasRead then
        p.lastAuras = entry.auras
        p.lastAurasAt = entry.aurasAt
    end
    if not p.gearRead then
        p.lastGear = entry.gear
        p.lastGearAt = entry.gearAt
    end
    if p.weaponMain == nil then
        p.lastWeaponMain = entry.weaponMain
        p.lastWeaponMainName = entry.weaponMainName
        p.lastWeaponAt = entry.weaponAt
    end
end

-- SweepLastKnown(cache, rosterSet, cap) -- cap-safety eviction (item 1).
-- rosterSet = { [name]=true } of the CURRENT roster. Roster members are
-- never evicted (their rows may need the data right now); once the cache
-- holds more than cap entries, roster-absent entries drop oldest-first
-- (oldest = smallest NEWEST At across the entry's channels; name is the
-- deterministic tiebreaker) until the size is back at cap.
function E.SweepLastKnown(cache, rosterSet, cap)
    cap = cap or E.CACHE_CAP
    rosterSet = rosterSet or {}
    local size = 0
    for _ in pairs(cache) do
        size = size + 1
    end
    if size <= cap then
        return
    end
    local cand = {}
    for name, entry in pairs(cache) do
        if not rosterSet[name] then
            local newest = 0
            if entry.aurasAt and entry.aurasAt > newest then
                newest = entry.aurasAt
            end
            if entry.debuffsAt and entry.debuffsAt > newest then
                newest = entry.debuffsAt
            end
            if entry.gearAt and entry.gearAt > newest then
                newest = entry.gearAt
            end
            if entry.weaponAt and entry.weaponAt > newest then
                newest = entry.weaponAt
            end
            table.insert(cand, { name = name, at = newest })
        end
    end
    table.sort(cand, function(a, b)
        if a.at ~= b.at then
            return a.at < b.at
        end
        return a.name < b.name
    end)
    local i = 1
    local n = table.getn(cand)
    while size > cap and i <= n do
        cache[cand[i].name] = nil
        size = size - 1
        i = i + 1
    end
end

-- ==================================================================
-- WoW part
-- ==================================================================
if CreateFrame then

    local queue = {}          -- pending roster entries
    local results = {}        -- store player entries, roster order
    local running = false
    local restartPending = false

    -- BuildRoster() -> array of { unit, name, class, online, guid,
    -- subgroup }. online is true|false for raid entries (roster flag,
    -- GetRaidRosterInfo return 8 = SERVER TRUTH) and nil for party
    -- entries (no roster flag exists there -- scanOne falls back to the
    -- reach result); "player" is trivially true.
    -- Snapshot semantics: raid indices are volatile, so this
    -- is (re)taken at scan (re)start, never cached across roster events.
    -- Public: core/probe.lua reuses it for the probe battery.
    function E.BuildRoster()
        local list = {}
        local nraid = 0
        if GetNumRaidMembers then
            nraid = GetNumRaidMembers() or 0
        end
        if nraid > 0 then
            for i = 1, nraid do
                -- 11 returns on 1.12; fileName (english class token) is
                -- position 6, online position 8
                local ok, name, rank, subgroup, level, class, fileName,
                    zone, online = pcall(GetRaidRosterInfo, i)
                if ok and name then
                    local unit = "raid" .. i
                    local guid = nil
                    if UnitExists then
                        -- SuperWoW: 2nd return of UnitExists = GUID
                        local ok2, ex, g = pcall(UnitExists, unit)
                        if ok2 and ex and g then
                            guid = g
                        end
                    end
                    table.insert(list, {
                        unit = unit, name = name, class = fileName,
                        online = (online and true) or false,
                        guid = guid, subgroup = subgroup,
                    })
                end
            end
        else
            local units = { "player", "party1", "party2", "party3", "party4" }
            for i = 1, 5 do
                local unit = units[i]
                local exists = false
                local guid = nil
                if UnitExists then
                    local ok, ex, g = pcall(UnitExists, unit)
                    if ok and ex then
                        exists = true
                        if g then
                            guid = g
                        end
                    end
                end
                if exists then
                    local name = UnitName(unit)
                    local classToken = nil
                    if UnitClass then
                        local ok, loc, token = pcall(UnitClass, unit)
                        if ok then
                            classToken = token
                        end
                    end
                    -- party path has NO roster online flag: online stays
                    -- nil so scanOne falls back to the reach result;
                    -- the own unit is trivially online
                    local online = nil
                    if unit == "player" then
                        online = true
                    end
                    if name then
                        table.insert(list, {
                            unit = unit, name = name, class = classToken,
                            online = online, guid = guid, subgroup = nil,
                        })
                    end
                end
            end
        end
        return list
    end

    -- readWeapon(unit) -> weaponMain, weaponMainName
    -- (the NAME rides along -- self via the hidden-tooltip scan, foreign
    -- via the SuperWoW GetWeaponEnchantInfo(unit) name return)
    local function readWeapon(unit)
        if not GetWeaponEnchantInfo then
            return nil, nil
        end
        local isSelf = false
        if UnitIsUnit then
            local ok, v = pcall(UnitIsUnit, unit, "player")
            if ok and v then
                isSelf = true
            end
        end
        if isSelf then
            local ok, hasMain = pcall(GetWeaponEnchantInfo)
            if not ok then
                return nil, nil
            end
            local main = E.NormalizeWeapon(true, hasMain)
            local name = nil
            if main and DC_Gear and DC_Gear.ReadSelfWeaponEnchantName then
                name = DC_Gear.ReadSelfWeaponEnchantName()
            end
            return main, name
        end
        local ok, mainName = pcall(GetWeaponEnchantInfo, unit)
        if not ok then
            return nil, nil
        end
        -- A nil name is ambiguous on its own (see E.NormalizeWeapon): it means
        -- either "no imbue" or "this unit is not readable". The main-hand item
        -- link decides -- if the slot resolves, the unit IS readable and the
        -- missing imbue is a real gap. Measured: all 14 nil cases in a raid had
        -- a resolvable main hand, i.e. they were genuinely unbuffed.
        local readable = nil
        if mainName == nil and GetInventoryItemLink then
            local lok, link = pcall(GetInventoryItemLink, unit, 16)
            readable = (lok and link ~= nil) or false
        end
        return E.NormalizeWeapon(false, mainName, readable),
            E.NormalizeWeaponName(mainName)
    end

    local function bumpUnknown(unknown)
        local n = table.getn(unknown)
        for i = 1, n do
            local key = unknown[i]
            DC.unknownSeen[key] = (DC.unknownSeen[key] or 0) + 1
        end
    end

    -- readResists(unit, guid, isSelf, hit, race) -> resists, resistsRead,
    -- source (E.AssembleResists' three returns). WoW-only gather for the
    -- RESIST tab: three DIRECT read paths, each ATTEMPTED only once the
    -- earlier one has already proven unusable (skips the extra client
    -- calls on the common case -- token alone almost always answers for a
    -- same-zone unit) -- plus the gear-reconstruction fallback (see
    -- E.AssembleResists' header), which is why the caller now hands in the
    -- `hit`/`race` results of this SAME scan's hit read (scanOne runs the
    -- hit read before this call precisely so hit.resistGear/
    -- resistGearRead are available here; no extra client call of its own).
    -- School range 2..6 (fire/nature/frost/shadow/arcane); school 0
    -- (physical) and 1 (holy, always 0) are never queried.
    local function readResists(unit, guid, isSelf, hit, race)
        local tokenRows = {}
        if UnitResistance then
            for school = 2, 6 do
                local ok, base, total = pcall(UnitResistance, unit, school)
                table.insert(tokenRows, { school = school, ok = ok,
                    total = total })
            end
        end
        local guidRows = {}
        local fieldRows = {}
        -- A path counts as usable only if it produced EVIDENCE. For the
        -- own character any number is evidence (a real 0 resistance is a
        -- measurement). For a FOREIGN unit it is not: UnitResistance
        -- returns ok=true with total=0 for every school of a player the
        -- client cannot resolve, which is indistinguishable from a
        -- genuinely unresisted character. Treating that as "usable"
        -- claimed the token path and left the GUID and descriptor paths
        -- below unreachable -- so every foreign player read as UNKNOWN
        -- even though GetUnitField(guid, "resistances") had the numbers.
        local tokenUsable = false
        for i = 1, table.getn(tokenRows) do
            local r = tokenRows[i]
            if r.ok and type(r.total) == "number"
               and (isSelf or r.total > 0) then
                tokenUsable = true
            end
        end
        if not tokenUsable and guid and UnitResistance then
            -- SuperWoW accepts a GUID directly as the first argument on
            -- several UnitXXX calls (source-confirmed for mob armor;
            -- unverified for a player's elemental schools -- pcall-guarded
            -- and gated by the same honesty rule as every other path)
            for school = 2, 6 do
                local ok, base, total = pcall(UnitResistance, guid, school)
                table.insert(guidRows, { school = school, ok = ok,
                    total = total })
            end
        end
        local guidUsable = false
        for i = 1, table.getn(guidRows) do
            local r = guidRows[i]
            if r.ok and type(r.total) == "number"
               and (isSelf or r.total > 0) then
                guidUsable = true
            end
        end
        if not tokenUsable and not guidUsable and guid and GetUnitField then
            local ok, t = pcall(GetUnitField, guid, "resistances")
            if ok and type(t) == "table" then
                -- 7-entry table, index convention verified defensively:
                -- tried as 1-based for school 0..6 (t[school+1]); a
                -- non-number entry is simply skipped (AssembleResists
                -- also drops non-positive field values -- see its header)
                for school = 2, 6 do
                    table.insert(fieldRows, { school = school,
                        val = t[school + 1] })
                end
            end
        end
        local gearFallback = nil
        if hit then
            gearFallback = { resistGear = hit.resistGear,
                resistGearRead = hit.resistGearRead, race = race }
        end
        return E.AssembleResists(isSelf, tokenRows, guidRows, fieldRows,
            gearFallback)
    end

    -- scan one roster entry into a store player entry.
    -- Online source (measured in-game): the roster
    -- online flag (GetRaidRosterInfo return 8) is SERVER TRUTH and WINS
    -- over UnitIsConnected, which can read nil mid-zoning while the
    -- player is actually online (false-offline bug). ONLY entries
    -- without a roster flag (entry.online == nil, party path) fall back
    -- to the reach result. Distance stays from reach (diagnostic only).
    local function scanOne(entry)
        local reachOnline, distance = DC_Reach.ReadUnit(entry.unit)
        local online = entry.online
        if online == nil then
            online = reachOnline  -- no roster flag: reach fallback
        end

        local auraRes = nil
        local gearRes = nil
        local weaponMain = nil
        local weaponMainName = nil
        local resRes = nil
        local hitRes = nil

        if online then
            local rawA, rawB, rawDA, rawDB, idNames =
                DC_Aura.ReadUnit(entry.unit, entry.guid)
            local auras, aurasRead, disagreements, unknown =
                DC_Aura.Assemble(rawA, rawB, idNames)
            -- debuffs: assembled alongside, readability
            -- rides on aurasRead; debuff names NEVER feed DC.unknownSeen
            auraRes = { read = aurasRead, auras = auras,
                debuffs = DC_Aura.AssembleDebuffs(rawDA, rawDB) }
            bumpUnknown(unknown)

            -- diagnostic path coverage (plan: disagreements between path A
            -- and path B are counted into DC.probeStats)
            local ps = DC.probeStats
            local hadA = table.getn(rawA) > 0
            local hadB = table.getn(rawB) > 0
            if hadA then
                ps.unitsPathA = ps.unitsPathA + 1
                ps.lastScan.unitsA = ps.lastScan.unitsA + 1
            end
            if hadB then
                ps.unitsPathB = ps.unitsPathB + 1
                ps.lastScan.unitsB = ps.lastScan.unitsB + 1
            end
            if hadA and hadB then
                ps.unitsBoth = ps.unitsBoth + 1
                ps.lastScan.both = ps.lastScan.both + 1
            end
            ps.idDisagreements = ps.idDisagreements + disagreements
            ps.lastScan.disagreements = ps.lastScan.disagreements + disagreements

            local rawLinks = DC_Gear.ReadUnit(entry.unit)
            local gear, gearRead = DC_Gear.Assemble(rawLinks, DC_Gear.InvSlots(),
                DC_Gear.ItemInfo)
            gearRes = { read = gearRead, gear = gear }

            weaponMain, weaponMainName = readWeapon(entry.unit)

            local isSelf = false
            if UnitIsUnit then
                local ok, v = pcall(UnitIsUnit, entry.unit, "player")
                isSelf = (ok and v) and true or false
            end

            -- hit: the item links from the gear read above are handed over
            -- so the tooltip pass does not fetch them a second time.
            -- Declared OUTSIDE the if-block (unlike before this scope held
            -- only hitRes) because readResists below now needs `hit`/
            -- `race` too, for the gear-reconstruction fallback -- see
            -- E.AssembleResists' header for why the hit read must run
            -- BEFORE the resist read.
            local hit, race = nil, nil
            if DC_Hit and DC_Hit.ReadUnit then
                hit, race = DC_Hit.ReadUnit(entry.unit, rawLinks)
                if isSelf and hit and DC_Hit.ReadSelfSkill then
                    -- the own character is the ONLY one whose weapon skill
                    -- can be MEASURED (rank + modifier); for everyone else
                    -- it is unreadable in principle and stays an estimate
                    if hit.skillName then
                        local exact = DC_Hit.ReadSelfSkill(hit.skillName)
                        if exact then
                            hit.skill = exact
                            hit.skillExact = true
                        end
                    end
                    local rangedSkillName = DC.WEAPON_SKILL_OF_SUBTYPE
                        and DC.WEAPON_SKILL_OF_SUBTYPE[hit.rangedSub]
                    if rangedSkillName then
                        local rexact = DC_Hit.ReadSelfSkill(rangedSkillName)
                        if rexact then
                            hit.rangedSkill = rexact
                            hit.rangedSkillExact = true
                        end
                    end
                end
                -- estimate whatever was not measured: base skill + racial
                -- specialization + the user's per-player weapon-skill-book
                -- flag. Snapshot semantics -- a flag toggled after the scan
                -- reaches the display layer, not this table.
                if DC_Hit.ApplyEstimate then
                    local db = DopingControlDB
                    local books = nil
                    if db and db.skillBooks then
                        books = db.skillBooks[entry.name]
                    end
                    DC_Hit.ApplyEstimate(hit, race, books)
                end
                -- TALENT hit (data/talenthit.lua). TWO sources, ONE
                -- mathematics:
                --   * own character -- GetTalentInfo, which has no unit
                --     parameter and never will (the server transmits no
                --     foreign talents at all: no SMSG_INSPECT_TALENT in
                --     this fork, no talent field in InitVisibleBits);
                --   * every other player -- this server's own inspect
                --     protocol (scan/talents.lua): we ask by name, their
                --     client answers with its whole tree.
                -- Both hand the SAME name->rank table to the same
                -- DC_Hit.TalentHit, so a foreign hit number cannot drift
                -- from an own one. talentsRead stays false only while no
                -- plausible reply has arrived yet -- that is a "not yet",
                -- not "impossible". The dual-wield gate uses the weapon
                -- subtypes the item pass just resolved.
                if hit and DC_Hit.TalentHit then
                    local ranks = nil
                    if isSelf then
                        if DC_Hit.ReadSelfTalents then
                            ranks = DC_Hit.ReadSelfTalents()
                        end
                    elseif DC_Talents and DC_Talents.RanksFor then
                        ranks = DC_Talents.RanksFor(entry.name)
                    end
                    if ranks then
                        local dw = DC_Hit.DualWield(hit.mainSub, hit.offSub)
                        local t = DC_Hit.TalentHit(entry.class, ranks, dw)
                        hit.talentMelee = t.melee
                        hit.talentRanged = t.ranged
                        hit.talentSpell = t.spell
                        hit.talentOffhand = t.offhand
                        hit.talentSchools = t.schools
                        hit.talentsRead = true
                    end
                end
                hitRes = { hit = hit, race = race }
            end

            local resists, resistsRead, source =
                readResists(entry.unit, entry.guid, isSelf, hit, race)
            resRes = { read = resistsRead, resists = resists, source = source }
        end

        local p = E.BuildPlayer(entry, online, distance, auraRes, gearRes,
            weaponMain, weaponMainName, resRes, hitRes)
        -- last-known cache: successful channels refresh
        -- DC.lastKnown, failed channels get the cached references attached
        -- as p.last* -- display-only for the model (IRON RULE)
        local now = 0
        if GetTime then
            now = GetTime()
        end
        E.UpdateLastKnown(DC.lastKnown, p, now)
        table.insert(results, p)
    end

    -- one reused batch frame (allocating a throwaway frame per
    -- batch would leak; we use ONE named frame).
    -- CAUTION: hidden frames receive no OnUpdate on 1.12, so the frame is
    -- Show()n for the duration of a scan (it has no regions -- draws
    -- nothing) and Hide()n again in finish().
    local scanFrame = CreateFrame("Frame", "DopingControlScanFrame")
    scanFrame:Hide()

    local function beginQueue()
        queue = E.BuildRoster()
        results = {}
        DC.probeStats.lastScan =
            { unitsA = 0, unitsB = 0, both = 0, disagreements = 0 }
    end

    local function finish()
        running = false
        scanFrame:SetScript("OnUpdate", nil)
        scanFrame:Hide()
        -- cap-safety sweep on the last-known cache: runs on
        -- every finished pass, roster members are never evicted
        local rosterSet = {}
        for i = 1, table.getn(results) do
            rosterSet[results[i].name] = true
        end
        E.SweepLastKnown(DC.lastKnown, rosterSet, E.CACHE_CAP)
        local db = DopingControlDB
        if DC.SimOwnsStore(db) then
            -- Test mode OR demo mode was on (or switched on while this scan
            -- was in flight): the simulator fully replaces the data source
            -- ("real data never beats the simulation") -- drop the result.
            -- This is the load-bearing gate: it is the only thing between a
            -- finished scan and DC.store = E.NewStore(...) below.
            results = {}
            return
        end
        local now = 0
        if GetTime then
            now = GetTime()
        end
        DC.probeStats.scans = DC.probeStats.scans + 1
        -- Line up talent requests for everyone this scan actually saw
        -- (scan/talents.lua paces and de-duplicates them; a player whose
        -- talents we already hold is skipped there, not here). Only
        -- players with a KNOWN CLASS are worth asking: DC_Hit.TalentHit
        -- keys its table by class, so a reply we cannot attribute would be
        -- traffic for nothing. Own character excluded -- GetTalentInfo is
        -- authoritative and free for that one.
        if DC_Talents and DC_Talents.Request then
            local me = UnitName and UnitName("player") or nil
            local names = {}
            for i = 1, table.getn(results) do
                local p = results[i]
                if p.name and p.name ~= me and p.class and p.class ~= "" then
                    table.insert(names, p.name)
                end
            end
            DC_Talents.Request(names)
        end
        DC.store = E.NewStore(results, now)
        DC.storeInvalid = nil
        results = {}
        if type(DC.OnStoreUpdated) == "function" then
            DC.OnStoreUpdated()
        end
    end

    local function tick()
        if restartPending then
            -- roster changed mid-scan: indices volatile => full restart
            restartPending = false
            beginQueue()
        end
        local count = 0
        while table.getn(queue) > 0 and count < E.BATCH do
            local entry = table.remove(queue, 1)
            scanOne(entry)
            count = count + 1
        end
        if table.getn(queue) == 0 and not restartPending then
            finish()
        end
    end

    -- Start(force) -> bool (scan started/restarted).
    -- Already running: no-op unless force, which restarts with a fresh
    -- roster snapshot. DC.SimOwnsStore is NOT checked here -- an explicit
    -- Start is user intent, and the callers that are NOT user intent
    -- (READY_CHECK, the roster-change and window-open auto-scans) check it
    -- themselves. The scan may therefore run in test/demo mode; what it may
    -- never do is publish, so finish() drops the result instead.
    function E.Start(force)
        if running then
            if not force then
                return false
            end
            restartPending = true
            return true
        end
        running = true
        restartPending = false
        beginQueue()
        scanFrame:Show()  -- hidden frames get no OnUpdate on 1.12
        scanFrame:SetScript("OnUpdate", tick)
        tick()  -- first batch immediately (solo/party scans finish at once)
        return true
    end

    function E.IsRunning()
        return running
    end

    -- event wiring
    local eventFrame = CreateFrame("Frame", "DopingControlScanEventFrame")
    eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    -- READY_CHECK: unverified as a native 1.12 event -- register defensively
    pcall(eventFrame.RegisterEvent, eventFrame, "READY_CHECK")
    eventFrame:SetScript("OnEvent", function()
        if event == "READY_CHECK" then
            local db = DopingControlDB
            if db and db.readyCheckScan and not DC.SimOwnsStore(db) then
                E.Start()
            end
            return
        end
        -- RAID_ROSTER_UPDATE / PARTY_MEMBERS_CHANGED
        if running then
            restartPending = true
        elseif DC.store and DC.store.source == "scan" then
            DC.storeInvalid = true  -- finished store no longer matches roster
        end
    end)

end
