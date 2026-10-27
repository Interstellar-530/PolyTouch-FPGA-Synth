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


## 2026-10-10 修订十一更新

- UART 引脚由错误的 N6/N7 更正为 M11(TX)/T13(RX)，Bank 2 的 3.3 V 调试串口。
- 修正版码流 SHA256 `80089e293129be7f77c7ee32c630690f769eb4417e579392f83182b4b8e9357a`，User Code `0x000059D1`，已同时写入 SRAM 与外部 Flash，并经重配置对照实验验证。
- COM 口仍需 USB-JTAG 口上的 BL702 枚举成功后才会出现，与本次引脚纠错是两件独立的事。


## 2026-10-10 修订十二更新：四声部复音与测试曲

- 音频链路已从单声部扩为四声部复音：每声部独立的相位累加器、ADSR 与力度，四路求和后统一做饱和、平滑和主音量。
- 新增四声部分配器 `voice_alloc`，音符事件统一走 `{valid, on, note, velocity}` 总线，这就是将来 MPR121 触摸键盘的接入点；UART 已能通过同一总线实时触发音符。
- 内置测试曲《晚夜微雨问海棠》副歌，旋律加三个和弦音同时发声，共 146 个旋律事件（两遍副歌，59.26 秒），播完自动循环；转写依据、节奏表与和弦见 `SONG_WANYE_WEIYU.md`。
- S1 在和弦套 A 与 B 之间切换，S2 重播，S3 保持同步复位，N14 指示灯显示当前和弦套。
- 资源 4522 逻辑单元、772 寄存器、4 BSRAM、6 DSP；Fmax 37.409 MHz，无建立与保持违规。
- 码流 SHA256 `802305f7…`，User Code `0x00009EC7`，已写入 SRAM。外部 Flash 里仍是修订十一的基线码流，按 S4 或断电即可回到基线。
- 已用 Python 金模型渲染两套和弦的 WAV 并逐音符校验音高，41 个音全部通过；板上的实际听感还需要人耳确认。
- 待确认：四声部同时发声时耳机里是否干净、S1 切换和弦套是否有明显区别、底噪是否仍与单声部时一致。


## 2026-10-10 修订十三更新：速度、气口与力度

- 四分音符由 92 BPM 降到 66 BPM，每个音占 6 个节拍单位（约 682 毫秒），全曲约 36.8 秒。
- 旋律每个音提前两个节拍单位（约 227 毫秒）释放，音符之间有明显气口，发声时间占槽位七成半。
- 旋律 ROM 加入三位力度码：每句第一个音力度 127 作重音，其余 104，和弦统一 32，旋律与伴奏相差 8 到 10 dB。
- 资源 4526 逻辑单元、780 寄存器、4 BSRAM、6 DSP；Fmax 37.880 MHz，零时序违规。
- 码流 SHA256 `a37094e1…`，User Code `0x00007F46`，已写入 SRAM；外部 Flash 仍是修订十一基线。
- 金模型两套渲染峰值 -9.2 与 -8.2 dBFS，41 个音逐音校验通过，气口残留检查通过。
- 待确认：现在的速度与气口是否合适，旋律是否已经能从和弦里分辨出来。


## 2026-10-10 修订十四更新：按原谱划分节拍、现场调速档位

- 节拍单位改为十六分音符，每句时值按原谱重新划分，不再是每个音等长：我从山中来 2 2 2 2 6，带着兰花草 2 3 1 2 2，种在小院中 4 2 2 2 2，其余同型。
- 气口改为按音符长度取四分之一、最少一个单位，由播放器从发声长度算出，全曲发声占七成二。
- 新增 `tempo_sel`，把每个单位拉伸 1 到 4 倍；默认 2 倍（整曲 65 秒），按 S2 循环切换并自动重播，L14/L16 二进制显示档位。
- S1 仍切和弦套，S3 仍同步复位，N14 仍指示和弦套。
- 资源 4568 逻辑单元、784 寄存器、4 BSRAM、6 DSP；Fmax 36.441 MHz，无警告、零时序违规。
- 码流 SHA256 `c2a34937…`，User Code `0x000069DC`，已写入 SRAM；外部 Flash 仍是修订十一基线。
- 金模型按默认档渲染并逐音校验通过，A 套 -9.2 dBFS、B 套 -8.6 dBFS。
- 待确认：哪一个速度档位合适，以及板上实际速度是否与文档一致（可用 N16 每秒一闪核对）。


