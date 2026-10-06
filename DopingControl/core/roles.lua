if WDI_DOPING_SKIP then return end -- DopingControl core/roles.lua
-- Role suggestion heuristic + confirmed-role resolution: five roles, the
-- role hangs on the player NAME, and no heuristic ever decides silently --
-- a suggestion is always flagged as such and carries a reason string.
-- Badge UX: CLASS_ROLES = ordered plausible roles per class, cycle() =
-- badge right-click (step + immediate confirm).
-- Per-class expectations:
-- ROLE_CLASSES = generated inversion of CLASS_ROLES (ordered classes per
-- role) -- the domain of db.expectations[role][class].
-- Pure Lua 5.0, no WoW API -- dofile-loadable offline.

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Roles = DC_Roles or {}

-- Transient confirmations for the simulated raid (test mode). NEVER written
-- to SavedVariables: synthetic names must not pollute db.roles.
-- Reset by DC_Sim.buildStore() on every (re-)entry into test mode.
DC.simRoles = DC.simRoles or {}

-- ------------------------------------------------------------------
-- Plausible roles per class token, ORDERED (the order is
-- the badge right-click cycle order). suggest() below must only ever
-- return a role CONTAINED in the class's list -- property-tested over
-- every class x fact combination in the offline test suite.
-- ------------------------------------------------------------------
DC_Roles.CLASS_ROLES = {
    WARRIOR = { "MELEE", "TANK" },
    ROGUE   = { "MELEE" },
    HUNTER  = { "RANGED", "MELEE" },  -- melee hunter is a real spec on TWoW
    MAGE    = { "CASTER" },
    WARLOCK = { "CASTER" },
    PRIEST  = { "HEALER", "CASTER" },
    DRUID   = { "HEALER", "TANK", "MELEE", "CASTER" },
    SHAMAN  = { "HEALER", "TANK", "MELEE", "CASTER" },
    PALADIN = { "HEALER", "TANK", "MELEE" },
}

-- ------------------------------------------------------------------
-- Per-class expectations:
-- ROLE_CLASSES = the INVERSION of CLASS_ROLES -- for each role the
-- ordered list of class tokens that can perform it, in the fixed
-- class order below, filtered per role. GENERATED from CLASS_ROLES so
-- the two tables can never drift apart.
-- Consumers: core/config.lua materializes db.expectations[role][class]
-- over exactly these lists, core/model.lua iterates them for the
-- dynamic-column check, and the options expectation grid renders one
-- indented class row per entry.
-- ------------------------------------------------------------------
DC_Roles.CLASS_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

DC_Roles.ROLE_CLASSES = {}
do
    -- fresh tables on every (re-)load -- regeneration, not accretion
    local inv = DC_Roles.ROLE_CLASSES
    for i = 1, table.getn(DC_Roles.CLASS_ORDER) do
        local cls = DC_Roles.CLASS_ORDER[i]
        local list = DC_Roles.CLASS_ROLES[cls] or {}
        for j = 1, table.getn(list) do
            local role = list[j]
            if inv[role] == nil then
                inv[role] = {}
            end
            table.insert(inv[role], cls)
        end
    end
end

-- ------------------------------------------------------------------
-- Facts extraction: derive the suggestion facts from a store player entry.
-- Works on both aura paths: form NAMES from
-- the tooltip path, form SPELL IDS from the GUID path (which delivers ids
-- only).
-- [ASSUMPTION] Form aura spell IDs (vanilla 1.12): Cat Form 768, Bear Form
-- 5487, Dire Bear Form 9634, Moonkin Form 24858, Shadowform 15473.
-- ------------------------------------------------------------------
DC_Roles.FORM_NAMES = {
    ["Cat Form"]      = "catForm",
    ["Bear Form"]     = "bearForm",
    ["Dire Bear Form"] = "bearForm",
    ["Moonkin Form"]  = "moonkin",
    ["Shadowform"]    = "shadowform",
}

DC_Roles.FORM_IDS = {
    [768]   = "catForm",
    [5487]  = "bearForm",
    [9634]  = "bearForm",
    [24858] = "moonkin",
    [15473] = "shadowform",
}

function DC_Roles.factsFor(player)
    local facts = {
        hasShield = false, catForm = false, bearForm = false,
        shadowform = false, moonkin = false,
    }
    if not player then
        return facts
    end
    if player.aurasRead and player.auras then
        if player.auras.names then
            for name, key in pairs(DC_Roles.FORM_NAMES) do
                if player.auras.names[name] then
                    facts[key] = true
                end
            end
        end
        if player.auras.ids then
            for id, key in pairs(DC_Roles.FORM_IDS) do
                if player.auras.ids[id] then
                    facts[key] = true
                end
            end
        end
    end
    if player.gearRead and player.gear then
        local off = player.gear[17]  -- off hand inventory slot
        if type(off) == "table" and off.subType == "Shields" then
            facts.hasShield = true
        end
    end
    return facts
