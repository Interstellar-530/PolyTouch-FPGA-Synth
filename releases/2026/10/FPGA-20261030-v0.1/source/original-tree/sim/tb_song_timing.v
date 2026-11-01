`timescale 1ns/1ps

// Check that one pass through the tune really takes the length the song data
// says it does, and that every melody note and every chord note is emitted
// exactly once per pass.
//
// The expected numbers come from the same generated header the RTL uses, so a
// change to the song data cannot silently stop being tested.
//
// The running instance deliberately overrides UNIT_SAMPLES to 97 so the two
// full passes finish quickly; the shipped 8681-sample unit is checked on a
// second instance that is held in reset, together with MELODY_LAST and
// CHORD_LAST.  What the long run proves is the unit count and the event count,
// which are the parts the tables can get wrong; the sample constant itself is
// a single parameter and is compared against song_expect.vh.
module tb_song_timing;
    parameter SAMPLE_DIV    = 1;
    parameter FAST_UNIT     = 97;
    parameter TEMPO_SEL     = 2'd0;      // the shipped power-on default: 1x
    parameter MAX_TICKS     = 2000000;

    `include "rtl/audio/song_expect.vh"

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg sample_tick = 1'b0;
    reg restart = 1'b0;
    reg chord_set = 1'b0;
    reg [1:0] tempo_sel = TEMPO_SEL;

    wire        ev_wr;
    wire [15:0] ev_data;
    wire [7:0]  mel_idx_dbg;
    wire [5:0]  chord_idx_dbg;

    // Running instance: shortened unit so both passes fit in a short gate.
    song_player #(.UNIT_SAMPLES(FAST_UNIT)) dut (
        .clk          (clk),
        .rst          (rst),
        .sample_tick  (sample_tick),
        .restart      (restart),
        .chord_set    (chord_set),
        .tempo_sel    (tempo_sel),
        .ev_ready     (1'b1),
        .ev_wr        (ev_wr),
        .ev_data      (ev_data),
        .mel_idx_dbg  (mel_idx_dbg),
        .chord_idx_dbg(chord_idx_dbg)
    );

    // Parameter reference instance: never leaves reset, only its defaults are
    // inspected below.
    song_player dut_default (
        .clk          (clk),
        .rst          (1'b1),
        .sample_tick  (1'b0),
        .restart      (1'b0),
        .chord_set    (1'b0),
        .tempo_sel    (2'd0),
        .ev_ready     (1'b1),
        .ev_wr        (),
        .ev_data      (),
        .mel_idx_dbg  (),
        .chord_idx_dbg()
    );

    always #5 clk = ~clk;

    reg [3:0] div = 4'd0;
    always @(posedge clk) begin
        if (div == SAMPLE_DIV - 1) begin
            div <= 4'd0;
            sample_tick <= 1'b1;
        end else begin
            div <= div + 4'd1;
            sample_tick <= 1'b0;
        end
    end

    localparam integer EXPECTED_PASS_TICKS =
        SONG_TOTAL_UNITS * FAST_UNIT * (TEMPO_SEL + 1);
    localparam integer EXPECTED_NOTE_ONS =
        SONG_MELODY_NOTES + SONG_CHORD_NOTES;

    integer ticks = 0;
    integer note_ons = 0;
    integer last_wrap = 0;
    integer last_wrap_notes = 0;
    integer wraps = 0;
    reg [7:0] mel_d = 8'd0;

    always @(posedge clk) begin
        if (sample_tick)
            ticks = ticks + 1;

        if (ev_wr && ev_data[15] && (ev_data[14:8] != 8'd0))
            note_ons = note_ons + 1;

        mel_d <= mel_idx_dbg;
        if ((mel_idx_dbg == 8'd0) && (mel_d != 8'd0)) begin
            wraps = wraps + 1;
            $display("pass %0d complete at tick %0d, delta %0d, note ons %0d",
                     wraps, ticks, ticks - last_wrap, note_ons - last_wrap_notes);
            if (wraps >= 2) begin
                if ((ticks - last_wrap) != EXPECTED_PASS_TICKS)
                    $fatal(1, "FAIL tb_song_timing: pass is %0d ticks, expected %0d",
                           ticks - last_wrap, EXPECTED_PASS_TICKS);
                if ((note_ons - last_wrap_notes) != EXPECTED_NOTE_ONS)
                    $fatal(1, "FAIL tb_song_timing: %0d note events, expected %0d",
                           note_ons - last_wrap_notes, EXPECTED_NOTE_ONS);
                $display("PASS tb_song_timing: pass = %0d ticks, %0d note events",
                         EXPECTED_PASS_TICKS, EXPECTED_NOTE_ONS);
                $finish;
            end
            last_wrap = ticks;
            last_wrap_notes = note_ons;
        end
    end

    initial begin
        #200;
        if (dut_default.MELODY_LAST != SONG_MELODY_LAST)
            $fatal(1, "FAIL tb_song_timing: MELODY_LAST %0d, header says %0d",
                   dut_default.MELODY_LAST, SONG_MELODY_LAST);
        if (dut_default.CHORD_LAST != SONG_CHORD_LAST)
            $fatal(1, "FAIL tb_song_timing: CHORD_LAST %0d, header says %0d",
                   dut_default.CHORD_LAST, SONG_CHORD_LAST);
        if (dut_default.UNIT_SAMPLES != SONG_UNIT_SAMPLES)
            $fatal(1, "FAIL tb_song_timing: UNIT_SAMPLES %0d, header says %0d",
                   dut_default.UNIT_SAMPLES, SONG_UNIT_SAMPLES);
        rst = 1'b0;
        $display("expecting pass = %0d units x %0d samples x %0d = %0d ticks, %0d note events",
                 SONG_TOTAL_UNITS, FAST_UNIT, TEMPO_SEL + 1,
                 EXPECTED_PASS_TICKS, EXPECTED_NOTE_ONS);
        #(MAX_TICKS * SAMPLE_DIV * 10);
        $fatal(1, "FAIL tb_song_timing: timeout after %0d ticks, %0d passes",
               ticks, wraps);
    end
endmodule
