if WDI_DOPING_SKIP then return end -- DopingControl core/config.lua
-- SavedVariables defaults + fill-in: single DEFAULTS table, per-field fill-in
-- with nil-checks (NEVER 'or' for booleans -- would flip saved false),
-- copy-on-assign for table values so editing a live value can never mutate
-- the defaults.
-- Pure Lua 5.0, no WoW API -- dofile-loadable offline.

DopingControl = DopingControl or {}
local DC = DopingControl

-- SavedVariables root (the client replaces this global at ADDON_LOADED;
-- core/init.lua then calls DC.EnsureDefaults(DopingControlDB)).
DopingControlDB = DopingControlDB or {}

-- ------------------------------------------------------------------
-- Defaults
--
-- Two keys intentionally have NO entry here (a nil value cannot live in a
-- Lua table):
--   framePos     -- default nil = "no saved position, use the anchor
--                   default"; written by the UI on drag as
--                   { point=..., relPoint=..., x=..., y=... }.
--   expectations -- default nil = "not initialized yet"; EnsureDefaults
--                   special-cases it below: the saved shape
--                   is PER CLASS (db.expectations[role][class][slotId]),
--                   materialized/migrated from the DC.DEFAULT_EXPECT seed
--                   by DC.EnsureExpectations.
-- ------------------------------------------------------------------
DC.DEFAULTS = {
    testMode          = false,  -- /dc test: simulated raid
    showMinimapButton = true,
    minimapAngle      = 215,    -- degrees around the minimap rim
    readyCheckScan    = true,   -- auto-scan on READY_CHECK
    readyCheckOpen    = true,   -- auto-open window on READY_CHECK
    collapse          = {},     -- per-role collapsed flags, e.g. collapse.RANGED = true
    filterGapsOnly    = false,  -- toolbar filter All | Gaps only
    roles             = {},     -- confirmed roles keyed by player NAME
    -- Weapon skill books: db.skillBooks[playerName][weaponSkillName] =
    -- true|false. A quest weapon-skill book (+3 skill) is INVISIBLE on
    -- other players -- foreign weapon skill cannot be read at all (see
    -- data/hit.lua) -- so it is an opt-in the user ticks per player and
    -- per weapon skill; it only shifts that player's melee/ranged hit CAP.
    -- Unchecking stores an explicit false (never nil), exactly like the
    -- expectation grid, so "deliberately off" survives any later fill-in.
    -- The own character ignores these flags: its weapon skill is measured
    -- and a measured value already contains the book.
    skillBooks        = {},
}

-- ------------------------------------------------------------------
-- DC.SimOwnsStore(db) -> bool
--
-- The ONE owner predicate for DC.store, and the question every scan gate
-- asks -- never db.testMode alone. Both simulated modes replace the store
-- with the simulated raid, and while either is on "real data never beats
-- the simulation":
--   * db.testMode  -- /dc test, persisted (DEFAULTS above)
--   * DC.demoMode  -- /dc demo, transient (core/demo.lua)
--
-- Why it exists: the gates named db.testMode only, so a finished scan
-- overwrote the sim store while demo mode was still armed. The demo
-- expectation layer then graded the REAL raid against all six school
-- protection columns (five of which ship with no seed entry at all): every
-- raider grew fabricated MISSING cells, the banner vanished with the "sim"
-- source that had been the only marker that this is a mode and not a
-- measurement, and each row's whisper button went live against a real
-- player.
--
-- Why HERE and not in core/demo.lua, where the mode lives: config.lua loads
-- second, ahead of every gate that calls this, so the gates need no
-- load-order guard -- and a demo module that fails to load can never take
-- test mode's protection down with it (DC.demoMode is then simply nil).
--
-- db is optional; the fallback is for callers that do not hold one.
-- Always returns a real boolean -- the gates invert it.
-- ------------------------------------------------------------------
function DC.SimOwnsStore(db)
    db = db or DC.db or DopingControlDB
    if db and db.testMode then
        return true
    end
    if DC.demoMode then
        return true
    end
    return false
end

-- Generic deep copy (tables only; keys are copied by reference, values
-- recursively). No cycle handling -- config/expectation shapes are trees.
function DC.DeepCopy(src)
    if type(src) ~= "table" then
        return src
    end
    local out = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            out[k] = DC.DeepCopy(v)
        else
            out[k] = v
        end
    end
    return out
end

