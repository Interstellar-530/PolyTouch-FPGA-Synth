// 32-voice complete-propotype top: event/ADSR scheduler -> RAM wavetable core
// -> wide master -> I2S. 49.152 MHz / 48 kHz gives 1024 clocks per frame; the
// core renders 32 voices in 27*32 = 864 clocks and leaves the rest of the frame
// for configuration writes and the master multiply.
module ram32_top #(
    parameter integer VOICES = 32,
    parameter [15:0] ATTACK_STEP   = 16'd140,
    parameter [15:0] DECAY_STEP    = 16'd16,
    parameter [15:0] RELEASE_STEP  = 16'd48,
    parameter [15:0] SUSTAIN_LEVEL = 16'd45875
)(
    input  wire        clk,
    input  wire        rst,
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
    output wire        tick,
    output wire        initialized
);
    wire        cfg_valid, cfg_ready, cfg_retrigger;
    wire [5:0]  cfg_voice;
    wire [31:0] cfg_increment;
    wire [15:0] cfg_envelope;
    wire [6:0]  cfg_velocity;
    wire [23:0] cfg_param;
    wire [2:0]  cfg_mask;

    instrument_ram_audio_datapath #(.VOICES(VOICES), .CLK_HZ(49152000), .FS_HZ(48000)) u_dp (
        .clk(clk), .rst(rst),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready), .cfg_voice(cfg_voice),
        .cfg_increment(cfg_increment), .cfg_envelope(cfg_envelope),
        .cfg_velocity(cfg_velocity), .cfg_retrigger(cfg_retrigger), .cfg_param(cfg_param), .cfg_mask(cfg_mask),
        .mix_weight(8'hff), .pressure_enable(1'b0), .pressure_level(12'd0), .mute(1'b0),
        // 旧原型保持原接线：主音量固定单位增益（Q8 256），控制能力只在 ram32_clocked_top。
        .volume_gain_q8(9'd256),
        .i2s_bck(i2s_bck), .i2s_lrck(i2s_lrck), .i2s_din(i2s_din),
        .sample_tick(tick), .audio_sample(audio_sample), .sample_valid(sample_valid),
        .clip_count(clip_count), .initialized(initialized)
    );

    voice_sched32 #(.VOICES(VOICES), .ATTACK_STEP(ATTACK_STEP),
                    .DECAY_STEP(DECAY_STEP), .RELEASE_STEP(RELEASE_STEP),
                    .SUSTAIN_LEVEL(SUSTAIN_LEVEL), .FS_HZ(48000)) u_sched (
        .clk(clk), .rst(rst), .sample_tick(tick),
        .instrument(instrument), .piano_tone({1'b0, piano_tone}),
        .ev_valid(ev_valid), .ev_on(ev_on), .ev_note(ev_note), .ev_vel(ev_vel),
        .ev_ready(ev_ready),
        .cfg_voice(cfg_voice), .cfg_increment(cfg_increment),
        .cfg_envelope(cfg_envelope), .cfg_velocity(cfg_velocity),
        .cfg_retrigger(cfg_retrigger), .cfg_param(cfg_param), .cfg_mask(cfg_mask), .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .active_count(active_count), .bend_ratio(17'd65536)
    );
endmodule
