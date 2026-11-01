`timescale 1ns/1ps
// Piano selection must read bank 5 and produce a different waveform sum from
// the ordinary band-limited bright path under identical phase/velocity.
module tb_piano_engine;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1, tick = 1'b0, retrig = 1'b1;
    wire signed [18:0] normal_sine, normal_bright, piano_sine, piano_bright;
    wire normal_valid, piano_valid;
    reg saw_piano_bank = 1'b0;
    integer frames = 0, differences = 0;

    shared_wavetable_engine #(
        .BEND_SHARED_ENABLE(1), .SHARED_MULT_ENABLE(0),
        .BANDLIMIT_ENABLE(1), .EXTRA_FRACTION_BITS(0)
    ) normal(
        .clk(clk), .rst(rst), .sample_tick(tick),
        .inc0(32'd23409824), .inc1(32'd0), .inc2(32'd0), .inc3(32'd0),
        .retrig0(retrig), .retrig1(1'b0), .retrig2(1'b0), .retrig3(1'b0),
        .env0(16'hffff), .env1(16'd0), .env2(16'd0), .env3(16'd0),
        .vel0(8'd127), .vel1(8'd0), .vel2(8'd0), .vel3(8'd0),
        .bend_ratio_q16(17'd65536), .piano_enable(1'b0), .guitar_enable(1'b0), .piano_tone(3'd0),
        .sine_sum(normal_sine), .bright_sum(normal_bright),
        .sums_valid(normal_valid), .mult_request(), .mult_operand_a(),
        .mult_operand_b(), .mult_result(36'sd0));

    shared_wavetable_engine #(
        .BEND_SHARED_ENABLE(1), .SHARED_MULT_ENABLE(0),
        .BANDLIMIT_ENABLE(1), .EXTRA_FRACTION_BITS(0)
    ) piano(
        .clk(clk), .rst(rst), .sample_tick(tick),
        .inc0(32'd23409824), .inc1(32'd0), .inc2(32'd0), .inc3(32'd0),
        .retrig0(retrig), .retrig1(1'b0), .retrig2(1'b0), .retrig3(1'b0),
        .env0(16'hffff), .env1(16'd0), .env2(16'd0), .env3(16'd0),
        .vel0(8'd127), .vel1(8'd0), .vel2(8'd0), .vel3(8'd0),
        .bend_ratio_q16(17'd65536), .piano_enable(1'b1), .guitar_enable(1'b0), .piano_tone(3'd0),
        .sine_sum(piano_sine), .bright_sum(piano_bright),
        .sums_valid(piano_valid), .mult_request(), .mult_operand_a(),
        .mult_operand_b(), .mult_result(36'sd0));

    always @(posedge clk) begin
        if (piano.bank_low == 7'd22) saw_piano_bank <= 1'b1;
        if (normal_valid && piano_valid) begin
            frames = frames + 1;
            if (normal_bright !== piano_bright) differences = differences + 1;
        end
    end

    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (8) begin
            tick = 1'b1; @(negedge clk); tick = 1'b0;
            repeat (180) @(negedge clk);
        end
        retrig = 1'b0;
        if (!saw_piano_bank) $fatal(1, "piano engine never selected C4 loud hammer bank 22");
        if (frames < 4) $fatal(1, "not enough completed engine frames: %0d", frames);
        if (differences == 0) $fatal(1, "piano and normal bright sums are identical");
        $display("PASS tb_piano_engine: C4 loud hammer bank selected, frames=%0d differing=%0d", frames, differences);
        $finish;
    end
    initial begin #2000000; $fatal(1, "tb_piano_engine timeout"); end
endmodule
