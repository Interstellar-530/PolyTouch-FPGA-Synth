`timescale 1ns/1ps
// Key-loudness gain unit test: same table/phase/velocity, only note changes.
module tb_key_gain;
    reg clk=0; always #5 clk=~clk;
    reg rst=1, tick=0, retrig=0;
    reg [31:0] inc=32'd40315427;
    reg [15:0] env=16'hFFFF;
    reg [7:0] vel=8'd100;
    reg [6:0] note=7'd60;
    reg piano_en=1, guitar_en=0;
    wire signed [20:0] ss,bs; wire valid,req;
    wire signed [17:0] ma,mb; reg signed [35:0] prod=0;
    always @(posedge clk) if(req) prod<=ma*mb;

    shared_wavetable_engine #(.BEND_SHARED_ENABLE(0),.SHARED_MULT_ENABLE(0),
      .BANDLIMIT_ENABLE(0),.GENERIC_BRIGHT_ENABLE(0),.ZONE_LATCH_ENABLE(0),
      .STAGE_TIME_ENABLE(0),.VOICES8(0),.EXTRA_FRACTION_BITS(2),
      .KEY_GAIN_ENABLE(1)) dut (
      .clk(clk),.rst(rst),.sample_tick(tick),
      .inc0(inc),.inc1(32'd0),.inc2(32'd0),.inc3(32'd0),
      .inc4(32'd0),.inc5(32'd0),.inc6(32'd0),.inc7(32'd0),
      .retrig0(retrig),.retrig1(1'b0),.retrig2(1'b0),.retrig3(1'b0),
      .retrig4(1'b0),.retrig5(1'b0),.retrig6(1'b0),.retrig7(1'b0),
      .env0(env),.env1(16'd0),.env2(16'd0),.env3(16'd0),
      .env4(16'd0),.env5(16'd0),.env6(16'd0),.env7(16'd0),
      .vel0(vel),.vel1(8'd0),.vel2(8'd0),.vel3(8'd0),
      .vel4(8'd0),.vel5(8'd0),.vel6(8'd0),.vel7(8'd0),
      .note0(note),.note1(7'd0),.note2(7'd0),.note3(7'd0),
      .note4(7'd0),.note5(7'd0),.note6(7'd0),.note7(7'd0),
      .piano_enable(piano_en),.guitar_enable(guitar_en),
      .piano_tone(3'd0),.sine_sum(ss),.bright_sum(bs),.sums_valid(valid),
      .bend_ratio_q16(17'd65536),.mult_request(req),
      .mult_operand_a(ma),.mult_operand_b(mb),.mult_result(prod));

    integer frame_cycles;
    integer cap;
    integer absv;

    task run_capture;
        begin
            tick = 1'b1; @(negedge clk); tick = 1'b0;
            while (valid) @(negedge clk);
            frame_cycles = 0;
            cap = 0;
            while (!valid && frame_cycles < 600) begin
                @(negedge clk); frame_cycles = frame_cycles + 1;
                absv = (bs < 0) ? -bs : bs;
                if (absv > cap) cap = absv;
            end
            if (frame_cycles >= 600) $fatal(1, "frame timeout");
            absv = (bs < 0) ? -bs : bs;
            if (absv > cap) cap = absv;
            @(negedge clk);
        end
    endtask

    task run_one;
        begin
            retrig = 1'b1;
            run_capture;          // first frame: phase 0, table index 0 may be zero
            retrig = 1'b0;
            run_capture;          // second frame: phase advanced, capture this
        end
    endtask

    integer base;
    task check_note;
        input [6:0] n;
        input integer coeff;        // 0..256
        input integer tol;
        integer got;
        integer expected;
        begin
            note = n; run_one; got = cap;
            if (coeff == 0) begin
                $display("note=%0d cap=%0d expect=silence", n, got);
                if (got != 0) $fatal(1, "note %0d expected silence", n);
            end else begin
                expected = (base * coeff) / 256;
                $display("note=%0d cap=%0d expect=%0d (C=%0d)", n, got, expected, coeff);
                if ((got - expected) > tol || (expected - got) > tol)
                    $fatal(1, "note %0d cap=%0d base=%0d expect=%0d tol=%0d",
                           n, got, base, expected, tol);
            end
        end
    endtask

    initial begin
        note=7'd60; vel=8'd100; piano_en=1; guitar_en=0;
        repeat(4) @(negedge clk); rst=0; repeat(2) @(negedge clk);
        run_one; base = cap;
        $display("base note60 cap=%0d", base);
        if (base == 0) $fatal(1, "base is zero");
        check_note(7'd36, 256, 32);   // <=C4: unity
        check_note(7'd64, 228, 32);   // C=228
        check_note(7'd72, 181, 32);   // C=181
        check_note(7'd84, 128, 32);   // C=128

        vel=8'd0; check_note(7'd84, 0, 0); vel=8'd100;

        guitar_en=1; piano_en=0;
        check_note(7'd84, 144, 32);   // guitar C=144

        guitar_en=0; piano_en=0;      // generic bypass
        check_note(7'd84, 256, 32);

        $display("PASS tb_key_gain: curve, zero velocity, guitar clamp, generic bypass");
        $finish;
    end
    initial begin #2000000; $fatal(1, "timeout"); end
endmodule
