// Static 73.728 MHz build wrapper for the dual-clock 32-voice prototype.
module ram32_clocked_wrap(
 input  wire        clk_ref,
 input  wire        reset,
 input  wire        instrument,
 input  wire [1:0]  piano_tone,
 input  wire        ev_valid,
 input  wire        ev_on,
 input  wire [6:0]  ev_note,
 input  wire [7:0]  ev_vel,
 output wire        ev_ready,
 output wire        i2s_bck,
 output wire        i2s_lrck,
 output wire        i2s_din,
 output wire signed [23:0] audio_sample,
 output wire        sample_valid,
 output wire [5:0]  active_count,
 output wire [31:0] clip_count,
 output wire        locked,
 output wire        initialized,
 output wire [7:0]  frame_id
);
 ram32_clocked_top #(.MULT(6)) u_top(
  .clk_ref(clk_ref),.reset(reset),
  .instrument(instrument),.piano_tone(piano_tone),
  .ev_valid(ev_valid),.ev_on(ev_on),.ev_note(ev_note),.ev_vel(ev_vel),
  .ev_ready(ev_ready),
  .i2s_bck(i2s_bck),.i2s_lrck(i2s_lrck),.i2s_din(i2s_din),
  .audio_sample(audio_sample),.sample_valid(sample_valid),
  .active_count(active_count),.clip_count(clip_count),.locked(locked),
  .initialized(initialized),.frame_id(frame_id));
endmodule
