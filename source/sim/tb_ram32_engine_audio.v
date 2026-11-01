`timescale 1ns/1ps
// Full 73.728 MHz core, real ROM models, CDC, master and pin-level I2S.
module tb_ram32_engine_audio;
 reg clk=0; always #40.690104 clk=~clk;
 reg reset=1,ev_valid=0,ev_on=0,mute=0,pressure_enable=0;
 reg [6:0] note=60,volume=100;
 reg [11:0] pressure=3200,bend=2048;
 wire ready,bck,lrck,din,valid,locked,initialized;
 wire signed [23:0] audio,dl,dr;
 wire [5:0] active;
 wire [31:0] clips;
 wire decoded;
 ram32_clocked_top #(.MULT(6),.ATTACK_STEP(65535),.DECAY_STEP(65535),
   .SUSTAIN_LEVEL(65535),.RELEASE_STEP(65535)) dut(
   .clk_ref(clk),.reset(reset),.instrument(1'b0),.piano_tone(3'd4),
   .volume_target(volume),.mute(mute),.pressure_enable(pressure_enable),
   .pressure_adc(pressure),.bend_adc(bend),
   .ev_valid(ev_valid),.ev_on(ev_on),.ev_note(note),.ev_vel(8'd127),.ev_ready(ready),
   .i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),.audio_sample(audio),
   .sample_valid(valid),.active_count(active),.clip_count(clips),.locked(locked),
   .initialized(initialized),.frame_id());
 i2s_rx_model #(.DATA_BITS(24)) rx(.bck(bck),.rst(reset),.lrck(lrck),.din(din),
   .left_word(dl),.right_word(dr),.frame_valid(decoded));
 integer frames=0,checked=0,gain=4096,w=64,target,expected_clips=0;
 integer frame_cycle=0,max_tail=0,zeros=0,nonzeros=0,low_pressure_frames=0;
 reg pending=0;
 reg signed [63:0] a,b,num,base,expected;
 reg signed [23:0] expected_sample,sent_previous=0,sent_current=0;
 realtime first_event=0,first_pin=0,burst_start=0,burst_done=0;
 realtime accepted_at=0,queue_min=1.0e9,queue_max=0;
 integer queued_events=0;
 reg bend_check=0;
 always @(posedge clk)if(!reset && ev_valid && ready)accepted_at=$realtime;
 always @(posedge dut.clk_compute)if(!dut.reset_compute && dut.ev_valid_c && dut.ev_ready_c)begin
   if($realtime-accepted_at<queue_min)queue_min=$realtime-accepted_at;
   if($realtime-accepted_at>queue_max)queue_max=$realtime-accepted_at;
   queued_events=queued_events+1;
 end
 always @(posedge dut.clk_compute) begin
   if(dut.reset_compute) begin gain=4096;w=64;pending=0;expected_clips=0;frame_cycle=0; end
   else begin
     if(bend_check && dut.cfg_valid && dut.cfg_ready && dut.cfg_retrigger)
       $fatal(1,"held-note bend retriggered an envelope");
     if(dut.tick_compute) frame_cycle=0; else frame_cycle=frame_cycle+1;
     if(dut.u_core.sums_valid) begin
       if(pending)$fatal(1,"overlapping master transaction");
       if(w<255)w=w+1;
       target=dut.mute_c ? 0 : !dut.pressure_enable_c ? 4096 :
         dut.pressure_level_c<=128 ? 1024 : dut.pressure_level_c>=3200 ? 4096 : dut.pressure_level_c+896;
       target=(target*dut.volume_gain_c)>>8;
       if(target>4096)target=4096;
       if(target>gain+32)gain=gain+32;else if(target<gain-32)gain=gain-32;else gain=target;
       a=$signed(dut.u_core.sine_total);b=$signed(dut.u_core.bright_total);
       num=a*(255-w)+b*w+4096; base=num>>>13;
       expected=(base*gain+2048)>>>12;
       if(expected>8388607)begin expected=8388607;expected_clips=expected_clips+1;end
       if(expected< -8388608)begin expected=-8388608;expected_clips=expected_clips+1;end
       expected_sample=expected[23:0];pending=1;
       if(dut.pressure_enable_c && dut.pressure_level_c<600)low_pressure_frames=low_pressure_frames+1;
     end
     if(valid) begin
       if(!pending || audio!==expected_sample || clips!==expected_clips)
         $fatal(1,"audio reference mismatch frame=%0d got=%0d expected=%0d gain=%0d clips=%0d/%0d",checked,audio,expected_sample,gain,clips,expected_clips);
       if(frame_cycle>max_tail)max_tail=frame_cycle;
       if(frame_cycle>1152)$fatal(1,"less than 25 percent frame headroom: %0d/1536",frame_cycle);
       pending=0;checked=checked+1;
       if(audio==0)zeros=zeros+1;else nonzeros=nonzeros+1;
     end
   end
 end
 always @(negedge lrck)begin sent_previous=sent_current;sent_current=dut.left_audio;end
 always @(posedge decoded)begin
   #1;frames=frames+1;
   if(frames>4 && (dl!==dr || dl!==sent_previous || ^dl===1'bx))$fatal(1,"pin-level I2S frame mismatch");
   if(first_event>0 && first_pin==0 && dl!=0)first_pin=$realtime;
 end
 task wait_frames;input integer n;integer j;begin
   for(j=0;j<n;j=j+1)@(posedge decoded);@(negedge clk);
 end endtask
 task event_send;input on;input [6:0] n;begin
   while(!ready)@(negedge clk);
   @(negedge clk);ev_valid=1;ev_on=on;note=n;
   @(negedge clk);ev_valid=0;
 end endtask
 task check_zero;integer j;begin
   for(j=0;j<16;j=j+1)begin @(posedge decoded);#2;
     if(dl!==0 || dr!==0)$fatal(1,"digital silence not exact: %0d %0d",dl,dr);
   end
 end endtask
 integer i;
 initial begin
   repeat(20)@(negedge clk);reset=0;wait(initialized);wait_frames(8);
   first_event=$realtime;event_send(1,60);wait_frames(6);
   if(first_pin==0 || first_pin-first_event>4*20833.334)$fatal(1,"single event pin latency %0f",first_pin-first_event);
   $display("METRIC single_event_to_first_nonzero_i2s_us=%.3f (fast attack, no UART or external queue)",(first_pin-first_event)/1000.0);
   event_send(0,60);wait_frames(4);
   burst_start=$realtime;
   for(i=0;i<32;i=i+1)event_send(1,36+i);
   wait(active==32);burst_done=$realtime;
   if(burst_done-burst_start>1000000)$fatal(1,"32-event burst allocation exceeded 1ms");
   wait_frames(6);
   $display("METRIC burst32_allocation_us=%.3f burst32_to_i2s_upper_us=%.3f",(burst_done-burst_start)/1000.0,($realtime-burst_start)/1000.0);
   if(clips!=0)$fatal(1,"maximum velocity 32 notes unexpectedly clipped");
   volume=0;wait_frames(240);check_zero;
   if(dut.volume_gain_c!==0)$fatal(1,"volume did not settle");
   volume=100;wait_frames(240);
   pressure_enable=1;pressure=128;wait_frames(600);
   if(low_pressure_frames<10)$fatal(1,"low pressure gain not exercised");
   pressure=3200;wait_frames(600);
   mute=1;wait_frames(160);check_zero;
   mute=0;wait_frames(160);
   bend_check=1;bend=4095;wait_frames(80);bend_check=0;
   if(dut.bend_ratio_c<72000)$fatal(1,"bend did not reach live engine");
   if(checked<1900 || zeros<100 || nonzeros<100)$fatal(1,"insufficient audio coverage");
   $display("METRIC checked=%0d exact_zero_frames=%0d nonzero_frames=%0d max_frame_tail=%0d/1536 clips=%0d",checked,zeros,nonzeros,max_tail,clips);
   $display("METRIC accepted_to_scheduler_us_min=%.3f max=%.3f count=%0d UART=not_in_core Attack=65535_per_frame_test_only",queue_min/1000.0,queue_max/1000.0,queued_events);
   // Reset under active control/event traffic; PLL and bridge must restart cleanly.
   @(negedge clk);reset=1;volume=100;mute=0;bend=2048;pressure_enable=0;
   repeat(20)@(negedge clk);sent_previous=0;sent_current=0;frames=0;reset=0;
   wait(initialized);wait_frames(8);
   if(active!=0)$fatal(1,"reset left active voices");
   event_send(1,72);wait_frames(8);
   if(active!=1)$fatal(1,"post-reset event lost");
   $display("PASS tb_ram32_engine_audio: real ROM engine, independent arithmetic, 32 notes, pressure/volume/mute/bend, exact silence, I2S latency, reset");$finish;
 end
 initial begin #65000000;$fatal(1,"engine audio timeout");end
endmodule
