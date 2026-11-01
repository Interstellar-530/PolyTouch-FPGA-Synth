// Dock 3714 板载 PT8211 调试 DAC：16 位双声道，左右发送同一单声道采样。
// 27 MHz / 18 = 1.5 MHz BCK；每帧 32 个 BCK，即 27 MHz / 576 = 46.875 kHz。
// sample_tick 每帧仅一个 clk 宽，不是持续一整帧的电平，也不是新的时钟域。
//
// PT8211 使用右对齐格式，与 PCM5102A 所需标准 I2S 不同，不能直接复用。
// framing 参照 Sipeed/Gowin TangPrimer-20K-example 的 PT8211/src/pt8211_drive.v：
// b_cnt 0/16 请求装载，3/19 更新 WS；req_r/req_r1 的延迟须与移位时序一同理解。
// 若只把 WS 改到 15/31，会破坏现有字边界关系。
// 本版在 BCK 下降沿更新 DIN/WS，给 DAC 上升沿采样留下约半周期建立时间。
// 外置 PCM5102A 标准 I2S 仍属后续任务，本模块仅服务板载耳机调试路径。
module pt8211_tx (
    input  wire               clk,
    input  wire               rst,
    input  wire signed [15:0] sample_in,
    output reg                bck,
    output reg                ws,
    output reg                din,
    output reg                sample_tick
);

    reg [3:0]  div_cnt;     // 0..8, nine 27 MHz cycles per BCK half period
    reg [4:0]  b_cnt;       // 0..31, incremented once per BCK
    reg        req_r;       // word request, one BCK wide
    reg        req_r1;      // req_r delayed by one BCK
    reg [15:0] idata_r;     // serialiser shift register
    reg [15:0] frame_data;  // hold register so both channels see one sample

    wire bck_falling = (div_cnt == 4'd8) && bck;

    always @(posedge clk) begin
        if (rst) begin
            div_cnt     <= 4'd0;
            bck         <= 1'b0;
            b_cnt       <= 5'd0;
            req_r       <= 1'b0;
            req_r1      <= 1'b0;
            idata_r     <= 16'd0;
            frame_data  <= 16'd0;
            ws          <= 1'b0;
            din         <= 1'b0;
            sample_tick <= 1'b0;
        end else begin
            // 每 clk 先清零，只有下方帧边界置一，确保音源只前进一次。
            sample_tick <= 1'b0;

            if (div_cnt == 4'd8) begin
                div_cnt <= 4'd0;
                bck     <= ~bck;
            end else begin
                div_cnt <= div_cnt + 1'b1;
            end

            if (bck_falling) begin
                b_cnt <= b_cnt + 1'b1;

                // Vendor word framing: request at b_cnt 0 and 16, load the
                // held sample one BCK later, present its MSB on the next BCK.
                req_r   <= (b_cnt == 5'd0) || (b_cnt == 5'd16);
                req_r1  <= req_r;
                idata_r <= req_r1 ? frame_data : {idata_r[14:0], 1'b0};
                din     <= idata_r[15];

                // Vendor word select placement.
                if (b_cnt == 5'd3)
                    ws <= 1'b0;
                else if (b_cnt == 5'd19)
                    ws <= 1'b1;

                // 一帧末尾锁存 sample_in，后续两个声道共用 frame_data。
                // 非阻塞赋值：其他模块在下一 clk 看到 sample_tick；这次锁存取旧采样，
                // 所以整条音频流水线存在帧延迟，不能假定本帧 tick 算出的值立即发出。
                if (b_cnt == 5'd31) begin
                    frame_data  <= sample_in;
                    sample_tick <= 1'b1;
                end
            end
        end
    end

endmodule

