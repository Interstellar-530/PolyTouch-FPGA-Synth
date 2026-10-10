# Hardware Notes

## Board

- Sipeed Tang Primer 20K core board.
- Dock 3714 full-function board.
- FPGA: `GW2A-LV18PG256C8/I7`, device version C.

## Confirmed Debug Pins

| Signal | Pin |
| --- | --- |
| 27 MHz clock | H11 |
| PT8211 BCK | N15 |
| PT8211 WS | P16 |
| PT8211 DIN | P15 |
| Headphone amplifier enable | R16 |
| Orange_LED0 | C13 |
| Orange_LED1 | A13 |
| Orange_LED2 | N16 |
| Orange_LED3 | N14 |
| Orange_LED4 | L14 |
| Orange_LED5 | L16 |

User LEDs are active-low. The FPGA pin is the cathode, the LED anode is tied to
3.3 V through a 510 ohm resistor. Orange_LED2, N16, is the normal blink
indicator.

## 27 MHz Clock

The core board contains a 27 MHz oscillator U10. Its EN pin is tied to +3V3,
and its output goes through R20 22 ohm to H11. The original no-blink problem was
caused by the core board not being fully seated. After reseating the core board,
the 27 MHz four-LED diagnostic blinked normally.

## Debug Audio Path

- On-board PT8211-S.
- On-board LPA4809MSF headphone amplifier.
- 3.5 mm headphone jack.

## Still Unresolved

- Whether Dock 3714 PMOD exposes a free 3.3 V GCLK pin for 12.288 MHz.
- MPR121 module I2C pull-up configuration.
- PCM5102A module FMT/FLT/DEMP/XSMT jumper configuration.
- Dock switch/power-mode behavior and exact Key/SW mapping.
- Whether the team has confirmed Primer 20K eligibility with the organizer.
- Gowin IDE direct synthesis path for `rtl/audio/wave_sine.hex`.

## Do Not Do

- Do not connect 3.3 V peripherals directly to a 1.5 V DDR3 bank.
- Do not treat PT8211 as the final I2S proof.
- Do not use BL702 as an audio controller.
- Do not use `SRAM Program and Verify`; use `SRAM Program`.
- Do not power-cycle after SRAM programming while testing.

## 2026-10-10 Key and Volume Update
- S0/T10 is the FPGA reset key and is not used for tone switching.
- key_s1 is T3, 1.5 V active-low, selects C4 261.63 Hz.
- key_s2 is T2, 1.5 V active-low, selects C5 523.25 Hz.
- Default tone remains A4 440 Hz.
- PT8211 sample level is shifted right by 2 for about -12 dB attenuation.


## 2026-10-10 按键丝印与引脚映射（Dock 3714）

| 丝印 | 原理图网络 | FPGA 引脚 | 作用 |
| --- | --- | --- | --- |
| S0 | `T10_IOR35B_FPGA_~RST` | T10 | 普通 IO，官方固件把它当复位输入 |
| S1 | `T3_IOB52B_1V5` | T3 | 普通 IO，当前用作 C4 261.63 Hz |
| S2 | `T2_IOB48B_1V5` | T2 | 普通 IO，当前用作 C5 523.25 Hz |
| S3 | `D7_IOL53B_1V5` | D7 | 普通 IO，空闲 |
| S4 | `B10_IOR31B_~{RECFG}` | B10 | RECONFIG_N，按下触发 FPGA 重新配置 |

依据：Dock 3714 原理图 `P007_Things` 页五个 Silicone Key 的走线；核心板 SOM 原理图里 `B10 = IOR31B/RECONIG_N`、`T10 = IOR35B/D2`；以及 Sipeed 开箱指南中"S0 复位屏幕/摄像头/HDMI"的描述和底板照片上的 S0..S4 丝印。

注意：S4 触发的是硬件重配置，JTAG 写进 SRAM 的码流会立即丢失；只有把码流写进板载外部 SPI Flash，重配置或断电后设计才会自动恢复。


丝印证据：\eference/board_docs/dock3714_key_silkscreen.png\ 是从 Sipeed 官方底板照片裁出的左侧按键区域，可以清楚读到 S0、S1、S2、S3、S4 五个标号。



## 2026-10-10 引脚与接口补充（修订四）

| 信号 | 引脚 | 说明 |
| --- | --- | --- |
| key_rst | D7 | S3 按键，1.5 V Bank，同步复位输入 |
| uart_rx | N6 | BL702_UART1_TX 进 FPGA，与 RGB LCD 的 R3 共用 |
| uart_tx | N7 | FPGA 送 BL702_UART1_RX，与 RGB LCD 的 R4 共用 |
| key_s0 | T10 | 不可用：GW2A-18PG256 保留给配置 SSPI |

音频与 UART 输出统一设成 DRIVE=4（高云 CST 里 DRIVE 的单位是 mA，写成 `DRIVE=4`，不能写 `4MA`，多个属性之间用空格分隔不能用逗号）。


## 2026-10-10 串口与自检补充（修订五）

