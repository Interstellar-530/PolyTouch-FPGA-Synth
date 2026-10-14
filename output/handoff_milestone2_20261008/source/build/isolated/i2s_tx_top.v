// [S3-AI | deepseek | 2026-10-14] 隔离综合用顶层（只用于综合验证，不进生产顶层、不烧录）。
//
// 目的：i2s_tx 尚未被顶层实例化，用现有 top 的综合结果不能证明新模块可综合、也不能给出它的
// 资源数字。这里把 i2s_tx 接到引脚上单独综合：输入样本来自自由计数器，复位由上电计数器产生，
// 避免常量传播把模块内部逻辑优化掉。引脚只在本隔离工程里使用，不改生产 CST。
module i2s_tx_top #(
    parameter integer CLK_HZ         = 12288000,
    parameter integer SAMPLE_RATE_HZ = 48000,
    parameter integer DATA_BITS      = 16
)(
    input  wire clk,          // 隔离工程时钟脚，标准档按 12.288 MHz 约束
    output wire i2s_bck,
    output wire i2s_lrck,
    output wire i2s_din
);

    reg [23:0] acc = 24'd0;
    reg [7:0]  por_cnt = 8'd0;

    wire                 rst = (por_cnt != 8'hFF);
    wire [DATA_BITS-1:0] src_l = acc[DATA_BITS-1:0];
    wire [DATA_BITS-1:0] src_r = ~acc[DATA_BITS-1:0];

    always @(posedge clk) begin
        acc <= acc + 24'd1;
        if (por_cnt != 8'hFF)
            por_cnt <= por_cnt + 8'd1;
    end

    wire tick_unused;

    i2s_tx #(.CLK_HZ(CLK_HZ), .SAMPLE_RATE_HZ(SAMPLE_RATE_HZ), .DATA_BITS(DATA_BITS)) dut (
        .clk(clk), .rst(rst), .sample_l(src_l), .sample_r(src_r),
        .bck(i2s_bck), .lrck(i2s_lrck), .din(i2s_din), .sample_tick(tick_unused)
    );

endmodule
