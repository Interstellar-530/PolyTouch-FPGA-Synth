"""Song data for the PolyTouch FPGA test tune.

The melody is a transcription of the public numbered-notation score of
"Lan Hua Cao" (1=bB, 2/4) that was read from a published sheet-music image.
The tune is harmonised in G dorian: degree 6 is the tonic G, and the raised
fourth (#4, the dorian sixth) appears in the fourth phrase exactly as the
score writes it.

Degrees are numbered the way the score numbers them, relative to 1 = Bb.
Nothing here is a recording: the FPGA generates every sample from these
numbers at run time.
"""

# Degree -> MIDI note number.  1 = Bb4, 6 = G4 (the tonic), 7 = A4.
# The melody therefore sits between G4 (392 Hz) and F5 (698 Hz).
DEGREE_MIDI = {
    1: 70,      # Bb4
    2: 72,      # C5
    3: 74,      # D5
    4: 75,      # Eb5
    "4#": 76,   # E5, the raised fourth written as #4 in the score
    5: 77,      # F5
    6: 67,      # G4, tonic
    7: 69,      # A4
}

# --------------------------------------------------------------- rhythm ---
# The score is marked quarter = 72 in 2/4 and its shortest note value is a
# sixteenth, so one tick is a sixteenth note and one beat is four ticks.  The
# debug sample rate is 27e6 / 18 / 32 = 46875 Hz.
#
# Every note is written as its sounding length in sixteenths; the player adds
# the articulation gap itself, see gap_units().
BPM = 72
SAMPLE_RATE = 46875
UNIT_SAMPLES = round(60 / BPM / 4 * SAMPLE_RATE)     # 9766 samples per sixteenth

# The board can stretch every tick by 1x .. 4x at run time with key S2, so one
# bitstream covers both a rehearsal tempo and the written tempo.
TEMPO_PRESETS = (1, 2, 3, 4)
TEMPO_DEFAULT = 1                                     # index 1, i.e. 2x slower

# Velocity codes stored in the melody ROM.  Three bits per note, so the phrase
# head can be accented without a second ROM.
VELOCITY_CODES = (0, 32, 56, 72, 88, 104, 120, 127)
MELODY_ACCENT_CODE = 7       # first note of every phrase
MELODY_NORMAL_CODE = 5

# The accompaniment sits below the melody so the tune is the part the ear
# follows.  A sustained triad at 32 against a melody at 104..127 is roughly
# 8 to 10 dB of separation.
CHORD_VELOCITY = 32

# (lyric, [(degree, sounding length in sixteenths), ...]).
#
# The rhythm follows the score rather than a uniform pulse: the phrases the
# score writes as "6 3 3 3 | 3. 2" are four eighth notes plus a dotted quarter,
# the phrases it writes as "1. 2 1 7" open with a dotted eighth plus sixteenth,
# and "种在小院中" starts on a quarter where the score has "6 -".
#
# A sixteenth at quarter = 72 is about 208 ms, so the player's default 2x
# tempo preset makes one sixteenth about 417 ms and an eighth about 833 ms.
PHRASES = [
    ("我从山中来", [(6, 2), (3, 2), (3, 2), (3, 2), (3, 6)]),
    ("带着兰花草", [(2, 2), (1, 3), (2, 1), (1, 2), (7, 2)]),
    ("种在小院中", [(6, 4), (6, 2), (6, 2), (6, 2), (6, 2)]),
    ("希望花开早", [(5, 2), (3, 2), (5, 2), (5, 2), ("4#", 6)]),
    ("一日看三回", [(3, 2), (6, 2), (6, 2), (5, 2), (3, 6)]),
    ("看得花时过", [(2, 2), (1, 3), (2, 1), (1, 2), (7, 2)]),
    ("兰花却依然", [(6, 2), (3, 3), (3, 1), (1, 2), (1, 2)]),
    ("苞也无一个", [(7, 4), (6, 2), (3, 2), (2, 2), (1, 2)]),
    ("尾声",       [(6, 16)]),
]

# Chord voicings sit below the melody so the two layers stay separated.
# quality 0 = major triad (0, 4, 7), 1 = minor triad (0, 3, 7).
CHORD_VOICING = {
    "Gm": (55, 1),   # G3  Bb3 D4
    "Bb": (58, 0),   # Bb3 D4  F4
    "Cm": (60, 1),   # C4  Eb4 G4
    "F":  (53, 0),   # F3  A3  C4
    "Dm": (62, 1),   # D4  F4  A4
}

# Two harmonisations of the same melody.  One chord per phrase, so the
# key switch is clearly audible while the tune keeps running.
CHORD_SETS = {
    "A": ["Gm", "Cm", "Gm", "F", "Gm", "Cm", "Bb", "Gm", "Gm"],
    "B": ["Bb", "F", "Cm", "Dm", "Bb", "F", "Gm", "Cm", "Gm"],
}

ROM_WIDTH = 16
MELODY_ROM_DEPTH = 64
CHORD_ROM_DEPTH = 16


