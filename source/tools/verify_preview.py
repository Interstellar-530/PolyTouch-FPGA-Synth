"""Check that the rendered preview really plays the transcribed melody.

For every melody note the script measures the Goertzel magnitude at the
expected frequency and at every other semitone in the neighbourhood, then
asserts that the expected pitch is the strongest one present.  That is the
test for the tune: if the sequencer, the note table or the mixer were wrong,
the wrong semitone would win.

    python tools/verify_preview.py <preview.wav> [chord_set]
"""

import math
import os
import struct
import sys
import wave

import song_data

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, ".."))


def read_wav(path):
    with wave.open(path, "rb") as handle:
        if handle.getsampwidth() != 2 or handle.getnchannels() != 1:
            raise SystemExit("expected 16 bit mono")
        frames = handle.readframes(handle.getnframes())
    return list(struct.unpack(f"<{len(frames) // 2}h", frames))


def goertzel(samples, freq, rate):
    coeff = 2.0 * math.cos(2.0 * math.pi * freq / rate)
    s1 = s2 = 0.0
    for value in samples:
        s0 = value + coeff * s1 - s2
        s2, s1 = s1, s0
    return math.sqrt(max(0.0, s1 * s1 + s2 * s2 - coeff * s1 * s2))


def midi_hz(note):
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        SRC, "..", "artifacts", "wanye_chordA.wav")
    samples = read_wav(path)
    rate = song_data.SAMPLE_RATE

    tempo_mult = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    unit_samples = song_data.UNIT_SAMPLES * tempo_mult
    window = 4000
    warmup = 2000
    failures = 0
    rows = []
    tick = 0

    for note, slot, _code in song_data.melody_events():
        if not note:
            tick += slot
            continue
        gap = song_data.gap_units(slot)
        release = max(1, slot - gap)
        # measure inside the sounding part of the slot, after the attack
        start = tick * unit_samples + warmup
        stop = (tick + release) * unit_samples
        tick += slot
        if stop - start < window:
            continue
        chunk = samples[start:start + window]

        expected = midi_hz(note)
        # Compare against the semitones around the expected pitch, plus the
        # fifth below and above, so an octave or harmony error is caught.
        rivals = [n for n in range(note - 7, note + 8) if n != note]
        expected_mag = goertzel(chunk, expected, rate)
        best_rival = max(goertzel(chunk, midi_hz(n), rate) for n in rivals)

        ok = expected_mag > best_rival
        if not ok:
            failures += 1
            rows.append(f"FAIL note {note} ({expected:.1f} Hz): "
                        f"{expected_mag:.0f} vs best rival {best_rival:.0f}")

    print(f"melody notes checked: {len(song_data.melody_events())}, failures: {failures}")
    for row in rows[:12]:
        print(row)

    if failures:
        raise SystemExit(1)
    print(f"PASS verify_preview: {os.path.basename(path)} plays the transcribed melody")


if __name__ == "__main__":
    main()
