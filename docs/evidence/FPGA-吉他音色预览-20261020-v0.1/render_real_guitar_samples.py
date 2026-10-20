#!/usr/bin/env python3
"""Render guitar previews from the original Karoryfer 24-bit WAV samples.

Unlike the single-cycle FPGA wavetable renderer, this keeps the real pick
transient, initial brightness and natural decay. It is a software reference
for what a sample-based guitar engine can sound like, not the current bitstream.
"""
from pathlib import Path
import json
import math
import wave

import numpy as np

OUT = Path(r"D:\NanjingUniversity\FPGA\PolyTouch-FPGA-Synth-20261020-guitar-previews-v0.1")
SAMPLES = OUT / "samples"
DEST = OUT / "real_samples"
FS_OUT = 48000


def read_wav24(path):
    with wave.open(str(path), "rb") as handle:
        if handle.getnchannels() != 1 or handle.getsampwidth() != 3:
            raise RuntimeError(f"expected mono 24-bit PCM: {path}")
        rate = handle.getframerate()
        frames = handle.getnframes()
        data = handle.readframes(frames)
    raw = np.frombuffer(data, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
    value = raw[:, 0] | (raw[:, 1] << 8) | (raw[:, 2] << 16)
    value = np.where(value >= (1 << 23), value - (1 << 24), value).astype(np.float64)
    return value / float(1 << 23), rate


def resample_linear(x, source_rate, target_rate):
    count = int(round(len(x) * target_rate / source_rate))
    source_t = np.arange(len(x), dtype=np.float64)
    target_t = np.arange(count, dtype=np.float64) * source_rate / target_rate
    return np.interp(target_t, source_t, x)


def normalize(x, dbfs=-3.0):
    peak = float(np.max(np.abs(x)))
    if peak < 1e-12:
        return x
    return x * ((10.0 ** (dbfs / 20.0)) / peak)


def fade_tail(x, rate, milliseconds=25.0):
    count = min(len(x), max(1, int(round(milliseconds * rate / 1000.0))))
    x[-count:] *= np.linspace(1.0, 0.0, count)
    return x


def trim(x, rate, seconds, fade_ms=25.0):
    count = min(len(x), int(round(seconds * rate)))
    return fade_tail(x[:count].copy(), rate, fade_ms)


def write_wav(path, samples, rate):
    pcm = np.round(np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(pcm.tobytes())


def metrics(x, rate):
    peak = float(np.max(np.abs(x)))
    rms = float(np.sqrt(np.mean(x * x)))

    def centroid(start, end):
        a = min(len(x), int(start * rate))
        b = min(len(x), int(end * rate))
        if b - a < 64:
            a, b = 0, len(x)
        seg = x[a:b]
        spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg))))
        freqs = np.fft.rfftfreq(len(seg), 1.0 / rate)
        return float(np.sum(freqs * spec) / np.sum(spec)) if np.sum(spec) else 0.0

    return {
        "duration_s": round(len(x) / rate, 3),
        "peak_dbfs": round(20.0 * math.log10(max(peak, 1e-12)), 2),
        "rms_dbfs": round(20.0 * math.log10(max(rms, 1e-12)), 2),
        "centroid_attack_hz": round(centroid(0.03, 0.30), 1),
        "centroid_body_hz": round(centroid(0.60, 1.20), 1),
    }


def load(name):
    path = SAMPLES / name
    x, rate = read_wav24(path)
    return x, rate, path


def make_single(name, source, seconds, label):
    x, rate, path = load(source)
    raw = trim(x, rate, seconds, 35.0)
    (DEST / "wav_raw_44100" / f"{name}.wav").parent.mkdir(parents=True, exist_ok=True)
    write_wav(DEST / "wav_raw_44100" / f"{name}.wav", raw, rate)
    playback = normalize(resample_linear(raw, rate, FS_OUT))
    write_wav(DEST / "wav" / f"{name}.wav", playback, FS_OUT)
    return {
        "file": f"real_samples/wav/{name}.wav",
        "raw_file": f"real_samples/wav_raw_44100/{name}.wav",
        "source": f"samples/{source}",
        "source_rate_hz": rate,
        "label": label,
        **metrics(playback, FS_OUT),
    }


