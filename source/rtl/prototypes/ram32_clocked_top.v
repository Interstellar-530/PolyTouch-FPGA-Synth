// Dual-clock 32-voice prototype: 12.288 MHz audio reference (I2S + frame edge)
// and an rPLL compute domain (scheduler, RAM engine, wide master). Events and
// slow controls cross through a four-phase handshake / two-flop synchronizers.
// MULT=4 keeps 49.152 MHz; MULT=6/8 select 73.728/98.304 MHz build profiles.
module ram32_clocked_top #(
 parameter integer MULT=4,
 parameter integer VOICES=32,
 parameter [15:0] ATTACK_STEP   = 16'd140,
 parameter [15:0] DECAY_STEP    = 16'd16,
 parameter [15:0] RELEASE_STEP  = 16'd48,
 parameter [15:0] SUSTAIN_LEVEL = 16'd45875
)(
 input  wire        clk_ref,
 input  wire        reset,
 input  wire        instrument,
 input  wire [2:0]  piano_tone,
 // 生产控制输入（ref 域，准静态）：主音量、静音、压力开关、FSR 与弯音 ADC。
 input  wire [6:0]  volume_target,
 input  wire        mute,
 input  wire        pressure_enable,
 input  wire [11:0] pressure_adc,
 input  wire [11:0] bend_adc,
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
 wire clk_compute,reset_compute,reset_audio;
 audio_pll_clock #(.MULT(MULT)) u_pll(
  .clk_ref(clk_ref),.reset(reset),.clk_compute(clk_compute),
  .locked(locked),.reset_compute(reset_compute),.reset_audio(reset_audio));

 wire tick_audio,tick_compute,valid_audio;
 wire signed [23:0] left_audio,right_audio;
 i2s_tx #(.CLK_HZ(12288000),.SAMPLE_RATE_HZ(48000),.DATA_BITS(24)) u_i2s(
  .clk(clk_ref),.rst(reset_audio),.sample_l(left_audio),.sample_r(right_audio),
  .bck(i2s_bck),.lrck(i2s_lrck),.din(i2s_din),.sample_tick(tick_audio));
 audio_frame_bridge_stereo u_bridge(
  .clk_audio(clk_ref),.reset_audio(reset_audio),.tick_audio(tick_audio),
  .clk_compute(clk_compute),.reset_compute(reset_compute),.tick_compute(tick_compute),
  .left_compute(audio_sample),.right_compute(audio_sample),.valid_compute(sample_valid),
  .left_audio(left_audio),.right_audio(right_audio),.valid_audio(valid_audio),
  .frame_id_audio(frame_id));

 // ------------------------------------- coherent slow-control bundle ---
 // 51 位控制束经四相握手整束快照跨域（见 ram32_control_front）：不再用"按位两拍
 // 一致"去假称多位原子。压力/弯音的滤波、映射与 Q16 比率复用生产 pressure_bend，
 // 主音量斜坡与曲线复用 top.v 的同一条表。
 wire instrument_c;
 wire [2:0] piano_tone_c;
 wire [8:0] volume_gain_c;
 wire [6:0] volume_c;
 wire mute_c;
 wire pressure_enable_c;
 wire [11:0] pressure_level_c;
 wire [16:0] bend_ratio_c;
 ram32_control_front #(.CLK_REF_HZ(12288000)) u_ctrl (
  .clk_ref(clk_ref), .reset_ref(reset_audio),
  .clk_compute(clk_compute), .reset_compute(reset_compute),
  .instrument(instrument), .piano_tone(piano_tone), .volume_target(volume_target),
  .mute(mute), .pressure_enable(pressure_enable),
  .pressure_adc(pressure_adc), .bend_adc(bend_adc), .frame_tick(tick_audio),
  .instrument_c(instrument_c), .piano_tone_c(piano_tone_c),
  .volume_gain_c(volume_gain_c), .volume_c(volume_c),
  .mute_c(mute_c), .pressure_enable_c(pressure_enable_c),
  .pressure_level_c(pressure_level_c), .bend_ratio_c(bend_ratio_c),
  .control_busy()
 );

 // ------------------------------------------------- event handshake (4-phase) ---
 wire ev_ready_c;
 reg ev_req=0,ev_busy=0;
 reg [15:0] ev_hold=0;
 (* ASYNC_REG="TRUE" *) reg ev_ack_meta=0,ev_ack_sync=0;
 reg ev_ack_seen=0;
 always @(posedge clk_ref or posedge reset_audio)begin
  if(reset_audio)begin
   ev_req<=0;ev_busy<=0;ev_hold<=0;ev_ack_meta<=0;ev_ack_sync<=0;ev_ack_seen<=0;
  end else begin
   ev_ack_meta<=ev_ack;ev_ack_sync<=ev_ack_meta;ev_ack_seen<=ev_ack_sync;
   if(ev_ack_sync^ev_ack_seen)ev_busy<=0;
   if(ev_valid && !ev_busy)begin
    ev_hold<={ev_on,ev_note,ev_vel};ev_req<=!ev_req;ev_busy<=1;
   end
  end
 end
 assign ev_ready=!ev_busy;

 (* ASYNC_REG="TRUE" *) reg ev_req_meta=0,ev_req_sync=0;
 reg ev_req_seen=0;
 reg ev_ack=0,ev_pending=0;
 reg [15:0] ev_hold_c=0;
 always @(posedge clk_compute or posedge reset_compute)begin
  if(reset_compute)begin
   ev_req_meta<=0;ev_req_sync<=0;ev_req_seen<=0;ev_ack<=0;ev_pending<=0;ev_hold_c<=0;
  end else begin
   ev_req_meta<=ev_req;ev_req_sync<=ev_req_meta;ev_req_seen<=ev_req_sync;
   if(ev_req_sync^ev_req_seen)begin ev_hold_c<=ev_hold;ev_pending<=1;end
   if(ev_pending && ev_ready_c)begin ev_pending<=0;ev_ack<=!ev_ack;end
  end
 end
 wire ev_valid_c=ev_pending;
 wire ev_on_c=ev_hold_c[15];
 wire [6:0] ev_note_c=ev_hold_c[14:8];
 wire [7:0] ev_vel_c=ev_hold_c[7:0];

 // ------------------------------------------------- compute domain ---
 wire cfg_valid,cfg_ready,cfg_retrigger;
 wire [5:0] cfg_voice;
 wire [31:0] cfg_increment;
 wire [15:0] cfg_envelope;
 wire [6:0] cfg_velocity;
 wire [23:0] cfg_param;
 wire [2:0] cfg_mask;
 instrument_ram_audio_compute #(.VOICES(VOICES),.FRAME_CYCLES(256*MULT)) u_core(
  .clk(clk_compute),.rst(reset_compute),.sample_tick(tick_compute),
  .cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_voice(cfg_voice),
  .cfg_increment(cfg_increment),.cfg_envelope(cfg_envelope),
  .cfg_velocity(cfg_velocity),.cfg_retrigger(cfg_retrigger),
  .cfg_param(cfg_param),.cfg_mask(cfg_mask),
  .mix_weight(8'hff),.pressure_enable(pressure_enable_c),.pressure_level(pressure_level_c),.mute(mute_c),
  .volume_gain_q8(volume_gain_c),
  .audio_sample(audio_sample),.sample_valid(sample_valid),
  .clip_count(clip_count),.initialized(initialized),
  .sine_total(),.bright_total(),.sums_valid(),.master_req(),.master_ready());
 voice_sched32 #(.VOICES(VOICES),.ATTACK_STEP(ATTACK_STEP),.DECAY_STEP(DECAY_STEP),
                 .RELEASE_STEP(RELEASE_STEP),.SUSTAIN_LEVEL(SUSTAIN_LEVEL),.FS_HZ(48000)) u_sched(
  .clk(clk_compute),.rst(reset_compute),.sample_tick(tick_compute),
  .instrument(instrument_c),.piano_tone(piano_tone_c),
  .ev_valid(ev_valid_c),.ev_on(ev_on_c),.ev_note(ev_note_c),.ev_vel(ev_vel_c),
  .ev_ready(ev_ready_c),
  .cfg_voice(cfg_voice),.cfg_increment(cfg_increment),.cfg_envelope(cfg_envelope),
  .cfg_velocity(cfg_velocity),.cfg_retrigger(cfg_retrigger),.cfg_param(cfg_param),
  .cfg_mask(cfg_mask),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),
  .active_count(active_count),.bend_ratio(bend_ratio_c));
endmodule
