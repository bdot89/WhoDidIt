if WDI_DOPING_SKIP then return end -- DopingControl scan/talents.lua
-- Reading OTHER players' talents.
--
-- Why this file exists: talents raise hit (Precision, Elemental Precision,
-- Shadow Focus, Suppression, ...), so a hit number that omits them is
-- systematically LOW. GetTalentInfo has no unit parameter and the server
-- never transmits foreign talents (no SMSG_INSPECT_TALENT in this fork,
-- no talent field in InitVisibleBits or SMSG_PARTY_MEMBER_STATS).
--
-- This server nonetheless ships its OWN inspect protocol, and it is a
-- plain addon-message conversation any addon may hold.
--
--   ask    SendAddonMessage("TW_CHAT_MSG_WHISPER<Name>", "INSTalentShow",
--                           "GUILD")
--   reply  the TARGET's client runs GetTalentInfo on ITSELF and sends one
--          message per line:
--            INSTalentTabInfo;<tree>;<treeName>;<pointsSpent>;<numTalents>
--            INSTalentInfo;<tree>;<index>;<name>;<tier>;<column>;
--                          <currRank>;<maxRank>;<meetsPrereq>;
--                          <ptier>;<pcolumn>;<isLearnable>
--            INSTalentEND;
--
-- Cost, as observed: ONE outgoing message per player; the reply is a few
-- dozen messages, ending in INSTalentEND.
--
-- Three properties of the reply path decide the design here:
--
--   * The answering client checks NOTHING -- no CanInspect, no group,
--     guild, range or visibility test. Anyone whose NAME we know answers.
--     So the limit has to be ours: we only ask for players the scan
--     actually shows (ASK_GAP apart, each name at most REASK_AFTER), and
--     the whole sender can be switched off.
--   * We cannot ask for single talents. What gets sent is decided by the
--     target's client (Turtle's own code in patch-9.mpq), not by us -- it
--     dumps the whole tree. Our outgoing traffic is one message per
--     player; everything else is inbound and we drop the lines we do not
--     need.
--   * 1.12's wire format is PREFIX<TAB>MESSAGE, and the server rewrites
--     the "<Name>" tag out of the prefix on the way -- which leaves the
--     TAB at the HEAD OF THE PAYLOAD (measured: first bytes 9 73 78 83).
--     An anchored match on "INS..." therefore fails on every single line.
--     T.Normalize is not cosmetic; without it the whole reply is dropped.
--
-- The pure half (Normalize/Parse/Feed/Plausible/ShouldAsk) is offline
-- tested under real Lua 5.0; only the frame, the event and SendAddonMessage
-- are in-game.

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Talents = DC_Talents or {}
local T = DC_Talents

-- addon-message prefix of the protocol (ours to send, theirs to answer on)
T.PREFIX = "TW_CHAT_MSG_WHISPER"
-- the channel argument is INERT once a "<Name>" tag is in the prefix (the
-- tag is the whisper substitute) -- kept exactly as Turtle's own UI sends
-- it, because a value the server does not expect is a needless risk
T.CHANNEL = "GUILD"
T.ASK_MSG = "INSTalentShow"

-- seconds between two outgoing requests (any target). Nothing documents a
-- rate limit for THIS protocol, so the number is deliberately timid: one
-- request per this many seconds is far below what Turtle's own UI produces
-- when a player clicks through an inspect window.
T.ASK_GAP = 5
-- do not ask the same player again for this long. Talents change on
-- respec, which is rare and never mid-raid.
T.REASK_AFTER = 1800
-- how long an unfinished reply stays open. A whole reply lands within a
-- fraction of a second, so a line arriving this much later cannot belong to
-- it -- it is the start of a NEW reply and must not be folded into the old
-- accumulator (see T.AccStale).
T.ACC_TTL = 10

-- ==================================================================
-- PURE SECTION (offline-testable)
-- ==================================================================

-- Strip the leading wire separator. See the header: the payload arrives as
-- <TAB>INSTalent... because the server rewrote the name tag out of the
-- prefix. Leading spaces/CR/LF are stripped too -- cheap, and it keeps the
-- parser from depending on which whitespace the transport happens to leave.
function T.Normalize(msg)
    if type(msg) ~= "string" then
        return ""
    end
    return (string.gsub(msg, "^[ \t\r\n]+", ""))
end

-- Split on ";" -- Lua 5.0 has no string.split and no gmatch. Empty fields
-- are preserved (the protocol uses fixed positions, so a dropped empty
-- field would shift every later one).
local function split(s)
    local out, from = {}, 1
    while true do
        local i = string.find(s, ";", from, true)
        if not i then
            table.insert(out, string.sub(s, from))
            break
        end
        table.insert(out, string.sub(s, from, i - 1))
        from = i + 1
    end
    return out
end

