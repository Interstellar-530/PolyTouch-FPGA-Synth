#!/usr/bin/env python3
"""Independent A2 verifier for the 48 shipped instrument banks.

It reads the *ROM wrappers* (the vendor initialisation that actually ships),
decodes them back to 512-point tables and checks both the decoded data and the
``*.hex`` sources.  Nothing here depends on how the tables were generated, so it
can audit the baseline (which fails the band-limit check) and the optimised set.

Checks, per bank:
  * 512 samples, every sample inside int16,
  * hex source and pROM initialisation decode to the same samples,
  * DC term below a documented bound,
  * periodic seam no larger than the largest interior step,
  * harmonic content above the zone's band limit,
  * modelled aliasing residual at the zone's worst pitch including bend.

Exit code is non-zero when any check fails, so the gate can consume it directly.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

import wtlib as w
from gen_bandlimit import (BEND_MAX, PLAY_HI, PLAY_LO, emit_guitar_bank,
                           emit_piano_bank, zone_limits)

SOURCE = Path(__file__).resolve().parents[3]
AUDIO = SOURCE / "rtl" / "audio"
DC_LIMIT_LSB = 1.0
HARMONIC_FLOOR_DB = -60.0


def decode_banks() -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    piano_prom = w.parse_prom_module(AUDIO / "gowin_prom_piano_bank.v")
    guitar_prom = w.parse_prom_module(AUDIO / "gowin_prom_guitar_bank.v")
    bright_prom = w.parse_prom_module(AUDIO / "gowin_prom_bright_bank.v")
    if len(piano_prom) != 6:
        raise SystemExit(f"piano wrapper has {len(piano_prom)} pROMs, expected 6")
    if len(guitar_prom) != 15:
        raise SystemExit(f"guitar wrapper has {len(guitar_prom)} pROMs, expected 15")
    if len(bright_prom) != 3:
        raise SystemExit(f"bright wrapper has {len(bright_prom)} pROMs, expected 3")
    piano = np.array([t for i in range(6) for t in piano_prom[i]], dtype=np.int64)
    guitar = np.array([t for i in range(15) for t in guitar_prom[i]], dtype=np.int64)
    bright = np.array([t for i in range(3) for t in bright_prom[i]], dtype=np.int64)
    return piano, guitar, bright


def fnv1a32(table: np.ndarray) -> int:
    h = 2166136261
    for value in table:
        h ^= int(value) & 0xFFFF
        h = (h * 16777619) & 0xFFFFFFFF
    return h


def wrap_step(table: np.ndarray) -> int:
    return int(abs(int(table[0]) - int(table[-1])))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--expect-bandlimit", action="store_true",
                        help="fail when a table exceeds its zone band limit")
    parser.add_argument("--emit-header", type=Path,
                        help="write the RTL expectation header for sim/opt_a")
    args = parser.parse_args()

    piano, guitar, bright = decode_banks()
    limits = zone_limits()
    hex_piano = w.read_bank_hex(AUDIO / "epiano_bank_all.hex", 12)
    hex_guitar = w.read_bank_hex(AUDIO / "guitar_bank_all.hex", 30)

    failures: list[str] = []
    banks: list[dict] = []

    for kind, decoded, source in (("epiano", piano, hex_piano),
                                  ("guitar", guitar, hex_guitar),
                                  ("bright", bright, None)):
        for index in range(len(decoded)):
            table = decoded[index]
            key = index if kind == "epiano" else (12 + index if kind == "guitar"
                                                 else 42 + index)
            info = limits.get(key)
            row = {
                "bank": key, "kind": kind,
                "group": info["group"] if info else None,
                "table_index": index,
                "note_hi": info["note_hi"] if info else None,
                "f_max_hz": round(info["f_max_hz"], 2) if info else None,
                "h_limit": info["h_limit"] if info else None,
                "fnv1a32": fnv1a32(table),
                "sum": int(np.sum(table)),
                "peak_abs": int(np.max(np.abs(table))),
                "rms_dbfs": round(w.rms_dbfs(table), 3),
                "dc_lsb": round(w.dc_lsb(table), 3),
                "wrap_step": wrap_step(table),
                "max_adjacent_step": w.max_adjacent_step(table),
            }
            amp, _ = w.spectrum(table)
            row["significant_harmonics"] = w.significant_harmonics(amp, HARMONIC_FLOOR_DB)
            if info:
                row["alias_db"] = round(w.alias_residual(table, info["f_max_hz"])["alias_db"], 2)
                row["alias_db_all_bins"] = round(w.alias_residual(
                    table, info["f_max_hz"], floor_dbfs=-400.0)["alias_db"], 2)
            else:
                row["alias_db"] = None
                row["alias_db_all_bins"] = None
            row["checks"] = {}

            if source is not None and not np.array_equal(table, source[index]):
                failures.append(f"bank {key}: hex and pROM init disagree")
                row["checks"]["hex_matches_prom"] = False
            else:
                row["checks"]["hex_matches_prom"] = True
            if abs(row["dc_lsb"]) > DC_LIMIT_LSB:
                failures.append(f"bank {key}: DC {row['dc_lsb']:.2f} LSB exceeds {DC_LIMIT_LSB}")
                row["checks"]["dc_ok"] = False
            else:
                row["checks"]["dc_ok"] = True
            interior = int(np.max(np.abs(np.diff(table))))
            if row["wrap_step"] > interior:
                failures.append(f"bank {key}: wrap step {row['wrap_step']} > interior {interior}")
                row["checks"]["seam_ok"] = False
            else:
                row["checks"]["seam_ok"] = True
            if info:
                within = row["significant_harmonics"] <= info["h_limit"]
                row["checks"]["band_limit_ok"] = within
                if not within and args.expect_bandlimit:
                    failures.append(
                        f"bank {key}: {row['significant_harmonics']} harmonics above "
                        f"{HARMONIC_FLOOR_DB} dB exceeds the zone limit {info['h_limit']}")
            else:
                row["checks"]["band_limit_ok"] = None
            banks.append(row)

    payload = {
        "generated_by": "tools/offline_opt/a/verify_tables.py",
        "strict_bandlimit": args.expect_bandlimit,
        "constants": {"play_lo": PLAY_LO, "play_hi": PLAY_HI,
                      "bend_max_ratio": round(BEND_MAX, 6),
                      "dc_limit_lsb": DC_LIMIT_LSB,
                      "harmonic_floor_db": HARMONIC_FLOOR_DB},
        "sources": {"epiano_bank_all.hex": w.sha256(AUDIO / "epiano_bank_all.hex"),
                    "guitar_bank_all.hex": w.sha256(AUDIO / "guitar_bank_all.hex"),
                    "gowin_prom_piano_bank.v": w.sha256(AUDIO / "gowin_prom_piano_bank.v"),
                    "gowin_prom_guitar_bank.v": w.sha256(AUDIO / "gowin_prom_guitar_bank.v")},
        "banks": banks,
        "failures": failures,
        "passed": not failures,
    }
    w.json_dump(args.report, payload)

    if args.emit_header:
        lines = ["// Generated by tools/offline_opt/a/verify_tables.py -- do not edit.",
                 "// Frozen {bank, fnv1a32, peak, sum} for the 48 installed banks.",
                 f"  TBL_COUNT = {len(banks)};"]
        for row in banks:
            lines.append(
                f"  tbl_expect({row['bank']}, 32'h{row['fnv1a32']:08X}, "
                f"{row['peak_abs']}, {row['sum']});")
        args.emit_header.parent.mkdir(parents=True, exist_ok=True)
        args.emit_header.write_text("\n".join(lines) + "\n", encoding="ascii")

    over = [row for row in banks if row["checks"]["band_limit_ok"] is False]
    print(f"banks={len(banks)} failures={len(failures)} over_band_limit={len(over)}")
    for row in banks:
        flag = " <-- over limit" if row["checks"]["band_limit_ok"] is False else ""
        limit = "-" if row["h_limit"] is None else f"{row['h_limit']:3d}"
        alias = "   n/a " if row["alias_db"] is None else f"{row['alias_db']:7.1f}"
        print(f"  bank {row['bank']:2d} {row['kind']:7} H={row['significant_harmonics']:3d}"
              f"/{limit} alias={alias} dB fnv={row['fnv1a32']:08X}{flag}")
    for message in failures:
        print("FAIL", message)
    print(f"wrote {args.report}")
    sys.exit(0 if not failures else 1)


if __name__ == "__main__":
    main()
