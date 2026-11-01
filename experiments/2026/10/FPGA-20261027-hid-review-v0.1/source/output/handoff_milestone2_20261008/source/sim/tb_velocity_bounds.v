`timescale 1ns/1ps
// 力度边界与增益位宽回归。
// 生产引擎把 vel*key_coeff 存进 15 位 key_a：C=256 时 128*256=32768 被截成 0，
// 旧行为是“力度 128 反而静音、129 只剩 -42 dB”。本台要求：
//   1) 0..127 与改造前的整数公式逐位一致（唯一候选 E 全表命中）；
//   2) 128..255 全部饱和到 127，单调不降，只有 0 才是零输出；
//   3) KEY_GAIN_ENABLE=0 的旁路路径同样饱和（它等价于 C=256）。
module tb_velocity_bounds;
    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1, tick = 0, retrig = 0;
    reg [31:0] inc  = 32'd40315427;
    reg [15:0] env  = 16'hFFFF;
    reg [7:0]  vel  = 8'd100;
    reg [6:0]  note = 7'd60;
    reg piano_en = 1, guitar_en = 0;

    wire signed [20:0] ss_g, bs_g, ss_b, bs_b;
    wire valid_g, valid_b, req_g, req_b;
    wire signed [17:0] ma_g, mb_g, ma_b, mb_b;
    reg signed [35:0] prod_g = 0, prod_b = 0;
    always @(posedge clk) if (req_g) prod_g <= ma_g * mb_g;
    always @(posedge clk) if (req_b) prod_b <= ma_b * mb_b;

    shared_wavetable_engine #(.BEND_SHARED_ENABLE(0), .SHARED_MULT_ENABLE(0),
      .BANDLIMIT_ENABLE(0), .GENERIC_BRIGHT_ENABLE(0), .ZONE_LATCH_ENABLE(0),
      .STAGE_TIME_ENABLE(0), .VOICES8(0), .EXTRA_FRACTION_BITS(2),
      .KEY_GAIN_ENABLE(1)) dut_gain (
      .clk(clk), .rst(rst), .sample_tick(tick),
      .inc0(inc), .inc1(32'd0), .inc2(32'd0), .inc3(32'd0),
      .inc4(32'd0), .inc5(32'd0), .inc6(32'd0), .inc7(32'd0),
      .retrig0(retrig), .retrig1(1'b0), .retrig2(1'b0), .retrig3(1'b0),
      .retrig4(1'b0), .retrig5(1'b0), .retrig6(1'b0), .retrig7(1'b0),
      .env0(env), .env1(16'd0), .env2(16'd0), .env3(16'd0),
      .env4(16'd0), .env5(16'd0), .env6(16'd0), .env7(16'd0),
      .vel0(vel), .vel1(8'd0), .vel2(8'd0), .vel3(8'd0),
      .vel4(8'd0), .vel5(8'd0), .vel6(8'd0), .vel7(8'd0),
      .note0(note), .note1(7'd0), .note2(7'd0), .note3(7'd0),
      .note4(7'd0), .note5(7'd0), .note6(7'd0), .note7(7'd0),
      .piano_enable(piano_en), .guitar_enable(guitar_en), .piano_tone(3'd0),
      .sine_sum(ss_g), .bright_sum(bs_g), .sums_valid(valid_g),
      .bend_ratio_q16(17'd65536), .mult_request(req_g),
      .mult_operand_a(ma_g), .mult_operand_b(mb_g), .mult_result(prod_g));

    // 旁路档：KEY_GAIN_ENABLE=0，系数恒为 256，等价于最坏截断条件。
    shared_wavetable_engine #(.BEND_SHARED_ENABLE(0), .SHARED_MULT_ENABLE(0),
      .BANDLIMIT_ENABLE(0), .GENERIC_BRIGHT_ENABLE(0), .ZONE_LATCH_ENABLE(0),
      .STAGE_TIME_ENABLE(0), .VOICES8(0), .EXTRA_FRACTION_BITS(2),
      .KEY_GAIN_ENABLE(0)) dut_bypass (
      .clk(clk), .rst(rst), .sample_tick(tick),
      .inc0(inc), .inc1(32'd0), .inc2(32'd0), .inc3(32'd0),
      .inc4(32'd0), .inc5(32'd0), .inc6(32'd0), .inc7(32'd0),
      .retrig0(retrig), .retrig1(1'b0), .retrig2(1'b0), .retrig3(1'b0),
      .retrig4(1'b0), .retrig5(1'b0), .retrig6(1'b0), .retrig7(1'b0),
      .env0(env), .env1(16'd0), .env2(16'd0), .env3(16'd0),
      .env4(16'd0), .env5(16'd0), .env6(16'd0), .env7(16'd0),
      .vel0(vel), .vel1(8'd0), .vel2(8'd0), .vel3(8'd0),
      .vel4(8'd0), .vel5(8'd0), .vel6(8'd0), .vel7(8'd0),
      .note0(note), .note1(7'd0), .note2(7'd0), .note3(7'd0),
      .note4(7'd0), .note5(7'd0), .note6(7'd0), .note7(7'd0),
      .piano_enable(piano_en), .guitar_enable(guitar_en), .piano_tone(3'd0),
      .sine_sum(ss_b), .bright_sum(bs_b), .sums_valid(valid_b),
      .bend_ratio_q16(17'd65536), .mult_request(req_b),
      .mult_operand_a(ma_b), .mult_operand_b(mb_b), .mult_result(prod_b));

    integer cap_g, cap_b, cyc;
    integer sig_g, sig_b;
    reg seen_g, seen_b;

    // 一帧：先给 retrig 把相位清零，再跑一帧捕获同一相位点的分量和。
    task frame_capture;
        begin
            tick = 1'b1; @(negedge clk); tick = 1'b0;
            cap_g = 0; cap_b = 0; sig_g = 0; sig_b = 0;
            seen_g = 0; seen_b = 0; cyc = 0;
            while ((!seen_g || !seen_b) && cyc < 600) begin
                @(negedge clk); cyc = cyc + 1;
                if (valid_g) begin
                    seen_g = 1'b1; sig_g = bs_g;
                    cap_g = (bs_g < 0) ? -bs_g : bs_g;
                end
                if (valid_b) begin
                    seen_b = 1'b1; sig_b = bs_b;
                    cap_b = (bs_b < 0) ? -bs_b : bs_b;
                end
            end
            if (!seen_g || !seen_b) $fatal(1, "frame timeout after %0d cycles", cyc);
            @(negedge clk);
        end
    endtask

    task run_one;
        begin
            retrig = 1'b1; frame_capture;   // 相位 0：表首可能为 0
            retrig = 1'b0; frame_capture;   // 相位 inc：用于比较
        end
    endtask

    integer amp_g [0:255];
    integer amp_b [0:255];
    integer sig_tab [0:255];
    integer v, k, base, found;
    integer cand [0:3];
    reg signed [63:0] exp_val;
    reg signed [63:0] base64;

    initial begin
        repeat(4) @(negedge clk); rst = 0; repeat(2) @(negedge clk);

        // 全 256 个输入：note 60 -> key_coeff = 256，最坏截断点 128*256。
        for (v = 0; v < 256; v = v + 1) begin
            vel = v; run_one;
            amp_g[v] = cap_g; amp_b[v] = cap_b; sig_tab[v] = sig_g;
        end

        if (amp_g[0] != 0 || amp_b[0] != 0)
            $fatal(1, "vel=0 must be silent, got gain=%0d bypass=%0d", amp_g[0], amp_b[0]);
        if (amp_g[127] == 0)
            $fatal(1, "vel=127 must be audible");

        for (v = 1; v <= 127; v = v + 1) begin
            if (amp_g[v] < amp_g[v - 1])
                $fatal(1, "gain not monotonic at vel %0d: %0d -> %0d",
                       v, amp_g[v - 1], amp_g[v]);
            if (amp_b[v] < amp_b[v - 1])
                $fatal(1, "bypass not monotonic at vel %0d: %0d -> %0d",
                       v, amp_b[v - 1], amp_b[v]);
        end

        for (v = 0; v < 256; v = v + 1) begin
            if (amp_b[v] != amp_g[v])
                $fatal(1, "bypass path differs at vel %0d: %0d vs %0d",
                       v, amp_b[v], amp_g[v]);
            if (v >= 128 && amp_g[v] != amp_g[127])
                $fatal(1, "vel %0d cap=%0d, expected saturation %0d",
                       v, amp_g[v], amp_g[127]);
        end
        if (amp_g[128] != amp_g[127])
            $fatal(1, "regression: vel 128 wrapped to %0d instead of %0d",
                   amp_g[128], amp_g[127]);

        // 合法区间逐位一致：amp = (E*256*v + 16384) >>> 15，E 是包络积。
        // 由 vel=127 反解出最多四个候选 E（含符号），全表回代必须唯一命中。
        // 66017*32768 超过 32 位整数，必须用 64 位求商。
        base64 = ($signed(amp_g[127]) * 64'sd32768) / 64'sd32512;
        base = base64[31:0];
        cand[0] = base - 1; cand[1] = base; cand[2] = base + 1; cand[3] = -base;
        found = 0;
        for (k = 0; k < 4; k = k + 1) begin
            if (!found) begin
                found = 1;
                for (v = 0; v <= 127; v = v + 1) begin
                    exp_val = ($signed(cand[k]) * 64'sd256 * v + 64'sd16384) >>> 15;
                    if (exp_val != sig_tab[v]) found = 0;
                end
                if (found)
                    $display("INFO velocity model hit: E=%0d amp(127)=%0d amp(128)=%0d",
                             cand[k], amp_g[127], amp_g[128]);
            end
        end
        if (!found) begin
            $display("DIAG amp127=%0d sig127=%0d base=%0d sig1=%0d sig64=%0d sig100=%0d",
                     amp_g[127], sig_tab[127], base, sig_tab[1], sig_tab[64], sig_tab[100]);
            $fatal(1, "legal 0..127 range no longer matches (E*256*v+16384)>>>15");
        end

        // 第二组系数：note 72 -> C=181，旧实现的截断点在 182（约 -45 dB）。
        note = 7'd72;
        vel = 8'd127; run_one; base = cap_g;
        if (cap_g == 0) $fatal(1, "note 72 vel 127 must be audible");
        vel = 8'd128; run_one;
        if (cap_g != base) $fatal(1, "note 72: vel 128 cap=%0d, expected %0d", cap_g, base);
        vel = 8'd182; run_one;
        if (cap_g != base) $fatal(1, "note 72: vel 182 cap=%0d, expected %0d", cap_g, base);
        vel = 8'd255; run_one;
        if (cap_g != base) $fatal(1, "note 72: vel 255 cap=%0d, expected %0d", cap_g, base);
        $display("INFO note72 C=181: amp(127)=%0d saturates at 128/182/255", base);

        $display("PASS tb_velocity_bounds: 0..127 formula-exact, 128..255 saturate, bypass identical");
        $finish;
    end
    initial begin #20000000; $fatal(1, "timeout"); end
endmodule
