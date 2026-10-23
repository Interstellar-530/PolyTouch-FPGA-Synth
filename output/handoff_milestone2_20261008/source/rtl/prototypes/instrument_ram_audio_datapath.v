// Compute/I2S prototype with externally supplied envelopes and bent increments.
// Event ownership, ADSR/transition state and PLL are added by a board wrapper.
module instrument_ram_audio_datapath #(
 parameter integer VOICES=8,
 parameter integer CLK_HZ=VOICES==8?12288000:49152000,
 parameter integer FS_HZ=48000
)(
 input wire clk,rst,input wire cfg_valid,output wire cfg_ready,
 input wire[5:0]cfg_voice,input wire[31:0]cfg_increment,input wire[15:0]cfg_envelope,
 input wire[6:0]cfg_velocity,input wire cfg_retrigger,input wire[23:0]cfg_param,input wire[2:0]cfg_mask,
 input wire[7:0]mix_weight,input wire pressure_enable,input wire[11:0]pressure_level,input wire mute,
 input wire[8:0]volume_gain_q8,
 output wire i2s_bck,i2s_lrck,i2s_din,output wire sample_tick,
 output wire signed[23:0]audio_sample,output wire sample_valid,
 output wire[31:0]clip_count,output wire initialized
);
 wire signed[31:0]sine_total,bright_total;wire sums_valid,master_req;wire[0:0]aux_ready_v;
 instrument_ram_audio_compute #(.VOICES(VOICES),.FRAME_CYCLES(CLK_HZ/FS_HZ)) u_compute(
  .clk(clk),.rst(rst),.sample_tick(sample_tick),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),
  .cfg_voice(cfg_voice),.cfg_increment(cfg_increment),.cfg_envelope(cfg_envelope),.cfg_velocity(cfg_velocity),.cfg_retrigger(cfg_retrigger),.cfg_param(cfg_param),.cfg_mask(cfg_mask),
  .mix_weight(mix_weight),.pressure_enable(pressure_enable),.pressure_level(pressure_level),.mute(mute),.volume_gain_q8(volume_gain_q8),
  .audio_sample(audio_sample),.sample_valid(sample_valid),.clip_count(clip_count),.initialized(initialized),
  .sine_total(sine_total),.bright_total(bright_total),.sums_valid(sums_valid),.master_req(master_req),.master_ready(aux_ready_v[0]));
 i2s_tx #(.CLK_HZ(CLK_HZ),.SAMPLE_RATE_HZ(FS_HZ),.DATA_BITS(24)) u_i2s(
  .clk(clk),.rst(rst),.sample_l(audio_sample),.sample_r(audio_sample),
  .bck(i2s_bck),.lrck(i2s_lrck),.din(i2s_din),.sample_tick(sample_tick));
endmodule
