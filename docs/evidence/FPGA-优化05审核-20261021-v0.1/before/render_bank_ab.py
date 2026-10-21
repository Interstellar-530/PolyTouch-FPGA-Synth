#!/usr/bin/env python3
"""Render an A/B audition clip for the wavetable bank compaction.

Reads the old (36-table) and new (12/30-table) banks and plays the same short
phrase through a table-playback model of shared_wavetable_engine: 9-bit address,
9-bit linear interpolation, stage cross-fade by bank_weight, ADSR envelope.
This is not a full FPGA render (no master low-pass/VCA), it isolates the only
thing the compaction changes: which table the engine reads.

Outputs (48000 Hz, 16-bit mono): before.wav, after.wav, ab.wav, diff.wav and
null_test.txt with the measured difference in dB.
"""
import argparse
from pathlib import Path
import numpy as np
import wave

DEPTH = 512
TABLE_BITS = 9


def read_bank(path: Path, count: int) -> np.ndarray:
    vals = [int(line.strip(), 16) for line in path.read_text(encoding='ascii').splitlines() if line.strip()]
    if len(vals) != count * DEPTH:
        raise ValueError(f'{path}: expected {count * DEPTH} words, got {len(vals)}')
    return np.array(vals, dtype=np.uint16).view(np.int16).astype(np.int64).reshape(count, DEPTH)


def midi_inc(note: int, fs: int) -> int:
    f = 440.0 * 2.0 ** ((note - 69) / 12.0)
    return int(round(f / fs * 2 ** 32)) & 0xFFFFFFFF


def piano_zone(inc: int) -> int:
    limits = [0x00400000, 0x00800000, 0x01000000, 0x02000000, 0x04000000]
    for zone, lim in enumerate(limits):
        if inc < lim:
            return zone
    return 5


def guitar_band(inc: int) -> int:
    limits = [11985848, 23971696, 35916962, 60404889, 95886784]
    for band, lim in enumerate(limits):
        if inc < lim:
            return band
    return 5


def read_table(table: np.ndarray, phase: int) -> float:
    idx = (phase >> 23) & (DEPTH - 1)
    frac = (phase >> 14) & 0x1FF
    a = int(table[idx])
    b = int(table[(idx + 1) & (DEPTH - 1)])
    return a + ((b - a) * frac + 256) / 512.0


def envelope(n: int, total: int, fs: int) -> float:
    attack = int(0.012 * fs)
    decay = int(0.30 * fs)
    release = int(0.25 * fs)
    if n < attack:
        return n / max(attack, 1)
    if n < attack + decay:
        return 1.0 - 0.45 * (n - attack) / max(decay, 1)
    if n > total - release:
        return max(0.0, 0.55 * (total - n) / max(release, 1))
    return 0.55


