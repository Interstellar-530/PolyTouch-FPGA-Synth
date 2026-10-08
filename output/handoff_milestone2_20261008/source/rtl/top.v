// First instrument bring-up milestone:
// 27 MHz clock -> DDS sine -> ADSR -> on-board PT8211 debug DAC.
// No touch, ADC, or external PCM5102A logic is included in this build yet.
module top (
    input  wire clk_27m,
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
    reg  [15:0] gate_cnt;
    reg  [25:0] blink_cnt;
    reg         led_blink;
    wire signed [15:0] voice_sample;
    wire signed [15:0] pt_sample;

    localparam [31:0] PHASE_INC_440 = 32'd40315426; // 440 Hz at 46.875 kHz

    always @(posedge clk_27m) begin
        if (reset_cnt != 16'hFFFF)
            reset_cnt <= reset_cnt + 1'b1;
    end

    assign rst = (reset_cnt != 16'hFFFF);
    assign pa_en = ~rst;

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

    always @(posedge clk_27m) begin
        if (rst) begin
            gate_cnt <= 16'd0;
        end else if (sample_tick) begin
            if (gate_cnt == 16'd23437)
                gate_cnt <= 16'd0;
            else
                gate_cnt <= gate_cnt + 1'b1;
        end
    end

    assign gate = (gate_cnt < 16'd11718); // 0.25 s on, 0.25 s off

    voice u_voice (
        .clk         (clk_27m),
        .rst         (rst),
        .sample_tick (sample_tick),
        .gate        (gate),
        .phase_inc   (PHASE_INC_440),
        .sample      (voice_sample)
    );

    // The first frame is silent while the serial transmitter initializes.
    assign pt_sample = rst ? 16'sd0 : voice_sample;

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
