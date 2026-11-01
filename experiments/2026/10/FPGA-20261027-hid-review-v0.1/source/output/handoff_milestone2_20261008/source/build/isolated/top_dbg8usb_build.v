// [USB + FSR] 板载 PT8211 / 27 MHz / 46.875 kHz，普通 USB 键盘走 CH9350L，
// FSR 压力增益启用，GPIO 琴键关闭。旧的 debug8 档保持原样。
module top_dbg8usb_build (
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
    output wire        hp_bck,
    output wire        hp_ws,
    output wire        hp_din,
    output wire        pa_en,
    output wire        led,
    output wire        led_chord,
    output wire        led_t0,
    output wire        led_t1,
    output wire        uart_tx,
    output wire [3:0]  clip_fold
);
    wire i2s_bck_w, i2s_lrck_w, i2s_din_w, dac_xsmt_w;
    top #(.AUDIO_IF(0), .VOICES(8), .MASTER_VOLUME_SHIFT(3),
          .HOST_KBD_ENABLE(1), .GPIO_KEY_ENABLE(0), .PRESSURE_ENABLE(1)) u_top (
        .clk_27m(clk_27m), .clk_12m288(1'b0),
        .key_rst(key_rst), .key_s1(key_s1), .key_s2(key_s2),
        .uart_rx(uart_rx), .gpio_key_n(12'hFFF),
        .kbd_uart_rx(kbd_uart_rx), .kbd_uart_tx(kbd_uart_tx),
        .adc_cs_n(adc_cs_n), .adc_sck(adc_sck), .adc_mosi(adc_mosi), .adc_miso(adc_miso),
        .hp_bck(hp_bck), .hp_ws(hp_ws), .hp_din(hp_din), .pa_en(pa_en),
        .led(led), .led_chord(led_chord), .led_t0(led_t0), .led_t1(led_t1),
        .uart_tx(uart_tx), .clip_fold(clip_fold),
        .i2s_bck(i2s_bck_w), .i2s_lrck(i2s_lrck_w), .i2s_din(i2s_din_w), .dac_xsmt(dac_xsmt_w)
    );
endmodule