`timescale 1ns/1ps
module tb_bend_ratio_pipeline;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,update=0;reg[11:0]code=2048;
 wire[16:0]ratio;wire valid;
 reg[16:0]reference[0:4095];reg[1:0]pending=0;
 reg[11:0]code0=2048,code1=2048;reg[16:0]expected=65536;
 reg expected_valid=0;integer cycles=0,outputs=0,i;
 reg[31:0]rng=32'h38512679;
 bend_ratio_pipeline dut(clk,rst,update,code,ratio,valid);
 always @(posedge clk)begin
  if(rst)begin pending=0;expected_valid=0;expected=65536;end
  else begin
   expected_valid=pending[1];
   if(pending[1])begin expected=reference[code1];outputs=outputs+1;end
   code1=code0;code0=code;pending={pending[0],update};
  end
  #1;
  if(ratio!==expected || valid!==expected_valid)$fatal(1,"pipeline mismatch cycle=%0d ratio=%0d expected=%0d valid=%b/%b",cycles,ratio,expected,valid,expected_valid);
  cycles=cycles+1;
 end
 task drive;begin @(negedge clk);end endtask
 initial begin
  $readmemh("sim/vectors/bend_ratio_reference.hex",reference);
  repeat(4)drive();rst=0;
  for(i=0;i<4096;i=i+1)begin code=i;update=1;drive();end
  for(i=4095;i>=0;i=i-1)begin code=i;update=1;drive();update=0;repeat(i%4)drive();end
  for(i=0;i<4096;i=i+1)begin
   rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
   rst=(i%137)==0;update=rng[12];code=rng[11:0];drive();
  end
  rst=0;update=0;repeat(5)drive();
  if(outputs<9000)$fatal(1,"insufficient results");
  $display("PASS tb_bend_ratio_pipeline: all 4096 codes dense and gapped, random resets/updates, outputs=%0d; 3 registered stages",outputs);$finish;
 end
endmodule
