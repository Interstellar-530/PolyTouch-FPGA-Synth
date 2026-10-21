# 优化 04：事件仲裁关键路径（2026-10-21）

对应 `docs/reviews/FPGA-Git差异与优化方向-20261021-v0.1.md` 的第 4 项。只改动 `top.v` 的事件
分发边界：`voice_alloc` 的选择语义、FIFO 语义、UART/HID 协议和音频通路都没有变化。

注意：本轮工作期间工作树在 12:16 被并行做过一次“HID 审核修正”（`hid_keymap.v`、`tb_host_kbd.v`、
`tb_top_host_ctrl.v`）。为了让资源对比只反映本项改动，下面的“优化前”是对**含该审核修正、但不含
事件预取**的同一棵树重新构建得到的（run `20261021T164344271`），而不是第 3 项完成时的旧数字。

## 原指标

- 最差建立路径：`u_top/u_manual/rd_ptr_0` → `u_alloc/v_note_28/CE`，**23 级逻辑**；
  Fmax 31.938 MHz，建立裕量 +5.727 ns。
- 路径分解：FIFO 的 `empty` 指针比较（进位链）→ 16 位源选择 mux（3 级 LUT，扇出 40 的长线）
  → `note_ownership` → 分配器音符比较（进位链）→ 优先级/年龄选择（十余级 LUT，其中一级被映射到
  DSP，单级约 3.6 ns）→ `v_note` 使能。FIFO 指针、仲裁 mux 与分配器优先级串在同一个 37 ns 周期里。

## 优化方法

按评审建议先做**事件预取（注册化 valid/data）**：仲裁结果进入分配器前先打一拍。

```verilog
reg        ev_q_valid;
reg [15:0] ev_q_word;
always @(posedge clk_audio) begin
    if (rst) begin ev_q_valid <= 1'b0; ev_q_word <= 16'd0; end
    else begin ev_q_valid <= owned_ev_valid; if (owned_ev_valid) ev_q_word <= ev_word; end
end
wire ev_deliver = ev_q_valid && !clear_events;
```

- 分配器每拍都能接收一个事件，没有停顿，所以不需要反压；源事件在 `owned_ev_valid` 那拍弹出一次，
  之后由暂存寄存器递送一次，不丢不重。
- 清理拍（panic/模式切换/F6 切换）不递送暂存事件；被清理拍本身不弹出源事件，原有“首键暂存”
  路径不变。事件到声部的延迟增加 1 个 27 MHz 周期（37 ns），远小于 576 拍的采样节拍。
- 未做更激进的优先级重构：加寄存器后最差路径已降到 20 级、裕量 +11.662 ns。最差路径仍从事件寄存器进入分配器的选择逻辑，只是前级 FIFO/仲裁组合链已被切开。

## 最终指标

| 检查项 | 优化前（含审核修正） | 优化后 | 差值 |
|---|---:|---:|---:|
| 最差路径逻辑级数 | 23 | **20** | −3 |
| 最差路径起点 | `u_manual/rd_ptr_0` | `u_top/ev_q_word_8` | — |
| Fmax @ 27 MHz | 31.938 MHz | **39.408 MHz** | **+7.470 MHz（+23.4%）** |
| 最差建立裕量 | +5.727 ns | **+11.662 ns** | +5.935 ns |
| 最差保持裕量 | +0.319 ns | +0.318 ns | −0.001 ns |
| 建立/保持负裕量端点 | 0 / 0 | 0 / 0 | 0 |

功能验证（14 台定向台全部通过）：

| 台 | 覆盖点 |
|---|---|
| `tb_event_fifo` | 满队列、同拍读写、顺序、清理——FIFO 语义未变 |
| `tb_voice_order` | 65538 次 Note On 后最老声部判断——选择语义未变 |
| `tb_voice_retrigger` | 同音重按、占用窃取、释音复用、排空 |
| `tb_song_backpressure` | 演示 FIFO 反压与突发排空 |
| `tb_mode_uart` | 模式切换首键、Panic、非法命令 |
| `tb_gpio_top` | GPIO 退出演示、四键同拍突发、Panic 优先、UART 路径 |
| `tb_top_host_ctrl` | CH9350L 首键/和弦/F6 切换/音量边界/Esc 清音、UART 兼容 |
| `tb_top_pitch8`、`tb_top_i2s`、`tb_top_switch`、`tb_timbre_top`、`tb_timbre_uart`、`tb_pressure_top`、`tb_host_kbd` | 8 声部顶层、真实 I2S、I0/I1 切换、音色/音量、压力链路、HID 链路 |

## 资源占用对比（debug8usb，GW2A-18，gw_sh V1.9.11.03）

| 资源 | 优化前 | 优化后 | 差值 |
|---|---:|---:|---:|
| Logic | 11537 / 20736 | 11668 / 20736 | **+131** |
| Register | 3689 / 16173 (23%) | 3705 / 16173 (23%) | **+16**（全设计净增量） |
| BSRAM | 40 / 46 (87%) | 40 / 46 (87%) | 0 |
| DSP | 1.75 / 24 | 1.75 / 24 | 0 |

Logic 和 Register 是报告中的两项独立统计，不能把 16 个寄存器计入 131 个 LUT。RTL 声明的暂存为
1 位 valid 加 16 位事件数据；综合后的全设计寄存器净增 16，Logic 净增 131。本次没有修改时序约束，
两次构建的输入差异只有 `top.v`；资源变化还包含综合映射与布局的变化，不能全部归因到新增暂存。
当前资源和时序均满足目标器件要求，是否继续缩减面积需单独测量，现有证据不能断言一定会牺牲时序。

2026-10-21 审核补充：新增 `tb_event_prefetch` 短台及门禁登记，验证实际顶层中的首键、共享音高归属、
满队列同拍读写、17 个连续 Note On、连续 Note Off、Panic/模式清理暂存事件，全部通过。没有改动生产 RTL，
没有重复综合。`regression_subset_extra.log` 另有 `tb_top_song` 编译失败，未计入上列 14 台通过结果；本项不宣称完整门禁通过。

## 复现命令

```powershell
cd output\handoff_milestone2_20261008\source\build
.\build.ps1 -Profile debug8usb -GwSh E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe
```

## 文件

- `event_prefetch.patch`：本项唯一的功能改动（`top.v`，相对第 3 项完成时的版本）
- `baseline_metrics.json`、`metrics_after.json`：A/B 两次构建的完整指标（含位流 SHA256）
- `worst_path_before.txt` / `worst_path_after.txt`：两次 STA 的最差路径原文
- `regression_subset.log`（10 台）、`regression_subset_extra.log`（4 台）
- `debug8usb.receipt.json`、`build_reports/`（优化后报告，`instrument_before.rpt.txt` 为优化前报告）
