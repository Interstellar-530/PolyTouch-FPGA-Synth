"""Song data for the PolyTouch FPGA test tune.

The melody is a transcription of the chorus of "Wan Ye Wei Yu Wen Hai Tang"
(晚夜微雨问海棠, 镜予歌/喧笑/陈亦洺) from the published piano reduction that
tan8 user 许暮甜 uploaded as "C调无歌词高潮" (score 119727).  The piano score
states quarter = 81 in 4/4 with no key signature, i.e. C major; the original
recording is in E flat and the guitar chord charts put a capo on fret 3, so
this C-major reading is the usual transposed practice key.

The chorus lasts ten bars.  Two passes are stored back to back: 20 bars, 320
sixteenth-note units.  At quarter = 81 that is 59.26 s, which is the "about one
minute" test length asked for, and the tempo is the score's own tempo, not a
slowed-down or stretched version.

Harmony, set A, follows the chorus progression printed in the ktvc8/词曲网
chord-and-melody edition: F G | Am | F G | C | F G | Am | Dm Em | Am | F G |
Am.  Set B is the piano reduction's own left-hand loop, F G | Em Am, repeated;
it fits the same melody because the transcription came from that reduction.
S1 still switches between the two sets on the board.

Every unit is a sixteenth note.  The number stored per note is the SLOT: the
whole time the note owns.  There is no hidden articulation gap any more; the
voice is released exactly on the slot edge, so a note sustains for its full
written value and only an explicit rest (note 0) is silent.  Long notes that
the score leaves hanging without a rest symbol are written as one long slot
instead of a short note followed by an invented rest.
"""

# --------------------------------------------------------------- pitch -----
NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
NOTE_BASE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note(name):
    """'A4' / 'F#5' / 'Bb4' -> MIDI number."""
    letter = name[0].upper()
    rest = name[1:]
    accidental = 0
    while rest and rest[0] in "#b":
        accidental += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    octave = int(rest)
    return 12 * (octave + 1) + NOTE_BASE[letter] + accidental


def note_name(midi):
    return f"{NOTE_NAMES[midi % 12]}{midi // 12 - 1}"


# --------------------------------------------------------------- timing ----
# The two independent published tempo marks are 81 (tan8 piano reduction) and
# 81 (oguitar chord chart); the guitar chart's 93 bars over 4:39 also works out
# to 80 BPM, so 81 is the score tempo, not an interpretation.
BPM = 81
SAMPLE_RATE = 46875                       # debug profile: 27 MHz / 18 / 32
UNIT_SAMPLES = round(60.0 / BPM / 4.0 * SAMPLE_RATE)   # 8681 samples per 16th

# S2 still walks 1x..4x.  The power-on default is now the score tempo (1x);
# the old tune shipped 2x because 72 BPM felt slow, this one does not.
TEMPO_PRESETS = (1, 2, 3, 4)
TEMPO_DEFAULT = 0

# --------------------------------------------------------------- melody ----
# (note-or-0, slot in sixteenths).  0 is a rest.  Every bar must sum to 16.
#
# Bar-by-bar rhythm was read from the reduction's beaming and note spacing:
# dotted eighths, sixteenth pairs, ties written as one longer slot.  Where the
# engraved bar leaves a gap without a rest symbol, the preceding note is held
# through it.  The only silences left are the notated rest at the start of
# bar 1 and the breath before the "晚夜" phrase in bar 9.
PASS_BARS = [
    # 1  "爱恨此消彼长" - the hook picks up after an eighth rest
    [(0, 2), ("A4", 2), ("A4", 2), ("E5", 2), ("D5", 2), ("C5", 2),
     ("B4", 2), ("C5", 2)],
    # 2  "停步回望 我陪你同往"
    [("E5", 6), ("F5", 2), ("E5", 4), ("D5", 2), ("E5", 2)],
    # 3  "念想从未消亡"
    [("A5", 2), ("G5", 1), ("E5", 2), ("D5", 3),
     ("A5", 2), ("G5", 1), ("E5", 2), ("D5", 3)],
    # 4  "踏断红尘不肯相忘" - the E5 is tied and held through the engraved gap
    [("D5", 2), ("E5", 1), ("G5", 2), ("D5", 2),
     ("E5", 6), ("D5", 2), ("E5", 1)],
    # 5  "飞上九天落千丈"
    [("A5", 2), ("G5", 1), ("E5", 2), ("D5", 3),
     ("A5", 2), ("G5", 1), ("E5", 2), ("D5", 3)],
    # 6  "为你闯一趟"
    [("D5", 3), ("E5", 1), ("E5", 2), ("G5", 2),
     ("E5", 4), ("D5", 2), ("E5", 2)],
    # 7  "若你独留远方" - tied D5 held, no extra stroke, then the answer phrase
    [("A5", 2), ("G5", 1), ("E5", 2), ("C5", 2),
     ("D5", 5), ("D5", 2), ("E5", 2)],
    # 8  "谁来与我相望" - quarter C6, then the long dotted A5 through the gap
    [("C6", 4), ("B5", 2), ("A5", 2), ("A5", 6), ("C5", 1), ("C5", 1)],
    # 9  "晚夜微雨问海棠"
    [(0, 2), ("D5", 2), ("C5", 1), ("D5", 1), ("D5", 1), ("E5", 2),
     ("C6", 3), ("B5", 1), ("B5", 2), ("G5", 1)],
    # 10 "用地久天长" - dotted half on the tonic, 3 beats
    [("G5", 2), ("A5", 1), ("A5", 1), ("A5", 12)],
]

