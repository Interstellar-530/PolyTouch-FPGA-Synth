"""Offline high-note-safe modal-string preview.

The first modal preview allowed 12 modes at every pitch. At C6 those modes
pile up at 8-12 kHz and the hammer noise remains full strength, producing a
harsh, distorted impression. This revision limits modes by pitch, tapers
upper-mode amplitude and softens the hammer noise.
"""
from pathlib import Path
import json
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/evidence/FPGA-钢琴音色-20261018-v0.1'
FS = 48000


def note_hz(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def modal_note(note, seconds=2.2, gate_seconds=1.4, velocity=0.78):
    n = int(round(seconds * FS))
    t = np.arange(n, dtype=np.float64) / FS
    f0 = note_hz(note)
    inharmonic = 0.00035
    phases = np.array([0.0, 0.7, 1.9, 0.3, 2.5, 1.2, 2.0, 0.4, 2.8, 1.6, 0.9, 2.2])
    amplitudes = np.array([1.0, 0.52, 0.34, 0.22, 0.14, 0.10, 0.07, 0.05, 0.035, 0.025, 0.018, 0.013])
    if f0 > 800.0:
        # The real C6 sample is almost a single fundamental with only a very
        # weak second partial. Do not let the generic modal profile swamp it.
        mode_limit = 2
        amplitudes[1] = 0.05
        amplitudes[2:] = 0.0
    else:
        mode_limit = int(np.clip(np.floor(7000.0 / f0), 6, 12))
    # High notes keep fewer modes and a steeper upper-mode taper.
    for index in range(mode_limit, 12):
        amplitudes[index] = 0.0
    if f0 > 700.0:
        amplitudes *= np.exp(-0.06 * np.arange(1, 13))
    result = np.zeros(n, dtype=np.float64)
    for index in range(mode_limit):
        h = index + 1
        freq = h * f0 * np.sqrt(1.0 + inharmonic * h * h)
        # The source C4/C6 samples decay much faster than the first generic
        # prototype: roughly 0.3-0.55 s for the low modes, shorter for highs.
        tau = (0.55 * np.sqrt(261.6255653 / f0)) / (1.0 + 0.25 * (h - 1))
        decay = np.exp(-t / tau)
        tone = np.sin(2.0 * np.pi * freq * t + phases[index])
        tone += 0.22 * np.sin(2.0 * np.pi * freq * 1.0007 * t + phases[index] + 0.5)
        result += amplitudes[index] * decay * tone
    rng = np.random.default_rng(0x50A10)
    noise = rng.standard_normal(n)
    kernel = np.ones(17 if f0 > 700.0 else 9)
    noise = np.convolve(noise, kernel / kernel.size, mode='same')
    noise_gain = 0.025 if f0 > 800.0 else (0.08 if f0 > 700.0 else 0.22)
    result += noise_gain * noise * np.exp(-t / 0.018)
    attack = np.minimum(1.0, t / 0.006)
    release = np.ones(n)
    gate = int(gate_seconds * FS)
    release[gate:] = np.exp(-(t[gate:] - t[gate]) / 0.12)
    result *= attack * release * velocity
    # Gentle reconstruction low-pass keeps the top mode from sounding like a hiss.
    cutoff = 6000.0 if f0 > 800.0 else 8000.0
    alpha = 1.0 - np.exp(-2.0 * np.pi * cutoff / FS)
    filtered = np.empty_like(result)
    filtered[0] = result[0]
    for i in range(1, n):
        filtered[i] = filtered[i - 1] + alpha * (result[i] - filtered[i - 1])
    result = filtered
    result *= 0.85 / max(np.max(np.abs(result)), 1e-12)
    return result


def main():
    mix = np.zeros(int(12.0 * FS), dtype=np.float64)
    cursor = int(0.2 * FS)
    segments = []
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
    sf.write(OUT / 'piano-modal-calibrated-preview.wav', mix, FS, subtype='PCM_16')
    meta = {'model': 'modal strings, pitch-limited modes, high-note taper, hammer-noise smoothing',
            'sample_rate_hz': FS, 'duration_seconds': len(mix) / FS,
            'segments': segments,
            'note': 'Offline prototype only; no FPGA image changed.'}
    (OUT / 'piano-modal-calibrated-preview.json').write_text(
        json.dumps(meta, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(meta, indent=2))


if __name__ == '__main__':
    main()
