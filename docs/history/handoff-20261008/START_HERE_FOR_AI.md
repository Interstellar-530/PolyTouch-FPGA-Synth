# AI Handoff: FPGA Electronic Instrument, Milestone 2

You are taking over an existing FPGA project. Do not redesign it from scratch.
This folder is a self-contained snapshot after the 2026-10-08 debugging session.

## Read Order

1. `PROJECT_MANIFEST.json`
2. `CURRENT_STATUS.md`
3. `NEXT_TASKS.json`
4. `DESIGN_DECISIONS.md`
5. `HARDWARE_NOTES.md`
6. `COMPETITION_REQUIREMENTS.md`
7. `CHANGELOG.md`
8. `source/`, `artifacts/`, and `reference/logs/FPGA_DEBUG_LOG_20261008.md`

If historical documents in `reference/` conflict with the top-level files or
the current source, the top-level files and current source win.

## Project Identity

- Competition: 2026 National College Student Embedded Chip and System Design
  Competition, FPGA Innovation Design Track, Gowin topic 2.
- Product: real-time polyphonic digital musical instrument.
- Hardware: Sipeed Tang Primer 20K core board plus Dock 3714.
- FPGA: `GW2A-LV18PG256C8/I7`, device version C.
- Current milestone: 27 MHz debug path restored, single DDS voice plus ADSR
  through the on-board PT8211, LED2 blinking, and GAO core integrated.
- Formal output for later milestones: external PCM5102A over standard I2S.

## Current State

The 27 MHz clock problem was traced to the core board seating. After reseating
the core board, the four-LED 27 MHz diagnostic blinked, proving that the board
oscillator, FPGA configuration, and user LEDs are working. The normal design
was then restored with a single DDS voice, ADSR, PT8211 debug output, and
Orange_LED2 on N16 blinking.

Two bitstreams are included:

- `artifacts/instrument.fs`: normal single-voice design with LED2 blinking.
  SHA256 `e79c1c58b66bc4cff6f4eafb03f51a6c9b5fc9a73f348420a1cbed23c7d19985`.
- `artifacts/ao_0.fs`: GAO-enabled debug bitstream. SHA256
  `f637549f363fc23e5fceb29422b2291a3cb229e56e86145fced257fee6c85ebb`.

SRAM programming must use operation 2, `SRAM Program`, not operation 4,
`SRAM Program and Verify`. Operation 4 reports `Verify Failed` on this board
with status code `0x00006020`; operation 2 succeeds and returns exit code 0.
Do not power-cycle the board after SRAM programming.

## First Task

The immediate task is to observe the internal audio engine without headphones:

1. Open the project in Gowin IDE.
2. Program `artifacts/ao_0.fs` with operation 2 if the SRAM is not already
   running the GAO bitstream.
3. In the Design window, double-click `source/rtl/gao_top.rao`.
4. Open the Gowin IDE built-in GAO capture window.
5. Connect to Local jtagserver, select `Gowin USB Cable(FT2CH)`, set the
   device chain to Gowin Device, Series `GW2A`, Device `GW2A-18C`, and check
   Enable. Disable the integrated programmer because the bitstream is already
   in SRAM, or select `SRAM Program` if reprogramming.
6. Trigger on `sample_tick` rising edge and inspect `gate`,
   `voice_sample[15:0]`, `hp_bck`, `hp_ws`, `hp_din`, and `pa_en`.

The standalone `gao_analyzer.exe` exits immediately in this environment. Use
the GAO tool inside Gowin IDE; do not keep retrying the standalone executable.

## Hard Rules

- Keep the audio generation path in FPGA HDL.
- Do not put a CPU, MCU, PC software, or BL702 in the sample-by-sample path.
- Do not play recorded PCM, songs, or full audio samples.
- A wavetable may contain only one cycle of a mathematical waveform.
- Use `SRAM Program` operation 2, not `Program and Verify`.
- Do not power-cycle after SRAM programming while testing.
- Preserve the existing low-resource, buildable milestone while expanding.
- After every source change, rebuild with `source/build/build.ps1`.
- Run `source/tools/collect_build_evidence.py` after a successful build.

## Important Technical Facts

- Board 27 MHz clock pin: H11. The core-board oscillator is U10 and its EN pin
  is tied to +3V3; the output goes through R20 22 ohm to H11.
- PT8211 debug pins: BCK N15, WS P16, DIN P15, PA_EN R16.
- User LED mapping: Orange_LED0=C13, Orange_LED1=A13, Orange_LED2=N16,
  Orange_LED3=N14, Orange_LED4=L14, Orange_LED5=L16.
- LEDs are active-low: the FPGA pin is the cathode.
- Debug sample rate: 27 MHz / 18 / 32 = 46.875 kHz.
- PT8211 BCK: about 1.5 MHz.
- Formal 48 kHz path requires an external 12.288 MHz clock and PCM5102A.
- The `wave_sine.hex` relative path works in the Tcl build because the Tcl
  changes to the source root before `run all`. Gowin IDE direct synthesis may
  still report `Cannot open file 'rtl\audio\wave_sine.hex'`; fix this with a
  Gowin ROM IP or a project-local memory file before relying on IDE builds.

## Expansion Order

1. Capture and verify the audio engine with GAO.
2. Fix the wavetable path so Gowin IDE direct synthesis is warning-free.
3. Add UART status output and an audio-activity LED.
4. Add MPR121 I2C and 12-key touch events.
5. Parameterize the voice module and expand to 4 voices.
6. Add MCP3208/FSR pressure and a second waveform.
7. Replace the PT8211 debug output with PCM5102A standard I2S after confirming
   a free 3.3 V GCLK pin on Dock 3714.

Do not start with 32 voices, reverb, Bluetooth, or a display.
