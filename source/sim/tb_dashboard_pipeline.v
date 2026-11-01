`timescale 1ns/1ps
module tb_dashboard_pipeline;
    reg clk=0,rst=1,de=0;
    reg [10:0] x=0;
    reg [9:0] y=0;
    reg [63:0] st=64'h00fc0000643d3000;
    reg [255:0] wave=256'h1234567012345670123456701234567012345670123456701234567012345670;
    wire [23:0] actual,reference;
    reg [23:0] delayed;
    integer n, warm=0;
    always #5 clk=~clk;
    dashboard_renderer dut(.pix_clk(clk),.rst(rst),.de(de),.x(x),.y(y),.st(st),
        .waveform(wave),.spectrum(64'h8070605040302010),.lissajous(64'h0123456789abcdef),
        .rgb_r(actual[23:16]),.rgb_g(actual[15:8]),.rgb_b(actual[7:0]));
    baseline_dashboard_renderer ref_dut(.pix_clk(clk),.rst(rst),.de(de),.x(x),.y(y),.st(st),
        .waveform(wave),.spectrum(64'h8070605040302010),.lissajous(64'h0123456789abcdef),
        .rgb_r(reference[23:16]),.rgb_g(reference[15:8]),.rgb_b(reference[7:0]));
    always @(posedge clk) begin
        delayed <= reference;
        if(rst) warm=0; else warm=warm+1;
        #1;
        if(warm>8 && actual!==delayed) $fatal(1,"pipeline pixel mismatch n=%0d got=%h expected=%h",n,actual,delayed);
    end
    initial begin
        repeat(4) @(negedge clk); rst=0;
        // Consecutive pixels with changing text rows, geometry, status and DE.
        for(n=0;n<20000;n=n+1) begin
            @(negedge clk);
            x=(n*37)%1280; y=(n*17)%720; de=(n%13)!=0;
            if(n%101==0) st[43]=~st[43];
        end
        $display("PASS tb_dashboard_pipeline: 20000 pixels match baseline with exactly one added cycle");
        $finish;
    end
endmodule
