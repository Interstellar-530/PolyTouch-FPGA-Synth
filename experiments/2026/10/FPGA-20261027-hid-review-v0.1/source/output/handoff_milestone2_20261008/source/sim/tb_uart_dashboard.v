`timescale 1ns/1ps
// Protocol gate for the computer dashboard route and Q snapshot. The bench
// decodes the actual UART TX stream so a truncated snapshot cannot pass.
module tb_uart_dashboard;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg rx = 1'b1;
    reg [63:0] status = 64'h0123456789ABCDEF;
    reg [255:0] waveform = 256'h00112233445566778899AABBCCDDEEFF00112233445566778899AABBCCDDEEFF;
    reg [63:0] spectrum = 64'h1020304050607080;
    reg [63:0] lissajous = 64'h89ABCDEF01234567;
    wire tx;
    wire route;
    uart_ctrl #(.CLK_HZ(1_000_000), .BAUD(100_000)) dut (
        .clk(clk), .rst(rst), .uart_rx(rx), .uart_tx(tx),
        .ui_status(status), .ui_waveform(waveform),
        .ui_spectrum(spectrum), .ui_lissajous(lissajous),
        .display_route(route)
    );

    task byte_tx;
        input [7:0] value;
        integer bitno;
        begin
            @(negedge clk); rx = 1'b0; repeat (10) @(negedge clk);
            for (bitno = 0; bitno < 8; bitno = bitno + 1) begin
                rx = value[bitno]; repeat (10) @(negedge clk);
            end
            rx = 1'b1; repeat (10) @(negedge clk);
        end
    endtask

    task byte_rx;
        output [7:0] value;
        integer bitno;
        begin
            @(negedge tx);
            repeat (5) @(negedge clk); // start-bit centre
            for (bitno = 0; bitno < 8; bitno = bitno + 1) begin
                repeat (10) @(negedge clk);
                value[bitno] = tx;
            end
            repeat (10) @(negedge clk); // stop bit
        end
    endtask

    task expect_ok;
        reg [7:0] b;
        begin
            byte_rx(b); if (b !== "O") $fatal(1, "expected O, got %h", b);
            byte_rx(b); if (b !== "K") $fatal(1, "expected K, got %h", b);
            byte_rx(b); if (b !== 8'h0D) $fatal(1, "expected CR, got %h", b);
            byte_rx(b); if (b !== 8'h0A) $fatal(1, "expected LF, got %h", b);
        end
    endtask

    integer i;
    reg [7:0] line [0:115];
    initial begin
        repeat (5) @(negedge clk); rst = 1'b0;
        byte_tx("R"); byte_tx("0"); byte_tx(8'h0D); expect_ok();
        if (route !== 1'b0) $fatal(1, "R0 did not select computer route");
        byte_tx("R"); byte_tx("1"); byte_tx(8'h0D); expect_ok();
        if (route !== 1'b1) $fatal(1, "R1 did not select HDMI route");
        byte_tx("Q"); byte_tx(8'h0D);
        for (i = 0; i < 116; i = i + 1) byte_rx(line[i]);
        if (line[0] !== "@" || line[1] !== "S") $fatal(1, "Q header mismatch");
        if (line[2] !== "0" || line[17] !== "F") $fatal(1, "Q status hex mismatch");
        if (line[114] !== 8'h0D || line[115] !== 8'h0A) $fatal(1, "Q terminator mismatch");
        $display("PASS tb_uart_dashboard: R0/R1 route and 116-byte Q snapshot");
        $finish;
    end
    initial begin #2_000_000; $fatal(1, "tb_uart_dashboard timeout"); end
endmodule