## 2026-10-10 修订十五更新：歌曲表改常量逻辑，N16 改为循环标记

- 混叠排查：采样率 46875 Hz、奈奎斯特 23.4 kHz，波表 512 点加线性插值，带内误差 -94.8 dBFS，混音后还有奈奎斯特零点的平滑滤波器，设计里没有混叠路径。
- 音序排查：状态机推演一圈 156 单位、41 音，循环点 0/156/312，没有提前回头；UART 与复位引脚都有上拉，不会悬空误触发。
- 把歌曲表从 `$readmemh` 数组改成 `tools/gen_song_rom.py` 生成的常量 `case` 函数（`rtl/audio/song_roms.vh`），彻底排除内部 RAM 初始化不完整的可能；三个 `.hex` 文件已删除。
- N16 从每秒心跳改为循环标记，每走完一圈闪约 110 毫秒，可用秒表量出实际循环长度。C13/A13 是 DONE/READY 专用引脚，不能用。
- 资源 4576 逻辑单元、786 寄存器、4 BSRAM、6 DSP；码流 SHA256 `2f4867cf…`，User Code `0x00009525`，已写入 SRAM。
- 待确认：N16 两次闪烁的实测秒数（标称 2 档 65 秒）。


## 2026-10-10 修订十六更新：定位并修复循环飞快的根因

- 安装 Icarus Verilog 并写了两个 RTL 仿真测试台，直接测硬件行为。
- `sample_tick` 实测 576 个 27 MHz 时钟一个周期，即 46875 Hz，音频接口与音高都没有问题，混叠可以排除。
- 根因：`tick_pulse` 由 `tick_cnt == tick_top` 直接产生，而 `tick_cnt` 只在 `sample_tick` 时更新，因此该信号是宽 576 个时钟的电平而非单周期脉冲；播放器按脉冲使用它，在一个节拍内把音符计数器连减数百次，旋律飞速跑圈。这也解释了前两轮降速无效的原因。
- 修复：`wire tick_pulse = sample_tick && (tick_cnt == tick_top);`
- 仿真复验：两圈间隔 3046992 个采样节拍，正好 65.0 秒；一圈 68 个音符事件（41 旋律 + 27 和弦）与设计一致。
- 资源 4588 逻辑单元、786 寄存器、4 BSRAM、6 DSP；码流 SHA256 `d295a316…`，User Code `0x0000EC2E`，已写入 SRAM。
- 待确认：板上听感与循环标记灯的间隔是否已与 65 秒标称值一致。


## 2026-10-10 修订十七更新：仿真门禁成为强制环节，节奏、和弦与音量优化

- 项目 `AGENTS.md` 写入"仿真与烧录门禁（强制）"：任何 Verilog 改动烧录前必须先过 RTL 仿真，`program_sram.ps1` 默认先跑门禁，未通过拒绝烧录。
- 门禁由 `sim/run_simulation.ps1` 执行，含三个自检测试台，整轮约 95 秒；测试台断言失败时用 `$fatal` 退出，返回非零。
- 门禁立刻抓到两个问题：`reset_cnt` 缺上电初值导致仿真里上电复位永不完成；我先前文档里的档位指示灯表写反了（灯亮表示该位为 1）。
- 现场认定的合适速度是 L14 亮、L16 灭，按真实逻辑是 2 倍档，已设为上电默认；档位表已改正。
- 节奏优化：每句统一 14 个十六分音符，按谱面区分四个八分音符、附点八分加十六分、四分音符起句三类句型。
- 和弦改为每句两个共 18 个；A 套走自然小调、力度 30，B 套走多利亚明亮色彩、力度 46，切换时音区与响度同时变化。
- 主音量由右移两位改为右移一位，提升约 6 分贝；金模型在默认 2 倍档峰值 A 套 -3.4 dBFS、B 套 -1.7 dBFS，各档位都在 -3 到 -2 dBFS 之间，未削波。
- 仿真：默认档一遍 3300908 个采样节拍（70.4 秒）、95 个开音（41 旋律 + 54 和弦），与设计一致。
- 资源 4573 逻辑单元、789 寄存器、4 BSRAM、6 DSP；码流 SHA256 `640c8924…`，User Code `0x00006DD1`，经门禁脚本写入 SRAM。
- 待确认：新节奏与和弦切换的听感，以及音量是否合适。

