#!/usr/bin/env python3
"""A2 wavetable optimiser: band limit, DC removal, loudness consistency.

Run from the source root (writes only where told):

  tools/.venv-audio-analysis/Scripts/python.exe tools/offline_opt/a/gen_bandlimit.py \
      --out-dir ../../tmp/offline-opt-a/a2 --report ../../../docs/evidence/offline-opt/A/A2-bandlimit.json

What it changes, and only this:

  * harmonic-domain band limit  H = min(255, floor(0.45*Fs/f_max))
    where f_max is the worst supported pitch that can select the table
    (frozen bank map, documented playable range MIDI 36..96, exact bend
    ceiling 73562/65536 from ``bend_coefficients.vh``),
  * DC removed (a periodic table's DC term is a constant bias, never pitch),
  * loudness consistency: every table in a morph/velocity group is scaled to the
    quietest member's RMS, so a velocity threshold or a stage transition cannot
    jump the level.  Scaling is always <= 1, so no table can clip.

Phases are not rotated: the e-piano stages are already >= 0.997 correlated and
the guitar variants are never crossfaded (``candidate_weight`` is 0 for
guitar), so a rotation would only move a sample's time origin for no gain.

``--legacy`` regenerates the shipped tables from the shipped hex so the emitter
can be proven byte-identical before any data is replaced.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

import wtlib as w

SOURCE = Path(__file__).resolve().parents[3]
AUDIO = SOURCE / "rtl" / "audio"

PLAY_LO, PLAY_HI = 36, 96
BEND_MAX = 73562 / 65536.0

# Frozen bank map: bank -> (kind, group, table index in its hex file)
PIANO_NOTE_HI = [(0, 77), (6, 127)]          # group -> highest note it serves


def zone_limits() -> dict[int, dict]:
    """Per-bank worst-case pitch, including the bend ceiling."""
    limits: dict[int, dict] = {}
    for group, first in ((0, 0), (1, 6)):
        hi = min(PIANO_NOTE_HI[group][1], PLAY_HI)
        f_note = w.midi_hz(hi)
        f_bend = f_note * BEND_MAX
        for stage in range(6):
            limits[first + stage] = {
                "kind": "epiano", "group": group, "index": first + stage,
                "note_hi": hi, "f_max_hz": f_bend,
                "h_limit": w.bandlimit_harmonic(f_bend),
            }
    guitar_band_hi = {0: 59, 1: 59, 2: 66, 3: 75, 4: 83, 5: 96}
    for band, hi in guitar_band_hi.items():
        group = 0 if band <= 1 else band - 1
        limits.setdefault(("guitar", group), {"note_hi": 0})
        limits[("guitar", group)]["note_hi"] = max(limits[("guitar", group)]["note_hi"], hi)
    for group in range(5):
        hi = min(limits[("guitar", group)]["note_hi"], PLAY_HI)
        f_note = w.midi_hz(hi)
        f_bend = f_note * BEND_MAX
        for variant in range(6):
            index = group * 6 + variant
            limits[12 + index] = {
                "kind": "guitar", "group": group, "index": index,
                "note_hi": hi, "f_max_hz": f_bend,
                "h_limit": w.bandlimit_harmonic(f_bend),
            }
    return {k: v for k, v in limits.items() if isinstance(k, int)}


def process_table(table: np.ndarray, h_limit: int) -> tuple[np.ndarray, dict]:
    amp, phase = w.spectrum(table)
    dc = float(amp[0])
    out = w.resynthesise(amp, phase, h_limit)
    out = out - int(round(np.mean(out.astype(np.float64))))
    return out, {"dc_removed_lsb": dc}


def scale_to_rms(table: np.ndarray, target_dbfs: float) -> tuple[np.ndarray, float]:
    current = w.rms_dbfs(table)
    gain_db = min(0.0, target_dbfs - current)          # never amplify
    gain = 10.0 ** (gain_db / 20.0)
    scaled = np.clip(np.rint(np.asarray(table, dtype=np.float64) * gain), -32768, 32767)
    return scaled.astype(np.int64), gain_db


def describe(table: np.ndarray) -> dict:
    amp, _ = w.spectrum(table)
    return {
        "rms_dbfs": round(w.rms_dbfs(table), 3),
        "peak_dbfs": round(w.peak_dbfs(table), 3),
        "dc_lsb": round(w.dc_lsb(table), 3),
        "significant_harmonics": w.significant_harmonics(amp, -60.0),
        "highest_harmonic": int(np.nonzero(amp[1:] > 0.5)[0].max()) + 1
        if np.any(amp[1:] > 0.5) else 0,
        "max_adjacent_step_lsb": w.max_adjacent_step(table),
    }


# ----------------------------------------------------------- prom emitters --
def emit_piano_bank(tables: np.ndarray, comment: list[str]) -> str:
    lines = list(comment)
    lines += [
        "module gowin_prom_piano_bank(input wire clk,ce,rst, input wire [5:0] bank,",
        " input wire [8:0] addr, output reg [15:0] dout);",
        "reg [2:0] selected=0;",
        "always @(posedge clk) if(rst) selected<=0; else if(ce) selected<=bank[3:1];",
    ]
    for group in range(6):
        lines.append(f"wire [31:0] gd{group};")
    lines += ["always @* case(selected)"]
    for group in range(6):
        lines.append(f" 3'd{group}: dout=gd{group}[15:0];")
    lines += [" default: dout=16'd0;", "endcase"]
    for group in range(6):
        words = w.prom_init_words([tables[group * 2], tables[group * 2 + 1]])
        lines.append('pROM #(.READ_MODE(1\'b0),.BIT_WIDTH(6\'d16),.RESET_MODE("SYNC"),')
        lines.append(w.emit_prom_params(words))
        lines += [
            f" ) gp{group} (.DO(gd{group}),.AD({{bank[0],addr,4'b0}}),",
            f" .CLK(clk),.CE(ce && bank[3:1]==3'd{group}),.OCE(1'b1),.RESET(rst));",
        ]
    lines += ["endmodule", ""]
    return "\n".join(lines)


def emit_guitar_bank(tables: np.ndarray, comment: list[str]) -> str:
    lines = list(comment)
    lines += [
        "module gowin_prom_guitar_bank(input wire clk,ce,rst, input wire [5:0] bank,",
        " input wire [8:0] addr, output reg [15:0] dout);",
        "reg [3:0] selected=0;",
        "always @(posedge clk) if(rst) selected<=0; else if(ce) selected<=bank[4:1];",
    ]
    for group in range(15):
        lines.append(f"wire [31:0] gd{group};")
    lines += ["always @* case(selected)"]
    for group in range(15):
        lines.append(f" 4'd{group}: dout=gd{group}[15:0];")
    lines += [" default: dout=16'd0;", "endcase"]
    for group in range(15):
        words = w.prom_init_words([tables[group * 2], tables[group * 2 + 1]])
        lines.append('pROM #(.READ_MODE(1\'b0),.BIT_WIDTH(6\'d16),.RESET_MODE("SYNC"),')
        lines.append(w.emit_prom_params(words))
        lines += [
            f") gp{group} (.DO(gd{group}),.AD({{bank[0],addr,4'b0}}),",
            f" .CLK(clk),.CE(ce && bank[4:1]==4'd{group}),.OCE(1'b1),.RESET(rst));",
        ]
    lines += ["endmodule", ""]
    return "\n".join(lines)


PIANO_COMMENT = [
    "// Generated by tools/offline_opt/a/gen_bandlimit.py from epiano_bank_all.hex.",
    "// 12 tables = 2 zone groups x 6 stages, two tables per pROM (6 BSRAM).",
    "// A2: per-zone harmonic band limit, DC removed, group RMS matched.",
]
GUITAR_COMMENT = [
    "// Generated by tools/offline_opt/a/gen_bandlimit.py v2 (Karoryfer CC0).",
    "// 30 tables = 5 band groups x 6 variants, exact-f0 harmonics, 15 BSRAM.",
    "// A2: per-zone harmonic band limit, DC removed, group RMS matched.",
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--legacy", action="store_true",
                        help="re-emit the shipped tables (equivalence check)")
    parser.add_argument("--src-dir", type=Path,
                        help="directory holding the *source* epiano/guitar hex; "
                             "defaults to rtl/audio.  Reproduction must point this at "
                             "the pre-optimisation set (archive .../source/before-a2), "
                             "because running the transform on its own output is a "
                             "second optimisation pass, not a reproduction.")
    args = parser.parse_args()
    out = args.out_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    src_dir = (args.src_dir or AUDIO).resolve()

    epiano = w.read_bank_hex(src_dir / "epiano_bank_all.hex", 12)
    guitar = w.read_bank_hex(src_dir / "guitar_bank_all.hex", 30)
    limits = zone_limits()

    report: dict = {
        "generated_by": "tools/offline_opt/a/gen_bandlimit.py",
        "mode": "legacy-equivalence" if args.legacy else "bandlimit",
        "constants": {"play_lo": PLAY_LO, "play_hi": PLAY_HI,
                      "bend_max_ratio": round(BEND_MAX, 6),
                      "nyquist_margin": w.NYQUIST_MARGIN},
        "inputs": {"epiano_bank_all.hex": w.sha256(AUDIO / "epiano_bank_all.hex"),
                   "guitar_bank_all.hex": w.sha256(AUDIO / "guitar_bank_all.hex")},
        "banks": [],
    }

    # --- band limit / DC per table, then group loudness matching -------------
    def optimise(bank_tables: np.ndarray, kind: str) -> tuple[np.ndarray, list[dict]]:
        rows = []
        stage1 = []
        for index, table in enumerate(bank_tables):
            key = index if kind == "epiano" else 12 + index
            info = limits[key]
            before = describe(table)
            # Worst-case alias residual at the zone's top note, with bend.
            alias_before = w.alias_residual(table, info["f_max_hz"])
            if args.legacy:
                new = table.copy()
                extra = {}
            else:
                new, extra = process_table(table, info["h_limit"])
            stage1.append(new)
            rows.append({
                "bank": key, "kind": kind, "group": info["group"],
                "table_index": index, "note_hi": info["note_hi"],
                "f_max_hz": round(info["f_max_hz"], 2),
                "h_limit": info["h_limit"],
                "before": before,
                "before_alias_db": round(alias_before["alias_db"], 2),
                **{("dc_" + k): v for k, v in extra.items()},
            })
        stage1 = np.stack(stage1)
        rows_by_group: dict[int, list[int]] = {}
        for row in rows:
            rows_by_group.setdefault(row["group"], []).append(row["bank"] - (0 if kind == "epiano" else 12))
        gains = [0.0] * len(bank_tables)
        if not args.legacy:
            for group, members in rows_by_group.items():
                target = min(w.rms_dbfs(stage1[m]) for m in members)
                for m in members:
                    stage1[m], gains[m] = scale_to_rms(stage1[m], target)
                for m in members:
                    rows[m]["group_rms_target_dbfs"] = round(target, 3)
        for i, row in enumerate(rows):
            row["gain_db"] = round(gains[i], 3)
            row["after"] = describe(stage1[i])
            row["after_alias_db"] = round(w.alias_residual(stage1[i], limits[
                i if kind == "epiano" else 12 + i]["f_max_hz"])["alias_db"], 2)
            removed = stage1[i].astype(np.float64) - (bank_tables[i].astype(np.float64)
                                                      * 10 ** (gains[i] / 20.0))
            row["removed_rms_db"] = round(20 * np.log10(
                max(float(np.sqrt(np.mean(removed ** 2))), 1e-9)
                / max(float(np.sqrt(np.mean(bank_tables[i].astype(np.float64) ** 2))), 1e-9)), 2)
        return stage1, rows

    epiano_new, epiano_rows = optimise(epiano, "epiano")
    guitar_new, guitar_rows = optimise(guitar, "guitar")
    report["banks"] = epiano_rows + guitar_rows

    w.write_hex(out / "epiano_bank_all.hex", epiano_new)
    w.write_hex(out / "guitar_bank_all.hex", guitar_new)
    (out / "gowin_prom_piano_bank.v").write_text(
        emit_piano_bank(epiano_new, PIANO_COMMENT), encoding="ascii")
    (out / "gowin_prom_guitar_bank.v").write_text(
        emit_guitar_bank(guitar_new, GUITAR_COMMENT), encoding="ascii")

    # --- the emitted ROM initialisation must decode back to these tables ----
    # This is the check that "hex, vendor init and metadata ship together":
    # the wrapper is parsed again and compared sample by sample.
    def roundtrip(path: Path, intended: np.ndarray) -> bool:
        decoded = w.parse_prom_module(path)
        flat = np.array([t for i in sorted(decoded) for t in decoded[i]], dtype=np.int64)
        return flat.shape == intended.shape and np.array_equal(flat, intended)

    report["roundtrip"] = {
        "piano_prom_decodes_to_tables": roundtrip(
            out / "gowin_prom_piano_bank.v", epiano_new),
        "guitar_prom_decodes_to_tables": roundtrip(
            out / "gowin_prom_guitar_bank.v", guitar_new),
        "hex_roundtrip": bool(np.array_equal(
            w.read_bank_hex(out / "epiano_bank_all.hex", 12), epiano_new)
            and np.array_equal(w.read_bank_hex(out / "guitar_bank_all.hex", 30), guitar_new)),
    }
    if not all(report["roundtrip"].values()):
        raise SystemExit(f"emitted ROM initialisation does not round-trip: {report['roundtrip']}")

    # --- metadata delivered with the tables --------------------------------
    epiano_meta = {
        "source": "AKWF_epiano_0001.wav",
        "license": "CC0",
        "generator": "tools/offline_opt/a/gen_bandlimit.py",
        "tables": 12, "depth": w.DEPTH, "bsram_blocks": 6,
        "bank_index": "group*6 + stage",
        "band_limit": {
            "rule": "H = min(255, floor(margin*Fs/f_max))",
            "margin": w.NYQUIST_MARGIN, "fs_hz": w.FS_HZ,
            "play_range_midi": [PLAY_LO, PLAY_HI],
            "bend_max_ratio": round(BEND_MAX, 6),
            "note": "f_max includes the exact worst-case bend ratio; DC removed; "
                    "each group scaled to its quietest member's RMS",
        },
        "banks": epiano_rows,
    }
    guitar_meta = {
        "source": "Karoryfer Black And Green Guitars",
        "license": "CC0",
        "generator": "tools/offline_opt/a/gen_bandlimit.py",
        "tables": 30, "depth": w.DEPTH, "bsram_blocks": 15,
        "band_index": [40, 48, 56, 64, 72, 80, 89],
        "variants": ["green/p", "green/mf", "green/f",
                     "black/p", "black/mf", "black/f"],
        "band_limit": epiano_meta["band_limit"],
        "banks": guitar_rows,
    }
    w.json_dump(out / "epiano_bank_meta.json", epiano_meta)
    w.json_dump(out / "guitar_bank_meta.json", guitar_meta)
    w.json_dump(args.report, report)

    print(f"{'bank':>4} {'kind':8} {'Hlim':>4} {'H60':>4} {'Hmax':>5} "
          f"{'alias dB before':>15} {'after':>7} {'gain':>6} {'removed':>8}")
    for row in report["banks"]:
        print(f"{row['bank']:>4} {row['kind']:8} {row['h_limit']:>4} "
              f"{row['before']['significant_harmonics']:>4} "
              f"{row['before']['highest_harmonic']:>5} "
              f"{row['before_alias_db']:>15.1f} {row['after_alias_db']:>7.1f} "
              f"{row['gain_db']:>6.2f} {row.get('removed_rms_db', 0.0):>8.1f}")
    print(report["roundtrip"])
    print(f"wrote {out} and {args.report}")


if __name__ == "__main__":
    main()
