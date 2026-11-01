// Gowin rPLL 行为模型：仅供 Icarus 仿真，不参与综合。
//
// 只实现 32 声部原型用到的静态配置：FCLKOUT = FCLKIN * (FBDIV_SEL+1)。
// 与设计要求一致：MULT=4/6/8 -> 49.152/73.728/98.304 MHz（周期 20.345/13.564/10.173 ns）。
// LOCK 在若干 CLKIN 上升沿后拉高，复位期间清零；不建模抖动、相位与 duty 微调。
// 参数表必须覆盖 audio_pll_clock.v 的实例化列表，否则 iverilog 会报未知参数。
`timescale 1ns/1ps
module rPLL #(
    parameter FCLKIN = "12.288",
    parameter DYN_IDIV_SEL = "false",
    parameter integer IDIV_SEL = 0,
    parameter DYN_FBDIV_SEL = "false",
    parameter integer FBDIV_SEL = 5,
    parameter DYN_ODIV_SEL = "false",
    parameter integer ODIV_SEL = 8,
    parameter PSDA_SEL = "0000",
    parameter DUTYDA_SEL = "1000",
    parameter DYN_DA_EN = "false",
    parameter CLKFB_SEL = "internal",
    parameter CLKOUT_BYPASS = "false",
    parameter DEVICE = "GW2A-18C"
) (
    input  wire CLKIN,
    input  wire CLKFB,
    input  wire RESET,
    input  wire RESET_P,
    input  wire [5:0] FBDSEL,
    input  wire [5:0] IDSEL,
    input  wire [5:0] ODSEL,
    input  wire [3:0] PSDA,
    input  wire [3:0] DUTYDA,
    input  wire [3:0] FDLY,
    output wire CLKOUT,
    output wire LOCK,
    output wire CLKOUTP,
    output wire CLKOUTD,
    output wire CLKOUTD3
);
    // FCLKIN 是 MHz 字符串；这里只接受 12.288 这一种参考频率。
    localparam real FIN_MHZ = 12.288;
    localparam real DIV     = (IDIV_SEL + 1);
    localparam real MULT    = (FBDIV_SEL + 1);
    localparam real FOUT_MHZ = FIN_MHZ * MULT / DIV;
    localparam real HALF_NS = 500.0 / FOUT_MHZ;

    reg clk_out = 1'b0;
    always #(HALF_NS) clk_out = ~clk_out;

    reg [3:0] lock_count = 4'd0;
    always @(posedge CLKIN or posedge RESET) begin
        if (RESET) lock_count <= 4'd0;
        else if (lock_count != 4'd15) lock_count <= lock_count + 1'b1;
    end

    assign CLKOUT   = RESET ? 1'b0 : clk_out;
    assign LOCK     = (lock_count == 4'd15);
    assign CLKOUTP  = CLKOUT;
    assign CLKOUTD  = CLKOUT;
    assign CLKOUTD3 = CLKOUT;
endmodule
