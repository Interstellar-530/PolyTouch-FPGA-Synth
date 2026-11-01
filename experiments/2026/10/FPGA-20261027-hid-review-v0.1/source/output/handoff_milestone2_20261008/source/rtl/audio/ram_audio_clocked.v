// PLL compute clock and direct-reference I2S clock, with a held-sample bridge.
// All configuration/control inputs belong to clk_compute/reset_compute.
module ram_audio_clocked #(parameter integer VOICES=64)(
 input wire clk_ref,reset,
 output wire clk_compute,reset_compute,locked,
 input wire cfg_valid,output wire cfg_ready,input wire[5:0]cfg_voice,
 input wire[31:0]cfg_increment,input wire[15:0]cfg_envelope,input wire[6:0]cfg_velocity,input wire cfg_retrigger,
 input wire[7:0]mix_weight,input wire pressure_enable,input wire[11:0]pressure_level,input wire mute,
 output wire i2s_bck,i2s_lrck,i2s_din,dac_xsmt,output wire initialized,
 output wire signed[23:0]audio_sample,output wire sample_valid,output wire[31:0]clip_count
);
 wire reset_audio,tick_audio,tick_compute,valid_compute;
 wire signed[23:0]sample_compute;
 audio_pll_clock u_clock(clk_ref,reset,clk_compute,locked,reset_compute,reset_audio);
 audio_frame_bridge u_bridge(clk_ref,reset_audio,tick_audio,clk_compute,reset_compute,
  tick_compute,sample_compute,valid_compute,audio_sample,sample_valid);
 ram_audio_compute #(.VOICES(VOICES),.FRAME_CYCLES(1024)) u_compute(
  .clk(clk_compute),.rst(reset_compute),.sample_tick(tick_compute),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),
  .cfg_voice(cfg_voice),.cfg_increment(cfg_increment),.cfg_envelope(cfg_envelope),.cfg_velocity(cfg_velocity),.cfg_retrigger(cfg_retrigger),
  .mix_weight(mix_weight),.pressure_enable(pressure_enable),.pressure_level(pressure_level),.mute(mute),
  .audio_sample(sample_compute),.sample_valid(valid_compute),.clip_count(clip_count),.initialized(initialized),
  .sine_total(),.bright_total(),.sums_valid(),.master_req(),.master_ready());
 i2s_tx #(.CLK_HZ(12288000),.SAMPLE_RATE_HZ(48000),.DATA_BITS(24)) u_i2s(
  .clk(clk_ref),.rst(reset_audio),.sample_l(audio_sample),.sample_r(audio_sample),
  .bck(i2s_bck),.lrck(i2s_lrck),.din(i2s_din),.sample_tick(tick_audio));
 assign dac_xsmt=!reset_audio;
endmodule
