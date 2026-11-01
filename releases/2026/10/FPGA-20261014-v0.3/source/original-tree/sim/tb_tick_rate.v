`timescale 1ns/1ps

// Check the PT8211 frame rate.
//
// Nominal: BCK = 27 MHz / 18 = 1.5 MHz and one frame is 32 BCK, so a new
// sample_tick must arrive every 576 clocks.  If this test fails the pitch and
// every timing derived from it are wrong, so it is the first gate.
module tb_tick_rate;
    parameter EXPECTED_CLOCKS = 576;
    parameter TOLERANCE       = 1;

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
    integer checked = 0;
    integer bad = 0;

    always @(posedge clk) begin
        clocks = clocks + 1;
        if (sample_tick) begin
            ticks = ticks + 1;
            if (ticks > 1) begin
                checked = checked + 1;
                if ((clocks - last_tick_clock) < EXPECTED_CLOCKS - TOLERANCE ||
                    (clocks - last_tick_clock) > EXPECTED_CLOCKS + TOLERANCE) begin
                    bad = bad + 1;
                    $display("FAIL: sample_tick period %0d clocks, expected %0d",
                             clocks - last_tick_clock, EXPECTED_CLOCKS);
                end
            end
            last_tick_clock = clocks;
        end
    end

    initial begin
        #1000;
        rst = 1'b0;
        sample_in = 16'sh2000;
        #4000000;
        if (checked == 0)
            $fatal(1, "FAIL tb_tick_rate: no sample_tick seen");
        if (bad != 0)
            $fatal(1, "FAIL tb_tick_rate: %0d of %0d periods wrong", bad, checked);
        $display("PASS tb_tick_rate: %0d periods, all %0d clocks (%0.1f Hz)",
                 checked, EXPECTED_CLOCKS,
                 // #18.5185 是半周期；频率显示用完整的 37.037 ns。
                 // 此显示公式不改变上面的时钟计数/容差断言。
                 checked * 1.0e9 / (checked * EXPECTED_CLOCKS * 37.037));
        $finish;
    end
endmodule
