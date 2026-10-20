#!/usr/bin/env python3
"""Render guitar timbre previews from the FPGA 36-table Karoryfer bank.

The renderer mirrors the current RTL rules:
  band = 6 MIDI zones using the same phase-increment thresholds
  variant = velocity-dependent green/black and p/mf/f selection
  playback = 512-point linear interpolation at 46.875 kHz
  envelope = guitar ADSR (attack 256, decay 3, sustain 45875, release 8)
No pluck transient is added because the FPGA tables contain one steady period.
"""
from pathlib import Path
import hashlib
import json
import math
import wave

import numpy as np

REPO = Path(r"D:\NanjingUniversity\FPGA\PolyTouch-FPGA-Synth")
OUT = Path(r"D:\NanjingUniversity\FPGA\PolyTouch-FPGA-Synth-20261020-guitar-previews-v0.1")
HEX = REPO / "output/handoff_milestone2_20261008/source/rtl/audio/guitar_bank_all.hex"
META = REPO / "output/handoff_milestone2_20261008/source/rtl/audio/guitar_bank_meta.json"

FS_FPGA = 46875
FS_OUT = 48000
THRESHOLDS = [11985848, 23971696, 35916962, 60404889, 95886784]
VARIANT_NAMES = ["green/p", "green/mf", "green/f", "black/p", "black/mf", "black/f"]


