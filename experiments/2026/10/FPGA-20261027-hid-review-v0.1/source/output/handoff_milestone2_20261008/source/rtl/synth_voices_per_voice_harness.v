// 资源对比用测量顶层 A：逐声部架构（四个声部各自读两个 pROM、各自做插值与混合），
// 与共享版（测量顶层 B）在功能上等价：4 个 ADSR + 4 个相位累加器 + 包络/力度缩放
// + 交叉混合 + 除二饱和，差别只在 ROM 数量/组织、插值乘法器是否共享、交叉混合位置。
module synth_voices_per_voice_harness (
    input  wire               clk_27m,
    input  wire               rst,
    output wire signed [15:0] sample_out,
    output wire [3:0]         fold
);
    // 与共享版相同的 2 kHz 控制节拍派生出的音频节拍（只用于资源对比）
    reg [4:0] div = 5'd0;
    reg       sample_tick = 1'b0;
    always @(posedge clk_27m) begin
        sample_tick <= 1'b0;
        if (div == 5'd23) begin
            div <= 5'd0;
            sample_tick <= 1'b1;
        end else begin
            div <= div + 1'b1;
        end
    end

    reg [31:0] inc0 = 32'd47756, inc1 = 32'd56818, inc2 = 32'd67622, inc3 = 32'd80460;
    reg [15:0] env0 = 16'd40000, env1 = 16'd50000, env2 = 16'd60000, env3 = 16'd65535;
    reg [7:0]  vel0 = 8'd120, vel1 = 8'd100, vel2 = 8'd80, vel3 = 8'd60;
    reg [31:0] ph0 = 32'd0, ph1 = 32'h2000_0000, ph2 = 32'h4000_0000, ph3 = 32'h6000_0000;

    always @(posedge clk_27m) begin
        if (rst) begin
            ph0 <= 32'd0; ph1 <= 32'h2000_0000; ph2 <= 32'h4000_0000; ph3 <= 32'h6000_0000;
        end else if (sample_tick) begin
            ph0 <= ph0 + inc0; ph1 <= ph1 + inc1; ph2 <= ph2 + inc2; ph3 <= ph3 + inc3;
        end
    end

    // 每个声部一个双表 pROM 振荡器（各 4 块）与一次逐声部混合
    wire signed [15:0] v0, v1, v2, v3;
    wavetable_osc_dual_prom o0 (.clk(clk_27m), .rst(rst), .en(1'b1), .phase(ph0),
        .mix_enable(1'b1), .mix_weight(8'h40), .sample_q(v0));
    wavetable_osc_dual_prom o1 (.clk(clk_27m), .rst(rst), .en(1'b1), .phase(ph1),
        .mix_enable(1'b1), .mix_weight(8'h40), .sample_q(v1));
    wavetable_osc_dual_prom o2 (.clk(clk_27m), .rst(rst), .en(1'b1), .phase(ph2),
        .mix_enable(1'b1), .mix_weight(8'h40), .sample_q(v2));
    wavetable_osc_dual_prom o3 (.clk(clk_27m), .rst(rst), .en(1'b1), .phase(ph3),
        .mix_enable(1'b1), .mix_weight(8'h40), .sample_q(v3));

    // 包络与力度缩放（与 poly_voice_s6 相同的定点口径）
    function signed [15:0] scale_voice;
        input signed [15:0] src;
        input [15:0] e;
        input [7:0]  v;
        reg signed [31:0] m1, m2;
        begin
            m1 = $signed(src) * $signed({16'd0, e});
            m2 = $signed(m1[31:16]) * $signed({24'd0, v});
            scale_voice = $signed(m2[22:7]);
        end
    endfunction

    wire signed [15:0] s0 = scale_voice(v0, env0, vel0);
    wire signed [15:0] s1 = scale_voice(v1, env1, vel1);
    wire signed [15:0] s2 = scale_voice(v2, env2, vel2);
    wire signed [15:0] s3 = scale_voice(v3, env3, vel3);

    wire clip_event;
    mixer_s6 #(.VOLUME_SHIFT(1), .FIR_ENABLE(0), .CLIP_COUNTER_WIDTH(16)) u_mix (
        .clk(clk_27m), .rst(rst), .sample_tick(sample_tick), .clear_clip(1'b0),
        .v0(s0), .v1(s1), .v2(s2), .v3(s3),
        .sample_out(sample_out), .clip_count(), .clip_event(clip_event)
    );

    assign fold = sample_out[15:12] ^ sample_out[11:8] ^ sample_out[7:4] ^ sample_out[3:0];
endmodule