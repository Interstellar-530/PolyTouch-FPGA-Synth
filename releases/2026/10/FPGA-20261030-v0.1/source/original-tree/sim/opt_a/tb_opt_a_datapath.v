`timescale 1ns/1ps
// A1 datapath bench: 32 voices through the real ROM models against the
// independent 64-bit reference in tools/offline_opt/a/ref_engine.py.
//
// The include files carry both the stimulus (one configuration transaction per
// voice per frame that changes something) and the expected values, all
// generated from the reference model.  Any arithmetic change that is not
// bit-exact for this stimulus fails here with $fatal.
//
// Coverage: 32 independent voices, full and zero envelope/velocity extremes,
// every reachable e-piano table pair, guitar banks (weight 0), silent voices,
// pressure gain, zero volume, mute, 192 warm-up frames whose output must be
// exactly zero, and a second scenario that keeps every voice deliberately
// silent while the controls move.
module tb_opt_a_datapath;
 localparam integer VOICES = 32;
 localparam integer FRAME_CYCLES = 768;
 reg clk = 0;
 always #6.781684 clk = ~clk;              // 73.728 MHz, production compute clock
 reg rst = 1;
 reg cfg_valid = 0;
 reg [5:0] cfg_voice = 0;
 reg [31:0] cfg_increment = 0;
 reg [15:0] cfg_envelope = 0;
 reg [6:0] cfg_velocity = 0;
 reg cfg_retrigger = 0;
 reg [23:0] cfg_param = 0;
 reg [2:0] cfg_mask = 0;
 reg [7:0] mix_weight = 8'hff;
 reg pressure_enable = 0;
 reg [11:0] pressure_level = 12'd3200;
 reg mute = 0;
 reg [8:0] volume_gain_q8 = 9'd256;
 reg sample_tick = 0;
 integer frame_phase = 0;

 wire cfg_ready, sample_valid, initialized, sums_valid, master_req, master_ready;
 wire signed [23:0] audio_sample;
 wire [31:0] clip_count;
 wire signed [31:0] sine_total, bright_total;

 always @(posedge clk) begin
  if (rst) begin
   sample_tick <= 0;
   frame_phase <= 0;
  end else if (frame_phase == FRAME_CYCLES - 1) begin
   sample_tick <= 1;
   frame_phase <= 0;
  end else begin
   sample_tick <= 0;
   frame_phase <= frame_phase + 1;
  end
 end

 instrument_ram_audio_compute #(.VOICES(VOICES), .FRAME_CYCLES(FRAME_CYCLES)) dut (
  .clk(clk), .rst(rst), .sample_tick(sample_tick),
  .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_voice(cfg_voice),
  .cfg_increment(cfg_increment), .cfg_envelope(cfg_envelope),
  .cfg_velocity(cfg_velocity), .cfg_retrigger(cfg_retrigger),
  .cfg_param(cfg_param), .cfg_mask(cfg_mask),
  .mix_weight(mix_weight), .pressure_enable(pressure_enable),
  .pressure_level(pressure_level), .mute(mute), .volume_gain_q8(volume_gain_q8),
  .audio_sample(audio_sample), .sample_valid(sample_valid), .clip_count(clip_count),
  .initialized(initialized), .sine_total(sine_total), .bright_total(bright_total),
  .sums_valid(sums_valid), .master_req(master_req), .master_ready(master_ready));

 integer DP_DATAPATH_FRAMES = 0;
 integer DP_SILENCE_FRAMES = 0;
 integer checked = 0;

 // ------------------------------------------------------------- stimulus ---
 task dp_frame_ctrl(input [7:0] weight, input pen, input [11:0] level,
                    input m, input [8:0] volume);
  begin
   @(negedge clk);
   mix_weight = weight; pressure_enable = pen; pressure_level = level;
   mute = m; volume_gain_q8 = volume;
  end
 endtask

 // cfg_ready is combinational on the voice FSM state and the registered
 // sample_tick, so its value at a negedge is the value the next posedge samples.
 task dp_cfg(input [5:0] vsel, input [31:0] inc, input [15:0] env, input [6:0] vel,
             input retrig, input [23:0] param, input [2:0] mask);
  begin
   @(negedge clk);
   cfg_valid = 1'b1; cfg_voice = vsel; cfg_increment = inc; cfg_envelope = env;
   cfg_velocity = vel; cfg_retrigger = retrig; cfg_param = param; cfg_mask = mask;
   while (cfg_ready !== 1'b1) @(negedge clk);
   @(negedge clk);                       // the posedge in between accepts it
   cfg_valid = 1'b0;
  end
 endtask

 task dp_check(input integer frame, input signed [31:0] exp_sine,
               input signed [31:0] exp_bright, input signed [23:0] exp_sample,
               input [7:0] exp_weight, input [12:0] exp_gain,
               input [12:0] exp_combined);
  integer guard;
  begin
   @(negedge clk);
   guard = 0;
   while (sample_valid !== 1'b1) begin
    @(negedge clk);
    guard = guard + 1;
    if (guard > 4 * FRAME_CYCLES) $fatal(1, "frame %0d never produced a sample", frame);
   end
   if (sine_total !== exp_sine || bright_total !== exp_bright ||
       audio_sample !== exp_sample) begin
    $display("FATAL frame %0d sine %0d/%0d bright %0d/%0d sample %0d/%0d",
             frame, sine_total, exp_sine, bright_total, exp_bright,
             audio_sample, exp_sample);
    $fatal(1, "A1 datapath mismatch against the bit-exact reference");
   end
   if (dut.u_master.frame_weight !== exp_weight ||
       dut.u_master.frame_gain !== exp_gain ||
       dut.u_master.combined_gain !== exp_combined) begin
    $display("FATAL frame %0d weight %0d/%0d gain %0d/%0d combined %0d/%0d",
             frame, dut.u_master.frame_weight, exp_weight,
             dut.u_master.frame_gain, exp_gain,
             dut.u_master.combined_gain, exp_combined);
    $fatal(1, "A1 master state mismatch");
   end
   if (clip_count !== 0)
    $fatal(1, "frame %0d unexpected clip count %0d", frame, clip_count);
   checked = checked + 1;
  end
 endtask

 initial begin
  repeat (4) @(negedge clk);
  rst = 1;
  repeat (4) @(negedge clk);
  rst = 0;
  wait (initialized === 1'b1);
  repeat (2) @(negedge clk);
  `include "sim/opt_a/vectors_datapath.vh"
  `include "sim/opt_a/vectors_silence.vh"
  if (checked !== DP_DATAPATH_FRAMES + DP_SILENCE_FRAMES)
   $fatal(1, "checked %0d of %0d frames", checked,
          DP_DATAPATH_FRAMES + DP_SILENCE_FRAMES);
  $display("METRIC a1_datapath bit_exact_frames=%0d voices=%0d", checked, VOICES);
  $display("PASS tb_opt_a_datapath: 32 voices, bit-exact vs 64-bit reference, exact digital silence");
  $finish;
 end

 initial begin
  #400000000;
  $fatal(1, "tb_opt_a_datapath timeout");
 end
endmodule
