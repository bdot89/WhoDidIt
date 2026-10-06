if WDI_DOPING_SKIP then return end -- DopingControl ui/matrix.lua
-- Main window: titlebar (coverage pill, unassigned chip, scan age,
-- buttons), tabs, toolbar
-- (filter + legend), slot header row, scrollable role-grouped matrix,
-- sticky "missing per slot" footer, frame foot hints, TEST MODE banner,
-- whisper buttons, role badge (left-click confirm / right-click cycle),
-- toast.
--
-- Binding UI rules implemented here:
--   Fixed visual system: layout tree, palette, cell states,
--   group headers, tabs, toolbar, footer, titlebar, whisper, tooltips,
--   trinket tiles; role interaction is the badge click UX below
--   (no role popover).
--   DEBUFFS tab visuals: header icon tiles, afflicted =
--   MISSING with debuff icon, no whisper; equipment quality border +
--   8px enchant corner marker; far tag (>= DC.FAR_LIMIT yd, diagnostic);
--   MX.PAD = 22 border-band clearance.
--   Role badge: left-click = confirm the
--   displayed role, right-click = DC_Roles.cycle + save + toast (no-op
--   for single-entry classes); badge tooltip lists the class's actual
--   cycle options (MX.RoleTooltipLines); header icons 20px (the 26px
--   tile sits in a 30px row -- 30px icons crossed both row hairlines);
--   weapon HAS tooltip shows the temp-enchant name when the model
--   delivers one (store field weaponMainName).
--   Last-known display (IRON RULE: last-known data is
--   DISPLAY-ONLY -- it never counts as HAS/MISSING in gaps, pills, sums,
--   footer or report; those keep treating the cell as UNKNOWN):
--   UNKNOWN cells carrying cell.last = { state, detail, icon, item, age }
--   render the cached visual dimmed (MX.DIM_ALPHA, texture/FontString
--   level -- the gray UNKNOWN border stays crisp); cells without .last
--   stay the plain gray "?". Equipment rows with rowVM.gearUnreadable
--   show ONE pooled row-spanning message ("out of range - items not
--   readable (NNyd)") when no cached gear exists, or the dimmed tiles +
--   an "out of range" status chip when it does (MX.UnreadRowMode).
--   Tooltip on cached cells: UNKNOWN reason first, then
--   "Last known (N min ago): <detail>" (MX.AgeText / MX.LastLine).
--   Sum column and pills: NO change. Refresh passes GetTime() as the
--   model's `now` (5th build param) so cell.last.age exists.
--   DEBUFFS is a WARNING SIGNAL,
--   not expectation fulfillment -- display artifacts only,
--   gap/sort semantics unchanged: sum column renders rowVM.debuffCount
--   ("0" faint when clean, "N" red when >0, "--" unreadable --
--   MX.DebuffSumText); CLEAN cells render the near-invisible NOTEXP dot
--   instead of the green check (afflicted cells keep red tile + icon);
--   HIT tab (its own tab, slot kind "hit": melee, ranged and one column
--   per magic school): cells render the percentage with one decimal.
--   A cell AT OR ABOVE its cap renders like a fulfilled cell -- green
--   background AND green border (the HAS colours), not merely green text
--   -- so a capped raid is readable at a glance across 40 rows; below the
--   cap the cell keeps the neutral resistance tile with parchment text,
--   faint on a plain 0, "?" when unreadable, and the near-invisible
--   NOTEXP dot for a player without a ranged weapon. Never red: nothing
--   on this tab is a gap (MX.HitCellStyle owns that mapping).
--   Cell tooltip = MX.HitTooltipLines: the value as a plain ADDITION --
--   one right-aligned row per source (items, set bonuses, auras, talents,
--   weapon skill), "?" for a source that could not be read -- then the
--   generic/school-specific split on a school column, weapon-skill
--   assumption incl. the book note, dual wield incl. the off-hand hit
--   talent, and the school-specific set-bonus row where one applies);
--   header tiles use the slot label/sub and get no "expected for:" line;
--   the footer shows the column average with one decimal.
--   RESIST and HIT share every display-tab rule (MX.IsDisplayTab): "--"
--   in the sum column, neutral "display" group pill, average footer.
--   group pill via MX.DebuffPillText ("clean" green iff debuffTotal==0 and
--   all readable, "N debuffs" red when >0, gray "0 debuffs" while
--   unreadables remain), "N unreadable" chip stays; footer label swaps to
--   "AFFLICTED PER DEBUFF" (MX.FooterLabel). The bold red sum idea has
--   no 1.12 bold flag -- color alone carries the emphasis.
--
-- Rendering reads ONLY the vm from DC_Model.build -- never the raw store,
-- except store.source (TEST MODE banner + chat kill switch) and
-- store.scanAt (age ticker).
--
-- WoW adaptations of the visual design (1.12 has no CSS):
--   * header + footer live OUTSIDE the scroll frame (no sticky in 1.12).
--   * suggested role badge: no dashed borders on 1.12 -> "?" suffix on the
--     badge text + dimmer border + tooltip reason.
--   * glyphs: HAS/MISSING use the vanilla check/cross textures (tinted);
--     UNKNOWN "?" and skip middle-dot are FontStrings. CONSUMABLE HAS
--     cells render the ITEM's icon (phase-1 ladder via
--     MX.ConsumableCellVisual: resolved item icon -> slot-generic icon ->
--     green check -- never the aura texture, never blank); class-buff HAS
--     cells keep the buff texture (cell.icon); equipment cells with a
--     known item (cell.item) render the item icon. All of them on a lazy
--     named per-cell texture (DopingControlCell<i>Icon) instead of the
--     glyph. Caret = "-"/"+"
--     (quest-log convention), whisper button = "PST", unreadable sum = "--"
--     (the unicode carets/envelope/em-dash are not in the 1.12 font).
--   * decorative logo glyph + tab chip -> a tab tooltip note instead.
--
-- OnUpdate is used ONLY for: scan-age ticker (1 s throttle, on the main
-- frame so it stops when hidden) + toast fade. No per-frame allocation:
-- the ticker builds at most one short string per second and the guarded
-- setters skip identical values.
--
-- Structure note (Lua 5.0): closures may carry at most 32 upvalues, so the
-- WoW section keeps ALL frame references in one `UI` table and all private
-- helpers in one `M` table -- each function then closes over a handful of
-- tables instead of dozens of individual locals.
--
-- Pure Lua 5.0. The pure layout/predicate section at the top is offline
-- dofile-testable; everything that touches frames sits behind
-- `if CreateFrame then`.

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Matrix = DC_Matrix or {}
local MX = DC_Matrix

-- ==================================================================
-- PURE SECTION -- layout math + predicates (offline-testable)
-- ==================================================================

-- Layout constants. CELL 30x23 and TRK width 34 are fixed (the whole
-- grid is tuned around them); the rest is derived spacing.
MX.CELL_W       = 30
MX.CELL_H       = 23
MX.TRK_W        = 34
MX.CELL_GAP     = 3
MX.NAME_COL_MIN = 150
MX.ROLE_COL_W   = 62
MX.SUM_COL_W    = 36
MX.PAD          = 22   -- must clear the 16px opaque panel_border band with
                       -- >=6px inset (was 12,
                       -- which put left-edge texts inside the border art)
MX.ROW_H        = 27
MX.GROUP_H      = 24
MX.MAX_COLS     = 22   -- "N slots hidden" fallback only ABOVE this
                       -- (consumables v6: 22 slots incl. the five school
                       -- protection columns is the widest tab now;
                       -- equipment is 17)
MX.SCROLLBAR_W  = 34   -- 6 gap + 16 bar (UIPanelScrollFrameTemplate puts the
                       -- bar at +6..+22 right of the scroll frame edge) + 12
                       -- clearance before the 16px opaque border band
MX.MIN_FRAME_W  = 580  -- titlebar content needs this much
MX.WHISPER_COOLDOWN = 30  -- seconds per player
MX.HEADER_ICON  = 20   -- header tile icon edge (the tile is
                       -- 26px high inside a 30px row -- a 30px icon crossed
                       -- both row hairlines, seen in-game)
MX.CELL_ICON    = 18   -- cell icon edge (fits the 30x23 cell with
                       -- >=2px clearance to the cell border on every side)
MX.ICON_CROP    = 0.08 -- TexCoord inset (0.08..0.92) -- crops the baked-in
                       -- dark icon border so the tile border stays the
                       -- only frame (same crop the item/debuff icons use)
-- Tab strip geometry. The strip starts at MX.PAD and must still fit the
-- NARROWEST window (MX.MIN_FRAME_W, the titlebar minimum) with the same
-- padding on the right -- one more tab therefore costs width per tab, not
-- window width. Pinned by test_matrix_layout so adding a tab cannot
-- silently push the last one under the frame border.
MX.TAB_W        = 84
MX.TAB_PITCH    = 88

-- Transient state (tab/filter are not persisted; collapse
-- lives in db).
MX.state = MX.state or { tab = "CONSUMABLES", gapsOnly = false }
MX.lastWhisper = MX.lastWhisper or {}   -- [playerName] = GetTime() of last whisper
MX.hooks = MX.hooks or {}               -- init wires: scan / report / options

-- Column layout for a slot array. Columns: Player | Role | slots... | Sum.
-- Returns { nameW, roleX, cols = { {x, w, id} ... }, sumX, totalW }.
-- All x offsets are from the window's left edge and include MX.PAD.
function MX.ColumnLayout(slots, nameW)
    nameW = nameW or MX.NAME_COL_MIN
    if nameW < MX.NAME_COL_MIN then
        nameW = MX.NAME_COL_MIN
    end
    local roleX = MX.PAD + nameW + MX.CELL_GAP
    local x = roleX + MX.ROLE_COL_W + MX.CELL_GAP
    local cols = {}
    local n = table.getn(slots)
    for i = 1, n do
        local w = MX.CELL_W
        if slots[i].kind == "trinket" then
            w = MX.TRK_W
        end
        cols[i] = { x = x, w = w, id = slots[i].id }
        x = x + w + MX.CELL_GAP
    end
    local sumX = x
    local totalW = sumX + MX.SUM_COL_W + MX.PAD
    return { nameW = nameW, roleX = roleX, cols = cols, sumX = sumX, totalW = totalW }
end

-- Window width: content width + scrollbar allowance, clamped so the
-- titlebar content always fits.
function MX.FrameWidth(totalW)
    local w = totalW + MX.SCROLLBAR_W
    if w < MX.MIN_FRAME_W then
        w = MX.MIN_FRAME_W
    end
    return w
end

-- Column cap: render at most `cap` slot columns, report how
-- many are hidden. Model/whisper/report still use the FULL slot set.
function MX.VisibleSlots(slots, cap)
    cap = cap or MX.MAX_COLS
    local n = table.getn(slots)
    if n <= cap then
        return slots, 0
    end
    local out = {}
    for i = 1, cap do
        out[i] = slots[i]
    end
    return out, n - cap
end

-- Filter predicate: "Gaps only" hides readable+complete rows but KEEPS
-- unreadable rows and rows with gaps.
-- "Complete" mirrors the model's own ready-pill definition (core/model.lua:
-- readable AND gaps==0 AND unknowns==0) rather than gaps==0 alone -- on
-- RESIST/HIT (M.IsDisplayTab) gaps can NEVER be nonzero (classify()'s
-- resist/hit branches never return MISSING, it is a display-only tab by
-- design), so gaps==0 is true for EVERY row there, verified or not. Without
-- the unknowns check "Gaps only" could not tell a genuinely clean row from
-- one nobody could actually read -- row.readable tracks aurasRead, which is
-- independent of resistsRead/hitRead, so a player is routinely "readable"
-- while their resistance/hit channel specifically failed (foreign
-- UNIT_FIELD_RESISTANCES is never sent by this server at all, so RESIST
-- reads UNKNOWN for nearly every non-self player). Checking unknowns too
-- fixes that without any tab-specific branch: on the expectation tabs
-- (CONSUMABLES/CLASSBUFFS/EQUIPMENT/DEBUFFS) a readable row's cells are
-- gated by the SAME flag that made it readable, so unknowns is already 0
-- there and this adds nothing -- except for the one existing edge case that
-- shared the exact same bug (a gearRead/weaponMain-specific read failing
-- despite aurasRead succeeding), which this also fixes for free.
function MX.RowVisible(row, gapsOnly)
    if not gapsOnly then
        return true
    end
    if not row.readable then
        return true
    end
    return row.gaps > 0 or (row.unknowns or 0) > 0
end

-- Which slice of the unit list is on screen at a given scroll offset, where
-- units may differ in height (group heads are shorter than rows). Two spare
-- units so a partially scrolled unit is never blank. Pure math: no frames,
-- no globals, offline-tested.
MX.WINDOW_SPARE = 2

function MX.VisibleWindow(heights, viewportH, scrollOffset)
    local n = table.getn(heights)
    if n <= 0 then
        return 1, 0, 0
    end
    local offset = scrollOffset or 0
    if offset < 0 then
        offset = 0
    end
    -- the unit that contains the offset, and its distance from the top
    local first, firstY, y = 1, 0, 0
    for i = 1, n do
        if y + heights[i] > offset then
            first, firstY = i, y
            break
        end
        y = y + heights[i]
        first, firstY = i + 1, y     -- offset past the end: keep walking
    end
    if first > n then
        first, firstY = n, y - heights[n]
    end
    -- extend until the viewport is covered, then add the spare units.
    -- `reached` records whether that coverage was actually hit (as opposed
    -- to running out of units first) -- see the pull-back note below.
    local covered, last, reached = 0, first, false
    for i = first, n do
        covered = covered + heights[i]
        last = i
        if covered >= viewportH then
            reached = true
            break
        end
    end
    last = last + MX.WINDOW_SPARE
    if last > n then
        last = n
    end
    -- do not leave a gap at the bottom: pull `first` back, but ONLY when
    -- extending forward genuinely could not cover the viewport (`reached`
    -- is false, i.e. the list ran out before the loop above ever broke).
    -- A naive `last == n` check is not enough: the spare units above can
    -- push `last` to exactly `n` by coincidence even when the extension
    -- already covered the viewport comfortably (e.g. a short list tail
    -- right after `first`) -- pulling back in that case would drag `first`
    -- toward 1 for no reason and defeat the window entirely.
    if not reached then
        local back = 0
        while first > 1 and back < viewportH do
            back = back + heights[first - 1]
            first = first - 1
            firstY = firstY - heights[first]
        end
    end
    return first, last, firstY
end

-- Pool-slot assignment for ONE unit, by WINDOW POSITION rather than data
-- index: this is what keeps the pool size fixed at roughly the viewport's
-- worth of frames (~20-23) instead of growing with the full roster (up to
-- 45) -- NOT a claim that fewer frames get repositioned per redraw. Every
-- unit inside the window gets ClearAllPoints/SetPoint on every single call
-- to M.RenderWindow regardless (that function always repaints the whole
-- window from scratch, see the loop body there): window-position pooling
-- caps how MANY pooled frames exist, not how many of them get touched on
-- any one redraw. Heads and rows are pooled separately (M.EnsureGroupHead
-- / M.EnsureRow are two different pools), so each kind gets its own
-- counter, threaded through as two plain numbers (headSlot, rowSlot)
-- rather than folded into a returned table, because M.RenderWindow calls
-- this once per visible unit
-- on every scroll-throttled redraw: a full window (~20-23 units) at the
-- 20 Hz throttle ceiling would otherwise allocate ~450 short-lived tables a
-- second, straight into the "no allocation per frame" project rule this
-- whole task exists to satisfy. Pure (plain values only, no table, no
-- frame): offline-tested by driving it in the same incremental loop
-- M.RenderWindow uses. Returns kind, slot (for `unit`), and the updated
-- headSlot/rowSlot counters to pass into the next call.
function MX.NextWindowSlot(unit, headSlot, rowSlot)
    if unit.kind == "head" then
        headSlot = headSlot + 1
        return "head", headSlot, headSlot, rowSlot
    end
    rowSlot = rowSlot + 1
    return "row", rowSlot, headSlot, rowSlot
end

-- Whether an open tooltip should be closed because the pooled widget that
-- owns it is about to be rebound to different data. Pure decision core of
-- M.RenderWindow's tooltip guard: no frames, no GameTooltip -- just the
-- comparison, so it is offline-testable (unlike the real-frame-identity
-- ownership matching, which needs W.dcTipOwner (ui/widgets.lua) and stays
-- in M.RowOwnsTooltip in the WoW section).
--
-- `stampedPlayer` is the player name the tooltip's builder recorded when
-- it opened (M.CellTooltip / M.SumTooltip set owner.dcTipPlayer; nil for
-- tooltip kinds that never stamp one -- whisper/badge/pill). `newPlayer`
-- is the player about to be bound to that same pooled widget (nil for a
-- group-head unit, which has no stamp either). `sliceMoved` is the coarser
-- "did the window actually scroll" fallback used only when there is no
-- stamp to compare exactly.
--
-- With a stamp: compare it directly, independent of sliceMoved -- this is
-- what covers a roster join/leave at an unchanged scroll offset (`first`
-- stays numerically the same, but the slot's player still changes).
-- Without one: fall back to sliceMoved, since whisper/badge/pill tooltips
-- print the player's name themselves (or aren't about one single player at
-- all, for the group pill), so a moment of staleness there is self-evident
-- rather than silently wrong -- see M.RenderWindow for that reasoning in
-- full.
function MX.ShouldHideTooltip(stampedPlayer, newPlayer, sliceMoved)
    if stampedPlayer ~= nil then
        return stampedPlayer ~= newPlayer
    end
    return sliceMoved and true or false
end

-- Whether `owner` (GameTooltip's current owner) is one of a pooled row's
-- tooltip-bearing widgets: the three named ones (`a1`/`a2`/`a3` -- the
-- whisper button, role badge, sum) or one of its live slot cells
-- (`cells[1..cellMax]`, matching rf.cells/rf.cellMax's shape exactly, no
-- array copy). Pure: table-identity comparison and a bounded loop only, no
-- WoW API -- works identically for real frames and plain stub tables, so
-- it is offline-testable without a CreateFrame harness.
--
-- Shared by two different call sites in the WoW section: M.RowOwnsTooltip
-- asks it from M.RenderWindow while a row is about to be REBOUND (still
-- shown, different data); M.RowOnHide asks the same question when a row
-- is about to be HIDDEN entirely (the leftover-hide loop when the roster
-- shrinks, a group collapses, or a filter reduces the visible count) --
-- that path never touches M.RenderWindow's rebind check at all, so
-- without a dedicated OnHide guard a tooltip anchored to a
-- now-invisible widget would keep showing a vanished player's values with
-- nothing to close it.
function MX.OwnsTooltip(a1, a2, a3, cells, cellMax, owner)
    if owner == nil then
        return false
    end
    if owner == a1 or owner == a2 or owner == a3 then
        return true
    end
    for i = 1, (cellMax or 0) do
        if cells and cells[i] == owner then
            return true
        end
    end
    return false
end

-- Unassigned-chip predicate (pure): the titlebar chip renders only while
-- at least one player's role is a heuristic suggestion (vm.unassigned
-- from DC_Model.build). n > 0 => visible; 0 or absent aggregate => hidden.
function MX.UnassignedVisible(unassigned)
    if not unassigned then
        return false
    end
    return (unassigned.count or 0) > 0
end

