`timescale 1ns/1ps

// Check that one pass through the tune really takes the length the song data
// says it does, and that every note of the melody and every chord note is
// emitted exactly once per pass.
//
// The expected numbers come from the same generated header the RTL uses, so a
// change to the song data cannot silently stop being tested.
module tb_song_timing;
    parameter SAMPLE_DIV    = 4;
    parameter TEMPO_SEL     = 2'd1;      // the shipped power-on default
    parameter MAX_TICKS     = 40000000;

    `include "rtl/audio/song_expect.vh"

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg sample_tick = 1'b0;
    reg restart = 1'b0;
    reg chord_set = 1'b0;
    reg [1:0] tempo_sel = TEMPO_SEL;

    wire        ev_wr;
    wire [15:0] ev_data;
    wire [5:0]  mel_idx_dbg;
    wire [4:0]  chord_idx_dbg;

    song_player dut (
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
        SONG_TOTAL_UNITS * SONG_UNIT_SAMPLES * (TEMPO_SEL + 1);
    localparam integer EXPECTED_NOTE_ONS =
        SONG_MELODY_NOTES + SONG_CHORD_NOTES;

    integer ticks = 0;
    integer note_ons = 0;
    integer last_wrap = 0;
    integer last_wrap_notes = 0;
    integer wraps = 0;
    reg [5:0] mel_d = 6'd0;

    always @(posedge clk) begin
        if (sample_tick)
            ticks = ticks + 1;

        if (ev_wr && ev_data[15] && (ev_data[14:8] != 8'd0))
            note_ons = note_ons + 1;

        mel_d <= mel_idx_dbg;
        if ((mel_idx_dbg == 6'd0) && (mel_d != 6'd0)) begin
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
        rst = 1'b0;
        $display("expecting pass = %0d units x %0d samples x %0d = %0d ticks, %0d note events",
                 SONG_TOTAL_UNITS, SONG_UNIT_SAMPLES, TEMPO_SEL + 1,
                 EXPECTED_PASS_TICKS, EXPECTED_NOTE_ONS);
        #(MAX_TICKS * SAMPLE_DIV * 10);
        $fatal(1, "FAIL tb_song_timing: timeout after %0d ticks, %0d passes",
               ticks, wraps);
    end
endmodule
