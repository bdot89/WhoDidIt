<#
    WhoDidIt-Sync - pulls kill times and full clears from Chronicle's public
    External API (https://legacy.chronicleclassic.com/developers/api) for
    your server and writes them where the WhoDidIt addon can read them in
    game (WoW folder\CustomData\WhoDidIt_Chronicle.txt, via Nampower).

    WoW addons can't reach the internet, so this small helper does it for
    them. Leave it running while you play; WhoDidIt picks up new data on its
    own - no /reload needed.

    It also finds your own characters (from the WTF folder) in Chronicle's
    raid rosters, so your personal best kills and clears show up too.

    It also installs and updates what's built into WhoDidIt, each from its
    official source, checking every hour:
      - the Chronicle logger (github.com/Emyrk/ChronicleCompanion),
        RollFor (github.com/sica42/roll-for-vanilla) and DopingControl
        (github.com/ShempError/DopingControl) - see EmbedUpdate.ps1
      (ClassicAPI, a DLL inside the game, is never updated by this: run
      Install-ClassicAPI.cmd yourself when you want a new version)
      - the auto marker's mob packs (github.com/MarcelineVQ/AutoMarker) -
        see MarkDataUpdate.ps1

    Usage (or just double-click WhoDidIt-Sync.cmd):
      WhoDidIt-Sync.ps1                    sync now, then every 10 minutes
      WhoDidIt-Sync.ps1 -Once              sync once and exit
      WhoDidIt-Sync.ps1 -Server "OctoWoW"  another Chronicle server
      WhoDidIt-Sync.ps1 -Days 30           only raids from the last 30 days
      WhoDidIt-Sync.ps1 -UpdatesOnly       only install / update the built-in addons and mob packs
      WhoDidIt-Sync.ps1 -LoggerOnly        only install / update the Chronicle logger
      WhoDidIt-Sync.ps1 -NoLoggerUpdate    leave the Chronicle logger alone
      WhoDidIt-Sync.ps1 -NoRollForUpdate   leave RollFor alone
      WhoDidIt-Sync.ps1 -NoDopingUpdate    leave DopingControl alone
      WhoDidIt-Sync.ps1 -NoPackUpdate      leave the mob packs alone
      WhoDidIt-Sync.ps1 -DetailsPerSync 600  read more raids in full per sync (default 150)

    To have it run in the background (no window) every time you log into Windows, double-click
    AutoSync-On.cmd; AutoSync-Off.cmd undoes it. Only one copy runs at a time.

    The API allows 60 requests a minute; this stays at about one a second
    and caches everything it has read, so only new uploads are fetched
    after the first sync.
#>
param(
    [string]$Server = "OctoWoW",
    [int]$Days = 90,
    [int]$IntervalMinutes = 10,
    [switch]$Once,
    [switch]$LoggerOnly,
    [switch]$UpdatesOnly,
    [switch]$NoLoggerUpdate,
    [switch]$NoRollForUpdate,
    [switch]$NoDopingUpdate,
    [switch]$NoPackUpdate,
    [int]$DetailsPerSync = 150
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Api          = "https://legacy.chronicleclassic.com/api/external/v1"
$UserAgent    = "WhoDidIt-Sync/1.1 (+https://github.com/bdot89/WhoDidIt)"
$CacheVersion = 2

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
# progress for the game's Rankings tab, and the game's "Sync now" request
$StatusFile  = Join-Path $DataDir "WhoDidIt_SyncStatus.txt"
$RequestFile = Join-Path $DataDir "WhoDidIt_SyncRequest.txt"
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }

function Log($msg) { Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg) }

