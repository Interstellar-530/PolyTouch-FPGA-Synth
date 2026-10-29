"""Render the test tune with the same arithmetic the RTL uses.

This is the golden model for the four-voice chain.  It mirrors
dds_osc -> adsr -> poly_voice -> voice_alloc -> mixer sample by sample, so the
WAV it writes is a preview of what the board should sound like and the peak
level it prints is something a GAO capture can be compared against.

    python tools/render_preview.py [out.wav] [chord_set]
"""

import math
import os
import struct
import sys
import wave

import song_data

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, ".."))

PHASE_BITS = 32
TABLE_BITS = 9
TABLE_SIZE = 1 << TABLE_BITS
MASK32 = 0xFFFFFFFF

ATTACK_STEP = 140
DECAY_STEP = 16
RELEASE_STEP = 48
SUSTAIN_LEVEL = 45875
# Must match mixer.v VOLUME_SHIFT: 1 means the master level is -6 dB.
VOLUME_SHIFT = 1

# Arrangement mock-up only (not the four-voice RTL chain).
BASS_VEL = 40
ARP_VEL = 20
COLOR_VEL = 22
DOUBLE_VEL = 26


def load_wave():
    values = []
    path = os.path.join(SRC, "rtl", "audio", "wave_sine.hex")
    with open(path, "r", encoding="ascii") as handle:
        for line in handle:
            token = line.strip()
            if not token:
                continue
            raw = int(token, 16)
            values.append(raw - 0x10000 if raw & 0x8000 else raw)
    if len(values) != TABLE_SIZE:
        raise SystemExit(f"wave table has {len(values)} entries, expected {TABLE_SIZE}")
    return values


def phase_inc_for(note):
    scale = 2.0 ** (1.0 / 12.0)
    f0 = 440.0 * (2.0 ** ((0 - 69) / 12.0))
    return int(round(f0 * (scale ** note) * (2 ** 32) / song_data.SAMPLE_RATE)) & MASK32


class Voice:
    """Mirrors dds_osc + adsr + the velocity scale in poly_voice."""

    def __init__(self):
        self.note = 0
        self.gate = False
        self.vel = 0
        self.phase = 0
        self.age = 0
        self.env = 0
        self.state = "IDLE"

    @property
    def idle(self):
        return self.state == "IDLE"

    def step(self, table):
        self.phase = (self.phase + (phase_inc_for(self.note) if self.note else 0)) & MASK32

        idx_a = (self.phase >> (PHASE_BITS - TABLE_BITS)) & (TABLE_SIZE - 1)
        idx_b = (idx_a + 1) & (TABLE_SIZE - 1)
        frac = (self.phase >> (PHASE_BITS - TABLE_BITS - 9)) & 0x1FF
        ya, yb = table[idx_a], table[idx_b]
        interp = max(-32768, min(32767, ya + (((yb - ya) * frac + 256) >> 9)))

        self._adsr()
        voiced = (interp * self.env) >> 16
        return (voiced * self.vel) >> 7

    def _adsr(self):
        if self.state == "IDLE":
            self.env = 0
            if self.gate:
                self.state = "ATTACK"
        elif self.state == "ATTACK":
            if self.env >= 0xFFFF - ATTACK_STEP:
                self.env, self.state = 0xFFFF, "DECAY"
            else:
                self.env += ATTACK_STEP
        elif self.state == "DECAY":
            if self.env <= SUSTAIN_LEVEL + DECAY_STEP:
                self.env, self.state = SUSTAIN_LEVEL, "SUSTAIN"
            else:
                self.env -= DECAY_STEP
        elif self.state == "SUSTAIN":
            self.env = SUSTAIN_LEVEL
            if not self.gate:
                self.state = "RELEASE"
        elif self.state == "RELEASE":
            if self.env <= RELEASE_STEP:
                self.env, self.state = 0, "IDLE"
            else:
                self.env -= RELEASE_STEP


class Allocator:
    """Mirrors voice_alloc: idle first, then oldest released, then oldest held."""

    def __init__(self, count=4):
        self.voices = [Voice() for _ in range(count)]
        self.age = 0

    def note_on(self, note, vel):
        free = [v for v in self.voices if v.idle and not v.gate]
        if free:
            target = free[0]
        else:
            pool = [v for v in self.voices if not v.gate] or self.voices
            target = min(pool, key=lambda v: v.age)
        target.note, target.vel, target.gate, target.age = note, vel, True, self.age
        # The RTL restarts phase and envelope on every note-on, including a
        # repeated note that reuses its own voice.  Mirror that here so the
        # preview articulates repeated pitches instead of gluing them together.
        target.phase = 0
        target.env = 0
        target.state = "ATTACK"
        self.age += 1

    def note_off(self, note):
        for v in self.voices:
            if v.gate and v.note == note:
                v.gate = False

    def panic(self):
        for v in self.voices:
            v.gate = False


