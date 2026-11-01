`timescale 1ns/1ps
module tb_split_audio_multiplier;
`ifdef GOWIN_VENDOR_MODEL
 GSR GSR(.GSRI(1'b1));
`endif
 reg clk=0;always #5 clk=~clk;
 reg rst=1,en=0;reg signed[34:0]a=0;reg signed[17:0]b=0;
 wire signed[41:0]p24;wire signed[50:0]p33;wire signed[52:0]p35;
 split_audio_multiplier #(24) u24(clk,rst,en,a[23:0],b,p24);
 split_audio_multiplier #(33) u33(clk,rst,en,a[32:0],b,p33);
 split_audio_multiplier #(35) u35(clk,rst,en,a,b,p35);
 reg signed[63:0]ex24=0,ex33=0,ex35=0,aa,bb;
 reg[31:0]rng=32'habc13579;integer i;
 function[31:0]next_random;input[31:0]x;reg[31:0]v;begin v=x^(x<<13);v=v^(v>>17);next_random=v^(v<<5);end endfunction
 task check;begin
  if(rst)begin ex24=0;ex33=0;ex35=0;end
  else if(en)begin
   bb=$signed(b);aa=$signed(a[23:0]);ex24=aa*bb;
   aa=$signed(a[32:0]);ex33=aa*bb;aa=$signed(a);ex35=aa*bb;
  end
  @(posedge clk);#1;
  if(p24!==ex24[41:0] || p33!==ex33[50:0] || p35!==ex35[52:0])
   $fatal(1,"split product mismatch i=%0d A=%0d B=%0d 24:%0d/%0d 33:%0d/%0d 35:%0d/%0d",i,a,b,p24,ex24,p33,ex33,p35,ex35);
  @(negedge clk);
 end endtask
 initial begin
  check();rst=0;
  for(i=0;i<32768;i=i+1)begin
   rng=next_random(rng);a[31:0]=rng;rng=next_random(rng);a[34:32]=rng[2:0];b=rng[20:3];
   en=(i%11)!=0;rst=(i%1009)==0;
   if(i<32)begin a=i[0]?35'sh400000000:35'sh3ffffffff;b=i[1]?18'sh20000:18'sh1ffff;end
   if(i>=32 && i<64)begin a=35'd131072+(i-48);b=i[0]?-18'sd65536:18'sd73562;end
   check();
  end
  $display("PASS tb_split_audio_multiplier: 32768 events each for widths24/33/35; signed extrema, low-limb sign boundaries, CE holds, resets");$finish;
 end
endmodule
