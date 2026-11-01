`timescale 1ns/1ps
module bridge_phase_case #(parameter integer PHASE=0)(
 input wire clk_audio,reset,tick_audio,output integer received=0,output real worst_ns=0
);
 reg fast=0;initial begin #(PHASE*1.2);forever #10.1725 fast=~fast;end
 wire tick_fast,valid_audio;reg valid_fast=0;reg signed[23:0]sample_fast=0;wire signed[23:0]sample_audio;
 audio_frame_bridge dut(clk_audio,reset,tick_audio,fast,reset,tick_fast,sample_fast,valid_fast,sample_audio,valid_audio);
 integer sent=0,generated=0,delay_count=0;reg[23:0]pending_sample;
 real start_time[0:512];real latency;real published_at=0;real previous_publish=0;
 function[23:0]pattern;input integer n;begin pattern=(24'h5a1234^(n*24'h010051))+PHASE;end endfunction
 always @(posedge clk_audio or posedge reset)begin
  if(reset)sent=0;else if(tick_audio)begin sent=sent+1;start_time[sent]=$realtime;end
 end
 always @(posedge fast or posedge reset)begin
  if(reset)begin valid_fast<=0;generated<=0;delay_count<=0;sample_fast<=0;pending_sample<=0;end
  else begin
   valid_fast<=0;
   if(tick_fast)begin
    if(delay_count!=0)$fatal(1,"synthetic producer overlapped requests");
    generated<=generated+1;pending_sample<=pattern(generated+1);
    delay_count<=1+((generated*73+PHASE*17)%900);
   end else if(delay_count>1)delay_count<=delay_count-1;
   else if(delay_count==1)begin sample_fast<=pending_sample;valid_fast<=1;delay_count<=0;end
  end
 end
 always @(posedge reset)begin received=0;worst_ns=0;end
 always @(posedge fast or posedge reset)begin
  if(reset)begin published_at=0;previous_publish=0;end
  else if(valid_fast)begin
   if(previous_publish!=0 && $realtime-previous_publish<2000)
    $fatal(1,"source sample overwritten before bundled transfer can finish");
   published_at=$realtime;previous_publish=$realtime;
  end
 end
 always @(posedge valid_audio)begin
  #1;received=received+1;
  if($realtime-published_at<162.7)
   $fatal(1,"bundled bus captured before two full reference periods phase=%0d age=%f",PHASE,$realtime-published_at);
  if(received>sent || sample_audio!==pattern(received))$fatal(1,"bridge loss/duplication/tearing phase=%0d received=%0d sent=%0d actual=%h",PHASE,received,sent,sample_audio);
  latency=$realtime-start_time[received];if(latency>worst_ns)worst_ns=latency;
  if(latency>20000)$fatal(1,"bridge producer/transfer missed frame phase=%0d latency=%f",PHASE,latency);
 end
endmodule
module tb_audio_frame_bridge;
 reg clk=0;always #40.690104 clk=~clk;
 reg rst=1,tick=0;integer divider=0,i;integer count[0:15];wire real worst[0:15];
 generate for(genvar g=0;g<16;g=g+1)begin:phase
  bridge_phase_case #(g) test(clk,rst,tick,count[g],worst[g]);
 end endgenerate
 always @(posedge clk)begin
  if(rst)begin divider<=0;tick<=0;end
  else if(divider==255)begin divider<=0;tick<=1;end
  else begin divider<=divider+1;tick<=0;end
 end
 initial begin
  repeat(5)@(negedge clk);rst=0;
  repeat(64)@(posedge tick);#173;rst=1;
  repeat(5)@(negedge clk);rst=0;
  repeat(128)@(posedge tick);#20500;
  for(i=0;i<16;i=i+1)begin
   if(count[i]!=128)$fatal(1,"bridge completion count phase=%0d count=%0d",i,count[i]);
   $display("METRIC bridge phase=%0d samples=%0d worst_producer_and_transfer_ns=%.3f",i,count[i],worst[i]);
  end
  $display("PASS tb_audio_frame_bridge:16 phases, variable1..900-cycle computation, atomic24-bit samples, reset during pending frame");$finish;
 end
 initial begin #5000000;$fatal(1,"bridge timeout");end
endmodule
