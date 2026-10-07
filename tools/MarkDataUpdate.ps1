<#
    MarkDataUpdate - for the WhoDidIt maintainer: rebuilds PackData.lua, the
    raid pack data WhoDidIt ships with.

    The data (zone, pack, mob GUIDs, the mark each gets, mob names) comes
    from the AutoMarker addon's NPCList.lua (by Weird Vibes,
    https://github.com/MarcelineVQ/AutoMarker), at the commit pinned below,
    converted to WhoDidIt's own format. Only the data is kept: none of
    AutoMarker's code or notes. GUIDs and pack membership identify the actual
    mobs, and the marks follow the kill orders raids use, so they're kept
    as they are. It's credited in the file and the README, isn't covered by
    WhoDidIt's MIT licence, and comes out again if AutoMarker's author asks.

    Players never run this: WhoDidIt works from PackData.lua alone and never
    downloads anything from AutoMarker. To take in a newer AutoMarker list,
    move $MarkPin, run this, read the diff, and commit PackData.lua.
      MarkDataUpdate.ps1           rebuild if the pin changed
      MarkDataUpdate.ps1 -Force    rebuild anyway
#>
param([switch]$Force)

$MarkRepo   = "MarcelineVQ/AutoMarker"
$MarkBranch = "master"
# the tested pack data (see EmbedUpdate.ps1 for how pins move); $null = newest
$MarkPin = "cd66b7ae08da2a6258f53778a73689aca4ec027b"
$MarkUA     = "WhoDidIt-MarkDataUpdate/1.0 (+https://github.com/bdot89/WhoDidIt)"
$MarkDir    = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$MarkFile   = Join-Path $MarkDir "PackData.lua"
$MarkUtf8   = New-Object Text.UTF8Encoding $false
$MarkNames  = @{ SKULL = 8; CROSS = 7; SQUARE = 6; MOON = 5; TRIANGLE = 4; DIAMOND = 3; CIRCLE = 2; STAR = 1; UNMARKED = 0 }

if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
    function Log($msg) { Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg) }
}

function Get-MarkInstalled {
    if (-not (Test-Path -LiteralPath $MarkFile)) { return $null }
    $t = [IO.File]::ReadAllText($MarkFile)
    return @{
        commit  = [regex]::Match($t, 'commit = "([^"]*)"').Groups[1].Value
        version = [regex]::Match($t, 'version = "([^"]*)"').Groups[1].Value
    }
}

function Get-MarkRaw($sha, $path) {
    $r = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$MarkRepo/$sha/$path" -UseBasicParsing -TimeoutSec 60 -Headers @{ "User-Agent" = $MarkUA }
    if ($r.Content -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($r.Content) }
    return [string]$r.Content
}

function Lua-Str([string]$s) { '"' + ($s -replace '\\', '\\' -replace '"', '\"') + '"' }

