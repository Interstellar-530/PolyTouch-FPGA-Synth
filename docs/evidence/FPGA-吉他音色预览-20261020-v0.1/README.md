# 吉他音色预览与改造原型（2026-10-20）

## 三套预览

当前 FPGA 引擎每张吉他表只保存一个稳定周期，再把周期循环播放，因此 `wav/` 听起来更像持续的合成器音色。真实吉他的辨识度很大一部分来自拨弦瞬态、起音后的快速频谱变化和自然衰减，而这些信息在单周期表里已经不存在。

本目录有三套文件：

- `wav/`：当前 `codex/s4-s6-pressure` 分支 FPGA 波表引擎的忠实输出，代表现在板子实际会听到的声音。
- `real_samples/wav/`：Karoryfer 原始 24 位采样，保留真实拨弦起音和自然衰减，是完整采样播放的参考目标。
- `hybrid/`：可落地的混合方案原型，用真实采样的拨弦起音接现有 512 点波表，再把包络改成指数衰减；它不是当前位流输出，而是下一步 RTL 改造的试听目标。

## A. 当前 FPGA 单周期波表版

源提交为 `9d467e01f3899933043ef759bdafe1f302dd9f4b`。6 个音区沿用 RTL 的相位增量边界，变体沿用当前力度映射；512 点线性插值，吉他 ADSR 为 attack 256、decay 3、sustain 45875、release 8。原始渲染采样率 46.875 kHz，`wav/` 是 48 kHz 播放版。

| 文件 | 内容 | 力度 | 变体 |
|---|---|---:|---|
| `wav/00_all_variants_C4.wav` | C4 五种音色串联 | 20/48/80/100/120 | green/p → green/mf → green/f → black/mf → black/f |
| `wav/01_green_p_C4_vel20.wav` | C4 单音 | 20 | green/p |
| `wav/02_green_mf_C4_vel48.wav` | C4 单音 | 48 | green/mf |
| `wav/03_green_f_C4_vel80.wav` | C4 单音 | 80 | green/f |
| `wav/04_black_mf_C4_vel100.wav` | C4 单音 | 100 | black/mf |
| `wav/05_black_f_C4_vel120.wav` | C4 单音 | 120 | black/f |
| `wav/06_green_f_phrase_C4_G4_C5_E5.wav` | C4–G4–C5–E5 短句 | 80 | green/f |
| `wav/07_black_f_phrase_C4_G4_C5_E5.wav` | C4–G4–C5–E5 短句 | 120 | black/f |

`wav_raw_46875/` 保存原始 46.875 kHz 文件。C4 单音频谱重心分别为 green/p 439.2 Hz、green/mf 472.6 Hz、green/f 521.8 Hz、black/mf 412.3 Hz、black/f 480.5 Hz。

## B. Karoryfer 原始采样参考版

采样库：`https://github.com/sfzinstruments/karoryfer.black-and-green-guitars`，提交 `b3b3249d37dc977a1a297bd2dc053e6d9b6b805c`，许可证 CC0-1.0。下载的 12 个原始 WAV 保存在 `samples/`，均为 44.1 kHz、24 位单声道。`real_samples/wav/` 是线性重采样到 48 kHz 的播放版，`real_samples/wav_raw_44100/` 保留原始采样率。

| 文件 | 内容 |
|---|---|
| `real_samples/wav/00_all_six_real_B3.wav` | B3 六种原始采样串联：green/p、green/mf、green/f、black/p、black/mf、black/f |
| `real_samples/wav/01_green_p_B3_real.wav` | green/p，B3 原始采样 |
| `real_samples/wav/02_green_mf_B3_real.wav` | green/mf，B3 原始采样 |
| `real_samples/wav/03_green_f_B3_real.wav` | green/f，B3 原始采样 |
| `real_samples/wav/04_black_p_B3_real.wav` | black/p，B3 原始采样 |
| `real_samples/wav/05_black_mf_B3_real.wav` | black/mf，B3 原始采样 |
| `real_samples/wav/06_black_f_B3_real.wav` | black/f，B3 原始采样 |
| `real_samples/wav/09_green_mf_phrase_B3_E4_G4_B4.wav` | green/mf 真实采样短句 |
| `real_samples/wav/09_black_mf_phrase_B3_E4_G4_B4.wav` | black/mf 真实采样短句 |
| `real_samples/wav/10_green_mf_chord_B3_E4_G4_B4.wav` | green/mf 扫弦和弦 |
| `real_samples/wav/10_black_mf_chord_B3_E4_G4_B4.wav` | black/mf 扫弦和弦 |