-- Classify + decode one payload.
-- Returns "tab", { tree, treeName, spent, numTalents }
--      or "talent", { tree, index, name, tier, column, rank, maxRank }
--      or "end", nil
--      or nil (not ours -- every other addon's traffic lands here too)
--
-- A talent line with a MISSING or non-numeric rank is rejected rather than
-- read as 0: a silently zeroed rank looks exactly like an untrained talent
-- and would understate hit without any sign that something went wrong.
function T.Parse(msg)
    msg = T.Normalize(msg)
    if msg == "" then
        return nil
    end
    if string.find(msg, "INSTalentEND", 1, true) == 1 then
        return "end", nil
    end
    if string.find(msg, "INSTalentTabInfo;", 1, true) == 1 then
        local f = split(msg)
        local tree = tonumber(f[2])
        local spent = tonumber(f[4])
        if not tree or not spent then
            return nil
        end
        return "tab", { tree = tree, treeName = f[3], spent = spent,
                        numTalents = tonumber(f[5]) }
    end
    if string.find(msg, "INSTalentInfo;", 1, true) == 1 then
        local f = split(msg)
        local tree = tonumber(f[2])
        local name = f[4]
        local rank = tonumber(f[7])
        if not tree or type(name) ~= "string" or name == "" or not rank then
            return nil
        end
        return "talent", { tree = tree, index = tonumber(f[3]), name = name,
                           tier = tonumber(f[5]), column = tonumber(f[6]),
                           rank = rank, maxRank = tonumber(f[8]) }
    end
    return nil
end

-- A per-sender accumulator. Shape:
--   { ranks = { [talentName] = rank },  -- rank > 0 only, like the own read
--     spent = <sum of pointsSpent over the trees that reported>,
--     sumRank = <sum of every rank we stored>,
--     trees = <how many tab lines arrived>,
--     complete = <INSTalentEND seen>,
--     at = <when the first line arrived, nil offline> }
function T.NewAcc(now)
    return { ranks = {}, spent = 0, sumRank = 0, trees = 0, complete = false,
             at = now }
end

-- Has this accumulator been waiting so long that the next line must belong to
-- a different reply? Only the END marker drops an accumulator, so a reply
-- whose tail was lost would otherwise stay open forever and swallow the next
-- one: tab lines add up twice while ranks are deduplicated by name, so
-- T.Plausible rejects a perfectly good retry. Without a clock (offline) or an
-- opening stamp nothing expires -- the old behaviour, unchanged.
function T.AccStale(acc, now)
    if not acc or not acc.at or not now then
        return false
    end
    return (now - acc.at) > T.ACC_TTL
end

-- Fold one parsed line into the accumulator. Returns the accumulator so
-- callers can chain; `complete` flips exactly once, on the END marker.
function T.Feed(acc, kind, data)
    if not acc or not kind then
        return acc
    end
    if kind == "end" then
        acc.complete = true
        return acc
    end
    if kind == "tab" and data then
        acc.trees = acc.trees + 1
        acc.spent = acc.spent + (data.spent or 0)
        return acc
    end
    if kind == "talent" and data and data.rank and data.rank > 0 then
        -- keyed BY NAME, because that is what DC.TALENT_HIT matches on
        -- (data/talenthit.lua) and what ReadSelfTalents produces -- the two
        -- paths must hand DC_Hit.TalentHit the same shape or they would
        -- drift apart silently
        if not acc.ranks[data.name] then
            acc.sumRank = acc.sumRank + data.rank
            acc.ranks[data.name] = data.rank
        end
    end
    return acc
end

-- Consistency gate before a reply is believed.
--
-- The client that answered told us two independent things: how many points
-- it spent per tree, and every individual rank. They must agree. They are
-- computed from the same source on the far side, so agreement does not
-- prove the data is FRESH -- but disagreement proves we mis-parsed or lost
-- messages, and that is exactly the failure this protects against (a
-- half-received tree would understate hit while looking perfectly normal).
--
-- All three trees must have reported; a talentless character legitimately
-- sends three empty tab lines and zero talent lines, which passes.
function T.Plausible(acc)
    if not acc or not acc.complete then
        return false
    end
    if acc.trees < 3 then
        return false
    end
    return acc.sumRank == acc.spent
end

-- Throttle decision, pure so the whole policy is testable without a client.
--   asked   = { [name] = <time we last asked> }
--   lastAny = <time of the last request to ANYBODY>
function T.ShouldAsk(name, now, asked, lastAny)
    if type(name) ~= "string" or name == "" then
        return false
    end
    now = now or 0
    if lastAny and (now - lastAny) < T.ASK_GAP then
        return false
    end
    local last = asked and asked[name]
    if last and (now - last) < T.REASK_AFTER then
        return false
    end
    return true
end

-- ==================================================================
-- WOW SECTION -- frame, event, sending
-- ==================================================================
if CreateFrame then

    local acc = {}        -- [sender] = accumulator, dropped once complete
    local ranks = {}      -- [sender] = { [talent] = rank }, the result
    local readAt = {}     -- [sender] = when that result landed
    local asked = {}      -- [name] = when we last asked
    local lastAny = nil   -- when we last asked anybody
    local queue = {}      -- names waiting to be asked
    local queued = {}     -- [name] = true, so the queue cannot hold dupes

    local function enabled()
        local d = DopingControlDB
        -- default ON: an addon that computes hit and silently leaves out a
        -- readable component is the bug this file fixes
        return not (d and d.readTalents == false)
    end

    -- ranks for a player, or nil if we have not got a plausible reply yet.
    -- nil (not {}) is load-bearing, exactly as for the own character:
    -- "not read" and "read, no talents" are different states and only the
    -- second one may count as a measured zero.
    function T.RanksFor(name)
        return ranks[name]
    end

    function T.ReadAt(name)
        return readAt[name]
    end

    -- diagnostics for /dc talents
    function T.Stats()
        local nRanks, nPending = 0, 0
        for _ in pairs(ranks) do
            nRanks = nRanks + 1
        end
        for _ in pairs(acc) do
            nPending = nPending + 1
        end
        return { known = nRanks, pending = nPending,
                 queued = table.getn(queue), enabled = enabled() }
    end

    function T.Ask(name)
        if not enabled() or type(name) ~= "string" or name == "" then
            return false
        end
        if not SendAddonMessage then
            return false
        end
        -- pcall: a malformed name must never take the scan down with it
        local ok = pcall(SendAddonMessage, T.PREFIX .. "<" .. name .. ">",
            T.ASK_MSG, T.CHANNEL)
        if ok then
            asked[name] = GetTime()
            lastAny = asked[name]
        end
        return ok
    end

    -- set below, once the frame exists: arms the paced sender
    local arm

    -- Called by the scan with the players it can see. Nothing is sent here
    -- -- names are only lined up; the timer below paces them out.
    function T.Request(names)
        if not enabled() or type(names) ~= "table" then
            return
        end
        local now = GetTime()
        for i = 1, table.getn(names) do
            local n = names[i]
            if type(n) == "string" and n ~= "" and not queued[n]
                and T.ShouldAsk(n, now, asked, nil) then
                queued[n] = true
                table.insert(queue, n)
            end
        end
        if arm and table.getn(queue) > 0 then
            arm()
        end
    end

    local f = CreateFrame("Frame", "DopingControlTalentFrame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function()
        -- 1.12: arg1 prefix, arg2 message, arg3 channel, arg4 sender
        if arg1 ~= T.PREFIX then
            return
        end
        local sender = arg4
        if type(sender) ~= "string" or sender == "" then
            return
        end
        local kind, data = T.Parse(arg2)
        if not kind then
            return
        end
        local now = GetTime()
        local a = acc[sender]
        if a and T.AccStale(a, now) then
            -- the previous reply lost its END line; this one starts fresh
            a = nil
        end
        if not a then
            a = T.NewAcc(now)
            acc[sender] = a
        end
        T.Feed(a, kind, data)
        if a.complete then
            acc[sender] = nil
            if T.Plausible(a) then
                ranks[sender] = a.ranks
                readAt[sender] = GetTime()
                -- a fresh talent set changes computed hit, so the view has
                -- to be rebuilt -- without this the number only corrects
                -- itself on the next scan
                if DC_Matrix and DC_Matrix.Refresh then
                    DC_Matrix.Refresh()
                end
            end
        end
    end)

    -- Paced sender: one request per T.ASK_GAP, and only ever from the
    -- queue the scan filled. Deliberately a plain timer rather than a burst
    -- after each scan -- 40 requests in one frame is what a rate limit
    -- would punish, and nothing documents where that limit sits.
    --
    -- It is installed only while there is something to send and takes itself
    -- off again the moment the queue runs dry (or the feature is switched
    -- off): an OnUpdate runs 60+ times a second for the whole session, and a
    -- player who never scans must not pay for a queue that is always empty.
    -- Re-arming needs no extra wiring -- every scan calls T.Request.
    local elapsed = 0

    local function disarm()
        f:SetScript("OnUpdate", nil)
    end

    local function drain()
        elapsed = elapsed + (arg1 or 0)
        if elapsed < 1 then
            return
        end
        elapsed = 0
        if not enabled() or table.getn(queue) == 0 then
            disarm()
            return
        end
        local now = GetTime()
        if lastAny and (now - lastAny) < T.ASK_GAP then
            return
        end
        local name = table.remove(queue, 1)
        if name then
            queued[name] = nil
            if T.ShouldAsk(name, now, asked, lastAny) then
                T.Ask(name)
            end
        end
        if table.getn(queue) == 0 then
            disarm()
        end
    end

    arm = function()
        if f:GetScript("OnUpdate") then
            return
        end
        -- a long idle gap must not fire an immediate burst
        elapsed = 0
        f:SetScript("OnUpdate", drain)
    end

    -- forget everything (respec, or a deliberate re-read)
    function T.Clear()
        disarm()
        acc = {}
        ranks = {}
        readAt = {}
        asked = {}
        queue = {}
        queued = {}
        lastAny = nil
    end

end
