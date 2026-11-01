#!/usr/bin/env python3
"""Bit-exact 64-bit reference for the 32-voice RAM audio datapath (A1).

The model mirrors ``instrument_ram_wavetable_engine`` and ``wide_master``
operation by operation, in exact integer arithmetic, and offers two width
modes:

``wide``    the intended arithmetic: every intermediate is wide enough for the
            operands the datapath actually carries.
``legacy``  the shipped arithmetic: the three interpolation deltas and the two
            final amplitude products are truncated to 24-bit signed and the
            per-voice accumulators to 32-bit, exactly like the RTL bit slices.

Both modes are identical unless a truncation actually wraps, which is what A1
has to prove.  Nothing here reads the RTL; it is an independent implementation
of the documented contract in ``A1-arithmetic.md``.
"""
from __future__ import annotations

from dataclasses import dataclass, field

DEPTH = 512


def s24(value: int) -> int:
    """Reinterpret the low 24 bits as signed, like a 24-bit Verilog reg."""
    value &= 0xFFFFFF
    return value - 0x1000000 if value & 0x800000 else value


def s32(value: int) -> int:
    value &= 0xFFFFFFFF
    return value - 0x100000000 if value & 0x80000000 else value


def s64(value: int) -> int:
    return value


def trunc(value: int, mode: str) -> int:
    """Apply the legacy 24-bit truncation only in legacy mode."""
    return s24(value) if mode == "legacy" else value


def round_shift(product: int, shift: int) -> int:
    """RTL rounding: (p >> shift) + bit (shift-1), i.e. floor(p/2^s) + round bit.

    This is the exact behaviour of ``product[24:1] + product[0]`` and friends:
    an arithmetic shift (floor towards -inf) plus half an LSB.  It is not
    round-half-away-from-zero; the difference matters for negative odd
    products and is recorded in the contract.
    """
    return (product >> shift) + ((product >> (shift - 1)) & 1)


@dataclass
class Voice:
    envelope: int = 0
    velocity: int = 0
    phase: int = 0
    increment: int = 0
    bank: int = 0
    weight: int = 0
    retrigger: bool = False


@dataclass
class Tables:
    sine: list
    banks: list
    depth: int = DEPTH

    def read(self, bank: int, index: int) -> int:
        return self.banks[bank][index % self.depth]

    def read_sine(self, index: int) -> int:
        return self.sine[index % self.depth]


