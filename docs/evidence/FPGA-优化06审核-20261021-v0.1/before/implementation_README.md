# 优化 06：32 声部完整调度与精度预算（2026-10-21）

对应 `docs/reviews/FPGA-Git差异与优化方向-20261021-v0.1.md` 的第 6 项。生产共享引擎仍是 4/8 路；
本项把独立的 32 路 RAM 核心补成**完整路径原型**：事件 → 分配/ADSR/窃声/重按 → RAM 核心 →
宽主混合 → I2S，并给出每帧周期预算与独立原型的 PnR。没有改生产 `top`，没有外设、没有烧录。

## 原指标

| 项 | 改前状态 |
|---|---|
| 生产共享引擎 | 4/8 路，每声部 27 拍；27 MHz / 46.875 kHz 时一帧 576 拍，32 路需 32×27=864 拍，**放不下** |
| 32/64 路 RAM 核心 | 已有 `ram_wavetable_engine` / `ram_audio_compute` / `ram_audio_datapath`，但只接受外部常量配置（`cfg_envelope/increment`） |
| 既有 32 路测试 | `tb_ram_audio_datapath` 只验证常量配置下的逐样本主通路与 `27×32+6` 拍；**没有事件、ADSR、窃声、重按** |
| 既有合成数据 | 32 路核心 969 LUT / 527 FF / 5 BSRAM，仅综合预估、未 PnR、无时序约束 |

## 优化方法

新增两个原型模块（`rtl/prototypes/`）：

1. `voice_sched32.v`：32 路音乐状态（音符/力度/gate/包络/年龄/重触发）与配置写入器。
   - 包络更新按**每拍一个声部**串行执行，32 拍/帧，不需要 32 个 ADSR 实例。
   - 事件分配规则与生产分配器一致：同音重按 → 空声部 → 最老释音声部 → 最老按住声部；
     松键进入 Release，env 归零才释放。
   - 事件搜索同样串行：32 拍扫描 + 1 拍提交。事件间隔是毫秒级，扫描延迟可忽略，
     但 49.152 MHz 的一个时钟周期里不再有 32 路比较链。
   - 配置写入器在核心渲染结束后的空闲窗口，把变化声部的 env/inc/vel/retrig 写入，
     每声部 3 拍（1 拍请求 + 2 拍引擎写入）。
2. `ram32_top.v`：`ram_audio_datapath`（VOICES=32, 49.152 MHz/48 kHz）+ `voice_sched32`，
   帧长 1024 拍。
3. `sim/tb_ram32_complete.v`：32 个音同时按下，逐声部检查增量、包络、相位步进；再测窃声、
   同音重按、松键归零与每帧最坏周期数。
4. `build/ram32_proto.tcl` + `constraints/ram32_proto.sdc`：独立原型的 PnR（49.152 MHz 约束）。

## 最终指标

| 检查项 | 结果 |
|---|---|
| 32 路同时发声 | 32 个声部全部占用，RAM 中每声部增量与 `note_phase_inc` 逐一相等 |
| 音高不串路 | 相邻两帧每声部相位增量 = 该声部自己的增量（32/32 通过） |
| 窃声 | 第 33 个音替换最老声部，其余 31 路增量不变 |
| 重按 | 同音复用原声部、相位复位、包络从头开始 |
| 松键 | Release 到 0 后声部释放，`active_count` 32→31 |
| 每帧周期预算 | 渲染+主混合 **871 拍** + 配置 32×3=**96 拍** = **967 拍** ≤ 1016 拍上限（1024 帧长） |
| 32 路原型 PnR | Logic **4225/20736 (21%)**、Register **2226/16173 (14%)**、BSRAM **5/46**、DSP **1/24** |
| 原型时序（49.152 MHz） | Fmax **52.188 MHz**，最差 setup 裕量 **+1.184 ns**，hold **+0.425 ns**，TNS 0、负裕量端点 0 |
| 最差路径 | `u_sched/env_ptr` → `dirty` 使能，15 级 |

结论：32 路在 **49.152 MHz / 48 kHz（1024 拍/帧）** 下可以完成，周期预算 967 拍，余量 57 拍；
在 27 MHz / 46.875 kHz（576 拍/帧）下**放不下**，32 声部产品必须使用 49.152 MHz 计算时钟
（或双 lane、或提高时钟），这正是本项要给出的结论。

## 资源占用情况对比

| 资源 | 改前（仅 32 路核心，未 PnR） | 改后（完整 32 路原型，已 PnR） | 说明 |
|---|---:|---:|---|
| Logic | 969 | **4225** | 增加事件/ADSR/窃声调度、主混合与 I2S |
| Register | 527 | **2226** | 同上；核心本身是 RAM 状态 |
| BSRAM | 5 | **5** | 正弦表 1 + 明亮表 3 + 状态 RAM 1 |
| DSP | 1.0（2×18×18 等效） | **1** | 与改前相同 |
| Fmax | 未布线（13 级综合预估，默认 10 ns 约束，slack −1.246 ns） | **52.188 MHz（15 级，+1.184 ns）** | 首次给出真实 PnR 时序 |

生产 8 声部 `debug8usb` 作为参照：Logic 11392、Register 3702、BSRAM 25、Fmax 37.890 MHz（27 MHz 约束）。
32 路原型与生产顶层是两套架构，不能直接互换；原型的价值是证明“32 路完整路径 + 每帧预算 + 时序”
可以同时成立，并把面积/时序代价量化出来。

## 复现命令

```powershell
# 功能与周期预算
cd output\handoff_milestone2_20261008\source
C:\iverilog\bin\iverilog.exe -g2012 -DSIMULATION -s tb_ram32_complete -I . `
  -o ..\..\..\tmp\tb_ram32_complete.vvp sim\tb_ram32_complete.v `
  rtl\prototypes\ram32_top.v rtl\prototypes\voice_sched32.v `
  rtl\audio\ram_audio_datapath.v rtl\audio\ram_audio_compute.v `
  rtl\audio\ram_wavetable_engine.v rtl\audio\voice_state_ram.v `
  rtl\audio\note_phase_inc.v rtl\audio\wide_master.v rtl\audio\i2s_tx.v `
  rtl\audio\split_audio_multiplier.v rtl\audio\gowin_prom_wave_sine.v `
  rtl\audio\gowin_prom_bright_bank.v sim\gowin_prom_model.v
C:\iverilog\bin\vvp.exe ..\..\..\tmp\tb_ram32_complete.vvp

# 原型 PnR
$env:FPGA_BUILD_RUN_DIR = 'E:\Working Space\FPGA\tmp\ram32_proto_run'
& 'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe' `
  output\handoff_milestone2_20261008\source\build\ram32_proto.tcl
```

## 文件

- `source/voice_sched32.v`、`source/ram32_top.v`、`source/tb_ram32_complete.v`
- `tb_ram32_complete.log`：32 路分配/相位/窃声/重按/释放/预算全部通过
- `build_reports/`：原型 PnR 报告（资源、Fmax、时序路径）
- `commands/ram32_proto.tcl`、`commands/ram32_proto.sdc`
