// [USB + FSR] 外置 PCM5102A / 27 MHz / 46.875 kHz，普通 USB 键盘走 CH9350L，
// FSR 压力增益启用，GPIO 琴键关闭。
module top_std27_build (
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
    output wire        dac_xsmt
);
    wire hp_bck_w, hp_ws_w, hp_din_w, pa_en_w;
    wire [3:0] clip_fold_w;
    top #(.AUDIO_IF(2), .I2S_DATA_BITS(24), .VOICES(8),
          .HOST_KBD_ENABLE(1), .GPIO_KEY_ENABLE(0), .PRESSURE_ENABLE(1)) u_top (
        .clk_27m(clk_27m), .clk_12m288(1'b0),
        .key_rst(key_rst), .key_s1(key_s1), .key_s2(key_s2),
        .uart_rx(uart_rx), .gpio_key_n(12'hFFF),
        .kbd_uart_rx(kbd_uart_rx), .kbd_uart_tx(kbd_uart_tx),
        .adc_cs_n(adc_cs_n), .adc_sck(adc_sck), .adc_mosi(adc_mosi), .adc_miso(adc_miso),
        .hp_bck(hp_bck_w), .hp_ws(hp_ws_w), .hp_din(hp_din_w), .pa_en(pa_en_w),
        .led(led), .led_chord(led_chord), .led_t0(led_t0), .led_t1(led_t1),
        .uart_tx(uart_tx), .clip_fold(clip_fold_w),
        .i2s_bck(i2s_bck), .i2s_lrck(i2s_lrck), .i2s_din(i2s_din), .dac_xsmt(dac_xsmt)
    );
endmodule