`timescale 1ns/1ps
// Deterministic MCP3208 pin-level model and master self-check.
module tb_mcp3208_spi;
    reg clk = 1'b0;
    always #5 clk = ~clk; // 100 MHz in this focused test; divider is overridden
    reg rst = 1'b1;
    reg start = 1'b0;
    reg [2:0] channel = 3'd0;
    wire miso;
    wire cs_n, sclk, mosi, busy, done;
    wire [11:0] data;
    wire data_valid;
    wire [11:0] adc_data;

    mcp3208_spi #(.CLK_HZ(100_000_000), .SPI_HZ(1_000_000)) dut (
        .clk(clk), .rst(rst), .start(start), .channel(channel), .miso(miso),
        .cs_n(cs_n), .sclk(sclk), .mosi(mosi), .busy(busy), .done(done),
        .data(data), .data_valid(data_valid), .adc_data(adc_data)
    );

    reg [11:0] model_ch0, model_ch1, model_ch2, model_ch3;
    reg [11:0] model_ch4, model_ch5, model_ch6, model_ch7;
    integer failures;
    integer i;

    // MCP3208 changes MISO on falling edges; the reusable model selects the
    // value by the command's channel field and keeps all unused channels zero.
    mcp3208_model model (
        .cs_n(cs_n), .sclk(sclk), .mosi(mosi), .miso(miso),
        .ch0(model_ch0), .ch1(model_ch1), .ch2(model_ch2),
        .ch3(model_ch3), .ch4(model_ch4), .ch5(model_ch5),
        .ch6(model_ch6), .ch7(model_ch7)
    );

    task run_case;
        input [2:0] ch;
        input [11:0] expected;
        begin
            @(negedge clk);
            channel <= ch;
            model_ch0 <= 12'd0; model_ch1 <= 12'd0;
            model_ch2 <= 12'd0; model_ch3 <= 12'd0;
            model_ch4 <= 12'd0; model_ch5 <= 12'd0;
            model_ch6 <= 12'd0; model_ch7 <= 12'd0;
            case (ch)
                3'd0: model_ch0 <= expected;
                3'd1: model_ch1 <= expected;
                3'd2: model_ch2 <= expected;
                3'd3: model_ch3 <= expected;
                3'd4: model_ch4 <= expected;
                3'd5: model_ch5 <= expected;
                3'd6: model_ch6 <= expected;
                default: model_ch7 <= expected;
            endcase
            start <= 1'b1;
            @(negedge clk);
            start <= 1'b0;
            wait(done);
            #1;
            if (!data_valid || data !== expected || adc_data !== expected) begin
                $display("FAIL ch=%0d expected=%0d got=%0d", ch, expected, data);
                failures = failures + 1;
            end
            @(posedge clk);
        end
    endtask

    initial begin
        failures = 0;
        // Keep a reviewable pin-level trace for GTKWave or offline rendering.
        $dumpfile("sim/tb_mcp3208_spi.vcd");
        $dumpvars(0, tb_mcp3208_spi);
        repeat (4) @(posedge clk);
        rst = 1'b0;
        run_case(3'd0, 12'd0);
        run_case(3'd1, 12'd1);
        run_case(3'd2, 12'd2047);
        run_case(3'd3, 12'd2048);
        run_case(3'd4, 12'd4095);

        // Abort a transaction with reset; CS must recover high and a later
        // request must still complete with a fresh result.
        @(negedge clk); channel <= 3'd5;
        model_ch0 <= 12'd0; model_ch1 <= 12'd0; model_ch2 <= 12'd0; model_ch3 <= 12'd0;
        model_ch4 <= 12'd0; model_ch5 <= 12'h555; model_ch6 <= 12'd0; model_ch7 <= 12'd0;
        start <= 1'b1;
        @(negedge clk); start <= 1'b0;
        repeat (7) @(posedge clk);
        rst <= 1'b1;
        repeat (2) @(posedge clk);
        rst <= 1'b0;
        #1;
        if (cs_n !== 1'b1 || busy !== 1'b0 || sclk !== 1'b0) begin
            $display("FAIL reset recovery cs=%b busy=%b sclk=%b", cs_n, busy, sclk);
            failures = failures + 1;
        end
        run_case(3'd6, 12'hA5A);

        if (failures != 0) $fatal(1, "tb_mcp3208_spi failures=%0d", failures);
        $display("tb_mcp3208_spi PASS");
        $finish;
    end
endmodule
