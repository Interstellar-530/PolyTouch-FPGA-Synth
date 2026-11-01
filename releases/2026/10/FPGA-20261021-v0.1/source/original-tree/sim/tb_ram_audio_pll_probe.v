`timescale 1ns/1ps
module tb_ram_audio_pll_probe;
 GSR GSR(.GSRI(1'b1));
 reg clk=0;always #40.690104 clk=~clk;
 reg kr=0,k1=1;wire bck,lrck,din,xsmt,led;
 ram_audio_pll_probe dut(clk,kr,k1,bck,lrck,din,xsmt,led);
 wire signed[23:0]left,right;wire decoded;
 i2s_rx_model #(.DATA_BITS(24)) receiver(.bck(bck),.rst(dut.u_audio.reset_audio),.lrck(lrck),.din(din),
  .left_word(left),.right_word(right),.frame_valid(decoded));
 reg[23:0]sent_current=0,sent_previous=0,last_fast_sample=0;
 integer w=64,gain=4096,target,fast_cycles=0,fast_frames=0,commits=0,serial_frames=0,local_serial=0,nonzero=0;
 reg signed[63:0]a,b,number,master,expected;
 realtime fast_time=0,reference_time=0,worst_transfer=0,worst_frame=0,last_bck=0,last_lrck=0;
 always @(negedge lrck)begin
  sent_previous=sent_current;sent_current=dut.u_audio.audio_sample;
  if(xsmt && last_lrck>0 && ($realtime-last_lrck<20833.2 || $realtime-last_lrck>20833.4))$fatal(1,"reference I2S frame period");
  last_lrck=$realtime;
 end
 always @(posedge bck)begin
  if(xsmt && last_bck>0 && ($realtime-last_bck<325.50 || $realtime-last_bck>325.55))$fatal(1,"reference I2S BCK period");
  last_bck=$realtime;
 end
 always @(posedge clk)begin
  if(dut.u_audio.reset_audio)begin local_serial=0;sent_current=0;sent_previous=0;last_bck=0;last_lrck=0;end
  if(dut.u_audio.tick_audio)reference_time=$realtime;
 end
 always @(posedge decoded)begin
  #1;
  if(local_serial>3 && (left!==right || left!==sent_previous || ^left===1'bx))$fatal(1,"PLL reference I2S word mismatch");
  serial_frames=serial_frames+1;local_serial=local_serial+1;if(left!=0)nonzero=nonzero+1;
 end
 always @(posedge dut.compute_clk)begin
  if(dut.compute_reset)begin w=64;gain=4096;fast_cycles=0;expected=0;end
  else begin
   if(dut.u_audio.tick_compute)fast_cycles=0;else fast_cycles=fast_cycles+1;
   if(dut.u_audio.u_compute.sums_valid)begin
    if(w<128)w=w+1;else if(w>128)w=w-1;
    target=dut.button_sync?4096:0;
    if(target>gain+32)gain=gain+32;else if(target<gain-32)gain=gain-32;else gain=target;
    a=$signed(dut.u_audio.u_compute.sine_total);b=$signed(dut.u_audio.u_compute.bright_total);
    number=a*(255-w)+b*w+8192;master=number>>>14;expected=(master*gain+2048)>>>12;
    if(expected>8388607)expected=8388607;if(expected< -8388608)expected=-8388608;
   end
  end
 end
 always @(posedge dut.u_audio.valid_compute)begin
  #1;
  if(dut.u_audio.sample_compute!==expected[23:0] || fast_cycles!=870)$fatal(1,"PLL compute mismatch or deadline cycles=%0d",fast_cycles);
  last_fast_sample=dut.u_audio.sample_compute;fast_time=$realtime;fast_frames=fast_frames+1;
 end
 always @(posedge dut.u_audio.sample_valid)begin
  #1;
  if(dut.u_audio.audio_sample!==last_fast_sample)$fatal(1,"PLL CDC sample tearing/loss");
  if($realtime-fast_time>worst_transfer)worst_transfer=$realtime-fast_time;
  if($realtime-reference_time>worst_frame)worst_frame=$realtime-reference_time;
  if($realtime-reference_time>20000)$fatal(1,"PLL sample missed next audio frame");
  commits=commits+1;
 end
 initial begin
  repeat(20)@(negedge clk);kr=1;wait(dut.configured);
  repeat(200)@(posedge dut.u_audio.tick_audio);@(negedge clk);k1=0;
  repeat(140)@(posedge dut.u_audio.tick_audio);wait(dut.u_audio.sample_valid);#1;
  if(dut.u_audio.audio_sample!==0)$fatal(1,"PLL mute failed");
  @(negedge clk);k1=1;repeat(140)@(posedge dut.u_audio.tick_audio);
  @(negedge clk);kr=0;#1;if(xsmt!==0)$fatal(1,"PLL reset did not mute DAC");
  repeat(20)@(negedge clk);kr=1;wait(dut.configured);repeat(128)@(posedge dut.u_audio.tick_audio);
  if(serial_frames<550 || nonzero<300 || dut.clips!=0)$fatal(1,"PLL probe coverage/headroom");
  $display("METRIC PLL_audio fast_frames=%0d commits=%0d decoded=%0d worst_CDC_ns=%.3f worst_tick_to_commit_ns=%.3f",fast_frames,commits,serial_frames,worst_transfer,worst_frame);
  $display("PASS tb_ram_audio_pll_probe: vendor PLL/RAM/ROM/DSP,64 configured voices, reference-clock I2S,24-bit exact, mute/relock/reset");$finish;
 end
 initial begin #20000000;$fatal(1,"PLL audio timeout");end
endmodule
