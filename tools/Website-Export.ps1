<#
    Website-Export - for the WhoDidIt maintainer: every raid time and 5-man run
    as one JSON file a website can show (www.errorguild.com, when it's ready).

    The sync helper (WhoDidIt-Sync.ps1) runs this after every good sync. It reads
      CustomData\WhoDidIt_Chronicle.txt   every guild's raid times (the helper's own file)
      CustomData\WhoDidIt_Runs.txt        the 5-man boards your WhoDidIt writes (master characters)
    and writes
      CustomData\WhoDidIt_Website.json    the export (no personal bests of your characters)
      CustomData\WhoDidIt_WebStatus.txt   what happened, for WhoDidIt's Website panel
                                          (Rankings > 5-mans > Website)

    Upload: off until tools\website.json exists with "enabled": true. Copy
    tools\website.example.json to tools\website.json and fill in the site's
    upload address and key. website.json stays on this PC (.gitignore): the key
    never goes into the repository. The upload is one HTTPS POST of the JSON
    with the key as a Bearer token.

      Website-Export.ps1            export (and upload, if switched on)
      Website-Export.ps1 -NoUpload  only write the file
#>
param([switch]$NoUpload, [string]$DataDir)   # -DataDir: another folder than CustomData (testing)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$wow = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$data = if ($DataDir) { $DataDir } else { Join-Path $wow "CustomData" }
$chronFile = Join-Path $data "WhoDidIt_Chronicle.txt"
$runsFile = Join-Path $data "WhoDidIt_Runs.txt"
$outFile = Join-Path $data "WhoDidIt_Website.json"
$statusFile = Join-Path $data "WhoDidIt_WebStatus.txt"
$configFile = Join-Path $PSScriptRoot "website.json"
$site = "https://www.errorguild.com"
$utf8 = New-Object Text.UTF8Encoding($false)

function Read-Lines($path) {
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    return ([IO.File]::ReadAllText($path, $utf8) -replace "`r`n", "`n") -split "`n" | Where-Object { $_ -ne "" }
}
function Num($s) { $d = 0.0; if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }; return $null }
function Log-Url($slug) { if ($slug) { return "https://legacy.chronicleclassic.com/instances/$slug" }; return $null }

# the dungeons, their bosses (for the splits) and the scaling change: from Data.lua
$dataLua = [IO.File]::ReadAllText((Join-Path $repo "Data.lua"))
$dungeons = [ordered]@{}
foreach ($m in [regex]::Matches($dataLua, '(?s)\{ key = "(\w+)", title = "([^"]+)".*?bosses = \{(.*?)\} \}')) {
    $bosses = @(); foreach ($b in [regex]::Matches($m.Groups[3].Value, '"([^"]+)"')) { $bosses += $b.Groups[1].Value }
    $dungeons[$m.Groups[1].Value] = [ordered]@{ key = $m.Groups[1].Value; title = $m.Groups[2].Value; bosses = $bosses }
}
$scaling = 0
$sm = [regex]::Match($dataLua, 'D\.SCALING = \{\s*at = (\d+)')
if ($sm.Success) { $scaling = [long]$sm.Groups[1].Value }
$classes = @{ Wa = "Warrior"; Pa = "Paladin"; Hu = "Hunter"; Ro = "Rogue"; Pr = "Priest"; Sh = "Shaman"; Ma = "Mage"; Wl = "Warlock"; Dr = "Druid" }

# raid times: C / K (best ever), C2 / K2 (best since the scaling change). PC / PK (your own) stay out.
$synced = 0; $server = ""
$clears = New-Object System.Collections.Generic.List[object]
$kills = New-Object System.Collections.Generic.List[object]
foreach ($l in (Read-Lines $chronFile)) {
    $p = $l -split '\|'
    switch ($p[0]) {
        "WDICHRON" { $synced = [long]$p[2]; $server = $p[3] }
        { $_ -in "C", "C2" } {
            $clears.Add([ordered]@{ realm = $p[1]; instance = $p[2]; guild = $p[3]; faction = $p[4]; seconds = (Num $p[5]); ended = [long](Num $p[6]);
                players = [int](Num $p[7]); sinceScaling = ($p[0] -eq "C2"); log = (Log-Url $p[8]) })
        }
        { $_ -in "K", "K2" } {
            $kills.Add([ordered]@{ realm = $p[1]; instance = $p[2]; boss = $p[3]; guild = $p[4]; faction = $p[5]; seconds = (Num $p[6]); ended = [long](Num $p[7]);
                players = [int](Num $p[8]); sinceScaling = ($p[0] -eq "K2"); log = (Log-Url $p[9]) })
        }
    }
}

