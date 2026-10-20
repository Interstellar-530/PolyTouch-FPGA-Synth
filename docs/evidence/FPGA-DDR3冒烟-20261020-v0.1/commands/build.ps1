$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$gwsh = 'D:\Gowin_V1.9.11.03_Education_x64_win\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe'
if (-not (Test-Path -LiteralPath $gwsh -PathType Leaf)) { throw "gw_sh.exe not found: $gwsh" }
& $gwsh (Join-Path $root 'build.tcl')
if ($LASTEXITCODE -ne 0) { throw "Gowin build failed: exit $LASTEXITCODE" }
$fs = Join-Path $root 'src\impl\pnr\ddr3_smoke.fs'
if (-not (Test-Path -LiteralPath $fs -PathType Leaf)) { throw "No bitstream: $fs" }
Get-Item -LiteralPath $fs | Select-Object Length,LastWriteTime,FullName