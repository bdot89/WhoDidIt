<#
    EmbedUpdate - keeps the addons built into WhoDidIt up to date.

    WhoDidIt carries other addons inside it, so they don't have to be
    installed separately. None of them is stored in the WhoDidIt repository:
    this downloads each from its official source and, whenever its authors
    push a new version, fetches that too.

      Chronicle logger  ChronicleCompanion by Emyrk (chronicleclassic.com)
                        github.com/Emyrk/ChronicleCompanion, branch main
                        -> WhoDidIt\Chronicle
      RollFor           the master-loot roller by Obszczymucha, sica42's
                        1.12 fork (the original now only supports TBC)
                        github.com/sica42/roll-for-vanilla, latest release
                        -> WhoDidIt\RollFor
      DopingControl     the raid consumables / buffs / enchants checker by
                        ShempError (MIT), github.com/ShempError/DopingControl,
                        branch main -> WhoDidIt\DopingControl

    To run from inside WhoDidIt, a few things in their files are changed,
    and nothing else is touched:
      - their version comes from <folder>\wdi_version.lua instead of their
        own .toc (the Chronicle logger also starts on WhoDidIt's
        ADDON_LOADED)
      - paths to their images point at WhoDidIt\<folder>
      - every file starts with "if WDI_<KEY>_SKIP then return end", so the
        built-in copy stands down if the separate addon is still switched on
      - .xml file lists (libraries) are expanded into WhoDidIt.toc
    WhoDidIt.toc gets their file list and saved variables, and
    WhoDidIt\Bindings.xml their key bindings. If a new version can't be
    adapted safely, the current one is kept.

    Updates are only swapped in while WoW is closed; one that arrives while
    you're playing is downloaded and installed when you exit.

    Pinned versions: each addon is installed at the exact commit in its Pin
    (below), a version the WhoDidIt maintainer has tested - never whatever
    happens to be newest upstream. To try a newer one: run with -Latest, test
    it in game, then put the commit it prints into Pin and release.

    WhoDidIt-Sync.ps1 runs this every hour. To run it on its own:
      EmbedUpdate.ps1                    check all of them and install updates
      EmbedUpdate.ps1 -Only RollFor      just one (Chronicle, RollFor or Doping)
      EmbedUpdate.ps1 -Force             download and reinstall even if up to date
#>
param([switch]$Force, [string]$Only = "", [switch]$Latest)
$script:EmbedLatest = $Latest

$EmbedUA    = "WhoDidIt-EmbedUpdate/1.0 (+https://github.com/bdot89/WhoDidIt)"
$AddonDir   = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$EmbedWow   = (Resolve-Path (Join-Path $AddonDir "..\..\..")).Path
$EmbedToc   = Join-Path $AddonDir "WhoDidIt.toc"
$EmbedBinds = Join-Path $AddonDir "Bindings.xml"
$EmbedUtf8  = New-Object Text.UTF8Encoding $false
# not needed in game: tests, docs, editor files, the other client's libraries
$EmbedSkip  = @("tests", "test", "examples", "docs", ".github", ".gitignore", ".idea", ".vscode", ".luarc.json",
                ".editorconfig", "bcc", "globaldefs.lua", "screenshots", "dev")

