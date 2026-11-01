`timescale 1ns/1ps
module tb_ram_audio_datapath #(parameter integer VOICES=8);
`ifdef GOWIN_VENDOR_MODEL
 GSR GSR(.GSRI(1'b1));
`endif
 localparam integer CLOCK_HZ=VOICES==8?12288000:49152000;
 localparam integer PERIOD=CLOCK_HZ/48000;
 reg clk=0;always #(1.0e9/(2.0*CLOCK_HZ))clk=~clk;
 reg rst=1,cv=0,muted=0;reg[5:0]id=0;reg[31:0]inc=0;
 reg[15:0]env=65535;reg[6:0]vel=100;reg rt=1;reg[7:0]weight=64;reg[11:0]pressure=0;
 wire cr,bck,lrck,din,tick,valid,initialized;wire signed[23:0]audio,left,right;wire[31:0]clips;wire decoded;
 ram_audio_datapath #(.VOICES(VOICES),.CLK_HZ(CLOCK_HZ)) dut(clk,rst,cv,cr,id,inc,env,vel,rt,
  weight,1'b1,pressure,muted,bck,lrck,din,tick,audio,valid,clips,initialized);
 i2s_rx_model #(.DATA_BITS(24)) receiver(.bck(bck),.rst(rst),.lrck(lrck),.din(din),
  .left_word(left),.right_word(right),.frame_valid(decoded));
 reg[23:0]sent_current=0,sent_previous=0;
 reg signed[63:0]aa,bb,num,master,expected=0;
 integer w=64,gain=4096,target,frames=0,serial_frames=0,audible=0,low_bits=0;
 integer frame_cycles=0,products=0,i,unmute_audible;
 always @(negedge lrck)begin sent_previous=sent_current;sent_current=audio;end
 always @(posedge decoded)begin
  #1;
  if(serial_frames>3 && (left!==sent_previous || left!==right || ^left===1'bx))
   $fatal(1,"RAM I2S mismatch left=%h right=%h expected=%h",left,right,sent_previous);
  serial_frames=serial_frames+1;if(left!=0)audible=audible+1;if(left[7:0]!=0)low_bits=low_bits+1;
 end
 always @(posedge clk)begin
  if(rst)begin w=64;gain=4096;expected=0;end
  else if(dut.sums_valid)begin
   if(w<weight)w=w+1;else if(w>weight)w=w-1;
   target=muted?0:pressure<=128?1024:pressure>=3200?4096:pressure+896;
   if(target>gain+32)gain=gain+32;else if(target<gain-32)gain=gain-32;else gain=target;
   aa=$signed(dut.sine_total);bb=$signed(dut.bright_total);
   num=aa*(255-w)+bb*w+(64'sd1<<(7+$clog2(VOICES)));
   master=num>>>(8+$clog2(VOICES));expected=(master*gain+2048)>>>12;
   if(expected>8388607)expected=8388607;if(expected< -8388608)expected=-8388608;
  end
  if(tick)begin frame_cycles=0;products=0;end else frame_cycles=frame_cycles+1;
  if(dut.master_req && dut.aux_ready_v[0])products=products+1;
 end
 always @(posedge valid)begin
  #1;
  if(audio!==expected[23:0] || products!=2 || frame_cycles!=27*(VOICES>32?32:VOICES)+6)
   $fatal(1,"RAM master mismatch sample=%0d expected=%0d cycles=%0d requests=%0d",audio,expected,frame_cycles,products);
  frames=frames+1;
 end
 initial begin
  repeat(5)@(negedge clk);rst=0;wait(initialized);
  for(i=0;i<VOICES;i=i+1)begin
   wait(cr);@(negedge clk);id=i;inc=32'd15000000+i*32'd5000000;cv=1;
   @(negedge clk);cv=0;wait(cr);@(negedge clk);
  end
  repeat(64)@(posedge tick);@(negedge clk);weight=255;pressure=4095;
  repeat(256)@(posedge tick);@(negedge clk);muted=1;
  repeat(140)@(posedge tick);wait(valid);#1;if(audio!==0)$fatal(1,"RAM mute failed");
  @(negedge clk);muted=0;weight=0;pressure=0;unmute_audible=audible;
  repeat(260)@(posedge tick);@(negedge clk);
  if(audible-unmute_audible<100 || low_bits<100 || frames<600 || clips!=0)$fatal(1,"RAM audio coverage/headroom failed");
  $display("PASS tb_ram_audio_datapath: voices=%0d master_frames=%0d decoded=%0d low_bits=%0d shared_products=2 frame_cycles=%0d period=%0d; slew/mute/stereo/24-bit exact",VOICES,frames,serial_frames,low_bits,27*(VOICES>32?32:VOICES)+6,PERIOD);$finish;
 end
 initial begin #100000000;$fatal(1,"RAM audio timeout");end
endmodule
