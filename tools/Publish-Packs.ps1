<#
    Publish-Packs - for the WhoDidIt maintainer: makes the packs you learned
    and saved in game the standard packs everyone gets with the download.

    In game first: /wdi marks export (writes CustomData\WhoDidIt_StdPacks.lua).
    Then double-click Publish-Packs.cmd: it checks that file, copies it over
    DefaultPacks.lua in the addon, and commits and pushes it. Needs git with
    push access to the repository.

    It only accepts the exact lines the export writes (comments, the table
    header, one line per pack, the closing line), refuses an export with fewer
    than -MinPacks packs or less than half the packs published now (-Force
    publishes anyway), and only pushes main, after catching up with GitHub.
#>
param([int]$MinPacks = 10, [switch]$Force)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$wow = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$src = Join-Path $wow "CustomData\WhoDidIt_StdPacks.lua"
$dst = Join-Path $repo "DefaultPacks.lua"

if (-not (Test-Path -LiteralPath $src)) {
    Write-Host "Nothing to publish: type /wdi marks export in game first (it writes $src)."
    return
}
$text = [IO.File]::ReadAllText($src) -replace "`r`n", "`n"
# only the lines the export writes (MarkLearn.lua, L:Export), nothing else:
#   -- comment
#   WDI_STDPACKS = { date = "2026-10-07", packs = {
#   <tab>{ "zone", "pack name", { "guid", mark, "mob name", ... } },
#   } }
$q = '"(?:[^"\\\n]|\\.)*"'
$mob = "$q, \d+, $q"
$grammar = @(
    '^-- [^\n]*$',
    ('^WDI_STDPACKS = \{ date = ' + $q + ', packs = \{$'),
    ('^\t\{ ' + $q + ', ' + $q + ', \{ (' + $mob + '(, ' + $mob + ')*)? \} \},$'),
    '^\} \}$',
    '^$'
)
$n = 0
foreach ($line in ($text -split "`n")) {
    $n++
    $ok = $false
    foreach ($g in $grammar) { if ($line -match $g) { $ok = $true; break } }
    if (-not $ok) { throw "Line $n isn't something the pack export writes - not publishing it:`n  $line" }
}
if ($text -notmatch '(?m)^WDI_STDPACKS = \{') { throw "That file doesn't look like a WhoDidIt pack export." }
$packs = ([regex]::Matches($text, '(?m)^\t\{ ')).Count
# an empty or much smaller export would take the packs away from everyone
$now = 0
if (Test-Path -LiteralPath $dst) { $now = ([regex]::Matches([IO.File]::ReadAllText($dst), '(?m)^\t\{ ')).Count }
if (-not $Force -and ($packs -lt $MinPacks -or $packs -lt [math]::Floor($now / 2))) {
    throw "The export has $packs packs (published now: $now). That looks wrong, so it isn't published. Publish-Packs.ps1 -Force publishes it anyway."
}
[IO.File]::WriteAllText($dst, $text, (New-Object Text.UTF8Encoding($false)))
Write-Host "DefaultPacks.lua now has $packs packs."

Push-Location $repo
$ErrorActionPreference = "Continue"   # git prints line-ending warnings on stderr
try {
    $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
    if ($branch -ne "main") { throw "The repository is on '$branch', not main - switch to main first." }
    # catch up with GitHub first, so the push isn't refused for being behind
    git pull -q --rebase --autostash origin main 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git pull failed - fix that first (nothing was committed)" }
    git add DefaultPacks.lua 2>$null
    git diff --cached --quiet -- DefaultPacks.lua
    if ($LASTEXITCODE -eq 0) { Write-Host "No change since the last publish."; return }
    git commit -q -m "Standard raid packs ($packs, learned in game)" -- DefaultPacks.lua 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
    git push -q origin main 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git push failed - check you can push to the repository" }
    Write-Host "Published: everyone who downloads WhoDidIt now gets these packs."
} finally {
    Pop-Location
}
