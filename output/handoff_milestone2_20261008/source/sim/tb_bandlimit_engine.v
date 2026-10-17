`timescale 1ns/1ps
module tb_bandlimit_engine;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,tick=0;reg[127:0]incs=0;reg[63:0]envs=0;reg[31:0]vels=0;
 reg[16:0]ratio=65536;reg[3:0]retrigs=0;
 wire[1:0]valid;wire signed[18:0]ss[0:1],bs[0:1];
 genvar g;generate for(g=0;g<2;g=g+1)begin:lane
  wire request;wire signed[17:0]ma,mb;reg signed[35:0]product=0;
  always @(posedge clk)if(request)product<=ma*mb;
  shared_wavetable_engine #(.BEND_SHARED_ENABLE(1),.SHARED_MULT_ENABLE(g),.BANDLIMIT_ENABLE(1)) dut(
   .clk(clk),.rst(rst),.sample_tick(tick),.inc0(incs[31:0]),.inc1(incs[63:32]),.inc2(incs[95:64]),.inc3(incs[127:96]),
   .env0(envs[15:0]),.env1(envs[31:16]),.env2(envs[47:32]),.env3(envs[63:48]),
   .vel0(vels[7:0]),.vel1(vels[15:8]),.vel2(vels[23:16]),.vel3(vels[31:24]),
   .retrig0(retrigs[0]),.retrig1(retrigs[1]),.retrig2(retrigs[2]),.retrig3(retrigs[3]),
   .bend_ratio_q16(ratio),.sine_sum(ss[g]),.bright_sum(bs[g]),.sums_valid(valid[g]),
   .mult_request(request),.mult_operand_a(ma),.mult_operand_b(mb),.mult_result(product));
 end endgenerate
 integer fd,n,rc,frames=0,expected_s,expected_b,cycles,products,capture=0;
 reg[1023:0]path;
 initial begin
  if(!$value$plusargs("VECTORS=%s",path))begin
   path="sim/vectors/bandlimit_smoke.txt";
  end
  fd=$fopen(path,"r");if(!fd)$fatal(1,"cannot open vectors");
  if($value$plusargs("CAPTURE=%s",path))capture=$fopen(path,"w");
  if(capture)$fdisplay(capture,"case_id,sine,bright");
  repeat(4)@(negedge clk);rst=0;
  while(!$feof(fd))begin
   rc=$fscanf(fd,"%h %h %h %h %h %h %d %d\n",incs,ratio,envs,vels,retrigs,n,expected_s,expected_b);
   if(rc!=8)$fatal(1,"malformed vectors at %0d",frames);
   tick=1;@(negedge clk);tick=0;cycles=0;products=0;
   while(!valid[0] && cycles<200)begin
    if(lane[1].request)products=products+1;
    @(negedge clk);cycles=cycles+1;
   end
   if(valid!==3 || cycles!=108 || products!=40)$fatal(1,"deadline/valid/products %0d %0d %b",cycles,products,valid);
   if(ss[0]!==expected_s || bs[0]!==expected_b || ss[0]!==ss[1] || bs[0]!==bs[1])
    $fatal(1,"frame %0d expected=%0d/%0d local=%0d/%0d shared=%0d/%0d",frames,expected_s,expected_b,ss[0],bs[0],ss[1],bs[1]);
   if(capture && n>=0)$fdisplay(capture,"%0d,%0d,%0d",n,ss[1],bs[1]);
   frames=frames+1;repeat(2)@(negedge clk);
  end
  $fclose(fd);$display("PASS tb_bandlimit_engine: %0d independent-reference frames; 108 clocks, 40 products, local/shared exact",frames);$finish;
 end
 initial begin #1000000000;$fatal(1,"timeout");end
endmodule
