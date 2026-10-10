# Changelog

## 2026-10-08

- Checked the previous handoff package: 50 files matched their manifest
  SHA256 values.
- Fixed the `.gprj` existence check in `build_instrument.tcl`.
- Added and debugged the LED2 blink indicator on Orange_LED2, N16.
- Added a four-LED 27 MHz diagnostic and an internal-OSC diagnostic.
- Confirmed the 27 MHz clock restores after reseating the core board.
- Restored the normal single-voice DDS + ADSR + PT8211 design.
- Confirmed `SRAM Program`, operation 2, succeeds.
- Confirmed `SRAM Program and Verify`, operation 4, fails with verify error
  `0x00006020`; all future SRAM programming uses operation 2.
- Added `source/rtl/gao_top.rao` and integrated a GAO core.
- Generated `artifacts/ao_0.fs` with the GAO core.
- Diagnosed the standalone GAO launcher and jtagserver conflict.
- Added the 2026-10-08 debug log and PDF.
- Updated the board documentation set with datasheets, schematics, GAO manual,
  and Programmer manual.
- Updated global and project AGENTS.md, created the 2026-10-07 archive, and
  cleaned project temporary files.

## 2026-10-10
- Rebuilt the normal design without GAO; verified no GAO/OSC resources in the report.
- Added T3/T2 user-key tone switching: T3 -> C4 261.63 Hz, T2 -> C5 523.25 Hz, default A4 440 Hz.
- Reduced PT8211 output by >>>2, about -12 dB.
- Programmed SRAM with operation 2; User Code 0x00006AE4. Read Device Codes succeeds.
- Verified Gowin key executables and GAO IP core files are present.


## 2026-10-10 修订二：连续发声与 PT8211 位对齐

听众反馈两个问题：播放时背景噪声大，以及不切换按键时会出现 0.25 秒通断的警报式嗡鸣。两处根因都已经定位并修改。

- `source/rtl/top.v`：删掉 0.25 秒通断门控和 `gate_cnt`。复位释放后 `gate` 恒为高，ADSR 走完起音、衰减后停在延音电平并一直保持；按键只改变 DDS 的频率控制字，不再周期性静音。
- `source/rtl/audio/pt8211_tx.v`：按 Sipeed/Gowin 官方 `TangPrimer-20K-example/PT8211/src/pt8211_drive.v` 重写帧结构和 WS 相位。帧计数 `b_cnt` 走 0..31，`b_cnt` 为 0 和 16 时请求新字，WS 在 `b_cnt` 3 拉低、19 拉高。原来的 15/31 翻转比 DAC 期望的相位晚一个位，DAC 会按错位的符号位重组字，听感上就是叠加在音调上的严重失真。
- 新模块的 DIN/WS 在 BCK 下降沿更新，DAC 仍在上升沿采样，位流序列与官方一致，建立时间从几乎为零增加到约半个 BCK 周期。
- 用 Python 时序模型分别仿真官方驱动和新模块，两者 DAC 可见的 (WS, DIN) 序列逐点相同。
- 重新构建结果：331 LUT/ALU/ROM16、188 寄存器、1 块 BSRAM、1 个 18×18 乘法器；0 个建立违规端点、0 个保持违规端点，实际 Fmax 113.169 MHz，约束 27 MHz。构建日志不再出现 `wave_sine.hex` 找不到的警告，工程里没有 GAO 核。
- 新码流 SHA256 `0612d3383736688423204cd2a04ad2350a110d9c7c7e3f483008a6ddb2faa399`，User Code `0x00009F8A`，已用 `SRAM Program`（操作 2）写入。


## 2026-10-10 修订三：插值降噪、按键与复位说明

### 背景噪声

听众反馈耳机里除了音调之外还有一层闪烁的噪声。先排除波表本身的问题：把 `wave_sine.hex` 的 512 个值与理想正弦逐点比对，最大误差为 0，表是干净的。所以噪声来自相位截断，也就是只用 `phase[31:23]` 查表带来的阶梯误差，它的谐波一直延伸到几百千赫兹，超过 23.4 kHz 的部分折回可听频段。

