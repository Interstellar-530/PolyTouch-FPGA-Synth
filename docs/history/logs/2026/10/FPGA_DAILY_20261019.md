# FPGA 每日工作记录 · 2026-10-19

分支：`codex/s4-s6-pressure`  
基线：`ff2c7d6`（2026-10-17，64 声部原型提交；生产 `top` 仍为 4 声部）  
主题：8 声部落地、钢琴/吉他音色重做、运行时切换与电脑端 UI、烧录与设计文档。

## 1. 8 声部与混音

- `top` 增加 `VOICES` 参数，标准 27 MHz 档设 8；`shared_wavetable_engine` 增加 `VOICES8`，相位/包络 8 路展开。
- 修复 8 声部真实 bug：`ST_BEND_APPLY` 原来把当前声部的弯音增量写到全部 8 个相位，A4 周期从 106.5 掉到 94.19；改为只更新 `phase_v[vsel]`，恢复到 106.43。
- 混音：`MASTER_VOLUME_SHIFT=3`（÷8），`global_crossfade` 增加 0.75 FS、4:1 软限幅；没有新增 FIR，旧 (1,4,6,4,1) 继续旁路。
- 指标（后续音色版之前）：Logic 9836、Register 3380、BSRAM 40/46、MULT 1、Fmax 30.061 MHz、违规 0。

## 2. 钢琴音色柔化

- 发现 72 张钢琴表里 28 张二次谐波 > 基频 3 倍（最大 45.36 倍），低音区平均 16 倍；生成器改为按基频归一化、每个谐波限制在全体中位数 2 倍内，并对 6 个阶段做中值平滑。二次谐波最大降到 2.49 倍。
- 阶段方向改为“起音较亮 → 每 8192 采样降一级 → 琴体表”，权重 8191→0 连续，切级不跳变。
- 试听脚本相位单位错误（把 Hz 当表索引增量）导致 C4 跑到约 24 kHz 混叠；修正后频谱重心 11 kHz→1.14 kHz，5 kHz 以上能量 71%→0.66%。

## 3. HID 可靠性（v0.8 规划 P1）

- `hid_keymap` 事件 FIFO 指针 5 位→4 位，`count` 保留 5 位，修复累计 16 次后的越界/回绕。
- `flush`/超时/0x86 同一周期清队列并禁止该拍入队/出队；满队列同拍出队时允许入队，不丢 Note Off。
- 0x86 经 `device_notify` 并入顶层 `manual_flush`/`clear_events`；`ch9350_rx` 增加 `frame_error` 立即重同步；停用 A/F/K 同音别名。
- `tb_host_kbd` 扩展到 20 次按/松回绕、flush、0x86，全部 PASS。

## 4. 运行时钢琴/吉他切换与 UI

- `uart_ctrl` 新增 `I0/I1`（钢琴/吉他），带 OK 应答；`top` 用 `instrument_id` 切 `piano_mode`/`guitar_mode`，切换拍清声部/事件。
- 电脑端 `KeyboardWindow` 新增“音色：钢琴/吉他”按钮和 **F6**；`KeyboardCore` 串口白名单加入 `I[01]`；钢琴分支补发当前 `T250–T254`。
- 统一 `debug8` 同时保留钢琴/吉他表，切换不需要换位流；实测 `I1 -> OK`、`I0 -> OK`、`T254 -> OK`。

## 5. AKWF 电钢琴 + Karoryfer 吉他（18:18）

- 钢琴：AKWF `AKWF_epiano_0001`（CC0，600 点单周期）→ 36 表（6 音区 × 6 阶段），18 BSRAM；包络改为持续型（sustain 32768、release 24）。
- 吉他：Karoryfer Black And Green（CC0）`green/black × p/mf/f` → 36 表（6 频段 × 6 变体），18 BSRAM；力度高 3 位选变体，`vel_variant` 与幅度分离的思路保留。
- 总 BSRAM **40/46**（钢琴 18 + 吉他 18 + 通用 3 + 正弦 1），表数 36:36；Logic 10544、Fmax 36.081 MHz、违规 0。

## 6. 低音毛刺修复

- 根因：时域取“一个周期”后重采样，低音长周期的小数 lag 误差导致首尾不闭合；最低表 `wrap/median step=20.5`、最大步进 3979，每周期一次咔嗒。加上 0.30 s 取样已衰减到噪声、默认力度映射到 `black/p`。
- 改为精确 f0 谐波分解（零填充 FFT + 抛物线 + Goertzel）、−62 dB 噪声门、6.5 kHz 一阶低通，合成严格周期表；取样提前到 0.08 s；低音区默认 `green/f`。
- 结果：最低表 `wrap/median` 20.5→2.47、最大步进 3979→671、5 kHz 以上能量 6.2%→0%；`tb_guitar_bank` PASS。

## 7. 高音尖锐优化

