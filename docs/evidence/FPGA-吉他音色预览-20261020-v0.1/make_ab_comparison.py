#!/usr/bin/env python3
"""Make short A/B clips: current single-cycle wavetable vs original sample."""
from pathlib import Path
import wave

import numpy as np

import render_guitar_previews as fpga
import render_real_guitar_samples as real

OUT = Path(r"D:\NanjingUniversity\FPGA\PolyTouch-FPGA-Synth-20261020-guitar-previews-v0.1")


def read_pcm16(path):
    with wave.open(str(path), "rb") as handle:
        rate = handle.getframerate()
        data = handle.readframes(handle.getnframes())
    return np.frombuffer(data, dtype="<i2").astype(np.float64) / 32768.0, rate


def write_pcm16(path, x, rate):
    pcm = np.round(np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(pcm.tobytes())


def make_ab(name, velocity, table_bank, real_file):
    tables = fpga.load_tables()
    wave_raw, _, _, _ = fpga.render_note(tables, 59, velocity, 1.2, 0.25)
    wave_raw = fpga.normalize(fpga.fade_edges(wave_raw))
    wavetable = fpga.normalize(fpga.resample_linear(wave_raw, fpga.FS_FPGA, fpga.FS_OUT))
    sample, _ = read_pcm16(OUT / "real_samples" / "wav" / real_file)
    sample = real.normalize(real.fade_tail(sample[:int(2.0 * 48000)].copy(), 48000, 80.0))
    silence = np.zeros(int(0.35 * 48000))
    mix = np.concatenate([silence, wavetable, silence, sample, silence])
    write_pcm16(OUT / "ab" / f"{name}.wav", mix, 48000)
    return f"ab/{name}.wav"


print(make_ab("ab_wavetable_vs_real_green_f_B3", 80, 8, "03_green_f_B3_real.wav"))
print(make_ab("ab_wavetable_vs_real_black_f_B3", 120, 11, "06_black_f_B3_real.wav"))