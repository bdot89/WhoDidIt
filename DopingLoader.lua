--[[--------------------------------------------------------------------
	WhoDidIt - built-in DopingControl

	WhoDidIt carries its own copy of DopingControl, the raid consumables,
	class buffs, debuffs, resistances, hit and enchant checker by ShempError
	(MIT licence). It lives in the DopingControl\ folder and ships with
	WhoDidIt, at the commit in DopingControl\wdi_version.lua (from
	github.com/ShempError/DopingControl, its LICENSE kept). Its window opens
	from the Consumes tab ("Open DopingControl") or with /dc.

	tools\EmbedUpdate.ps1 (maintainer) makes small changes so it runs from inside WhoDidIt: its
	version comes from DopingControl\wdi_version.lua, its images are found
	in this folder, it starts on WhoDidIt's ADDON_LOADED, and each file
	starts with "if WDI_DOPING_SKIP then return end".

	If the separate DopingControl addon is switched on, it has already loaded
	by now (it's an optional dependency), so the built-in copy stands down
	and WhoDidIt asks once whether to switch the separate one off.
----------------------------------------------------------------------]]

WDI_DOPING_SKIP = IsAddOnLoaded("DopingControl") and true or nil

-- the version its options window shows
function WDI_DopingVersion()
	return WDI_DOPING_VERSION or ""
end

-- Both declare DopingControlDB (that's how settings move to the built-in
-- copy), so WhoDidIt's saved copy would replace the separate addon's table
-- while it's running. Give it its own table back once WhoDidIt has loaded.
local standaloneDB = WDI_DOPING_SKIP and DopingControlDB
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
	if event == "ADDON_LOADED" then
		if arg1 ~= "WhoDidIt" then return end
		if standaloneDB then DopingControlDB = standaloneDB end
		return
	end
	this:UnregisterAllEvents()
	-- only offer to switch it off when the built-in copy is really there
	if WDI_DOPING_SKIP and WDI_DOPING_VERSION and WhoDidIt.AskHandover then
		WhoDidIt:AskHandover("DopingControl", "DopingControl (Full check on the Consumes tab)")
	end
end)