# their NPCList.lua -> ordered packs @{ zone; name; mobs = @(@(guid, mark, mobName)) }
# Understands the shapes it uses: addToDefaultNpcsToMark(zone, "pack", { ... }),
# and packs built from groups (bat1["x"] = { ... } merged into a table that
# is then passed by name). Anything else in a pack is an error, so a format
# change upstream keeps the current packs instead of installing broken ones.
function Convert-NpcList([string]$text, $zoneNames) {
    $packs = New-Object System.Collections.Generic.List[object]
    $groups = @{}   # bat1 -> @{ key -> list of mobs }
    $vars = @{}     # cbat -> list of mobs
    $cur = $null; $curGroup = $null; $forSrc = $null
    $consts = @{}   # local errenius = "0x...", local errenius_mark = CIRCLE
    $n = 0
    $markOf = {
        param($m)
        if ($MarkNames.ContainsKey($m)) { return $MarkNames[$m] }
        if ($m -match '^\d+$') { return [int]$m }
        if ($consts.ContainsKey($m) -and $consts[$m] -is [int]) { return $consts[$m] }
        throw "line ${n}: unknown mark '$m'"
    }
    $zoneOf = {
        param($z)
        if ($z -match '^L\["(.+)"\]$') { $k = $matches[1]; if ($zoneNames.ContainsKey($k)) { return $zoneNames[$k] }; return $k }
        if ($z -match '^"(.+)"$') { return $matches[1] }
        throw "line ${n}: can't read the zone '$z'"
    }
    foreach ($raw in ($text -split "\r?\n")) {
        $n++
        $l = $raw.Trim()
        if ($null -ne $cur -or $null -ne $curGroup) {
            # ["0x..."] = SKULL, -- Mob name     or     [errenius] = errenius_mark, -- note
            if ($l -match '^\[(?:"(0x[0-9A-Fa-f]{16})"|([A-Za-z_]\w*))\]\s*=\s*([A-Za-z_]\w*|\d+)\s*,?\s*(?:--\s*(.*))?$') {
                $guid = $matches[1]; $var = $matches[2]; $m = $matches[3]; $note = $matches[4]
                $who = ""
                if ($var) {
                    if (-not ($consts.ContainsKey($var) -and $consts[$var] -is [string])) { throw "line ${n}: unknown mob '$var'" }
                    $guid = $consts[$var]
                    $who = $var.Substring(0, 1).ToUpper() + $var.Substring(1).Replace("_", " ")
                } elseif ($note) {
                    $who = (($note -split ',')[0]).Trim().Trim('"')
                }
                $mark = & $markOf $m
                if ($mark -lt 0 -or $mark -gt 8) { throw "line ${n}: mark $mark out of range" }
                $mob = @($guid.ToUpper().Replace("0X", "0x"), $mark, $who)
                if ($null -ne $cur) { $cur.mobs.Add($mob) } else { $curGroup.Add($mob) }
                continue
            }
            if ($l -eq "" -or $l.StartsWith("--")) { continue }
            if ($null -ne $cur -and $l -match '^\}\)\s*;?$') { $packs.Add($cur); $cur = $null; continue }
            if ($null -ne $curGroup -and $l -match '^\}\s*;?$') { $curGroup = $null; continue }
            throw "line ${n}: unexpected '$l' inside a pack"
        }
        if ($l -match '^addToDefaultNpcsToMark\(\s*(L\["[^"]+"\]|"[^"]+")\s*,\s*"([^"]+)"\s*,\s*\{\s*$') {
            $cur = @{ zone = (& $zoneOf $matches[1]); name = $matches[2]; mobs = (New-Object System.Collections.Generic.List[object]) }
            continue
        }
        if ($l -match '^addToDefaultNpcsToMark\(\s*(L\["[^"]+"\]|"[^"]+")\s*,\s*"([^"]+)"\s*,\s*([A-Za-z_]\w*)\s*\)\s*;?$') {
            $v = $matches[3]
            if (-not $vars.ContainsKey($v)) { throw "line ${n}: pack '$($matches[2])' uses '$v', which wasn't built" }
            $p = @{ zone = (& $zoneOf $matches[1]); name = $matches[2]; mobs = (New-Object System.Collections.Generic.List[object]) }
            foreach ($mob in $vars[$v]) { $p.mobs.Add($mob) }
            $packs.Add($p)
            continue
        }
        if ($l -match '^addToDefaultNpcsToMark') { throw "line ${n}: unexpected '$l'" }
        # local errenius = "0xF13000ED4B2739FA"   /   local errenius_mark = CIRCLE
        if ($l -match '^local\s+([A-Za-z_]\w*)\s*=\s*"(0x[0-9A-Fa-f]{16})"\s*;?\s*(--.*)?$') { $consts[$matches[1]] = [string]$matches[2]; continue }
        if ($l -match '^local\s+([A-Za-z_]\w*)\s*=\s*([A-Z]+|\d+)\s*;?\s*(--.*)?$') {
            $k = $matches[1]; $v = $matches[2]
            if ($MarkNames.ContainsKey($v)) { $consts[$k] = [int]$MarkNames[$v] } elseif ($v -match '^\d+$') { $consts[$k] = [int]$v }
            continue
        }
        # bat1 = {}   /   local cbat = {}
        if ($l -match '^(?:local\s+)?([A-Za-z_]\w*)\s*=\s*\{\s*\}\s*;?$') {
            $groups[$matches[1]] = [ordered]@{}
            $vars[$matches[1]] = New-Object System.Collections.Generic.List[object]
            continue
        }
        # bat1["bat_one_rider_1"] = {
        if ($l -match '^([A-Za-z_]\w*)\["([^"]+)"\]\s*=\s*\{\s*$') {
            if (-not $groups.ContainsKey($matches[1])) { $groups[$matches[1]] = [ordered]@{} }
            $curGroup = New-Object System.Collections.Generic.List[object]
            $groups[$matches[1]][$matches[2]] = $curGroup
            continue
        }
        # for _,pack in pairs(bat1) do ... cbat[guid] = mark
        if ($l -match '^for\s+_\s*,\s*\w+\s+in\s+pairs\(\s*([A-Za-z_]\w*)\s*\)\s+do$') { $forSrc = $matches[1]; continue }
        if ($forSrc -and $l -match '^([A-Za-z_]\w*)\[\s*guid\s*\]\s*=\s*mark$') {
            $dst = $matches[1]
            if (-not $vars.ContainsKey($dst)) { $vars[$dst] = New-Object System.Collections.Generic.List[object] }
            foreach ($g in $groups[$forSrc].Values) { foreach ($mob in $g) { $vars[$dst].Add($mob) } }
            $forSrc = $null
            continue
        }
    }
    if ($null -ne $cur -or $null -ne $curGroup) { throw "the file ends inside a pack" }
    return $packs
}

