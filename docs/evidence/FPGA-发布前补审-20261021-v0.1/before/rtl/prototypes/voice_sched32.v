// 32-voice event/ADSR scheduler for the RAM wavetable prototype.
//
// The RAM core renders all voices from its own state; this block owns the
// musical state (note/velocity/gate/envelope/age/stage) and pushes one
// configuration transaction per changed voice into the core during the frame's
// idle window. Envelope stepping and the event search are serialised (one voice
// per clock) so no 32-way comparison chain sits inside one clock period.
//
// Allocation rules follow the production allocator: retrigger a held note, then
// a free voice, then the oldest released voice, then the oldest held voice. A
// note-off starts release; the voice becomes free only when env reaches zero.
//
// Timbre: instrument 0 selects the e-piano bank (zone group x stage, with the
// per-voice stage cross-fade weight), instrument 1 selects the guitar bank
// (band group x velocity variant). The engine receives {bank, weight} through
// the third configuration word, so each voice can carry its own table.
module voice_sched32 #(
    parameter integer VOICES = 32,
    parameter [15:0] ATTACK_STEP   = 16'd140,
    parameter [15:0] DECAY_STEP    = 16'd16,
    parameter [15:0] RELEASE_STEP  = 16'd48,
    parameter [15:0] SUSTAIN_LEVEL = 16'd45875,
    parameter integer FS_HZ = 48000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_tick,
    input  wire        instrument,     // 0 = e-piano, 1 = guitar
    input  wire [1:0]  piano_tone,
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
    output wire        cfg_valid,
    input  wire        cfg_ready,
    output reg  [5:0]  active_count
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
    (* syn_ramstyle = "registers" *) reg [2:0]  stage_q[0:VOICES-1];
    (* syn_ramstyle = "registers" *) reg [12:0] timer[0:VOICES-1];
    (* syn_ramstyle = "registers" *) reg [VOICES-1:0] dirty;

    wire [2:0] start_stage = (piano_tone >= 2'd3) ? 3'd4 : 3'd3;

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
    reg        env_run;
    reg [5:0]  env_ptr;
    reg [15:0] env_new;
    reg [2:0]  est_new;
    wire [15:0] env_cur = env[env_ptr];

    always @* begin
        env_new = env_cur;
        est_new = est[env_ptr];
        if ((est[env_ptr] != ST_IDLE) && !gate[env_ptr] &&
            (est[env_ptr] != ST_RELEASE))
            est_new = ST_RELEASE;
        case (est_new)
            ST_IDLE: env_new = 16'd0;
            ST_ATTACK: begin
                if (env_cur >= (16'hFFFF - ATTACK_STEP)) begin
                    env_new = 16'hFFFF; est_new = ST_DECAY;
                end else env_new = env_cur + ATTACK_STEP;
            end
            ST_DECAY: begin
                if (env_cur <= (SUSTAIN_LEVEL + DECAY_STEP)) begin
                    env_new = SUSTAIN_LEVEL; est_new = ST_SUSTAIN;
                end else env_new = env_cur - DECAY_STEP;
            end
            ST_SUSTAIN: env_new = SUSTAIN_LEVEL;
            ST_RELEASE: begin
                if (env_cur <= RELEASE_STEP) begin
                    env_new = 16'd0; est_new = ST_IDLE;
                end else env_new = env_cur - RELEASE_STEP;
            end
            default: begin env_new = 16'd0; est_new = ST_IDLE; end
        endcase
    end

    // ---------------------------------------------------------- configuration ---
    reg        cfg_valid_r;
    reg        instrument_q;
    reg [5:0]  sel;
    reg [6:0]  sel_note;
    wire [31:0] sel_inc;
    note_phase_inc #(.FS_HZ(FS_HZ)) u_inc (.note(sel_note), .inc(sel_inc));

    function [2:0] piano_zone;
        input [31:0] inc;
        begin
            if (inc < 32'h00400000) piano_zone = 3'd0;
            else if (inc < 32'h00800000) piano_zone = 3'd1;
            else if (inc < 32'h01000000) piano_zone = 3'd2;
            else if (inc < 32'h02000000) piano_zone = 3'd3;
            else if (inc < 32'h04000000) piano_zone = 3'd4;
            else piano_zone = 3'd5;
        end
    endfunction

    function [2:0] guitar_band;
        input [31:0] inc;
        begin
            if (inc < 32'd11985848) guitar_band = 3'd0;
            else if (inc < 32'd23971696) guitar_band = 3'd1;
            else if (inc < 32'd35916962) guitar_band = 3'd2;
            else if (inc < 32'd60404889) guitar_band = 3'd3;
            else if (inc < 32'd95886784) guitar_band = 3'd4;
            else guitar_band = 3'd5;
        end
    endfunction

    wire [2:0] sel_zone    = piano_zone(sel_inc);
    wire [2:0] sel_band    = guitar_band(sel_inc);
    wire [2:0] sel_stage   = start_stage - stage_q[sel];
    wire [2:0] sel_variant = (vel[sel] >= 8'd112) ? 3'd5 :
                             (vel[sel] >= 8'd96)  ? 3'd4 :
                             (vel[sel] >= 8'd64)  ? 3'd2 :
                             (vel[sel] >= 8'd32)  ? 3'd1 : 3'd0;
    wire [2:0] sel_group_p = (sel_zone == 3'd5) ? 3'd1 : 3'd0;
    wire [2:0] sel_group_g = (sel_band <= 3'd1) ? 3'd0 : (sel_band - 3'd1);
    wire [5:0] sel_bank    = instrument ?
                             (6'd12 + {3'd0, sel_group_g} * 6'd6 + {3'd0, sel_variant}) :
                             ({3'd0, sel_group_p} * 6'd6 + {3'd0, sel_stage});
    wire [15:0] sel_weight = instrument ? 16'd0 :
                             ((16'd8191 - {3'd0, timer[sel]}) << 3);
    assign cfg_param = {8'd0, sel_bank, sel_weight};

    wire dirty_any = |dirty;
    reg [5:0] dirty_sel;
    always @* begin
        dirty_sel = 6'd0;
        for (k = VOICES - 1; k >= 0; k = k - 1)
            if (dirty[k]) dirty_sel = k[5:0];
    end

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < VOICES; i = i + 1) begin
                note[i] <= 7'd0; vel[i] <= 8'd0; env[i] <= 16'd0;
                est[i] <= ST_IDLE; gate[i] <= 1'b0; age[i] <= 5'd0;
                retrig[i] <= 1'b0; stage_q[i] <= 3'd0; timer[i] <= 13'd0;
            end
            dirty <= {VOICES{1'b0}};
            env_run <= 1'b0; env_ptr <= 6'd0; cfg_valid_r <= 1'b0;
            sel <= 6'd0; sel_note <= 7'd0;
            ev_q_valid <= 1'b0; ev_q_on <= 1'b0; ev_q_note <= 7'd0; ev_q_vel <= 8'd0;
            instrument_q <= 1'b0;
            ev_state <= EV_IDLE; scan_ptr <= 6'd0;
            ev_on_q <= 1'b0; note_q <= 7'd0; vel_q <= 8'd0;
            match_idx <= 6'd0; free_idx <= 6'd0; rel_idx <= 6'd0; held_idx <= 6'd0;
            rel_age <= 5'd0; held_age <= 5'd0;
            match_any <= 1'b0; free_any <= 1'b0; rel_any <= 1'b0; held_any <= 1'b0;
        end else begin
            // Instrument switch: every voice must refresh its table word.
            if (instrument != instrument_q) begin
                instrument_q <= instrument;
                dirty <= {VOICES{1'b1}};
            end

            // Event capture: one entry.
            if (ev_valid && !ev_q_valid) begin
                ev_q_valid <= 1'b1; ev_q_on <= ev_on;
                ev_q_note <= ev_note; ev_q_vel <= ev_vel;
            end

            // Envelope pass, one voice per clock; piano stage timers advance here.
            if (sample_tick && !env_run) begin
                env_run <= 1'b1; env_ptr <= 6'd0;
            end
            if (env_run) begin
                env[env_ptr] <= env_new;
                est[env_ptr] <= est_new;
                if ((env_new != env_cur) || (est_new != est[env_ptr]))
                    dirty[env_ptr] <= 1'b1;
                if (!instrument && (stage_q[env_ptr] < start_stage)) begin
                    if (timer[env_ptr] == 13'd8191) begin
                        timer[env_ptr] <= 13'd0;
                        stage_q[env_ptr] <= stage_q[env_ptr] + 1'b1;
                    end else
                        timer[env_ptr] <= timer[env_ptr] + 1'b1;
                    dirty[env_ptr] <= 1'b1;
                end
                if (env_ptr == VOICES - 1) env_run <= 1'b0;
                else env_ptr <= env_ptr + 1'b1;
            end

            // Serial event search: one voice per clock.
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
                    if (!match_any && gate[scan_ptr] && (note[scan_ptr] == ev_q_note)) begin
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
                        vel[pick]    <= vel_q;
                        env[pick]    <= 16'd0;
                        est[pick]    <= ST_ATTACK;
                        gate[pick]   <= 1'b1;
                        retrig[pick] <= 1'b1;
                        dirty[pick]  <= 1'b1;
                        stage_q[pick] <= 3'd0;
                        timer[pick]   <= 13'd0;
                        for (i = 0; i < VOICES; i = i + 1) begin
                            if (i == pick) age[i] <= 5'd0;
                            else age[i] <= age[i] + 1'b1;
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

            // Configuration writer: keep valid high and present the next dirty
            // voice on every accept, so the engine writes one voice per 4 clocks
            // (accept + word0 + word2 + word4) instead of one per 5.
            if (cfg_valid_r && cfg_ready) begin
                retrig[sel] <= 1'b0;
                if (dirty_any) begin
                    sel      <= dirty_sel;
                    sel_note <= note[dirty_sel];
                    dirty[dirty_sel] <= 1'b0;
                end else begin
                    cfg_valid_r <= 1'b0;
                end
            end else if (!cfg_valid_r && dirty_any && cfg_ready) begin
                sel      <= dirty_sel;
                sel_note <= note[dirty_sel];
                dirty[dirty_sel] <= 1'b0;
                cfg_valid_r <= 1'b1;
            end
        end
    end

    assign cfg_voice     = sel;
    assign cfg_increment = sel_inc;
    assign cfg_envelope  = env[sel];
    assign cfg_velocity  = vel[sel][6:0];
    assign cfg_retrigger = retrig[sel];
    assign cfg_valid     = cfg_valid_r;
endmodule