- `source/rtl/audio/dds_osc.v`：加入线性插值。`phase[31:23]` 选表项，`phase[22:14]` 作为 9 位小数在相邻两项之间插值，用一次 17×9 乘法完成。插值把一阶阶梯误差变成二阶误差，误差均方根从 164 个码值降到 0.6 个码值。
- `source/rtl/top.v`：在音量控制前加两级两抽头平均，等效 (1,2,1)/4 低通。在 46.875 kHz 采样率下 440 Hz 处基本无衰减，8.5 kHz 附近 -3 dB，15 kHz 约 -11 dB，Nyquist 处有零点。
- `source/rtl/top.v`：音量右移改为先加四舍五入再移位，去掉截断带来的信号相关直流台阶。
- 频谱模型对比：带内误差从 -46.0 dBFS（-43.0 dBc）降到 -94.8 dBFS（-91.9 dBc），改善 48.8 dB；最强的带内杂散从 9.5 kHz 的 -57 dBc 降到 -111 dBc。

### 按键与复位

从 Dock 3714 原理图和核心板 SOM 原理图逐网络追踪，再用 Sipeed wiki 的开箱指南和相关图片交叉确认，五个按键的真实连接是：

| 丝印 | 原理图网络 | FPGA 引脚 | 作用 |
| --- | --- | --- | --- |
| S0 | Silicone Key_0 / `T10_IOR35B_FPGA_~RST` | T10 | 普通 IO，被官方固件当作复位输入 |
| S1 | Silicone Key_1 / `T3_IOB52B_1V5` | T3 | 普通 IO（当前工程用作 C4） |
| S2 | Silicone Key_2 / `T2_IOB48B_1V5` | T2 | 普通 IO（当前工程用作 C5） |
| S3 | Silicone Key_3 / `D7_IOL53B_1V5` | D7 | 普通 IO |
| S4 | Silicone Key_4 / `B10_IOR31B_~{RECFG}` | B10 | **RECONFIG_N，按下即触发 FPGA 重新配置** |

所以 S4 不是软件复位键，它接的是 GW2A 的专用重配置引脚。按下后 FPGA 从配置源重新加载，JTAG 写进 SRAM 的码流被丢弃，于是程序失效。要真正复位自己的设计，应该用 S0 或 S3 这类普通 IO 在 RTL 里做一个同步复位；要让程序在重配置和断电后仍然存在，需要把码流写进板载外部 SPI Flash（编程器里的 exFlash 操作），而不是只写 SRAM。


## 2026-10-10 修订四：UART 写频率、S3 同步复位、啸叫排查

- 新增 `source/rtl/audio/uart_pitch.v`：115200 8N1 的 UART 控制接口，`F<数字>` 直接设定音高，`M0`/`M1` 数字静音/解除。频率到相位增量的换算封装为 `freq_to_phase_inc()` 函数，常数取 `f * 91626`，与精确值 91625.937 的相对误差 6.9e-7。收到合法命令回 `OK\r\n`，非法回 `ERR\r\n`。
- `source/rtl/top.v` 改成单一 `phase_inc` 寄存器，S1、S2 预置音和 UART 三个来源后写覆盖，复用原有去抖逻辑。
- 平滑滤波从 (1,2,1)/4 加强为 (1,4,6,4,1)/16，在 8 kHz 处约 -5 dB、15 kHz 约 -22 dB、20 kHz 约 -26 dB，Nyquist 处有零点。
- 新增 S3/D7 上的同步复位：两拍同步器加复位树，耳机功放使能只跟随上电复位，按键复位不关功放也不产生爆音。
- `source/constraints/primer20k_dock3714.cst` 新增 `key_rst`(D7)、`uart_rx`(N6)、`uart_tx`(N7)，并把音频与 UART 输出的 `DRIVE` 从默认 8 mA 降到 4，降低 BCK 向模拟通路的耦合。
- 构建结果：1259 LUT/ALU、429 寄存器、1 BSRAM、3 个 18×18 乘法器和 1 个 PADD18；0 建立违规、0 保持违规，Fmax 54.361 MHz。
- 修订四码流 SHA256 `a4188e1b90c84e904532644aca573608fb8eca1cb5e4d84e2f8ffb75dd463a34`，User Code `0x000064F6`，已用 SRAM Program 写入并读回确认。
- 排除了 S0/T10 作为用户 IO 的可能：布局布线报 `the location is a dedicated pin (SSPI)`。
- 新增 `docs/planning/外部硬件清单与版本规划.md`，整理外设清单、最终产物和 v0.5 到 v1.0 的版本规划。



