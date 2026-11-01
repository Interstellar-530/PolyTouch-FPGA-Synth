// 与 wavetable_osc_dual_s6 契约相同的变体，但两张表用显式 Gowin pROM 原语
// （rtl/audio/gowin_prom_wave_*.v，由 tools/gen_gowin_prom_init.py 生成），
// 不依赖综合器把行为数组推断成 BSRAM。pROM 的 bypass 读自带一级寄存，
// 因此本模块不再像行为版那样另加 a/b 寄存器，总体仍是“地址 -> 两拍后输出”。
module wavetable_osc_dual_prom (
    input  wire               clk,
    input  wire               rst,
    input  wire               en,
    input  wire [31:0]        phase,
    input  wire               mix_enable,
    input  wire [7:0]         mix_weight,
    output reg signed [15:0]  sample_q
);

    wire [8:0] idx_a = phase[31:23];
    wire [8:0] idx_b = idx_a + 9'd1;          // 9 位自然回绕到 0
    wire [8:0] frac  = phase[22:14];

    wire [15:0] sine_a_d, sine_b_d, bright_a_d, bright_b_d;

    gowin_prom_wave_sine u_sine_rom (
        .clk(clk), .ce(en), .rst(rst), .addr(idx_a), .dout(sine_a_d));
    gowin_prom_wave_sine u_sine_rom_b (
        .clk(clk), .ce(en), .rst(rst), .addr(idx_b), .dout(sine_b_d));
    gowin_prom_wave_bright u_bright_rom (
        .clk(clk), .ce(en), .rst(rst), .addr(idx_a), .dout(bright_a_d));
    gowin_prom_wave_bright u_bright_rom_b (
        .clk(clk), .ce(en), .rst(rst), .addr(idx_b), .dout(bright_b_d));

    wire signed [15:0] sine_a_q = sine_a_d;
    wire signed [15:0] sine_b_q = sine_b_d;
    wire signed [15:0] bright_a_q = bright_a_d;
    wire signed [15:0] bright_b_q = bright_b_d;

    // 与 S6 行为版逐位相同的插值与混合口径。
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
    wire signed [15:0] selected_sat =
        (selected > 18'sd32767)  ? 16'sd32767 :
        (selected < -18'sd32768) ? -16'sd32768 : selected[15:0];

    always @(posedge clk) begin
        if (rst)
            sample_q <= 16'sd0;
        else if (en)
            sample_q <= selected_sat;
    end

endmodule