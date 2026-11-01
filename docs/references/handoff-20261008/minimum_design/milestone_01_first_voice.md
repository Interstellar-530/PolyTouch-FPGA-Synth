# 里程碑 1：单声部 DDS + ADSR + PT8211

日期：2026-10-07

## 已实现

- 27 MHz 板载时钟输入。
- 512 点 16 位单周期正弦波表，推断为 1 个 BSRAM pROM。
- 单个 32 位相位累加器 DDS，目标音高 440 Hz。
- ADSR 包络。里程碑 1 当时用 0.25 s 发声、0.25 s 静音的方式重复触发，便于观察包络；该做法在 2026-10-10 的修订二中改为门控常开、包络停在延音电平，见 `docs/history/logs/2026/10/FPGA_DEBUG_LOG_20261010.md`。
- PT8211 右对齐调试发送器。
- 板载耳机功放 `PA_EN` 上电延迟使能。

## 构建结果

- Gowin 综合、布局布线和码流生成通过。
- 目标器件：`GW2A-LV18PG256C8/I7`，版本 C。
- LUT：275。
- 寄存器：111。
- BSRAM：1。
- 18x18 乘法器：1。
- 建立违例：0。
- 保持违例：0。
- 实际 Fmax：115.505 MHz。
- 码流：`D:\NanjingUniversity\FPGA\FPGA\impl\pnr\instrument.fs`。
- 构建证据：`docs\evidence\first_voice_build.json`。

## 引脚

| 信号 | 引脚 |
| --- | --- |
| 27 MHz | H11 |
| PT8211 BCK | N15 |
| PT8211 WS | P16 |
| PT8211 DIN | P15 |
| 功放使能 | R16 |
| LED | N16 |

## 当前限制

- 该版本使用 27 MHz 生成约 1.5 MHz BCK 和 46.875 kHz WS，仅用于板载 PT8211 调试。
- 正式版本仍需外部 12.288 MHz 时钟和 PCM5102A 标准 I2S。
- 当前尚未完成上板烧录和听音验证：Gowin Programmer 未检测到 JTAG 电缆。
- 尚未接入触摸、FSR、多声部混音和 UART 状态输出。

## 下一步

1. 连接板卡并确认 `programmer_cli.exe --scan-cables` 能识别下载器。
2. 执行 `build\program_sram.ps1`，确认能听到重复 440 Hz 单音和 ADSR。
3. 加入 UART 状态输出。
4. 接入 MPR121，完成 12 键触摸事件。
5. 参数化扩展到 4 声部。