首轮构建后发现 FIR 系数写成 (1,2,6,2,1)，与设计的 (1,4,6,4,1) 不符，把 (v1 + v3) <<< 1 改成 <<< 2 后重新构建、烧录。以上资源、Fmax、哈希、User Code 均为修正后的最终值。



## 2026-10-10 修订五：串口平台、0.25 秒底噪核查、外设清单与 TDM 复核

- 新增 `tools/serial_console/serial_console.ps1`：基于 System.IO.Ports + WinForms 的串口控制台，免安装，带端口选择、波特率、收发记录、日志文件，以及 F440/F262/F523/M0/M1 快捷按钮。注意 PowerShell 5.1 以 ANSI 读取无 BOM 的 .ps1，中文字符串会损坏，脚本必须存成带 UTF-8 BOM。
- 串口排查结论：本机可用串口只有 COM13，属于 Gowin FT2CH 下载器的 FT2232 第二通道，实测发给它 `F440` 收不到 FPGA 的应答。FPGA 的 UART 走 N6/N7 接板载 BL702，因此要把底板的 USB-JTAG&UART Type-C 接到电脑才会出现新的 COM 口。其余 COM3/4/6/7/8/9 是蓝牙虚拟串口。
- 0.25 秒底噪核查：枚举 RTL 里全部计数器与比较常量，只有 `reset_cnt`（16 位，一次性 2.43 ms）、`db_s1_cnt`/`db_s2_cnt`（20 位，按住键时 38.8 ms）、`blink_cnt`（计数到 13,499,999，即 0.5 秒翻转，LED 1 Hz）以及 PT8211 与 UART 的小计数器。没有任何 0.25 秒周期的成分（那需要 6,750,000 个计数），旧的 0.25 秒通断门控确实已经删除。板内当前码流 User Code `0x000064F6`，确认跑的就是修订四版本。
- 新增 `docs/planning/项目整体进展与规划-通俗版.md`：用整体语言描述项目目标、当前进度、已解决的问题、后续顺序、需要的硬件和风险。
- 新增 `docs/planning/外设采购清单-20261010.xlsx`：三个工作表，分别是"待采购清单"（只列仍需购买或实验室借用的设备，22 项，含优先级与参考价格）、"已划去-板上已含"（15 项板上已有外设）、"说明"。
- 新增 `docs/planning/时分复用方案外部复核意见.md`：把 TDM 方案交给另一个模型独立评审，结论是方向可行但需要修正四处；同时修正了资源口径——综合报告 `DSP 1.5/24` 配 `MULT18X18 3` 说明一块 DSP 含两个乘法器，器件实际是 24 块 DSP、48 个 18×18 乘法器。
- 建议的推进顺序改为：先做 4 声部直连保底，再实现参数化的 TDM 引擎并用 N=4/8 验证调度，最后扩到 32。


## 2026-10-10 修订六：码流写入外部 Flash、电源接口确认、底噪来源收窄

