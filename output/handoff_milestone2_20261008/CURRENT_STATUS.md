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
- ADSR state machine and repeating 0.25 s on / 0.25 s off gate.
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
