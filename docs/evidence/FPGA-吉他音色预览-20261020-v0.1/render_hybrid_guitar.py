#!/usr/bin/env python3
"""Prototype a BSRAM-feasible guitar voice: real attack + wavetable body.

This is a software concept for the next RTL step. It uses a real pick attack
(about 40-50 ms) and crossfades into the existing 512-point guitar table with
an exponential decay, instead of the current 70% sustain. It is not the current
bitstream output.
"""
from pathlib import Path
import json
import math
import wave

import numpy as np

import render_guitar_previews as fpga
import render_real_guitar_samples as real

OUT = Path(r"D:\NanjingUniversity\FPGA\PolyTouch-FPGA-Synth-20261020-guitar-previews-v0.1")
DEST = OUT / "hybrid"
FS = 46875
FS_OUT = 48000
ATTACK_S = 0.050
XFADE_START_S = 0.018
XFADE_S = 0.028


def onset_index(x, sr):
    width = max(1, int(0.005 * sr))
    power = np.convolve(x * x, np.ones(width) / width, mode="same")
    threshold = max(float(np.max(power)) * 0.01, 10.0 ** (-30.0 / 10.0))
    indices = np.nonzero(power > threshold)[0]
    return int(indices[0]) if len(indices) else 0


def pitch_shift(x, ratio):
    if abs(ratio - 1.0) < 1e-9:
        return x.copy()
    count = max(2, int(round(len(x) / ratio)))
    source = np.arange(len(x), dtype=np.float64)
    target = np.arange(count, dtype=np.float64) * ratio
    return np.interp(target, source, x)


def one_pole(x, cutoff, rate):
    alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / rate)
    y = np.empty_like(x)
    state = 0.0
    for i, value in enumerate(x):
        state += alpha * (value - state)
        y[i] = state
    return y


def table_fundamental_phase(table):
    k = np.arange(512, dtype=np.float64)
    return float(np.angle(np.sum(table * np.exp(-2j * np.pi * k / 512.0))))


def signal_phase(x, start, length, rate, frequency):
    start = max(0, min(start, len(x) - length))
    seg = x[start:start + length] * np.hanning(length)
    n = np.arange(length, dtype=np.float64)
    return float(np.angle(np.sum(seg * np.exp(-2j * np.pi * frequency * n / rate))))


def render_body(tables, note, velocity, seconds, phase0=0.0):
    band = fpga.band_for(note)
    variant = fpga.variant_for(band, velocity)
    bank = band * 6 + variant
    table = tables[bank]
    inc = fpga.phase_inc(note)
    count = int(round(seconds * FS))
    phase = int(round((phase0 % (2.0 * math.pi)) / (2.0 * math.pi) * (1 << 32))) & 0xFFFFFFFF
    out = np.empty(count, dtype=np.float64)
    for i in range(count):
        index = (phase >> 23) & 511
        frac = (phase >> 14) & 511
        a = table[index]
        b = table[(index + 1) & 511]
        out[i] = (a * (512 - frac) + b * frac + 256) / 512.0
        phase = (phase + inc) & 0xFFFFFFFF
    return out, band, variant, bank


def load_attack(guitar, dynamic, source_note, target_note):
    name = f"{guitar}/ord/twang_{note_name(source_note).lower().replace('#','')}_{dynamic}_rr1.wav"
    # note_name returns e.g. B3/E4; filenames are lower-case b3/e4.
    x, sr, path = real.load(name)
    onset = onset_index(x, sr)
    raw = x[onset:onset + int(ATTACK_S * sr)].copy()
    raw = real.resample_linear(raw, sr, FS)
    ratio = fpga.midi_freq(target_note) / fpga.midi_freq(source_note)
    raw = pitch_shift(raw, ratio)
    return raw, path


def note_name(note):
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return f"{names[note % 12]}{note // 12 - 1}"


def render_hybrid(tables, guitar, dynamic, source_note, target_note, velocity, seconds):
    attack, source_path = load_attack(guitar, dynamic, source_note, target_note)
    xfade_start = int(XFADE_START_S * FS)
    xfade_len = int(XFADE_S * FS)
    probe_len = min(int(0.010 * FS), len(attack) - xfade_start)
    if probe_len < 16:
        phase_real = 0.0
    else:
        phase_real = signal_phase(attack, xfade_start, probe_len, FS, fpga.midi_freq(target_note))
    band = fpga.band_for(target_note)
    variant = fpga.variant_for(band, velocity)
    table = tables[band * 6 + variant]
    phase_table = table_fundamental_phase(table)
    phase0 = phase_real - phase_table - 2.0 * math.pi * fpga.midi_freq(target_note) * (xfade_start / FS)
    body, band, variant, bank = render_body(tables, target_note, velocity, seconds, phase0)
    body = one_pole(body, 5000.0, FS)
    t = np.arange(len(body), dtype=np.float64) / FS
    tau = max(0.45, 1.15 * (261.6256 / fpga.midi_freq(target_note)))
    body *= np.exp(-t / tau)
    # Match body loudness to the attack in the crossfade window.
    a = xfade_start
    b = min(len(attack), a + xfade_len)
    attack_rms = float(np.sqrt(np.mean(attack[a:b] ** 2))) if b > a else 1.0
    body_rms = float(np.sqrt(np.mean(body[a:b] ** 2))) if b > a else 1.0
    body *= attack_rms / max(body_rms, 1e-9)
    mix = np.zeros(len(body), dtype=np.float64)
    attack_len = min(len(attack), len(mix))
    mix[:attack_len] += attack[:attack_len]
    for i in range(a, min(len(mix), b)):
        w = (i - a) / max(1, (b - a))
        w = w * w * (3.0 - 2.0 * w)
        mix[i] = attack[i] * (1.0 - w) + body[i] * w
    if b < len(mix):
        mix[b:] += body[b:]
        # Remove the crossfade body already added at the boundary sample.
        mix[b - 1] = body[b - 1]
    mix = real.fade_tail(mix, FS, 40.0)
    return {
        "mix": fpga.normalize(mix),
        "band": band,
        "variant": variant,
        "bank": bank,
        "source": str(source_path),
    }


