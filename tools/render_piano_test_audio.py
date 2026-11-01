"""Render the current FPGA piano bank on the PC for diagnostic listening.

This is an offline model of the current DDS/ADSR/table-selection equations.
It does not use the board DAC or reproduce analog noise.
"""
from pathlib import Path
import json
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
AUDIO = ROOT / 'source/rtl/audio'
OUT = ROOT / 'evidence/2026/10/FPGA-钢琴音色-20261018-v0.1'
FS = 48000


def load_tables():
    tables = []
    for index in range(72):
        zone, remainder = divmod(index, 12)
        layer, stage = divmod(remainder, 6)
        path = AUDIO / f'wave_piano_z{zone}v{layer}s{stage}.hex'
        values = np.array([int(v, 16) for v in path.read_text().split()], dtype=np.int64)
        values = np.where(values >= 32768, values - 65536, values)
        tables.append(values.astype(np.float64))
    return np.asarray(tables)


def note_hz(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def zone_for_note(note):
    return int(np.clip((note - 24) // 12, 0, 5))


def env_step(env, state, gate):
    if state == 'attack':
        env = min(65535, env + 2048)
        if env == 65535:
            state = 'decay'
    elif state == 'decay':
        env = max(256, env - 2)
        if env == 256:
            state = 'sustain'
    elif state == 'sustain':
        env = 256
        if not gate:
            state = 'release'
    elif state == 'release':
        env = max(0, env - 32)
        if env == 0:
            state = 'idle'
    return env, state


def render_note(tables, note, tone, velocity, seconds, gate_seconds):
    count = int(round(seconds * FS))
    zone = zone_for_note(note)
    layer = 1 if velocity >= 64 else 0
    base = min(tone, 4)
    phase = 0
    inc = int(round(note_hz(note) / FS * (1 << 32))) & 0xFFFFFFFF
    env = 0
    state = 'attack'
    values = np.zeros(count, dtype=np.float64)
    stages = np.zeros(count, dtype=np.int16)
    for i in range(count):
        gate = i < int(gate_seconds * FS)
        if state == 'sustain' and not gate:
            state = 'release'
        pos = base + (env >> 13)
        if pos >= 5:
            bank = zone * 12 + layer * 6 + 4
            weight = 1.0
        else:
            bank = zone * 12 + layer * 6 + pos
            weight = ((env & 0x1FFF) << 3) / 65536.0
        table_a = tables[bank]
        table_b = tables[min(bank + 1, 71)]
        index = phase >> 23
        frac = (phase >> 14) & 0x1FF
        a = table_a[index]
        b = table_a[(index + 1) & 0x1FF]
        interpolated_a = a + ((b - a) * frac / 512.0)
        a = table_b[index]
        b = table_b[(index + 1) & 0x1FF]
        interpolated_b = a + ((b - a) * frac / 512.0)
        sample = interpolated_a + (interpolated_b - interpolated_a) * weight
        values[i] = sample * (env / 65535.0) * (velocity / 255.0) / 4.0
        stages[i] = bank
        env, state = env_step(env, state, gate)
        phase = (phase + inc) & 0xFFFFFFFF
    return values, stages


def add_segment(destination, start, values):
    end = min(len(destination), start + len(values))
    destination[start:end] += values[:end - start]
    return end


def main():
    tables = load_tables()
    segments = []
    cursor = int(0.2 * FS)
    spec = [
        ('F1 soft C4', 60, 0, 100, 1.25),
        ('F2 mellow C4', 60, 1, 100, 1.25),
        ('F3 medium C4', 60, 2, 100, 1.25),
        ('F4 bright C4', 60, 3, 100, 1.25),
        ('F5 hammer C4', 60, 4, 100, 1.25),
        ('C2 hammer', 36, 4, 100, 1.6),
        ('C4 hammer', 60, 4, 100, 1.6),
        ('C6 hammer', 84, 4, 100, 1.6),
    ]
    total = cursor
    rendered = {}
    for label, note, tone, velocity, seconds in spec:
        values, stages = render_note(tables, note, tone, velocity, seconds + 0.35, seconds)
        rendered[label] = (values, stages)
        total += len(values) + int(0.25 * FS)
    total += int(1.6 * FS) + int(0.5 * FS)
    mix = np.zeros(total, dtype=np.float64)
    manifest = []
    cursor = int(0.2 * FS)
    for label, note, tone, velocity, seconds in spec:
        values, stages = rendered[label]
        end = add_segment(mix, cursor, values)
        manifest.append({
            'label': label,
            'note': note,
            'tone': tone,
            'velocity': velocity,
            'start_sample': cursor,
            'end_sample': end,
            'peak': float(np.max(np.abs(values))),
            'rms': float(np.sqrt(np.mean(values * values))),
            'stage_span': [int(np.min(stages)), int(np.max(stages))],
        })
        cursor = end + int(0.25 * FS)
    chord_start = cursor
    chord = np.zeros(int(2.0 * FS), dtype=np.float64)
    for note in (60, 64, 67, 72):
        values, _ = render_note(tables, note, 4, 100, 2.0, 1.4)
        chord += values
    add_segment(mix, chord_start, chord)
    manifest.append({'label': 'C major chord', 'notes': [60, 64, 67, 72],
                     'start_sample': chord_start,
                     'end_sample': chord_start + len(chord),
                     'peak': float(np.max(np.abs(chord))),
                     'rms': float(np.sqrt(np.mean(chord * chord)))})
    peak = float(np.max(np.abs(mix)))
    gain = 0.88 / peak if peak > 0 else 1.0
    mix *= gain
    OUT.mkdir(parents=True, exist_ok=True)
    wav = OUT / 'piano-current-test.wav'
    sf.write(wav, mix, FS, subtype='PCM_16')
    report = {
        'model': 'current DDS + piano ADSR + stage/bank interpolation + /4 gain',
        'sample_rate_hz': FS,
        'duration_seconds': len(mix) / FS,
        'global_normalization': gain,
        'segments': manifest,
        'note': 'This bypasses PT8211, LPA4809, USB power, headphones and analog noise.',
    }
    (OUT / 'piano-current-test-report.json').write_text(
        json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
