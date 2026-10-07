if WDI_DOPING_SKIP then return end -- DopingControl scan/reach.lua
-- Unit readability probe: online FALLBACK via UnitIsConnected, distance via
-- UnitXP_SP3 "distanceBetween". Distance is DIAGNOSTIC ONLY -- it is written
-- into the store but NEVER used as a filter (readability is
-- decided from the read RESULT, not from a range assumption).
--
-- ONLINE IS A FALLBACK ONLY (measured
-- in-game): the raid roster online flag (GetRaidRosterInfo return 8) is
-- SERVER TRUTH and wins in scan/engine.lua scanOne -- UnitIsConnected can
-- read nil mid-zoning while the player is actually online (false-offline
-- bug). The reach online result is only consulted for roster entries
-- WITHOUT a roster flag (the party path).
--
-- Pure Lua 5.0, dofile-loadable offline: the WoW calls live in ReadUnit,
-- which is only invoked in-game; Normalize is pure and offline-tested.

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Reach = DC_Reach or {}
local R = DC_Reach

-- ------------------------------------------------------------------
-- Normalize(haveOnline, onlineRaw, distOk, distVal) -> online, distance
--   haveOnline : bool  -- UnitIsConnected existed AND its pcall succeeded.
--                        UnitIsConnected returns 1/nil, where nil is read
--                        as offline -- BUT it can also read nil mid-zoning
--                        while the player is online (measured in-game),
--                        which is why the engine only uses this value as a
--                        fallback when there is no roster online flag.
--   onlineRaw  : raw UnitIsConnected return (1/nil/false)
--   distOk     : pcall success of UnitXP("distanceBetween", ...)
--   distVal    : its first return
-- Returns:
--   online   : true|false|nil  -- nil = could not determine; the caller
--                                 (engine scanOne) consults this at all
--                                 only for entries without a roster flag
--   distance : number|nil      -- nil = not measurable (no UnitXP_SP3, or
--                                 the call failed / returned a non-number)
-- ------------------------------------------------------------------
function R.Normalize(haveOnline, onlineRaw, distOk, distVal)
    local online = nil
    if haveOnline then
        if onlineRaw then
            online = true
        else
            online = false
        end
    end
    local distance = nil
    if distOk and type(distVal) == "number" then
        distance = distVal
    end
    return online, distance
end

-- ------------------------------------------------------------------
-- ReadUnit(unit) -> online, distance   (WoW runtime only)
-- Every foreign-unit call is pcall-wrapped (hard rule).
-- Missing UnitXP_SP3 only drops the diagnostic distance
-- -- the online read runs regardless.
-- ------------------------------------------------------------------
function R.ReadUnit(unit)
    local haveOnline = false
    local onlineRaw = nil
    if UnitIsConnected then
        local ok, v = pcall(UnitIsConnected, unit)
        if ok then
            haveOnline = true
            onlineRaw = v
        end
    end
    local distOk = false
    local distVal = nil
    if UnitXP then
        distOk, distVal = pcall(UnitXP, "distanceBetween", "player", unit)
    end
    return R.Normalize(haveOnline, onlineRaw, distOk, distVal)
end
