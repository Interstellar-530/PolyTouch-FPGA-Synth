# A 音频线无硬件优化：证据索引

日期 2026-10-24。提示词：`docs/handoff/FPGA-无硬件优化-A音频线提示词-20261024-v0.1.md`；
计划：`docs/planning/FPGA-无硬件双人并行优化清单-20261024-v0.1.md`。
本目录只放**可复现的数字**与结论，不放长音频。当前没有电表、示波器、实体音频与显示，
因此下面所有“通过”都只针对数字通路；FSR 标定、模拟音质、整机延迟仍是待验证项。

## 0. 共同基线

- 分支 `codex/v2.1.1-integration-20261022`，HEAD `67a9aaf`，**工作区 dirty**。
- 本轮开工前复核 9 个关键文件哈希，与 `archive/FPGA-20261023-v0.8` 及
  `docs/evidence` 中的基线审计完全一致（`instrument_ram_wavetable_engine.v`
  `d2b7bf75…`、`wide_master.v` `c8f1da8e…` 等），因此未提交的 v0.8 核心修复已在
  当前工作区内，本轮在其之上修改。记录见 `baseline.md`。
- 只读文件（`voice_sched32.v`、`ram32_control_front.v`、`pressure_bend.v`、
  `bend_ratio_pipeline.v`）本轮未改动；A3 的调度器侧问题按计划移交。

## 1. 交付与结果

| 任务 | 结论 | 证据 |
|---|---|---|
| A1 定点与混音 | 逐级位宽穷举：全部有正余量；最小为插值值 256 LSB、包络缩放 383 LSB。32 声部结构上不削波。舍入为“算术右移 + 半 LSB”（向 +∞），零输入/零力度/静音逐位为 0。 | `A1-arithmetic.md`、`A1-bounds.json`、`A1-metrics.json` |
| A2 波表与高音 | 48 张表按冻结音区与弯音上界（73562/65536）带限；最差折叠残差从 −62.8 dB 降到无谐波折叠（残余为 16 位量化底噪 −91.8..−95.7 dB）；组内 RMS 完全一致；DC=0；HEX↔厂商初始化逐样点一致。 | `A2-table-baseline.json`、`A2-tables-baseline.json`、`A2-tables-bandlimited.json`、`A2-wavetables.md` |
| A3 去爆音 | 表阶段迁移、换表、释放、静音、主音量与压力阶跃的**额外残差均为 0**（过渡阶跃低于正常波形斜率）。唯一真实阶跃是重按的包络清零：额外残差 53 603 LSB（−43.9 dBFS），属调度器，已给出补丁建议并移交。 | `A3-transitions.json`、`A3-transitions.md` |
| A4 合流 | 新组合 PnR：BSRAM 26/46、3×MULT18X18、1×MULTALU36X18、LUT/ALU 6027、寄存器 2929，与 v0.8 完全一致；setup/hold 违例端点 0/0，最差 setup +0.330 ns（73.728 MHz）。OptA 3 项、Quick 12 项、Ram32 5 项全部通过。 | `pnr/`、`A4-gates.md` |

## 2. 复现命令

全部在仓库根执行，无需硬件，不烧录。

```powershell
$src  = '.\output\handoff_milestone2_20261008\source'
$py   = '.\tools\.venv-audio-analysis\Scripts\python.exe'

# A1：位宽穷举证明（失败会非零退出）
& $py "$src\tools\offline_opt\a\a1_bounds.py" --report '.\docs\evidence\offline-opt\A\A1-bounds.json'

# A2：重新生成带限表（从优化前表集，输出到临时目录）并独立校验现装文件
& $py "$src\tools\offline_opt\a\gen_bandlimit.py" `
    --src-dir ".\archive\FPGA-20261024-A-v0.1\source\before-a2" `
    --out-dir '.\tmp\offline-opt-a\a2-repro' --report '.\tmp\offline-opt-a\a2-repro.json'
& $py "$src\tools\offline_opt\a\verify_tables.py" --expect-bandlimit --report '.\tmp\offline-opt-a\a2-verify.json' --emit-header "$src\sim\opt_a\table_expect.vh"

# A3：过渡阶跃测量
& $py "$src\tools\offline_opt\a\a3_transitions.py" --report '.\docs\evidence\offline-opt\A\A3-transitions.json'

# A4：向量重生成 + 三个门禁
& $py "$src\tools\offline_opt\a\make_vectors.py" --out-dir "$src\sim\opt_a" --mode wide
& "$src\sim\run_simulation.ps1" -Suite OptA
& "$src\sim\run_simulation.ps1" -Suite Quick
& "$src\sim\run_simulation.ps1" -Suite Ram32

# 实现与静态时序（约 10 分钟，写出到临时目录，不烧录）
$env:FPGA_BUILD_RUN_DIR = "$PWD\tmp\offline-opt-a\pnr-repro"
& 'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe' "$src\build\ram32_clocked.tcl"
Remove-Item Env:FPGA_BUILD_RUN_DIR
```

A 线自带 runner 也可单独跑：`& "$src\sim\opt_a\run_opt_a.ps1"`。

## 3. 边界与未验证项

- 没有测量设备，`clip_count`、帧尾、静态时序都是仿真/静态分析结果，不是板级实测。
- 未烧录；`ram32c.fs` 只是带空引脚约束的原型实现产物，不能直接上板。
- 采样率 48 kHz、1536 拍/帧、32 声部、12/30 物理表 bank 编号均未改变。
- 实体 FSR/弯音标定、模拟音质、USB→发声总延迟、上电稳定性仍需硬件阶段补证。
- 重按爆音**未消除**（移交 B 线），材料中不得写成已解决。
