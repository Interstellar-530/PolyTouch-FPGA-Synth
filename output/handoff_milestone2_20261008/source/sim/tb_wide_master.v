`timescale 1ns/1ps
module tb_wide_master;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,update=0,mute=0;reg[11:0]pressure=0;reg[7:0]weight=0;
 reg signed[20:0]a=0,b=0;
 wire signed[23:0]value[0:1];wire signed[15:0]sample16[0:1];wire[1:0]clip;
 genvar g;generate for(g=0;g<2;g=g+1)begin:lane
  wire req;wire signed[17:0]ma,mb;reg signed[35:0]product=0;
  always @(posedge clk)if(req)product<=ma*mb;
  global_crossfade #(.PRESSURE_GAIN_ENABLE(1),.MUTE_SLEW_ENABLE(1),.TIMBRE_SLEW_ENABLE(1),
   .MASTER_VOLUME_SHIFT(2),.SHARED_MULT_ENABLE(g),.EXTRA_FRACTION_BITS(2),.REGISTER_MIX_INPUTS_ENABLE(g)) dut(
   .clk(clk),.rst(rst),.update(update),.clear_clip(1'b0),.mix_weight(weight),.sine_sum(a),.bright_sum(b),
   .sample_out(sample16[g]),.sample_out24(value[g]),.clip_event(clip[g]),.pressure_enable(1'b1),
   .pressure_level(pressure),.mute(mute),.mult_request(req),.mult_operand_a(ma),.mult_operand_b(mb),.mult_result(product));
 end endgenerate
 integer i,gain=4096,w=64,target,expected_clip;reg[31:0]randoms=32'h53170261;
 reg signed[63:0]num,master,expected;
 function[31:0]next_random;input[31:0]x;reg[31:0]v;begin v=x^(x<<13);v=v^(v>>17);next_random=v^(v<<5);end endfunction
 task frame;begin
  if(w<weight)w=w+1;else if(w>weight)w=w-1;
  target=mute?0:pressure<=128?1024:pressure>=3200?4096:pressure+896;
  if(target>gain+32)gain=gain+32;else if(target<gain-32)gain=gain-32;else gain=target;
  num=$signed(a);num=num*(255-w);master=$signed(b);num=num+master*w+512;
  master=num>>>10;expected=(master*gain+32)>>>6;
  expected_clip=expected>8388607 || expected< -8388608;
  if(expected>8388607)expected=8388607;if(expected< -8388608)expected=-8388608;
  update=1;@(negedge clk);update=0;
  // Local output is valid immediately; shared completion is five edges later.
  if(value[0]!==expected[23:0] || clip[0]!==expected_clip[0])$fatal(1,"local wide master mismatch %0d actual=%0d expected=%0d",i,value[0],expected);
  // Adversarial mid-frame changes must not alter the registered frame.
  a=~a;b=~b;weight=~weight;pressure=~pressure;mute=~mute;
  wait(lane[1].dut.result_valid);@(posedge clk);#1;
  if(value[1]!==expected[23:0] || sample16[1]!==expected[23:8] || clip[1]!==expected_clip[0])
   $fatal(1,"shared wide master mismatch %0d actual=%0d expected=%0d",i,value[1],expected);
  repeat(2)@(negedge clk);
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst=0;
  for(i=0;i<8192;i=i+1)begin
   pressure=i&4095;weight=i&255;mute=(i%257)<40;
   randoms=next_random(randoms);a=randoms[20:0];randoms=next_random(randoms);b=randoms[20:0];
   if(i<256)begin a=i[0]?21'sh0fffff:21'sh100000;b=i[1]?21'sh0fffff:21'sh100000;end
   frame();
  end
  $display("PASS tb_wide_master: 8192 frames, full signed input extrema, pressure/mute/timbre slew, local/shared exact and clip decisions");$finish;
 end
 initial begin #10000000;$fatal(1,"wide master timeout");end
endmodule
