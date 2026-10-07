if WDI_DOPING_SKIP then return end -- DopingControl ui/widgets.lua
-- Shared UI building blocks: panel backdrop, pooled-widget factories
-- (cell / pill / badge / button), tooltip helpers, pfUI-aware font helper,
-- change-guarded setters (only touch a region when the value changed).
--
-- Factory + pooling patterns follow common 1.12 addon practice
-- (pfUI-style WHITE8X8 backdrops, pooled regions, save-and-call hooks).
--
-- Pure Lua 5.0 dofile-loadable: top level only defines tables/functions;
-- CreateFrame & friends are only referenced INSIDE factory functions, which
-- are never called offline.

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Widgets = DC_Widgets or {}
local W = DC_Widgets

-- ------------------------------------------------------------------
-- Texture / font constants
-- ------------------------------------------------------------------
W.SOLID_TEX = "Interface\\Buttons\\WHITE8X8"          -- 1px-border backdrop base
W.FONT      = "Fonts\\FRIZQT__.TTF"                    -- default client font
W.CHECK_TEX = "Interface\\Buttons\\UI-CheckBox-Check"  -- HAS glyph (tinted green)
W.CROSS_TEX = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" -- MISSING glyph (tinted red)

-- Main window backdrop (textures shipped in DopingControl\textures\).
W.PANEL_BACKDROP = {
    bgFile   = "Interface\\AddOns\\WhoDidIt\\DopingControl\\textures\\panel_bg",
    edgeFile = "Interface\\AddOns\\WhoDidIt\\DopingControl\\textures\\panel_border",
    tile = true, tileSize = 128, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

-- Solid 1px-border backdrop for cells/pills/badges/buttons (pfUI-style
-- WHITE8X8 recipe; bg + border colored via SetBackdropColor /
-- SetBackdropBorderColor).
W.SOLID_BACKDROP = {
    bgFile   = W.SOLID_TEX,
    edgeFile = W.SOLID_TEX,
    tile = false, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

W.WHITE = { r = 1, g = 1, b = 1 }

-- ------------------------------------------------------------------
-- Cell-box fallback palette: variant name -> (bg, border) color reference,
-- used ONLY when ui/cellsheet.lua's baked sheet is unavailable (see
-- W.HasCellSheet below). `border` is a DC.COLORS key, or a number that
-- indexes DC.QUALITY -- same convention as DC_Cells.VARIANTS in
-- ui/cellsheet.lua, which this table intentionally mirrors: colors are
-- pulled LIVE from DC.COLORS/DC.QUALITY (core/const.lua, already loaded --
-- ui/cellsheet.lua only bakes that same palette into a texture, it does
-- not own it), so nothing here duplicates a color VALUE. The pairing
-- itself (which key goes with which variant) can't be derived
-- mechanically -- it is the one piece of information that has to exist
-- twice given the failure mode this guards (ui/cellsheet.lua not loaded
-- at all). tools/luatests/test_widgets.lua cross-checks every entry
-- against the real DC_Cells.VARIANTS so the two cannot silently drift.
W.CELL_FALLBACK_VARIANTS = {
    HAS          = { bg = "hatBg",   border = "hatBorder"   },
    MISSING      = { bg = "fehltBg", border = "fehltBorder" },
    UNKNOWN      = { bg = "unbekBg", border = "unbekBorder" },
    SKIP         = { bg = "skip",    border = "skipBorder"  },
    NEUTRAL      = { bg = "theadBg", border = "line"        },
    ITEM_HAS     = { bg = "theadBg", border = "hatBorder"   },
    ITEM_MISSING = { bg = "theadBg", border = "fehltBorder" },
    Q_RARE       = { bg = "theadBg", border = "rareBorder"  },
    Q_EPIC       = { bg = "theadBg", border = "epicBorder"  },
    Q_0          = { bg = "theadBg", border = 0 },
    Q_1          = { bg = "theadBg", border = 1 },
    Q_2          = { bg = "theadBg", border = 2 },
    Q_5          = { bg = "theadBg", border = 5 },
    Q_6          = { bg = "theadBg", border = 6 },
}

-- ------------------------------------------------------------------
-- DC_Cells fallback shim -- covers a mid-session /reload where THIS file
-- (ui/widgets.lua, an EXISTING file whose new content /reload happily
-- re-executes) deploys, but ui/cellsheet.lua (a NEW file added in the same
-- change) does not: 1.12's /reload re-runs existing files but never loads
-- a file that was not already part of the running session (verified
-- in-game). Left alone, DC_Cells stays nil, and it is not only
-- W.MakeCell/W.SetCellBox below that touch it -- ui/matrix.lua calls
-- DC_Cells.VariantFor(...) directly at two paint sites (M.PaintItemTile
-- and the legacy trinket path, ui/matrix.lua ~2182/2381 -- out of scope
-- for this change) and would error on the very first painted item/trinket
-- cell regardless of anything done here.
--
-- The shim supplies ONLY the pure classification function -- state/kind/
-- quality -> variant NAME string -- no sheet, no texture, no coordinate
-- math, because none of that can work without ui/cellsheet.lua's baked
-- sheet file. It is a verbatim copy of DC_Cells.VariantFor's logic (see
-- ui/cellsheet.lua); test_widgets.lua cross-checks the two stay in sync.
-- Installs only when DC_Cells does not already exist, so the normal
-- (full-restart) load path -- where ui/cellsheet.lua runs before this file
-- per DopingControl.toc and sets the real DC_Cells -- is untouched.
if not DC_Cells then
    DC_Cells = {
        VariantFor = function(state, kind, quality)
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
        end,
    }