- 把 `artifacts/instrument.fs` 用 `exFlash Erase,Program,Verify`（操作 9）写入板载外部 SPI Flash。工具在 Verify 阶段报 `SPI Verify failed`，和 SRAM 读回校验失败是同一类限制（状态码 0x00006020），不代表写入失败。
- 用对照法证明写入成功：先把另一个码流（`ao_0.fs`，User Code 0x0000B32D）写进 SRAM 并读回确认，再触发一次重配置（操作 1 Reprogram），重配置后器件报告的 User Code 变成 0x000064F6，也就是只存在于刚写进 Flash 的那个码流。结论是 Flash 已正确保存设计，且上电与按 S4 重配置时都会自动从 Flash 加载。
- 电源接口确认：底板有一个 **DC-IN 电源座 J13（型号 DC-036A-2.5A-2.0）**，输入网络标为 **+12 V**，经 U16（EUP3458VIR1）降压到 **+5 V**。原理图同时显示 USB Type-C 的 VBUS 直接接到 +5 V 轨，所以 USB 口也能给板子供电。要用独立电源验证地环路，最彻底的方式是拔掉 JTAG/USB 线，只用 DC-IN 供电。
- 底噪定位：用户实测按住 S3 保持同步复位（DAC 数据被强制为 0，等价于 UART 的 M0）时虫鸣样底噪依然存在，**说明它不来自我们产生的数字信号**，后续只需往供电、地环路、板级耦合和耳机功放方向排查，数字侧不必再改。
- 串口控制台窗口没出现的原因找到并修复：用 `Start-Process -WindowStyle Hidden` 启动 GUI 时，`SW_HIDE` 会被子进程继承，WinForms 窗体被创建成隐藏窗口。改成通过桌面的 `打开串口控制台.cmd` 启动，窗口正常显示（句柄 264628，标题 PolyTouch 串口控制台）。


## 2026-10-10 修订十一：UART 引脚纠错（根因）

之前串口一直收不到 FPGA 应答，根因是**引脚用错了**，而且是我读原理图时读错的。

底板原理图第 1 页里，FPGA 到 BL702 的串口是这两根：

| FPGA 球号 | 网络名 | 方向 | 连接对象 |
| --- | --- | --- | --- |
| M11（2/IOR27B） | `M11_IOR27B_FPGA_TXO` | FPGA 发 | BL702_UART1_RX |
| T13（2/IOR8B） | `T13_IOR8B_FPGA_RXO` | FPGA 收 | BL702_UART1_TX |

这两根都属于 **Bank 2**，而底板原理图明确写着 "BANK2 VOLTAGE is locked to 3V3 (JTAG IO)"，所以用 LVCMOS33 正确。

而我先前误判的 N6 / N7 其实是 **RGB_LCD_R4 与 RGB_LCD_R3**，是液晶接口的信号，跟调试串口无关。错误来源是 SODIMM 引脚表非常密集，我用按行取词的脚本提取时把相邻两列的标签混到了一行里；这次把原理图放大到 8 倍渲染，直接看到 SOM 球号与 BL702 网络之间的连线，才确认了正确映射。

改动与验证：

- `source/constraints/primer20k_dock3714.cst`：`uart_tx` 改为 M11，`uart_rx` 改为 T13，并加注释说明不要和 N6/N7 混淆。
- 重新构建：1259 LUT/ALU、429 寄存器、1 BSRAM、3 个 18×18 乘法器加 1 个 PADD18；0 建立违规、0 保持违规，Fmax 54.361 MHz。引脚报告确认 `uart_tx` 落在 M11/2、`uart_rx` 落在 T13/2。
- 码流 SHA256 `80089e293129be7f77c7ee32c630690f769eb4417e579392f83182b4b8e9357a`，User Code `0x000059D1`，已写入 SRAM，并用外部 Flash 操作写入掉电保存区。
- 写入验证沿用对照法：先把另一个码流（User Code 0x0000B32D）写进 SRAM 并读回确认，再触发重配置，重配置后读到的 User Code 变成 0x000059D1，说明 Flash 里确实已经是修正版。

要说明的一点：这次纠错解决的是"FPGA 收不到、也不回话"的问题，**它不会让电脑凭空出现一个 COM 口**。COM 口仍然必须由底板 USB-JTAG 口上的 BL702 枚举出来；两件事是独立的。


## 2026-10-10 修订十二：四声部复音、内置测试曲与和弦切换