def midi_freq(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def phase_inc(note):
    return int(round(midi_freq(note) / FS_FPGA * (1 << 32)))


def band_for(note):
    inc = phase_inc(note)
    for index, threshold in enumerate(THRESHOLDS):
        if inc < threshold:
            return index
    return 5


def variant_for(band, velocity):
    if band <= 1:
        return 5 if velocity >= 112 else 2
    if velocity >= 112:
        return 5
    if velocity >= 96:
        return 4
    if velocity >= 64:
        return 2
    if velocity >= 32:
        return 1
    return 0


def load_tables():
    words = [int(token, 16) for token in HEX.read_text(encoding="ascii").split()]
    if len(words) != 36 * 512:
        raise RuntimeError(f"expected 18432 words, got {len(words)}")
    values = np.asarray(words, dtype=np.int32)
    values = np.where(values >= 32768, values - 65536, values)
    return values.reshape(36, 512).astype(np.float64)


def adsr_curve(samples, gate_samples):
    env = np.zeros(samples, dtype=np.float64)
    state = 0  # 0 idle, 1 attack, 2 decay, 3 sustain, 4 release
    level = 0
    for i in range(samples):
        gate = i < gate_samples
        if i == 0:
            level = 0
            state = 1
        elif not gate and state not in (0, 4):
            state = 4
        elif gate and state == 4:
            level = 0
            state = 1
        elif state == 0:
            level = 0
            if gate:
                state = 1
        elif state == 1:
            if level >= 65535 - 256:
                level = 65535
                state = 2
            else:
                level += 256
        elif state == 2:
            if level <= 45875 + 3:
                level = 45875
                state = 3
            else:
                level -= 3
        elif state == 3:
            level = 45875
            if not gate:
                state = 4
        elif state == 4:
            if level <= 8:
                level = 0
                state = 0
            else:
                level -= 8
        env[i] = level
    return env / 65536.0


def render_note(tables, note, velocity, gate_seconds, tail_seconds):
    band = band_for(note)
    variant = variant_for(band, velocity)
    bank = band * 6 + variant
    table = tables[bank]
    total = int(round((gate_seconds + tail_seconds) * FS_FPGA))
    gate = int(round(gate_seconds * FS_FPGA))
    envelope = adsr_curve(total, gate)
    inc = phase_inc(note)
    phase = 0
    out = np.empty(total, dtype=np.float64)
    for i in range(total):
        index = (phase >> 23) & 511
        frac = (phase >> 14) & 511
        a = table[index]
        b = table[(index + 1) & 511]
        sample = (a * (512 - frac) + b * frac + 256) / 512.0
        out[i] = sample * envelope[i] * (velocity / 128.0)
        phase = (phase + inc) & 0xFFFFFFFF
    return out, band, variant, bank


def normalize(x, dbfs=-3.0):
    peak = float(np.max(np.abs(x)))
    if peak < 1e-12:
        return x
    return x * ((10.0 ** (dbfs / 20.0)) / peak)


def fade_edges(x, milliseconds=4.0):
    count = max(1, int(round(milliseconds * FS_FPGA / 1000.0)))
    ramp = np.linspace(0.0, 1.0, count)
    x[:count] *= ramp
    x[-count:] *= ramp[::-1]
    return x


def resample_linear(x, source_rate, target_rate):
    count = int(round(len(x) * target_rate / source_rate))
    source_t = np.arange(len(x), dtype=np.float64)
    target_t = np.arange(count, dtype=np.float64) * source_rate / target_rate
    return np.interp(target_t, source_t, x)


def write_wav(path, samples, rate):
    pcm = np.round(np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(pcm.tobytes())


def clip_metrics(samples, rate, steady_start=0.20, steady_end=0.75):
    peak = float(np.max(np.abs(samples)))
    rms = float(np.sqrt(np.mean(samples * samples)))
    a = min(len(samples), int(steady_start * rate))
    b = min(len(samples), int(steady_end * rate))
    if b - a < 64:
        a, b = 0, len(samples)
    segment = samples[a:b]
    window = np.hanning(len(segment))
    spectrum = np.abs(np.fft.rfft(segment * window))
    freqs = np.fft.rfftfreq(len(segment), 1.0 / rate)
    centroid = float(np.sum(freqs * spectrum) / np.sum(spectrum)) if np.sum(spectrum) else 0.0
    return {
        "duration_s": round(len(samples) / rate, 3),
        "peak_dbfs": round(20.0 * math.log10(max(peak, 1e-12)), 2),
        "rms_dbfs": round(20.0 * math.log10(max(rms, 1e-12)), 2),
        "spectral_centroid_hz": round(centroid, 1),
    }


def make_single(tables, note, velocity, name, gate=1.2, tail=0.25):
    raw, band, variant, bank = render_note(tables, note, velocity, gate, tail)
    raw = fade_edges(raw)
    playback = normalize(resample_linear(raw, FS_FPGA, FS_OUT))
    write_wav(OUT / "wav_raw_46875" / f"{name}.wav", raw, FS_FPGA)
    write_wav(OUT / "wav" / f"{name}.wav", playback, FS_OUT)
    return {
        "file": f"wav/{name}.wav",
        "raw_file": f"wav_raw_46875/{name}.wav",
        "note": note,
        "note_name": note_name(note),
        "velocity": velocity,
        "band": band,
        "variant": variant,
        "variant_name": VARIANT_NAMES[variant],
        "bank": bank,
        **clip_metrics(playback, FS_OUT),
    }


def note_name(note):
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return f"{names[note % 12]}{note // 12 - 1}"


def make_phrase(tables, notes, velocity, name, gate=0.55, tail=0.20, gap=0.04):
    pieces = []
    details = []
    for note in notes:
        raw, band, variant, bank = render_note(tables, note, velocity, gate, tail)
        raw = fade_edges(raw)
        pieces.append(raw)
        pieces.append(np.zeros(int(round(gap * FS_FPGA))))
        details.append({"note": note, "note_name": note_name(note), "band": band,
                        "variant_name": VARIANT_NAMES[variant], "bank": bank})
    raw = np.concatenate(pieces)
    playback = normalize(resample_linear(raw, FS_FPGA, FS_OUT))
    write_wav(OUT / "wav_raw_46875" / f"{name}.wav", raw, FS_FPGA)
    write_wav(OUT / "wav" / f"{name}.wav", playback, FS_OUT)
    return {
        "file": f"wav/{name}.wav",
        "raw_file": f"wav_raw_46875/{name}.wav",
        "notes": details,
        "velocity": velocity,
        **clip_metrics(playback, FS_OUT),
    }


def make_medley(tables, name):
    pieces = []
    details = []
    for note, velocity in [(60, 20), (60, 48), (60, 80), (60, 100), (60, 120)]:
        raw, band, variant, bank = render_note(tables, note, velocity, 0.55, 0.22)
        raw = normalize(fade_edges(raw))
        pieces.append(raw)
        pieces.append(np.zeros(int(round(0.06 * FS_FPGA))))
        details.append({"note": note, "note_name": note_name(note), "velocity": velocity,
                        "band": band, "variant_name": VARIANT_NAMES[variant], "bank": bank})
    raw = np.concatenate(pieces)
    playback = normalize(resample_linear(raw, FS_FPGA, FS_OUT))
    write_wav(OUT / "wav_raw_46875" / f"{name}.wav", raw, FS_FPGA)
    write_wav(OUT / "wav" / f"{name}.wav", playback, FS_OUT)
    return {
        "file": f"wav/{name}.wav",
        "raw_file": f"wav_raw_46875/{name}.wav",
        "segments": details,
        **clip_metrics(playback, FS_OUT),
    }


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def main():
    tables = load_tables()
    meta = json.loads(META.read_text(encoding="utf-8"))
    clips = []
    clips.append(make_medley(tables, "00_all_variants_C4"))
    clips.append(make_single(tables, 60, 20, "01_green_p_C4_vel20"))
    clips.append(make_single(tables, 60, 48, "02_green_mf_C4_vel48"))
    clips.append(make_single(tables, 60, 80, "03_green_f_C4_vel80"))
    clips.append(make_single(tables, 60, 100, "04_black_mf_C4_vel100"))
    clips.append(make_single(tables, 60, 120, "05_black_f_C4_vel120"))
    clips.append(make_phrase(tables, [60, 67, 72, 76], 80, "06_green_f_phrase_C4_G4_C5_E5"))
    clips.append(make_phrase(tables, [60, 67, 72, 76], 120, "07_black_f_phrase_C4_G4_C5_E5"))
    payload = {
        "generated": "2026-10-20",
        "source_repo": str(REPO),
        "source_commit": "9d467e01f3899933043ef759bdafe1f302dd9f4b",
        "source_branch": "codex/s4-s6-pressure",
        "source_hex": str(HEX),
        "source_hex_sha256": sha256(HEX),
        "source_meta_sha256": sha256(META),
        "source_license": meta["license"],
        "source_name": meta["source"],
        "tables": meta["tables"],
        "bands": meta["bands"],
        "variants": meta["variants"],
        "render_rate_hz": FS_FPGA,
        "playback_rate_hz": FS_OUT,
        "normalization": "-3 dBFS per preview; all_variants segments normalized individually",
        "limitation": "One steady-state period per table; no pluck transient, pickup position variation over time, cabinet or overdrive.",
        "clips": clips,
    }
    (OUT / "evidence" / "preview_metrics.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()