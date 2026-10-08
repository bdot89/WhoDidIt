--[[--------------------------------------------------------------------
	WhoDidIt - Chronicle log controls

	Drives the Chronicle logger (ChronicleCompanion, which writes the combat
	logs you upload to chronicleclassic.com) from the WhoDidIt window. It is
	built in (see ChronicleLoader.lua); the separate addon works too: start/stop
	logging, save, archive, delete and its auto-logging settings, plus two
	WhoDidIt extras - start logging on a boss pull and save after every
	boss fight. Uploading has to be done on the website: addons can't
	reach the internet.
----------------------------------------------------------------------]]

local W = WhoDidIt
local L = {}
W.Logs = L

L.savedLines = 0
L.lastSave = nil
L.history = {}   -- this session's saves, newest first: { time, lines, what }

function L:Available()
	return ChronicleLog ~= nil and ChronicleLog.Enable ~= nil and ChronicleLog.FlushToFile ~= nil
end

-- which logger is running: "builtin" (WhoDidIt's Chronicle\ copy),
-- "standalone" (the separate ChronicleCompanion addon) or nil
function L:Source()
	if not L:Available() then return nil end
	if not WDI_CHRON_SKIP and WDI_CHRON_VERSION then return "builtin" end
	return "standalone"
end

function L:Version()
	if L:Source() == "builtin" then return WDI_CHRON_VERSION end
	return GetAddOnMetadata("ChronicleCompanion", "Version")
end

function L:Enabled()
	return L:Available() and ChronicleLog:IsEnabled() and true or false
end

function L:File()
	if not L:Available() then return nil end
	return ChronicleLog:GetLogFilename()
end

function L:Unsaved()
	if not L:Available() then return 0 end
	return ChronicleLog:GetBufferSize() or 0
end

local function noted(n, what)
	if n and n > 0 then
		L.savedLines = L.savedLines + n
		L.lastSave = date("%H:%M:%S")
		tinsert(L.history, 1, { L.lastSave, n, what or "Saved" })
	end
end

-- the built-in copy logs only once the player has said yes (asked the first
-- time they enter a raid); the separate addon is the player's own choice
local AUTO = { autoEnableInRaid = true, autoEnableInDungeon = true, showLogReminder = true }
function L:Allowed()
	return L:Source() ~= "builtin" or WhoDidItDB.opts.chronUse == true
end
local function quiet()
	if not (L:Available() and L:Source() == "builtin") then return end
	for k in pairs(AUTO) do ChronicleLog:SetSetting(k, false) end
	if ChronicleLog:IsEnabled() then ChronicleLog:Disable() end
end
function L:Use(on)
	WhoDidItDB.opts.chronUse = on and true or false
	if not L:Available() then return end
	if on then
		for k, v in pairs(AUTO) do ChronicleLog:SetSetting(k, v) end
	else
		quiet()
	end
end

W:On("ADDON_LOADED", function(name)
	if name ~= "WhoDidIt" then return end
	if WhoDidItDB.opts.chronUse ~= true then quiet() end
end)

StaticPopupDialogs["WHODIDIT_CHRONLOG"] = {
	text = "WhoDidIt has Chronicle's logger built in. It records your raids to a log file that you can upload to chronicleclassic.com (for the Rankings and your guild's logs).\n\nLog your raids?",
	button1 = "Yes, log them", button2 = "No",
	OnAccept = function()
		L:Use(true)
		L:Start()
		W.Print("Chronicle logging is |cff33ff33on|r: it starts by itself in raids. The Logging tab has the details and switches.")
	end,
	OnCancel = function()
		L:Use(false)
		W.Print("Chronicle logging stays |cffff5555off|r. Switch it on any time on the Logging tab.")
	end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
}
local askedLog
local function askLog()
	if askedLog or not WhoDidItDB or WhoDidItDB.opts.chronUse ~= nil or L:Source() ~= "builtin" then return end
	local inInst, typ = IsInInstance()
	if not inInst or typ ~= "raid" then return end
	askedLog = true
	StaticPopup_Show("WHODIDIT_CHRONLOG")
end
W:On("ZONE_CHANGED_NEW_AREA", askLog)
W:On("PLAYER_ENTERING_WORLD", askLog)

function L:Start()
	if not L:Available() then return end
	-- starting it by hand is a yes
	if L:Source() == "builtin" and WhoDidItDB.opts.chronUse ~= true then L:Use(true) end
	if not ChronicleLog:IsEnabled() then
		ChronicleLog:Enable()
		W.Print("Chronicle logging |cff33ff33started|r.")
	end
end

function L:Stop()
	if not L:Available() or not ChronicleLog:IsEnabled() then return end
	local n = ChronicleLog:Disable() or 0
	noted(n, "Stopped & saved")
	W.Print("Chronicle logging |cffff5555stopped|r - saved " .. n .. " lines to " .. (L:File() or "?") .. ".")
end

function L:Save(quiet)
	if not L:Available() then return 0 end
	local n = ChronicleLog:FlushToFile() or 0
	noted(n, quiet and "Auto-saved" or "Saved")
	if not quiet then
		W.Print(n > 0 and ("Saved " .. n .. " lines to " .. (L:File() or "?") .. ".") or "Nothing new to save.")
	end
	return n
end

function L:Archive()
	if not L:Available() or not ChronicleLog.ArchiveLogs then return end
	L:Save(true)
	ChronicleLog:ArchiveLogs("backup")
end

-- Chronicle's own "are you sure" popup
function L:Delete()
	if not L:Available() then return end
	if StaticPopupDialogs["CHRONICLELOG_CLEAR_CONFIRM"] then
		StaticPopup_Show("CHRONICLELOG_CLEAR_CONFIRM")
	else
		ChronicleLog:DeleteLogs()
	end
end

function L:Setting(key)
	if not L:Available() then return nil end
	return ChronicleLog:GetSetting(key)
end

function L:ToggleSetting(key)
	if not L:Available() then return end
	ChronicleLog:SetSetting(key, not ChronicleLog:GetSetting(key))
end

------------------------------------------------------------------ hand-over from the separate addon

-- The separate ChronicleCompanion is still switched on next to the built-in
-- copy: it keeps logging this session (the built-in one stood down) and is
-- switched off from the next /reload. Both declare Chronicle's saved
-- variables, so its settings are saved with WhoDidIt's on the way out.
local handedOver
W:On("PLAYER_ENTERING_WORLD", function()
	if handedOver or not (WDI_CHRON_SKIP and WDI_CHRON_VERSION) or not IsAddOnLoaded("ChronicleCompanion") then return end
	handedOver = true
	W:AskHandover("ChronicleCompanion", "the Chronicle logger (v" .. WDI_CHRON_VERSION .. ", the Logging tab)")
end)

------------------------------------------------------------------ hooks from the tracker

-- a boss was pulled
function L:OnFightStart()
	if WhoDidItDB.opts.chronStartOnPull and L:Available() and L:Allowed() and not ChronicleLog:IsEnabled() then
		ChronicleLog:Enable()
		W.Print("Chronicle logging |cff33ff33started|r for the pull.")
	end
end

-- a boss fight ended (rec = the saved report)
function L:OnFightEnd(rec)
	if WhoDidItDB.opts.chronSaveOnFight and L:Enabled() and not rec.demo then
		L:Save(true)
	end
end
