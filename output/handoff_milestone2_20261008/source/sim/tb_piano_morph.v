`timescale 1ns/1ps
// The same note must move from the hammer bank at high envelope toward the
// body bank as the envelope decays. Two engines receive identical phase and
// velocity, differing only in envelope-driven bank position.
module tb_piano_morph;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1, tick = 1'b0, retrig = 1'b1;
    wire signed [18:0] low_sine, low_bright, high_sine, high_bright;
    wire low_valid, high_valid;
    reg saw_low_body = 1'b0, saw_high_hammer = 1'b0;
    integer frames = 0, differences = 0;

    shared_wavetable_engine #(
        .BEND_SHARED_ENABLE(1), .SHARED_MULT_ENABLE(0),
        .BANDLIMIT_ENABLE(1), .EXTRA_FRACTION_BITS(0)
    ) low_env(
        .clk(clk), .rst(rst), .sample_tick(tick),
        .inc0(32'd23409824), .inc1(32'd0), .inc2(32'd0), .inc3(32'd0),
        .retrig0(retrig), .retrig1(1'b0), .retrig2(1'b0), .retrig3(1'b0),
        .env0(16'd0), .env1(16'd0), .env2(16'd0), .env3(16'd0),
        .vel0(8'd127), .vel1(8'd0), .vel2(8'd0), .vel3(8'd0),
        .bend_ratio_q16(17'd65536), .piano_enable(1'b1), .piano_tone(3'd0),
        .sine_sum(low_sine), .bright_sum(low_bright), .sums_valid(low_valid),
        .mult_request(), .mult_operand_a(), .mult_operand_b(), .mult_result(36'sd0));

    shared_wavetable_engine #(
        .BEND_SHARED_ENABLE(1), .SHARED_MULT_ENABLE(0),
        .BANDLIMIT_ENABLE(1), .EXTRA_FRACTION_BITS(0)
    ) high_env(
        .clk(clk), .rst(rst), .sample_tick(tick),
        .inc0(32'd23409824), .inc1(32'd0), .inc2(32'd0), .inc3(32'd0),
        .retrig0(retrig), .retrig1(1'b0), .retrig2(1'b0), .retrig3(1'b0),
        .env0(16'hffff), .env1(16'd0), .env2(16'd0), .env3(16'd0),
        .vel0(8'd127), .vel1(8'd0), .vel2(8'd0), .vel3(8'd0),
        .bend_ratio_q16(17'd65536), .piano_enable(1'b1), .piano_tone(3'd0),
        .sine_sum(high_sine), .bright_sum(high_bright), .sums_valid(high_valid),
        .mult_request(), .mult_operand_a(), .mult_operand_b(), .mult_result(36'sd0));

    always @(posedge clk) begin
        if (low_env.bank_low == 7'd42) saw_low_body <= 1'b1;
        if (high_env.bank_low == 7'd46) saw_high_hammer <= 1'b1;
        if (low_valid && high_valid) begin
            frames = frames + 1;
            if (low_bright !== high_bright) differences = differences + 1;
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
        if (!saw_low_body) $fatal(1, "low envelope never selected C4 loud body bank 42");
        if (!saw_high_hammer) $fatal(1, "high envelope never selected C4 loud hammer bank 46");
        if (frames < 4 || differences == 0)
            $fatal(1, "morph frames=%0d differences=%0d", frames, differences);
        $display("PASS tb_piano_morph: low env uses body, high env uses hammer, frames=%0d differences=%0d",
                 frames, differences);
        $finish;
    end
    initial begin #2000000; $fatal(1, "tb_piano_morph timeout"); end
endmodule
