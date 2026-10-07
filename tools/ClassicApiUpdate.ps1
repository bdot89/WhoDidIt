<#
    ClassicApiUpdate - installs and updates ClassicAPI, an OPTIONAL extra
    for WhoDidIt.

    ClassicAPI (github.com/brues-code/ClassicAPI, GPL-3.0, by brues-code) is
    a client DLL that adds many newer WoW API functions to the 1.12 client.
    WhoDidIt works fine without it; with it you get a few extras (see
    "ClassicAPI (optional)" in the README).

    What installing does:
      1. downloads ClassicAPI.dll from the release the WhoDidIt maintainer
         has tested (pinned below, like every other download), not whatever
         is newest
      2. checks its SHA-256 against the checksum pinned here (and the one
         GitHub publishes) - if they don't match, nothing is changed
      3. backs up dlls.txt (dlls.txt.bak, once) and copies the DLL into the
         WoW folder
      4. adds "ClassicAPI.dll" to dlls.txt, the list of DLLs VanillaFixes
         loads when the game starts

    Nothing updates it behind your back: run Install-ClassicAPI.cmd again
    (WoW closed) after a WhoDidIt update to get a newer pinned version. If
    you never install it, this does nothing.

    To remove it: delete the ClassicAPI.dll line from dlls.txt (or put
    dlls.txt.bak back) and restart WoW.

    Usage (or double-click Install-ClassicAPI.cmd):
      ClassicApiUpdate.ps1 -Install     install it, or update it
      ClassicApiUpdate.ps1              update it only if already installed
      ClassicApiUpdate.ps1 -Install -Latest   testers: the newest release instead
                                            (checked against GitHub's checksum only)
#>
param([switch]$Install, [switch]$Latest)

# the tested release and the SHA-256 of its ClassicAPI.dll (maintainer: update both together)
$CapiPin    = "v1.15.16"
$CapiPinSha = "e34886fb9725b9059375a5c37bff81ce220633c4e2c39719ef3223a6b8fc703d"

$CapiUA   = "WhoDidIt-ClassicApiUpdate/1.0 (+https://github.com/bdot89/WhoDidIt)"
$CapiRepo = "brues-code/ClassicAPI"
$CapiWow  = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
$CapiDll  = Join-Path $CapiWow "ClassicAPI.dll"
$CapiList = Join-Path $CapiWow "dlls.txt"

if (-not (Get-Command Log -ErrorAction SilentlyContinue)) {
    function Log($msg) { Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $msg) }
}

function Test-ClassicApiListed {
    if (-not (Test-Path -LiteralPath $CapiList)) { return $false }
    foreach ($l in [IO.File]::ReadAllLines($CapiList)) {
        if ($l.Trim() -ieq "ClassicAPI.dll") { return $true }
    }
    return $false
}

function Test-ClassicApiGameRunning {
    foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
        try {
            if ($p.Path -and $p.Path.StartsWith($CapiWow + "\", [StringComparison]::OrdinalIgnoreCase)) { return $true }
        } catch { }
    }
    return $false
}

function Get-FileSha256($path) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Update-ClassicAPI([switch]$Install, [switch]$Latest) {
    $installed = (Test-Path -LiteralPath $CapiDll) -and (Test-ClassicApiListed)
    if (-not $installed -and -not $Install) { return }   # optional: never installed without asking

    if (-not (Test-Path -LiteralPath (Join-Path $CapiWow "VanillaFixes.exe"))) {
        Log "ClassicAPI: VanillaFixes.exe isn't in $CapiWow - ClassicAPI needs it to load, so nothing was changed"
        return
    }
    try {
        $which = if ($Latest) { "latest" } else { "tags/$CapiPin" }
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$CapiRepo/releases/$which" -TimeoutSec 30 `
            -Headers @{ "User-Agent" = $CapiUA; "Accept" = "application/vnd.github+json" }
    } catch {
        Log ("ClassicAPI: couldn't check for updates (" + $_.Exception.Message + ")")
        return
    }
    $asset = $rel.assets | Where-Object { $_.name -eq "ClassicAPI.dll" } | Select-Object -First 1
    if (-not $asset) { Log "ClassicAPI: the latest release ($($rel.tag_name)) has no ClassicAPI.dll"; return }
    $want = ([string]$asset.digest -replace '^sha256:', '').ToLowerInvariant()
    if ($Latest) {
        if ($want -notmatch '^[0-9a-f]{64}$') { Log "ClassicAPI: GitHub gave no checksum for $($rel.tag_name), so it wasn't installed"; return }
        Log "ClassicAPI: testing the newest release, $($rel.tag_name) (not the pinned $CapiPin)"
    } else {
        # the pinned checksum decides; a release whose file changed since it was tested is refused
        if ($want -and $want -ne $CapiPinSha) { Log "ClassicAPI: the file in release $CapiPin isn't the one that was tested - nothing was changed"; return }
        $want = $CapiPinSha
    }

    $have = if (Test-Path -LiteralPath $CapiDll) { Get-FileSha256 $CapiDll } else { "" }
    if ($have -eq $want -and (Test-ClassicApiListed)) {
        Log "ClassicAPI: $($rel.tag_name) is installed and up to date"
        return
    }
    if (Test-ClassicApiGameRunning) {
        $what = if ($have) { "an update ($($rel.tag_name))" } else { "it" }
        Log "ClassicAPI: close WoW first - $what can only be installed while the game is closed"
        return
    }

    $tmp = Join-Path $env:TEMP ("wdi-ClassicAPI-" + $rel.tag_name + ".dll")
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -UseBasicParsing -TimeoutSec 120 -Headers @{ "User-Agent" = $CapiUA }
        $got = Get-FileSha256 $tmp
        if ($got -ne $want) { Log "ClassicAPI: the download's checksum doesn't match GitHub's - not installed"; return }

        if ((Test-Path -LiteralPath $CapiList) -and -not (Test-Path -LiteralPath ($CapiList + ".bak"))) {
            Copy-Item -LiteralPath $CapiList -Destination ($CapiList + ".bak")
        }
        Copy-Item -LiteralPath $tmp -Destination $CapiDll -Force
        if (-not (Test-ClassicApiListed)) {
            $raw = if (Test-Path -LiteralPath $CapiList) { [IO.File]::ReadAllText($CapiList) } else { "" }
            $nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
            if ($raw.Length -gt 0 -and -not $raw.EndsWith("`n")) { $raw += $nl }
            [IO.File]::WriteAllText($CapiList, $raw + "ClassicAPI.dll" + $nl, (New-Object Text.UTF8Encoding $false))
        }
        $verb = if ($have) { "updated to" } else { "installed" }
        Log "ClassicAPI: $verb $($rel.tag_name) (checksum OK). Start WoW through your launcher as usual; /wdi status shows it."
    } catch {
        Log ("ClassicAPI: install failed - " + $_.Exception.Message)
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

# run directly (not dot-sourced by WhoDidIt-Sync)
if ($MyInvocation.InvocationName -ne ".") {
    $ErrorActionPreference = "Stop"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if ($Install) {
        Log "ClassicAPI is optional: WhoDidIt works without it. It adds a few extras (see the README)."
    }
    Update-ClassicAPI -Install:$Install -Latest:$Latest
}
