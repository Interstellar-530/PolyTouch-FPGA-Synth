#!/usr/bin/env python3
"""Bit-exact S5 pressure/bend reference model.

The model intentionally uses integer operations matching ``pressure_bend.v``:
three-sample median, y += (median-y) >> 1, Q8 semitone bend and Q16 piecewise
linear pitch ratios.  It is useful both as a reviewable algorithm reference and
as a deterministic data source for later co-simulation.
"""

from __future__ import annotations

import argparse
import json
from typing import Iterable, List, Sequence, Tuple

ADC_MAX = 4095
ADC_CENTER = 2048
BEND_Q8_MAX = 512  # two semitones, Q8 semitones
RATIO_Q16 = (58400, 61858, 65536, 69402, 73530)


def clamp_adc(value: int) -> int:
    return max(0, min(ADC_MAX, int(value)))


def median3(a: int, b: int, c: int) -> int:
    return sorted((a, b, c))[1]


def pressure_filter(samples: Iterable[int], initial: int = 0) -> List[int]:
    """Return one filtered value per control tick.

    ``d0`` and ``d1`` are the two previous ADC samples, as in the RTL.  All
    state and arithmetic are bounded to the 12-bit ADC range.
    """

    d0 = clamp_adc(initial)
    d1 = clamp_adc(initial)
    y = clamp_adc(initial)
    result: List[int] = []
    for raw in samples:
        x = clamp_adc(raw)
        m = median3(d0, d1, x)
        y += (m - y) >> 1
        y = clamp_adc(y)
        d1, d0 = d0, x
        result.append(y)
    return result


def bend_q8(adc: int) -> int:
    """Map 0..4095 to -512..+512 Q8 semitones.

    The two half-ranges use their exact integer denominators so 0, 2048 and
    4095 map to -2, 0 and +2 semitones respectively.
    """

    x = clamp_adc(adc)
    if x >= ADC_CENTER:
        return ((x - ADC_CENTER) * BEND_Q8_MAX) // (ADC_MAX - ADC_CENTER)
    return -((ADC_CENTER - x) * BEND_Q8_MAX) // ADC_CENTER


def bend_ratio_q16(q8: int) -> int:
    """Interpolate the five fixed Q16 semitone ratios used by the RTL."""

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
    return (base * bend_ratio_q16(bend_q8(bend_adc_value))) >> 16


def step_response_90(initial: int = 0, step: int = ADC_MAX) -> Tuple[int, List[int]]:
    """Return the first tick at >=90% and the complete deterministic trace."""

    target = (ADC_MAX * 9 + 9) // 10
    trace = pressure_filter([initial] * 3 + [step] * 32, initial=initial)
    # Count from the first high input tick, matching the report in the HDL TB.
    high_start = 3
    for i, value in enumerate(trace[high_start:], start=1):
        if value >= target:
            return i, trace
    raise AssertionError("IIR step did not reach 90 percent")


def self_test() -> dict:
    """Run deterministic edge, monotonicity and spike checks."""

    assert pressure_filter([0, ADC_MAX, 0]) == [0, 0, 0]
    ramp = pressure_filter(range(0, ADC_MAX + 1, 17))
    assert all(0 <= x <= ADC_MAX for x in ramp)
    # The filtered ramp is nondecreasing even though the raw ramp is sampled
    # through a median window.
    assert all(a <= b for a, b in zip(ramp, ramp[1:]))
    assert [bend_q8(x) for x in (0, ADC_CENTER, ADC_MAX)] == [-512, 0, 512]
    mapped = [bend_q8(x) for x in range(0, ADC_MAX + 1, 31)]
    assert all(a <= b for a, b in zip(mapped, mapped[1:]))
    ratios = [bend_ratio_q16(q) for q in range(-512, 513, 17)]
    assert all(a <= b for a, b in zip(ratios, ratios[1:]))
    assert phase_inc(1_000_000, 0) < phase_inc(1_000_000, ADC_CENTER)
    assert phase_inc(1_000_000, ADC_CENTER) < phase_inc(1_000_000, ADC_MAX)
    t90, trace = step_response_90()
    assert t90 == 5
    return {
        "pressure_step_t90_ticks": t90,
        "pressure_step_trace": trace,
        "bend_edges_q8": {str(x): bend_q8(x) for x in (0, ADC_CENTER, ADC_MAX)},
        "phase_edges": {str(x): phase_inc(1_000_000, x) for x in (0, ADC_CENTER, ADC_MAX)},
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true", help="run checks and print JSON")
    parser.add_argument("--json", metavar="PATH", help="write the self-test report to PATH")
    args = parser.parse_args()
    report = self_test()
    if args.self_test or args.json:
        payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
        if args.json:
            with open(args.json, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(payload)
        print(payload, end="")
    else:
        print("pressure_bend_ref: PASS")


if __name__ == "__main__":
    main()

