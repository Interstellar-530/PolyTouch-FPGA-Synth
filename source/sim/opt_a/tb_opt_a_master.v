`timescale 1ns/1ps
// A1 master bench: wide_master alone, fed with the signed 32-bit lane totals at
// their extremes, against the same 64-bit reference used for the full datapath.
//
// Coverage: positive and negative full-scale sums, sign-mixed sums, zero sums
// with every gain/mute/volume combination, the +-1 LSB inputs that decide
// rounding, saturation on both rails with no wrap-around, the clip counter, the
// one-step-per-frame mix weight ramp and the +-32 Q12 gain ramp.
module tb_opt_a_master;
 localparam integer VOICE_SHIFT = 5;
 reg clk = 0;
 always #6.781684 clk = ~clk;
 reg rst = 1;
 reg update = 0;
 reg signed [31:0] sine_sum = 0;
 reg signed [31:0] bright_sum = 0;
 reg [7:0] mix_weight = 8'hff;
 reg pressure_enable = 0;
 reg [11:0] pressure_level = 12'd3200;
 reg mute = 0;
 reg [8:0] volume_gain_q8 = 9'd256;

 wire signed [23:0] sample_out;
 wire result_valid, busy, clip_event;
 wire [31:0] clip_count;
 wire mult_request;
 wire mult_ready;
 wire signed [32:0] mult_operand_a;
 wire signed [17:0] mult_operand_b;
 reg signed [50:0] product = 0;

 assign mult_ready = 1'b1;
 always @(posedge clk) begin
  if (rst) product <= 0;
  else if (mult_request) product <= mult_operand_a * mult_operand_b;
 end

 wide_master #(.VOICE_SHIFT(VOICE_SHIFT)) dut (
  .clk(clk), .rst(rst), .update(update), .sine_sum(sine_sum), .bright_sum(bright_sum),
  .mix_weight(mix_weight), .pressure_enable(pressure_enable),
  .pressure_level(pressure_level), .mute(mute), .volume_gain_q8(volume_gain_q8),
  .sample_out(sample_out), .result_valid(result_valid), .busy(busy),
  .clip_count(clip_count), .clip_event(clip_event),
  .mult_request(mult_request), .mult_ready(mult_ready),
  .mult_operand_a(mult_operand_a), .mult_operand_b(mult_operand_b),
  .mult_product(product));

 integer MA_FRAMES = 0;
 integer checked = 0;
 integer clipped_frames = 0;

 task ma_frame(input signed [31:0] sine, input signed [31:0] bright,
               input [7:0] weight, input pen, input [11:0] level, input m,
               input [8:0] volume);
  begin
   @(negedge clk);
   while (busy !== 1'b0) @(negedge clk);
   sine_sum = sine; bright_sum = bright; mix_weight = weight;
   pressure_enable = pen; pressure_level = level; mute = m; volume_gain_q8 = volume;
   update = 1'b1;
   @(negedge clk);
   update = 1'b0;
  end
 endtask

 task ma_check(input signed [23:0] exp_sample, input exp_clipped,
               input [7:0] exp_weight, input [12:0] exp_gain);
  integer guard;
  reg [31:0] clips_before;
  begin
   clips_before = clip_count;
   guard = 0;
   @(negedge clk);
   while (result_valid !== 1'b1) begin
    @(negedge clk);
    guard = guard + 1;
    if (guard > 256) $fatal(1, "wide_master never produced a result");
   end
   if (sample_out !== exp_sample) begin
    $display("FATAL master sample %0d expected %0d (sine %0d bright %0d)",
             sample_out, exp_sample, sine_sum, bright_sum);
    $fatal(1, "A1 master arithmetic mismatch");
   end
   if (dut.frame_weight !== exp_weight || dut.frame_gain !== exp_gain)
    $fatal(1, "master ramp mismatch weight %0d/%0d gain %0d/%0d",
           dut.frame_weight, exp_weight, dut.frame_gain, exp_gain);
   if ((clip_count - clips_before) !== (exp_clipped ? 32'd1 : 32'd0))
    $fatal(1, "clip counter mismatch: %0d vs expected %0d",
           clip_count - clips_before, exp_clipped);
   if (exp_clipped) clipped_frames = clipped_frames + 1;
   checked = checked + 1;
  end
 endtask

 initial begin
  repeat (4) @(negedge clk);
  rst = 0;
  repeat (2) @(negedge clk);
  `include "sim/opt_a/vectors_master.vh"
  if (checked < MA_FRAMES) $fatal(1, "master vector set incomplete");
  if (clipped_frames < 3) $fatal(1, "saturation not exercised");
  $display("METRIC a1_master bit_exact_frames=%0d clipped_frames=%0d", checked, clipped_frames);
  $display("PASS tb_opt_a_master: saturation without wrap, exact zero, gain and weight ramps");
  $finish;
 end

 initial begin
  #200000;
  $fatal(1, "tb_opt_a_master timeout");
 end
endmodule
