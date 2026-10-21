# 优化 03：脱机键盘控制补齐（2026-10-21）

对应 `docs/reviews/FPGA-Git差异与优化方向-20261021-v0.1.md` 的第 3 项。改动只涉及 HID 键位映射、
顶层控制接入和新增顶层测试台；UART 协议、音频通路和波表都没有改动，也没有烧录或连接实体键盘。

## 原指标

- `hid_keymap.v` 只把音符键、F1–F5（T250–T254 钢琴硬度）、PageUp/PageDown（八度）、Esc（清音）
  映射成事件。USB 键盘演奏时**没有**钢琴/吉他切换，也**没有**主音量键。
- 这两项此前只能靠串口 `I0/I1`（乐器）和 `V0..V100`（音量）或板上 S1 长按完成，
  即 CH9350L 直连键盘的方案缺两个常用控制。
- 电脑端 `tools/serial_keyboard/KeyboardWindow.cs` 已有约定：F6 切换钢琴/吉他，↑/↓ 每步 5% 音量。
  HID 路径需要与它保持一致，而不是另定一套。

## 优化方法

- `hid_keymap.v`：新增 `instr_toggle`（F6，HID usage 0x3F）、`vol_down`（↓，0x51）、
  `vol_up`（↑，0x52）三个单拍脉冲；只在按键首次出现时触发，按住不连发，与 F1–F5 同一套差分逻辑。
- `host_kbd_input.v`：把三个脉冲原样引出，链路其余部分不变。
- `top.v`：
  - F6 与串口 `I0/I1` 同义：`instrument_id ^ 1`，并置 `instrument_change`，复用既有的
    “切换拍清事件/清按键”路径（`manual_flush` 已包含 `instrument_change`），不另写一套清音逻辑。
  - ↑/↓ 每步 5，钳在 0..100：`volume_gain` 只定义到 100，越界会静音，所以在写 `volume_target`
    之前先钳位；UART 的 `V` 仍然优先（同一拍串口覆盖）。
  - 音量斜坡、静音判定、LED 叠加和 `instrument_controls` 都没有改动。
- 测试：新增顶层 `tb_top_host_ctrl.v`，用真实 CH9350L state-2 帧（含接入序列）驱动 `top`，覆盖
  首键、和弦、F6 切换、↑/↓ 上下界、Esc 清音，并同时验证 UART 的 `D0/X/N/V` 在 HID 档下仍生效。
  该台已加入 `sim/run_simulation.ps1` 门禁。

## 原实现验证指标（审核修正前）

| 检查项 | 结果 |
|---|---|
| 首键 | 只分配 1 个声部，音高 60 |
| 和弦 | Q+W 分配 2 个声部，60/62 |
| F6 切换 | `instrument_id` 0→1（吉他）→0（钢琴），`guitar_mode` 跟随 |
| 切换时不残留 | 切换拍声部数立即归 0，`hid_held_count` 归 0；重新按键在新乐器上正常起音 |
| 音量上界 | V95 后 ↑ 两次：100、100（越界不再增长） |
| 音量下界 | V5 后 ↓ 两次：0、0（越界不再减小） |
| 音量步长 | ↑ 一次 0→5，↓ 一次 5→0；`volume` 斜坡最终落到 0 |
| Esc 清音 | 按住两键后 Esc：声部归 0、按键状态归 0，之后 2 ms 无残留 |
| UART 兼容 | 同一 RTL 上 `D0/X/N60/V95` 全部照常工作 |
| 回归 | 10 台定向台全过：`tb_host_kbd`、`tb_timbre_controls`、`tb_top_host_ctrl`、`tb_timbre_uart`、`tb_timbre_top`、`tb_mode_uart`、`tb_top_pitch8`、`tb_top_switch`、`tb_gpio_top`、`tb_top_i2s` |
| 既有失败 | `tb_top_guitar` 在 HEAD 原版 `top.v` 上同样失败（`guitar sustain env=16384 after 1s`），属改动前就存在的陈旧断言，本项未引入 |

## 原实现资源占用对比（审核修正前，debug8usb，GW2A-18，gw_sh V1.9.11.03）

| 资源 | 优化前 | 优化后 | 差值 |
|---|---:|---:|---:|
| Logic | 11379 / 20736 (55%) | 11342 / 20736 (55%) | **−37** |
| Register | 3686 / 16173 (23%) | 3689 / 16173 (23%) | **+3**（三个单拍脉冲） |
| BSRAM | 40 / 46 (87%) | 40 / 46 (87%) | 0 |
| DSP | 1.75 / 24 | 1.75 / 24 | 0 |
| Fmax @ 27 MHz | 31.039 MHz | 30.076 MHz | −0.963 MHz |
| 最差建立裕量 | +4.820 ns | +3.788 ns | −1.032 ns |
| 最差保持裕量 | +0.214 ns | +0.216 ns | +0.002 ns |
| 最差路径 | 手动 FIFO `rd_ptr` → 分配器 `v_note` 使能，21 级 | 手动 FIFO `wr_ptr` → 分配器 `v_note[29]` 使能，24 级 | 路径改变 |

时序仍满足 27 MHz：Fmax 30.076 MHz，建立裕量 +3.788 ns，建立/保持负裕量端点均为 0。
逻辑单元反而少 37 个，是综合重新映射的结果（新增的只是 3 个脉冲寄存器和一个 7 位加减/比较）；
最差路径从读指针换到写指针，正是第 4 项要处理的分配器关键路径，留给下一项统一优化。

## 复现命令

2026-10-21 审核发现：F6 引发的 `flush` 会清掉去重记录，同一个持键报告再次到达时会重复切换。现已更正为普通清音保留物理键身份、清除音符归属，松开后重新允许触发；断线通知和超时仍完全清空。顶层与键盘测试已加入重复上报检查。审核后的结果、资源和位流以 `../FPGA-优化03审核-20261021-v0.1/` 为准，本目录的日志、凭据和表格保留为原实现记录。

```powershell
cd output\handoff_milestone2_20261008\source
C:\iverilog\bin\iverilog.exe -g2012 -DSIMULATION -s tb_top_host_ctrl -I . `
  -o ..\..\..\tmp\tb_top_host_ctrl.vvp sim\tb_top_host_ctrl.v `
  rtl\audio\*.v rtl\top.v sim\gowin_prom_model.v sim\mcp3208_model.v
C:\iverilog\bin\vvp.exe ..\..\..\tmp\tb_top_host_ctrl.vvp

cd build
.\build.ps1 -Profile debug8usb -GwSh E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe
```

## 文件

- `hid_control.patch`：`hid_keymap.v` / `host_kbd_input.v` / `top.v` 的完整改动
- `tb_top_host_ctrl.v`、`tb_top_host_ctrl.log`、`tb_host_kbd.log`
- `regression_subset.log`（最终代码）、`regression_subset_first_run.log`（含 `tb_top_guitar` 既有失败）
- `metrics_after.json`、`debug8usb.receipt.json`、`build_reports/`