end

-- ------------------------------------------------------------------
-- Suggestion heuristic. ALWAYS returns a
-- (role, reason) pair -- no suggestion without a stated reason (the badge
-- tooltip shows it).
-- ------------------------------------------------------------------
function DC_Roles.suggest(class, facts)
    facts = facts or {}
    if class == "WARRIOR" then
        if facts.hasShield then
            return "TANK", "shield equipped"
        end
        return "MELEE", "class default"
    elseif class == "ROGUE" then
        return "MELEE", "class default"
    elseif class == "HUNTER" then
        return "RANGED", "class default"
    elseif class == "MAGE" then
        return "CASTER", "class default"
    elseif class == "WARLOCK" then
        return "CASTER", "class default"
    elseif class == "PRIEST" then
        if facts.shadowform then
            return "CASTER", "Shadowform at scan time"
        end
        return "HEALER", "class default"
    elseif class == "DRUID" then
        -- form precedence: bear > cat > moonkin > none (a druid can only be
        -- in one form at a time; the order only matters for garbage input)
        if facts.bearForm then
            return "TANK", "Bear Form at scan time"
        end
        if facts.catForm then
            return "MELEE", "Cat Form at scan time"
        end
        if facts.moonkin then
            return "CASTER", "Moonkin Form at scan time"
        end
        return "HEALER", "class default"
    elseif class == "SHAMAN" then
        -- deliberately NOT shield->MELEE: resto shamans
        -- carry shields too, so a shield is no enhancement signal here.
        -- Plain class default; enhancers get confirmed by hand once.
        return "HEALER", "class default"
    elseif class == "PALADIN" then
        if facts.hasShield then
            return "TANK", "shield equipped"
        end
        return "HEALER", "class default"
    end
    -- unknown class token: still return a pair, never nil
    return "MELEE", "unknown class"
end

-- ------------------------------------------------------------------
-- Resolution: confirmed role wins over suggestion.
--   source "sim"  -> confirmations live ONLY in DC.simRoles (transient);
--                    db.roles is never consulted and never written for
--                    simulated players (synthetic names must
--                    not end up in SavedVariables).
--   source "scan" -> confirmations live in db.roles (persistent, keyed by
--                    player name).
-- Returns role, suggested(bool), reason(string|nil):
--   confirmed  -> (role, false, nil)
--   suggested  -> (role, true, reason)
-- ------------------------------------------------------------------
function DC_Roles.resolve(db, storeSource, player)
    local name = player and player.name
    local confirmed
    if storeSource == "sim" then
        confirmed = name and DC.simRoles[name]
    else
        confirmed = name and db and db.roles and db.roles[name]
    end
    if confirmed then
        return confirmed, false, nil
    end
    local role, reason = DC_Roles.suggest(player and player.class,
                                          DC_Roles.factsFor(player))
    return role, true, reason
end

-- Confirm a role (badge LEFT-click). Same routing rule as resolve().
function DC_Roles.confirm(db, storeSource, name, role)
    if storeSource == "sim" then
        DC.simRoles[name] = role
    else
        db.roles[name] = role
    end
end

-- ------------------------------------------------------------------
-- cycle(db, storeSource, name, class, currentRole) -> nextRole
-- Badge RIGHT-click: step to the entry AFTER currentRole
-- in CLASS_ROLES[class] (wrapping; currentRole not in the list -> the
-- FIRST entry) and CONFIRM it immediately -- same persistence routing as
-- confirm() (sim source -> DC.simRoles, else db.roles).
-- Single-entry classes wrap onto themselves (the UI treats right-click
-- as a no-op there and never calls this; calling it anyway is harmless:
-- the same role comes back and is re-confirmed).
-- Unknown class token: no list -> currentRole returned unchanged and
-- NOTHING confirmed (defensive; scan classes are always known tokens).
-- ------------------------------------------------------------------
function DC_Roles.cycle(db, storeSource, name, class, currentRole)
    local list = DC_Roles.CLASS_ROLES[class]
    if not list or table.getn(list) == 0 then
        return currentRole
    end
    local n = table.getn(list)
    local nextRole = list[1]
    for i = 1, n do
        if list[i] == currentRole then
            nextRole = list[math.mod(i, n) + 1]
            break
        end
    end
    DC_Roles.confirm(db, storeSource, name, nextRole)
    return nextRole
end
