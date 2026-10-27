// 《兰花草》演示事件播放器：旋律与三音伴奏共用节拍，各自维护剩余时长。
// 曲目 ROM 保存音高、力度码和时长，不是 PCM 录音，也不是振荡器波表。
// ev_wr/ev_ready 在 clk 上升沿同时为 1 才接受当前事件；外设模式仲裁位于 top。
//
// Table contents come from tools/gen_song_rom.py:
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
    parameter [7:0]   CHORD_VEL_A  = 8'd30,
    parameter [7:0]   CHORD_VEL_B  = 8'd46,
    parameter [5:0]   MELODY_LAST  = 6'd40,
    parameter [4:0]   CHORD_LAST   = 5'd17
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       sample_tick,
    input  wire       restart,
    input  wire       chord_set,        // 0 = set A, 1 = set B
    input  wire [1:0] tempo_sel,        // 0..3 -> every unit stretched 1x..4x
    input  wire       ev_ready,         // FIFO accepts current event this clock
    output wire       ev_wr,
    output wire [15:0] ev_data,
    output wire [5:0] mel_idx_dbg,
    output wire [4:0] chord_idx_dbg
);

    // ----------------------------------------------------------- tables ---
    // 这里的少量 case 是曲目事件表。音频单周期波表在 dds_osc.v 中使用 BSRAM，
    // 不应把曲目表实现方式照搬到 512/1024 点振荡器波表。
    `include "rtl/audio/song_roms.vh"

    // ----------------------------------------------------------- tick base --
    reg [15:0] tick_cnt;
    // UNIT_SAMPLES * 4 is 39064, still inside 16 bits, so the slice below is
    // exact; slicing keeps the 32 bit parameter arithmetic explicit.
    wire [31:0] tick_period = UNIT_SAMPLES * (tempo_sel + 1);
    wire [15:0] tick_top    = tick_period[15:0] - 16'd1;

    // tick_cnt 每个音频采样才更新，到顶比较会保持 576 个 clk。
    // 必须与单周期 sample_tick 相与；否则 tick_pulse 会变成宽电平，
    // 时长计数器在一个采样内连续递减，曲目会飞速跑圈。
    wire tick_pulse = sample_tick && (tick_cnt == tick_top);

    always @(posedge clk) begin
        if (rst)
            tick_cnt <= 16'd0;
        else if (sample_tick)
            tick_cnt <= tick_pulse ? 16'd0 : tick_cnt + 16'd1;
    end

    // ------------------------------------------------------------ pointers --
    reg [5:0]  mel_idx;
    reg [4:0]  chord_idx;
    reg [7:0]  mel_left;
    reg [7:0]  chord_left;
    reg [7:0]  mel_gap_len;      // gap of the note that is currently sounding

    // Notes of the chord that is currently sounding, so the "off" events match
    // what was switched on even if the chord set changes in between.
    reg [6:0]  cnote0, cnote1, cnote2;

    wire [5:0] mel_nxt       = (mel_idx == MELODY_LAST) ? 6'd0 : mel_idx + 6'd1;
    wire [15:0] mel_cur_word = mel_word(mel_idx);
    wire [15:0] mel_nxt_word = mel_word(mel_nxt);
    wire [6:0] mel_cur_note  = mel_cur_word[12:6];
    wire [6:0] mel_nxt_note  = mel_nxt_word[12:6];
    wire [2:0] mel_nxt_code  = mel_nxt_word[15:13];
    wire [5:0] mel_nxt_on    = mel_nxt_word[5:0];

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

    wire [4:0] chord_nxt     = (chord_idx == CHORD_LAST) ? 5'd0 : chord_idx + 5'd1;
    wire [15:0] ch_nxt_entry = chord_set ? chord_b_word(chord_nxt)
                                         : chord_a_word(chord_nxt);
    // The two harmonisations also differ in level, which makes the S1 switch
    // unmistakable next to the different progressions.
    wire [7:0]  chord_vel    = chord_set ? CHORD_VEL_B : CHORD_VEL_A;
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
    // 一次转场最多八个事件，先发所有 Note Off 再发 Note On。
    // 顺序保证先撤销旧 gate；Release 仍需时间，不能保证声部已空闲或无需窃取。
    // bmask[7-i] 决定是否发送槽 i；未启用的槽只推进索引，不写入 FIFO。
    reg [7:0]  bmask;              // bmask[7-i] enables slot i
    reg [15:0] bdata [0:7];
    reg [2:0]  bidx;
    reg        bactive;
    assign ev_wr   = bactive && bmask[7-bidx];
    assign ev_data = bdata[bidx];

    always @(posedge clk) begin
        if (rst) begin
            // 从表尾初始化，使第一个节拍转到索引 0，启动第一组旋律/和弦。
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
        end else begin
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
                    bdata[5] <= {1'b1, ch_nxt_n0[6:0], chord_vel};
                    bdata[6] <= {1'b1, ch_nxt_n1[6:0], chord_vel};
                    bdata[7] <= {1'b1, ch_nxt_n2[6:0], chord_vel};

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
                // 启用槽在 ev_ready=0 时保持 bidx、ev_wr 和 ev_data，不丢事件。
                // burst 未完成时不更新 mel_left/chord_left；若长期背压跨过节拍，
                // 曲目时长会延长。正常 top 每 clk 消费一个，短 burst 可迅速清空。
                if (!ev_wr || ev_ready) begin
                    if (bidx == 3'd7)
                        bactive <= 1'b0;
                    else
                        bidx <= bidx + 3'd1;
                end
            end
        end
    end

    assign mel_idx_dbg   = mel_idx;
    assign chord_idx_dbg = chord_idx;

endmodule