`ab/ab_wavetable_vs_real_green_f_B3.wav` 和 `ab/ab_wavetable_vs_real_black_f_B3.wav` 是同一 B3 音的当前波表与原始采样直接对照。

## C. 混合方案原型（推荐先落地）

`hybrid/` 使用真实采样的前 50 ms 起音，在约 18–46 ms 内交叉淡入现有 512 点波表，波表部分使用约 0.45–1.15 s 的指数衰减和 5 kHz 低通，不再保持 70% 的持续电平。这样既保留真实拨弦瞬态，又继续使用现有 36 张波表和 8 声部结构。

| 文件 | 内容 |
|---|---|
| `hybrid/01_green_p_C4_hybrid.wav` | green/p，C4 混合音色 |
| `hybrid/02_green_mf_C4_hybrid.wav` | green/mf，C4 混合音色 |
| `hybrid/03_green_f_C4_hybrid.wav` | green/f，C4 混合音色 |
| `hybrid/04_black_mf_C4_hybrid.wav` | black/mf，C4 混合音色 |
| `hybrid/05_black_f_C4_hybrid.wav` | black/f，C4 混合音色 |
| `hybrid/06_all_variants_C4_hybrid.wav` | 五种 C4 混合音色串联 |
| `hybrid/07_ab_wavetable_hybrid_real_green_f_B3.wav` | B3：当前波表 → 混合 → 原始采样 |
| `hybrid/07_ab_wavetable_hybrid_real_black_f_B3.wav` | B3：当前波表 → 混合 → 原始采样 |
| `hybrid/08_green_mf_chord_B3_E4_G4_B4_hybrid.wav` | green/mf 混合扫弦和弦 |
| `hybrid/08_black_mf_chord_B3_E4_G4_B4_hybrid.wav` | black/mf 混合扫弦和弦 |

### 存储预算

当前综合结果为 BSRAM 40/46，剩余 6 块，约 13.5 KB。46.875 kHz、16 位单声道下：

- 40 ms 起音采样约 3.75 KB；2 个吉他类型约 7.5 KB，占 4 块 BSRAM。
- 30 ms 起音采样约 2.81 KB；4 个起音变体约 11.25 KB，占 5 块 BSRAM。
- 6 个变体各 50 ms 约 28 KB，放不进剩余 BSRAM；因此 RTL 版不能照搬软件原型的 50 ms × 6，需要压到 2–4 个起音采样，或用 20–30 ms 并配合力度/滤波近似。
- 128M DDR3 和 32 Mbit NOR Flash 都在板上，但完整多秒采样播放需要 DDR3/Flash 控制器、缓存、仲裁和新的引脚约束，属于第二阶段，不是本轮小改。

## 客观指标与边界

`evidence/preview_metrics.json`、`real_samples/evidence/real_sample_metrics.json` 和 `hybrid/hybrid_metrics.json` 分别记录三套版本的时长、峰值、RMS、频谱重心和映射。所有播放文件峰值归一化到 −3 dBFS，避免音量差异掩盖音色差异。

`real_samples/` 和 `hybrid/` 都是软件参考，不是当前位流输出。混合方案的声音会比当前波表版明显更接近吉他，但仍不包含完整采样琴体、整段自然衰减和真实拾音位置变化；要做到与 `real_samples/` 完全一致，必须上完整采样播放架构。

## 复现

```powershell
python .\render_guitar_previews.py
python .\render_real_guitar_samples.py
python .\make_ab_comparison.py
python .\render_hybrid_guitar.py
python .\make_comparison_svg.py
```

需要 Python 3.12 与 NumPy。原始采样版还需要先从上述 CC0 仓库下载 `samples/` 中的 12 个 WAV；下载地址和文件清单记录在 `MANIFEST.md`。输出目录写死在脚本顶部，移动目录后需同步修改 `OUT`。