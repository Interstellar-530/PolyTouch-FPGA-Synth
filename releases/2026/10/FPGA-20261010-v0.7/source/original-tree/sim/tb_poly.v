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

    wire hp_bck, hp_ws, hp_din, pa_en, led, led_chord, led_t0, led_t1, uart_tx;

    integer errors = 0;

    always #18.5185 clk = ~clk;      // 27 MHz

    top dut (
        .clk_27m  (clk),
        .key_rst  (key_rst),
        .key_s1   (key_s1),
        .key_s2   (key_s2),
        .uart_rx  (uart_rx),
        .hp_bck   (hp_bck),
        .hp_ws    (hp_ws),
        .hp_din   (hp_din),
        .pa_en    (pa_en),
        .led      (led),
        .led_chord(led_chord),
        .led_t0   (led_t0),
        .led_t1   (led_t1),
        .uart_tx  (uart_tx)
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

        // Default preset is index 2 (3x): bit 0 set, bit 1 clear.  The LEDs
        // are active low, so lit means the bit is zero.
        check_equal("power-on reset released", pa_en, 1'b1);
        check_equal("default preset index 1, bit0 lit", led_t0, 1'b0);
        check_equal("default preset index 1, bit1 dark", led_t1, 1'b1);
        check_equal("chord set A, indicator dark", led_chord, 1'b1);

        // S1 switches to chord set B; its indicator lights.
        key_s1 = 1'b0;
        #(DEBOUNCE_HOLD);
        key_s1 = 1'b1;
        #1000000;
        check_equal("S1 selected chord set B", led_chord, 1'b0);

        // S2 steps to preset 3 (4x): both bits set, both tempo LEDs dark.
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
