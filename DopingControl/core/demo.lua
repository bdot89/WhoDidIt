if WDI_DOPING_SKIP then return end -- DopingControl core/demo.lua
-- Demo mode: the showcase view. It reuses test mode's simulated raid
-- (DC_Sim.buildStore -- no second roster exists) and lays its OWN
-- expectation table on top so ALL SIX school protection columns
-- (FR/FrR/NR/SR/HR/AR) are visible at once.
--
-- Two hard rules, both of them the reason this file exists at all:
--
--   1. The demo layer NEVER writes into db.expectations. Live, five of the
--      six school columns ship with no seed entry (data/expectations.lua)
--      and are therefore hidden -- that is a deliberate default, and a
--      screenshot mode must not rewrite the user's saved matrix to get its
--      picture. BuildDemoExpectations deep-copies every line it starts
--      from, so no table is ever shared with the DB either.
--   2. Demo state is TRANSIENT -- DC.demoMode / DC.demoExpectations live in
--      memory only and are gone after a reload. Deliberately unlike
--      db.testMode (which is persisted): the same treatment DC.simRoles
--      gets in core/roles.lua, and the BulwarkFrame /bf demo pattern.
--
-- Why the columns must be forced per (role, class) and not per role: the
-- model resolves a row through expect[role][class] and falls back to the
-- DC.DEFAULT_EXPECT ROLE line whenever that class line is missing
-- (core/model.lua, expectLine) -- a partially filled demo table would fall
-- back into the seed and silently lose the school columns again. The same
-- fallback drives the dynamic-column check (anyClassExpects), so an
-- incomplete layer would also drop the columns from the header.
--
-- FR is forced too, although the seed already ships it true for all five
-- roles: the user may have unchecked it, and "all six schools" is the
-- point of the mode.
--
-- Pure Lua 5.0, no WoW API -- dofile-loadable offline.

DopingControl = DopingControl or {}
local DC = DopingControl

-- ------------------------------------------------------------------
-- Transient state (NEVER SavedVariables -- see rule 2 above).
-- ------------------------------------------------------------------
DC.demoMode = false
DC.demoExpectations = nil

-- DC.demoMode is the demo half of DC.SimOwnsStore (core/config.lua) -- the
-- predicate every scan gate asks. It deliberately lives in config.lua, not
-- here: config.lua loads second, ahead of every gate, so a broken demo
-- module can never take TEST mode's protection down with it.

-- The six school protection columns of the consumables slot table
-- (data/consumables.lua). FR is the only one with a seed entry.
DC.DEMO_SCHOOL_SLOTS = { "FR", "FrR", "NR", "SR", "HR", "AR" }

local function forceSchools(line)
    local n = table.getn(DC.DEMO_SCHOOL_SLOTS)
    for i = 1, n do
        line[DC.DEMO_SCHOOL_SLOTS[i]] = true
    end
end

-- ------------------------------------------------------------------
-- DC.BuildDemoExpectations(db) -> demo table (also cached in
-- DC.demoExpectations)
--
-- Shape is exactly the live one -- demo[role][class][slotId] -- built per
-- (role, performing class) over DC_Roles.ROLE_CLASSES, so it can be handed
-- to DC_Model.build in place of db.expectations without any special case
-- in the model.
--
-- Source per class line, in order: the user's saved line, else the
-- DC.DEFAULT_EXPECT seed line -- deep-copied either way, then the six
-- school slots forced on. A legacy old-shape role line (booleans directly
-- under [role], migrated away by DC.EnsureExpectations at ADDON_LOADED)
-- is not a table per class and therefore falls back to the seed; demo mode
-- showing seed defaults for one session is acceptable, writing into the DB
-- to avoid it is not.
-- ------------------------------------------------------------------
function DC.BuildDemoExpectations(db)
    local src = db and db.expectations
    local out = {}
    local nRoles = table.getn(DC.ROLES)
    for r = 1, nRoles do
        local role = DC.ROLES[r]
        local seedLine = (DC.DEFAULT_EXPECT and DC.DEFAULT_EXPECT[role]) or {}
        local savedByClass = src and src[role]
        local classes = (DC_Roles and DC_Roles.ROLE_CLASSES
                         and DC_Roles.ROLE_CLASSES[role]) or {}
        local nClasses = table.getn(classes)
        if nClasses > 0 then
            local byClass = {}
            for c = 1, nClasses do
                local cls = classes[c]
                local saved = savedByClass and savedByClass[cls]
                local line
                if type(saved) == "table" then
                    line = DC.DeepCopy(saved)
                else
                    line = DC.DeepCopy(seedLine)
                end
                forceSchools(line)
                byClass[cls] = line
            end
            out[role] = byClass
        else
            -- defensive: without DC_Roles there is no class domain to fill,
            -- so emit the legacy role x slot line (the model falls back to
            -- the seed for the cells, but the header tooltip and any
            -- legacy reader still see the schools)
            local line = DC.DeepCopy(seedLine)
            forceSchools(line)
            out[role] = line
        end
    end
    DC.demoExpectations = out
    return out
end

-- ------------------------------------------------------------------
-- DC.SetDemoMode(v) -- the switch behind /dc demo and the options button.
-- Mirrors DC.SetTestMode (core/init.lua) but touches no SavedVariables.
--
-- Store handling: entering demo mode swaps in the simulated raid. Leaving
-- it hands the store back to the REAL scan -- unless db.testMode is on,
-- which owns the simulated store on its own account and must not be kicked
-- out of it. DC.SetTestMode mirrors that in the other direction, so neither
-- mode can empty the other's showcase; both ask DC.SimOwnsStore
-- (core/config.lua), which is also what every scan gate now asks instead
-- of db.testMode.
-- ------------------------------------------------------------------
function DC.SetDemoMode(v)
    local db = DC.db or DopingControlDB
    if v then
        DC.demoMode = true
        DC.BuildDemoExpectations(db)
        if DC_Sim and DC_Sim.buildStore then
            -- buildStore() also refills the transient DC.simRoles -- do NOT
            -- wipe them afterwards (see DC.SetTestMode)
            DC.store = DC_Sim.buildStore()
        end
    else
        DC.demoMode = false
        DC.demoExpectations = nil
        if not (db and db.testMode) then
            DC.store = { players = {}, source = "scan" }
            if DC_Scan and DC_Scan.Start then
                DC_Scan.Start(true)  -- leaving demo mode: immediate rescan
            end
        end
    end
    if DC_Matrix and DC_Matrix.Refresh then
        DC_Matrix.Refresh()
    end
    if DC_Options and DC_Options.Refresh then
        DC_Options.Refresh()  -- relabels the options button when it is open
    end
end
