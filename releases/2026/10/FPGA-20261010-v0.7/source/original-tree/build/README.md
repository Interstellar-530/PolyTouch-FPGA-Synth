# Build and Program

Scripts auto-detect Gowin installed under a top-level `Gowin*` directory on
`C:`, `D:`, or `E:`. If auto-detection fails, pass the executable path or set
`GOWIN_GW_SH` / `GOWIN_PROGRAMMER`.

## Build

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\build.ps1'
```

Output:

```text
..\impl\pnr\instrument.fs
..\impl\pnr\instrument.rpt.txt
..\impl\pnr\instrument_tr_content.html
```

## Scan JTAG

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\scan_jtag.ps1'
```

## Program SRAM

Operation 4 means SRAM Program and Verify. SRAM configuration is lost on power
cycle, which is useful for the first listening test.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\program_sram.ps1'
```

To use a non-default cable:

```powershell
.\program_sram.ps1 -Cable 'Gowin USB CableFT2CH'
```