`timescale 1ns/1ps

// Top level wiring check.
//
// This is deliberately short.  It checks that the design leaves reset, that
// the default tempo preset is the one that was found correct on the bench, and
// that the two user keys actually reach the sequencer through the debouncer.
// Deep sequencer and audio timing are covered by tb_song_timing and
// tb_tick_rate, which run much faster because they do not instantiate the
// whole chip.
module tb_poly;

    parameter DEBOUNCE_HOLD = 50000000;   // 50 ms, longer than the 38.8 ms debounce

    reg clk = 1'b0;
    reg key_rst = 1'b0;      // active low: 0 holds the design in reset
    reg key_s1 = 1'b1;
    reg key_s2 = 1'b1;
    reg uart_rx = 1'b1;
    reg [11:0] gpio_key_n = 12'hFFF;    // [S2-AI] 全部松开，本测试台不涉及 GPIO

    wire hp_bck, hp_ws, hp_din, pa_en, led, led_chord, led_t0, led_t1, uart_tx;

    integer errors = 0;

    always #18.5185 clk = ~clk;      // 27 MHz

    // [S4/S5/S6] 新增顶层端口与 MCP3208 器件模型：CH0 作压力、CH1 作弯音。
    // 弯音保持在中点 2048，比率恰为 1.0，因此本测试台原有的音频期望不变。
    wire adc_cs_n, adc_sck, adc_mosi, adc_miso;
    wire [3:0] clip_fold;
    reg [11:0] adc_ch0 = 12'd1024, adc_ch1 = 12'd2048;
    mcp3208_model u_adc_model (
        .cs_n(adc_cs_n), .sclk(adc_sck), .mosi(adc_mosi), .miso(adc_miso),
        .ch0(adc_ch0), .ch1(adc_ch1), .ch2(12'd0), .ch3(12'd0),
        .ch4(12'd0), .ch5(12'd0), .ch6(12'd0), .ch7(12'd0)
    );

    top dut (
        .clk_27m  (clk),
        .key_rst  (key_rst),
        .key_s1   (key_s1),
        .key_s2   (key_s2),
        .uart_rx  (uart_rx),
        .gpio_key_n(gpio_key_n),
        .hp_bck   (hp_bck),
        .hp_ws    (hp_ws),
        .hp_din   (hp_din),
        .pa_en    (pa_en),
        .led      (led),
        .led_chord(led_chord),
        .led_t0   (led_t0),
        .led_t1   (led_t1),
        .uart_tx  (uart_tx),
        .adc_cs_n (adc_cs_n), .adc_sck (adc_sck), .adc_mosi (adc_mosi),
        .adc_miso (adc_miso), .clip_fold (clip_fold)
    );


    // Named check_equal rather than "expect": that word is a SystemVerilog
    // keyword and the parser rejects it as a task name.
    task check_equal;
        input [255:0] what;
        input         got;
        input         want;
        begin
            if (got !== want) begin
                $display("FAIL %0s: got %b want %b", what, got, want);
                errors = errors + 1;
            end else begin
                $display("ok   %0s", what);
            end
        end
    endtask

    initial begin
        // Hold the design in reset, then release it.
        #100000;
        key_rst = 1'b1;
        // The power-on reset takes 65536 clocks, about 2.4 ms; wait well past
        // it before reading any output.
        #5000000;

        // 默认档位 index 1（2x），tempo_sel=01。LED 引脚低电平亮：
        // led_t0=~bit0=0 表示 bit0=1，led_t1=~bit1=1 表示 bit1=0。
        check_equal("power-on reset released", pa_en, 1'b1);
        check_equal("default preset index 1, bit0 lit", led_t0, 1'b0);
        check_equal("default preset index 1, bit1 dark", led_t1, 1'b1);
        check_equal("chord set A, indicator dark", led_chord, 1'b1);

        // S1 switches to chord set B; its indicator lights.
        key_s1 = 1'b0;
        #(DEBOUNCE_HOLD);
        key_s1 = 1'b1;
        #25000000; // S1 short press commits after 20 ms release debounce.
        check_equal("S1 selected chord set B", led_chord, 1'b0);

        // S2 从 index 1 到 index 2（3x），tempo_sel=10；bit0 灯灭、bit1 灯亮。
        key_s2 = 1'b0;
        #(DEBOUNCE_HOLD);
        key_s2 = 1'b1;
        #1000000;
        check_equal("S2 stepped to preset index 2, bit0 dark", led_t0, 1'b1);
        check_equal("S2 stepped to preset index 2, bit1 lit", led_t1, 1'b0);

        if (errors == 0)
            $display("PASS tb_poly");
        else
            $fatal(1, "FAIL tb_poly with %0d error(s)", errors);
        $finish;
    end

    initial begin
        #400000000;
        $fatal(1, "FAIL tb_poly: timeout");
    end
endmodule
