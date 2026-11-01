`timescale 1ns/1ps
// S4 criterion "the ADC must not stall I2S".
//
// The production PT8211 transmitter and the MCP3208 master run from the same
// 27 MHz clock.  The transmitter owns the 46.875 kHz sample tick, so the test
// checks that every tick is exactly 576 clocks after the previous one while
// ADC frames are issued back to back, that every SCLK half period is the
// expected 54 clocks (27 MHz / 250 kHz / 2), and that every frame still
// delivers the requested code.
module tb_mcp3208_i2s_coexist;
    localparam integer TICK_CLOCKS = 576;
    localparam integer HALF_CLOCKS = 54;
    localparam integer REQUESTS    = 40;
    localparam integer IDLE_CLOCKS = 400;   // >> tCSH = 500 ns = 14 clocks

    reg clk = 1'b0;
    always #18.5185 clk = ~clk;             // 27 MHz
    reg rst = 1'b1;
    reg signed [15:0] sample_in = 16'sd0;

    wire bck, ws, din, sample_tick;

    reg start = 1'b0;
    reg [2:0] channel = 3'd0;
    wire miso, cs_n, sclk, mosi, busy, done, data_valid;
    wire [11:0] data, adc_data;

    pt8211_tx i2s (
        .clk(clk), .rst(rst), .sample_in(sample_in),
        .bck(bck), .ws(ws), .din(din), .sample_tick(sample_tick)
    );

    mcp3208_spi #(.CLK_HZ(27_000_000), .SPI_HZ(250_000)) adc (
        .clk(clk), .rst(rst), .start(start), .channel(channel), .miso(miso),
        .cs_n(cs_n), .sclk(sclk), .mosi(mosi), .busy(busy), .done(done),
        .data(data), .data_valid(data_valid), .adc_data(adc_data)
    );

    reg [11:0] chv [0:7];
    mcp3208_model model (
        .cs_n(cs_n), .sclk(sclk), .mosi(mosi), .miso(miso),
        .ch0(chv[0]), .ch1(chv[1]), .ch2(chv[2]), .ch3(chv[3]),
        .ch4(chv[4]), .ch5(chv[5]), .ch6(chv[6]), .ch7(chv[7])
    );

    integer failures, clkcnt, last_tick, ticks, checked_ticks, checked_halves;
    integer adc_ok, adc_done, i, last_sclk_edge;
    reg [2:0] chidx;

    always @(posedge clk) begin
        clkcnt = clkcnt + 1;
        if (sample_tick) begin
            ticks = ticks + 1;
            if (ticks > 1) begin
                checked_ticks = checked_ticks + 1;
                if ((clkcnt - last_tick) != TICK_CLOCKS) begin
                    $display("FAIL tick %0d period %0d clocks, expected %0d",
                             ticks, clkcnt - last_tick, TICK_CLOCKS);
                    failures = failures + 1;
                end
            end
            last_tick = clkcnt;
        end
    end

    always @(sclk) begin
        if (!cs_n && (clkcnt > 0)) begin
            if (last_sclk_edge > 0) begin
                checked_halves = checked_halves + 1;
                if ((clkcnt - last_sclk_edge) != HALF_CLOCKS) begin
                    $display("FAIL sclk half period %0d clocks, expected %0d",
                             clkcnt - last_sclk_edge, HALF_CLOCKS);
                    failures = failures + 1;
                end
            end
            last_sclk_edge = clkcnt;
        end else begin
            last_sclk_edge = 0;
        end
    end

    task request;
        input [2:0] ch;
        input [11:0] value;
        begin
            chv[ch] = value;
            @(negedge clk); channel <= ch; start <= 1'b1;
            @(negedge clk); start <= 1'b0;
            wait (done);
            adc_done = adc_done + 1;
            #1;
            if (data_valid !== 1'b1 || data !== value || adc_data !== value) begin
                $display("FAIL coexist ch=%0d value=%0d data=%0d valid=%b",
                         ch, value, data, data_valid);
                failures = failures + 1;
            end else begin
                adc_ok = adc_ok + 1;
            end
            repeat (IDLE_CLOCKS) @(posedge clk);
        end
    endtask

    initial begin
        failures = 0; clkcnt = 0; last_tick = 0; ticks = 0;
        checked_ticks = 0; checked_halves = 0; adc_ok = 0; adc_done = 0;
        last_sclk_edge = 0;
        chv[0] = 12'h123; chv[1] = 12'h456; chv[2] = 12'h789; chv[3] = 12'hABC;
        chv[4] = 12'hDEF; chv[5] = 12'h0F0; chv[6] = 12'h555; chv[7] = 12'hAAA;

        // Waveform capture is opt in: run `vvp tb.vvp +dump` to write
        // sim/tb_mcp3208_i2s_coexist.vcd.  The gate stays free of multi-megabyte dumps.
        if ($test$plusargs("dump")) begin
            $dumpfile("sim/tb_mcp3208_i2s_coexist.vcd");
            $dumpvars(0, tb_mcp3208_i2s_coexist);
        end

        repeat (4) @(posedge clk);
        rst = 1'b0;
        sample_in = 16'sh2000;
        repeat (10) @(posedge clk);

        for (i = 0; i < REQUESTS; i = i + 1) begin
            chidx = i[0] ? 3'd1 : 3'd0;
            request(chidx, 12'h100 + i[11:0]);
        end

        if (checked_ticks < 20) begin
            $display("FAIL coexist: only %0d tick periods observed", checked_ticks);
            failures = failures + 1;
        end
        if (checked_halves < (REQUESTS * 19) - REQUESTS) begin
            $display("FAIL coexist: only %0d SCLK half periods observed", checked_halves);
            failures = failures + 1;
        end
        if (adc_ok != REQUESTS || adc_done != REQUESTS) begin
            $display("FAIL coexist: %0d of %0d frames returned the requested code",
                     adc_ok, REQUESTS);
            failures = failures + 1;
        end
        if (failures != 0) $fatal(1, "tb_mcp3208_i2s_coexist failures=%0d", failures);
        $display("tb_mcp3208_i2s_coexist PASS: %0d frames, %0d ticks, %0d SCLK half periods",
                 adc_ok, checked_ticks, checked_halves);
        $finish;
    end

    initial begin
        #200_000_000;
        $fatal(1, "FAIL tb_mcp3208_i2s_coexist: timeout");
    end
endmodule