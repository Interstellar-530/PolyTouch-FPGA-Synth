# 优化 07：32 声部引擎流水重构（2026-10-22）

对应规划文件第 2 项“计算流水线与资源重新分配”。目标是把 32 路干声帧末从 992 拍压到
**≤768 拍（首轮）/ ≈640 拍（冲刺）**，同时把 49.152 MHz 下的时序余量从 +0.062 ns 拉厚。
只改原型的调度与运算组织，不改 12/30 表、不改音频算法。

## 原指标（重构前，v2.1.1 基线）

| 项 | 数值 |
|---|---:|
| 每声部渲染 | 27 拍 |
| 32 路干声帧末 | **992 / 1024 拍** |
| 配置写回 | 32 声部 × 4 拍 = 128 拍 |
| Fmax（49.152 MHz 约束） | **49.302 MHz，setup +0.062 ns**，13 级 |
| 资源 | Logic 5262、Register 2341、BSRAM 26、DSP 1 |

## 方法

1. **引擎调度 27 → 16 拍/声部**（`instrument_ram_wavetable_engine.v`）
   - 4 个状态字连续取指，4 次查表背靠背发射（ROM 选择器已按读周期寄存 bank）；
   - 插值、bank 混合、幅度乘法在操作数就绪后立即发射，结果两拍后消费；
   - 包络×力度折叠为一个 16 位系数，正弦与明亮两路各只做一次幅度乘法。
2. **配置写回裁剪**（引擎 + `voice_sched32.v`）
   - 新增 3 位写掩码：bit0=env/vel/retrig，bit1=inc，bit2=bank/weight；
   - 接收配置的当拍直接写 word0，省掉原来的独立 CFG0 拍；
   - 调度器新增 `dirty_inc`/`dirty_param` 位图：只有按键、换音色或阶段推进才写 inc/param。
3. **包络遍历两级流水**（`voice_sched32.v`）
   - 先锁存 `env/est/gate/timer/stage`，下一拍再计算并写回；
   - 数组读选择器与 ADSR 算术分处两个时钟周期，49.152 MHz 关键路径从 15 级降到 9 级。
4. 测试台把“最后活动”改为同时统计配置握手，帧末测量不再漏掉配置写回。

## 最终指标

| 检查项 | 结果 |
|---|---|
| 每声部渲染 | **16 拍** |
| 32 路干声帧末 | **576 拍**（常规帧）/ **606 拍**（32 声部同时换音色的最坏帧） |
| 配置写回 | 常规 1 字/声部（32 拍）；换音色 3 字/声部 |
| Fmax（49.152 MHz 约束） | **60.110 MHz，setup +3.709 ns**，9 级 |
| 与重构前逐样本对比 | **161 个样本，最大差 0（逐位一致）** |
| 32 路功能检查 | 分配、相位、窃声、重按、释放、钢琴/吉他选表全部通过 |
| I2S 解码 | 151 帧一致，低 8 位非零 148 帧 |

## 资源占用情况对比

| 资源 | 重构前 | 重构后 | 变化 |
|---|---:|---:|---:|
| Logic | 5262 | **5367 / 20736 (26%)** | +105 |
| Register | 2341 | **2468 / 16173 (16%)** | +127 |
| BSRAM | 26 | **26 / 46** | 0 |
| DSP | 1 | **1 / 24** | 0 |
| Fmax | 49.302 MHz | **60.110 MHz** | +10.8 MHz |
| Setup 裕量 | +0.062 ns | **+3.709 ns** | +3.65 ns |

结论：帧末 992 → 576/606（**−42%/−39%**），Fmax 49.302 → 60.110 MHz（+22%），
资源只增加约 2% 的逻辑和 5% 的寄存器，BSRAM/乘法器不变；输出与重构前逐位一致。
冲刺目标 640 拍达成（最坏 606 拍），首轮目标 768 拍有 162 拍余量。

## 复现

```powershell
cd output\handoff_milestone2_20261008\source
C:\iverilog\bin\iverilog.exe -g2012 -DSIMULATION -s tb_ram32_complete -I . `
  -o ..\..\..\tmp\tb_ram32_complete.vvp sim\tb_ram32_complete.v sim\i2s_rx_model.v `
  rtl\prototypes\ram32_top.v rtl\prototypes\voice_sched32.v `
  rtl\prototypes\instrument_rom_banks.v rtl\prototypes\instrument_ram_audio_datapath.v `
  rtl\prototypes\instrument_ram_audio_compute.v rtl\prototypes\instrument_ram_wavetable_engine.v `
  rtl\audio\voice_state_ram.v rtl\audio\note_phase_inc.v rtl\audio\wide_master.v `
  rtl\audio\i2s_tx.v rtl\audio\split_audio_multiplier.v rtl\audio\gowin_prom_wave_sine.v `
  rtl\audio\gowin_prom_piano_bank.v rtl\audio\gowin_prom_guitar_bank.v `
  rtl\audio\gowin_prom_bright_bank.v sim\gowin_prom_model.v
C:\iverilog\bin\vvp.exe ..\..\..\tmp\tb_ram32_complete.vvp
```

PnR 仍用 `build/ram32_proto.tcl`（49.152 MHz 约束）。

## 文件

- `source/`：重构后的引擎、调度器、顶层、数据通路与测试台副本
- `tb_ram32_complete.log`：32 路功能与帧末测量
- `samples/baseline.txt`、`samples/pipelined.txt`：重构前后逐样本对照（161 点，最大差 0）
- `build_reports/`：PnR 资源、Fmax、时序路径