本机串口只有 COM13 是真实可用端口（Gowin FT2CH 下载器的 FT2232 第二通道），COM3/4/6/7/8/9 都是蓝牙虚拟串口，试开时会超时。

FPGA 的 UART 在 N6/N7 上接到板载 BL702，所以要让电脑能对 FPGA 讲话，必须使用底板的 USB-JTAG&UART Type-C 口。当前只接了下载器，因此 COM13 收不到 FPGA 的应答。

零成本的底噪自检方法：按住 S3 不放。S3 是同步复位输入，按住时 DAC 数据被强制为 0（功放仍然使能），等价于 UART 的 `M0` 命令。若按住 S3 期间虫鸣样底噪依然存在，它就不来自我们产生的数字信号，应往供电、地环路、板级耦合或耳机功放方向排查。


## 2026-10-10 电源输入与码流保存（修订六）

底板有两种供电方式。

| 供电方式 | 接口 | 电压 | 是否与电脑隔离 |
| --- | --- | --- | --- |
| DC-IN 电源座 J13（型号 DC-036A-2.5A-2.0） | 圆形电源插头，常见规格 5.5×2.1 mm，中心正极 | 12 V，经 U16 EUP3458VIR1 降到 +5 V | 是，与 USB/JTAG 完全无关 |
| USB Type-C | 任一 Type-C 口 | 5 V（VBUS 直接接 +5 V 轨） | 否，只要同时连着电脑就仍有地环路 |

要在换电源后做干净的底噪对比，推荐同时做到两件事：拔掉下载器与所有 USB 线，只用 DC-IN 座供 12 V。因为设计已经写进 Flash，不接 JTAG 也能正常启动。

码流保存方式对比：

| 写入位置 | 命令/操作 | 掉电后是否保留 |
| --- | --- | --- |
| FPGA 内部 SRAM | SRAM Program（操作 2） | 不保留 |
| 板载外部 SPI Flash | exFlash Erase,Program,Verify（操作 9） | 保留，上电与按 S4 重配置都会从 Flash 加载 |

判定 Flash 是否真的写进去的办法：先用操作 2 把另一个 User Code 的码流写进 SRAM，再用操作 1 Reprogram 触发重配置，然后读器件码。若读到的 User Code 变回 Flash 里那个，就说明重配置确实从 Flash 取码流。


## 2026-10-10 当前串口与快捷方式状态（修订七）

复查串口：本机可用端口仍然只有 COM13（Gowin FT2CH 下载器的 FT2232 第二通道），COM3/4/6/7/8/9 全部是蓝牙虚拟串口。设备列表里依然没有出现 BL702 的 USB 设备，说明底板的 USB-JTAG&UART Type-C 还没有接到电脑。结论：现在板子与电脑之间只有下载器的 JTAG 通道在工作，COM13 虽然是真实串口，但它不通到 FPGA 的 UART（实测发 `F440` 无应答）。要让电脑对 FPGA 讲话，必须插上底板的 USB-JTAG&UART Type-C。

桌面新增快捷方式 `串口控制台.lnk`，指向 `tools/serial_console/open_console.cmd`，后者再调用 `serial_console.ps1`。原先桌面上临时的 `.cmd` 启动器已删除，只保留这一个快捷方式。快捷方式实测可以正常拉起控制台窗口。

同时新增 `tools/serial_console/install_desktop_shortcut.ps1`，用于在任何一台机器上重建这个桌面快捷方式。

再次提醒：启动串口控制台时不要使用 `-WindowStyle Hidden`，`SW_HIDE` 会被子进程继承，WinForms 窗口会被建成隐藏窗口，看起来就是"程序没打开"。


## 2026-10-10 更换连接方式后的复查（修订八）

重新枚举的结果：

- 串口列表只剩 COM3、COM4、COM6、COM7、COM8、COM9，全部是蓝牙虚拟串口。
- 原来的 COM13 以及它背后的 FTDI 设备（`VID_0403&PID_6010`）已经从 USB 总线上消失。
- 没有出现任何新的 USB 设备，也没有驱动异常的未知设备。
- `programmer_cli --scan-cables F` 已经扫不到任何下载电缆，读器件码也不再返回 ID。

结论：**开发板目前与电脑之间没有任何连接**，既没有 JTAG 也没有串口，因此现在不存在"板子挂在哪个窗口"这件事。串口控制台已重启，端口列表随之为空（只剩蓝牙口）。如果本意是把底板的 USB-JTAG&UART Type-C 接到电脑，那么这次没有枚举成功，需要检查三件事：是否插在标着 USB-JTAG 的那个 Type-C（另一个口标 USB-OTG，不走 BL702 的调试桥），是否用了只能供电的线，以及底板 1 号拨码是否处在使能位置。

如果是有意拔掉所有 USB 线、只用 DC-IN 12 V 供电来做底噪对比，那么这个状态正是预期的。此时设计已经在外部 Flash 里，板子独立上电就会自动加载并开始发声，不接电脑也能工作；听感对比的结果需要人工确认。