$EmbedSpecs = @{
    Chronicle = @{
        Name = "Chronicle logger"; Key = "CHRON"; Addon = "ChronicleCompanion"; Dest = "Chronicle"
        Repo = "Emyrk/ChronicleCompanion"; Ref = "branch"; Branch = "main"; SubDir = ""
        Pin = "b367dfe17d1183a43552d3985cad6362c7051457"; PinLabel = "0.38"
        VersionFn = "WDI_ChronVersion"; EqualsName = $true; Bindings = $false
        Begin = "# >>> Chronicle files (generated)"; End = "# <<< Chronicle files"
        # any use of its own name left over would break once it runs inside WhoDidIt
        Forbid = @('["'']ChronicleCompanion["'']')
    }
    RollFor = @{
        Name = "RollFor"; Key = "ROLLFOR"; Addon = "RollFor"; Dest = "RollFor"
        Repo = "sica42/roll-for-vanilla"; Ref = "release"; Branch = "master"; SubDir = "RollFor"
        Pin = "7f64d60872e66c4244c821986db56aacc11ed641"; PinLabel = "v4.8.1"
        VersionFn = "WDI_RollForVersion"; EqualsName = $false; Bindings = $true
        Begin = "# >>> RollFor files (generated)"; End = "# <<< RollFor files"
        # "RollFor" is also its chat/addon-message prefix, so only API uses are checked
        Forbid = @('GetAddOnMetadata\(\s*["'']RollFor["'']', 'IsAddOnLoaded\(\s*["'']RollFor["'']',
                   'AddOns[\\/]+RollFor[\\/]', 'ADDON_LOADED')
    }
    Doping = @{
        Name = "DopingControl"; Key = "DOPING"; Addon = "DopingControl"; Dest = "DopingControl"
        Repo = "ShempError/DopingControl"; Ref = "branch"; Branch = "main"; SubDir = ""
        Pin = "32403474ebb711c403a3a484bb383d567b7d4a03"; PinLabel = "0.6.4"
        VersionFn = "WDI_DopingVersion"; EqualsName = $true; Bindings = $false
        Begin = "# >>> DopingControl files (generated)"; End = "# <<< DopingControl files"
        # its .toc lists a developer-only file (dev\raiddump.lua) that isn't published
        AllowMissing = $true
        Forbid = @('GetAddOnMetadata\(\s*["'']DopingControl["'']', 'IsAddOnLoaded\(\s*["'']DopingControl["'']',
                   'AddOns[\\/]+DopingControl[\\/]', 'arg1\s*[~=]=\s*["'']DopingControl["'']')
    }
}

if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
    function Log($msg) { Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg) }
}

# ------------------------------------------------------------------ helpers

function Get-EmbedPaths($s) {
    @{ dir = (Join-Path $AddonDir $s.Dest); new = (Join-Path $AddonDir ($s.Dest + ".new")); old = (Join-Path $AddonDir ($s.Dest + ".old")) }
}

# <folder>\wdi_version.lua -> @{ version; commit; files; sv; svChar; binds }
function Get-EmbedInfo($s, $dir) {
    $f = Join-Path $dir "wdi_version.lua"
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $t = [IO.File]::ReadAllText($f)
    $files = @()
    foreach ($m in [regex]::Matches($t, '(?m)^-- file: (.+)$')) { $files += $m.Groups[1].Value.Trim() }
    $binds = @()
    foreach ($m in [regex]::Matches($t, '(?m)^-- binding: (.+)$')) { $binds += $m.Groups[1].Value.Trim() }
    return @{
        version = [regex]::Match($t, "WDI_$($s.Key)_VERSION\s*=\s*""([^""]*)""").Groups[1].Value
        commit  = [regex]::Match($t, "WDI_$($s.Key)_COMMIT\s*=\s*""([^""]*)""").Groups[1].Value
        sv      = [regex]::Match($t, '(?m)^-- savedvariables: (.*)$').Groups[1].Value.Trim()
        svChar  = [regex]::Match($t, '(?m)^-- savedvariablespercharacter: (.*)$').Groups[1].Value.Trim()
        files   = $files
        binds   = $binds
    }
}

