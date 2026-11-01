"""Extract a 6-zone x 2-velocity x 6-stage piano spectrum bank.

Source: Salamander Grand Piano v3 C1-C6, soft/loud velocity samples by
Alexander Holm, CC BY 3.0. Only relative harmonic amplitudes and a common
phase profile are written; source recordings are never embedded in RTL.
"""
from pathlib import Path
import hashlib
import json
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
AUDIO = ROOT / 'source/rtl/audio'
EVIDENCE = ROOT / 'evidence/2026/10/FPGA-钢琴音色-20261018-v0.1'
SAMPLES = ROOT / 'tmp/salamander-samples'
HARMONICS = 10
NOTES = [
    ('C1', 32.7031956626),
    ('C2', 65.4063913251),
    ('C3', 130.8127826503),
    ('C4', 261.6255653006),
    ('C5', 523.2511306012),
    ('C6', 1046.5022612024),
]
STAGE_START = (1.20, 0.65, 0.35, 0.15, 0.05, 0.0)


def load(path):
    data, rate = sf.read(path, always_2d=True)
    mono = data.mean(axis=1)
    peak = float(np.max(np.abs(mono)))
    onset = int(np.flatnonzero(np.abs(mono) > peak * 0.01)[0])
    return mono[onset:], rate, onset, peak


def fit(signal, rate, start_s, length_s, f0):
    start = int(round(start_s * rate))
    count = min(int(round(length_s * rate)), len(signal) - start)
    if start < 0 or count < 32:
        return None
    x = signal[start:start + count].astype(np.float64)
    t = np.arange(count, dtype=np.float64) / rate
    taper = np.hanning(count)
    columns = [np.ones(count)]
    for h in range(1, HARMONICS + 1):
        columns.append(np.cos(2.0 * np.pi * h * f0 * t))
        columns.append(np.sin(2.0 * np.pi * h * f0 * t))
    design = np.column_stack(columns) * taper[:, None]
    coeff = np.linalg.lstsq(design, x * taper, rcond=None)[0]
    amplitudes = []
    phases = []
    for h in range(1, HARMONICS + 1):
        cosine = coeff[1 + 2 * (h - 1)]
        sine = coeff[2 + 2 * (h - 1)]
        amplitudes.append(float(np.hypot(cosine, sine)))
        phases.append(float(np.arctan2(cosine, sine)))
    amplitudes = np.asarray(amplitudes)
    amplitudes /= max(amplitudes[0], 1.0e-12)
    return amplitudes, np.asarray(phases)


def main():
    profiles = []
    source_files = []
    common_phase = None
    for zone, (name, f0) in enumerate(NOTES):
        for layer, velocity in enumerate(('1', '16')):
            path = SAMPLES / f'{name}v{velocity}.ogg'
            signal, rate, onset, peak = load(path)
            source_files.append({
                'path': path.name,
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'sample_rate_hz': rate,
                'onset_sample': onset,
                'peak': peak,
            })
            win = max(0.02, 6.0 / f0)
            stage_amplitudes = []
            for stage, start_s in enumerate(STAGE_START):
                fitted = fit(signal, rate, start_s, win, f0)
                if fitted is None:
                    fitted = fit(signal, rate, max(0.0, len(signal) / rate - win), win, f0)
                if fitted is None:
                    raise ValueError(f'no analysis window for {path.name} stage {stage}')
                amplitudes, phases = fitted
                stage_amplitudes.append(amplitudes)
                if zone == 3 and layer == 1 and stage == 3:
                    common_phase = phases
            # Stage order is body -> hammer for the FPGA envelope map.
            for amplitudes in reversed(stage_amplitudes):
                profiles.append(amplitudes)

    if common_phase is None:
        raise ValueError('C4 loud phase reference missing')
    n = np.arange(512, dtype=np.float64)
    for index, amplitudes in enumerate(profiles):
        wave = np.zeros(512, dtype=np.float64)
        for h, (amp, phase) in enumerate(zip(amplitudes, common_phase), start=1):
            wave += amp * np.sin(2.0 * np.pi * h * n / 512.0 + phase)
        wave = np.rint(wave * 32767.0 / np.max(np.abs(wave))).astype(int)
        zone, layer, stage = divmod(index, 12)[0], (index % 12) // 6, index % 6
        (AUDIO / f'wave_piano_z{zone}v{layer}s{stage}.hex').write_text(
            ''.join(f'{int(v) & 0xFFFF:04X}\n' for v in wave), encoding='ascii')

    profile = {
        'source': {
            'name': 'Salamander Grand Piano v3 C1-C6 soft/loud',
            'author': 'Alexander Holm',
            'license': 'CC BY 3.0',
            'repository': 'https://github.com/tambien/Piano',
            'license_url': 'https://creativecommons.org/licenses/by/3.0/',
            'note': 'Relative harmonic amplitudes only; no source PCM is embedded.',
            'files': source_files,
        },
        'zones': [
            {'name': name, 'fundamental_hz': f0, 'first_midi': 24 + 12 * zone}
            for zone, (name, f0) in enumerate(NOTES)
        ],
        'harmonics': HARMONICS,
        'layout': 'bank = zone * 12 + velocity_layer * 6 + stage',
        'stage_windows_seconds': list(STAGE_START),
        'window_cycles': 6,
        'relative_amplitudes': [list(map(float, x)) for x in profiles],
        'phase_radians': list(map(float, common_phase)),
        'peaks': [32767] * len(profiles),
    }
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    (EVIDENCE / 'piano-spectra.json').write_text(
        json.dumps(profile, indent=2) + '\n', encoding='utf-8')
    (AUDIO / 'piano_profiles.json').write_text(
        json.dumps(profile, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({
        'tables': len(profiles),
        'zones': len(NOTES),
        'layers': 2,
        'stages': 6,
        'harmonics': HARMONICS,
    }, indent=2))


if __name__ == '__main__':
    main()
