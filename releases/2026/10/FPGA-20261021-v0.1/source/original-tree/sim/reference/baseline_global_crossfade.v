// 全局交叉混合：把两条分量和（19 位）按 (255-w, w) >> 8 混合一次，
// 再做与 mixer_s6 相同的“除以 2”、16 位饱和与主增益边界削波统计。
// 混合使用整机一个 18x9 可变乘法，高位用移位修正；
// 舍入只发生一次而不是每声部一次，偏差界见集成复核记录。
//
// 削波统计沿用 S6 的定义：主增益边界上，本帧（混合/除二及可选压力增益后）的取值
// 超出 16 位有符号范围时计一次，计数到全 1 饱和，clear_clip 同步清零。
// 逐声部版由 mixer_s6 在该边界计数；共享引擎把这条边界移到了本模块。
module baseline_global_crossfade #(
    parameter integer CLIP_COUNTER_WIDTH = 32,
    // Default disabled keeps existing standalone users bit-exact. The product
    // standard-I2S profile enables this frame-rate global VCA before saturation.
    parameter integer PRESSURE_GAIN_ENABLE = 0,
    parameter integer PRESSURE_ADC_LOW = 128,
    parameter integer PRESSURE_ADC_FULL = 3200,
    parameter integer PRESSURE_MIN_GAIN_Q12 = 1024,
    parameter integer PRESSURE_GAIN_STEP = 32,
    parameter integer TIMBRE_SLEW_ENABLE = 0,
    parameter [7:0] TIMBRE_RESET_WEIGHT = 64
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
    output reg                clip_event,
    // Ignored at elaboration when PRESSURE_GAIN_ENABLE=0. No board ports or
    // UART commands are added; pressure_level is the filtered CH0 ADC code.
    input  wire               pressure_enable,
    input  wire [11:0]        pressure_level
);
    reg [7:0] weight_state;
    wire [7:0] weight_next = (mix_weight > weight_state) ? weight_state+8'd1 :
                            (mix_weight < weight_state) ? weight_state-8'd1 : weight_state;
    wire [7:0] active_weight = TIMBRE_SLEW_ENABLE ? weight_next : mix_weight;
    always @(posedge clk) begin
        if(rst) weight_state<=TIMBRE_RESET_WEIGHT;
        else if(update) weight_state<=active_weight;
    end
    // Exact identity: A*(255-w)+B*w = (A<<8)-A+(B-A)*w.
    // One variable multiply instead of two. The difference needs 20 signed
    // bits, and its product 28; opposite full-scale inputs must not overflow.
    wire signed [19:0] difference = $signed({bright_sum[18],bright_sum}) -
                                   $signed({sine_sum[18],sine_sum});
    // Recenter the low 18 bits as signed. The remaining coefficient is only
    // -2..2, so its product is a mux/shift, leaving one true 18x9 multiply.
    wire signed [17:0] difference_low = difference[17:0];
    wire signed [2:0] difference_high = $signed({difference[19],difference[19:18]}) +
                                         $signed({2'b0,difference[17]});
    wire signed [26:0] low_product = difference_low * $signed({1'b0,active_weight});
    wire signed [10:0] weight_wide = $signed({3'b0,active_weight});
    reg signed [10:0] high_product;
    always @* begin
        case(difference_high)
            -3'sd2: high_product=-(weight_wide <<< 1);
            -3'sd1: high_product=-weight_wide;
             3'sd1: high_product=weight_wide;
             3'sd2: high_product=weight_wide <<< 1;
            default: high_product=0;
        endcase
    end
    wire signed [27:0] high_shifted = $signed({{17{high_product[10]}},high_product}) <<< 18;
    wire signed [27:0] delta_product = $signed({low_product[26],low_product}) + high_shifted;
    wire signed [27:0] sine_wide = {{9{sine_sum[18]}},sine_sum};
    wire signed [27:0] base_product = (sine_wide <<< 8) - sine_wide;
    wire signed [28:0] numerator = $signed({base_product[27],base_product}) +
                                  $signed({delta_product[27],delta_product}) + 29'sd127;
    wire signed [26:0] blend = numerator >>> 8;
    wire signed [27:0] scaled = blend >>> 1;              // 与 mixer_s6 的 VOLUME_SHIFT=1 一致
    wire signed [27:0] after_pressure;
    generate
        if (PRESSURE_GAIN_ENABLE != 0) begin : g_pressure
            localparam integer ADC_SPAN = (PRESSURE_ADC_FULL > PRESSURE_ADC_LOW) ?
                                           PRESSURE_ADC_FULL - PRESSURE_ADC_LOW : 1;
            localparam integer GAIN_SPAN = 4096 - PRESSURE_MIN_GAIN_Q12;
            wire [11:0] pressure_delta = pressure_level - PRESSURE_ADC_LOW;
            wire [12:0] mapped_gain;
            // The default spans are both 3072: calibration needs only an adder,
            // with no divider, lookup ROM or control-path multiplier.
            if (ADC_SPAN == GAIN_SPAN) begin : g_unit_slope
                assign mapped_gain = PRESSURE_MIN_GAIN_Q12 + pressure_delta;
            end else begin : g_calibrated_slope
                wire [31:0] gain_numerator = {20'd0, pressure_delta} * GAIN_SPAN;
                assign mapped_gain = PRESSURE_MIN_GAIN_Q12 + gain_numerator / ADC_SPAN;
            end
            wire [12:0] calibrated_gain = (pressure_level <= PRESSURE_ADC_LOW) ?
                                          PRESSURE_MIN_GAIN_Q12 :
                                          (pressure_level >= PRESSURE_ADC_FULL) ?
                                          13'd4096 : mapped_gain;
            wire [12:0] target_gain = pressure_enable ? calibrated_gain : 13'd4096;
            reg  [12:0] gain_q12;
            reg  [12:0] gain_next;
            always @* begin
                gain_next = target_gain;
                if ((target_gain > gain_q12) &&
                    ((target_gain - gain_q12) > PRESSURE_GAIN_STEP))
                    gain_next = gain_q12 + PRESSURE_GAIN_STEP;
                else if ((gain_q12 > target_gain) &&
                         ((gain_q12 - target_gain) > PRESSURE_GAIN_STEP))
                    gain_next = gain_q12 - PRESSURE_GAIN_STEP;
            end
            always @(posedge clk) begin
                if (rst)
                    gain_q12 <= 13'd4096;
                else if (update)
                    gain_q12 <= gain_next;
            end
            // signed 19-bit component inputs and weights summing to 255 bound
            // scaled to [-130560,130559], so signed 18 bits suffice. Q12 unity
            // needs 13 unsigned bits / 14 signed bits: one 18x18-sized VCA.
            wire signed [17:0] master_sample = scaled[17:0];
            wire signed [31:0] pressure_product =
                master_sample * $signed({1'b0, gain_next});
            assign after_pressure = pressure_product >>> 12;
`ifdef SIMULATION
            initial begin
                if ((PRESSURE_ADC_LOW < 0) || (PRESSURE_ADC_FULL > 4095) ||
                    (PRESSURE_ADC_FULL <= PRESSURE_ADC_LOW) ||
                    (PRESSURE_MIN_GAIN_Q12 < 0) || (PRESSURE_MIN_GAIN_Q12 > 4096) ||
                    (PRESSURE_GAIN_STEP < 1) || (PRESSURE_GAIN_STEP > 4096))
                    $fatal(1, "Invalid pressure calibration or slew parameters");
            end
`endif
        end else begin : g_pressure_bypass
            assign after_pressure = scaled;
        end
    endgenerate

    // The gain acts on the wide sample, not on an already clipped 16-bit word.
    // Statistics describe the actual post-pressure master boundary once/frame.
    wire raw_clip = (after_pressure > 28'sd32767) || (after_pressure < -28'sd32768);
    wire signed [15:0] sat = (after_pressure > 28'sd32767) ? 16'sd32767 :
                             (after_pressure < -28'sd32768) ? -16'sd32768 : after_pressure[15:0];

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
