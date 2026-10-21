# 优化 05：波表空间与带限配置（2026-10-21）

对应 `docs/reviews/FPGA-Git差异与优化方向-20261021-v0.1.md` 的第 5 项。做法是先用入库 HEX 做
频谱/重建误差/资源代价分析，再按分析结果复用表数据：**钢琴 36 表压到 12 表、吉他 36 表压到 30 表，
BSRAM 40 → 25 块**。没有改采样深度、没有改寻址位宽、没有改 ROM 类型。

## 原指标

| 项 | 改前状态 |
|---|---|
| BSRAM | 40/46（钢琴 bank 18、吉他 bank 18、明亮 bank 3、正弦 1），仅余 6 块 |
| 钢琴 | 6 音区 × 6 阶段 = 36 表，bank = zone*6 + stage |
| 吉他 | 6 频段 × 6 力度变体 = 36 表，bank = band*6 + variant |
| 明亮 | 6 张通用表，3 块 BSRAM |

### 分析结果（脚本读数，见 `commands/analyze_banks.py`）

- **钢琴音区**：zone 0–4 的表只差浮点舍入。相对 zone 0 的逐阶段 waveform 误差（mean over stages）：
  zone1 −87.2 dB、zone2 −82.3 dB、zone3 −76.8 dB、zone4 −73.1 dB；**最差单个阶段 −60.7 dB**。
  zone 5 因为真正被带限到 10 个谐波，与 zone 0 差 −52.0 dB。
- **钢琴阶段**：相邻阶段差 −34…−37 dB，属于真实音色演进，但比音区差异大 2–3 个数量级。
- **吉他**：band 0 与 band 1 取自同一个采样，6 个力度变体**逐位相同**；其余 band 之间差 +0.2…+3.8 dB
  （真实不同，不能合并）。
- **明亮 bank**：`wave_bright_h16` 与 `wave_bright` 逐位相同，但 6 表压到 5 表仍占 3 块，**没有收益**，未改。
- **降低深度到 256 点**：重建误差 −66…−69 dB、>h128 混叠能量 ≤ −86.9 dB，技术上可行；但要把所有
  ROM 和两套引擎的 9 位地址/插值统一改成 8 位，改动面大，本项不做，留作后续选项。
- **合并阶段（6→4）**：可省同样 12 块，但误差 −34 dB（比音区合并差 26 dB），不选。

## 优化方法

1. 按分析结论做**表复用**，保持 Gowin pROM 原语与 512 点深度不变：
   - 钢琴：zone 0–4 共用 zone 0 的 6 张阶段表（组 0），zone 5 单独 6 张（组 1，保留 10 谐波带限，
     保证 MIDI 95 的 12 次谐波不会越过 Nyquist）。`bank = group*6 + stage`。
   - 吉他：band 0/1 共用一组，其余 4 个 band 各自一组。`bank = group*6 + variant`。
2. 再制表脚本显式产出压缩后的 bank（`gen_epiano_bank.py` 12 表/6 pROM、`gen_guitar_samples_bank.py`
   30 表/15 pROM、`gen_piano_prom.py` 同步）；pROM 选择位宽相应改为 3 位/4 位。
3. 引擎只改两个 bank 映射函数（`piano_band_config`、`guitar_band_config`），寻址、插值、包络、
   交叉淡化、键控增益全部未动。
4. 测试同步：`tb_piano_bank` 12 表、`tb_guitar_bank` 30 表；`tb_piano_engine`（bank 4）、
   `tb_piano_morph`（body 0 / hammer 4）、`tb_piano_stage`（start 3 / stage2 2）改为新 bank 编号，
   这三台原本因旧 72 表编号而失败，现在通过。

## 最终指标

| 检查项 | 改前 | 改后 |
|---|---:|---:|
| BSRAM | 40 / 46 | **25 / 46** |
| 空闲 BSRAM | 6 | **21** |
| 钢琴表 | 36 | **12**（2 组 × 6 阶段） |
| 吉他表 | 36 | **30**（5 组 × 6 变体） |
| 钢琴音色变化（含 zone 0–4 复用） | — | 最差单阶段 **−60.7 dB**（0.09% RMS，听不见） |
| 吉他音色变化 | — | **0（逐位相同）** |
| ROM 逐地址校验 | — | `tb_piano_bank`（6144 地址）、`tb_guitar_bank`（15360 地址）全过 |
| 相关回归 | — | 10/11 通过；`tb_generic_bright` 仍是既有的旧调度期望（108/40 vs 现引擎 120/44），与本项无关 |

## 试听文件（本次交付）

`audio/piano/` 与 `audio/guitar/` 各含：

