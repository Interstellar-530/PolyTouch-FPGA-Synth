param(
    [string]$FsFile = '',
    [string]$Device = 'GW2A-18C',
    [int]$Operation = 2,
    [switch]$SkipSimulation
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $SkipSimulation) {
    throw 'DDR3 smoke test has no full RTL simulation yet. Re-run with -SkipSimulation only for the documented hardware bring-up exception.'
}
if (-not $FsFile) { $FsFile = Join-Path $root 'src\impl\pnr\ddr3_smoke.fs' }
$fs = (Resolve-Path -LiteralPath $FsFile).Path
$programmer = 'D:\Gowin_V1.9.11.03_Education_x64_win\Gowin\Gowin_V1.9.11.03_Education_x64\Programmer\bin\programmer_cli.exe'
if (-not (Test-Path -LiteralPath $programmer -PathType Leaf)) { throw "programmer_cli.exe not found: $programmer" }
Write-Warning 'Skipping simulation. This is a hardware bring-up exception; record the reason before programming.'
& $programmer --device $Device --operation_index ([string]$Operation) --fsFile $fs
exit $LASTEXITCODE