-- Collapse/filter arithmetic: how many player rows are shown vs hidden.
-- groups = vm.groups-shaped array; collapsed = { [role] = true }.
function MX.CountVisibleRows(groups, collapsed, gapsOnly)
    collapsed = collapsed or {}
    local shown, total = 0, 0
    local nG = table.getn(groups)
    for gi = 1, nG do
        local g = groups[gi]
        local nR = table.getn(g.rows)
        total = total + nR
        if not collapsed[g.role] then
            for ri = 1, nR do
                if MX.RowVisible(g.rows[ri], gapsOnly) then
                    shown = shown + 1
                end
            end
        end
    end
    return shown, total - shown
end

-- Whisper eligibility mirror incl. 30 s per-player cooldown.
-- Returns canSend(bool), remainingCooldown(number|nil).
-- rowVM.whisperEligible (readable AND >=1 gap in the active tab) comes
-- from DC_Model.build; this only adds the cooldown on top.
function MX.CanWhisper(row, now, lastTimes)
    if not (row and row.whisperEligible) then
        return false, nil
    end
    lastTimes = lastTimes or MX.lastWhisper
    local name = row.player and row.player.name
    local last = name and lastTimes[name]
    if last and (now - last) < MX.WHISPER_COOLDOWN then
        return false, MX.WHISPER_COOLDOWN - (now - last)
    end
    return true, nil
end

-- Cooldown-table eviction (every t[key]=now throttle table
-- gets a periodic sweep): drop entries older than twice the cooldown.
-- gets a periodic sweep): drop entries older than twice the cooldown.
-- Called from Refresh -- the table is small (distinct whispered names),
-- so a full pass per refresh is cheap. Clearing fields during a pairs
-- traversal is explicitly allowed in Lua 5.0.
function MX.SweepWhispers(now, lastTimes)
    lastTimes = lastTimes or MX.lastWhisper
    for name, t in pairs(lastTimes) do
        if (now - t) > (MX.WHISPER_COOLDOWN * 2) then
            lastTimes[name] = nil
        end
    end
end

-- Known spell ID(s) for a buff name, as a display string ("17626" or
-- "1459/1460/..." for rank lists) -- nil when no table knows the name or
-- the entry is name-match-only (spellID 0 / empty ids). Used by the HAS
-- cell tooltip: the spell ID is mandatory tooltip content,
-- and name-matched cells carry no ID in their detail string.
function MX.KnownSpellIds(name)
    if type(name) ~= "string" then
        return nil
    end
    local c = DC.CONSUMABLES and DC.CONSUMABLES[name]
    if c then
        if c.spellID and c.spellID > 0 then
            return tostring(c.spellID)
        end
        return nil
    end
    local b = DC.CLASSBUFFS and DC.CLASSBUFFS[name]
    if b and b.ids then
        local n = table.getn(b.ids)
        if n > 0 then
            local parts = {}
            for i = 1, n do
                table.insert(parts, tostring(b.ids[i]))
            end
            return table.concat(parts, "/")
        end
    end
    return nil
end

-- ------------------------------------------------------------------
-- Consumable HAS-cell visual: the item, not a check (spec
-- 2026-08-11-slot-model-item-icons-design.md, "Display"). The cell shows
-- the icon of the CONSUMABLE that produced the buff -- resolved through
-- the phase-1 identification ladder (DC.ResolveItem: unique buff name ->
-- entry; generic name -> tooltip effect-line discriminator) -- and falls
-- back down a fixed ladder when the item cannot be determined:
--   resolved item icon -> slot-generic icon (SLOTS_CONSUMABLES[i].icon)
--   -> today's green check. No cell ever goes blank.
-- All pure -- the painter and the tooltip builder consume the same
-- resolution, so what the eye sees and what the tooltip says can never
-- disagree.
-- ------------------------------------------------------------------

-- Data icons are BARE texture names; the path prefix is a render-time
-- concern and lives here exactly once.
MX.ICON_PREFIX = "Interface\\Icons\\"

function MX.IconPath(bare)
    if type(bare) ~= "string" or bare == "" then
        return nil
    end
    return MX.ICON_PREFIX .. bare
end

-- Buff name out of a HAS detail string: ID-matched details embed
-- " (spell N)" (core/model.lua), name matches are the plain name.
function MX.BuffNameFromDetail(detail)
    if type(detail) ~= "string" or detail == "" then
        return nil
    end
    local cut = string.find(detail, " (spell ", 1, true)
    if cut then
        return string.sub(detail, 1, cut - 1)
    end
    return detail
end

-- The ladder, resolved for one cell. `effects` is the scanned
-- player.auras.effects table ([buffName] = tooltip effect line, optional/
-- partial -- scan/aura.lua). Returns { icon, item, generic }:
--   icon    full texture path to render, nil = keep the green check
--   item    resolved consumable name, nil = item unknown
--   generic true when the icon is the slot-generic fallback
function MX.ConsumableCellVisual(sd, detail, effects)
    local buff = MX.BuffNameFromDetail(detail)
    local entry = buff and DC.CONSUMABLES and DC.CONSUMABLES[buff]
    if entry and DC.ResolveItem then
        local eff = nil
        if type(effects) == "table" then
            eff = effects[buff]
        end
        local item, icon = DC.ResolveItem(buff, eff)
        if item then
            local path = MX.IconPath(icon)
            if path then
                return { icon = path, item = item }
            end
            -- item resolved but no sourced icon (icon=nil in the data):
            -- slot-generic icon, the tooltip still names the item
            return { icon = MX.IconPath(sd and sd.icon), item = item,
                     generic = true }
        end
    end
    -- unresolved buff (generic name without a matching effect line, or a
    -- bare "spell N" detail): slot filled, item unknown
    return { icon = MX.IconPath(sd and sd.icon), generic = true }
end

-- Tooltip content of a consumable aura HAS cell, as a PURE array of
-- { text, color, wrap } (the WoW builder only applies colors): item name
-- + buff name; on the slot-generic fallback "<slot> active - item
-- unknown" + buff name + the pick-one alternatives.
function MX.HasTooltipLines(sd, detail, effects)
    local vis = MX.ConsumableCellVisual(sd, detail, effects)
    local buff = MX.BuffNameFromDetail(detail) or (sd and sd.full) or "?"
    -- spell id rides along like before: ID-match details already embed
    -- "(spell N)", name matches get the table-known id appended
    local buffLine = detail
    if type(detail) ~= "string"
        or not string.find(detail, " (spell ", 1, true) then
        local ids = MX.KnownSpellIds(buff)
        if ids then
            buffLine = buff .. " (spell " .. ids .. ")"
        else
            buffLine = buff
        end
    end
    local lines = {}
    if vis.item then
        table.insert(lines, { text = vis.item, color = "hat" })
        table.insert(lines, { text = "Buff: " .. buffLine, color = "parch",
                              wrap = 1 })
        table.insert(lines, { text = "Slot " .. ((sd and sd.full) or "?"),
                              color = "parchDim", wrap = 1 })
    else
        table.insert(lines, { text = ((sd and sd.full) or "?")
            .. " active - item unknown", color = "hat" })
        table.insert(lines, { text = "Buff: " .. buffLine, color = "parch",
                              wrap = 1 })
        if sd and sd.items then
            table.insert(lines, { text = "e.g. " .. sd.items,
                                  color = "parchDim", wrap = 1 })
        end
    end
    return lines
end

-- Trinket monogram fallback (no icon texture known): first letter of each
-- word, max 3 ("Hand of Justice" -> "HOJ"); single words use their first
-- three letters ("Earthstrike" -> "EAR").
function MX.Monogram(name)
    if not name or name == "" then
        return "?"
    end
    local out = ""
    local inWord = false
    local len = string.len(name)
    for i = 1, len do
        local ch = string.sub(name, i, i)
        if string.find(ch, "%a") then
            if not inWord then
                out = out .. string.upper(ch)
                inWord = true
                if string.len(out) >= 3 then
                    break
                end
            end
        else
            inWord = false
        end
    end
    if string.len(out) < 2 then
        local w = ""
        for i = 1, len do
            local ch = string.sub(name, i, i)
            if string.find(ch, "%a") then
                w = w .. string.upper(ch)
            end
            if string.len(w) >= 3 then
                break
            end
        end
        if string.len(w) > string.len(out) then
            out = w
        end
    end
    if out == "" then
        out = "?"
    end
    return out
end

-- Far-tag text: "<n>yd", floored. Rendered
-- next to the player name only while rowVM.far is set -- the MODEL decides
-- (readable and distance >= DC.FAR_LIMIT); distance stays diagnostic and
-- never changes any state/sum/pill.
function MX.FarTag(distance)
    if not distance then
        return nil
    end
    return string.format("%dyd", distance)
end

-- ------------------------------------------------------------------
-- Last-known display helpers. IRON RULE: the
-- cache is DISPLAY-ONLY -- nothing in here feeds gaps/sums/pills/footer,
-- and none of these helpers is consulted by any counting path.
-- ------------------------------------------------------------------

-- Content dim for cached observations. Applied at texture/FontString
-- level only -- never on the cell frame -- so the gray UNKNOWN border
-- stays crisp.
MX.DIM_ALPHA = 0.45

-- Pure: should opening the window trigger a scan? (fixed bug:
-- after a reload NOTHING scanned until a roster event fired while the
-- window was shown -- the window opened empty with "no scan yet").
-- Stale after 60s; test mode never auto-scans; without a clock
-- no staleness claim is made.
function MX.WantScanOnShow(testMode, scanAt, now)
    if testMode then
        return false
    end
    if not scanAt then
        return true
    end
    if now and (now - scanAt) > 60 then
        return true
    end
    return false
end

-- Age text for a cached observation: "45 s ago" under a minute, then
-- "12 min ago" (floored). nil age (no cache timestamp) -> nil.
function MX.AgeText(seconds)
    if seconds == nil then
        return nil
    end
    if seconds < 60 then
        return math.floor(seconds) .. " s ago"
    end
    return math.floor(seconds / 60) .. " min ago"
end

-- Equipment-row render mode (decision tree):
--   "plain"   -> row is not gear-unreadable: normal cell painting
--   "message" -> gear unreadable, NO cached gear: cells hide, ONE dim
--                row-spanning line explains why
--   "dimmed"  -> gear unreadable, cached gear present: dimmed tiles
--                render instead; the status chip carries "out of range"
-- rowVM.gearUnreadable is already tab-scoped by the model (only ever
-- true on EQUIPMENT), so no tab check happens here.
function MX.UnreadRowMode(row, hasAnyLast)
    if not (row and row.gearUnreadable) then
        return "plain"
    end
    if hasAnyLast then
        return "dimmed"
    end
    return "message"
end

-- Row-spanning message for a gear-unreadable equipment row without
-- cached gear; distance appended when known (diagnostic, floored yards).
-- The row-spanning line for a player whose GEAR could not be read. It
-- states what was OBSERVED -- no equipment slot returned an item link --
-- and appends the measured distance when there is one, so the reader can
-- judge the range hypothesis instead of being handed it as a verdict:
-- distance is only one of the ways this read comes back empty.
function MX.UnreadRowText(distance)
    local s = "items not readable - no equipment slot returned an item link"
    if distance then
        s = s .. " (" .. MX.FarTag(distance) .. ")"
    end
    return s
end

-- Tooltip line for a cached observation:
-- "Last known (12 min ago): Flask of the Titans". Table details (trinket
-- HAS) degrade to their item name; absent detail degrades to the cached
-- state; absent age drops the parenthesis.
function MX.LastLine(last)
    if type(last) ~= "table" then
        return nil
    end
    local d = last.detail
    local dtxt
    if type(d) == "table" then
        dtxt = d.name or (type(last.item) == "table" and last.item.name)
            or "item"
    elseif d ~= nil and d ~= "" then
        dtxt = tostring(d)
    elseif type(last.item) == "table" and last.item.name then
        dtxt = last.item.name
    elseif last.state == "HAS" then
        dtxt = "present"
    else
        dtxt = "missing"
    end
    local age = MX.AgeText(last.age)
    if age then
        return "Last known (" .. age .. "): " .. dtxt
    end
    return "Last known: " .. dtxt
end

-- Singular role display names (badge, toasts, tooltips). The WoW section
-- reads these too -- single source for the role wording.
MX.ROLE_NAME = { TANK = "Tank", MELEE = "Melee", RANGED = "Ranged",
                 CASTER = "Caster", HEALER = "Healer" }

-- Class token -> display word ("WARRIOR" -> "Warrior") for the fixed-role
-- tooltip line; nil/empty tokens degrade to generic wording.
function MX.ClassTitle(class)
    if type(class) ~= "string" or class == "" then
        return "this class"
    end
    return string.upper(string.sub(class, 1, 1))
        .. string.lower(string.sub(class, 2))
end