这一版把单声部链路扩成四声部复音，并加入一首内置测试曲，用来验证复音、混音和按键。音频通路没有引入任何软核或外设，全部是 RTL。

### 新增模块

| 文件 | 作用 |
| --- | --- |
| `rtl/audio/note_phase_inc.v` | MIDI 音号到 32 位相位增量。只存一个半音八度的 12 个常量，其余音高左移八度号得到 |
| `rtl/audio/poly_voice.v` | 一个完整声部：插值 DDS 加 ADSR 加力度，取代原来的 `voice.v` |
| `rtl/audio/event_fifo.v` | 16 深 16 宽的音符事件 FIFO，用分布式逻辑，不占 BSRAM |
| `rtl/audio/voice_alloc.v` | 四声部分配器，就是将来触摸键盘接入的那一层接口 |
| `rtl/audio/song_player.v` | 测试曲播放器，旋律 ROM 加两套和弦 ROM |
| `rtl/audio/mixer.v` | 四路求和、主音量、饱和、平滑 |
| `rtl/audio/uart_ctrl.v` | UART 音符控制，取代原来的 `uart_pitch.v` |

`voice.v` 与 `uart_pitch.v` 已经删除，功能分别由 `poly_voice.v` 和 `uart_ctrl.v` 承担。

### 音符事件接口

所有音符来源都汇到一条事件总线上，事件字是 `{on, note[6:0], velocity[7:0]}`。目前有两个来源：内置播放器写进事件 FIFO，UART 控制器直接给出事件，UART 优先。将来的 MPR121 触摸控制器只要驱动同样的 `{valid, on, note, velocity}` 信号接到 `voice_alloc` 的入口即可，下游一行都不用改。这条接口现在就能用串口验证：`N<音号>` 按键、`O<音号>` 松键、`X` 全松、`M0`/`M1` 静音。

### 混音顺序

第一版把主音量放在饱和之后，四个声部相加立刻超过满量程，金模型渲染出来的峰值正好卡在 8192（-12 dBFS），也就是被削平了。改成先求和、再乘主音量、最后饱和，四路满量程相加后右移两位刚好落回 16 位范围。旋律力度 96、和弦力度 56，金模型峰值 -8.2 dBFS，不削波。

### 按键

| 丝印 | 引脚 | 作用 |
| --- | --- | --- |
| S1 | T3 | 在和弦套 A 与 B 之间切换，N14 指示灯同步亮灭 |
| S2 | T2 | 测试曲从头重播 |
| S3 | D7 | 设计同步复位，不变 |
| S4 | B10 | RECONFIG_N，仍然不能用 |

### 构建结果

- 资源：4522 逻辑单元、772 寄存器、4 块 BSRAM、6 个 DSP（即 12 个 18×18 乘法器）。
- 时序：约束 27 MHz，实际 Fmax 37.409 MHz，0 个建立违规端点、0 个保持违规端点，TNS 为 0。
- 码流 SHA256 `802305f7e5656c90594e1f09e5239094b3a8551d6c7807105573f7d0d8d844c2`，User Code `0x00009EC7`，已用 SRAM Program（操作 2）写入。
- 上一版基线码流 SHA256 `80089e29…`、User Code `0x000059D1` 保留在 `artifacts/instrument.fs`，按 S4 重配置或断电即可回到基线。

### 验证

- Python 金模型按 RTL 逐模块等价重写，渲染出 `artifacts/lanhuacao_chordA.wav` 与 `lanhuacao_chordB.wav` 供试听。
- `verify_preview.py` 用 Goertzel 在每个旋律音窗口内比较期望频率与邻近半音，41 个音全部通过。
- 两套和弦渲染的 RMS 差异 118%，确认切换确实换掉了伴奏。
- 硬件侧只做了烧录与器件回读，听感需要人耳确认。


## 2026-10-10 修订十三：放慢速度、加入气口、拉开旋律与伴奏的力度

试听后反馈三条：整体太快、复音响度一致听不出旋律、音符之间没有间隔。这三条都改在曲谱数据与播放器上，音频链路结构没动。

