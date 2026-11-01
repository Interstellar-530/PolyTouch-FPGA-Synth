// Bench only: no external keys/ADC/oscillator/DAC connected.
module board_only_top(
    input wire clk_27m,key_rst,key_s1,key_s2,uart_rx,
    output wire hp_bck,hp_ws,hp_din,pa_en,
    output wire led,led_chord,led_t0,led_t1,uart_tx
);
    wire adc_cs_unused,adc_sck_unused,adc_mosi_unused;
    wire [3:0] fold_unused;
    wire i2s_bck_unused,i2s_lrck_unused,i2s_din_unused,xsmt_unused;
    top #(.AUDIO_IF(0)) u_top(
        .clk_27m(clk_27m),.clk_12m288(1'b0),
        .key_rst(key_rst),.key_s1(key_s1),.key_s2(key_s2),.uart_rx(uart_rx),
        .gpio_key_n(12'hfff),.adc_miso(1'b0),
        .adc_cs_n(adc_cs_unused),.adc_sck(adc_sck_unused),.adc_mosi(adc_mosi_unused),
        .hp_bck(hp_bck),.hp_ws(hp_ws),.hp_din(hp_din),.pa_en(pa_en),
        .led(led),.led_chord(led_chord),.led_t0(led_t0),.led_t1(led_t1),.uart_tx(uart_tx),
        .clip_fold(fold_unused),.i2s_bck(i2s_bck_unused),.i2s_lrck(i2s_lrck_unused),
        .i2s_din(i2s_din_unused),.dac_xsmt(xsmt_unused)
    );
    // Existing parameter, isolated bench calibration: constant zero => no bend.
    defparam u_top.u_bend.ADC_CENTER=12'd0;
endmodule
