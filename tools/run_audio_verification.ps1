<#
Run the complete RTL gate, then the independent S1 PCM/FFT checks.
Python is an offline analysis tool only; this script never programs hardware.
The output contains raw capture, WAV/PNG/JSON and reproducibility evidence.
#>
param(
    [Parameter(Mandatory=$true)][string]$OutputDir,
    [string]$Python = '',
    [string]$Iverilog = 'C:\iverilog\bin\iverilog.exe',
    [string]$Vvp = 'C:\iverilog\bin\vvp.exe'
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$sourceRoot = Join-Path $repoRoot 'output\handoff_milestone2_20261008\source'
$gate = Join-Path $sourceRoot 'sim\run_simulation.ps1'
if (-not $Python) { $Python = Join-Path $repoRoot 'tools\.venv-audio-analysis\Scripts\python.exe' }
foreach ($exe in @($Python, $Iverilog, $Vvp)) {
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Tool not found: $exe" }
}
if (Test-Path -LiteralPath (Join-Path $OutputDir 'simulation_gate.log')) {
    throw 'Use a new OutputDir to preserve previous verification evidence.'
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path
$captureDir = Join-Path $OutputDir 'capture'
$analysisDir = Join-Path $OutputDir 'analysis'
$buildDir = Join-Path $OutputDir 'build'
New-Item -ItemType Directory -Force -Path $captureDir, $analysisDir, $buildDir | Out-Null
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Push-Location $repoRoot
try {
    $commit = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read Git commit.' }
    $inputs = @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'rtl') -File -Recurse)
    $inputs += @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'sim') -File | Where-Object { $_.Extension -eq '.v' -or $_.Extension -eq '.ps1' })
    $inputs += @(Get-Item -LiteralPath $PSCommandPath, (Join-Path $PSScriptRoot 'analyze_audio_capture.py'))
    $hashes = @($inputs | Sort-Object FullName | ForEach-Object {
        @{ path=$_.FullName.Substring($repoRoot.Length+1).Replace('\','/'); sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
    @{
        source_commit=$commit; working_tree=(@(& git -c core.quotepath=false status --short));
        inputs=$hashes; tools=@{ python=$Python; iverilog=$Iverilog; vvp=$Vvp; powershell=$psExe };
        hardware_programmed=$false; sample_rate_hz=46875; clock_hz=27000000
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputDir 'reproduction.json') -Encoding UTF8
    # vvp -V writes its normal version banner to stderr. In Windows PS 5.1,
    # ErrorAction=Stop would otherwise turn that banner into a fatal error.
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Iverilog -V *> (Join-Path $OutputDir 'iverilog_version.txt')
        $iverilogVersionExit = $LASTEXITCODE
        & $Vvp -V *> (Join-Path $OutputDir 'vvp_version.txt')
        $vvpVersionExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    if ($iverilogVersionExit -ne 0 -or $vvpVersionExit -ne 0) { throw 'Tool version query failed.' }
    Write-Output "Running complete RTL gate; log: $OutputDir\simulation_gate.log"
    & $psExe -NoProfile -ExecutionPolicy Bypass -File $gate -Iverilog $Iverilog -Vvp $Vvp -AudioCaptureDir $captureDir -BuildDir $buildDir *> (Join-Path $OutputDir 'simulation_gate.log')
    $gateExit = $LASTEXITCODE
    if ($gateExit -ne 0) { throw "RTL gate failed (exit $gateExit). See simulation_gate.log." }
    Write-Output 'RTL gate passed. Checking analyzer negative controls.'
    & $Python (Join-Path $PSScriptRoot 'analyze_audio_capture.py') --self-test *> (Join-Path $OutputDir 'analysis_selftest.log')
    if ($LASTEXITCODE -ne 0) { throw 'Analyzer self-test failed.' }
    # Analyzer CLI contract is documented beside its source.
    & $Python (Join-Path $PSScriptRoot 'analyze_audio_capture.py') --capture (Join-Path $captureDir 'audio_capture.csv') --manifest (Join-Path $captureDir 'capture_manifest.csv') --output-dir $analysisDir --git-commit $commit *> (Join-Path $OutputDir 'analysis.log')
    $analysisExit = $LASTEXITCODE
    if ($analysisExit -ne 0) { throw "Audio analysis failed (exit $analysisExit). See analysis.log." }
    @{ rtl_gate_exit=$gateExit; analysis_exit=$analysisExit; result='PASS' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDir 'verification_result.json') -Encoding UTF8
    Write-Output "PASS complete RTL and S1 audio verification: $OutputDir"
} finally { Pop-Location }
