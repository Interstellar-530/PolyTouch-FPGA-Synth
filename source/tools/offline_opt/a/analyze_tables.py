#!/usr/bin/env python3
"""A2 baseline measurement: what the shipped 48 instrument tables actually contain.

Run from the source root:

  tools/.venv-audio-analysis/Scripts/python.exe \
    tools/offline_opt/a/analyze_tables.py --out-dir ../../../evidence/2026/10/offline-opt/A

The bank map below is the frozen one from ``voice_sched32`` (2026-10-24):

  0..5   e-piano zone group 0 (notes   0..77), stage 0..5
  6..11  e-piano zone group 1 (notes  78..127), stage 0..5
  12..41 guitar, table = 12 + group*6 + variant; group from the note band
  42..47 generic bright spectra (not selected by the scheduler)

Only the documented playable range MIDI 36..96 is asserted; the bend ceiling
1.122467 is the exact worst case of the shipped ``bend_coefficients.vh``
(``fine_ratio_from_adc(4095) == 73562``), not a rounded +/-2 semitone guess.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

import wtlib as w

SOURCE = Path(__file__).resolve().parents[3]
AUDIO = SOURCE / "rtl" / "audio"

PLAY_LO = 36
PLAY_HI = 96
BEND_MAX = 73562 / 65536.0          # exact worst case from bend_coefficients.vh

PIANO_GROUPS = [  # (group, first bank, note lo, note hi)
    (0, 0, 0, 77),
    (1, 6, 78, 127),
]
GUITAR_NOTE_BANDS = [  # frozen candidate_band boundaries from voice_sched32
    (0, 0, 47), (1, 48, 59), (2, 60, 66), (3, 67, 75), (4, 76, 83), (5, 84, 127),
]
BRIGHT_FILES = ["wave_bright_h16.hex", "wave_bright_h8.hex", "wave_bright_h4.hex",
                "wave_bright_h2.hex", "wave_bright_h1.hex", "wave_bright.hex"]


def guitar_group_for_band(band: int) -> int:
    return 0 if band <= 1 else band - 1


def build_bank_map() -> list[dict]:
    banks = []
    epiano = w.read_bank_hex(AUDIO / "epiano_bank_all.hex", 12)
    guitar = w.read_bank_hex(AUDIO / "guitar_bank_all.hex", 30)
    bright = [w.read_hex(AUDIO / name) for name in BRIGHT_FILES]

    for group, first, lo, hi in PIANO_GROUPS:
        for stage in range(6):
            banks.append({"bank": first + stage, "kind": "epiano", "group": group,
                          "stage": stage, "variant": None,
                          "note_lo": lo, "note_hi": min(hi, PLAY_HI),
                          "table": epiano[first + stage]})
    for group in range(5):
        bands = [b for b, lo, hi in GUITAR_NOTE_BANDS if guitar_group_for_band(b) == group]
        lo = min(GUITAR_NOTE_BANDS[b][1] for b in bands)
        hi = min(max(GUITAR_NOTE_BANDS[b][2] for b in bands), PLAY_HI)
        for variant in range(6):
            index = group * 6 + variant
            banks.append({"bank": 12 + index, "kind": "guitar", "group": group,
                          "stage": None, "variant": variant,
                          "note_lo": lo, "note_hi": hi,
                          "table": guitar[index]})
    for i, table in enumerate(bright):
        banks.append({"bank": 42 + i, "kind": "bright", "group": None, "stage": None,
                      "variant": i, "note_lo": None, "note_hi": None, "table": table})
    return banks


def measure(entry: dict) -> dict:
    table = entry["table"]
    amp, _ = w.spectrum(table)
    row = {
        "bank": entry["bank"],
        "kind": entry["kind"],
        "group": entry["group"],
        "stage": entry["stage"],
        "variant": entry["variant"],
        "note_lo": entry["note_lo"],
        "note_hi": entry["note_hi"],
        "peak_dbfs": round(w.peak_dbfs(table), 3),
        "rms_dbfs": round(w.rms_dbfs(table), 3),
        "dc_lsb": round(w.dc_lsb(table), 3),
        "max_adjacent_step_lsb": w.max_adjacent_step(table),
        "significant_harmonics": w.significant_harmonics(amp, -60.0),
        "highest_harmonic_with_energy": int(np.nonzero(amp[1:] > 0.5)[0].max()) + 1
        if np.any(amp[1:] > 0.5) else 0,
    }
    if entry["note_hi"] is not None:
        f_note = w.midi_hz(entry["note_hi"])
        f_bend = f_note * BEND_MAX
        row.update({
            "f_max_hz": round(f_note, 3),
            "f_max_with_bend_hz": round(f_bend, 3),
            "h_allowed_045": w.bandlimit_harmonic(f_bend),
            "h_allowed_050": int(min(255, np.floor(0.5 * w.FS_HZ / f_bend))),
        })
        for label, f0 in (("no_bend", f_note), ("with_bend", f_bend)):
            res = w.alias_residual(table, f0)
            row[f"alias_db_{label}"] = round(res["alias_db"], 2)
            row[f"alias_peak_hz_{label}"] = round(res["worst_alias_hz"], 1)
    else:
        row["h_allowed_045"] = None
    return row


def group_consistency(banks: list[dict]) -> list[dict]:
    """RMS spread and crossfade phase coherence inside each morph group."""
    out = []
    for kind, size in (("epiano", 6), ("guitar", 6)):
        for group in sorted({b["group"] for b in banks if b["kind"] == kind}):
            members = [b for b in banks if b["kind"] == kind and b["group"] == group]
            if len(members) != size:
                continue
            ref = members[0]["table"]
            rows = []
            for member in members[1:]:
                shift = w.phase_alignment_shift(ref, member["table"])
                aligned = w.circular_shift(member["table"], shift)
                a = ref.astype(np.float64)
                b = member["table"].astype(np.float64)
                ba = aligned.astype(np.float64)
                denom = np.linalg.norm(a) * np.linalg.norm(b)
                denom_a = np.linalg.norm(a) * np.linalg.norm(ba)
                rows.append({
                    "stage_or_variant": member["stage"] if member["stage"] is not None
                    else member["variant"],
                    "align_shift_samples": shift,
                    "cosine_raw": round(float(np.dot(a, b) / max(denom, 1e-9)), 4),
                    "cosine_aligned": round(float(np.dot(a, ba) / max(denom_a, 1e-9)), 4),
                })
            out.append({
                "kind": kind, "group": group,
                "rms_dbfs": [round(w.rms_dbfs(m["table"]), 3) for m in members],
                "rms_spread_db": round(max(w.rms_dbfs(m["table"]) for m in members)
                                       - min(w.rms_dbfs(m["table"]) for m in members), 3),
                "members": rows,
            })
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()

    banks = build_bank_map()
    rows = [measure(entry) for entry in banks]
    groups = group_consistency(banks)

    payload = {
        "generated_by": "tools/offline_opt/a/analyze_tables.py",
        "scope": "Offline table measurement only; no RTL, no simulation, no board.",
        "inputs": {
            "epiano_bank_all.hex": w.sha256(AUDIO / "epiano_bank_all.hex"),
            "guitar_bank_all.hex": w.sha256(AUDIO / "guitar_bank_all.hex"),
            **{name: w.sha256(AUDIO / name) for name in BRIGHT_FILES},
        },
        "constants": {
            "depth": w.DEPTH, "fs_hz": w.FS_HZ,
            "nyquist_margin": w.NYQUIST_MARGIN,
            "play_lo": PLAY_LO, "play_hi": PLAY_HI,
            "bend_max_ratio": round(BEND_MAX, 6),
        },
        "banks": rows,
        "groups": groups,
    }
    out = args.out_dir / "A2-table-baseline.json"
    w.json_dump(out, payload)

    header = (f"{'bank':>4} {'kind':8} {'g':>2} {'s/v':>4} {'note':>9} {'RdB':>7} "
              f"{'pkdB':>7} {'H60':>4} {'Hmax':>5} {'H045':>5} {'alias':>7} {'bend':>7}")
    print(header)
    for row in rows:
        note = (f"{row['note_lo']}-{row['note_hi']}" if row["note_lo"] is not None else "-")
        sv = row["stage"] if row["stage"] is not None else row["variant"]
        print(f"{row['bank']:>4} {row['kind']:8} {str(row['group']):>2} {sv:>4} {note:>9} "
              f"{row['rms_dbfs']:>7.2f} {row['peak_dbfs']:>7.2f} "
              f"{row['significant_harmonics']:>4} {row['highest_harmonic_with_energy']:>5} "
              f"{str(row['h_allowed_045']):>5} "
              f"{row.get('alias_db_no_bend', 0.0):>7.1f} {row.get('alias_db_with_bend', 0.0):>7.1f}")
    print()
    for group in groups:
        print(f"group {group['kind']} {group['group']}: rms spread "
              f"{group['rms_spread_db']:.2f} dB, shifts "
              f"{[m['align_shift_samples'] for m in group['members']]}")
        print(f"   cosine raw {[m['cosine_raw'] for m in group['members']]}")
        print(f"   cosine aligned {[m['cosine_aligned'] for m in group['members']]}")
    print(f"\nwrote {out}")


if __name__ == "__main__":
    main()
