`timescale 1ns/1ps
module tb_shared_master;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,update=0,enable=1;reg[7:0]w=64;reg[11:0]pressure=0;
    reg signed[18:0]a=0,b=0;
    wire signed[15:0]y0,y1;wire[31:0]c0,c1;wire e0,e1,req;
    wire signed[17:0]ma,mb;reg signed[35:0]product=0;
    always @(posedge clk)if(req)product<=ma*mb;
    global_crossfade #(.PRESSURE_GAIN_ENABLE(1),.TIMBRE_SLEW_ENABLE(1)) direct(
        .clk(clk),.rst(rst),.update(update),.clear_clip(1'b0),.mix_weight(w),.sine_sum(a),.bright_sum(b),
        .sample_out(y0),.clip_count(c0),.clip_event(e0),.pressure_enable(enable),.pressure_level(pressure));
    global_crossfade #(.PRESSURE_GAIN_ENABLE(1),.TIMBRE_SLEW_ENABLE(1),.SHARED_MULT_ENABLE(1)) shared(
        .clk(clk),.rst(rst),.update(update),.clear_clip(1'b0),.mix_weight(w),.sine_sum(a),.bright_sum(b),
        .sample_out(y1),.clip_count(c1),.clip_event(e1),.pressure_enable(enable),.pressure_level(pressure),
        .mult_request(req),.mult_operand_a(ma),.mult_operand_b(mb),.mult_result(product));
    integer n,requests;reg signed[15:0]expected;reg expected_clip;
    initial begin
        repeat(4)@(negedge clk);rst=0;
        for(n=0;n<4096;n=n+1)begin
            a=$random;b=$random;w=n;pressure=n;enable=n%3!=0;
            if(n%4==0)begin a=-262144;b=262143;end
            if(n%4==1)begin a=262143;b=-262144;end
            update=1;@(negedge clk);update=0;expected=y0;expected_clip=e0;requests=0;
            repeat(4)begin if(req)requests=requests+1;@(negedge clk);end
            if(y1!==expected || c1!==c0 || e1!==expected_clip || requests!=2)
                $fatal(1,"shared master mismatch frame=%d y=%d expected=%d req=%d",n,y1,expected,requests);
            repeat(3)@(negedge clk);
        end
        $display("PASS tb_shared_master: 4096 ADC levels, all weights, random signed extrema, smoothing/gain/bypass/clipping match, two shared products");$finish;
    end
endmodule
