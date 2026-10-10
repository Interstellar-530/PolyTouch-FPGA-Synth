// First instrument bring-up milestone:
// 27 MHz clock -> DDS sine -> ADSR -> on-board PT8211 debug DAC.
// No touch, ADC, or external PCM5102A logic is included in this build yet.
//
// The ADSR gate is held high after reset so the voice attacks, decays to the
// sustain level, and then holds that level indefinitely. The previous build
// chopped the gate on and off every 0.25 s to prove the envelope was running;
// that produced the alarm-like buzz the listener reported. Tone switching is
// now the only thing that changes while running.
module top (
    input  wire clk_27m,
    input  wire key_s1,
    input  wire key_s2,
    output wire hp_bck,
    output wire hp_ws,
    output wire hp_din,
    output wire pa_en,
    output wire led
);

    reg [15:0] reset_cnt;
    wire       rst;
    wire       sample_tick;
    wire       gate;
    reg  [25:0] blink_cnt;
    reg         led_blink;
    wire signed [15:0] voice_sample;
    wire signed [15:0] pt_sample;

    localparam [31:0] PHASE_INC_A4 = 32'd40315426; // 440.00 Hz at 46.875 kHz
    localparam [31:0] PHASE_INC_C4 = 32'd23971696; // 261.63 Hz, middle C
    localparam [31:0] PHASE_INC_C5 = 32'd47943392; // 523.25 Hz, high C
    localparam [1:0]  TONE_A4 = 2'd0;
    localparam [1:0]  TONE_C4 = 2'd1;
    localparam [1:0]  TONE_C5 = 2'd2;
    localparam [3:0]  VOLUME_SHIFT = 4'd2;         // divide by 4, about -12 dB

    always @(posedge clk_27m) begin
        if (reset_cnt != 16'hFFFF)
            reset_cnt <= reset_cnt + 1'b1;
    end

    assign rst = (reset_cnt != 16'hFFFF);
    assign pa_en = ~rst;

    // T3/T2 user keys are active-low and pulled to the 1.5 V bank rail.
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

    reg [1:0] tone_sel;
    always @(posedge clk_27m) begin
        if (rst)
            tone_sel <= TONE_A4;
        else if (s1_press)
            tone_sel <= TONE_C4;
        else if (s2_press)
            tone_sel <= TONE_C5;
    end

    reg [31:0] phase_inc;
    always @(*) begin
        case (tone_sel)
            TONE_C4: phase_inc = PHASE_INC_C4;
            TONE_C5: phase_inc = PHASE_INC_C5;
            default: phase_inc = PHASE_INC_A4;
        endcase
    end

    // Visible programming/run indicator: toggle about every 0.5 s at 27 MHz.
    always @(posedge clk_27m) begin
        if (rst) begin
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
    // Tone selection only changes the DDS frequency control word.
    assign gate = ~rst;

    voice u_voice (
        .clk         (clk_27m),
        .rst         (rst),
        .sample_tick (sample_tick),
        .gate        (gate),
        .phase_inc   (phase_inc),
        .sample      (voice_sample)
    );

    // Two-stage smoothing and rounded level control, applied before the
    // fixed-gain PT8211 / LPA4809 headphone amplifier.
    //
    // Each stage is a two-tap average; cascading two of them gives the
    // (1,2,1)/4 FIR. At 46.875 kHz that is flat at 440 Hz, about -3 dB near
    // 8.5 kHz, about -11 dB at 15 kHz and a null at Nyquist, and it needs
    // nothing but adds and shifts. Together with the interpolating oscillator
    // this removes the residual high-frequency shimmer that the bare
    // 512-entry lookup left behind.
    reg signed [15:0] x_d1;
    reg signed [16:0] avg1;
    reg signed [16:0] avg1_d;

    always @(posedge clk_27m) begin
        if (rst) begin
            x_d1   <= 16'sd0;
            avg1   <= 17'sd0;
            avg1_d <= 17'sd0;
        end else if (sample_tick) begin
            x_d1   <= voice_sample;
            avg1   <= (voice_sample + x_d1) >>> 1;
            avg1_d <= avg1;
        end
    end

    wire signed [16:0] smooth = (avg1 + avg1_d) >>> 1;

    // Round before shifting down instead of truncating, so the level control
    // does not add a signal-dependent DC step. The first frame stays silent
    // while the serial transmitter initialises.
    wire signed [17:0] scaled =
        (smooth + (17'sd1 <<< (VOLUME_SHIFT - 1))) >>> VOLUME_SHIFT;

    assign pt_sample = rst ? 16'sd0 : scaled[15:0];

    pt8211_tx u_pt8211 (
        .clk         (clk_27m),
        .rst         (rst),
        .sample_in   (pt_sample),
        .bck         (hp_bck),
        .ws          (hp_ws),
        .din         (hp_din),
        .sample_tick (sample_tick)
    );

    // Orange_LED2 on N16: visible programming/run indicator.
    assign led = led_blink;

endmodule

