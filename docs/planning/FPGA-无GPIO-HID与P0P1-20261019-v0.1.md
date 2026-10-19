# 标准档输入与音色引擎变更

日期：2026-10-19，版本 v0.1。对应方案 v0.3 的 P0/P1 与“去 GPIO、电脑键盘演奏”决定。

## 1. 输入：停用 12 路 GPIO，改用 CH9350L + 标准电脑键盘

| 项目 | 变更 |
|---|---|
| 演奏输入 | 12 路 GPIO 机械键在标准 27 MHz 档停用（`GPIO_KEY_ENABLE=0`），由 USB 电脑键盘经 CH9350L 下位机输入 |
| Host TXD → FPGA | **L9 / J5-5**（原 key0） |
| FPGA → Host RXD | **N8 / J5-6**（原 key1），当前固定高，保留给将来 LED/握手 |
| 释放的引脚 | J5-5/J5-6 以外的 10 路 GPIO 键脚、T7（原 12.288 MHz）均不再分配 |
| 旧档 | `debug`（PT8211）与 `standard`（12.288 MHz）保留 GPIO=1、HOST=0，便于回归/回退 |

CH9350L 只用**下位机/发送端**（SEL=1），S1/S0 拨到 **state 2**：UART 115200 8N1、3.3 V TTL，键盘帧固定为

```text
57 AB 01 [mod] [00] [k0 k1 k2 k3 k4 k5]     11 字节，无校验
```

同状态还会出现 `57 AB 02`（鼠标 5 字节）、`57 AB 80/82`（4 字节）、`57 AB 86/89`（3 字节），解析器按命令字长度跳过。每次按键 CH9350L 会重复 3–4 帧，`hid_keymap` 用“上一报告差分”去重。

## 2. 键位与控制

与 `tools/serial_keyboard/KeyboardCore.cs` 完全一致：

- `Z S X D C V G B H N J M` → base−12 .. base−1
- `Q 2 W 3 E R 5 T 6 Y 7 U` → base+0 .. base+11
- `A/F/K` 旧版兼容键
- `F1–F5` → T250–T254
- `Esc` → 全松键
- `PageUp/PageDown` → 八度 ±12，范围 36..84

移调时每个物理键在按下时把实际 MIDI 音高存进 `prev_note`，松开用存下的音高；不会出现“按新八度释放旧音”。断线处理：state 2 约 1 s 一次 `0x82` 心跳，2 s 无帧或收到 `0x86` 时释放所有音。

## 3. P0：非钢琴音色不再误读钢琴表

`shared_wavetable_engine` 新增 `GENERIC_BRIGHT_ENABLE`。使能后：

- `piano_enable=1`：仍读 `gowin_prom_piano_bank`（72 张表），与原实现逐位相同；
- `piano_enable=0`：读 `gowin_prom_bright_bank`（6 级通用明亮表，3 块 BSRAM）；
- `piano_sel_q` 在 `ST_ADDR_A` 与 bank/地址同拍锁存，读取窗口内稳定；
- 帧长仍 108 拍、40 次乘积。

资源代价：BSRAM 37 → **40/46**，仍剩 6 块；钢琴路径没有增加表。

## 4. P1：音区锁存与阶段计时器

- `ZONE_LATCH_ENABLE=1`：起音时用**未弯音**的 `inc` 锁存 `zone_q`；之后弯音只改变相位增量，不再硬切音区。相邻音区交叉淡化仍未实现，属于下一阶段。
- `STAGE_TIME_ENABLE=1`：每声部一个 16 位计时器，每 `STAGE_STEP_SAMPLES = AUDIO_FS_HZ/8` 个采样推进一级（46.875 kHz 时 5859 采样 ≈ 125 ms，6 级约 750 ms）；表内插值权重取计时器低 13 位。
- 音色阶段不再取 `env[15:13]`，所以包络/力度变化不会把 F5 长期钉在最亮表；幅度包络与频谱阶段解耦。

## 5. 验证

| 测试 | 结果 |
|---|---|
| `tb_host_kbd` | PASS：按下/松开、重复去重、和弦、移调持音、PageDown、Esc、F1、截断帧 1 ms 重同步、rollover |
| `tb_generic_bright` | PASS：通用表 18096 / 钢琴表 −169824，108 拍、40 乘积，选择器无错配 |
| `tb_piano_stage` | PASS：包络恒 FFFF 时阶段仍按 8 拍推进；弯音不 retrig 不改音区；retrig 后锁存新音区并归零阶段 |
| `tb_top_i2s_27m` | PASS：见 `archive/FPGA-20261019-v0.5/evidence/tb_top_i2s_27m.log` |
| `tb_top_i2s`（48 kHz 旧档） | 未在本轮改动后重跑；生产档已切到 27 MHz，旧档仅作回退 |

`standard27` PnR（Gowin V1.9.11.03，GW2A-LV18PG256C8/I7 C）：

| 指标 | v0.4（仅 27 MHz 档） | v0.5（+P0/HID/P1） |
|---|---:|---:|
| Logic | 6668 | **7001 / 20736（34%）** |
| Register | 2471 | **2777（18%）** |
| BSRAM | 37 | **40 / 46（87%）** |
| MULT18X18 | 1 | 1 |
| Fmax / 约束 | 57.353 / 27 MHz | **49.407 / 27 MHz（1.83×）** |
| Setup/Hold 违规 | 0 / 0 | **0 / 0** |

中途把 HID 键位做成“一拍内 6×6 并行查找”时 Fmax 曾降到 30.36 MHz；改成 12 拍逐键状态机后回到 49.407 MHz，同时 Logic 从 11043 降到 7001。BSRAM 增加 3 块是 P0 通用明亮表的代价，仍在方案预算内（40/46，剩 6 块）。

## 6. 边界与未完成

1. **8/32 声部未做**。当前仍是 4 声部；共享引擎的 4 个相位累加器、`voice_alloc`、顶层总线都要加宽，属于方案第四阶段。
2. **相邻音区交叉淡化、分音独立衰减、非谐性、击弦噪声未做**，需要试听/频谱基线，不能在无实物试听时声称改善。
3. **实物未验证**：CH9350L 实际帧重复次数、PCM5102A 在 46.875 kHz 的 PLL 锁定、CJMCU 电源路径、FSR 源阻抗。
4. 完整 `run_simulation.ps1` 未跑；本轮只跑了与改动直接相关的四个测试台。烧录前必须补跑。
