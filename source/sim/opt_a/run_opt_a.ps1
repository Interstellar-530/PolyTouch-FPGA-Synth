# A-line offline optimisation gate (sim/opt_a).
#
# Standalone runner: it does not need the shared registry in
# sim/run_simulation.ps1 to know these benches.  Every bench is self-checking
# and ends with $fatal on any mismatch, so a non-zero exit code is the only
# pass criterion; "no test ran" is a failure, not a pass.
#
#   pwsh -File sim/opt_a/run_opt_a.ps1                 # all A-line benches
#   pwsh -File sim/opt_a/run_opt_a.ps1 -Tests tb_opt_a_master
#
# Run from the source root (the directory that holds rtl/, sim/, tools/).
param(
    [string[]]$Tests = @(),
    [string]$WorkDir,
    [switch]$ListTests,
    [switch]$KeepBuild
)
$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
Set-Location -LiteralPath $sourceRoot

function Resolve-Tool([string]$name, [string]$envName, [string[]]$candidates) {
    if ($envName -and (Test-Path env:$envName)) {
        $value = [Environment]::GetEnvironmentVariable($envName)
        if ($value) { return $value }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw "$name not found; set $envName or install it"
}
$iverilog = Resolve-Tool 'iverilog' 'IVERILOG' @('C:\iverilog\bin\iverilog.exe')
$vvp = Resolve-Tool 'vvp' 'VVP' @('C:\iverilog\bin\vvp.exe')

$common = @(
    'rtl\audio\voice_state_ram.v', 'rtl\audio\split_audio_multiplier.v',
    'rtl\audio\wide_master.v', 'rtl\audio\gowin_prom_wave_sine.v',
    'rtl\audio\gowin_prom_piano_bank.v', 'rtl\audio\gowin_prom_guitar_bank.v',
    'rtl\audio\gowin_prom_bright_bank.v', 'sim\gowin_prom_model.v')
$datapathSources = $common + @(
    'rtl\prototypes\instrument_rom_banks.v',
    'rtl\prototypes\instrument_ram_wavetable_engine.v',
    'rtl\prototypes\instrument_ram_audio_compute.v')

$suite = @(
    @{ Name = 'tb_opt_a_datapath'; Top = 'sim\opt_a\tb_opt_a_datapath.v'; Src = $datapathSources },
    @{ Name = 'tb_opt_a_master';   Top = 'sim\opt_a\tb_opt_a_master.v';   Src = @('rtl\audio\wide_master.v') },
    @{ Name = 'tb_opt_a_tables';   Top = 'sim\opt_a\tb_opt_a_tables.v';   Src = $common + @('rtl\prototypes\instrument_rom_banks.v') }
)
$names = @($suite | ForEach-Object { $_.Name })
if ($ListTests) { $names | ForEach-Object { Write-Output $_ }; exit 0 }
if ($Tests.Count -gt 0) {
    $unknown = @($Tests | Where-Object { $_ -notin $names })
    if ($unknown.Count -gt 0) { throw ('Unknown test(s): ' + ($unknown -join ', ')) }
    $suite = @($suite | Where-Object { $_.Name -in $Tests })
}
if ($suite.Count -eq 0) { throw 'No tests selected; the A-line gate cannot pass.' }

$root = Split-Path -Parent $sourceRoot
if (-not $WorkDir) { $WorkDir = Join-Path $root 'tmp\offline-opt-a\build' }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
if ($WorkDir -match '[^\x00-\x7F]') {
    throw "Icarus runtime path must use ASCII characters: $WorkDir"
}

$failures = @()
foreach ($entry in $suite) {
    $out = Join-Path $WorkDir ($entry.Name + '.vvp')
    $log = Join-Path $WorkDir ($entry.Name + '.log')
    Write-Output ("== " + $entry.Name)
    $compileArgs = @('-g2012', '-DSIMULATION', '-s', $entry.Name, '-I', 'sim\opt_a', '-o', $out, $entry.Top) + $entry.Src
    & $iverilog @compileArgs 2>&1 | Tee-Object -FilePath $log
    if ($LASTEXITCODE -ne 0) { $failures += ($entry.Name + ': compile'); continue }
    Push-Location -LiteralPath $WorkDir
    try { & $vvp (Split-Path -Leaf $out) 2>&1 | Tee-Object -FilePath $log -Append }
    finally { Pop-Location }
    $exit = $LASTEXITCODE
    $text = Get-Content -LiteralPath $log -Raw
    if ($exit -ne 0 -or $text -notmatch 'PASS') {
        $failures += ($entry.Name + ": run (exit $exit)")
        continue
    }
    foreach ($line in ($text -split "`r?`n" | Where-Object { $_ -match '^METRIC ' })) {
        Write-Output ("   " + $line)
    }
}
if (-not $KeepBuild) { }
if ($failures.Count -gt 0) {
    Write-Output ("FAILED: " + ($failures -join '; '))
    exit 1
}
Write-Output ("PASS opt_a: " + ($suite.Count) + " bench(es)")
exit 0
