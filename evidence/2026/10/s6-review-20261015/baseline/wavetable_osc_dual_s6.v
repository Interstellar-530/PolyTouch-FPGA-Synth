// S6 synchronous dual-table phase reader with linear interpolation.
//
// `phase` uses the same split as dds_osc.v: bits [31:23] address a 512-point
// table and bits [22:14] are a 9-bit interpolation fraction.  Both adjacent
// entries of both tables are sampled on a clock edge.  sample_q is produced
// from the previously sampled entries, so the model has an explicit one-clock
// ROM/output latency.  The two array ports map to true dual-port Gowin ROM
// IPs in hardware; this behavioral form keeps the simulation deterministic.
module wavetable_osc_dual_s6 #(
    parameter integer DEPTH = 512,
    parameter SINE_INIT = "rtl/audio/wave_sine.hex",
    parameter BRIGHT_INIT = "rtl/audio/wave_bright.hex"
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               en,
    input  wire [31:0]        phase,
    input  wire               mix_enable,
    input  wire [7:0]         mix_weight,
    output reg signed [15:0]  sample_q
);

    reg signed [15:0] sine_rom [0:DEPTH-1];
    reg signed [15:0] bright_rom [0:DEPTH-1];
    reg signed [15:0] sine_a_q, sine_b_q, bright_a_q, bright_b_q;

    wire [8:0] idx_a = phase[31:23];
    wire [8:0] idx_b = idx_a + 9'd1;
    wire [8:0] frac = phase[22:14];

    initial begin
        $readmemh(SINE_INIT, sine_rom);
        $readmemh(BRIGHT_INIT, bright_rom);
    end

    wire signed [16:0] sine_diff = $signed(sine_b_q) - $signed(sine_a_q);
    wire signed [16:0] bright_diff = $signed(bright_b_q) - $signed(bright_a_q);
    wire signed [9:0] frac_ext = $signed({1'b0, frac});
    wire signed [26:0] sine_diff_ext = {{10{sine_diff[16]}}, sine_diff};
    wire signed [26:0] bright_diff_ext = {{10{bright_diff[16]}}, bright_diff};
    wire signed [26:0] frac_wide = {{17{frac_ext[9]}}, frac_ext};
    wire signed [53:0] sine_prod_full = sine_diff_ext * frac_wide;
    wire signed [53:0] bright_prod_full = bright_diff_ext * frac_wide;
    wire signed [26:0] sine_prod = sine_prod_full[26:0];
    wire signed [26:0] bright_prod = bright_prod_full[26:0];
    wire signed [17:0] sine_interp = $signed(sine_a_q) + ((sine_prod + 27'sd256) >>> 9);
    wire signed [17:0] bright_interp = $signed(bright_a_q) + ((bright_prod + 27'sd256) >>> 9);

    wire signed [24:0] sine_ext = {{7{sine_interp[17]}}, sine_interp};
    wire signed [24:0] bright_ext = {{7{bright_interp[17]}}, bright_interp};
    wire signed [24:0] sine_weight = {17'd0, (8'hff - mix_weight)};
    wire signed [24:0] bright_weight = {17'd0, mix_weight};
    wire signed [49:0] sine_mix_prod = sine_ext * sine_weight;
    wire signed [49:0] bright_mix_prod = bright_ext * bright_weight;
    wire signed [25:0] blend_sum = sine_mix_prod[25:0] + bright_mix_prod[25:0] + 26'sd127;
    wire signed [25:0] blend = blend_sum >>> 8;
    wire signed [17:0] selected = mix_enable ? blend[17:0] :
                                   (mix_weight[7] ? bright_interp : sine_interp);
    wire selected_clip_hi = selected > 18'sd32767;
    wire selected_clip_lo = selected < -18'sd32768;
    wire signed [15:0] selected_sat =
        selected_clip_hi ? 16'sd32767 :
        selected_clip_lo ? -16'sd32768 : selected[15:0];

    always @(posedge clk) begin
        if (rst) begin
            sine_a_q   <= 16'sd0;
            sine_b_q   <= 16'sd0;
            bright_a_q <= 16'sd0;
            bright_b_q <= 16'sd0;
            sample_q   <= 16'sd0;
        end else if (en) begin
            sample_q   <= selected_sat;
            sine_a_q   <= sine_rom[idx_a];
            sine_b_q   <= sine_rom[idx_b];
            bright_a_q <= bright_rom[idx_a];
            bright_b_q <= bright_rom[idx_b];
        end
    end

endmodule
