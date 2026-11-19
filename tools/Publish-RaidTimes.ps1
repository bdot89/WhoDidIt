<#
    Publish-RaidTimes - for the WhoDidIt maintainer: puts every guild's raid
    times into the download, so a fresh install shows full Rankings at once
    (even while the master is offline) and the master feed only has to send
    what's newer.

    It reads the sync helper's file (CustomData\WhoDidIt_Chronicle.txt),
    keeps the guilds' kill and clear times (C / K, and C2 / K2 since the raid
    scaling change) and the raid details (L), leaves out your own characters'
    personal bests (PC / PK), adds the 5-man runs your WhoDidIt saved
    (CustomData\WhoDidIt_Runs.txt, R5 lines, with the members' names; a run
    someone in the group opted out of is never on your boards), writes
    RaidTimes.lua and commits and pushes it.
    Needs git with push access to the repository.

    The sync helper runs it daily (-Auto): the older the snapshot, the more
    the feed has to send a fresh install.
      Publish-RaidTimes.ps1             write, commit and push
      Publish-RaidTimes.ps1 -NoPush     only write RaidTimes.lua
      Publish-RaidTimes.ps1 -Force      publish even if it looks much smaller
      Publish-RaidTimes.ps1 -Auto       (the sync helper, daily) skip unless main has nothing
                                        unpushed of yours - it never pushes your own commits
#>
param([switch]$NoPush, [switch]$Force, [switch]$Auto)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$wow = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$src = Join-Path $wow "CustomData\WhoDidIt_Chronicle.txt"
$dst = Join-Path $repo "RaidTimes.lua"

if (-not (Test-Path -LiteralPath $src)) {
    Write-Host "Nothing to publish: the sync helper hasn't written $src yet."
    return
}
$lines = ([IO.File]::ReadAllText($src) -replace "`r`n", "`n") -split "`n"
$head = $lines[0] -split '\|'
if ($head[0] -ne "WDICHRON" -or $head[5] -ne "ok") { throw "The helper's file isn't a finished sync (header: $($lines[0])) - try again after its next sync." }
$synced = [long]$head[2]
$server = $head[3]

