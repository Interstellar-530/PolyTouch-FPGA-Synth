# Design Decisions

1. The submitted instrument must have a completely FPGA-HDL audio path.
   No MCU, CPU, PC DSP, or BL702 is allowed in the sample-by-sample path.

2. The first development output is the Dock 3714 on-board PT8211 because its
   pins are known and already wired to the headphone amplifier.

3. The first audio milestone uses a 27 MHz-derived debug clock:
   `27 MHz / 18 = 1.5 MHz BCK`, `1.5 MHz / 32 = 46.875 kHz WS`.
   This is for bring-up only.

4. The final formal output will use an external 12.288 MHz clock and PCM5102A
   standard I2S. The 12.288 MHz source cannot be replaced by an exact integer
   PLL division of 27 MHz.

5. A wavetable ROM stores one mathematical cycle only. It must never contain
   songs, full recordings, or long PCM segments.

6. Start with one voice. Expand to four voices only after the single-voice
   hardware path passes.

7. Preserve parameterization in the RTL so voice count can later move from 4 to
   8 and then to a more resource-efficient 32-voice design.

8. Touch and pressure are part of the final instrument, but they are not part
   of the first DDS/PT8211 bring-up milestone.

9. LED2 is Orange_LED2 on N16 and is active-low. It is the normal programming
   and run indicator. Other user LEDs are C13, A13, N14, L14, and L16.

10. Use `SRAM Program` operation 2 for this board. Do not use `Program and
    Verify`; the readback verification fails with status code `0x00006020`.

11. Use `source/build/launch_gao.ps1` for the standalone GAO analyzer. It
    supplies the required `-gao`, `-family`, and `-device` arguments. The
    Gowin IDE built-in GAO remains the fallback.

12. The generated Gowin project sets `-include_path` to `source/rtl/audio`,
    so `dds_osc.v` loads `wave_sine.hex` in both Tcl and IDE-driven
    synthesis. Normal and GAO builds use separate project directories to
    preserve the normal `instrument.fs` build.
