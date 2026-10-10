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

