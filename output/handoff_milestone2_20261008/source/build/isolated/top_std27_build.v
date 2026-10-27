// [集成] 27 MHz 标准 I2S 档（AUDIO_IF=2，外置 PCM5102A / 板载 27 MHz / 46.875 kHz）构建入口。
//
// 与 top_std_build 的区别：
//   1) 不接收 T7 的 12.288 MHz，直接用核心板 H11 的 27 MHz；27e6/9/64 = 46875 Hz 整除，
//      BCK = 3.000 MHz，仍是 64 BCK/帧、24 位槽。采样率是 46.875 kHz，不是 48 kHz；
//      音高由 top 的 AUDIO_FS_HZ 参数保证，不是把 12.288 MHz 位流改接 27 MHz 冒充 48 kHz。
//   2) 停用 12 路 GPIO 演奏键（GPIO_KEY_ENABLE=0），演奏由 USB 电脑键盘经 CH9350L
//      下位机（state 2）从 kbd_uart_rx 输入；GPIO 输入在内部固定为未按下。
//
// 本文件与 top.v 的端口列表必须同步；改动 top.v 端口后要一起改这里。
module top_std27_build #(
    parameter integer HOST_KBD_TIMEOUT_POLICY = 1
) (
    input  wire        clk_27m,       // H11，核心板板载 27 MHz 有源晶振
    input  wire        key_rst,       // S3 / D7，低有效设计复位
    input  wire        key_s1,        // S1 / T3，切伴奏集
    input  wire        key_s2,        // S2 / T2，下一速度档
    input  wire        uart_rx,       // T13，BL702 调试串口
    input  wire        kbd_uart_rx,   // L9（J5-5），CH9350L 下位机 TXD
    output wire        kbd_uart_tx,   // N8（J5-6），到 CH9350L RXD；当前固定高
    output wire        adc_cs_n,
    output wire        adc_sck,
    output wire        adc_mosi,
    input  wire        adc_miso,
    output wire        led,
    output wire        led_chord,
    output wire        led_t0,
    output wire        led_t1,
    output wire        uart_tx,
    output wire        i2s_bck,       // B12（J6-5）-> PCM5102A BCK，3.000 MHz
    output wire        i2s_lrck,      // C12（J6-6）-> LRCK，46.875 kHz
    output wire        i2s_din,       // B13（J6-7）-> DIN，24 位有效数据
    output wire        dac_xsmt       // P6（J14-12）-> 软静音，1 = 解除静音
);

    wire        hp_bck_w, hp_ws_w, hp_din_w, pa_en_w;   // 本档不用板载耳放
    wire [3:0]  clip_fold_w;                            // 本档没有空闲脚，观测口折入内部

    top #(
        .AUDIO_IF(2), .I2S_DATA_BITS(24),
        // +6.02 dB over the previous /8 mix; retain soft limiting and V0..V100.
        .VOICES(8), .MASTER_VOLUME_SHIFT(2),
        .GPIO_KEY_ENABLE(0), .HOST_KBD_TIMEOUT_POLICY(HOST_KBD_TIMEOUT_POLICY), .HOST_KBD_ENABLE(1)
    ) u_top (
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
