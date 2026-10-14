"""S1 acceptance of native-clock PT8211 pin captures (offline only).

No RTL, ADC or analog measurements are synthesized by this program. NumPy is
used for FFT and least squares; Matplotlib is only needed to export evidence.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import platform
from pathlib import Path
import sys
import wave

import numpy as np

FS = 46875
NOTES = (60, 63, 66, 69)
STAGES = {
    "initial_silence": (512, ()),
    "a4_steady": (32768, (69,)),
    "release_a4": (4096, ()),
    "chord4": (4096, NOTES),
    "after_off60": (4096, (63, 66, 69)),
    "after_off63": (4096, (66, 69)),
    "after_off66": (4096, (69,)),
    "all_released": (512, ()),
    "muted_active": (512, NOTES),
    "unmuted_active": (4096, NOTES),
}
ZERO_STAGES = {"initial_silence", "all_released", "muted_active"}
COLS = ("frame", "left", "right", "stage", "gate_mask", "idle_mask",
        "note0", "note1", "note2", "note3", "final_sample_reference")


class AcceptanceError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise AcceptanceError(message)


def hz(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def read_inputs(capture: Path, manifest_path: Path):
    with manifest_path.open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    require(all(set(row) == {"key", "value"} for row in rows), "Invalid manifest columns")
    require(len({row["key"] for row in rows}) == len(rows), "Duplicate manifest keys")
    manifest = {row["key"]: row["value"] for row in rows}
    with capture.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        require(tuple(reader.fieldnames or ()) == COLS, "Unexpected capture columns")
        records = list(reader)
    require(bool(records), "Empty capture")
    groups = {}
    ordered = []
    previous_frame = -1
    previous_stage = None
    for row in records:
        stage = row["stage"]
        require(stage in STAGES, f"Unknown stage: {stage}")
        if stage != previous_stage:
            ordered.append(stage)
        try:
            numeric = [int(row[column]) for column in COLS if column != "stage"]
        except (TypeError, ValueError) as exc:
            raise AcceptanceError("Non-integer or X/Z capture value") from exc
        frame = numeric[0]
        require(frame > previous_frame, "Duplicate or reordered frame")
        if stage == previous_stage:
            require(frame == previous_frame + 1, f"Missing frame inside {stage}")
        groups.setdefault(stage, []).append(numeric)
        previous_frame, previous_stage = frame, stage
    require(ordered == list(STAGES), "Missing, duplicated or reordered capture stage")
    return {key: np.asarray(value, dtype=np.int64) for key, value in groups.items()}, manifest


def estimate_frequency(signal, sample_rate=FS):
    """Hann FFT finds the tone; continuous sine/cos/DC LS refines its frequency.

    Refinement optimizes residuals of the ORIGINAL time samples, rather than
    interpreting zero padding as added physical resolution.
    """
    signal = np.asarray(signal, dtype=np.float64)
    count = len(signal)
    centered = signal - signal.mean()
    spectrum = np.abs(np.fft.rfft(centered * np.hanning(count)))
    frequencies = np.fft.rfftfreq(count, 1.0 / sample_rate)
    selected = np.flatnonzero((frequencies >= 80) & (frequencies <= 2000))
    peak = selected[np.argmax(spectrum[selected])]
    require(spectrum[peak] > 1.0, "No tone for pitch estimation")
    time = np.arange(count, dtype=np.float64) / sample_rate
    energy = float(signal @ signal)

    def cost(frequency):
        angle = 2.0 * np.pi * frequency * time
        design = np.column_stack((np.sin(angle), np.cos(angle), np.ones(count)))
        gram = design.T @ design
        projected = design.T @ signal
        coefficients = np.linalg.solve(gram, projected)
        return max(0.0, energy - float(projected @ coefficients)) / count

    spacing = sample_rate / count
    low, high = frequencies[peak] - spacing, frequencies[peak] + spacing
    ratio = (math.sqrt(5.0) - 1.0) / 2.0
    x1, x2 = high - ratio * (high - low), low + ratio * (high - low)
    c1, c2 = cost(x1), cost(x2)
    for _ in range(42):
        if c1 < c2:
            high, x2, c2 = x2, x1, c1
            x1 = high - ratio * (high - low)
            c1 = cost(x1)
        else:
            low, x1, c1 = x1, x2, c2
            x2 = low + ratio * (high - low)
            c2 = cost(x2)
    estimate = (low + high) / 2.0
    return {
        "estimate_hz": estimate, "expected_hz": 440.0,
        "absolute_error_hz": abs(estimate - 440.0),
        "samples": count, "duration_s": count / sample_rate,
        "fft_bin_spacing_hz": spacing, "coarse_fft_peak_hz": float(frequencies[peak]),
        "method": "Hann FFT dominant 80-2000 Hz peak, then continuous sine/cosine/DC least-squares residual minimization over original samples",
        "fit_residual_rms_lsb": math.sqrt(cost(estimate)),
    }


def fit_note_amplitudes(signal, sample_rate=FS):
    # Simultaneously fit all four bases so leakage from the remaining tones
    # cannot masquerade as a released fundamental in short 4096-frame windows.
    time = np.arange(len(signal), dtype=np.float64) / sample_rate
    columns = []
    for note in NOTES:
        angle = 2.0 * np.pi * hz(note) * time
        columns.extend((np.sin(angle), np.cos(angle)))
    columns.append(np.ones(len(signal)))
    design = np.column_stack(columns)
    coefficients, _, _, _ = np.linalg.lstsq(design, signal.astype(float), rcond=None)
    amplitudes = {str(note): float(np.hypot(coefficients[2*i], coefficients[2*i+1]))
                  for i, note in enumerate(NOTES)}
    residual = signal - design @ coefficients
    return amplitudes, float(np.sqrt(np.mean(residual ** 2)))


def validate(groups, manifest):
    expected_manifest = {
        "sample_rate": str(FS), "clk_hz": "27000000", "uart_baud": "115200",
        "bits_per_word": "16", "bck_period_clocks": "18", "frame_period_clocks": "576",
        "channel_format": "PT8211_16bit_right_aligned",
        "decoder_uses_serializer_bit_counter": "false", "sample_tick_forced": "false",
        "result": "PASS", "captured_frames": "58880",
    }
    for key, expected in expected_manifest.items():
        require(manifest.get(key) == expected, f"Manifest {key}: expected {expected}")
    require(set(groups) == set(STAGES), "Missing capture groups")
    metrics = {}
    for stage, (count, expected_notes) in STAGES.items():
        values = groups[stage]
        require(values.shape == (count, 10), f"Wrong sample count/columns in {stage}")
        require(manifest.get("stage_count_" + stage) == str(count), f"Manifest count mismatch in {stage}")
        listed_notes = ";".join(map(str, expected_notes)) or "none"
        require(manifest.get("expected_notes_" + stage) == listed_notes, f"Manifest notes mismatch in {stage}")
        left, right, reference = values[:, 1], values[:, 2], values[:, 9]
        require(bool(np.all((left >= -32768) & (left <= 32767))), f"Sample range invalid in {stage}")
        require(np.array_equal(left, right), f"Channel mismatch in {stage}")
        require(np.array_equal(left, reference), f"Serializer reference mismatch in {stage}")
        gate, idle, voice_notes = values[:, 3], values[:, 4], values[:, 5:9]
        require(bool(np.all((gate >= 0) & (gate <= 15) & (idle >= 0) & (idle <= 15))), "Voice mask range invalid")
        # Validate distinct pitches and voice lifetime on every captured frame.
        for row_index in range(count):
            active = [int(voice_notes[row_index, index]) for index in range(4)
                      if gate[row_index] & (1 << index)]
            require(sorted(active) == list(expected_notes), f"Voice/pitch mismatch in {stage}")
            require((gate[row_index] & idle[row_index]) == 0, f"Held voice marked idle in {stage}")
        if stage != "release_a4":
            require(bool(np.all((gate | idle) == 15)), f"Release did not become idle in {stage}")
        peak = int(np.max(np.abs(left)))
        if stage in ZERO_STAGES:
            require(peak == 0, f"Nonzero digital silence in {stage}")
        elif expected_notes:
            require(peak > 500, f"No audible-level digital signal in {stage}")
        metrics[stage] = {"samples": count, "peak_lsb": peak,
                          "rms_lsb": float(np.sqrt(np.mean(left.astype(float) ** 2))),
                          "expected_notes": list(expected_notes)}
    # The release-tail capture must begin with real audio and end in exact zero.
    tail = groups["release_a4"][:, 1]
    require(np.max(np.abs(tail[:256])) > 500, "Release tail was cut off immediately")
    require(np.all(tail[-512:] == 0), "Release tail did not reach exact zero")
    pitch = estimate_frequency(groups["a4_steady"][:, 1])
    require(pitch["absolute_error_hz"] <= 1.0, f"A4 frequency error {pitch['absolute_error_hz']:.6f} Hz > 1 Hz")
    spectral_stages = ("chord4", "after_off60", "after_off63", "after_off66", "unmuted_active")
    for stage in spectral_stages:
        amplitudes, residual = fit_note_amplitudes(groups[stage][:, 1])
        metrics[stage].update(fundamental_amplitude_lsb=amplitudes, fit_residual_rms_lsb=residual)
        active = STAGES[stage][1]
        for note in active:
            require(amplitudes[str(note)] >= 1000, f"Missing held fundamental {note} in {stage}")
        if stage != "chord4":
            for note in NOTES:
                if note not in active:
                    baseline = metrics["chord4"]["fundamental_amplitude_lsb"][str(note)]
                    ratio = amplitudes[str(note)] / baseline
                    metrics[stage].setdefault("released_ratio_to_chord4", {})[str(note)] = ratio
                    require(ratio < 0.01 and amplitudes[str(note)] < 100,
                            f"Released fundamental {note} remains in {stage}: {amplitudes[str(note)]:.3f} LSB, ratio {ratio:.6f}")
    return {"result": "PASS", "sample_rate_hz": FS, "captured_frames": 58880,
            "format": "stereo signed 16-bit little-endian PCM, PT8211 right-aligned pin decode",
            "pitch": pitch, "stages": metrics,
            "scope": "RTL digital output only; no analog noise, voltage, headphone latency or oscillator accuracy measurement"}


def export_artifacts(groups, result, destination):
    import matplotlib
    matplotlib.use("Agg")
    from matplotlib import pyplot as plt
    destination.mkdir(parents=True, exist_ok=True)
    for stage in STAGES:
        stereo = groups[stage][:, 1:3].astype("<i2")
        with wave.open(str(destination / (stage + ".wav")), "wb") as stream:
            stream.setnchannels(2)
            stream.setsampwidth(2)
            stream.setframerate(FS)
            stream.writeframes(stereo.tobytes())
        # Read back the generated WAV metadata/data count, independently of its file size.
        with wave.open(str(destination / (stage + ".wav")), "rb") as stream:
            require((stream.getnchannels(), stream.getsampwidth(), stream.getframerate(), stream.getnframes())
                    == (2, 2, FS, len(stereo)), f"WAV format/count mismatch in {stage}")
        stereo.tofile(destination / (stage + ".pcm"))
    fig, axes = plt.subplots(3, 2, figsize=(12, 10), layout="constrained")
    stages = ("a4_steady", "chord4", "after_off60", "after_off63", "after_off66", "unmuted_active")
    for axis, stage in zip(axes.flat, stages):
        signal = groups[stage][:, 1].astype(float)
        window = np.hanning(len(signal))
        spectrum = 2 * np.abs(np.fft.rfft((signal-signal.mean()) * window)) / window.sum()
        frequencies = np.fft.rfftfreq(len(signal), 1/FS)
        axis.plot(frequencies, 20*np.log10(np.maximum(spectrum, 1e-4)/32768), linewidth=1)
        for note in NOTES:
            axis.axvline(hz(note), color="#8c8c8c", alpha=.4, linewidth=.7)
        axis.set(xlim=(200, 520), ylim=(-110, 0), title=f"{stage}: N={len(signal)}, bin={FS/len(signal):.4f} Hz",
                 xlabel="Frequency (Hz)", ylabel="Amplitude (dBFS)")
        axis.grid(alpha=.2)
    fig.savefig(destination / "spectra.png", dpi=160)
    plt.close(fig)
    fig, axis = plt.subplots(figsize=(10, 3), layout="constrained")
    tail = groups["release_a4"][:, 1]
    axis.plot(np.arange(len(tail))/FS*1000, tail, linewidth=.6)
    axis.set(xlabel="Time after Note Off (ms)", ylabel="Decoded PCM (LSB)", title="A4 release tail: real serial samples")
    axis.grid(alpha=.2)
    fig.savefig(destination / "release_tail.png", dpi=160)
    plt.close(fig)
    result["versions"] = {"python": platform.python_version(), "numpy": np.__version__, "matplotlib": matplotlib.__version__}


def synthetic_inputs():
    groups, manifest, frame = {}, {}, 100
    manifest.update(sample_rate=str(FS), clk_hz="27000000", uart_baud="115200", bits_per_word="16",
                    bck_period_clocks="18", frame_period_clocks="576", result="PASS", captured_frames="58880",
                    channel_format="PT8211_16bit_right_aligned", decoder_uses_serializer_bit_counter="false", sample_tick_forced="false")
    for stage, (count, notes) in STAGES.items():
        time = np.arange(count) / FS
        values = np.zeros((count, 10), dtype=np.int64)
        values[:, 0] = np.arange(frame, frame+count)
        signal = sum((6000*np.sin(2*np.pi*hz(note)*time + note*.1) for note in notes), np.zeros(count))
        if stage in ZERO_STAGES:
            signal[:] = 0
        if stage == "release_a4":
            signal = 6000 * np.sin(2*np.pi*440*time) * np.maximum(0, 1-np.arange(count)/1000)
        rounded = np.rint(signal).astype(np.int64)
        values[:, 1] = values[:, 2] = values[:, 9] = rounded
        values[:, 3] = (1 << len(notes)) - 1
        values[:, 4] = 15 ^ values[:, 3]
        for index, note in enumerate(notes):
            values[:, 5+index] = note
        groups[stage] = values
        manifest["stage_count_"+stage] = str(count)
        manifest["expected_notes_"+stage] = ";".join(map(str, notes)) or "none"
        frame += count+2000
    return groups, manifest


def self_test():
    groups, manifest = synthetic_inputs()
    validate(groups, manifest)
    rejected = []
    cases = ("wrong_sample_rate", "channel_corruption", "pitch_error", "missing_held_voice",
             "off_ignored_in_audio", "nonzero_mute", "missing_frame", "instant_release_cutoff")
    for name in cases:
        bad = {key: value.copy() for key, value in groups.items()}
        bad_manifest = manifest.copy()
        if name == "wrong_sample_rate":
            bad_manifest["sample_rate"] = "48000"
        elif name == "channel_corruption":
            bad["a4_steady"][100, 2] += 1
        elif name == "pitch_error":
            signal = np.rint(6000*np.sin(2*np.pi*443*np.arange(32768)/FS)).astype(np.int64)
            bad["a4_steady"][:, 1] = bad["a4_steady"][:, 2] = bad["a4_steady"][:, 9] = signal
        elif name == "missing_held_voice":
            stage, notes = "chord4", (63, 66, 69)
            signal = np.rint(sum(6000*np.sin(2*np.pi*hz(note)*np.arange(4096)/FS + note*.1) for note in notes)).astype(np.int64)
            bad[stage][:, 1] = bad[stage][:, 2] = bad[stage][:, 9] = signal
        elif name == "off_ignored_in_audio":
            signal = groups["chord4"][:, 1]
            bad["after_off60"][:, 1] = bad["after_off60"][:, 2] = bad["after_off60"][:, 9] = signal
        elif name == "nonzero_mute":
            bad["muted_active"][10, 1] = bad["muted_active"][10, 2] = bad["muted_active"][10, 9] = 1
        elif name == "missing_frame":
            bad["chord4"] = bad["chord4"][:-1]
        else:
            bad["release_a4"][:, 1] = bad["release_a4"][:, 2] = bad["release_a4"][:, 9] = 0
        try:
            validate(bad, bad_manifest)
        except AcceptanceError as exc:
            rejected.append({"case": name, "rejected": True, "reason": str(exc)})
        else:
            raise AcceptanceError(f"Negative control was accepted: {name}")
    print(json.dumps({"result": "PASS", "synthetic_positive": "PASS", "negative_controls": rejected}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--git-commit", default="unrecorded")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not all((args.capture, args.manifest, args.output_dir)):
        parser.error("--capture, --manifest, --output-dir are required")
    groups, manifest = read_inputs(args.capture, args.manifest)
    result = validate(groups, manifest)
    result.update(git_commit=args.git_commit, capture_sha256=hashlib.sha256(args.capture.read_bytes()).hexdigest(),
                  manifest_sha256=hashlib.sha256(args.manifest.read_bytes()).hexdigest())
    export_artifacts(groups, result, args.output_dir)
    (args.output_dir / "audio_analysis.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"result": result["result"], "frames": result["captured_frames"], "pitch": result["pitch"]}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (AcceptanceError, ValueError, OSError) as exc:
        print(f"FAIL audio capture: {exc}", file=sys.stderr)
        sys.exit(1)
