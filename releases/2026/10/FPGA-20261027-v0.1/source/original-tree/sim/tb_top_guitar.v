`timescale 1ns/1ps
// 吉他档顶层快速检查：INSTRUMENT_DEFAULT=1 时选吉他表、起音、持续段不归零。
module tb_top_guitar;
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

    top #(.AUDIO_IF(0), .VOICES(8), .MASTER_VOLUME_SHIFT(3),
          .GPIO_KEY_ENABLE(0), .HOST_KBD_ENABLE(0), .INSTRUMENT_DEFAULT(1)) dut (
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

    integer frames = 0, win_start;
    integer maxabs = 0, active = 0;
    reg signed [15:0] bs;

    always @(posedge clk27) if (dut.sums_valid) begin
        frames = frames + 1;
        bs = dut.bright_sum;
        if (bs < 0) bs = -bs;
        if (bs > maxabs) maxabs = bs;
        if (bs > 200) active = active + 1;
    end

    initial begin
        repeat (20) @(posedge clk27);
        rst = 1;
        while (dut.por) @(posedge clk27);
        repeat (10) @(posedge clk27);
        if (dut.guitar_mode !== 1'b1) $fatal(1, "guitar_mode not set");
        send_cmd3("X", " ", " ");
        send_cmd3("N", "6", "9");
        repeat (2000) @(posedge clk27);
        if (dut.v_gate[0] !== 1'b1) $fatal(1, "guitar voice 0 not gated");
        if (dut.u_engine.guitar_sel_q !== 1'b1) $fatal(1, "guitar_sel_q not latched");
        if (dut.inc[0] !== 32'd40315424) $fatal(1, "A4 inc=%0d", dut.inc[0]);
        win_start = frames;
        while (frames - win_start < 3000) @(posedge clk27);
        if (maxabs < 500 || active < 2000)
            $fatal(1, "guitar audio too quiet maxabs=%0d active=%0d", maxabs, active);
        $display("INFO tb_top_guitar: maxabs=%0d active=%0d env=%0d inc=%0d",
                 maxabs, active, dut.v_env[0], dut.inc[0]);

        // 1 s 后仍在持续段，包络不能自行归零。当前 guitar sustain 为 16384。
        while (frames < 25000) @(posedge clk27);
        if (dut.v_env[0] < 16'd8192)
            $fatal(1, "guitar sustain env=%0d after 1s", dut.v_env[0]);
        $display("PASS tb_top_guitar: guitar table selected, audio active, sustain env=%0d", dut.v_env[0]);
        $finish;
    end

    initial begin #2000000000; $fatal(1, "timeout"); end
endmodule
