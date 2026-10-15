# FPGA-20261015-v0.10 归档清单

## 内容

本次归档是 2026-10-15 对 S6（双波表、同步 ROM 与混音）数字交付的独立复核与
其后的修正。来源工作树为 `PolyTouch-FPGA-Synth-sim-main-55528`（分支
`fix/m2-build-issues`），交付目录为 `output/handoff_milestone2_20261008/source`，
离线工具在仓库根 `tools/`。版本号按 v0.4(S2)、v0.7(S3)、v0.8(S4)、v0.9(S5)
顺延取 v0.10；若主工作区流水号不同只需改目录名。

复核结论：两张 512 点表、同步读延迟、插值（含 511→0 接缝）、表选择与 256 级
交叉混合、四路极值饱和、clip 计数/清零都正确；主要缺陷是 `mixer_s6.v` 的 FIR
中抽头写成 8 而不是文档所述 6，实际系数 (1,4,8,4,1)/16，直流增益 18/16，
1 kHz 处抬升约 1 dB 并让本不削波的信号削波，交付版自检只测已削波的满幅输入
所以漏检。本轮修正抽头，并把插值/混合/混音/FIR 全部改为与
`tools/s6_reference.py` 向量逐值对照，补记 FIR 群延迟与频响，14 台门禁退出 0。
详细判定与证据见 `evidence/README.md`。

## 目录

- `source/rtl/audio/mixer_s6.v`：修正后的混音器（FIR 中抽头 6，单位直流增益）。
- `source/rtl/audio/wavetable_rom_dual.v`、`wavetable_osc_dual_s6.v`：未改，行为级同步 ROM/插值模型。
- `source/rtl/audio/wave_sine.hex`、`wave_bright.hex`：两张 512×16 表（重生成后校验值不变）。
- `source/sim/tb_s6_audio.v`：向量逐值自检（3584 相位点、1024 ROM 混合点、256 插值混合点、510 混音样本、32 FIR 样本）。
- `source/sim/vectors/`：22 支向量与 `meta.json`（含 FIR 频响与群延迟）。
- `source/sim/run_simulation.ps1`：门禁脚本（14 台）。
- `source/tools/s6_reference.py`：扩展后的定点参考与向量生成器；`generate_wavetables.py` 未改。
- `evidence/README.md`：S6 复核记录（结论、依据、证据、FIR 延迟/频响表、修改、风险、复现命令、基线说明）。
- `evidence/baseline/`：交付版八件文件原样副本（三个 RTL、测试台、两个工具、交付说明、两张表）。
- `evidence/logs/`：交付版自检日志、修正后通过日志、两项故障注入（交付版 FIR 抽头 240 条失败、插值取整 12 条失败）。
- `evidence/gate-20261015.log`：14 台门禁完整输出。
- `FPGA-缺件期间仿真与算法任务-20261014-v0.2-S6复核后.md`：任务清单在本次复核后的副本。

## 复现命令

```powershell
$env:PATH = 'D:\NanjingUniversity\FPGA\msys64\ucrt64\bin;' + $env:PATH
Set-Location <repo>
python tools/generate_wavetables.py
python tools/s6_reference.py --vectors output/handoff_milestone2_20261008/source/sim/vectors
Set-Location output/handoff_milestone2_20261008/source
pwsh -NoProfile -File sim/run_simulation.ps1 `
  -Iverilog D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\iverilog.exe `
  -Vvp D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\vvp.exe
```

## 回退

`rtl/audio/mixer_s6.v` 用 `evidence/baseline/mixer_s6.v` 覆盖、
`tools/s6_reference.py` 用同名基线覆盖、`sim/tb_s6_audio.v` 用
`evidence/baseline/tb_s6_audio.v` 覆盖并删除 `sim/vectors/` 即可回到交付版。

## 限制

行为模型不能代替 Gowin BSRAM/pROM 原语的综合与 PnR 验证；每个 ROM 实例按
512×16 计 2 块 BSRAM，振荡器与混合另有 25×25/27×27 乘法器，需在下一次综合
报告里记录 DSP/LUT 占用。FIR 启用比旁路多 2 帧群延迟，顶层接 I2S 时要计入或
固定启用。交叉混合端点为 1/256 低（≤128 LSB，约 -0.034 dB），属 8 位权重取舍。