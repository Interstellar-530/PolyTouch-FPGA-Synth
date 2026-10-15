// 一个独立声部（S6 变体）：32 位相位累加器 + 双波表插值读取 + ADSR 包络 + 力度缩放。
//
// 与 poly_voice 的区别只有振荡器：这里把 dds_osc 换成
// wavetable_osc_dual_s6（sin/bright 两张 512 点表的相邻四点同步读取 + 9 位
// 线性插值 + 8 位交叉混合），相位累加器因此上移到本模块。包络、力度缩放与
// restart_sample 的时序口径与 poly_voice 完全一致，保持顶层行为可比。
// mix_enable/mix_weight 由本模块内部传给振荡器（本增量固定为 25% 明亮混合）。
//
// [2026-10-15 集成] 产品顶层已改用 shared_wavetable_engine + global_crossfade，
// 本模块不再被 top 实例化，保留作为逐声部参考实现：tb_shared_engine 用它的
// 振荡器做等价基准，资源对比顶层 synth_voices_per_voice_harness 也用它。
module poly_voice_s6 (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    input  wire               gate,
    input  wire               start,         // one clk pulse from the allocator
    input  wire        [31:0] phase_inc,
    input  wire        [7:0]  velocity,      // 0 .. 127
    input  wire               mix_enable,
    input  wire        [7:0]  mix_weight,
    output wire signed [15:0] sample,
    output wire               idle           // envelope is back at zero
);

    wire signed [15:0] osc_sample;
    wire        [15:0] env;
    reg                start_pending;
    wire               restart_sample = gate & (start | start_pending);
    reg         [31:0] phase;

    // 分配器 start 只有一个 clk，事件未必对齐音频采样点，因此暂存到 sample_tick。
    always @(posedge clk) begin
        if (rst)
            start_pending <= 1'b0;
        else if (sample_tick)
            start_pending <= 1'b0;
        else if (start)
            start_pending <= 1'b1;
    end

    // 相位只在 sample_tick 步进，重按清零；32 位溢出自然回绕。
    always @(posedge clk) begin
        if (rst)
            phase <= 32'd0;
        else if (sample_tick) begin
            if (restart_sample)
                phase <= 32'd0;
            else
                phase <= phase + phase_inc;
        end
    end

    wavetable_osc_dual_s6 u_osc (
        .clk        (clk),
        .rst        (rst),
        .en         (1'b1),
        .phase      (phase),
        .mix_enable (mix_enable),
        .mix_weight (mix_weight),
        .sample_q   (osc_sample)
    );

    adsr u_adsr (
        .clk         (clk),
        .rst         (rst),
        .sample_tick (sample_tick),
        .gate        (gate),
        .retrigger   (restart_sample),
        .env         (env),
        .idle        (idle)
    );

    // 与 poly_voice 相同的定点口径：signed 16 位样本 × 0..65535 包络，
    // 取 [31:16]；再乘 0..127 的力度并取 [22:7]。
    wire signed [31:0] osc_ext = {{16{osc_sample[15]}}, osc_sample};
    wire signed [31:0] env_ext = {16'd0, env};
    wire signed [31:0] env_mul = osc_ext * env_ext;
    wire signed [15:0] voiced  = env_mul[31:16];
    wire signed [31:0] vel_mul = voiced * $signed({1'b0, velocity});

    assign sample = vel_mul[22:7];

endmodule