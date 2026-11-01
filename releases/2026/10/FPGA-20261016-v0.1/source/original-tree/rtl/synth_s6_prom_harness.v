// 综合测量用顶层：pROM 原语版双波表振荡器（四声部），用于确认显式原语
// 被综合器接受并映射到 BSRAM/pROM，而不是依赖行为数组的推断。
// 这是测量顶层，不是产品顶层。
module synth_s6_prom_harness (
    input  wire               clk_27m,
    input  wire               rst,
    output wire signed [15:0] sample_out,
    output wire [3:0]         fold
);
    reg [31:0] phase0 = 32'd0, phase1 = 32'h2000_0000,
               phase2 = 32'h4000_0000, phase3 = 32'h6000_0000;
    wire signed [15:0] v0, v1, v2, v3;

    wavetable_osc_dual_prom u0 (.clk(clk_27m), .rst(rst), .en(1'b1), .phase(phase0),
        .mix_enable(1'b1), .mix_weight(8'h40), .sample_q(v0));
    wavetable_osc_dual_prom u1 (.clk(clk_27m), .rst(rst), .en(1'b1), .phase(phase1),
        .mix_enable(1'b1), .mix_weight(8'h40), .sample_q(v1));
    wavetable_osc_dual_prom u2 (.clk(clk_27m), .rst(rst), .en(1'b1), .phase(phase2),
        .mix_enable(1'b1), .mix_weight(8'h80), .sample_q(v2));
    wavetable_osc_dual_prom u3 (.clk(clk_27m), .rst(rst), .en(1'b1), .phase(phase3),
        .mix_enable(1'b1), .mix_weight(8'hc0), .sample_q(v3));

    always @(posedge clk_27m) begin
        phase0 <= phase0 + 32'd47756;
        phase1 <= phase1 + 32'd56818;
        phase2 <= phase2 + 32'd67622;
        phase3 <= phase3 + 32'd80460;
    end

    assign sample_out = v0 + v1 + v2 + v3;
    assign fold = sample_out[15:12] ^ sample_out[11:8] ^ v0[7:4] ^ v1[3:0];
endmodule