### 速度

四分音符从 92 BPM 降到 66 BPM，一个节拍单位从 3821 个采样点变成 5327 个，也就是 114 毫秒。每个音占的槽从 4 个节拍单位加长到 6 个，句尾长音从 16 个加长到 12 个但绝对时间更长。全曲从 23.5 秒变成 36.8 秒。

### 气口

旋律每个音的槽比发声时间长两个节拍单位，播放器提前两拍释放这个音，于是每个音后面有约 227 毫秒的气口。旋律的实际发声时间占槽位七成半，听上去是一个一个断开的音，而不是连成一片。和弦保持延音铺底，旋律的气口里只剩伴奏，反差更明显。

### 强弱

旋律 ROM 的每一项从 16 位的音高加时长改成三位力度码加七位音高加六位槽长，播放器用一张八项力度表把它还原成 0 到 127 的力度。每句的第一个音用 127 作重音，其余旋律音 104，和弦压到 32，旋律与伴奏差 8 到 10 dB。

### 构建结果

- 资源：4526 逻辑单元、780 寄存器、4 块 BSRAM、6 个 DSP。
- 时序：约束 27 MHz，实际 Fmax 37.880 MHz，零建立与保持违规。
- 码流 SHA256 `a37094e1238a9f2c313bfbb4021ab1924dcd52f7c5afefe8334ec7fc32c4fe96`，User Code `0x00007F46`，已写入 SRAM。
- 外部 Flash 里仍是修订十一的基线，按 S4 或断电可以回到基线。

### 验证

- 金模型重新渲染两套和弦，峰值 -9.2 与 -8.2 dBFS，没有削波。
- 41 个旋律音逐个比对音高全部通过；同一批音的力度检查同时确认气口处该音的残留低于发声段的 35%，也就是音符确实断开了。


## 2026-10-10 修订十四：按原谱重新划分节拍，并加入现场调速档位

反馈两条：曲谱的节拍划分不对；板上听感仍然偏快。

### 节拍划分

前两版把每个旋律音都设成相同的时值，这是不能接受的简化。现在按原谱最小音值重新划分，一个单位取十六分音符，四个单位为一拍，每句的时值不再是均匀的：

| 句 | 歌词 | 音级 | 时值（十六分音符） |
| --- | --- | --- | --- |
| 1 | 我从山中来 | 6 3 3 3 3 | 2 2 2 2 6 |
| 2 | 带着兰花草 | 2 1 2 1 7 | 2 3 1 2 2 |
| 3 | 种在小院中 | 6 6 6 6 6 | 4 2 2 2 2 |
| 4 | 希望花开早 | 5 3 5 5 #4 | 2 2 2 2 6 |
| 5 | 一日看三回 | 3 6 6 5 3 | 2 2 2 2 6 |
| 6 | 看得花时过 | 2 1 2 1 7 | 2 3 1 2 2 |
| 7 | 兰花却依然 | 6 3 3 1 1 | 2 3 1 2 2 |
| 8 | 苞也无一个 | 7 6 3 2 1 | 4 2 2 2 2 |
| 9 | 尾声 | 6 | 16 |

对应的做法是：原谱的"6 3 3 3 | 3. 2"读成四个八分音符加一个附点四分音符，"1. 2 1 7"那一类读成附点八分加十六分，"6 - | 6 6 6 6"读成四分音符起句。

### 气口

每个音后面的静音改为按音符自身长度计算，取四分之一，最少一个单位，由播放器从 ROM 里的发声长度直接算出来，不再是一个固定值。这样十六分音符也听得见，长音也不会被切得太短。

### 现场调速

播放器的时基加了 `tempo_sel`，把每个单位拉伸 1 到 4 倍。默认 2 倍（比原谱慢一倍，整曲 65 秒），按 S2 循环切换，切一次曲子从头重播，L14/L16 用二进制显示档位。S1 仍然切和弦套，S3 仍然同步复位。这样调整速度不需要重新构建和烧录。

