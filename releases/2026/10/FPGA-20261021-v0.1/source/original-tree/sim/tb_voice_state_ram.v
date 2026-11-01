`timescale 1ns/1ps
module tb_voice_state_ram;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,we=0,re=0;reg[8:0]wa=0,ra=0;reg[31:0]wd=0;
 wire[31:0]rd;wire valid,ready;
 voice_state_ram dut(clk,rst,we,wa,wd,re,ra,rd,valid,ready);
 reg[31:0]reference[0:511];reg[31:0]expected=0;
 reg expected_valid=0;integer i,clear_cycles=0,checked=0;
 reg[31:0]rng=32'h51359127;
 function[31:0]next_random;input[31:0]x;reg[31:0]v;begin v=x^(x<<13);v=v^(v>>17);next_random=v^(v<<5);end endfunction
 task cycle;begin
  expected_valid=!rst && ready && re;
  if(rst)expected=0;else if(expected_valid)begin expected=reference[ra];checked=checked+1;end
  if(!rst && ready && we)reference[wa]=wd;
  @(posedge clk);#1;
  if(valid!==expected_valid || rd!==expected)$fatal(1,"state RAM mismatch i=%0d addr=%0d actual=%h expected=%h valid=%b/%b",i,ra,rd,expected,valid,expected_valid);
  @(negedge clk);
 end endtask
 task initialize;begin
  rst=1;cycle();rst=0;clear_cycles=0;
  for(i=0;i<512;i=i+1)reference[i]=0;
  while(!ready)begin
   we=1;re=1;wa=7;ra=3;wd=32'hdeadbeef;cycle();clear_cycles=clear_cycles+1;
  end
  if(clear_cycles!=512)$fatal(1,"reset clear took %0d cycles",clear_cycles);
  we=0;re=1;for(i=0;i<512;i=i+1)begin ra=i;cycle();end
 end endtask
 initial begin
  cycle();initialize();
  we=1;re=1;
  for(i=0;i<512;i=i+1)begin wa=i;ra=(i+1)&511;wd=32'h12345678^(32'h01010101*i);cycle();end
  we=0;for(i=0;i<512;i=i+1)begin ra=511-i;cycle();end
  for(i=0;i<8192;i=i+1)begin
   rng=next_random(rng);wa=rng[8:0];ra=rng[17:9];we=rng[18];re=rng[19];
   if(wa==ra)wa=wa+9'd1;rng=next_random(rng);wd=rng;cycle();
  end
  initialize();we=0;re=0;repeat(8)cycle();
  $display("PASS tb_voice_state_ram: all512 addresses/all32bits, 8192 randomized cycles, CE holds, simultaneous separate-address access, two512-cycle reset sweeps; read checks=%0d",checked);$finish;
 end
 initial begin #1000000;$fatal(1,"state RAM timeout");end
endmodule
