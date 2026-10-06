<#
    Publish-RaidTimes - for the WhoDidIt maintainer: refreshes ChronicleData.lua
    (every guild's raid times, shipped inside the addon) and pushes it to
    GitHub, so players get new times just by updating WhoDidIt.

    It runs WhoDidIt-Sync.ps1 -CI (guild times only - no characters are read
    or written), keeping its cache in .ci\ in the repository (git-ignored),
    then commits and pushes ChronicleData.lua if any time changed.

    Run it now and then, or from a Windows scheduled task. Needs git, with
    push access to the repository.
#>
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ci = Join-Path $repo ".ci"
New-Item -ItemType Directory -Force $ci | Out-Null
$lua = Join-Path $repo "ChronicleData.lua"

& (Join-Path $PSScriptRoot "WhoDidIt-Sync.ps1") -CI -DataDir $ci -LuaOut $lua -DetailsPerSync 600

Push-Location $repo
$ErrorActionPreference = "Continue"   # git prints line-ending warnings on stderr
try {
    git add ChronicleData.lua 2>$null
    # only the "synced at" stamp changed: nothing worth publishing
    $real = @(git diff --cached -U0 -- ChronicleData.lua | Where-Object { $_ -match '^[+-]' -and $_ -notmatch '^(\+\+\+|---)' -and $_ -notmatch 'WDICHRON\|' }).Count
    if ($real -eq 0) {
        git reset -q -- ChronicleData.lua
        Write-Host "No new raid times - nothing to publish."
        return
    }
    git commit -q -m ("Chronicle raid times " + (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm") + " UTC") -- ChronicleData.lua 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
    git push -q 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git push failed - check you can push to the repository" }
    Write-Host "Published new raid times ($real changed lines)."
} finally {
    Pop-Location
}