# only these kinds of line, and each one plain text (it goes inside a Lua [[ ]] string)
$keep = New-Object System.Collections.Generic.List[string]
$counts = @{}
foreach ($l in $lines) {
    $t = ($l -split '\|')[0]
    if ($t -notin "C", "K", "C2", "K2", "L") { continue }
    if ($l -match '\[\[|\]\]|[\x00-\x08\x0b-\x1f]') { throw "A line can't be stored safely, not publishing: $l" }
    $keep.Add($l)
    $counts[$t] = 1 + [int]$counts[$t]
}
# 5-man runs: your WhoDidIt writes
#   R5|realm|key|group|secs|date|deaths|faction|members|splits|named|ok
# Every one is published, members' names included (the maintainer's choice, 1 Nov 2026:
# times should spread to every realm). ok (the members seen sharing it) isn't needed any
# more. A run someone in the group opted out of (/wdi 5man off) is never written. Published
# as the first 11 fields, as WhoDidIt reads them.
$runsFile = Join-Path $wow "CustomData\WhoDidIt_Runs.txt"
if (Test-Path -LiteralPath $runsFile) {
    foreach ($l in (([IO.File]::ReadAllText($runsFile) -replace "`r`n", "`n") -split "`n")) {
        $p = $l -split '\|'
        if ($p[0] -ne "R5" -or ($p.Count -ne 11 -and $p.Count -ne 12)) { continue }
        if ($l -match '\[\[|\]\]|[\x00-\x1f]' -or $p[4] -notmatch '^\d+$' -or $p[5] -notmatch '^\d+$') { continue }   # (WhoDidIt checks the rest when it loads them)
        if ($p[8] -eq "") { continue }
        $keep.Add(($p[0..10] -join '|'))
        $counts["R5"] = 1 + [int]$counts["R5"]
    }
    # withdrawn 5-man runs (a member took a wrong time off the boards; WhoDidIt doesn't write
    # the run itself any more): W5|realm|key|secs|names|ok, published as the first 5 fields,
    # so the download takes the run off PCs that got it from an earlier one
    foreach ($l in (([IO.File]::ReadAllText($runsFile) -replace "`r`n", "`n") -split "`n")) {
        $p = $l -split '\|'
        if ($p[0] -ne "W5" -or $p.Count -ne 6) { continue }
        if ($l -match '\[\[|\]\]|[\x00-\x1f]' -or $p[3] -notmatch '^\d+$') { continue }
        if ($p[4] -eq "") { continue }
        $keep.Add(($p[0..4] -join '|'))
        $counts["W5"] = 1 + [int]$counts["W5"]
    }
}
# player details (P / X, tools\Raid-Stats.ps1) for the 20 fastest clears per realm and raid, all
# times and since the scaling change. Each raid is fetched once and kept in
# CustomData\WhoDidIt_RaidStats.txt; at most 60 new ones a run, and a failure only leaves them out.
try {
    . (Join-Path $PSScriptRoot "Raid-Stats.ps1")
    $cacheFile = Join-Path $wow "CustomData\WhoDidIt_RaidStats.txt"
    $cache = @{}
    if (Test-Path -LiteralPath $cacheFile) {
        foreach ($l in [IO.File]::ReadAllLines($cacheFile)) {
            $p = $l -split '\|', 3
            if ($p.Count -eq 3) { if (-not $cache[$p[1]]) { $cache[$p[1]] = @() }; $cache[$p[1]] += $l }
        }
    }
    $boards = @{}
    foreach ($l in $lines) {
        $p = $l -split '\|'
        if (($p[0] -eq "C" -or $p[0] -eq "C2") -and $p.Count -ge 9 -and $p[8]) {
            $k = $p[0] + "|" + $p[1] + "|" + $p[2]
            if (-not $boards[$k]) { $boards[$k] = @() }
            $boards[$k] += ,@([double]$p[5], $p[8])
        }
    }
    # and each boss board's 3 fastest kills: K|realm|raid|boss|guild|faction|secs|ended|players|slug
    foreach ($l in $lines) {
        $p = $l -split '|'
        if ($p[0] -eq "K" -and $p.Count -ge 10 -and $p[9]) {
            $k = "K|" + $p[1] + "|" + $p[3]
            if (-not $boards[$k]) { $boards[$k] = @() }
            $boards[$k] += ,@([double]$p[6], $p[9])
        }
    }
    $want = @{}
    foreach ($bk in $boards.Keys) { $b = $boards[$bk]; $take = if ($bk.StartsWith("K|")) { 3 } else { 20 }; foreach ($e in @($b | Sort-Object { $_[0] } | Select-Object -First $take)) { $want[$e[1]] = $true } }
    $new = 0
    foreach ($slug in $want.Keys) {
        if (-not $cache[$slug] -and $new -lt 60) {
            $new++
            try {
                $inst = Invoke-RestMethod -Uri "$script:RsApi/raidlogs/instances/$slug" -UserAgent $script:RsUA -TimeoutSec 60
                $cache[$slug] = @(Get-RaidStats $slug $inst)
                [IO.File]::AppendAllText($cacheFile, (($cache[$slug] -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
            } catch { Write-Host "No player details for raid $slug`: $_" }
            Start-Sleep -Seconds 1
        }
        foreach ($l in @($cache[$slug])) {
            if ($l -and $l -notmatch '\[\[|\]\]|[\x00-\x1f]') { $keep.Add($l); $counts["P"] = 1 + [int]$counts["P"] }
        }
    }
    Write-Host ("Player details: {0} raids wanted, {1} fetched now." -f $want.Count, $new)
} catch { Write-Host "Player details left out: $_" }
$times = [int]$counts["C"] + [int]$counts["K"]
$now = 0
if (Test-Path -LiteralPath $dst) {
    $now = ([regex]::Matches([IO.File]::ReadAllText($dst), '(?m)^[CK]\|')).Count
}
if (-not $Force -and ($times -lt 100 -or $times -lt [math]::Floor($now / 2))) {
    throw "Only $times guild times (published now: $now). That looks wrong, so it isn't published. -Force publishes it anyway."
}

$when = [DateTimeOffset]::FromUnixTimeSeconds($synced).ToString("yyyy-MM-dd HH:mm") + " UTC"
$o = New-Object System.Text.StringBuilder
[void]$o.AppendLine("-- Every guild's raid times, as of the WhoDidIt maintainer's sync of $when, so a")
[void]$o.AppendLine("-- fresh install shows full Rankings at once; the master feed sends what's newer.")
[void]$o.AppendLine("-- From Chronicle's public API (chronicleclassic.com). Generated by tools\Publish-RaidTimes.ps1 - do not edit.")
[void]$o.AppendLine("-- C / K: a guild's best clear / kill; C2 / K2: the same since the 6 Oct raid scaling change; L: a raid's bosses;")
[void]$o.AppendLine("-- R5: a 5-man group's best run (its members by name);")
[void]$o.AppendLine("-- W5: a run a member withdrew (a time the timer got wrong).")
[void]$o.AppendLine("WDI_RAIDTIMES = { synced = $synced, server = `"$server`", text = [[")
foreach ($l in $keep) { [void]$o.AppendLine($l) }
[void]$o.AppendLine("]] }")
[IO.File]::WriteAllText($dst, $o.ToString(), (New-Object Text.UTF8Encoding($false)))
Write-Host ("RaidTimes.lua: {0} clears, {1} kills, {2} / {3} since the scaling change, {4} raid details, {5} 5-man runs, {6} withdrawn, synced {7} ({8:N0} KB)." -f `
    [int]$counts["C"], [int]$counts["K"], [int]$counts["C2"], [int]$counts["K2"], [int]$counts["L"], [int]$counts["R5"], [int]$counts["W5"], $when, ((Get-Item $dst).Length / 1KB))
if ($NoPush) { return }

# OctoRank (the folder next to this one, if it's there) ships the same file. Its own process and a
# time limit: whatever goes wrong there can't touch this publish, which is already done.
function Refresh-OctoRank {
    try {
        $tool = Join-Path (Split-Path -Parent $repo) "OctoRank\tools\Refresh-RaidTimes.ps1"
        if (-not (Test-Path -LiteralPath $tool)) { return }
        $log = [IO.Path]::GetTempFileName()
        $err = [IO.Path]::GetTempFileName()
        $p = Start-Process powershell -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$tool`"", "-From", "`"$repo`"" `
            -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError $err
        if ($p.WaitForExit(90000)) {
            Write-Host (([IO.File]::ReadAllText($log) + [IO.File]::ReadAllText($err)).Trim())
        } else {
            $p.Kill()
            Write-Host "OctoRank: stopped after 90 seconds, its raid times weren't refreshed."
        }
        Remove-Item -LiteralPath $log, $err -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "OctoRank's raid times weren't refreshed: $_"
    }
}
$publishOk = $false

Push-Location $repo
$ErrorActionPreference = "Continue"   # git prints line-ending warnings on stderr
try {
    $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
    if ($branch -ne "main") { throw "The repository is on '$branch', not main - switch to main first." }
    if ($Auto) {
        git fetch -q origin main 2>$null
        $ahead = [int](git rev-list --count origin/main..HEAD 2>$null)
        if ($ahead -gt 0) { Write-Host "Skipped: main has $ahead commit(s) of yours not pushed yet, and this would push them. Next try in 3 hours."; return }
    }
    git pull -q --rebase --autostash origin main 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git pull failed - fix that first (nothing was committed)" }
    git add RaidTimes.lua 2>$null
    git diff --cached --quiet -- RaidTimes.lua
    if ($LASTEXITCODE -eq 0) { Write-Host "No change since the last publish."; $publishOk = $true; return }
    git commit -q -m "Raid times snapshot ($when)" -- RaidTimes.lua 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
    git push -q origin main 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git push failed - check you can push to the repository" }
    Write-Host "Published: a fresh install of WhoDidIt now starts with these raid times."
    $publishOk = $true
} finally {
    Pop-Location
    if ($publishOk) { Refresh-OctoRank }   # ("No change" too: it may have been skipped last time)
}
