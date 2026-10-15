# Review archives

Each `FPGA-<date>-vX.Y` directory is a review deliverable for one checklist item:
the corrected sources, the evidence (raw logs, rendered figures, datasheet
citations), `MANIFEST.md` describing what changed and why, `checksums.sha256`
over every archived file, and the checklist document copy after that review.

| Archive | Scope |
| --- | --- |
| `FPGA-20261015-v0.8` | S4 MCP3208 digital delivery: 19-clock DS21298E frame, device model, three benches |
| `FPGA-20261015-v0.9` | S5 pressure and pitch bend: rounding direction, ADC centre, widened phase product |
| `FPGA-20261015-v0.10` | S6 wavetable voices: 512-point tables, three-point interpolation, (1,4,6,4,1)/16 FIR |

## What is intentionally not in the repository

`FPGA-20261015-v0.8/evidence/MCP3204-3208-datasheet.pdf` is a third-party vendor
document. It stays out of the repository (the `.gitignore` rule matches that one
file name), while its SHA256 remains recorded as a comment inside that archive's
`checksums.sha256`, so a clone shows exactly one intentionally absent file.
Download the datasheet from Microchip to restore a byte-identical archive. The
short excerpt in `evidence/datasheet-excerpt.txt`, which carries the frame
structure the S4 fix is based on, is kept for auditability.

Everything else under `archive/` is versioned: these archives are the record that
the checklist item was reviewed and verified, so they belong in history next to
the code they describe.