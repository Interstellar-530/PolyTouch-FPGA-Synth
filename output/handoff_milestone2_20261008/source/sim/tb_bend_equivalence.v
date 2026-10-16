`timescale 1ns/1ps
module tb_bend_equivalence;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,tick=0;reg[11:0]adc=0,pressure=0;reg[31:0]inc=0;
    wire[11:0]p0,p1,p2,p3,l0,l1,l2,l3;
    wire signed[15:0]b0,b1,b2,b3;
    wire[16:0]r0,r1,r2,r3;wire[31:0]i0,i1,i2,i3;
    pressure_bend a(clk,rst,tick,pressure,adc,1'b1,inc,p0,l0,b0,r0,i0);
    baseline_pressure_bend b(clk,rst,tick,pressure,adc,1'b1,inc,p1,l1,b1,r1,i1);
    pressure_bend #(.ADC_CENTER(1730)) c(clk,rst,tick,pressure,adc,1'b1,inc,p2,l2,b2,r2,i2);
    baseline_pressure_bend #(.ADC_CENTER(1730)) d(clk,rst,tick,pressure,adc,1'b1,inc,p3,l3,b3,r3,i3);
    integer n;
    initial begin
        repeat(4)@(negedge clk);rst=0;
        for(n=0;n<4096;n=n+1)begin
            adc=n;pressure=$random;inc=$random;tick=1;@(negedge clk);tick=0;@(negedge clk);
            if({p0,l0,b0,r0,i0}!=={p1,l1,b1,r1,i1} || {p2,l2,b2,r2,i2}!=={p3,l3,b3,r3,i3})$fatal(1,"bend equivalence ADC=%d",n);
        end
        $display("PASS tb_bend_equivalence: all 4096 ADC codes, default and calibrated center, full 32-bit increments, pressure state exact");$finish;
    end
endmodule
