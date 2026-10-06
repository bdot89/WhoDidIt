--[[--------------------------------------------------------------------
	WhoDidIt - built-in Chronicle logger

	WhoDidIt carries its own copy of ChronicleCompanion, the official
	logging addon for chronicleclassic.com (by Emyrk), so it doesn't need
	installing separately. The copy lives in the Chronicle\ folder and is
	downloaded - and kept up to date - from the official source
	(github.com/Emyrk/ChronicleCompanion) by tools\WhoDidIt-Sync. It isn't
	part of the WhoDidIt repository.

	The sync tool makes three small changes to Chronicle's files so they
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
