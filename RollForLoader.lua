--[[--------------------------------------------------------------------
	WhoDidIt - built-in RollFor

	WhoDidIt carries its own copy of RollFor, the master-loot roller by
	Obszczymucha - sica42's 1.12 fork, the newest version that still runs
	on the 1.12 client (the original moved to TBC only). It lives in the
	RollFor\ folder and is downloaded and kept up to date from
	github.com/sica42/roll-for-vanilla by tools\WhoDidIt-Sync; it isn't part
	of the WhoDidIt repository. The Loot tab (Loot.lua) explains and drives it.

	The sync tool makes small changes so RollFor runs from inside WhoDidIt:
	its version comes from RollFor\wdi_version.lua, its images are found in
	this folder, its library .xml lists are expanded into WhoDidIt.toc, and
	each file starts with "if WDI_ROLLFOR_SKIP then return end".

	If the separate RollFor addon is still switched on, it has already
	loaded by now (it's an optional dependency), so the built-in copy
	stands down for this session; Loot.lua switches the separate addon off
	for the next one.
----------------------------------------------------------------------]]

WDI_ROLLFOR_SKIP = IsAddOnLoaded("RollFor") and true or nil

-- the version RollFor reports (and compares with other raiders' copies)
function WDI_RollForVersion()
	return WDI_ROLLFOR_VERSION or ""
end
