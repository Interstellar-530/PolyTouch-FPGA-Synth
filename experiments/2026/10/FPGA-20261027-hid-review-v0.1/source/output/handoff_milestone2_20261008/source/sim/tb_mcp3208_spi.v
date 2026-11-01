`timescale 1ns/1ps
// S4 MCP3208 master self-check, independent review revision (2026-10-15).
//
// The device side is mcp3208_model.v, which follows the Microchip DS21298E
// frame (19 clocks: null bit on clock 7, B11..B0 on clocks 8..19).  Using a
// model that encodes the real device timing instead of mirroring the master
// is what makes a bit placement error visible: an 18-clock master reads the
// null bit as B11 and returns every code shifted right by one bit.
//
// The audit block watches the pins and fails the run when a frame is not 19
// SCLK pulses, when the DIN command does not match the requested channel,
// when busy/CS/SCLK are wrong during the frame, or when a code is committed
// while CS is still low.
module tb_mcp3208_spi;
    reg clk = 1'b0;
    always #5 clk = ~clk;                    // 100 MHz core clock in this test
    reg rst = 1'b1;
    reg start = 1'b0;
    reg [2:0] channel = 3'd0;

    wire miso;
    wire cs_n, sclk, mosi, busy, done, data_valid;
    wire [11:0] data, adc_data;

    mcp3208_spi #(.CLK_HZ(100_000_000), .SPI_HZ(1_000_000)) dut (
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

    integer failures;
    integer i;
    integer k;
    integer n;
    reg [31:0] rnd;
    reg [2:0] chidx;

    // ---- wire level audit ------------------------------------------------
    integer rcount;         // SCLK rising edges in the current frame
    integer adc_clk;        // device clock index, 1 = start bit, 0 = none yet
    reg     seen_start;
    reg [2:0] audit_ch;
    reg     txn_ignore;     // set while a deliberately truncated frame runs
    integer snap_rcount;
    integer snap_adc_clk;
    reg [2:0] snap_ch;
    integer commits;
    reg [11:0] held_data;

    always @(posedge sclk) begin
        if (!cs_n) begin
            rcount = rcount + 1;
            if (busy !== 1'b1) begin
                $display("FAIL audit: busy low on SCLK edge %0d", rcount);
                failures = failures + 1;
            end
            if (!seen_start) begin
                if (mosi === 1'b1) begin
                    seen_start = 1'b1;
                    adc_clk    = 1;
                    if (rcount != 1) begin
                        $display("FAIL audit: %0d leading zero clocks before START", rcount - 1);
                        failures = failures + 1;
                    end
                end
            end else begin
                adc_clk = adc_clk + 1;
                case (adc_clk)
                    2: if (mosi !== 1'b1) begin
                           $display("FAIL audit: SGL/DIFF is not single ended");
                           failures = failures + 1;
                       end
                    3: audit_ch[2] = mosi;
                    4: audit_ch[1] = mosi;
                    5: audit_ch[0] = mosi;
                    default: ;
                endcase
            end
        end
    end

    always @(posedge clk) begin
        if (data_valid === 1'b1) commits = commits + 1;
        if (!cs_n) begin
            if (data_valid === 1'b1) begin
                $display("FAIL audit: data_valid pulsed while CS is low");
                failures = failures + 1;
            end
            if (data !== held_data) begin
                $display("FAIL audit: code committed before CS returned high: data=%h held=%h",
                         data, held_data);
                failures = failures + 1;
            end
        end else begin
            held_data = data;
        end
    end

    always @(posedge cs_n) begin
        if (rcount != 0) begin
            if (txn_ignore) begin
                txn_ignore = 1'b0;
            end else begin
                snap_rcount  = rcount;
                snap_adc_clk = adc_clk;
                snap_ch      = audit_ch;
            end
        end
        rcount     = 0;
        adc_clk    = 0;
        seen_start = 1'b0;
        commits    = 0;
    end

    function [31:0] xorshift;
        input [31:0] x;
        begin
            x = x ^ (x << 13);
            x = x ^ (x >> 17);
            x = x ^ (x << 5);
            xorshift = x;
        end
    endfunction

    task set_channels;
        begin
            // Distinct non zero codes: a wrong channel decode cannot pass.
            chv[0] = 12'h123; chv[1] = 12'h456;
            chv[2] = 12'h789; chv[3] = 12'hABC;
            chv[4] = 12'hDEF; chv[5] = 12'h0F0;
            chv[6] = 12'h555; chv[7] = 12'hAAA;
        end
    endtask

    task run_case;
        input [2:0] ch;
        input [11:0] value;
        begin
            chv[ch] = value;
            @(negedge clk); channel <= ch; start <= 1'b1;
            @(negedge clk); start <= 1'b0;
            wait (done);
            #1;
            if (data_valid !== 1'b1 || data !== value || adc_data !== value) begin
                $display("FAIL ch=%0d value=%0d: data=%0d adc_data=%0d valid=%b",
                         ch, value, data, adc_data, data_valid);
                failures = failures + 1;
            end
            @(posedge clk); #1;
            if (commits != 1) begin
                $display("FAIL ch=%0d value=%0d: %0d commit pulses in one frame", ch, value, commits);
                failures = failures + 1;
            end
            if (snap_rcount != 19 || snap_adc_clk != 19) begin
                $display("FAIL ch=%0d value=%0d: frame used %0d SCLK edges / %0d device clocks, expected 19",
                         ch, value, snap_rcount, snap_adc_clk);
                failures = failures + 1;
            end
            if (snap_ch !== ch) begin
                $display("FAIL ch=%0d value=%0d: device decoded channel %0d", ch, value, snap_ch);
                failures = failures + 1;
            end
            if (busy !== 1'b0 || cs_n !== 1'b1) begin
                $display("FAIL ch=%0d value=%0d: busy=%b cs_n=%b after done", ch, value, busy, cs_n);
                failures = failures + 1;
            end
            @(negedge clk);
        end
    endtask

    task start_while_busy;
        begin
            chv[3] = 12'h321;
            chv[6] = 12'h654;
            @(negedge clk); channel <= 3'd3; start <= 1'b1;
            @(negedge clk); start <= 1'b0;
            repeat (6) @(posedge sclk);
            @(negedge clk); channel <= 3'd6; start <= 1'b1;
            @(negedge clk); start <= 1'b0;
            wait (done);
            #1;
            if (data !== 12'h321) begin
                $display("FAIL start-while-busy: data=%0d, expected %0d from the latched channel",
                         data, 12'h321);
                failures = failures + 1;
            end
            @(posedge clk); #1;
            if (snap_ch !== 3'd3 || snap_rcount != 19) begin
                $display("FAIL start-while-busy: decoded channel %0d, %0d SCLK edges",
                         snap_ch, snap_rcount);
                failures = failures + 1;
            end
            @(negedge clk);
            // The ignored request is not queued; a fresh request is needed.
            run_case(3'd6, 12'h654);
        end
    endtask

    task abort_with_reset;
        input integer nclk;
        begin
            txn_ignore = 1'b1;
            @(negedge clk); channel <= 3'd5; start <= 1'b1;
            @(negedge clk); start <= 1'b0;
            for (k = 0; k < nclk; k = k + 1) @(posedge sclk);
            @(negedge clk); rst <= 1'b1;
            repeat (2) @(posedge clk);
            rst <= 1'b0;
            @(posedge clk); #1;
            if (cs_n !== 1'b1 || busy !== 1'b0 || sclk !== 1'b0 || done !== 1'b0) begin
                $display("FAIL reset after %0d clocks: cs_n=%b busy=%b sclk=%b done=%b",
                         nclk, cs_n, busy, sclk, done);
                failures = failures + 1;
            end
            if (commits != 0) begin
                $display("FAIL reset after %0d clocks: %0d commits in the truncated frame", nclk, commits);
                failures = failures + 1;
            end
            txn_ignore = 1'b0;
            @(negedge clk);
        end
    endtask

    initial begin
        failures = 0; rcount = 0; adc_clk = 0; seen_start = 1'b0; audit_ch = 3'd0;
        commits = 0; held_data = 12'd0; snap_rcount = 0; snap_adc_clk = 0; snap_ch = 3'd0;
        txn_ignore = 1'b0; rnd = 32'h1234_5678;

        // Waveform capture is opt in: run `vvp tb.vvp +dump` to write
        // sim/tb_mcp3208_spi.vcd.  The gate stays free of multi-megabyte dumps.
        if ($test$plusargs("dump")) begin
            $dumpfile("sim/tb_mcp3208_spi.vcd");
            $dumpvars(0, tb_mcp3208_spi);
        end

        set_channels;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        // 1) boundary codes on CH0 and CH1 while every other channel holds a
        //    different non zero code
        run_case(3'd0, 12'd0);
        run_case(3'd1, 12'd0);
        run_case(3'd0, 12'd1);
        run_case(3'd1, 12'd1);
        run_case(3'd0, 12'd2047);
        run_case(3'd1, 12'd2047);
        run_case(3'd0, 12'd2048);
        run_case(3'd1, 12'd2048);
        run_case(3'd0, 12'd4095);
        run_case(3'd1, 12'd4095);

        // 2) two channel interleave, both codes live at the same time
        chv[0] = 12'd1374;
        chv[1] = 12'd2748;
        for (i = 0; i < 4; i = i + 1) begin
            run_case(3'd0, 12'd1374);
            run_case(3'd1, 12'd2748);
        end

        // 3) every remaining channel
        for (i = 2; i < 8; i = i + 1) begin
            chidx = i[2:0];
            run_case(chidx, 12'h100 + i[11:0]);
        end

        // 4) fixed seed pseudo random channel/code sweep (xorshift32)
        for (i = 0; i < 256; i = i + 1) begin
            rnd = xorshift(rnd);
            run_case(rnd[2:0], rnd[27:16]);
        end

        // 5) a request while a conversion is in flight is ignored
        start_while_busy;

        // 6) reset in the middle of a frame, at three different positions
        abort_with_reset(3);
        abort_with_reset(8);
        abort_with_reset(15);
        run_case(3'd5, chv[5]);

        if (failures != 0) $fatal(1, "tb_mcp3208_spi failures=%0d", failures);
        $display("tb_mcp3208_spi PASS");
        $finish;
    end

    initial begin
        #200_000_000;                        // watchdog: frames are ~19 us each
        $fatal(1, "FAIL tb_mcp3208_spi: timeout, no progress after 200 ms");
    end
endmodule