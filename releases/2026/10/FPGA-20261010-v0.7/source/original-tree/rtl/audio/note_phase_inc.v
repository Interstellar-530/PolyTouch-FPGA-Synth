// MIDI note number -> 32 bit DDS phase increment.
//
// The audio sample rate of the on-board debug path is 46875 Hz
// (27 MHz / 18 / 32), so a frequency f becomes
//
//     phase_inc = round(f * 2^32 / 46875)
//
// Only one chromatic octave is stored, starting at MIDI 0.  Every other note
// is the same constant shifted left by the octave number, because shifting a
// phase increment by one bit is exactly one octave.  Twelve constants keep
// this in ordinary logic; the values were produced by tools/gen_song_rom.py,
// and this is a frequency table rather than audio data, so a case statement is
// the right implementation.
module note_phase_inc (
    input  wire [6:0]  note,
    output reg  [31:0] inc
);

    reg  [31:0] base;
    wire [6:0]  semi     = note % 7'd12;
    wire [6:0]  oct_full = note / 7'd12;
    wire [3:0]  oct      = oct_full[3:0];

    always @(*) begin
        case (semi)
            7'd0:  base = 32'd749115;    // C
            7'd1:  base = 32'd793660;    // C#
            7'd2:  base = 32'd840854;    // D
            7'd3:  base = 32'd890853;    // D#
            7'd4:  base = 32'd943826;    // E
            7'd5:  base = 32'd999949;    // F
            7'd6:  base = 32'd1059409;   // F#
            7'd7:  base = 32'd1122405;   // G
            7'd8:  base = 32'd1189147;   // G#
            7'd9:  base = 32'd1259857;   // A
            7'd10: base = 32'd1334772;   // A#
            default: base = 32'd1414142; // B
        endcase
        inc = base << oct;
    end

endmodule
