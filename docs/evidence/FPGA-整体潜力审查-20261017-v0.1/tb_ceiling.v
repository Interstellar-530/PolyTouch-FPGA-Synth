
`timescale 1ns/1ps
module tb_ceiling;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,tick=0;reg[6:0]note=60;reg[16:0]ratio=65536;
 wire[31:0]base_inc;wire signed[18:0]sine_sum,bright_sum;
 wire valid;wire signed[15:0]sample;
 note_phase_inc #(.FS_HZ(48000)) npi(note,base_inc);
 shared_wavetable_engine #(.BEND_SHARED_ENABLE(1)) core(
 .clk(clk),.rst(rst),.sample_tick(tick),
 .inc0(base_inc),.inc1(32'd0),.inc2(32'd0),.inc3(32'd0),
 .retrig0(1'b0),.retrig1(1'b0),.retrig2(1'b0),.retrig3(1'b0),
 .env0(16'd65535),.env1(16'd0),.env2(16'd0),.env3(16'd0),
 .vel0(8'd127),.vel1(8'd0),.vel2(8'd0),.vel3(8'd0),
 .bend_ratio_q16(ratio),.sine_sum(sine_sum),.bright_sum(bright_sum),.sums_valid(valid));
 global_crossfade #(.MASTER_VOLUME_SHIFT(2)) xf(.clk(clk),.rst(rst),.update(valid),
 .clear_clip(1'b0),.mix_weight(8'd255),.sine_sum(sine_sum),.bright_sum(bright_sum),.sample_out(sample));
 integer notes[0:6];integer fd,c,n;reg[2047:0]capture;
 initial begin
  if(!$value$plusargs("CAPTURE=%s",capture))$fatal(1,"capture missing");
  fd=$fopen(capture,"w");if(!fd)$fatal(1,"capture open");
  $fwrite(fd,"case_id,note,ratio_q16,base_inc,frame,phase,sine_sum,bright_sum,sample\n");
  notes[0]=60;notes[1]=71;notes[2]=89;notes[3]=91;notes[4]=96;notes[5]=108;notes[6]=127;
  for(c=0;c<7;c=c+1)begin
   rst=1;tick=0;note=notes[c];ratio=c==2?17'd73562:17'd65536;
   repeat(4)@(negedge clk);rst=0;
   for(n=0;n<8192;n=n+1)begin
    tick=1;@(negedge clk);tick=0;
    wait(valid);repeat(2)@(negedge clk);
    if(^sample===1'bx || ^sine_sum===1'bx || ^bright_sum===1'bx)$fatal(1,"unknown output");
    $fwrite(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",c,note,ratio,base_inc,n,core.phase0,sine_sum,bright_sum,sample);
    repeat(2)@(negedge clk);
   end
  end
  $fclose(fd);$display("PASS tb_ceiling: 7 pitches, 8192 actual RTL frames per case, no unknown output");$finish;
 end
 initial begin #100000000;$fatal(1,"ceiling capture timeout");end
endmodule
