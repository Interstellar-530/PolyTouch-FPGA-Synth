`timescale 1ns/1ps
module tb_bend_precision;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,tick=0;reg[11:0]adc=2048;reg[31:0]inc=1;
    wire[16:0]ratio;wire[31:0]phase;wire signed[15:0]q8;
    pressure_bend dut(.clk(clk),.rst(rst),.control_tick(tick),.pressure_adc(12'd0),.bend_adc(adc),
        .pressure_enable(1'b1),.base_phase_inc(inc),.bend_q8(q8),.bend_ratio_q16(ratio),.phase_inc_out(phase));
    integer n,previous=0,worst_adc=0,fd=0;reg[2047:0]capture;
    reg[63:0]product_ref;reg[31:0]phase_ref;reg[16:0]held_ratio;
    real semitone,ideal,error_cents,abs_error,max_error=0;
    initial begin
        if($value$plusargs("CAPTURE=%s",capture))begin
            fd=$fopen(capture,"w");if(!fd)$fatal(1,"capture open");
            $fwrite(fd,"adc,ratio_q16,error_cents\n");
        end
        repeat(3)@(negedge clk);rst=0;
        for(n=0;n<4096;n=n+1)begin
            adc=n;inc=$random;held_ratio=ratio;
            @(negedge clk);if(ratio!==held_ratio)$fatal(1,"ratio changed without tick");
            tick=1;@(negedge clk);tick=0;
            semitone=2.0*(n-2048)/(n>=2048?2047.0:2048.0);
            ideal=2.0**(semitone/12.0);
            error_cents=1200.0*$ln((real'(ratio)/65536.0)/ideal)/$ln(2.0);
            abs_error=error_cents<0?-error_cents:error_cents;
            if(abs_error>max_error)begin max_error=abs_error;worst_adc=n;end
            if(abs_error>0.04 || ratio<previous)$fatal(1,"precision/monotonic failure adc=%d cents=%f",n,error_cents);
            previous=ratio;
            product_ref={32'd0,inc}*{47'd0,ratio};phase_ref=product_ref>>16;
            if(phase!==phase_ref)$fatal(1,"phase product mismatch");
            if((n==0 && ratio!=58386)||(n==2048 && ratio!=65536)||(n==4095 && ratio!=73562))$fatal(1,"bend endpoint");
            if(fd)$fwrite(fd,"%0d,%0d,%.12f\n",n,ratio,error_cents);
        end
        if(fd)$fclose(fd);
        $display("METRIC bend_precision adc_codes=4096 max_abs_cents=%.9f worst_adc=%0d segments=32",max_error,worst_adc);
        $display("PASS tb_bend_precision: analytic exponential, monotonic, endpoints, hold, random 32-bit phase products");$finish;
    end
endmodule
