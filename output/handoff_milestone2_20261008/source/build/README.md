# Build and Program

Scripts auto-detect Gowin installed under a top-level `Gowin*` directory on
`C:`, `D:`, or `E:`. If auto-detection fails, pass the executable path or set
`GOWIN_GW_SH` / `GOWIN_PROGRAMMER` / `GOWIN_GAO_ANALYZER`.

## Build

Normal single-voice build:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\build.ps1'
```

Output:

```text
..\impl\pnr\instrument.fs
..\impl\pnr\instrument.rpt.txt
..\impl\pnr\instrument_tr_content.html
```

GAO debug build (separate Gowin project):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\build.ps1' -Gao
```

Output:

```text
..\impl\pnr\ao_0.fs
```

Both generated projects set `-include_path` to `..\rtl\audio`, so
`$readmemh("wave_sine.hex", ...)` works in Tcl and in direct Gowin IDE
synthesis.

## Scan JTAG

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\scan_jtag.ps1'
```

## Program SRAM

Operation 2 means SRAM Program and is the required default on this board.
Operation 4 (SRAM Program and Verify) fails readback verification with status
code 0x00006020. SRAM configuration is lost on power cycle, which is useful
for the first listening test.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\program_sram.ps1'
```

To use a non-default cable:

```powershell
.\program_sram.ps1 -Cable 'Gowin USB CableFT2CH'
```
## Launch GAO

The standalone analyzer needs its required `-family` and `-device` arguments.
Use the wrapper so it opens with the project GAO configuration:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\launch_gao.ps1'
```

If the board is already running the GAO bitstream, the analyzer can connect
without reprogramming. Pass `-FsFile '..\impl\pnr\ao_0.fs'` only when the script
should offer that bitstream for programming. The built-in Gowin IDE GAO flow
remains available as a fallback.
