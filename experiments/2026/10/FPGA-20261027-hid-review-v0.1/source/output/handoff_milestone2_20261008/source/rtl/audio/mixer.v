// 四声部混音：18 位有符号求和 -> 主音量右移 -> 饱和到 16 位 -> 五抽头 FIR。
// FIR 系数为 (1,4,6,4,1)/16，历史样本和输出仅在单周期 sample_tick 更新。
// 该平滑滤波改变频响，不能消除模拟链路的静音底噪，也不替代波表抗混叠。
module mixer #(
    parameter [3:0] VOLUME_SHIFT = 4'd1      // divide by 2, about -6 dB
)(
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    input  wire signed [15:0] v0,
    input  wire signed [15:0] v1,
    input  wire signed [15:0] v2,
    input  wire signed [15:0] v3,
    output reg  signed [15:0] sample_out
);

    wire signed [17:0] sum = v0 + v1 + v2 + v3;

    // 四个 signed 16 位输入需 18 位和；先降增益再饱和，可减少和弦削波。
    // 默认右移 1 位（除 2）仍不能保证四个同相满幅声部不削波；完全覆盖这种
    // 极端输入需至少除 4。当前保留默认音量，饱和器负责防止溢出翻转。
    // 现有舍入表达式按 VOLUME_SHIFT>=1 编写，不应直接把该参数设为 0。
    wire signed [19:0] sum_ext = {{2{sum[17]}}, sum};
    wire signed [19:0] scaled  =
        (sum_ext + (20'sd1 <<< (VOLUME_SHIFT - 1))) >>> VOLUME_SHIFT;

    // 超界钳制为 +32767/-32768，避免截低位导致符号翻转。
    wire signed [15:0] sat =
        (scaled > 20'sd32767)  ? 16'sd32767 :
        (scaled < -20'sd32768) ? -16'sd32768 :
        scaled[15:0];

    reg signed [15:0] d1, d2, d3, d4;

    always @(posedge clk) begin
        if (rst) begin
            d1 <= 16'sd0;
            d2 <= 16'sd0;
            d3 <= 16'sd0;
            d4 <= 16'sd0;
        end else if (sample_tick) begin
            d1 <= sat;
            d2 <= d1;
            d3 <= d2;
            d4 <= d3;
        end
    end

    // 权重和为 16，20 位 signed 中间结果覆盖 16 位饱和样本的累加范围。
    // 非阻塞更新使用旧 d1..d4，smooth 是本采样点加前四点的加权平均。
    wire signed [19:0] fir_sum =
        sat + d4 + ((d1 + d3) <<< 2) + ((d2 <<< 2) + (d2 <<< 1));

    wire signed [19:0] smooth = fir_sum >>> 4;

    always @(posedge clk) begin
        if (rst)
            sample_out <= 16'sd0;
        else if (sample_tick)
            sample_out <= smooth[15:0];
    end

endmodule
