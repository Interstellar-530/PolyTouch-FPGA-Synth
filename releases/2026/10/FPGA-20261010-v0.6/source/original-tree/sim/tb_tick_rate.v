`timescale 1ns/1ps

// Measures the real sample tick period of the PT8211 transmitter, in 27 MHz
// clock cycles.  Nominal is BCK = 27/18 = 1.5 MHz and 32 BCK per frame, i.e.
// 576 clocks, or 46875 Hz.
module tb_tick_rate;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg signed [15:0] sample_in = 16'sd0;

    wire bck, ws, din, sample_tick;

    always #18.5185 clk = ~clk;      // 27 MHz

    pt8211_tx dut (
        .clk         (clk),
        .rst         (rst),
        .sample_in   (sample_in),
        .bck         (bck),
        .ws          (ws),
        .din         (din),
        .sample_tick (sample_tick)
    );

    integer clocks = 0;
    integer ticks = 0;
    integer last_tick_clock = 0;

    always @(posedge clk) begin
        clocks = clocks + 1;
        if (sample_tick) begin
            ticks = ticks + 1;
            if (ticks <= 4)
                $display("sample_tick %0d at clock %0d, period %0d clocks",
                         ticks, clocks, clocks - last_tick_clock);
            last_tick_clock = clocks;
        end
    end

    initial begin
        #1000;
        rst = 1'b0;
        sample_in = 16'sh2000;
        #4000000;
        $display("total ticks %0d, sample rate %0.1f Hz",
                 ticks, ticks * 1.0e9 / 4000000.0 * 1.0 / 1.0);
        $finish;
    end
endmodule
