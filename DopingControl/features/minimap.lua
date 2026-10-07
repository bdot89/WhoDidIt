if WDI_DOPING_SKIP then return end -- DopingControl features/minimap.lua
-- Minimap button, standard hand-rolled 1.12 pattern:
-- LEFT click toggles the main window, RIGHT
-- click opens the options.
--
-- Design facts (in-game verified on 1.12):
-- - Hand-rolled, no LibDBIcon on 1.12.
-- - pfUI-safe: parent = Minimap, frame NAME contains "Minimap",
--   SetFrameStrata("HIGH") + SetFrameLevel(9) -- MEDIUM hides under pfUI.
--   /dc options stays as the fallback path.
-- - Border recipe (vanilla FrameXML MiniMapTrackingButton): 54px
--   MiniMap-TrackingBorder anchored TOPLEFT(0,0) on a 33px button. The
--   ring is deliberately off-centre within the texture -- do NOT centre it.
-- - Drag + click coexist: drag flag on OnDragStart/Stop, plain clicks
--   still fire OnClick.
-- - Radius = Minimap:GetWidth()/2 + 5 (follows resized minimaps).
--
-- Pure-Lua 5.0 dofile-loadable: all WoW wiring behind "if CreateFrame then";
-- BuildButton/PlaceButton only touch the WoW API when called at runtime.

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Minimap = DC_Minimap or {}

local button = nil
local function db() return DopingControlDB end

local function PlaceButton(angleDeg)
    if not button then return end
    local radius = (Minimap:GetWidth() / 2) + 5
    local rad = angleDeg * math.pi / 180
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function BuildButton()
    if button then return end
    local btn = CreateFrame("Button", "DopingControlMinimapButton", Minimap)
    btn:SetWidth(33); btn:SetHeight(33)
    btn:SetFrameStrata("HIGH"); btn:SetFrameLevel(9)

    local icon = btn:CreateTexture("DopingControlMinimapIcon", "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Potion_97")  -- the addon's fixed icon
    icon:SetWidth(20); icon:SetHeight(20)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- standard action-button crop

    local border = btn:CreateTexture("DopingControlMinimapBorder", "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(54); border:SetHeight(54)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    btn:SetScript("OnDragStart", function() this.isDragging = true end)
    btn:SetScript("OnDragStop", function() this.isDragging = false end)
    btn:SetScript("OnUpdate", function()
        if not this.isDragging then return end
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local angle = math.deg(math.atan2(cy - my, cx - mx))
        db().minimapAngle = angle          -- persist live while dragging
        PlaceButton(angle)
    end)

    -- LEFT = main window toggle (same as /dc), RIGHT = options.
    btn:SetScript("OnClick", function()
        if arg1 == "RightButton" then DC_Options.Toggle() else DC_Matrix.Toggle() end
    end)
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("DopingControl", 1, 1, 1)
        GameTooltip:AddLine("Left click: show / hide the window", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right click: options", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: move around the minimap", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button = btn
    PlaceButton(db().minimapAngle or 215)
end

-- Honours the "Show minimap button" checkbox (db.showMinimapButton);
-- ui/options.lua calls this after toggling the setting.
function DC_Minimap.Update()
    if not db().showMinimapButton then
        if button then button:Hide() end
        return
    end
    BuildButton()
    PlaceButton(db().minimapAngle or 215)
    button:Show()
end

-- Reload survival: build on ADDON_LOADED for
-- THIS addon (SavedVariables populated by then), then UnregisterEvent.
-- NEVER on PLAYER_ENTERING_WORLD (would re-run and leak textures).
if CreateFrame then
    local ev = CreateFrame("Frame", "DopingControlMinimapEventFrame", UIParent)
    ev:RegisterEvent("ADDON_LOADED")
    ev:SetScript("OnEvent", function()
        if event == "ADDON_LOADED" and arg1 == "WhoDidIt" then
            -- This handler fires BEFORE core/init.lua's (registration order
            -- follows TOC load order), so defaults may not be filled yet on a
            -- first-ever load. EnsureDefaults is idempotent -- run it here so
            -- showMinimapButton/minimapAngle are valid.
            DopingControlDB = DopingControlDB or {}
            DC.EnsureDefaults(DopingControlDB)
            DC_Minimap.Update()
            ev:UnregisterEvent("ADDON_LOADED")
        end
    end)
end
