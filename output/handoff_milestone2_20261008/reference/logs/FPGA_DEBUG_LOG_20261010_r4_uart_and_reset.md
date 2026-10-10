# FPGA 电子乐器调试日志（2026-10-10 修订四：UART 调音、同步复位、啸叫排查）

## 一、高云烧录不成功

先看链路：命令行 `programmer_cli.exe --device GW2A-18C --operation_index 0` 能读到 `ID Code 0x0000081B`，电缆识别为 `Gowin USB Cable(FT2CH)`。这说明电缆、驱动、JTAG 链路和器件供电都是好的，图形界面失败不是硬件连接问题。

这块 Dock 的 USB-JTAG 口接的是板载 BL702，BL702 内部做 USB 转 JTAG，FPGA 侧的 TCK/TDI/TMS/TDO 是 D11、A11、B11、D10，全由 BL702 驱动。所以 JTAG 就是唯一正确的烧录接口，不存在"不该用 JTAG"这回事。

图形界面失败的可能原因按概率排：Cable 或 Device 没选到 `Gowin USB Cable(FT2CH)` / `GW2A-18C`；IDE 自带编程器和独立 Gowin Programmer 同时开着抢同一根电缆；用了带读回校验的 `Program and Verify`，而这台板子读回校验本来就会报 `0x00006020`，看起来像失败其实已经编程成功。

顺带发现：读器件时板子跑的 User Code 是 `0x0000E195`，不是上一版的 `0x000071A6`，说明中间发生过一次重配置并从 Flash 加载了别的码流，反过来印证了 S4 的行为。

## 二、高频啸叫

数字侧已经被证明干净：插值加 (1,4,6,4,1)/16 平滑后，相对理想正弦的带内误差是 -94.8 dBFS，最强带内杂散在 16.5 kHz 处只有 -111 dBc，远低于 16 位系统底噪。所以剩下的尖啸大概率不在数字链路里。

三个主要嫌疑：PT8211 到耳机功放之间被 1.5 MHz BCK 耦合；PC USB 供电带来的地环路噪声；耳机灵敏度过高或功放固定增益偏大。

本轮做了三件事：平滑滤波从 (1,2,1)/4 加强到 (1,4,6,4,1)/16；音频和 UART 输出的 DRIVE 从默认 8 mA 降到 4；新增 `M0` 命令把 DAC 数据强制为 0，用来分离数字内容和板级底噪。

判读方法：发 `M0` 之后如果啸叫依旧，它不是我们产生的数字信号，往供电和板级方向查；如果 `M0` 之后消失，说明还在数字侧。

## 三、复位按键

S4 接 B10 的 RECONFIG_N，语义是重新配置，按下就丢 SRAM 码流。S0 的网络名虽然是 `FPGA_~RST`，但 T10 在 GW2A-18PG256 封装里是保留给配置 SSPI 的专用脚，布局布线直接拒绝：`'key_s0' cannot be placed according to constraint, for the location is a dedicated pin (SSPI)`。

所以同步复位做在 S3/D7 上：D7 是普通 1.5 V 用户 IO，与 T3、T2 同组。实现是两拍同步器加 `rst = por | soft_rst` 复位树，耳机功放使能只跟上电复位，按键复位不会关功放也不会爆音。

## 四、UART 写频率

新增 `source/rtl/audio/uart_pitch.v`，115200 8N1，引脚 `uart_rx=N6`、`uart_tx=N7`（板载 BL702 的 USB-UART 桥，注意这两根与 RGB LCD 的 R3/R4 共用）。命令 `F<数字>` 设音高，`M0`/`M1` 静音与解除，收到合法命令回 `OK\r\n`。

频率换算封装成函数 `freq_to_phase_inc(f) = f * 91626`，对应 `fs = 46875 Hz`。常数与精确值 91625.937 的相对误差 6.9e-7，440 Hz 上折合 0.0012 音分。以后采样率换到 48 kHz 只需要把常数改成 89478。

## 五、构建与烧录

1261 LUT/ALU、429 寄存器、1 BSRAM、3 个 18×18 乘法器加 1 个 PADD18；0 建立违规、0 保持违规，Fmax 63.276 MHz。码流 SHA256 `7a409f4e3b38b0718d5a84c2c1f4a4b815ccab2b4d8982edeaf3298b23c2b3cc`，User Code `0x0000136B`，已用 SRAM Program 写入并读回确认。

## 六、待确认

- 发 `M0` 之后啸叫是否还在，据此判断噪声来源。
- 串口写 `F440`、`F523` 等命令是否能改变音高，是否收到 `OK`。
- 按 S3 是否只复位设计、不丢音、不产生爆音。
- 是否改用图形界面做一次 exFlash 写入，让设计在重配置和断电后仍然存在。
