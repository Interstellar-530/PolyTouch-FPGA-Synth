"""Render a C6 playback-chain isolation test."""
from pathlib import Path
import json
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'evidence/2026/10/FPGA-钢琴音色-20261018-v0.1'
FS = 48000


def fit(values, peak=0.5):
    values = np.asarray(values, dtype=np.float64)
    values = values - np.mean(values)
    return values * (peak / max(float(np.max(np.abs(values))), 1e-12))


def main():
    sine_t = np.arange(int(1.0 * FS)) / FS
    sine = fit(0.6 * np.sin(2.0 * np.pi * 1000.0 * sine_t))
    raw, raw_fs = sf.read(ROOT / 'tmp/salamander-samples/C6v16.ogg', always_2d=True)
    raw = raw.mean(axis=1)
    peak = float(np.max(np.abs(raw)))
    onset = int(np.flatnonzero(np.abs(raw) > peak * 0.01)[0])
    raw = raw[onset:onset + int(1.6 * raw_fs)]
    if raw_fs != FS:
        t_old = np.arange(len(raw)) / raw_fs
        t_new = np.arange(int(len(raw) * FS / raw_fs)) / FS
        raw = np.interp(t_new, t_old, raw)
    raw = fit(raw)
    modal, fs = sf.read(OUT / 'piano-modal-safe-preview.wav')
    rep = json.loads((OUT / 'piano-modal-safe-preview.json').read_text())
    c6_seg = next(x for x in rep['segments'] if x['label'] == 'C6')
    modal = fit(modal[c6_seg['start_sample']:c6_seg['end_sample']])
    total = int(0.2 * FS + len(sine) + 0.25 * FS + len(raw) + 0.25 * FS + len(modal) + 0.3 * FS)
    mix = np.zeros(total, dtype=np.float64)
    cursor = int(0.2 * FS)
    starts = {}
    for label, values in [('1kHz sine', sine), ('raw Salamander C6', raw), ('modal safe C6', modal)]:
        starts[label] = cursor
        end = min(total, cursor + len(values))
        mix[cursor:end] += values[:end - cursor]
        cursor = end + int(0.25 * FS)
    sf.write(OUT / 'c6-isolation-test.wav', mix, FS, subtype='PCM_16')
    report = {'sample_rate_hz': FS, 'segments': []}
    for label, start in starts.items():
        values = {'1kHz sine': sine, 'raw Salamander C6': raw, 'modal safe C6': modal}[label]
        report['segments'].append({
            'label': label, 'start_sample': start, 'duration_seconds': len(values) / FS,
            'peak': float(np.max(np.abs(values))),
            'rms': float(np.sqrt(np.mean(values * values))),
            'crest': float(np.max(np.abs(values)) / np.sqrt(np.mean(values * values))),
            'clipped': int(np.sum(np.abs(values) >= 0.999)),
        })
    (OUT / 'c6-isolation-test.json').write_text(
        json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
