// CH9350L state-2 Boot 键盘报告 -> 音符/控制事件。
//
// 报告布局（8 字节，report[7:0] 是第 1 字节）：
//   [0] modifier, [1] reserved(00), [2..7] k0..k5
// 保留电脑端旧演奏区，硬件另扩展完整键盘（tools/keyboard_layout.md）：
//   Z S X D C V G B H N J M  -> base-12 .. base-1
//   Q 2 W 3 E R 5 T 6 Y 7 U  -> base+0  .. base+11
//   合计 88 个独立音符键（含 8 个 modifier）；F1-F5 -> T250..T254；F6 -> 钢琴/吉他；
//   Up/Down -> 主音量 +/-5（同串口 V）；Esc -> 全松键；PageUp/PageDown -> 八度。
//   F7 -> 手动/自动切换；整份报告先检测，优先于同帧音符，松开后才可再切换。
//   F8 -> 自动曲目暂停/继续；与 F7 相同，按下边沿只触发一次。
//
// 时序：报告每 ~87 us 才来一帧，而 27 MHz 有 2000+ 拍余量，所以键位差分用
// 14 个状态槽逐键处理：6 个普通键及 modifier 的 8 个独立位。
// 最多 28 个 OFF/ON 事件使用 32 项 FIFO；背压时停在当前事件，不静默丢掉释放。
//
// 去重：同一报告连续重复 3-4 次（CH9350L 特性）不会重复触发。
// 移调：按下时把实际 MIDI 音高存进 prev_note，松开用存下的音高。
// 断线：有效超时或收到 0x86 时清空按键；host_kbd_input 默认只在无持键时采用 2 s 静默超时。
module hid_keymap (
    input  wire        clk,
    input  wire        rst,
    input  wire        report_valid,
    input  wire [63:0] report,
    input  wire        flush,
    input  wire        link_timeout,
    input  wire        device_notify,
    output wire        ev_valid,
    output wire [15:0] ev_word,
    input  wire        ev_ready,
    output reg         panic,
    output reg         timbre_valid,
    output reg  [7:0]  timbre_value,
    // F6 与串口 I0/I1 同义：切换钢琴/吉他；Up/Down 是主音量单步脉冲。
    output reg         instr_toggle,
    output reg         mode_toggle,
    output reg         pause_toggle,
    output reg         vol_up,
    output reg         vol_down,
    output reg  [6:0]  base_note,
    output wire [3:0]  held_count,
    output reg         overflow
);
    localparam integer KEY_SLOTS = 14;
    localparam [7:0] VELOCITY = 8'd100;
    wire clear_all = flush || link_timeout || device_notify;
    wire report_has_mode = (report[23:16] == 8'h40) || (report[31:24] == 8'h40) ||
                           (report[39:32] == 8'h40) || (report[47:40] == 8'h40) ||
                           (report[55:48] == 8'h40) || (report[63:56] == 8'h40);
    reg mode_key_held = 1'b0;
    wire report_has_pause = (report[23:16] == 8'h41) || (report[31:24] == 8'h41) ||
                            (report[39:32] == 8'h41) || (report[47:40] == 8'h41) ||
                            (report[55:48] == 8'h41) || (report[63:56] == 8'h41);
    reg pause_key_held = 1'b0;

    // Detect F7 before the per-key scan can enqueue notes from this report.
    // The resulting top-level flush cancels that scan and keeps the physical
    // key identities. Do not rearm F7 on a mode flush or a silent timeout:
    // repeated/slot-reordered reports still represent the same held key.
    always @(posedge clk) begin
        if (rst || device_notify) begin
            mode_key_held <= 1'b0;
            mode_toggle <= 1'b0;
            pause_key_held <= 1'b0;
            pause_toggle <= 1'b0;
        end else begin
            mode_toggle <= 1'b0;
            pause_toggle <= 1'b0;
            if (report_valid) begin
                mode_key_held <= report_has_mode;
                if (report_has_mode && !mode_key_held) mode_toggle <= 1'b1;
                pause_key_held <= report_has_pause;
                if (report_has_pause && !pause_key_held) pause_toggle <= 1'b1;
            end
        end
    end
    reg [5:0] count = 6'd0;
    // 满队列时若本拍同时出队，仍允许入队；否则会静默丢掉 Note Off。
    wire room = (count < 6'd32) || (ev_valid && ev_ready);

    // ------------------------------------------------------------ event FIFO ---
    reg [15:0] mem [0:31];
    reg [4:0]  wptr = 5'd0, rptr = 5'd0;
    assign ev_valid = (count != 6'd0);
    assign ev_word  = mem[rptr];

    // ------------------------------------------------------------- key state ---
    reg [7:0] prev_key [0:KEY_SLOTS-1];
    reg [6:0] prev_note[0:KEY_SLOTS-1];
    reg       prev_ok  [0:KEY_SLOTS-1];
    reg       prev_seen[0:KEY_SLOTS-1];

    reg [7:0] cur_key  [0:KEY_SLOTS-1];
    reg [7:0] next_key [0:KEY_SLOTS-1];
    reg [6:0] next_note[0:KEY_SLOTS-1];
    reg       next_ok  [0:KEY_SLOTS-1];
    reg       next_seen[0:KEY_SLOTS-1];

    reg [3:0] idx = 4'd0;
    reg [1:0] phase = 2'd0;   // 0=OFF 扫描, 1=ON 扫描, 2=提交
    reg       busy = 1'b0;
    reg       pending = 1'b0;
    reg [63:0] pending_report = 64'd0;

    integer m, hc, i, mi;
    always @* begin
        hc = 0;
        for (m = 0; m < KEY_SLOTS; m = m + 1) if (prev_ok[m]) hc = hc + 1;
    end
    assign held_count = hc[3:0];

    // ------------------------------------------------------------- key tables ---
    `include "rtl/audio/hid_note_map.vh"

    function is_note_key;
        input [7:0] k;
        begin is_note_key = (key_note(k) != 8'd0); end
    endfunction

    // Ordinary slots are de-duplicated within each report; modifiers never
    // consume those six slots and use their standard E0..E7 identities.
    function [7:0] report_key;
        input [63:0] r;
        input integer slot;
        integer j;
        reg duplicate;
        begin
            if (slot < 6) begin
                duplicate = 1'b0;
                for (j = 0; j < 6; j = j + 1)
                    if (j < slot && r[16 + 8*j +: 8] == r[16 + 8*slot +: 8])
                        duplicate = 1'b1;
                report_key = duplicate ? 8'd0 : r[16 + 8*slot +: 8];
            end else begin
                report_key = r[slot-6] ? (8'hE0 + slot-6) : 8'd0;
            end
        end
    endfunction

    function [6:0] clamp_note;
        input [7:0] n;
        begin
            if (n < 8'd36) clamp_note = 7'd36;
            else if (n > 8'd84) clamp_note = 7'd84;
            else clamp_note = n[6:0];
        end
    endfunction

    // --------------------------------------------------- per-cycle key decision ---
    reg [7:0] key;
    reg       found;
    reg [3:0] match;
    reg signed [9:0] n8;
    reg       push;
    reg [15:0] push_word;

    always @* begin
        key   = (phase == 1'b0) ? prev_key[idx] : cur_key[idx];
        found = 1'b0;
        match = 4'd0;
        n8    = 10'sd0;
        push  = 1'b0;
        push_word = 16'd0;

        if (busy && phase == 1'b0 && key != 8'd0 && prev_seen[idx]) begin
            // OFF：上一报告有、当前报告没有
            for (i = 0; i < KEY_SLOTS; i = i + 1)
                if (cur_key[i] == key) found = 1'b1;
            if (!found) begin
                // 只有音符键才发 Note Off；控制键（PageUp/PageDown/Esc/F1-F6/方向键）
                // 的 prev_note 为 0，释放时不能产生 note=0 的假事件。
                if (prev_ok[idx]) begin
                    push = 1'b1;
                    push_word = {1'b0, prev_note[idx], VELOCITY};
                end
            end
        end else if (busy && phase == 1'b1 && key != 8'd0) begin
            // ON：在当前报告中找同一键是否上一报告已按住
            for (i = 0; i < KEY_SLOTS; i = i + 1)
                if (prev_seen[i] && prev_key[i] == key) begin
                    found = 1'b1;
                    match = i[3:0];
                end
            if (!found && is_note_key(key)) begin
                n8 = $signed({3'b0, base_note}) + $signed({2'b0, key_note(key)}) - 10'sd60;
                if (n8 >= 10'sd1 && n8 <= 10'sd127) begin
                    push = 1'b1;
                    push_word = {1'b1, n8[6:0], VELOCITY};
                end
            end
        end
    end

    // --------------------------------------------------------------- main FSM ---
    integer c;
    integer wp;
    always @(posedge clk) begin
        if (rst) begin
            wptr <= 5'd0; rptr <= 5'd0; count <= 6'd0;
            panic <= 1'b0; timbre_valid <= 1'b0; timbre_value <= 8'd0;
            instr_toggle <= 1'b0; vol_up <= 1'b0; vol_down <= 1'b0;
            base_note <= 7'd60; overflow <= 1'b0;
            idx <= 4'd0; phase <= 1'b0; busy <= 1'b0; pending <= 1'b0;
            for (m = 0; m < KEY_SLOTS; m = m + 1) begin
                prev_key[m] <= 8'd0; prev_note[m] <= 7'd0;
                prev_ok[m] <= 1'b0;  prev_seen[m] <= 1'b0;
                cur_key[m] <= 8'd0;  next_key[m] <= 8'd0;
                next_note[m] <= 7'd0; next_ok[m] <= 1'b0; next_seen[m] <= 1'b0;
            end
        end else begin
            panic <= 1'b0;
            timbre_valid <= 1'b0;
            instr_toggle <= 1'b0;
            vol_up <= 1'b0;
            vol_down <= 1'b0;
            c  = count;
            wp = wptr;

            if (push && !clear_all && room) begin
                mem[wp[4:0]] = push_word;
                wp = wp + 1;
                c  = c + 1;
            end
            if (ev_valid && ev_ready && !clear_all) begin
                rptr <= rptr + 1'b1;
                c = c - 1;
            end
            if (clear_all) begin
                count <= 6'd0;
                wptr  <= 5'd0;
                rptr  <= 5'd0;
                overflow <= 1'b0;
            end else begin
                count <= c[5:0];
                wptr  <= wp[4:0];
            end

            if (flush || link_timeout || device_notify) begin
                // 清除音符归属，但普通清音保留物理按键身份，持键须松开后再触发。
                // F6 会在当前报告提交前触发 flush，因此需从正在扫描的报告取键。
                busy <= 1'b0; pending <= 1'b0; phase <= 1'b0; idx <= 4'd0;
                for (m = 0; m < KEY_SLOTS; m = m + 1) begin
                    prev_note[m] <= 7'd0;
                    prev_ok[m] <= 1'b0;
                    if (link_timeout || device_notify) begin
                        prev_key[m] <= 8'd0;
                        prev_seen[m] <= 1'b0;
                    end else if (report_valid) begin
                        prev_key[m] <= report_key(report, m);
                        prev_seen[m] <= (report_key(report, m) != 8'd0);
                    end else if (pending) begin
                        prev_key[m] <= report_key(pending_report, m);
                        prev_seen[m] <= (report_key(pending_report, m) != 8'd0);
                    end else if (busy) begin
                        prev_key[m] <= cur_key[m];
                        prev_seen[m] <= (cur_key[m] != 8'd0);
                    end
                end
            end else if (!busy) begin
                if (report_valid) begin
                    for (m = 0; m < KEY_SLOTS; m = m + 1)
                        cur_key[m] <= report_key(report, m);
                    busy <= 1'b1; phase <= 1'b0; idx <= 4'd0;
                end else if (pending) begin
                    for (m = 0; m < KEY_SLOTS; m = m + 1)
                        cur_key[m] <= report_key(pending_report, m);
                    pending <= 1'b0; busy <= 1'b1; phase <= 1'b0; idx <= 4'd0;
                end
            end else begin
                if (report_valid && !pending) begin pending <= 1'b1; pending_report <= report; end
                else if (report_valid && pending && phase != 2'd2) overflow <= 1'b1;
                if (!push || room) begin
                if (phase == 1'b0) begin
                // OFF 扫描只发 Note Off，不改 prev
                if (idx == 4'd13) begin phase <= 1'b1; idx <= 4'd0; end
                else idx <= idx + 1'b1;
            end else if (phase == 1'b1) begin
                // ON 扫描写 next，避免覆盖仍在被查找的 prev
                next_key[idx]  <= key;
                next_seen[idx] <= (key != 8'd0);
                if (key == 8'd0) begin
                    next_note[idx] <= 7'd0; next_ok[idx] <= 1'b0;
                end else if (found) begin
                    next_note[idx] <= prev_note[match];
                    next_ok[idx]   <= prev_ok[match];
                end else if (is_note_key(key)) begin
                    if (n8 >= 10'sd1 && n8 <= 10'sd127) begin
                        next_note[idx] <= n8[6:0]; next_ok[idx] <= 1'b1;
                    end else begin
                        next_note[idx] <= 7'd0; next_ok[idx] <= 1'b0;
                    end
                end else begin
                    next_note[idx] <= 7'd0; next_ok[idx] <= 1'b0;
                    case (key)
                        8'h29, 8'h2C: panic <= 1'b1; // Esc / Space: emergency release
                        8'h3A: begin timbre_valid <= 1'b1; timbre_value <= 8'd250; end
                        8'h3B: begin timbre_valid <= 1'b1; timbre_value <= 8'd251; end
                        8'h3C: begin timbre_valid <= 1'b1; timbre_value <= 8'd252; end
                        8'h3D: begin timbre_valid <= 1'b1; timbre_value <= 8'd253; end
                        8'h3E: begin timbre_valid <= 1'b1; timbre_value <= 8'd254; end
                        8'h3F: instr_toggle <= 1'b1;   // F6：钢琴/吉他切换
                        8'h51: vol_down <= 1'b1;      // Down：主音量 -
                        8'h52: vol_up <= 1'b1;        // Up：主音量 +
                        8'h4B: base_note <= clamp_note({1'b0, base_note} + 8'd12);
                        8'h4E: base_note <= clamp_note({1'b0, base_note} - 8'd12);
                        default: ;
                    endcase
                end
                if (idx == 4'd13) begin phase <= 2'd2; idx <= 4'd0; end
                else idx <= idx + 1'b1;
            end else begin
                // 提交：next -> prev
                for (m = 0; m < KEY_SLOTS; m = m + 1) begin
                    prev_key[m]  <= next_key[m];
                    prev_note[m] <= next_note[m];
                    prev_ok[m]   <= next_ok[m];
                    prev_seen[m] <= next_seen[m];
                end
                busy <= 1'b0; idx <= 4'd0;
                if (report_valid) begin
                    pending <= 1'b1; pending_report <= report;
                end
            end
            end // advance only after the event can be queued
        end
    end
    end
endmodule
