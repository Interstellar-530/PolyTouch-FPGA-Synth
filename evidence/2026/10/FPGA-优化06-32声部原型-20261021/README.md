# 优化 06：32 声部完整调度与精度预算（2026-10-21）

对应 `docs/reviews/FPGA-Git差异与优化方向-20261021-v0.1.md` 的第 6 项。生产共享引擎仍是 4/8 路；
本项把独立的 32 路 RAM 核心补成**完整路径原型**：事件 → 分配/ADSR/窃声/重按 → RAM 核心 →
宽主混合 → I2S，并给出每帧周期预算与独立原型的 PnR。没有改生产 `top`，没有外设、没有烧录。

审核修正：初版的排队事件扫描、年龄回绕、配置背压及力度截断均已通过短台复现并修复，配置负载现锁存至握手完成。下列当前指标已更新；本目录 `source/`、原日志和 `build_reports/` 保留初版历史证据，修正后的源码、测试与 PnR 在 `../FPGA-优化06审核-20261021-v0.1/`。本原型只用正弦/通用明亮表，尚不包含生产钢琴/吉他少表音色、时钟产生或板级引脚约束。

## 原指标

| 项 | 改前状态 |
|---|---|
| 生产共享引擎 | 4/8 路；旧基本带限路径仅按每声部 27 拍计算，32 路已需 864 拍，超过 27 MHz / 46.875 kHz 的 576 拍。当前键控增益等开销还需计入，不能把旧 27 拍数字当完整生产预算 |
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
   - 配置写入器在核心空闲窗口，把变化声部的 env/inc/vel/retrig 锁存并写入。核心接收后有两拍 RAM 写入，调度器的请求、握手间隔也要计入，不能按整条链路每声部 3 拍估算；valid/data 在背压时保持。
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
| 实际帧预算 | 按最后一次主输出或 RAM 配置写完成沿计数，最晚 **992 拍**，小于 1016 拍检查上限；1024 拍帧长下剩 **32 拍**。不是旧公式估算的 967 拍 |
| 32 路原型 PnR | Logic **4635/20736**、Register **2252/16173**、BSRAM **5/46**、DSP **1/24（2×MULT18X18）** |
| 原型时序（49.152 MHz） | Fmax **51.922 MHz**，最差 setup 裕量 **+1.085 ns**，hold **+0.425 ns**，TNS 0、负裕量端点 0 |
| 最差路径 | `u_sched/env_ptr` → `dirty` 使能，16 级 |

结论：当前通用明亮音色原型在 **49.152 MHz / 48 kHz（1024 拍/帧）** 下通过已测功能、帧预算和内部时序，实测最后活动 992 拍，余量 32 拍。在 27 MHz / 46.875 kHz 的 576 拍下，现有单 lane 调度放不下。49.152MHz 是本原型验证过的选项，并非所有 32 声部实现唯一可用的时钟；接入生产音色、时钟和控制路径后需重新预算及 PnR。

## 资源占用情况对比

| 资源 | 改前（仅 32 路核心，未 PnR） | 改后（完整 32 路原型，已 PnR） | 说明 |
|---|---:|---:|---|
| Logic | 969 | **4635** | 增加事件/ADSR/窃声调度、主混合与 I2S，含审核修正 |
| Register | 527 | **2252** | 同上；核心本身是 RAM 状态 |
| BSRAM | 5 | **5** | 正弦表 1 + 明亮表 3 + 状态 RAM 1 |
| DSP | 1.0（2×18×18 等效） | **1** | 与改前相同 |
| Fmax | 未布线（13 级综合预估，默认 10 ns 约束，slack −1.246 ns） | **51.922 MHz（16 级，+1.085 ns）** | 修正后的独立原型 PnR，尚无板级引脚/IO 时序验收 |

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
  rtl\audio\gowin_prom_bright_bank.v sim\gowin_prom_model.v sim\i2s_rx_model.v
C:\iverilog\bin\vvp.exe ..\..\..\tmp\tb_ram32_complete.vvp

# 原型 PnR
Set-Location ..\..\..  # 回到项目根目录
$env:FPGA_BUILD_RUN_DIR = 'E:\Working Space\FPGA\tmp\ram32_proto_run'
& 'E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe' `
  output\handoff_milestone2_20261008\source\build\ram32_proto.tcl
```

## 文件

- `source/voice_sched32.v`、`source/ram32_top.v`、`source/tb_ram32_complete.v`
- `tb_ram32_complete.log`：32 路分配/相位/窃声/重按/释放/预算全部通过
- `build_reports/`：原型 PnR 报告（资源、Fmax、时序路径）
- `commands/ram32_proto.tcl`、`commands/ram32_proto.sdc`

## 追加：把 32 路原型接入钢琴/吉他音色（2026-10-21 晚）

原型原来只读 5 带通用明亮表；本次把每声部的选表字写入状态 RAM，让 32 路可以逐声部使用
生产同款的钢琴（12 表）和吉他（30 表）音色。

### 方法

1. 状态 RAM 从 4 字/声部扩到 8 字/声部：0=env/vel/retrig，1=相位，2=增量，4=bank+weight。
   32 声部占 256 字，512 字 RAM 仍有余量；渲染仍是每声部 27 拍。
2. 引擎增加第三配置字（CFG0/CFG1/CFG2 写 0/2/4 字），`{bank[5:0], weight[15:0]}` 随声部切换；
   `BANK_ADDR_A` 的 bank+1 在 47 处钳位。
3. 新增 `instrument_rom_banks.v`：bank 0–11 钢琴（6 个 pROM）、12–41 吉他（15 个）、
   42–47 通用明亮（3 个），按 bank 门控 CE、输出四选一。
4. 调度器增加逐声部 stage 计时器（8192 样本/级）与 `instrument`/`piano_tone` 输入：
   钢琴按 zone→组、stage→表，weight=(8191-timer)<<3；吉他按 band→组、velocity→variant，
   weight=0；切换乐器时把全部声部标脏，下一帧刷新选表字。
5. 配置写入器保持 valid 连续、每次接收后立刻换下一个脏声部，做到 4 拍/声部（接收+3 次写）。

### 仿真结果

```
INFO piano voice 4: bank=3 weight=65504
INFO guitar voice 4: bank=29 weight=0 (band=3 group=2 variant=5)
PASS tb_ram32_complete: 32 voices, per-voice pitch, steal, retrigger, release, budget, piano/guitar banks
```

- 钢琴：note 72 落在 group 0、stage 3，bank=3，weight 随计时器从 65528 递减。
- 吉他：note 72 的 band=3 → group 2，vel 120 → variant 5，bank=12+12+5=29，weight=0。
- 32 路仍逐声部相位步进一致；帧内实际活动在第 992 拍结束（上限 1016），每帧最多 32 次配置。

### PnR（接入音色后，49.152 MHz 约束）

| 资源 | 接入前 | 接入后 |
|---|---:|---:|
| Logic | 4225 | **5215 / 20736 (26%)** |
| Register | 2226 | **2783 / 16173 (18%)** |
| BSRAM | 5 | **26 / 46 (57%)** |
| DSP | 1 | **1 / 24** |
| Fmax | 52.188 MHz | **50.945 MHz** |
| Setup / Hold | +1.184 / +0.425 ns | **+0.716 / +0.425 ns** |

BSRAM 26 = 正弦 1 + 钢琴 6 + 吉他 15 + 明亮 3 + 状态 1；TNS 0、负裕量端点 0。
生产 `top` 未改动，仍是 8 声部；本项只证明 32 路原型可以带生产同款音色闭环。