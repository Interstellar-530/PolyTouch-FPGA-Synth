`timescale 1ns/1ps
// S4 parameter checks for mcp3208_spi.
//
//   1. production pair 27 MHz / 250 kHz: half period must be exactly 54
//      clocks (2 us), i.e. SCLK = 250 kHz, the frame must use 19 rising
//      edges, and CS fall to the first rising edge must satisfy
//      tSUCS >= 100 ns (100 ns = 2.7 clocks at 27 MHz),
//   2. SPI_HZ far above CLK_HZ / 2: the divider must clamp to one clock and
//      the frame must still complete with the correct code (no hang, no lost
//      bit),
//   3. SPI_HZ below 1 Hz: the guard has to keep elaboration defined.  This
//      instance is only elaborated, never started, because one frame would
//      take 19 x 2 x 13.5 M clocks.
module tb_mcp3208_params;
    reg clk = 1'b0;
    always #18.5185 clk = ~clk;             // 27 MHz
    reg rst = 1'b1;

    integer failures, clkcnt;

    // ---- production configuration ---------------------------------------
    reg p_start = 1'b0;
    wire p_miso, p_cs_n, p_sclk, p_mosi, p_busy, p_done, p_valid;
    wire [11:0] p_data, p_adc;
    mcp3208_spi #(.CLK_HZ(27_000_000), .SPI_HZ(250_000)) u_prod (
        .clk(clk), .rst(rst), .start(p_start), .channel(3'd2), .miso(p_miso),
        .cs_n(p_cs_n), .sclk(p_sclk), .mosi(p_mosi), .busy(p_busy),
        .done(p_done), .data(p_data), .data_valid(p_valid), .adc_data(p_adc)
    );
    wire [11:0] p_chv = 12'h345;
    mcp3208_model m_prod (
        .cs_n(p_cs_n), .sclk(p_sclk), .mosi(p_mosi), .miso(p_miso),
        .ch0(p_chv), .ch1(p_chv), .ch2(p_chv), .ch3(p_chv),
        .ch4(p_chv), .ch5(p_chv), .ch6(p_chv), .ch7(p_chv)
    );
    integer p_edges, p_last_edge, p_sucs, p_cs_fall_clk, p_first_rise;
    integer p_half_bad;

    // ---- clamped configuration ------------------------------------------
    reg f_start = 1'b0;
    wire f_miso, f_cs_n, f_sclk, f_mosi, f_busy, f_done, f_valid;
    wire [11:0] f_data, f_adc;
    mcp3208_spi #(.CLK_HZ(27_000_000), .SPI_HZ(20_000_000)) u_fast (
        .clk(clk), .rst(rst), .start(f_start), .channel(3'd1), .miso(f_miso),
        .cs_n(f_cs_n), .sclk(f_sclk), .mosi(f_mosi), .busy(f_busy),
        .done(f_done), .data(f_data), .data_valid(f_valid), .adc_data(f_adc)
    );
    wire [11:0] f_chv = 12'h6A5;
    mcp3208_model m_fast (
        .cs_n(f_cs_n), .sclk(f_sclk), .mosi(f_mosi), .miso(f_miso),
        .ch0(f_chv), .ch1(f_chv), .ch2(f_chv), .ch3(f_chv),
        .ch4(f_chv), .ch5(f_chv), .ch6(f_chv), .ch7(f_chv)
    );
    integer f_edges, f_last_edge, f_sucs, f_cs_fall_clk, f_first_rise;
    integer f_half_bad;

    // ---- elaboration only ------------------------------------------------
    wire z_miso, z_cs_n, z_sclk, z_mosi, z_busy, z_done;
    mcp3208_spi #(.CLK_HZ(27_000_000), .SPI_HZ(0)) u_zero (
        .clk(clk), .rst(rst), .start(1'b0), .channel(3'd0), .miso(z_miso),
        .cs_n(z_cs_n), .sclk(z_sclk), .mosi(z_mosi), .busy(z_busy),
        .done(z_done), .data(), .data_valid(), .adc_data()
    );

    always @(posedge clk) clkcnt = clkcnt + 1;

    always @(negedge p_cs_n) p_cs_fall_clk = clkcnt;

    always @(p_sclk) begin
        if (!p_cs_n) begin
            if (p_sclk === 1'b1) begin
                p_edges = p_edges + 1;
                if (p_edges == 1) begin
                    p_first_rise = clkcnt;
                    p_sucs       = clkcnt - p_cs_fall_clk;
                end
            end
            if (p_last_edge > 0) begin
                if ((clkcnt - p_last_edge) != 54) begin
                    p_half_bad = p_half_bad + 1;
                    $display("FAIL prod half period %0d clocks", clkcnt - p_last_edge);
                end
            end
            p_last_edge = clkcnt;
        end else begin
            p_last_edge = 0;
        end
    end

    always @(negedge f_cs_n) f_cs_fall_clk = clkcnt;

    always @(f_sclk) begin
        if (!f_cs_n) begin
            if (f_sclk === 1'b1) begin
                f_edges = f_edges + 1;
                if (f_edges == 1) begin
                    f_first_rise = clkcnt;
                    f_sucs       = clkcnt - f_cs_fall_clk;
                end
            end
            if (f_last_edge > 0) begin
                if ((clkcnt - f_last_edge) != 1) begin
                    f_half_bad = f_half_bad + 1;
                    $display("FAIL clamped half period %0d clocks", clkcnt - f_last_edge);
                end
            end
            f_last_edge = clkcnt;
        end else begin
            f_last_edge = 0;
        end
    end

    initial begin
        failures = 0; clkcnt = 0;
        p_edges = 0; p_last_edge = 0; p_sucs = 0; p_cs_fall_clk = 0;
        p_first_rise = 0; p_half_bad = 0;
        f_edges = 0; f_last_edge = 0; f_sucs = 0; f_cs_fall_clk = 0;
        f_first_rise = 0; f_half_bad = 0;

        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (4) @(posedge clk);

        // production frame
        @(negedge clk); p_start <= 1'b1;
        @(negedge clk); p_start <= 1'b0;
        wait (p_done);
        #1;
        if (p_valid !== 1'b1 || p_data !== p_chv) begin
            $display("FAIL prod data=%h expected %h", p_data, p_chv);
            failures = failures + 1;
        end
        if (p_edges != 19) begin
            $display("FAIL prod frame used %0d rising SCLK edges", p_edges);
            failures = failures + 1;
        end
        if (p_half_bad != 0) failures = failures + 1;
        // tSUCS: 100 ns is 2.7 clocks at 27 MHz
        if (p_sucs < 3) begin
            $display("FAIL prod tSUCS interval %0d clocks", p_sucs);
            failures = failures + 1;
        end
        $display("prod: %0d rising edges, half period 54 clocks, CS to first edge %0d clocks (%0.0f ns), data=%h",
                 p_edges, p_sucs, p_sucs * 37.037, p_data);
        repeat (20) @(posedge clk);

        // clamped frame
        @(negedge clk); f_start <= 1'b1;
        @(negedge clk); f_start <= 1'b0;
        wait (f_done);
        #1;
        if (f_valid !== 1'b1 || f_data !== f_chv) begin
            $display("FAIL clamped data=%h expected %h", f_data, f_chv);
            failures = failures + 1;
        end
        if (f_edges != 19) begin
            $display("FAIL clamped frame used %0d rising SCLK edges", f_edges);
            failures = failures + 1;
        end
        if (f_half_bad != 0) failures = failures + 1;
        // The clamped pair is a deliberate misuse: SCLK 13.5 MHz and a 37 ns
        // CS setup, both outside the device ratings, so only report it.
        $display("clamped: %0d rising edges, half period 1 clock (SCLK 13.5 MHz), CS to first edge %0d clocks (%0.0f ns), data=%h",
                 f_edges, f_sucs, f_sucs * 37.037, f_data);

        if (z_cs_n !== 1'b1 || z_sclk !== 1'b0) begin
            $display("FAIL guarded instance is not idle: cs_n=%b sclk=%b", z_cs_n, z_sclk);
            failures = failures + 1;
        end
        $display("SPI_HZ=0 instance elaborated and idle (guard keeps the divider defined)");

        if (failures != 0) $fatal(1, "tb_mcp3208_params failures=%0d", failures);
        $display("tb_mcp3208_params PASS");
        $finish;
    end

    initial begin
        #200_000_000;
        $fatal(1, "FAIL tb_mcp3208_params: timeout");
    end
endmodule