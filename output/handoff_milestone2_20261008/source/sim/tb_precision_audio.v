`timescale 1ns/1ps
module tb_precision_audio;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,tick=0,retrigger=0;reg[15:0]env=0;reg[11:0]pressure=3200;
 wire signed[23:0]audio[0:1];wire[31:0]phase;
 genvar g;generate for(g=0;g<2;g=g+1)begin:lane
  wire signed[18+2*g:0]sine,bright;wire valid,er,xr;
  wire signed[17:0]ea,eb,xa,xb;reg signed[35:0]product=0;
  always @(posedge clk)begin
   if(er && xr)$fatal(1,"precision test multiplier collision");
   if(er || xr)product<=(er?ea:xa)*(er?eb:xb);
  end
  shared_wavetable_engine #(.BEND_SHARED_ENABLE(1),.SHARED_MULT_ENABLE(1),.BANDLIMIT_ENABLE(1),.EXTRA_FRACTION_BITS(2*g)) engine(
   .clk(clk),.rst(rst),.sample_tick(tick),.inc0(32'd39321600),.inc1(32'd0),.inc2(32'd0),.inc3(32'd0),
   .env0(env),.env1(16'd0),.env2(16'd0),.env3(16'd0),.vel0(8'd100),.vel1(8'd0),.vel2(8'd0),.vel3(8'd0),
   .retrig0(retrigger),.retrig1(1'b0),.retrig2(1'b0),.retrig3(1'b0),.bend_ratio_q16(17'd65536),
   .sine_sum(sine),.bright_sum(bright),.sums_valid(valid),.mult_request(er),.mult_operand_a(ea),.mult_operand_b(eb),.mult_result(product));
  global_crossfade #(.PRESSURE_GAIN_ENABLE(1),.MASTER_VOLUME_SHIFT(2),.SHARED_MULT_ENABLE(1),.EXTRA_FRACTION_BITS(2*g)) master(
   .clk(clk),.rst(rst),.update(valid),.clear_clip(1'b0),.mix_weight(8'd0),.sine_sum(sine),.bright_sum(bright),
   .sample_out24(audio[g]),.pressure_enable(1'b1),.pressure_level(pressure),.mute(1'b0),
   .mult_request(xr),.mult_operand_a(xa),.mult_operand_b(xb),.mult_result(product));
 end endgenerate
 assign phase=lane[1].engine.phase0;
 integer fd=0,c,i,low_bits=0;reg[1023:0]path;
 task frame;begin tick=1;@(negedge clk);tick=0;repeat(120)@(negedge clk);end endtask
 task end_frame;begin repeat(135)@(negedge clk);end endtask
 initial begin
  if($value$plusargs("CAPTURE=%s",path))fd=$fopen(path,"w");
  if(fd)$fdisplay(fd,"case_id,env,gain,phase,legacy,wide");
  repeat(4)@(negedge clk);rst=0;
  for(c=0;c<8;c=c+1)begin
   case(c/2)0:env=65535;1:env=4096;2:env=256;3:env=16;endcase
   pressure=c[0]?0:3200;
   repeat(140)begin frame();end_frame();end
   for(i=0;i<(fd?8192:64);i=i+1)begin
    frame();
    if(audio[1][7:0]!=0)low_bits=low_bits+1;
    if(fd)$fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d",c,env,lane[1].master.g_pressure.gain_q12,phase,audio[0],audio[1]);
    end_frame();
   end
  end
  if(low_bits==0)$fatal(1,"wide output low bits never carry signal");
  $display("PASS tb_precision_audio: eight envelope/gain conditions; real shared engines and VCA; nonzero low bits=%0d",low_bits);$finish;
 end
 initial begin #1000000000;$fatal(1,"precision audio timeout");end
endmodule
