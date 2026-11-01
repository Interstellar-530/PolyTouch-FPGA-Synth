// Test-tune player: melody plus a chord accompaniment, emitted as note events.
//
// The melody and the chord progression run on independent tick counters and
// both write into the shared event bus, so the voice allocator sees one
// uniform stream.  When the future MPR121 keyboard arrives it feeds exactly
// the same bus; nothing in this file changes.
//
// ROM contents come from tools/gen_song_rom.py:
//   melody : {velocity_code[2:0], note[6:0], sounding_units[5:0]}, note 0 = rest
//   chords : {root[7:0], slot_units[5:0], quality[1:0]}, quality 0 = major
//
// One unit is a sixteenth note, four units to the beat.  The melody ROM stores
// how long each note SOUNDS; the player adds the articulation gap (a quarter of
// the note, at least one unit) itself, so a short note still gets heard.
//
// tempo_sel stretches every unit by 1x .. 4x.  That lets the same bitstream be
// played at the written tempo or several times slower without a rebuild, which
// is how the listening tempo gets settled.
module song_player #(
    parameter integer UNIT_SAMPLES = 9766,
    parameter [7:0]   CHORD_VEL    = 8'd32,
    parameter [5:0]   MELODY_LAST  = 6'd40,
    parameter [3:0]   CHORD_LAST   = 4'd8
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       sample_tick,
    input  wire       restart,
    input  wire       chord_set,        // 0 = set A, 1 = set B
    input  wire [1:0] tempo_sel,        // 0..3 -> every unit stretched 1x..4x
    output reg        ev_wr,
    output reg [15:0] ev_data,
    output wire [5:0] mel_idx_dbg,
    output wire [3:0] chord_idx_dbg
);

    // -------------------------------------------------------------- ROMs ---
    reg [15:0] mel_rom     [0:63];
    reg [15:0] chord_a_rom [0:15];
    reg [15:0] chord_b_rom [0:15];

    initial begin
        $readmemh("rtl/audio/song_melody.hex",   mel_rom);
        $readmemh("rtl/audio/song_chords_a.hex", chord_a_rom);
        $readmemh("rtl/audio/song_chords_b.hex", chord_b_rom);
    end

    // ----------------------------------------------------------- tick base --
    reg [15:0] tick_cnt;
    // UNIT_SAMPLES * 4 is 39064, still inside 16 bits, so the slice below is
    // exact; slicing keeps the 32 bit parameter arithmetic explicit.
    wire [31:0] tick_period = UNIT_SAMPLES * (tempo_sel + 1);
    wire [15:0] tick_top    = tick_period[15:0] - 16'd1;

    wire tick_pulse = (tick_cnt == tick_top);

    always @(posedge clk) begin
        if (rst)
            tick_cnt <= 16'd0;
        else if (sample_tick)
            tick_cnt <= tick_pulse ? 16'd0 : tick_cnt + 16'd1;
    end

    // ------------------------------------------------------------ pointers --
    reg [5:0]  mel_idx;
    reg [3:0]  chord_idx;
    reg [7:0]  mel_left;
    reg [7:0]  chord_left;
    reg [7:0]  mel_gap_len;      // gap of the note that is currently sounding

    // Notes of the chord that is currently sounding, so the "off" events match
    // what was switched on even if the chord set changes in between.
    reg [6:0]  cnote0, cnote1, cnote2;

    wire [5:0] mel_nxt       = (mel_idx == MELODY_LAST) ? 6'd0 : mel_idx + 6'd1;
    wire [6:0] mel_cur_note  = mel_rom[mel_idx][12:6];
    wire [6:0] mel_nxt_note  = mel_rom[mel_nxt][12:6];
    wire [2:0] mel_nxt_code  = mel_rom[mel_nxt][15:13];
    wire [5:0] mel_nxt_on    = mel_rom[mel_nxt][5:0];

    // gap = max(1, sounding / 4), exactly what song_data.gap_units() computes.
    wire [5:0] mel_nxt_gap   = (mel_nxt_on < 6'd4) ? 6'd1 : (mel_nxt_on >> 2);
    wire [6:0] mel_nxt_slot  = {1'b0, mel_nxt_on} + {1'b0, mel_nxt_gap};

    // Velocity code to actual velocity.  The accent lands on the first note of
    // every phrase so the metre is audible even when only one note is heard.
    function [7:0] vel_of;
        input [2:0] code;
        begin
            case (code)
                3'd0:    vel_of = 8'd0;
                3'd1:    vel_of = 8'd32;
                3'd2:    vel_of = 8'd56;
                3'd3:    vel_of = 8'd72;
                3'd4:    vel_of = 8'd88;
                3'd5:    vel_of = 8'd104;
                3'd6:    vel_of = 8'd120;
                default: vel_of = 8'd127;
            endcase
        end
    endfunction

    wire [3:0] chord_nxt     = (chord_idx == CHORD_LAST) ? 4'd0 : chord_idx + 4'd1;
    wire [15:0] ch_nxt_entry = chord_set ? chord_b_rom[chord_nxt] : chord_a_rom[chord_nxt];
    wire [7:0]  ch_nxt_root  = ch_nxt_entry[15:8];
    wire [7:0]  ch_nxt_ticks = ch_nxt_entry[7:2];
    wire [7:0]  ch_nxt_third = (ch_nxt_entry[1:0] == 2'd0) ? 8'd4 : 8'd3;
    wire [7:0]  ch_nxt_n0    = ch_nxt_root;
    wire [7:0]  ch_nxt_n1    = ch_nxt_root + ch_nxt_third;
    wire [7:0]  ch_nxt_n2    = ch_nxt_root + 8'd7;

    wire mel_expire   = tick_pulse && (mel_left   <= 8'd1);
    wire chord_expire = tick_pulse && (chord_left <= 8'd1);
    wire mel_gap      = tick_pulse && (mel_gap_len != 8'd0) &&
                        (mel_left == (mel_gap_len + 8'd1));

    // -------------------------------------------------------- event bursts --
    // One burst carries at most eight events.  All the note-offs are emitted
    // before any note-on so the allocator never steals a voice that is about
    // to be reused by the same burst.
    reg [7:0]  bmask;              // bmask[7-i] enables slot i
    reg [15:0] bdata [0:7];
    reg [2:0]  bidx;
    reg        bactive;

    always @(posedge clk) begin
        if (rst) begin
            mel_idx    <= MELODY_LAST;
            chord_idx  <= CHORD_LAST;
            mel_left   <= 8'd0;
            chord_left <= 8'd0;
            mel_gap_len <= 8'd1;
            cnote0     <= 7'd0;
            cnote1     <= 7'd0;
            cnote2     <= 7'd0;
            bmask      <= 8'h00;
            bidx       <= 3'd0;
            bactive    <= 1'b0;
            ev_wr      <= 1'b0;
            ev_data    <= 16'd0;
        end else begin
            ev_wr <= 1'b0;

            if (restart) begin
                mel_idx    <= MELODY_LAST;
                chord_idx  <= CHORD_LAST;
                mel_left   <= 8'd0;
                chord_left <= 8'd0;
                mel_gap_len <= 8'd1;
                cnote0     <= 7'd0;
                cnote1     <= 7'd0;
                cnote2     <= 7'd0;
                bactive    <= 1'b0;
                bmask      <= 8'h00;
            end else if (!bactive) begin
                // ---- start a burst when either counter runs out ----------
                if (mel_expire || chord_expire || mel_gap) begin
                    bmask <= {
                        (mel_expire | mel_gap),  // slot 0 : melody note off
                        chord_expire,            // slot 1 : chord note 0 off
                        chord_expire,            // slot 2 : chord note 1 off
                        chord_expire,            // slot 3 : chord note 2 off
                        mel_expire & (mel_nxt_note != 7'd0),  // slot 4 : melody on
                        chord_expire,            // slot 5 : chord note 0 on
                        chord_expire,            // slot 6 : chord note 1 on
                        chord_expire             // slot 7 : chord note 2 on
                    };

                    bdata[0] <= {1'b0, mel_cur_note, 8'd0};
                    bdata[1] <= {1'b0, cnote0,       8'd0};
                    bdata[2] <= {1'b0, cnote1,       8'd0};
                    bdata[3] <= {1'b0, cnote2,       8'd0};
                    // note fields are seven bits, exactly like the event word
                    bdata[4] <= {1'b1, mel_nxt_note,   vel_of(mel_nxt_code)};
                    bdata[5] <= {1'b1, ch_nxt_n0[6:0], CHORD_VEL};
                    bdata[6] <= {1'b1, ch_nxt_n1[6:0], CHORD_VEL};
                    bdata[7] <= {1'b1, ch_nxt_n2[6:0], CHORD_VEL};

                    bidx    <= 3'd0;
                    bactive <= 1'b1;

                    if (mel_expire) begin
                        mel_idx     <= mel_nxt;
                        mel_left    <= {1'b0, mel_nxt_slot};
                        mel_gap_len <= {1'b0, mel_nxt_gap};
                    end else begin
                        mel_left <= mel_left - 8'd1;
                    end

                    if (chord_expire) begin
                        chord_idx  <= chord_nxt;
                        chord_left <= ch_nxt_ticks;
                        cnote0     <= ch_nxt_n0[6:0];
                        cnote1     <= ch_nxt_n1[6:0];
                        cnote2     <= ch_nxt_n2[6:0];
                    end else begin
                        chord_left <= chord_left - 8'd1;
                    end
                end else if (tick_pulse) begin
                    mel_left   <= mel_left   - 8'd1;
                    chord_left <= chord_left - 8'd1;
                end
            end else begin
                // ---- walk the burst, one event per clock -----------------
                if (bmask[7-bidx]) begin
                    ev_wr   <= 1'b1;
                    ev_data <= bdata[bidx];
                end
                if (bidx == 3'd7)
                    bactive <= 1'b0;
                else
                    bidx <= bidx + 3'd1;
            end
        end
    end

    assign mel_idx_dbg   = mel_idx;
    assign chord_idx_dbg = chord_idx;

endmodule