function Test-WowRunning {
    foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
        try {
            if ($p.Path -and $p.Path.StartsWith($EmbedWow + "\", [StringComparison]::OrdinalIgnoreCase)) { return $true }
        } catch { }
    }
    return $false
}

function Get-GitHub($url) {
    Invoke-RestMethod -Uri $url -TimeoutSec 30 -Headers @{ "User-Agent" = $EmbedUA; "Accept" = "application/vnd.github+json" }
}

# the commit to install: the latest release's, or the branch head
function Get-EmbedTarget($s) {
    # the tested version, unless -Latest asks for the newest
    if ($s.Pin -and -not $script:EmbedLatest) {
        $c = Get-GitHub "https://api.github.com/repos/$($s.Repo)/commits/$($s.Pin)"
        return @{ sha = [string]$c.sha; date = ([datetime]$c.commit.committer.date).ToString("yyyy-MM-dd"); label = "pinned " + $s.PinLabel }
    }
    $label = $s.Branch
    $ref = $s.Branch
    if ($s.Ref -eq "release") {
        try {
            $rel = Get-GitHub "https://api.github.com/repos/$($s.Repo)/releases/latest"
            if ($rel.tag_name) { $ref = [string]$rel.tag_name; $label = $ref }
        } catch { }
    }
    $c = Get-GitHub "https://api.github.com/repos/$($s.Repo)/commits/$ref"
    return @{ sha = [string]$c.sha; date = ([datetime]$c.commit.committer.date).ToString("yyyy-MM-dd"); label = $label }
}

function Copy-EmbedTree($from, $to) {
    New-Item -ItemType Directory -Path $to -Force | Out-Null
    foreach ($i in Get-ChildItem -LiteralPath $from -Force) {
        if ($EmbedSkip -contains $i.Name -or $i.Extension -eq ".toc" -or $i.Extension -eq ".sh") { continue }
        $d = Join-Path $to $i.Name
        if ($i.PSIsContainer) { Copy-EmbedTree $i.FullName $d } else { Copy-Item -LiteralPath $i.FullName -Destination $d }
    }
}

# a .xml file list -> the .lua files it loads, in order (Include / Script only)
function Expand-EmbedXml($root, [string]$rel, $depth) {
    if ($depth -gt 5) { throw "'$rel' includes too deeply" }
    $path = Join-Path $root $rel
    if (-not (Test-Path -LiteralPath $path)) { throw "'$rel' isn't in the download" }
    $xml = [IO.File]::ReadAllText($path)
    $xml = [regex]::Replace($xml, '(?s)<!--.*?-->', '')
    $base = Split-Path $rel -Parent
    $out = @()
    foreach ($m in [regex]::Matches($xml, '<(\w+)\b([^>]*)/?>')) {
        $tag = $m.Groups[1].Value
        if ($tag -eq "Ui") { continue }
        $file = [regex]::Match($m.Groups[2].Value, 'file\s*=\s*"([^"]+)"').Groups[1].Value -replace '/', '\'
        $full = if ($base) { Join-Path $base $file } else { $file }
        if ($tag -eq "Include" -and $file) { $out += Expand-EmbedXml $root $full ($depth + 1) }
        elseif ($tag -eq "Script" -and $file) { $out += $full }
        else { throw "'$rel' uses <$tag> - only file lists can be built in" }
    }
    return $out
}

# the changes that let their files run from inside WhoDidIt
function Convert-EmbedLua($s, [string]$text) {
    $a = [regex]::Escape($s.Addon)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    $text = [regex]::Replace($text, '(?:[\w.:]+[.:])?GetAddOnMetadata\(\s*"' + $a + '"\s*,\s*"Version"\s*\)', $s.VersionFn + '()')
    $text = [regex]::Replace($text, 'GetAddOnMetadata\(\s*"' + $a + '"', 'GetAddOnMetadata("WhoDidIt"')
    $text = [regex]::Replace($text, 'IsAddOnLoaded\(\s*"' + $a + '"\s*\)', 'IsAddOnLoaded("WhoDidIt")')
    if ($s.EqualsName) { $text = [regex]::Replace($text, '(==|~=)\s*"' + $a + '"', '${1} "WhoDidIt"') }
    $text = [regex]::Replace($text, '(?i)Interface(\\\\|/)AddOns(\\\\|/)' + $a + '(\\\\|/)', 'Interface${1}AddOns${2}WhoDidIt${3}' + $s.Dest + '${3}')
    # same line as their first line, so error line numbers still match the source
    return "if WDI_$($s.Key)_SKIP then return end " + $text
}

function Split-Names([string]$list) { @($list -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

# WhoDidIt.toc with this addon's files and saved variables filled in
function New-EmbedToc($s, $info) {
    $raw = [IO.File]::ReadAllText($EmbedToc)
    $nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = $raw -split "\r?\n"
    $b = [Array]::IndexOf($lines, $s.Begin); $e = [Array]::IndexOf($lines, $s.End)
    if ($b -lt 0 -or $e -lt $b) { throw "WhoDidIt.toc is missing the '$($s.Begin)' / '$($s.End)' lines" }
    $out = New-Object System.Collections.Generic.List[string]
    $haveChar = $false
    for ($i = 0; $i -lt $b; $i++) {
        $l = $lines[$i]
        # saved variables: add theirs, never remove (the other built-in addon's are on the same line)
        if ($l -match '^##\s*SavedVariables(PerCharacter)?\s*:\s*(.*)$') {
            $isChar = [bool]$matches[1]
            $names = @(Split-Names $matches[2])
            $add = if ($isChar) { @(Split-Names $info.svChar) } else { @(Split-Names $info.sv) }
            foreach ($n in $add) { if ($names -notcontains $n) { $names += $n } }
            if ($isChar) { $haveChar = $true; $out.Add("## SavedVariablesPerCharacter: " + ($names -join ", ")) }
            else { $out.Add("## SavedVariables: " + ($names -join ", ")) }
            continue
        }
        $out.Add($l)
    }
    if (-not $haveChar -and $info.svChar) {
        $at = 0
        for ($i = 0; $i -lt $out.Count; $i++) { if ($out[$i] -match '^##\s*SavedVariables\s*:') { $at = $i + 1 } }
        $out.Insert($at, "## SavedVariablesPerCharacter: " + ((Split-Names $info.svChar) -join ", "))
    }
    $out.Add($s.Begin)
    $out.Add($s.Dest + "\wdi_version.lua")
    foreach ($f in $info.files) { $out.Add($s.Dest + "\" + $f) }
    for ($i = $e; $i -lt $lines.Count; $i++) { $out.Add($lines[$i]) }
    $text = ($out -join $nl)
    return @{ text = $text; changed = ($text -ne $raw) }
}

# WhoDidIt\Bindings.xml with this addon's key bindings filled in
function New-EmbedBindings($s, $info) {
    if (-not $s.Bindings) { return @{ changed = $false } }
    $raw = [IO.File]::ReadAllText($EmbedBinds)
    $begin = "<!-- >>> $($s.Name) bindings (generated) -->"; $end = "<!-- <<< $($s.Name) bindings -->"
    $b = $raw.IndexOf($begin); $e = $raw.IndexOf($end)
    if ($b -lt 0 -or $e -lt $b) { throw "Bindings.xml is missing the '$begin' / '$end' lines" }
    $nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $body = ""
    foreach ($x in $info.binds) { $body += "`t" + $x + $nl }
    $text = $raw.Substring(0, $b + $begin.Length) + $nl + $body + "`t" + $raw.Substring($e)
    return @{ text = $text; changed = ($text -ne $raw) }
}

# ------------------------------------------------------------------ build + install

function Build-EmbedStaging($s, $t) {
    $p = Get-EmbedPaths $s
    $short = $t.sha.Substring(0, 7)
    $zip = Join-Path $env:TEMP "wdi-$($s.Dest)-$short.zip"
    $tmp = Join-Path $env:TEMP "wdi-$($s.Dest)-$short"
    try {
        Invoke-WebRequest -Uri "https://codeload.github.com/$($s.Repo)/zip/$($t.sha)" -OutFile $zip -UseBasicParsing -TimeoutSec 120 -Headers @{ "User-Agent" = $EmbedUA }
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
        $src = (Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1).FullName
        if ($s.SubDir) { $src = Join-Path $src $s.SubDir }
        $toc = Join-Path $src ($s.Addon + ".toc")
        if (-not (Test-Path -LiteralPath $toc)) { throw "no $($s.Addon).toc in the download" }

        # their .toc: version, saved variables, file list (.xml lists expanded)
        $meta = @{}; $files = @()
        foreach ($l in [IO.File]::ReadAllLines($toc)) {
            $x = $l.Trim()
            if ($x -match '^##\s*([^:]+?)\s*:\s*(.*)$') { $meta[$matches[1]] = $matches[2].Trim(); continue }
            if ($x -eq "" -or $x.StartsWith("#")) { continue }
            $x = $x -replace '/', '\'
            if ($x -match '\.\.' -or $x -match '^[\\/]' -or $x -match ':') { throw "unexpected file path '$x' in their .toc" }
            if ($x -match '\.xml$') { $files += Expand-EmbedXml $src $x 0 }
            elseif ($x -match '\.lua$') { $files += $x }
            else { throw "their .toc loads '$x', which can't be built in" }
        }
        $version = ($meta["Version"] -replace '[^0-9A-Za-z._-]', '')
        if (-not $version) { throw "no version in their .toc" }
        if ($files.Count -eq 0) { throw "their .toc lists no files" }

        # key bindings
        $binds = @()
        if ($s.Bindings) {
            $bf = Join-Path $src "Bindings.xml"
            if (Test-Path -LiteralPath $bf) {
                $bx = [regex]::Replace([IO.File]::ReadAllText($bf), '(?s)<!--.*?-->', '')
                foreach ($m in [regex]::Matches($bx, '(?s)<Binding\b[^>]*>.*?</Binding>')) {
                    $b = ($m.Value -replace '\s*\r?\n\s*', ' ').Trim()
                    # a key pressed while the addon isn't loaded must not raise an error
                    $b = $b -replace '>\s*(RollFor\.key_bindings\.\w+)\(\)\s*<', '>if RollFor and RollFor.key_bindings then $1() end<'
                    $binds += $b
                }
            }
        }

        if (Test-Path $p.new) { Remove-Item $p.new -Recurse -Force }
        if ($s.AllowMissing) {
            # the game skips a listed file that doesn't exist, so do the same
            $files = @($files | Where-Object { Test-Path -LiteralPath (Join-Path $src $_) })
        }
        Copy-EmbedTree $src $p.new
        $bad = @()
        foreach ($f in $files) {
            $fp = Join-Path $p.new $f
            if (-not (Test-Path -LiteralPath $fp)) { throw "their .toc loads '$f' but it isn't in the download" }
            $lua = Convert-EmbedLua $s ([IO.File]::ReadAllText($fp))
            $n = 0
            foreach ($ln in ($lua -split "\n")) {
                $n++
                foreach ($pat in $s.Forbid) { if ($ln -match $pat) { $bad += "$f line $n" } }
            }
            [IO.File]::WriteAllText($fp, $lua, $EmbedUtf8)
        }
        if ($bad.Count -gt 0) { throw ("their code uses its own name in a way WhoDidIt can't adapt (" + (($bad | Select-Object -First 5) -join ", ") + ")") }

        $v = New-Object System.Collections.Generic.List[string]
        $v.Add("-- Generated by WhoDidIt's tools\WhoDidIt-Sync - do not edit.")
        $v.Add("-- $($s.Addon) from https://github.com/$($s.Repo) ($($t.label), commit $($t.sha))")
        $v.Add("-- savedvariables: " + $meta["SavedVariables"])
        $v.Add("-- savedvariablespercharacter: " + $meta["SavedVariablesPerCharacter"])
        foreach ($f in $files) { $v.Add("-- file: $f") }
        foreach ($x in $binds) { $v.Add("-- binding: $x") }
        $v.Add("WDI_$($s.Key)_VERSION = `"$version`"")
        $v.Add("WDI_$($s.Key)_COMMIT = `"$($t.sha)`"")
        $v.Add("WDI_$($s.Key)_DATE = `"$($t.date)`"")
        [IO.File]::WriteAllText((Join-Path $p.new "wdi_version.lua"), (($v -join "`n") + "`n"), $EmbedUtf8)
        return (Get-EmbedInfo $s $p.new)
    } catch {
        if (Test-Path $p.new) { Remove-Item $p.new -Recurse -Force -ErrorAction SilentlyContinue }
        throw
    } finally {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# swap <folder>.new in, update WhoDidIt.toc and Bindings.xml; $true if either changed
function Install-EmbedStaging($s) {
    $p = Get-EmbedPaths $s
    $info = Get-EmbedInfo $s $p.new
    if (-not $info) { throw "$($s.Dest).new is incomplete" }
    $toc = New-EmbedToc $s $info
    $bnd = New-EmbedBindings $s $info
    if (Test-Path $p.old) { Remove-Item $p.old -Recurse -Force }
    if (Test-Path $p.dir) { Rename-Item -LiteralPath $p.dir -NewName ($s.Dest + ".old") }
    try {
        Rename-Item -LiteralPath $p.new -NewName $s.Dest
    } catch {
        if (Test-Path $p.old) { Rename-Item -LiteralPath $p.old -NewName $s.Dest }
        throw
    }
    if ($toc.changed) { [IO.File]::WriteAllText($EmbedToc, $toc.text, $EmbedUtf8) }
    if ($bnd.changed) { [IO.File]::WriteAllText($EmbedBinds, $bnd.text, $EmbedUtf8) }
    if (Test-Path $p.old) { Remove-Item $p.old -Recurse -Force -ErrorAction SilentlyContinue }
    return ($toc.changed -or $bnd.changed)
}

# ------------------------------------------------------------------ main

function Update-Embedded($s, [switch]$Force) {
    $p = Get-EmbedPaths $s
    $running = Test-WowRunning

    # an update downloaded while WoW was open
    if ((Test-Path $p.new) -and -not $running) {
        $st = Get-EmbedInfo $s $p.new
        try {
            [void](Install-EmbedStaging $s)
            Log "$($s.Name): installed v$($st.version), downloaded earlier"
        } catch { Log ("$($s.Name): couldn't install the downloaded update: " + $_.Exception.Message) }
    }

    $have = Get-EmbedInfo $s $p.dir
    try {
        $t = Get-EmbedTarget $s
    } catch {
        Log ("$($s.Name): couldn't check for updates (" + $_.Exception.Message + ")")
        return
    }
    if (-not $Force -and $have -and $have.commit -eq $t.sha) {
        Log "$($s.Name): v$($have.version) is up to date"
        return
    }
    $staged = Get-EmbedInfo $s $p.new
    if (-not $Force -and $staged -and $staged.commit -eq $t.sha) {
        Log "$($s.Name): v$($staged.version) is downloaded and installs when WoW is closed"
        return
    }

    try {
        $new = Build-EmbedStaging $s $t
    } catch {
        $keep = if ($have) { "keeping v$($have.version)" } else { "not installed" }
        Log ("$($s.Name): update skipped, $keep - " + $_.Exception.Message)
        return
    }
    $what = if ($have) { "updated v$($have.version) -> v$($new.version)" } else { "installed v$($new.version)" }

    # first install: nothing to disturb. Updates wait until WoW is closed.
    if ($running -and $have) {
        Log "$($s.Name): v$($new.version) downloaded ($($t.label), $($t.date)) - it installs when you close WoW"
        return
    }
    try {
        $changed = Install-EmbedStaging $s
    } catch {
        Log ("$($s.Name): couldn't install: " + $_.Exception.Message)
        return
    }
    Log "$($s.Name): $what ($($t.label), $($t.sha.Substring(0, 7)), $($t.date))"
    if ($running -and $changed) { Log "$($s.Name): exit WoW and start it again to load it (a /reload isn't enough)" }
}

function Update-Chronicle([switch]$Force) { Update-Embedded $EmbedSpecs.Chronicle -Force:$Force }
function Update-RollFor([switch]$Force) { Update-Embedded $EmbedSpecs.RollFor -Force:$Force }
function Update-Doping([switch]$Force) { Update-Embedded $EmbedSpecs.Doping -Force:$Force }

# run directly (not dot-sourced by WhoDidIt-Sync)
if ($MyInvocation.InvocationName -ne ".") {
    $ErrorActionPreference = "Stop"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    foreach ($k in @("Chronicle", "RollFor", "Doping")) {
        if ($Only -and $Only -ne $k) { continue }
        Update-Embedded $EmbedSpecs[$k] -Force:$Force
    }
}
