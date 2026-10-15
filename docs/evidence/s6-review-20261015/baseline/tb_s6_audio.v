// S6 self-checking testbench: synchronous dual-ROM reads, controllable table
// selection/cross-fade, and four-voice mixer saturation/clip accounting.
`timescale 1ns/1ps
module tb_s6_audio;
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
    wire signed [15:0] mix_off_sample;
    wire [7:0] mix_off_clip;
    wire mix_off_event;
    mixer_s6 #(.FIR_ENABLE(0), .VOLUME_SHIFT(1), .CLIP_COUNTER_WIDTH(8)) dut_mix_off (
        .clk(clk), .rst(rst), .sample_tick(sample_tick), .clear_clip(clear_clip),
        .v0(v0), .v1(v1), .v2(v2), .v3(v3), .sample_out(mix_off_sample),
        .clip_count(mix_off_clip), .clip_event(mix_off_event)
    );

    wire signed [15:0] mix_on_sample;
    wire [7:0] mix_on_clip;
    wire mix_on_event;
    mixer_s6 #(.FIR_ENABLE(1), .VOLUME_SHIFT(1), .CLIP_COUNTER_WIDTH(8)) dut_mix_on (
        .clk(clk), .rst(rst), .sample_tick(sample_tick), .clear_clip(clear_clip),
        .v0(v0), .v1(v1), .v2(v2), .v3(v3), .sample_out(mix_on_sample),
        .clip_count(mix_on_clip), .clip_event(mix_on_event)
    );

    task tick;
        begin
            sample_tick = 1'b1;
            @(posedge clk);
            #1 sample_tick = 1'b0;
        end
    endtask

    initial begin
        // ROM reset is intentionally not needed; the first edge with en=1 is
        // the synchronous read request and the following edge exposes it.
        repeat (2) @(posedge clk);
        rst = 1'b0;

        en = 1'b1;
        addr = 9'd0;
        @(posedge clk); #1;
        if (sine_q !== 16'sh0000 || bright_q !== 16'sh0000)
            $fatal(1, "ROM address 0 mismatch: sine=%h bright=%h", sine_q, bright_q);

        // Address 128 is a nonzero boundary sample.  The value must arrive
        // after a clock edge, never combinationally when addr changes.
        addr = 9'd128;
        if (sine_q !== 16'sh0000)
            $fatal(1, "ROM changed before synchronous edge");
        @(posedge clk); #1;
        if (sine_q !== 16'sh7fff || bright_q !== 16'sh36e6)
            $fatal(1, "ROM address 128 mismatch: sine=%h bright=%h", sine_q, bright_q);

        // Exact table switch and a 50/50 blend are both controlled at the
        // registered ROM output, with no second memory read or truncation.
        mix_enable = 1'b0;
        mix_weight = 8'hff;
        #1;
        if (sample_q !== bright_q)
            $fatal(1, "bright table selection mismatch sample=%h bright=%h sine=%h weight=%h dutw=%h sel=%h en=%b",
                   sample_q, bright_q, sine_q, mix_weight, dut_rom.mix_weight,
                   dut_rom.selected_table, mix_enable);
        mix_enable = 1'b1;
        mix_weight = 8'd128;
        #1;
        if ((sample_q > 16'sh5af4) || (sample_q < 16'sh5af2))
            $fatal(1, "50/50 blend mismatch: %0d", sample_q);

        // The phase reader uses the same synchronous table contract while
        // adding 9-bit linear interpolation.  One request edge fills the
        // adjacent-entry registers; the following edge exposes the result.
        osc_en = 1'b1;
        phase = 32'h40000000; // table address 128, fraction 0
        @(posedge clk); #1;
        @(posedge clk); #1;
        if (osc_sample !== 16'sh7fff)
            $fatal(1, "dual oscillator interpolation mismatch: %h", osc_sample);
        osc_mix_weight = 8'hff;
        @(posedge clk); #1;
        if (osc_sample !== 16'sh36e6)
            $fatal(1, "dual oscillator bright selection mismatch: %h", osc_sample);
        phase = 32'hffffffff;
        osc_mix_weight = 8'd0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        if ((osc_sample > 16'sd1) || (osc_sample < -16'sd2))
            $fatal(1, "phase wrap interpolation mismatch: %0d", osc_sample);

        // Saturation and clip count: same-phase four-voice extrema must never
        // wrap to the opposite sign.  Each sample tick contributes one count.
        mix_enable = 1'b0;
        mix_weight = 8'd0;
        v0 = 16'sh7fff; v1 = 16'sh7fff; v2 = 16'sh7fff; v3 = 16'sh7fff;
        tick();
        if (mix_off_sample !== 16'sh7fff || mix_off_clip !== 8'd1 || !mix_off_event)
            $fatal(1, "positive saturation/clip mismatch sample=%h count=%0d event=%b",
                   mix_off_sample, mix_off_clip, mix_off_event);
        v0 = -16'sh8000; v1 = -16'sh8000; v2 = -16'sh8000; v3 = -16'sh8000;
        tick();
        if (mix_off_sample !== -16'sh8000 || mix_off_clip !== 8'd2 || !mix_off_event)
            $fatal(1, "negative saturation/clip mismatch sample=%h count=%0d event=%b",
                   mix_off_sample, mix_off_clip, mix_off_event);

        clear_clip = 1'b1;
        tick();
        clear_clip = 1'b0;
        if (mix_off_clip !== 8'd0)
            $fatal(1, "clip counter did not clear");

        // FIR starts at a deterministic zero history and converges without
        // wrapping.  Its one-sample-tick register boundary is observable.
        v0 = 16'sd0; v1 = 16'sd0; v2 = 16'sd0; v3 = 16'sd0;
        repeat (4) tick();
        v0 = 16'sh7fff; v1 = 16'sh7fff; v2 = 16'sh7fff; v3 = 16'sh7fff;
        tick();
        if (mix_on_sample !== 16'sd2047)
            $fatal(1, "FIR first-sample latency/weight mismatch: %0d", mix_on_sample);
        repeat (4) tick();
        if (mix_on_sample !== 16'sh7fff)
            $fatal(1, "FIR steady-state saturation mismatch: %h", mix_on_sample);

        $display("PASS tb_s6_audio: dual ROM sync/select/interpolation, mixer saturation, FIR and clip counter");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "tb_s6_audio timeout");
    end
endmodule
