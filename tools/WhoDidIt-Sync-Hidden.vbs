' WhoDidIt - the sync helper's launcher, run by the "WhoDidIt-Sync" scheduled task.
'
' On the maintainer's PC (tools\WhoDidIt-Sync.ps1 is there): starts the sync
' helper with no window.
'
' Anywhere else: the helper isn't part of the WhoDidIt download, so this is an
' older version's leftover task. It removes that task (and the old Startup
' shortcut) without a word, so nothing pops up again, and does nothing else.
' (The paths are worked out here at run time, so a folder name with an accent
' or umlaut is fine.)
Option Explicit
Dim fso, sh, helper, startupLink
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
helper = fso.BuildPath(fso.GetParentFolderName(WScript.ScriptFullName), "WhoDidIt-Sync.ps1")
If fso.FileExists(helper) Then
    sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & helper & """", 0, False
Else
    sh.Run "schtasks.exe /Delete /TN ""WhoDidIt-Sync"" /F", 0, True
    startupLink = fso.BuildPath(sh.SpecialFolders("Startup"), "WhoDidIt-Sync.lnk")
    If fso.FileExists(startupLink) Then fso.DeleteFile startupLink, True
End If