# MANIFEST

- 项目：PolyTouch-FPGA-Synth
- 归档版本：v0.1
- 修改日：2026-10-20
- FPGA 源仓库：`https://github.com/Interstellar-530/PolyTouch-FPGA-Synth`
- FPGA 源分支：`codex/s4-s6-pressure`
- FPGA 源提交：`9d467e01f3899933043ef759bdafe1f302dd9f4b`
- 原始采样库：`https://github.com/sfzinstruments/karoryfer.black-and-green-guitars`
- 原始采样提交：`b3b3249d37dc977a1a297bd2dc053e6d9b6b805c`
- 原始采样许可证：CC0-1.0
- 板卡：Tang Primer 20K Dock 3714，GW2A-LV18PG256C8/I7；板载 128M DDR3、32 Mbit NOR Flash
- 当前综合余量：BSRAM 40/46，剩余 6 块，约 13.5 KB

## 归档目的

区分三种状态并提供可复现证据：

1. `wav/`：当前单周期 FPGA 波表引擎的真实软件渲染。
2. `real_samples/wav/`：原始 Karoryfer 采样，保留真实拨弦起音和自然衰减，是完整采样架构的参考目标。
3. `hybrid/`：可落地的“真实起音 + 波表延音 + 指数衰减”混合方案原型，是下一步 RTL 改造的试听目标。

## 文件分区

### 当前 FPGA 波表版

- `render_guitar_previews.py`：按 RTL 音区、力度变体、512 点插值和吉他 ADSR 渲染。
- `make_comparison_svg.py`：生成波形/谐波对比 SVG。
- `wav/`：48 kHz、16 位单声道播放版。
- `wav_raw_46875/`：46.875 kHz 原始渲染版。
- `guitar_timbre_comparison.png` / `.svg`：五种 C4 波表变体的波形和前 40 个谐波。
- `evidence/preview_metrics.json`：时长、峰值、RMS、频谱重心、bank 与变体映射。

### Karoryfer 原始采样参考版

- `samples/`：从 CC0 仓库下载的 12 个 44.1 kHz、24 位单声道 WAV。
- `render_real_guitar_samples.py`：读取 24 位 WAV，保留真实起音和衰减，生成 48 kHz 播放版。
- `real_samples/wav/`：六个 B3 单音、两段短句、两个扫弦和弦。
- `real_samples/wav_raw_44100/`：44.1 kHz 原始渲染版。
- `real_samples/evidence/real_sample_metrics.json`：时长、峰值、RMS、起音/衰减段频谱重心和源文件映射。
- `make_ab_comparison.py`：同一 B3 的波表版与真实采样版 A/B。
- `ab/`：两个 A/B 对照文件。

### 混合方案原型

- `render_hybrid_guitar.py`：真实起音 + 波表主体 + 指数衰减 + 5 kHz 低通。
- `hybrid/01`–`05`：五个 C4 混合单音。
- `hybrid/06`：五个 C4 混合音色串联。
- `hybrid/07`：B3 的“当前波表 → 混合 → 原始采样”三段 A/B。
- `hybrid/08`：green/mf 和 black/mf 的四音混合扫弦和弦。
- `hybrid/hybrid_metrics.json`：映射、时长、峰值、RMS 和起音/衰减段频谱重心。

### 其他

- `README.md`：试听顺序、音色说明、存储预算、边界和复现方法。
- `commands/reproduce.ps1`：复现命令。
- `checksums.sha256`：本目录所有文件的 SHA256，不包含自身。

## 混合方案的资源边界

- 40 ms 起音、16 位、46.875 kHz 单声道约 3.75 KB；2 个吉他类型约 7.5 KB，占 4 块 BSRAM。
- 30 ms 起音约 2.81 KB；4 个起音变体约 11.25 KB，占 5 块 BSRAM。
- 6 个变体各 50 ms 约 28 KB，超出剩余 BSRAM；软件原型使用 50 ms × 6 只是为了试听，不代表 RTL 可以直接照搬。
- 完整多秒采样需要 128M DDR3 或 32 Mbit NOR Flash 的控制器、缓存、仲裁和新引脚约束，属于后续架构阶段。

## 仓库状态

本轮只在独立归档目录生成试听、采样、混合原型和对比文件，没有修改 Git 仓库、RTL、位流或工作区文件。