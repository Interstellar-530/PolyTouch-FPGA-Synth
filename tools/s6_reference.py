#!/usr/bin/env python3
"""Bit-exact S6 fixed-point reference and HDL vector generator.

The model mirrors the RTL integer operations: 9-bit address and 9-bit
interpolation fraction with 512-entry wrap, the (255-w, w) >> 8 cross-fade,
the four-voice sum with master-gain rounding and signed 16-bit saturation, the
clip statistic taken at the master-gain boundary, and the five-tap
(1,4,6,4,1)/16 smoother selected by FIR_ENABLE.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path

DEPTH = 512
MAX_POS = 32767
MIN_NEG = -32768
FIR_TAPS = (1, 4, 6, 4, 1)
FIR_SHIFT = 4
SINE_DEFAULT = Path("source/rtl/audio/wave_sine.hex")
BRIGHT_DEFAULT = Path("source/rtl/audio/wave_bright.hex")

# Vector sizes, mirrored by the testbench arrays.
OSC_ADDRS = 512
# 2 and 4 are the smallest fractions that hit the rounding tie condition
# (diff * frac) mod 512 == 256, so the +256 rounding constant is exercised.
OSC_FRACS = (0, 1, 2, 4, 127, 255, 511)
BLEND_PAIRS = ((32767, -32768), (1000, -1000), (-32768, 32767))
MIX_SHIFTS = (0, 1, 2)


def read_hex(path: Path) -> list[int]:
    words = [line.strip() for line in path.read_text(encoding="ascii").splitlines() if line.strip()]
    if len(words) != DEPTH:
        raise ValueError(f"{path}: expected {DEPTH} entries")
    result = []
    for word in words:
        raw = int(word, 16)
        result.append(raw - 0x10000 if raw & 0x8000 else raw)
    return result


def sat16(value: int) -> int:
    return max(MIN_NEG, min(MAX_POS, value))


def interp(table: list[int], phase: int) -> int:
    phase &= 0xFFFFFFFF
    idx = (phase >> 23) & 0x1FF
    frac = (phase >> 14) & 0x1FF
    ya = table[idx]
    yb = table[(idx + 1) & 0x1FF]
    return sat16(ya + (((yb - ya) * frac + 256) >> 9))


def blend(a: int, b: int, weight: int) -> int:
    """(255-w, w) >> 8 cross-fade exactly as wavetable_rom_dual.v computes it.

    The weights sum to 255 rather than 256, so a fade endpoint sits 1/256
    (about 128 LSB at full scale) below the pure table value; the deviation is
    measured in the review record instead of being silently "fixed" here.
    """
    return sat16((a * (0xFF - weight) + b * weight + 127) >> 8)


def mix4(values: list[int], volume_shift: int = 1, fir_enable: int = 1,
         history: list[int] | None = None) -> tuple[int, bool, bool, list[int]]:
    """Return (sample_out, raw_clip, fir_clip, new_history)."""
    if len(values) != 4:
        raise ValueError("mixer requires four samples")
    total = sum(values)
    bias = 0 if volume_shift == 0 else (1 << (volume_shift - 1))
    scaled = (total + bias) >> volume_shift
    raw_clip = scaled < MIN_NEG or scaled > MAX_POS
    sat_raw = sat16(scaled)
    if history is None:
        history = [0, 0, 0, 0]
    taps = [sat_raw] + list(history[:4])
    fir_sum = sum(t * h for t, h in zip(FIR_TAPS, taps))
    fir_value = fir_sum >> FIR_SHIFT
    fir_clip = fir_value < MIN_NEG or fir_value > MAX_POS
    sat_fir = sat16(fir_value)
    out = sat_fir if fir_enable else sat_raw
    return out, raw_clip, fir_clip, [sat_raw] + list(history[:3])


def fir_response_db(freq: float, fs: float) -> float:
    w = 2.0 * math.pi * freq / fs
    re = sum(t * math.cos(-w * i) for i, t in enumerate(FIR_TAPS))
    im = sum(t * math.sin(-w * i) for i, t in enumerate(FIR_TAPS))
    return 20.0 * math.log10(math.hypot(re, im) / (1 << FIR_SHIFT))


def oscillator_vectors(sine: list[int], bright: list[int]) -> list[tuple[int, int, int]]:
    vectors = []
    for addr in range(OSC_ADDRS):
        for frac in OSC_FRACS:
            phase = ((addr & 0x1FF) << 23) | ((frac & 0x1FF) << 14)
            vectors.append((phase, interp(sine, phase), interp(bright, phase)))
    return vectors


def blend_vectors() -> list[tuple[int, int, int, int]]:
    vectors = []
    for a, b in BLEND_PAIRS:
        for weight in range(256):
            vectors.append((a, b, weight, blend(a, b, weight)))
    return vectors


def mixer_vectors() -> list[tuple[list[int], int, int, int, int, int]]:
    """(voices, volume_shift, fir, expected, raw_clip, fir_clip) with FIR history replayed."""
    cases: list[list[int]] = [
        [MAX_POS] * 4, [MIN_NEG] * 4, [0, 0, 0, 0],
        [MAX_POS, MIN_NEG, MAX_POS, MIN_NEG], [MAX_POS, MAX_POS, 0, 0],
        [1, 1, 1, 1], [-1, -1, -1, -1], [3, 3, 3, 3], [1000] * 4, [-1000] * 4,
        [32767, 32766, -32768, -32767], [16384] * 4, [-16384] * 4,
        [29127] * 4, [29126] * 4, [16383, 16383, 16383, 16383],
    ]
    # rounding boundary cases around the master gain
    for pair in ((1, 0, 0, 0), (1, 1, 0, 0), (-1, 0, 0, 0), (-1, -1, 0, 0),
                 (65535 - 65536, 0, 0, 0)):
        cases.append(list(pair))
    lfsr = 0xACE1
    for _ in range(64):
        words = []
        for _ in range(4):
            bit = ((lfsr >> 13) ^ (lfsr >> 10) ^ (lfsr >> 8) ^ (lfsr >> 6)) & 1
            lfsr = ((lfsr << 1) | bit) & 0xFFFF
            words.append(lfsr - 0x8000)
        cases.append(words)
    # Every (shift, fir) instance sees the whole 510 sample driving sequence,
    # because the instances share the voice inputs in hardware.  The vectors
    # are emitted block by block; for each block the owning instance is
    # replayed over the complete sequence so its history and cumulative clip
    # count match the hardware exactly.
    order = [(shift, fir) for shift in MIX_SHIFTS for fir in (0, 1)]
    sequence = [case for _ in order for case in cases]
    block_len = len(cases)
    vectors = []
    for block_index, (shift, fir) in enumerate(order):
        history = [0, 0, 0, 0]
        count = 0
        stream = []
        for case in sequence:
            out, raw_clip, fir_clip, history = mix4(case, shift, fir, history)
            if raw_clip:
                count += 1
            stream.append((out, int(raw_clip), int(fir_clip), count))
        start = block_index * block_len
        for offset in range(block_len):
            out, raw_clip, fir_clip, count = stream[start + offset]
            vectors.append((cases[offset], shift, fir, out, raw_clip, fir_clip, count))
    return vectors


ROM_BLEND_ADDRS = (0, 1, 128, 383)
OSC_BLEND_PHASE = (200 << 23) | (255 << 14)


def rom_blend_vectors(sine: list[int], bright: list[int]) -> list[tuple[int, int, int]]:
    out = []
    for addr in ROM_BLEND_ADDRS:
        for weight in range(256):
            out.append((addr, weight, blend(sine[addr], bright[addr], weight)))
    return out


def osc_blend_vectors(sine: list[int], bright: list[int]) -> list[tuple[int, int, int]]:
    a = interp(sine, OSC_BLEND_PHASE)
    b = interp(bright, OSC_BLEND_PHASE)
    return [(OSC_BLEND_PHASE, weight, blend(a, b, weight)) for weight in range(256)]


def fir_sequence() -> tuple[list[int], list[int]]:
    """Small-amplitude step/return sequence for the FIR path (FIR_ENABLE=1)."""
    inputs = [0] * 4 + [1000] * 6 + [0] * 8 + [-1000] * 6 + [0] * 8
    expected = []
    history = [0, 0, 0, 0]
    for level in inputs:
        out, _, _, history = mix4([level, 0, 0, 0], volume_shift=0, fir_enable=1, history=history)
        expected.append(out)
    return inputs, expected


def write_vectors(directory: Path, sine: list[int], bright: list[int]) -> dict:
    directory.mkdir(parents=True, exist_ok=True)
    digest: dict[str, str] = {}

    def emit(name: str, lines: list[str]) -> None:
        payload = "\n".join(lines) + "\n"
        (directory / name).write_text(payload, encoding="ascii", newline="\n")
        digest[name] = hashlib.sha256(payload.encode("ascii")).hexdigest()

    osc = oscillator_vectors(sine, bright)
    emit("osc_phase.hex", ["%08x" % p for p, _, _ in osc])
    emit("osc_sine_expected.hex", ["%04x" % (v & 0xFFFF) for _, v, _ in osc])
    emit("osc_bright_expected.hex", ["%04x" % (v & 0xFFFF) for _, _, v in osc])

    bl = blend_vectors()
    emit("blend_a.hex", ["%04x" % (a & 0xFFFF) for a, _, _, _ in bl])
    emit("blend_b.hex", ["%04x" % (b & 0xFFFF) for _, b, _, _ in bl])
    emit("blend_weight.hex", ["%02x" % w for _, _, w, _ in bl])
    emit("blend_expected.hex", ["%04x" % (v & 0xFFFF) for _, _, _, v in bl])

    mx = mixer_vectors()
    emit("mix_v0.hex", ["%04x" % (c[0][0] & 0xFFFF) for c in mx])
    emit("mix_v1.hex", ["%04x" % (c[0][1] & 0xFFFF) for c in mx])
    emit("mix_v2.hex", ["%04x" % (c[0][2] & 0xFFFF) for c in mx])
    emit("mix_v3.hex", ["%04x" % (c[0][3] & 0xFFFF) for c in mx])
    emit("mix_shift.hex", ["%01x" % c[1] for c in mx])
    emit("mix_fir.hex", ["%01x" % c[2] for c in mx])
    emit("mix_expected.hex", ["%04x" % (c[3] & 0xFFFF) for c in mx])
    emit("mix_rawclip.hex", ["%01x" % c[4] for c in mx])
    emit("mix_firclip.hex", ["%01x" % c[5] for c in mx])
    emit("mix_count.hex", ["%02x" % (c[6] & 0xFF) for c in mx])

    rb = rom_blend_vectors(sine, bright)
    emit("rom_blend_addr.hex", ["%03x" % a for a, _, _ in rb])
    emit("rom_blend_weight.hex", ["%02x" % w for _, w, _ in rb])
    emit("rom_blend_expected.hex", ["%04x" % (v & 0xFFFF) for _, _, v in rb])

    ob = osc_blend_vectors(sine, bright)
    emit("osc_blend_phase.hex", ["%08x" % p for p, _, _ in ob])
    emit("osc_blend_weight.hex", ["%02x" % w for _, w, _ in ob])
    emit("osc_blend_expected.hex", ["%04x" % (v & 0xFFFF) for _, _, v in ob])

    fir_in, fir_exp = fir_sequence()
    emit("fir_input.hex", ["%04x" % (v & 0xFFFF) for v in fir_in])
    emit("fir_expected.hex", ["%04x" % (v & 0xFFFF) for v in fir_exp])

    meta = {
        "depth": DEPTH,
        "osc_vectors": len(osc),
        "blend_vectors": len(bl),
        "rom_blend_vectors": len(rb),
        "osc_blend_vectors": len(ob),
        "mixer_vectors": len(mx),
        "fir_vectors": len(fir_in),
        "fir_taps": list(FIR_TAPS),
        "fir_shift": FIR_SHIFT,
        "fir_dc_gain": sum(FIR_TAPS) / (1 << FIR_SHIFT),
        "fir_group_delay_samples": (len(FIR_TAPS) - 1) // 2,
        "fir_response_db_46875": {str(f): round(fir_response_db(f, 46875.0), 3)
                                 for f in (1000, 5000, 10000, 15000, 20000)},
        "fir_response_db_48000": {str(f): round(fir_response_db(f, 48000.0), 3)
                                  for f in (1000, 5000, 10000, 15000, 20000)},
        "vector_sha256": digest,
    }
    (directory / "meta.json").write_text(json.dumps(meta, indent=2, sort_keys=True) + "\n",
                                         encoding="utf-8", newline="\n")
    return meta


def self_test(sine: list[int], bright: list[int]) -> None:
    if not all(MIN_NEG <= x <= MAX_POS for x in sine + bright):
        raise AssertionError("signed 16-bit range violation")
    if interp(sine, 0) != sine[0] or interp(sine, (512 << 23) & 0xFFFFFFFF) != sine[0]:
        raise AssertionError("table boundary phase does not wrap")
    if interp(sine, 0) != interp(sine, 0x100000000):
        raise AssertionError("phase wrap was not deterministic")
    # every address must wrap into entry 0 at the seam
    for addr in range(DEPTH):
        phase = (addr << 23) | (511 << 14)
        ya = sine[addr]
        yb = sine[(addr + 1) % DEPTH]
        if interp(sine, phase) != sat16(ya + ((yb - ya) * 511 + 256 >> 9)):
            raise AssertionError(f"interpolation mismatch at {addr}")
    pos = mix4([MAX_POS] * 4, volume_shift=1, fir_enable=0)
    neg = mix4([MIN_NEG] * 4, volume_shift=1, fir_enable=0)
    assert pos[0] == MAX_POS and pos[1] is True
    assert neg[0] == MIN_NEG and neg[1] is True
    # unity gain on a small signal is the property that catches a wrong tap set
    out, raw_clip, fir_clip, _ = mix4([1000, 0, 0, 0], volume_shift=0, fir_enable=1,
                                      history=[1000, 1000, 1000, 1000])
    if out != 1000 or raw_clip or fir_clip:
        raise AssertionError(f"FIR unity gain violated: {out}")
    step_in, step_out = fir_sequence()
    # the step settles at its own level with no overshoot, and decays back to 0
    assert step_out[8] == 1000 and max(step_out) == 1000 and step_out[-1] == 0, step_out
    print(f"PASS s6_reference: sine/bright depth={DEPTH}, wrap/interp, blend, "
          f"FIR taps={FIR_TAPS} dc_gain={sum(FIR_TAPS) / (1 << FIR_SHIFT):.3f}, extrema clipped")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sine", type=Path, default=SINE_DEFAULT)
    parser.add_argument("--bright", type=Path, default=BRIGHT_DEFAULT)
    parser.add_argument("--vectors", type=Path, help="write HDL comparison vectors to this directory")
    parser.add_argument("--json", type=Path, help="write the vector metadata to this path")
    args = parser.parse_args()

    sine = read_hex(args.sine)
    bright = read_hex(args.bright)
    self_test(sine, bright)
    if args.vectors:
        meta = write_vectors(args.vectors, sine, bright)
        payload = json.dumps(meta, indent=2, sort_keys=True) + "\n"
        if args.json:
            args.json.write_text(payload, encoding="utf-8", newline="\n")
        print(payload, end="")
    elif args.json:
        args.json.write_text(json.dumps({"depth": DEPTH, "fir_taps": list(FIR_TAPS)},
                                        indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()