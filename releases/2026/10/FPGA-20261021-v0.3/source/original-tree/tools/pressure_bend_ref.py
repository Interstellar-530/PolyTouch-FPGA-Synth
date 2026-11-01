#!/usr/bin/env python3
"""Bit-exact S5 pressure/bend reference model.

The model intentionally uses integer operations matching ``pressure_bend.v``:
three-sample median, ``y += (median - y) >> 1``, Q8 semitone bend and Q16
piecewise linear pitch ratios.  It serves three purposes:

* a reviewable statement of the algorithm,
* a deterministic vector generator (``--vectors DIR``) so the HDL testbench can
  compare every pressure tick and every one of the 4096 ADC codes instead of a
  handful of hand written points,
* a self test (``--self-test``) that reports the 90 percent step response and
  tuning error across all 4096 ADC codes. Default-center tuning uses 32 ADC
  intervals; the original five anchors remain the nondefault-center fallback.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from typing import Dict, Iterable, List, Sequence, Tuple

ADC_MAX = 4095
ADC_CENTER = 2048
BEND_Q8_MAX = 512  # two semitones, Q8 semitones
RATIO_Q16 = (58400, 61858, 65536, 69402, 73530)
BEND_SEMITONES = (-2, -1, 0, 1, 2)

# Vector file sizes; mirrored by the testbench arrays.
PRESSURE_VECTORS = 640
BEND_VECTORS = ADC_MAX + 1
PHASE_BASE = 1_000_000


def clamp_adc(value: int) -> int:
    return max(0, min(ADC_MAX, int(value)))


def median3(a: int, b: int, c: int) -> int:
    return sorted((a, b, c))[1]


def pressure_filter(samples: Iterable[int], initial: int = 0, clamp: bool = True) -> List[int]:
    """Return one filtered value per control tick.

    ``d0`` and ``d1`` are the two previous ADC samples, as in the RTL.  With
    ``clamp`` the result is bounded to the 12-bit ADC range exactly like the
    hardware; without it the raw recurrence is returned so the caller can show
    whether the clamp ever has to act.
    """

    d0 = clamp_adc(initial)
    d1 = clamp_adc(initial)
    y = clamp_adc(initial)
    result: List[int] = []
    for raw in samples:
        x = clamp_adc(raw)
        m = median3(d0, d1, x)
        y += (m - y) >> 1
        if clamp:
            y = clamp_adc(y)
        d1, d0 = d0, x
        result.append(y)
    return result


def bend_q8(adc: int) -> int:
    """Map 0..4095 to -512..+512 Q8 semitones.

    Both half ranges floor the magnitude with their exact integer denominators,
    which is what Verilog's unsigned division does: the RTL computes
    (x-center)*512/pos_den and (center-x)*512/neg_den and negates the second
    result, so a negative side value must not be rounded away from zero.  With
    that rule 0, 2048 and 4095 map to -2, 0 and +2 semitones exactly.
    """

    x = clamp_adc(adc)
    pos_den = (ADC_MAX - ADC_CENTER) if ADC_MAX > ADC_CENTER else 1
    neg_den = ADC_CENTER if ADC_CENTER > 0 else 1
    if x >= ADC_CENTER:
        return ((x - ADC_CENTER) * BEND_Q8_MAX) // pos_den
    return -((ADC_CENTER - x) * BEND_Q8_MAX // neg_den)


def bend_ratio_q16(q8: int) -> int:
    """Interpolate the five fixed Q16 semitone anchors used by the RTL."""

    q = max(-BEND_Q8_MAX, min(BEND_Q8_MAX, int(q8)))
    u = q + BEND_Q8_MAX
    if u >= 2 * BEND_Q8_MAX:
        return RATIO_Q16[-1]
    segment, fraction = divmod(u, 256)
    a, b = RATIO_Q16[segment], RATIO_Q16[segment + 1]
    return a + ((b - a) * fraction >> 8)


def phase_inc(base_phase_inc: int, bend_adc_value: int) -> int:
    """Apply the bend ratio to a 32-bit DDS increment with Q16 truncation."""

    base = max(0, min(0xFFFFFFFF, int(base_phase_inc)))
    return ((base * fine_ratio_from_adc(bend_adc_value)) >> 16) & 0xFFFFFFFF


def fine_ratio_from_adc(adc: int) -> int:
    """32 ADC intervals, rounded Q16 anchors and nearest interpolation."""
    x = clamp_adc(adc)
    segment, fraction = divmod(x, 128)
    def anchor(code: int) -> int:
        semi = 2 * (code - 2048) / (2047 if code >= 2048 else 2048)
        return round(65536 * 2 ** (semi / 12))
    a, b = anchor(segment*128), anchor((segment+1)*128)
    return a + ((b-a)*fraction + 64 >> 7)


def ratio_deviations() -> List[Dict[str, float]]:
    """Report legacy fallback anchor errors, not the default fine mapping."""

    report = []
    for semitone, value in zip(BEND_SEMITONES, RATIO_Q16):
        exact = 2 ** (semitone / 12.0) * 65536.0
        report.append({
            "semitone": semitone,
            "ratio_q16": value,
            "exact_q16": round(exact, 3),
            "rounded_q16": round(exact),
            "deviation_cents": round(1200.0 * math.log2(value / exact), 3),
        })
    return report


def fine_accuracy() -> dict:
    errors = []
    for adc in range(4096):
        semi = 2 * (adc - 2048) / (2047 if adc >= 2048 else 2048)
        errors.append(1200 * math.log2(fine_ratio_from_adc(adc) / 65536) - 100 * semi)
    worst = max(range(4096), key=lambda adc: abs(errors[adc]))
    assert abs(errors[worst]) < 0.04
    return dict(max_abs_cents=abs(errors[worst]), worst_adc=worst)


def build_pressure_sequence() -> List[int]:
    """Deterministic pressure ADC sequence: step, ramp, spikes, pseudo random."""

    seq: List[int] = [0] * 8
    seq += [ADC_MAX] * 24                       # full scale step up
    seq += [0] * 24                             # full scale step down
    seq += list(range(0, ADC_MAX + 1, 32))      # 128 tick ramp
    seq += [ADC_CENTER] * 16
    for i in range(24):                         # isolated spikes on a settled value
        seq.append(ADC_MAX if i % 8 == 3 else (0 if i % 8 == 5 else ADC_CENTER))
    lfsr = 0x1234
    while len(seq) < PRESSURE_VECTORS:          # fixed seed pseudo random tail
        bit = ((lfsr >> 11) ^ (lfsr >> 9) ^ (lfsr >> 8)) & 1
        lfsr = ((lfsr << 1) | bit) & 0xFFF
        seq.append(lfsr)
    return seq[:PRESSURE_VECTORS]


def write_vectors(directory: str) -> Dict[str, object]:
    """Write the hex vectors consumed by tb_pressure_bend.v."""

    os.makedirs(directory, exist_ok=True)
    sequence = build_pressure_sequence()
    filtered = pressure_filter(sequence)
    unclamped = pressure_filter(sequence, clamp=False)
    clamp_events = sum(1 for value in unclamped if value < 0 or value > ADC_MAX)

    files: Dict[str, List[str]] = {
        "pressure_inputs.hex": ["%03x" % value for value in sequence],
        "pressure_expected.hex": ["%03x" % value for value in filtered],
        "bend_q8_expected.hex": ["%04x" % (bend_q8(x) & 0xFFFF) for x in range(BEND_VECTORS)],
        "bend_ratio_expected.hex": ["%05x" % fine_ratio_from_adc(x) for x in range(BEND_VECTORS)],
        "bend_phase_expected.hex": ["%08x" % phase_inc(PHASE_BASE, x) for x in range(BEND_VECTORS)],
    }
    digests: Dict[str, str] = {}
    for name, lines in files.items():
        payload = "\n".join(lines) + "\n"
        path = os.path.join(directory, name)
        with open(path, "w", encoding="ascii", newline="\n") as handle:
            handle.write(payload)
        digests[name] = hashlib.sha256(payload.encode("ascii")).hexdigest()

    t90, trace = step_response_90()
    meta = {
        "adc_max": ADC_MAX,
        "adc_center": ADC_CENTER,
        "bend_q8_max": BEND_Q8_MAX,
        "ratio_mode": "adc_32_segment_q16",
        "fine_accuracy": fine_accuracy(),
        "legacy_ratio_q16": list(RATIO_Q16),
        "legacy_ratio_deviations": ratio_deviations(),
        "phase_base": PHASE_BASE,
        "pressure_vectors": len(sequence),
        "bend_vectors": BEND_VECTORS,
        "pressure_step_t90_ticks": t90,
        "pressure_clamp_events": clamp_events,
        "pressure_filtered_min": min(filtered),
        "pressure_filtered_max": max(filtered),
        "vector_sha256": digests,
    }
    with open(os.path.join(directory, "meta.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(meta, handle, indent=2, sort_keys=True)
        handle.write("\n")
    return meta


def step_response_90(initial: int = 0, step: int = ADC_MAX) -> Tuple[int, List[int]]:
    """Return the first tick at >=90 percent and the complete deterministic trace."""

    target = (ADC_MAX * 9 + 9) // 10
    trace = pressure_filter([initial] * 3 + [step] * 32, initial=initial)
    high_start = 3
    for index, value in enumerate(trace[high_start:], start=1):
        if value >= target:
            return index, trace
    raise AssertionError("IIR step did not reach 90 percent")


def self_test() -> dict:
    """Run deterministic edge, monotonicity and spike checks."""

    assert pressure_filter([0, ADC_MAX, 0]) == [0, 0, 0]
    ramp = pressure_filter(range(0, ADC_MAX + 1, 17))
    assert all(0 <= x <= ADC_MAX for x in ramp)
    assert all(a <= b for a, b in zip(ramp, ramp[1:]))
    assert [bend_q8(x) for x in (0, ADC_CENTER, ADC_MAX)] == [-512, 0, 512]
    mapped = [bend_q8(x) for x in range(0, ADC_MAX + 1, 31)]
    assert all(a <= b for a, b in zip(mapped, mapped[1:]))
    ratios = [fine_ratio_from_adc(x) for x in range(4096)]
    assert all(a <= b for a, b in zip(ratios, ratios[1:]))
    assert phase_inc(PHASE_BASE, 0) < phase_inc(PHASE_BASE, ADC_CENTER)
    assert phase_inc(PHASE_BASE, ADC_CENTER) < phase_inc(PHASE_BASE, ADC_MAX)
    t90, trace = step_response_90()
    assert t90 == 5
    return {
        "pressure_step_t90_ticks": t90,
        "pressure_step_trace": trace,
        "bend_edges_q8": {str(x): bend_q8(x) for x in (0, ADC_CENTER, ADC_MAX)},
        "phase_edges": {str(x): phase_inc(PHASE_BASE, x) for x in (0, ADC_CENTER, ADC_MAX)},
        "fine_accuracy": fine_accuracy(),
        "legacy_ratio_deviations": ratio_deviations(),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="run checks and print JSON")
    parser.add_argument("--json", metavar="PATH", help="write the self-test report to PATH")
    parser.add_argument("--vectors", metavar="DIR", help="write HDL comparison vectors to DIR")
    args = parser.parse_args()

    if args.vectors:
        meta = write_vectors(args.vectors)
        print(json.dumps(meta, indent=2, sort_keys=True))

    report = self_test()
    if args.self_test or args.json:
        payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
        if args.json:
            with open(args.json, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(payload)
        print(payload, end="")
    elif not args.vectors:
        print("pressure_bend_ref: PASS")


if __name__ == "__main__":
    main()
