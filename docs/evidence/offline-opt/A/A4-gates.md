# A4 合流：门禁、资源与静态时序

日期 2026-10-24。对象是**改动后的完整 32 声部原型**（新波表 + 登记后的测试台），
`ram32_clocked_wrap` / `ram32_clocked_top` / `instrument_ram_audio_compute` 结构未变。
本轮不烧录、不接板、不跑 Full 历史回归（按要求只跑定向与短门禁）。

## 1. 仿真门禁（真实结果）

| 套件 | 结果 | 用时 | 证据 |
|---|---|---|---|
| `-Suite OptA`（新增） | **PASS，3 项** | 5.19 s | `A4-gate-optA.json` |
| `-Suite Quick` | **PASS，18 项**（含 6 项预期失败参数用例） | 80.02 s | `A4-gate-quick.json` |
| `-Suite Ram32` | **PASS，5 项** | 97.66 s | `A4-gate-ram32.json` |

信号来自真实日志，不是推测：

```
tb_opt_a_datapath   METRIC a1_datapath bit_exact_frames=208 voices=32
tb_opt_a_master     METRIC a1_master bit_exact_frames=10 clipped_frames=4
tb_opt_a_tables     METRIC a2_tables banks=48 samples=24576 peak_checked=1 dc_checked=1 seam_checked=1
tb_ram32_engine_audio METRIC checked=2135 exact_zero_frames=197 nonzero_frames=1938 max_frame_tail=617/1536 clips=0
tb_ram32_engine_audio METRIC single_event_to_first_nonzero_i2s_us=83.293 (fast attack, 无 UART/外部队列)
tb_ram32_engine_audio METRIC burst32_allocation_us=15.543 burst32_to_i2s_upper_us=125.000
tb_ram32_engine_audio METRIC accepted_to_scheduler_us_min=0.042 max=0.283 count=34
```

`tb_ram32_engine_audio` 同时用真实 ROM 模型、PLL 模型、跨域握手与引脚级 I2S 接收模型
核对每一帧的期望值，`checked=2135`、`clips=0`、`max_frame_tail=617/1536`（余量 59.8%）。
这组数字与 v0.8 归档 **完全一致**，说明 A2 换表没有改变帧预算，也没有引入削波。

## 2. 实现结果（新组合另留记录）

`gw_sh build/ram32_clocked.tcl`，器件 GW2A-LV18PG256C8/I7 version C，`run all` 正常退出，
产物在 `tmp/offline-opt-a/pnr-ram32c-a/`，报告已复制到 `pnr/`。

| 资源 | 本次 | v0.8 归档 |
|---|---|---|
| BSRAM | **26/46** | 26/46 |
| MULT18X18 | **3** | 3 |
| MULTALU36X18 | **1** | 1 |
| LUT/ALU/ROM16 | **6027**（4539 LUT，1488 ALU，0 ROM16） | 6027 |
| 寄存器 | **2929** | 2929 |
| 逻辑 FF | 2873/15552（19%） | 2873 |

| 时序 | 本次 | v0.8 归档 |
|---|---|---|
| Setup delay model | Slow 0.95V 85C C8/I7 | 同 |
| Hold delay model | Fast 1.05V 0C C8/I7 | 同 |
| 分析路径/端点 | 19860 / 9368 | 19860 / 9368 |
| Setup 违例端点 | **0** | 0 |
| Hold 违例端点 | **0** | 0 |
| 最差 setup slack | **+0.330 ns** | +0.330 ns |
| 最差路径 | `u_banks/u_guitar/gp5/DO[1] → u_core/mul_a[22]/D`，13.199/13.563 ns | 同一路径（实例名 `gg5`，本次封装重生成后为 `gp5`） |

资源与时序与 v0.8 **逐项相同**：A1/A3 未改 RTL，A2 只替换 ROM 初始化内容，
不改变端口、位宽与组合深度；`gp5`/`gg5` 只是 pROM 实例名的重建差异，不影响逻辑。

时钟约束核对：计算域 `CLKOUT` 周期 13.563 ns = 73.728 MHz，与 `ram32_clocked_tcl`
的 MULT=6 一致；`ram32c_tr_content.html` 中 setup/hold 违例端点均为 0。

## 3. 结论与边界

- 数字通路：32 声部、48 kHz、每帧一次提交、帧尾 617/1536、无削波 —— 有新组合的实测。
- 资源：BSRAM 26/46、DSP 3×MULT18X18 + 1×MULTALU36X18，与基线一致，未超预算。
- 静态时序：73.728 MHz 下 setup/hold 违例 0，最差 +0.330 ns（与基线相同的窄余量）。
- **没有**证明：模拟音质、FSR 标定、物理按键到发声的总延迟、上电稳定性、板级引脚约束。
  `ram32c.fs` 是带空引脚约束的原型产物，不能直接烧录。
- Full 历史回归本轮按用户要求未运行；`-ListTests` 可列出全部，不等同于已通过。
