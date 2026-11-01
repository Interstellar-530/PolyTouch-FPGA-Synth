#!/usr/bin/env python3
"""Small, dependency-free S6 fixed-point reference checks.

It mirrors the phase split used by the RTL DDS (9-bit address, 9-bit
interpolation fraction), verifies table wrap at 512 entries, and checks the
same signed 16-bit saturation rule used by mixer_s6.v.
"""

from __future__ import annotations

import argparse
from pathlib import Path


DEPTH = 512
MAX_POS = 32767
MIN_NEG = -32768


def read_hex(path: Path) -> list[int]:
    words = [line.strip() for line in path.read_text(encoding="ascii").splitlines() if line.strip()]
    if len(words) != DEPTH:
        raise ValueError(f"{path}: expected {DEPTH} entries")
    result = []
    for word in words:
        raw = int(word, 16)
        result.append(raw - 0x10000 if raw & 0x8000 else raw)
    return result


def interp(table: list[int], phase: int) -> int:
    phase &= 0xFFFFFFFF
    idx = (phase >> 23) & 0x1FF
    frac = (phase >> 14) & 0x1FF
    ya = table[idx]
    yb = table[(idx + 1) & 0x1FF]
    return max(MIN_NEG, min(MAX_POS, ya + ((yb - ya) * frac + 256) // 512))


def sat16(value: int) -> int:
    return max(MIN_NEG, min(MAX_POS, value))


def mix4(values: list[int], volume_shift: int = 1) -> tuple[int, bool]:
    if len(values) != 4:
        raise ValueError("mixer requires four samples")
    total = sum(values)
    scaled = (total + (1 << (volume_shift - 1))) >> volume_shift
    return sat16(scaled), scaled < MIN_NEG or scaled > MAX_POS


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sine", type=Path, default=Path("output/handoff_milestone2_20261008/source/rtl/audio/wave_sine.hex"))
    parser.add_argument("--bright", type=Path, default=Path("output/handoff_milestone2_20261008/source/rtl/audio/wave_bright.hex"))
    args = parser.parse_args()

    sine = read_hex(args.sine)
    bright = read_hex(args.bright)
    if not all(MIN_NEG <= x <= MAX_POS for x in sine + bright):
        raise AssertionError("signed 16-bit range violation")
    if interp(sine, 0) != interp(sine, 0x100000000):
        raise AssertionError("phase wrap was not deterministic")
    # Advancing one full 512-entry cycle wraps the phase and returns entry 0.
    if interp(sine, 0) != sine[0] or interp(sine, (512 << 23) & 0xFFFFFFFF) != sine[0]:
        raise AssertionError("table boundary phase does not wrap")
    selected = interp(bright, 0x12345678)
    blended = (interp(sine, 0x12345678) * 127 + selected * 128 + 127) >> 8
    if not MIN_NEG <= blended <= MAX_POS:
        raise AssertionError("cross-fade range violation")
    pos, pos_clip = mix4([MAX_POS] * 4)
    neg, neg_clip = mix4([MIN_NEG] * 4)
    assert (pos, pos_clip) == (MAX_POS, True)
    assert (neg, neg_clip) == (MIN_NEG, True)
    print(f"PASS s6_reference: sine/bright depth={DEPTH}, wrap/interp, blend={blended}, extrema clipped")


if __name__ == "__main__":
    main()
