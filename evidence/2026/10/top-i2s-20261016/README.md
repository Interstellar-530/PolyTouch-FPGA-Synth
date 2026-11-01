# 顶层标准 I2S 接入（2026-10-16）

本轮完成清单第一大类第一项：把已复核的 `i2s_tx` 接进产品顶层，并给标准 I2S 档配齐
时钟与引脚约束。到此，赛题要求的“48 kHz、24 位槽、64 BCK/LRCK 到 PCM5102A”在数字侧
已经可综合、可仿真验收；只剩外置 12.288 MHz 晶振到货后的实机验证。

## 顶层接口怎么选

`rtl/top.v` 增加编译期参数 `AUDIO_IF`：`0` = 板载 PT8211（27 MHz / 46.875 kHz，18 拍 BCK
帧，与现有点流逐位一致），`1` = 外置 PCM5102A 标准 I2S（12.288 MHz / 48 kHz，BCK =
clk/4 = 3.072 MHz，每帧 64 个 BCK）。选择是常数，综合时折叠成直连，没有运行时切钟，
没有 CDC，也不需要时钟切换原语。同一份 `top.v` 同时服务两档，参数只改默认值与约束文件。

两档各自用一个构建专用薄封装（`build/isolated/top_dbg_build.v`、`top_std_build.v`）
把本档需要的端口引到芯片边界。这不是为了好看：`top.v` 同时声明了两套音频接口，而未选
中的那套输出是常量；如果直接以 `top` 为顶层，布局器会把没有引脚约束的输出**自动分配到
Bank 5 的 SOM 互连脚**（实测落在 J3/H4/J6/J1，VCCIO 1.8 V，见本轮第一次构建报告）。
封装把未用接口在内部消化掉，于是 CST 覆盖全部端口、没有自动分配，也不会去驱动 SOM 上
别的外设。两档的点流互斥，硬件上不能同时接板载耳机和外部 DAC。

## 时钟迁移清单逐项处理

`rtl/audio/clk_params.vh` 里列出的迁移清单本轮逐项落实，避免“只换时钟、漏改分频常数”：

| 项目 | 处理方式 |
| --- | --- |
| 顶层 / POR / 同步 | 内部时钟统一为 `clk_audio`（参数折叠）；POR 计数 65536 拍，12.288 MHz 下约 5.3 ms |
| 唯一 `sample_tick` 来源 | 由选中的发送器给出：PT8211 档 576 拍（46.875 kHz），I2S 档 256 拍（48 kHz） |
| `uart_ctrl.v` | 新增 `.CLK_HZ(AUDIO_CLK_HZ)`：27 MHz 档 234 拍/位，12.288 MHz 档 107 拍/位（实际 114 841，误差 0.31%，在 UART 容许范围内） |
| `note_phase_inc.v` | 新增 `FS_HZ` 档案：48 kHz 由同一张 12 项常数表按 46875/48000 = 125/128 整数缩放得到，整数误差 ≤1 LSB；MIDI 36–96 全音域实测相对误差 ≤0.0018 cent |
| `song_player.v` | 单位时长按采样数表示：46.875 kHz 档 9766，48 kHz 档取 10000，两者都是 208.3 ms（偏差 0.004%） |
| `adsr.v` / `mixer_s6.v` | 都以 `sample_tick` 为节拍，与主时钟无关；包络步长按采样计，两档的包络时间差 2.3%（46.875→48 kHz），低于可闻阈值，本轮不动 RTL，此处明示为已知量 |
| `gpio_keyboard.v` | 新增 `CLK_HZ` 参数，按下/松开门限由它推导（1 ms / 3 ms），换档后毫秒数不变；显式指定门限的既有测试不受影响 |
| `pt8211_tx.v` | 只在调试档例化；标准档下三根板载 DAC 线恒低 |
| 控制节拍与 ADC | 2 kHz 控制节拍由 `AUDIO_CLK_HZ/2000` 推导（13500 / 6144 拍），`mcp3208_spi` 的 `CLK_HZ` 由顶层传入，SPI 仍是 250 kHz |
| 折叠观测 `clip_fold` | 引脚来自 J5/J6/J14 三个排针；硬件文档确认每个排针只有 8 个信号脚、只剩 J5-7(N9) 与 J14-11 两个空闲，装不下 4 位观测口，因此标准档不引出它（封装内部消化），调试档保持原样 |
| `analyze_audio_capture.py` 等 | 仍是 46875 Hz 基线，只对调试档有效；标准档的音频验收用本轮新增的 `tb_top_i2s.v` |

