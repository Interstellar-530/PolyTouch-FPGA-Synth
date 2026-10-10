# Current Status

Date: 2026-10-08

## Verified

- The handoff package from 2026-10-07 was checked: all 50 listed files match
  their SHA256 values.
- RTL source exists and is buildable with the package Tcl script.
- Gowin synthesis, place and route, and bitstream generation pass.
- Target device is `GW2A-LV18PG256C8/I7`, version C.
- The board 27 MHz clock was restored by reseating the core board.
- Four user LEDs (N16, N14, L14, L16) blink when driven by the 27 MHz clock.
- Orange_LED2 on N16 blinks in the normal single-voice bitstream.
- `SRAM Program` operation 2 succeeds and returns exit code 0.
- `SRAM Program and Verify` operation 4 fails with `Verify Failed` and status
  code `0x00006020`; use operation 2 instead.
- GAO core is integrated and `artifacts/ao_0.fs` is generated.

## Implemented

- 27 MHz board clock input.
- 512-entry, 16-bit signed sine wavetable.
- One 32-bit DDS phase accumulator.
- 440 Hz target tone at the 46.875 kHz debug sample rate.
- ADSR state machine. The gate is held high after reset, so the voice attacks, decays to sustain and then holds that level continuously.
- PT8211 serial transmitter and PA_EN power-on delay.
- LED2 (N16) 1 Hz blink indicator.
- GAO RTL configuration `source/rtl/gao_top.rao`.
- GAO capture signals: `sample_tick`, `gate`, `voice_sample[15:0]`,
  `hp_bck`, `hp_ws`, `hp_din`, `pa_en`, and `led`.

## Not Verified

- Audio has not been listened to on hardware because no headphone or powered
  speaker was available.
- GAO waveform capture has not been completed yet.
- The standalone `gao_analyzer.exe` does not open in this environment; use the
  Gowin IDE built-in GAO.
- Gowin IDE direct synthesis can still miss `rtl/audio/wave_sine.hex`.
- No MPR121, MCP3208, FSR, UART, PCM5102A, or polyphonic mixer exists yet.

## Current Technical Boundary

- Debug output uses the on-board PT8211 and 27 MHz clock.
- Debug BCK is about 1.5 MHz and WS is 46.875 kHz.
- The final competition path must use standard I2S to PCM5102A.
- The formal 48 kHz clock source needs a confirmed free 3.3 V GCLK pin.

## Immediate Next Action

Open the project in Gowin IDE, program `artifacts/ao_0.fs` with operation 2 if
needed, open `source/rtl/gao_top.rao`, and use the built-in GAO capture window
to verify `sample_tick`, `gate`, `voice_sample[15:0]`, and the PT8211 signals.

## 2026-10-10 Update
- Normal bitstream rebuilt from the latest source: SHA256 f2cb3a6d84eeab1cee3a43c4ecb44e0566b93e09c1b4476c774154ceb03ecafb.
- Key tone switching implemented with T3/T2 user keys and a 38.8 ms debounce.
- Volume reduced by digital right shift 2, about -12 dB.
- Normal build contains no GAO core and uses 361 LUT, 189 registers, 1 BSRAM, 0.5 DSP.
- Gowin SRAM Program operation 2 succeeds; Read Device Codes succeeds; installation key files are present.


## 2026-10-10 修订二更新

- 已消除 0.25 秒通断门控，复位释放后持续发声，ADSR 保持在延音电平。
- 已按官方例程重写 PT8211 帧结构和 WS 相位，修掉一个位的字对齐错误。
- 修订二码流 SHA256 `0612d3383736688423204cd2a04ad2350a110d9c7c7e3f483008a6ddb2faa399`，User Code `0x00009F8A`。
- 修订二资源：331 逻辑单元、188 寄存器、1 BSRAM、0.5 DSP；0 建立违规、0 保持违规。
- 默认输出 A4 440 Hz，T3 切 C4 261.63 Hz，T2 切 C5 523.25 Hz，音量数字右移 2 位约 -12 dB。
- 硬件听感复核仍需要用户戴上耳机确认背景噪声是否下降到可接受水平。



## 2026-10-10 修订三更新

- DDS 加入线性插值，音频链路加入 (1,2,1)/4 两级平滑和四舍五入的音量控制。
- 频谱模型显示带内误差由 -46.0 dBFS 降到 -94.8 dBFS，改善 48.8 dB。
- 资源：968 LUT/ALU、237 寄存器、1 BSRAM、2 个 18×18 乘法器（含 1 个 PADD18）；0 建立违规、0 保持违规，Fmax 115.474 MHz。
- 修订三码流 SHA256 `4095ed01d1b8c2d89aec808e06ebe846047089063cf7a67ff24a518d60aabed6`，User Code `0x000071A6`，已用 SRAM Program 写入。
- 确认 Dock 按键丝印 S0..S4 与引脚映射：S4 = B10 = RECONFIG_N，按下会导致 SRAM 码流丢失；真正的软复位应使用 S0/T10 或 S3/D7 在 RTL 内实现。
- 已打开 Gowin IDE 与独立 Gowin Programmer 图形界面，供直接点击烧录；建议改用 exFlash 操作把码流写入板载 SPI Flash。


## 2026-10-10 修订四更新

- UART 115200 控制接口可用：写 `F440` 设音高，写 `M0` 数字静音用于分离数字噪声与板级底噪。
- S3/D7 同步复位已实现；S0/T10 因是配置专用 SSPI 引脚无法使用，S4/B10 是 RECONFIG_N，不能当按键。
- 平滑滤波加强为 (1,4,6,4,1)/16，音频与 UART 输出驱动强度降到 4 mA。
- 资源：1259 LUT/ALU、429 寄存器、1 BSRAM、1.5 DSP；0 时序违规，Fmax 54.361 MHz。
- 修订四码流 SHA256 `a4188e1b90c84e904532644aca573608fb8eca1cb5e4d84e2f8ffb75dd463a34`，User Code `0x000064F6`。
- 外部硬件清单与版本规划见 `reference/planning/外部硬件清单与版本规划.md`。
- 待确认：`M0` 静音后啸叫是否仍然存在，用来判断噪声来自数字侧还是模拟侧。




## 2026-10-10 修订五更新

- 串口控制台 `tools/serial_console/serial_console.ps1` 可用，已在 COM13 上打开。若要连到 FPGA 的 UART，需要把底板 USB-JTAG&UART Type-C 接到电脑。
- 已确认 RTL 中不存在 0.25 秒周期成分，旧门控彻底移除；板内码流 User Code `0x000064F6`。
- 外设清单 Excel 与通俗版规划、TDM 外部复核意见均已加入 `reference/planning/`。
- 待确认：耳机里的虫鸣样底噪是否在按下 S3 保持复位（数字静音）后仍然存在。


## 2026-10-10 修订六更新

- 设计已写入板载外部 SPI Flash，掉电、重配置后都会自动加载（对照实验证据：重配置后 User Code 由 0x0000B32D 变为 0x000064F6）。现在可以放心换供电方式。
- 独立于 JTAG 的供电接口是底板 DC-IN 电源座 J13，输入 12 V，插头常见规格 5.5×2.1 mm，中心正极。USB Type-C 的 VBUS 也接在 +5 V 轨上，但用 USB 供电时电脑的地环路仍在。
- 按住 S3 时底噪依旧，已排除数字信号来源，后续只查供电与板级。
- 串口控制台改为用桌面 `打开串口控制台.cmd` 启动，窗口已正常显示。
