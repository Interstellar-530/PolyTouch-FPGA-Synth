`timescale 1ns/1ps
module tb_timbre_controls;
    reg clk=0; always #5000 clk=~clk; // 100 kHz, actual 1 ms timebase
    reg por=1,rst=1,k1=1,k2=1,tv=0;
    reg [7:0] value=0;
    wire short1,press2,show;
    wire [7:0] target; wire [1:0] preset;
    integer shorts=0,seconds=0;
    instrument_controls #(.CLK_HZ(100000)) dut(clk,por,rst,k1,k2,tv,value,short1,press2,target,show,preset);
    always @(negedge clk) begin if(short1) shorts=shorts+1; if(press2) seconds=seconds+1; end
    task ms; input integer n; begin repeat(n*100) @(negedge clk); end endtask
    task long_press; input [7:0] expected;
        begin k1=0; ms(650); if(target!==expected) $fatal(1,"long target %d expected %d",target,expected);
            k1=1; ms(25); if(shorts!=1) $fatal(1,"long triggered short"); end
    endtask
    initial begin
        ms(2); por=0; rst=0; ms(2);
        if(target!=64 || preset!=1) $fatal(1,"boot preset");
        k1=0; ms(10); k1=1; ms(25);
        if(shorts!=0 || target!=64) $fatal(1,"bounce triggered");
        k1=0; ms(40); if(shorts!=0) $fatal(1,"short fired before release");
        k1=1; ms(25); if(shorts!=1) $fatal(1,"short missing/repeated");
        k1=0; ms(650); if(target!=160 || shorts!=1) $fatal(1,"long missing");
        ms(800); if(target!=160) $fatal(1,"long auto repeated");
        k1=1; ms(25); if(shorts!=1) $fatal(1,"long release fired short");
        long_press(255); long_press(0); long_press(64);
        k2=0; ms(700); if(seconds!=1) $fatal(1,"S2 repeated"); k2=1; ms(25);
        value=210; tv=1; @(negedge clk); tv=0; ms(1);
        if(target!=210 || preset!=3 || !show) $fatal(1,"UART/nearest preset");
        rst=1; ms(2); rst=0; ms(2); if(target!=210) $fatal(1,"S3 lost preset");
        long_press(0);
        // Same-cycle UART wins over a board long press.
        k1=0; @(negedge clk); while(!dut.long1) @(negedge clk); value=255; tv=1;
        @(negedge clk); tv=0; if(target!=255 || preset!=3) $fatal(1,"UART priority");
        k1=1; ms(25); if(shorts!=1) $fatal(1,"priority release fired short");
        ms(1000); if(show) $fatal(1,"LED overlay stuck");
        $display("PASS tb_timbre_controls: bounce, release-only short, long no-repeat, four presets, S2, UART priority, S3 retention, LED timeout");
        $finish;
    end
    initial begin #15000000000; $fatal(1,"timeout"); end
endmodule
