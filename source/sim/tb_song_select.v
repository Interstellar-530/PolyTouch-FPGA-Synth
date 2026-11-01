`timescale 1ns/1ps
module tb_song_select;
    reg clk=0, rst=1, restart=0, sel=0, ready=1;
    always #5 clk=~clk;
    reg [4:0] div=0;
    always @(posedge clk) div <= div+1'b1;
    wire tick=(div==0);
    wire wr;
    wire [15:0] data;
    wire [7:0] idx;
    song_player #(.UNIT_SAMPLES(5), .SECOND_UNIT_SAMPLES(4), .SONG_SELECT_ENABLE(1)) dut (
        .clk(clk),.rst(rst),.sample_tick(tick),.restart(restart),.song_select(sel),
        .chord_set(1'b0),.tempo_sel(2'd0),.ev_ready(ready),.ev_wr(wr),.ev_data(data),
        .mel_idx_dbg(idx),.chord_idx_dbg());
    integer ticks=0, ons=0, first_tick=0, first_ons=0, loops=0;
    reg [7:0] prev_idx=0;
    reg tracking=0;
    always @(posedge clk) begin
        if (tick) ticks=ticks+1;
        if (wr && ready && data[15] && tracking) ons=ons+1;
        if (tracking && idx==0 && prev_idx!=0) begin
            if (loops>0) begin
                if(ticks-first_tick != 208*4) $fatal(1,"second song loop duration %0d",ticks-first_tick);
                if(ons-first_ons != 46+13*3) $fatal(1,"second song note count %0d",ons-first_ons);
            end
            first_tick=ticks; first_ons=ons; loops=loops+1;
        end
        prev_idx=idx;
    end
    reg [15:0] held;
    integer n;
    initial begin
        repeat(5) @(negedge clk); rst=0;
        wait(idx==1); #1;
        if(dut.mel_cur_note!=69) $fatal(1,"first song table changed");
        @(negedge clk); sel=1; restart=1; ready=0;
        @(negedge clk); restart=0; tracking=1;
        if(idx!=46 || dut.tick_cnt!=0 || wr) $fatal(1,"switch did not reset transport/burst");
        wait(wr); held=data;
        repeat(60) begin @(negedge clk); if(!wr || data!==held) $fatal(1,"backpressure lost event"); end
        ready=1;
        wait(idx==0); #1;
        if(dut.mel_cur_note!=77 || dut.ch_nxt_root==0) $fatal(1,"second song wrong first note");
        wait(loops==3);
        @(negedge clk); sel=0; restart=1;
        @(negedge clk); restart=0; tracking=0;
        if(idx!=137 || dut.tick_cnt!=0 || wr) $fatal(1,"return did not reset first song");
        wait(idx==1); #1;
        if(dut.mel_cur_note!=69) $fatal(1,"return selected wrong song");
        $display("PASS tb_song_select: both tables, restart, two 208-unit loops, 85 notes/loop, backpressure");
        $finish;
    end
    initial begin #2000000; $fatal(1,"song selection timeout"); end
endmodule
