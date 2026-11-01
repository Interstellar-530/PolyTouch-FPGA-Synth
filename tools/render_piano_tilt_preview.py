"""Render original and spectral-tilt candidates from the current piano bank."""
from pathlib import Path
import json
import numpy as np
import soundfile as sf

from render_piano_test_audio import FS, load_tables, render_note

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'evidence/2026/10/FPGA-钢琴音色-20261018-v0.1'
TARGETS = {
    'original': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    'natural':  [0, -9, -15, -20, -25, -30, -35, -40, -45, -50],
    'soft':     [0, -5, -10, -15, -20, -25, -30, -35, -40, -45],
    'balanced': [0, -3, -8, -12, -16, -20, -24, -28, -32, -36],
    'bright':   [0, -1, -5, -9, -13, -17, -21, -25, -29, -33],
}


def tilted_tables(tables, target_db):
    result = []
    scale = 10.0 ** (np.asarray(target_db, dtype=float) / 20.0)
    for table in tables:
        spectrum = np.fft.rfft(table)
        spectrum[0] = 0
        spectrum[1:11] *= scale
        spectrum[11:] = 0
        wave = np.fft.irfft(spectrum, n=512)
        wave = np.rint(wave * 32767.0 / np.max(np.abs(wave)))
        result.append(wave)
    return np.asarray(result)


def add_segment(destination, start, values):
    end = start + len(values)
    destination[start:end] += values
    return end


def main():
    tables = load_tables()
    variants = {name: tilted_tables(tables, target) for name, target in TARGETS.items()}
    labels = [('original F5 C4', 'original'), ('natural F5 C4', 'natural'),
              ('soft F5 C4', 'soft'), ('balanced F5 C4', 'balanced'),
              ('bright F5 C4', 'bright')]
    order = [60, 60, 60, 60, 60]
    total = int(0.2 * FS) + sum(int((1.55 + 0.25) * FS) for _ in labels)
    total += int(2.1 * FS) + int(0.5 * FS)
    mix = np.zeros(total, dtype=np.float64)
    report = []
    cursor = int(0.2 * FS)
    for (label, name), note in zip(labels, order):
        values, stages = render_note(variants[name], note, 4, 100, 1.55, 1.2)
        end = add_segment(mix, cursor, values)
        report.append({
            'label': label,
            'tilt_db': TARGETS[name],
            'peak': float(np.max(np.abs(values))),
            'rms': float(np.sqrt(np.mean(values * values))),
            'stage_span': [int(np.min(stages)), int(np.max(stages))]
        })
        cursor = end + int(0.25 * FS)
    chord_start = cursor
    chord = np.zeros(int(2.1 * FS), dtype=np.float64)
    for note in (60, 64, 67, 72):
        values, _ = render_note(variants['balanced'], note, 4, 100, 2.1, 1.5)
        chord += values
    add_segment(mix, chord_start, chord)
    report.append({'label': 'balanced C major chord', 'notes': [60, 64, 67, 72],
                   'peak': float(np.max(np.abs(chord))),
                   'rms': float(np.sqrt(np.mean(chord * chord)))})
    # Preserve perceptual level across the short comparison segments.
    for item, (label, _) in zip(report[:-1], labels):
        start = int(item.get('start_sample', 0))
    peak = float(np.max(np.abs(mix)))
    mix *= 0.88 / peak if peak else 1.0
    OUT.mkdir(parents=True, exist_ok=True)
    wav = OUT / 'piano-tilt-preview.wav'
    sf.write(wav, mix, FS, subtype='PCM_16')
    meta = {
        'sample_rate_hz': FS,
        'duration_seconds': len(mix) / FS,
        'segments': report,
        'note': 'Normalized offline candidate audio; no FPGA or analog path involved.',
    }
    (OUT / 'piano-tilt-preview.json').write_text(
        json.dumps(meta, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(meta, indent=2))


if __name__ == '__main__':
    main()
