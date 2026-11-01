`timescale 1ns/1ps
module tb_instrument_rom_banks;
reg clk=0;always #5 clk=~clk;
reg rst=1,ce=0;reg [5:0] bank=0;reg [8:0] addr=0;
wire [15:0] data;
reg [15:0] piano[0:6143],guitar[0:15359],bright[0:3071];
reg [15:0] want;
integer b,a,checked=0,stalls=0;
instrument_rom_banks dut(clk,ce,rst,bank,addr,data);
initial begin
 $readmemh("rtl/audio/epiano_bank_all.hex",piano);
 $readmemh("rtl/audio/guitar_bank_all.hex",guitar);
 $readmemh("rtl/audio/wave_bright_h16.hex",bright,0,511);
 $readmemh("rtl/audio/wave_bright_h8.hex",bright,512,1023);
 $readmemh("rtl/audio/wave_bright_h4.hex",bright,1024,1535);
 $readmemh("rtl/audio/wave_bright_h2.hex",bright,1536,2047);
 $readmemh("rtl/audio/wave_bright_h1.hex",bright,2048,2559);
 $readmemh("rtl/audio/wave_bright.hex",bright,2560,3071);
 repeat(4)@(negedge clk);rst=0;
 for(b=0;b<48;b=b+1)for(a=0;a<512;a=a+1)begin
  @(negedge clk);ce=1;bank=b;addr=a;
  want=b<12?piano[b*512+a]:b<42?guitar[(b-12)*512+a]:bright[(b-42)*512+a];
  @(posedge clk);#1;
  if(data!==want)$fatal(1,"instrument_ROM_mismatch bank=%0d addr=%0d got=%h want=%h",b,a,data,want);
  checked=checked+1;
  if(a%127==0)begin
   @(negedge clk);ce=0;bank=(b+13)%48;addr=511-a;
   @(posedge clk);#1;
   if(data!==want)$fatal(1,"ROM_CE_hold_selected_wrong_group bank=%0d addr=%0d",b,a);
   stalls=stalls+1;
  end
 end
 $display("PASS tb_instrument_rom_banks: addresses=%0d CE_hold_checks=%0d",checked,stalls);$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
