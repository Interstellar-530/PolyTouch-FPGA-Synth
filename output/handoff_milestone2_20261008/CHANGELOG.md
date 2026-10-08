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

## 2026-10-08 follow-up

- Changed `dds_osc.v` to load `wave_sine.hex` through the synthesizer
  include path and added that path to the generated Gowin project. Direct IDE
  synthesis now finds the sine table and keeps `dds_osc`, `adsr`, and
  `voice` in the design.
- Split normal and GAO projects. `build.ps1` now builds the normal
  `instrument.fs`; `build.ps1 -Gao` builds the GAO `ao_0.fs` without
  replacing the normal build mode.
- Added `source/build/launch_gao.ps1` with the required Gowin analyzer
  arguments (`-gao`, `-family`, `-device`). The standalone analyzer no
  longer exits immediately when launched through this wrapper.
- Changed `program_sram.ps1` to default to `SRAM Program` operation 2.
- Verified normal and GAO rebuilds with Gowin V1.9.11.03; the sine ROM still
  maps to BSRAM (4/46 blocks).
