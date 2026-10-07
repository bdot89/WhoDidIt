if WDI_DOPING_SKIP then return end -- DopingControl scan/gear.lua
-- Equipment + enchant reading for one unit: GetInventoryItemLink for the 16
-- equipment-tab slots (DC.SLOTS_EQUIPMENT), enchant id parsed from the item
-- link ("item:ID:ENCHANT:..."), item details via GetItemInfo with the
-- MEASURED Turtle 1.18.1 return order
-- : 1 name, 2 link, 3 QUALITY, 4 reqLevel, 5 itemType,
-- 6 ITEMSUBTYPE, 7 maxStack, 8 equipSlot, 9 ICONPATH, 10 vendorPrice.
-- Reading position 4 as itemLevel or 10 as texture breaks SILENTLY with
-- plausible-looking values -- do not "fix" this back to the vanilla order.
--
-- Readability rule (binding):
--   ANY slot returned a link  => gearRead = true; slots with nil => "EMPTY"
--   ALL 13 slots returned nil => gearRead = false (failed read, NOT naked)
-- A link that came back but does not parse leaves its slot nil while
-- gearRead stays true -- core/model.lua shows that cell as UNKNOWN
-- ("no data"), never as MISSING (resolution: a parse anomaly must not be
-- claimed as "no item").
--
-- Pure Lua 5.0, dofile-loadable offline: ParseLink / ParseLinkName /
-- ParseWeaponEnchantLine / Assemble are pure (offline-tested);
-- ReadUnit, ItemInfo and ReadSelfWeaponEnchantName
-- touch the WoW API and run in-game only, pcall-wrapped.

DopingControl = DopingControl or {}
local DC = DopingControl

DC_Gear = DC_Gear or {}
local G = DC_Gear

-- Fallback inventory-slot list (= invSlot column of DC.SLOTS_EQUIPMENT,
-- data/enchants.lua) so this file works standalone in tests.
local FALLBACK_INV_SLOTS = { 1, 2, 3, 15, 5, 6, 9, 10, 7, 8, 16, 17, 18, 11, 12, 13, 14 }

-- InvSlots() -> array of the 17 inventory slot numbers, in column order.
-- Prefers DC.SLOTS_EQUIPMENT (single source of truth once data/ is loaded).
function G.InvSlots()
    if DC.SLOTS_EQUIPMENT then
        local out = {}
        local n = table.getn(DC.SLOTS_EQUIPMENT)
        for i = 1, n do
            table.insert(out, DC.SLOTS_EQUIPMENT[i].invSlot)
        end
        return out
    end
    return FALLBACK_INV_SLOTS
end

-- ==================================================================
-- Pure part
-- ==================================================================

-- ParseLink(link) -> itemId, enchantId (numbers) | nil, nil on malformed.
-- Enchant id is the 2nd field of the link payload (standard 1.12 link
-- pattern, widened to also capture the item id).
function G.ParseLink(link)
    if type(link) ~= "string" then
        return nil, nil
    end
    local _, _, idStr, enchStr = string.find(link, "item:(%d+):(%d+)")
    if not idStr then
        return nil, nil
    end
    return tonumber(idStr), tonumber(enchStr)
end

-- ParseLinkName(link) -> "[bracket] name" | nil (fallback when GetItemInfo
-- has no cached data yet; standard 1.12 pattern).
function G.ParseLinkName(link)
    if type(link) ~= "string" then
        return nil
    end
    local _, _, name = string.find(link, "%[(.+)%]")
    return name
end

-- ParseWeaponEnchantLine(text) -> name|nil (pure).
-- The main-hand tooltip's temporary-enchant line reads "<Name> (N min)" on
-- the English client (e.g. "Dense Sharpening Stone (28 min)") -- strip the
-- "(N min)" part, keep the name. Any other line (item name, "Speed 2.70",
-- "+9 Damage", a bare "(28 min)") and any non-string input -> nil.
function G.ParseWeaponEnchantLine(text)
    if type(text) ~= "string" then
        return nil
    end
    local _, _, name = string.find(text, "^(.-)%s*%((%d+) min%)%s*$")
    if name and name ~= "" then
        return name
    end
    return nil
end