# ------------------------------------------------------------------ progress for the game
# CustomData\WhoDidIt_SyncStatus.txt, shown as a bar on the Rankings tab:
#   WDISYNC|1|<now>|<state>|<step>|<steps>|<what>|<done>|<total>|<seconds left>|<next sync>
# state: running / waiting / error / stopped. It's rewritten at least every
# 30 seconds while this runs, so the game can tell when the helper is closed.
$script:St = @{ state = "running"; step = 0; steps = 4; what = "Starting"; done = 0; total = 0; next = 0; since = (Get-Date); key = "" }
$script:LastBeat = [datetime]::MinValue
function Write-Status {
    $s = $script:St
    $eta = 0
    if ($s.state -eq "running" -and $s.total -gt 0) {
        $per = 1.1
        if ($s.done -ge 3) { $per = ((Get-Date) - $s.since).TotalSeconds / $s.done }
        $eta = [int]([math]::Max(0, $s.total - $s.done) * $per)
    }
    $what = ([string]$s.what) -replace '[\|\r\n]', ' '
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $line = "WDISYNC|1|$now|$($s.state)|$($s.step)|$($s.steps)|$what|$($s.done)|$($s.total)|$eta|$($s.next)"
    try { [IO.File]::WriteAllText($StatusFile, $line + "`n", (New-Object Text.UTF8Encoding($false))) } catch { }
    $script:LastBeat = Get-Date
}
# where a sync is up to; a new step restarts the time-left estimate
function Set-Progress($step, $what, $done, $total) {
    $s = $script:St
    if ($s.key -ne "$step|$what") { $s.since = Get-Date; $s.key = "$step|$what" }
    $s.state = "running"; $s.step = $step; $s.what = $what; $s.done = $done; $s.total = $total
    Write-Status
}

# your characters: WTF\Account\<account>\<realm>\<character>
$MyChars = @{}   # "realm|name(lowercase)" -> "Name"
$wtf = Join-Path $WowDir "WTF\Account"
if (Test-Path $wtf) {
    foreach ($acct in Get-ChildItem $wtf -Directory) {
        foreach ($realmDir in Get-ChildItem $acct.FullName -Directory) {
            if ($realmDir.Name -eq "SavedVariables") { continue }
            foreach ($char in Get-ChildItem $realmDir.FullName -Directory) {
                $MyChars["$($realmDir.Name)|$($char.Name.ToLower())"] = $char.Name
            }
        }
    }
}

# ------------------------------------------------------------------ HTTP (rate limited)

$script:lastCall = [datetime]::MinValue
function Get-Api([string]$path) {
    if (((Get-Date) - $script:LastBeat).TotalSeconds -gt 15) { Write-Status }   # still alive
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

# Alliance / Horde from the raiders' races; Mixed for cross-faction raids
function Get-Faction($players) {
    $a = 0; $h = 0
    if ($players) {
        foreach ($p in $players.PSObject.Properties) {
            $race = $p.Value.race
            if ($Alliance -contains $race) { $a++ } elseif ($Horde -contains $race) { $h++ }
        }
    }
    # Mixed when 2+ players of each faction raided together; one odd player
    # (a log glitch) doesn't flip a raid
    if ($a + $h -eq 0) { return "Unknown" }
    if ($a -ge 2 -and $h -ge 2) { return "Mixed" }
    if ($a -gt $h) { return "Alliance" }
    if ($h -gt $a) { return "Horde" }
    return "Mixed"
}

# which of your characters were in a raid
function Get-Mine($realm, $players) {
    $out = @()
    if ($players) {
        foreach ($p in $players.PSObject.Properties) {
            $name = $p.Value.name
            if ($name -and $MyChars.ContainsKey("$realm|$($name.ToLower())")) { $out += $name }
        }
    }
    return ,$out
}

# ------------------------------------------------------------------ cache

function New-Cache { @{ version = $CacheVersion; server = $Server; lastUpload = $null; days = 0; logs = @{}; att = @{} } }

function Load-Cache {
    if (Test-Path $CacheFile) {
        try {
            $c = Get-Content $CacheFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ([int]$c.version -ne $CacheVersion) { Log "Cache is from an older version - re-reading Chronicle"; return New-Cache }
            $logs = @{}; $att = @{}
            if ($c.logs) { foreach ($p in $c.logs.PSObject.Properties) { $logs[$p.Name] = $p.Value } }
            if ($c.att) { foreach ($p in $c.att.PSObject.Properties) { $att[$p.Name] = $p.Value } }
            return @{ version = $CacheVersion; server = $c.server; lastUpload = $c.lastUpload; days = [int]$c.days; logs = $logs; att = $att }
        } catch { Log "Cache unreadable - starting fresh" }
    }
    return New-Cache
}

function Save-Cache($cache) {
    $obj = [pscustomobject]@{ version = $CacheVersion; server = $cache.server; lastUpload = $cache.lastUpload;
                              days = $cache.days; logs = $cache.logs; att = $cache.att }
    $tmp = "$CacheFile.tmp"
    [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 6 -Compress), (New-Object Text.UTF8Encoding($false)))
    Move-Item -Force $tmp $CacheFile
}

