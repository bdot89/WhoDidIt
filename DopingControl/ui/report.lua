if WDI_DOPING_SKIP then return end -- DopingControl ui/report.lua
-- Report preview overlay + raid-chat send queue.
--
-- Pure part (offline-testable):
--   DC_Report.SendDisabled(source)     -> bool (true iff source == "sim")
--   DC_Report.QueueCreate(lines)       -> queue (independent copy of lines)
--   DC_Report.QueueTick(q, now, src)   -> line-to-send-now | nil
--   DC_Report.QueueLabel(q)            -> "sending k/n" button label
--   DC_Report.BuildLines(store, db, tab) -> lines, vm (via DC_Model)
--
-- Queue semantics:
--   * First line goes out immediately on Send; every further line waits
--     >= SEND_INTERVAL (0.6 s) measured from the PREVIOUS ACTUAL SEND
--     (the client chat throttle is ~10 msgs/10 s --
--     0.6 s spacing stays safely under it even with other addons chatting).
--   * ABORT: if store.source flips to "sim" mid-drain, the very next tick
--     aborts the queue without sending (synthetic names must
--     never reach real chat). An aborted queue never resumes.
--   * In sim mode the Send button never activates in the first place
--     (SendDisabled predicate), with tooltip "disabled in test mode".
--
-- WoW wiring (behind `if CreateFrame then`): overlay frame
-- DopingControlReportFrame, DIALOG strata, anchored over the matrix frame,
-- scrollable preview FontString showing DC_Model.reportLines output EXACTLY
-- as it will be sent, buttons "Send to raid chat" + "Close".
-- SendChatMessage(line, "RAID") only ever fires from the queue drainer here
-- (single-sender rule).
--
-- Deliberate resolutions:
--   * DC_Report.Open() is exposed with OPTIONAL (vm, tab) arguments: the
--     matrix "Report..." button may pass its already-built vm; with no
--     arguments the report builds its own vm from DC.store via
--     DC_Model/DC_Roles and the current tab (DC_Matrix.GetTab()/.tab if
--     the matrix exposes it, else DC.currentTab, else "CONSUMABLES").
--   * The matrix frame global name is not fixed; anchoring
--     tries DC_Matrix.frame, then DopingControlFrame /
--     DopingControlMatrixFrame, else UIParent.
--   * Closing the overlay (Close / ESC) while draining cancels the rest of
--     the queue -- hidden frames get no OnUpdate on 1.12, so a hidden
--     "paused" queue would silently resume minutes later; cancel is the
--     predictable behavior.

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Report = DC_Report or {}
local R = DC_Report

-- ==================================================================
-- Pure queue core
-- ==================================================================

R.SEND_INTERVAL = 0.6     -- seconds between two sent lines
R.CHAT_TYPE = "RAID"

-- Send is dead exactly in test mode. nil source (no scan
-- yet) is NOT sim: sending a "coverage 0/0" report is pointless but safe.
function R.SendDisabled(source)
    return source == "sim"
end

-- The chat API rejects the WHOLE message with "Invalid escape code in chat
-- message" when it meets a "|" that does not open a valid escape sequence
-- (|c |r |H |h |T |t |n ||). Our header line uses " | " as a plain ASCII
-- separator, so every report was refused. "||" is the escape for a literal
-- pipe and still renders as a single "|", which is why this runs at the
-- send point and NOT inside DC_Model.reportLines: the preview shows what
-- reportLines returns and must keep showing the text as it APPEARS in chat.
-- Report lines are pure ASCII by design (no item links, no colour codes),
-- so doubling every pipe cannot damage a real escape sequence here.
function R.ChatSafe(line)
    if not line then
        return line
    end
    return (string.gsub(line, "|", "||"))
end

