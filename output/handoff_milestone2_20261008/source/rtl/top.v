// Milestone 2 instrument bring-up:
// 27 MHz -> interpolating DDS -> ADSR -> smoothing -> on-board PT8211 DAC,
// with a synchronous design reset on S0 and a UART pitch interface.
//
// Still no touch, no ADC and no external PCM5102A logic in this build.
module top (
    input  wire clk_27m,
    input  wire key_rst,       // S3 / D7, active-low design reset
    input  wire key_s1,        // S1 / T3, tone preset C4
    input  wire key_s2,        // S2 / T2, tone preset C5
    input  wire uart_rx,       // N6, from the BL702 USB-UART bridge
    output wire hp_bck,
    output wire hp_ws,
    output wire hp_din,
    output wire pa_en,
    output wire led,
    output wire uart_tx        // N7, to the BL702 USB-UART bridge
);

    localparam [31:0] PHASE_INC_A4 = 32'd40315426; // 440.00 Hz at 46.875 kHz
    localparam [31:0] PHASE_INC_C4 = 32'd23971696; // 261.63 Hz, middle C
    localparam [31:0] PHASE_INC_C5 = 32'd47943392; // 523.25 Hz, high C
    localparam [1:0]  TONE_A4 = 2'd0;
    localparam [1:0]  TONE_C4 = 2'd1;
    localparam [1:0]  TONE_C5 = 2'd2;
    localparam [3:0]  VOLUME_SHIFT = 4'd2;         // divide by 4, about -12 dB

    // ------------------------------------------------------- reset tree ---
    // The power-on reset releases about 2.4 ms after configuration. The
    // headphone amplifier enable follows the power-on reset only, so pressing
    // the reset key never mutes the amplifier and never produces a pop.
    reg [15:0] reset_cnt;
    always @(posedge clk_27m) begin
        if (reset_cnt != 16'hFFFF)
            reset_cnt <= reset_cnt + 1'b1;
    end

    wire por = (reset_cnt != 16'hFFFF);
    assign pa_en = ~por;

    // The board has no dedicated reset key that the fabric can read: S0 sits
    // on T10, which the GW2A-18PG256 package reserves for the configuration
    // SSPI function, and S4 is wired to B10 RECONFIG_N. S3 on D7 is a plain
    // 1.5 V user IO in the same bank group as the S1 and S2 keys, so the
    // design reset is built from it here.
    reg [1:0] rst_key_sync;
    always @(posedge clk_27m)
        rst_key_sync <= {rst_key_sync[0], key_rst};

    wire soft_rst = ~rst_key_sync[1];

    // Everything in the audio chain uses this reset, which includes S0.
    wire rst = por | soft_rst;

    // -------------------------------------------------------- tone keys ---
    reg [1:0] key_s1_sync;
    reg [1:0] key_s2_sync;
    always @(posedge clk_27m) begin
        key_s1_sync <= {key_s1_sync[0], key_s1};
        key_s2_sync <= {key_s2_sync[0], key_s2};
    end

    wire key_s1_pressed = ~key_s1_sync[1];
    wire key_s2_pressed = ~key_s2_sync[1];

    localparam [19:0] DEBOUNCE_MAX = 20'hFFFFF; // about 38.8 ms at 27 MHz
    reg [19:0] db_s1_cnt;
    reg [19:0] db_s2_cnt;
    reg        s1_stable;
    reg        s2_stable;

    always @(posedge clk_27m) begin
        if (rst) begin
            db_s1_cnt <= 20'd0;
            db_s2_cnt <= 20'd0;
            s1_stable <= 1'b0;
            s2_stable <= 1'b0;
        end else begin
            if (!key_s1_pressed) begin
                db_s1_cnt <= 20'd0;
                s1_stable <= 1'b0;
            end else if (db_s1_cnt == DEBOUNCE_MAX) begin
                s1_stable <= 1'b1;
            end else begin
                db_s1_cnt <= db_s1_cnt + 1'b1;
            end

            if (!key_s2_pressed) begin
                db_s2_cnt <= 20'd0;
                s2_stable <= 1'b0;
            end else if (db_s2_cnt == DEBOUNCE_MAX) begin
                s2_stable <= 1'b1;
            end else begin
                db_s2_cnt <= db_s2_cnt + 1'b1;
            end
        end
    end

    reg s1_stable_d;
    reg s2_stable_d;
    always @(posedge clk_27m) begin
        s1_stable_d <= s1_stable;
        s2_stable_d <= s2_stable;
    end

    wire s1_press = s1_stable & ~s1_stable_d;
    wire s2_press = s2_stable & ~s2_stable_d;

    // -------------------------------------------------- pitch sources -----
    // A single frequency control word, written by three independent sources:
    // the S1 / S2 presets and the UART. Last writer wins, so the host can
    // type any frequency and the keys remain usable as quick presets.
    wire [31:0] uart_inc;
    wire [15:0] uart_freq;
    wire        uart_muted;
    wire        uart_accepted;

    uart_pitch u_uart_pitch (
        .clk        (clk_27m),
        .rst        (por),          // survive the S0 design reset
        .uart_rx    (uart_rx),
        .uart_tx    (uart_tx),
        .phase_inc  (uart_inc),
        .freq_hz    (uart_freq),
        .muted      (uart_muted),
        .accepted   (uart_accepted)
    );

    reg [31:0] phase_inc;
    always @(posedge clk_27m) begin
        if (rst)
            phase_inc <= PHASE_INC_A4;
        else if (uart_accepted)
            phase_inc <= uart_inc;
        else if (s1_press)
            phase_inc <= PHASE_INC_C4;
        else if (s2_press)
            phase_inc <= PHASE_INC_C5;
    end

    // ------------------------------------------------ run indicator -------
    reg [25:0] blink_cnt;
    reg        led_blink;
    always @(posedge clk_27m) begin
        if (por) begin
            blink_cnt <= 26'd0;
            led_blink <= 1'b0;
        end else if (blink_cnt == 26'd13_499_999) begin
            blink_cnt <= 26'd0;
            led_blink <= ~led_blink;
        end else begin
            blink_cnt <= blink_cnt + 1'b1;
        end
    end

    // Continuous gate: attack, then decay to sustain and hold there.
    wire gate = ~rst;

    wire signed [15:0] voice_sample;
    wire signed [15:0] pt_sample;
    wire               sample_tick;

    voice u_voice (
        .clk         (clk_27m),
        .rst         (rst),
        .sample_tick (sample_tick),
        .gate        (gate),
        .phase_inc   (phase_inc),
        .sample      (voice_sample)
    );

    // ------------------------------------------- smoothing and level ------
    // (1,4,6,4,1)/16 FIR, which is four cascaded two-tap averages. At
    // 46.875 kHz it is flat at 440 Hz, roughly -5 dB at 8 kHz, -22 dB at
    // 15 kHz and -26 dB at 20 kHz, with a null at Nyquist. It costs four
    // registers and a handful of adds, and it removes whatever high-frequency
    // residue the interpolating oscillator still leaves behind.
    reg signed [15:0] v1, v2, v3, v4;

    always @(posedge clk_27m) begin
        if (rst) begin
            v1 <= 16'sd0;
            v2 <= 16'sd0;
            v3 <= 16'sd0;
            v4 <= 16'sd0;
        end else if (sample_tick) begin
            v1 <= voice_sample;
            v2 <= v1;
            v3 <= v2;
            v4 <= v3;
        end
    end

    wire signed [19:0] fir_sum =
        voice_sample + v4 + ((v1 + v3) <<< 1) + ((v2 <<< 2) + (v2 <<< 1));

    wire signed [19:0] smooth = fir_sum >>> 4;

    // Round before shifting down instead of truncating, so the level control
    // does not add a signal-dependent DC step.
    wire signed [21:0] scaled =
        (smooth + (20'sd1 <<< (VOLUME_SHIFT - 1))) >>> VOLUME_SHIFT;

    // M0 from the host forces a digital zero so the listener can tell digital
    // content apart from board-level noise.
    assign pt_sample = (rst | uart_muted) ? 16'sd0 : scaled[15:0];

    pt8211_tx u_pt8211 (
        .clk         (clk_27m),
        .rst         (por),
        .sample_in   (pt_sample),
        .bck         (hp_bck),
        .ws          (hp_ws),
        .din         (hp_din),
        .sample_tick (sample_tick)
    );

    // Orange_LED2 on N16: blinking means running, solid means muted.
    assign led = uart_muted ? 1'b0 : led_blink;

endmodule
