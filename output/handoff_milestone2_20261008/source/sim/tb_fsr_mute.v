`timescale 1ns/1ps
module tb_fsr_mute;
    reg clk=0,rst=1,enable=1,update=0;
    reg [11:0] pressure=0;
    wire muted;
    always #5 clk=~clk;
    fsr_mute dut(clk,rst,enable,update,pressure,muted);
    integer n,checks=0;
    task tick(input integer code,input integer expected);
        begin
            @(negedge clk);pressure=code;update=1;
            @(negedge clk);update=0;
            if(muted!==expected[0])$fatal(1,"FSR code=%0d muted=%b expected=%0d",code,muted,expected);
            checks=checks+1;
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=0;
        for(n=0;n<512;n=n+1)tick(n,0);
        tick(512,1);
        for(n=511;n>256;n=n-1)tick(n,1);
        tick(256,0);
        for(n=257;n<512;n=n+1)tick(n,0);
        tick(4095,1);tick(300,1);tick(500,1);tick(0,0);
        pressure=4095;repeat(5)@(negedge clk);
        if(muted!==0)$fatal(1,"FSR changed without a fresh update");
        tick(4095,1);enable=0;@(negedge clk);
        if(muted!==0)$fatal(1,"FSR bypass did not unmute");
        tick(4095,0);enable=1;tick(4095,1);rst=1;@(negedge clk);
        if(muted!==0)$fatal(1,"FSR reset did not unmute");
        $display("PASS tb_fsr_mute: %0d threshold/hysteresis checks, update, bypass and reset",checks);
        $finish;
    end
    initial begin #100000;$fatal(1,"FSR mute timeout");end
endmodule