-- Create a drain queue from an array of lines. Takes an independent copy
-- (the preview may be rebuilt while an old queue is still draining).
function R.QueueCreate(lines)
    local q = {
        lines = {},
        n = 0,
        sent = 0,
        nextAt = 0,        -- absolute time the next send is allowed
        done = false,
        aborted = false,
    }
    local n = table.getn(lines)
    for i = 1, n do
        table.insert(q.lines, lines[i])
    end
    q.n = n
    if n == 0 then
        q.done = true
    end
    return q
end

-- One drain step. now = current time (GetTime() in-game), source = current
-- store source ("scan"/"sim"/nil). Returns the line to send NOW, or nil.
-- Sets q.done when the last line went out, q.aborted on a sim flip.
function R.QueueTick(q, now, source)
    if not q or q.done or q.aborted then
        return nil
    end
    if source == "sim" then
        q.aborted = true          -- never resumes
        return nil
    end
    if now < q.nextAt then
        return nil
    end
    q.sent = q.sent + 1
    local line = q.lines[q.sent]
    q.nextAt = now + R.SEND_INTERVAL
    if q.sent >= q.n then
        q.done = true
    end
    return line
end

-- Button label while a queue exists.
function R.QueueLabel(q)
    if not q then
        return nil
    end
    if q.aborted then
        return "aborted"
    end
    return string.format("sending %d/%d", q.sent, q.n)
end

-- ==================================================================
-- Line building (pure given a store; uses DC_Model + DC_Roles)
-- ==================================================================

-- "14:04"-style timestamp: WoW 1.12 exposes a global date(); plain
-- Lua 5.0 has os.date.
function R.TimeStr()
    if type(date) == "function" then
        return date("%H:%M")
    end
    if os and type(os.date) == "function" then
        return os.date("%H:%M")
    end
    return "--:--"
end

-- Build the report lines for a store + db + tab. Returns lines, vm.
function R.BuildLines(store, dbt, tab)
    store = store or DC.store or { players = {} }
    tab = tab or "CONSUMABLES"
    -- Same expectation resolver the matrix uses, or the report preview
    -- would show different columns and different gap totals than the grid
    -- it was opened from (demo mode). Safe for the SEND path too: the demo
    -- layer only applies over the "sim" store, and R.SendDisabled blocks
    -- sending on exactly that source. Guarded because ui/report.lua is
    -- loadable without ui/matrix.lua (tools/luatests/test_report_queue.lua).
    local expect
    if DC_Matrix and DC_Matrix.ExpectTable then
        expect = DC_Matrix.ExpectTable(dbt)
    else
        expect = (dbt and dbt.expectations) or DC.DEFAULT_EXPECT or {}
    end
    local function roleOf(p)
        return DC_Roles.resolve(dbt, store.source, p)
    end
    local vm = DC_Model.build(store, roleOf, expect, tab)
    local label = (DC.TAB_LABEL and DC.TAB_LABEL[tab]) or tab
    return DC_Model.reportLines(vm, label, R.TimeStr()), vm
end

