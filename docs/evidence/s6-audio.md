# S6 双波表、同步 ROM 与混音自检

本交付只覆盖无外设条件下的数字模型。`wavetable_rom_dual.v` 提供两个
512×16 signed 表的同步读模型：地址在时钟边沿采样，`sine_q`/`bright_q`
在该边沿更新。`mix_enable=0` 时由 `mix_weight` 的高位选择表，置 1 时按
`mix_weight` 做 8 位交叉混合；输出在 16 位范围内饱和。工程中保留
Gowin BSRAM/pROM 的替换边界，行为模型不能代替厂商原语的综合验证。

`wavetable_osc_dual_s6.v` 在同一同步 ROM 契约上读取相邻地址并做 9 位
线性插值；相位 bits `[31:23]` 为 512 点地址，`[22:14]` 为小数，输出比
ROM 请求多一拍。相邻地址回绕依赖 9 位地址宽度，因此 `DEPTH` 固定为 512。
它是双端口 ROM 的仿真模型，生产实现应替换为两张 Gowin BSRAM/pROM IP。

`mixer_s6.v` 将四个 16 位声部先扩展到 20 位再求和，按
`VOLUME_SHIFT`（默认除以 2）缩放并饱和。`clip_count` 在每个
`sample_tick` 对主增益缩放后超出 signed 16 位的帧加一次，统计点固定在 FIR
之前；`clip_event` 给出同一帧的脉冲，FIR 后的饱和不会把同一帧重复计数。
`clear_clip` 同步清零，计数器到全 1 后保持。五抽头 FIR 的系数是标准二项式
`(1,4,6,4,1)/16`（中抽头 6，直流增益 1），通过 `FIR_ENABLE` 旁路，两个路径
都在采样节拍寄存输出。旁路路径的帧边界是采样节拍本身，FIR 路径的中抽头落在
`d2`，比旁路多 2 帧群延迟（46.875 kHz 下 42.7 µs，48 kHz 下 41.7 µs）；
修正后的频响为 1 kHz -0.08 dB、5 kHz -1.99 dB、10 kHz -8.47 dB、
15 kHz -21.68 dB、20 kHz -51.31 dB（46.875 kHz），顶层接入 I2S 时要把这
2 帧延迟计入或固定启用 FIR。

`tools/generate_wavetables.py` 保留 v1.0.0 正弦表并生成最多 16 次谐波的
亮音色表；两表各 512 项、signed 16 位，重新生成后校验值不变：

| 表 | 最小值 | 最大值 | SHA-256 |
| --- | ---: | ---: | --- |
| `wave_sine.hex` | -32767 | 32767 | `b75030d2aee625d0628efc6e79d27ecbd52c747f1ba8deab5334064f3aa70ef9` |
| `wave_bright.hex` | -32767 | 32767 | `c16616d4149f6d142569b266d325b5e99e13eb2f476a93bf8e67fd73d4bcfd63` |

`tools/s6_reference.py` 是与 RTL 位精确对应的定点参考，并可直接生成 HDL
逐值对照所需的向量（插值、混合、混音与 FIR），自检会报出 FIR 抽头、直流
增益与频响：

```text
python tools/generate_wavetables.py
python tools/s6_reference.py
python tools/s6_reference.py --vectors output/handoff_milestone2_20261008/source/sim/vectors
PASS s6_reference: sine/bright depth=512, wrap/interp, blend, FIR taps=(1, 4, 6, 4, 1) dc_gain=1.000, extrema clipped
```

RTL 自检台 `source/sim/tb_s6_audio.v` 保留交付版定性检查的同时，改成与向量
逐值对照：3584 个相位点（全部 512 个地址 × 7 个分数，含 511→0 接缝与取整
平局分数）、1024 个 ROM 交叉混合点、256 个插值后混合点、510 个混音器样本
（VOLUME_SHIFT 0/1/2 × FIR 旁路/启用，逐个核对输出、每帧 clip_event 与累计
clip 计数）、32 个 FIR 小幅度样本。运行：

```powershell
$env:PATH = 'D:\NanjingUniversity\FPGA\msys64\ucrt64\bin;' + $env:PATH   # 否则会缺少 msys DLL
Set-Location output/handoff_milestone2_20261008/source
python ../../../tools/s6_reference.py --vectors sim/vectors       # 改参考后必须重生成
iverilog -g2012 -I . -o sim/tb_s6_audio.vvp `
  sim/tb_s6_audio.v rtl/audio/wavetable_rom_dual.v rtl/audio/wavetable_osc_dual_s6.v rtl/audio/mixer_s6.v
vvp sim/tb_s6_audio.vvp
# PASS tb_s6_audio: ROM sync/select, 3584 osc vectors, 1024+256 blend points, 510 mixer vectors, 32 FIR samples
```

2026-10-15 的独立复核发现交付版 `mixer_s6.v` 的 FIR 中抽头写成 8，实际系数
是 (1,4,8,4,1)/16，直流增益 18/16 并在 1 kHz 处抬升约 1 dB；交付版自检只测
已削波的满幅输入，两版都会饱和到同一值，所以没有暴露。同一轮复核补齐了
逐值对照、修正抽头、记录 FIR 群延迟与频响，14 台门禁通过，详见
[S6 复核记录](../s6-review-20261015/README.md)。交叉混合采用
`(255-w, w) >> 8`，端点比纯表值低 1/256（满幅最多 128 LSB，约 -0.034 dB），
属 8 位权重的取舍，已在复核记录中登记。

板级双 ROM 的 Gowin IP、CST/SDC、I2S 顶层接线和 DAC 波形仍属于 T04 实机
验收范围；本记录不把仿真 PASS 记为硬件 PASS。本模块尚未做综合与 PnR，每个
ROM 实例按 512×16 计 2 块 BSRAM，振荡器与混合另有 25×25/27×27 乘法器，
建议在下一次综合报告里记录 DSP/LUT 占用。