- `ab.wav`：**前段=压缩前、后段=压缩后**，中间 0.6 s 静音；同一个乐句（6 个音，各 0.7 s）
- `before.wav` / `after.wav`：单独的前/后乐句
- `diff.wav`：`(after − before)` 放大 +40 dB（刻意放大；未放大时约比音乐低 78 dB）
- `null_control.wav`：数字静音（播放器/环境噪声参照）
- `diff_control_stage.wav`：真实起音音色变化（起始阶段 4 vs 3）同样 +40 dB，用于校准“可闻差异”的响度
- `null_test.txt`、`controls.txt`：差分与对照的电平记录

实测空测结果（48 kHz WAV，逐样本回读）：

| 乐器 | 差分 RMS（相对音乐） | 绝对差分 RMS | 绝对差分峰值 | 结论 |
|---|---:|---:|---:|---|
| 钢琴 | **−77.6 dB** | −88.3 dBFS（≈1.26 LSB RMS） | −63.5 dBFS（≈22 LSB） | 远低于正常回放的可闻阈值，约 1 LSB 量级的舍入噪声 |
| 吉他 | **精确 0** | 精确 0 | 精确 0 | 数据逐位相同 |

补充：差分与信号相关性仅 0.128、能量在 0–24 kHz 平坦分布，属于表格各自量化取整的差异，不是增益或音色偏差；
6 个音里 C6（zone 5，保留独立表）差分为**精确 0**，差异全部来自 C2–C5（zone 0–4 复用 zone 0 表）。
`diff_control_stage.wav` 是真实音色变化的对照，同增益下比 `diff.wav` 响约 42 dB，可用来判断“听到的内容”
到底属于哪一档。

试听用的“压缩前”bank 保留在 `banks_before/`；渲染脚本 `tools/render_bank_ab.py` 可重跑。
该 WAV 是“波表回放模型”（9 位地址、9 位线性插值、阶段交叉淡化、ADSR），不含主低通/VCA，
只隔离本项改变的“读哪张表”。

## 资源占用对比（debug8usb，GW2A-18，gw_sh V1.9.11.03）

| 资源 | 优化前 | 优化后 | 差值 |
|---|---:|---:|---:|
| **BSRAM** | **40 / 46 (87%)** | **25 / 46 (54%)** | **−15（−37.5%）** |
| Logic | 11668 / 20736 (56%) | 11392 / 20736 (55%) | −276 |
| Register | 3705 / 16173 (23%) | 3702 / 16173 (23%) | −3 |
| DSP | 1.75 / 24 | 1.75 / 24 | 0 |
| Fmax @ 27 MHz | 39.408 MHz | 37.890 MHz | −1.518 MHz |
| 最差建立裕量 | +11.662 ns | +10.645 ns | −1.017 ns |
| 最差保持裕量 | +0.318 ns | +0.208 ns | −0.110 ns |

时序仍远高于 27 MHz（37.890 MHz、建立裕量 +10.645 ns、负裕量端点 0）；逻辑单元同时少了 276 个
（ROM 选择树变小）。空出的 21 块 BSRAM 可供合唱、显示缓冲或更多音色使用，但按项目规则，
新增功能前仍需重新核算 RAM 与 18×18/36×18 乘法资源。

## 复现命令

```powershell
# 分析
tools\.venv-audio-analysis\Scripts\python.exe commands\analyze_banks.py
# 再制表（源素材在 tmp/akwf、tmp/karoryfer）
tools\.venv-audio-analysis\Scripts\python.exe tools\gen_epiano_bank.py
tools\.venv-audio-analysis\Scripts\python.exe tools\gen_piano_prom.py
tools\.venv-audio-analysis\Scripts\python.exe tools\gen_guitar_samples_bank.py
# 试听
tools\.venv-audio-analysis\Scripts\python.exe tools\render_bank_ab.py `
  --before-hex banks_before\epiano_bank_all_36.hex `
  --after-hex ..\..\output\handoff_milestone2_20261008\source\rtl\audio\epiano_bank_all.hex `
  --kind piano --out-dir audio\piano
# 构建
cd output\handoff_milestone2_20261008\source\build
.\build.ps1 -Profile debug8usb -GwSh E:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe
```

## 文件

- `audio/piano/`、`audio/guitar/`：试听 WAV 与空测报告
- `banks_before/`：压缩前的 36 表 bank（复现试听用）
- `metrics_after.json`、`debug8usb.receipt.json`、`build_reports/`
- 分析/渲染脚本在 `tools/`（`render_bank_ab.py`）与本目录 `commands/`（`analyze_banks.py`）
