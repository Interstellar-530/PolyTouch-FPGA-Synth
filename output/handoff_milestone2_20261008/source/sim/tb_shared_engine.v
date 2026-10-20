`timescale 1ns/1ps
// 共享引擎等价性自检，两部分：
//  (a) 分量和逐位相等：引擎的 sine_sum / bright_sum 必须等于四个声部按
//      “行为版 S6 振荡器（纯 sine / 纯 bright）-> 包络 -> 力度”逐声部算完再求和；
//  (b) 交叉混合位置差异有界：逐声部混合后求和 与 先求和后全局混合，
//      两者的最终 16 位输出差必须不超过 BOUND（舍入只发生一次而不是四次）。
//
// 相位用分层 force 固定，避免依赖两套相位累加器的长序列一致性。
module tb_shared_engine;
    localparam integer BOUND = 2;          // 由 s6_reference.py 的数值扫描给出上界

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg sample_tick = 1'b0;

    reg [31:0] ph0 = 32'd0, ph1 = 32'h2000_0000, ph2 = 32'h4000_0000, ph3 = 32'h6000_0000;
    reg [15:0] env0 = 16'd30000, env1 = 16'd45000, env2 = 16'd60000, env3 = 16'd65535;
    reg [7:0]  vel0 = 8'd100, vel1 = 8'd64, vel2 = 8'd127, vel3 = 8'd40;
    reg [7:0]  weight = 8'd128;

    // 八个行为版振荡器：四个纯 sine、四个纯 bright
    wire signed [15:0] s0, s1, s2, s3, b0, b1, b2, b3;
    wavetable_osc_dual_s6 o_s0 (.clk(clk), .rst(rst), .en(1'b1), .phase(ph0), .mix_enable(1'b0), .mix_weight(8'd0),  .sample_q(s0));
    wavetable_osc_dual_s6 o_s1 (.clk(clk), .rst(rst), .en(1'b1), .phase(ph1), .mix_enable(1'b0), .mix_weight(8'd0),  .sample_q(s1));
    wavetable_osc_dual_s6 o_s2 (.clk(clk), .rst(rst), .en(1'b1), .phase(ph2), .mix_enable(1'b0), .mix_weight(8'd0),  .sample_q(s2));
    wavetable_osc_dual_s6 o_s3 (.clk(clk), .rst(rst), .en(1'b1), .phase(ph3), .mix_enable(1'b0), .mix_weight(8'd0),  .sample_q(s3));
    wavetable_osc_dual_s6 o_b0 (.clk(clk), .rst(rst), .en(1'b1), .phase(ph0), .mix_enable(1'b0), .mix_weight(8'hff), .sample_q(b0));
    wavetable_osc_dual_s6 o_b1 (.clk(clk), .rst(rst), .en(1'b1), .phase(ph1), .mix_enable(1'b0), .mix_weight(8'hff), .sample_q(b1));
    wavetable_osc_dual_s6 o_b2 (.clk(clk), .rst(rst), .en(1'b1), .phase(ph2), .mix_enable(1'b0), .mix_weight(8'hff), .sample_q(b2));
    wavetable_osc_dual_s6 o_b3 (.clk(clk), .rst(rst), .en(1'b1), .phase(ph3), .mix_enable(1'b0), .mix_weight(8'hff), .sample_q(b3));

    // 共享引擎
    wire signed [18:0] sine_sum, bright_sum;
    wire sums_valid;
    shared_wavetable_engine u_engine (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .piano_enable(1'b0), .piano_tone(3'd0),
        .inc0(32'd1), .inc1(32'd1), .inc2(32'd1), .inc3(32'd1),
        .retrig0(1'b0), .retrig1(1'b0), .retrig2(1'b0), .retrig3(1'b0),
        .env0(env0), .env1(env1), .env2(env2), .env3(env3),
        .vel0(vel0), .vel1(vel1), .vel2(vel2), .vel3(vel3),
        .sine_sum(sine_sum), .bright_sum(bright_sum), .sums_valid(sums_valid)
    );

    // 全局交叉混合
    wire signed [15:0] shared_out;
    global_crossfade u_xf (
        .clk(clk), .rst(rst), .update(sums_valid), .clear_clip(1'b0), .mix_weight(weight),
        .sine_sum(sine_sum), .bright_sum(bright_sum), .sample_out(shared_out)
    );

    integer failures = 0;
    integer ci, k;
    reg [31:0] phases [0:3];
    reg [15:0] envs [0:3];
    reg [7:0]  vels [0:3];
    reg [7:0]  weights [0:4];

    // 逐声部参考：行为版振荡器（纯分量）-> 包络 -> 力度
    function signed [15:0] voice_out;
        input signed [15:0] src;
        input [15:0] e;
        input [7:0]  v;
        reg signed [31:0] m1, m2;
        begin
            m1 = $signed(src) * $signed({16'd0, e});
            m2 = $signed(m1[31:16]) * $signed({24'd0, v});
            voice_out = $signed(m2[22:7]);
        end
    endfunction

    // 参考侧的符号扩展。旧版这里写成 {13'd0, x}，那会把 16 位有符号样值当
    // 无符号数处理；引擎犯了同一个错误，两个错误互相抵消，测试因此看不出来。
    function signed [18:0] ext19;
        input signed [15:0] x;
        begin
            ext19 = {{3{x[15]}}, x};
        end
    endfunction

    // 逐声部混合（与 wavetable_osc_dual_s6 的 (255-w,w)>>8 相同）
    function signed [15:0] mix16;
        input signed [15:0] a;
        input signed [15:0] b;
        input [7:0] w;
        reg signed [26:0] sum;
        begin
            sum = $signed(a) * $signed({19'd0, (8'hff - w)}) + $signed(b) * $signed({19'd0, w}) + 27'sd127;
            mix16 = $signed(sum) >>> 8;
        end
    endfunction

    reg signed [18:0] ref_sine_sum, ref_bright_sum;
    reg [31:0] clip_before;
    reg signed [18:0] ref_mix_sum;
    reg signed [15:0] ref_out;
    reg signed [27:0] ref_scaled;

    task run_case;
        input [7:0] w;
        begin
            weight = w;
            clip_before = u_xf.clip_count;
            // 固定相位：在 sample_tick 之后、FSM 读取相位之前用层次赋值写入。
            // Icarus 不支持对未打包数组元素执行 force，因此不能继续使用 force。
            // 发一个采样节拍，等 FSM 跑完（15 拍 × 4 声部 + 余量）
            @(negedge clk); sample_tick = 1'b1;
            @(negedge clk); sample_tick = 1'b0;
            u_engine.phase_v[0] = ph0;
            u_engine.phase_v[1] = ph1;
            u_engine.phase_v[2] = ph2;
            u_engine.phase_v[3] = ph3;
            repeat (90) @(posedge clk);
            #1;
            // (a) 分量和逐位核对
            ref_sine_sum   = ext19(voice_out(s0, env0, vel0)) + ext19(voice_out(s1, env1, vel1))
                           + ext19(voice_out(s2, env2, vel2)) + ext19(voice_out(s3, env3, vel3));
            ref_bright_sum = ext19(voice_out(b0, env0, vel0)) + ext19(voice_out(b1, env1, vel1))
                           + ext19(voice_out(b2, env2, vel2)) + ext19(voice_out(b3, env3, vel3));
            if (sine_sum !== ref_sine_sum) begin
                failures = failures + 1;
                $display("FAIL w=%0d sine_sum=%0d ref=%0d", w, sine_sum, ref_sine_sum);
            end
            if (bright_sum !== ref_bright_sum) begin
                failures = failures + 1;
                $display("FAIL w=%0d bright_sum=%0d ref=%0d", w, bright_sum, ref_bright_sum);
            end
            // (b) 交叉混合位置差异有界
            ref_mix_sum = ext19(voice_out(mix16(s0, b0, w), env0, vel0))
                        + ext19(voice_out(mix16(s1, b1, w), env1, vel1))
                        + ext19(voice_out(mix16(s2, b2, w), env2, vel2))
                        + ext19(voice_out(mix16(s3, b3, w), env3, vel3));
            ref_scaled = $signed(ref_mix_sum) >>> 1;
            ref_out = (ref_scaled > 28'sd32767) ? 16'sd32767 :
                      (ref_scaled < -28'sd32768) ? -16'sd32768 : ref_scaled[15:0];
            // 与全局混合的组合输出比较：寄存器输出要等下一个 sample_tick，
            // 那是跨用例的一拍延迟，不是引擎差异。
            if (u_xf.sat !== ref_out) begin
                if ((u_xf.sat - ref_out > BOUND) || (ref_out - u_xf.sat > BOUND)) begin
                    failures = failures + 1;
                    $display("FAIL w=%0d global=%0d per-voice=%0d diff=%0d", w, u_xf.sat, ref_out, u_xf.sat - ref_out);
                end
            end
            // (c) 主增益边界削波统计：每帧最多计一次，且与逐声部参考同判
            if ((u_xf.clip_count - clip_before) !== ((ref_scaled > 28'sd32767) || (ref_scaled < -28'sd32768) ? 32'd1 : 32'd0)) begin
                failures = failures + 1;
                $display("FAIL w=%0d clip_count delta=%0d ref_clip=%0d", w, u_xf.clip_count - clip_before,
                         (ref_scaled > 28'sd32767) || (ref_scaled < -28'sd32768));
            end
        end
    endtask

    initial begin
        weights[0] = 8'd0; weights[1] = 8'd64; weights[2] = 8'd128;
        weights[3] = 8'd192; weights[4] = 8'hff;
        phases[0] = 32'h0000_0000; phases[1] = 32'h2000_0000;
        phases[2] = 32'h4000_0000; phases[3] = 32'h6000_0000;
        envs[0] = env0; envs[1] = env1; envs[2] = env2; envs[3] = env3;
        vels[0] = vel0; vels[1] = vel1; vels[2] = vel2; vels[3] = vel3;

        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (4) @(posedge clk);

        for (ci = 0; ci < 5; ci = ci + 1) begin
            ph0 = phases[0]; ph1 = phases[1]; ph2 = phases[2]; ph3 = phases[3];
            env0 = envs[0]; env1 = envs[1]; env2 = envs[2]; env3 = envs[3];
            vel0 = vels[0]; vel1 = vels[1]; vel2 = vels[2]; vel3 = vels[3];
            run_case(weights[ci]);
        end

        // 第二组相位/包络（含接缝与极端相位）
        ph0 = 32'hFFC0_0000; ph1 = 32'h7FFF_FF00; ph2 = 32'h0000_3FFF; ph3 = 32'hABCD_1234;
        env0 = 16'd1000; env1 = 16'd65535; env2 = 16'd20000; env3 = 16'd65535;
        vel0 = 8'd127; vel1 = 8'd1; vel2 = 8'd90; vel3 = 8'd127;
        for (ci = 0; ci < 5; ci = ci + 1) run_case(weights[ci]);

        // 第三组：全部带非零小数位，专门压插值路径（此前的用例 frac 都是 0）
        ph0 = 32'h0000_7FFF; ph1 = 32'h2001_FFC0; ph2 = 32'h4000_3FFF; ph3 = 32'h6002_0000;
        env0 = 16'd65535; env1 = 16'd45000; env2 = 16'd60000; env3 = 16'd32768;
        vel0 = 8'd127; vel1 = 8'd64; vel2 = 8'd127; vel3 = 8'd100;
        for (ci = 0; ci < 5; ci = ci + 1) run_case(weights[ci]);

        // 第四组：故意过载（四声部同相负峰、满包络满力度、全正弦）必须计一次削波
        ph0 = 32'hC000_0000; ph1 = 32'hC000_0000; ph2 = 32'hC000_0000; ph3 = 32'hC000_0000;
        env0 = 16'd65535; env1 = 16'd65535; env2 = 16'd65535; env3 = 16'd65535;
        vel0 = 8'd127; vel1 = 8'd127; vel2 = 8'd127; vel3 = 8'd127;
        run_case(8'd0);
        if (u_xf.clip_count != (clip_before + 32'd1)) begin
            failures = failures + 1;
            $display("FAIL overdrive clip_count=%0d expected %0d", u_xf.clip_count, clip_before + 32'd1);
        end

        if (failures != 0) $fatal(1, "tb_shared_engine failures=%0d", failures);
        $display("PASS tb_shared_engine: 16 cases, component sums bit-exact, global crossfade within %0d LSB and clip count on the master boundary", BOUND);
        $finish;
    end

    initial begin
        #20_000_000;
        $fatal(1, "FAIL tb_shared_engine: timeout");
    end
endmodule
