<#
    AutoSync - run WhoDidIt's sync helper in the background, starting with Windows.

    For anyone happy to have the helper (WhoDidIt-Sync.ps1) running: it starts
    with no window every time you log into Windows, so new Chronicle raid times
    keep arriving (every 10 minutes, or straight away with Sync now on
    WhoDidIt's Rankings tab) without you opening anything. The Rankings bar in
    game shows what it's doing.

    It adds one shortcut to your Windows Startup folder, plus a tiny launcher
    script next to this file (WhoDidIt-Sync-Hidden.vbs) that starts the helper
    without a window. Nothing else changes.
      %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\WhoDidIt-Sync.lnk

    Usage (or double-click AutoSync-On.cmd / AutoSync-Off.cmd):
      AutoSync.ps1              start it with Windows, in the background, and start it now
      AutoSync.ps1 -Minimised   the same, but with a minimised window on the taskbar
      AutoSync.ps1 -Off         stop it starting with Windows, and stop it now
#>
param([switch]$Off, [switch]$Minimised)

$startup = [Environment]::GetFolderPath("Startup")
$link = Join-Path $startup "WhoDidIt-Sync.lnk"
$script = Join-Path $PSScriptRoot "WhoDidIt-Sync.ps1"
$vbs = Join-Path $PSScriptRoot "WhoDidIt-Sync-Hidden.vbs"
$ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$wscript = Join-Path $env:SystemRoot "System32\wscript.exe"

function Get-Helper {
    @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*WhoDidIt-Sync.ps1*" })
}

if ($Off) {
    if (Test-Path -LiteralPath $link) {
        Remove-Item -LiteralPath $link -Force
        Write-Host "Done: the WhoDidIt sync helper no longer starts with Windows."
    } else {
        Write-Host "It wasn't set to start with Windows."
    }
    if (Test-Path -LiteralPath $vbs) { Remove-Item -LiteralPath $vbs -Force }
    $running = Get-Helper
    foreach ($p in $running) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($running.Count -gt 0) { Write-Host "Stopped the helper that was running." }
    return
}

$shell = New-Object -ComObject WScript.Shell
$sc = $shell.CreateShortcut($link)
if ($Minimised) {
    $psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$script`""
    $sc.TargetPath = $ps
    $sc.Arguments = $psArgs
    $sc.WindowStyle = 7
} else {
    # wscript runs the helper with no window at all (PowerShell alone would flash one)
    $line = "CreateObject(""WScript.Shell"").Run ""powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """"$script"""""", 0, False"
    $vb = "' Starts WhoDidIt's sync helper with no window (written by AutoSync.ps1).`r`n" + $line + "`r`n"
    # UTF-16 with a BOM, which wscript reads: a folder name with an accent or umlaut stays intact
    [IO.File]::WriteAllText($vbs, $vb, [Text.Encoding]::Unicode)
    $sc.TargetPath = $wscript
    $sc.Arguments = "`"$vbs`""
}
$sc.WorkingDirectory = $PSScriptRoot
$sc.Description = "WhoDidIt: fetch Chronicle raid times for the Rankings tab"
$sc.Save()
Write-Host ("Done: the WhoDidIt sync helper now starts with Windows" + $(if ($Minimised) { " (minimised)." } else { ", in the background (no window)." }))
Write-Host "Its progress shows on WhoDidIt's Rankings tab. To undo: double-click AutoSync-Off.cmd."

# start it now too, unless it's already running
if ((Get-Helper).Count -gt 0) {
    Write-Host "The helper is already running."
} elseif ($Minimised) {
    Start-Process -FilePath $ps -ArgumentList $sc.Arguments -WorkingDirectory $PSScriptRoot -WindowStyle Minimized
    Write-Host "Started it now (minimised on your taskbar)."
} else {
    Start-Process -FilePath $wscript -ArgumentList "`"$vbs`"" -WorkingDirectory $PSScriptRoot
    Write-Host "Started it now, in the background."
}

# check it really runs (a hidden helper that fails says nothing otherwise)
if ((Get-Helper).Count -eq 0) {
    Start-Sleep -Seconds 4
    if ((Get-Helper).Count -eq 0) {
        Write-Host "But the helper isn't running. Try double-clicking WhoDidIt-Sync.cmd to see why." -ForegroundColor Yellow
    }
}
