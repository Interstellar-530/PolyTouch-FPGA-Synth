<#
[S3-REVIEW | Codex | 2026-10-14]
Prove that the S3 checker rejects padding corruption, missing tick and stale RX reset state.
Mutated sources and compiled output are created only in the chosen workspace tmp directory.
This script never changes production RTL and never programs hardware.
#>
param(
    [Parameter(Mandatory=$true)][string]$OutputDir,
    [string]$Iverilog = 'C:\iverilog\bin\iverilog.exe',
    [string]$Vvp = 'C:\iverilog\bin\vvp.exe'
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourceRoot = Join-Path $repoRoot 'source'
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path
$allowedRoot = (Resolve-Path -LiteralPath (Join-Path $repoRoot 'tmp')).Path.TrimEnd('\') + '\'
if (-not $OutputDir.StartsWith($allowedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Mutation output must be within the workspace tmp directory.'
}
if (Test-Path -LiteralPath (Join-Path $OutputDir 'mutation_results.json')) {
    throw 'Use a fresh OutputDir to preserve existing evidence.'
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$cases = @(
    @{ name='padding'; file='rtl\audio\i2s_tx.v';
       old="sr  <= {sr[DATA_BITS-1:0], 1'b0};";
       new="sr  <= {sr[DATA_BITS-1:0], 1'b1};"; reason='S3_PADDING_NONZERO' },
    @{ name='missing_tick'; file='rtl\audio\i2s_tx.v';
       old="sample_tick <= 1'b1;"; new="sample_tick <= 1'b0;"; reason='S3_TICK_BOUNDARY' },
    @{ name='rx_reset'; file='sim\i2s_rx_model.v';
       old='always @(posedge bck or posedge rst)'; new='always @(posedge bck)';
       reason='S3_RX_RESET_STALE' }
)
$results = @()
foreach ($case in $cases) {
    $original = [IO.File]::ReadAllText((Join-Path $sourceRoot $case.file), $utf8)
    if ([regex]::Matches($original, [regex]::Escape($case.old)).Count -ne 1) {
        throw ('Mutation anchor not unique: ' + $case.name)
    }
    $mutant = Join-Path $OutputDir ($case.name + '.v')
    [IO.File]::WriteAllText($mutant, $original.Replace($case.old, $case.new), $utf8)
    $out = Join-Path $OutputDir ($case.name + '.vvp')
    $sources = @('sim\tb_i2s_tx.v', 'rtl\audio\i2s_tx.v', 'sim\i2s_rx_model.v', 'sim\i2s_tx_checker.v') |
        ForEach-Object { if ($_ -eq $case.file) { $mutant } else { Join-Path $sourceRoot $_ } }
    & $Iverilog '-g2012' '-DSIMULATION' '-I' $sourceRoot '-s' 'tb_i2s_tx' '-o' $out @sources
    if ($LASTEXITCODE -ne 0) { throw ('Mutation compilation failed: ' + $case.name) }
    $log = (& $Vvp $out 2>&1 | Out-String)
    $caseExit = $LASTEXITCODE
    $log | Set-Content -LiteralPath (Join-Path $OutputDir ($case.name + '.log')) -Encoding UTF8
    if ($caseExit -ne 1 -or $log -notmatch [regex]::Escape($case.reason)) {
        throw ('Mutation not rejected for the intended reason: ' + $case.name + ', exit=' + $caseExit)
    }
    $results += @{ name=$case.name; exit=$caseExit; expected_reason=$case.reason; result='PASS' }
    Write-Output ('PASS checker mutation: ' + $case.name + ', reason=' + $case.reason)
}
@{ result='PASS'; cases=$results; hardware_programmed=$false } | ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $OutputDir 'mutation_results.json') -Encoding UTF8
