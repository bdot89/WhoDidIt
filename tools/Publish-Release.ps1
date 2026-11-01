<#
    Publish-Release - for the WhoDidIt maintainer: a GitHub Release for the current
    version, with WhoDidIt.zip attached.

    Why: GitHub counts every download of a release's file (it can't count
    "Download ZIP"), and the zip's folder is already called WhoDidIt, so players
    don't have to rename "WhoDidIt-main". The README's install link points at the
    latest release's zip:
      https://github.com/bdot89/WhoDidIt/releases/latest/download/WhoDidIt.zip

    The zip is made by git from what's on GitHub (origin/main), exactly like
    "Download ZIP": the maintainer's tools are left out (.gitattributes
    export-ignore). The version is the one in WhoDidIt.toc there; a version that
    already has a release is left alone (-Force puts a fresh zip on it instead, which
    restarts its download count).

    When the version already has one but RaidTimes.lua changed since the latest
    release (the helper's daily publish), it puts out a "times" release instead:
    tag v<version>-times-<yyyymmdd>, marked latest, so the download link carries
    the newest raid times and each release keeps its own download count.

      Publish-Release.ps1            release the current version (or new raid times) if it has none yet
      Publish-Release.ps1 -Force     replace the zip on the current version's release
      Publish-Release.ps1 -Auto      (the sync helper, daily) quiet unless it releases
      Publish-Release.ps1 -Count     show the download counts

    Needs GitHub's command line tool (gh), logged in with push access.
#>
param([switch]$Force, [switch]$Auto, [switch]$Count)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$slug = "bdot89/WhoDidIt"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    if (-not $Auto) { Write-Host "GitHub's command line tool (gh) isn't installed - https://cli.github.com" }
    return
}

if ($Count) {
    $rel = gh api "repos/$slug/releases" | ConvertFrom-Json
    $total = 0
    foreach ($r in $rel) {
        foreach ($a in $r.assets) {
            Write-Host ("{0,-10} {1,-16} {2,6} downloads   ({3})" -f $r.tag_name, $a.name, $a.download_count, $r.published_at.Substring(0, 10))
            $total += $a.download_count
        }
    }
    Write-Host "All releases: $total downloads"
    return
}

Push-Location $repo
$ErrorActionPreference = "Continue"   # git and gh print progress on stderr
try {
    git fetch -q origin main 2>$null
    $sha = (git rev-parse origin/main 2>$null).Trim()
    if (-not $sha) { throw "couldn't read origin/main" }
    $toc = (git show "origin/main:WhoDidIt.toc" 2>$null) -join "`n"
    $m = [regex]::Match($toc, '(?m)^## Version:\s*([0-9][0-9.]*)')
    if (-not $m.Success) { throw "no version in WhoDidIt.toc" }
    $ver = $m.Groups[1].Value
    $tag = "v$ver"

    gh release view $tag --repo $slug 2>$null | Out-Null
    $exists = ($LASTEXITCODE -eq 0)
    $times = $null   # a "times" release: the same version, newer raid times
    if ($exists -and -not $Force) {
        # the daily raid times (RaidTimes.lua) changed since the latest release: a release for
        # them, so the latest-release link has them (each one keeps its own download count)
        $latest = (gh release view --repo $slug --json tagName --jq ".tagName" 2>$null)
        if ($latest) { git fetch -q origin "refs/tags/${latest}:refs/tags/${latest}" 2>$null }
        if ($latest) { git diff --quiet $latest $sha -- RaidTimes.lua 2>$null }
        if ($latest -and $LASTEXITCODE -eq 1) {
            $at = [long](git log -1 --format=%ct $sha -- RaidTimes.lua 2>$null)
            $times = [DateTimeOffset]::FromUnixTimeSeconds($at).UtcDateTime
            $tag = "v$ver-times-" + $times.ToString("yyyyMMdd")
            gh release view $tag --repo $slug 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $times = $null }
        }
        if (-not $times) {
            if (-not $Auto) { Write-Host "v$ver already has a release, and the raid times haven't changed since $latest (-Force replaces its zip)." }
            return
        }
        $exists = $false
    }

    # the zip: exactly what "Download ZIP" has, in a folder called WhoDidIt
    $tmp = Join-Path $env:TEMP "wdi-release"
    New-Item -ItemType Directory -Force $tmp | Out-Null
    $zip = Join-Path $tmp "WhoDidIt.zip"
    if (Test-Path -LiteralPath $zip) { [IO.File]::Delete($zip) }
    git archive --format=zip --prefix=WhoDidIt/ -o $zip $sha 2>$null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $zip)) { throw "git archive failed" }

    if ($exists) {
        gh release upload $tag $zip --clobber --repo $slug 2>$null
        if ($LASTEXITCODE -ne 0) { throw "gh release upload failed" }
        Write-Host "Replaced WhoDidIt.zip on $tag."
        return
    }

    # what changed since the last release (commit subjects)
    $prev = (gh release list --repo $slug --limit 1 --json tagName --jq ".[0].tagName" 2>$null)
    $changes = @()
    if ($prev) { $changes = @(git log --format="- %s" "$prev..$sha" 2>$null | Where-Object { $_ -notmatch '^- (Raid times snapshot|docs:|README)' }) }
    $notes = @"
## Install

1. Download **WhoDidIt.zip** below.
2. Unzip it into ``World of Warcraft\Interface\AddOns\``. You get a folder called ``WhoDidIt`` - nothing to rename.
3. Make sure **Nampower** and **SuperWoW** are installed, start the game and type ``/wdi``.

**Updating:** close the game, delete the old ``WhoDidIt`` folder and unzip the new one in its place. Your settings,
fights and Hall of Fame are kept (they're saved in the ``WTF`` folder, not in the addon).

Everything is in the zip - the Chronicle logger, RollFor, DopingControl and the Auto Marker's raid packs. Nothing to run.

"@
    $title = "WhoDidIt $ver"
    if ($times) {
        $day = $times.ToString("d MMM yyyy", [Globalization.CultureInfo]::InvariantCulture)
        $title = "WhoDidIt $ver (raid times $day)"
        $notes = "**Fresh raid times** (every guild's kill and clear times, and the 5-man runs) as of $day. WhoDidIt itself is " +
            "the same as $ver, so update only if you want the newer times.`n`n" + $notes
    } elseif ($changes.Count -gt 0) { $notes += "## Changes since $prev`n`n" + (($changes | Select-Object -First 40) -join "`n") + "`n" }
    $notesFile = Join-Path $tmp "notes.md"
    [IO.File]::WriteAllText($notesFile, $notes, (New-Object Text.UTF8Encoding($false)))

    gh release create $tag $zip --repo $slug --target $sha --title $title --notes-file $notesFile --latest 2>$null
    if ($LASTEXITCODE -ne 0) { throw "gh release create failed" }
    Write-Host "Released $tag with WhoDidIt.zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB): https://github.com/$slug/releases/tag/$tag"
} finally {
    Pop-Location
}
