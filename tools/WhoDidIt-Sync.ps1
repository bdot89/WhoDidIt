<#
    WhoDidIt-Sync - pulls kill times and full clears from Chronicle's public
    External API (https://legacy.chronicleclassic.com/developers/api) for
    your server and writes them where the WhoDidIt addon can read them in
    game (WoW folder\CustomData\WhoDidIt_Chronicle.txt, via Nampower).

    WoW addons can't reach the internet, so this small helper does it for
    them. Leave it running while you play; WhoDidIt picks up new data on its
    own - no /reload needed.

    Usage (or just double-click WhoDidIt-Sync.cmd):
      WhoDidIt-Sync.ps1                    sync now, then every 10 minutes
      WhoDidIt-Sync.ps1 -Once              sync once and exit
      WhoDidIt-Sync.ps1 -Server "OctoWoW"  another Chronicle server
      WhoDidIt-Sync.ps1 -Days 30           only raids from the last 30 days

    The API allows 60 requests a minute; this stays at about one a second
    and caches every raid log it has read, so only new uploads are fetched
    after the first sync.
#>
param(
    [string]$Server = "OctoWoW",
    [int]$Days = 90,
    [int]$IntervalMinutes = 10,
    [switch]$Once
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Api       = "https://legacy.chronicleclassic.com/api/external/v1"
$UserAgent = "WhoDidIt-Sync/1.0 (+https://github.com/bdot89/WhoDidIt)"

# raids shown in WhoDidIt's Rankings (Chronicle's instance names)
$Instances = @(
    "Molten Core", "Onyxia's Lair", "Blackwing Lair", "Zul'Gurub",
    "Ruins of Ahn'Qiraj", "Temple of Ahn'Qiraj", "Naxxramas", "Emerald Sanctum",
    "Lower Tower of Karazhan", "Upper Tower of Karazhan"
)
$Alliance = @("Human", "Dwarf", "NightElf", "Night Elf", "Gnome", "HighElf", "High Elf", "Draenei")
$Horde    = @("Orc", "Troll", "Tauren", "Undead", "Scourge", "Goblin", "BloodElf", "Blood Elf")

# tools -> WhoDidIt -> AddOns -> Interface -> WoW folder
$WowDir    = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$DataDir   = Join-Path $WowDir "CustomData"
$OutFile   = Join-Path $DataDir "WhoDidIt_Chronicle.txt"
$CacheFile = Join-Path $DataDir "WhoDidIt_ChronicleCache.json"
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }

function Log($msg) { Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg) }

# ------------------------------------------------------------------ HTTP (rate limited)

$script:lastCall = [datetime]::MinValue
function Get-Api([string]$path) {
    $wait = 1.05 - ((Get-Date) - $script:lastCall).TotalSeconds
    if ($wait -gt 0) { Start-Sleep -Milliseconds ([int]($wait * 1000)) }
    for ($try = 1; $try -le 5; $try++) {
        $script:lastCall = Get-Date
        try {
            return Invoke-RestMethod -Uri ($Api + $path) -UserAgent $UserAgent -TimeoutSec 60
        } catch [System.Net.WebException] {
            $resp = $_.Exception.Response
            $code = if ($resp) { [int]$resp.StatusCode } else { 0 }
            if ($code -eq 429) {
                $after = 10
                if ($resp.Headers["Retry-After"]) { $after = [int]$resp.Headers["Retry-After"] + 1 }
                Log "Rate limited - waiting $after s"
                Start-Sleep -Seconds $after
            } elseif ($code -eq 404) {
                return $null
            } elseif ($try -lt 5) {
                Log "Request failed ($code) - retrying"
                Start-Sleep -Seconds (5 * $try)
            } else {
                throw
            }
        }
    }
}

function Q([string]$s) { [uri]::EscapeDataString($s) }

function To-Epoch($iso) {
    if (-not $iso) { return 0 }
    [int64]([datetimeoffset]::Parse($iso).ToUnixTimeSeconds())
}

# Alliance / Horde / Mixed from the raiders' races (OctoWoW raids cross-faction)
function Get-Faction($players) {
    $a = 0; $h = 0
    if ($players) {
        foreach ($p in $players.PSObject.Properties) {
            $race = $p.Value.race
            if ($Alliance -contains $race) { $a++ } elseif ($Horde -contains $race) { $h++ }
        }
    }
    $n = $a + $h
    if ($n -eq 0) { return "Unknown" }
    if ($a / $n -ge 0.75) { return "Alliance" }
    if ($h / $n -ge 0.75) { return "Horde" }
    return "Mixed"
}