def build_script(chord_set):
    """Expand the ROMs into a note on/off script on the tick grid."""
    script = {}

    tick = 0
    for note, slot, code in song_data.melody_events():
        gap = song_data.gap_units(slot)
        if note:
            script.setdefault(tick, []).append(
                ("on", note, song_data.VELOCITY_CODES[code]))
            # The RTL releases the voice gap units before the slot ends; a
            # one-unit slot is released on the next slot boundary instead.
            release = max(1, slot - gap)
            script.setdefault(tick + release, []).append(("off", note))
        tick += slot

    tick, prev_triad = 0, []
    chord_vel = song_data.CHORD_VELOCITY[0 if chord_set == "A" else 1]
    for root, quality, length in song_data.chord_events(chord_set):
        for note in prev_triad:
            script.setdefault(tick, []).append(("off", note))
        triad = song_data.triad(root, quality)
        for note in triad:
            script.setdefault(tick, []).append(("on", note, chord_vel))
        prev_triad = triad
        tick += length

    # The RTL emits every note-off before any note-on in the same burst.
    for key, items in script.items():
        offs = [i for i in items if i[0] == "off" and i[1] is not None]
        ons = [i for i in items if i[0] == "on"]
        script[key] = offs + ons
    return script


def build_arranged_script(chord_set):
    """Eight-voice arrangement mock-up: melody, pad triad, bass, arp, colour,
    and a melody double.

    This is NOT the four-voice RTL chain.  It is an audition of the arrangement
    we intend to port to the eight-voice engine (extra voices need more event
    slots in song_player.v).
    """
    script = build_script(chord_set)
    tick = 0
    for root, quality, length in song_data.chord_events(chord_set):
        triad = song_data.triad(root, quality)
        bass = root - 12
        script.setdefault(tick, []).append(("on", bass, BASS_VEL))
        script.setdefault(tick + length, []).append(("off", bass))
        colour = triad[2] + 12
        script.setdefault(tick, []).append(("on", colour, COLOR_VEL))
        script.setdefault(tick + length, []).append(("off", colour))
        for k in range(0, length, 2):
            note = triad[(k // 2) % 3] + 24
            script.setdefault(tick + k, []).append(("on", note, ARP_VEL))
            script.setdefault(tick + k + 2, []).append(("off", note))
        tick += length

    # Melody double an octave below, at low level, so the lead keeps its edge.
    tick = 0
    for note, slot, code in song_data.melody_events():
        if note:
            low = note - 12
            script.setdefault(tick, []).append(("on", low, DOUBLE_VEL))
            script.setdefault(tick + max(1, slot), []).append(("off", low))
        tick += slot

    for key, items in script.items():
        offs = [i for i in items if i[0] == "off"]
        ons = [i for i in items if i[0] == "on"]
        script[key] = offs + ons
    return script


def render(chord_set="A", tempo_mult=1, arranged=False):
    table = load_wave()
    alloc = Allocator(8 if arranged else 4)
    script = build_arranged_script(chord_set) if arranged else build_script(chord_set)

    unit_samples = song_data.UNIT_SAMPLES * tempo_mult
    total_ticks = song_data.total_slot_units()
    total_samples = total_ticks * unit_samples

    samples = []
    hist = [0, 0, 0, 0]
    peak = 0
    tick = 0
    next_boundary = 0

    for index in range(total_samples):
        if index == next_boundary:
            for item in script.get(tick, []):
                if item[0] == "off":
                    alloc.note_off(item[1])
                else:
                    alloc.note_on(item[1], item[2])
            tick = (tick + 1) % total_ticks
            next_boundary = tick * unit_samples

        total = sum(v.step(table) for v in alloc.voices)
        scaled = (total + (1 << (VOLUME_SHIFT - 1))) >> VOLUME_SHIFT
        mixed = max(-32768, min(32767, scaled))

        hist = [mixed] + hist[:4]
        fir = hist[0] + hist[4] + 4 * (hist[1] + hist[3]) + 6 * hist[2]
        scaled = max(-32768, min(32767, fir >> 4))
        hist = hist[:4]

        samples.append(scaled)
        peak = max(peak, abs(scaled))

    return samples, peak


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        SRC, "..", "artifacts", "wanye_preview.wav")
    chord_set = (sys.argv[2] if len(sys.argv) > 2 else "A").upper()
    tempo_mult = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    arranged = len(sys.argv) > 4 and sys.argv[4].lower() == "arrange"

    issues = song_data.check()
    if issues:
        for issue in issues:
            print("FAIL:", issue)
        raise SystemExit(1)
    if chord_set not in song_data.PASS_CHORDS:
        raise SystemExit(f"unknown chord set {chord_set}")

    samples, peak = render(chord_set, tempo_mult, arranged)
    if peak == 0:
        raise SystemExit("FAIL: the render is silent")

    out = os.path.abspath(out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with wave.open(out, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(song_data.SAMPLE_RATE)
        handle.writeframes(b"".join(struct.pack("<h", s) for s in samples))

    print(f"wrote {out}")
    print(f"{'arrangement mock' if arranged else 'RTL-equivalent'} chord set {chord_set}, "
          f"tempo x{tempo_mult}: {len(samples)} samples, "
          f"{len(samples) / song_data.SAMPLE_RATE:.2f} s, peak {peak} "
          f"({20 * math.log10(peak / 32768.0):.1f} dBFS)")


if __name__ == "__main__":
    main()