# faction + your characters for one raid (roster only: ~4 KB), cached
function Get-Attendance($id, $realm, $cache) {
    if (-not $id) { return $null }
    # fv 3 = faction worked out with the current rule (older entries are read again once)
    if ($cache.att.ContainsKey($id) -and [int]$cache.att[$id].fv -ge 3) { return $cache.att[$id] }
    $i = Get-Api ("/raidlogs/instances/" + $id + "?attendance_only=true")
    if (-not $i) { return $null }
    $a = @{ faction = (Get-Faction $i.players); mine = (Get-Mine $realm $i.players); fv = 3 }
    $cache.att[$id] = $a
    return $a
}

# ------------------------------------------------------------------ output for the addon

function Clean([string]$s) { if ($null -eq $s) { return "" }; ($s -replace '[\|\r\n]', ' ').Trim() }

function Keep-Best($table, $key, $rec) {
    if (-not $table.ContainsKey($key) -or $rec.secs -lt $table[$key].secs) { $table[$key] = $rec }
}

# best kill per realm / boss / guild (or, $mine, per realm / your character / boss)
function Get-BestKills($cache, [bool]$mine = $false) {
    $best = @{}
    foreach ($id in $cache.logs.Keys) {
        $log = $cache.logs[$id]
        foreach ($k in @($log.kills)) {
            $rec = @{ id = $id; realm = $log.realm; instance = $log.instance; boss = $k.n; guild = $log.guild; faction = $log.faction;
                      secs = $k.s; ended = $log.ended; players = $log.players; slug = $log.slug }
            if (-not $mine) {
                if ($log.guild) { Keep-Best $best "$($log.realm)|$($k.n)|$($log.guild)" $rec }
            } else {
                foreach ($me in @($log.mine)) {
                    $r2 = $rec.Clone(); $r2.char = $me
                    Keep-Best $best "$($log.realm)|$me|$($k.n)" $r2
                }
            }
        }
    }
    return $best
}

# one raid log's boss kills in order: name, kill time, time into the raid, wipes on it before the kill
function Read-LogKills($inst) {
    $encs = @(@($inst.encounters) | Where-Object { $_.start_time } | Sort-Object { [datetimeoffset]::Parse($_.start_time) })
    $first = $null
    if ($encs.Count -gt 0) { $first = [datetimeoffset]::Parse($encs[0].start_time) }
    $kills = @(); $wipes = @{}
    foreach ($enc in $encs) {
        if (-not $enc.boss) { continue }
        if ($enc.kill_type -eq "wipe") { $wipes[$enc.name] = 1 + [int]$wipes[$enc.name]; continue }
        if (-not $enc.end_time) { continue }
        $st = [datetimeoffset]::Parse($enc.start_time); $et = [datetimeoffset]::Parse($enc.end_time)
        $secs = ($et - $st).TotalSeconds
        if ($secs -ge 3) { $kills += @{ n = $enc.name; s = [math]::Round($secs, 1); a = [math]::Round(($et - $first).TotalSeconds); w = [int]$wipes[$enc.name] } }
    }
    return ,$kills
}