def render_note(bank: np.ndarray, kind: str, note: int, vel: int, seconds: float,
                fs: int, tone: int, mapping: str) -> np.ndarray:
    total = int(seconds * fs)
    inc = midi_inc(note, fs)
    phase = 0
    out = np.zeros(total)
    start_stage = 4 if tone >= 3 else 3
    step = 8192
    for n in range(total):
        if kind == 'piano':
            zone = piano_zone(inc)
            zone_q = min(n // step, start_stage)
            timer = n - zone_q * step if zone_q < start_stage else step - 1
            stage = start_stage - zone_q
            frac = (step - 1) - timer
            weight = frac * 8
            if mapping == 'before':
                lo = zone * 6 + stage
                hi = zone * 6 + min(stage + 1, 5)
            else:
                group = 1 if zone == 5 else 0
                lo = group * 6 + stage
                hi = group * 6 + min(stage + 1, 5)
        else:
            band = guitar_band(inc)
            if vel >= 112:
                variant = 5
            elif vel >= 96:
                variant = 4
            elif vel >= 64:
                variant = 2
            elif vel >= 32:
                variant = 1
            else:
                variant = 0
            if mapping == 'before':
                lo = band * 6 + variant
                hi = lo + 1 if variant < 5 else lo
            else:
                group = 0 if band <= 1 else band - 1
                lo = group * 6 + variant
                hi = group * 6 + min(variant + 1, 5)
            # 引擎在吉他档把 bank_weight 置 0，只用 bank 本身
            weight = 0
        s0 = read_table(bank[lo], phase)
        s1 = read_table(bank[hi], phase)
        mixed = s0 + ((s1 - s0) * weight + 32768) / 65536.0
        out[n] = mixed * (vel / 128.0) * envelope(n, total, fs)
        phase = (phase + inc) & 0xFFFFFFFF
    return out


def resample(x: np.ndarray, fs_in: int, fs_out: int) -> np.ndarray:
    n_out = int(len(x) * fs_out / fs_in)
    t = np.linspace(0, len(x) - 1, n_out)
    return np.interp(t, np.arange(len(x)), x)


def write_wav(path: Path, x: np.ndarray, fs: int, peak: float) -> None:
    y = np.clip(x / max(peak, 1e-9), -1.0, 1.0)
    pcm = np.rint(y * 32767).astype('<i2')
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(fs)
        w.writeframes(pcm.tobytes())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before-hex', type=Path, required=True)
    parser.add_argument('--after-hex', type=Path, required=True)
    parser.add_argument('--kind', choices=['piano', 'guitar'], required=True)
    parser.add_argument('--out-dir', type=Path, required=True)
    parser.add_argument('--notes', default='36,48,60,67,72,84')
    parser.add_argument('--seconds', type=float, default=0.7)
    parser.add_argument('--vel', type=int, default=100)
    parser.add_argument('--tone', type=int, default=0)
    parser.add_argument('--fs', type=int, default=46875)
    parser.add_argument('--fs-out', type=int, default=48000)
    args = parser.parse_args()

    notes = [int(n) for n in args.notes.split(',') if n.strip()]
    before = read_bank(args.before_hex, 36)
    after = read_bank(args.after_hex, 12 if args.kind == 'piano' else 30)
    args.out_dir.mkdir(parents=True, exist_ok=True)

    gap = int(0.05 * args.fs)
    sig_before, sig_after = [], []
    for note in notes:
        sig_before.append(render_note(before, args.kind, note, args.vel, args.seconds, args.fs, args.tone, 'before'))
        sig_after.append(render_note(after, args.kind, note, args.vel, args.seconds, args.fs, args.tone, 'after'))
        sig_before.append(np.zeros(gap))
        sig_after.append(np.zeros(gap))
    b = np.concatenate(sig_before)
    a = np.concatenate(sig_after)

    peak = max(np.max(np.abs(b)), np.max(np.abs(a)), 1e-9)
    diff = a - b
    diff_rms_db = 20 * np.log10(np.sqrt(np.mean(diff ** 2)) / np.sqrt(np.mean(b ** 2)) + 1e-20)
    peak_db = 20 * np.log10(np.max(np.abs(diff)) / np.max(np.abs(b)) + 1e-20)

    b48 = resample(b, args.fs, args.fs_out)
    a48 = resample(a, args.fs, args.fs_out)
    write_wav(args.out_dir / 'before.wav', b48, args.fs_out, peak)
    write_wav(args.out_dir / 'after.wav', a48, args.fs_out, peak)
    write_wav(args.out_dir / 'ab.wav', np.concatenate([b48, np.zeros(int(0.6 * args.fs_out)), a48]),
              args.fs_out, peak)
    boost = 10 ** (40 / 20.0)
    write_wav(args.out_dir / 'diff.wav', resample(diff * boost, args.fs, args.fs_out), args.fs_out, peak)

    report = [
        f'kind            : {args.kind}',
        f'notes           : {notes}',
        f'velocity        : {args.vel}   tone={args.tone}',
        f'seconds/note    : {args.seconds}',
        f'before tables   : {before.shape[0]}',
        f'after tables    : {after.shape[0]}',
        f'diff RMS        : {diff_rms_db:8.2f} dB re before',
        f'diff peak       : {peak_db:8.2f} dB re before peak',
        f'audible?        : {"yes" if diff_rms_db > -60 else "no (< -60 dB, below 16-bit LSB noise)"}',
        '',
        'ab.wav   : before (0.7 s x 6 notes) -> silence -> after, same phrase',
        'diff.wav : (after - before) boosted +40 dB, same length as one phrase',
        'before.wav / after.wav : individual phrases',
    ]
    (args.out_dir / 'null_test.txt').write_text('\n'.join(report) + '\n', encoding='utf-8')
    print('\n'.join(report))


if __name__ == '__main__':
    main()
