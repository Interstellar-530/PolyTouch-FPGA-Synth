"""Offline modal-string piano preview, not an FPGA image."""
from pathlib import Path
import json
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'evidence/2026/10/FPGA-钢琴音色-20261018-v0.1'
FS = 48000


def note_hz(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def modal_note(note, seconds=2.2, gate_seconds=1.4, velocity=0.78):
    n = int(round(seconds * FS))
    t = np.arange(n, dtype=np.float64) / FS
    f0 = note_hz(note)
    # Mild inharmonicity; higher modes are progressively stretched.
    inharmonic = 0.00035
    phases = np.array([0.0, 0.7, 1.9, 0.3, 2.5, 1.2, 2.0, 0.4, 2.8, 1.6, 0.9, 2.2])
    amplitudes = np.array([1.0, 0.52, 0.34, 0.22, 0.14, 0.10, 0.07, 0.05, 0.035, 0.025, 0.018, 0.013])
    result = np.zeros(n, dtype=np.float64)
    for index in range(12):
        h = index + 1
        freq = h * f0 * np.sqrt(1.0 + inharmonic * h * h)
        tau = 1.9 / (1.0 + 0.26 * (h - 1))
        decay = np.exp(-t / tau)
        # Two slightly detuned strings create a small piano-like beating.
        tone = np.sin(2.0 * np.pi * freq * t + phases[index])
        tone += 0.22 * np.sin(2.0 * np.pi * freq * 1.0007 * t + phases[index] + 0.5)
        result += amplitudes[index] * decay * tone
    # Hammer noise is generated locally by the model, not a stored sample.
    rng = np.random.default_rng(0x50A10)
    noise = rng.standard_normal(n)
    noise = np.convolve(noise, np.ones(9) / 9.0, mode='same')
    result += 0.22 * noise * np.exp(-t / 0.018)
    attack = np.minimum(1.0, t / 0.006)
    release = np.ones(n)
    gate = int(gate_seconds * FS)
    release[gate:] = np.exp(-(t[gate:] - t[gate]) / 0.12)
    result *= attack * release
    result *= velocity
    result *= 0.85 / max(np.max(np.abs(result)), 1e-12)
    return result


def main():
    segments = []
    mix = np.zeros(int(12.0 * FS), dtype=np.float64)
    cursor = int(0.2 * FS)
    for label, note in [('C2', 36), ('C4', 60), ('C6', 84)]:
        values = modal_note(note)
        end = min(len(mix), cursor + len(values))
        mix[cursor:end] += values[:end - cursor]
        segments.append({'label': label, 'start_sample': cursor, 'end_sample': end,
                         'peak': float(np.max(np.abs(values)))})
        cursor = end + int(0.2 * FS)
    chord_start = cursor
    chord = np.zeros(int(2.2 * FS), dtype=np.float64)
    for note in (60, 64, 67, 72):
        chord += modal_note(note)
    end = min(len(mix), chord_start + len(chord))
    mix[chord_start:end] += chord[:end - chord_start]
    segments.append({'label': 'C major chord', 'start_sample': chord_start, 'end_sample': end,
                     'peak': float(np.max(np.abs(chord)))})
    peak = float(np.max(np.abs(mix)))
    if peak > 0.95:
        mix *= 0.92 / peak
    OUT.mkdir(parents=True, exist_ok=True)
    sf.write(OUT / 'piano-modal-preview.wav', mix, FS, subtype='PCM_16')
    meta = {
        'model': 'offline inharmonic modal strings + hammer noise',
        'sample_rate_hz': FS,
        'duration_seconds': len(mix) / FS,
        'segments': segments,
        'note': 'Prototype only; no PCM sample is embedded and no FPGA image was changed.'
    }
    (OUT / 'piano-modal-preview.json').write_text(
        json.dumps(meta, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(meta, indent=2))


if __name__ == '__main__':
    main()
