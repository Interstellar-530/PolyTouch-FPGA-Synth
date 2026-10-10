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