-- Assemble(rawLinks, slots, itemInfo) -> gear, gearRead
--   rawLinks : { [invSlot] = link string | nil }
--   slots    : array of invSlot numbers (default G.InvSlots())
--   itemInfo : nil, or function(itemId) -> name, quality, subType, texture
--              (already de-shifted; in-game wrapper is G.ItemInfo, tests
--              pass a stub)
-- Returns the store shape:
--   gearRead = false => gear = nil
--   gearRead = true  => gear[invSlot] = { id, enchant, quality, subType,
--                        texture, name } | "EMPTY" (no link) | nil
--                        (link present but unparseable -> UNKNOWN cell)
-- The subType field feeds DC.ENCH_EXEMPT in core/model.lua (wand/holdable
-- exemptions); the model explicitly expects it.
function G.Assemble(rawLinks, slots, itemInfo)
    rawLinks = rawLinks or {}
    slots = slots or G.InvSlots()
    local n = table.getn(slots)

    local gear = {}
    local any = false
    for i = 1, n do
        local inv = slots[i]
        local link = rawLinks[inv]
        if link ~= nil then
            any = true
            local id, ench = G.ParseLink(link)
            if id then
                local entry = { id = id, enchant = ench }
                if itemInfo then
                    local name, quality, subType, texture = itemInfo(id)
                    entry.name = name
                    entry.quality = quality
                    entry.subType = subType
                    entry.texture = texture
                end
                if not entry.name then
                    entry.name = G.ParseLinkName(link)
                end
                gear[inv] = entry
            end
            -- unparseable link: slot stays nil (UNKNOWN), see header
        end
    end

    if not any then
        return nil, false
    end
    for i = 1, n do
        local inv = slots[i]
        if rawLinks[inv] == nil then
            gear[inv] = "EMPTY"
        end
    end
    return gear, true
end

-- ==================================================================
-- WoW part (runtime only; every foreign-unit call pcall-wrapped)
-- ==================================================================

-- ItemInfo(itemId) -> name, quality, subType, texture | nil (uncached/err).
-- De-shifts the Turtle 1.18.1 GetItemInfo order (see header).
function G.ItemInfo(itemId)
    if not GetItemInfo then
        return nil
    end
    local ok, name, link, quality, reqLevel, itemType, subType,
        maxStack, equipSlot, iconPath = pcall(GetItemInfo, itemId)
    if not ok or not name then
        return nil
    end
    return name, quality, subType, iconPath
end

-- ReadSelfWeaponEnchantName() -> name|nil (WoW runtime only).
-- Self path for store.weaponMainName: GetWeaponEnchantInfo() carries
-- no NAME for the own unit, but the equipped main hand's tooltip lists the
-- temp enchant as its own "<Name> (N min)" line (English client). Scans
-- the shared hidden tooltip (scan/aura.lua accessor -- never a second
-- frame under the same global name) over SetInventoryItem("player", 16)
-- and returns the first line that parses; nil-safe when no such line.
function G.ReadSelfWeaponEnchantName()
    local tip = DC_Aura and DC_Aura.GetScanTip and DC_Aura.GetScanTip()
    if not tip then
        return nil
    end
    local ok = pcall(function()
        tip:ClearLines()
        tip:SetInventoryItem("player", 16)
    end)
    if not ok then
        return nil
    end
    local n = 30
    if tip.NumLines then
        local ok2, v = pcall(tip.NumLines, tip)
        if ok2 and type(v) == "number" then
            n = v
        end
    end
    for i = 1, n do
        local obj = getglobal("DopingControlScanTipTextLeft" .. i)
        if obj then
            local name = G.ParseWeaponEnchantLine(obj:GetText())
            if name then
                return name
            end
        end
    end
    return nil
end

-- ReadUnit(unit) -> rawLinks table for G.Assemble.
-- Vanilla serves GetInventoryItemLink only for the own/inspected unit;
-- SuperWoW serves it for all friendly units (unverified beyond sight,
-- probe questions 4/5) -- either way nil slots are handled by the
-- EMPTY-vs-gearRead rule above, so no capability branching here.
function G.ReadUnit(unit)
    local raw = {}
    if GetInventoryItemLink then
        local slots = G.InvSlots()
        local n = table.getn(slots)
        for i = 1, n do
            local ok, link = pcall(GetInventoryItemLink, unit, slots[i])
            if ok and link then
                raw[slots[i]] = link
            end
        end
    end
    return raw
end
