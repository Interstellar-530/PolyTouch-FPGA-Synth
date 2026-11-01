`timescale 1ns/1ps
module tb_audio_pll_clock;
 GSR GSR(.GSRI(1'b1));
 reg clk_ref=0;always #40.690104 clk_ref=~clk_ref;
 reg reset=1;wire clk_compute,locked,reset_compute,reset_audio;
 audio_pll_clock dut(clk_ref,reset,clk_compute,locked,reset_compute,reset_audio);
 integer compute_edges=0,start_edges,delta,pass=0;realtime first,last,lock_start,lock_us;
 always @(posedge clk_compute)compute_edges=compute_edges+1;
 always @(negedge reset_compute)if(clk_compute!==1'b1 || !locked)$fatal(1,"compute reset release was not synchronous/locked");
 always @(negedge reset_audio)if(clk_ref!==1'b1 || !locked)$fatal(1,"audio reset release was not synchronous/locked");
 task check_clock;begin
  lock_start=$realtime;wait(locked);lock_us=($realtime-lock_start)/1000;
  if(lock_us>1100)$fatal(1,"PLL lock exceeded datasheet bound");
  wait(!reset_compute && !reset_audio);
  @(posedge clk_compute);first=$realtime;repeat(256)@(posedge clk_compute);last=$realtime;
  if((last-first)/256<20.33 || (last-first)/256>20.36)$fatal(1,"PLL period invalid %f",(last-first)/256);
  @(posedge clk_ref);#1;start_edges=compute_edges;repeat(256)@(posedge clk_ref);#1;delta=compute_edges-start_edges;
  if(delta<1023 || delta>1025)$fatal(1,"PLL ratio invalid %0d",delta);
  $display("METRIC PLL period_ns=%.6f edges_per256ref=%0d model_lock_us=%.3f",(last-first)/256,delta,lock_us);pass=pass+1;
 end endtask
 initial begin
  repeat(20)@(negedge clk_ref);reset=0;check_clock();
  @(negedge clk_ref);reset=1;#1;
  if(!reset_compute || !reset_audio)$fatal(1,"PLL domain reset did not assert");
  repeat(20)@(negedge clk_ref);reset=0;check_clock();
  $display("PASS tb_audio_pll_clock: vendor rPLL4x, startup reset, lock, domain reset release, reset/relock, passes=%0d",pass);$finish;
 end
 initial begin #3000000;$fatal(1,"PLL timeout");end
endmodule
