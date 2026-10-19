`timescale 1ns/1ps
// 8 声部顶层音高快速回归：UART X + N69，测引擎 sine_sum 的过零周期。
// 不做 I2S 解码/屏幕统计，几千帧即可，避免长门禁。
module tb_top_pitch8;
    reg clk27 = 0, clk12 = 0;
    always #18.5185 clk27 = ~clk27;
    always #40.69 clk12 = ~clk12;

    reg rst = 0, s1 = 1, s2 = 1, uart_rx = 1;
    wire uart_tx, kbd_tx;
    wire hp_bck, hp_ws, hp_din, pa_en, led, led_chord, led_t0, led_t1;
    wire adc_cs_n, adc_sck, adc_mosi, adc_miso;
    wire [3:0] clip_fold;
    wire i2s_bck, i2s_lrck, i2s_din, dac_xsmt;

    mcp3208_model u_adc (
        .cs_n(adc_cs_n), .sclk(adc_sck), .mosi(adc_mosi), .miso(adc_miso),
        .ch0(12'd2048), .ch1(12'd2048), .ch2(12'd0), .ch3(12'd0),
        .ch4(12'd0), .ch5(12'd0), .ch6(12'd0), .ch7(12'd0)
    );

    top #(.AUDIO_IF(2), .I2S_DATA_BITS(24), .VOICES(8), .MASTER_VOLUME_SHIFT(3),
          .GPIO_KEY_ENABLE(0), .HOST_KBD_ENABLE(0)) dut (
        .clk_27m(clk27), .clk_12m288(clk12),
        .key_rst(rst), .key_s1(s1), .key_s2(s2),
        .uart_rx(uart_rx), .gpio_key_n(12'hFFF),
        .kbd_uart_rx(1'b1), .kbd_uart_tx(kbd_tx),
        .adc_cs_n(adc_cs_n), .adc_sck(adc_sck), .adc_mosi(adc_mosi), .adc_miso(adc_miso),
        .hp_bck(hp_bck), .hp_ws(hp_ws), .hp_din(hp_din), .pa_en(pa_en),
        .led(led), .led_chord(led_chord), .led_t0(led_t0), .led_t1(led_t1),
        .uart_tx(uart_tx), .clip_fold(clip_fold),
        .i2s_bck(i2s_bck), .i2s_lrck(i2s_lrck), .i2s_din(i2s_din), .dac_xsmt(dac_xsmt)
    );

    task send_byte;
        input [7:0] b;
        integer i;
        begin
            @(negedge clk27); uart_rx = 1'b0; #8667;
            for (i = 0; i < 8; i = i + 1) begin uart_rx = b[i]; #8667; end
            uart_rx = 1'b1; #8667;
        end
    endtask

    task send_cmd3;
        input [7:0] a, b, c;
        begin
            send_byte(a); send_byte(b); send_byte(c); send_byte(8'h0D);
        end
    endtask

    integer frames = 0, win_start, n, period;
    integer xing = 0, first = -1, last = -1, idx = 0;
    reg signed [20:0] prev = 0;
    always @(posedge clk27) if (dut.sums_valid) begin
        frames = frames + 1;
        idx = idx + 1;
        if (prev <= 0 && dut.sine_sum > 0) begin
            xing = xing + 1;
            if (first < 0) first = idx;
            last = idx;
        end
        prev <= dut.sine_sum;
    end

    initial begin
        repeat (20) @(posedge clk27);
        rst = 1;
        while (dut.por) @(posedge clk27);
        repeat (10) @(posedge clk27);
        send_cmd3("X", " ", " ");
        send_cmd3("N", "6", "9");
        repeat (2000) @(posedge clk27);
        if (dut.v_gate !== 8'b0000_0001)
            $fatal(1, "voice 0 not gated: %b", dut.v_gate);
        xing = 0; first = -1; last = -1; idx = 0; prev = 0;
        win_start = frames;
        while (frames - win_start < 2500) @(posedge clk27);
        if (xing < 20) $fatal(1, "too few sine crossings: %0d", xing);
        period = ((last - first) * 100) / (xing - 1);
        $display("INFO tb_top_pitch8: A4 sine period=%0d.%02d (expect 106.53), crossings=%0d, inc=%0d",
                 period / 100, period % 100, xing, dut.inc[0]);
        if (period < 10546 || period > 10760)
            $fatal(1, "8-voice top pitch wrong: %0d.%02d", period / 100, period % 100);
        $display("PASS tb_top_pitch8");
        $finish;
    end

    initial begin
        #200000000;
        $fatal(1, "timeout");
    end
endmodule
