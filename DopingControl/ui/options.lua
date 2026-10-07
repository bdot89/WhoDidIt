if WDI_DOPING_SKIP then return end -- DopingControl ui/options.lua
-- Standalone options frame,
-- built with proven 1.12 options-window patterns
-- : lazy build on first Toggle, layout cursor, widget factories with
-- getglobal labels, GetChecked() == 1, save-and-chain tooltips (no
-- HookScript on 1.12), OnShow repopulation from DB, ESC via
-- UISpecialFrames, pfUI skin hooks. (No sliders needed here; the
-- SetMinMaxValues-before-SetValue rule therefore has no call site.)
--
-- Contents, top to bottom:
--   title "DopingControl"
--   [x] Test mode (simulated raid)   -> DC.SetTestMode(v)  (core/init.lua)
--   [x] Show minimap button          -> DC_Minimap.Update() (features/minimap.lua)
--   [x] Auto-scan on ready check     -> db.readyCheckScan
--   [x] Auto-open on ready check     -> db.readyCheckOpen
--   divider
--   Editor: a tab selector (Consumables / Class buffs / Equipment /
--     Skill books, O.EditorTabs()) picks ONE of two mutually exclusive
--     content blocks that share the same position and width -- only one
--     is ever shown (ApplyEditorTabVisibility), so the window height is
--     fixed at build time to whichever block is taller and never jumps
--     when the tab changes:
--     - the three expectation tabs (O.ExpectationTabs(), expectations are
--       PER ROLE x CLASS) show a GROUPED grid inside a scroll frame (max
--       height O.GRID_MAX_H): per role one HEADER row (role name, role
--       color; clicking a header cell bulk-toggles that slot for ALL
--       performing classes of the role -- majority flip, O.BulkNewValue)
--       and beneath it one indented row per performing class (class name
--       in class color, own checkboxes on db.expectations[role][class]
--       [slotId]). Row order = O.GridRows: 25 rows (TANK 1+4, MELEE 1+6,
--       RANGED 1+1, CASTER 1+5, HEALER 1+4), identical for all three
--       tabs. Checkbox cells are POOLED (lazy creation, reuse per tab
--       switch, surplus hidden -- up to 25x16 on equipment). A click
--       applies to the matrix IMMEDIATELY. The editor always shows ALL
--       slots of the tab -- dynamic columns apply to the matrix, not here
--       (a fully disabled slot must stay re-enableable). Role header
--       cells have no tri-state on 1.12: all classes checked = checked,
--       none = unchecked, mixed = checked at 0.45 alpha. The
--       "Reset expectations" button (double-click-to-confirm --
--       StaticPopup is 1.12-fiddly: first click arms ("Click again to
--       confirm"), second click within 5 s reseeds every class line from
--       DC.DEFAULT_EXPECT via DC.ResetExpectations; the label reverts
--       automatically when the window lapses) belongs to this block.
--     - the Skill books tab (O.IsSkillBookTab) shows the SAME KIND OF
--       GRID as the expectation tabs, so both read as one table: sticky
--       3-character column headers, one row per scanned player, a
--       checkbox at the crossing. The columns are the FIXED weapon-skill
--       set (O.BOOK_COLUMNS, 15), never the per-player skill list -- the
--       old layout wrapped each player's skills across up to 5 ragged
--       lines with the label next to every box, which made the tab
--       unreadable at raid size. Cell state comes from
--       O.BookCellState: worn = full strength (the common tick),
--       trainable = dimmed, not trainable = no checkbox at all. A player
--       whose class is unknown gets a hint line instead of cells. A tick
--       writes db.skillBooks[player][skill] = true (an untick writes
--       explicit false) and refreshes the matrix at once. Rows come from
--       the store and change with every scan, so the pool is rebuilt on
--       OnShow/Refresh; an empty store shows a hint line instead. Fixed
--       scroll height (O.BOOKS_MAX_H) -- the roster length never resizes
--       the window. The explanation line ("A book is worth about 0.6%
--       hit...") sits at the top of this block.
--   version footer from GetAddOnMetadata
--
-- Cross-module calls (DC.SetTestMode, DC_Minimap,
-- DC_Matrix, DC_Roles.ROLE_CLASSES, DC.ResetExpectations) are
-- existence-guarded so a partially loaded addon never hard-errors here;
-- O.RoleClasses falls back to inverting
-- DC_Roles.CLASS_ROLES when ROLE_CLASSES is absent.
-- Dofile-loadable under pure Lua 5.0 -- all WoW wiring behind CreateFrame;
-- the pure grid helpers at the top are offline-tested.

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Options = DC_Options or {}
local O = DC_Options

-- seconds the "Reset expectations" confirmation stays armed
O.RESET_ARM_WINDOW = 5

-- The expectation grid and the weapon-skill-book list are separate TABS
-- of the same editor now and never show at once (ApplyEditorTabVisibility
-- picks one), so they no longer share a combined height budget -- each
-- gets its own scroll cap. The window height is fixed at BUILD time to
-- the taller of the two tab contents (see BuildOptionsFrame), so
-- switching to the Skill books tab never resizes the window; giving the
-- book list the SAME cap as the grid keeps that taller side unchanged and
-- avoids a large empty gap under the shorter tab.
O.GRID_MAX_H = 240

-- weapon-skill-book section: FIXED scroll height (the roster length must
-- never resize the window), same cap as the grid for the reason above.
O.BOOKS_MAX_H = O.GRID_MAX_H

-- ------------------------------------------------------------------
-- O.BOOK_COLUMNS -- the FIXED column set of the Skill books grid, in
-- display order: one column per weapon skill that exists on this client,
-- grouped one-hand melee / two-hand melee / ranged. Same shape as the
-- equipment slot table (data/enchants.lua): `label` is the 3-character
-- column header, `full` the tooltip word, `skill` the write key into
-- db.skillBooks (and the exact string DC.CLASS_WEAPON_SKILLS uses).
--
-- The column set is FIXED, never derived from the current roster -- the
-- same reason the expectation editor always shows all slots of its tab:
-- columns that appear and disappear with the scan make the grid unreadable
-- and move every tick target. A cell is simply hidden on a row whose class
-- cannot train that skill (O.SkillBookRows' `has`).
--
-- This list is a literal on purpose (no dependency on data/hit.lua's load
-- order); test_options_grid pins it against DC.WEAPON_SKILL_OF_SUBTYPE's
-- value set and against every DC.CLASS_WEAPON_SKILLS entry, so a skill
-- added there can never silently lose its column.
-- ------------------------------------------------------------------
O.BOOK_COLUMNS = {
    { skill = "Axes",              label = "AXE", sub = "1h",   full = "Axes" },
    { skill = "Maces",             label = "MAC", sub = "1h",   full = "Maces" },
    { skill = "Swords",            label = "SWD", sub = "1h",   full = "Swords" },
    { skill = "Daggers",           label = "DAG", sub = "1h",   full = "Daggers" },
    { skill = "Unarmed",           label = "UNA", sub = "fist", full = "Unarmed (fist weapons)" },
    { skill = "Two-Handed Axes",   label = "2HA", sub = "2h",   full = "Two-Handed Axes" },
    { skill = "Two-Handed Maces",  label = "2HM", sub = "2h",   full = "Two-Handed Maces" },
    { skill = "Two-Handed Swords", label = "2HS", sub = "2h",   full = "Two-Handed Swords" },
    { skill = "Polearms",          label = "POL", sub = "2h",   full = "Polearms" },
    { skill = "Staves",            label = "STV", sub = "2h",   full = "Staves" },
    { skill = "Bows",              label = "BOW", sub = "rng",  full = "Bows" },
    { skill = "Crossbows",         label = "XBW", sub = "rng",  full = "Crossbows" },
    { skill = "Guns",              label = "GUN", sub = "rng",  full = "Guns" },
    { skill = "Thrown",            label = "THR", sub = "rng",  full = "Thrown" },
    { skill = "Wands",             label = "WND", sub = "rng",  full = "Wands" },
}

-- ------------------------------------------------------------------
-- Shared grid geometry for BOTH editor grids. The column pitch and the
-- header-tile size are deliberately the MAIN WINDOW's numbers
-- (MX.CELL_W 30 + MX.CELL_GAP 3, MX header tile 26 high with a 9 px label
-- over a 7 px sub) so the options tables read as the same furniture as
-- the matrix instead of as a second, denser style. They are repeated here
-- rather than read from DC_Matrix: ui/matrix.lua may not be loaded when
-- this file is dofile'd offline, and a silent nil would collapse the
-- layout to zero-width columns.
-- ------------------------------------------------------------------
O.CELL_W     = 30   -- = MX.CELL_W
O.CELL_GAP   = 3    -- = MX.CELL_GAP
O.COL_PITCH  = 33   -- CELL_W + CELL_GAP, both grids
O.HEAD_H     = 26   -- header tile height (= MX header tile: HEADER_H - 4)
O.HEAD_ROW_H = 30   -- header bar height (= MX.HEADER_H)

O.GRID_LABEL_W = 74   -- role/class label column (expectation grid)
O.BOOK_NAME_W  = 96   -- player-name column (skill book grid)
O.ROW_H        = 22   -- one grid row's height, both grids

-- consumables (v6 slot model) has the most configurable slots (22 incl.
-- the five school protection columns);
-- equipment follows with 14 (11 armor enchants + neck + 2 rings --
-- trinkets are item tiles and never configurable, see slotsForTab).
-- The widest grid the pools have to serve.
O.MAX_SLOT_COLS = 22

-- x-offset of the 20 px check button inside its O.CELL_W-wide column
O.CELL_INSET = math.floor((O.CELL_W - 20) / 2)

-- ⚠ Lua 5.0 allows a function at most 32 UPVALUES, and BuildOptionsFrame
-- in the WoW section below sits right at that ceiling. Every geometry
-- number therefore lives HERE, on the O table (one upvalue), instead of
-- as its own file-local in that block -- twelve locals cost twelve
-- upvalues and overflowing is a COMPILE error that stops the whole file
-- from loading, i.e. the addon silently loses its options window.

-- content width of either grid: label column + one pitch per column.
function O.GridContentW(nCols)
    return O.GRID_LABEL_W + (nCols or 0) * O.COL_PITCH
end

-- ------------------------------------------------------------------
-- Window width follows the CONTENT of the selected tab, the way the main
-- window follows its own column count -- a window sized once to its widest
-- tab leaves the narrow ones (class buffs: 6 columns) swimming in empty
-- space.
--
-- The floor is not a taste number: the editor's own tab BUTTON ROW has to
-- fit, so it is derived from the button geometry and the tab count. Add a
-- fifth tab and the floor grows by itself.
-- ------------------------------------------------------------------
O.FRAME_PAD_L   = 24
O.FRAME_PAD_R   = 24
O.SCROLLBAR_W   = 22   -- UIPanelScrollFrameTemplate's bar, right of the scroll
O.TAB_BTN_W     = 108
O.TAB_BTN_PITCH = 114

function O.MinFrameW()
    local n = table.getn(O.EditorTabs())
    if n < 1 then
        n = 1
    end
    return O.FRAME_PAD_L + (n - 1) * O.TAB_BTN_PITCH + O.TAB_BTN_W
        + O.FRAME_PAD_R
end

function O.FrameWidthFor(contentW)
    local w = O.FRAME_PAD_L + (contentW or 0) + O.SCROLLBAR_W + O.FRAME_PAD_R
    local min = O.MinFrameW()
    if w < min then
        w = min
    end
    return w
end

-- total content width of the book section (name column + all skill
-- columns); the options frame is sized to fit this (see widestFrameW()).
function O.BooksContentW()
    return O.BOOK_NAME_W + table.getn(O.BOOK_COLUMNS) * O.COL_PITCH
end

-- shown instead of checkboxes for a player whose class could not be
-- determined -- weapon skills are derived from the class
-- (DC.CLASS_WEAPON_SKILLS), so without a class there is nothing to offer.
O.SKILLBOOK_UNREADABLE_HINT = "class unknown - can't tell weapon skills"

-- ==================================================================
-- PURE SECTION -- grid row model (offline-testable)
-- ==================================================================

-- Class token order for role lines (WARRIOR,
-- PALADIN, HUNTER, ROGUE, PRIEST, SHAMAN, MAGE, WARLOCK, DRUID, filtered
-- per role). Used by the ROLE_CLASSES fallback inversion below.
O.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
                  "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- Performing classes of a role, ordered. Prefers DC_Roles.ROLE_CLASSES
-- (core/roles.lua); when it is absent,
-- derives the same lists by inverting DC_Roles.CLASS_ROLES in
-- O.CLASS_ORDER. Resolved at CALL time, never cached across files.
function O.RoleClasses(role)
    if DC_Roles and DC_Roles.ROLE_CLASSES and DC_Roles.ROLE_CLASSES[role] then
        return DC_Roles.ROLE_CLASSES[role]
    end
    local out = {}
    local cr = DC_Roles and DC_Roles.CLASS_ROLES
    if not cr then
        return out
    end
    for i = 1, table.getn(O.CLASS_ORDER) do
        local class = O.CLASS_ORDER[i]
        local list = cr[class]
        if list then
            for j = 1, table.getn(list) do
                if list[j] == role then
                    table.insert(out, class)
                end
            end
        end
    end
    return out
end

-- Ordered grid row descriptors for the expectation editor:
-- { kind = "role"|"class", role = <token>, class = <token|nil> }.
-- Identical for all three expectation tabs (the tab only changes the
-- COLUMNS); the parameter is kept for signature symmetry. 25 rows total:
-- TANK 1+4, MELEE 1+6, RANGED 1+1, CASTER 1+5, HEALER 1+4.
function O.GridRows(tab)
    local rows = {}
    local nR = table.getn(DC.ROLES)
    for i = 1, nR do
        local role = DC.ROLES[i]
        table.insert(rows, { kind = "role", role = role })
        local classes = O.RoleClasses(role)
        for j = 1, table.getn(classes) do
            table.insert(rows, { kind = "class", role = role,
                                 class = classes[j] })
        end
    end
    return rows
end

-- Bulk toggle target for a role header cell click: the new value is the
-- flip of the current majority. Strict majority checked -> uncheck all;
-- majority unchecked OR tie -> check all.
function O.BulkNewValue(checkedCount, total)
    return not (checkedCount * 2 > total)
end

-- ------------------------------------------------------------------
-- Weapon skill books (+3). A quest book raises a weapon skill by 3 --
-- worth roughly 0.6% hit -- and there is NO way to read it off another
-- player (no skill channel exists for foreign units). So it is entered
-- by hand here, per player and per weapon skill, and the scan folds it
-- into that player's assumed weapon skill on the next read.
--
-- A book applies no matter what is currently in the player's hand (a
-- weapon swap or a spare off-hand does not un-learn a skill), so every
-- skill the player's CLASS can plausibly train is offered -- not just
-- whatever happens to be equipped at scan time. The currently WORN
-- skills are still called out (sorted first, rendered brighter): that is
-- the common case a raid leader wants to tick without hunting through the
-- full class list.
-- ------------------------------------------------------------------

-- Rows for the book section: { name, class, skills = { <skill>, ... },
-- wornCount = <n>, has = { [skill] = true }, worn = { [skill] = true },
-- unreadable = <bool> }.
--
-- `has`/`worn` are the render keys of the GRID (one fixed column per
-- weapon skill, O.BOOK_COLUMNS): `has` decides whether the row shows a
-- checkbox in that column at all, `worn` whether it renders at full
-- strength. They carry exactly the same information as the ordered
-- `skills` array below -- which the grid no longer needs for placement,
-- but which stays because it is the readable form of "what is this player
-- offered", and because worn-first order is what a per-row tooltip and any
-- future list rendering would use.
-- `skills` is the UNION of (a) every weapon skill DC.CLASS_WEAPON_SKILLS
-- lists for the player's class and (b) whatever the scan currently sees
-- equipped (subtype -> skill via DC.WEAPON_SKILL_OF_SUBTYPE,
-- data/hit.lua). Order: the CURRENTLY WORN skills first (`skills`
-- 1..wornCount, deduplicated -- both hands on the same skill line count
-- once), then the rest of the class list in ITS declared order. A worn
-- skill outside the class list (server-specific exception) still rides
-- along in the worn block -- see the header of DC.CLASS_WEAPON_SKILLS.
-- A player whose CLASS is unknown gets `unreadable = true` and an empty
-- `skills` -- still a row (the roster line is never silently dropped),
-- rendered as a hint instead of checkboxes (O.SKILLBOOK_UNREADABLE_HINT).
-- Players sorted by name (deterministic across scans, like every other
-- list in this addon).
function O.SkillBookRows(store)
    local rows = {}
    local players = (store and store.players) or {}
    local subMap = DC.WEAPON_SKILL_OF_SUBTYPE or {}
    local classSkills = DC.CLASS_WEAPON_SKILLS or {}
    for i = 1, table.getn(players) do
        local p = players[i]
        local class = p.class
        if type(class) == "string" and class ~= "" then
            local seen, skills, worn = {}, {}, {}
            local h = p.hit
            if type(h) == "table" then
                local subs = { h.mainSub, h.offSub }
                for s = 1, 2 do
                    local sub = subs[s]
                    local skill = (type(sub) == "string") and subMap[sub]
                        or nil
                    if skill and not seen[skill] then
                        seen[skill] = true
                        worn[skill] = true
                        table.insert(skills, skill)
                    end
                end
            end
            local wornCount = table.getn(skills)
            local cls = classSkills[class] or {}
            for c = 1, table.getn(cls) do
                local skill = cls[c]
                if not seen[skill] then
                    seen[skill] = true
                    table.insert(skills, skill)
                end
            end
            table.insert(rows, { name = p.name, class = class,
                                 skills = skills, wornCount = wornCount,
                                 has = seen, worn = worn })
        else
            table.insert(rows, { name = p.name, class = class,
                                 skills = {}, wornCount = 0,
                                 has = {}, worn = {},
                                 unreadable = true })
        end
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
end

-- Cell state for (row, column) in the Skill books grid:
--   "worn"   -- the player is holding a weapon on this skill line right
--              now: the common tick, rendered at full strength
--   "train"  -- the player's class can train it but nothing on that line
--              is equipped: still tickable, rendered dimmed
--   nil      -- this class cannot train it (and it is not worn): no
--              checkbox at all, so the eye only ever meets cells that can
--              actually carry a book
-- A row with an unknown class has no cells at all (hint line instead).
function O.BookCellState(row, skill)
    if not row or row.unreadable or type(skill) ~= "string" then
        return nil
    end
    if row.worn and row.worn[skill] then
        return "worn"
    end
    if row.has and row.has[skill] then
        return "train"
    end
    return nil
end

-- Empty-state line for the book section, nil once rows exist. Rows now
-- need only a known CLASS (see O.SkillBookRows), so this only fires for a
-- genuinely empty roster -- no scan has happened yet.
function O.SkillBookHint(rows)
    if rows and table.getn(rows) > 0 then
        return nil
    end
    return "No scanned players yet - scan the raid first."
end

-- Saved shape: db.skillBooks[playerName][skillName] = true|false.
function O.SkillBookGet(db, name, skill)
    local books = db and db.skillBooks
    local line = books and books[name]
    return (line and line[skill]) and true or false
end

-- Unticking writes an explicit FALSE, never nil -- a bare nil would let a
-- later defaults top-up re-create the entry and silently re-tick a book
-- the user deliberately removed (same rule as the expectation grid).
function O.SkillBookSet(db, name, skill, value)
    if not db or type(name) ~= "string" or type(skill) ~= "string" then
        return
    end
    if db.skillBooks == nil then
        db.skillBooks = {}
    end
    if type(db.skillBooks[name]) ~= "table" then
        db.skillBooks[name] = {}
    end
    db.skillBooks[name][skill] = value and true or false
end

-- ------------------------------------------------------------------
-- Tabs the expectation editor offers.
-- A tab that never CONSULTS expectations must never appear here, or the
-- grid would let the user tick boxes that change nothing: DEBUFFS (every
-- column applies to every player), RESIST and HIT (display-only tabs --
-- their columns are always all active, see core/model.lua). The list is
-- derived from DC.TABS by exclusion rather than by index, so a new tab
-- shifting positions cannot silently drag a display tab into the editor.
-- ------------------------------------------------------------------
O.NO_EXPECTATION_TABS = {
    DEBUFFS = true,
    RESIST  = true,
    HIT     = true,
}

function O.ExpectationTabs()
    local out = {}
    local src = (DC and DC.TABS)
        or { "CONSUMABLES", "CLASSBUFFS", "EQUIPMENT" }
    for i = 1, table.getn(src) do
        if not O.NO_EXPECTATION_TABS[src[i]] then
            table.insert(out, src[i])
        end
    end
    return out
end

-- ------------------------------------------------------------------
-- The editor's FULL tab order: the three expectation tabs plus the
-- weapon-skill-book tab last. A SEPARATE list from O.ExpectationTabs() on
-- purpose -- SKILLBOOKS has no expectation grid (O.IsSkillBookTab), so any
-- code that walks "tabs with a grid" must keep using O.ExpectationTabs()
-- and never this one.
-- ------------------------------------------------------------------
O.SKILLBOOK_TAB = "SKILLBOOKS"
O.SKILLBOOK_TAB_LABEL = "Skill books"

function O.EditorTabs()
    local out = O.ExpectationTabs()
    table.insert(out, O.SKILLBOOK_TAB)
    return out
end

-- True for the one editor tab that swaps the expectation grid for the
-- weapon-skill-book list (see the WoW section: RefreshEditor /
-- ApplyEditorTabVisibility).
function O.IsSkillBookTab(tab)
    return tab == O.SKILLBOOK_TAB
end

-- Button label for an editor tab: DC.TAB_LABEL for the three real tabs,
-- O.SKILLBOOK_TAB_LABEL for the pseudo-tab that only exists in this editor.
function O.EditorTabLabel(tab)
    if O.IsSkillBookTab(tab) then
        return O.SKILLBOOK_TAB_LABEL
    end
    return (DC.TAB_LABEL and DC.TAB_LABEL[tab]) or tab
end

-- Class token -> display word ("WARRIOR" -> "Warrior") for class row labels.
function O.ClassTitle(class)
    if type(class) ~= "string" or class == "" then
        return "?"
    end
    return string.upper(string.sub(class, 1, 1))
        .. string.lower(string.sub(class, 2))
end

-- Label of the demo-mode button. Demo mode is TRANSIENT (core/demo.lua:
-- never SavedVariables), so it gets a self-relabeling button rather than a
-- checkbox -- the checkbox row above is bound to db fields, and a checkbox
-- whose state dies on reload would read like a broken setting.
function O.DemoButtonLabel()
    if DC.demoMode then
        return "Demo mode: ON (click to stop)"
    end
    return "Demo mode: OFF (click to start)"
end

-- ==================================================================
-- WOW SECTION -- frame, widgets, wiring
-- ==================================================================
if CreateFrame then

    local frame = nil            -- DopingControlOptionsFrame (lazy)
    local checkboxes = {}        -- top checkboxes, for OnShow repopulate
    local expTab = "CONSUMABLES" -- editor tab (not persisted)

    -- ⚠ Geometry deliberately has NO file-locals here (see the upvalue
    -- note at O.MAX_SLOT_COLS): everything is read off O, which every
    -- function in this block already captures as a single upvalue.
    --   O.GRID_LABEL_W  label column          O.COL_PITCH  column pitch
    --   O.BOOK_NAME_W   player-name column    O.ROW_H      row pitch
    --   O.CELL_INSET    check button inset    O.MAX_SLOT_COLS widest grid
    -- The two grids differ in column count (22 consumable slots vs. 15
    -- weapon skills); the frame is BUILT at the wider of the two and
    -- narrowed per tab by ApplyEditorWidth, so no widget is ever created
    -- against a width it later has to grow past.
    local function gridWidest()
        return O.GridContentW(O.MAX_SLOT_COLS)
    end
    local function widestFrameW()
        local c = gridWidest()
        if O.BooksContentW() > c then
            c = O.BooksContentW()
        end
        return O.FrameWidthFor(c)
    end

    -- grid pools (lazy creation, never destroyed, surplus hidden)
    local gridChild = nil        -- scroll child, parent of labels + cells
    local gridRowMax = 0         -- highest row index ever created
    local gridColMax = {}        -- [r] = highest col index created for row r
    local gridZebra = {}         -- [r] = alternating-row wash texture
    local eqHintFS = nil         -- equipment-only dim note (RefreshGrid sets text/visibility)
    local dividerTex = nil       -- head divider, width follows the frame
    local RefreshGrid            -- forward declaration (click handlers call it)

    -- weapon-skill-book section: same pooling pattern as the expectation
    -- grid, and now the same geometry -- the pool addresses PLAYER ROWS x
    -- the fixed O.BOOK_COLUMNS. Unlike the expectation grid the ROW
    -- CONTENT comes from the STORE and changes with every scan, so the
    -- pool is refilled on OnShow/Refresh (the row COUNT is what varies,
    -- never the columns).
    local booksChild = nil       -- scroll child, parent of name labels + cells
    local booksRowMax = 0
    local booksColMax = {}       -- [r] = highest col index created for row r
    local booksZebra = {}        -- [r] = alternating-row wash texture
    local booksHintFS = nil      -- empty-state line (O.SkillBookHint)
    local RefreshBooks           -- forward declaration

    -- Full editor tab order -- resolved by the pure O.EditorTabs() above
    -- (the three expectation tabs, DEBUFFS/RESIST/HIT excluded there,
    -- plus SKILLBOOKS last).
    local EDITOR_TABS = O.EditorTabs()

    local function db()
        return DopingControlDB
    end

    local function slotsForTab(tab)
        if tab == O.SKILLBOOK_TAB then
            -- no expectation grid on this tab (see O.IsSkillBookTab); the
            -- caller hides the grid block entirely, this is defensive
            return {}
        elseif tab == "CLASSBUFFS" then
            return DC.SLOTS_CLASSBUFFS or {}
        elseif tab == "EQUIPMENT" then
            -- only kind=="ench" slots are configurable here (15: the 11
            -- armor slots + neck/rings/waist, which are enchantable on
            -- this server -- data/enchants.lua). T1/T2 (trinket item tiles)
            -- have no enchant question to ask and never appear: the
            -- matrix always shows them (item present/absent decides,
            -- expectations are never consulted for tiles).
            local all = DC.SLOTS_EQUIPMENT or {}
            local out = {}
            for i = 1, table.getn(all) do
                if all[i].kind == "ench" then
                    table.insert(out, all[i])
                end
            end
            return out
        end
        return DC.SLOTS_CONSUMABLES or {}
    end

    -- expectations table (shape: [role][class][slotId] = true|nil),
    -- created on demand (config.EnsureDefaults normally materialized +
    -- migrated this at ADDON_LOADED; defensive for odd load orders)
    local function expectations()
        local d = db()
        if not d.expectations then
            local t = {}
            for i = 1, table.getn(DC.ROLES) do
                local role = DC.ROLES[i]
                t[role] = {}
                local classes = O.RoleClasses(role)
                local def = (DC.DEFAULT_EXPECT and DC.DEFAULT_EXPECT[role])
                    or {}
                for j = 1, table.getn(classes) do
                    local line = {}
                    for k, v in pairs(def) do
                        if v then
                            line[k] = true
                        end
                    end
                    t[role][classes[j]] = line
                end
            end
            d.expectations = t
        end
        return d.expectations
    end

    -- Effective expectation line for (role, class): the explicit class
    -- line when present, else the DC.DEFAULT_EXPECT role line (rule-5
    -- runtime fallback -- same rule the model applies). Old-shape saved
    -- tables (booleans directly under [role]) are migrated by
    -- config.EnsureDefaults; here they simply fall back to the default.
    local function effLine(exp, role, class)
        local r = exp[role]
        if r and type(r[class]) == "table" then
            return r[class]
        end
        return (DC.DEFAULT_EXPECT and DC.DEFAULT_EXPECT[role]) or {}
    end

    -- Materialize the class line before the FIRST write: copy the
    -- effective line, so toggling one slot never silently drops the
    -- fallback values of the other slots (the model treats a present
    -- class line as authoritative).
    local function materializeLine(exp, role, class)
        exp[role] = exp[role] or {}
        if type(exp[role][class]) ~= "table" then
            local copy = {}
            local src = effLine(exp, role, class)
            for k, v in pairs(src) do
                if v then
                    copy[k] = true
                end
            end
            exp[role][class] = copy
        end
        return exp[role][class]
    end

    local function refreshMatrix()
        if DC_Matrix and DC_Matrix.Refresh then
            DC_Matrix.Refresh()
        end
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

    -- ----------------------------------------------------------------
    -- widget helpers
    -- ----------------------------------------------------------------
    local function ApplyFont(fs, size)
        if pfUI and pfUI.font_default and pfUI_config and pfUI_config.global
           and pfUI_config.global.font_size then
            fs:SetFont(pfUI.font_default, pfUI_config.global.font_size)
        elseif size then
            fs:SetFont("Fonts\\FRIZQT__.TTF", size)
        end
    end

    -- save-and-chain tooltip (no HookScript on 1.12)
    local function AddTooltip(widget, text)
        local oldEnter = widget:GetScript("OnEnter")
        local oldLeave = widget:GetScript("OnLeave")
        widget.dcTooltip = text
        widget:SetScript("OnEnter", function()
            if oldEnter then oldEnter() end
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(this.dcTooltip, 1, 1, 1, 1, 1)
            GameTooltip:Show()
        end)
        widget:SetScript("OnLeave", function()
            if oldLeave then oldLeave() end
            GameTooltip:Hide()
        end)
    end

    local checkCounter = 0
    local function CreateCheckbox(parent, label, getter, setter)
        checkCounter = checkCounter + 1
        local name = "DopingControlOptCheck" .. checkCounter
        local cb = CreateFrame("CheckButton", name, parent,
            "UICheckButtonTemplate")
        cb:SetWidth(24)
        cb:SetHeight(24)
        local text = getglobal(name .. "Text")
        text:SetText(label)
        ApplyFont(text, 11)
        cb.dcGet = getter
        cb.dcSet = setter
        cb:SetScript("OnClick", function()
            this.dcSet(this:GetChecked() == 1)  -- GetChecked returns 1|nil
        end)
        if pfUI and pfUI.api and pfUI.api.SkinCheckbox then
            pfUI.api.SkinCheckbox(cb)
        end
        table.insert(checkboxes, cb)
        return cb
    end

    local function CreateButton(parent, name, label, width, onClick)
        local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
        b:SetWidth(width or 140)
        b:SetHeight(22)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        if pfUI and pfUI.api and pfUI.api.SkinButton then
            pfUI.api.SkinButton(b)
        end
        return b
    end

    -- ----------------------------------------------------------------
    -- column-header furniture, deliberately identical to the MAIN
    -- window's header row (ui/matrix.lua: header bar with theadBg/goldSoft,
    -- one panel2/line tile per column, a 9 px label over a 7 px sub-line).
    -- The two windows are meant to read as one tool -- bare grey text over
    -- the grid did not.
    --
    -- These use their OWN font helper: the file-local ApplyFont takes
    -- pfUI's GLOBAL font size when pfUI is loaded, which is right for
    -- flowing option text but would blow a 7 px sub-line out of a 26 px
    -- tile. ApplyFontFixed keeps our pixel size and only borrows pfUI's
    -- font family -- exactly what DC_Widgets.ApplyFont does for the matrix.
    -- ----------------------------------------------------------------
    local function ApplyFontFixed(fs, size)
        if DC_Widgets and DC_Widgets.ApplyFont then
            DC_Widgets.ApplyFont(fs, size)
        elseif pfUI and pfUI.font_default then
            fs:SetFont(pfUI.font_default, size)
        else
            fs:SetFont("Fonts\\FRIZQT__.TTF", size)
        end
    end

    local function colorOf(key, r, g, b)
        local c = DC.COLORS and DC.COLORS[key]
        if c then
            return c
        end
        return { r = r, g = g, b = b }
    end

    local function solidBackdrop()
        if DC_Widgets and DC_Widgets.SOLID_BACKDROP then
            return DC_Widgets.SOLID_BACKDROP
        end
        return {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        }
    end

    -- the dark bar the tiles sit in; `leadLabel` is the main window's
    -- "PLAYER" device -- it names the label column of the grid below.
    local function CreateHeaderBar(parent, name, px, py, w, leadLabel)
        local bar = CreateFrame("Frame", name, parent)
        bar:SetWidth(w)
        bar:SetHeight(O.HEAD_ROW_H)
        bar:SetPoint("TOPLEFT", parent, "TOPLEFT", px, py)
        bar:SetBackdrop(solidBackdrop())
        local bg = colorOf("theadBg", 0.078, 0.094, 0.129)
        local br = colorOf("goldSoft", 0.329, 0.275, 0.165)
        bar:SetBackdropColor(bg.r, bg.g, bg.b, 1)
        bar:SetBackdropBorderColor(br.r, br.g, br.b, 1)
        local lead = bar:CreateFontString(name .. "Lead", "OVERLAY")
        ApplyFontFixed(lead, 8)
        local fc = colorOf("faint", 0.357, 0.384, 0.439)
        lead:SetTextColor(fc.r, fc.g, fc.b)
        lead:SetPoint("LEFT", bar, "LEFT", 6, 0)
        lead:SetText(leadLabel or "")
        return bar
    end

    -- one column tile. `left` is the x of the column INSIDE the bar (the
    -- tile spans the full O.CELL_W, the check button below is centered in
    -- it by O.CELL_INSET), so tile and cells cannot drift apart.
    local function CreateHeaderTile(bar, name, left)
        local t = CreateFrame("Frame", name, bar)
        t:SetWidth(O.CELL_W)
        t:SetHeight(O.HEAD_H)
        t:SetPoint("LEFT", bar, "LEFT", left, 0)
        t:SetBackdrop(solidBackdrop())
        local bg = colorOf("panel2", 0.09, 0.106, 0.137)
        local br = colorOf("line", 0.149, 0.173, 0.216)
        t:SetBackdropColor(bg.r, bg.g, bg.b, 1)
        t:SetBackdropBorderColor(br.r, br.g, br.b, 1)
        t:EnableMouse(true)
        local lbl = t:CreateFontString(name .. "Label", "OVERLAY")
        ApplyFontFixed(lbl, 9)
        local pc = colorOf("parch", 0.839, 0.804, 0.722)
        lbl:SetTextColor(pc.r, pc.g, pc.b)
        lbl:SetPoint("TOP", t, "TOP", 0, -3)
        local sub = t:CreateFontString(name .. "Sub", "OVERLAY")
        ApplyFontFixed(sub, 7)
        local fc = colorOf("faint", 0.357, 0.384, 0.439)
        sub:SetTextColor(fc.r, fc.g, fc.b)
        sub:SetPoint("BOTTOM", t, "BOTTOM", 0, 3)
        t.dcLabelFS = lbl
        t.dcSubFS = sub
        return t
    end

    -- ----------------------------------------------------------------
    -- grid cell handlers (defined once, shared by every pooled cell)
    -- ----------------------------------------------------------------
    local function GridCellOnClick()
        local slotId = this.dcSlot
        if not slotId or not this.dcRole then
            return
        end
        local exp = expectations()
        if this.dcKind == "role" then
            -- header-row cell: bulk-toggle the slot for ALL performing
            -- classes of the role -- majority flip
            local role = this.dcRole
            local classes = O.RoleClasses(role)
            local n = table.getn(classes)
            local checked = 0
            for i = 1, n do
                if effLine(exp, role, classes[i])[slotId] then
                    checked = checked + 1
                end
            end
            local newVal = O.BulkNewValue(checked, n)
            for i = 1, n do
                local line = materializeLine(exp, role, classes[i])
                if newVal then
                    line[slotId] = true
                else
                    -- explicit false, NOT nil: a bare nil would let a
                    -- later EnsureExpectations top-up (core/config.lua)
                    -- silently re-check a slot the user deliberately
                    -- unchecked (A1 migration fix)
                    line[slotId] = false
                end
            end
        else
            local line = materializeLine(exp, this.dcRole, this.dcClass)
            if this:GetChecked() == 1 then
                line[slotId] = true
            else
                line[slotId] = false     -- explicit deselect, see above
            end
        end
        RefreshGrid()    -- resync class rows + header aggregate cells
        refreshMatrix()  -- applies immediately
    end

    local function GridCellOnEnter()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        if this.dcKind == "role" then
            GameTooltip:SetText((DC.ROLE_LABEL[this.dcRole] or this.dcRole
                or "?") .. " (all classes) - " .. (this.dcLabel or "?"),
                1, 1, 1)
            GameTooltip:AddLine("Click toggles this slot for every class of"
                .. " the role (majority flip).", 0.8, 0.8, 0.8, 1)
        else
            GameTooltip:SetText((DC.ROLE_LABEL[this.dcRole] or this.dcRole
                or "?") .. " " .. O.ClassTitle(this.dcClass) .. " - "
                .. (this.dcLabel or "?"), 1, 1, 1)
            GameTooltip:AddLine("Click to toggle whether this class is"
                .. " expected to have it in this role.", 0.8, 0.8, 0.8, 1)
        end
        GameTooltip:Show()
    end

    local function GridCellOnLeave()
        GameTooltip:Hide()
    end

    -- ----------------------------------------------------------------
    -- weapon-skill-book cell handlers (shared by every pooled cell)
    -- ----------------------------------------------------------------
    local function BookCellOnClick()
        if not this.dcName or not this.dcSkill then
            return
        end
        O.SkillBookSet(db(), this.dcName, this.dcSkill,
            this:GetChecked() == 1)
        -- No rescan needed: the assumed weapon skill is resolved when the
        -- matrix builds its view-model (it reads db.skillBooks), so the
        -- new cap is on screen with this refresh.
        refreshMatrix()
    end

    local function BookCellOnEnter()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText((this.dcName or "?") .. " - "
            .. (this.dcSkill or "?"), 1, 1, 1)
        -- the column header is 3 characters; without this line a dimmed
        -- cell and a bright one would be indistinguishable on hover
        if this.dcWorn then
            GameTooltip:AddLine("Currently equipped on this skill line.",
                0.6, 0.8, 0.6, 1)
        else
            GameTooltip:AddLine("Trainable by this class, nothing equipped"
                .. " on it right now.", 0.7, 0.7, 0.7, 1)
        end
        GameTooltip:AddLine("Weapon skill book: +3 skill, about 0.6% hit."
            .. " Nothing on this client can read it off another player, so"
            .. " tick it by hand.", 0.8, 0.8, 0.8, 1)
        GameTooltip:Show()
    end

    -- ----------------------------------------------------------------
    -- grid pools (lazy factories; positions are index-fixed at creation
    -- because O.GridRows is identical across the three expectation tabs)
    -- ----------------------------------------------------------------
    -- alternating-row wash, one pooled texture per row of a grid. Same
    -- device and same strength as the matrix rows (DC.ZEBRA_ALPHA) -- the
    -- point is that a row can be followed across 14-15 columns by eye.
    -- Textures live on the SCROLL CHILD at BACKGROUND layer; the check
    -- buttons are child FRAMES and therefore always draw above them.
    local function EnsureZebra(store, parent, r, w, rh)
        local t = store[r]
        if t then
            return t
        end
        t = parent:CreateTexture(nil, "BACKGROUND")
        local zc = (DC.COLORS and DC.COLORS.zebra) or { r = 1, g = 1, b = 1 }
        t:SetTexture(zc.r, zc.g, zc.b)
        t:SetAlpha(DC.ZEBRA_ALPHA or 0.035)
        t:SetWidth(w)
        t:SetHeight(rh)
        t:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((r - 1) * rh))
        store[r] = t
        return t
    end

    -- `on` is the CALLER's decision, not a parity of r: the expectation
    -- grid stripes every second CLASS row while the role headers between
    -- them stay unstriped (they carry their own emphasis), so the two
    -- indices are not the same number.
    local function PaintZebra(store, parent, r, w, rh, on)
        local t = EnsureZebra(store, parent, r, w, rh)
        -- width is re-applied every time, not just at creation: the grid
        -- narrows with the tab (ApplyEditorWidth) and a stripe left at the
        -- widest tab's width would run out under the scroll frame's edge
        t:SetWidth(w)
        if on then
            t:Show()
        else
            t:Hide()
        end
    end

    local function EnsureRowLabel(r)
        local name = "DopingControlOptRowLabel" .. r
        local fs = getglobal(name)
        if fs then
            return fs
        end
        fs = gridChild:CreateFontString(name, "ARTWORK",
            "GameFontNormalSmall")
        fs:SetJustifyH("LEFT")
        if r > gridRowMax then
            gridRowMax = r
        end
        if gridColMax[r] == nil then
            gridColMax[r] = 0
        end
        return fs
    end

    local function EnsureGridCell(r, c)
        local name = "DopingControlOptExpR" .. r .. "C" .. c
        local cb = getglobal(name)
        if cb then
            return cb
        end
        cb = CreateFrame("CheckButton", name, gridChild,
            "UICheckButtonTemplate")
        cb:SetWidth(20)
        cb:SetHeight(20)
        cb:SetPoint("TOPLEFT", gridChild, "TOPLEFT",
            O.GRID_LABEL_W + (c - 1) * O.COL_PITCH + O.CELL_INSET, -((r - 1) * O.ROW_H) - 1)
        getglobal(name .. "Text"):SetText("")
        cb:SetScript("OnClick", GridCellOnClick)
        cb:SetScript("OnEnter", GridCellOnEnter)
        cb:SetScript("OnLeave", GridCellOnLeave)
        -- Deliberately NOT pfUI-skinned (unlike the top checkboxes):
        -- SkinCheckbox puts its dark box on an own frame, and inside the
        -- scroll child its frame level clamps ABOVE the check button --
        -- the check mark rendered BEHIND the box (observed
        -- in-game). The stock template draws its check on top by
        -- construction; a slight style mix beats invisible state.
        if r > gridRowMax then
            gridRowMax = r
        end
        if gridColMax[r] == nil or c > gridColMax[r] then
            gridColMax[r] = c
        end
        return cb
    end

    -- ----------------------------------------------------------------
    -- weapon-skill-book pools (lazy; ROW and COLUMN positions are
    -- index-fixed like the expectation grid -- only which cells are SHOWN
    -- changes with the roster, see RefreshBooks)
    -- ----------------------------------------------------------------
    local function EnsureBookLabel(r)
        local name = "DopingControlOptBookName" .. r
        local fs = getglobal(name)
        if fs then
            return fs
        end
        fs = booksChild:CreateFontString(name, "ARTWORK",
            "GameFontNormalSmall")
        ApplyFont(fs, 10)
        fs:SetJustifyH("LEFT")
        fs:SetWidth(O.BOOK_NAME_W - 4)
        fs:SetPoint("TOPLEFT", booksChild, "TOPLEFT", 0,
            -((r - 1) * O.ROW_H) - 5)
        if r > booksRowMax then
            booksRowMax = r
        end
        if booksColMax[r] == nil then
            booksColMax[r] = 0
        end
        return fs
    end

    -- one pooled hint line per row, shown instead of the checkboxes for a
    -- player whose class is unknown (O.SKILLBOOK_UNREADABLE_HINT)
    local function EnsureBookRowHint(r)
        local name = "DopingControlOptBookRowHint" .. r
        local fs = getglobal(name)
        if fs then
            return fs
        end
        fs = booksChild:CreateFontString(name, "ARTWORK",
            "GameFontNormalSmall")
        ApplyFont(fs, 9)
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(0.36, 0.38, 0.44)
        fs:SetPoint("TOPLEFT", booksChild, "TOPLEFT", O.BOOK_NAME_W,
            -((r - 1) * O.ROW_H) - 5)
        return fs
    end

    local function EnsureBookCell(r, c)
        local name = "DopingControlOptBookR" .. r .. "C" .. c
        local cb = getglobal(name)
        if cb then
            return cb
        end
        cb = CreateFrame("CheckButton", name, booksChild,
            "UICheckButtonTemplate")
        cb:SetWidth(20)
        cb:SetHeight(20)
        cb:SetPoint("TOPLEFT", booksChild, "TOPLEFT",
            O.BOOK_NAME_W + (c - 1) * O.COL_PITCH + O.CELL_INSET,
            -((r - 1) * O.ROW_H) - 1)
        -- no per-cell label any more: the column header carries the skill
        -- name (that IS the readability fix -- see O.BOOK_COLUMNS)
        getglobal(name .. "Text"):SetText("")
        cb:SetScript("OnClick", BookCellOnClick)
        cb:SetScript("OnEnter", BookCellOnEnter)
        cb:SetScript("OnLeave", GridCellOnLeave)
        -- deliberately NOT pfUI-skinned, for the same reason as the
        -- expectation cells above (the skin's box clamps above the check
        -- mark inside a scroll child)
        if r > booksRowMax then
            booksRowMax = r
        end
        if booksColMax[r] == nil or c > booksColMax[r] then
            booksColMax[r] = c
        end
        return cb
    end

    -- ----------------------------------------------------------------
    -- weapon-skill-book refresh: one ROW per scanned player from the
    -- CURRENT store (O.SkillBookRows), one cell per FIXED column
    -- (O.BOOK_COLUMNS), check states from db.skillBooks. A cell exists
    -- only where the player could own a book (O.BookCellState); worn
    -- skills -- the common tick -- render at full strength, the rest of
    -- the class list dimmed. A row whose class is unknown shows a hint
    -- instead of cells.
    -- ----------------------------------------------------------------
    RefreshBooks = function()
        if not booksChild then
            return
        end
        local rows = O.SkillBookRows(DC.store)
        local nRows = table.getn(rows)
        local d = db()
        for r = 1, nRows do
            local rd = rows[r]
            -- every row here IS a data row (one player), so plain parity
            PaintZebra(booksZebra, booksChild, r, O.BooksContentW(), O.ROW_H,
                math.mod(r, 2) == 0)
            local lbl = EnsureBookLabel(r)
            local cc = DC.COLORS and DC.COLORS["class" .. (rd.class or "")]
            if cc then
                lbl:SetTextColor(cc.r, cc.g, cc.b)
            else
                lbl:SetTextColor(0.79, 0.8, 0.83)
            end
            lbl:SetText(rd.name or "")
            lbl:Show()
            local rowHint = EnsureBookRowHint(r)
            if rd.unreadable then
                rowHint:SetText(O.SKILLBOOK_UNREADABLE_HINT)
                rowHint:Show()
            else
                rowHint:Hide()
            end
            for c = 1, table.getn(O.BOOK_COLUMNS) do
                local skill = O.BOOK_COLUMNS[c].skill
                local state = O.BookCellState(rd, skill)
                if state then
                    local cb = EnsureBookCell(r, c)
                    cb.dcName = rd.name
                    cb.dcSkill = skill
                    cb.dcWorn = (state == "worn")
                    -- Every offered cell renders at FULL strength: a
                    -- half-transparent CHECKED box reads as broken, not
                    -- as a hint. Which weapon is in hand is a scan
                    -- detail, not a property of the book, so it belongs
                    -- in the tooltip (BookCellOnEnter) and nowhere else. Which
                    -- weapon is in hand is a scan detail, not a property
                    -- of the book, so it belongs in the tooltip
                    -- (BookCellOnEnter) and nowhere else.
                    cb:SetAlpha(1)
                    cb:SetChecked(O.SkillBookGet(d, rd.name, skill)
                        and 1 or nil)
                    cb:Show()
                else
                    local cb = getglobal("DopingControlOptBookR" .. r
                        .. "C" .. c)
                    if cb then
                        cb:Hide()
                    end
                end
            end
        end
        -- surplus pooled rows (the roster shrinks between scans)
        for r = nRows + 1, booksRowMax do
            local lbl = getglobal("DopingControlOptBookName" .. r)
            if lbl then
                lbl:Hide()
            end
            if booksZebra[r] then
                booksZebra[r]:Hide()
            end
            local rowHint = getglobal("DopingControlOptBookRowHint" .. r)
            if rowHint then
                rowHint:Hide()
            end
            for c = 1, (booksColMax[r] or 0) do
                local cb = getglobal("DopingControlOptBookR" .. r
                    .. "C" .. c)
                if cb then
                    cb:Hide()
                end
            end
        end
        local contentH = nRows * O.ROW_H + 4
        if contentH < 1 then
            contentH = 1
        end
        booksChild:SetHeight(contentH)
        if booksHintFS then
            booksHintFS:SetText(O.SkillBookHint(rows) or "")
        end
    end

    -- ----------------------------------------------------------------
    -- expectation grid refresh (headers, row labels, check states, tabs)
    -- ----------------------------------------------------------------
    RefreshGrid = function()
        local slots = slotsForTab(expTab)
        local nSlots = table.getn(slots)
        local exp = expectations()
        local rows = O.GridRows(expTab)
        local nRows = table.getn(rows)
        -- column header tiles (outside the scroll frame, sticky). The tile
        -- SET is per tab (consumables 11, class buffs 6, equipment 14), so
        -- unlike the book grid's fixed columns these are refilled here.
        for c = 1, O.MAX_SLOT_COLS do
            local head = getglobal("DopingControlOptColHead" .. c)
            if head then
                if c <= nSlots then
                    local sd = slots[c]
                    head.dcLabelFS:SetText(sd.label or sd.id)
                    head.dcSubFS:SetText(sd.sub or "")
                    head.dcTooltip = sd.full or sd.id
                    head:Show()
                else
                    head:Hide()
                end
            end
        end
        -- grouped rows: role header + indented class rows.
        -- Stripes span THIS tab's content width, not the widest tab's.
        local gridW = O.GridContentW(nSlots)
        local dataIdx = 0
        for r = 1, nRows do
            local rd = rows[r]
            local lbl = EnsureRowLabel(r)
            local indent = 0
            if rd.kind == "class" then
                indent = 12
            end
            -- stripe every second CLASS row; role headers stay clean
            if rd.kind == "class" then
                dataIdx = dataIdx + 1
                PaintZebra(gridZebra, gridChild, r, gridW, O.ROW_H,
                    math.mod(dataIdx, 2) == 0)
            else
                PaintZebra(gridZebra, gridChild, r, gridW, O.ROW_H, false)
            end
            if lbl.dcIndent ~= indent then
                lbl.dcIndent = indent
                lbl:ClearAllPoints()
                lbl:SetPoint("TOPLEFT", gridChild, "TOPLEFT", indent,
                    -((r - 1) * O.ROW_H) - 5)
                lbl:SetWidth(O.GRID_LABEL_W - indent)
            end
            if rd.kind == "role" then
                -- 1.12 has no bold flag: size 11 + role color carry the
                -- header hierarchy over the size-10 class rows
                ApplyFont(lbl, 11)
                local rc = DC.COLORS and DC.COLORS["role" .. rd.role]
                if rc then
                    lbl:SetTextColor(rc.r, rc.g, rc.b)
                end
                lbl:SetText(DC.ROLE_LABEL[rd.role] or rd.role)
            else
                ApplyFont(lbl, 10)
                local cc = DC.COLORS and DC.COLORS["class" .. rd.class]
                if cc then
                    lbl:SetTextColor(cc.r, cc.g, cc.b)
                end
                lbl:SetText(O.ClassTitle(rd.class))
            end
            lbl:Show()
            for c = 1, O.MAX_SLOT_COLS do
                if c <= nSlots then
                    local sd = slots[c]
                    local cb = EnsureGridCell(r, c)
                    cb.dcKind = rd.kind
                    cb.dcRole = rd.role
                    cb.dcClass = rd.class
                    cb.dcSlot = sd.id
                    cb.dcLabel = sd.full or sd.id
                    if rd.kind == "role" then
                        -- aggregate cell: all classes checked = checked,
                        -- none = unchecked, mixed = checked at 0.45 alpha
                        -- (no tri-state CheckButton on 1.12)
                        local classes = O.RoleClasses(rd.role)
                        local nCl = table.getn(classes)
                        local nOn = 0
                        for k = 1, nCl do
                            if effLine(exp, rd.role, classes[k])[sd.id] then
                                nOn = nOn + 1
                            end
                        end
                        cb:SetChecked((nCl > 0 and nOn > 0) and 1 or nil)
                        if nOn > 0 and nOn < nCl then
                            cb:SetAlpha(0.45)
                        else
                            cb:SetAlpha(1)
                        end
                    else
                        cb:SetChecked(
                            effLine(exp, rd.role, rd.class)[sd.id] and 1
                            or nil)
                        cb:SetAlpha(1)
                    end
                    cb:Show()
                else
                    local cb = getglobal("DopingControlOptExpR" .. r
                        .. "C" .. c)
                    if cb then
                        cb:Hide()
                    end
                end
            end
        end
        -- hide surplus pooled rows (row count is constant today; the pool
        -- pattern keeps this safe if GridRows ever shrinks)
        for r = nRows + 1, gridRowMax do
            local lbl = getglobal("DopingControlOptRowLabel" .. r)
            if lbl then
                lbl:Hide()
            end
            if gridZebra[r] then
                gridZebra[r]:Hide()
            end
            for c = 1, (gridColMax[r] or 0) do
                local cb = getglobal("DopingControlOptExpR" .. r .. "C" .. c)
                if cb then
                    cb:Hide()
                end
            end
        end
        -- equipment-only dim note: the grid only configures ENCHANTS
        -- (empty slots are always a gap, regardless of these checkboxes)
        if eqHintFS then
            if expTab == "EQUIPMENT" then
                eqHintFS:SetText(
                    "checkboxes = enchant expectations; empty slots always count")
            else
                eqHintFS:SetText("")
            end
        end
    end

    -- ----------------------------------------------------------------
    -- editor tab switching: exactly one of {grid block, book block} is
    -- shown at a time, in the SAME position/width (see BuildOptionsFrame,
    -- which sizes the window to the taller of the two so this never
    -- resizes it). Named widgets are looked up by their global name --
    -- every one of them is created once in BuildOptionsFrame and just
    -- toggled here.
    -- ----------------------------------------------------------------
    local function ApplyEditorTabVisibility()
        local isBooks = O.IsSkillBookTab(expTab)
        local gridScroll = getglobal("DopingControlOptExpScroll")
        local hintFS = getglobal("DopingControlOptExpHint")
        local resetBtn = getglobal("DopingControlOptResetBtn")
        local bookNote = getglobal("DopingControlOptBookNote")
        local bookScroll = getglobal("DopingControlOptBookScroll")
        local gridHeadBar = getglobal("DopingControlOptHeadBar")
        local bookHeadBar = getglobal("DopingControlOptBookHeadBar")
        if isBooks then
            -- hiding the BAR hides its tiles with it (they are its
            -- children), so a stale grid tab's headers cannot bleed
            -- into this tab
            if gridHeadBar then gridHeadBar:Hide() end
            if bookHeadBar then bookHeadBar:Show() end
            if gridScroll then gridScroll:Hide() end
            if hintFS then hintFS:Hide() end
            if eqHintFS then eqHintFS:Hide() end
            if resetBtn then resetBtn:Hide() end
            if bookNote then bookNote:Show() end
            if bookScroll then bookScroll:Show() end
            if booksHintFS then booksHintFS:Show() end
        else
            -- WHICH tiles of the grid bar are lit is governed by
            -- RefreshGrid (per-tab slot count), not repeated here
            if gridHeadBar then gridHeadBar:Show() end
            if bookHeadBar then bookHeadBar:Hide() end
            if gridScroll then gridScroll:Show() end
            if hintFS then hintFS:Show() end
            if eqHintFS then eqHintFS:Show() end
            if resetBtn then resetBtn:Show() end
            if bookNote then bookNote:Hide() end
            if bookScroll then bookScroll:Hide() end
            if booksHintFS then booksHintFS:Hide() end
        end
    end

    -- ----------------------------------------------------------------
    -- Width follows the selected tab, like the main window follows its
    -- column count. Only WIDTHS change here -- every widget is anchored
    -- TOPLEFT (or to the frame's own right/bottom edge), so nothing needs
    -- repositioning when the frame narrows.
    -- ----------------------------------------------------------------
    local function EditorContentW(tab)
        if O.IsSkillBookTab(tab) then
            return O.BooksContentW()
        end
        return O.GridContentW(table.getn(slotsForTab(tab)))
    end

    local function ApplyEditorWidth()
        if not frame then
            return
        end
        local contentW = EditorContentW(expTab)
        frame:SetWidth(O.FrameWidthFor(contentW))
        if dividerTex then
            dividerTex:SetWidth(O.FrameWidthFor(contentW) - 48)
        end
        if O.IsSkillBookTab(expTab) then
            return   -- the book block is fixed-width (15 fixed columns)
        end
        local bar = getglobal("DopingControlOptHeadBar")
        if bar then
            bar:SetWidth(contentW)
        end
        local scroll = getglobal("DopingControlOptExpScroll")
        if scroll then
            scroll:SetWidth(contentW)
        end
        if gridChild then
            gridChild:SetWidth(contentW)
        end
    end

    -- the active editor tab's button is disabled (disabled = selected),
    -- every other one enabled -- walks the FULL O.EditorTabs() order (4
    -- buttons), unlike the old grid-only loop this replaces
    local function UpdateTabButtons()
        for i = 1, table.getn(EDITOR_TABS) do
            local b = getglobal("DopingControlOptTabBtn" .. i)
            if b then
                if EDITOR_TABS[i] == expTab then
                    b:Disable()
                else
                    b:Enable()
                end
            end
        end
    end

    -- single entry point for "the editor tab (may have) changed": always
    -- refreshes both pools (pooled widgets are cheap to touch even while
    -- hidden, and this keeps state consistent if the user flips tabs
    -- quickly), then shows/hides the two content blocks and the tab row.
    local function RefreshEditor()
        RefreshGrid()
        RefreshBooks()
        ApplyEditorTabVisibility()
        ApplyEditorWidth()
        UpdateTabButtons()
    end

    -- reset button: double-click-to-confirm (see header)
    local function ResetDisarmWatcher()
        if not this.dcArmedUntil or GetTime() > this.dcArmedUntil then
            this.dcArmedUntil = nil
            this:SetText("Reset expectations")
            this:SetScript("OnUpdate", nil)
        end
    end

    local function ResetOnClick()
        local now = GetTime()
        if this.dcArmedUntil and now <= this.dcArmedUntil then
            -- second click inside the window: reseed every (role, class)
            -- line from DC.DEFAULT_EXPECT (config.ResetExpectations,
            -- per-class shape; fallback: drop + re-materialize)
            this.dcArmedUntil = nil
            this:SetText("Reset expectations")
            this:SetScript("OnUpdate", nil)
            if DC.ResetExpectations then
                DC.ResetExpectations(db())
            else
                db().expectations = nil
            end
            RefreshGrid()    -- expectations() re-materializes when cleared
            refreshMatrix()
        else
            -- first click (or lapsed): arm
            this.dcArmedUntil = now + O.RESET_ARM_WINDOW
            this:SetText("Click again to confirm")
            this:SetScript("OnUpdate", ResetDisarmWatcher)
        end
    end

    local function ResetDisarm(btn)
        btn.dcArmedUntil = nil
        btn:SetText("Reset expectations")
        btn:SetScript("OnUpdate", nil)
    end

    -- ----------------------------------------------------------------
    -- frame build (lazy, once)
    -- ----------------------------------------------------------------
    local function BuildOptionsFrame()
        if frame then
            return frame
        end

        local f = CreateFrame("Frame", "DopingControlOptionsFrame", UIParent)
        f:SetWidth(widestFrameW())
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        f:SetFrameStrata("DIALOG")
        f:SetBackdrop(panelBackdrop())
        f:SetBackdropColor(1, 1, 1, 0.97)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function() this:StartMoving() end)
        f:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
        f:SetClampedToScreen(true)

        -- title (gold)
        local title = f:CreateFontString("DopingControlOptionsTitle",
            "ARTWORK", "GameFontNormal")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
        ApplyFont(title, 14)
        local g = DC.COLORS and DC.COLORS.goldHi
        if g then
            title:SetTextColor(g.r, g.g, g.b)
        else
            title:SetTextColor(0.85, 0.66, 0.31)
        end
        title:SetText("DopingControl")

        -- close X
        local closeX = CreateFrame("Button", "DopingControlOptionsCloseX",
            f, "UIPanelCloseButton")
        closeX:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
        if pfUI and pfUI.api and pfUI.api.SkinCloseButton then
            pfUI.api.SkinCloseButton(closeX)
        end

        -- layout cursor
        local x, y = 24, -44
        local function place(w, dy)
            w:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
            y = y + dy
        end

        -- ------------------------------------------------------------
        -- checkboxes
        -- ------------------------------------------------------------
        local cbTest = CreateCheckbox(f, "Test mode (simulated raid)",
            function() return db().testMode end,
            function(v)
                if DC.SetTestMode then
                    DC.SetTestMode(v)     -- core/init.lua: swaps store + rescan
                else
                    db().testMode = v     -- fallback if init not loaded yet
                end
            end)
        place(cbTest, -28)
        AddTooltip(cbTest, "Replace the scan with a fixed simulated raid.\nChat outputs are disabled while active.")

        -- Demo mode sits right below the test-mode row: same idea (the
        -- simulated raid), plus a transient expectation layer that shows
        -- all six school protection columns at once. A BUTTON, not a
        -- checkbox -- the state is never saved, so it relabels itself
        -- instead of pretending to be a stored setting.
        local btnDemo = CreateButton(f, "DopingControlOptDemoBtn",
            O.DemoButtonLabel(), 200,
            function()
                -- Capture the widget BEFORE SetDemoMode runs. `this` is a
                -- plain global the 1.12 dispatcher sets per script call and
                -- never restores: SetDemoMode synchronously drives
                -- DC_Matrix.Refresh -> M.Render, whose leftover-hide loop
                -- Hide()s pooled rows and group heads that carry their own
                -- OnHide handlers (ui/matrix.lua M.RowOnHide /
                -- M.GroupHeadOnHide -- they read `this` themselves). After
                -- that nested dispatch `this` is the last-hidden widget, and
                -- a row frame is a plain Frame with no SetText. Same order
                -- the other handlers in this file already keep
                -- (GridCellOnClick, ResetOnClick): finish the `this` reads
                -- and writes before refreshing anything.
                local btn = this
                if DC.SetDemoMode then
                    DC.SetDemoMode(not DC.demoMode)
                end
                btn:SetText(O.DemoButtonLabel())
            end)
        place(btnDemo, -28)
        AddTooltip(btnDemo, "Simulated raid with ALL SIX protection columns"
            .. " (fire, frost, nature, shadow, holy, arcane) shown at once."
            .. "\nYour saved expectations are left untouched, and demo mode"
            .. " is never saved - it ends with the next reload."
            -- the demo layer is snapshotted on entry (core/demo.lua), so
            -- grid edits made while it is armed do not reach the matrix
            .. "\nThe view is a snapshot: restart demo mode to pick up"
            .. " expectation changes made while it is running.")

        local cbMinimap = CreateCheckbox(f, "Show minimap button",
            function() return db().showMinimapButton end,
            function(v)
                db().showMinimapButton = v
                if DC_Minimap and DC_Minimap.Update then
                    DC_Minimap.Update()
                end
            end)
        place(cbMinimap, -28)

        local cbScan = CreateCheckbox(f, "Auto-scan on ready check",
            function() return db().readyCheckScan end,
            function(v) db().readyCheckScan = v end)
        place(cbScan, -28)

        local cbOpen = CreateCheckbox(f, "Auto-open on ready check",
            function() return db().readyCheckOpen end,
            function(v) db().readyCheckOpen = v end)
        place(cbOpen, -28)

        -- ------------------------------------------------------------
        -- divider
        -- ------------------------------------------------------------
        local divider = f:CreateTexture("DopingControlOptDivider", "ARTWORK")
        divider:SetHeight(1)
        divider:SetWidth(widestFrameW() - 48)
        local lc = DC.COLORS and DC.COLORS.line
        if lc then
            divider:SetTexture(lc.r, lc.g, lc.b)
        else
            divider:SetTexture(0.15, 0.17, 0.22)
        end
        divider:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - 6)
        dividerTex = divider
        y = y - 14

        -- ------------------------------------------------------------
        -- expectation editor (role x class grouped rows)
        -- ------------------------------------------------------------
        local heading = f:CreateFontString("DopingControlOptExpHeading",
            "ARTWORK", "GameFontNormalSmall")
        ApplyFont(heading, 11)
        heading:SetTextColor(0.79, 0.8, 0.83)
        heading:SetText("Expectations (role x class x slot)")
        place(heading, -22)

        -- tab selector: one small button per EDITOR_TABS entry (the three
        -- expectation tabs plus Skill books last); the selected one is
        -- disabled. widestFrameW() already accounts for the widest of the two
        -- content blocks below, so this fits comfortably.
        local tabRowY = y
        for i = 1, table.getn(EDITOR_TABS) do
            local tabKey = EDITOR_TABS[i]
            local b = CreateButton(f, "DopingControlOptTabBtn" .. i,
                O.EditorTabLabel(tabKey), 108,
                function()
                    expTab = this.dcTab
                    RefreshEditor()
                end)
            b:SetHeight(20)
            b.dcTab = tabKey
            b:SetPoint("TOPLEFT", f, "TOPLEFT", x + (i - 1) * 114, tabRowY)
        end
        y = y - 26

        -- shared top for the two mutually exclusive content blocks below
        -- (only one is ever shown, ApplyEditorTabVisibility); the window
        -- height is fixed to whichever block is taller so switching tabs
        -- never resizes it (see the height computation after both).
        local contentTop = y

        -- ------------------------------------------------------------
        -- BLOCK 1: expectation grid (Consumables / Class buffs /
        -- Equipment) -- column headers, scrolling grouped grid, hint,
        -- equipment-only note, reset button
        -- ------------------------------------------------------------
        local gy = contentTop

        -- column header bar + tiles (outside the scroll frame, so they stay
        -- put while the grid scrolls) -- same furniture as the main window
        local gridHeadBar = CreateHeaderBar(f, "DopingControlOptHeadBar",
            x, gy, gridWidest(), "ROLE / CLASS")
        for c = 1, O.MAX_SLOT_COLS do
            local head = CreateHeaderTile(gridHeadBar,
                "DopingControlOptColHead" .. c, O.GRID_LABEL_W + (c - 1) * O.COL_PITCH)
            AddTooltip(head, "")
        end
        gy = gy - O.HEAD_ROW_H - 2

        -- scroll frame around the grouped grid (the 25 rows would be
        -- ~550px -- cap at O.GRID_MAX_H, scroll the rest)
        local rows = O.GridRows(expTab)
        local nRows = table.getn(rows)
        local contentH = nRows * O.ROW_H + 4
        local gridH = contentH
        if gridH > O.GRID_MAX_H then
            gridH = O.GRID_MAX_H
        end
        local scroll = CreateFrame("ScrollFrame", "DopingControlOptExpScroll",
            f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", x, gy)
        scroll:SetWidth(gridWidest())
        scroll:SetHeight(gridH)
        gridChild = CreateFrame("Frame", "DopingControlOptExpScrollChild",
            scroll)
        gridChild:SetWidth(gridWidest())
        gridChild:SetHeight(contentH)
        scroll:SetScrollChild(gridChild)
        if pfUI and pfUI.api and pfUI.api.SkinScrollbar then
            pfUI.api.SkinScrollbar(
                getglobal("DopingControlOptExpScrollScrollBar"))
        end
        gy = gy - gridH - 8

        -- hint
        local hint = f:CreateFontString("DopingControlOptExpHint",
            "ARTWORK", "GameFontNormalSmall")
        ApplyFont(hint, 9)
        hint:SetTextColor(0.36, 0.38, 0.44)
        hint:SetText("Click a cell to toggle - applies immediately."
            .. " Role-row cells set all classes of the role.")
        hint:SetPoint("TOPLEFT", f, "TOPLEFT", x, gy)
        gy = gy - 12

        -- equipment-only note (RefreshGrid sets the text; empty string on
        -- every other tab, so it costs one small blank line there)
        local eqHint = f:CreateFontString("DopingControlOptEqHint",
            "ARTWORK", "GameFontNormalSmall")
        ApplyFont(eqHint, 9)
        eqHint:SetTextColor(0.36, 0.38, 0.44)
        eqHint:SetText("")
        eqHint:SetPoint("TOPLEFT", f, "TOPLEFT", x, gy)
        gy = gy - 14
        eqHintFS = eqHint

        -- reset button (double-click-to-confirm)
        local resetBtn = CreateButton(f, "DopingControlOptResetBtn",
            "Reset expectations", 160, ResetOnClick)
        resetBtn:SetPoint("TOPLEFT", f, "TOPLEFT", x, gy)
        gy = gy - 30
        AddTooltip(resetBtn,
            "Restore the default expectations for every class.\nFirst click arms, second click within "
            .. O.RESET_ARM_WINDOW .. " s confirms.")

        local gridBlockBottom = gy

        -- ------------------------------------------------------------
        -- BLOCK 2: weapon skill books -- explanation line at the TOP
        -- (same spot the column headers occupy in block 1), then the
        -- scrolling, wrapped skill list, then the empty-state hint
        -- ------------------------------------------------------------
        local by = contentTop

        local bookNote = f:CreateFontString("DopingControlOptBookNote",
            "ARTWORK", "GameFontNormalSmall")
        ApplyFont(bookNote, 9)
        bookNote:SetTextColor(0.36, 0.38, 0.44)
        bookNote:SetText("A book is worth about 0.6% hit and cannot be read"
            .. " off another player - tick what you know.")
        bookNote:SetPoint("TOPLEFT", f, "TOPLEFT", x, by)
        by = by - 16

        -- sticky column header bar (outside the scroll frame, so it stays
        -- put while the roster scrolls) -- same furniture as the
        -- expectation grid above and as the main window, only with a FIXED
        -- set of labels (O.BOOK_COLUMNS), filled once here.
        local bookHeadBar = CreateHeaderBar(f, "DopingControlOptBookHeadBar",
            x, by, O.BooksContentW(), "PLAYER")
        for c = 1, table.getn(O.BOOK_COLUMNS) do
            local cd = O.BOOK_COLUMNS[c]
            local head = CreateHeaderTile(bookHeadBar,
                "DopingControlOptBookColHead" .. c,
                O.BOOK_NAME_W + (c - 1) * O.COL_PITCH)
            head.dcLabelFS:SetText(cd.label)
            head.dcSubFS:SetText(cd.sub or "")
            AddTooltip(head, cd.full or cd.skill)
        end
        by = by - O.HEAD_ROW_H - 2

        -- fixed height: the roster length must never resize the window;
        -- width fits the fixed weapon-skill column set (O.BooksContentW)
        -- Height: stretch this block so it ends exactly where the (taller)
        -- grid block ends -- the window is sized to the taller of the two
        -- and a fixed cap would leave dead space under this tab. 24 = the
        -- 8 px gap plus the 16 px hint line that still follow below.
        -- Floored at O.BOOKS_MAX_H so this block, not a shrinking grid
        -- block, decides the minimum.
        local booksScrollH = by - gridBlockBottom - 24
        if booksScrollH < O.BOOKS_MAX_H then
            booksScrollH = O.BOOKS_MAX_H
        end
        local bookScroll = CreateFrame("ScrollFrame",
            "DopingControlOptBookScroll", f, "UIPanelScrollFrameTemplate")
        bookScroll:SetPoint("TOPLEFT", f, "TOPLEFT", x, by)
        bookScroll:SetWidth(O.BooksContentW())
        bookScroll:SetHeight(booksScrollH)
        booksChild = CreateFrame("Frame", "DopingControlOptBookScrollChild",
            bookScroll)
        booksChild:SetWidth(O.BooksContentW())
        booksChild:SetHeight(booksScrollH)
        bookScroll:SetScrollChild(booksChild)
        if pfUI and pfUI.api and pfUI.api.SkinScrollbar then
            pfUI.api.SkinScrollbar(
                getglobal("DopingControlOptBookScrollScrollBar"))
        end
        by = by - booksScrollH - 8

        -- empty state (RefreshBooks sets the text; empty string once rows
        -- exist, so it costs one blank line then)
        local bookHint = f:CreateFontString("DopingControlOptBookHint",
            "ARTWORK", "GameFontNormalSmall")
        ApplyFont(bookHint, 9)
        bookHint:SetTextColor(0.36, 0.38, 0.44)
        bookHint:SetText("")
        bookHint:SetPoint("TOPLEFT", f, "TOPLEFT", x, by)
        by = by - 16
        booksHintFS = bookHint

        local booksBlockBottom = by

        -- the window is sized to the TALLER of the two blocks (more
        -- negative y = descended further) so it never jumps when the
        -- Skill books tab is selected
        if gridBlockBottom < booksBlockBottom then
            y = gridBlockBottom
        else
            y = booksBlockBottom
        end

        -- version footer
        local footer = f:CreateFontString("DopingControlOptFooter",
            "ARTWORK", "GameFontNormalSmall")
        ApplyFont(footer, 9)
        footer:SetTextColor(0.6, 0.6, 0.6)
        local ver = GetAddOnMetadata
            and WDI_DopingVersion()
        footer:SetText("DopingControl " .. (ver or ""))
        footer:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)

        -- window height: computed from the layout cursor (grows
        -- with the grid but stays bounded by the scroll cap);
        -- 34 = footer strip below the last placed widget
        f:SetHeight(-y + 34)

        -- OnShow repopulates every widget from DB
        f:SetScript("OnShow", function()
            for i = 1, table.getn(checkboxes) do
                local cb = checkboxes[i]
                cb:SetChecked(cb.dcGet() and 1 or nil)
            end
            RefreshEditor()  -- grid/books pools + tab visibility + buttons
            ResetDisarm(getglobal("DopingControlOptResetBtn"))
            -- demo mode can have been toggled by /dc demo meanwhile
            local bd = getglobal("DopingControlOptDemoBtn")
            if bd then
                bd:SetText(O.DemoButtonLabel())
            end
        end)

        -- ESC closes
        table.insert(UISpecialFrames, "DopingControlOptionsFrame")

        -- widgets are built shown by default; establish the correct
        -- initial block visibility once even though OnShow will redo it
        -- on every real Show() (defensive against odd load orders, same
        -- spirit as the rest of this file)
        frame = f
        ApplyEditorTabVisibility()
        -- the per-tab WIDTH is applied by RefreshEditor on the first
        -- OnShow, not here: BuildOptionsFrame sits one upvalue under Lua
        -- 5.0's hard limit of 32, and capturing ApplyEditorWidth as well
        -- pushes it over ("too many upvalues" -- a COMPILE error, i.e. the
        -- whole file stops loading). The frame is built at its widest, so
        -- the only cost is that it stays wide until the first Show().

        f:Hide()
        return f
    end

    -- ----------------------------------------------------------------
    -- public API
    -- ----------------------------------------------------------------
    function O.Toggle()
        local f = BuildOptionsFrame()
        if f:IsShown() then
            f:Hide()
        else
            f:Show()
        end
    end

    function O.Open()
        local f = BuildOptionsFrame()
        f:Show()
    end

    -- external state changes (/dc test, /dc demo, minimap toggle) can
    -- resync an open options window
    function O.Refresh()
        if frame and frame:IsShown() then
            for i = 1, table.getn(checkboxes) do
                local cb = checkboxes[i]
                cb:SetChecked(cb.dcGet() and 1 or nil)
            end
            local bd = getglobal("DopingControlOptDemoBtn")
            if bd then
                bd:SetText(O.DemoButtonLabel())
            end
            RefreshEditor()  -- a fresh scan can add or drop book rows
        end
    end

    -- convenience alias (minimap right-click / slash handler)
    DC.ToggleOptions = O.Toggle

end
