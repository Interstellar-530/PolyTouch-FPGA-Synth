`timescale 1ns/1ps

// Measures how long one pass through the tune really takes.
//
// sample_tick is generated every SAMPLE_DIV clocks so the simulation runs
// faster than real time; the ratio between the tick count and the nominal
// 156 units x 9766 ticks x tempo multiplier is what matters.
module tb_song_timing;
    parameter SAMPLE_DIV = 4;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg sample_tick = 1'b0;
    reg restart = 1'b0;
    reg chord_set = 1'b0;
    reg [1:0] tempo_sel = 2'd1;

    wire        ev_wr;
    wire [15:0] ev_data;
    wire [5:0]  mel_idx_dbg;
    wire [3:0]  chord_idx_dbg;

    song_player dut (
        .clk          (clk),
        .rst          (rst),
        .sample_tick  (sample_tick),
        .restart      (restart),
        .chord_set    (chord_set),
        .tempo_sel    (tempo_sel),
        .ev_wr        (ev_wr),
        .ev_data      (ev_data),
        .mel_idx_dbg  (mel_idx_dbg),
        .chord_idx_dbg(chord_idx_dbg)
    );

    always #5 clk = ~clk;

    // sample_tick generator
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

    integer ticks = 0;
    integer note_ons = 0;
    integer last_wrap = 0;
    integer wraps = 0;
    reg [5:0] mel_d = 6'd0;

    reg [7:0] vel_seen [0:127];
    integer   vel_count = 0;

    always @(posedge clk) begin
        if (sample_tick)
            ticks = ticks + 1;

        if (ev_wr && ev_data[15] && (ev_data[14:8] != 8'd0)) begin
            note_ons = note_ons + 1;
            if (note_ons <= 12)
                $display("  note_on #%0d tick %0d midi %0d vel %0d",
                         note_ons, ticks, ev_data[14:8], ev_data[7:0]);
        end

        mel_d <= mel_idx_dbg;
        if ((mel_idx_dbg == 6'd0) && (mel_d != 6'd0)) begin
            wraps = wraps + 1;
            $display("WRAP %0d: sample_tick %0d, delta %0d, note_ons %0d",
                     wraps, ticks, ticks - last_wrap, note_ons);
            last_wrap = ticks;
            if (wraps == 2)
                $finish;
        end
    end

    initial begin
        #200;
        rst = 1'b0;
        $display("expected one pass: 156 units x 9766 ticks x %0d = %0d sample ticks",
                 tempo_sel + 1, 156 * 9766 * (tempo_sel + 1));
        #400000000;
        $display("TIMEOUT after %0d sample ticks, %0d wraps", ticks, wraps);
        $finish;
    end

    // Trace the sequencer state on the first few tick pulses.
    integer traces = 0;
    always @(posedge clk) begin
        if (dut.tick_pulse && traces < 14) begin
            traces = traces + 1;
            $display("  pulse %0d at tick %0d: mel_idx %0d mel_left %0d gap_len %0d bactive %b",
                     traces, ticks, dut.mel_idx, dut.mel_left,
                     dut.mel_gap_len, dut.bactive);
        end
    end
endmodule