### 构建结果

- 资源：4568 逻辑单元、784 寄存器、4 块 BSRAM、6 个 DSP。
- 时序：约束 27 MHz，实际 Fmax 36.441 MHz，无警告、零时序违规。
- 码流 SHA256 `c2a349375877bfb5a6a487bcd7745612b83eaf07416738d18264957955b9869a`，User Code `0x000069DC`，已写入 SRAM。

### 验证

- 金模型按默认 2 倍档渲染两套和弦：A 套峰值 -9.2 dBFS，B 套 -8.6 dBFS，无削波。
- 41 个旋律音的音高与气口残留检查全部通过。
- 需要人耳确认的是速度和档位；如果板上速度仍与文档差得远，用 N16 指示灯的每秒一闪来核对 27 MHz 时钟。


## 2026-10-10 修订十五：排查"播一小段就重复"，歌曲表改为常量逻辑

反馈现象：曲子播放一小段后就开始重复，并怀疑音频接口波形发生混叠。

### 混叠排查结论

设计里不存在混叠路径。采样率是 46875 Hz，奈奎斯特上限 23.4 kHz；波表只有 512 点，代表一个完整周期，用九位小数做线性插值，一阶阶梯误差被降成二阶，早前实测带内误差是 -94.8 dBFS；混音后还有一级 (1,4,6,4,1)/16 平滑，它在奈奎斯特处正好是零点。旋律最高音约 700 Hz，能量集中在基频，离奈奎斯特还有三十多倍余量。所以"重复"不是混叠造成的，而是音序或时间基准的问题。

### 音序排查

逐项核对：播放器状态机按当前参数推演，一圈是 156 个十六分音符单位、41 个旋律音，循环三次的时间点是 0、156、312 单位，没有提前回头；歌曲表内容与 Python 模型逐项一致；UART 接收脚有上拉，悬空不会产生随机字节触发全停音；S3 复位脚也有上拉。也就是说逻辑层面找不到提前重复的原因。

不过综合报告显示歌曲表被推断成了内部 RAM，而初始化数据是否被完整装载无法从报告确认。如果只装载了一部分，后面的表项会读成 0，旋律会在几句之后变成跳着走，听感正是"播一小段就重复"。

### 改动

歌曲表不再用 `$readmemh` 数组，改由 `tools/gen_song_rom.py` 生成 `rtl/audio/song_roms.vh`，内容是三个常量 `case` 函数，由 `song_player.v` 在模块内 `include`。表本身很小（41 项与 9 项），用组合逻辑实现完全不依赖综合器如何映射存储器，也就不存在初始化不完整这一风险。原来的三个 `.hex` 文件已经删除。

同时把 N16 指示灯从每秒一闪的心跳改成**循环标记**：每走完一圈曲子闪一次，约 110 毫秒。这样"重复得太早"可以直接用秒表量出来，而不必靠描述。循环长度的标称值是 1 档 32.5 秒、2 档 65 秒、3 档 97.5 秒、4 档 130 秒。

C13 是 DONE 专用引脚、A13 是 READY 专用引脚，都不能当用户 IO，所以没有新增指示灯，而是把 N16 的心跳功能合并进循环标记。

### 构建结果

- 资源：4576 逻辑单元、786 寄存器、4 块 BSRAM、6 个 DSP。
- 时序：约束 27 MHz，实际 Fmax 工作正常，无警告、零时序违规。
- 码流 SHA256 `2f4867cf52d2f66603fc54b72517f23a2c0e0467685d384956d5496fdba174ce`，User Code `0x00009525`，已写入 SRAM。

### 需要你做的测量

记一下 N16 两次闪烁之间的秒数。如果约 65 秒，说明音序和时间基准都正确，之前听到的"重复"来自曲子本身的反复（原谱里"带着兰花草"和"看得花时过"旋律完全相同，和弦套 A 的前四句也是 Gm–Cm–Gm–F 重复一次）；如果明显短于标称值，把实测秒数告诉我，我按比例修正。
