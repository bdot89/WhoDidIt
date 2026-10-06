<#
    AutoSync - start WhoDidIt's sync helper automatically with Windows.

    For anyone happy to have the helper (WhoDidIt-Sync.ps1) running: it then
    starts minimised every time you log into Windows, so new Chronicle raid
    times keep arriving (every 10 minutes, or straight away with Sync now on
    WhoDidIt's Rankings tab) without you thinking about it. If you're the
    master (/wdi master on), everyone on your realm gets them from you.

    It only adds a shortcut to your Windows Startup folder - nothing else
    changes, and you can see it there:
      %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\WhoDidIt-Sync.lnk

    Usage (or double-click AutoSync-On.cmd / AutoSync-Off.cmd):
      AutoSync.ps1          add the shortcut and start the helper now
      AutoSync.ps1 -Off     remove the shortcut (and stop it starting)
#>
param([switch]$Off)

$startup = [Environment]::GetFolderPath("Startup")
$link = Join-Path $startup "WhoDidIt-Sync.lnk"
$script = Join-Path $PSScriptRoot "WhoDidIt-Sync.ps1"
$ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$script`""

if ($Off) {
    if (Test-Path -LiteralPath $link) {
        Remove-Item -LiteralPath $link -Force
        Write-Host "Done: the WhoDidIt sync helper no longer starts with Windows."
        Write-Host "(If its window is open now, close it to stop it.)"
    } else {
        Write-Host "It wasn't set to start with Windows - nothing to do."
    }
    return
}

$shell = New-Object -ComObject WScript.Shell
$sc = $shell.CreateShortcut($link)
$sc.TargetPath = $ps
$sc.Arguments = $psArgs
$sc.WorkingDirectory = $PSScriptRoot
$sc.WindowStyle = 7   # minimised
$sc.Description = "WhoDidIt: fetch Chronicle raid times for the Rankings tab"
$sc.Save()
Write-Host "Done: the WhoDidIt sync helper now starts (minimised) when you log into Windows."
Write-Host "Shortcut: $link"
Write-Host "To undo: double-click AutoSync-Off.cmd."

# start it now too, unless it's already running
$running = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*WhoDidIt-Sync.ps1*" }
if ($running) {
    Write-Host "The helper is already running."
} else {
    Start-Process -FilePath $ps -ArgumentList $psArgs -WorkingDirectory $PSScriptRoot -WindowStyle Minimized
    Write-Host "Started it now (minimised on your taskbar)."
}
