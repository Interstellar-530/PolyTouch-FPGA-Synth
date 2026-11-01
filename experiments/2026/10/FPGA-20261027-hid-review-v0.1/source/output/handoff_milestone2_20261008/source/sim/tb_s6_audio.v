`timescale 1ns/1ps
// S6 self-checking testbench, independent review revision (2026-10-15).
//
// The delivered checks (synchronous ROM read, table select, 50/50 blend,
// saturation without wrap, clip count/clear, FIR register boundary) are kept.
// On top of them every datapath is now compared value by value against
// tools/s6_reference.py vectors:
//   * 2560 phases (all 512 addresses x 5 interpolation fractions, including
//     the 511 -> 0 wrap seam) through the interpolating reader,
//   * 1024 ROM cross-fade points (4 addresses x all 256 weights) and 256
//     interpolated cross-fade points,
//   * 510 mixer samples across VOLUME_SHIFT 0/1/2 and FIR on/off, checking the
//     saturated output, the per-frame clip_event and the running clip count,
//   * a 32-sample small-amplitude FIR sequence that pins unity DC gain (the
//     delivered revision used a centre tap of 8, i.e. 18/16 gain, which the
//     old full-scale-only check could not see).
//
// Regenerate the vectors with:
//   python tools/s6_reference.py --vectors output/handoff_milestone2_20261008/source/sim/vectors
module tb_s6_audio;
    localparam integer OSC_VECTORS       = 3584;
    localparam integer BLEND_VECTORS     = 768;
    localparam integer ROM_BLEND_VECTORS = 1024;
    localparam integer OSC_BLEND_VECTORS = 256;
    localparam integer MIX_VECTORS       = 510;
    localparam integer FIR_VECTORS       = 32;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;

    reg en = 1'b0;
    reg [8:0] addr = 9'd0;
    reg mix_enable = 1'b0;
    reg [7:0] mix_weight = 8'd0;
    wire signed [15:0] sine_q, bright_q, sample_q;

    wavetable_rom_dual dut_rom (
        .clk(clk), .en(en), .addr(addr), .mix_enable(mix_enable),
        .mix_weight(mix_weight), .sine_q(sine_q), .bright_q(bright_q),
        .sample_q(sample_q)
    );

    reg osc_en = 1'b0;
    reg [31:0] phase = 32'd0;
    reg osc_mix_enable = 1'b0;
    reg [7:0] osc_mix_weight = 8'd0;
    wire signed [15:0] osc_sample;
    wavetable_osc_dual_s6 dut_osc (
        .clk(clk), .rst(rst), .en(osc_en), .phase(phase),
        .mix_enable(osc_mix_enable), .mix_weight(osc_mix_weight),
        .sample_q(osc_sample)
    );

    reg sample_tick = 1'b0;
    reg clear_clip = 1'b0;
    reg signed [15:0] v0 = 0, v1 = 0, v2 = 0, v3 = 0;

    wire signed [15:0] m_s0_off, m_s1_off, m_s2_off, m_s0_on, m_s1_on, m_s2_on;
    wire [7:0] c_s0_off, c_s1_off, c_s2_off, c_s0_on, c_s1_on, c_s2_on;
    wire e_s0_off, e_s1_off, e_s2_off, e_s0_on, e_s1_on, e_s2_on;

    mixer_s6 #(.VOLUME_SHIFT(0), .FIR_ENABLE(0), .CLIP_COUNTER_WIDTH(8)) u_m_s0_off (
        .clk(clk), .rst(rst), .sample_tick(sample_tick), .clear_clip(clear_clip),
        .v0(v0), .v1(v1), .v2(v2), .v3(v3), .sample_out(m_s0_off),
        .clip_count(c_s0_off), .clip_event(e_s0_off));
    mixer_s6 #(.VOLUME_SHIFT(1), .FIR_ENABLE(0), .CLIP_COUNTER_WIDTH(8)) u_m_s1_off (
        .clk(clk), .rst(rst), .sample_tick(sample_tick), .clear_clip(clear_clip),
        .v0(v0), .v1(v1), .v2(v2), .v3(v3), .sample_out(m_s1_off),
        .clip_count(c_s1_off), .clip_event(e_s1_off));
    mixer_s6 #(.VOLUME_SHIFT(2), .FIR_ENABLE(0), .CLIP_COUNTER_WIDTH(8)) u_m_s2_off (
        .clk(clk), .rst(rst), .sample_tick(sample_tick), .clear_clip(clear_clip),
        .v0(v0), .v1(v1), .v2(v2), .v3(v3), .sample_out(m_s2_off),
        .clip_count(c_s2_off), .clip_event(e_s2_off));
    mixer_s6 #(.VOLUME_SHIFT(0), .FIR_ENABLE(1), .CLIP_COUNTER_WIDTH(8)) u_m_s0_on (
        .clk(clk), .rst(rst), .sample_tick(sample_tick), .clear_clip(clear_clip),
        .v0(v0), .v1(v1), .v2(v2), .v3(v3), .sample_out(m_s0_on),
        .clip_count(c_s0_on), .clip_event(e_s0_on));
    mixer_s6 #(.VOLUME_SHIFT(1), .FIR_ENABLE(1), .CLIP_COUNTER_WIDTH(8)) u_m_s1_on (
        .clk(clk), .rst(rst), .sample_tick(sample_tick), .clear_clip(clear_clip),
        .v0(v0), .v1(v1), .v2(v2), .v3(v3), .sample_out(m_s1_on),
        .clip_count(c_s1_on), .clip_event(e_s1_on));
    mixer_s6 #(.VOLUME_SHIFT(2), .FIR_ENABLE(1), .CLIP_COUNTER_WIDTH(8)) u_m_s2_on (
        .clk(clk), .rst(rst), .sample_tick(sample_tick), .clear_clip(clear_clip),
        .v0(v0), .v1(v1), .v2(v2), .v3(v3), .sample_out(m_s2_on),
        .clip_count(c_s2_on), .clip_event(e_s2_on));

    // ---- vectors ---------------------------------------------------------
    reg [31:0] osc_phase [0:OSC_VECTORS-1];
    reg [15:0] osc_sine_exp [0:OSC_VECTORS-1];
    reg [15:0] osc_bright_exp [0:OSC_VECTORS-1];
    reg [15:0] bl_a [0:BLEND_VECTORS-1];
    reg [15:0] bl_b [0:BLEND_VECTORS-1];
    reg [7:0]  bl_w [0:BLEND_VECTORS-1];
    reg [15:0] bl_exp [0:BLEND_VECTORS-1];
    reg [8:0]  rb_addr [0:ROM_BLEND_VECTORS-1];
    reg [7:0]  rb_w [0:ROM_BLEND_VECTORS-1];
    reg [15:0] rb_exp [0:ROM_BLEND_VECTORS-1];
    reg [31:0] ob_phase [0:OSC_BLEND_VECTORS-1];
    reg [7:0]  ob_w [0:OSC_BLEND_VECTORS-1];
    reg [15:0] ob_exp [0:OSC_BLEND_VECTORS-1];
    reg [15:0] mx_v0 [0:MIX_VECTORS-1], mx_v1 [0:MIX_VECTORS-1];
    reg [15:0] mx_v2 [0:MIX_VECTORS-1], mx_v3 [0:MIX_VECTORS-1];
    reg [3:0]  mx_shift [0:MIX_VECTORS-1];
    reg [3:0]  mx_fir [0:MIX_VECTORS-1];
    reg [15:0] mx_exp [0:MIX_VECTORS-1];
    reg [3:0]  mx_rawclip [0:MIX_VECTORS-1];
    reg [3:0]  mx_firclip [0:MIX_VECTORS-1];
    reg [7:0]  mx_count [0:MIX_VECTORS-1];
    reg [15:0] fir_in [0:FIR_VECTORS-1];
    reg [15:0] fir_exp [0:FIR_VECTORS-1];

    integer failures;
    integer i, k, idx;
    reg signed [15:0] cur_out;
    reg cur_ev;
    reg [7:0] cur_cnt;

    task tick;
        begin
            sample_tick = 1'b1;
            @(posedge clk);
            #1 sample_tick = 1'b0;
        end
    endtask

    initial begin
        $readmemh("sim/vectors/osc_phase.hex", osc_phase);
        $readmemh("sim/vectors/osc_sine_expected.hex", osc_sine_exp);
        $readmemh("sim/vectors/osc_bright_expected.hex", osc_bright_exp);
        $readmemh("sim/vectors/blend_a.hex", bl_a);
        $readmemh("sim/vectors/blend_b.hex", bl_b);
        $readmemh("sim/vectors/blend_weight.hex", bl_w);
        $readmemh("sim/vectors/blend_expected.hex", bl_exp);
        $readmemh("sim/vectors/rom_blend_addr.hex", rb_addr);
        $readmemh("sim/vectors/rom_blend_weight.hex", rb_w);
        $readmemh("sim/vectors/rom_blend_expected.hex", rb_exp);
        $readmemh("sim/vectors/osc_blend_phase.hex", ob_phase);
        $readmemh("sim/vectors/osc_blend_weight.hex", ob_w);
        $readmemh("sim/vectors/osc_blend_expected.hex", ob_exp);
        $readmemh("sim/vectors/mix_v0.hex", mx_v0);
        $readmemh("sim/vectors/mix_v1.hex", mx_v1);
        $readmemh("sim/vectors/mix_v2.hex", mx_v2);
        $readmemh("sim/vectors/mix_v3.hex", mx_v3);
        $readmemh("sim/vectors/mix_shift.hex", mx_shift);
        $readmemh("sim/vectors/mix_fir.hex", mx_fir);
        $readmemh("sim/vectors/mix_expected.hex", mx_exp);
        $readmemh("sim/vectors/mix_rawclip.hex", mx_rawclip);
        $readmemh("sim/vectors/mix_firclip.hex", mx_firclip);
        $readmemh("sim/vectors/mix_count.hex", mx_count);
        $readmemh("sim/vectors/fir_input.hex", fir_in);
        $readmemh("sim/vectors/fir_expected.hex", fir_exp);
    end

    initial begin
        failures = 0;
        repeat (2) @(posedge clk);
        rst = 1'b0;

        // ---- delivered qualitative checks --------------------------------
        en = 1'b1;
        addr = 9'd0;
        @(posedge clk); #1;
        if (sine_q !== 16'sh0000 || bright_q !== 16'sh0000) begin
            $display("FAIL ROM address 0 mismatch: sine=%h bright=%h", sine_q, bright_q);
            failures = failures + 1;
        end
        addr = 9'd128;
        if (sine_q !== 16'sh0000) begin
            $display("FAIL ROM changed before synchronous edge");
            failures = failures + 1;
        end
        @(posedge clk); #1;
        if (sine_q !== 16'sh7fff || bright_q !== 16'sh36e6) begin
            $display("FAIL ROM address 128 mismatch: sine=%h bright=%h", sine_q, bright_q);
            failures = failures + 1;
        end
        mix_enable = 1'b0;
        mix_weight = 8'hff;
        #1;
        if (sample_q !== bright_q) begin
            $display("FAIL bright table selection mismatch sample=%h bright=%h", sample_q, bright_q);
            failures = failures + 1;
        end
        mix_enable = 1'b1;
        mix_weight = 8'd128;
        #1;
        if ((sample_q > 16'sh5af4) || (sample_q < 16'sh5af2)) begin
            $display("FAIL 50/50 blend mismatch: %0d", sample_q);
            failures = failures + 1;
        end

        // ---- ROM cross-fade: 4 addresses x all 256 weights ---------------
        mix_enable = 1'b1;
        for (i = 0; i < ROM_BLEND_VECTORS; i = i + 1) begin
            if ((i == 0) || (rb_addr[i] !== rb_addr[i-1])) begin
                addr = rb_addr[i];
                @(posedge clk); #1;
            end
            mix_weight = rb_w[i];
            #1;
            if (sample_q !== $signed(rb_exp[i])) begin
                $display("FAIL rom blend addr=%0d w=%0d: dut=%0d ref=%0d",
                         rb_addr[i], rb_w[i], sample_q, $signed(rb_exp[i]));
                failures = failures + 1;
            end
        end
        mix_enable = 1'b0;
        mix_weight = 8'd0;

        // ---- interpolating reader: every address x five fractions --------
        osc_en = 1'b1;
        mix_enable = 1'b0;
        for (i = 0; i < OSC_VECTORS; i = i + 1) begin
            phase = osc_phase[i];
            osc_mix_enable = 1'b0;
            osc_mix_weight = 8'd0;
            @(posedge clk);              // request the adjacent entries
            @(posedge clk); #1;          // expose the interpolated sample
            if (osc_sample !== $signed(osc_sine_exp[i])) begin
                $display("FAIL osc sine phase=%h: dut=%0d ref=%0d",
                         osc_phase[i], osc_sample, $signed(osc_sine_exp[i]));
                failures = failures + 1;
            end
            osc_mix_weight = 8'hff;
            @(posedge clk); #1;
            if (osc_sample !== $signed(osc_bright_exp[i])) begin
                $display("FAIL osc bright phase=%h: dut=%0d ref=%0d",
                         osc_phase[i], osc_sample, $signed(osc_bright_exp[i]));
                failures = failures + 1;
            end
            osc_mix_weight = 8'd0;
        end

        // ---- interpolated cross-fade: one phase, all 256 weights ---------
        phase = ob_phase[0];
        osc_mix_enable = 1'b1;
        osc_mix_weight = 8'd0;
        @(posedge clk);
        @(posedge clk); #1;
        for (i = 0; i < OSC_BLEND_VECTORS; i = i + 1) begin
            osc_mix_weight = ob_w[i];
            @(posedge clk); #1;
            if (osc_sample !== $signed(ob_exp[i])) begin
                $display("FAIL osc blend w=%0d: dut=%0d ref=%0d",
                         ob_w[i], osc_sample, $signed(ob_exp[i]));
                failures = failures + 1;
            end
        end
        osc_mix_enable = 1'b0;

        // ---- mixer: 510 vectors over volume shift and FIR path ------------
        for (i = 0; i < MIX_VECTORS; i = i + 1) begin
            v0 = mx_v0[i]; v1 = mx_v1[i]; v2 = mx_v2[i]; v3 = mx_v3[i];
            tick();
            // the registered output is only valid after the sample tick
            idx = (mx_shift[i] * 2) + mx_fir[i];
            case (idx)
                0: begin cur_out = m_s0_off; cur_ev = e_s0_off; cur_cnt = c_s0_off; end
                1: begin cur_out = m_s0_on;  cur_ev = e_s0_on;  cur_cnt = c_s0_on;  end
                2: begin cur_out = m_s1_off; cur_ev = e_s1_off; cur_cnt = c_s1_off; end
                3: begin cur_out = m_s1_on;  cur_ev = e_s1_on;  cur_cnt = c_s1_on;  end
                4: begin cur_out = m_s2_off; cur_ev = e_s2_off; cur_cnt = c_s2_off; end
                default: begin cur_out = m_s2_on; cur_ev = e_s2_on; cur_cnt = c_s2_on; end
            endcase
            if (cur_out !== $signed(mx_exp[i])) begin
                $display("FAIL mixer vec %0d shift=%0d fir=%0d: dut=%0d ref=%0d",
                         i, mx_shift[i], mx_fir[i], cur_out, $signed(mx_exp[i]));
                failures = failures + 1;
            end
            if (cur_ev !== (mx_rawclip[i] != 0)) begin
                $display("FAIL mixer vec %0d clip_event=%b raw_clip=%0d",
                         i, cur_ev, mx_rawclip[i]);
                failures = failures + 1;
            end
            if (cur_cnt !== mx_count[i]) begin
                $display("FAIL mixer vec %0d clip_count=%0d expected=%0d", i, cur_cnt, mx_count[i]);
                failures = failures + 1;
            end
        end

        // ---- small amplitude FIR sequence: unity gain ---------------------
        v0 = 0; v1 = 0; v2 = 0; v3 = 0;
        repeat (4) tick();
        for (i = 0; i < FIR_VECTORS; i = i + 1) begin
            v0 = fir_in[i];
            tick();
            if (m_s0_on !== $signed(fir_exp[i])) begin
                $display("FAIL fir vec %0d in=%0d: dut=%0d ref=%0d",
                         i, $signed(fir_in[i]), m_s0_on, $signed(fir_exp[i]));
                failures = failures + 1;
            end
        end
        v0 = 0; v1 = 0; v2 = 0; v3 = 0;

        // ---- delivered clip/extrema and FIR boundary checks ---------------
        v0 = 16'sh7fff; v1 = 16'sh7fff; v2 = 16'sh7fff; v3 = 16'sh7fff;
        tick();
        if (m_s1_off !== 16'sh7fff || !e_s1_off) begin
            $display("FAIL positive saturation sample=%h event=%b", m_s1_off, e_s1_off);
            failures = failures + 1;
        end
        v0 = -16'sh8000; v1 = -16'sh8000; v2 = -16'sh8000; v3 = -16'sh8000;
        tick();
        if (m_s1_off !== -16'sh8000 || !e_s1_off) begin
            $display("FAIL negative saturation sample=%h event=%b", m_s1_off, e_s1_off);
            failures = failures + 1;
        end
        clear_clip = 1'b1;
        tick();
        clear_clip = 1'b0;
        if (c_s1_off !== 8'd0 || c_s1_on !== 8'd0) begin
            $display("FAIL clip counter did not clear: off=%0d on=%0d", c_s1_off, c_s1_on);
            failures = failures + 1;
        end

        v0 = 16'sd0; v1 = 16'sd0; v2 = 16'sd0; v3 = 16'sd0;
        repeat (4) tick();
        v0 = 16'sh7fff; v1 = 16'sh7fff; v2 = 16'sh7fff; v3 = 16'sh7fff;
        tick();
        if (m_s1_on !== 16'sd2047) begin
            $display("FAIL FIR first-sample latency/weight mismatch: %0d", m_s1_on);
            failures = failures + 1;
        end
        repeat (4) tick();
        if (m_s1_on !== 16'sh7fff) begin
            $display("FAIL FIR steady-state saturation mismatch: %h", m_s1_on);
            failures = failures + 1;
        end

        if (failures != 0) $fatal(1, "tb_s6_audio failures=%0d", failures);
        $display("PASS tb_s6_audio: ROM sync/select, %0d osc vectors, %0d+%0d blend points, %0d mixer vectors, %0d FIR samples",
                 OSC_VECTORS, ROM_BLEND_VECTORS, OSC_BLEND_VECTORS, MIX_VECTORS, FIR_VECTORS);
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "FAIL tb_s6_audio: timeout");
    end
endmodule