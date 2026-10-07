<#
    AutoSync - run WhoDidIt's sync helper in the background, starting with Windows.

    For anyone happy to have the helper (WhoDidIt-Sync.ps1) running: it starts
    with no window every time you log into Windows, so new Chronicle raid times
    keep arriving (every 10 minutes, or straight away with Sync now on
    WhoDidIt's Rankings tab) without you opening anything. The Rankings bar in
    game shows what it's doing.

    It adds one scheduled task for your Windows user ("WhoDidIt-Sync", no admin
    rights needed), plus a tiny launcher script next to this file
    (WhoDidIt-Sync-Hidden.vbs) that starts the helper without a window. The
    task starts the helper when you log into Windows, when you unlock the PC
    (also after sleep), and every 15 minutes in case it stopped; the helper
    only ever runs once, so a start while it's running just ends. Nothing
    else changes. (Older versions used a Startup folder shortcut instead;
    it's removed.)

    -Minimised keeps the old way: a Startup shortcut with a minimised window.

    Usage (or double-click AutoSync-On.cmd / AutoSync-Off.cmd):
      AutoSync.ps1              start it with Windows, in the background, and start it now
      AutoSync.ps1 -Minimised   the same, but with a minimised window on the taskbar
      AutoSync.ps1 -Off         stop it starting with Windows, and stop it now
#>
param([switch]$Off, [switch]$Minimised)

$taskName = "WhoDidIt-Sync"
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
    $had = $false
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        $had = $true
    }
    if (Test-Path -LiteralPath $link) {
        Remove-Item -LiteralPath $link -Force
        $had = $true
    }
    if ($had) { Write-Host "Done: the WhoDidIt sync helper no longer starts by itself." }
    else { Write-Host "It wasn't set to start by itself." }
    if (Test-Path -LiteralPath $vbs) { Remove-Item -LiteralPath $vbs -Force }
    $running = @(Get-Helper)
    foreach ($p in $running) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($running.Count -gt 0) { Write-Host "Stopped the helper that was running." }
    return
}

if (-not $Minimised) {
    # the hidden launcher, run by a scheduled task (log on, unlock, every 15 minutes)
    $line = "CreateObject(""WScript.Shell"").Run ""powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """"$script"""""", 0, False"
    $vb = "' Starts WhoDidIt's sync helper with no window (written by AutoSync.ps1).`r`n" + $line + "`r`n"
    # UTF-16 with a BOM, which wscript reads: a folder name with an accent or umlaut stays intact
    [IO.File]::WriteAllText($vbs, $vb, [Text.Encoding]::Unicode)

    $me = "$env:USERDOMAIN\$env:USERNAME"
    $action = New-ScheduledTaskAction -Execute $wscript -Argument "`"$vbs`"" -WorkingDirectory $PSScriptRoot
    $logon = New-ScheduledTaskTrigger -AtLogOn -User $me
    $every = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration (New-TimeSpan -Days 3650)
    $cls = Get-CimClass -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_TaskSessionStateChangeTrigger
    $unlock = New-CimInstance -CimClass $cls -ClientOnly
    $unlock.StateChange = 8   # unlocking the PC (also after sleep)
    $unlock.UserId = $me
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($logon, $unlock, $every) -Settings $settings `
        -Principal $principal -Description "WhoDidIt: keeps the sync helper running (Chronicle raid times for the Rankings tab). Remove with AutoSync-Off.cmd." -Force | Out-Null
    # the old way (a Startup shortcut) isn't needed any more
    if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Force }
    Write-Host "Done: the WhoDidIt sync helper now runs in the background (no window), starting when you log into"
    Write-Host "Windows, when you unlock the PC, and every 15 minutes if it ever stopped."
    Write-Host "Its progress shows on WhoDidIt's Rankings tab. To undo: double-click AutoSync-Off.cmd."
    if (@(Get-Helper).Count -gt 0) {
        Write-Host "The helper is already running."
    } else {
        Start-ScheduledTask -TaskName $taskName
        Write-Host "Started it now, in the background."
        Start-Sleep -Seconds 6
        if (@(Get-Helper).Count -eq 0) {
            Write-Host "But the helper isn't running. Try double-clicking WhoDidIt-Sync.cmd to see why." -ForegroundColor Yellow
        }
    }
    return
}

# -Minimised: the old way, a Startup shortcut with a minimised window
$shell = New-Object -ComObject WScript.Shell
$sc = $shell.CreateShortcut($link)
$sc.TargetPath = $ps
$sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$script`""
$sc.WindowStyle = 7
$sc.WorkingDirectory = $PSScriptRoot
$sc.Description = "WhoDidIt: fetch Chronicle raid times for the Rankings tab"
$sc.Save()
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
Write-Host "Done: the WhoDidIt sync helper now starts with Windows (minimised)."
Write-Host "Its progress shows on WhoDidIt's Rankings tab. To undo: double-click AutoSync-Off.cmd."
if (@(Get-Helper).Count -gt 0) {
    Write-Host "The helper is already running."
} else {
    Start-Process -FilePath $ps -ArgumentList $sc.Arguments -WorkingDirectory $PSScriptRoot -WindowStyle Minimized
    Write-Host "Started it now (minimised on your taskbar)."
}