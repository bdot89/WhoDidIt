<#
    Publish-Packs - for the WhoDidIt maintainer: makes the packs you learned
    and saved in game the standard packs everyone gets with the download.

    In game first: /wdi marks export (writes CustomData\WhoDidIt_StdPacks.lua).
    Then double-click Publish-Packs.cmd: it checks that file, copies it over
    DefaultPacks.lua in the addon, and commits and pushes it. Needs git with
    push access to the repository.
#>
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$wow = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$src = Join-Path $wow "CustomData\WhoDidIt_StdPacks.lua"
$dst = Join-Path $repo "DefaultPacks.lua"

if (-not (Test-Path -LiteralPath $src)) {
    Write-Host "Nothing to publish: type /wdi marks export in game first (it writes $src)."
    return
}
$text = [IO.File]::ReadAllText($src)
# only what the export writes: the WDI_STDPACKS table, nothing else
if ($text -notmatch '(?m)^WDI_STDPACKS = \{') { throw "That file doesn't look like a WhoDidIt pack export." }
if ($text -match '(?i)\b(function|loadstring|RunScript|SendChatMessage|setglobal|getglobal|_G)\b') { throw "That file contains code, not just pack data - not publishing it." }
$packs = ([regex]::Matches($text, '(?m)^\t\{ ')).Count
[IO.File]::WriteAllText($dst, $text, (New-Object Text.UTF8Encoding($false)))
Write-Host "DefaultPacks.lua now has $packs packs."

Push-Location $repo
$ErrorActionPreference = "Continue"   # git prints line-ending warnings on stderr
try {
    git add DefaultPacks.lua 2>$null
    git diff --cached --quiet -- DefaultPacks.lua
    if ($LASTEXITCODE -eq 0) { Write-Host "No change since the last publish."; return }
    git commit -q -m "Standard raid packs ($packs, learned in game)" -- DefaultPacks.lua 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
    git push -q 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git push failed - check you can push to the repository" }
    Write-Host "Published: everyone who downloads WhoDidIt now gets these packs."
} finally {
    Pop-Location
}