- 主混合后加一阶低通：`mix_lp_y += (mixed_shared - mix_lp_y) >>> 1`，a=0.5，fc≈5.2 kHz；只用移位，不新增乘法器。
- 频响：5.2 kHz −3 dB、10 kHz −6.7 dB、15 kHz −9.6 dB；低音区 3 kHz 以上能量少，主要压高音。
- 指标：Logic 10647、Register 3309、BSRAM 40/46、MULT 1、Fmax 33.703 MHz、违规 0；位流 `A1B2A2AC…1B6A685C`。
- **已知口径**：该低通目前只作用于 16 位 `mixed`；24 位 `mixed_shared24` 直接送 I2S，绕过低通。后续需统一到 24 位公共节点或双份同系数滤波。

## 8. 键控响度混音设计（未实现）

- v0.1 提出“每声部键控增益 + 节目压缩 + 前瞻限幅”；用户指出 Q8 >1 需 9 位、声部通路可能先溢出、16/24 位低通口径不一致。
- v0.2 修正为首版**只衰减**：C4 以下 0 dB，高音每半音 −0.5 dB、限幅 −6 dB（钢琴）/−5 dB（吉他）；增益折叠进 `vel_amp`（≤127），保留 `vel_variant` 选吉他采样；不增加压缩器/前瞻/双段；16/24 位共用声部增益，低通统一到 24 位公共节点或双份实现。
- 代价：整体电平降低，低音不会比当前更响；这是首版有意折中。

## 9. 指标与烧录记录

| 档位 | Logic | Register | BSRAM | MULT | Fmax | 违规 |
|---|---:|---:|---:|---:|---:|---:|
| `debug8`（8 声部钢琴，早期） | 9836 | 3380 | 40/46 | 1 | 30.061 | 0/0 |
| `debug8`（钢琴+吉他统一） | 10544 | 3296 | 40/46 | 1 | 36.081 | 0/0 |
| `debug8`（低音修复） | 10612 | 3293 | 40/46 | 1 | 34.800 | 0/0 |
| `debug8`（高音 5.2k 低通） | 10647 | 3309 | 40/46 | 1 | 33.703 | 0/0 |
| `debug8g`（仅吉他，回退档） | 8634 | 2907 | 7/46 | 1 | 34.830 | 0/0 |

- Flash 统一使用操作 **37**（`exFlash Erase,Program,Verify thru GAO-Bridge`）；普通操作 9 在这块板子上会 `SPI Verify failed`。
- 最后一次烧录：`debug8` 高音低通版，`Program and Verify flash successfully.`，27.43 s；UI `D0/M1 -> OK`。
- 串口实测：`T252/N48` → `I1/N48` → `I0/T252/N48` 全部 OK。

## 10. 验证状态与边界

- 已通过：`tb_host_kbd`（回绕/flush/0x86）、`tb_piano_bank`（36 表）、`tb_guitar_bank`（36 表）、`tb_piano_stage`、`tb_top_switch`、`tb_engine8_pitch`、`tb_top_pitch8`。
- **未跑完整 `run_simulation.ps1`**：按用户“可以跳过时间过长的验证”要求，多次烧录使用 `-SkipSimulation`；旧黄金向量仍按 72 表布局，未纳入本轮。
- **未做冷启动验收**：最后一次烧录后 UI 重连 D0/M1 OK，但没有彻底断电再上电验证 Flash 持久化。
- 已知限制：Karoryfer 最低音 E3，C2–D#3 仍是 E3 表下移；无真实低音弦 body；过载/箱体/2× 过采样、压力表情/手势未做；24 位 I2S 尚未接主低通；键控响度仅设计未实现。
- 归档目录（`archive/` 被 `.gitignore` 排除）：`FPGA-20261019-v0.6` 到 `v0.13`，以及并行的 `v0.9` 音色来源评估；详细证据在各自 MANIFEST。

## 11. 今日新增/修改的主要文件

- RTL：`top.v`、`shared_wavetable_engine.v`、`voice_transition.v`、`uart_ctrl.v`、`global_crossfade.v`、`hid_keymap.v`、`ch9350_rx.v`、`host_kbd_input.v`、`gowin_prom_piano_bank.v`、`gowin_prom_guitar_bank.v`。
- 数据：`epiano_bank_all.hex`、`guitar_bank_all.hex`、`piano_bank_all.hex`、`*_meta.json`。
- 生成器：`tools/gen_epiano_bank.py`、`tools/gen_guitar_samples_bank.py`、`tools/gen_bandlimited_prom.py`。
- UI：`tools/serial_keyboard/KeyboardCore.cs`、`KeyboardWindow.cs`、`README.md`。
- 测试：`tb_host_kbd.v`、`tb_piano_bank.v`、`tb_guitar_bank.v`、`tb_piano_stage.v`、`tb_top_switch.v`、`tb_top_guitar.v`、`tb_engine8_pitch.v`、`tb_top_pitch8.v`。
- 文档：`docs/planning/FPGA-8声部与混音-20261019-v0.1.md`、`FPGA-AKWF电钢琴与Karoryfer吉他-20261019-v0.1.md`、`FPGA-吉他低音毛刺修复-20261019-v0.1.md`、`FPGA-高音尖锐优化-20261019-v0.1.md`、`FPGA-键控响度混音-20261019-v0.2.md`、`docs/history/logs/2026/10/FPGA_FLASH_20261019.md`。