-- Role badge tooltip content as a PURE string
-- array; the WoW tooltip builder only applies colors. Lines:
--   1) "Role: X" (confirmed) or "Suggestion: X" (heuristic)
--   2) "Reason: <reason>"           -- suggested only
--   .) "Left-click: confirm role"
--   .) "Right-click: cycle: A / B / C" from DC_Roles.CLASS_ROLES[class]
--      (the class's ACTUAL options, full list), or
--      "Role is fixed for <Class>" for single-entry/unknown classes
--      (right-click is a no-op there).
-- DC_Roles.CLASS_ROLES is read at CALL time and nil-guarded (parallel
-- builder owns core/roles.lua) -- absent table degrades to the fixed line.
function MX.RoleTooltipLines(class, role, suggested, reason)
    local lines = {}
    local roleName = MX.ROLE_NAME[role] or role or "?"
    if suggested then
        table.insert(lines, "Suggestion: " .. roleName)
        table.insert(lines, "Reason: " .. (reason or "unknown"))
    else
        table.insert(lines, "Role: " .. roleName)
    end
    table.insert(lines, "Left-click: confirm role")
    local list = DC_Roles and DC_Roles.CLASS_ROLES
        and DC_Roles.CLASS_ROLES[class]
    if list and table.getn(list) >= 2 then
        local parts = {}
        local n = table.getn(list)
        for i = 1, n do
            table.insert(parts, MX.ROLE_NAME[list[i]] or list[i])
        end
        table.insert(lines, "Right-click: cycle: "
            .. table.concat(parts, " / "))
    else
        table.insert(lines, "Role is fixed for " .. MX.ClassTitle(class))
    end
    return lines
end

-- Weapon cell HAS detail discriminator: the model puts the
-- temp-enchant NAME into detail when store.weaponMainName is set, else the
-- generic string below. Returns the name, or nil on the generic/absent
-- detail (tooltip then keeps the standard HAS path).
MX.WEAPON_GENERIC = "main hand temp enchant"

function MX.WeaponEnchantName(detail)
    if type(detail) ~= "string" then
        return nil
    end
    if detail == MX.WEAPON_GENERIC or detail == "" then
        return nil
    end
    return detail
end

-- Scan-age text (titlebar, ticks 1/s): "Ns ago" under 60 s, else minutes.
function MX.FormatScanAge(seconds)
    if seconds == nil then
        return "no scan yet"
    end
    if seconds < 60 then
        return "Scan: " .. math.floor(seconds) .. " s ago"
    end
    return "Scan: " .. math.floor(seconds / 60) .. " min ago"
end

-- ------------------------------------------------------------------
-- DEBUFFS warning-signal helpers. The tab reports
-- what IS wrong, not what fulfills an expectation: rowVM.debuffCount is
-- the TOTAL count of distinct debuff names on the player (including any
-- beyond the 10 shown columns), nil when not readable; group.debuffTotal
-- sums it over readable rows. sumHas/sumExpected stay nil on this tab.
-- ------------------------------------------------------------------

-- DISPLAY tabs (RESIST + HIT): static columns, no expectations, no gaps.
-- Mirrors DC_Model.IsDisplayTab -- the model is the authority, this is the
-- rendering side of the same rule (delegated when the model is loaded, so
-- the two can never disagree; the literal list keeps this pure section
-- standalone under the offline harness).
function MX.IsDisplayTab(tab)
    if DC_Model and DC_Model.IsDisplayTab then
        return DC_Model.IsDisplayTab(tab)
    end
    return tab == "RESIST" or tab == "HIT"
end

-- Footer strip label per tab (footer counts stay the model's numbers).
function MX.FooterLabel(tab)
    if tab == "DEBUFFS" then
        return "AFFLICTED PER DEBUFF"
    elseif MX.IsDisplayTab(tab) then
        return "AVERAGE (READABLE)"
    end
    return "MISSING PER SLOT"
end

-- Sum-column text for a DEBUFFS row: quiet "0" when clean, red "N" when
-- afflicted, "--" when the row is not readable (debuffCount nil counts as
-- not readable -- the model only sets it on readable rows).
-- Returns { text = string, colorKey = "faint"|"fehlt" } (DC.COLORS key).
function MX.DebuffSumText(count, readable)
    if not readable or count == nil then
        return { text = "--", colorKey = "faint" }
    end
    if count > 0 then
        return { text = tostring(count), colorKey = "fehlt" }
    end
    return { text = "0", colorKey = "faint" }
end

-- Group pill on DEBUFFS: green "clean" ONLY when zero debuffs AND every
-- member readable (an unreadable member forbids the clean claim -- same
-- rule as UNKNOWN-never-ready); red "N debuffs" whenever any exist; gray
-- neutral "0 debuffs" while zero-but-unreadables-remain. nil total =
-- model without the debuffTotal field -> "?" (callers guard anyway).
-- Returns { text = string, kind = "good"|"bad"|"unknown" }.
function MX.DebuffPillText(debuffTotal, allReadable)
    if debuffTotal == nil then
        return { text = "?", kind = "unknown" }
    end
    if debuffTotal > 0 then
        local noun = " debuffs"
        if debuffTotal == 1 then
            noun = " debuff"
        end
        return { text = debuffTotal .. noun, kind = "bad" }
    end
    if allReadable then
        return { text = "clean", kind = "good" }
    end
    return { text = "0 debuffs", kind = "unknown" }
end

-- ------------------------------------------------------------------
-- Hit columns (the HIT tab). The model already did every bit of math --
-- these helpers only turn a hit cell into text and color keys, so the
-- numbers on screen can never disagree with the ones in the report.
-- ------------------------------------------------------------------

-- Cell number: always one decimal, so a column of hit values stays
-- aligned. Single source for the rounding is the model's formatter; the
-- local fallback only keeps this pure section standalone.
function MX.HitText(v)
    if DC_Model and DC_Model.HitText then
        return DC_Model.HitText(v)
    end
    if type(v) ~= "number" then
        return "?"
    end
    return string.format("%.1f", v)
end

-- Cell text color key (DC.COLORS): green once the cap is met, parchment
-- below it, faint for a plain 0 -- most melee players carry no spell hit
-- and most casters no melee hit, and that zero should stay quiet rather
-- than shout. Never red: a hit number is information, not a gap.
function MX.HitColorKey(cvm)
    if not cvm or type(cvm.value) ~= "number" then
        return "unbek"
    end
    if cvm.capMet then
        return "hat"
    end
    if cvm.value <= 0 then
        return "faint"
    end
    return "parch"
end

-- Full tile style of a HAS hit cell: { bg, border, text } DC.COLORS keys.
-- A cell at or above its cap gets the FULFILLED look -- green background
-- AND green border, the same pair a green check sits on everywhere else --
-- because green text alone is invisible when scanning 40 rows for the
-- players who are still short. Below the cap the cell keeps the neutral
-- resistance tile: informative, not alarming. Never the red MISSING pair;
-- nothing on a display tab is a gap.
function MX.HitCellStyle(cvm)
    if cvm and cvm.capMet then
        return { bg = "hatBg", border = "hatBorder", text = "hat" }
    end
    return { bg = "theadBg", border = "line", text = MX.HitColorKey(cvm) }
end

-- "arcane" -> "Arcane": slot school tokens are lower case, tooltip prose
-- is not. Pure ASCII single-byte handling is enough (the six school
-- tokens are ASCII by construction).
function MX.SchoolTitle(school)
    if type(school) ~= "string" or school == "" then
        return ""
    end
    return string.upper(string.sub(school, 1, 1))
        .. string.lower(string.sub(school, 2))
end

-- The one thing this addon can NOT read off another player: the quest
-- weapon-skill books. Stated in every melee/ranged hit tooltip so the
-- assumed skill is never mistaken for a measurement.
MX.HIT_BOOK_NOTE = "A quest weapon-skill book (+3 skill, about 0.6% hit)"
    .. " cannot be detected on other players - tick it in the options if"
    .. " it applies."

-- SET BONUSES are counted, once per set (scan/hit.lua H.SumSets). The
-- bonus line IS printed on every piece, which is why a per-item sum would
-- multiply it -- but the tooltip also states the set name, the piece count
-- and each bonus's threshold, so the honest answer is to group by set and
-- count each bonus once. The note only tells the reader that a set line in
-- the breakdown means the whole set, not one item.
MX.HIT_SETBONUS_NOTE = "Set bonuses count once per set, not once per"
    .. " piece - a set line names the set and how many pieces it needed."

-- Hit cell tooltip content as a PURE array of
-- { text = string, color = <DC.COLORS key>, wrap = 1|nil }; the WoW
-- tooltip builder only applies the colors. Returns nil for states this
-- builder does not own (UNKNOWN keeps the generic not-readable tooltip).
function MX.HitTooltipLines(sd, cvm)
    if not (sd and cvm) then
        return nil
    end
    local lines = {}
    -- add(text, color, wrap) -- a plain sentence
    -- addv(label, value, color, valueColor) -- a BREAKDOWN row: label left,
    --   value flush right (W.TipDouble). Every addend of the hit number is
    --   one of these, so the figures line up in a single column and the
    --   total can be checked by adding them up on screen.
    local function add(text, color, wrap)
        table.insert(lines, { text = text, color = color or "parch",
                              wrap = wrap })
    end
    local function addv(label, value, color, valueColor)
        table.insert(lines, { text = label, right = value,
                              color = color or "parchDim",
                              rightColor = valueColor or color or "parch" })
    end
    if cvm.state == DC.STATE.NOTEXP then
        -- The only NOTEXP a hit column can produce is "this player has no
        -- ranged-hit question". The REASON is the model's string, printed
        -- verbatim: an empty ranged slot and an equipped wand/relic are
        -- different causes, and naming a wand for a player who carries
        -- none would be a wrong explanation.
        local why = (type(cvm.detail) == "string") and cvm.detail
            or "no ranged attack weapon"
        add(sd.full .. ": " .. why, "parch")
        add("so there is no ranged hit cap to meet", "parchDim", 1)
        return lines
    end
    if cvm.state ~= DC.STATE.HAS then
        return nil
    end
    local b = (type(cvm.detail) == "table") and cvm.detail or {}
    local value = cvm.value or b.value or 0
    local function pct(v)
        return MX.HitText(v) .. "%"
    end
    local function plus(v)
        return "+" .. MX.HitText(v) .. "%"
    end

    -- ---- the number, then the addition that produces it ----------------
    addv(sd.full, pct(value), "parch", cvm.capMet and "hat" or "parch")
    addv("  from items", plus(b.gear or 0))
    addv("  from set bonuses", plus(b.set or 0))
    if b.aurasRead == false then
        -- the aura channel failed THIS scan -- an unknown quantity, not a
        -- verified zero, and a "+0.0%" would claim the opposite
        addv("  from auras", "?", "parchDim", "unbek")
    else
        addv("  from auras", plus(b.aura or 0))
    end
    if b.talentsRead then
        addv("  from talents", plus(b.talent or 0))
    else
        addv("  from talents", "?", "parchDim", "unbek")
    end
    -- Weapon skill sits on THIS side of the comparison (core/model.lua):
    -- the boss's floor does not move, the attacker's skill is what he
    -- brings. Shown for melee/ranged only -- spell hit knows no skill.
    if b.kind ~= "spell" and b.skill then
        local base = b.skillBase or 300
        local over = b.skill - base
        local label = "  from " .. (b.skillName and string.lower(b.skillName)
            or "weapon") .. " skill " .. b.skill
        if over > 0 then
            label = label .. " (+" .. over .. " over " .. base .. ")"
        end
        addv(label, plus(b.skillHit or 0))
    end
    if b.school then
        -- a school column adds its school-only bonuses on top of the
        -- generic number; they are addends of THIS column and belong in
        -- the same addition
        local title = MX.SchoolTitle(b.school)
        addv("  " .. string.lower(title) .. " only, from items",
            plus(b.gearSchool or 0))
        if (b.setSchool or 0) > 0 then
            addv("  " .. string.lower(title) .. " only, from set bonuses",
                plus(b.setSchool))
        end
        addv("  " .. string.lower(title) .. " only, from talents",
            plus(b.talentSchool or 0))
    end
    if b.talentsRead == false then
        add("talents not received yet - the total will rise once they"
            .. " arrive", "parchDim", 1)
    end
    if b.aurasRead == false then
        add("the buff read failed for this player, so aura hit is unknown",
            "parchDim", 1)
    end

    -- ---- the cap, as its own little addition ---------------------------
    local cap = cvm.cap or b.cap
    if cap then
        -- one flat number: what a +3-level boss demands. It does not move
        -- with the attacker's weapon skill -- that is an addend above.
        addv("Cap vs a +3-level boss", pct(cap), "parch")
        if cvm.capMet then
            add("at or above the cap", "hat")
        else
            add("missing " .. pct(cap - value) .. " to the cap", "parch")
        end
        if b.capUnverified then
            add("this cap is the commonly quoted value, not one measured"
                .. " on this server", "parchDim", 1)
        end
    end

    -- ---- what the weapon-skill number itself rests on -------------------
    if b.kind ~= "spell" then
        if b.skill then
            if b.skillExact then
                add("weapon skill measured on your own character",
                    "parchDim", 1)
            elseif b.book then
                add("weapon skill assumed: 300 + racial bonus + the skill"
                    .. " book you ticked", "parchDim", 1)
            else
                add("weapon skill assumed: 300 + racial bonus. A quest skill"
                    .. " book (+3 skill, about 0.6% hit) cannot be detected"
                    .. " on other players - tick it in the options if it"
                    .. " applies", "parchDim", 1)
            end
        else
            add("Weapon skill: unknown - the equipped weapon could not be"
                .. " identified", "parch", 1)
        end
        if b.dualWield then
            addv("Dual wield: white swings need", pct(b.capWhite or 0),
                "parchDim")
            if (b.talentOffhand or 0) > 0 then
                -- an off-hand hit talent raises OFF-HAND swings only, so
                -- it is deliberately absent from the number at the top --
                -- naming it here is the whole point of carrying it
                addv("  off-hand only, from talents",
                    plus(b.talentOffhand))
            end
        end
    end
    if type(b.schools) == "table" then
        -- generic spell column: school-specific hit counts against that
        -- school ONLY, so it is never part of the number above
        local names = {}
        for school in pairs(b.schools) do
            table.insert(names, school)
        end
        table.sort(names)
        for i = 1, table.getn(names) do
            addv("  " .. names[i] .. " only (not in the total above)",
                plus(b.schools[names[i]]))
        end
    end
    add("display only", "parchDim", 1)
    return lines
end

-- Header-tile "expected for:" roles line (seam fix):
-- db.expectations is PER CLASS now -- [role][class][slotId] -- so the old
-- [role][slotId] read returned nil for every slot ("expected for: no
-- role" on ALL header tooltips). A role counts as expecting the slot when
-- ANY performing class resolves to expected, with the SAME fallback
-- fallback as the model: an explicit class line wins, a missing/non-table
-- line falls back to the DC.DEFAULT_EXPECT role line. Legacy role x slot
-- tables (the RenderHeader fallback while db.expectations is nil) keep
-- working through the direct boolean read -- their per-class semantics
-- are identical to the model's corollary (every combo = the role line).
function MX.ExpectedForString(slotId, expectTbl)
    local parts = {}
    local n = table.getn(DC.ROLES)
    for i = 1, n do
        local role = DC.ROLES[i]
        local byClass = expectTbl and expectTbl[role]
        local def = DC.DEFAULT_EXPECT and DC.DEFAULT_EXPECT[role]
        local expected = false
        if type(byClass) == "table" then
            if byClass[slotId] == true then
                expected = true   -- legacy role x slot line
            else
                local classes = DC_Roles and DC_Roles.ROLE_CLASSES
                    and DC_Roles.ROLE_CLASSES[role]
                if classes then
                    for c = 1, table.getn(classes) do
                        local line = byClass[classes[c]]
                        if type(line) ~= "table" then
                            line = def   -- rule-5 fallback, as in the model
                        end
                        if line and line[slotId] then
                            expected = true
                            break
                        end
                    end
                elseif def and def[slotId] then
                    -- defensive: DC_Roles absent -> role-line fallback
                    expected = true
                end
            end
        elseif def and def[slotId] then
            -- absent role table: SAME rule-5 fallback as the model's
            -- expectLine -- the tooltip must agree with the rendered
            -- columns (an absent role still contributes its default line)
            expected = true
        end
        if expected then
            table.insert(parts, DC.ROLE_LABEL[role])
        end
    end
    if table.getn(parts) == 0 then
        return "no role"
    end
    return table.concat(parts, ", ")
end

-- ------------------------------------------------------------------
-- The ONE expectation-table resolver for the whole window. Both consumers
-- -- M.RenderHeader (header tiles + their "expected for:" tooltip) and
-- MX.Refresh (the model build behind the cells) -- must read the SAME
-- table, or the header drifts from the grid below it.
--
-- Demo mode (core/demo.lua) swaps the whole table for a TRANSIENT layer
-- that expects all six school protection columns; it is built lazily here
-- if the mode was armed without one. Normal mode reads db.expectations,
-- falling back to the seed while the DB is not materialized yet.
--
-- The demo layer is only legitimate over the SIMULATED store. DC.SimOwnsStore
-- keeps a real scan result from ever landing while demo mode is armed; this
-- is the belt-and-suspenders half of that guarantee. Should a gate ever be
-- missed again, grading real raid members against five columns that ship OFF
-- would fabricate MISSING cells and arm their whisper buttons -- so a
-- non-"sim" store degrades to the user's OWN expectations instead. A store
-- that does not exist yet (pre-ADDON_LOADED) is not a real scan and keeps
-- the layer.
-- ------------------------------------------------------------------
function MX.ExpectTable(d)
    local st = DC.store
    if DC.demoMode and (not st or st.source == "sim") then
        local demo = DC.demoExpectations
        if not demo and DC.BuildDemoExpectations then
            demo = DC.BuildDemoExpectations(d)
        end
        if demo then
            return demo
        end
    end
    -- Defensive re-top-up (2026-08-30 bug): EnsureExpectations normally
    -- runs once, at ADDON_LOADED (core/init.lua) -- but a materialized
    -- db.expectations that predates a slot added to DC.DEFAULT_EXPECT
    -- since (e.g. WAIST, v0.6.3) is loaded as-is otherwise and stays
    -- missing that key until the NEXT full ADDON_LOADED cycle actually
    -- runs against the CURRENT seed. anyClassExpects (core/model.lua)
    -- then finds the new slot true nowhere and the whole column stays
    -- hidden -- reproduced offline in tools/luatests/test_expectations_topup.lua
    -- with the exact real SavedVariables shape. EnsureExpectations is
    -- idempotent and only fills nils (topUpLine, core/config.lua), so
    -- calling it again here every refresh is side-effect-free and cheap
    -- (~5 roles x a handful of classes x slot count) -- it self-heals
    -- this class of bug the moment the window is drawn, without waiting
    -- for a second reload.
    if d and d.expectations and DC.EnsureExpectations then
        DC.EnsureExpectations(d)
    end
    return (d and d.expectations) or DC.DEFAULT_EXPECT or {}
end

-- Banner visibility. The store source drives it (test mode and demo mode
-- both run on the "sim" store), but demo mode shows it unconditionally: the
-- banner is the ONE visual marker that the extra columns are a mode and not
-- a measurement, and it must not be the thing that disappears if a real
-- store ever slips past the scan gates.
function MX.ShowBanner(source)
    if source == "sim" then
        return true
    end
    if DC.demoMode then
        return true
    end
    return false
end

-- Banner line for the simulated-raid banner (shown whenever the store
-- source is "sim"). Demo mode says so explicitly -- its extra columns are
-- a mode, not a scan result.
--
-- Wording: "protection columns", NOT "resistance columns". What demo mode
-- reveals are the six school PROTECTION-POTION columns of the CONSUMABLES
-- tab; the RESIST tab has actual resistance columns and demo mode does not
-- touch it. Same wording as the /dc demo chat line (core/init.lua).
function MX.BannerText()
    if DC.demoMode then
        return "DEMO MODE - simulated raid \194\183 all six protection columns shown"
    end
    return "TEST MODE - simulated raid \194\183 chat output disabled"
end

-- Tab/filter state setters (state part is pure; re-render only in-game).
function MX.SetTab(id)
    local n = table.getn(DC.TABS)
    local valid = false
    for i = 1, n do
        if DC.TABS[i] == id then
            valid = true
        end
    end
    if not valid then
        return
    end
    MX.state.tab = id
    if MX.Refresh then
        MX.Refresh()
    end
end

function MX.SetFilter(gapsOnly)
    MX.state.gapsOnly = gapsOnly and true or false
    if MX.Refresh then
        MX.Refresh()
    end
end

-- Current tab id -- ui/report.lua asks DC_Matrix.GetTab() for it when it
-- builds its own vm (report of the ACTIVE tab, not always CONSUMABLES).
function MX.GetTab()
    return MX.state.tab
end

-- ==================================================================
-- WOW SECTION -- frames, rendering, interaction
-- ==================================================================
if CreateFrame then

local W = DC_Widgets
local C = DC.COLORS
local S = DC.STATE

local UI = {   -- every frame reference + pool lives here (upvalue budget)
    headerTiles = {}, headerMax = 0,
    footerFS = {}, footerMax = 0,
    groupHeads = {}, groupHeadMax = 0,
    rowPool = {}, rowMax = 0,
    cellIconN = 0,   -- running index for named per-cell icon textures
    cellCornerN = 0, -- running index for named per-cell corner markers
}
local M = {}   -- private helpers (factories, painters, tooltip builders)

-- vertical metrics (frame-local, negative y = down)
local LC = {
    TITLE_H = 30, TABS_H = 24, TOOLBAR_H = 24,
    CONTENT_TOP = -88,      -- -(10 + TITLE_H + TABS_H + TOOLBAR_H)
    BANNER_H = 20, HEADER_H = 30, FOOTER_H = 18, FOOT_H = 14,
    MAX_SCROLL_H = 560, MIN_SCROLL_H = 40,   -- 560 = fixed design value
    BAR_X_OFF = 16,         -- banner/header/footer bars clear the border band
                            -- (panel_border.tga is ~16px fully opaque;
                            -- checked in-game: 10 still left 6px
                            -- of the bars inside the band)
    DIMBORDER = {},         -- dimmer role borders for SUGGESTED badges
}
for i = 1, table.getn(DC.ROLES) do
    local role = DC.ROLES[i]
    local b = C["roleBorder" .. role]
    LC.DIMBORDER[role] = { r = b.r * 0.55, g = b.g * 0.55, b = b.b * 0.55 }
end

function M.db()
    return DopingControlDB
end

function M.store()
    return DC.store or { players = {}, source = "scan" }
end

function M.roleName(role)
    return MX.ROLE_NAME[role] or role or "?"
end

-- ------------------------------------------------------------------
-- tooltip builders
-- ------------------------------------------------------------------
function M.qualityColors(q)
    -- custom accents for the common raid qualities; DC.QUALITY for the rest
    if q == 3 then
        return C.rareText, C.rareBorder
    elseif q == 4 then
        return C.epicText, C.epicBorder
    end
    local base = DC.QUALITY[q or 1] or DC.QUALITY[1]
    return base, base
end

function M.CellTooltip(cell)
    local sd, cvm, row = cell.dcSD, cell.dcVM, cell.dcRow
    if not (sd and cvm and row) then
        return
    end
    -- Identity stamp for M.RenderWindow: this tooltip's text never prints
    -- the player's name anywhere below (it is entirely slot/state driven),
    -- so if the pooled cell is rebound to a DIFFERENT player while this
    -- tooltip is still open (no OnEnter fires without real mouse movement,
    -- so nothing else would rebuild it), the stale text would read as
    -- fact for the new player with no way for the reader to tell. Stamped
    -- fresh on every open; M.RenderWindow compares it before rebinding.
    cell.dcTipPlayer = row.player and row.player.name
    local state = cvm.state
    -- Equipment cell with a known item: native
    -- item tooltip via SetHyperlink -- it includes the green enchant line,
    -- which is the ONLY way to show WHAT the item is enchanted with (no
    -- enchant-name table exists in 1.12). Re-SetOwner with ANCHOR_LEFT
    -- (clears the AttachTooltip cursor anchor) + one colored state line.
    -- Uncached items may render an empty tooltip on the first hover (the
    -- client fires the server query); acceptable, fills once cached.
    -- The custom tooltip below stays as the fallback when item is nil.
    local item = cvm.item
    if (sd.kind == "ench" or sd.kind == "trinket")
        and type(item) == "table" and item.id then
        GameTooltip:SetOwner(cell, "ANCHOR_LEFT")
        GameTooltip:SetHyperlink("item:" .. item.id .. ":" .. (item.enchant or 0))
        if sd.kind == "ench" then
            if state == S.HAS then
                GameTooltip:AddLine("Enchanted", C.hat.r, C.hat.g, C.hat.b)
            elseif state == S.MISSING then
                GameTooltip:AddLine("Not enchanted",
                    C.fehlt.r, C.fehlt.g, C.fehlt.b)
            elseif state == S.NOTEXP then
                -- two distinct reasons share this state (core/model.lua):
                -- a subtype exemption (wand/holdable, detail carries the
                -- "<subType> - not enchantable" string) vs. the enchant
                -- simply not being expected for this role/class (detail
                -- nil) -- the tile itself renders identically (bright,
                -- quality border, no marker), only the reason differs
                if cvm.detail then
                    GameTooltip:AddLine("This item cannot be enchanted",
                        C.parch.r, C.parch.g, C.parch.b)
                else
                    GameTooltip:AddLine("Enchant not expected for this role/class",
                        C.parch.r, C.parch.g, C.parch.b)
                end
            end
        elseif state == S.HAS then
            GameTooltip:AddLine("Equipped", C.hat.r, C.hat.g, C.hat.b)
        end
        GameTooltip:Show()
        return
    end
    -- Debuffs tab: afflicted = MISSING
    -- carrying the debuff icon, clean = HAS with no icon. UNKNOWN falls
    -- through to the generic branch below; NOTEXP does not occur here
    -- (expectations are not consulted on DEBUFFS).
    if sd.kind == "debuff" and state == S.MISSING then
        W.TipLine(tostring(cvm.detail or ("Afflicted: " .. sd.full)), C.fehlt)
        W.TipLine("counts as a gap until the debuff is gone", C.parchDim, 1)
        return
    elseif sd.kind == "debuff" and state == S.HAS then
        W.TipLine("Clean - no " .. sd.full, C.hat)
        return
    end
    -- Resistances tab: display only, never a gap (state is always HAS or
    -- UNKNOWN -- UNKNOWN falls through to the generic branch below).
    -- Provenance line (honesty rule, see core/model.lua's classify()
    -- resist branch and scan/engine.lua's AssembleResists header): a
    -- GEAR-RECONSTRUCTED total (row.player.resistsSource == "gear" -- the
    -- server never transmits UNIT_FIELD_RESISTANCES for a foreign player
    -- at all, so this is the ONLY source a foreign row can ever carry) is
    -- not the same kind of fact as a measured UnitResistance/GetUnitField
    -- reading, and the cell must say so rather than presenting a rebuilt
    -- number as an unqualified measurement. Every other source -- direct
    -- token/guid/field reads, and the always-measured own character
    -- (resistsSource nil) -- keeps the plain "display only" line.
    if sd.kind == "resist" and state == S.HAS then
        W.TipLine(sd.full .. ": " .. tostring(cvm.value or 0), C.parch)
        if row.player and row.player.resistsSource == "gear" then
            W.TipLine("reconstructed from equipment + race (not measured)",
                C.parchDim, 1)
        else
            W.TipLine("display only", C.parchDim, 1)
        end
        return
    end
    -- Hit columns: value, cap and how it was derived, gear breakdown,
    -- weapon skill assumption incl. the book note, dual wield, school
    -- extras -- all of it composed by the pure builder, which returns nil
    -- for UNKNOWN so those cells keep the generic not-readable tooltip.
    if sd.kind == "hit" then
        local hitLines = MX.HitTooltipLines(sd, cvm)
        if hitLines then
            local nH = table.getn(hitLines)
            for i = 1, nH do
                local hl = hitLines[i]
                if hl.right then
                    -- breakdown row: value flush right, so the addends of
                    -- the hit number line up in one column
                    W.TipDouble(hl.text, hl.right, C[hl.color] or C.parchDim,
                        C[hl.rightColor] or C[hl.color] or C.parch)
                else
                    W.TipLine(hl.text, C[hl.color] or C.parch, hl.wrap)
                end
            end
            return
        end
    end
    if state == S.HAS then
        -- Weapon cell with a KNOWN temp-enchant name (
        -- self = hidden-tooltip scan, foreign = SuperWoW
        -- GetWeaponEnchantInfo): the name is the title line; the generic
        -- weapon detail falls through to the standard HAS path below.
        if sd.kind == "weapon" then
            local ench = MX.WeaponEnchantName(cvm.detail)
            if ench then
                W.TipLine(ench, C.parch)
                W.TipLine("main hand temp enchant", C.parchDim, 1)
                return
            end
        end
        if sd.kind == "trinket" and type(cvm.detail) == "table" then
            local e = cvm.detail
            local qc = M.qualityColors(e.quality)
            W.TipLine(e.name or sd.full, qc)
            W.TipLine(sd.full .. " - inventory slot " .. sd.invSlot, C.parchDim, 1)
        elseif sd.kind == "aura" and sd.icon then
            -- consumable cell: same ladder as the painter --
            -- item name + buff name, or "<slot> active - item unknown"
            -- on the slot-generic fallback (MX.HasTooltipLines)
            local p = row.player
            local hLines = MX.HasTooltipLines(sd, cvm.detail,
                p and p.auras and p.auras.effects)
            for i = 1, table.getn(hLines) do
                local hl = hLines[i]
                W.TipLine(hl.text, C[hl.color] or C.parch, hl.wrap)
            end
        else
            -- Fixed HAS tooltip content: buff name,
            -- spell ID ("ID before name"), example item, slot. ID-match
            -- details already embed "(spell N)"; name matches get the
            -- table-known ID(s) appended here.
            local headline = tostring(cvm.detail or sd.full)
            local plain = headline
            local cut = string.find(plain, " (spell ", 1, true)
            if cut then
                plain = string.sub(plain, 1, cut - 1)
            else
                local ids = MX.KnownSpellIds(plain)
                if ids then
                    headline = headline .. " (spell " .. ids .. ")"
                end
            end
            W.TipLine(headline, C.hat)
            -- example item: the matched entry's item, else the slot list
            local entry = (DC.CONSUMABLES and DC.CONSUMABLES[plain])
                or (DC.CLASSBUFFS and DC.CLASSBUFFS[plain])
            local example = (entry and entry.item) or sd.items
            if example then
                W.TipLine("e.g. " .. example, C.parchDim, 1)
            end
            W.TipLine("Slot " .. sd.full, C.parch, 1)
        end
    elseif state == S.MISSING then
        if sd.kind == "trinket" then
            W.TipLine(sd.full .. " empty", C.fehlt)
            W.TipLine("unit readable, no trinket equipped - counts as a gap",
                C.parchDim, 1)
        elseif sd.kind == "ench" and cvm.detail ~= "no enchant" then
            -- empty gear slot (no item at all, cvm.detail == "<full>
            -- empty" -- core/model.lua): ALWAYS a gap, independent of the
            -- expectation checkbox -- distinct wording from the real
            -- "item present, no enchant" case right below
            W.TipLine(tostring(cvm.detail or (sd.full .. " empty")), C.fehlt)
            W.TipLine("unit readable, no item equipped - counts as a gap"
                .. " regardless of expectations", C.parchDim, 1)
        else
            W.TipLine("Missing: " .. sd.full, C.fehlt)
            W.TipLine("unit readable, slot empty - expected for "
                .. M.roleName(row.role), C.parchDim, 1)
        end
    elseif state == S.UNKNOWN then
        -- cells with cached data lead with the UNKNOWN
        -- reason ("offline" / "out of range" / "read failed"), then the
        -- aged observation. The cache NEVER upgrades the cell (iron rule).
        local last = (type(cvm.last) == "table") and cvm.last or nil
        local cause = row.unreadNote or tostring(cvm.detail or "no data")
        if last then
            W.TipLine(cause, C.unbek)
            W.TipLine(MX.LastLine(last) or "no cached data", C.parch, 1)
            W.TipLine("display only - still counts as UNKNOWN",
                C.parchDim, 1)
            return
        end
        W.TipLine("Not readable", C.unbek)
        if cause == "offline" then
            cause = "offline (UnitIsConnected = false)"
        elseif row.player and row.player.distance then
            cause = cause .. " - dist " .. math.floor(row.player.distance)
                .. " yd recorded (diagnosis, not a filter)"
        end
        W.TipLine(cause, C.parch, 1)
        W.TipLine("UNKNOWN is never condensed into MISSING", C.parchDim, 1)
    else -- NOTEXP
        -- Three different causes land here, and only ONE of them is the
        -- expectation matrix (core/model.lua): a class exemption (":689",
        -- detail "no ranged enchant for this class"), a legitimately empty
        -- exemptable slot (":705", detail "no item") and the actual
        -- expectation checkbox (detail nil). Both exemptions are decided
        -- BEFORE `expected` is ever read, so pointing their tooltip at the
        -- Options grid sent the user to a switch that cannot change the
        -- cell. Print the model's own reason where it has one.
        if cvm.detail then
            W.TipLine(tostring(cvm.detail), C.parch)
            W.TipLine("decided by class/item - the expectation matrix does"
                .. " not apply here", C.parchDim, 1)
        else
            W.TipLine("Not expected for role " .. M.roleName(row.role),
                C.parch)
            W.TipLine("change via Options - expectation matrix",
                C.parchDim, 1)
        end
    end
end

function M.HeaderTooltip(tile)
    local sd = tile.dcSD
    if not sd then
        return
    end
    W.TipLine(sd.full, W.WHITE)
    if sd.kind == "debuff" or sd.kind == "resist" then
        -- debuff/resist header tooltip is
        -- the full name only; no items line, no expected-for line
        -- (expectations are never consulted on either tab)
        return
    end
    if sd.kind == "hit" then
        -- hit columns: one sentence on where the number comes from --
        -- there is no hit API on this client, it is summed off the
        -- equipped items (plus auras and, for the own character,
        -- talents). No expected-for line (no expectations here).
        if sd.school then
            W.TipLine("generic spell hit plus everything that only helps "
                .. MX.SchoolTitle(sd.school) .. " spells - gear and talents",
                C.parchDim, 1)
        else
            W.TipLine("summed from the equipped items - no client API"
                .. " reports hit", C.parchDim, 1)
        end
        return
    end
    if sd.items then
        W.TipLine(sd.items, C.parch, 1)
    end
    if sd.kind == "trinket" then
        W.TipLine("Equipped item shown; only an EMPTY slot counts as a gap",
            C.parchDim, 1)
    end
    W.TipLine("expected for: " .. (tile.dcExpFor or "-"), C.parchDim, 1)
end

function M.BadgeTooltip(badge)
    local row = badge.dcRow
    if not row then
        return
    end
    -- content comes from the pure builder (current role +
    -- reason when suggested, then the left/right click actions with the
    -- class's actual cycle options); this only applies colors.
    local lines = MX.RoleTooltipLines(row.player and row.player.class,
        row.role, row.suggested, row.reason)
    local n = table.getn(lines)
    for i = 1, n do
        if i == 1 then
            W.TipLine(lines[i], row.suggested and C.goldHi or W.WHITE)
        elseif row.suggested and i == 2 then
            W.TipLine(lines[i], C.parch, 1)   -- reason line
        else
            W.TipLine(lines[i], C.parchDim, 1)
        end
    end
end

function M.WhisperTooltip(btn)
    local row = btn.dcRow
    if not row then
        return
    end
    W.TipLine("Whisper " .. row.player.name, W.WHITE)
    W.TipLine("sends their missing " .. (DC.TAB_LABEL[MX.state.tab] or "")
        .. " items - one click, one whisper, never automatic", C.parchDim, 1)
    local canW, remaining = MX.CanWhisper(row, GetTime())
    if not canW and remaining then
        W.TipLine("cooldown: " .. math.ceil(remaining) .. " s remaining", C.unbek)
    end
    if M.store().source == "sim" then
        W.TipLine("test mode: prints a local note, sends nothing",
            C.bannerYellowText, 1)
    end
end

function M.SumTooltip(sumf)
    local row = sumf.dcRow
    if not row then
        return
    end
    -- Identity stamp for M.RenderWindow -- see the same comment on
    -- M.CellTooltip. Like the cell tooltip, nothing below prints the
    -- player's name.
    sumf.dcTipPlayer = row.player and row.player.name
    if not row.readable then
        W.TipLine("not readable - no claim", C.unbek)
        return
    end
    if MX.IsDisplayTab(MX.state.tab) then
        W.TipLine("display only - no expectation on this tab", C.parchDim)
        return
    end
    -- DEBUFFS: no x/y expectation math on this tab --
    -- sumHas/sumExpected are nil, the column carries the TOTAL distinct
    -- debuff count (rowVM.debuffCount) instead.
    if row.sumHas == nil then
        local n = row.debuffCount or 0
        if n > 0 then
            local noun = (n == 1) and " distinct debuff" or " distinct debuffs"
            W.TipLine(n .. noun .. " on this player", C.fehlt)
        else
            W.TipLine("No debuffs - clean", C.hat)
        end
        W.TipLine("counts every debuff name, including any beyond the"
            .. " shown columns", C.parchDim, 1)
        return
    end
    W.TipLine(row.sumHas .. " of " .. row.sumExpected
        .. " expected slots active", W.WHITE)
    if row.unknowns and row.unknowns > 0 then
        W.TipLine(row.unknowns .. " expected slot(s) not verifiable"
            .. " (UNKNOWN) - excluded from both numbers", C.unbek, 1)
    end
end

function M.PillTooltip(pill)
    local g = pill.dcG
    if not g then
        return
    end
    -- DEBUFFS: the pill is a warning aggregate, not a
    -- readiness claim. Nil-guarded: a model without debuffTotal
    -- falls through to the ready wording (matches the rendered pill).
    if MX.state.tab == "DEBUFFS" and g.debuffTotal ~= nil then
        if g.debuffTotal > 0 then
            local noun = (g.debuffTotal == 1) and " debuff" or " debuffs"
            W.TipLine(g.debuffTotal .. noun
                .. " across this group's readable players", C.fehlt)
        elseif g.readable == g.total then
            W.TipLine("Clean - no debuffs on any player", C.hat)
        else
            W.TipLine("No debuffs found, but not every player is readable",
                C.parch)
        end
        W.TipLine("warning signal, not an expectation - green only when"
            .. " every player is readable and clean", C.parchDim, 1)
        if g.unreadable > 0 then
            W.TipLine(g.unreadable .. " not readable", C.unbek)
        end
        return
    end
    if MX.IsDisplayTab(MX.state.tab) then
        W.TipLine("Display only - no expectation tracked here", C.parch)
        if g.unreadable > 0 then
            W.TipLine(g.unreadable .. " not readable", C.unbek)
        end
        return
    end
    W.TipLine(g.ready .. " of " .. g.total .. " verified complete", W.WHITE)
    W.TipLine("green only when every player is readable and has no gaps"
        .. " - UNKNOWN never counts as ready", C.parchDim, 1)
    if g.unreadable > 0 then
        W.TipLine(g.unreadable .. " not readable", C.unbek)
    end
end

function M.CoverageTooltip()
    local cov = MX.vm and MX.vm.coverage
    if not cov then
        return
    end
    W.TipLine(cov.readable .. " of " .. cov.total .. " raid members readable",
        W.WHITE)
    W.TipLine(cov.offline .. " offline \194\183 " .. cov.readfailed
        .. " read failed", C.parch)
    if cov.far and cov.far > 0 then
        -- Diagnostic count only -- and a SUBSET of the readable number
        -- above, not a fourth bucket beside offline/read failed: a player
        -- who could not be read is never counted as far (core/model.lua).
        -- The threshold is inclusive there (distance >= FAR_LIMIT), so
        -- ">" would misstate the boundary by exactly one player standing
        -- at 40 yd.
        W.TipLine("at or beyond " .. (DC.FAR_LIMIT or 40) .. " yd: "
            .. cov.far, C.parch)
        W.TipLine("readable, already counted above - distance is"
            .. " diagnostic and never filters", C.parchDim, 1)
    end
    W.TipLine("Determined from the read result itself, not from a range"
        .. " assumption", C.parchDim, 1)
end

-- ------------------------------------------------------------------
-- unassigned chip (titlebar, right of the coverage pill): players whose
-- role is only a heuristic suggestion (vm.unassigned). Lazy singleton
-- like the toast, hidden while every role is confirmed. Plain Frame ->
-- NOT clickable; assignment happens on the role badge in the player row.
-- ------------------------------------------------------------------
function M.UnassignedTooltip()
    local vm = MX.vm
    local ua = vm and vm.unassigned
    if not ua then
        return
    end
    W.TipLine("Players without a confirmed role", C.goldHi)
    -- class colors, looked up from the vm rows (rendering reads only
    -- the vm); tooltip opens are event-driven, so this small pass does
    -- not violate the no-alloc-per-frame rule
    local classOf = {}
    local nG = table.getn(vm.groups)
    for gi = 1, nG do
        local g = vm.groups[gi]
        local nR = table.getn(g.rows)
        for ri = 1, nR do
            local row = g.rows[ri]
            if row.suggested and row.player then
                classOf[row.player.name] = row.player.class
            end
        end
    end
    local n = table.getn(ua.names)
    for i = 1, n do
        local nm = ua.names[i]
        local cc = classOf[nm] and C["class" .. classOf[nm]]
        W.TipLine(nm, cc or C.parch)
    end
    W.TipLine("Click the role badge in a player row to assign.",
        C.parchDim, 1)
end

function M.EnsureUnassignedPill()
    if UI.unassignedPill then
        return UI.unassignedPill
    end
    local pill = W.MakePill(UI.main, "DopingControlUnassignedPill")
    pill:SetPoint("LEFT", UI.coveragePill, "RIGHT", 8, 0)
    pill:SetHeight(17)
    W.SetBackdropG(pill, C.void, C.line)   -- coverage-pill look ...
    W.SetTextColorG(pill.text, C.goldHi)   -- ... with gold warning text
    W.AttachTooltip(pill, M.UnassignedTooltip, "ANCHOR_LEFT")
    UI.unassignedPill = pill
    return pill
end

-- ------------------------------------------------------------------
-- toast (simple fading FontString frame; OnUpdate only while shown)
-- ------------------------------------------------------------------
function M.EnsureToast()
    if UI.toast then
        return UI.toast
    end
    local toast = CreateFrame("Frame", "DopingControlToast", UI.main)
    toast:SetFrameStrata("DIALOG")
    toast:SetHeight(24)
    toast:SetPoint("BOTTOM", UI.main, "BOTTOM", 0, 26)
    toast:SetBackdrop(W.SOLID_BACKDROP)
    W.SetBackdropG(toast, C.bannerGreenBg, C.btnGreenBorder)
    toast.text = W.MakeText(toast, 10, C.btnGreenText)
    toast.text:SetPoint("CENTER", toast, "CENTER", 0, 0)
    toast:SetScript("OnUpdate", function()
        local e = GetTime() - (this.dcT0 or 0)
        if e >= 3.0 then
            this:Hide()
        elseif e > 2.6 then
            this:SetAlpha((3.0 - e) / 0.4)
        end
    end)
    toast:Hide()
    UI.toast = toast
    return toast
end

function MX.ShowToast(text)
    M.EnsureToast()
    UI.toast.text:SetText(text)
    UI.toast:SetWidth(UI.toast.text:GetStringWidth() + 32)
    UI.toast.dcT0 = GetTime()
    UI.toast:SetAlpha(1)
    UI.toast:Show()
end

-- ------------------------------------------------------------------
-- whisper (the ONLY SendChatMessage in this file; dead in sim mode)
-- ------------------------------------------------------------------
function M.WhisperClick()
    local row = this.dcRow
    if not row then
        return
    end
    local now = GetTime()
    local canW = MX.CanWhisper(row, now)
    if not canW then
        return
    end
    local text = DC_Model.whisperText(row, DC.TAB_LABEL[MX.state.tab], MX.vm.slots)
    if M.store().source == "sim" then
        -- Test mode: chat outputs are dead -> local note only.
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("DopingControl (test mode) - whisper"
                .. " suppressed. Would send to " .. row.player.name .. ": " .. text,
                0.88, 0.79, 0.54)
        end
    else
        SendChatMessage(text, "WHISPER", nil, row.player.name)
    end
    MX.lastWhisper[row.player.name] = now
    MX.Refresh()
end

-- ------------------------------------------------------------------
-- pooled factories (create on demand, never destroy, hide surplus)
-- ------------------------------------------------------------------
function M.EnsureHeaderTile(i)
    local t = UI.headerTiles[i]
    if t then
        return t
    end
    t = CreateFrame("Frame", "DopingControlHeaderTile" .. i, UI.headerRow)
    t:SetHeight(LC.HEADER_H - 4)
    t:SetBackdrop(W.SOLID_BACKDROP)
    W.SetBackdropG(t, C.panel2, C.line)
    t:EnableMouse(true)
    t.label = W.MakeText(t, 9, C.parch)
    t.label:SetPoint("TOP", t, "TOP", 0, -4)
    t.sub = W.MakeText(t, 7, C.faint)
    t.sub:SetPoint("BOTTOM", t, "BOTTOM", 0, 3)
    W.AttachTooltip(t, M.HeaderTooltip, "ANCHOR_LEFT")
    UI.headerTiles[i] = t
    if i > UI.headerMax then
        UI.headerMax = i
    end
    return t
end

function M.EnsureFooterCount(i)
    local fs = UI.footerFS[i]
    if fs then
        return fs
    end
    fs = W.MakeText(UI.footerRow, 9, C.faint)
    UI.footerFS[i] = fs
    if i > UI.footerMax then
        UI.footerMax = i
    end
    return fs
end

function M.GroupHeadClick()
    local d = M.db()
    if not d then
        return
    end
    if not d.collapse then
        d.collapse = {}
    end
    if d.collapse[this.dcRole] then
        d.collapse[this.dcRole] = nil
    else
        d.collapse[this.dcRole] = true
    end
    MX.Refresh()
end

function M.EnsureGroupHead(i)
    local gh = UI.groupHeads[i]
    if gh then
        return gh
    end
    gh = CreateFrame("Button", "DopingControlGroupHead" .. i, UI.scrollChild)
    gh:SetHeight(MX.GROUP_H)
    gh.bg = gh:CreateTexture(nil, "BACKGROUND")
    gh.bg:SetAllPoints(gh)
    gh.bg:SetTexture(0.063, 0.078, 0.106)  -- #10141b
    gh.bar = gh:CreateTexture(nil, "ARTWORK")
    gh.bar:SetPoint("TOPLEFT", gh, "TOPLEFT", 0, 0)
    gh.bar:SetPoint("BOTTOMLEFT", gh, "BOTTOMLEFT", 0, 0)
    gh.bar:SetWidth(3)
    gh.caret = W.MakeText(gh, 10, C.dim)
    gh.caret:SetPoint("LEFT", gh, "LEFT", 10, 0)
    gh.label = W.MakeText(gh, 10)
    gh.label:SetPoint("LEFT", gh, "LEFT", 24, 0)
    gh.pill = W.MakePill(gh, "DopingControlGroupHead" .. i .. "Pill")
    gh.pill:SetPoint("LEFT", gh.label, "RIGHT", 12, 0)
    W.AttachTooltip(gh.pill, M.PillTooltip, "ANCHOR_LEFT")
    -- marks this as a scroll-window pooled widget, so M.RenderWindow can
    -- tell "our tooltip, safe to close on rebind" from "some other addon's
    -- (or Blizzard's own) tooltip, leave it alone"
    gh.pill.dcPoolOwned = true
    gh.unread = W.MakeText(gh, 9, C.unbek)
    gh.unread:SetPoint("LEFT", gh.pill, "RIGHT", 10, 0)
    gh.gcount = W.MakeText(gh, 9, C.dim)
    gh.gcount:SetPoint("RIGHT", gh, "RIGHT", -10, 0)
    gh:SetScript("OnClick", M.GroupHeadClick)
    -- closes a tooltip anchored to gh.pill if this frame gets hidden
    -- outright (the leftover-hide loop in M.RenderWindow) -- see
    -- M.GroupHeadOnHide for why the rebind-path check alone is not enough
    gh:SetScript("OnHide", M.GroupHeadOnHide)
    UI.groupHeads[i] = gh
    if i > (UI.groupHeadMax or 0) then
        UI.groupHeadMax = i
    end
    return gh
end

-- Role badge clicks (replaces the earlier popover idea):
--   LEFT  = confirm the DISPLAYED role (clears the suggested state).
--   RIGHT = DC_Roles.cycle -> next plausible role for the class, saved
--           immediately (same persistence routing as confirm) + toast.
--           Single-entry/unknown classes: no-op, no toast.
function M.BadgeClick()
    local row = this.dcRow
    if not row then
        return
    end
    local d = M.db()
    if d and not d.roles then
        d.roles = {}
    end
    local src = M.store().source
    if arg1 == "RightButton" then
        local class = row.player and row.player.class
        local list = DC_Roles.CLASS_ROLES and DC_Roles.CLASS_ROLES[class]
        if not (list and table.getn(list) >= 2 and DC_Roles.cycle) then
            return   -- role is fixed for this class (or cycle not loaded)
        end
        local nextRole = DC_Roles.cycle(d, src, row.player.name, class,
            row.role)
        MX.ShowToast("Role: " .. M.roleName(nextRole) .. " (saved)")
        MX.Refresh()
        return
    end
    DC_Roles.confirm(d, src, row.player.name, row.role)
    local verb = row.suggested and "Suggestion confirmed: " or "Role confirmed: "
    local where = " (stored on the name)"
    if src == "sim" then
        where = " (test mode - not saved)"
    end
    MX.ShowToast(verb .. row.player.name .. " -> " .. M.roleName(row.role)
        .. where)
    MX.Refresh()
end

function M.EnsureRow(i)
    local rf = UI.rowPool[i]
    if rf then
        return rf
    end
    rf = CreateFrame("Frame", "DopingControlRow" .. i, UI.scrollChild)
    rf.dcIndex = i   -- pool index -> stable names for lazy row children
    rf:SetHeight(MX.ROW_H)
    -- alternating-row wash: created FIRST so the meaning-carrying
    -- unreadable wash below draws on top of it, never the other way round
    rf.zebra = rf:CreateTexture(nil, "BACKGROUND")
    rf.zebra:SetAllPoints(rf)
    rf.zebra:SetTexture(C.zebra.r, C.zebra.g, C.zebra.b)
    rf.zebra:SetAlpha(DC.ZEBRA_ALPHA)
    rf.zebra:Hide()
    rf.bg = rf:CreateTexture(nil, "BACKGROUND")
    rf.bg:SetAllPoints(rf)
    rf.bg:SetTexture(0.118, 0.133, 0.165)  -- unreadable-row wash
    rf.bg:SetAlpha(0.25)
    rf.bg:Hide()
    rf.name = W.MakeText(rf, 10)
    rf.name:SetPoint("LEFT", rf, "LEFT", MX.PAD + 2, 0)
    rf.name:SetJustifyH("LEFT")
    rf.status = W.MakeText(rf, 8, C.faint)
    rf.status:SetPoint("LEFT", rf.name, "RIGHT", 4, 0)
    -- out-of-range tag: "<n>yd" right of the
    -- name/status pair, melee-orange so it reads as a warning but not as
    -- an error; shown only while rowVM.far. Pooled with the row.
    rf.farFS = W.MakeText(rf, 8, C.roleMELEE or C.dim)
    rf.farFS:SetPoint("LEFT", rf.status, "RIGHT", 4, 0)
    rf.farFS:Hide()
    -- whisper button, right-aligned inside the name column
    rf.wsp = CreateFrame("Button", nil, rf)  -- pool child (factory exception)
    rf.wsp:SetWidth(26)
    rf.wsp:SetHeight(14)
    rf.wsp:SetPoint("LEFT", rf, "LEFT", MX.PAD + MX.NAME_COL_MIN - 28, 0)
    rf.wsp:SetBackdrop(W.SOLID_BACKDROP)
    W.SetBackdropG(rf.wsp, C.panel2, C.goldSoft)
    rf.wsp.text = W.MakeText(rf.wsp, 7, C.goldDim)
    rf.wsp.text:SetPoint("CENTER", rf.wsp, "CENTER", 0, 0)
    rf.wsp.text:SetText("PST")
    rf.wsp:SetScript("OnClick", M.WhisperClick)
    W.AttachTooltip(rf.wsp, M.WhisperTooltip, "ANCHOR_LEFT")
    -- marks scroll-window pooled tooltip owners -- see rf.sum.dcPoolOwned
    -- below for why M.RenderWindow needs this
    rf.wsp.dcPoolOwned = true
    -- role badge (right-click cycles, so the factory's
    -- left-only registration is widened here)
    rf.badge = W.MakeBadge(rf, nil)
    rf.badge:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    rf.badge:SetPoint("LEFT", rf, "LEFT",
        MX.PAD + MX.NAME_COL_MIN + MX.CELL_GAP + 3, 0)
    rf.badge:SetScript("OnClick", M.BadgeClick)
    W.AttachTooltip(rf.badge, M.BadgeTooltip, "ANCHOR_LEFT")
    rf.badge.dcPoolOwned = true
    -- sum (own mini frame so it can carry a tooltip)
    rf.sum = CreateFrame("Frame", nil, rf)  -- pool child (factory exception)
    rf.sum:SetWidth(MX.SUM_COL_W)
    rf.sum:SetHeight(MX.ROW_H)
    rf.sum:EnableMouse(true)
    rf.sum.text = W.MakeText(rf.sum, 10, C.parch)
    rf.sum.text:SetPoint("CENTER", rf.sum, "CENTER", 0, 0)
    W.AttachTooltip(rf.sum, M.SumTooltip, "ANCHOR_LEFT")
    -- marks this as a scroll-window pooled widget, so M.RenderWindow can
    -- tell "our tooltip, safe to close on a real rebind" from "some other
    -- addon's (or Blizzard's own) tooltip, leave it alone"
    rf.sum.dcPoolOwned = true
    rf.cells = {}
    rf.cellMax = 0
    -- closes a tooltip anchored to any of this row's children if the row
    -- gets hidden outright (the leftover-hide loop in M.RenderWindow) --
    -- see M.RowOnHide for why the rebind-path check alone is not enough
    rf:SetScript("OnHide", M.RowOnHide)
    UI.rowPool[i] = rf
    if i > UI.rowMax then
        UI.rowMax = i
    end
    return rf
end

-- Lazy pooled row-spanning message: ONE named FontString
-- per row, shown only in "message" mode (equipment row, gear unreadable,
-- no cached gear) -- the slot cells hide underneath it. Created on first
-- need, never destroyed; position set by PaintRow from the live layout.
function M.EnsureUnreadMsg(rf)
    if rf.unreadMsg then
        return rf.unreadMsg
    end
    local fs = rf:CreateFontString("DopingControlRow" .. rf.dcIndex
        .. "UnreadMsg", "OVERLAY")
    W.ApplyFont(fs, 9)
    W.SetTextColorG(fs, C.unbek)
    fs:SetJustifyH("LEFT")
    rf.unreadMsg = fs
    return fs
end

function M.EnsureCell(rf, i)
    local cell = rf.cells[i]
    if cell then
        return cell
    end
    cell = W.MakeCell(rf, nil, MX.CELL_W, MX.CELL_H)  -- pool child (factory exception)
    W.AttachTooltip(cell, M.CellTooltip, "ANCHOR_CURSOR")
    cell.dcPoolOwned = true   -- see rf.sum.dcPoolOwned: scroll-window rebind marker
    rf.cells[i] = cell
    if i > rf.cellMax then
        rf.cellMax = i
    end
    return cell
end

-- Lazy named icon texture per cell: shows buff
-- icons (aura HAS with cell.icon) and item icons (equipment cell.item).
-- Created once on first need, never destroyed; the standard 0.08..0.92
-- crop is constant, so it is set here exactly once. SetTexture goes
-- through W.SetTextureG (dcLastTex guard) -- no re-set on repaint.
function M.EnsureIconTex(cell)
    if cell.iconTex then
        return cell.iconTex
    end
    UI.cellIconN = UI.cellIconN + 1
    local t = cell:CreateTexture("DopingControlCell" .. UI.cellIconN .. "Icon",
        "ARTWORK")
    t:SetPoint("CENTER", cell, "CENTER", 0, 0)
    t:SetWidth(MX.CELL_ICON)
    t:SetHeight(MX.CELL_ICON)
    t:SetTexCoord(MX.ICON_CROP, 1 - MX.ICON_CROP,
        MX.ICON_CROP, 1 - MX.ICON_CROP)
    t:Hide()
    cell.iconTex = t
    return t
end

function M.HideIconTex(cell)
    if cell.iconTex then
        cell.iconTex:Hide()
    end
end

-- Lazy named corner marker per cell: 8px
-- solid square bottom-right. It carries the ENCHANT state of an equipment
-- item tile (green = enchanted, red = ench-kind slot without enchant and
-- not exempt) now that the tile border shows item QUALITY. OVERLAY layer
-- so it stays visible on top of the 18px ARTWORK item icon. Trinkets and
-- NOTEXP/EMPTY/UNKNOWN cells never show it.
function M.EnsureCornerTex(cell)
    if cell.cornerTex then
        return cell.cornerTex
    end
    UI.cellCornerN = UI.cellCornerN + 1
    local t = cell:CreateTexture("DopingControlCell" .. UI.cellCornerN
        .. "Corner", "OVERLAY")
    t:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -2, 2)
    t:SetWidth(8)
    t:SetHeight(8)
    t:SetTexture(W.SOLID_TEX)
    t:Hide()
    cell.cornerTex = t
    return t
end

function M.HideCornerTex(cell)
    if cell.cornerTex then
        cell.cornerTex:Hide()
    end
end

-- Lazy named icon texture per header tile (DEBUFFS tab):
-- MX.HEADER_ICON px (20 -- a 30px icon crossed both row
-- hairlines of the 26px tile), standard 0.08..0.92 crop, replaces the
-- label text when the model knows the debuff texture. Tile pool indices
-- are stable -> stable name.
function M.EnsureHeaderIcon(tile, i)
    if tile.iconTex then
        return tile.iconTex
    end
    local t = tile:CreateTexture("DopingControlHeaderTile" .. i .. "Icon",
        "ARTWORK")
    t:SetPoint("CENTER", tile, "CENTER", 0, 0)
    t:SetWidth(MX.HEADER_ICON)
    t:SetHeight(MX.HEADER_ICON)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t:Hide()
    tile.iconTex = t
    return t
end

-- ------------------------------------------------------------------
-- painters (change-guarded: style keys / guarded setters skip no-ops)
-- ------------------------------------------------------------------
-- Item tile: equipment (ench/trinket) cell whose vm carries cell.item
-- ({ id, enchant, quality, texture, name },
-- present whenever the gear entry is a table -- HAS, enchant-missing, or
-- NOTEXP with an item: subtype-exempt (wand/holdable) or the enchant
-- simply not expected for this role/class). The tile border ALWAYS
-- carries the item QUALITY color (unknown quality -> the state border as
-- fallback); the ENCHANT state rides ONLY the 8px corner marker (green
-- enchant>0, red enchant==0 on a non-exempt ench slot). NOTEXP renders as
-- a normal BRIGHT tile -- quality border, no marker, no dimming: with
-- neck/ring enchants defaulting unexpected, dimming every neck/ring in
-- the raid would read as a data failure rather than a deliberate
-- "not tracked" choice. The 0.45 dim stays EXCLUSIVE to the last-known
-- (cached) rendering below (M.PaintLastCell). Icon preferred over
-- monogram whenever item.texture is present.
function M.PaintItemTile(cell, sd, state, item)
    -- The cell's icon and FontString are created on demand (see W.MakeCell);
    -- this path touches both, so materialize both before anything reads them.
    W.CellIcon(cell)
    W.CellText(cell)
    local bg, border, textColor
    local marker = nil
    if sd.kind == "trinket" then
        local qText, qBorder = M.qualityColors(item.quality)
        bg, border, textColor = C.theadBg, qBorder, qText
    else -- ench-kind with a real item: neutral tile + quality border
        local qText, qBorder
        if item.quality ~= nil then
            qText, qBorder = M.qualityColors(item.quality)
        end
        bg = C.theadBg
        textColor = qText or C.parch
        if state == S.HAS then
            border = qBorder or C.hatBorder
            marker = C.hat
        elseif state == S.MISSING then
            border = qBorder or C.fehltBorder
            marker = C.fehlt
        else -- NOTEXP: bright quality-bordered tile, no marker (see header)
            border = qBorder or C.line
        end
    end
    W.SetCellBox(cell, DC_Cells.VariantFor(state, sd.kind, item and item.quality))
    if marker then
        local mk = M.EnsureCornerTex(cell)
        W.SetVertexG(mk, marker)
        W.SetAlphaG(mk, 1)   -- reset: cell may come out of dimmed rendering
        mk:Show()
    else
        M.HideCornerTex(cell)
    end
    cell.icon:Hide()
    if item.texture then
        cell.text:Hide()
        local t = M.EnsureIconTex(cell)
        W.SetTextureG(t, item.texture)
        W.SetAlphaG(t, 1)
        t:Show()
    else
        M.HideIconTex(cell)
        W.SetTextG(cell.text, MX.Monogram(item.name))
        W.SetTextColorG(cell.text, textColor)
        W.SetAlphaG(cell.text, 1)
        cell.text:Show()
    end
end

-- Last-known rendering (IRON RULE: display only). The
-- cell KEEPS the gray UNKNOWN backdrop + border -- it still IS an UNKNOWN
-- cell -- and only the content region (item icon / buff icon / check /
-- cross / monogram) shows the cached observation at MX.DIM_ALPHA. Alpha
-- sits on the texture/FontString, NEVER on the cell frame, so the border
-- stays crisp; every normal painter resets content alpha to 1 through
-- the same guarded setter. Ench tiles keep their (dimmed) corner marker
-- -- on a tile it is what encodes enchanted vs not.
function M.PaintLastCell(cell, sd, last)
    -- The cell's icon and FontString are created on demand (see W.MakeCell);
    -- this path touches both, so materialize both before anything reads them.
    W.CellIcon(cell)
    W.CellText(cell)
    W.SetCellBox(cell, "UNKNOWN")
    local item = nil
    if (sd.kind == "ench" or sd.kind == "trinket")
        and type(last.item) == "table" then
        item = last.item
    end
    if item then
        if sd.kind == "ench" then
            local mk = M.EnsureCornerTex(cell)
            W.SetVertexG(mk, (last.state == S.HAS) and C.hat or C.fehlt)
            W.SetAlphaG(mk, MX.DIM_ALPHA)
            mk:Show()
        else
            M.HideCornerTex(cell)
        end
        cell.icon:Hide()
        if item.texture then
            cell.text:Hide()
            local t = M.EnsureIconTex(cell)
            W.SetTextureG(t, item.texture)
            W.SetAlphaG(t, MX.DIM_ALPHA)
            t:Show()
        else
            M.HideIconTex(cell)
            W.SetTextG(cell.text, MX.Monogram(item.name))
            W.SetTextColorG(cell.text, C.unbek)
            W.SetAlphaG(cell.text, MX.DIM_ALPHA)
            cell.text:Show()
        end
    elseif last.icon then
        -- cached aura icon (HAS) or cached debuff icon (MISSING)
        cell.text:Hide()
        cell.icon:Hide()
        M.HideCornerTex(cell)
        local t = M.EnsureIconTex(cell)
        W.SetTextureG(t, last.icon)
        W.SetAlphaG(t, MX.DIM_ALPHA)
        t:Show()
    elseif last.state == S.HAS then
        cell.text:Hide()
        M.HideIconTex(cell)
        M.HideCornerTex(cell)
        cell.icon:SetWidth(16)
        cell.icon:SetHeight(16)
        W.SetTextureG(cell.icon, W.CHECK_TEX)
        cell.icon:SetTexCoord(0, 1, 0, 1)
        W.SetVertexG(cell.icon, C.hat)
        W.SetAlphaG(cell.icon, MX.DIM_ALPHA)
        cell.icon:Show()
    elseif last.state == S.MISSING then
        cell.text:Hide()
        M.HideIconTex(cell)
        M.HideCornerTex(cell)
        cell.icon:SetWidth(13)
        cell.icon:SetHeight(13)
        W.SetTextureG(cell.icon, W.CROSS_TEX)
        cell.icon:SetTexCoord(0, 1, 0, 1)
        W.SetVertexG(cell.icon, C.fehlt)
        W.SetAlphaG(cell.icon, MX.DIM_ALPHA)
        cell.icon:Show()
    else
        -- unexpected cached state (NOTEXP etc.): plain UNKNOWN "?"
        cell.icon:Hide()
        M.HideIconTex(cell)
        M.HideCornerTex(cell)
        W.SetTextG(cell.text, "?")
        W.SetTextColorG(cell.text, C.unbek)
        W.SetAlphaG(cell.text, 1)
        cell.text:Show()
    end
end

function M.PaintCell(cell, sd, cvm, row)
    -- The cell's icon and FontString are created on demand (see W.MakeCell);
    -- this path touches both, so materialize both before anything reads them.
    W.CellIcon(cell)
    W.CellText(cell)
    cell.dcSD = sd
    cell.dcVM = cvm
    cell.dcRow = row
    local state = cvm.state
    -- Cell shape: aura/weapon cells may carry .icon (texture
    -- path, only when HAS; weapon always nil for now), ench/trinket cells
    -- may carry .item. Both OPTIONAL -- every read below is nil-guarded,
    -- absent fields fall back to the glyph rendering.
    local item = nil
    if (sd.kind == "ench" or sd.kind == "trinket")
        and type(cvm.item) == "table" and state ~= S.UNKNOWN then
        item = cvm.item
    end
    local icon = nil
    if state == S.HAS and (sd.kind == "aura" or sd.kind == "weapon") then
        if sd.icon then
            -- consumable slot (only SLOTS_CONSUMABLES carries a slot
            -- icon): the ITEM behind the buff, never the aura texture --
            -- resolved item icon -> slot-generic icon -> green check
            -- (MX.ConsumableCellVisual, spec "Display"). Runs on repaint
            -- only (rebuild-on-scan), never per frame.
            local p = row.player
            local vis = MX.ConsumableCellVisual(sd, cvm.detail,
                p and p.auras and p.auras.effects)
            icon = vis.icon
        else
            icon = cvm.icon   -- class buffs keep the aura texture
        end
    elseif state == S.MISSING and sd.kind == "debuff" then
        icon = cvm.icon   -- afflicted cell = debuff texture
    end
    -- UNKNOWN cell carrying cell.last renders the cached
    -- visual dimmed; without .last it stays the plain gray "?". The cache
    -- is OPTIONAL vm data -- everything below is nil-guarded.
    local last = nil
    if state == S.UNKNOWN and type(cvm.last) == "table" and cvm.last.state then
        last = cvm.last
    end
    local key = state
    if last then
        -- dim flag baked into the style key so the change guard repaints
        -- when a cell flips between plain UNKNOWN and cached rendering
        local li = last.item
        key = "LAST:" .. tostring(last.state) .. ":" .. tostring(last.icon)
            .. ":" .. tostring(li and li.texture) .. ":"
            .. tostring(li and li.name) .. ":" .. tostring(li and li.quality)
    elseif item then
        key = "ITEM:" .. state .. ":" .. tostring(item.texture) .. ":"
            .. tostring(item.quality) .. ":" .. tostring(item.name)
    elseif icon then
        key = "ICON:" .. state .. ":" .. icon
    elseif state == S.HAS and sd.kind == "trinket" and type(cvm.detail) == "table" then
        -- legacy trinket detail table (older model shape) -- fallback path
        local e = cvm.detail
        key = "TRK:" .. tostring(e.texture) .. ":" .. tostring(e.quality)
            .. ":" .. tostring(e.name)
    elseif state == S.HAS and sd.kind == "debuff" then
        -- clean debuff cell shares the NOTEXP visual --
        -- own style key so pooled cells repaint when the tab switches
        -- (a plain "HAS" key would keep the green check from other tabs)
        key = "DBCLEAN"
    elseif state == S.HAS and sd.kind == "resist" then
        -- RESIST: the number IS the content -- own style key so a
        -- changed value repaints (a plain "HAS" key would not)
        key = "RESIST:" .. tostring(cvm.value or 0)
    elseif state == S.HAS and sd.kind == "hit" then
        -- hit columns: value AND cap state drive the look, so both go
        -- into the style key
        key = "HIT:" .. tostring(cvm.value or 0) .. ":"
            .. tostring(cvm.capMet)
    end
    if cell.dcStyle == key then
        return
    end
    cell.dcStyle = key

    if last then
        M.PaintLastCell(cell, sd, last)
    elseif item then
        M.PaintItemTile(cell, sd, state, item)
    elseif state == S.HAS and sd.kind == "trinket" and type(cvm.detail) == "table" then
        -- legacy trinket path (model without cell.item): unchanged
        local e = cvm.detail
        local qText, qBorder = M.qualityColors(e.quality)
        W.SetCellBox(cell, DC_Cells.VariantFor(state, sd.kind, e.quality))
        M.HideIconTex(cell)
        M.HideCornerTex(cell)
        if e.texture then
            cell.text:Hide()
            cell.icon:SetWidth(18)
            cell.icon:SetHeight(18)
            W.SetTextureG(cell.icon, e.texture)
            cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            W.SetVertexG(cell.icon, W.WHITE)
            W.SetAlphaG(cell.icon, 1)
            cell.icon:Show()
        else
            cell.icon:Hide()
            W.SetTextG(cell.text, MX.Monogram(e.name))
            W.SetTextColorG(cell.text, qText)
            W.SetAlphaG(cell.text, 1)
            cell.text:Show()
        end
    elseif state == S.HAS and icon then
        -- aura HAS with known buff texture: icon instead of the check
        -- glyph, green HAS backdrop kept
        W.SetCellBox(cell, "HAS")
        cell.text:Hide()
        cell.icon:Hide()
        M.HideCornerTex(cell)
        local t = M.EnsureIconTex(cell)
        W.SetTextureG(t, icon)
        W.SetAlphaG(t, 1)
        t:Show()
    elseif state == S.MISSING and icon then
        -- afflicted debuff cell: the debuff icon on the
        -- red MISSING backdrop -- same lazy icon mechanism as aura HAS
        W.SetCellBox(cell, "MISSING")
        cell.text:Hide()
        cell.icon:Hide()
        M.HideCornerTex(cell)
        local t = M.EnsureIconTex(cell)
        W.SetTextureG(t, icon)
        W.SetAlphaG(t, 1)
        t:Show()
    elseif state == S.HAS and sd.kind == "debuff" then
        -- clean cell = quiet near-invisible dot (NOTEXP
        -- visual): on a warning-signal tab the absence of a debuff is
        -- the unremarkable normal state, not a fulfilled expectation --
        -- NO green check. Afflicted cells keep the red tile + icon above.
        W.SetCellBox(cell, "SKIP")
        cell.icon:Hide()
        M.HideIconTex(cell)
        M.HideCornerTex(cell)
        W.SetTextG(cell.text, "\194\183")
        W.SetTextColorG(cell.text, C.skipGlyph)
        W.SetAlphaG(cell.text, 1)
        cell.text:Show()
    elseif state == S.HAS and sd.kind == "resist" then
        -- RESIST: neutral tile, the number is the text -- 0 is legitimate
        -- and renders dimmed (faint), any other value in parch. Never
        -- green/red -- this tab is display only, never a gap.
        W.SetCellBox(cell, "NEUTRAL")
        cell.icon:Hide()
        M.HideIconTex(cell)
        M.HideCornerTex(cell)
        local v = cvm.value or 0
        W.SetTextG(cell.text, tostring(v))
        if v > 0 then
            W.SetTextColorG(cell.text, C.parch)
        else
            W.SetTextColorG(cell.text, C.faint)
        end
        W.SetAlphaG(cell.text, 1)
        cell.text:Show()
    elseif state == S.HAS and sd.kind == "hit" then
        -- hit: the percentage IS the content. At or above the cap the
        -- whole tile turns green (background + border, the fulfilled
        -- look) so a capped player is visible at a glance across 40 rows;
        -- below the cap it keeps the neutral resistance tile with
        -- parchment text, faint on a plain 0. Never red: a hit number
        -- below its cap is information on a display tab, not a gap.
        local hs = MX.HitCellStyle(cvm)
        W.SetCellBox(cell, hs.bg == "hatBg" and "HAS" or "NEUTRAL")
        cell.icon:Hide()
        M.HideIconTex(cell)
        M.HideCornerTex(cell)
        W.SetTextG(cell.text, MX.HitText(cvm.value or 0))
        W.SetTextColorG(cell.text, C[hs.text] or C.parch)
        W.SetAlphaG(cell.text, 1)
        cell.text:Show()
    elseif state == S.HAS then
        W.SetCellBox(cell, "HAS")
        cell.text:Hide()
        M.HideIconTex(cell)
        M.HideCornerTex(cell)
        cell.icon:SetWidth(16)
        cell.icon:SetHeight(16)
        W.SetTextureG(cell.icon, W.CHECK_TEX)
        cell.icon:SetTexCoord(0, 1, 0, 1)
        W.SetVertexG(cell.icon, C.hat)
        W.SetAlphaG(cell.icon, 1)
        cell.icon:Show()
    elseif state == S.MISSING then
        W.SetCellBox(cell, "MISSING")
        cell.text:Hide()
        M.HideIconTex(cell)
        M.HideCornerTex(cell)
        cell.icon:SetWidth(13)
        cell.icon:SetHeight(13)
        W.SetTextureG(cell.icon, W.CROSS_TEX)
        cell.icon:SetTexCoord(0, 1, 0, 1)
        W.SetVertexG(cell.icon, C.fehlt)
        W.SetAlphaG(cell.icon, 1)
        cell.icon:Show()
    elseif state == S.UNKNOWN then
        W.SetCellBox(cell, "UNKNOWN")
        cell.icon:Hide()
        M.HideIconTex(cell)
        M.HideCornerTex(cell)
        W.SetTextG(cell.text, "?")
        W.SetTextColorG(cell.text, C.unbek)
        W.SetAlphaG(cell.text, 1)
        cell.text:Show()
    else -- NOTEXP: near-invisible middle dot
        W.SetCellBox(cell, "SKIP")
        cell.icon:Hide()
        M.HideIconTex(cell)
        M.HideCornerTex(cell)
        W.SetTextG(cell.text, "\194\183")
        W.SetTextColorG(cell.text, C.skipGlyph)
        W.SetAlphaG(cell.text, 1)
        cell.text:Show()
    end
end

function M.PaintGroupHead(gh, g, collapsed)
    gh.dcRole = g.role
    local rc = C["role" .. g.role]
    W.SetVertexG(gh.bar, rc)
    W.SetTextG(gh.caret, collapsed and "+" or "-")
    W.SetTextG(gh.label, string.upper(g.label))
    W.SetTextColorG(gh.label, rc)
    -- ready pill: green iff EVERY member is readable and verified complete.
    -- DEBUFFS: warning pill instead -- "clean" green
    -- only when debuffTotal==0 AND all readable, red "N debuffs" when >0,
    -- gray neutral while zero-but-unreadable. Nil-guarded: a
    -- model without debuffTotal keeps the ready pill.
    local pill = gh.pill
    pill.dcG = g
    if MX.state.tab == "DEBUFFS" and g.debuffTotal ~= nil then
        local pr = MX.DebuffPillText(g.debuffTotal, g.readable == g.total)
        W.SetTextG(pill.text, pr.text)
        if pr.kind == "good" then
            W.SetBackdropG(pill, C.hatBg, C.hatBorder)
            W.SetTextColorG(pill.text, C.hat)
        elseif pr.kind == "bad" then
            W.SetBackdropG(pill, C.fehltBg, C.fehltBorder)
            W.SetTextColorG(pill.text, C.fehlt)
        else
            W.SetBackdropG(pill, C.unbekBg, C.unbekBorder)
            W.SetTextColorG(pill.text, C.unbek)
        end
    elseif MX.IsDisplayTab(MX.state.tab) then
        -- neutral "info" style: display only, never a readiness claim --
        -- no green/red, just a quiet gray label
        W.SetTextG(pill.text, "display")
        W.SetBackdropG(pill, C.panel2, C.line)
        W.SetTextColorG(pill.text, C.dim)
    else
        W.SetTextG(pill.text, g.ready .. "/" .. g.total .. " ready")
        if g.ready == g.total then
            W.SetBackdropG(pill, C.hatBg, C.hatBorder)
            W.SetTextColorG(pill.text, C.hat)
        else
            W.SetBackdropG(pill, C.fehltBg, C.fehltBorder)
            W.SetTextColorG(pill.text, C.fehlt)
        end
    end
    pill:SetWidth(pill.text:GetStringWidth() + 16)
    if g.unreadable > 0 then
        W.SetTextG(gh.unread, "\194\183 " .. g.unreadable .. " unreadable")
    else
        W.SetTextG(gh.unread, "")
    end
    if collapsed then
        W.SetTextG(gh.gcount, "")
    else
        local gapsTxt
        if g.gaps > 0 then
            gapsTxt = "|cffd05252" .. g.gaps .. " gaps|r"
        else
            gapsTxt = g.gaps .. " gaps"
        end
        W.SetTextG(gh.gcount, g.total .. " players \194\183 " .. gapsTxt
            .. " \194\183 " .. g.readable .. "/" .. g.total .. " readable")
    end
end

function M.PaintRow(rf, row, layout, slots, now)
    local p = row.player
    local n = table.getn(slots)
    -- equipment-row render mode. hasAnyLast = any visible
    -- cell carries cached gear (cell.last); only consulted while the row
    -- is gear-unreadable, so the scan stays off the common path.
    local hasAnyLast = false
    if row.gearUnreadable then
        for i = 1, n do
            local cvm = row.cells[slots[i].id]
            if cvm and cvm.last then
                hasAnyLast = true
                break
            end
        end
    end
    local mode = MX.UnreadRowMode(row, hasAnyLast)
    -- name in class color; unreadable rows dimmed + washed background
    local cc = C["class" .. (p.class or "")] or C.ink
    W.SetTextG(rf.name, p.name)
    W.SetTextColorG(rf.name, cc)
    W.SetAlphaG(rf.name, row.readable and 1 or 0.55)
    if row.readable then
        rf.bg:Hide()
    else
        rf.bg:Show()
    end
    -- status: subgroup + unreadable reason. In "dimmed" mode the
    -- chip carries rowVM.unreadNote ("out of range") -- the spanning
    -- message is replaced by dimmed tiles, so the reason moves up here;
    -- in "message" mode the spanning line has it.
    local st = ""
    if p.subgroup then
        st = "G" .. p.subgroup
    end
    local note = nil
    if not row.readable then
        note = row.unreadableReason or "not readable"
    elseif mode == "dimmed" then
        note = row.unreadNote or "out of range"
    end
    if note then
        if st ~= "" then
            st = st .. " (" .. note .. ")"
        else
            st = "(" .. note .. ")"
        end
    end
    W.SetTextG(rf.status, st)
    -- far tag: diagnostic only, never changes any state/sum/pill (item 5).
    -- Suppressed in "message" mode -- the spanning line already carries
    -- the distance, a second "NNyd" next to the name would double it.
    if row.far and p.distance and mode ~= "message" then
        W.SetTextG(rf.farFS, MX.FarTag(p.distance))
        rf.farFS:Show()
    else
        rf.farFS:Hide()
    end
    -- whisper button (readable AND >=1 gap only; dim during cooldown)
    if row.whisperEligible then
        rf.wsp.dcRow = row
        local canW = MX.CanWhisper(row, now)
        W.SetAlphaG(rf.wsp, canW and 1 or 0.4)
        rf.wsp:Show()
    else
        rf.wsp:Hide()
    end
    -- role badge (suggested: "?" suffix + dimmer border -- 1.12 stand-in
    -- for a dashed border)
    local badge = rf.badge
    badge.dcRow = row
    W.SetTextG(badge.text, row.suggested and (row.role .. "?") or row.role)
    W.SetTextColorG(badge.text, C["role" .. row.role] or C.ink)
    W.SetBackdropG(badge, C.panel,
        row.suggested and LC.DIMBORDER[row.role]
        or C["roleBorder" .. row.role] or C.line)
    -- cells / row-spanning message: in "message" mode
    -- (gear unreadable, no cached gear) the slot cells hide and ONE dim
    -- pooled FontString spans the slot columns; "dimmed" and "plain" run
    -- the normal cell loop -- cached cells dim inside PaintCell.
    if mode == "message" then
        for i = 1, rf.cellMax do
            rf.cells[i]:Hide()
        end
        local msg = M.EnsureUnreadMsg(rf)
        local x0 = (layout.cols[1] and layout.cols[1].x) or layout.sumX
        if msg.dcX ~= x0 or msg.dcSumX ~= layout.sumX then
            msg.dcX = x0
            msg.dcSumX = layout.sumX
            msg:ClearAllPoints()
            msg:SetPoint("LEFT", rf, "LEFT", x0 + 2, 0)
            msg:SetWidth(layout.sumX - x0 - MX.CELL_GAP - 2)
        end
        W.SetTextG(msg, MX.UnreadRowText(p.distance))
        msg:Show()
    else
        if rf.unreadMsg then
            rf.unreadMsg:Hide()
        end
        for i = 1, n do
            local sd = slots[i]
            local col = layout.cols[i]
            local cell = M.EnsureCell(rf, i)
            if cell.dcX ~= col.x or cell.dcW ~= col.w then
                if cell.dcW ~= col.w then
                    -- The cell sprite is width-specific: DC_Cells.Coords picks
                    -- a DIFFERENT sheet tile for 30 and for 34 (the trinket
                    -- columns). M.PaintCell short-circuits on an unchanged
                    -- style key -- and the plain state keys ("HAS"/"MISSING"/
                    -- ...) carry no width -- so a pooled cell reused at the
                    -- other width would keep the old tile's texcoord and
                    -- render its baked 1px border squeezed or stretched.
                    -- W.SetCellBox guards on the width itself, but never gets
                    -- called; dropping the style key here is what lets it run.
                    cell.dcStyle = nil
                end
                cell.dcX = col.x
                cell.dcW = col.w
                cell:ClearAllPoints()
                cell:SetPoint("LEFT", rf, "LEFT", col.x, 0)
                cell:SetWidth(col.w)
            end
            M.PaintCell(cell, sd, row.cells[sd.id], row)
            cell:Show()
        end
        for i = n + 1, rf.cellMax do
            rf.cells[i]:Hide()
        end
    end
    -- sum
    if rf.sum.dcX ~= layout.sumX then
        rf.sum.dcX = layout.sumX
        rf.sum:ClearAllPoints()
        rf.sum:SetPoint("LEFT", rf, "LEFT", layout.sumX, 0)
    end
    rf.sum.dcRow = row
    if MX.state.tab == "DEBUFFS"
        and (row.debuffCount ~= nil or row.sumHas == nil) then
        -- no x/y on this tab -- the column carries the
        -- TOTAL distinct debuff count ("0" faint when clean, red when >0,
        -- "--" unreadable). Red alone carries the emphasis (no 1.12 bold).
        -- Degradation guard: a model (sumHas set, no
        -- debuffCount) keeps the old x/y path below.
        local dst = MX.DebuffSumText(row.debuffCount, row.readable)
        W.SetTextG(rf.sum.text, dst.text)
        W.SetTextColorG(rf.sum.text, C[dst.colorKey] or C.faint)
    elseif MX.IsDisplayTab(MX.state.tab) then
        -- no x/y on the display tabs either (row.sumHas is nil, see
        -- core/model.lua) -- the existing "no sum" glyph, not a new one
        W.SetTextG(rf.sum.text, "--")
        W.SetTextColorG(rf.sum.text, C.faint)
    elseif row.readable then
        W.SetTextG(rf.sum.text, row.sumHas .. "/" .. row.sumExpected)
        -- green only when verified complete; UNKNOWN cells tint the sum
        -- grey so a "7/7" next to a red ready pill does not read as green
        -- (UNKNOWN is excluded from both numbers)
        local scol = C.hat
        if row.gaps > 0 then
            scol = C.fehlt
        elseif row.unknowns and row.unknowns > 0 then
            scol = C.unbek
        end
        W.SetTextColorG(rf.sum.text, scol)
    else
        W.SetTextG(rf.sum.text, "--")
        W.SetTextColorG(rf.sum.text, C.faint)
    end
end

-- ------------------------------------------------------------------
-- expected-for string for header tile tooltips: pure MX.ExpectedForString
-- (per-class shape aware; offline-tested)
-- ------------------------------------------------------------------
-- scan-age ticker (1 s throttle; runs only while the window is shown)
-- ------------------------------------------------------------------
function M.TickerOnUpdate()
    local now = GetTime()
    if now < (this.dcNext or 0) then
        return
    end
    this.dcNext = now + 1
    local st = DC.store
    if st and st.scanAt then
        W.SetTextG(UI.scanAgeFS, MX.FormatScanAge(now - st.scanAt))
    else
        W.SetTextG(UI.scanAgeFS, MX.FormatScanAge(nil))
    end
end

-- ------------------------------------------------------------------
-- window construction (once, lazily)
-- ------------------------------------------------------------------
function M.TabClick()
    MX.SetTab(this.dcTab)
end

function M.FilterClick()
    MX.SetFilter(this.dcGapsOnly)
end

function M.BuildTitlebar(f)
    UI.titleFS = W.MakeText(f, 13, C.goldHi)
    UI.titleFS:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -13)
    UI.titleFS:SetText("DopingControl")

    local pill = W.MakePill(f, "DopingControlCoveragePill")
    pill:SetPoint("LEFT", UI.titleFS, "RIGHT", 12, 0)
    pill:SetHeight(17)
    W.SetBackdropG(pill, C.void, C.line)
    W.SetTextColorG(pill.text, C.parch)
    pill.bar = pill:CreateTexture("DopingControlCoveragePillBar", "ARTWORK")
    pill.bar:SetTexture(0.55, 0.61, 0.69)
    pill.bar:SetHeight(3)
    pill.bar:SetPoint("BOTTOMLEFT", pill, "BOTTOMLEFT", 2, 2)
    pill.bar:SetWidth(1)
    W.AttachTooltip(pill, M.CoverageTooltip, "ANCHOR_LEFT")
    UI.coveragePill = pill

    UI.scanAgeFS = W.MakeText(f, 9, C.dim)
    UI.scanAgeFS:SetPoint("LEFT", pill, "RIGHT", 12, 0)
    UI.scanAgeFS:SetText("no scan yet")

    local closeBtn = W.MakeButton(f, "DopingControlCloseButton", "X", 22, 19)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
    closeBtn:SetScript("OnClick", function()
        UI.main:Hide()
    end)
    local optionsBtn = W.MakeButton(f, "DopingControlOptionsButton", "Options", 62, 19)
    optionsBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    optionsBtn:SetScript("OnClick", function()
        if MX.hooks.options then
            MX.hooks.options()
        elseif DC_Options and DC_Options.Toggle then
            DC_Options.Toggle()
        end
    end)
    local reportBtn = W.MakeButton(f, "DopingControlReportButton", "Report...", 66, 19)
    reportBtn:SetPoint("RIGHT", optionsBtn, "LEFT", -6, 0)
    reportBtn:SetScript("OnClick", function()
        if MX.hooks.report then
            MX.hooks.report()
        elseif DC_Report and DC_Report.Toggle then
            DC_Report.Toggle()
        end
    end)
    local scanBtn = W.MakeButton(f, "DopingControlScanButton", "Scan", 50, 19)
    scanBtn:SetPoint("RIGHT", reportBtn, "LEFT", -6, 0)
    scanBtn:SetScript("OnClick", function()
        if MX.hooks.scan then
            MX.hooks.scan()
        end
    end)
end

function M.BuildTabs(f)
    UI.tabButtons = {}
    local tabY = -(10 + LC.TITLE_H)
    local tabX = MX.PAD
    for i = 1, table.getn(DC.TABS) do
        local id = DC.TABS[i]
        local b = CreateFrame("Button", "DopingControlTab" .. i, f)
        b:SetHeight(20)
        b:SetWidth(MX.TAB_W)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", tabX, tabY)
        b:SetBackdrop(W.SOLID_BACKDROP)
        b.text = W.MakeText(b, 10, C.dim)
        b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.text:SetText(DC.TAB_LABEL[id])
        b.dcTab = id
        b:SetScript("OnClick", M.TabClick)
        if id == "CLASSBUFFS" then
            W.AttachTooltip(b, function()
                W.TipLine("Class buffs", W.WHITE)
                W.TipLine("decision 12.4 still open - group assignment vs"
                    .. " self-responsibility", C.parchDim, 1)
            end, "ANCHOR_LEFT")
        end
        UI.tabButtons[i] = b
        tabX = tabX + MX.TAB_PITCH
    end
end

function M.BuildToolbar(f)
    UI.filterButtons = {}
    local tbY = -(10 + LC.TITLE_H + LC.TABS_H)
    local filterLabel = W.MakeText(f, 9, C.dim)
    filterLabel:SetPoint("TOPLEFT", f, "TOPLEFT", MX.PAD, tbY - 5)
    filterLabel:SetText("Filter:")
    local fx = MX.PAD + 34
    local defs = { { label = "All", gapsOnly = false, w = 36 },
                   { label = "Gaps only", gapsOnly = true, w = 66 } }
    for i = 1, 2 do
        local b = CreateFrame("Button", "DopingControlFilter" .. i, f)
        b:SetHeight(17)
        b:SetWidth(defs[i].w)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", fx, tbY - 1)
        b:SetBackdrop(W.SOLID_BACKDROP)
        b.text = W.MakeText(b, 9, C.dim)
        b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.text:SetText(defs[i].label)
        b.dcGapsOnly = defs[i].gapsOnly
        b:SetScript("OnClick", M.FilterClick)
        UI.filterButtons[i] = b
        fx = fx + defs[i].w + 2
    end
    local hintFS = W.MakeText(f, 8, C.faint)
    hintFS:SetPoint("TOPLEFT", f, "TOPLEFT", fx + 12, tbY - 6)
    hintFS:SetText("Grouped by role \194\183 gaps first \194\183 click a group"
        .. " header to collapse")

    -- legend (right side), built right-to-left so it follows frame width
    local legend = { { "not expected", C.skip, C.skipBorder },
                     { "not readable", C.unbekBg, C.unbekBorder },
                     { "missing", C.fehltBg, C.fehltBorder },
                     { "active", C.hatBg, C.hatBorder } }
    local anchor = nil
    for i = 1, 4 do
        local lfs = W.MakeText(f, 8, C.dim)
        if anchor then
            lfs:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
        else
            lfs:SetPoint("TOPRIGHT", f, "TOPRIGHT", -MX.PAD, tbY - 6)
        end
        lfs:SetText(legend[i][1])
        local sw = CreateFrame("Frame", "DopingControlLegendSwatch" .. i, f)
        sw:SetWidth(10)
        sw:SetHeight(10)
        sw:SetPoint("RIGHT", lfs, "LEFT", -3, 0)
        sw:SetBackdrop(W.SOLID_BACKDROP)
        W.SetBackdropG(sw, legend[i][2], legend[i][3])
        anchor = sw
    end
    UI.hiddenFS = W.MakeText(f, 8, C.goldDim)
    UI.hiddenFS:SetPoint("RIGHT", anchor, "LEFT", -16, 0)
    UI.hiddenFS:SetText("")
end

function M.BuildBody(f)
    -- TEST MODE banner
    local banner = CreateFrame("Frame", "DopingControlBanner", f)
    banner:SetHeight(LC.BANNER_H - 2)
    banner:SetBackdrop(W.SOLID_BACKDROP)
    W.SetBackdropG(banner, C.bannerYellowBg, C.bannerYellowBorder)
    banner.text = W.MakeText(banner, 9, C.bannerYellowText)
    banner.text:SetPoint("CENTER", banner, "CENTER", 0, 0)
    banner.dcText = MX.BannerText()   -- cache + text stay in step (see M.Render)
    banner.text:SetText(banner.dcText)
    banner:Hide()
    UI.banner = banner

    -- header row (OUTSIDE the scroll frame -- 1.12 has no sticky)
    local hr = CreateFrame("Frame", "DopingControlHeaderRow", f)
    hr:SetHeight(LC.HEADER_H)
    hr:SetBackdrop(W.SOLID_BACKDROP)
    W.SetBackdropG(hr, C.theadBg, C.goldSoft)
    UI.headerRow = hr
    UI.headPlayerFS = W.MakeText(hr, 8, C.faint)
    -- bar-relative x: PAD - BAR_X_OFF + 2 = 8px inset inside the bar
    -- (>=6px) and frame-x PAD+2 = aligned with row names
    UI.headPlayerFS:SetPoint("LEFT", hr, "LEFT", MX.PAD - LC.BAR_X_OFF + 2, 0)
    UI.headPlayerFS:SetText("PLAYER")
    UI.headRoleFS = W.MakeText(hr, 8, C.faint)
    UI.headRoleFS:SetText("ROLE")
    UI.headSumFS = W.MakeText(hr, 8, C.faint)
    UI.headSumFS:SetText("SUM")

    -- scroll frame
    UI.scrollFrame = CreateFrame("ScrollFrame", "DopingControlScrollFrame", f,
        "UIPanelScrollFrameTemplate")
    UI.scrollChild = CreateFrame("Frame", "DopingControlScrollChild", UI.scrollFrame)
    UI.scrollChild:SetWidth(600)
    UI.scrollChild:SetHeight(100)
    UI.scrollFrame:SetScrollChild(UI.scrollChild)

    -- Scrolling now changes WHICH rows are materialized, so the window has
    -- to be redrawn on top of whatever UIPanelScrollFrameTemplate's own
    -- OnVerticalScroll already does. That template handler is the ONLY
    -- place in FrameXML that re-syncs the scrollbar thumb to the new
    -- offset (scrollbar:SetValue(arg1)) and enables/disables the up/down
    -- arrow buttons at the ends of the range
    -- (_wow-reference/FrameXML-1.12.1/FrameXML/UIPanelTemplates.xml:
    -- 191-206) -- overwriting it outright instead of chaining would leave
    -- the up arrow permanently disabled and the down arrow never disabling
    -- at the bottom. Chained the same way W.AttachTooltip chains
    -- OnEnter/OnLeave (ui/widgets.lua:307-308): capture the template's
    -- handler and call it FIRST, on every event -- only OUR repaint is
    -- throttled, never the template's own bookkeeping.
    local dcOldOnVerticalScroll = UI.scrollFrame:GetScript("OnVerticalScroll")
    UI.scrollFrame:SetScript("OnVerticalScroll", function()
        if dcOldOnVerticalScroll then
            dcOldOnVerticalScroll()
        end
        local t = GetTime()
        if t < (UI.nextWindowDraw or 0) then
            -- throttled: remember a redraw is owed. The self-unhooking
            -- OnUpdate below catches up once the throttle window opens
            -- back up, so a dropped event's final position (a fast wheel
            -- spin, or the end of a quick thumb-drag) is never silently
            -- lost -- see M.CatchUpScrollWindow.
            UI.windowDirty = true
            if not UI.scrollFrame:GetScript("OnUpdate") then
                UI.scrollFrame:SetScript("OnUpdate", M.CatchUpScrollWindow)
            end
            return
        end
        UI.nextWindowDraw = t + 0.05
        M.RenderWindow()
    end)

    -- empty state (no scan yet)
    UI.emptyFS = W.MakeText(f, 11, C.parch)
    UI.emptyFS:SetPoint("CENTER", UI.scrollFrame, "CENTER", 0, 14)
    UI.emptyFS:SetText("No raid, no party - nothing to check")
    UI.emptyFS:Hide()
    UI.emptyHintFS = W.MakeText(f, 9, C.faint)
    UI.emptyHintFS:SetPoint("TOP", UI.emptyFS, "BOTTOM", 0, -6)
    UI.emptyHintFS:SetText("/dc test shows a simulated raid \194\183"
        .. " /dc probe writes the M0 probe")
    UI.emptyHintFS:Hide()

    -- footer row (sticky "missing per slot", OUTSIDE the scroll frame)
    local fr = CreateFrame("Frame", "DopingControlFooterRow", f)
    fr:SetHeight(LC.FOOTER_H)
    fr:SetBackdrop(W.SOLID_BACKDROP)
    W.SetBackdropG(fr, C.theadBg, C.goldSoft)
    UI.footerRow = fr
    UI.footLabelFS = W.MakeText(fr, 8, C.faint)
    UI.footLabelFS:SetText("MISSING PER SLOT")

    -- frame foot hints
    local foot = W.MakeText(f, 8, C.faint)
    foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", MX.PAD, 16)
    foot:SetText("PST whispers that player's missing items of the current tab"
        .. " - on click only \194\183 Expectations per role: Options -"
        .. " expectation matrix")
    UI.footFS = foot
end

function M.BuildFrame()
    if UI.main then
        return UI.main
    end
    local f = CreateFrame("Frame", "DopingControlFrame", UIParent)
    UI.main = f
    f:SetWidth(MX.MIN_FRAME_W)
    f:SetHeight(300)
    f:SetBackdrop(W.PANEL_BACKDROP)
    f:SetBackdropColor(1, 1, 1, 0.97)
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    f:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local d = M.db()
        if d then
            d.framePos = { point = "TOPLEFT", relPoint = "BOTTOMLEFT",
                           x = this:GetLeft(), y = this:GetTop() }
        end
    end)
    local d = M.db()
    local pos = d and d.framePos
    if pos and pos.x and pos.y then
        f:SetPoint(pos.point or "TOPLEFT", UIParent, pos.relPoint or "BOTTOMLEFT",
            pos.x, pos.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    f:SetScript("OnUpdate", M.TickerOnUpdate)
    table.insert(UISpecialFrames, "DopingControlFrame")

    M.BuildTitlebar(f)
    M.BuildTabs(f)
    M.BuildToolbar(f)
    M.BuildBody(f)

    f:Hide()
    return f
end

-- ------------------------------------------------------------------
-- render (rebuilds nothing, repaints pooled frames; hides surplus)
-- ------------------------------------------------------------------
function M.RenderChrome(vm, layout, frameW, hiddenCount)
    -- tabs + filter styling
    for i = 1, table.getn(DC.TABS) do
        local b = UI.tabButtons[i]
        local active = (DC.TABS[i] == MX.state.tab)
        W.SetTextColorG(b.text, active and C.goldHi or C.dim)
        W.SetBackdropG(b, active and C.panel or C.panel2,
            active and C.goldSoft or C.line)
    end
    for i = 1, 2 do
        local b = UI.filterButtons[i]
        local active = (b.dcGapsOnly == MX.state.gapsOnly)
        W.SetTextColorG(b.text, active and C.btnGreenText or C.dim)
        W.SetBackdropG(b, active and C.btnGreenBg or C.panel2,
            active and C.btnGreenBorder or C.line)
    end
    if hiddenCount > 0 then
        W.SetTextG(UI.hiddenFS, hiddenCount .. " slots hidden")
    else
        W.SetTextG(UI.hiddenFS, "")
    end
    -- coverage pill + bar
    local cov = vm.coverage
    local pill = UI.coveragePill
    -- the tab's OWN read channel, named: gear/hit/resistances are not the
    -- aura channel, and one shared "readable" number claimed full
    -- coverage on tabs that knew far less (see DC_Model.ChannelRead)
    local covN = cov.channelReadable or cov.readable
    local covLabel = "readable"
    if DC_Model and DC_Model.CoverageLabel then
        covLabel = DC_Model.CoverageLabel(vm.tab)
    end
    W.SetTextG(pill.text, covN .. "/" .. cov.total .. " " .. covLabel)
    pill:SetWidth(pill.text:GetStringWidth() + 18)
    local frac = 0
    if cov.total > 0 then
        frac = covN / cov.total
    end
    local barW = math.floor((pill.text:GetStringWidth() + 14) * frac)
    if barW < 1 then
        barW = 1
    end
    if pill.dcBarW ~= barW then
        pill.dcBarW = barW
        pill.bar:SetWidth(barW)
    end
    -- unassigned chip: only while suggestions exist (n > 0), else hidden
    local ua = vm.unassigned
    if MX.UnassignedVisible(ua) then
        local upill = M.EnsureUnassignedPill()
        if upill.dcCount ~= ua.count then
            upill.dcCount = ua.count
            W.SetTextG(upill.text, ua.count .. " unassigned")
            upill:SetWidth(upill.text:GetStringWidth() + 18)
        end
        upill:Show()
    elseif UI.unassignedPill then
        UI.unassignedPill:Hide()
    end
    -- scan-age text yields its anchor to the chip while it is shown
    local ageAnchor = UI.coveragePill
    if MX.UnassignedVisible(ua) then
        ageAnchor = UI.unassignedPill
    end
    if UI.scanAgeFS.dcAnchor ~= ageAnchor then
        UI.scanAgeFS.dcAnchor = ageAnchor
        UI.scanAgeFS:ClearAllPoints()
        UI.scanAgeFS:SetPoint("LEFT", ageAnchor, "RIGHT", 12, 0)
    end
end

function M.RenderHeader(layout, slots, yTop, frameW)
    local hr = UI.headerRow
    hr:ClearAllPoints()
    hr:SetPoint("TOPLEFT", UI.main, "TOPLEFT", LC.BAR_X_OFF, yTop)
    hr:SetWidth(frameW - LC.BAR_X_OFF * 2)
    local d = M.db()
    local expectTbl = MX.ExpectTable(d)
    local nSlots = table.getn(slots)
    for i = 1, nSlots do
        local sd = slots[i]
        local col = layout.cols[i]
        local tile = M.EnsureHeaderTile(i)
        if tile.dcX ~= col.x or tile.dcW ~= col.w then
            tile.dcX = col.x
            tile.dcW = col.w
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", hr, "TOPLEFT", col.x - LC.BAR_X_OFF, -2)
            tile:SetWidth(col.w)
        end
        tile.dcSD = sd
        if sd.kind == "debuff" or sd.kind == "resist"
           or sd.kind == "hit" then
            -- expectations are not consulted on DEBUFFS/RESIST (hit
            -- columns included)
            tile.dcExpFor = nil
        else
            tile.dcExpFor = MX.ExpectedForString(sd.id, expectTbl)
        end
        -- DEBUFFS header tiles: the debuff icon (MX.HEADER_ICON px,
        -- standard crop) replaces the label text when the model knows a
        -- texture; the
        -- fallback for icon-less debuff columns is a monogram of the
        -- name (slot.label is nil on debuff columns by design).
        if sd.kind == "debuff" and sd.icon then
            -- icon header tiles are a DEBUFFS feature (dynamic columns
            -- carry the debuff texture as a FULL path). Consumable slots
            -- now carry a BARE slot-generic icon for the CELL fallback
            -- ladder -- their header keeps the label/sub text.
            local it = M.EnsureHeaderIcon(tile, i)
            W.SetTextureG(it, sd.icon)
            it:Show()
            tile.label:Hide()
            tile.sub:Hide()
        else
            if tile.iconTex then
                tile.iconTex:Hide()
            end
            local lbl = sd.label
            if not lbl and sd.kind == "debuff" then
                lbl = MX.Monogram(sd.full)
            end
            W.SetTextG(tile.label, lbl or "")
            W.SetTextG(tile.sub, sd.sub or "")
            tile.label:Show()
            tile.sub:Show()
        end
        tile:Show()
    end
    for i = nSlots + 1, UI.headerMax do
        UI.headerTiles[i]:Hide()
    end
    if UI.headRoleFS.dcX ~= layout.roleX then
        UI.headRoleFS.dcX = layout.roleX
        UI.headRoleFS:ClearAllPoints()
        UI.headRoleFS:SetPoint("LEFT", hr, "LEFT",
            layout.roleX - LC.BAR_X_OFF + 12, 0)
    end
    if UI.headSumFS.dcX ~= layout.sumX then
        UI.headSumFS.dcX = layout.sumX
        UI.headSumFS:ClearAllPoints()
        UI.headSumFS:SetPoint("LEFT", hr, "LEFT",
            layout.sumX - LC.BAR_X_OFF + 6, 0)
    end
end

-- ------------------------------------------------------------------
-- Scroll-range resync -- a 1.12 gotcha that shows up as "the list will
-- not scroll all the way down once every group is expanded".
--
-- Growing the scroll CHILD is not enough. The template's scrollbar keeps
-- whatever min/max it was last handed, so expanding a group while the bar
-- already sits at the OLD bottom leaves the new rows unreachable: the
-- thumb simply refuses to travel further. The arithmetic above is fine
-- (content height counts every group head and every visible row) -- what
-- was missing is telling the BAR about it.
--
-- UpdateScrollChildRect makes the frame recompute its range now rather
-- than on some later engine tick; SetMinMaxValues then does exactly what
-- Blizzard's own ScrollFrame_OnScrollRangeChanged does
-- (FrameXML/UIPanelTemplates.lua) -- we simply stop depending on WHETHER
-- that handler fires. Both are existence-guarded: this must never be the
-- thing that breaks the window.
-- ------------------------------------------------------------------
function M.SyncScrollRange()
    local sf = UI.scrollFrame
    if not sf or not sf.GetName then
        return
    end
    if sf.UpdateScrollChildRect then
        sf:UpdateScrollChildRect()
    end
    local name = sf:GetName()
    local bar = name and getglobal(name .. "ScrollBar")
    if not bar or not sf.GetVerticalScrollRange then
        return
    end
    local range = sf:GetVerticalScrollRange() or 0
    if range < 0 then
        range = 0
    end
    bar:SetMinMaxValues(0, range)
    -- clamp the thumb: after a COLLAPSE the old value can sit past the new
    -- bottom, which would leave the view parked in empty space
    local v = bar:GetValue() or 0
    if v > range then
        bar:SetValue(range)
    end
end

-- Flatten the view model into one ordered list of render units (group head or
-- data row) plus their heights. Built once per refresh so a scroll does not
-- have to re-walk the model, and so the window math sees real heights.
function M.BuildUnits(vm)
    local d = M.db()
    local collapsed = (d and d.collapse) or {}
    local gapsOnly = MX.state.gapsOnly
    local units, heights = {}, {}
    local visIdx = 0
    local nGroups = table.getn(vm.groups)
    for gi = 1, nGroups do
        local g = vm.groups[gi]
        local isCollapsed = collapsed[g.role] and true or false
        table.insert(units, { kind = "head", g = g, collapsed = isCollapsed })
        table.insert(heights, MX.GROUP_H)
        if not isCollapsed then
            local nRows = table.getn(g.rows)
            for ri = 1, nRows do
                local row = g.rows[ri]
                if MX.RowVisible(row, gapsOnly) then
                    -- zebra by VISIBLE index, exactly as before: with "gaps
                    -- only" on or a group collapsed the stripes must still
                    -- alternate on screen
                    visIdx = visIdx + 1
                    table.insert(units, {
                        kind = "row", row = row,
                        zebra = (math.mod(visIdx, 2) == 0),
                    })
                    table.insert(heights, MX.ROW_H)
                end
            end
        end
    end
    return units, heights
end

function M.RenderRows(vm, layout, slots)
    local units, heights = M.BuildUnits(vm)
    local total = 0
    for i = 1, table.getn(heights) do
        total = total + heights[i]
    end
    UI.units = { units = units, heights = heights, layout = layout,
                 slots = slots, total = total }
    UI.windowFirst = nil          -- force a full window draw
    UI.windowDirty = false        -- this draw covers whatever was owed
    M.RenderWindow()
    return total                  -- content height, same contract as before
end

-- Self-unhooking catch-up for the scroll throttle in M.BuildBody's
-- OnVerticalScroll handler: an event that lands inside the 0.05s window
-- only sets UI.windowDirty and returns without drawing (see there).
-- Without a follow-up, that dropped event's final scroll position would
-- never get painted -- a fast wheel spin (a mouse-wheel notch moves the
-- thumb by scrollBar:GetHeight()/2, roughly ten rows here, well past the
-- two spare units MX.VisibleWindow keeps) or the end of a quick
-- thumb-drag would leave a visibly blank strip, or a window that does not
-- match where the thumb ended up, until some UNRELATED refresh happened
-- to run later. Hooked onto UI.scrollFrame only while a redraw is owed
-- (OnVerticalScroll attaches it on the first throttled event), and
-- unhooks itself the instant nothing is pending -- no permanent
-- per-frame OnUpdate (project rule: hang up in the idle case).
function M.CatchUpScrollWindow()
    local t = GetTime()
    if UI.windowDirty and t >= (UI.nextWindowDraw or 0) then
        UI.windowDirty = false
        UI.nextWindowDraw = t + 0.05
        M.RenderWindow()
    end
    if not UI.windowDirty then
        this:SetScript("OnUpdate", nil)
    end
end

-- Whether `owner` (a GameTooltip owner frame) is one of `rf`'s pooled
-- tooltip-bearing children -- the whisper button, role badge, sum, or one
-- of its slot cells. Delegates to MX.OwnsTooltip (pure, offline-tested);
-- this wrapper only exists to supply the real frame references. Two call
-- sites: M.RenderWindow, to find which row (if any) is about to be
-- rebound out from under a currently open tooltip; M.RowOnHide, for a row
-- about to be hidden entirely (see there). Cheap pointer comparisons only,
-- no allocation; only ever called while a tooltip is actually shown and
-- owned by one of our pooled widgets (rare).
function M.RowOwnsTooltip(rf, owner)
    return MX.OwnsTooltip(rf.wsp, rf.badge, rf.sum, rf.cells, rf.cellMax, owner)
end

-- A pooled row frame being hidden entirely (the leftover-hide loop in
-- M.RenderWindow when the visible unit count shrinks -- a smaller roster,
-- a collapsed group, the "gaps only" filter -- or any future path that
-- hides a row) does NOT go through M.RenderWindow's per-unit rebind check
-- at all: that check only runs for units still inside [first, last] this
-- redraw. There is also no other OnHide handler anywhere in this addon
-- that touches GameTooltip (confirmed by grep across the repo). Without
-- this, a tooltip anchored to a widget on a row that just scrolled,
-- collapsed, or filtered out of view would keep showing that vanished
-- player's values, unboundedly, on an invisible frame -- the same failure
-- class fixed in M.RenderWindow's rebind path (fix round 2), reached
-- through a different door. Unconditional close, not routed through
-- MX.ShouldHideTooltip: a row that is disappearing has no "new identity"
-- to compare against the way a row being rebound in place does.
function M.RowOnHide()
    if not (GameTooltip and GameTooltip:IsShown()) then
        return
    end
    -- W.dcTipOwner, not GameTooltip's non-existent "GetOwner" method (see
    -- ui/widgets.lua's W.dcTipOwner / W.AttachTooltip for the full
    -- reasoning). GameTooltip:IsOwned(owner) IS real 1.12 API (used
    -- e.g. by FrameXML/ActionButton.lua and Blizzard_TalentUI) and serves
    -- here as the gegenprobe: it can only make this MORE conservative
    -- (refuse to hide if our bookkeeping and the tooltip's real owner ever
    -- disagree), never less -- matching the "never touch a foreign
    -- tooltip" rule dcPoolOwned already enforces.
    local owner = W.dcTipOwner
    if owner and owner.dcPoolOwned and GameTooltip:IsOwned(owner)
        and M.RowOwnsTooltip(this, owner) then
        GameTooltip:Hide()
    end
end

-- Same reasoning as M.RowOnHide, for the group-head pool -- its one
-- tooltip-bearing child is the ready/status pill.
function M.GroupHeadOnHide()
    if not (GameTooltip and GameTooltip:IsShown()) then
        return
    end
    -- W.dcTipOwner, not GameTooltip's non-existent "GetOwner" method -- see M.RowOnHide.
    local owner = W.dcTipOwner
    if owner and owner.dcPoolOwned and GameTooltip:IsOwned(owner)
        and owner == this.pill then
        GameTooltip:Hide()
    end
end

-- Draws only the units inside the scroll window. Pool slots are handed out
-- by window position rather than data index (MX.NextWindowSlot), so a
-- scrolled window still uses the SAME roughly-22-slot pool -- what changes
-- is which unit each slot paints. Every call here repaints the WHOLE
-- window (there is no per-row diffing against the previous slice), which
-- is exactly why the caller throttles how often this runs.
--
-- Viewport height: LC.MAX_SCROLL_H, the fixed design cap, rather than
-- UI.scrollFrame:GetHeight(). M.Render() computes contentH via
-- M.RenderRows() (which calls this) BEFORE it calls
-- UI.scrollFrame:SetHeight(scrollH) later in the same function -- reading
-- GetHeight() here would therefore see last render's height (0 on the very
-- first paint), not this one's. The constant sidesteps that ordering
-- hazard entirely; MX.VisibleWindow already clamps `last` to the real unit
-- count, so a short list (scrollH < MAX_SCROLL_H) just gets a slightly
-- larger-than-strictly-needed window, never an under-sized one.
function M.RenderWindow()
    local c = UI.units
    if not c then
        return
    end
    local offset = UI.scrollFrame:GetVerticalScroll() or 0
    local first, last, firstY =
        MX.VisibleWindow(c.heights, LC.MAX_SCROLL_H, offset)
    if UI.windowFirst == first then
        return                    -- same slice, nothing to redraw
    end
    -- A pooled widget whose row is about to be rebound may still own an
    -- open tooltip. GameTooltip is a SINGLETON shared with every other
    -- addon and Blizzard's own UI (SetOwner in ui/widgets.lua's
    -- W.AttachTooltip), so the
    -- owner check (dcPoolOwned, set at widget creation) always applies
    -- first -- a foreign tooltip is never touched here, full stop. Past
    -- that, the actual close/keep decision is MX.ShouldHideTooltip (pure,
    -- offline-tested) -- see its comment for the identity-stamp vs.
    -- sliceMoved reasoning.
    local sliceMoved = (UI.windowSliceFirst ~= first)
    UI.windowSliceFirst = first
    local tipOwner = nil
    if GameTooltip and GameTooltip:IsShown() then
        -- W.dcTipOwner, not GameTooltip's non-existent "GetOwner" method -- see M.RowOnHide.
        local o = W.dcTipOwner
        if o and o.dcPoolOwned and GameTooltip:IsOwned(o) then
            tipOwner = o
        end
    end
    UI.windowFirst = first
    local now = GetTime()
    local y = -firstY
    local headSlot, rowSlot = 0, 0
    for i = first, last do
        local u = c.units[i]
        local kind, slot
        kind, slot, headSlot, rowSlot = MX.NextWindowSlot(u, headSlot, rowSlot)
        if kind == "head" then
            local gh = M.EnsureGroupHead(slot)
            if tipOwner == gh.pill
                and MX.ShouldHideTooltip(gh.pill.dcTipPlayer, nil, sliceMoved) then
                GameTooltip:Hide()
                tipOwner = nil   -- handled -- at most one unit owns it
            end
            gh:ClearAllPoints()
            gh:SetPoint("TOPLEFT", UI.scrollChild, "TOPLEFT", MX.PAD, y)
            gh:SetWidth(c.layout.totalW - MX.PAD * 2)
            M.PaintGroupHead(gh, u.g, u.collapsed)
            gh:Show()
            y = y - MX.GROUP_H
        else
            local rf = M.EnsureRow(slot)
            if tipOwner and M.RowOwnsTooltip(rf, tipOwner) then
                local newName = u.row.player and u.row.player.name
                if MX.ShouldHideTooltip(tipOwner.dcTipPlayer, newName, sliceMoved) then
                    GameTooltip:Hide()
                end
                tipOwner = nil   -- handled -- at most one unit owns it
            end
            rf:ClearAllPoints()
            rf:SetPoint("TOPLEFT", UI.scrollChild, "TOPLEFT", 0, y)
            rf:SetWidth(c.layout.totalW)
            M.PaintRow(rf, u.row, c.layout, c.slots, now)
            if u.zebra then
                rf.zebra:Show()
            else
                rf.zebra:Hide()
            end
            rf:Show()
            y = y - MX.ROW_H
        end
    end
    for i = rowSlot + 1, UI.rowMax do
        UI.rowPool[i]:Hide()
    end
    for i = headSlot + 1, (UI.groupHeadMax or 0) do
        UI.groupHeads[i]:Hide()
    end
