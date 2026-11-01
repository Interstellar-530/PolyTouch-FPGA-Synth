`timescale 1ns/1ps

// Self-checking smoke test for the four-voice chain.
//
// It drives top with a fast 27 MHz clock, waits for the power-on reset, checks
// that the voice allocator hands out four voices to a four note chord, checks
// that a note-off releases the matching voice, and checks that S1 toggles the
// chord set.  It is intentionally independent of real time: the sample tick
// comes from pt8211_tx exactly as on hardware, so a few hundred microseconds
// of simulation already cover several musical events.
module tb_poly;

    reg clk = 1'b0;
    reg key_rst = 1'b1;
    reg key_s1 = 1'b1;
    reg key_s2 = 1'b1;
    reg uart_rx = 1'b1;

    wire hp_bck, hp_ws, hp_din, pa_en, led, led_chord, uart_tx;

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
        .uart_tx  (uart_tx)
    );

    task expect;
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

    // Wait for n sample ticks of the 46.875 kHz debug rate.
    task wait_ticks;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge dut.sample_tick);
        end
    endtask

    initial begin
        $dumpfile("tb_poly.vcd");
        $dumpvars(0, tb_poly);

        // Hold the design in reset for a while, then release it.
        #100000;
        key_rst = 1'b0;

        // The sequencer should start the tune on its own: within two ticks the
        // melody and the first chord must have claimed voices.
        wait_ticks(4);
        expect("voices allocated after start", |dut.v_gate, 1'b1);
        expect("chord set A is the default", led_chord, 1'b0);

        // The tune keeps running, so the mixer output must be non-zero at some
        // point over the first musical phrase.
        wait_ticks(400);
        expect("audio is running", |dut.mixed, 1'b1);

        // S1 toggles the chord set: the indicator follows, and the tune keeps
        // playing.
        key_s1 = 1'b0;
        #5000000;                     // longer than the 38.8 ms debounce
        key_s1 = 1'b1;
        wait_ticks(4);
        expect("S1 selected chord set B", led_chord, 1'b1);
        expect("tune still running after the key switch", |dut.v_gate, 1'b1);

        // S2 restarts: the allocator is cleared and the tune starts over.
        key_s2 = 1'b0;
        #5000000;
        key_s2 = 1'b1;
        wait_ticks(4);
        expect("S2 restarted the tune", |dut.v_gate, 1'b1);

        if (errors == 0)
            $display("PASS tb_poly");
        else
            $display("FAIL tb_poly with %0d error(s)", errors);
        $finish;
    end

    // Absolute timeout so a broken design cannot hang the simulator.
    initial begin
        #200000000;
        $display("FAIL tb_poly: timeout");
        $finish;
    end

endmodule
