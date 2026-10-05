--[[--------------------------------------------------------------------
	WhoDidIt - Chronicle log controls

	Drives the ChronicleCompanion addon (which writes the combat logs you
	upload to chronicleclassic.com) from the WhoDidIt window: start/stop
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

function L:Start()
	if not L:Available() then return end
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

------------------------------------------------------------------ hooks from the tracker

-- a boss was pulled
function L:OnFightStart()
	if WhoDidItDB.opts.chronStartOnPull and L:Available() and not ChronicleLog:IsEnabled() then
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
