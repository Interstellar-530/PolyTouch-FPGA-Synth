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

# Quarter note = 66 BPM, which is a walking pace rather than the previous
# 92 BPM.  The debug sample rate is 27e6 / 18 / 32 = 46875 Hz and one tick is
# an eighth of a beat, so a tick is about 114 ms and a note about 0.46 s.
BPM = 66
SAMPLE_RATE = 46875
TICK_SAMPLES = 5327          # round(60 / 66 / 8 * 46875)
TICKS_PER_PHRASE = 36

# The melody is played staccato: GAP_TICKS of every note's slot is silence, so
# the listener hears where one note stops and the next starts.
GAP_TICKS = 2

# Velocity codes stored in the melody ROM.  Three bits per note, so the phrase
# head can be accented without a second ROM.
VELOCITY_CODES = (0, 32, 56, 72, 88, 104, 120, 127)
MELODY_ACCENT_CODE = 7       # first note of every phrase
MELODY_NORMAL_CODE = 5

# (lyric, [(degree, length in ticks), ...]); five syllables per phrase.
PHRASES = [
    ("我从山中来", [(6, 6), (3, 6), (3, 6), (3, 6), (3, 12)]),
    ("带着兰花草", [(2, 6), (1, 6), (2, 6), (1, 6), (7, 12)]),
    ("种在小院中", [(6, 6), (6, 6), (6, 6), (6, 6), (6, 12)]),
    ("希望花开早", [(5, 6), (3, 6), (5, 6), (5, 6), ("4#", 12)]),
    ("一日看三回", [(3, 6), (6, 6), (6, 6), (5, 6), (3, 12)]),
    ("看得花时过", [(2, 6), (1, 6), (2, 6), (1, 6), (7, 12)]),
    ("兰花却依然", [(6, 6), (3, 6), (3, 6), (1, 6), (1, 12)]),
    ("苞也无一个", [(7, 6), (6, 6), (3, 6), (2, 6), (1, 12)]),
    ("尾声",       [(6, 36)]),
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

# The accompaniment sits well below the melody so the tune is the part the ear
# follows.  A sustained triad at 32 against a staccato melody at 104..127 is
# roughly 8 to 10 dB of separation.
CHORD_VELOCITY = 32

ROM_WIDTH = 16
MELODY_ROM_DEPTH = 64
CHORD_ROM_DEPTH = 16


def melody_events():
    """Flatten PHRASES into (midi_note, slot_ticks, velocity_code) tuples.

    slot_ticks is the spacing between note starts, not the sounding length:
    the player silences each note GAP_TICKS before the next one starts.
    """
    events = []
    for _lyric, notes in PHRASES:
        for index, (degree, ticks) in enumerate(notes):
            code = MELODY_ACCENT_CODE if index == 0 else MELODY_NORMAL_CODE
            events.append((DEGREE_MIDI[degree], ticks, code))
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
    """16-bit entries: {velocity_code[2:0], note[6:0], slot_ticks[5:0]}."""
    entries = []
    for note, ticks, code in melody_events():
        entries.append(((code & 0x7) << 13) | ((note & 0x7F) << 6) | (ticks & 0x3F))
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

    melody = melody_events()
    melody_len = len(melody)
    if melody_len > MELODY_ROM_DEPTH:
        problems.append(f"melody has {melody_len} entries, ROM depth is {MELODY_ROM_DEPTH}")
    for note, ticks, code in melody:
        if not (0 < note < 128):
            problems.append(f"melody note {note} is out of MIDI range")
        if ticks < GAP_TICKS + 1 or ticks > 63:
            problems.append(f"melody slot {ticks} does not fit the ROM field or is shorter than the gap")
        if not (0 <= code < len(VELOCITY_CODES)):
            problems.append(f"melody velocity code {code} is out of range")

    for name in ("A", "B"):
        events = chord_events(name)
        if len(events) > CHORD_ROM_DEPTH:
            problems.append(f"chord set {name} has {len(events)} entries, ROM depth is {CHORD_ROM_DEPTH}")
        chord_ticks = sum(t for _r, _q, t in events)
        melody_ticks = sum(t for _n, t, _c in melody)
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
    events = melody_events()
    total = sum(t for _n, t, _c in events)
    sounding = sum(t - GAP_TICKS for _n, t, _c in events)
    print("melody entries:", len(events), " total ticks:", total,
          " duration:", round(total * TICK_SAMPLES / SAMPLE_RATE, 2), "s")
    print(f"tick {TICK_SAMPLES} samples ({TICK_SAMPLES / SAMPLE_RATE * 1000:.1f} ms), "
          f"gap {GAP_TICKS} ticks ({GAP_TICKS * TICK_SAMPLES / SAMPLE_RATE * 1000:.1f} ms), "
          f"sounding {sounding / total * 100:.0f}% of the slot")
    print("chord set A:", CHORD_SETS["A"])
    print("chord set B:", CHORD_SETS["B"])
