"""Write the melody and chord ROM images and the note table constants.

Run from the source root:
    python tools/gen_song_rom.py

It writes rtl/audio/song_melody.hex, song_chords_a.hex and song_chords_b.hex,
and prints the twelve note_phase_inc base constants so the Verilog table can be
checked against the model.
"""

import os

import song_data


def write_hex(path, entries, depth):
    lines = [f"{value:04x}" for value in entries]
    lines += ["0000"] * (depth - len(entries))
    with open(path, "w", encoding="ascii", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")
    print(f"wrote {path}: {len(entries)} entries used, depth {depth}")


def main():
    issues = song_data.check()
    if issues:
        for issue in issues:
            print("FAIL:", issue)
        raise SystemExit(1)

    here = os.path.dirname(os.path.abspath(__file__))
    rtl = os.path.normpath(os.path.join(here, "..", "rtl", "audio"))

    write_hex(os.path.join(rtl, "song_melody.hex"),
              song_data.melody_rom_image(), song_data.MELODY_ROM_DEPTH)
    write_hex(os.path.join(rtl, "song_chords_a.hex"),
              song_data.chord_rom_image("A"), song_data.CHORD_ROM_DEPTH)
    write_hex(os.path.join(rtl, "song_chords_b.hex"),
              song_data.chord_rom_image("B"), song_data.CHORD_ROM_DEPTH)

    # note_phase_inc base table: phase_inc = round(f * 2^32 / 46875) for the
    # twelve semitones starting at MIDI 0 (C-1).
    scale = 2.0 ** (1.0 / 12.0)
    f0 = 440.0 * (2.0 ** ((0 - 69) / 12.0))
    factor = (2 ** 32) / song_data.SAMPLE_RATE
    print("note_phase_inc base constants (MIDI 0..11):")
    for i in range(12):
        value = int(round(f0 * (scale ** i) * factor))
        if value > 0xFFFFFFFF:
            raise SystemExit("base constant overflows 32 bits")
        print(f"  4'd{i:<2d}: base = 32'd{value};")


if __name__ == "__main__":
    main()
