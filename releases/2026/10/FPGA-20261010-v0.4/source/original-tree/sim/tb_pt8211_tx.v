`timescale 1ns/1ps
module tb_pt8211_tx;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg signed [15:0] sample_in = 16'sd0;
    wire bck;
    wire ws;
    wire din;
    wire sample_tick;

    always #18.5185 clk = ~clk;

    pt8211_tx dut (
        .clk         (clk),
        .rst         (rst),
        .sample_in   (sample_in),
        .bck         (bck),
        .ws          (ws),
        .din         (din),
        .sample_tick (sample_tick)
    );

    initial begin
        $dumpfile("tb_pt8211_tx.vcd");
        $dumpvars(0, tb_pt8211_tx);
        #1000;
        rst = 1'b0;
        sample_in = 16'sh4000;
        #200000;
        sample_in = 16'shC000;
        #200000;
        $finish;
    end
endmodule
