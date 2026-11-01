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

This board's established flow uses operation **2 (SRAM Program)**, which is
also the script default. Do not substitute operation 4 based on this old
README. SRAM configuration is lost on power cycle.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File '.\program_sram.ps1'
```

To use a non-default cable, scan the current connection and supply the cable
name reported by your Programmer installation. Channel and Location are also
connection-dependent; this wrapper does not expose these as separate options.
When a precise target selection is needed, run the simulation gate first and
select that target in Gowin Programmer. Do not reuse a historical location ID.

```powershell
.\program_sram.ps1 -Cable '<cable name from current scan>' -FsFile '<explicit bitstream path>'
```

For the v1.0.0 historical 0x5633 configuration, use the versioned file at
`releases/v1.0.0/instrument_sram_0x5633.fs` relative to the repository root.
The programmer wrapper prefers a local freshly built file when -FsFile is
omitted, which is not guaranteed to have the same bytes or User Code.
