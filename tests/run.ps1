# Runs tests\withdraw.lua (the offline replay of withdrawing a wrong 5-man run) on DmorphOcto's
# LuaHost (LuaJIT from OBS Studio with Lua 5.0 shims). LuaJIT accepts #, % and ... that 5.0 does
# not: run AddOns\OctoBG\tools\LuaCheck.ps1 on the .lua as well.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run.ps1
# Needs git (the 1.26.0 comparison client comes from commit eaaa906) and LuaHost built once.
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$exe = Join-Path $root "..\DmorphOcto\tools\LuaHost\bin\LuaHost.exe"
if (-not (Test-Path $exe)) { throw "LuaHost not built: run DmorphOcto\tools\run_tests.ps1 once" }

# scratch: the 1.26.0 files and a WoW tree (wow\CustomData, wow\Interface\AddOns\WhoDidIt\tools)
# for a copy of Publish-RaidTimes.ps1
$tmp = Join-Path $env:TEMP "wdi-withdraw-test"
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
$old = Join-Path $tmp "old126"
$tools = Join-Path $tmp "wow\Interface\AddOns\WhoDidIt\tools"
New-Item -ItemType Directory -Force $old, $tools, (Join-Path $tmp "wow\CustomData") | Out-Null
Copy-Item (Join-Path $root "tools\Publish-RaidTimes.ps1") $tools

Push-Location $root
try {
    # 1.26.0 as released (Data.lua is unchanged since, so the current one is loaded for it too)
    foreach ($f in "Board.lua", "Dungeons.lua") {
        $text = (git show "eaaa906:$f") -join "`n"
        if ($LASTEXITCODE -ne 0) { throw "git show eaaa906:$f failed" }
        [IO.File]::WriteAllText((Join-Path $old $f), $text + "`n", (New-Object Text.UTF8Encoding($false)))
    }
    $env:WDI_TMP = $tmp
    $env:WDI_OLD = $old
    & $exe "tests/withdraw.lua"
    exit $LASTEXITCODE
} finally { Pop-Location }
