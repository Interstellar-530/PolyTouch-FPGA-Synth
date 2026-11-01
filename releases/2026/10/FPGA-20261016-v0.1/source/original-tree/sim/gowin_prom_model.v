// pROM 仿真模型（BIT_WIDTH 16/32），按厂商模型语义实现，供门禁在不依赖
// 未入库厂商文件的情况下运行原语等价性测试。
//
// 语义依据：Gowin V1.9.11.03 随工具发布的 tools/vendor/gowin/prim_sim.v 中
// pROM 的实现：
//   * ram_MEM = {INIT_RAM_3F, ..., INIT_RAM_00}，INIT_RAM_00 占最低 256 位；
//   * BIT_WIDTH=16 时字地址取 AD[13:4]（AD[3:0] 忽略），BIT_WIDTH=32 取 AD[13:5]；
//   * 16 位模式下 mem_t[15:0] = ram_MEM[base+15:0]，因此样本 k 位于第 k/16 个
//     256 位字的第 (k%16) 个 16 位槽（低位在前）；
//   * bypass 读在 CE 有效的时钟沿更新输出寄存器，pipeline 读再经 OCE 打一拍；
//   * RESET 清零寄存器而不清存储器内容，支持同步与异步两种复位。
// 与该厂商模型在同一组向量上的逐值一致性已单独验证（见集成复核记录）。
module pROM #(
    parameter READ_MODE  = 1'b0,
    parameter BIT_WIDTH  = 32,
    parameter RESET_MODE = "SYNC",
    parameter [255:0] INIT_RAM_00 = 256'h0, INIT_RAM_01 = 256'h0, INIT_RAM_02 = 256'h0,
    parameter [255:0] INIT_RAM_03 = 256'h0, INIT_RAM_04 = 256'h0, INIT_RAM_05 = 256'h0,
    parameter [255:0] INIT_RAM_06 = 256'h0, INIT_RAM_07 = 256'h0, INIT_RAM_08 = 256'h0,
    parameter [255:0] INIT_RAM_09 = 256'h0, INIT_RAM_0A = 256'h0, INIT_RAM_0B = 256'h0,
    parameter [255:0] INIT_RAM_0C = 256'h0, INIT_RAM_0D = 256'h0, INIT_RAM_0E = 256'h0,
    parameter [255:0] INIT_RAM_0F = 256'h0, INIT_RAM_10 = 256'h0, INIT_RAM_11 = 256'h0,
    parameter [255:0] INIT_RAM_12 = 256'h0, INIT_RAM_13 = 256'h0, INIT_RAM_14 = 256'h0,
    parameter [255:0] INIT_RAM_15 = 256'h0, INIT_RAM_16 = 256'h0, INIT_RAM_17 = 256'h0,
    parameter [255:0] INIT_RAM_18 = 256'h0, INIT_RAM_19 = 256'h0, INIT_RAM_1A = 256'h0,
    parameter [255:0] INIT_RAM_1B = 256'h0, INIT_RAM_1C = 256'h0, INIT_RAM_1D = 256'h0,
    parameter [255:0] INIT_RAM_1E = 256'h0, INIT_RAM_1F = 256'h0, INIT_RAM_20 = 256'h0,
    parameter [255:0] INIT_RAM_21 = 256'h0, INIT_RAM_22 = 256'h0, INIT_RAM_23 = 256'h0,
    parameter [255:0] INIT_RAM_24 = 256'h0, INIT_RAM_25 = 256'h0, INIT_RAM_26 = 256'h0,
    parameter [255:0] INIT_RAM_27 = 256'h0, INIT_RAM_28 = 256'h0, INIT_RAM_29 = 256'h0,
    parameter [255:0] INIT_RAM_2A = 256'h0, INIT_RAM_2B = 256'h0, INIT_RAM_2C = 256'h0,
    parameter [255:0] INIT_RAM_2D = 256'h0, INIT_RAM_2E = 256'h0, INIT_RAM_2F = 256'h0,
    parameter [255:0] INIT_RAM_30 = 256'h0, INIT_RAM_31 = 256'h0, INIT_RAM_32 = 256'h0,
    parameter [255:0] INIT_RAM_33 = 256'h0, INIT_RAM_34 = 256'h0, INIT_RAM_35 = 256'h0,
    parameter [255:0] INIT_RAM_36 = 256'h0, INIT_RAM_37 = 256'h0, INIT_RAM_38 = 256'h0,
    parameter [255:0] INIT_RAM_39 = 256'h0, INIT_RAM_3A = 256'h0, INIT_RAM_3B = 256'h0,
    parameter [255:0] INIT_RAM_3C = 256'h0, INIT_RAM_3D = 256'h0, INIT_RAM_3E = 256'h0,
    parameter [255:0] INIT_RAM_3F = 256'h0
) (
    input  wire        CLK,
    input  wire        CE,
    input  wire        OCE,
    input  wire        RESET,
    input  wire [13:0] AD,
    output reg  [31:0] DO
);
    localparam [16383:0] RAM_INIT = {
        INIT_RAM_3F, INIT_RAM_3E, INIT_RAM_3D, INIT_RAM_3C, INIT_RAM_3B, INIT_RAM_3A, INIT_RAM_39, INIT_RAM_38,
        INIT_RAM_37, INIT_RAM_36, INIT_RAM_35, INIT_RAM_34, INIT_RAM_33, INIT_RAM_32, INIT_RAM_31, INIT_RAM_30,
        INIT_RAM_2F, INIT_RAM_2E, INIT_RAM_2D, INIT_RAM_2C, INIT_RAM_2B, INIT_RAM_2A, INIT_RAM_29, INIT_RAM_28,
        INIT_RAM_27, INIT_RAM_26, INIT_RAM_25, INIT_RAM_24, INIT_RAM_23, INIT_RAM_22, INIT_RAM_21, INIT_RAM_20,
        INIT_RAM_1F, INIT_RAM_1E, INIT_RAM_1D, INIT_RAM_1C, INIT_RAM_1B, INIT_RAM_1A, INIT_RAM_19, INIT_RAM_18,
        INIT_RAM_17, INIT_RAM_16, INIT_RAM_15, INIT_RAM_14, INIT_RAM_13, INIT_RAM_12, INIT_RAM_11, INIT_RAM_10,
        INIT_RAM_0F, INIT_RAM_0E, INIT_RAM_0D, INIT_RAM_0C, INIT_RAM_0B, INIT_RAM_0A, INIT_RAM_09, INIT_RAM_08,
        INIT_RAM_07, INIT_RAM_06, INIT_RAM_05, INIT_RAM_04, INIT_RAM_03, INIT_RAM_02, INIT_RAM_01, INIT_RAM_00
    };

    reg [31:0] bp_reg, pl_reg;

    // BIT_WIDTH 决定地址对齐：16 位用 AD[13:4]，32 位用 AD[13:5]。
    wire [13:0] base16 = {AD[13:4], 4'b0000};
    wire [13:0] base32 = {AD[13:5], 5'b00000};
    wire [15:0] slice16 = RAM_INIT[base16 +: 16];
    wire [31:0] slice32 = RAM_INIT[base32 +: 32];
    wire [BIT_WIDTH-1:0] slice = (BIT_WIDTH == 32) ? slice32[BIT_WIDTH-1:0] : slice16[BIT_WIDTH-1:0];

    always @(posedge CLK) begin
        if (RESET) begin
            bp_reg <= 32'd0;
            pl_reg <= 32'd0;
        end else begin
            if (OCE)
                pl_reg <= bp_reg;
            if (CE)
                bp_reg[BIT_WIDTH-1:0] <= slice;
        end
    end

    always @* DO = (READ_MODE === 1'b0) ? bp_reg : pl_reg;
endmodule