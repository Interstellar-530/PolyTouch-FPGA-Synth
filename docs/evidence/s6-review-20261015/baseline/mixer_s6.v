// S6 four-voice mixer with explicit saturation and clip accounting.
//
// The clip counter is defined at the master-gain boundary: one count is added
// for each sample_tick whose four-voice sum, after VOLUME_SHIFT, lies outside
// the signed 16-bit output range.  A sample is counted once even if the FIR is
// enabled.  The counter saturates at all ones and is cleared synchronously by
// clear_clip.  FIR_ENABLE selects the five-tap (1,4,6,4,1)/16 smoother; both
// paths update sample_out only on sample_tick, giving an explicit sample-frame
// register boundary for downstream I2S.
module mixer_s6 #(
    parameter integer VOLUME_SHIFT = 1,
    parameter integer FIR_ENABLE = 1,
    parameter integer CLIP_COUNTER_WIDTH = 32
) (
    input  wire                                  clk,
    input  wire                                  rst,
    input  wire                                  sample_tick,
    input  wire                                  clear_clip,
    input  wire signed [15:0]                    v0,
    input  wire signed [15:0]                    v1,
    input  wire signed [15:0]                    v2,
    input  wire signed [15:0]                    v3,
    output reg  signed [15:0]                    sample_out,
    output reg  [CLIP_COUNTER_WIDTH-1:0]         clip_count,
    output reg                                  clip_event
);

    localparam signed [19:0] ROUND_BIAS =
        (VOLUME_SHIFT == 0) ? 20'sd0 : (20'sd1 <<< (VOLUME_SHIFT - 1));

    // Sign-extend before every addition.  Extending only the final net would
    // allow a 16-bit intermediate addition to wrap before it is assigned.
    wire signed [19:0] sum_ext =
        {{4{v0[15]}}, v0} + {{4{v1[15]}}, v1} +
        {{4{v2[15]}}, v2} + {{4{v3[15]}}, v3};
    wire signed [19:0] scaled = (sum_ext + ROUND_BIAS) >>> VOLUME_SHIFT;
    wire raw_clip = (scaled > 20'sd32767) || (scaled < -20'sd32768);
    wire signed [15:0] sat_raw =
        (scaled > 20'sd32767)  ? 16'sd32767 :
        (scaled < -20'sd32768) ? -16'sd32768 : scaled[15:0];

    reg signed [15:0] d1, d2, d3, d4;
    wire signed [21:0] sat_ext = {{6{sat_raw[15]}}, sat_raw};
    wire signed [21:0] d1_ext = {{6{d1[15]}}, d1};
    wire signed [21:0] d2_ext = {{6{d2[15]}}, d2};
    wire signed [21:0] d3_ext = {{6{d3[15]}}, d3};
    wire signed [21:0] d4_ext = {{6{d4[15]}}, d4};
    wire signed [21:0] fir_sum = sat_ext + d4_ext +
                                  ((d1_ext + d3_ext) <<< 2) +
                                  (d2_ext <<< 3);
    wire signed [21:0] fir_value = fir_sum >>> 4;
    wire fir_clip = (fir_value > 22'sd32767) || (fir_value < -22'sd32768);
    wire signed [15:0] sat_fir =
        (fir_value > 22'sd32767)  ? 16'sd32767 :
        (fir_value < -22'sd32768) ? -16'sd32768 : fir_value[15:0];
    wire signed [15:0] next_sample = FIR_ENABLE ? sat_fir : sat_raw;
    // The declared statistic is taken at the master-gain boundary.  FIR
    // saturation is observable in sample_out but does not double-count a
    // frame (and can never hide an upstream raw clip).
    wire count_clip = raw_clip;

    always @(posedge clk) begin
        if (rst) begin
            d1         <= 16'sd0;
            d2         <= 16'sd0;
            d3         <= 16'sd0;
            d4         <= 16'sd0;
            sample_out <= 16'sd0;
            clip_count <= {CLIP_COUNTER_WIDTH{1'b0}};
            clip_event <= 1'b0;
        end else begin
            clip_event <= 1'b0;
            if (clear_clip)
                clip_count <= {CLIP_COUNTER_WIDTH{1'b0}};
            if (sample_tick) begin
                d1         <= sat_raw;
                d2         <= d1;
                d3         <= d2;
                d4         <= d3;
                sample_out <= next_sample;
                clip_event <= count_clip;
                if (count_clip && !clear_clip &&
                    (clip_count != {CLIP_COUNTER_WIDTH{1'b1}}))
                    clip_count <= clip_count + {{(CLIP_COUNTER_WIDTH-1){1'b0}}, 1'b1};
            end
        end
    end

endmodule
