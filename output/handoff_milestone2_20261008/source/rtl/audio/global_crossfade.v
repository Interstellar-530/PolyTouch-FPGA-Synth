// 全局交叉混合：把两条分量和（19 位）按 (255-w, w) >> 8 混合一次，
// 再做与 mixer_s6 相同的“除以 2”、16 位饱和与主增益边界削波统计。
// 与逐声部版相比，混合乘法从每声部 2 次降为整机 2 次；
// 舍入只发生一次而不是每声部一次，偏差界见集成复核记录。
//
// 削波统计沿用 S6 的定义：主增益边界上，本帧（混合/除二及可选压力增益后）的取值
// 超出 16 位有符号范围时计一次，计数到全 1 饱和，clear_clip 同步清零。
// 逐声部版由 mixer_s6 在该边界计数；共享引擎把这条边界移到了本模块。
module global_crossfade #(
    parameter integer CLIP_COUNTER_WIDTH = 32,
    // Default disabled keeps existing standalone users bit-exact. The product
    // standard-I2S profile enables this frame-rate global VCA before saturation.
    parameter integer PRESSURE_GAIN_ENABLE = 0,
    parameter integer PRESSURE_ADC_LOW = 128,
    parameter integer PRESSURE_ADC_FULL = 3200,
    parameter integer PRESSURE_MIN_GAIN_Q12 = 1024,
    parameter integer PRESSURE_GAIN_STEP = 32
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
    wire signed [26:0] sine_prod = $signed(sine_sum) * $signed({19'd0, (8'hff - mix_weight)});
    wire signed [26:0] bright_prod = $signed(bright_sum) * $signed({19'd0, mix_weight});
    wire signed [26:0] blend = (sine_prod + bright_prod + 27'sd127) >>> 8;
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
