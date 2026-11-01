`timescale 1ns/1ps
// Dual-clock shell test: 12.288 MHz reference + rPLL compute domain, stereo
// frame bridge, event handshake, I2S output. Checks PLL lock, event delivery,
// 32-voice allocation, mono-consistent I2S output and frame ids.
module tb_ram32_clocked #(parameter integer MULT=4);
 reg clk_ref=0;
 always #40.690104 clk_ref=~clk_ref;   // 12.288 MHz
 reg reset=1;
 reg ev_valid=0,ev_on=0;
 reg [6:0] ev_note=0;
 reg [7:0] ev_vel=8'd120;
 reg instrument=0;
 reg [1:0] piano_tone=0;
 wire ev_ready,bck,lrck,din,locked,initialized;
 wire signed [23:0] audio;
 wire [5:0] active;
 wire [31:0] clips;
 wire [7:0] frame_id;
 wire sample_valid;
 wire signed [23:0] dl,dr;
 wire decoded;
 integer frames=0,i,ev_count=0,request_count=0,result_count=0,capture_count=0;
 reg frame_seen=0;
 reg [7:0] previous_frame_id=0;
 realtime t_first,t_last,period;
 real expected_period;

 ram32_clocked_top #(.MULT(MULT),.ATTACK_STEP(16'd8192),.DECAY_STEP(16'd4096),
                     .RELEASE_STEP(16'd4096),.SUSTAIN_LEVEL(16'd32768)) dut(
  .clk_ref(clk_ref),.reset(reset),
  .instrument(instrument),.piano_tone(piano_tone),
  .ev_valid(ev_valid),.ev_on(ev_on),.ev_note(ev_note),.ev_vel(ev_vel),
  .ev_ready(ev_ready),
  .i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),
  .audio_sample(audio),.sample_valid(sample_valid),
  .active_count(active),.clip_count(clips),.locked(locked),.initialized(initialized),
  .frame_id(frame_id));

 i2s_rx_model #(.DATA_BITS(24)) receiver(.bck(bck),.rst(reset),.lrck(lrck),.din(din),
  .left_word(dl),.right_word(dr),.frame_valid(decoded));
 always @(posedge decoded)begin
  #1;
  if(frames>3 && (dl!==dr || ^dl===1'bx)) $fatal(1,"stereo mismatch l=%h r=%h",dl,dr);
  frames=frames+1;
 end
 always @(posedge dut.clk_compute)begin
  if(!dut.reset_compute && dut.tick_compute)request_count=request_count+1;
  if(!dut.reset_compute && sample_valid)result_count=result_count+1;
 end
 always @(posedge dut.valid_audio)begin
  if(frame_seen && frame_id!==previous_frame_id+1'b1)
   $fatal(1,"non-contiguous frame id previous=%0d current=%0d",previous_frame_id,frame_id);
  previous_frame_id=frame_id;frame_seen=1;capture_count=capture_count+1;
 end

 task send_event;
  input on;
  input [6:0] n;
  begin
   while(!ev_ready) @(negedge clk_ref);
   @(negedge clk_ref); ev_valid=1; ev_on=on; ev_note=n;
   @(negedge clk_ref); ev_valid=0; ev_on=0;
   ev_count=ev_count+1;
  end
 endtask

 initial begin
  repeat(20) @(negedge clk_ref);
  reset=0;
  wait(locked);
  wait(initialized);
  // compute clock period from the internal PLL output
  @(posedge dut.clk_compute); t_first=$realtime;
  repeat(64) @(posedge dut.clk_compute); t_last=$realtime;
  period=(t_last-t_first)/64.0;
  expected_period=81.380208/MULT;
  if(period<expected_period-0.05 || period>expected_period+0.05) $fatal(1,"compute period %f ns expect %f",period,expected_period);
  $display("METRIC compute_period_ns=%.4f",period);

  // A bundled control update must cross as one coherent value.
  instrument=1; piano_tone=2'b11;
  i=0;
  while((dut.instrument_c!==1'b1 || dut.piano_tone_c!==2'b11) && i<32)begin
   @(posedge clk_ref);i=i+1;
  end
  if(i==32)$fatal(1,"coherent control update did not cross");
  instrument=0; piano_tone=2'b00;
  i=0;
  while((dut.instrument_c!==1'b0 || dut.piano_tone_c!==2'b00) && i<32)begin
   @(posedge clk_ref);i=i+1;
  end
  if(i==32)$fatal(1,"coherent control return did not cross");

  for(i=0;i<32;i=i+1) send_event(1'b1,7'd36+i[6:0]);
  repeat(120) @(posedge decoded);
  if(active!==6'd32) $fatal(1,"active=%0d expect 32 after %0d events",active,ev_count);
  if(clips!=0) $fatal(1,"clip counter moved");
  if(frame_id<8'd80) $fatal(1,"frame id too small: %0d",frame_id);
  if(result_count>request_count || request_count-result_count>1)
   $fatal(1,"request/result imbalance requests=%0d results=%0d",request_count,result_count);
  if(capture_count>result_count || result_count-capture_count>1)
   $fatal(1,"result/capture imbalance results=%0d captures=%0d",result_count,capture_count);
  $display("METRIC frames=%0d frame_id=%0d active=%0d",frames,frame_id,active);

  send_event(1'b0,7'd40);
  repeat(40) @(posedge decoded);
  if(active!==6'd31) $fatal(1,"release left active=%0d",active);
  if(frames<140) $fatal(1,"not enough decoded frames: %0d",frames);
  $display("PASS tb_ram32_clocked: mult=%0d 12.288MHz ref, PLL compute, stereo bridge, I2S, events, 32 voices",
           MULT);
  $finish;
 end
 initial begin #60000000; $fatal(1,"clocked top timeout"); end
endmodule
