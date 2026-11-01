// [集成] 标准 I2S 档（AUDIO_IF=1，外置 PCM5102A / 12.288 MHz / 48 kHz）构建入口。
//
// 与 top_dbg_build.v 对称：只引出本档使用的端口。板载 PT8211 三线、pa_en 与
// clip_fold 在本档不接芯片边界（前两者在 RTL 里恒为低，clip_fold 是调试观测口，
// 而 J5/J6/J14 已无 4 个空闲信号脚可放），在封装内部被常量驱动并优化掉，
// 因此 CST 覆盖全部端口、没有自动分配，也不会去驱动 SOM 上别的外设。
//
// 本文件与 top.v 的端口列表必须同步；改动 top.v 端口后要一起改这里。
module top_std_build (
    input  wire        clk_12m288,    // T7（J14-10，GCLKT_3），外置有源晶振
    input  wire        key_rst,       // S3 / D7，低有效设计复位
    input  wire        key_s1,        // S1 / T3，切伴奏集
    input  wire        key_s2,        // S2 / T2，下一速度档
    input  wire        uart_rx,       // T13
    input  wire [11:0] gpio_key_n,    // 12 路琴键，低有效
    output wire        adc_cs_n,
    output wire        adc_sck,
    output wire        adc_mosi,
    input  wire        adc_miso,
    output wire        led,
    output wire        led_chord,
    output wire        led_t0,
    output wire        led_t1,
    output wire        uart_tx,
    output wire        i2s_bck,       // B12（J6-5）-> PCM5102A BCK
    output wire        i2s_lrck,      // C12（J6-6）-> LRCK
    output wire        i2s_din,       // B13（J6-7）-> DIN
    output wire        dac_xsmt       // P6（J14-12）-> 软静音，1 = 解除静音
);

    wire        hp_bck_w, hp_ws_w, hp_din_w, pa_en_w;   // 本档不用板载耳放
    wire [3:0]  clip_fold_w;                            // 本档没有空闲脚，观测口折入内部

    top #(.AUDIO_IF(1), .I2S_DATA_BITS(24)) u_top (
        .clk_27m(1'b0), .clk_12m288(clk_12m288),
        .key_rst(key_rst), .key_s1(key_s1), .key_s2(key_s2),
        .uart_rx(uart_rx), .gpio_key_n(gpio_key_n),
        .adc_cs_n(adc_cs_n), .adc_sck(adc_sck), .adc_mosi(adc_mosi), .adc_miso(adc_miso),
        .hp_bck(hp_bck_w), .hp_ws(hp_ws_w), .hp_din(hp_din_w), .pa_en(pa_en_w),
        .led(led), .led_chord(led_chord), .led_t0(led_t0), .led_t1(led_t1),
        .uart_tx(uart_tx), .clip_fold(clip_fold_w),
        .i2s_bck(i2s_bck), .i2s_lrck(i2s_lrck), .i2s_din(i2s_din), .dac_xsmt(dac_xsmt)
    );

endmodule