# ------------------------------------------------------------------ cache

function Load-Cache {
    if (Test-Path $CacheFile) {
        try {
            $c = Get-Content $CacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $logs = @{}
            if ($c.logs) { foreach ($p in $c.logs.PSObject.Properties) { $logs[$p.Name] = $p.Value } }
            return @{ server = $c.server; lastUpload = $c.lastUpload; days = [int]$c.days; logs = $logs }
        } catch { Log "Cache unreadable - starting fresh" }
    }
    return @{ server = $Server; lastUpload = $null; days = 0; logs = @{} }
}

function Save-Cache($cache) {
    $obj = [pscustomobject]@{ server = $cache.server; lastUpload = $cache.lastUpload; days = $cache.days; logs = $cache.logs }
    $tmp = "$CacheFile.tmp"
    [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 6 -Compress), (New-Object Text.UTF8Encoding($false)))
    Move-Item -Force $tmp $CacheFile
}

# ------------------------------------------------------------------ output for the addon

function Clean([string]$s) { if ($null -eq $s) { return "" }; ($s -replace '[\|\r\n]', ' ').Trim() }

function Write-Output-File($clears, $cache, $status) {
    $lines = New-Object System.Collections.Generic.List[string]
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $lines.Add("WDICHRON|1|$now|$(Clean $Server)|$Days|$status")
    foreach ($c in $clears.Values) {
        $lines.Add(("C|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}" -f (Clean $c.realm), (Clean $c.instance), (Clean $c.guild), $c.faction,
            [math]::Round($c.secs, 1), $c.ended, $c.players, $c.slug))
    }
    # best kill per realm / boss / guild
    $best = @{}
    foreach ($log in $cache.logs.Values) {
        if (-not $log.guild) { continue }
        foreach ($k in $log.kills) {
            $key = "$($log.realm)|$($k.n)|$($log.guild)"
            if (-not $best.ContainsKey($key) -or $k.s -lt $best[$key].secs) {
                $best[$key] = @{ realm = $log.realm; instance = $log.instance; boss = $k.n; guild = $log.guild;
                                 faction = $log.faction; secs = $k.s; ended = $log.ended; players = $log.players; slug = $log.slug }
            }
        }
    }
    foreach ($b in $best.Values) {
        $lines.Add(("K|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}" -f (Clean $b.realm), (Clean $b.instance), (Clean $b.boss), (Clean $b.guild),
            $b.faction, [math]::Round($b.secs, 1), $b.ended, $b.players, $b.slug))
    }
    $tmp = "$OutFile.tmp"
    [IO.File]::WriteAllText($tmp, ($lines -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    Move-Item -Force $tmp $OutFile
    return $best.Count
}

# ------------------------------------------------------------------ one sync

function Sync {
    $cache = Load-Cache
    if ($cache.server -ne $Server) { $cache = @{ server = $Server; lastUpload = $null; days = 0; logs = @{} } }
    # a longer look-back than last time: rescan everything (cached logs are still skipped)
    if ($Days -gt $cache.days) { $cache.lastUpload = $null; $cache.days = $Days }

    $servers = Get-Api "/explore/servers"
    $srv = $servers.servers | Where-Object { $_.name -eq $Server } | Select-Object -First 1
    if (-not $srv) { throw "Server '$Server' isn't on Chronicle. Servers: $(($servers.servers | ForEach-Object name) -join ', ')" }
    $realms = @($srv.realms)
    Log ("{0}: {1}" -f $Server, (($realms | ForEach-Object name) -join ", "))

    # guild faction from the logs we've read (for the clear boards)
    $guildFaction = @{}
    foreach ($log in $cache.logs.Values) { if ($log.guildId) { $guildFaction[$log.guildId] = $log.faction } }

    # 1) full clears: Chronicle's speedrun boards, best per realm / instance / guild
    $clears = @{}
    $realmQs = ($realms | ForEach-Object { "realm_name=" + (Q $_.name) }) -join "&"
    foreach ($inst in $Instances) {
        for ($page = 1; $page -le 10; $page++) {
            $r = Get-Api ("/leaderboards/speedruns?instance_name={0}&timing=full&{1}&page_size=50&page={2}" -f (Q $inst), $realmQs, $page)
            $entries = @($r.entries)
            foreach ($e in $entries) {
                if (-not $e.guild_name -or -not $e.canonical) { continue }
                $key = "$($e.realm_name)|$inst|$($e.guild_name)"
                $secs = $e.canonical.duration_ms / 1000.0
                if (-not $clears.ContainsKey($key) -or $secs -lt $clears[$key].secs) {
                    $fac = $guildFaction[$e.guild_id]; if (-not $fac) { $fac = "Unknown" }
                    $clears[$key] = @{ realm = $e.realm_name; instance = $inst; guild = $e.guild_name; faction = $fac;
                                       secs = $secs; ended = (To-Epoch $e.canonical.completion_time);
                                       players = $e.player_count; slug = $e.canonical.slug }
                }
            }
            if ($entries.Count -lt 50) { break }
        }
    }
    Log "Full clears: $($clears.Count) guild records"
    Write-Output-File $clears $cache "syncing" | Out-Null

    # 2) boss kills: every new raid log on these realms
    $since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $newest = $cache.lastUpload
    $todo = New-Object System.Collections.Generic.List[object]
    foreach ($realm in $realms) {
        for ($page = 1; $page -le 200; $page++) {
            $path = "/raidlogs/recent?realm_id={0}&after_date={1}&page_size=50&page={2}" -f $realm.id, (Q $since), $page
            if ($cache.lastUpload) { $path += "&upload_after=" + (Q $cache.lastUpload) }
            $r = Get-Api $path
            foreach ($a in @($r.activities)) {
                if ($Instances -notcontains $a.name -or $a.boss_kills -lt 1) { continue }
                if ($cache.logs.ContainsKey($a.id)) { continue }
                $a | Add-Member -NotePropertyName realmName -NotePropertyValue $realm.name -Force
                $todo.Add($a)
                if (-not $newest -or $a.uploaded_at -gt $newest) { $newest = $a.uploaded_at }
            }
            if (-not $r.pagination.has_more) { break }
        }
    }
    Log "New raid logs to read: $($todo.Count)"

    $done = 0
    foreach ($a in $todo) {
        $done++
        $inst = Get-Api ("/raidlogs/instances/" + $a.id)
        if (-not $inst) { continue }
        $kills = @()
        foreach ($enc in @($inst.encounters)) {
            if (-not $enc.boss -or $enc.kill_type -eq "wipe" -or -not $enc.end_time) { continue }
            $secs = ([datetimeoffset]::Parse($enc.end_time) - [datetimeoffset]::Parse($enc.start_time)).TotalSeconds
            if ($secs -ge 3) { $kills += @{ n = $enc.name; s = [math]::Round($secs, 1) } }
        }
        $cache.logs[$a.id] = @{
            instance = $a.name; realm = $a.realmName; slug = $a.slug;
            guild = $a.guild.name; guildId = $a.guild.id; players = $a.player_count;
            faction = (Get-Faction $inst.players); ended = (To-Epoch $a.ended_at); kills = $kills
        }
        if ($done % 25 -eq 0 -or $done -eq $todo.Count) {
            Save-Cache $cache
            $n = Write-Output-File $clears $cache "syncing $done/$($todo.Count)"
            Log "Read $done / $($todo.Count) logs ($n guild boss records)"
        }
    }

    # clear boards again, now that guild factions are known from the logs
    foreach ($log in $cache.logs.Values) { if ($log.guildId) { $guildFaction[$log.guildId] = $log.faction } }
    foreach ($c in $clears.Values) {
        if ($c.faction -eq "Unknown") {
            foreach ($log in $cache.logs.Values) {
                if ($log.guild -eq $c.guild -and $log.realm -eq $c.realm) { $c.faction = $log.faction; break }
            }
        }
    }
    if ($newest) { $cache.lastUpload = $newest }
    Save-Cache $cache
    $n = Write-Output-File $clears $cache "ok"
    Log "Done: $($clears.Count) clear records, $n boss kill records -> $OutFile"
}

# ------------------------------------------------------------------ main

Log "WhoDidIt-Sync for $Server (WoW folder: $WowDir)"
while ($true) {
    try { Sync } catch { Log ("Sync failed: " + $_.Exception.Message) }
    if ($Once) { break }
    Log "Next sync in $IntervalMinutes minutes (close this window to stop)"
    Start-Sleep -Seconds ($IntervalMinutes * 60)
}
