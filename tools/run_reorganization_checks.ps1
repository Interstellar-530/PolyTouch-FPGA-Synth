param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$work = Join-Path $repo 'tmp/reorganization-20261101'
$evidence = Join-Path $repo 'evidence/2026/11/FPGA-20261101-reorganization-v0.1'
$gate = Join-Path $repo 'source/sim/run_simulation.ps1'
& $gate -Tests @('tb_pressure_bend','tb_fsr_mute','tb_fsr_idle_timeout','tb_fsr_idle_strict','tb_sustain_pedal','tb_fsr_sustain','tb_fsr_pedal_latency') -BuildDir (Join-Path $work 'targeted-build') -AudioCaptureDir (Join-Path $work 'targeted-capture') -MetricsDir (Join-Path $evidence 'targeted')
exit $LASTEXITCODE
