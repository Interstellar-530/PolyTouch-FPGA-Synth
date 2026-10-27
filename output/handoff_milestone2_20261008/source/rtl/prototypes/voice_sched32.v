// 32-voice event/ADSR scheduler for the RAM wavetable prototype.
//
// The RAM core renders all voices from its own state; this block owns the
// musical state (note/velocity/gate/envelope/age) and pushes one configuration
// transaction per changed voice into the core during the frame's idle window.
//
// Both the envelope pass and the event search are serialised: one voice per
// clock. Envelopes cost 32 clocks per frame; a new event costs a 32-clock scan
// plus a commit clock. Events are milliseconds apart, so the scan latency is
// irrelevant and the 49.152 MHz timing no longer contains a 32-way comparison
// chain in one clock period.
//
// Rules follow the production allocator: retrigger a held note, then a free
// voice, then the oldest released voice, then the oldest held voice. A note-off
// starts release; the voice becomes free only when env reaches zero.
module voice_sched32 #(
    parameter integer VOICES = 32,
    parameter [15:0] ATTACK_STEP   = 16'd140,
    parameter [15:0] DECAY_STEP    = 16'd16,
    parameter [15:0] RELEASE_STEP  = 16'd48,
    parameter [15:0] SUSTAIN_LEVEL = 16'd45875,
    parameter integer FS_HZ = 48000,
    parameter integer STAGE_STEP_SAMPLES = 5859
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_tick,
    input  wire        instrument,
    input  wire [2:0]  piano_tone,
    input  wire        ev_valid,
    input  wire        ev_on,
    input  wire [6:0]  ev_note,
    input  wire [7:0]  ev_vel,
    output wire        ev_ready,
    output wire [5:0]  cfg_voice,
    output wire [31:0] cfg_increment,
    output wire [15:0] cfg_envelope,
    output wire [6:0]  cfg_velocity,
    output wire        cfg_retrigger,
    output wire [23:0] cfg_param,
    output wire [2:0]  cfg_mask,
    output wire        cfg_valid,
    input  wire        cfg_ready,
    output reg  [5:0]  active_count,
    // 全局弯音比率（Q16，65536=不弯）。施加在每次配置事务的增量上，
    // 不重触发包络；只在比率变化时把活动声部标脏刷新。
    input  wire [16:0] bend_ratio
);
    localparam [2:0] ST_IDLE = 3'd0, ST_ATTACK = 3'd1, ST_DECAY = 3'd2,
                     ST_SUSTAIN = 3'd3, ST_RELEASE = 3'd4;
    localparam [1:0] EV_IDLE = 2'd0, EV_SCAN = 2'd1, EV_COMMIT = 2'd2;

    (* syn_ramstyle = "registers" *) reg [6:0]  note  [0:VOICES-1];
    (* syn_ramstyle = "registers" *) reg [7:0]  vel   [0:VOICES-1];
    (* syn_ramstyle = "registers" *) reg [15:0] env   [0:VOICES-1];
    (* syn_ramstyle = "registers" *) reg [2:0]  est   [0:VOICES-1];
    (* syn_ramstyle = "registers" *) reg        gate  [0:VOICES-1];
    (* syn_ramstyle = "registers" *) reg [4:0]  age   [0:VOICES-1];
    (* syn_ramstyle = "registers" *) reg        retrig[0:VOICES-1];
    (* syn_ramstyle = "registers" *) reg [VOICES-1:0] dirty, dirty_inc, dirty_param;
    reg [2:0] stage_q[0:VOICES-1];
    reg [12:0] timer[0:VOICES-1];
    reg instrument_q;
    reg [2:0] tone_q;
    reg [16:0] ratio_q = 17'd65536;
    wire [2:0] start_stage=(tone_q>=3)?3'd4:3'd3;

    integer i, k;
    integer active_n;
    always @* begin
        active_n = 0;
        for (i = 0; i < VOICES; i = i + 1)
            if (est[i] != ST_IDLE) active_n = active_n + 1;
        active_count = active_n[5:0];
    end

    // --------------------------------------------------------- event queue ---
    reg        ev_q_valid, ev_q_on;
    reg [6:0]  ev_q_note;
    reg [7:0]  ev_q_vel;
    assign ev_ready = !ev_q_valid;

    // ------------------------------------------------------- serial event FSM ---
    reg [1:0] ev_state;
    reg [5:0] scan_ptr;
    reg       ev_on_q;
    reg [6:0] note_q;
    reg [7:0] vel_q;
    reg [5:0] match_idx, free_idx, rel_idx, held_idx;
    reg [4:0] rel_age, held_age;
    reg match_any, free_any, rel_any, held_any;

    wire [5:0] pick = match_any ? match_idx :
                      free_any  ? free_idx  :
                      rel_any   ? rel_idx   : held_idx;

    // ------------------------------------------------------- envelope engine ---
    // Two clocks per voice: latch the voice state, then step and write it back.
    // The array read mux and the ADSR arithmetic sit in different stages, which
    // keeps the 49.152MHz path short.
    reg        env_run;
    reg [5:0]  env_ptr;
    reg [15:0] env_new;
    reg [2:0]  est_new;
    reg [15:0] env_lat;
    reg [2:0]  est_lat;
    reg        gate_lat;
    reg [12:0] timer_lat;
    reg [2:0]  stage_lat;
    reg        env_phase;

    always @* begin
        env_new = env_lat;
        est_new = est_lat;
        if ((est_lat != ST_IDLE) && !gate_lat && (est_lat != ST_RELEASE))
            est_new = ST_RELEASE;
        case (est_new)
            ST_IDLE: env_new = 16'd0;
            ST_ATTACK: begin
                if (env_lat >= (16'hFFFF - ATTACK_STEP)) begin
                    env_new = 16'hFFFF; est_new = ST_DECAY;
                end else env_new = env_lat + ATTACK_STEP;
            end
            ST_DECAY: begin
                if (env_lat <= (SUSTAIN_LEVEL + DECAY_STEP)) begin
                    env_new = SUSTAIN_LEVEL; est_new = ST_SUSTAIN;
                end else env_new = env_lat - DECAY_STEP;
            end
            ST_SUSTAIN: env_new = SUSTAIN_LEVEL;
            ST_RELEASE: begin
                if (env_lat <= RELEASE_STEP) begin
                    env_new = 16'd0; est_new = ST_IDLE;
                end else env_new = env_lat - RELEASE_STEP;
            end
            default: begin env_new = 16'd0; est_new = ST_IDLE; end
        endcase
    end

    // ---------------------------------------------------------- configuration ---
    reg        cfg_pend;
    reg [5:0]  sel;
    reg [2:0]  cfg_mask_q;
    reg [31:0] cfg_inc_q;
    reg [23:0] cfg_param_q;
    reg [15:0] cfg_env_q;
    reg [6:0]  cfg_vel_q;
    reg        cfg_retrig_q;

    // Register one complete array snapshot before deriving the phase
    // increment. This removes the 32-way note read mux from the long
    // note_phase_inc path while the pending transaction provides backpressure.
    reg        snap_valid;
    reg [1:0]  snap_phase;
    reg [31:0] snap_base_inc;
    reg [16:0] snap_ratio;
    reg [48:0] bent_inc_prod;
    reg env_mark_pending,env_mark_changed;
    reg [5:0] env_mark_voice;
    reg [5:0]  snap_sel;
    reg [6:0]  snap_note;
    reg [7:0]  snap_vel;
    reg [15:0] snap_env;
    reg [2:0]  snap_stage;
    reg [12:0] snap_timer;
    reg        snap_retrig;
    reg [2:0]  snap_mask;

    reg [5:0] dirty_sel;
    // Round-robin scan removes the combinational priority encoder ahead of
    // the note lookup. A full refresh still submits one packet per 4 clocks;
    // a sparse update is visited within VOICES available snapshot slots.
    wire clean_any = dirty[dirty_sel] || dirty_inc[dirty_sel] || dirty_param[dirty_sel];

    wire [31:0] candidate_inc;
    // 弯音：candidate_inc 是基础增量，bend_ratio 是全局 Q16 比率。
    // 先乘后加半位再右移 16，最后饱和到 1..0xFFFFFFFF；比率下限 0.891 不会到 0。
    wire [32:0] bent_inc_round = (bent_inc_prod + 49'd32768) >> 16;
    wire [31:0] bent_inc = (bent_inc_round > 33'hFFFFFFFF) ? 32'hFFFFFFFF :
                           (bent_inc_round == 0) ? 32'd1 : bent_inc_round[31:0];
    note_phase_inc #(.FS_HZ(FS_HZ)) u_inc(.note(snap_note),.inc(candidate_inc));
    // Use note boundaries, preserving the production 46.875kHz musical mapping
    // when the prototype runs at 48kHz. Piano group 1 starts at MIDI 78.
    wire [2:0] candidate_band=snap_note<48?0:snap_note<60?1:
        snap_note<67?2:snap_note<76?3:snap_note<84?4:5;
    wire [2:0] candidate_group=candidate_band<=1?0:candidate_band-1'b1;
    wire [2:0] candidate_variant=candidate_band<=1?
        (snap_vel>=112?5:2):snap_vel>=112?5:snap_vel>=96?4:
        snap_vel>=64?2:snap_vel>=32?1:0;
    wire [2:0] candidate_stage=snap_stage<start_stage?start_stage-snap_stage:0;
    wire [5:0] candidate_bank=instrument_q?
        6'd12+candidate_group*6'd6+candidate_variant:
        (snap_note>=78?6'd6:6'd0)+candidate_stage;
    wire [15:0] candidate_weight=instrument_q?16'd0:
        ((16'd8191-{3'd0,snap_timer})<<3);

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < VOICES; i = i + 1) begin
                note[i] <= 7'd0; vel[i] <= 8'd0; env[i] <= 16'd0;
                est[i] <= ST_IDLE; gate[i] <= 1'b0; age[i] <= i[4:0];
                retrig[i] <= 1'b0; stage_q[i]<=0; timer[i]<=0;
            end
            dirty <= {VOICES{1'b0}}; dirty_inc <= {VOICES{1'b0}}; dirty_param <= {VOICES{1'b0}};
            env_run <= 1'b0; env_ptr <= 6'd0; cfg_pend <= 1'b0; env_phase <= 1'b0;
            env_lat <= 16'd0; est_lat <= 3'd0; gate_lat <= 1'b0; timer_lat <= 13'd0; stage_lat <= 3'd0;
            sel <= 6'd0; dirty_sel<=0;cfg_inc_q<=0;cfg_param_q<=0;cfg_mask_q<=3'b001;instrument_q<=0;tone_q<=3'd0;ratio_q<=17'd65536;
            cfg_env_q <= 16'd0; cfg_vel_q <= 7'd0; cfg_retrig_q <= 1'b0;
            snap_valid<=1'b0;snap_phase<=0;snap_base_inc<=0;snap_ratio<=17'd65536;bent_inc_prod<=0;
            env_mark_pending<=0;env_mark_changed<=0;env_mark_voice<=0;
            snap_sel<=0;snap_note<=0;snap_vel<=0;snap_env<=0;
            snap_stage<=0;snap_timer<=0;snap_retrig<=0;snap_mask<=3'b001;
            ev_q_valid <= 1'b0; ev_q_on <= 1'b0; ev_q_note <= 7'd0; ev_q_vel <= 8'd0;
            ev_state <= EV_IDLE; scan_ptr <= 6'd0;
            ev_on_q <= 1'b0; note_q <= 7'd0; vel_q <= 8'd0;
            match_idx <= 6'd0; free_idx <= 6'd0; rel_idx <= 6'd0; held_idx <= 6'd0;
            rel_age <= 5'd0; held_age <= 5'd0;
            match_any <= 1'b0; free_any <= 1'b0; rel_any <= 1'b0; held_any <= 1'b0;
        end else begin
            // Register the envelope change comparison before the 32-way dirty
            // write enables. Drain it before taking another config snapshot.
            env_mark_pending<=0;
            if(env_mark_pending && env_mark_changed)dirty[env_mark_voice]<=1'b1;
            // Latch global timbre at frame boundary and refresh every voice.
            if(sample_tick && ((instrument_q!=instrument)||(tone_q!=piano_tone)))begin
                instrument_q<=instrument;tone_q<=piano_tone;dirty<={VOICES{1'b1}};dirty_inc<={VOICES{1'b1}};dirty_param<={VOICES{1'b1}};
                dirty_sel<=0;
            end else if(sample_tick && (ratio_q!=bend_ratio))begin
                // 弯音只刷新增量：不置 dirty_param、不重触发包络。
                ratio_q<=bend_ratio;dirty_inc<={VOICES{1'b1}};
                dirty_sel<=0;
            end
            // Event capture: one entry.
            if (ev_valid && !ev_q_valid) begin
                ev_q_valid <= 1'b1; ev_q_on <= ev_on;
                ev_q_note <= ev_note; ev_q_vel <= ev_vel;
            end

            // Envelope pass, two clocks per voice (latch, then step).
            if (sample_tick && !env_run) begin
                env_run <= 1'b1; env_ptr <= 6'd0; env_phase <= 1'b0;
            end
            if (env_run) begin
                if (!env_phase) begin
                    env_lat <= env[env_ptr]; est_lat <= est[env_ptr]; gate_lat <= gate[env_ptr];
                    timer_lat <= timer[env_ptr]; stage_lat <= stage_q[env_ptr];
                    env_phase <= 1'b1;
                end else begin
                    env[env_ptr] <= env_new;
                    est[env_ptr] <= est_new;
                    env_mark_pending<=1;env_mark_voice<=env_ptr;
                    env_mark_changed<=((env_new != env_lat) || (est_new != est_lat));
                    if(!instrument_q && est_lat!=ST_IDLE)begin
                        if(stage_lat>=start_stage)begin
                            if(timer_lat!=STAGE_STEP_SAMPLES-1)dirty_param[env_ptr]<=1;
                            timer[env_ptr]<=STAGE_STEP_SAMPLES-1;
                        end else if(timer_lat>=STAGE_STEP_SAMPLES-1)begin
                            timer[env_ptr]<=0;stage_q[env_ptr]<=stage_lat+1'b1;dirty_param[env_ptr]<=1;
                        end else begin timer[env_ptr]<=timer_lat+1'b1;dirty_param[env_ptr]<=1;end
                    end
                    env_phase <= 1'b0;
                    if (env_ptr == VOICES - 1) env_run <= 1'b0;
                    else env_ptr <= env_ptr + 1'b1;
                end
            end

            // Serial event search: one voice per clock, 5-bit compares only.
            case (ev_state)
                EV_IDLE: if (ev_q_valid && !env_run) begin
                    ev_on_q <= ev_q_on; note_q <= ev_q_note; vel_q <= ev_q_vel;
                    match_any <= 1'b0; free_any <= 1'b0; rel_any <= 1'b0; held_any <= 1'b0;
                    rel_age <= 5'd0; held_age <= 5'd0;
                    scan_ptr <= 6'd0;
                    ev_q_valid <= 1'b0;
                    ev_state <= EV_SCAN;
                end
                EV_SCAN: begin
                    if (!match_any && gate[scan_ptr] && (note[scan_ptr] == note_q)) begin
                        match_idx <= scan_ptr; match_any <= 1'b1;
                    end
                    if (!free_any && (est[scan_ptr] == ST_IDLE)) begin
                        free_idx <= scan_ptr; free_any <= 1'b1;
                    end
                    if (!gate[scan_ptr] && (est[scan_ptr] != ST_IDLE) &&
                        (!rel_any || (age[scan_ptr] > rel_age))) begin
                        rel_idx <= scan_ptr; rel_any <= 1'b1; rel_age <= age[scan_ptr];
                    end
                    if (gate[scan_ptr] && (!held_any || (age[scan_ptr] > held_age))) begin
                        held_idx <= scan_ptr; held_any <= 1'b1; held_age <= age[scan_ptr];
                    end
                    if (scan_ptr == VOICES - 1) ev_state <= EV_COMMIT;
                    else scan_ptr <= scan_ptr + 1'b1;
                end
                EV_COMMIT: if (!env_run) begin
                    if (ev_on_q) begin
                        note[pick]   <= note_q;
                        vel[pick]    <= vel_q[7] ? 8'd127 : vel_q;
                        env[pick]    <= 16'd0;
                        est[pick]    <= ST_ATTACK;
                        gate[pick]   <= 1'b1;
                        retrig[pick] <= 1'b1;
                        dirty[pick]  <= 1'b1; dirty_inc[pick]<=1'b1; dirty_param[pick]<=1'b1; stage_q[pick]<=0;timer[pick]<=0;
                        for (i = 0; i < VOICES; i = i + 1) begin
                            if (i == pick) age[i] <= 5'd0;
                            else if (age[i] < age[pick]) age[i] <= age[i] + 1'b1;
                        end
                    end else begin
                        for (i = 0; i < VOICES; i = i + 1)
                            if (gate[i] && (note[i] == note_q)) begin
                                gate[i] <= 1'b0;
                                if (est[i] != ST_IDLE) est[i] <= ST_RELEASE;
                                dirty[i] <= 1'b1;
                            end
                    end
                    ev_state <= EV_IDLE;
                end
                default: ev_state <= EV_IDLE;
            endcase

            // Convert the registered snapshot, then retain valid/data until
            // accepted. Clearing dirty at snapshot time lets a later musical
            // update set it again while this transaction is waiting.
            // Separate note LUT, multiplier and rounded saturation. The entire
            // snapshot remains stable through backpressure; no partial packet.
            if(snap_valid && snap_phase==0)begin
                snap_base_inc<=candidate_inc;snap_ratio<=ratio_q;snap_phase<=1;
            end else if(snap_valid && snap_phase==1)begin
                bent_inc_prod<=snap_base_inc*snap_ratio;snap_phase<=2;
            end
            if(!cfg_pend || cfg_ready)begin
                if(snap_valid && snap_phase==2)begin
                    sel<=snap_sel;cfg_inc_q<=bent_inc;
                    cfg_env_q<=snap_env;cfg_vel_q<=snap_vel[6:0];
                    cfg_retrig_q<=snap_retrig;cfg_param_q<={2'd0,candidate_bank,candidate_weight};
                    cfg_mask_q<=snap_mask;cfg_pend<=1;snap_valid<=0;
                end else cfg_pend<=0;
            end
            if((!cfg_pend || cfg_ready) &&
               !snap_valid &&
               !env_run && !env_mark_pending && !sample_tick && ev_state!=EV_COMMIT)begin
                dirty_sel <= dirty_sel==VOICES-1 ? 6'd0 : dirty_sel+1'b1;
                if(clean_any)begin
                    snap_valid<=1;snap_phase<=0;snap_sel<=dirty_sel;snap_note<=note[dirty_sel];
                    snap_vel<=vel[dirty_sel];snap_env<=env[dirty_sel];
                    snap_stage<=stage_q[dirty_sel];snap_timer<=timer[dirty_sel];
                    snap_retrig<=retrig[dirty_sel];
                    snap_mask<={dirty_param[dirty_sel],dirty_inc[dirty_sel],1'b1};
                    dirty[dirty_sel]<=0;dirty_inc[dirty_sel]<=0;dirty_param[dirty_sel]<=0;retrig[dirty_sel]<=0;
                end
            end
        end
    end

    assign cfg_voice     = sel;
    assign cfg_increment = cfg_inc_q;
    assign cfg_param = cfg_param_q;
    assign cfg_mask = cfg_mask_q;
    assign cfg_envelope  = cfg_env_q;
    assign cfg_velocity  = cfg_vel_q;
    assign cfg_retrigger = cfg_retrig_q;
    assign cfg_valid     = cfg_pend;
`ifdef SIMULATION
    initial if (STAGE_STEP_SAMPLES<1 || STAGE_STEP_SAMPLES>8192 || VOICES < 1 || VOICES > 32) $fatal(1, "voice_sched32 supports 1..32 voices");
`endif
endmodule
