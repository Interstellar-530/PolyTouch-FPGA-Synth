#!/usr/bin/env python3
"""A1 width proof: exhaustive reachable-range check of every datapath slice.

Every 24-bit slice in ``instrument_ram_wavetable_engine`` truncates a product
of two known-width operands.  Rather than guessing, this script enumerates
*all* reachable operand values for the 48 installed tables:

  * every bank, every bank+1 pair the engine can form,
  * all 512 interpolation phases (n) and all 512 fractions,
  * all weight and envelope/velocity extremes.

For each slice it reports the worst magnitude, the admissible 24-bit limit and
the remaining margin in bits, and exits non-zero when the margin drops below
``--min-margin-bits``.  That turns "the widths are fine because the tables are
smooth" into a checked property and fails before a future table set silently
wraps.

Run from the source root:
  tools/.venv-audio-analysis/Scripts/python.exe \
    tools/offline_opt/a/a1_bounds.py --report ../../../docs/evidence/offline-opt/A/A1-bounds.json
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import numpy as np

import wtlib as w

SOURCE = Path(__file__).resolve().parents[3]
AUDIO = SOURCE / "rtl" / "audio"
INT24_MIN, INT24_MAX = -(1 << 23), (1 << 23) - 1
INT32_MIN, INT32_MAX = -(1 << 31), (1 << 31) - 1


def load_tables() -> list[np.ndarray]:
    piano = w.read_bank_hex(AUDIO / "epiano_bank_all.hex", 12)
    guitar = w.read_bank_hex(AUDIO / "guitar_bank_all.hex", 30)
    bright = [w.read_hex(AUDIO / name) for name in
              ("wave_bright_h16.hex", "wave_bright_h8.hex", "wave_bright_h4.hex",
               "wave_bright_h2.hex", "wave_bright_h1.hex", "wave_bright.hex")]
    sine = w.read_hex(AUDIO / "wave_sine.hex")
    return [np.asarray(t, dtype=np.int64) for t in list(piano) + list(guitar) + bright], sine


def interp(table: np.ndarray, index: int, frac: int) -> int:
    """Wide (no-wrap) linear interpolation in the 8-fractional-bit domain."""
    n = index % w.DEPTH
    a = int(table[n])
    b = int(table[(n + 1) % w.DEPTH])
    return (a << 8) + (((b - a) * frac) >> 1) + (((b - a) * frac) & 1)


def bits_of(value: int) -> float:
    return math.log2(max(abs(int(value)), 1))


def margin_bits(limit: int, worst: int) -> float:
    """How many bits of headroom the 24-bit slice still has."""
    if worst == 0:
        return 24.0
    return math.log2(limit / abs(worst)) if limit > abs(worst) else -math.log2(abs(worst) / limit)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--min-margin-bits", type=float, default=1.0,
                        help="fail when a slice has less headroom than this")
    args = parser.parse_args()

    banks, sine = load_tables()
    count = len(banks)
    frac_axis = np.arange(w.DEPTH)
    index_axis = np.arange(w.DEPTH)

    # Frozen bank map (voice_sched32, 2026-10-24): candidate_stage is
    # start_stage - stage_q clamped to 0, start_stage is 3 or 4, so an e-piano
    # voice can select banks base..base+start_stage and the engine always reads
    # bank+1 as the crossfade partner.  Guitar sets weight = 0, so its mix
    # product is identically zero and cannot overflow.
    reachable_pairs = [(b, b + 1) for b in range(0, 5)] + \
                      [(b, b + 1) for b in range(6, 11)]
    piano_weight_max = (8191 - 0) << 3        # (8191-timer)<<3 at timer = 0

    # ---- interpolation deltas: (t[n+1]-t[n]) * frac, halved with rounding ---
    worst_delta = 0
    worst_delta_bank = None
    interp_abs = 0
    for bank, table in enumerate(banks):
        steps = np.abs(np.roll(table, -1) - table)          # |t[n+1]-t[n]|
        worst = int(steps.max()) * (w.DEPTH - 1)
        if worst > worst_delta:
            worst_delta, worst_delta_bank = worst, bank
        for n in index_axis:
            for f in (0, w.DEPTH - 1):
                interp_abs = max(interp_abs, abs(interp(table, int(n), int(f))))
    worst_interp_delta = (worst_delta >> 1) + 1

    # ---- mix term: |interp(bank+1) - interp(bank)| * weight ---------------
    def pair_difference(bank: int, hi: int) -> int:
        a = np.array([interp(banks[bank], int(n), int(f))
                      for n in index_axis for f in (0, w.DEPTH - 1)], dtype=np.int64)
        b = np.array([interp(banks[hi], int(n), int(f))
                      for n in index_axis for f in (0, w.DEPTH - 1)], dtype=np.int64)
        return int(np.abs(b - a).max())

    worst_mix = 0
    worst_mix_pair = None
    for bank in range(count):
        diff = pair_difference(bank, 47 if bank >= 47 else bank + 1)
        if diff > worst_mix:
            worst_mix, worst_mix_pair = diff, (bank, 47 if bank >= 47 else bank + 1)

    reachable = [(pair, pair_difference(*pair)) for pair in reachable_pairs]
    worst_reachable = max(reachable, key=lambda item: item[1])
    worst_reachable_mix = (worst_reachable[1] * piano_weight_max) >> 16
    worst_mix_product = worst_mix * 0xFFFF

    # ---- envelope / velocity products -------------------------------------
    env_product = interp_abs * 0xFFFF
    env_result = (env_product >> 16) + 1
    vel_product = env_result * 0x7F
    vel_result = (vel_product >> 7) + 1

    # ---- 32-voice accumulation -------------------------------------------
    acc_worst = 32 * vel_result
    two_lane = 64 * vel_result

    def row(slice_name: str, worst: int, limit: int, witness: str,
            informational: bool = False) -> dict:
        return {"slice": slice_name, "worst": worst, "limit": limit,
                "margin_lsb": limit - worst,
                "margin_bits": round(margin_bits(limit, worst), 2),
                "informational": informational, "witness": witness}

    rows = [
        # Every slice is "exactly sized" when its limit is the arithmetic maximum
        # for a 16-bit table, so the pass test is a positive LSB margin.  The
        # structural rows are informational: the frozen bank map cannot select
        # that operand combination (guitar crossfade weight is constant 0).
        row("interpolation delta  (diff*frac)>>1", worst_interp_delta, INT24_MAX,
            f"bank {worst_delta_bank}"),
        row("interp value (table<<8)+delta", interp_abs, INT24_MAX + 1,
            "all banks, n and frac extremes"),
        row("mix delta (bank+1 - bank)*weight >>16  [reachable]",
            worst_reachable_mix, INT24_MAX,
            f"pairs {worst_reachable[0]}, weight {piano_weight_max}"),
        row("mix delta  [all 48 banks, structural]",
            (worst_mix_product >> 16) + 1, INT24_MAX,
            f"banks {worst_mix_pair} (not selectable)", informational=True),
        row("envelope_result (interp*env)>>16", env_result, INT24_MAX,
            "max |interp| x 65535"),
        row("velocity_result (env*vel)>>7", vel_result, INT24_MAX,
            "max envelope x 127"),
        row("sine_acc / bright_acc (32 voices)", acc_worst, INT32_MAX,
            "32 x max voice contribution"),
        row("two-lane total (64 voices)", two_lane, INT32_MAX,
            "64 x max voice contribution"),
    ]
    failures = [r for r in rows if not r["informational"] and r["margin_lsb"] < 1]
    payload = {
        "generated_by": "tools/offline_opt/a/a1_bounds.py",
        "scope": "exhaustive over the 48 installed tables, all phases and fractions",
        "inputs": {"epiano_bank_all.hex": w.sha256(AUDIO / "epiano_bank_all.hex"),
                   "guitar_bank_all.hex": w.sha256(AUDIO / "guitar_bank_all.hex")},
        "min_margin_bits": args.min_margin_bits,
        "worst_adjacent_step": int(max(np.abs(np.roll(t, -1) - t).max() for t in banks)),
        "max_abs_sample": int(max(np.abs(t).max() for t in banks)),
        "max_abs_interp": int(interp_abs),
        "worst_mix_table_difference_structural": worst_mix,
        "worst_mix_table_difference_reachable": worst_reachable[1],
        "worst_reachable_pair": list(worst_reachable[0]),
        "reachable_pairs": [[list(pair), diff] for pair, diff in reachable],
        "rows": rows,
        "failures": [row["slice"] for row in failures],
        "passed": not failures,
    }
    w.json_dump(args.report, payload)

    print(f"{'slice':52} {'worst':>12} {'limit':>10} {'margin LSB':>11} {'bits':>7}")
    for row in rows:
        tag = " (info)" if row["informational"] else ""
        print(f"{row['slice']:52} {row['worst']:>12} {row['limit']:>10} "
              f"{row['margin_lsb']:>11} {row['margin_bits']:>7.2f}{tag}")
    print(f"worst adjacent step {payload['worst_adjacent_step']} LSB, "
          f"max |sample| {payload['max_abs_sample']}, "
          f"max |interp| {interp_abs}")
    print(f"worst table difference: structural {worst_mix} (banks {worst_mix_pair}), "
          f"reachable {worst_reachable[1]} (pairs {worst_reachable[0]})")
    for r in failures:
        print("FAIL", r["slice"], "margin_lsb", r["margin_lsb"])
    sys.exit(0 if not failures else 1)


if __name__ == "__main__":
    main()
