#!/usr/bin/env python3
"""Generate and validate the two 512-entry audio wavetable images.

The sine table is kept as the v1.0.0 baseline.  The second table is a bounded
16-harmonic bright timbre for C4--C5 (the highest partial is still below the
48 kHz Nyquist limit).  This script writes signed 16-bit two's-complement hex
words and checks depth, range, peak and SHA-256 so a ROM image is reproducible.
"""

from __future__ import annotations

import argparse
import hashlib
import math
from pathlib import Path


DEPTH = 512
BITS = 16
MAX_POS = (1 << (BITS - 1)) - 1
MIN_NEG = -(1 << (BITS - 1))


def q16(value: float) -> int:
    # Use round-half-up for a platform-independent integer conversion.
    sample = math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)
    return max(MIN_NEG, min(MAX_POS, sample))


def render_sine() -> list[int]:
    return [q16(MAX_POS * math.sin(2.0 * math.pi * i / DEPTH)) for i in range(DEPTH)]


def render_bright(harmonics: int = 16) -> list[int]:
    # A normalized 1/k additive series keeps every entry bounded while making
    # the higher partials explicit.  C5*16=8.37 kHz < 23.4375 kHz Nyquist.
    norm = sum(1.0 / k for k in range(1, harmonics + 1))
    raw: list[float] = []
    for i in range(DEPTH):
        phase = 2.0 * math.pi * i / DEPTH
        value = sum(math.sin(k * phase) / k for k in range(1, harmonics + 1)) / norm
        raw.append(value)
    peak = max(abs(value) for value in raw)
    return [q16(MAX_POS * value / peak) for value in raw]


def write_hex(path: Path, samples: list[int]) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = "".join(f"{sample & 0xffff:04X}\n" for sample in samples)
    path.write_text(payload, encoding="ascii", newline="\n")
    return hashlib.sha256(payload.encode("ascii")).hexdigest()


def read_hex(path: Path) -> list[int]:
    words = [line.strip() for line in path.read_text(encoding="ascii").splitlines() if line.strip()]
    if len(words) != DEPTH:
        raise ValueError(f"{path}: expected {DEPTH} words, found {len(words)}")
    samples = []
    for word in words:
        if len(word) != 4:
            raise ValueError(f"{path}: malformed word {word!r}")
        raw = int(word, 16)
        samples.append(raw - (1 << BITS) if raw & (1 << (BITS - 1)) else raw)
    return samples


def validate(path: Path, samples: list[int], digest: str) -> None:
    if len(samples) != DEPTH:
        raise ValueError(f"{path}: wrong depth")
    if min(samples) < MIN_NEG or max(samples) > MAX_POS:
        raise ValueError(f"{path}: sample outside signed 16-bit range")
    print(f"{path}: depth={len(samples)} min={min(samples)} max={max(samples)} sha256={digest}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sine", type=Path, default=Path("source/rtl/audio/wave_sine.hex"))
    parser.add_argument("--bright", type=Path, default=Path("source/rtl/audio/wave_bright.hex"))
    parser.add_argument("--harmonics", type=int, default=16)
    args = parser.parse_args()

    sine = read_hex(args.sine)
    sine_payload = args.sine.read_bytes()
    validate(args.sine, sine, hashlib.sha256(sine_payload).hexdigest())

    bright = render_bright(args.harmonics)
    digest = write_hex(args.bright, bright)
    validate(args.bright, bright, digest)


if __name__ == "__main__":
    main()
