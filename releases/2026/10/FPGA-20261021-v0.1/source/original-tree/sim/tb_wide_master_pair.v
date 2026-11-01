`timescale 1ns/1ps
module tb_wide_master_pair;
`ifdef GOWIN_VENDOR_MODEL
 GSR GSR(.GSRI(1'b1));
`endif
 reg clk=0;always #5 clk=~clk;
 reg rst=1,update=0,muted=0;reg[11:0]pressure=0;reg[7:0]weight=0;
 reg signed[31:0]a=0,b=0;reg ready=1;
 wire request,busy,valid,clip;wire signed[32:0]ma;wire signed[17:0]mb;
 wire signed[50:0]product;wire signed[23:0]sample_out;wire[31:0]clip_count;
 split_audio_multiplier #(33) backend(clk,rst,request && ready,ma,mb,product);
 wide_master dut(clk,rst,update,a,b,weight,1'b1,pressure,muted,sample_out,valid,busy,
  clip_count,clip,request,ready,ma,mb,product);
 integer i,cycle=0,products=0,gain=4096,w=64,target,expected_clip,expected_clips=0,waits;
 reg signed[63:0]num,master,expected,aa,bb;reg[31:0]rng=32'h59753137;
 function[31:0]next_random;input[31:0]x;reg[31:0]v;begin v=x^(x<<13);v=v^(v>>17);next_random=v^(v<<5);end endfunction
 always @(posedge clk)begin
  cycle=cycle+1;
  if(request && ready)products=products+1;
 end
 always @(negedge clk)ready=(cycle%7)!=0 && (cycle%7)!=1;
 initial begin
  repeat(4)@(negedge clk);rst=0;
  for(i=0;i<8192;i=i+1)begin
   rng=next_random(rng);a=rng;rng=next_random(rng);b=rng;
   if(i<256)begin a=i[0]?32'sh7fffffff:32'sh80000000;b=i[1]?32'sh7fffffff:32'sh80000000;end
   pressure=i&4095;weight=i&255;muted=i%257<40;
   if(w<weight)w=w+1;else if(w>weight)w=w-1;
   target=muted?0:pressure<=128?1024:pressure>=3200?4096:pressure+896;
   if(target>gain+32)gain=gain+32;else if(target<gain-32)gain=gain-32;else gain=target;
   aa=$signed(a);bb=$signed(b);num=aa*(255-w)+bb*w+8192;
   master=num>>>14;expected=(master*gain+2048)>>>12;
   expected_clip=expected>8388607 || expected< -8388608;
   if(expected>8388607)expected=8388607;if(expected< -8388608)expected=-8388608;
   expected_clips=expected_clips+expected_clip;
   products=0;update=1;@(negedge clk);update=0;
   a=~a;b=~b;weight=~weight;pressure=~pressure;muted=~muted;
   waits=0;while(!valid && waits<20)begin @(negedge clk);waits=waits+1;end
   if(!valid || products!=2 || sample_out!==expected[23:0] || clip!==expected_clip[0] || clip_count!==expected_clips)
    $fatal(1,"wide pair mismatch frame=%0d actual=%0d expected=%0d products=%0d wait=%0d",i,sample_out,expected,products,waits);
   @(negedge clk);
  end
  $display("PASS tb_wide_master_pair:8192 full32-bit input frames, ready stalls, atomic snapshots, pressure/mute/timbre slew, 2 requests/frame, clipped=%0d",expected_clips);$finish;
 end
 initial begin #2000000;$fatal(1,"wide master pair timeout");end
endmodule