end

function M.RenderFooter(vm, layout, slots, footerY, frameW)
    local fr = UI.footerRow
    fr:ClearAllPoints()
    fr:SetPoint("TOPLEFT", UI.main, "TOPLEFT", LC.BAR_X_OFF, footerY)
    fr:SetWidth(frameW - LC.BAR_X_OFF * 2)
    -- label per tab -- afflicted counts on DEBUFFS,
    -- missing counts everywhere else (numbers stay the model's footer)
    W.SetTextG(UI.footLabelFS, MX.FooterLabel(MX.state.tab))
    if UI.footLabelFS.dcX ~= layout.nameW then
        UI.footLabelFS.dcX = layout.nameW
        UI.footLabelFS:ClearAllPoints()
        UI.footLabelFS:SetPoint("RIGHT", fr, "LEFT",
            layout.roleX + MX.ROLE_COL_W - LC.BAR_X_OFF, 0)
    end
    local nSlots = table.getn(slots)
    for i = 1, nSlots do
        local col = layout.cols[i]
        local fs = M.EnsureFooterCount(i)
        local cx = col.x - LC.BAR_X_OFF + col.w / 2
        if fs.dcX ~= cx then
            fs.dcX = cx
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", fr, "LEFT", cx, 0)
        end
        if MX.IsDisplayTab(MX.state.tab) then
            -- average, not a count -- parch, never red (display only).
            -- Hit columns average with one decimal, like their cells.
            local avgTbl = vm.colAvg or vm.resistAvg
            local avg = (avgTbl and avgTbl[col.id]) or 0
            local sd = slots[i]
            if sd and sd.kind == "hit" then
                W.SetTextG(fs, MX.HitText(avg))
            else
                W.SetTextG(fs, tostring(avg))
            end
            W.SetTextColorG(fs, C.parch)
        else
            local entry = vm.footer[col.id]
            local count = entry and entry.count or 0
            W.SetTextG(fs, tostring(count))
            W.SetTextColorG(fs, count > 0 and C.fehlt or C.faint)
        end
        fs:Show()
    end
    for i = nSlots + 1, UI.footerMax do
        UI.footerFS[i]:Hide()
    end
end

function M.Render()
    local st = M.store()
    local vm = MX.vm

    -- columns: cap at MAX_COLS, layout from the VISIBLE set
    local slots, hiddenCount = MX.VisibleSlots(vm.slots)
    local layout = MX.ColumnLayout(slots, MX.NAME_COL_MIN)
    MX.layout = layout
    local frameW = MX.FrameWidth(layout.totalW)
    UI.main:SetWidth(frameW)

    M.RenderChrome(vm, layout, frameW, hiddenCount)

    -- banner (source read from the store -- the one permitted raw read)
    local yTop = LC.CONTENT_TOP
    if MX.ShowBanner(st.source) then
        -- test mode and demo mode share the banner; the text is cached on
        -- the frame so a re-render only calls SetText when it changed
        local btxt = MX.BannerText()
        if UI.banner.dcText ~= btxt then
            UI.banner.dcText = btxt
            UI.banner.text:SetText(btxt)
        end
        UI.banner:ClearAllPoints()
        UI.banner:SetPoint("TOPLEFT", UI.main, "TOPLEFT", LC.BAR_X_OFF, yTop)
        UI.banner:SetWidth(frameW - LC.BAR_X_OFF * 2)
        UI.banner:Show()
        yTop = yTop - LC.BANNER_H
    else
        UI.banner:Hide()
    end

    M.RenderHeader(layout, slots, yTop, frameW)

    local contentH = M.RenderRows(vm, layout, slots) + 4
    if contentH < LC.MIN_SCROLL_H then
        contentH = LC.MIN_SCROLL_H
    end
    local scrollH = contentH
    if scrollH > LC.MAX_SCROLL_H then
        scrollH = LC.MAX_SCROLL_H
    end
    UI.scrollChild:SetWidth(layout.totalW)
    UI.scrollChild:SetHeight(contentH)
    local scrollTop = yTop - LC.HEADER_H - 1
    UI.scrollFrame:ClearAllPoints()
    UI.scrollFrame:SetPoint("TOPLEFT", UI.main, "TOPLEFT", 0, scrollTop)
    UI.scrollFrame:SetWidth(frameW - MX.SCROLLBAR_W - 4)
    UI.scrollFrame:SetHeight(scrollH)
    M.SyncScrollRange()

    -- empty state
    if vm.coverage.total == 0 then
        UI.emptyFS:Show()
        UI.emptyHintFS:Show()
    else
        UI.emptyFS:Hide()
        UI.emptyHintFS:Hide()
    end

    -- footer (counts over ALL readable players -- independent of filter
    -- and collapse; same numbers as /dc report)
    local footerY = scrollTop - scrollH - 1
    M.RenderFooter(vm, layout, slots, footerY, frameW)

    -- total frame height
    UI.main:SetHeight(-(footerY) + LC.FOOTER_H + LC.FOOT_H + 20)
end

-- ------------------------------------------------------------------
-- public API (Toggle / Show / Refresh / SetTab + hooks)
-- ------------------------------------------------------------------

-- Rebuild the vm via DC_Model and re-render. Rendering reads ONLY the vm
-- (plus store.source/scanAt for banner + ticker).
function MX.Refresh()
    if not UI.main or not UI.main:IsShown() then
        return
    end
    MX.SweepWhispers(GetTime())  -- evict stale whisper-cooldown entries
    local st = M.store()
    local d = M.db()
    -- demo mode substitutes its own transient expectation layer here --
    -- the SAME resolver M.RenderHeader uses, so header and cells agree
    local expectTbl = MX.ExpectTable(d)
    -- pass GetTime() as the model's `now` (optional 5th
    -- build param) so UNKNOWN cells with cached data get
    -- cell.last.age, and db.skillBooks as the 6th so the hit columns
    -- resolve the weapon-skill assumption with the user's current book
    -- ticks (a tick therefore lands on THIS refresh, not on the next
    -- scan). Extra args are ignored by a model without them.
    MX.vm = DC_Model.build(st, function(p)
        return DC_Roles.resolve(d, st.source, p)
    end, expectTbl, MX.state.tab, GetTime(), d and d.skillBooks)
    M.Render()
end

function MX.Show()
    M.BuildFrame()
    UI.main:Show()
    MX.Refresh()
    local db = DopingControlDB
    local st = DC.store
    -- demo mode owns the store exactly like test mode does, so the
    -- staleness auto-scan must not fire for it either (DC.SimOwnsStore):
    -- the sim store is stamped at build time and goes stale after 60 s
    if MX.WantScanOnShow(DC.SimOwnsStore(db), st and st.scanAt, GetTime())
        and DC_Scan and DC_Scan.Start then
        DC_Scan.Start()
    end
end

function MX.Toggle()
    if UI.main and UI.main:IsShown() then
        UI.main:Hide()
    else
        MX.Show()
    end
end

function MX.Hide()
    if UI.main then
        UI.main:Hide()
    end
end

function MX.IsShown()
    return UI.main ~= nil and UI.main:IsShown()
end

end -- if CreateFrame
