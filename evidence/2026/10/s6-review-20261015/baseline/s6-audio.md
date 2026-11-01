# S6 双波表、同步 ROM 与混音自检

本交付只覆盖无外设条件下的数字模型。`wavetable_rom_dual.v` 提供两个
512×16 signed 表的同步读模型：地址在时钟边沿采样，`sine_q`/`bright_q`
在该边沿更新。`mix_enable=0` 时由 `mix_weight` 的高位选择表，置 1 时按
`mix_weight` 做 8 位交叉混合；输出在 16 位范围内饱和。工程中保留
Gowin BSRAM/pROM 的替换边界，行为模型不能代替厂商原语的综合验证。

`wavetable_osc_dual_s6.v` 在同一同步 ROM 契约上读取相邻地址并做 9 位
线性插值；相位 bits `[31:23]` 为 512 点地址，`[22:14]` 为小数，输出比
ROM 请求多一拍。它是双端口 ROM 的仿真模型，生产实现应替换为两张 Gowin
BSRAM/pROM IP。

`mixer_s6.v` 将四个 16 位声部先扩展到 20 位再求和，按
`VOLUME_SHIFT`（默认除以 2）缩放并饱和。`clip_count` 在每个
`sample_tick` 对主增益缩放后超出 signed 16 位的帧加一次，统计点固定在 FIR
之前；`clip_event` 给出同一帧的脉冲，FIR 后的饱和不会把同一帧重复计数。
`clear_clip` 同步清零，计数器到全 1 后保持。五抽头 FIR 的系数为
`(1,4,6,4,1)/16`，通过 `FIR_ENABLE` 旁路，两个路径都在采样节拍寄存输出，
明确保留一个帧边界。

`tools/generate_wavetables.py` 保留 v1.0.0 正弦表并生成最多 16 次谐波的
亮音色表；两表各 512 项、signed 16 位，当前校验如下：

| 表 | 最小值 | 最大值 | SHA-256 |
| --- | ---: | ---: | --- |
| `wave_sine.hex` | -32767 | 32767 | `b75030d2aee625d0628efc6e79d27ecbd52c747f1ba8deab5334064f3aa70ef9` |
| `wave_bright.hex` | -32767 | 32767 | `c16616d4149f6d142569b266d325b5e99e13eb2f476a93bf8e67fd73d4bcfd63` |

离线参考检查（相位 9 位地址、9 位插值小数、512 点环绕、混合与四路极值
饱和）通过：

```text
python tools/generate_wavetables.py
python tools/s6_reference.py
PASS s6_reference: sine/bright depth=512, wrap/interp, blend=18869, extrema clipped
```

RTL 自检台为 `source/sim/tb_s6_audio.v`，覆盖同步读延迟、表切换/50:50
混合、四路同相正负极值、clip 计数/清零，以及 FIR 从零历史到稳态的响应。
在装有 Icarus Verilog 的环境中运行：

```powershell
Set-Location output/handoff_milestone2_20261008/source
iverilog -g2012 -I . -o sim/tb_s6_audio.vvp `
  sim/tb_s6_audio.v rtl/audio/wavetable_rom_dual.v rtl/audio/wavetable_osc_dual_s6.v rtl/audio/mixer_s6.v
vvp sim/tb_s6_audio.vvp
# PASS tb_s6_audio: dual ROM sync/select/interpolation, mixer saturation, FIR and clip counter
```

在当前打包的 Windows MSYS2 环境，`iverilog.exe` 编译结束时会额外返回
`-1073741819`，但仍生成完整 `.vvp`；上述 `vvp` 退出码为 0 且自检通过。
干净安装的 Icarus 应以编译和运行均为 0 为准，临时 `.vvp` 文件不纳入交付。

板级双 ROM 的 Gowin IP、CST/SDC、I2S 顶层接线和 DAC 波形仍属于 T04 实机
验收范围；本记录不把仿真 PASS 记为硬件 PASS。
