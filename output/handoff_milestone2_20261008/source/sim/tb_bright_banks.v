`timescale 1ns/1ps
module tb_bright_banks;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,ce=0;reg[2:0]bank=0;reg[8:0]addr=0;
 wire[15:0]data;reg[15:0]expected[0:3071];reg[15:0]held;
 gowin_prom_bright_bank dut(clk,ce,rst,bank,addr,data);
 integer b,a;
 initial begin
  $readmemh("rtl/audio/wave_bright_h16.hex",expected,0,511);
  $readmemh("rtl/audio/wave_bright_h8.hex",expected,512,1023);
  $readmemh("rtl/audio/wave_bright_h4.hex",expected,1024,1535);
  $readmemh("rtl/audio/wave_bright_h2.hex",expected,1536,2047);
  $readmemh("rtl/audio/wave_bright_h1.hex",expected,2048,2559);
  $readmemh("rtl/audio/wave_bright.hex",expected,2560,3071);
  repeat(3)@(negedge clk);rst=0;
  for(a=0;a<512;a=a+1)for(b=0;b<6;b=b+1)begin
   bank=b;addr=a;ce=1;@(posedge clk);#1;
   if(data!==expected[b*512+a])$fatal(1,"bank/address mismatch %0d/%0d actual=%h expected=%h",b,a,data,expected[b*512+a]);
   @(negedge clk);ce=0;held=data;bank=(b+1)%6;addr=~a;
   @(posedge clk);#1;if(data!==held)$fatal(1,"CE did not hold output");@(negedge clk);
  end
  rst=1;@(posedge clk);#1;if(data!==0)$fatal(1,"reset failed");
  $display("PASS tb_bright_banks: 3072 interleaved addresses, CE hold and synchronous reset");$finish;
 end
endmodule
