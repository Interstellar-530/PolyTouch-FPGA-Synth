// [S3-AI | deepseek | 2026-10-14] PCM5102A 接收行为模型（独立解码器，仅仿真用）。
// [S3-REVIEW | Codex | 2026-10-14] rst 在 BCK 停止时也须清除未完成的左右配对。
//
// 它只观察 bck/lrck/din 三根引脚，不引用被测模块内部的槽计数器、相位或保持寄存器，
// 也不导入被测模块的串行逻辑，因此可以独立证明发送端的位序、声道极性和零延迟位。
// 行为按 TI SLAS859C §9.3.2 与图 14：DIN 在 BCK 上升沿被采样，LRCK 低是左声道、
// 高是右声道；每声道位置 0 是零延迟位，位置 1..DATA_BITS 是 MSB 在前的数据。
//
// 不模拟模拟 DAC、PLL 锁定、XSMT 斜坡或滤波延迟。硬复位或半帧边沿数不对时丢弃残段，
// 只有先看到一个完整的左半帧、再看到一个完整的右半帧才报 frame_valid（最多一个 BCK 周期）。
module i2s_rx_model #(
    parameter integer DATA_BITS  = 16,
    parameter integer HALF_SLOTS = 32
)(
    input  wire                        bck,
    input  wire                        rst,
    input  wire                        lrck,
    input  wire                        din,
    output reg  signed [DATA_BITS-1:0] left_word,
    output reg  signed [DATA_BITS-1:0] right_word,
    output reg                         frame_valid,
    output reg  [31:0]                 slot_l,      // 左半帧 32 槽原始位（位置 0 在 bit31）
    output reg  [31:0]                 slot_r,      // 右半帧 32 槽原始位
    output reg  [31:0]                 align_discards // 累计丢弃的残段半帧数（指标用）
);

    reg        lrck_prev;
    reg        pending_l;    // 左半帧已收到，等待右半帧
    integer    edge_cnt;     // 本半帧内第几个上升沿（从 1 起）
    reg [31:0] sh;

    initial begin
        lrck_prev   = 1'b0;
        pending_l   = 1'b0;
        edge_cnt    = 0;
        sh          = 32'd0;
        left_word   = {DATA_BITS{1'b0}};
        right_word  = {DATA_BITS{1'b0}};
        frame_valid = 1'b0;
        slot_l      = 32'd0;
        slot_r      = 32'd0;
        align_discards = 32'd0;
    end

    always @(posedge bck or posedge rst) begin
        frame_valid <= 1'b0;
        if (rst) begin
            lrck_prev   <= 1'b0;  // 发送器硬复位后的 LRCK 固定为低
            pending_l   <= 1'b0;
            edge_cnt    <= 0;
            sh          <= 32'd0;
            left_word   <= {DATA_BITS{1'b0}};
            right_word  <= {DATA_BITS{1'b0}};
            slot_l      <= 32'd0;
            slot_r      <= 32'd0;
        end else if (lrck != lrck_prev) begin
            // LRCK 只在 BCK 下降沿改变，所以本上升沿属于新的半帧：先结算刚结束的半帧。
            if (edge_cnt != HALF_SLOTS) begin
                align_discards <= align_discards + 1'b1;
                pending_l   <= 1'b0;                  // 残段丢弃，不参与比较
            end else if (lrck_prev == 1'b0) begin
                slot_l    <= sh;
                left_word <= sh[30 -: DATA_BITS];     // 位置 1..DATA_BITS
                pending_l <= 1'b1;
            end else if (pending_l) begin
                slot_r      <= sh;
                right_word  <= sh[30 -: DATA_BITS];
                frame_valid <= 1'b1;
                pending_l   <= 1'b0;
            end else begin
                pending_l <= 1'b0;                    // 没有配对的左半帧
            end
            lrck_prev <= lrck;
            edge_cnt  <= 1;
            sh        <= {sh[30:0], din};             // 位置 0 也先收下，结算时被跳过
        end else begin
            edge_cnt <= edge_cnt + 1;
            sh       <= {sh[30:0], din};
        end
    end

endmodule
