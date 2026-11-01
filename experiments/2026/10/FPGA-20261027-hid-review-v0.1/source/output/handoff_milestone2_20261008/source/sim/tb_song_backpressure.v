`timescale 1ns/1ps
module tb_song_backpressure;
    reg clk = 0, rst = 1, ready = 0;
    wire ev_wr;
    wire [15:0] ev_data;
    integer held_word, i, accepts = 0;
    song_player #(.UNIT_SAMPLES(1)) dut (
        .clk(clk), .rst(rst), .sample_tick(1'b1), .restart(1'b0),
        .chord_set(1'b0), .tempo_sel(2'd0), .ev_ready(ready),
        .ev_wr(ev_wr), .ev_data(ev_data), .mel_idx_dbg(), .chord_idx_dbg()
    );
    always #5 clk = ~clk;
    initial begin
        @(negedge clk); rst = 0;
        wait (ev_wr);
        held_word = ev_data;
        for (i = 0; i < 24; i = i + 1) begin
            @(negedge clk);
            if (!ev_wr || ev_data !== held_word)
                $fatal(1, "Song event changed under backpressure");
        end
        ready = 1;
        repeat (20) begin
            @(posedge clk);
            if (ev_wr && ready) accepts = accepts + 1;
        end
        if (accepts < 4) $fatal(1, "Song did not drain its burst");
        $display("PASS tb_song_backpressure: event held and burst drained");
        $finish;
    end
    initial begin #100000; $fatal(1, "Song backpressure timeout"); end
endmodule