def gap_units(on_units):
    """Silence appended to a note: a quarter of its length, at least one tick.

    Shortening every note is what makes the line sound separated instead of
    running together, and the one-tick floor keeps even a sixteenth audible.
    """
    return max(1, on_units // 4)


def slot_units(on_units):
    """Total time a note occupies: its sounding length plus its gap."""
    return on_units + gap_units(on_units)


def melody_events():
    """(midi_note, sounding_units, velocity_code) for every melody note."""
    events = []
    for _lyric, notes in PHRASES:
        for index, (degree, on_units) in enumerate(notes):
            code = MELODY_ACCENT_CODE if index == 0 else MELODY_NORMAL_CODE
            events.append((DEGREE_MIDI[degree], on_units, code))
    return events


def phrase_slots():
    """Slot length of each phrase; the chords have to match these exactly."""
    return [sum(slot_units(on) for _d, on in notes) for _lyric, notes in PHRASES]


def total_slot_units():
    return sum(phrase_slots())


def chord_events(set_name):
    """(root, quality, slot_units) for one chord set, one entry per phrase."""
    events = []
    slots = phrase_slots()
    for index, name in enumerate(CHORD_SETS[set_name]):
        root, quality = CHORD_VOICING[name]
        events.append((root, quality, slots[index]))
    return events


def triad(root, quality):
    """Return the three MIDI notes of the triad."""
    third = 4 if quality == 0 else 3
    return [root, root + third, root + 7]


def melody_rom_image():
    """16-bit entries: {velocity_code[2:0], note[6:0], sounding_units[5:0]}."""
    entries = []
    for note, on_units, code in melody_events():
        entries.append(((code & 0x7) << 13) | ((note & 0x7F) << 6) | (on_units & 0x3F))
    return entries


def chord_rom_image(set_name):
    """16-bit entries: {root[7:0], slot_units[5:0], quality[1:0]}."""
    entries = []
    for root, quality, slot in chord_events(set_name):
        entries.append(((root & 0xFF) << 8) | ((slot & 0x3F) << 2) | (quality & 0x3))
    return entries


def check():
    """Consistency checks that must hold before the ROMs are written."""
    problems = []

    for index, (lyric, notes) in enumerate(PHRASES):
        if index < len(PHRASES) - 1 and len(notes) != 5:
            problems.append(f"phrase {lyric} has {len(notes)} notes, not 5")
        for degree, on_units in notes:
            if degree not in DEGREE_MIDI:
                problems.append(f"phrase {lyric} uses unknown degree {degree}")
            if on_units < 1 or on_units > 63:
                problems.append(f"phrase {lyric} note length {on_units} does not fit the ROM field")
            if slot_units(on_units) > 63:
                problems.append(f"phrase {lyric} slot {slot_units(on_units)} does not fit the chord ROM field")

    melody = melody_events()
    if len(melody) > MELODY_ROM_DEPTH:
        problems.append(f"melody has {len(melody)} entries, ROM depth is {MELODY_ROM_DEPTH}")
    for note, on_units, code in melody:
        if not (0 < note < 128):
            problems.append(f"melody note {note} is out of MIDI range")
        if not (0 <= code < len(VELOCITY_CODES)):
            problems.append(f"melody velocity code {code} is out of range")

    for name in ("A", "B"):
        events = chord_events(name)
        if len(events) > CHORD_ROM_DEPTH:
            problems.append(f"chord set {name} has {len(events)} entries, ROM depth is {CHORD_ROM_DEPTH}")
        chord_ticks = sum(t for _r, _q, t in events)
        if chord_ticks != total_slot_units():
            problems.append(f"chord set {name} spans {chord_ticks} ticks "
                            f"but the melody spans {total_slot_units()}")

    if CHORD_SETS["A"] == CHORD_SETS["B"]:
        problems.append("chord sets A and B are identical, the key switch would be inaudible")

    for name, notes in CHORD_VOICING.items():
        root, quality = notes
        if quality not in (0, 1):
            problems.append(f"chord {name} has an invalid quality")
        for n in triad(root, quality):
            if not (0 < n < 128):
                problems.append(f"chord {name} produces an out-of-range MIDI note {n}")

    return problems


if __name__ == "__main__":
    issues = check()
    if issues:
        for issue in issues:
            print("FAIL:", issue)
        raise SystemExit(1)

    events = melody_events()
    total = total_slot_units()
    sounding = sum(on for _n, on, _c in events)
    print("song_data: all checks passed")
    print(f"melody entries {len(events)}, slot total {total} sixteenths "
          f"({total / 4:.1f} beats)")
    print(f"one sixteenth is {UNIT_SAMPLES} samples "
          f"({UNIT_SAMPLES / SAMPLE_RATE * 1000:.1f} ms) at quarter = {BPM} BPM")
    for index, mult in enumerate(TEMPO_PRESETS):
        seconds = total * UNIT_SAMPLES * mult / SAMPLE_RATE
        eighths = 2 * UNIT_SAMPLES * mult / SAMPLE_RATE
        print(f"  preset {index} (x{mult}): song {seconds:.1f} s, "
              f"eighth note {eighths * 1000:.0f} ms"
              + ("  <- default" if index == TEMPO_DEFAULT else ""))
    print(f"melody sounds for {sounding / total * 100:.0f} percent of the slot")
    print("chord set A:", CHORD_SETS["A"])
    print("chord set B:", CHORD_SETS["B"])