-- ==================================================================
-- WoW wiring
-- ==================================================================
if CreateFrame then

    local frame = nil          -- DopingControlReportFrame (lazy)
    local previewText = nil    -- the preview FontString
    local scrollChild = nil
    local infoText = nil
    local sendBtn = nil
    local sendBlocker = nil    -- invisible tooltip overlay while disabled
    local lines = nil          -- current preview lines (array)
    local queue = nil          -- active drain queue or nil

    local function db()
        return DopingControlDB
    end

    local function currentSource()
        return DC.store and DC.store.source
    end

    local function currentTab()
        if DC_Matrix then
            if DC_Matrix.GetTab then
                return DC_Matrix.GetTab()
            end
            if DC_Matrix.tab then
                return DC_Matrix.tab
            end
        end
        return DC.currentTab or "CONSUMABLES"
    end

    -- The matrix frame global name is not guaranteed; try the likely
    -- handles, fall back safely.
    local function anchorFrame()
        if DC_Matrix and DC_Matrix.frame then
            return DC_Matrix.frame
        end
        local m = getglobal("DopingControlFrame")
            or getglobal("DopingControlMatrixFrame")
        return m or UIParent
    end

    local function panelBackdrop()
        if DC_Widgets and DC_Widgets.PANEL_BACKDROP then
            return DC_Widgets.PANEL_BACKDROP
        end
        if DC.PANEL_BACKDROP then
            return DC.PANEL_BACKDROP
        end
        return {
            bgFile = "Interface\\AddOns\\WhoDidIt\\DopingControl\\textures\\panel_bg",
            edgeFile = "Interface\\AddOns\\WhoDidIt\\DopingControl\\textures\\panel_border",
            tile = true, tileSize = 128, edgeSize = 16,
            insets = { left = 5, right = 5, top = 5, bottom = 5 },
        }
    end

    -- Send button + blocker state machine: draining -> disabled "sending
    -- k/n"; sim -> disabled with tooltip blocker; else enabled.
    local function UpdateSendState()
        if not sendBtn then
            return
        end
        if queue and not queue.done and not queue.aborted then
            sendBtn:Disable()
            sendBtn:SetText(R.QueueLabel(queue))
            sendBlocker:Hide()
        elseif R.SendDisabled(currentSource()) then
            sendBtn:Disable()
            sendBtn:SetText("Send to raid chat")
            sendBlocker:Show()
        else
            sendBtn:Enable()
            sendBtn:SetText("Send to raid chat")
            sendBlocker:Hide()
        end
    end

    -- OnUpdate drainer (installed on the frame only while a queue exists;
    -- no allocation on the idle path).
    local function OnUpdateDrain()
        if not queue then
            this:SetScript("OnUpdate", nil)
            return
        end
        local line = R.QueueTick(queue, GetTime(), currentSource())
        if line then
            SendChatMessage(R.ChatSafe(line), R.CHAT_TYPE)
            UpdateSendState()
        end
        if queue.done or queue.aborted then
            queue = nil
            this:SetScript("OnUpdate", nil)
            UpdateSendState()
        end
    end

    local function OnSendClick()
        if queue then
            return
        end
        if not lines or table.getn(lines) == 0 then
            return
        end
        if R.SendDisabled(currentSource()) then
            return
        end
        queue = R.QueueCreate(lines)
        frame:SetScript("OnUpdate", OnUpdateDrain)
        UpdateSendState()
    end

    local function BuildReportFrame()
        if frame then
            return frame
        end
        local f = CreateFrame("Frame", "DopingControlReportFrame", UIParent)
        f:SetWidth(460)
        f:SetHeight(340)
        f:SetFrameStrata("DIALOG")
        f:SetPoint("CENTER", anchorFrame(), "CENTER", 0, 0)
        f:SetBackdrop(panelBackdrop())
        f:SetBackdropColor(1, 1, 1, 0.97)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function() this:StartMoving() end)
        f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
        f:SetClampedToScreen(true)

        -- title (gold)
        local title = f:CreateFontString("DopingControlReportTitle",
            "ARTWORK", "GameFontNormal")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
        local g = DC.COLORS and DC.COLORS.goldHi
        if g then
            title:SetTextColor(g.r, g.g, g.b)
        else
            title:SetTextColor(0.85, 0.66, 0.31)
        end
        title:SetText("Report preview")

        -- info line (line count + pacing note)
        infoText = f:CreateFontString("DopingControlReportInfo",
            "ARTWORK", "GameFontNormalSmall")
        infoText:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -30)
        infoText:SetTextColor(0.6, 0.6, 0.6)
        infoText:SetText("")

        -- close X
        local closeX = CreateFrame("Button", "DopingControlReportCloseX",
            f, "UIPanelCloseButton")
        closeX:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)

        -- scrollable preview: shows reportLines output EXACTLY as sent
        local scroll = CreateFrame("ScrollFrame", "DopingControlReportScroll",
            f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -48)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -36, 44)

        scrollChild = CreateFrame("Frame", "DopingControlReportScrollChild",
            scroll)
        scrollChild:SetWidth(400)
        scrollChild:SetHeight(1)
        scroll:SetScrollChild(scrollChild)

        previewText = scrollChild:CreateFontString("DopingControlReportText",
            "ARTWORK", "GameFontHighlightSmall")
        previewText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        previewText:SetWidth(390)
        previewText:SetJustifyH("LEFT")
        previewText:SetJustifyV("TOP")
        -- mono-ish: 1.12 ships no true monospace; the condensed number
        -- font keeps the indented name lists readable
        previewText:SetFont("Fonts\\ARIALN.TTF", 12)

        -- buttons
        sendBtn = CreateFrame("Button", "DopingControlReportSendButton",
            f, "UIPanelButtonTemplate")
        sendBtn:SetWidth(150)
        sendBtn:SetHeight(22)
        sendBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
        sendBtn:SetText("Send to raid chat")
        sendBtn:SetScript("OnClick", OnSendClick)

        local closeBtn = CreateFrame("Button", "DopingControlReportCloseButton",
            f, "UIPanelButtonTemplate")
        closeBtn:SetWidth(80)
        closeBtn:SetHeight(22)
        closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
        closeBtn:SetText("Close")
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        if pfUI and pfUI.api then
            if pfUI.api.SkinButton then
                pfUI.api.SkinButton(sendBtn)
                pfUI.api.SkinButton(closeBtn)
            end
            if pfUI.api.SkinCloseButton then
                pfUI.api.SkinCloseButton(closeX)
            end
        end

        -- invisible overlay for the disabled-in-test-mode tooltip
        -- (disabled buttons receive no mouse events on 1.12)
        sendBlocker = CreateFrame("Frame", "DopingControlReportSendBlocker", f)
        sendBlocker:SetAllPoints(sendBtn)
        sendBlocker:SetFrameLevel(sendBtn:GetFrameLevel() + 2)
        sendBlocker:EnableMouse(true)
        sendBlocker:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText("disabled in test mode", 1, 1, 1)
            GameTooltip:AddLine("Simulated names never reach real chat.", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("The preview stays fully usable.", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        sendBlocker:SetScript("OnLeave", function() GameTooltip:Hide() end)
        sendBlocker:Hide()

        -- closing cancels a running drain (see header)
        f:SetScript("OnHide", function()
            if queue then
                queue = nil
                this:SetScript("OnUpdate", nil)
            end
        end)

        -- ESC closes
        table.insert(UISpecialFrames, "DopingControlReportFrame")

        f:Hide()
        frame = f
        return f
    end

    -- Rebuild the preview content. vm/tab optional (see header).
    function R.Refresh(vm, tab)
        BuildReportFrame()
        tab = tab or currentTab()
        if vm then
            local label = (DC.TAB_LABEL and DC.TAB_LABEL[tab]) or tab
            lines = DC_Model.reportLines(vm, label, R.TimeStr())
        else
            lines = R.BuildLines(DC.store, db(), tab)
        end
        local n = table.getn(lines)
        previewText:SetText(table.concat(lines, "\n"))
        scrollChild:SetHeight(n * 14 + 24)
        infoText:SetText(string.format(
            "%d line%s - sent one per %.1f s", n, (n == 1) and "" or "s",
            R.SEND_INTERVAL))
        UpdateSendState()
    end

    -- Public entry point (matrix "Report..." button, /dc report).
    function R.Open(vm, tab)
        local f = BuildReportFrame()
        R.Refresh(vm, tab)
        f:Show()
    end

    function R.Toggle(vm, tab)
        local f = BuildReportFrame()
        if f:IsShown() then
            f:Hide()
        else
            R.Open(vm, tab)
        end
    end

end
