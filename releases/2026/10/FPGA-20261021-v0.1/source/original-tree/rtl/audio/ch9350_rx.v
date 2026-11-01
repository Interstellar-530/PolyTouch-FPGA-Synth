// CH9350L 下位机（SEL=1）state 2 帧解析器。
//
// state 2 的键盘帧是固定长度、无校验：
//   57 AB 01 [mod] [00] [k0..k5]        11 字节
// 其它同状态帧按长度跳过：
//   57 AB 02 [btn][dx][dy][wheel]        5 字节（相对鼠标）
//   57 AB 04 [id][btn][XL][XH][YL][YH][wheel]  8 字节（state 3/4 绝对鼠标，state 2 不发）
//   57 AB 10 [VID_LO][VID_HI][PID_LO][PID_HI]  7 字节
//   57 AB 80 [VAL]                       4 字节（LED/启动状态）
//   57 AB 82 [IO]                        4 字节（心跳）
//   57 AB 86 / 89                        3 字节（设备通知/状态宣告）
// 解析器只对 0x01 输出 8 字节报告；同一帧重复 3-4 次由上层按键状态差分去重。
module ch9350_rx #(
    parameter integer CLK_HZ      = 27000000,
    parameter integer WATCHDOG_MS = 2000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  byte_data,
    input  wire        byte_valid,
    input  wire        frame_error,
    output reg  [63:0] report,
    output reg         report_valid,
    output reg         frame_seen,
    output reg         device_notify,
    output reg         heartbeat,
    output reg         link_timeout
);
    localparam integer WATCHDOG = (CLK_HZ / 1000) * WATCHDOG_MS;
    localparam integer GAP      = (CLK_HZ / 1000000) * 1000;   // 1 ms 字节间隔超时
    localparam [2:0] W57 = 3'd0, WAB = 3'd1, CMD = 3'd2, PAY = 3'd3, SKIP = 3'd4;

    reg [2:0]  st = W57;
    reg [3:0]  idx = 4'd0;
    reg [7:0]  skip = 8'd0;
    reg [7:0]  pb [0:7];
    reg [26:0] idle_cnt = 27'd0;
    reg [14:0] gap_cnt = 15'd0;
    reg        timed_out = 1'b0;

    always @(posedge clk) begin
        if (rst) begin
            st <= W57; idx <= 4'd0; skip <= 8'd0;
            report <= 64'd0; report_valid <= 1'b0; frame_seen <= 1'b0;
            device_notify <= 1'b0; heartbeat <= 1'b0; link_timeout <= 1'b0;
            idle_cnt <= 27'd0; timed_out <= 1'b0;
        end else begin
            report_valid  <= 1'b0;
            frame_seen    <= 1'b0;
            device_notify <= 1'b0;
            heartbeat     <= 1'b0;
            link_timeout  <= 1'b0;

            // 帧内字节间隔超时：截断帧/坏帧后 1 ms 内没有新字节就回到找 57 AB，
            // 避免把下一帧的头当成残留 payload 吃掉。
            if (byte_valid) gap_cnt <= 15'd0;
            else if (gap_cnt != GAP - 1) gap_cnt <= gap_cnt + 1'b1;
            if ((st == PAY || st == SKIP) && gap_cnt == GAP - 1) begin
                st <= W57;
                gap_cnt <= 15'd0;
            end

            if (idle_cnt != WATCHDOG - 1)
                idle_cnt <= idle_cnt + 1'b1;
            else if (!timed_out) begin
                timed_out <= 1'b1;
                link_timeout <= 1'b1;
            end

            if (frame_error) begin
                // UART 停止位错误：当前协议帧作废，立即重新找 57 AB。
                st <= W57; idx <= 4'd0; skip <= 8'd0;
            end

            if (byte_valid) begin
                case (st)
                    W57: if (byte_data == 8'h57) st <= WAB;
                    WAB: begin
                        if (byte_data == 8'hAB) st <= CMD;
                        else if (byte_data != 8'h57) st <= W57;
                    end
                    CMD: begin
                        idx <= 4'd0;
                        case (byte_data)
                            8'h01: st <= PAY;
                            8'h02: begin skip <= 8'd4; st <= SKIP; end
                            8'h04: begin skip <= 8'd7; st <= SKIP; end
                            8'h10: begin skip <= 8'd4; st <= SKIP; end
                            8'h80: begin skip <= 8'd1; st <= SKIP; end
                            8'h82: begin heartbeat <= 1'b1; skip <= 8'd1; st <= SKIP; end
                            8'h86: begin
                                device_notify <= 1'b1; frame_seen <= 1'b1;
                                st <= W57; idle_cnt <= 27'd0; timed_out <= 1'b0;
                            end
                            8'h89: begin
                                frame_seen <= 1'b1;
                                st <= W57; idle_cnt <= 27'd0; timed_out <= 1'b0;
                            end
                            default: st <= W57;
                        endcase
                    end
                    PAY: begin
                        // 按到达顺序存字节；第 8 字节到达时拼成 report[7:0]=第 1 字节。
                        pb[idx] <= byte_data;
                        if (idx == 4'd7) begin
                            // 第 2 字节是 Boot 报告的 reserved，必须为 0；否则按坏帧丢弃。
                            if (pb[1] == 8'd0) begin
                                report <= {byte_data, pb[6], pb[5], pb[4], pb[3], pb[2], pb[1], pb[0]};
                                report_valid <= 1'b1;
                            end
                            frame_seen <= 1'b1;
                            st <= W57; idle_cnt <= 27'd0; timed_out <= 1'b0;
                        end else begin
                            idx <= idx + 1'b1;
                        end
                    end
                    SKIP: begin
                        if (skip == 8'd0) begin
                            st <= W57;
                        end else begin
                            skip <= skip - 1'b1;
                            if (skip == 8'd1) begin
                                frame_seen <= 1'b1;
                                st <= W57; idle_cnt <= 27'd0; timed_out <= 1'b0;
                            end
                        end
                    end
                    default: st <= W57;
                endcase
            end
        end
    end
endmodule