# The hook plus its cadence is one pass; the published chorus is sung twice,
# so store it twice.  The player wraps from the last entry to the first.
PASSES = 2

# Velocity codes stored in the melody ROM.  Three bits per note, so the first
# note of every bar can be accented without a second ROM.
VELOCITY_CODES = (0, 32, 56, 72, 88, 104, 120, 127)
MELODY_ACCENT_CODE = 7       # first sounding note of every bar
MELODY_NORMAL_CODE = 5

# Chord loudness per set, indexed by the chord_set signal.
CHORD_VELOCITY = (30, 46)

# --------------------------------------------------------------- chords ----
# quality 0 = major triad (0, 4, 7), 1 = minor triad (0, 3, 7).
CHORD_VOICING = {
    "F":  (53, 0),   # F3  A3  C4
    "G":  (55, 0),   # G3  B3  D4
    "Am": (57, 1),   # A3  C4  E4
    "C":  (48, 0),   # C3  E3  G3
    "Dm": (50, 1),   # D3  F3  A3
    "Em": (52, 1),   # E3  G3  B3
}

# One pass is ten bars.  Chord entries are (name, slot in sixteenths).
PASS_CHORDS = {
    # The ktvc8 chorus chart: F G | Am | F G | C | F G | Am | Dm Em | Am |
    # F G | Am.  The E lead-in belongs to the preceding "如梦几场" phrase and
    # is not part of the hook, so the loop starts on the F-G bar.
    "A": [
        [("F", 8), ("G", 8)],
        [("Am", 8), ("Am", 8)],
        [("F", 8), ("G", 8)],
        [("C", 8), ("C", 8)],
        [("F", 8), ("G", 8)],
        [("Am", 8), ("Am", 8)],
        [("Dm", 8), ("Em", 8)],
        [("Am", 8), ("Am", 8)],
        [("F", 8), ("G", 8)],
        [("Am", 8), ("Am", 8)],
    ],
    # The piano reduction's own left-hand loop, F G | Em Am, five times.
    "B": [
        [("F", 8), ("G", 8)],
        [("Em", 8), ("Am", 8)],
        [("F", 8), ("G", 8)],
        [("Em", 8), ("Am", 8)],
        [("F", 8), ("G", 8)],
        [("Em", 8), ("Am", 8)],
        [("F", 8), ("G", 8)],
        [("Em", 8), ("Am", 8)],
        [("F", 8), ("G", 8)],
        [("Em", 8), ("Am", 8)],
    ],
}

ROM_WIDTH = 16
MELODY_ADDR_BITS = 8
CHORD_ADDR_BITS = 6
MELODY_ROM_DEPTH = 1 << MELODY_ADDR_BITS      # 256
CHORD_ROM_DEPTH = 1 << CHORD_ADDR_BITS        # 64
BAR_UNITS = 16
CHORDS_PER_BAR = 2


def gap_units(slot):
    """Legato: every note sounds for its whole slot.

    Silences are written as explicit rests.  The old model cut a quarter of
    each slot (at least one sixteenth) off every note, which at 81 BPM is a
    185 ms hole after each note and is exactly the stutter heard on the board.
    """
    return 0


def bars():
    """The stored pass, repeated PASSES times."""
    return PASS_BARS * PASSES


def bar_slots():
    return [sum(slot for _n, slot in bar) for bar in bars()]


def total_slot_units():
    return sum(bar_slots())


def melody_events():
    """(midi note or 0, slot, velocity code) for every melody event."""
    events = []
    for bar in bars():
        accent = True
        for name, slot in bar:
            midi = note(name) if name else 0
            code = MELODY_NORMAL_CODE
            if accent and midi:
                code = MELODY_ACCENT_CODE
                accent = False
            elif not midi:
                # a leading rest does not consume the accent
                code = 0
            events.append((midi, slot, code))
    return events


def chord_events(set_name):
    """(root, quality, slot) for one chord set, in playing order."""
    events = []
    for bar in PASS_CHORDS[set_name] * PASSES:
        for name, slot in bar:
            root, quality = CHORD_VOICING[name]
            events.append((root, quality, slot))
    return events


def triad(root, quality):
    third = 4 if quality == 0 else 3
    return [root, root + third, root + 7]


