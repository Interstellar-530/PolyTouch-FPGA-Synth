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
