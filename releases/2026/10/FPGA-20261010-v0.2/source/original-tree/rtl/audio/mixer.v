// Four-voice mixer with saturation, smoothing and master level.
//
// The four voices are summed with one extra guard bit each, saturated back to
// 16 bits, then smoothed by the same (1,4,6,4,1)/16 FIR the single voice used
// and finally scaled by a power-of-two master volume with rounding.
module mixer #(
    parameter [3:0] VOLUME_SHIFT = 4'd2      // divide by 4, about -12 dB
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

    // The master level is applied before the saturation, not after.  Four
    // voices can reach four times full scale, and a power-of-two shift down is
    // exactly the head room that brings that back inside 16 bits; saturating
    // first would hard-clip every chord.
    wire signed [19:0] sum_ext = {{2{sum[17]}}, sum};
    wire signed [19:0] scaled  =
        (sum_ext + (20'sd1 <<< (VOLUME_SHIFT - 1))) >>> VOLUME_SHIFT;

    // Saturate instead of wrapping: four loud voices must clip, not fold over.
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
