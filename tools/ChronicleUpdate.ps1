<#
    ChronicleUpdate - keeps WhoDidIt's built-in Chronicle logger up to date.

    WhoDidIt includes ChronicleCompanion, the official logging addon for
    chronicleclassic.com (by Emyrk), so it doesn't have to be installed
    separately. This downloads it from the official source
    (https://github.com/Emyrk/ChronicleCompanion) into WhoDidIt\Chronicle,
    and whenever Chronicle's team push a change it fetches that too.

    To run from inside WhoDidIt, three things in Chronicle's files are
    changed (nothing else is touched):
      - it starts on WhoDidIt's ADDON_LOADED instead of ChronicleCompanion's
      - its version comes from Chronicle\wdi_version.lua instead of
        ChronicleCompanion.toc
      - the minimap icon paths point at WhoDidIt\Chronicle
    and every file starts with "if WDI_CHRON_SKIP then return end", so the
    built-in copy stands down if the separate addon is still switched on.
    If a new version can't be adapted safely, the current one is kept.

    Updates are only swapped in while WoW is closed. One that arrives
    while you're playing is downloaded and installed when you exit.

    WhoDidIt-Sync.ps1 runs this every hour. To run it on its own:
      ChronicleUpdate.ps1            check for an update and install it
      ChronicleUpdate.ps1 -Force     download and reinstall even if up to date
#>
param([switch]$Force)

$ChronRepo   = "Emyrk/ChronicleCompanion"
$ChronBranch = "main"
$ChronUA     = "WhoDidIt-ChronicleUpdate/1.0 (+https://github.com/bdot89/WhoDidIt)"
$AddonDir    = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ChronWow    = (Resolve-Path (Join-Path $AddonDir "..\..\..")).Path
$ChronDir    = Join-Path $AddonDir "Chronicle"
$ChronNew    = Join-Path $AddonDir "Chronicle.new"
$ChronOld    = Join-Path $AddonDir "Chronicle.old"
$ChronToc    = Join-Path $AddonDir "WhoDidIt.toc"
$TocBegin    = "# >>> Chronicle files (generated)"
$TocEnd      = "# <<< Chronicle files"
# not needed in game (tests, editor files, a type-hints file their .toc doesn't load)
$ChronSkip   = @("tests", ".github", ".gitignore", ".idea", ".vscode", "globaldefs.lua")
$Utf8        = New-Object Text.UTF8Encoding $false

if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
    function Log($msg) { Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg) }
}

# ------------------------------------------------------------------ helpers

# Chronicle\wdi_version.lua -> @{ version; commit; files; sv; svChar }
function Get-ChronInfo($dir) {
    $f = Join-Path $dir "wdi_version.lua"
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $t = [IO.File]::ReadAllText($f)
    $get = { param($k) [regex]::Match($t, $k + '\s*=\s*"([^"]*)"').Groups[1].Value }
    $files = @()
    foreach ($m in [regex]::Matches($t, '(?m)^-- file: (.+)$')) { $files += $m.Groups[1].Value.Trim() }
    return @{
        version = (& $get "WDI_CHRON_VERSION"); commit = (& $get "WDI_CHRON_COMMIT")
        sv = [regex]::Match($t, '(?m)^-- savedvariables: (.*)$').Groups[1].Value.Trim()
        svChar = [regex]::Match($t, '(?m)^-- savedvariablespercharacter: (.*)$').Groups[1].Value.Trim()
        files = $files
    }
}

