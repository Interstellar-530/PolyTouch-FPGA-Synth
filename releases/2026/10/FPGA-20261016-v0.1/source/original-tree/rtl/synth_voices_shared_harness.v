// 资源对比用测量顶层 B：共享引擎架构（4 个声部共用 2 个 pROM、插值/缩放乘法器时分复用、
// 交叉混合全局一次）。功能与 A 等价，差别只在架构组织，详见 shared_wavetable_engine.v。
module synth_voices_shared_harness (
    input  wire               clk_27m,
    input  wire               rst,
    output wire signed [15:0] sample_out,
    output wire [3:0]         fold
);
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

    reg [15:0] env0 = 16'd40000, env1 = 16'd50000, env2 = 16'd60000, env3 = 16'd65535;
    reg [7:0]  vel0 = 8'd120, vel1 = 8'd100, vel2 = 8'd80, vel3 = 8'd60;

    wire signed [18:0] sine_sum, bright_sum;
    wire sums_valid;
    shared_wavetable_engine u_engine (
        .clk(clk_27m), .rst(rst), .sample_tick(sample_tick),
        .inc0(32'd47756), .inc1(32'd56818), .inc2(32'd67622), .inc3(32'd80460),
        .retrig0(1'b0), .retrig1(1'b0), .retrig2(1'b0), .retrig3(1'b0),
        .env0(env0), .env1(env1), .env2(env2), .env3(env3),
        .vel0(vel0), .vel1(vel1), .vel2(vel2), .vel3(vel3),
        .sine_sum(sine_sum), .bright_sum(bright_sum), .sums_valid(sums_valid)
    );

    global_crossfade u_xf (
        .clk(clk_27m), .rst(rst), .sample_tick(sample_tick), .mix_weight(8'h40),
        .sine_sum(sine_sum), .bright_sum(bright_sum), .sample_out(sample_out)
    );

    assign fold = sample_out[15:12] ^ sample_out[11:8] ^ sample_out[7:4] ^ sample_out[3:0];
endmodule