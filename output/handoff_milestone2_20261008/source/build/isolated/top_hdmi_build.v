// HDMI dashboard production profile. Audio remains on the verified 27 MHz /
// 46.875 kHz external PCM5102A path; the same 27 MHz source feeds the HDMI PLL.
module top_hdmi_build (
    input  wire        clk_27m,
    input  wire        key_rst,
    input  wire        key_s1,
    input  wire        key_s2,
    input  wire        uart_rx,
    input  wire        kbd_uart_rx,
    output wire        kbd_uart_tx,
    output wire        adc_cs_n,
    output wire        adc_sck,
    output wire        adc_mosi,
    input  wire        adc_miso,
    output wire        led,
    output wire        led_chord,
    output wire        led_t0,
    output wire        led_t1,
    output wire        uart_tx,
    output wire        i2s_bck,
    output wire        i2s_lrck,
    output wire        i2s_din,
    output wire        dac_xsmt,
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_data_p,
    output wire [2:0]  tmds_data_n
);
    wire        hp_bck_w, hp_ws_w, hp_din_w, pa_en_w;
    wire [3:0]  clip_fold_w;
    wire [63:0] ui_status;
    wire        ui_status_toggle;
    wire [255:0] ui_waveform;
    wire [63:0]  ui_spectrum;
    wire [63:0]  ui_lissajous;
    wire         ui_visual_toggle;
    wire         display_route;
    wire [31:0]  ui_voice_mask;

    instrument32_top #(
        .AUDIO_IF(2), .I2S_DATA_BITS(24),
        .VOICES(32), .MASTER_VOLUME_SHIFT(5),
        .GPIO_KEY_ENABLE(0), .HOST_KBD_ENABLE(1)
    ) u_top (
        .clk_27m(clk_27m), .clk_12m288(1'b0),
        .key_rst(key_rst), .key_s1(key_s1), .key_s2(key_s2),
        .uart_rx(uart_rx), .gpio_key_n(12'hFFF),
        .kbd_uart_rx(kbd_uart_rx), .kbd_uart_tx(kbd_uart_tx),
        .adc_cs_n(adc_cs_n), .adc_sck(adc_sck), .adc_mosi(adc_mosi), .adc_miso(adc_miso),
        .hp_bck(hp_bck_w), .hp_ws(hp_ws_w), .hp_din(hp_din_w), .pa_en(pa_en_w),
        .led(led), .led_chord(led_chord), .led_t0(led_t0), .led_t1(led_t1),
        .uart_tx(uart_tx), .clip_fold(clip_fold_w),
        .i2s_bck(i2s_bck), .i2s_lrck(i2s_lrck), .i2s_din(i2s_din), .dac_xsmt(dac_xsmt),
        .ui_status(ui_status), .ui_status_toggle(ui_status_toggle),
        .ui_waveform(ui_waveform), .ui_spectrum(ui_spectrum),
        .ui_lissajous(ui_lissajous), .ui_visual_toggle(ui_visual_toggle),
        .display_route(display_route),.ui_voice_mask(ui_voice_mask)
    );

    hdmi_dashboard #(.SAMPLE_RATE_48K(0),.VOICES(32)) u_hdmi (
        .clk_27m(clk_27m), .key_rst(key_rst), .enable(display_route),
        .ui_status(ui_status), .ui_status_toggle(ui_status_toggle),.ui_voice_mask(ui_voice_mask),
        .ui_waveform(ui_waveform), .ui_spectrum(ui_spectrum),
        .ui_lissajous(ui_lissajous), .ui_visual_toggle(ui_visual_toggle),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n)
    );
endmodule
