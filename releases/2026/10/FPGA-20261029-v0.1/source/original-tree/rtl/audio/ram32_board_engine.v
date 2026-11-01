// Board-clock integration of the validated RAM scheduler and 32-voice core.
// I2S and controls stay at 27 MHz; each 46.875 kHz frame gets 1152 compute clocks.
module ram32_board_engine(
    input wire clk_ref,rst,clear,sample_tick,
    input wire ev_valid,input wire [15:0] ev_word,output wire ev_ready,
    input wire [68:0] control_in,
    output wire signed [23:0] sample_out,
    output wire [63:0] ui_status,output wire ui_status_toggle,
    output wire [31:0] ui_voice_mask,
    output wire [255:0] ui_waveform,output wire [63:0] ui_spectrum,ui_lissajous,
    output wire ui_visual_toggle,output wire locked,initialized
);
    wire clk_compute,pll_reset_c;
    board_audio_clock u_clock(.clk_ref(clk_ref),.reset(rst),.clk_compute(clk_compute),
        .locked(locked),.reset_compute(pll_reset_c));
    // Panic/switch clears both sides of the event/frame handshakes. Async assert,
    // synchronous release in the faster domain; FIFO holds the first new note.
    wire reset_ref=rst || clear || !locked;
    reg [3:0] clear_pipe=4'hf;
    always @(posedge clk_compute or posedge reset_ref)
        if(reset_ref) clear_pipe<=4'hf; else clear_pipe<={clear_pipe[2:0],1'b0};
    wire reset_c=pll_reset_c || clear_pipe[3];
    wire [68:0] controls;
    control_bundle_cdc #(.WIDTH(69)) u_controls(
        .src_clk(clk_ref),.src_reset(reset_ref),.src_valid(1'b1),.src_data(control_in),.src_ready(),
        .dst_clk(clk_compute),.dst_reset(reset_c),.dst_valid(),.dst_data(controls),.dst_ready(1'b1));
    wire [11:0] pressure_c;
    wire [16:0] bend_c;
    wire [8:0] gain_c;
    wire [7:0] mix_c,timbre_c;
    wire instrument_c,mute_c,demo_c,piano_c,song_c,pause_c,show_c,pedal_c;
    wire [2:0] tone_c;
    wire [1:0] instrid_c,tempo_c;
    assign {pressure_c,bend_c,gain_c,mix_c,instrument_c,tone_c,mute_c,demo_c,piano_c,
            instrid_c,song_c,pause_c,show_c,tempo_c,timbre_c,pedal_c}=controls;
    wire event_c,event_ready_c;
    wire [15:0] word_c;
    control_bundle_cdc u_events(
        .src_clk(clk_ref),.src_reset(reset_ref),.src_valid(ev_valid),.src_data(ev_word),.src_ready(ev_ready),
        .dst_clk(clk_compute),.dst_reset(reset_c),.dst_valid(event_c),.dst_data(word_c),.dst_ready(event_ready_c));
    wire tick_c,sample_valid;
    wire signed [23:0] sample_c,right_unused;
    wire valid_audio;
    (* ASYNC_REG="TRUE" *) reg init_meta=0,init_sync=0;
    always @(posedge clk_ref or posedge reset_ref)
        if(reset_ref) begin init_meta<=0;init_sync<=0;end
        else begin init_meta<=initialized;init_sync<=init_meta;end
    wire [7:0] frame_id;
    audio_frame_bridge_stereo u_frames(
        .clk_audio(clk_ref),.reset_audio(reset_ref),.tick_audio(sample_tick && init_sync),
        .clk_compute(clk_compute),.reset_compute(reset_c),.tick_compute(tick_c),
        .left_compute(sample_c),.right_compute(sample_c),.valid_compute(sample_valid),
        .left_audio(sample_out),.right_audio(right_unused),.valid_audio(valid_audio),.frame_id_audio(frame_id));
    wire cfg_valid,cfg_ready,cfg_retrigger;
    wire [5:0] cfg_voice,active_count;
    wire [31:0] cfg_increment;
    wire [15:0] cfg_envelope;
    wire [6:0] cfg_velocity;
    wire [23:0] cfg_param;
    wire [2:0] cfg_mask;
    wire [31:0] voice_active;
    wire [223:0] voice_notes;
    wire [255:0] voice_velocities;
    voice_sched32 #(.VOICES(32),.FS_HZ(46875),.STAGE_STEP_SAMPLES(8192),
        .HIGH_NOTE_BALANCE(1)) u_sched(
        .clk(clk_compute),.rst(reset_c),.sample_tick(tick_c),
        .instrument(instrument_c),.piano_tone(tone_c),.bend_ratio(bend_c),
        .ev_valid(event_c),.ev_ready(event_ready_c),.ev_on(word_c[15]),.ev_note(word_c[14:8]),.ev_vel(word_c[7:0]),
        .cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_voice(cfg_voice),.cfg_increment(cfg_increment),
        .cfg_envelope(cfg_envelope),.cfg_velocity(cfg_velocity),.cfg_retrigger(cfg_retrigger),
        .cfg_param(cfg_param),.cfg_mask(cfg_mask),.active_count(active_count),
        .voice_active(voice_active),.voice_notes(voice_notes),.voice_velocities(voice_velocities));
    instrument_ram_audio_compute #(.VOICES(32),.FRAME_CYCLES(1152)) u_core(
        .clk(clk_compute),.rst(reset_c),.sample_tick(tick_c),
        .cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_voice(cfg_voice),.cfg_increment(cfg_increment),
        .cfg_envelope(cfg_envelope),.cfg_velocity(cfg_velocity),.cfg_retrigger(cfg_retrigger),
        .cfg_param(cfg_param),.cfg_mask(cfg_mask),.mix_weight(mix_c),
        .pressure_enable(1'b0),.pressure_level(pressure_c),.mute(mute_c),.volume_gain_q8(gain_c),
        .audio_sample(sample_c),.sample_valid(sample_valid),.initialized(initialized),
        .clip_count(),.sine_total(),.bright_total(),.sums_valid(),.master_req(),.master_ready());
    wire [63:0] status_c;
    wire [31:0] mask_c;
    wire status_toggle_c;
    ui_status_export #(.VOICES(32),.TICK_DIV(54000),.TRANSPORT_ENABLE(1)) u_status(
        .clk(clk_compute),.rst(reset_c),.v_gate(voice_active),.v_note(voice_notes),.v_vel(voice_velocities),
        .pressure_level(pressure_c),.demo_mode(demo_c),.muted(mute_c),.piano_mode(piano_c),.guitar_mode(instrument_c),
        .chord_set(song_c),.show_timbre(show_c),.instrument_id({pedal_c,instrid_c[0]}),.tempo_sel(tempo_c),
        .timbre_target(timbre_c),.piano_tone(tone_c),.paused(pause_c),
        .status(status_c),.active_mask(mask_c),.status_toggle(status_toggle_c));
    ui_status_sync #(.WIDTH(96)) u_status_ref(
        .clk(clk_ref),.rst(reset_ref),.async_status({mask_c,status_c}),.async_toggle(status_toggle_c),
        .status({ui_voice_mask,ui_status}),.toggle_seen(ui_status_toggle));
    wire [255:0] wave_c;
    wire [63:0] spectrum_c,phase_c;
    wire visual_toggle_c;
    ui_audio_visual_export #(.VOICES(32),.WAVE_HOLD_WINDOWS(4)) u_visual(
        .clk(clk_compute),.rst(reset_c),.sample_tick(tick_c),.sample_in(sample_c[23:8]),
        .v_gate(voice_active),.v_note(voice_notes),.v_vel(voice_velocities),
        .waveform(wave_c),.spectrum(spectrum_c),.lissajous(phase_c),.snapshot_toggle(visual_toggle_c));
    ui_status_sync #(.WIDTH(384)) u_visual_ref(
        .clk(clk_ref),.rst(reset_ref),.async_status({wave_c,spectrum_c,phase_c}),.async_toggle(visual_toggle_c),
        .status({ui_waveform,ui_spectrum,ui_lissajous}),.toggle_seen(ui_visual_toggle));
endmodule
