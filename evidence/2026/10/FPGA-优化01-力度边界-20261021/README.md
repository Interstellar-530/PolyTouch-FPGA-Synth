# 优化 01：力度边界与增益位宽（2026-10-21）

对应 `docs/reviews/FPGA-Git差异与优化方向-20261021-v0.1.md` 的第 1 项。改动集中在
`rtl/audio/shared_wavetable_engine.v`，生产参数、接口位宽和乘法器数量都不变。

## 原指标（修复前，HEAD `2d3db6c`）

- 引擎力度端口是 8 位，但有效范围没有定义；`key_a` 只有 15 位无符号，存 `vel × key_coeff`。
- `key_coeff` 最大 256（note ≤ 60），`127×256 = 32512` 刚好装下，`128×256 = 32768` 被截成 0。
- 于是 128..255 实际是 0..127 的回绕：`amp(128+k) = amp(k)`。力度 128 静音（−∞ dB），
  129 只有力度 1 的 −42.1 dB，255 只有力度 127 的 −0.07 dB。响应在 127→128 处从
  −0.07 dB 直接掉到静音，非单调。
- 当前所有上游（GPIO 固定 100、UART 1..127、HID 固定 100、曲目 ≤127）都不超过 127，
  所以产品未暴露该缺陷，但接口本身没有约束。

## 优化方法

在力度进入 15 位增益字段之前做一次饱和，取 7 位合法值：

```verilog
wire [7:0] cur_vel_gain = cur_vel[7] ? 8'd127 : cur_vel;
```

- 综合后就是 7 个或门，被吸收进已有的 8 位 16:1 声部选择逻辑，不新增寄存器、
  乘法器、ROM，也不改动 `key_a` 位宽和任何舍入位置。
- 选择饱和而不是加宽：加宽到 16 位会让非法力度产生 >1.0 的增益并引入新的削波，
  还要额外做限幅；饱和保持“最大力度 = 127/128 = −0.07 dB”的既有标定。
- 0..127 的输入路径与原实现逐位相同（选择器对合法值是恒等映射）。

## 最终指标

| 检查项 | 结果 |
|---|---|
| 0..127 逐位兼容 | 全 127 个值命中唯一包络积 `E=66537` 的整数公式 `(E·256·v+16384)>>>15` |
| 力度 0 | `amp=0`（唯一静音点） |
| 128..255 | 全部等于 `amp(127)=66017`，逐位相同，单调不降 |
| 旁路档 `KEY_GAIN_ENABLE=0` | 全 256 个输入与 note 60 键控档逐位相同 |
| 第二组系数 note 72（C=181） | 128/182/255 全部等于 `amp(127)=46676` |
| 改前对照 | 同一测试台在 HEAD 引擎上于 vel=128 失败：`cap=0, expected 66017` |

仿真证据：`before_velocity_bounds.log`（旧引擎失败）、`after_velocity_bounds.log`（新引擎通过）。

## 资源占用对比（debug8usb，GW2A-18，gw_sh V1.9.11.03）

| 资源 | 改前 | 改后 | 差值 |
|---|---:|---:|---:|
| Logic | 11379 / 20736 (55%) | 11379 / 20736 (55%) | 0 |
| Register | 3686 / 16173 (23%) | 3686 / 16173 (23%) | 0 |
| BSRAM | 40 / 46 (87%) | 40 / 46 (87%) | 0 |
| DSP | 1.75 / 24 (8%) | 1.75 / 24 (8%) | 0 |
| 18×18 / 9×9 / 36×18 | 1 / 1 / 1 | 1 / 1 / 1 | 0 |
| Fmax @ 27 MHz | 31.039 MHz | 31.039 MHz | 0 |
| 最差建立裕量 | +4.820 ns | +4.820 ns | 0 |
| 最差保持裕量 | +0.214 ns | +0.214 ns | 0 |
| 最差建立路径 | FIFO `rd_ptr` → 分配器 `v_note` 使能，21 级 | 同左 | 0 |

## 回归范围

12 台定向仿真：`tb_velocity_bounds`、`tb_key_gain`、`tb_shared_engine`、`tb_bandlimit_engine`、
`tb_piano_stage`、`tb_architecture_equivalence`、`tb_guitar_bank`、`tb_top_pitch8`、`tb_top_i2s`
通过；`tb_generic_bright`、`tb_piano_engine`、`tb_piano_morph` 失败，但用 HEAD 原版引擎复跑
失败信息完全相同（见 `regression_subset_pre_engine.log`），属于本次改动之前就存在的陈旧断言，
不是本项引入。它们的期望值与当前“键控增益 + 36 表钢琴布局”不一致，留待单独修复。

## 复现命令

```powershell
cd output\handoff_milestone2_20261008\source
$out = 'E:\Working Space\FPGA\tmp\sim_build\tb_velocity_bounds.vvp'
C:\iverilog\bin\iverilog.exe -g2012 -DSIMULATION -s tb_velocity_bounds -I . -o $out `
  sim\tb_velocity_bounds.v rtl\audio\shared_wavetable_engine.v `
  rtl\audio\gowin_prom_wave_sine.v rtl\audio\gowin_prom_wave_bright.v sim\gowin_prom_model.v
C:\iverilog\bin\vvp.exe $out

# 资源与时序（debug8usb）
.\build\build.ps1 -Profile debug8usb -GwSh E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe
powershell -File E:\Working Space\FPGA\docs\evidence\FPGA-优化01-力度边界-20261021\commands\collect_metrics.ps1 `
  -Receipt build\receipts\debug8usb.json -OutFile metrics_after.json
```

## 文件

- `engine_diff.patch`：`shared_wavetable_engine.v` 的完整改动
- `metrics_before.json`：改前 PnR 指标（上一轮合流复核归档）
- `metrics_after.json`：改后 PnR 指标（含位流 SHA256 与全部输入 SHA256）
- `build_reports/`：改后综合布线报告
- `debug8usb.receipt.json`：改后构建凭据（构建期间输入未变）
- `commands/collect_metrics.ps1`：指标提取脚本
