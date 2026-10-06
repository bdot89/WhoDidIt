--[[--------------------------------------------------------------------
	WhoDidIt - built-in DopingControl

	WhoDidIt carries its own copy of DopingControl, the raid consumables,
	class buffs, debuffs, resistances, hit and enchant checker by ShempError
	(MIT licence). It lives in the DopingControl\ folder and is downloaded
	and kept up to date from github.com/ShempError/DopingControl by
	tools\WhoDidIt-Sync; it isn't part of the WhoDidIt repository. Its
	window opens from the Consumes tab ("Full check") or with /dc.

	The sync tool makes small changes so it runs from inside WhoDidIt: its
	version comes from DopingControl\wdi_version.lua, its images are found
	in this folder, it starts on WhoDidIt's ADDON_LOADED, and each file
	starts with "if WDI_DOPING_SKIP then return end".

	If the separate DopingControl addon is still switched on, it has already
	loaded by now (it's an optional dependency), so the built-in copy stands
	down for this session and the separate one is switched off for the next.
----------------------------------------------------------------------]]

WDI_DOPING_SKIP = IsAddOnLoaded("DopingControl") and true or nil

-- the version its options window shows
function WDI_DopingVersion()
	return WDI_DOPING_VERSION or ""
end

if WDI_DOPING_SKIP then
	DisableAddOn("DopingControl")
	local f = CreateFrame("Frame")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
	f:SetScript("OnEvent", function()
		this:UnregisterAllEvents()
		DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Who|cffffd100DidIt|r: DopingControl is now built into WhoDidIt, so the separate addon has been switched off for your next login (your settings carry over). Once you've logged in on each character, you can delete Interface\\AddOns\\DopingControl.")
	end)
end