def melody_rom_image():
    """16-bit entries: {velocity_code[2:0], note[6:0], slot[5:0]}."""
    entries = []
    for midi, slot, code in melody_events():
        entries.append(((code & 0x7) << 13) | ((midi & 0x7F) << 6) | (slot & 0x3F))
    return entries


def chord_rom_image(set_name):
    """16-bit entries: {root[7:0], slot[5:0], quality[1:0]}."""
    entries = []
    for root, quality, slot in chord_events(set_name):
        entries.append(((root & 0xFF) << 8) | ((slot & 0x3F) << 2) | (quality & 0x3))
    return entries


def melody_count():
    return len(melody_events())


def melody_sounding_count():
    """Entries that actually start a note; rests occupy a slot but stay silent."""
    return sum(1 for midi, _slot, _code in melody_events() if midi)


def chord_count(set_name):
    return len(chord_events(set_name))


def check():
    """Consistency checks that must hold before the tables are written."""
    problems = []

    for index, bar in enumerate(bars()):
        total = sum(slot for _n, slot in bar)
        if total != BAR_UNITS:
            problems.append(f"bar {index + 1} owns {total} units, not {BAR_UNITS}")
        for name, slot in bar:
            if name and name not in NOTE_BASE and name not in CHORD_VOICING:
                try:
                    note(name)
                except Exception:
                    problems.append(f"bar {index + 1}: cannot read note {name}")
            if slot < 1 or slot > 63:
                problems.append(f"bar {index + 1}: slot {slot} does not fit the ROM field")

    melody = melody_events()
    if len(melody) > MELODY_ROM_DEPTH:
        problems.append(f"melody has {len(melody)} entries, table depth is {MELODY_ROM_DEPTH}")
    for midi, slot, code in melody:
        if not (0 <= midi < 128):
            problems.append(f"melody note {midi} is out of MIDI range")
        if not (0 <= code < len(VELOCITY_CODES)):
            problems.append(f"melody velocity code {code} is out of range")
        if not (0 <= slot <= 63):
            problems.append(f"melody slot {slot} does not fit the ROM field")

    for name in ("A", "B"):
        events = chord_events(name)
        if len(events) > CHORD_ROM_DEPTH:
            problems.append(f"chord set {name} has {len(events)} entries, "
                            f"table depth is {CHORD_ROM_DEPTH}")
        chord_ticks = sum(t for _r, _q, t in events)
        if chord_ticks != total_slot_units():
            problems.append(f"chord set {name} spans {chord_ticks} ticks "
                            f"but the melody spans {total_slot_units()}")
        for _root, _quality, slot in events:
            if slot < 1 or slot > 63:
                problems.append(f"chord set {name} has a slot of {slot} ticks")

    if CHORD_SETS_IDENTICAL():
        problems.append("chord sets A and B are identical, the key switch would be inaudible")

    for name, (root, quality) in CHORD_VOICING.items():
        if quality not in (0, 1):
            problems.append(f"chord {name} has an invalid quality")
        for n in triad(root, quality):
            if not (0 < n < 128):
                problems.append(f"chord {name} produces an out-of-range MIDI note {n}")

    if not (0 <= TEMPO_DEFAULT < len(TEMPO_PRESETS)):
        problems.append("TEMPO_DEFAULT is out of range")

    return problems


def CHORD_SETS_IDENTICAL():
    """Compare the two chord sets as (root, quality, slot) sequences."""
    a = chord_events("A")
    b = chord_events("B")
    return a == b


if __name__ == "__main__":
    issues = check()
    if issues:
        for issue in issues:
            print("FAIL:", issue)
        raise SystemExit(1)

    events = melody_events()
    total = total_slot_units()
    sounding = sum(max(1, slot - gap_units(slot)) for n, slot, _c in events if n)
    print("song_data: all checks passed")
    print(f"bars {len(bars())} ({len(PASS_BARS)} per pass x {PASSES}), "
          f"melody entries {len(events)}, slot total {total} sixteenths "
          f"({total / 4:.0f} beats)")
    print(f"chords A: {len(chord_events('A'))}, B: {len(chord_events('B'))}")
    print(f"one sixteenth is {UNIT_SAMPLES} samples "
          f"({UNIT_SAMPLES / SAMPLE_RATE * 1000:.2f} ms) at quarter = {BPM} BPM")
    print(f"one pass {total // PASSES} units, song "
          f"{total * UNIT_SAMPLES / SAMPLE_RATE:.2f} s at 1x")
    for index, mult in enumerate(TEMPO_PRESETS):
        print(f"  preset {index} (x{mult}): {total * UNIT_SAMPLES * mult / SAMPLE_RATE:.1f} s"
              + ("  <- default" if index == TEMPO_DEFAULT else ""))
    print(f"melody sounds for {sounding / total * 100:.0f} percent of the grid")
    print("chord set A:", [name for bar in PASS_CHORDS["A"] for name, _s in bar])
    print("chord set B:", [name for bar in PASS_CHORDS["B"] for name, _s in bar])
