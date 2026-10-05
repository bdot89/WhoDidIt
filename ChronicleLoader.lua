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

-- the version Chronicle writes into its log header and shows in /chronicle
function WDI_ChronVersion()
	return WDI_CHRON_VERSION or ""
end
