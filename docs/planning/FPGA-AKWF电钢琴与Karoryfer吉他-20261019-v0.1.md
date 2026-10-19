# AKWF 电钢琴 + Karoryfer 吉他（18:18）

日期：2026-10-19；依据 v0.9《音色来源评估》，按用户选择执行：钢琴改用 **AKWF 电钢琴单周期波形**，吉他改用 **Karoryfer Black And Green 真实采样**，BSRAM 按 **18 : 18** 分配。

## 1. 数据来源与许可

| 用途 | 来源 | 许可 | 本轮用法 |
|---|---|---|---|
| 电钢琴 | [AKWF FREE](https://www.adventurekid.se/akrt/waveforms/adventure-kid-waveforms/)，`AKWF_epiano_0001.wav`（600 点、44.1 kHz、单周期） | CC0 / 公有领域 | FFT 重采样到 512 点，6 音区带限 × 6 阶段频谱倾斜 |
| 电吉他 | [Karoryfer Black And Green Guitars](https://github.com/sfzinstruments/karoryfer.black-and-green-guitars)，`green/black` × `p/mf/f` 的 `ord` 持续音 | CC0 | 每个变体取最接近频段中心的音，提取一个稳定周期到 512 点 |

AKWF 600→512 不是数学无损；只保留 512 点能容纳的谐波，属于单周期音色模型，不保留击弦瞬态。Karoryfer 每张表只取一个周期，保留该音的拾音器频谱与相位，但不保留拨弦起音和整段衰减。

## 2. 存储与 1:1

| 音色 | 表布局 | 表数 | BSRAM |
|---|---|---:|---:|
| 电钢琴 | `zone*6 + stage`，6 音区 × 6 阶段 | 36 | **18** |
| 电吉他 | `band*6 + variant`，6 频段 × 6 变体（green/black × p/mf/f） | 36 | **18** |
| 通用明亮 | 6 表 | 6 | 3 |
| 正弦 | 1 表 | 1 | 1 |
| 合计 | | 79 | **40 / 46** |

钢琴与吉他的表数、BSRAM 完全 1:1；剩余 6 块 BSRAM 预留给后续效果器/瞬态。

## 3. 实现

- `gowin_prom_piano_bank`：36 表、bank 6 位、18 个 pROM；`selected=bank[5:1]`。
- `gowin_prom_guitar_bank`：36 表、bank 6 位、18 个 pROM。
- `shared_wavetable_engine`：
  - 钢琴 `piano_band_config(stage, zone, frac)` 返回 `zone*6+stage`；阶段 5 特判为 `zone*6+4`、权重满，读表 5；阶段 0 落到表 0。
  - 吉他 `guitar_band_config(inc, vel)` 返回 `band*6+variant`；`variant = vel[7:5]`（0..5），软音走 green/p，硬音走向 black/f。
  - 钢琴/吉他 pROM 的 bank 端口改为 `rom_bank[5:0]`。
- `voice_transition` 钢琴包络改为电钢琴持续型：attack 1024（约 1.4 ms 到满）、decay 2、sustain **32768（0.5）**、release 24（约 68 ms）；不再是原声钢琴 −48 dB 的持续电平。
- F1–F5 仍选起始阶段（F1–F2 从第 4 级、F4–F5 从第 5 级），运行时 `I0/I1` 切钢琴/吉他。

## 4. 指标

| 项 | 值 |
|---|---|
| Logic | 10544 / 20736（51%） |
| Register | 3293（21%） |
| BSRAM | **40 / 46（87%）**，钢琴 18 + 吉他 18 |
| MULT18X18 | 1 |
| Fmax | **36.081 MHz**（约束 27，1.34×） |
| Setup/Hold 违规 | 0 / 0 |
| 位流 SHA256 | `CE9C5D32…BFA05ABF` |

## 5. 验证与烧录

| 项 | 结果 |
|---|---|
| `tb_piano_bank` | PASS：36 张 AKWF 表 × 512 地址 |
| `tb_guitar_bank` | PASS：36 张 Karoryfer 表 × 512 地址 |
| `tb_piano_stage` | PASS：zone1 起始 bank 9 → 8 |
| `tb_top_switch` | PASS：I0→I1→I0、清声部、表重选 |
| Flash 操作 37 | `Program and Verify flash successfully.`，27.04 s |
| UI 实测 | `T252/N48/O48` → `I1/N48/O48` → `I0/T252/N48/O48`，全部 OK |

完整 `run_simulation.ps1` 未跑（按用户要求跳过长验证）；`tb_bandlimit_engine` 等旧黄金向量仍按 72 表布局，未纳入本轮定向验证。

## 6. 边界

- AKWF 是单周期波形，不是采样电钢琴；丢失击弦噪声、释音和真实时间变化。
- Karoryfer 只取一个周期，丢失拨弦瞬态与整段衰减；变体按力度切换两把吉他，音色随力度会有琴体变化。
- 过载/箱体/2× 过采样、压力表情、逐音区真实多采样仍未做。
- 完整门禁未跑；下次 RTL 改动后需重建并过门禁再烧。
