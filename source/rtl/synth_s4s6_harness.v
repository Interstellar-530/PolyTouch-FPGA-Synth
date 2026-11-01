// Synthesis/PnR harness for the reviewed S4-S6 modules.
//
// This is NOT a functional product top: the real top-level integration (ADC
// scheduler into top.v, wavetable voices, standard I2S) is still pending.  The
// harness exists so that Gowin synthesis and place-and-route report the real
// resource cost of the reviewed control path (mcp3208_spi + pressure_bend) and
// audio path (dual wavetable ROM + interpolating reader + four-voice mixer_s6)
// instead of pruning them as unused logic.
//
// Pin usage comes from docs/hardware/FPGA-pinplan-20261013-v0.1.csv and is
// still a draft: constrain it, build it, but do not program until the physical
// wiring and bank voltages have been verified.
module synth_s4s6_harness (
    input  wire               clk_27m,
    input  wire               rst_n,          // active-low board reset
    // MCP3208 SPI (pinplan: N6/D11/A11/B11)
    output wire               adc_cs_n,
    output wire               adc_sck,
    output wire               adc_mosi,
    input  wire               adc_miso,
    // four voice phases are generated internally from a counter so the
    // oscillator datapath is exercised without a sequencer
    // audio result
    // Folded observables: every reviewed datapath must influence one of these
    // 4-bit outputs, otherwise synthesis prunes it as unreachable logic.
    // The pins are the twelve GPIO key pins from the pinplan CSV; the harness
    // does not use a keyboard, so they are free for measurement.
    output wire [3:0]         audio_fold,     // covers mixer_s6 / oscillators
    output wire [3:0]         status_fold,    // covers pressure filter, bend, ROM wrapper
    output wire [3:0]         clip_fold       // covers the clip counter and ADC status
);

    wire rst = ~rst_n;

    // ---------------------------------------------------- control clock ---
    // 2 kHz control tick from the 27 MHz system clock (13 500 clocks).
    reg [13:0] ctrl_div = 14'd0;
    reg        control_tick = 1'b0;
    always @(posedge clk_27m) begin
        if (ctrl_div == 14'd13499) begin
            ctrl_div     <= 14'd0;
            control_tick <= 1'b1;
        end else begin
            ctrl_div     <= ctrl_div + 1'b1;
            control_tick <= 1'b0;
        end
    end

    // ------------------------------------------------------- ADC sequencer --
    wire        adc_busy;
    wire        adc_done;
    wire        adc_valid;
    wire [11:0] adc_data;
    reg [2:0]  adc_channel = 3'd0;
    reg        adc_start   = 1'b0;
    reg [11:0] pressure_raw = 12'd2048;
    reg [11:0] bend_raw     = 12'd2048;

    always @(posedge clk_27m) begin
        adc_start <= 1'b0;
        if (control_tick && !adc_busy) begin
            adc_start   <= 1'b1;
            adc_channel <= ~adc_channel[0];
        end
        if (adc_done) begin
            if (adc_channel[0]) bend_raw     <= adc_data;
            else                pressure_raw <= adc_data;
        end
    end

    mcp3208_spi #(.CLK_HZ(27_000_000), .SPI_HZ(250_000)) u_adc (
        .clk(clk_27m), .rst(rst), .start(adc_start), .channel(adc_channel),
        .miso(adc_miso), .cs_n(adc_cs_n), .sclk(adc_sck), .mosi(adc_mosi),
        .busy(adc_busy), .done(adc_done), .data(adc_data), .data_valid(adc_valid),
        .adc_data()
    );

    // -------------------------------------------------- pressure and bend ---
    wire [11:0]        pressure_filtered;
    wire [11:0]        pressure_level;
    wire signed [15:0] bend_q8;
    wire [16:0]        bend_ratio_q16;
    wire [31:0]        bend_phase_inc;

    pressure_bend u_bend (
        .clk(clk_27m), .rst(rst), .control_tick(control_tick),
        .pressure_adc(pressure_raw), .bend_adc(bend_raw),
        .pressure_enable(1'b1), .base_phase_inc(32'd1_000_000),
        .pressure_filtered(pressure_filtered), .pressure_level(pressure_level),
        .bend_q8(bend_q8), .bend_ratio_q16(bend_ratio_q16),
        .phase_inc_out(bend_phase_inc)
    );

    // The module interface reports everything it needs on the pins above; the
    // level and filter outputs stay internal to the harness.
    wire [11:0] unused_level = pressure_level ^ pressure_filtered;

    // -------------------------------------------------------- four voices ---
    // Four free-running phases; the bend ratio scales each increment so the
    // measured resources include the per-voice bend multiply.
    reg [31:0] phase0 = 32'd0, phase1 = 32'h2000_0000,
               phase2 = 32'h4000_0000, phase3 = 32'h6000_0000;
    reg [31:0] inc0 = 32'd47756, inc1 = 32'd56818,
               inc2 = 32'd67622, inc3 = 32'd80460;   // C4/E4/G4/C5 at 46.875 kHz
    reg [31:0] b_inc0 = 32'd47756, b_inc1 = 32'd56818,
               b_inc2 = 32'd67622, b_inc3 = 32'd80460;

    always @(posedge clk_27m) begin
        phase0 <= phase0 + b_inc0;
        phase1 <= phase1 + b_inc1;
        phase2 <= phase2 + b_inc2;
        phase3 <= phase3 + b_inc3;
        if (control_tick) begin
            b_inc0 <= (inc0 * bend_ratio_q16) >> 16;
            b_inc1 <= (inc1 * bend_ratio_q16) >> 16;
            b_inc2 <= (inc2 * bend_ratio_q16) >> 16;
            b_inc3 <= (inc3 * bend_ratio_q16) >> 16;
        end
    end

    wire signed [15:0] v0, v1, v2, v3;
    wavetable_osc_dual_s6 u_osc0 (
        .clk(clk_27m), .rst(rst), .en(1'b1), .phase(phase0),
        .mix_enable(1'b0), .mix_weight(8'h00), .sample_q(v0));
    wavetable_osc_dual_s6 u_osc1 (
        .clk(clk_27m), .rst(rst), .en(1'b1), .phase(phase1),
        .mix_enable(1'b0), .mix_weight(8'h40), .sample_q(v1));
    wavetable_osc_dual_s6 u_osc2 (
        .clk(clk_27m), .rst(rst), .en(1'b1), .phase(phase2),
        .mix_enable(1'b1), .mix_weight(8'h80), .sample_q(v2));
    wavetable_osc_dual_s6 u_osc3 (
        .clk(clk_27m), .rst(rst), .en(1'b1), .phase(phase3),
        .mix_enable(1'b1), .mix_weight(8'hff), .sample_q(v3));

    // A single 46.875 kHz frame tick derived from the control tick keeps the
    // harness self-contained; the product top feeds the PT8211 tick instead.
    reg [4:0] frame_div = 5'd0;
    reg       sample_tick = 1'b0;
    always @(posedge clk_27m) begin
        sample_tick <= 1'b0;
        if (control_tick) begin
            if (frame_div == 5'd23) begin
                frame_div   <= 5'd0;
                sample_tick <= 1'b1;      // 2 kHz / 24 ~ 83 Hz placeholder
            end else begin
                frame_div <= frame_div + 1'b1;
            end
        end
    end

    wire signed [15:0] sample_out;
    wire [31:0]        clip_count;
    mixer_s6 #(.VOLUME_SHIFT(1), .FIR_ENABLE(1), .CLIP_COUNTER_WIDTH(32)) u_mix (
        .clk(clk_27m), .rst(rst), .sample_tick(sample_tick), .clear_clip(1'b0),
        .v0(v0), .v1(v1), .v2(v2), .v3(v3),
        .sample_out(sample_out), .clip_count(clip_count), .clip_event(clip_event)
    );

    // Touch the draft ROM wrapper too, so its BSRAM cost is measured next to
    // the interpolating reader.
    wire signed [15:0] rom_sine, rom_bright, rom_sample;
    reg  [8:0] rom_addr = 9'd0;
    always @(posedge clk_27m) rom_addr <= phase0[31:23];
    wavetable_rom_dual u_rom (
        .clk(clk_27m), .en(1'b1), .addr(rom_addr),
        .mix_enable(1'b1), .mix_weight(8'h80),
        .sine_q(rom_sine), .bright_q(rom_bright), .sample_q(rom_sample)
    );

    // ---------------------------------------------------- folded observables ---
    function [3:0] fold16;
        input [15:0] value;
        begin
            fold16 = value[15:12] ^ value[11:8] ^ value[7:4] ^ value[3:0];
        end
    endfunction

    function [3:0] fold12;
        input [11:0] value;
        begin
            fold12 = value[11:8] ^ value[7:4] ^ value[3:0];
        end
    endfunction

    assign audio_fold  = fold16(sample_out) ^ fold16({v0[15:8], v1[15:8]}) ^
                         fold16({v2[15:8], v3[15:8]}) ^ fold16(rom_sample);
    assign status_fold = fold12(pressure_filtered) ^ fold12(pressure_level) ^
                         fold16(bend_q8) ^ fold16(rom_sine) ^ fold16(rom_bright) ^
                         fold12(unused_level);
    assign clip_fold   = clip_count[31:28] ^ clip_count[27:24] ^ clip_count[23:20] ^
                         clip_count[19:16] ^ clip_count[15:12] ^ clip_count[11:8] ^
                         clip_count[7:4] ^ clip_count[3:0] ^ {3'd0, clip_event} ^
                         {2'b00, adc_busy, adc_valid};
endmodule