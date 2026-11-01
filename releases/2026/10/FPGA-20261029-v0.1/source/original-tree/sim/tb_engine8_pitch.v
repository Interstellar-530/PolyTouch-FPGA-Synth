`timescale 1ns/1ps
// 8 声部引擎单音音高定向测试：只让 voice 0 发声，分别看正弦与钢琴分量。
// 用途：区分“相位增量正确但钢琴表谐波导致过零计数偏多”和真正的引擎错位。
module tb_engine8_pitch;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1, tick = 0, piano_en = 1;
    reg [31:0] incs = 32'd0;
    reg [15:0] env0 = 16'd0;
    reg [7:0]  vel0 = 8'd100;
    reg        retrig0 = 1'b0;
    reg [7:0]  vel_others = 8'd0;
    reg [16:0] ratio = 17'd65536;

    wire signed [20:0] ss, bs;
    wire valid, req;
    wire signed [17:0] ma, mb;
    reg signed [35:0] product = 0;
    always @(posedge clk) if (req) product <= ma * mb;

    shared_wavetable_engine #(
        .BEND_SHARED_ENABLE(0), .SHARED_MULT_ENABLE(0),
        .BANDLIMIT_ENABLE(1), .GENERIC_BRIGHT_ENABLE(1),
        .ZONE_LATCH_ENABLE(1), .STAGE_TIME_ENABLE(1),
        .STAGE_STEP_SAMPLES(5859), .VOICES8(1), .EXTRA_FRACTION_BITS(2)
    ) dut (
        .clk(clk), .rst(rst), .sample_tick(tick),
        .inc0(incs), .inc1(32'd0), .inc2(32'd0), .inc3(32'd0),
        .inc4(32'd0), .inc5(32'd0), .inc6(32'd0), .inc7(32'd0),
        .retrig0(retrig0), .retrig1(1'b0), .retrig2(1'b0), .retrig3(1'b0),
        .retrig4(1'b0), .retrig5(1'b0), .retrig6(1'b0), .retrig7(1'b0),
        .env0(env0), .env1(16'd0), .env2(16'd0), .env3(16'd0),
        .env4(16'd0), .env5(16'd0), .env6(16'd0), .env7(16'd0),
        .vel0(vel0), .vel1(vel_others), .vel2(vel_others), .vel3(vel_others),
        .vel4(vel_others), .vel5(vel_others), .vel6(vel_others), .vel7(vel_others),
        .piano_enable(piano_en), .piano_tone(3'd2),
        .sine_sum(ss), .bright_sum(bs), .sums_valid(valid),
        .bend_ratio_q16(ratio),
        .mult_request(req), .mult_operand_a(ma), .mult_operand_b(mb), .mult_result(product)
    );

    integer cycles;
    integer n, last_s, xing_s, first_s, last_b, xing_b, first_b;
    reg signed [20:0] prev_s, prev_b;
    integer period;

    task frame;
        begin
            tick = 1; @(negedge clk); tick = 0;
            cycles = 0;
            while (!valid && cycles < 600) begin @(negedge clk); cycles = cycles + 1; end
            if (cycles >= 600) $fatal(1, "frame timeout");
            @(negedge clk);
        end
    endtask

    initial begin
        incs = 32'd40315427;   // A4 at 46875 Hz
        env0 = 16'hFFFF;
        repeat (4) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);
        retrig0 = 1'b1;
        frame();
        retrig0 = 1'b0;

        prev_s = 0; prev_b = 0;
        xing_s = 0; xing_b = 0; first_s = -1; first_b = -1;
        last_s = 0; last_b = 0;
        n = 0;
        while (n < 2000) begin
            frame();
            n = n + 1;
            if (prev_s <= 0 && ss > 0) begin
                xing_s = xing_s + 1;
                if (first_s < 0) first_s = n;
                last_s = n;
            end
            if (prev_b <= 0 && bs > 0) begin
                xing_b = xing_b + 1;
                if (first_b < 0) first_b = n;
                last_b = n;
            end
            prev_s = ss; prev_b = bs;
        end

        if (xing_s < 5) $fatal(1, "sine crossings too few: %0d", xing_s);
        period = ((last_s - first_s) * 100) / (xing_s - 1);
        $display("INFO engine8 sine period=%0d.%02d samples (expect 106.53), crossings=%0d",
                 period / 100, period % 100, xing_s);
        if (period < 10400 || period > 10900)
            $fatal(1, "sine pitch wrong: %0d.%02d", period / 100, period % 100);

        if (xing_b < 5) $fatal(1, "bright crossings too few: %0d", xing_b);
        period = ((last_b - first_b) * 100) / (xing_b - 1);
        $display("INFO engine8 bright period=%0d.%02d samples (harmonics may shorten this), crossings=%0d",
                 period / 100, period % 100, xing_b);

        $display("PASS tb_engine8_pitch: voice0 sine pitch correct, 8-voice engine frame ok");
        $finish;
    end

    initial begin
        #20000000;
        $fatal(1, "timeout");
    end
endmodule
