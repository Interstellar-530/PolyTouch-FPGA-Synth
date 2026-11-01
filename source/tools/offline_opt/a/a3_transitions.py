#!/usr/bin/env python3
"""A3 transition measurement: find and size every step the audio path produces.

The plan asks for short fragments with a continuous reference instead of one
blanket "smaller difference is better" threshold, because a normal high-pitched
waveform already moves several percent per sample.  So for each transition this
script reports

  * the per-sample step at the transition instant,
  * the steady-state step statistics of the same signal just before and after
    (p99 and max over +-64 samples, excluding the transition),
  * the *extra* residual: transition step minus the steady maximum,
  * everything in 24-bit LSB and dB relative to full scale.

Scenarios: e-piano table-stage transition, timbre change (bank jump), retrigger,
note-off release, mute, and a main-volume step.  Rendering uses the A1
reference model, which is bit-exact against the RTL, so no simulation is needed
and the numbers are the datapath's, not a model of it.

Run from the source root:
  tools/.venv-audio-analysis/Scripts/python.exe tools/offline_opt/a/a3_transitions.py \
      --report ../../../evidence/2026/10/offline-opt/A/A3-transitions.json
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

import make_vectors as mv
import ref_engine as ref

FS = 48000
STAGE_STEP = 5859                      # voice_sched32 STAGE_STEP_SAMPLES
ATTACK_STEP, DECAY_STEP, RELEASE_STEP, SUSTAIN = 140, 16, 48, 45875
FULL_SCALE = 8388608.0


def envelope_track(frames: int, release_at: int | None = None,
                   retrigger_at: int | None = None) -> list[int]:
    env = 0
    state = "attack"
    out = []
    for frame in range(frames):
        if retrigger_at is not None and frame == retrigger_at:
            env = 0
            state = "attack"
        elif release_at is not None and frame == release_at:
            state = "release"
        if state == "attack":
            env = min(0xFFFF, env + ATTACK_STEP)
            if env == 0xFFFF:
                state = "decay"
        elif state == "decay":
            env = max(SUSTAIN, env - DECAY_STEP)
            if env == SUSTAIN:
                state = "sustain"
        elif state == "sustain":
            env = SUSTAIN
        else:
            env = max(0, env - RELEASE_STEP)
        out.append(env)
    return out


class PianoSchedule:
    """(bank, weight) per frame exactly as voice_sched32 computes them."""

    def __init__(self, base: int, start_stage: int = 3, guitar: bool = False,
                 bank: int = 0):
        self.base, self.start_stage, self.guitar, self.fixed = base, start_stage, guitar, bank

    def __call__(self, frame: int) -> tuple[int, int]:
        if self.guitar:
            return self.fixed, 0
        stage_q = frame // STAGE_STEP
        timer = frame - stage_q * STAGE_STEP
        stage = max(self.start_stage - stage_q, 0)
        weight = ((8191 - timer) << 3) & 0xFFFF if timer <= 8191 else 0
        return self.base + stage, weight


def render(schedule, envelopes, frames, *, increment=0x01A5E1E6, velocity=100,
           mute_frames=(), volume=256, retrigger_at=None, bank_override=None):
    tables = mv.load_tables()
    model = ref.Datapath(tables=tables, mode="wide")
    samples = []
    for frame in range(frames):
        bank, weight = schedule(frame)
        if bank_override and frame >= bank_override[0]:
            bank, weight = bank_override[1], bank_override[2]
        model.configure(0, increment=increment, envelope=envelopes[frame],
                        velocity=velocity, retrigger=(frame == (retrigger_at or -1)),
                        bank=bank, weight=weight)
        out = model.frame(mix_weight=255, pressure_enable=0, pressure_level=3200,
                          mute=frame in mute_frames, volume_gain_q8=volume)
        samples.append(out["sample"])
    return samples


def step_stats(samples: list[int], centre: int, window: int = 64) -> dict:
    """Step at ``centre`` and the steady step statistics around it."""
    lo = max(1, centre - window)
    hi = min(len(samples) - 1, centre + window)
    steady = [abs(samples[i] - samples[i - 1]) for i in range(lo, hi)
              if i != centre and i != centre + 1]
    steady_sorted = sorted(steady)
    p99 = steady_sorted[int(0.99 * (len(steady_sorted) - 1))] if steady_sorted else 0
    peak = max(steady) if steady else 0
    step = abs(samples[centre] - samples[centre - 1]) if 0 < centre < len(samples) else 0
    extra = max(0, step - peak)
    return {
        "transition_step_lsb": step,
        "steady_p99_lsb": p99,
        "steady_peak_lsb": peak,
        "extra_residual_lsb": extra,
        "transition_dbfs": round(20 * math.log10(max(step, 1e-9) / FULL_SCALE), 2),
        "extra_dbfs": round(20 * math.log10(max(extra, 1e-9) / FULL_SCALE), 2),
        "step_over_steady_db": round(20 * math.log10(max(step, 1) / max(peak, 1)), 2),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    results = {}

    # 1. e-piano table-stage transition (bank 3 -> 2 -> 1 -> 0) -----------------
    frames = 3 * STAGE_STEP + 400
    schedule = PianoSchedule(base=0, start_stage=3)
    envelopes = envelope_track(frames)
    samples = render(schedule, envelopes, frames)
    transitions = []
    for k in range(1, frames):
        if schedule(k)[0] != schedule(k - 1)[0]:
            stats = step_stats(samples, k)
            stats["frame"] = k
            stats["bank_from"], stats["bank_to"] = schedule(k - 1)[0], schedule(k)[0]
            stats["weight_from"], stats["weight_to"] = schedule(k - 1)[1], schedule(k)[1]
            transitions.append(stats)
    results["stage_transition"] = {"transitions": transitions, "frames": frames}

    # 2. timbre change: a held note is rewritten from piano group 0 to group 1
    frames = 600
    schedule = PianoSchedule(base=0, start_stage=0)
    envelopes = envelope_track(frames)
    samples = render(schedule, envelopes, frames, bank_override=(300, 6, 65528))
    results["timbre_change"] = {
        "frame": 300, **step_stats(samples, 300),
        "note": "bank 0 weight 65528 -> bank 6 weight 65528",
    }

    # 3. retrigger of a held note (envelope reset, scheduler owned) ------------
    frames = 600
    schedule = PianoSchedule(base=0, start_stage=0)
    envelopes = envelope_track(frames, retrigger_at=300)
    samples = render(schedule, envelopes, frames, retrigger_at=300)
    results["retrigger"] = {"frame": 300, **step_stats(samples, 300),
                            "note": "envelope forced to 0 and phase restarted"}

    # 4. note-off release -----------------------------------------------------
    frames = 900
    schedule = PianoSchedule(base=0, start_stage=0)
    envelopes = envelope_track(frames, release_at=300)
    samples = render(schedule, envelopes, frames)
    results["note_off"] = {"frame": 300, **step_stats(samples, 300),
                           "note": "release ramp 48/frame from sustain"}
    # where the release reaches zero
    for k in range(301, frames):
        if envelopes[k] == 0 and envelopes[k - 1] != 0:
            results["note_off_end"] = {"frame": k, **step_stats(samples, k)}
            break

    # 5. mute and volume step -------------------------------------------------
    frames = 400
    schedule = PianoSchedule(base=0, start_stage=0)
    envelopes = envelope_track(frames)
    samples = render(schedule, envelopes, frames, mute_frames=set(range(200, frames)))
    results["mute"] = {"frame": 200, **step_stats(samples, 200),
                       "note": "mute asserted, gain ramps at 32/frame"}
    samples = render(schedule, envelopes, frames, volume=256)
    samples2 = render(schedule, envelopes, frames, volume=0)
    # splice: frames 0..199 at full volume, then zero volume
    spliced = samples[:200] + samples2[200:]
    results["volume_step"] = {"frame": 200, **step_stats(spliced, 200),
                              "note": "main volume 100 -> 0, +-32/frame Q12 ramp"}

    # 6. pressure step: FSR full scale -> minimum while the note is held -------
    tables = mv.load_tables()
    model = ref.Datapath(tables=tables, mode="wide")
    samples = []
    for frame in range(frames):
        bank, weight = schedule(frame)
        model.configure(0, increment=0x01A5E1E6, envelope=envelopes[frame],
                        velocity=100, retrigger=False, bank=bank, weight=weight)
        level = 3200 if frame < 200 else 128
        out = model.frame(mix_weight=255, pressure_enable=1, pressure_level=level,
                          mute=False, volume_gain_q8=256)
        samples.append(out["sample"])
    # Largest single-frame change anywhere in the ramp, not just at its start.
    worst_frame, worst_step = 200, 0
    for k in range(200, min(frames, 400)):
        step = abs(samples[k] - samples[k - 1])
        if step > worst_step:
            worst_step, worst_frame = step, k
    results["pressure_step"] = {
        "frame": 200, "worst_ramp_frame": worst_frame,
        **step_stats(samples, 200),
        "worst_ramp_step_lsb": worst_step,
        "worst_ramp_dbfs": round(20 * math.log10(max(worst_step, 1e-9) / FULL_SCALE), 2),
        "note": "pressure 3200 -> 128, Q12 gain ramps 32/frame",
    }

    payload = {
        "generated_by": "tools/offline_opt/a/a3_transitions.py",
        "renderer": "ref_engine.Datapath (bit-exact against tb_opt_a_datapath)",
        "full_scale_lsb": int(FULL_SCALE),
        "stage_step_samples": STAGE_STEP,
        "results": results,
    }
    mv.w.json_dump(args.report, payload)

    print(f"{'scenario':16} {'frame':>6} {'step':>8} {'steady99':>9} {'steadyMax':>10} "
          f"{'extra':>8} {'extra dBFS':>11}")
    rows = [("stage_transition", t) for t in results["stage_transition"]["transitions"]]
    for key in ("timbre_change", "retrigger", "note_off", "note_off_end", "mute",
                "volume_step"):
        if key in results:
            rows.append((key, results[key]))
    for name, row in rows:
        print(f"{name:16} {row['frame']:>6} {row['transition_step_lsb']:>8} "
              f"{row['steady_p99_lsb']:>9} {row['steady_peak_lsb']:>10} "
              f"{row['extra_residual_lsb']:>8} {row['extra_dbfs']:>11.2f}")
    print(f"wrote {args.report}")


if __name__ == "__main__":
    main()