## 验证证据

**门禁**（`logs/gate-top-i2s.log`）：22 台正向测试台 + 6 个参数负例全部通过，退出码 0。
新增的 `tb_top_i2s` 在 `AUDIO_IF=1` 下做引脚级验收：

- 8621 帧（8622 个采样节拍）全部核对：LRCK 周期 256 拍、BCK 周期 4 拍且高/低各 2 拍、
  每帧 64 个 BCK、DIN 只在 BCK 下降沿变化、位置 0 与 25..31 为零填充；
- 每个 24 位槽与 DUT 的 `final_sample` 逐帧相等（高 16 位 + 低 8 位零，左右一致）；
- 未选中的板载 PT8211 三线恒低、`dac_xsmt` 恒高、三线无 X；
- A4 解码波形的向上过零平均周期 108.57 采样（理想 109.09，误差 0.48%），峰值 >1000 LSB；
- 四个音的相位增量与 `440*2^((n-69)/12)*2^32/48000` 的偏差为 6/13/35/35 LSB（≤1.5 ppm）；
- UART `X` 退出演示后出声，`M0` 后字全零，`M1` 后恢复。

**综合与布局布线**（两档各跑一次，报告在 `reports/`）：

| 指标 | 调试档（27 MHz / PT8211） | 标准档（12.288 MHz / I2S） |
| --- | ---: | ---: |
| Logic | 3545（18%） | 3687（18%） |
| Register | 1462（10%） | 1415（9%） |
| BSRAM | 2/46（5%） | 2/46（5%） |
| DSP | 6.5/24（28%） | 6.5/24（28%） |
| 实测 Fmax / 约束 | 44.633 MHz / 27 MHz | 45.046 MHz / 12.288 MHz |
| setup/hold 违例 | 0 / 0 | 0 / 0 |
| 未约束端口 | 0 | 0 |

标准档逻辑级数 20，Fmax 是约束的 3.7 倍，余量足够；I2S 三线与全部逻辑同域，由同一时钟
分频得到，因此不需要生成时钟约束。

## 已知限制与未做

标准档的 24 位是**槽宽**：合成链本身仍是 16 位样值，放在 24 位槽的高 16 位、低 8 位补零，
所以帧格式满足“48 kHz / 24 位 / 64 BCK”，但有效位深仍是 16 位，不据此宣称已具备 24 位
合成精度；真正的 24 位数据通路（音源、混音、饱和都要加宽）属于后续工作。板载耳放
`pa_en` 与 `clip_fold` 不在标准档端口表里，标准档上位时板载耳机不会有声。

实机未做：12.288 MHz 有源晶振还没到货，本轮只有仿真与综合证据，PCM5102A 的实际发声、
BCK/LRCK/DIN 时序截图、以及 IRQ→I2S 的实测延迟都还欠着。

## 复现命令

```powershell
# 门禁（沙箱外运行 Icarus）
$env:PATH = 'D:\NanjingUniversity\FPGA\msys64\ucrt64\bin;' + $env:PATH
Set-Location output/handoff_milestone2_20261008/source
pwsh -NoProfile -File sim/run_simulation.ps1 `
  -Iverilog D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\iverilog.exe `
  -Vvp D:\NanjingUniversity\FPGA\msys64\ucrt64\bin\vvp.exe

# 两档综合 + 布局布线（只构建，不烧录）
cd D:\NanjingUniversity\FPGA\PolyTouch-FPGA-Synth-integration
& 'D:\Gowin_V1.9.11.03_Education_x64_win\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe' `
  output/handoff_milestone2_20261008/source/build/build_top_integrated.tcl
& 'D:\Gowin_V1.9.11.03_Education_x64_win\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe' `
  output/handoff_milestone2_20261008/source/build/build_top_i2s_std.tcl
```

换档后要重新生成的构建目录：`build/gowin_top_integrated/`、`build/gowin_top_i2s_std/`
（两档的 tcl 只在工程不存在时添加文件，改了文件表要先删掉对应目录）。