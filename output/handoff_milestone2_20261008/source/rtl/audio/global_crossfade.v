// 全局交叉混合：把两条分量和（19 位）按 (255-w, w) >> 8 混合一次，
// 再做与 mixer_s6 相同的“除以 2”与 16 位饱和。
// 与逐声部版相比，混合乘法从每声部 2 次降为整机 2 次；
// 舍入只发生一次而不是每声部一次，偏差界见集成复核记录。
module global_crossfade (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    input  wire [7:0]         mix_weight,
    input  wire signed [18:0] sine_sum,
    input  wire signed [18:0] bright_sum,
    output reg  signed [15:0] sample_out
);
    wire signed [26:0] sine_prod = $signed(sine_sum) * $signed({19'd0, (8'hff - mix_weight)});
    wire signed [26:0] bright_prod = $signed(bright_sum) * $signed({19'd0, mix_weight});
    wire signed [26:0] blend = (sine_prod + bright_prod + 27'sd127) >>> 8;
    wire signed [27:0] scaled = blend >>> 1;              // 与 mixer_s6 的 VOLUME_SHIFT=1 一致
    wire signed [15:0] sat = (scaled > 28'sd32767)  ? 16'sd32767 :
                             (scaled < -28'sd32768) ? -16'sd32768 : scaled[15:0];

    always @(posedge clk) begin
        if (rst)          sample_out <= 16'sd0;
        else if (sample_tick) sample_out <= sat;
    end
endmodule