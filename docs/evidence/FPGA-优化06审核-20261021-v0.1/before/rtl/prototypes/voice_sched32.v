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
    parameter integer FS_HZ = 48000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_tick,
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
    (* syn_ramstyle = "registers" *) reg [VOICES-1:0] dirty;

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
    reg        cfg_pend;
    reg [5:0]  sel;
    reg [6:0]  sel_note;
    wire [31:0] sel_inc;
    note_phase_inc #(.FS_HZ(FS_HZ)) u_inc (.note(sel_note), .inc(sel_inc));

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
                retrig[i] <= 1'b0;
            end
            dirty <= {VOICES{1'b0}};
            env_run <= 1'b0; env_ptr <= 6'd0; cfg_pend <= 1'b0;
            sel <= 6'd0; sel_note <= 7'd0;
            ev_q_valid <= 1'b0; ev_q_on <= 1'b0; ev_q_note <= 7'd0; ev_q_vel <= 8'd0;
            ev_state <= EV_IDLE; scan_ptr <= 6'd0;
            ev_on_q <= 1'b0; note_q <= 7'd0; vel_q <= 8'd0;
            match_idx <= 6'd0; free_idx <= 6'd0; rel_idx <= 6'd0; held_idx <= 6'd0;
            rel_age <= 5'd0; held_age <= 5'd0;
            match_any <= 1'b0; free_any <= 1'b0; rel_any <= 1'b0; held_any <= 1'b0;
        end else begin
            // Event capture: one entry.
            if (ev_valid && !ev_q_valid) begin
                ev_q_valid <= 1'b1; ev_q_on <= ev_on;
                ev_q_note <= ev_note; ev_q_vel <= ev_vel;
            end

            // Envelope pass, one voice per clock.
            if (sample_tick && !env_run) begin
                env_run <= 1'b1; env_ptr <= 6'd0;
            end
            if (env_run) begin
                env[env_ptr] <= env_new;
                est[env_ptr] <= est_new;
                if ((env_new != env_cur) || (est_new != est[env_ptr]))
                    dirty[env_ptr] <= 1'b1;
                if (env_ptr == VOICES - 1) env_run <= 1'b0;
                else env_ptr <= env_ptr + 1'b1;
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

            // Configuration writer: one transaction per dirty voice.
            if (cfg_pend) begin
                cfg_pend <= 1'b0;
                retrig[sel] <= 1'b0;
            end else if (dirty_any && cfg_ready) begin
                sel      <= dirty_sel;
                sel_note <= note[dirty_sel];
                cfg_pend <= 1'b1;
                dirty[dirty_sel] <= 1'b0;
            end
        end
    end

    assign cfg_voice     = sel;
    assign cfg_increment = sel_inc;
    assign cfg_envelope  = env[sel];
    assign cfg_velocity  = vel[sel][6:0];
    assign cfg_retrigger = retrig[sel];
    assign cfg_valid     = cfg_pend;
endmodule
