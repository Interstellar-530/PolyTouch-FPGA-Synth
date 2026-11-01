`timescale 1ns/1ps
// Checks the three static rPLL build profiles used by the clock shell:
// MULT=4 -> 49.152 MHz, MULT=6 -> 73.728 MHz, MULT=8 -> 98.304 MHz.
module tb_audio_pll_mult;
 GSR GSR(.GSRI(1'b1));
 reg clk_ref=0;
 always #40.690104 clk_ref=~clk_ref;   // 12.288 MHz
 reg reset=1;
 wire c4,l4,rc4,ra4,c6,l6,rc6,ra6,c8,l8,rc8,ra8;
 audio_pll_clock #(.MULT(4)) u4(clk_ref,reset,c4,l4,rc4,ra4);
 audio_pll_clock #(.MULT(6)) u6(clk_ref,reset,c6,l6,rc6,ra6);
 audio_pll_clock #(.MULT(8)) u8(clk_ref,reset,c8,l8,rc8,ra8);

 integer e4=0,e6=0,e8=0;
 always @(posedge c4) e4=e4+1;
 always @(posedge c6) e6=e6+1;
 always @(posedge c8) e8=e8+1;
 always @(negedge rc4) if(c4!==1'b1 || !l4) $fatal(1,"mult4 compute reset release invalid");
 always @(negedge rc6) if(c6!==1'b1 || !l6) $fatal(1,"mult6 compute reset release invalid");
 always @(negedge rc8) if(c8!==1'b1 || !l8) $fatal(1,"mult8 compute reset release invalid");

 task measure;
  input integer mult;
  input real expected_ns;
  input real tol_ns;
  input integer edges;
  realtime t0,t1,period;
  integer e0;
  begin
   @(posedge clk_ref); #1; e0 = (mult==4)?e4:(mult==6)?e6:e8;
   repeat(256) @(posedge clk_ref); #1;
   e0 = ((mult==4)?e4:(mult==6)?e6:e8) - e0;
   if (e0 < 256*mult-2 || e0 > 256*mult+2)
    $fatal(1,"mult%0d ratio invalid: %0d edges per 256 ref",mult,e0);
   if (mult==4) begin @(posedge c4); t0=$realtime; repeat(64) @(posedge c4); t1=$realtime; end
   else if (mult==6) begin @(posedge c6); t0=$realtime; repeat(64) @(posedge c6); t1=$realtime; end
   else begin @(posedge c8); t0=$realtime; repeat(64) @(posedge c8); t1=$realtime; end
   period=(t1-t0)/64.0;
   if (period < expected_ns-tol_ns || period > expected_ns+tol_ns)
    $fatal(1,"mult%0d period %f ns expected %f",mult,period,expected_ns);
   $display("METRIC mult%0d period_ns=%.6f fmax=%0.3fMHz ratio_edges=%0d",mult,period,1000.0/period,e0);
  end
 endtask

 initial begin
  repeat(40) @(negedge clk_ref); reset=0;
  wait(l4 && l6 && l8);
  wait(!rc4 && !rc6 && !rc8);
  measure(4,20.345052,0.05,4);
  measure(6,13.563368,0.05,6);
  measure(8,10.172526,0.05,8);
  $display("PASS tb_audio_pll_mult: 4x/6x/8x ratios, periods and domain reset release");
  $finish;
 end
 initial begin #4000000; $fatal(1,"PLL mult test timeout"); end
endmodule