# 5-man runs: R5|realm|key|group|secs|date|deaths|faction|members|splits|named
$runs = New-Object System.Collections.Generic.List[object]
foreach ($l in (Read-Lines $runsFile)) {
    $p = $l -split '\|'
    if ($p[0] -ne "R5" -or $p.Count -ne 11 -or -not $dungeons.Contains($p[2])) { continue }
    $dg = $dungeons[$p[2]]
    $members = @()
    foreach ($m in ($p[8] -split ',')) {
        $nc = $m -split ':'
        if ($nc.Count -eq 2) { $members += [ordered]@{ name = $nc[0]; class = $classes[$nc[1]] } }
    }
    $splits = @()
    foreach ($s in ($p[9] -split ';')) {
        $ia = $s -split '='
        if ($ia.Count -eq 2 -and [int]$ia[0] -ge 1 -and [int]$ia[0] -le $dg.bosses.Count) {
            $splits += [ordered]@{ boss = $dg.bosses[[int]$ia[0] - 1]; at = [int]$ia[1] }
        }
    }
    $splits = @($splits | Sort-Object { $_.at })
    $runs.Add([ordered]@{ realm = $p[1]; dungeon = $p[2]; dungeonTitle = $dg.title; group = $p[3]; seconds = [int]$p[4]; date = [long]$p[5];
        deaths = [int]$p[6]; faction = $p[7]; members = $members; splits = $splits })
}

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$dgList = @(); foreach ($d in $dungeons.Values) { $dgList += [ordered]@{ key = $d.key; title = $d.title } }
$doc = [ordered]@{
    generator = "WhoDidIt (https://github.com/bdot89/WhoDidIt)"
    format = 1
    exported = $now
    server = $server
    raidTimesSynced = $synced
    scalingChange = $scaling
    note = "Raid times from Chronicle (chronicleclassic.com), each guild's best. 5-man runs from WhoDidIt users (self-reported). Times in seconds, dates as Unix time (UTC)."
    raids = [ordered]@{ clears = $clears.ToArray(); kills = $kills.ToArray() }
    dungeons = $dgList
    runs = $runs.ToArray()
}
$json = $doc | ConvertTo-Json -Depth 8 -Compress
$tmp = "$outFile.tmp"
[IO.File]::WriteAllText($tmp, $json, $utf8)
Move-Item -Force $tmp $outFile
Write-Host ("Website export: {0} clears, {1} kills, {2} 5-man runs -> {3} ({4:N0} KB)" -f $clears.Count, $kills.Count, $runs.Count, $outFile, ((Get-Item $outFile).Length / 1KB))

# the upload, when it's switched on
$up, $upAt, $msg = "off", 0, ""
if (-not $NoUpload -and (Test-Path -LiteralPath $configFile)) {
    $cfg = $null
    try { $cfg = [IO.File]::ReadAllText($configFile) | ConvertFrom-Json } catch { $up, $upAt, $msg = "error", $now, "tools\website.json isn't valid JSON" }
    if ($cfg -and $cfg.site) { $site = [string]$cfg.site }
    if ($cfg -and $cfg.enabled) {
        $upAt = $now
        if (-not ([string]$cfg.url).StartsWith("https://")) {
            $up, $msg = "error", "the upload address must start with https://"
        } else {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $headers = @{ Authorization = "Bearer " + [string]$cfg.key }
                Invoke-WebRequest -Uri ([string]$cfg.url) -Method Post -Body ($utf8.GetBytes($json)) -ContentType "application/json; charset=utf-8" `
                    -Headers $headers -TimeoutSec 60 -UseBasicParsing | Out-Null
                $up = "ok"
                Write-Host "Uploaded to $($cfg.url)"
            } catch {
                $up, $msg = "error", ($_.Exception.Message -replace '[\|\r\n]', ' ')
                Write-Host "Upload failed: $msg"
            }
        }
    }
}
if ($msg.Length -gt 120) { $msg = $msg.Substring(0, 120) }
$status = "WDIWEB|1|$now|$($clears.Count + $kills.Count)|$($runs.Count)|$up|$upAt|$msg|$site"
[IO.File]::WriteAllText($statusFile, $status + "`n", $utf8)