def make_medley():
    entries = [
        ("green/ord/twang_b3_p_rr1.wav", "green/p"),
        ("green/ord/twang_b3_mf_rr1.wav", "green/mf"),
        ("green/ord/twang_b3_f_rr1.wav", "green/f"),
        ("black/ord/twang_b3_p_rr1.wav", "black/p"),
        ("black/ord/twang_b3_mf_rr1.wav", "black/mf"),
        ("black/ord/twang_b3_f_rr1.wav", "black/f"),
    ]
    pieces = []
    details = []
    for source, label in entries:
        x, rate, path = load(source)
        raw = normalize(trim(x, rate, 1.35, 35.0))
        pieces.append(raw)
        pieces.append(np.zeros(int(round(0.06 * rate))))
        details.append({"source": f"samples/{source}", "label": label})
    raw = np.concatenate(pieces)
    write_wav(DEST / "wav_raw_44100" / "00_all_six_real_B3.wav", raw, 44100)
    playback = normalize(resample_linear(raw, 44100, FS_OUT))
    write_wav(DEST / "wav" / "00_all_six_real_B3.wav", playback, FS_OUT)
    return {
        "file": "real_samples/wav/00_all_six_real_B3.wav",
        "raw_file": "real_samples/wav_raw_44100/00_all_six_real_B3.wav",
        "segments": details,
        **metrics(playback, FS_OUT),
    }


def make_phrase(guitar):
    sequence = ["b3", "e4", "g4", "b4"]
    pieces = []
    details = []
    for note in sequence:
        source = f"{guitar}/ord/twang_{note}_mf_rr1.wav"
        x, rate, path = load(source)
        raw = normalize(trim(x, rate, 1.05, 45.0))
        pieces.append(raw)
        pieces.append(np.zeros(int(round(0.025 * rate))))
        details.append({"note": note.upper(), "source": f"samples/{source}"})
    raw = np.concatenate(pieces)
    name = f"09_{guitar}_mf_phrase_B3_E4_G4_B4"
    write_wav(DEST / "wav_raw_44100" / f"{name}.wav", raw, 44100)
    playback = normalize(resample_linear(raw, 44100, FS_OUT))
    write_wav(DEST / "wav" / f"{name}.wav", playback, FS_OUT)
    return {"file": f"real_samples/wav/{name}.wav", "raw_file": f"real_samples/wav_raw_44100/{name}.wav", "notes": details, **metrics(playback, FS_OUT)}


def make_chord(guitar):
    sequence = [("b3", 0.000), ("e4", 0.022), ("g4", 0.044), ("b4", 0.066)]
    length = int(round(2.75 * 44100))
    mix = np.zeros(length, dtype=np.float64)
    details = []
    for note, offset in sequence:
        source = f"{guitar}/ord/twang_{note}_mf_rr1.wav"
        x, rate, path = load(source)
        raw = trim(x, rate, 2.7, 120.0)
        start = int(round(offset * rate))
        end = min(length, start + len(raw))
        mix[start:end] += raw[:end - start]
        details.append({"note": note.upper(), "offset_ms": round(offset * 1000, 1), "source": f"samples/{source}"})
    mix = normalize(mix)
    name = f"10_{guitar}_mf_chord_B3_E4_G4_B4"
    write_wav(DEST / "wav_raw_44100" / f"{name}.wav", mix, 44100)
    playback = normalize(resample_linear(mix, 44100, FS_OUT))
    write_wav(DEST / "wav" / f"{name}.wav", playback, FS_OUT)
    return {"file": f"real_samples/wav/{name}.wav", "raw_file": f"real_samples/wav_raw_44100/{name}.wav", "notes": details, **metrics(playback, FS_OUT)}


def main():
    clips = [make_medley()]
    clips.append(make_single("01_green_p_B3_real", "green/ord/twang_b3_p_rr1.wav", 4.0, "green/p, B3"))
    clips.append(make_single("02_green_mf_B3_real", "green/ord/twang_b3_mf_rr1.wav", 4.5, "green/mf, B3"))
    clips.append(make_single("03_green_f_B3_real", "green/ord/twang_b3_f_rr1.wav", 5.0, "green/f, B3"))
    clips.append(make_single("04_black_p_B3_real", "black/ord/twang_b3_p_rr1.wav", 1.35, "black/p, B3"))
    clips.append(make_single("05_black_mf_B3_real", "black/ord/twang_b3_mf_rr1.wav", 3.0, "black/mf, B3"))
    clips.append(make_single("06_black_f_B3_real", "black/ord/twang_b3_f_rr1.wav", 4.0, "black/f, B3"))
    clips.append(make_phrase("green"))
    clips.append(make_phrase("black"))
    clips.append(make_chord("green"))
    clips.append(make_chord("black"))
    payload = {
        "generated": "2026-10-20",
        "source": "Karoryfer Black And Green Guitars",
        "source_url": "https://github.com/sfzinstruments/karoryfer.black-and-green-guitars",
        "license": "CC0-1.0",
        "note": "Original 24-bit 44.1 kHz WAV samples, including pick transient and natural decay. Not the current single-cycle FPGA wavetable output.",
        "playback_rate_hz": FS_OUT,
        "normalization": "-3 dBFS per preview",
        "clips": clips,
    }
    (DEST / "evidence" / "real_sample_metrics.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()