function Update-MarkData([switch]$Force) {
    try {
        $ref = if ($MarkPin) { $MarkPin } else { $MarkBranch }
        $c = Invoke-RestMethod -Uri "https://api.github.com/repos/$MarkRepo/commits/$ref" -TimeoutSec 30 -Headers @{ "User-Agent" = $MarkUA; "Accept" = "application/vnd.github+json" }
    } catch {
        Log ("Mob packs: couldn't check for updates (" + $_.Exception.Message + ")")
        return
    }
    $sha = [string]$c.sha
    $have = Get-MarkInstalled
    if (-not $Force -and $have -and $have.commit -eq $sha) {
        Log "Mob packs: up to date (AutoMarker $($have.version))"
        return
    }
    try {
        $npc = Get-MarkRaw $sha "NPCList.lua"
        $toc = Get-MarkRaw $sha "AutoMarker.toc"
        $loc = Get-MarkRaw $sha "Locale/Localization_enUS.lua"
        $version = [regex]::Match($toc, '##\s*Version:\s*([0-9A-Za-z._-]+)').Groups[1].Value
        $zoneNames = @{}
        foreach ($m in [regex]::Matches($loc, '\["([^"]+)"\]\s*=\s*"([^"]+)"')) { $zoneNames[$m.Groups[1].Value] = $m.Groups[2].Value }

        $packs = Convert-NpcList $npc $zoneNames
        $mobs = 0; $seen = @{}
        foreach ($p in $packs) {
            $mobs += $p.mobs.Count
            $k = $p.zone + "|" + $p.name
            if ($seen.ContainsKey($k)) { Log "Mob packs: note - '$($p.name)' in $($p.zone) appears twice, the later one wins" }
            $seen[$k] = $true
        }
        if ($packs.Count -lt 50 -or $mobs -lt 300) { throw "only $($packs.Count) packs / $mobs mobs found - their file has probably changed shape" }

        $date = ([datetime]$c.commit.committer.date).ToString("yyyy-MM-dd")
        $o = New-Object System.Text.StringBuilder
        [void]$o.AppendLine("-- WhoDidIt's raid pack data: which mobs (by GUID) make up each pack in the raids, and the mark")
        [void]$o.AppendLine("-- each one gets in the kill order raids use.")
        [void]$o.AppendLine("--")
        [void]$o.AppendLine("-- Source: the AutoMarker addon by Weird Vibes, https://github.com/$MarkRepo")
        [void]$o.AppendLine("-- (NPCList.lua, version $version, commit $sha), converted to WhoDidIt's format. Data")
        [void]$o.AppendLine("-- only: none of AutoMarker's code or notes. Credit for collecting it goes to them. This file")
        [void]$o.AppendLine("-- is not covered by WhoDidIt's MIT licence, and it will be removed if AutoMarker's author asks.")
        [void]$o.AppendLine("--")
        [void]$o.AppendLine("-- Generated by tools\MarkDataUpdate.ps1 - do not edit (your own packs are saved in game).")
        [void]$o.AppendLine("-- Each pack: { zone, name, { guid, mark, mob name, guid, mark, mob name, ... } } in their order.")
        [void]$o.AppendLine("WDI_MARKDATA = {")
        [void]$o.AppendLine("version = " + (Lua-Str $version) + ", commit = " + (Lua-Str $sha) + ", date = " + (Lua-Str $date) + ",")
        [void]$o.AppendLine("packs = {")
        foreach ($p in $packs) {
            $parts = New-Object System.Collections.Generic.List[string]
            foreach ($mob in $p.mobs) { $parts.Add((Lua-Str $mob[0]) + "," + $mob[1] + "," + (Lua-Str $mob[2])) }
            [void]$o.AppendLine("{" + (Lua-Str $p.zone) + "," + (Lua-Str $p.name) + ",{" + ($parts -join ",") + "}},")
        }
        [void]$o.AppendLine("},")
        [void]$o.AppendLine("}")

        $tmp = $MarkFile + ".tmp"
        [IO.File]::WriteAllText($tmp, $o.ToString(), $MarkUtf8)
        Move-Item -LiteralPath $tmp -Destination $MarkFile -Force
        $was = if ($have) { "AutoMarker $($have.version) -> " } else { "" }
        Log "Pack data: PackData.lua rebuilt from ${was}AutoMarker $version ($($packs.Count) packs, $mobs mobs, $($sha.Substring(0, 7)), $date) - read the diff, then commit it"
    } catch {
        $keep = if ($have) { "keeping the current packs" } else { "none installed" }
        Log ("Mob packs: update skipped, $keep - " + $_.Exception.Message)
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    $ErrorActionPreference = "Stop"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Update-MarkData -Force:$Force
}
