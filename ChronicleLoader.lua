--[[--------------------------------------------------------------------
	WhoDidIt - built-in Chronicle logger

	WhoDidIt carries its own copy of ChronicleCompanion, the official
	logging addon for chronicleclassic.com (by Emyrk), so it doesn't need
	installing separately. The copy lives in the Chronicle\ folder and
	ships with WhoDidIt, at the commit in Chronicle\wdi_version.lua (from
	github.com/Emyrk/ChronicleCompanion, credited in Chronicle\WDI_NOTICE.txt).
	It logs nothing until the player says yes (Logs.lua asks once).

	tools\EmbedUpdate.ps1 (maintainer) makes three small changes to Chronicle's files so they
	run from inside WhoDidIt: it starts them on WhoDidIt's ADDON_LOADED
	instead of ChronicleCompanion's, takes the version from
	Chronicle\wdi_version.lua instead of ChronicleCompanion.toc, and points
	the minimap icons at this folder. Each file also starts with
	"if WDI_CHRON_SKIP then return end".

	If the separate ChronicleCompanion addon is still installed and
	switched on, it has already loaded by now (it's an optional
	dependency), so the built-in copy stands down for this session instead
	of logging everything twice. Logs.lua then switches the separate addon
	off for the next session.
----------------------------------------------------------------------]]

-- Only a separate ChronicleCompanion that is actually running makes the
-- built-in copy stand down. One that's switched off (WhoDidIt's hand-over
-- switches it off) or deleted doesn't: the built-in copy is the logger then.
-- (It used to stay off as well, which left nobody logging: the WTF folder
-- still lists "ChronicleCompanion: disabled" after the hand-over or after
-- the folder is deleted.) Whether anything is logged is the player's own
-- yes / no (Logs.lua asks once), not this.
WDI_CHRON_SKIP = IsAddOnLoaded("ChronicleCompanion") and true or nil

-- Both declare Chronicle's saved variables; while the separate addon runs,
-- give it its own tables back once WhoDidIt's saved copies have loaded.
local standaloneDB, standaloneCharDB = WDI_CHRON_SKIP and ChronicleCompanionDB, WDI_CHRON_SKIP and ChronicleCompanionCharDB
local keepChron = CreateFrame("Frame")
keepChron:RegisterEvent("ADDON_LOADED")
keepChron:SetScript("OnEvent", function()
	if arg1 ~= "WhoDidIt" then return end
	this:UnregisterAllEvents()
	if standaloneDB then ChronicleCompanionDB = standaloneDB end
	if standaloneCharDB then ChronicleCompanionCharDB = standaloneCharDB end
end)

-- the version Chronicle writes into its log header and shows in /chronicle
function WDI_ChronVersion()
	return WDI_CHRON_VERSION or ""
end
