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

    FOR THE WHODIDIT MAINTAINER ONLY. Players need none of this: their raid
    times arrive in game from the maintainer's master feed, and the Chronicle
    logger, RollFor, DopingControl and the raid packs ship with WhoDidIt.
    It only runs on a PC with one of the master characters (B.MASTERS in
    Board.lua, looked up in the WTF folder); -Force runs it anyway.
    (To move the built-in addons to newer versions: tools\EmbedUpdate.ps1.)
      (ClassicAPI, a DLL inside the game, is never updated by this: run
      Install-ClassicAPI.cmd yourself when you want a new version)

    Usage (or just double-click WhoDidIt-Sync.cmd):
      WhoDidIt-Sync.ps1                    sync now, then every 30 minutes
      WhoDidIt-Sync.ps1 -NoPublish         don't publish the raid times to the download each week
      (after every sync it also writes the website export: tools\Website-Export.ps1)
      WhoDidIt-Sync.ps1 -Once              sync once and exit
      WhoDidIt-Sync.ps1 -Server "OctoWoW"  another Chronicle server
      WhoDidIt-Sync.ps1 -Days 30           only raids from the last 30 days
      WhoDidIt-Sync.ps1 -Force             run on a PC without a master character (testing)

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
    [int]$IntervalMinutes = 30,
    [switch]$Once,
    [switch]$LoggerOnly,
    [switch]$UpdatesOnly,
    [switch]$NoLoggerUpdate,
    [switch]$NoRollForUpdate,
    [switch]$NoDopingUpdate,
    [switch]$NoPackUpdate,           # no longer used (the packs ship with WhoDidIt); kept so old shortcuts work
    [switch]$Force,                  # run even on a PC without a master character
    [switch]$NoPublish,              # don't publish the raid times to the download each week
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
# OctoWoW's raid scaling change (patch notes 2026-10-06, posted 04:54 UTC): raids
# under 30 got harder per player, so times from before it aren't comparable.
# Besides the all-time bests, each guild's best SINCE then is written too
# (C2 / K2 lines; the same as C / K). Keep in step with D.SCALING in Data.lua.
$ScalingCutoff = 1791262440
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