-- ------------------------------------------------------------------
-- Expectations: the saved shape is
-- PER CLASS --
--     db.expectations[role][class][slotId] = true|nil
-- with one class line for every class that can perform the role
-- (DC_Roles.ROLE_CLASSES, the ordered inversion of CLASS_ROLES).
-- DC.DEFAULT_EXPECT (data/expectations.lua) STAYS the role x slot SEED.
--
-- EnsureExpectations guarantees the full structure:
--   * first load (expectations == nil): every (role, performing class)
--     gets a deep copy of the seed's role line.
--   * legacy saved tables (one line per role) -- detected by BOOLEANS directly under
--     [role] (new-shape values are class tables) -- are MIGRATED: the
--     old role line is copied to every performing class, then the
--     structure is replaced. User edits survive on every class where
--     they are representable.
--   * new-shape tables: existing class lines are NEVER touched; missing
--     (role,class) combos are filled from the seed. The fill is
--     behavior-neutral -- the model resolves a missing combo to the
--     DC.DEFAULT_EXPECT role line anyway (runtime fallback) -- it only
--     hands the options grid a complete structure.
-- Known ambiguity (accepted): an old-shape role line with EVERY slot
-- unchecked is {} and indistinguishable from an untouched new-shape
-- role table (the boolean marker is gone); it is re-seeded per class.
--
-- Resolved at CALL time, not file-load time: data/expectations.lua and
-- core/roles.lua load after this file (TOC order const -> config ->
-- data/* -> model -> roles), but EnsureDefaults only runs at
-- ADDON_LOADED when everything is in. Offline callers without DC_Roles
-- loaded simply skip the expectations block.
-- ------------------------------------------------------------------
local function isOldShapeLine(line)
    for _, v in pairs(line) do
        if type(v) == "boolean" then
            return true
        end
    end
    return false
end

-- Top up ONE class line in place: slots the seed marks true and the line
-- has NEVER SEEN (nil) become true. Deliberate unchecks survive (the
-- options grid stores those as explicit false, never nil). Shared by both
-- EnsureExpectations branches below so a freshly migrated line is already
-- complete -- not just on the SECOND call (idempotency: a migration must
-- converge in one pass, not two).
local function topUpLine(cl, seedLine)
    for slotId, v in pairs(seedLine) do
        if v == true and cl[slotId] == nil then
            cl[slotId] = true
        end
    end
end

function DC.EnsureExpectations(db)
    if DC.DEFAULT_EXPECT == nil or DC_Roles == nil
       or DC_Roles.ROLE_CLASSES == nil then
        return
    end
    if db.expectations == nil then
        db.expectations = {}
    end
    local exp = db.expectations
    local nRoles = table.getn(DC.ROLES)
    for r = 1, nRoles do
        local role = DC.ROLES[r]
        local classes = DC_Roles.ROLE_CLASSES[role] or {}
        local nClasses = table.getn(classes)
        local line = exp[role]
        local seedLine = DC.DEFAULT_EXPECT[role] or {}
        if line ~= nil and isOldShapeLine(line) then
            -- migration: copy the old role line to every performing
            -- class, then top up each new class line from the CURRENT
            -- seed (a slot added since the old line was saved must reach
            -- it immediately, not only on a later call -- see topUpLine),
            -- then replace the structure (never lose user edits where
            -- representable)
            local byClass = {}
            for c = 1, nClasses do
                local cl = DC.DeepCopy(line)
                topUpLine(cl, seedLine)
                byClass[classes[c]] = cl
            end
            exp[role] = byClass
        else
            if line == nil then
                line = {}
                exp[role] = line
            end
            -- fill missing (role,class) combos from the seed; existing
            -- class lines keep their values, but slots the seed knows
            -- and the line has NEVER SEEN (nil) are topped up -- without
            -- this, a slot added in a later version never reaches saved
            -- lines (field report: neck/ring columns arrived as "not
            -- expected" for everyone). Deliberate unchecks survive: the
            -- options grid stores them as explicit false, never nil.
            for c = 1, nClasses do
                local cls = classes[c]
                if line[cls] == nil then
                    line[cls] = DC.DeepCopy(seedLine)
                else
                    topUpLine(line[cls], seedLine)
                end
            end
        end
    end
end

-- Fill missing fields in db from DC.DEFAULTS. Existing values -- including
-- saved booleans that are false -- are never touched. Table defaults are
-- deep-copied on assign.
function DC.EnsureDefaults(db)
    for k, v in pairs(DC.DEFAULTS) do
        if db[k] == nil then
            if type(v) == "table" then
                db[k] = DC.DeepCopy(v)
            else
                db[k] = v
            end
        end
    end
    -- expectations: per-(role,class) shape, materialized/migrated from
    -- the DC.DEFAULT_EXPECT seed (see EnsureExpectations above)
    DC.EnsureExpectations(db)
    return db
end

-- Reset the whole config IN PLACE (keeps the table reference -- the client
-- saves the global DopingControlDB, so the reference must survive).
function DC.ResetConfig(db)
    for k in pairs(db) do
        db[k] = nil
    end
    return DC.EnsureDefaults(db)
end

-- Reset only the expectation matrix to the DC.DEFAULT_EXPECT seed,
-- materialized per (role, performing class) -- options button
-- "Reset expectations" (reseeds ALL classes).
function DC.ResetExpectations(db)
    db.expectations = nil
    DC.EnsureDefaults(db)
    return db.expectations
end
