#!/usr/bin/env python3
"""A1 vector generator: stimulus script plus expected samples for the RTL.

Two vector sets are produced, both driven by the independent 64-bit reference
in ``ref_engine.py`` and consumed by the benches in ``sim/opt_a``:

``datapath``  32 voices through ``instrument_ram_audio_compute``; the include
              file issues the configuration transactions and then compares
              ``sine_total``, ``bright_total``, ``audio_sample`` and the clip
              counter frame by frame.  The bench generates the same stimulus,
              so a mismatch localises to a frame and a voice.
``master``    ``wide_master`` alone, fed with the signed 32-bit lane totals at
              their extremes, to exercise saturation, the clip counter, the
              weight/gain ramps and exact digital silence.

Run from the source root:
  tools/.venv-audio-analysis/Scripts/python.exe tools/offline_opt/a/make_vectors.py \
      --out-dir sim/opt_a --mode wide
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

import ref_engine as ref
import wtlib as w

SOURCE = Path(__file__).resolve().parents[3]
AUDIO = SOURCE / "rtl" / "audio"


def load_tables() -> ref.Tables:
    piano = w.read_bank_hex(AUDIO / "epiano_bank_all.hex", 12)
    guitar = w.read_bank_hex(AUDIO / "guitar_bank_all.hex", 30)
    bright = [w.read_hex(AUDIO / name) for name in
              ("wave_bright_h16.hex", "wave_bright_h8.hex", "wave_bright_h4.hex",
               "wave_bright_h2.hex", "wave_bright_h1.hex", "wave_bright.hex")]
    sine = w.read_hex(AUDIO / "wave_sine.hex")
    return ref.Tables(sine=[int(v) for v in sine],
                      banks=[[int(v) for v in t] for t in
                             list(piano) + list(guitar) + bright])


# --------------------------------------------------------------- scenarios ---
INCREMENTS = [0x00000000, 0x00000001, 0x001FFFFF, 0x02000000,
              0x7FFFFFFF, 0x40000000, 0x0FFFFFFF, 0x0000FFFF,
              0x01000000, 0x00FFFFFF, 0x20000000, 0x00000200]
ENVELOPES = [65535, 1, 2, 32768, 65534, 12345, 3, 65535,
             256, 65535, 7, 65535]
VELOCITIES = [127, 1, 2, 64, 100, 127, 33, 126, 127, 5, 127, 127]
BANKS = [0, 2, 4, 6, 8, 10, 12, 41, 1, 9, 20, 5]
WEIGHTS = [65528, 32768, 0, 65535, 1, 18672, 0, 0, 65528, 40000, 0, 18672]


def voice_setup() -> list[dict]:
    voices = []
    for v in range(32):
        voices.append({
            "increment": INCREMENTS[v % len(INCREMENTS)],
            "envelope": ENVELOPES[v % len(ENVELOPES)],
            "velocity": VELOCITIES[v % len(VELOCITIES)],
            "bank": BANKS[v % len(BANKS)],
            "weight": WEIGHTS[v % len(WEIGHTS)],
        })
    return voices


WARMUP_FRAMES = 192   # wide_master ramps frame_weight from 64 to 255 at 1/frame
MAIN_FRAMES = 12
CONTROL = [dict(mix_weight=255, pressure_enable=0, pressure_level=3200, mute=0,
                volume_gain_q8=256) for _ in range(WARMUP_FRAMES + MAIN_FRAMES)]
CONTROL[WARMUP_FRAMES + 10] = dict(mix_weight=255, pressure_enable=1, pressure_level=1024, mute=0,
                   volume_gain_q8=256)
CONTROL[WARMUP_FRAMES + 11] = dict(mix_weight=255, pressure_enable=0, pressure_level=3200, mute=1,
                   volume_gain_q8=256)


def datapath_scenario(model: ref.Datapath) -> dict:
    """Frame 0 configures all voices; later frames patch a few of them."""
    script: list[tuple] = []
    expected: list[dict] = []
    voices = voice_setup()
    for voice, cfg in enumerate(voices):
        script.append(dict(frame=WARMUP_FRAMES, voice=voice, mask=7, retrigger=1, **cfg))
    # Later-frame patches: silence, zero velocity, stage change, tiny envelope.
    script.append(dict(frame=WARMUP_FRAMES + 6, voice=0, mask=1, retrigger=0,
                       envelope=0, velocity=127))
    script.append(dict(frame=WARMUP_FRAMES + 6, voice=1, mask=1, retrigger=0,
                       envelope=65535, velocity=0))
    script.append(dict(frame=WARMUP_FRAMES + 9, voice=2, mask=6, retrigger=0,
                       increment=0x001FFFFF, bank=3, weight=65528))
    script.append(dict(frame=WARMUP_FRAMES + 9, voice=3, mask=1, retrigger=0,
                       envelope=1, velocity=127))

    for frame in range(WARMUP_FRAMES + MAIN_FRAMES):
        for item in script:
            if item["frame"] != frame:
                continue
            model.configure(item["voice"], increment=item.get("increment"),
                            envelope=item.get("envelope"),
                            velocity=item.get("velocity"),
                            retrigger=item.get("retrigger"),
                            bank=item.get("bank"), weight=item.get("weight"))
        expected.append(model.frame(**CONTROL[frame]))
    return {"script": script, "expected": expected}


def silence_scenario(model: ref.Datapath) -> dict:
    script = []
    for voice in range(32):
        script.append(dict(frame=0, voice=voice, mask=7, retrigger=1,
                           increment=0x01000000, envelope=0, velocity=127,
                           bank=0, weight=65528))
        model.configure(voice, increment=0x01000000, envelope=0, velocity=127,
                        retrigger=True, bank=0, weight=65528)
    controls = [dict(mix_weight=255, pressure_enable=0, pressure_level=3200,
                     mute=0, volume_gain_q8=256),
                dict(mix_weight=128, pressure_enable=1, pressure_level=128,
                     mute=0, volume_gain_q8=0),
                dict(mix_weight=0, pressure_enable=1, pressure_level=4095,
                     mute=0, volume_gain_q8=511),
                dict(mix_weight=255, pressure_enable=0, pressure_level=0,
                     mute=1, volume_gain_q8=256)]
    expected = [model.frame(**control) for control in controls]
    return {"script": script, "expected": expected}


MASTER_EXTREMES = [
    # (sine_sum, bright_sum, control index)
    (0x7FFFFFFF, 0x7FFFFFFF, 0),
    (-0x80000000, -0x80000000, 0),
    (0x7FFFFFFF, -0x80000000, 0),
    (0x08000000, 0x08000000, 0),
    (0, 0, 0),
    (0, 0, 2),
    (1, 0, 0),
    (-1, 0, 0),
    (-0x08000000, 0x08000000, 1),
    (0x7FFFFFFF, 0x00000000, 2),
]


def master_scenario(model: ref.Datapath) -> dict:
    controls = [
        dict(mix_weight=255, pressure_enable=0, pressure_level=3200, mute=0,
             volume_gain_q8=256),
        dict(mix_weight=255, pressure_enable=1, pressure_level=128, mute=0,
             volume_gain_q8=256),
        dict(mix_weight=0, pressure_enable=1, pressure_level=4095, mute=1,
             volume_gain_q8=511),
        dict(mix_weight=255, pressure_enable=0, pressure_level=3200, mute=0,
             volume_gain_q8=0),
    ]
    expected = [model.frame_from_sums(sine, bright, **controls[control])
                for sine, bright, control in MASTER_EXTREMES]
    return {"cases": MASTER_EXTREMES, "controls": controls, "expected": expected}


# ---------------------------------------------------------------- emit ------
def vsd(value: int, bits: int = 32) -> str:
    """Verilog signed decimal literal; the minus sign must sit outside the size."""
    return f"-{bits}'sd{-value}" if value < 0 else f"{bits}'sd{value}"


def emit_datapath(path: Path, scenario: dict, model: ref.Datapath) -> None:
    lines = ["// Generated by tools/offline_opt/a/make_vectors.py -- do not edit.",
             f"// mode = {model.mode}; tables hash "
             f"{w.sha256(AUDIO / 'epiano_bank_all.hex')[:16]}",
             f"  DP_DATAPATH_FRAMES = {len(scenario['expected'])};"]
    for frame, expect in enumerate(scenario["expected"]):
        control = CONTROL[frame] if frame < len(CONTROL) else CONTROL[-1]
        lines.append(f"  // ---------------- frame {frame}")
        lines.append(
            f"  dp_frame_ctrl({control['mix_weight']}, {int(control['pressure_enable'])}, "
            f"{control['pressure_level']}, {int(control['mute'])}, "
            f"{control['volume_gain_q8']});")
        for item in scenario["script"]:
            if item["frame"] != frame:
                continue
            lines.append(
                f"  dp_cfg({item['voice']}, 32'h{item.get('increment', 0):08X}, "
                f"16'd{item.get('envelope', 0)}, 7'd{item.get('velocity', 0)}, "
                f"1'b{item.get('retrigger', 0)}, "
                f"24'h{(item.get('bank', 0) << 16) | item.get('weight', 0):06X}, "
                f"3'b{item['mask']:03b});")
        lines.append(
            f"  dp_check({frame}, 32'sh{expect['sine_total'] & 0xFFFFFFFF:08X}, "
            f"32'sh{expect['bright_total'] & 0xFFFFFFFF:08X}, "
            f"{vsd(expect['sample'])}, {expect['frame_weight']}, "
            f"{expect['frame_gain']}, {expect['combined_gain']});")
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def emit_silence(path: Path, scenario: dict, frame_offset: int = 0) -> None:
    lines = ["// Generated by tools/offline_opt/a/make_vectors.py -- do not edit.",
             "// Digital silence: every frame must be exactly zero.",
             f"  DP_SILENCE_FRAMES = {len(scenario['expected'])};"]
    controls = [
        (255, 0, 3200, 0, 256), (128, 1, 128, 0, 0),
        (0, 1, 4095, 0, 511), (255, 0, 0, 1, 256),
    ]
    for frame, expect in enumerate(scenario["expected"]):
        mix_weight, pressure_enable, pressure, mute, volume = controls[frame]
        lines.append(f"  // ---------------- frame {frame}")
        lines.append(f"  dp_frame_ctrl({mix_weight}, {pressure_enable}, {pressure}, "
                     f"{mute}, {volume});")
        for item in scenario["script"]:
            if item["frame"] != frame:
                continue
            lines.append(
                f"  dp_cfg({item['voice']}, 32'h{item['increment']:08X}, "
                f"16'd{item['envelope']}, 7'd{item['velocity']}, "
                f"1'b{item['retrigger']}, "
                f"24'h{(item['bank'] << 16) | item['weight']:06X}, 3'b{item['mask']:03b});")
        lines.append(
            f"  dp_check({frame + frame_offset}, 32'sh{expect['sine_total'] & 0xFFFFFFFF:08X}, "
            f"32'sh{expect['bright_total'] & 0xFFFFFFFF:08X}, "
            f"{vsd(expect['sample'])}, {expect['frame_weight']}, "
            f"{expect['frame_gain']}, {expect['combined_gain']});")
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def emit_master(path: Path, scenario: dict) -> None:
    lines = ["// Generated by tools/offline_opt/a/make_vectors.py -- do not edit.",
             f"  MA_FRAMES = {len(scenario['expected'])};"]
    for (sine, bright, control), expect in zip(scenario["cases"], scenario["expected"]):
        ctl = scenario["controls"][control]
        lines.append(
            f"  ma_frame(32'sh{sine & 0xFFFFFFFF:08X}, 32'sh{bright & 0xFFFFFFFF:08X}, "
            f"{ctl['mix_weight']}, {int(ctl['pressure_enable'])}, "
            f"{ctl['pressure_level']}, {int(ctl['mute'])}, {ctl['volume_gain_q8']});")
        lines.append(
            f"  ma_check({vsd(expect['sample'])}, {int(expect['clipped'])}, "
            f"{expect['frame_weight']}, {expect['frame_gain']});")
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--mode", choices=["wide", "legacy"], default="wide")
    parser.add_argument("--tag", default="", help="suffix for the generated file names")
    args = parser.parse_args()
    out = args.out_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    tables = load_tables()

    model = ref.Datapath(tables=tables, mode=args.mode)
    datapath = datapath_scenario(model)
    emit_datapath(out / f"vectors_datapath{args.tag}.vh", datapath, model)

    silence = silence_scenario(model)
    emit_silence(out / f"vectors_silence{args.tag}.vh", silence, WARMUP_FRAMES + MAIN_FRAMES)

    master_model = ref.Datapath(tables=tables, mode=args.mode)
    master = master_scenario(master_model)
    emit_master(out / f"vectors_master{args.tag}.vh", master)

    wraps = model.wrap_events
    print(f"mode={args.mode} datapath_frames={len(datapath['expected'])} "
          f"silence_frames={len(silence['expected'])} "
          f"master_frames={len(master['expected'])} wraps={wraps or 'none'}")
    print(f"datapath samples={[e['sample'] for e in datapath['expected']]}")
    print(f"master samples={[e['sample'] for e in master['expected']]}")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