def write_wav(path, x, rate):
    real.write_wav(path, x, rate)


def metrics(x, rate):
    return real.metrics(x, rate)


def main():
    tables = fpga.load_tables()
    payload = {"generated": "2026-10-20", "concept": "real attack + wavetable body + exponential decay", "clips": []}
    clips = []
    # Single hybrid notes at C4, matching the earlier wavetable comparison.
    for name, dynamic, velocity in [
        ("01_green_p_C4_hybrid", "p", 20),
        ("02_green_mf_C4_hybrid", "mf", 48),
        ("03_green_f_C4_hybrid", "f", 80),
        ("04_black_mf_C4_hybrid", "mf", 100),
        ("05_black_f_C4_hybrid", "f", 120),
    ]:
        guitar = "black" if name.startswith("04") or name.startswith("05") else "green"
        result = render_hybrid(tables, guitar, dynamic, 59, 60, velocity, 2.2)
        playback = fpga.resample_linear(result["mix"], FS, FS_OUT)
        write_wav(DEST / f"{name}.wav", playback, FS_OUT)
        payload["clips"].append({"file": f"hybrid/{name}.wav", "guitar": guitar, "dynamic": dynamic, "source_note": 59, "target_note": 60, **{k: result[k] for k in ("band", "variant", "bank")}, **metrics(playback, FS_OUT)})
        clips.append((result["mix"], name))
    # All five C4 variants in one file.
    pieces = []
    for mix, name in clips:
        pieces.append(real.normalize(mix[:int(1.2 * FS)]))
        pieces.append(np.zeros(int(0.06 * FS)))
    all_mix = np.concatenate(pieces)
    write_wav(DEST / "06_all_variants_C4_hybrid.wav", fpga.resample_linear(real.normalize(all_mix), FS, FS_OUT), FS_OUT)
    payload["clips"].append({"file": "hybrid/06_all_variants_C4_hybrid.wav", "note": "five C4 hybrid variants"})
    # B3 A/B: current wavetable, hybrid, real sample.
    for suffix, dynamic, velocity in [("green_f", "f", 80), ("black_f", "f", 120)]:
        guitar = "black" if suffix.startswith("black") else "green"
        wave_raw, _, _, _ = fpga.render_note(tables, 59, velocity, 1.2, 0.25)
        wave_play = fpga.normalize(fpga.resample_linear(fpga.normalize(fpga.fade_edges(wave_raw)), FS, FS_OUT))
        hybrid = render_hybrid(tables, guitar, dynamic, 59, 59, velocity, 2.2)["mix"]
        hybrid_play = fpga.normalize(fpga.resample_linear(hybrid, FS, FS_OUT))
        sample, _ = real.read_wav24(OUT / "samples" / guitar / "ord" / f"twang_b3_{dynamic}_rr1.wav")
        sample = real.normalize(real.fade_tail(sample[:int(2.0 * 44100)].copy(), 44100, 80.0))
        sample_play = real.normalize(real.resample_linear(sample, 44100, FS_OUT))
        gap = np.zeros(int(0.35 * FS_OUT))
        ab = np.concatenate([gap, wave_play, gap, hybrid_play, gap, sample_play, gap])
        name = f"07_ab_wavetable_hybrid_real_{suffix}_B3.wav"
        write_wav(DEST / name, ab, FS_OUT)
        payload["clips"].append({"file": f"hybrid/{name}", "order": ["wavetable", "hybrid", "real_sample"], "note": "B3"})
    # Hybrid chord, four real attacks plus wavetable bodies.
    for guitar in ("green", "black"):
        length = int(3.0 * FS)
        mix = np.zeros(length, dtype=np.float64)
        for note, source_note, offset in [(59, 59, 0.0), (64, 64, 0.022), (67, 67, 0.044), (71, 71, 0.066)]:
            part = render_hybrid(tables, guitar, "mf", source_note, note, 80, 2.9)["mix"]
            start = int(offset * FS)
            end = min(length, start + len(part))
            mix[start:end] += part[:end - start]
        mix = real.normalize(mix)
        playback = fpga.resample_linear(mix, FS, FS_OUT)
        name = f"08_{guitar}_mf_chord_B3_E4_G4_B4_hybrid.wav"
        write_wav(DEST / name, playback, FS_OUT)
        payload["clips"].append({"file": f"hybrid/{name}", "notes": ["B3", "E4", "G4", "B4"], **metrics(playback, FS_OUT)})
    (DEST / "hybrid_metrics.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()