# best kill per realm / boss / guild (or, $mine, per realm / your character / boss);
# $since: only raids that ended at or after it
function Get-BestKills($cache, [bool]$mine = $false, [long]$since = 0) {
    $best = @{}
    foreach ($id in $cache.logs.Keys) {
        $log = $cache.logs[$id]
        if ($since -gt 0 -and [long]$log.ended -lt $since) { continue }
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

# each guild's best full clear since $since, worked out from the raid logs: the
# bosses every leaderboard run of that instance killed are the required ones,
# and the clear time is when the last of them died (time into the raid). Checked
# against Chronicle's own clear times: 191 of 193 top runs match to the second.
function Get-ClearsSince($clears, $cache, $bySlug, [long]$since) {
    $required = @{}
    foreach ($c in $clears.Values) {
        if (-not $c.slug -or -not $c.instance) { continue }
        $l = $bySlug[$c.slug]
        if (-not $l) { continue }
        $names = @(@($l.kills) | ForEach-Object { $_.n })
        if (-not $required.ContainsKey($c.instance)) { $required[$c.instance] = @{ n = 0; set = $names } }
        $r = $required[$c.instance]
        $r.n++
        $r.set = @($r.set | Where-Object { $names -contains $_ })
    }
    $best = @{}
    foreach ($id in $cache.logs.Keys) {
        $l = $cache.logs[$id]
        if ([long]$l.ended -lt $since -or -not $l.guild -or -not $l.instance) { continue }
        $r = $required[$l.instance]
        if (-not $r -or $r.n -lt 3 -or $r.set.Count -eq 0) { continue }   # too few runs to know what counts
        $at = @{}
        foreach ($k in @($l.kills)) { if ($k.n) { $at[$k.n] = $k.a } }
        $last = 0; $all = $true
        foreach ($n in $r.set) {
            if (-not $at.ContainsKey($n)) { $all = $false; break }
            if ($at[$n] -gt $last) { $last = $at[$n] }
        }
        if (-not $all -or $last -le 0) { continue }
        Keep-Best $best "$($l.realm)|$($l.instance)|$($l.guild)" @{
            realm = $l.realm; instance = $l.instance; guild = $l.guild; faction = $l.faction;
            secs = $last; ended = $l.ended; players = $l.players; slug = $l.slug }
    }
    return $best
}

function Write-Output-File($clears, $myClears, $cache, $status) {
    $best = Get-BestKills $cache
    $myKills = Get-BestKills $cache $true
    # logs behind any time on the boards: their whole boss list goes in too (L lines)
    $bySlug = @{}
    foreach ($id in $cache.logs.Keys) { $l = $cache.logs[$id]; if ($l.slug) { $bySlug[$l.slug] = $l } }
    # the same since the raid scaling change
    $postKills = Get-BestKills $cache $false $ScalingCutoff
    $postClears = Get-ClearsSince $clears $cache $bySlug $ScalingCutoff
    $shown = @{}
    foreach ($r in @($best.Values) + @($myKills.Values) + @($clears.Values) + @($myClears.Values) + @($postKills.Values) + @($postClears.Values)) { if ($r.slug) { $shown[$r.slug] = $true } }
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
    # since the raid scaling change: C2 / K2, the same fields as C / K
    foreach ($c in $postClears.Values) {
        $lines.Add(("C2|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}" -f (Clean $c.realm), (Clean $c.instance), (Clean $c.guild), $c.faction,
            [math]::Round($c.secs, 1), $c.ended, $c.players, $c.slug))
    }
    foreach ($b in $postKills.Values) {
        $lines.Add(("K2|{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}" -f (Clean $b.realm), (Clean $b.instance), (Clean $b.boss), (Clean $b.guild),
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

# This helper is for the WhoDidIt maintainer only: their master character feeds
# everyone's raid times in game, and the Chronicle logger, RollFor and
# DopingControl ship with WhoDidIt. So it runs only on a PC with one of the
# master characters (B.MASTERS in Board.lua, found in the WTF folder), unless
# started with -Force.
function Test-IsMaster {
    $board = Join-Path $PSScriptRoot "..\Board.lua"
    if (-not (Test-Path -LiteralPath $board)) { return $false }
    $src = [IO.File]::ReadAllText($board)
    $m = [regex]::Match($src, '(?s)B\.MASTERS\s*=\s*\{(.*?)\n\}')
    if (-not $m.Success) { return $false }
    foreach ($r in [regex]::Matches($m.Groups[1].Value, '\["([^"]+)"\]\s*=\s*\{([^}]*)\}')) {
        $realm = $r.Groups[1].Value
        foreach ($n in [regex]::Matches($r.Groups[2].Value, '(\w+)\s*=\s*true')) {
            if ($MyChars.ContainsKey("$realm|$($n.Groups[1].Value.ToLower())")) { return $true }
        }
    }
    return $false
}
if (-not $Force -and -not (Test-IsMaster)) {
    Log "Nothing to do here: this helper is only for WhoDidIt's maintainer."
    Log "Your raid times arrive in game from the maintainer's master feed, and everything else ships with WhoDidIt."
    Log "(If it was set to start with Windows, double-click tools\AutoSync-Off.cmd to stop that.)"
    Start-Sleep -Seconds 8
    return
}

. (Join-Path $PSScriptRoot "ClassicApiUpdate.ps1")

# only one helper at a time (e.g. started with Windows, then double-clicked too)
$script:Single = New-Object System.Threading.Mutex($false, "WhoDidIt-Sync")
$mine = $false
try { $mine = $script:Single.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $mine = $true }
if (-not $mine) {
    Log "WhoDidIt-Sync is already running in another window - this one closes. (Sync now in game asks that one.)"
    Start-Sleep -Seconds 4
    return
}
if ($LoggerOnly -or $UpdatesOnly) {
    Log "The built-in addons ship with WhoDidIt now. To move their pins, run tools\EmbedUpdate.ps1 and commit the result."
    return
}

# Once a week, after a good sync, the raid times go into the download
# (tools\Publish-RaidTimes.ps1 -Auto: it checks them, and skips if the
# repository is on another branch or has commits of yours not pushed yet,
# so it never pushes your work). A failed try is retried a day later.
function Publish-Weekly {
    if ($NoPublish) { return }
    $repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    if (-not (Test-Path -LiteralPath (Join-Path $repo ".git"))) { return }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $last = 0
    try { $last = [long](git -C $repo log -1 --format=%ct -- RaidTimes.lua 2>$null) } catch { }
    if ($now - $last -lt 7 * 86400) { return }
    $tryFile = Join-Path $DataDir "WhoDidIt_PublishTry.txt"
    $tried = 0
    if (Test-Path -LiteralPath $tryFile) { try { $tried = [long]([IO.File]::ReadAllText($tryFile).Trim()) } catch { } }
    if ($now - $tried -lt 86400) { return }
    [IO.File]::WriteAllText($tryFile, [string]$now)
    Log "Weekly: putting the raid times into the download (Publish-RaidTimes)"
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "Publish-RaidTimes.ps1") -Auto 2>&1 | Out-String
    foreach ($l in ($out.Trim() -split "`r?`n")) { if ($l) { Log ("  " + $l) } }
}

Log "WhoDidIt-Sync for $Server (WoW folder: $WowDir)"
while ($true) {
    if (Test-Path -LiteralPath $RequestFile) { [IO.File]::Delete($RequestFile) }   # this sync answers any request
    $failed = $null
    try { Sync } catch { $failed = $_.Exception.Message; Log ("Sync failed: " + $failed) }
    $script:St.next = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + $IntervalMinutes * 60
    if ($failed) { $script:St.state = "error"; $script:St.what = $failed }
    else { $script:St.state = "waiting"; $script:St.what = "Up to date"; $script:St.done = 0; $script:St.total = 0 }
    Write-Status
    if (-not $failed) { try { Publish-Weekly } catch { Log ("Weekly publish failed: " + $_.Exception.Message) } }
    # every raid time and 5-man run as one JSON file for the website (tools\Website-Export.ps1)
    if (-not $failed) {
        try {
            $out = & (Join-Path $PSScriptRoot "Website-Export.ps1") 6>&1 | Out-String
            foreach ($l in ($out.Trim() -split "`r?`n")) { if ($l) { Log ("  " + $l) } }
        } catch { Log ("Website export failed: " + $_.Exception.Message) }
    }
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