@dataclass
class Datapath:
    """instrument_ram_audio_compute + wide_master, VOICES=32 lane model."""
    tables: Tables
    voices: int = 32
    voice_shift: int = 5
    mode: str = "wide"
    pressure_low: int = 128
    pressure_full: int = 3200
    pressure_min_gain_q12: int = 1024
    gain_step: int = 32
    stress_wrap: bool = False          # force the constructible overflow case
    state: list = field(init=False)
    weight_state: int = field(init=False, default=64)
    gain_q12: int = field(init=False, default=4096)
    gain_prod: int = field(init=False, default=0)
    combined_gain: int = field(init=False, default=0)
    wrap_events: dict = field(init=False, default_factory=dict)

    def __post_init__(self):
        self.state = [Voice() for _ in range(self.voices)]

    # ---------------------------------------------------------- config -----
    def configure(self, voice: int, *, increment=None, envelope=None, velocity=None,
                  retrigger=None, bank=None, weight=None) -> None:
        v = self.state[voice]
        if envelope is not None:
            v.envelope = envelope & 0xFFFF
        if velocity is not None:
            v.velocity = velocity & 0x7F
        if retrigger is not None:
            v.retrigger = bool(retrigger)
        if increment is not None:
            v.increment = increment & 0xFFFFFFFF
        if bank is not None:
            v.bank = bank & 0x3F
        if weight is not None:
            v.weight = weight & 0xFFFF

    # ------------------------------------------------------ per voice ------
    def _interp_delta(self, product: int) -> int:
        raw = round_shift(product, 1)
        out = trunc(raw, self.mode)
        if out != raw:
            self._note("interp_delta")
        return out

    def _amp_delta(self, product: int, shift: int = 16) -> int:
        raw = round_shift(product, shift)
        out = trunc(raw, self.mode)
        if out != raw:
            self._note("amplitude_delta")
        return out

    def _note(self, name: str) -> None:
        self.wrap_events[name] = self.wrap_events.get(name, 0) + 1

    def voice_sample(self, index: int) -> tuple[int, int]:
        """Return the (sine, instrument) contribution of one voice."""
        v = self.state[index]
        if v.retrigger:
            v.phase = 0
            v.retrigger = False
        else:
            v.phase = (v.phase + v.increment) & 0xFFFFFFFF
        audible = v.envelope != 0 and v.velocity != 0
        if not audible:
            return 0, 0
        n = (v.phase >> 23) & 0x1FF
        frac = (v.phase >> 14) & 0x1FF
        bank_hi = 47 if v.bank >= 47 else v.bank + 1

        s0 = self.tables.read_sine(n)
        s1 = self.tables.read_sine(n + 1)
        b0 = self.tables.read(v.bank, n)
        b1 = self.tables.read(v.bank, n + 1)
        c0 = self.tables.read(bank_hi, n)
        c1 = self.tables.read(bank_hi, n + 1)

        if self.stress_wrap:
            # Force the constructible overflow: a full-scale sign step.
            s0, s1 = -32768, 32767
            b0, b1 = -32768, 32767
            c0, c1 = 32767, -32768

        delta_s = self._interp_delta((s1 - s0) * frac)
        delta_b = self._interp_delta((b1 - b0) * frac)
        delta_c = self._interp_delta((c1 - c0) * frac)
        interp_s = trunc((s0 << 8) + delta_s, self.mode)
        interp_b = trunc((b0 << 8) + delta_b, self.mode)
        bank_interp = trunc((c0 << 8) + delta_c, self.mode)
        if self.mode == "legacy" and interp_s != (s0 << 8) + delta_s:
            self._note("interp_sum")

        mix = self._amp_delta((bank_interp - interp_b) * v.weight)
        interp_b_new = trunc(interp_b + mix, self.mode)

        env_s = self._amp_delta(interp_s * v.envelope)
        env_b = self._amp_delta(interp_b_new * v.envelope)
        amp_s = self._amp_delta(env_s * v.velocity, 7)
        amp_b = self._amp_delta(env_b * v.velocity, 7)
        return amp_s, amp_b

    # ----------------------------------------------------------- frame -----
    def frame(self, *, mix_weight: int, pressure_enable: bool, pressure_level: int,
              mute: bool, volume_gain_q8: int) -> dict:
        sine_acc = 0
        bright_acc = 0
        for index in range(self.voices):
            amp_s, amp_b = self.voice_sample(index)
            sine_acc = s32(sine_acc + amp_s)
            bright_acc = s32(bright_acc + amp_b)
        return self.frame_from_sums(sine_acc, bright_acc, mix_weight=mix_weight,
                                    pressure_enable=pressure_enable,
                                    pressure_level=pressure_level, mute=mute,
                                    volume_gain_q8=volume_gain_q8)

    def frame_from_sums(self, sine_acc: int, bright_acc: int, *, mix_weight: int,
                        pressure_enable: bool, pressure_level: int,
                        mute: bool, volume_gain_q8: int) -> dict:
        """wide_master arithmetic for one frame given the lane totals."""
        # wide_master state 0
        if mix_weight > self.weight_state:
            active_weight = self.weight_state + 1
        elif mix_weight < self.weight_state:
            active_weight = self.weight_state - 1
        else:
            active_weight = self.weight_state
        frame_weight = active_weight
        self.weight_state = active_weight

        target_gain = self._target_gain(pressure_enable, pressure_level, mute)
        self.gain_prod = target_gain * volume_gain_q8
        # state 6
        self.combined_gain = min(self.gain_prod >> 8, 4096)
        # state 7
        target = self.combined_gain
        if target > self.gain_q12 and target - self.gain_q12 > self.gain_step:
            frame_gain = self.gain_q12 + self.gain_step
        elif self.gain_q12 > target and self.gain_q12 - target > self.gain_step:
            frame_gain = self.gain_q12 - self.gain_step
        else:
            frame_gain = target
        self.gain_q12 = frame_gain

        # state 1
        base = (sine_acc << 8) - sine_acc + (1 << (7 + self.voice_shift))
        product = (bright_acc - sine_acc) * frame_weight
        master_sample = (base + product) >> (8 + self.voice_shift)
        # state 3-5
        output = (master_sample * frame_gain + 2048) >> 12
        clipped = output > 8388607 or output < -8388608
        sample = max(-8388608, min(8388607, output))
        return {
            "sine_total": sine_acc,
            "bright_total": bright_acc,
            "sample": sample,
            "clipped": clipped,
            "frame_weight": frame_weight,
            "frame_gain": frame_gain,
            "combined_gain": self.combined_gain,
        }

    def _target_gain(self, pressure_enable: bool, pressure_level: int, mute: bool) -> int:
        span = self.pressure_full - self.pressure_low
        gain_span = 4096 - self.pressure_min_gain_q12
        delta = (pressure_level - self.pressure_low) & 0xFFF
        if span == gain_span:
            mapped = delta
        else:
            mapped = (delta * gain_span) // span
        if pressure_level <= self.pressure_low:
            calibrated = self.pressure_min_gain_q12
        elif pressure_level >= self.pressure_full:
            calibrated = 4096
        else:
            calibrated = self.pressure_min_gain_q12 + mapped
        if mute:
            return 0
        return calibrated if pressure_enable else 4096