end

-- Whether ui/cellsheet.lua's baked sheet is actually available (as
-- opposed to the shim above, which never sets .SHEET). One seam shared by
-- W.MakeCell and W.SetCellBox, and directly testable offline without
-- CreateFrame (unlike W.MakeCell itself).
function W.HasCellSheet()
    return DC_Cells ~= nil and DC_Cells.SHEET ~= nil
end

-- ------------------------------------------------------------------
-- Font helper (we keep OUR pixel
-- size -- the matrix layout depends on it -- and only take pfUI's font
-- FAMILY when pfUI is present; forcing pfUI's global font size would break
-- the 30x23 cell grid).
-- ------------------------------------------------------------------
function W.ApplyFont(fs, size)
    size = size or 10
    if pfUI and pfUI.font_default then
        fs:SetFont(pfUI.font_default, size)
    else
        fs:SetFont(W.FONT, size)
    end
end

-- ------------------------------------------------------------------
-- Change-guarded setters (convention: cache last-applied value on the
-- region as dcLast*; only call the real setter when the value changed.
-- Color guards compare by TABLE REFERENCE -- callers always pass the
-- shared DC.COLORS / DC.QUALITY tables, so this is exact and zero-alloc).
-- ------------------------------------------------------------------
function W.SetTextG(fs, text)
    if fs.dcLastText ~= text then
        fs.dcLastText = text
        fs:SetText(text)
    end
end

function W.SetTextColorG(fs, c)
    if fs.dcLastColor ~= c then
        fs.dcLastColor = c
        fs:SetTextColor(c.r, c.g, c.b)
    end
end

function W.SetBackdropG(f, bg, border)
    if f.dcLastBg ~= bg then
        f.dcLastBg = bg
        f:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 1)
    end
    if f.dcLastBorder ~= border then
        f.dcLastBorder = border
        f:SetBackdropBorderColor(border.r, border.g, border.b, 1)
    end
end

function W.SetTextureG(tex, path)
    if tex.dcLastTex ~= path then
        tex.dcLastTex = path
        tex:SetTexture(path)
    end
end

function W.SetVertexG(tex, c)
    if tex.dcLastVertex ~= c then
        tex.dcLastVertex = c
        tex:SetVertexColor(c.r, c.g, c.b)
    end
end

function W.SetAlphaG(region, a)
    if region.dcLastAlpha ~= a then
        region.dcLastAlpha = a
        region:SetAlpha(a)
    end
end

