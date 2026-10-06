if WDI_DOPING_SKIP then return end -- DopingControl ui/cellsheet.lua
--
-- The matrix draws one small box per cell: a solid background with a 1px
-- border whose color carries the state. Done with SetBackdrop that costs NINE
-- texture regions per cell (measured in the client: bare frame 0, backdrop
-- with bgFile only 1, backdrop with edgeFile 9). At 805 cells that is ~7200
-- regions of pure decoration.
--
-- Instead every box is baked into one sheet and a cell owns a single texture
-- region that picks its box with SetTexCoord. The border is part of the image,
-- so the result is pixel-identical -- the sheet is generated from the same
-- DC.COLORS palette by tools/gen-cellsheet.js.
--
-- Pure Lua on purpose: no WoW API at file scope, so the offline tests can
-- dofile it under lua50.exe.

DC_Cells = {}

DC_Cells.SHEET = {
    path   = "Interface\\AddOns\\WhoDidIt\\DopingControl\\textures\\cells",
    size   = 256,   -- power of two, mandatory: a 12x12 TGA fails silently
    tileW  = 64,    -- holds the widest sprite (34) with room to spare
    tileH  = 32,    -- holds CELL_H (23)
    perRow = 4,     -- 256 / 64
}

-- Cell height never varies; only the width does (trinket columns are 34).
DC_Cells.CELL_H  = 23
DC_Cells.WIDTHS  = { 30, 34 }

-- Every (background, border) pair a CELL can take, in sheet order. Borders
-- given as a number are DC.QUALITY indices, everything else is a DC.COLORS
-- key. Order is the wire format of the sheet: appending is safe, reordering
-- means regenerating the TGA.
DC_Cells.VARIANTS = {
    { name = "HAS",          bg = "hatBg",   border = "hatBorder"   },
    { name = "MISSING",      bg = "fehltBg", border = "fehltBorder" },
    { name = "UNKNOWN",      bg = "unbekBg", border = "unbekBorder" },
    { name = "SKIP",         bg = "skip",    border = "skipBorder"  },
    { name = "NEUTRAL",      bg = "theadBg", border = "line"        },
    { name = "ITEM_HAS",     bg = "theadBg", border = "hatBorder"   },
    { name = "ITEM_MISSING", bg = "theadBg", border = "fehltBorder" },
    { name = "Q_RARE",       bg = "theadBg", border = "rareBorder"  },
    { name = "Q_EPIC",       bg = "theadBg", border = "epicBorder"  },
    { name = "Q_0",          bg = "theadBg", border = 0 },
    { name = "Q_1",          bg = "theadBg", border = 1 },
    { name = "Q_2",          bg = "theadBg", border = 2 },
    { name = "Q_5",          bg = "theadBg", border = 5 },
    { name = "Q_6",          bg = "theadBg", border = 6 },
}

DC_Cells.INDEX = {}
for i = 1, table.getn(DC_Cells.VARIANTS) do
    DC_Cells.INDEX[DC_Cells.VARIANTS[i].name] = i
end

-- Tile slot of a variant/width pair: each variant owns two consecutive tiles,
-- one per width, in DC_Cells.WIDTHS order.
local function slotOf(name, w)
    local vi = DC_Cells.INDEX[name]
    if not vi then
        return nil
    end
    for k = 1, table.getn(DC_Cells.WIDTHS) do
        if DC_Cells.WIDTHS[k] == w then
            return (vi - 1) * table.getn(DC_Cells.WIDTHS) + (k - 1)
        end
    end
    return nil
end
DC_Cells.SlotOf = slotOf

-- SetTexCoord arguments for one box. Returns four numbers or nil -- nil so a
-- typo shows up as a missing box instead of silently sampling tile 0.
function DC_Cells.Coords(name, w)
    local slot = slotOf(name, w)
    if not slot then
        return nil
    end
    local S = DC_Cells.SHEET
    local col = math.mod(slot, S.perRow)
    local row = math.floor(slot / S.perRow)
    local x0  = col * S.tileW
    local y0  = row * S.tileH
    return x0 / S.size,
           (x0 + w) / S.size,
           y0 / S.size,
           (y0 + DC_Cells.CELL_H) / S.size
end

-- State + slot kind + item quality -> variant name. Mirrors exactly what the
-- old SetBackdropG call sites in ui/matrix.lua chose -- which, for a nil
-- quality, differed BY KIND (see ui/matrix.lua's M.PaintItemTile, old lines
-- 1965-1990, confirmed at tools/luatests/test_cellsheet.lua):
--   * trinket: M.qualityColors(item.quality) ran unconditionally, and for
--     quality == nil that resolves to DC.QUALITY[1] (common/white) via the
--     `q or 1` fallback -- state-INDEPENDENT.
--   * ench: quality == nil skipped M.qualityColors and fell back to
--     C.hatBorder/C.fehltBorder/C.line BY STATE -- exactly
--     ITEM_HAS/ITEM_MISSING/NEUTRAL.
-- So trinket's nil-quality case must NOT share ench's state-based fallback.
function DC_Cells.VariantFor(state, kind, quality)
    if kind == "ench" or kind == "trinket" then
        if quality == 3 then return "Q_RARE" end
        if quality == 4 then return "Q_EPIC" end
        if quality ~= nil then return "Q_" .. quality end
        if kind == "trinket" then
            return "Q_1"
        end
        if state == "HAS" then return "ITEM_HAS" end
        if state == "MISSING" then return "ITEM_MISSING" end
        return "NEUTRAL"
    end
    if state == "HAS" then return "HAS" end
    if state == "MISSING" then return "MISSING" end
    if state == "UNKNOWN" then return "UNKNOWN" end
    return "SKIP"
end
