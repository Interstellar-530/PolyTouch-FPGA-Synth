// S5 control path: bounded pressure filtering and a continuous +/-2 semitone
// pitch bend.  The control inputs are sampled only on control_tick (normally
// a 2 kHz scheduler); the audio phase increment is combinational, so changing
// the potentiometer does not retrigger a voice envelope.
//
// pressure_filtered is a three-sample median followed by the fixed-point IIR
// y += (median - y) >>> 1.  pressure_level is zero when pressure_enable is
// low, but the filter state is still updated so enabling it does not inject an
// old stale sample.  Pressure is deliberately not part of phase_inc_out.
//
// bend_q8 is signed semitones in Q8: -512 .. +512 means -2 .. +2 semitones.
// bend_ratio_q16 is a piecewise-linear interpolation through the exact
// semitone ratios at -2,-1,0,+1,+2.  phase_inc_out = base_phase_inc * ratio.
module pressure_bend #(
    parameter [11:0] ADC_CENTER = 12'd2048
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               control_tick,
    input  wire [11:0]        pressure_adc,
    input  wire [11:0]        bend_adc,
    input  wire               pressure_enable,
    input  wire [31:0]        base_phase_inc,
    output reg  [11:0]        pressure_filtered,
    output wire [11:0]        pressure_level,
    output reg  signed [15:0] bend_q8,
    output wire [16:0]        bend_ratio_q16,
    output wire [31:0]        phase_inc_out
);

    reg [11:0] pressure_d0;
    reg [11:0] pressure_d1;

    // Median is combinational from the two delayed samples and the current
    // sample.  The explicit comparisons avoid relying on a simulator's sort.
    wire [11:0] pressure_median =
        ((pressure_d0 <= pressure_d1) && (pressure_d1 <= pressure_adc)) ? pressure_d1 :
        ((pressure_adc <= pressure_d1) && (pressure_d1 <= pressure_d0)) ? pressure_d1 :
        ((pressure_d1 <= pressure_d0) && (pressure_d0 <= pressure_adc)) ? pressure_d0 :
        ((pressure_adc <= pressure_d0) && (pressure_d0 <= pressure_d1)) ? pressure_d0 :
        pressure_adc;

    wire signed [12:0] pressure_diff =
        $signed({1'b0, pressure_median}) - $signed({1'b0, pressure_filtered});
    wire signed [12:0] pressure_step = pressure_diff >>> 1;
    wire signed [13:0] pressure_next_ext =
        $signed({1'b0, pressure_filtered}) + pressure_step;

    // Use 32-bit operands so the multiply does not accidentally truncate in
    // Verilog's self-determined expression width rules.
    wire [31:0] bend_pos_num =
        ({20'd0, bend_adc} - {20'd0, ADC_CENTER}) * 32'd512;
    wire [31:0] bend_neg_num =
        ({20'd0, ADC_CENTER} - {20'd0, bend_adc}) * 32'd512;
    wire [31:0] bend_pos_q8 = bend_pos_num / 32'd2047;
    wire [31:0] bend_neg_q8 = bend_neg_num / 32'd2048;
    wire signed [15:0] bend_mapped =
        (bend_adc >= ADC_CENTER) ? $signed(bend_pos_q8[15:0]) :
                                     -$signed(bend_neg_q8[15:0]);

    always @(posedge clk) begin
        if (rst) begin
            pressure_d0      <= 12'd0;
            pressure_d1      <= 12'd0;
            pressure_filtered <= 12'd0;
            bend_q8          <= 16'sd0;
        end else if (control_tick) begin
            pressure_d1 <= pressure_d0;
            pressure_d0 <= pressure_adc;

            // Inputs and state are non-negative.  Clamp explicitly so a
            // future parameter change cannot create a signed wraparound.
            if (pressure_next_ext < 0)
                pressure_filtered <= 12'd0;
            else if (pressure_next_ext > 14'sd4095)
                pressure_filtered <= 12'd4095;
            else
                pressure_filtered <= pressure_next_ext[11:0];

            bend_q8 <= bend_mapped;
        end
    end

    assign pressure_level = pressure_enable ? pressure_filtered : 12'd0;

    // Semitone ratios in Q16.  Values are rounded from 2^(n/12):
    // 58400 ~= 2^(-2/12), 61858 ~= 2^(-1/12), 65536 = 1,
    // 69402 ~= 2^(1/12), 73530 ~= 2^(2/12).
    function [16:0] ratio_at;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: ratio_at = 17'd58400;
                3'd1: ratio_at = 17'd61858;
                3'd2: ratio_at = 17'd65536;
                3'd3: ratio_at = 17'd69402;
                default: ratio_at = 17'd73530;
            endcase
        end
    endfunction

    reg [10:0] bend_u;
    reg [2:0]  ratio_seg;
    reg [7:0]  ratio_frac;
    reg [16:0] ratio_a;
    reg [16:0] ratio_b;
    reg [31:0] ratio_delta_frac;
    reg [16:0] ratio_interp;

    always @* begin
        // bend_q8 is bounded to [-512,+512], therefore bend_u is 0..1024.
        bend_u = $signed(bend_q8) + 11'd512;
        if (bend_u >= 11'd1024) begin
            ratio_seg  = 3'd4;
            ratio_frac = 8'd0;
        end else begin
            ratio_seg  = bend_u[10:8];
            ratio_frac = bend_u[7:0];
        end
        ratio_a = ratio_at(ratio_seg);
        ratio_b = ratio_at(ratio_seg + 3'd1);
        ratio_delta_frac = (ratio_b - ratio_a) * ratio_frac;
        ratio_interp = ratio_a + (ratio_delta_frac >> 8);
    end

    assign bend_ratio_q16 = ratio_interp;

    // 32x17 -> 49 bit product.  The output truncation is safe for normal DDS
    // phase increments and preserves the same Q16 operation as the reference.
    wire [48:0] phase_product = base_phase_inc * bend_ratio_q16;
    assign phase_inc_out = phase_product >> 16;

endmodule