# is this WoW install running? (any process started from the WoW folder)
function Test-WowRunning {
    foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
        try {
            if ($p.Path -and $p.Path.StartsWith($ChronWow + "\", [StringComparison]::OrdinalIgnoreCase)) { return $true }
        } catch { }
    }
    return $false
}

function Get-GitHub($url) {
    Invoke-RestMethod -Uri $url -TimeoutSec 30 -Headers @{ "User-Agent" = $ChronUA; "Accept" = "application/vnd.github+json" }
}

function Copy-ChronTree($from, $to) {
    New-Item -ItemType Directory -Path $to -Force | Out-Null
    foreach ($i in Get-ChildItem -LiteralPath $from -Force) {
        if ($ChronSkip -contains $i.Name -or $i.Extension -eq ".toc") { continue }
        $d = Join-Path $to $i.Name
        if ($i.PSIsContainer) { Copy-ChronTree $i.FullName $d } else { Copy-Item -LiteralPath $i.FullName -Destination $d }
    }
}

# the three changes that let Chronicle run from inside WhoDidIt
function Convert-ChronLua([string]$text) {
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    $text = [regex]::Replace($text, 'GetAddOnMetadata\(\s*"ChronicleCompanion"\s*,\s*"Version"\s*\)', 'WDI_ChronVersion()')
    $text = [regex]::Replace($text, 'GetAddOnMetadata\(\s*"ChronicleCompanion"', 'GetAddOnMetadata("WhoDidIt"')
    $text = [regex]::Replace($text, 'IsAddOnLoaded\(\s*"ChronicleCompanion"\s*\)', 'IsAddOnLoaded("WhoDidIt")')
    $text = [regex]::Replace($text, '(==|~=)\s*"ChronicleCompanion"', '${1} "WhoDidIt"')
    $text = [regex]::Replace($text, '(?i)Interface(\\\\|/)AddOns(\\\\|/)ChronicleCompanion(\\\\|/)', 'Interface${1}AddOns${2}WhoDidIt${3}Chronicle${3}')
    # same line as their first line, so error line numbers still match the source
    return "if WDI_CHRON_SKIP then return end " + $text
}

# WhoDidIt.toc with Chronicle's file list and saved variables filled in
function New-ChronToc($info) {
    $raw = [IO.File]::ReadAllText($ChronToc)
    $nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = $raw -split "\r?\n"
    $b = [Array]::IndexOf($lines, $TocBegin); $e = [Array]::IndexOf($lines, $TocEnd)
    if ($b -lt 0 -or $e -lt $b) { throw "WhoDidIt.toc is missing the '$TocBegin' / '$TocEnd' lines" }
    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $b; $i++) {
        $l = $lines[$i]
        if ($l -match '^##\s*SavedVariablesPerCharacter\s*:') { continue }
        if ($l -match '^##\s*SavedVariables\s*:') {
            $sv = @("WhoDidItDB") + @($info.sv -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne "WhoDidItDB" })
            $out.Add("## SavedVariables: " + ($sv -join ", "))
            if ($info.svChar) { $out.Add("## SavedVariablesPerCharacter: " + $info.svChar) }
            continue
        }
        $out.Add($l)
    }
    $out.Add($TocBegin)
    $out.Add("Chronicle\wdi_version.lua")
    foreach ($f in $info.files) { $out.Add("Chronicle\" + $f) }
    for ($i = $e; $i -lt $lines.Count; $i++) { $out.Add($lines[$i]) }
    $text = ($out -join $nl)
    return @{ text = $text; changed = ($text -ne $raw) }
}

# ------------------------------------------------------------------ build + install

# download one commit and prepare it in Chronicle.new; returns its info
function Build-ChronStaging($sha, $date) {
    $short = $sha.Substring(0, 7)
    $zip = Join-Path $env:TEMP "wdi-chron-$short.zip"
    $tmp = Join-Path $env:TEMP "wdi-chron-$short"
    try {
        Invoke-WebRequest -Uri "https://codeload.github.com/$ChronRepo/zip/$sha" -OutFile $zip -UseBasicParsing -TimeoutSec 60 -Headers @{ "User-Agent" = $ChronUA }
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
        $src = (Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1).FullName
        $toc = Get-ChildItem -LiteralPath $src -Filter "*.toc" | Select-Object -First 1
        if (-not $toc) { throw "no .toc file in the download" }

        # their .toc: version, saved variables, file list
        $meta = @{}; $files = @()
        foreach ($l in [IO.File]::ReadAllLines($toc.FullName)) {
            $t = $l.Trim()
            if ($t -match '^##\s*([^:]+?)\s*:\s*(.*)$') { $meta[$matches[1]] = $matches[2].Trim(); continue }
            if ($t -eq "" -or $t.StartsWith("#")) { continue }
            $files += ($t -replace '/', '\')
        }
        $version = ($meta["Version"] -replace '[^0-9A-Za-z._-]', '')
        if (-not $version) { throw "no version in their .toc" }
        if ($files.Count -eq 0) { throw "their .toc lists no files" }
        foreach ($f in $files) {
            if ($f -notmatch '\.lua$') { throw "their .toc now loads '$f' - only .lua files can be switched off when the separate addon is installed, so WhoDidIt needs an update first" }
            if ($f -match '\.\.' -or $f -match '^[\\/]' -or $f -match ':') { throw "unexpected file path '$f' in their .toc" }
            if (-not (Test-Path -LiteralPath (Join-Path $src $f))) { throw "their .toc lists '$f' but it isn't in the download" }
        }

        if (Test-Path $ChronNew) { Remove-Item $ChronNew -Recurse -Force }
        Copy-ChronTree $src $ChronNew

        $left = @()
        foreach ($f in $files) {
            $p = Join-Path $ChronNew $f
            $lua = Convert-ChronLua ([IO.File]::ReadAllText($p))
            $n = 0
            foreach ($ln in ($lua -split "\n")) {
                $n++
                if ($ln -match '["'']ChronicleCompanion["'']') { $left += "$f line $n" }
            }
            [IO.File]::WriteAllText($p, $lua, $Utf8)
        }
        # anything still naming the addon would break once it runs inside WhoDidIt
        if ($left.Count -gt 0) { throw ("their code uses the addon name in a new way (" + ($left -join ", ") + ")") }

        $sv = $meta["SavedVariables"]; $svChar = $meta["SavedVariablesPerCharacter"]
        $v = New-Object System.Collections.Generic.List[string]
        $v.Add("-- Generated by WhoDidIt's tools\WhoDidIt-Sync - do not edit.")
        $v.Add("-- ChronicleCompanion by Emyrk: https://github.com/$ChronRepo (commit $sha)")
        $v.Add("-- savedvariables: $sv")
        $v.Add("-- savedvariablespercharacter: $svChar")
        foreach ($f in $files) { $v.Add("-- file: $f") }
        $v.Add("WDI_CHRON_VERSION = `"$version`"")
        $v.Add("WDI_CHRON_COMMIT = `"$sha`"")
        $v.Add("WDI_CHRON_DATE = `"$date`"")
        [IO.File]::WriteAllText((Join-Path $ChronNew "wdi_version.lua"), (($v -join "`n") + "`n"), $Utf8)
        return (Get-ChronInfo $ChronNew)
    } catch {
        if (Test-Path $ChronNew) { Remove-Item $ChronNew -Recurse -Force -ErrorAction SilentlyContinue }
        throw
    } finally {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# swap Chronicle.new in and update WhoDidIt.toc; returns $true if the toc changed
function Install-ChronStaging {
    $info = Get-ChronInfo $ChronNew
    if (-not $info) { throw "Chronicle.new is incomplete" }
    $toc = New-ChronToc $info
    if (Test-Path $ChronOld) { Remove-Item $ChronOld -Recurse -Force }
    if (Test-Path $ChronDir) { Rename-Item -LiteralPath $ChronDir -NewName "Chronicle.old" }
    try {
        Rename-Item -LiteralPath $ChronNew -NewName "Chronicle"
    } catch {
        if (Test-Path $ChronOld) { Rename-Item -LiteralPath $ChronOld -NewName "Chronicle" }
        throw
    }
    if ($toc.changed) { [IO.File]::WriteAllText($ChronToc, $toc.text, $Utf8) }
    if (Test-Path $ChronOld) { Remove-Item $ChronOld -Recurse -Force -ErrorAction SilentlyContinue }
    return $toc.changed
}

# ------------------------------------------------------------------ main

function Update-Chronicle([switch]$Force) {
    $running = Test-WowRunning

    # an update downloaded while WoW was open
    if ((Test-Path $ChronNew) -and -not $running) {
        $s = Get-ChronInfo $ChronNew
        try {
            [void](Install-ChronStaging)
            Log "Chronicle logger: installed v$($s.version), downloaded earlier"
        } catch { Log ("Chronicle logger: couldn't install the downloaded update: " + $_.Exception.Message) }
    }

    $have = Get-ChronInfo $ChronDir
    try {
        $c = Get-GitHub "https://api.github.com/repos/$ChronRepo/commits/$ChronBranch"
    } catch {
        Log ("Chronicle logger: couldn't check for updates (" + $_.Exception.Message + ")")
        return
    }
    $sha = [string]$c.sha
    $date = ([datetime]$c.commit.committer.date).ToString("yyyy-MM-dd")
    if (-not $Force -and $have -and $have.commit -eq $sha) {
        Log "Chronicle logger: v$($have.version) is up to date"
        return
    }
    $staged = Get-ChronInfo $ChronNew
    if (-not $Force -and $staged -and $staged.commit -eq $sha) {
        Log "Chronicle logger: v$($staged.version) is downloaded and installs when WoW is closed"
        return
    }

    try {
        $new = Build-ChronStaging $sha $date
    } catch {
        $keep = if ($have) { "keeping v$($have.version)" } else { "not installed" }
        Log ("Chronicle logger: update skipped, $keep - " + $_.Exception.Message)
        return
    }
    $what = if ($have) { "updated v$($have.version) -> v$($new.version)" } else { "installed v$($new.version)" }

    # first install: nothing to disturb. Updates wait until WoW is closed.
    if ($running -and $have) {
        Log "Chronicle logger: v$($new.version) downloaded ($($sha.Substring(0, 7)), $date) - it installs when you close WoW"
        return
    }
    try {
        $tocChanged = Install-ChronStaging
    } catch {
        Log ("Chronicle logger: couldn't install: " + $_.Exception.Message)
        return
    }
    Log "Chronicle logger: $what ($($sha.Substring(0, 7)), $date)"
    if ($running -and $tocChanged) { Log "Chronicle logger: exit WoW and start it again to load it (a /reload isn't enough)" }
}

# run directly (not dot-sourced by WhoDidIt-Sync)
if ($MyInvocation.InvocationName -ne ".") {
    $ErrorActionPreference = "Stop"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Update-Chronicle -Force:$Force
}
