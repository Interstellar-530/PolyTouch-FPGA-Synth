# 本轮检查

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run_reorganization_checks.ps1
& tools/.venv-docconvert/Scripts/python.exe tools/verify_reorganization.py
& tools/.venv-docconvert/Scripts/python.exe releases/2026/10/FPGA-20261030-v0.1/original-delivery/source/verify_release.py
```

构建设置检查：`tools/verify_build_profiles.py --setup-only --out <新的证据目录>`；门禁策略检查：`tools/test_simulation_gate_policy.py`。定向检查通过只覆盖所选范围。
