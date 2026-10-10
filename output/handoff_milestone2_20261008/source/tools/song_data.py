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

# Quarter note = 92 BPM, debug sample rate = 27e6 / 18 / 32 = 46875 Hz.
# One tick is an eighth of a beat; one phrase is four beats, i.e. 32 ticks.
BPM = 92
SAMPLE_RATE = 46875
TICK_SAMPLES = 3821          # round(60 / 92 / 8 * 46875)
TICKS_PER_PHRASE = 32

# (lyric, [(degree, length in ticks), ...]); five syllables per phrase.
PHRASES = [
    ("我从山中来", [(6, 4), (3, 4), (3, 4), (3, 4), (3, 16)]),
    ("带着兰花草", [(2, 4), (1, 4), (2, 4), (1, 4), (7, 16)]),
    ("种在小院中", [(6, 4), (6, 4), (6, 4), (6, 4), (6, 16)]),
    ("希望花开早", [(5, 4), (3, 4), (5, 4), (5, 4), ("4#", 16)]),
    ("一日看三回", [(3, 4), (6, 4), (6, 4), (5, 4), (3, 16)]),
    ("看得花时过", [(2, 4), (1, 4), (2, 4), (1, 4), (7, 16)]),
    ("兰花却依然", [(6, 4), (3, 4), (3, 4), (1, 4), (1, 16)]),
    ("苞也无一个", [(7, 4), (6, 4), (3, 4), (2, 4), (1, 16)]),
    ("尾声",       [(6, 32)]),
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

# Velocities leave the mixer room: the melody leads and the three chord voices
# together stay below it, so the sum never hits the saturator.
MELODY_VELOCITY = 96
CHORD_VELOCITY = 56

ROM_WIDTH = 16
MELODY_ROM_DEPTH = 64
CHORD_ROM_DEPTH = 16


def melody_events():
    """Flatten PHRASES into the list of (midi_note, ticks) written to the ROM."""
    events = []
    for _lyric, notes in PHRASES:
        for degree, ticks in notes:
            events.append((DEGREE_MIDI[degree], ticks))
    return events


def chord_events(set_name):
    """Flatten one chord set into the list of (root, quality, ticks)."""
    events = []
    for name in CHORD_SETS[set_name]:
        root, quality = CHORD_VOICING[name]
        events.append((root, quality, TICKS_PER_PHRASE))
    return events


def triad(root, quality):
    """Return the three MIDI notes of the triad."""
    third = 4 if quality == 0 else 3
    return [root, root + third, root + 7]


def melody_rom_image():
    """16-bit entries: {note[7:0], ticks[7:0]}; note 0 means a rest."""
    entries = []
    for note, ticks in melody_events():
        entries.append(((note & 0xFF) << 8) | (ticks & 0xFF))
    return entries


def chord_rom_image(set_name):
    """16-bit entries: {root[7:0], ticks[5:0], quality[1:0]}."""
    entries = []
    for root, quality, ticks in chord_events(set_name):
        entries.append(((root & 0xFF) << 8) | ((ticks & 0x3F) << 2) | (quality & 0x3))
    return entries


def check():
    """Consistency checks that must hold before the ROMs are written."""
    problems = []

    for index, (lyric, notes) in enumerate(PHRASES):
        total = sum(t for _d, t in notes)
        if total != TICKS_PER_PHRASE:
            problems.append(f"phrase {lyric} spans {total} ticks, not {TICKS_PER_PHRASE}")
        # Every sung phrase carries five syllables; the closing phrase is one
        # long tonic and is allowed to break that rule.
        if index < len(PHRASES) - 1 and len(notes) != 5:
            problems.append(f"phrase {lyric} has {len(notes)} notes, not 5")
        for degree, _t in notes:
            if degree not in DEGREE_MIDI:
                problems.append(f"phrase {lyric} uses unknown degree {degree}")

    melody_len = len(melody_events())
    if melody_len > MELODY_ROM_DEPTH:
        problems.append(f"melody has {melody_len} entries, ROM depth is {MELODY_ROM_DEPTH}")

    for name in ("A", "B"):
        events = chord_events(name)
        if len(events) > CHORD_ROM_DEPTH:
            problems.append(f"chord set {name} has {len(events)} entries, ROM depth is {CHORD_ROM_DEPTH}")
        chord_ticks = sum(t for _r, _q, t in events)
        melody_ticks = sum(t for _n, t in melody_events())
        if chord_ticks != melody_ticks:
            problems.append(f"chord set {name} spans {chord_ticks} ticks "
                            f"but the melody spans {melody_ticks}")

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
    print("song_data: all checks passed")
    print("melody entries:", len(melody_events()),
          " total ticks:", sum(t for _n, t in melody_events()),
          " duration:", round(sum(t for _n, t in melody_events()) * TICK_SAMPLES / SAMPLE_RATE, 2), "s")
    print("chord set A:", CHORD_SETS["A"])
    print("chord set B:", CHORD_SETS["B"])
