// Timing/self-test wrapper only. This is not the production instrument top.
// Uses existing oscillator/reset/button/I2S/LED pins; never auto-programmed.
module ram_audio_pll_probe(
 input wire clk_12m288,key_rst,key_s1,
 output wire i2s_bck,i2s_lrck,i2s_din,dac_xsmt,led
);
 wire compute_clk,compute_reset,locked,ready,initialized;
 reg[5:0]voice_id=0;reg configured=0;
 reg button_meta=1,button_sync=1;
 wire[6:0]note=7'd48+{1'b0,voice_id};wire[31:0]inc,clips;
 note_phase_inc #(.FS_HZ(48000)) frequency(note,inc);
 always @(posedge compute_clk or posedge compute_reset)begin
  if(compute_reset)begin voice_id<=0;configured<=0;button_meta<=1;button_sync<=1;end
  else begin
   button_meta<=key_s1;button_sync<=button_meta;
   if(!configured && ready)begin
    if(voice_id==63)configured<=1;else voice_id<=voice_id+6'd1;
   end
  end
 end
 ram_audio_clocked #(.VOICES(64)) u_audio(
  .clk_ref(clk_12m288),.reset(!key_rst),.clk_compute(compute_clk),.reset_compute(compute_reset),.locked(locked),
  .cfg_valid(!configured),.cfg_ready(ready),.cfg_voice(voice_id),.cfg_increment(inc),
  .cfg_envelope(16'd65535),.cfg_velocity(7'd100),.cfg_retrigger(1'b1),
  .mix_weight(8'd128),.pressure_enable(1'b0),.pressure_level(12'd0),.mute(!button_sync),
  .i2s_bck(i2s_bck),.i2s_lrck(i2s_lrck),.i2s_din(i2s_din),.dac_xsmt(dac_xsmt),
  .initialized(initialized),.audio_sample(),.sample_valid(),.clip_count(clips));
 assign led=compute_reset || !configured || (|clips);
endmodule
