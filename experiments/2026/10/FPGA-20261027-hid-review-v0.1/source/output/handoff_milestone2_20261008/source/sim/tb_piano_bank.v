`timescale 1ns/1ps
// 36 张 AKWF 电钢琴表与生成文件逐地址比对。
module tb_piano_bank;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg ce = 1'b0;
    reg [5:0] bank = 6'd0;
    reg [8:0] addr = 9'd0;
    wire [15:0] dout;
    reg [15:0] expected [0:6143];
    integer i, b;
    integer differences = 0;

    gowin_prom_piano_bank dut(
        .clk(clk), .ce(ce), .rst(rst), .bank(bank), .addr(addr), .dout(dout));

    task check_bank;
        input integer which;
        begin
            for (i = 0; i < 512; i = i + 1) begin
                @(negedge clk);
                bank = which[5:0];
                addr = i[8:0];
                @(posedge clk);
                #1;
                if (dout !== expected[which*512+i]) begin
                    differences = differences + 1;
                    if (differences < 8)
                        $display("FAIL epiano bank=%0d addr=%0d got=%h expected=%h",
                                 which, i, dout, expected[which*512+i]);
                end
            end
        end
    endtask

    initial begin
        $readmemh("rtl/audio/epiano_bank_all.hex", expected);
        repeat (4) @(posedge clk);
        rst = 1'b0;
        ce = 1'b1;
        for (b = 0; b < 12; b = b + 1) check_bank(b);
        if (differences != 0) $fatal(1, "tb_piano_bank differences=%0d", differences);
        $display("PASS tb_piano_bank: 12 AKWF e-piano tables (2 groups x 6 stages) x 512 addresses");
        $finish;
    end
    initial begin #2000000; $fatal(1, "tb_piano_bank timeout"); end
endmodule
