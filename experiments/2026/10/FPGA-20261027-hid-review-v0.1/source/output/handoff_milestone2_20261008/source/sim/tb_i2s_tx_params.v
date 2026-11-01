`timescale 1ns/1ps
// [S3-AI | deepseek | 2026-10-14] 参数负例台：非法配置必须在仿真开始时就以 $fatal 结束，
// [S3-REVIEW | Codex | 2026-10-14] 补零时钟负例。
// 退出码非零，并且输出里同时出现 S3_PARAM_INVALID 与对应原因。门禁脚本按 -D 宏逐例编译运行，
// 任何一例退出码为 0、或退出码非零但没有匹配原因，都算门禁失败（不能拿语法错误或工具崩溃充数）。
//
// 用例（对应 S3 任务书第 5 节）：
//   S3_CASE_ZERO_FS          采样率为 0
//   S3_CASE_NOT_DIVISIBLE    27 MHz / 48 kHz 不能整除
//   S3_CASE_FRAME_NOT_DIV64  12.336 MHz / 48 kHz 每帧 257 拍，不能被 64 整除
//   S3_CASE_BCK_TOO_FAST     3.072 MHz / 48 kHz 的 BCK 周期只有 1 拍
//   S3_CASE_DATA_BITS_32     DATA_BITS = 32
`include "rtl/audio/clk_params.vh"

module tb_i2s_tx_params;

`ifdef S3_CASE_ZERO_CLK
    localparam integer P_CLK  = 0;
    localparam integer P_FS   = 48000;
    localparam integer P_BITS = 16;
    localparam         P_OK   = 1'b1;
    localparam [8*16-1:0] P_NAME = "zero_clk";
`elsif S3_CASE_ZERO_FS
    localparam integer P_CLK  = 27000000;
    localparam integer P_FS   = 0;
    localparam integer P_BITS = 16;
    localparam         P_OK   = 1'b1;
    localparam [8*16-1:0] P_NAME = "zero_fs";
`elsif S3_CASE_NOT_DIVISIBLE
    localparam integer P_CLK  = 27000000;
    localparam integer P_FS   = 48000;
    localparam integer P_BITS = 16;
    localparam         P_OK   = 1'b1;
    localparam [8*16-1:0] P_NAME = "not_divisible";
`elsif S3_CASE_FRAME_NOT_DIV64
    localparam integer P_CLK  = 12336000;
    localparam integer P_FS   = 48000;
    localparam integer P_BITS = 16;
    localparam         P_OK   = 1'b1;
    localparam [8*16-1:0] P_NAME = "frame_not_div64";
`elsif S3_CASE_BCK_TOO_FAST
    localparam integer P_CLK  = 3072000;
    localparam integer P_FS   = 48000;
    localparam integer P_BITS = 16;
    localparam         P_OK   = 1'b1;
    localparam [8*16-1:0] P_NAME = "bck_too_fast";
`elsif S3_CASE_DATA_BITS_32
    localparam integer P_CLK  = 12288000;
    localparam integer P_FS   = 48000;
    localparam integer P_BITS = 32;
    localparam         P_OK   = 1'b1;
    localparam [8*16-1:0] P_NAME = "data_bits_32";
`else
    localparam integer P_CLK  = 12288000;
    localparam integer P_FS   = 48000;
    localparam integer P_BITS = 16;
    localparam         P_OK   = 1'b0;
    localparam [8*16-1:0] P_NAME = "no_case_selected";
`endif

    reg                    clk = 1'b0;
    reg                    rst = 1'b1;
    reg signed [P_BITS-1:0] sl = {P_BITS{1'b0}};
    reg signed [P_BITS-1:0] sr = {P_BITS{1'b0}};
    wire bck, lrck, din, tick;

    i2s_tx #(.CLK_HZ(P_CLK), .SAMPLE_RATE_HZ(P_FS), .DATA_BITS(P_BITS)) dut (
        .clk(clk), .rst(rst), .sample_l(sl), .sample_r(sr),
        .bck(bck), .lrck(lrck), .din(din), .sample_tick(tick)
    );

    always #10 clk = ~clk;

    initial begin
        if (!P_OK) begin
            $display("S3_PARAM_INVALID_MISSING: 没有选择负例（需要 -DS3_CASE_xxx）");
            $fatal(1, "S3_PARAM_INVALID_MISSING: no case selected");
        end
        repeat (10) @(posedge clk);
        // 走到这里说明非法参数没有被拦截，必须算失败。
        $display("S3_PARAM_INVALID_MISSING: 负例 %0s 的非法参数没有被拦截", P_NAME);
        $fatal(1, "S3_PARAM_INVALID_MISSING: %0s was not rejected", P_NAME);
    end

endmodule
