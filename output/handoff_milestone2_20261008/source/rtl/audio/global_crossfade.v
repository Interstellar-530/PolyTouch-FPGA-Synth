// 全局交叉混合：把两条分量和（19 位）按 (255-w, w) >> 8 混合一次，
// 再做与 mixer_s6 相同的“除以 2”、16 位饱和与主增益边界削波统计。
// 与逐声部版相比，混合乘法从每声部 2 次降为整机 2 次；
// 舍入只发生一次而不是每声部一次，偏差界见集成复核记录。
//
// 削波统计沿用 S6 的定义：主增益边界上，本帧（四声部混合后除以 2）的取值
// 超出 16 位有符号范围时计一次，计数到全 1 饱和，clear_clip 同步清零。
// 逐声部版由 mixer_s6 在该边界计数；共享引擎把这条边界移到了本模块。
module global_crossfade #(
    parameter integer CLIP_COUNTER_WIDTH = 32
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               update,       // 引擎 sums_valid：本拍结果是本帧的
    input  wire               clear_clip,
    input  wire [7:0]         mix_weight,
    input  wire signed [18:0] sine_sum,
    input  wire signed [18:0] bright_sum,
    output reg  signed [15:0] sample_out,
    output reg  [CLIP_COUNTER_WIDTH-1:0] clip_count,
    output reg                clip_event
);
    wire signed [26:0] sine_prod = $signed(sine_sum) * $signed({19'd0, (8'hff - mix_weight)});
    wire signed [26:0] bright_prod = $signed(bright_sum) * $signed({19'd0, mix_weight});
    wire signed [26:0] blend = (sine_prod + bright_prod + 27'sd127) >>> 8;
    wire signed [27:0] scaled = blend >>> 1;              // 与 mixer_s6 的 VOLUME_SHIFT=1 一致
    wire raw_clip = (scaled > 28'sd32767) || (scaled < -28'sd32768);
    wire signed [15:0] sat = (scaled > 28'sd32767)  ? 16'sd32767 :
                             (scaled < -28'sd32768) ? -16'sd32768 : scaled[15:0];

    always @(posedge clk) begin
        if (rst) begin
            sample_out <= 16'sd0;
            clip_count <= {CLIP_COUNTER_WIDTH{1'b0}};
            clip_event <= 1'b0;
        end else begin
            clip_event <= 1'b0;
            if (clear_clip)
                clip_count <= {CLIP_COUNTER_WIDTH{1'b0}};
            if (update) begin
                sample_out <= sat;
                clip_event <= raw_clip;
                if (raw_clip && !clear_clip &&
                    (clip_count != {CLIP_COUNTER_WIDTH{1'b1}}))
                    clip_count <= clip_count + {{(CLIP_COUNTER_WIDTH-1){1'b0}}, 1'b1};
            end
        end
    end
endmodule