function Write-Output-File($clears, $myClears, $cache, $status) {
    $best = Get-BestKills $cache
    $myKills = Get-BestKills $cache $true
    # logs behind any time on the boards: their whole boss list goes in too (L lines)
    $bySlug = @{}
    foreach ($id in $cache.logs.Keys) { $l = $cache.logs[$id]; if ($l.slug) { $bySlug[$l.slug] = $l } }
    $shown = @{}
    foreach ($r in @($best.Values) + @($myKills.Values) + @($clears.Values) + @($myClears.Values)) { if ($r.slug) { $shown[$r.slug] = $true } }
    $lines = New-Object System.Collections.Generic.List[string]
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $lines.Add("WDICHRON|2|$now|$(Clean $Server)|$Days|$status")
    foreach ($c in $clears.Values) {
        $lines.Add(("C|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}" -f (Clean $c.realm), (Clean $c.instance), (Clean $c.guild), $c.faction,
            [math]::Round($c.secs, 1), $c.ended, $c.players, $c.slug))
    }
    foreach ($b in $best.Values) {
        $lines.Add(("K|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}" -f (Clean $b.realm), (Clean $b.instance), (Clean $b.boss), (Clean $b.guild),
            $b.faction, [math]::Round($b.secs, 1), $b.ended, $b.players, $b.slug))
    }
    foreach ($m in $myClears.Values) {
        $lines.Add(("PC|{0}|{1}|{2}|{3}|{4}|{5}|{6}" -f (Clean $m.realm), (Clean $m.char), (Clean $m.instance),
            [math]::Round($m.secs, 1), $m.ended, (Clean $m.guild), $m.slug))
    }
    foreach ($m in $myKills.Values) {
        $lines.Add(("PK|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}" -f (Clean $m.realm), (Clean $m.char), (Clean $m.instance), (Clean $m.boss),
            [math]::Round($m.secs, 1), $m.ended, (Clean $m.guild), $m.slug))
    }
    # L|slug|realm|instance|guild|faction|ended|players|Boss=secs=into raid=wipes;Boss=...
    foreach ($slug in $shown.Keys) {
        $l = $bySlug[$slug]
        if (-not $l) { continue }
        $ks = @()
        foreach ($k in @($l.kills)) {
            $ks += ("{0}={1}={2}={3}" -f ((Clean $k.n) -replace '[=;]', ' '), $k.s, $k.a, $k.w)
        }
        $lines.Add(("L|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}" -f $slug, (Clean $l.realm), (Clean $l.instance), (Clean $l.guild), $l.faction,
            $l.ended, $l.players, ($ks -join ";")))
    }
    $tmp = "$OutFile.tmp"
    [IO.File]::WriteAllText($tmp, ($lines -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    Move-Item -Force $tmp $OutFile
    return $best.Count
}

# ------------------------------------------------------------------ one sync

function Sync {
    $cache = Load-Cache
    if ($cache.server -ne $Server) { $cache = New-Cache }
    # a longer look-back than last time: rescan everything (cached logs are still skipped)
    if ($Days -gt $cache.days) { $cache.lastUpload = $null; $cache.days = $Days }

    $servers = Get-Api "/explore/servers"
    $srv = $servers.servers | Where-Object { $_.name -eq $Server } | Select-Object -First 1
    if (-not $srv) { throw "Server '$Server' isn't on Chronicle. Servers: $(($servers.servers | ForEach-Object name) -join ', ')" }
    $realms = @($srv.realms)
    Log ("{0}: {1}" -f $Server, (($realms | ForEach-Object name) -join ", "))
    $mine = @($MyChars.Values | Sort-Object -Unique)
    Log ("Your characters: {0}" -f $(if ($mine.Count) { $mine -join ", " } else { "none found in WTF" }))

    # 1) full clears: Chronicle's speedrun boards, best per realm / instance / guild
    $clears = @{}; $myClears = @{}
    $realmQs = ($realms | ForEach-Object { "realm_name=" + (Q $_.name) }) -join "&"
    $ii = 0
    foreach ($inst in $Instances) {
        Set-Progress 1 "Full clears: leaderboards" $ii $Instances.Count
        $ii++
        for ($page = 1; $page -le 10; $page++) {
            $r = Get-Api ("/leaderboards/speedruns?instance_name={0}&timing=full&{1}&page_size=50&page={2}" -f (Q $inst), $realmQs, $page)
            $entries = @($r.entries)
            foreach ($e in $entries) {
                if (-not $e.guild_name -or -not $e.canonical) { continue }
                Keep-Best $clears "$($e.realm_name)|$inst|$($e.guild_name)" @{
                    realm = $e.realm_name; instance = $inst; guild = $e.guild_name; guildId = $e.guild_id; faction = "Unknown";
                    secs = $e.canonical.duration_ms / 1000.0; ended = (To-Epoch $e.canonical.completion_time);
                    players = $e.player_count; slug = $e.canonical.slug; id = $e.canonical.id }
            }
            if ($entries.Count -lt 50) { break }
        }
    }
    # faction (and whether you were there) from each best run's roster
    $n = 0
    foreach ($c in $clears.Values) {
        $att = Get-Attendance $c.id $c.realm $cache
        if ($att) {
            $c.faction = $att.faction
            foreach ($me in $att.mine) {
                $p = $c.Clone(); $p.char = $me
                Keep-Best $myClears "$($c.realm)|$me|$($c.instance)" $p
            }
        }
        $n++
        if ($n % 5 -eq 0) { Set-Progress 1 "Full clears: guild rosters" $n $clears.Count }
        if ($n % 50 -eq 0) { Log "Clear rosters: $n / $($clears.Count)"; Save-Cache $cache }
    }
    Save-Cache $cache
    Log "Full clears: $($clears.Count) guild records"
    Write-Output-File $clears $myClears $cache "syncing" | Out-Null

    # 2) boss kills: every new raid log on these realms
    $since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $newest = $cache.lastUpload
    $todo = New-Object System.Collections.Generic.List[object]
    Set-Progress 2 "Raid logs: looking for new uploads" 0 0
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
        if ($done % 5 -eq 1) { Set-Progress 2 "Raid logs" ($done - 1) $todo.Count }
        $inst = Get-Api ("/raidlogs/instances/" + $a.id)
        if (-not $inst) { continue }
        $cache.logs[$a.id] = @{
            instance = $a.name; realm = $a.realmName; slug = $a.slug;
            guild = $a.guild.name; guildId = $a.guild.id; players = $a.player_count;
            faction = (Get-Faction $inst.players); mine = (Get-Mine $a.realmName $inst.players);
            ended = (To-Epoch $a.ended_at); kills = (Read-LogKills $inst); v = 3
        }
        if ($done % 25 -eq 0 -or $done -eq $todo.Count) {
            Save-Cache $cache
            $k = Write-Output-File $clears $myClears $cache "syncing $done/$($todo.Count)"
            Log "Read $done / $($todo.Count) logs ($k guild boss records)"
        }
    }

    # 2b) the raids behind the times on the boards, in full detail (kill order, time into the
    #     raid, wipes) so clicking a time in game shows that whole raid. Logs read before this
    #     existed, and best clears older than the look-back, are fetched here, -DetailsPerSync at a time.
    $best = Get-BestKills $cache
    $need = [ordered]@{}
    foreach ($b in $best.Values) { if ([int]$cache.logs[$b.id].v -lt 3) { $need[$b.id] = $null } }   # v 3 = detail + current faction rule
    foreach ($c in $clears.Values) {
        if ($c.id -and (-not $cache.logs.ContainsKey([string]$c.id) -or [int]$cache.logs[[string]$c.id].v -lt 3)) { $need[[string]$c.id] = $c }
    }
    $left = $need.Count
    if ($left -gt 0) { Log "Raid details to read for the boards: $left (up to $DetailsPerSync now, the rest on later syncs)" }
    $n = 0
    foreach ($id in @($need.Keys)) {
        if ($n -ge $DetailsPerSync) { break }
        if ($n % 5 -eq 0) { Set-Progress 3 "Raid details for the boards" $n ([math]::Min($DetailsPerSync, $left)) }
        $n++
        $inst = Get-Api ("/raidlogs/instances/" + $id)
        if (-not $inst) { continue }
        $old = $cache.logs[$id]
        $c = $need[$id]
        if ($old) {
            $cache.logs[$id] = @{ instance = $old.instance; realm = $old.realm; slug = $old.slug; guild = $old.guild; guildId = $old.guildId;
                players = $old.players; faction = (Get-Faction $inst.players); mine = @($old.mine); ended = $old.ended; kills = (Read-LogKills $inst); v = 3 }
        } elseif ($c) {
            $cache.logs[$id] = @{ instance = $c.instance; realm = $c.realm; slug = $c.slug; guild = $c.guild; guildId = $c.guildId;
                players = $c.players; faction = (Get-Faction $inst.players); mine = (Get-Mine $c.realm $inst.players); ended = $c.ended;
                kills = (Read-LogKills $inst); v = 3 }
        }
        if ($n % 25 -eq 0) { Save-Cache $cache; Log "Raid details: $n / $([math]::Min($DetailsPerSync, $left))" }
    }
    if ($n -gt 0) { Save-Cache $cache }

    # 3) your full clears in runs that weren't your guild's best:
    #    every run of every guild you've raided with
    $myGuilds = @{}
    foreach ($log in $cache.logs.Values) { if ($log.mine.Count -gt 0 -and $log.guildId) { $myGuilds[$log.guildId] = $log.guild } }
    $gi = 0
    foreach ($gid in $myGuilds.Keys) {
        foreach ($inst in $Instances) {
            Set-Progress 4 "Your own clears" $gi ($myGuilds.Count * $Instances.Count)
            $gi++
            $r = Get-Api ("/leaderboards/speedruns?instance_name={0}&timing=full&guild_id={1}&page_size=50" -f (Q $inst), $gid)
            foreach ($e in @($r.entries)) {
                if (-not $e.canonical) { continue }
                $att = Get-Attendance $e.canonical.id $e.realm_name $cache
                if (-not $att) { continue }
                foreach ($me in $att.mine) {
                    Keep-Best $myClears "$($e.realm_name)|$me|$inst" @{
                        realm = $e.realm_name; char = $me; instance = $inst; guild = $e.guild_name;
                        secs = $e.canonical.duration_ms / 1000.0; ended = (To-Epoch $e.canonical.completion_time); slug = $e.canonical.slug }
                }
            }
        }
    }

    if ($newest) { $cache.lastUpload = $newest }
    Save-Cache $cache
    $k = Write-Output-File $clears $myClears $cache "ok"
    Log "Done: $($clears.Count) clears, $k boss kill records, $($myClears.Count) of your clears -> $OutFile"
}

# ------------------------------------------------------------------ main

. (Join-Path $PSScriptRoot "EmbedUpdate.ps1")
. (Join-Path $PSScriptRoot "MarkDataUpdate.ps1")
. (Join-Path $PSScriptRoot "ClassicApiUpdate.ps1")

# only one helper at a time (e.g. started with Windows, then double-clicked too),
# whatever it was started for: two updates at once would race on the same folders
$script:Single = New-Object System.Threading.Mutex($false, "WhoDidIt-Sync")
$mine = $false
try { $mine = $script:Single.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $mine = $true }
if (-not $mine) {
    if ($LoggerOnly -or $UpdatesOnly) {
        Log "WhoDidIt-Sync is already running - it checks for updates itself every hour. Close it first to update right now."
    } else {
        Log "WhoDidIt-Sync is already running in another window - this one closes. (Sync now in game asks that one.)"
    }
    Start-Sleep -Seconds 4
    return
}

if ($LoggerOnly) {
    Update-Chronicle
    return
}
if ($UpdatesOnly) {
    Update-Chronicle
    Update-RollFor
    Update-Doping
    Update-MarkData

    return
}

Log "WhoDidIt-Sync for $Server (WoW folder: $WowDir)"
$loggerEvery = [math]::Max(1, [math]::Ceiling(60 / [math]::Max(1, $IntervalMinutes)))
$round = 0
while ($true) {
    if (($round % $loggerEvery) -eq 0) {
        if (-not $NoLoggerUpdate) {
            try { Update-Chronicle } catch { Log ("Chronicle logger check failed: " + $_.Exception.Message) }
        }
        if (-not $NoRollForUpdate) {
            try { Update-RollFor } catch { Log ("RollFor check failed: " + $_.Exception.Message) }
        }
        if (-not $NoDopingUpdate) {
            try { Update-Doping } catch { Log ("DopingControl check failed: " + $_.Exception.Message) }
        }

        if (-not $NoPackUpdate) {
            try { Update-MarkData } catch { Log ("Mob pack check failed: " + $_.Exception.Message) }
        }
    }
    $round++
    Remove-Item -LiteralPath $RequestFile -Force -ErrorAction SilentlyContinue   # this sync answers any request
    $failed = $null
    try { Sync } catch { $failed = $_.Exception.Message; Log ("Sync failed: " + $failed) }
    $script:St.next = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + $IntervalMinutes * 60
    if ($failed) { $script:St.state = "error"; $script:St.what = $failed }
    else { $script:St.state = "waiting"; $script:St.what = "Up to date"; $script:St.done = 0; $script:St.total = 0 }
    Write-Status
    if ($Once) { break }
    Log "Next sync in $IntervalMinutes minutes, or click Sync now on WhoDidIt's Rankings tab (close this window to stop)"
    # wait, but start at once when the game asks (Sync now); keep telling the game we're here
    $next = (Get-Date).AddMinutes($IntervalMinutes)
    while ((Get-Date) -lt $next) {
        if (Test-Path -LiteralPath $RequestFile) { Log "Sync requested from the game"; break }
        if (((Get-Date) - $script:LastBeat).TotalSeconds -ge 30) { Write-Status }
        Start-Sleep -Seconds 3
    }
}
$script:St.state = "stopped"
Write-Status
