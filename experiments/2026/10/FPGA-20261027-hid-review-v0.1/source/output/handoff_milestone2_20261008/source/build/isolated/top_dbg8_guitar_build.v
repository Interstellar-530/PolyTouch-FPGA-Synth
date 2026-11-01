// [集成] 调试档（AUDIO_IF=0，板载 PT8211 / 27 MHz / 46.875 kHz）构建入口。
//
// 为什么要这层封装：top.v 同时声明了两套音频接口，调试档里标准 I2S 的四根输出
// 是常量但不接引脚的话布局器会把它们自动放到 Bank 5 的 SOM 互连脚上（1.8 V）。
// 这里只把本档真正使用的端口引到芯片边界，未用接口在封装内部被常量驱动并优化掉，
// 于是 CST 覆盖全部端口、没有自动分配，也不会去驱动 SOM 上别的外设。
//
// 本文件与 top.v 的端口列表必须同步；改动 top.v 端口后要一起改这里。
module top_dbg8_guitar_build (
    input  wire        clk_27m,       // H11
    input  wire        key_rst,       // S3 / D7，低有效设计复位
    input  wire        key_s1,        // S1 / T3，切伴奏集
    input  wire        key_s2,        // S2 / T2，下一速度档
    input  wire        uart_rx,       // T13
    input  wire [11:0] gpio_key_n,    // 12 路琴键，低有效
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

    wire        i2s_bck_w, i2s_lrck_w, i2s_din_w, dac_xsmt_w;   // 本档不用，内部消化

    top #(.AUDIO_IF(0), .VOICES(8), .MASTER_VOLUME_SHIFT(3), .INSTRUMENT_DEFAULT(1)) u_top (
        .clk_27m(clk_27m), .clk_12m288(1'b0),
        .key_rst(key_rst), .key_s1(key_s1), .key_s2(key_s2),
        .uart_rx(uart_rx), .gpio_key_n(gpio_key_n),
        .adc_cs_n(adc_cs_n), .adc_sck(adc_sck), .adc_mosi(adc_mosi), .adc_miso(adc_miso),
        .hp_bck(hp_bck), .hp_ws(hp_ws), .hp_din(hp_din), .pa_en(pa_en),
        .led(led), .led_chord(led_chord), .led_t0(led_t0), .led_t1(led_t1),
        .uart_tx(uart_tx), .clip_fold(clip_fold),
        .i2s_bck(i2s_bck_w), .i2s_lrck(i2s_lrck_w), .i2s_din(i2s_din_w), .dac_xsmt(dac_xsmt_w)
    );

endmodule