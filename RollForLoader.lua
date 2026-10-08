--[[--------------------------------------------------------------------
	WhoDidIt - built-in RollFor

	WhoDidIt carries its own copy of RollFor, the master-loot roller by
	Obszczymucha - sica42's 1.12 fork, the newest version that still runs
	on the 1.12 client (the original moved to TBC only). It lives in the
	RollFor\ folder and ships with WhoDidIt, at the commit in
	RollFor\wdi_version.lua (from github.com/sica42/roll-for-vanilla,
	credited in RollFor\WDI_NOTICE.txt). The Loot tab (Loot.lua) explains
	and drives it.

	tools\EmbedUpdate.ps1 (maintainer) makes small changes so RollFor runs from inside WhoDidIt:
	its version comes from RollFor\wdi_version.lua, its images are found in
	this folder, its library .xml lists are expanded into WhoDidIt.toc, and
	each file starts with "if WDI_ROLLFOR_SKIP then return end".

	If the separate RollFor addon is still switched on, it has already
	loaded by now (it's an optional dependency), so the built-in copy
	stands down for this session; Loot.lua switches the separate addon off
	for the next one.
----------------------------------------------------------------------]]

WDI_ROLLFOR_SKIP = IsAddOnLoaded("RollFor") and true or nil

-- Both declare RollFor's saved variables (so its settings, soft-res and
-- winners move to the built-in copy). While the separate RollFor runs, give
-- it its own tables back once WhoDidIt's saved copies have loaded over them.
local standaloneDb, standaloneCharDb = WDI_ROLLFOR_SKIP and RollForDb, WDI_ROLLFOR_SKIP and RollForCharDb
local keep = CreateFrame("Frame")
keep:RegisterEvent("ADDON_LOADED")
keep:SetScript("OnEvent", function()
	if arg1 ~= "WhoDidIt" then return end
	this:UnregisterAllEvents()
	-- Switched off in WhoDidIt (RollForML tab, or /wdi rollfor off), e.g. because it
	-- clashes with an EPGP loot addon: RollFor starts on PLAYER_LOGIN, which comes after
	-- this, so it never starts - no loot window of its own, no events, no /rf, no
	-- minimap button. The game's loot window stays as it is.
	local o = WhoDidItDB and WhoDidItDB.opts
	WDI_ROLLFOR_OFF = (not WDI_ROLLFOR_SKIP and o and o.rollforOff) and true or nil
	if WDI_ROLLFOR_OFF and RollForFrame then RollForFrame:UnregisterAllEvents() end
	-- In a raid, RollFor's announcements in raid chat are for the raid leader,
	-- assistants and the master looter, like everything WhoDidIt posts; anyone
	-- else sees them in their own chat. (RollFor builds its chat at login, after
	-- this, so its own files stay as they are.)
	if not WDI_ROLLFOR_SKIP and RollFor and RollFor.ChatApi and RollFor.ChatApi.new then
		local newApi = RollFor.ChatApi.new
		RollFor.ChatApi.new = function()
			local api = newApi()
			local send = api.SendChatMessage
			api.SendChatMessage = function(text, kind, lang, target)
				local W = WhoDidIt
				if (kind == "RAID" or kind == "RAID_WARNING") and W and W.CanLead and not W.CanLead() then
					local how, _, raidMaster = GetLootMethod()
					if not (how == "master" and raidMaster and GetRaidRosterInfo(raidMaster) == UnitName("player")) then
						W.LeadOnly()
						DEFAULT_CHAT_FRAME:AddMessage(tostring(text))
						return
					end
				end
				return send(text, kind, lang, target)
			end
			return api
		end
	end
	if standaloneDb then RollForDb = standaloneDb end
	if standaloneCharDb then RollForCharDb = standaloneCharDb end
end)

-- the version RollFor reports (and compares with other raiders' copies)
function WDI_RollForVersion()
	return WDI_ROLLFOR_VERSION or ""
end
