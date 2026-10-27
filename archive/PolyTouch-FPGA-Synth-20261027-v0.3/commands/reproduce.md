# Reproduce

```powershell
Set-Location D:\NanjingUniversity\FPGA\PolyTouch-FPGA-Synth
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\serial_keyboard\keyboard.ps1 -SelfTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\serial_keyboard\render_preview.ps1 -OutputPath .\tmp\dashboard-preview.png
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\output\handoff_milestone2_20261008\source\sim\run_simulation.ps1 -SkipAudioCapture -BuildDir .\tmp\simulation_regression_20261027 -MetricsDir .\tmp\i2s_metrics_regression_20261027
```

The skip run is the repeatable short regression and must report 80 positive benches plus 6 parameter negative cases. The long capture was separately exercised with the same script without `-SkipAudioCapture`, using ASCII output directories, and reported `PASS tb_audio_capture: 58880 frames, native tick, independent PT8211 decode, UART/ADSR/mute/chord`. The no-skip process was stopped after that long bench because the remaining 80 benches had already passed in the first run; the aggregate evidence therefore covers every bench but does not claim one no-skip exit code.

```powershell
& .\output\handoff_milestone2_20261008\source\build\build.ps1 -Profile hdmi
```

The build command requires a configured Gowin `gw_sh.exe`. Run the simulation evidence before programming; no bitstream was produced for this archive.
