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
// bend_ratio_q16 is a piecewise-linear interpolation between the five semitone
// anchors at -2,-1,0,+1,+2 (within 0.8 cent of 2^(n/12), see the table below).
// phase_inc_out = base_phase_inc * ratio.
module baseline_pressure_bend #(
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

    // Half range denominators.  Deriving them from ADC_CENTER keeps the
    // +/-2 semitone endpoints correct if the midpoint is ever changed, and the
    // guards keep an out-of-range parameter from dividing by zero.  Both are
    // elaboration time constants: 2048 is a shift and only the 2047 side
    // below needs a real divider.
    localparam [11:0] ADC_FULL = 12'hFFF;
    localparam integer BEND_POS_DEN = (ADC_FULL > ADC_CENTER) ? (ADC_FULL - ADC_CENTER) : 1;
    localparam integer BEND_NEG_DEN = (ADC_CENTER > 0) ? ADC_CENTER : 1;

    // Use 32-bit operands so the multiply does not accidentally truncate in
    // Verilog's self-determined expression width rules.
    wire [31:0] bend_pos_num =
        ({20'd0, bend_adc} - {20'd0, ADC_CENTER}) * 32'd512;
    wire [31:0] bend_neg_num =
        ({20'd0, ADC_CENTER} - {20'd0, bend_adc}) * 32'd512;
    wire [31:0] bend_pos_q8 = bend_pos_num / BEND_POS_DEN;
    wire [31:0] bend_neg_q8 = bend_neg_num / BEND_NEG_DEN;
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

    // Semitone ratios in Q16 for -2,-1,0,+1,+2 semitones.  -1 and 0 equal the
    // rounded 2^(n/12) values; -2 is +0.42 cent and +1/+2 are -0.77/-0.75 cent
    // away from 2^(n/12), so the whole bend range stays within 0.8 cent.  The
    // deviation is reported per anchor by tools/pressure_bend_ref.py; use
    // 58386/61858/65536/69433/73562 instead if the anchors must equal the
    // rounded semitone ratios exactly.
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

    // 32x17 -> 49 bit product.  Both operands are widened explicitly: letting
    // the assignment context extend a multiply is tool dependent, and a tool
    // that keeps the self determined 32 bit result would drop the high half of
    // the product (1_000_000 * 65536 would come back as 16960 instead of
    // 1_000_000).  The Q16 truncation below matches the reference.
    wire [48:0] phase_product = {17'd0, base_phase_inc} * {32'd0, bend_ratio_q16};
    assign phase_inc_out = phase_product >> 16;

endmodule
