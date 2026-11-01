`timescale 1ns/1ps
module tb_event_fifo;
    reg clk = 0, rst = 1, wr_en = 0, rd_en = 0;
    reg [15:0] wr_data = 0;
    wire [15:0] rd_data;
    wire empty, full, wr_ready;
    integer i;
    event_fifo dut (.clk(clk), .rst(rst), .wr_en(wr_en), .wr_data(wr_data),
                    .rd_en(rd_en), .rd_data(rd_data), .empty(empty),
                    .full(full), .wr_ready(wr_ready));
    always #5 clk = ~clk;

    initial begin
        @(negedge clk); rst = 0;
        for (i = 0; i < 16; i = i + 1) begin
            wr_en = 1; wr_data = i;
            if (!wr_ready) $fatal(1, "FIFO ready dropped before full");
            @(negedge clk);
        end
        if (!full || empty || wr_ready) $fatal(1, "FIFO did not reach full state");
        wr_data = 16'hDEAD;
        @(negedge clk);
        if (rd_data !== 16'd0) $fatal(1, "Full FIFO overwrote first item");
        rd_en = 1; wr_data = 16'd16;
        #1; // allow combinational wr_ready to reflect the new rd_en
        if (!wr_ready) $fatal(1, "Full FIFO rejected simultaneous read/write");
        @(negedge clk);
        wr_en = 0;
        if (!full || rd_data !== 16'd1) $fatal(1, "Simultaneous transfer lost order");
        for (i = 1; i <= 16; i = i + 1) begin
            if (empty || rd_data !== i[15:0])
                $fatal(1, "FIFO sequence mismatch at %0d got %0d", i, rd_data);
            @(negedge clk);
        end
        rd_en = 0;
        if (!empty || full) $fatal(1, "FIFO did not drain");
        wr_en = 1; wr_data = 16'h1234;
        @(negedge clk); wr_en = 0; rst = 1;
        @(negedge clk); rst = 0;
        if (!empty || full) $fatal(1, "FIFO reset kept stale event");
        $display("PASS tb_event_fifo: full, simultaneous read/write, order and clear");
        $finish;
    end
endmodule
