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
- 构建结果：1261 LUT/ALU、429 寄存器、1 BSRAM、3 个 18×18 乘法器和 1 个 PADD18；0 建立违规、0 保持违规，Fmax 63.276 MHz。
- 修订四码流 SHA256 `7a409f4e3b38b0718d5a84c2c1f4a4b815ccab2b4d8982edeaf3298b23c2b3cc`，User Code `0x0000136B`，已用 SRAM Program 写入并读回确认。
- 排除了 S0/T10 作为用户 IO 的可能：布局布线报 `the location is a dedicated pin (SSPI)`。
- 新增 `docs/planning/外部硬件清单与版本规划.md`，整理外设清单、最终产物和 v0.5 到 v1.0 的版本规划。