## 2026-10-24：外接 DAC 档已写 SRAM

已由 debug8（User Code 0x00003F62）切换到 standard27 / IdleOnly（0x0000BF87），只写 SRAM，未改 Flash。保留 COM13 原串口演奏，CH9350L 未到货；MCP3208 CH0=FSR、CH1=弯音，T7 不接。Quick 18/18、曲目专项 2/2、16 条串口命令 OK，PnR setup/hold 违例为零。最终 V50/I0/D1/M1，模拟输出和 ADC 实物效果待现场验收。完整记录见 docs/logs/FPGA_FLASH_20261024.md，归档 archive/FPGA-20261024-v0.2。


14:52 后续：用户仍反馈 CJMCU 耳机直插仅低频电噪声，VCC 未接、3.3V 孔供电，电源网络/焊桥未核实且无仪器。再次核对 User Code 0x0000BF87，改为手动持续正弦单音：M0 D0 X I0 T0 V50 N69 M1，全部 OK。新增独立生产包装器自检 2346 帧通过，非零 I2S、FSR、弯音及静音恢复均通过；实物无声原因仍待查。串口已释放，当前状态覆盖前述演示 D1。归档 545 文件 SHA256 核验通过，9 个本次临时目标已清理。


## 2026-10-24 15:10 重烧

按用户明确要求跳过本次门禁，复用同一 SHA256 位流，源码与收据一致。烧录前已回旧标识 0x00003F62，重写 SRAM 后独立读回 0x0000BF87，操作退出 0。串口 M0/X/V50/I0/T250/D1/M1 七条全部 OK，当前为50%音量的采样钢琴演示。用户仍反馈无声；排针已焊牢，需继续核实实物供电、模式脚、接线和线路输出负载。未写 Flash、无新增临时文件。证据 docs/evidence/FPGA-standard27-reflash-20261024-v0.1，归档 archive/FPGA-20261024-v0.3。


## 2026-10-24 15:32 FSR 改为消音

用户已反馈此前 CJMCU 音频恢复，随后要求将 FSR 改为延音或消音，本次选择按住消音、松开恢复，演示与手动均有效；旋钮弯音和原串口保留。新增阈值/滞回，沿用渐变静音，UART M0 与 FSR 合并且互不覆盖。新位流 SHA256 e9341aa47674ecf90bf677024830f4de7a771e3b56384240b9c32382cc062137，User Code 0x000063DC。四项定向测试、Quick 19 项通过，PnR setup/hold 违例均零；BSRAM27/46，乘法器未增加，Fmax44.227MHz。SRAM下载退出0且独立标识核对成功，未改Flash。COM13烧录后拒绝打开，未补做实际串口应答，未发送V50等预设；FSR实物按压效果待用户确认。归档archive/FPGA-20261024-v0.4，说明docs/releases/FPGA-FSR消音-20261024-v0.1.md。

## 2026-10-26 周末版本写入 Flash

用户明确要求将周末版本写 Flash 并跳过门禁。复用上述最终位流，核对 193 个归档构建输入及 SHA256 后，操作 37 完成外部 Flash 擦写校验，退出 0。操作 1 从 Flash 重载后延后读码为 0x000063DC / 0x00006020。没有重新构建或仿真，未改 RTL，未做彻底断电冷启动或串口、音频、CH9350L 实物验收。新归档 archive/FPGA-20261026-v0.1；记录 docs/logs/FPGA_FLASH_20261026.md。以后断电或 S4 重配置将加载本次 Flash 版本，替代此前 debug8。