-- ------------------------------------------------------------------
-- FontString factory
-- ------------------------------------------------------------------
function W.MakeText(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    W.ApplyFont(fs, size)
    if color then
        W.SetTextColorG(fs, color)
    end
    return fs
end

-- ------------------------------------------------------------------
-- Cell factory: 30x23 state cell (the 30x23 size is part of the fixed
-- visual layout). The box (background + 1px border) is one texture region
-- sampled from the baked sheet in ui/cellsheet.lua -- SetBackdrop with an
-- edgeFile costs NINE texture regions per cell, this costs one. The icon
-- (check/cross glyph OR trinket item icon) and FontString (?, skip dot,
-- trinket monogram) are created on demand via W.CellIcon / W.CellText;
-- the matrix paint code shows exactly one of them per state.
-- Pool children stay anonymous (documented factory exception).
-- ------------------------------------------------------------------
function W.MakeCell(parent, name, w, h)
    local c = CreateFrame("Frame", name, parent)
    c:SetWidth(w or 30)
    c:SetHeight(h or 23)
    c:EnableMouse(true)
    c.dcW = w or 30
    if W.HasCellSheet() then
        -- The state box (background + 1px border) comes from one baked sheet:
        -- SetBackdrop with an edgeFile costs NINE texture regions per cell,
        -- this costs one. See ui/cellsheet.lua.
        c.boxTex = c:CreateTexture(nil, "BACKGROUND")
        c.boxTex:SetAllPoints(c)
        c.boxTex:SetTexture(DC_Cells.SHEET.path)
        -- Without an initial texcoord the region would show the WHOLE sheet
        -- stretched across the cell until the first paint. Start on NEUTRAL.
        local l, r, t, b = DC_Cells.Coords("NEUTRAL", c.dcW)
        if l then
            c.boxTex:SetTexCoord(l, r, t, b)
            c.dcBoxVariant = "NEUTRAL"
            c.dcBoxW = c.dcW
        end
    else
        -- Fallback: ui/cellsheet.lua did not load this session (see
        -- W.HasCellSheet above) -- pre-refactor SetBackdrop path (no
        -- boxTex region at all) so the matrix still draws instead of
        -- erroring on a nil DC_Cells.SHEET. W.SetBackdropG and
        -- W.SOLID_BACKDROP are untouched by the sprite refactor, so this
        -- is exactly what W.MakeCell did before it.
        c:SetBackdrop(W.SOLID_BACKDROP)
        W.SetCellBox(c, "NEUTRAL")
    end
    return c
end

-- Icon and FontString on demand: a cell shows one or the other, and in 1.12
-- eagerly created regions cost even while hidden.
function W.CellIcon(cell)
    if not cell.icon then
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetPoint("CENTER", cell, "CENTER", 0, 0)
        cell.icon:SetWidth(16)
        cell.icon:SetHeight(16)
        cell.icon:Hide()
    end
    return cell.icon
end

function W.CellText(cell)
    if not cell.text then
        cell.text = cell:CreateFontString(nil, "OVERLAY")
        W.ApplyFont(cell.text, 9)
        cell.text:SetPoint("CENTER", cell, "CENTER", 0, 0)
    end
    return cell.text
end

-- Guards on variant AND width (cell.dcBoxW, the width the box was last
-- painted at) -- NOT variant alone. ui/matrix.lua resizes a pooled cell in
-- place when its column width changes (trinket columns are 34, normal
-- cells 30: see ui/matrix.lua's column-layout path around SetWidth(col.w))
-- and only ever writes cell.dcW; it has no notion of dcBoxVariant and isn't
-- expected to invalidate it. If this guard only checked variant, a cell
-- that kept its variant across such a resize would keep a stale texcoord
-- sized for the OLD width -- the baked border would sit off the new cell
-- edge. Tracking dcBoxW here keeps the guard self-contained: correctness
-- does not depend on any caller convention.
function W.SetCellBox(cell, variant)
    if not W.HasCellSheet() then
        -- Fallback: same pre-refactor SetBackdrop recipe, colors pulled
        -- LIVE from DC.COLORS/DC.QUALITY via W.CELL_FALLBACK_VARIANTS
        -- above. Never touches cell.boxTex -- a fallback cell (see
        -- W.MakeCell) does not have one. W.SetBackdropG already
        -- change-guards by table reference, so no separate
        -- dcBoxVariant/dcBoxW bookkeeping is needed here.
        local v = W.CELL_FALLBACK_VARIANTS[variant]
        if not v then
            return
        end
        local bg = DC.COLORS[v.bg]
        local border = v.border
        if type(border) == "number" then
            border = DC.QUALITY[border]
        else
            border = DC.COLORS[border]
        end
        if not bg or not border then
            return
        end
        W.SetBackdropG(cell, bg, border)
        return
    end
    if cell.dcBoxVariant == variant and cell.dcBoxW == cell.dcW then
        return
    end
    local l, r, t, b = DC_Cells.Coords(variant, cell.dcW)
    if not l then
        return
    end
    cell.dcBoxVariant = variant
    cell.dcBoxW = cell.dcW
    cell.boxTex:SetTexCoord(l, r, t, b)
end

-- ------------------------------------------------------------------
-- Pill factory (ready pill, coverage pill): bordered mini frame with a
-- centered FontString; width is adjusted by the caller to fit the text.
-- ------------------------------------------------------------------
function W.MakePill(parent, name)
    local p = CreateFrame("Frame", name, parent)
    p:SetWidth(70)
    p:SetHeight(16)
    p:SetBackdrop(W.SOLID_BACKDROP)
    p:EnableMouse(true)
    p.text = p:CreateFontString(nil, "OVERLAY")
    W.ApplyFont(p.text, 9)
    p.text:SetPoint("CENTER", p, "CENTER", 0, 0)
    return p
end

-- ------------------------------------------------------------------
-- Role badge factory: clickable bordered button with centered label.
-- Suggested roles render with a "?" suffix + dimmer border (matrix paints
-- that -- 1.12 has no dashed borders, see the adaptation note there).
-- ------------------------------------------------------------------
function W.MakeBadge(parent, name)
    local b = CreateFrame("Button", name, parent)
    b:SetWidth(56)
    b:SetHeight(16)
    b:SetBackdrop(W.SOLID_BACKDROP)
    b.text = b:CreateFontString(nil, "OVERLAY")
    W.ApplyFont(b.text, 8)
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b:RegisterForClicks("LeftButtonUp")
    return b
end

-- ------------------------------------------------------------------
-- Dark gold-trim button (titlebar Scan/Report/Options/X).
-- ------------------------------------------------------------------
function W.MakeButton(parent, name, label, width, height)
    local C = DC.COLORS
    local b = CreateFrame("Button", name, parent)
    b:SetWidth(width or 64)
    b:SetHeight(height or 19)
    b:SetBackdrop(W.SOLID_BACKDROP)
    W.SetBackdropG(b, C.panel2, C.goldSoft)
    b.text = b:CreateFontString(nil, "OVERLAY")
    W.ApplyFont(b.text, 10)
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
    W.SetTextColorG(b.text, C.goldHi)
    b.text:SetText(label)
    b:SetScript("OnEnter", function()
        W.SetBackdropG(this, C.panel3, C.gold)
    end)
    b:SetScript("OnLeave", function()
        W.SetBackdropG(this, C.panel2, C.goldSoft)
    end)
    return b
end

-- ------------------------------------------------------------------
-- Tooltip helpers. Convention: the builder only ADDS
-- lines; AttachTooltip calls SetOwner before and Show after -- AddLine
-- never calls Show itself.
-- AttachTooltip CHAINS any existing OnEnter/OnLeave (no HookScript on
-- 1.12 -- standard save-and-call pattern).
-- ------------------------------------------------------------------
function W.TipLine(text, c, wrap)
    if not GameTooltip then
        return
    end
    local r, g, b = 1, 1, 1
    if c then
        r, g, b = c.r, c.g, c.b
    end
    if wrap then
        GameTooltip:AddLine(text, r, g, b, 1)
    else
        GameTooltip:AddLine(text, r, g, b)
    end
end

-- Two-column tooltip line: label left, value flush RIGHT. This is what
-- makes a breakdown read like an addition on paper -- the values line up
-- in a column instead of trailing their labels at ragged positions. 1.12
-- has no monospace font and no tab stops; AddDoubleLine is the only way to
-- get a right-aligned column, and it exists in this client's FrameXML.
-- `cr` defaults to the label color when omitted.
function W.TipDouble(left, right, c, cr)
    if not GameTooltip then
        return
    end
    local r, g, b = 1, 1, 1
    if c then
        r, g, b = c.r, c.g, c.b
    end
    local r2, g2, b2 = r, g, b
    if cr then
        r2, g2, b2 = cr.r, cr.g, cr.b
    end
    GameTooltip:AddDoubleLine(left, right, r, g, b, r2, g2, b2)
end

-- W.dcTipOwner: our own record of which of OUR frames currently owns
-- GameTooltip. WoW 1.12's GameTooltip has no "GetOwner" method (confirmed
-- against FrameXML-1.12.1: zero real hits -- the only "GetOwner" match
-- anywhere in that tree is the unrelated global function
-- GetOwnerAuctionItems). Every caller in this addon that ever needs "who
-- currently owns the tooltip" goes through W.AttachTooltip to open one in
-- the first place, so this is the single place that needs to record it.
-- Set right after SetOwner
-- (matching order: SetOwner, then the builder runs, then Show -- a builder
-- that itself re-SetOwner()s the SAME frame, like M.CellTooltip's
-- ANCHOR_LEFT override, does not change who owns it). Cleared in OnLeave,
-- guarded on identity so a late/out-of-order OnLeave can never clobber a
-- newer owner.
W.dcTipOwner = nil

function W.AttachTooltip(frame, builder, anchor)
    frame.dcTipBuilder = builder
    frame.dcTipAnchor = anchor or "ANCHOR_LEFT"
    frame.dcOldEnter = frame:GetScript("OnEnter")
    frame.dcOldLeave = frame:GetScript("OnLeave")
    frame:SetScript("OnEnter", function()
        if this.dcOldEnter then
            this.dcOldEnter()
        end
        if GameTooltip and this.dcTipBuilder then
            GameTooltip:SetOwner(this, this.dcTipAnchor)
            W.dcTipOwner = this
            this.dcTipBuilder(this)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function()
        if this.dcOldLeave then
            this.dcOldLeave()
        end
        if W.dcTipOwner == this then
            W.dcTipOwner = nil
        end
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
end
