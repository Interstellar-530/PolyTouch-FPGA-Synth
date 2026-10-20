#!/usr/bin/env python3
"""Create a dependency-free SVG comparison of the five C4 guitar variants."""
from pathlib import Path
import json
import math

import numpy as np

REPO = Path(r"D:\NanjingUniversity\FPGA\PolyTouch-FPGA-Synth")
OUT = Path(r"D:\NanjingUniversity\FPGA\PolyTouch-FPGA-Synth-20261020-guitar-previews-v0.1")
HEX = REPO / "output/handoff_milestone2_20261008/source/rtl/audio/guitar_bank_all.hex"
META = REPO / "output/handoff_milestone2_20261008/source/rtl/audio/guitar_bank_meta.json"
METRICS = OUT / "evidence" / "preview_metrics.json"

BANKS = [12, 13, 14, 16, 17]
NAMES = ["green/p", "green/mf", "green/f", "black/mf", "black/f"]
VELOCITIES = [20, 48, 80, 100, 120]
COLORS = ["#6cc070", "#46a86a", "#2d8f5a", "#d08a4a", "#e05a4a"]


def load_tables():
    words = [int(token, 16) for token in HEX.read_text(encoding="ascii").split()]
    values = np.asarray(words, dtype=np.int32)
    values = np.where(values >= 32768, values - 65536, values)
    return values.reshape(36, 512).astype(float)


def polyline(values, x, y, width, height, color):
    values = np.asarray(values, dtype=float)
    peak = max(float(np.max(np.abs(values))), 1e-9)
    xs = x + np.arange(len(values)) * width / (len(values) - 1)
    ys = y + height / 2.0 - values / peak * (height * 0.42)
    points = " ".join(f"{a:.1f},{b:.1f}" for a, b in zip(xs, ys))
    return f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="1.6" stroke-linejoin="round"/>'


def spectrum_bars(table, x, y, width, height, color):
    spectrum = np.abs(np.fft.rfft(table))
    spectrum[0] = 0.0
    bins = spectrum[1:41]
    peak = max(float(np.max(bins)), 1e-9)
    normalized = np.sqrt(bins / peak)
    gap = 2.0
    bar_width = (width - gap * (len(bins) - 1)) / len(bins)
    parts = []
    for i, value in enumerate(normalized):
        h = max(1.0, float(value) * height)
        bx = x + i * (bar_width + gap)
        by = y + height - h
        parts.append(f'<rect x="{bx:.1f}" y="{by:.1f}" width="{bar_width:.1f}" height="{h:.1f}" rx="1.2" fill="{color}" opacity="0.88"/>')
    return "".join(parts)


def main():
    tables = load_tables()
    meta = json.loads(META.read_text(encoding="utf-8"))["entries"]
    metrics = json.loads(METRICS.read_text(encoding="utf-8"))["clips"]
    by_name = {clip.get("variant_name"): clip for clip in metrics if clip.get("variant_name")}
    width, row_h, top = 1200, 148, 112
    height = top + row_h * len(BANKS) + 72
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#0d1117"/>',
        '<text x="30" y="42" fill="#f0f6fc" font-family="Segoe UI, Microsoft YaHei, sans-serif" font-size="26" font-weight="600">PolyTouch Guitar Timbre Preview</text>',
        '<text x="30" y="70" fill="#8b949e" font-family="Segoe UI, Microsoft YaHei, sans-serif" font-size="14">C4 single note, 46.875 kHz FPGA tables, guitar ADSR, peak normalized to -3 dBFS</text>',
        '<text x="30" y="94" fill="#8b949e" font-family="Segoe UI, Microsoft YaHei, sans-serif" font-size="12">Left: one 512-point period waveform. Right: first 40 harmonic bins. Labels show velocity, bank, spectral centroid and source harmonics.</text>',
    ]
    for index, (bank, name, velocity, color) in enumerate(zip(BANKS, NAMES, VELOCITIES, COLORS)):
        y = top + index * row_h
        clip = by_name.get(name, {})
        entry = meta[bank]
        centroid = clip.get("spectral_centroid_hz", 0.0)
        parts += [
            f'<rect x="20" y="{y - 8}" width="{width - 40}" height="{row_h - 12}" rx="10" fill="#161b22" stroke="#30363d"/>',
            f'<text x="38" y="{y + 18}" fill="{color}" font-family="Segoe UI, Microsoft YaHei, sans-serif" font-size="18" font-weight="600">{name}</text>',
            f'<text x="38" y="{y + 38}" fill="#8b949e" font-family="Segoe UI, Microsoft YaHei, sans-serif" font-size="12">velocity {velocity} | bank {bank} | centroid {centroid:.1f} Hz | source harmonics {entry["harmonics_used"]}</text>',
            f'<rect x="38" y="{y + 48}" width="500" height="76" rx="6" fill="#0b0f14" stroke="#21262d"/>',
            f'<rect x="568" y="{y + 48}" width="594" height="76" rx="6" fill="#0b0f14" stroke="#21262d"/>',
            polyline(tables[bank], 38, y + 48, 500, 76, color),
            spectrum_bars(tables[bank], 568, y + 48, 594, 76, color),
        ]
    parts += [
        f'<text x="30" y="{height - 32}" fill="#6e7681" font-family="Segoe UI, Microsoft YaHei, sans-serif" font-size="12">Source: Karoryfer Black And Green Guitars (CC0). Tables contain one steady period; pluck transient and cabinet are intentionally absent.</text>',
        '</svg>',
    ]
    (OUT / "guitar_timbre_comparison.svg").write_text("\n".join(parts) + "\n", encoding="utf-8")
    print(OUT / "guitar_timbre_comparison.svg")


if __name__ == "__main__":
    main()