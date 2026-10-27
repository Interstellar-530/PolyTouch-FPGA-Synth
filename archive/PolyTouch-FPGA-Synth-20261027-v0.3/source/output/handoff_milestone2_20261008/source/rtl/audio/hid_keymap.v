// CH9350L state-2 Boot 键盘报告 -> 音符/控制事件。
//
// 报告布局（8 字节，report[7:0] 是第 1 字节）：
//   [0] modifier, [1] reserved(00), [2..7] k0..k5
// 键位与电脑端 tools/serial_keyboard/KeyboardCore.cs 完全一致：
//   Z S X D C V G B H N J M  -> base-12 .. base-1
//   Q 2 W 3 E R 5 T 6 Y 7 U  -> base+0  .. base+11
//   A/F/K 为旧版兼容键；F1-F5 -> T250..T254；F6 -> 钢琴/吉他切换（同串口 I0/I1）；
//   Up/Down -> 主音量 +/-5（同串口 V）；Esc -> 全松键；PageUp/PageDown -> 八度。
//
// 时序：报告每 ~87 us 才来一帧，而 27 MHz 有 2000+ 拍余量，所以键位差分用
// 12 拍状态机逐键处理，而不是一拍内做 6x6 查找。这样 event FIFO 的写使能只经过
// 一组 6 路比较，关键路径从 ~37 ns 降到十几 ns，避免把 27 MHz 时序压到 30 MHz。
//
// 去重：同一报告连续重复 3-4 次（CH9350L 特性）不会重复触发。
// 移调：按下时把实际 MIDI 音高存进 prev_note，松开用存下的音高。
// 断线：2 s 无帧或收到 0x86 时清空按键；顶层同时清声部，避免粘音。
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
    output reg         vol_up,
    output reg         vol_down,
    output reg  [6:0]  base_note,
    output wire [3:0]  held_count,
    output reg         overflow
);
    localparam [7:0] VELOCITY = 8'd100;
    wire clear_all = flush || link_timeout || device_notify;
    reg [4:0] count = 5'd0;
    // 满队列时若本拍同时出队，仍允许入队；否则会静默丢掉 Note Off。
    wire room = (count < 5'd16) || (ev_valid && ev_ready);

    // ------------------------------------------------------------ event FIFO ---
    reg [15:0] mem [0:15];
    // mem 只有 16 项：地址指针必须是 4 位，count 单独 5 位；
    // 5 位指针累计 16 次后会指向 16/17 越界，旧实现有真实回绕 bug。
    reg [3:0]  wptr = 4'd0, rptr = 4'd0;
    assign ev_valid = (count != 5'd0);
    assign ev_word  = mem[rptr];

    // ------------------------------------------------------------- key state ---
    reg [7:0] prev_key [0:5];
    reg [6:0] prev_note[0:5];
    reg       prev_ok  [0:5];
    reg       prev_seen[0:5];

    reg [7:0] cur_key  [0:5];
    reg [7:0] next_key [0:5];
    reg [6:0] next_note[0:5];
    reg       next_ok  [0:5];
    reg       next_seen[0:5];

    reg [2:0] idx = 3'd0;
    reg [1:0] phase = 2'd0;   // 0=OFF 扫描, 1=ON 扫描, 2=提交
    reg       busy = 1'b0;
    reg       pending = 1'b0;
    reg [63:0] pending_report = 64'd0;

    integer m, hc, i, mi;
    always @* begin
        hc = 0;
        for (m = 0; m < 6; m = m + 1) if (prev_ok[m]) hc = hc + 1;
    end
    assign held_count = hc[3:0];

    // ------------------------------------------------------------- key tables ---
    function signed [7:0] key_offset;
        input [7:0] k;
        begin
            case (k)
                8'h1D: key_offset = -8'sd12; // Z
                8'h16: key_offset = -8'sd11; // S
                8'h1B: key_offset = -8'sd10; // X
                8'h07: key_offset = -8'sd9;  // D
                8'h06: key_offset = -8'sd8;  // C
                8'h19: key_offset = -8'sd7;  // V
                8'h0A: key_offset = -8'sd6;  // G
                8'h05: key_offset = -8'sd5;  // B
                8'h0B: key_offset = -8'sd4;  // H
                8'h11: key_offset = -8'sd3;  // N
                8'h0D: key_offset = -8'sd2;  // J
                8'h10: key_offset = -8'sd1;  // M
                8'h14: key_offset =  8'sd0;  // Q
                8'h1F: key_offset =  8'sd1;  // 2
                8'h1A: key_offset =  8'sd2;  // W
                8'h20: key_offset =  8'sd3;  // 3
                8'h08: key_offset =  8'sd4;  // E
                8'h15: key_offset =  8'sd5;  // R
                8'h22: key_offset =  8'sd6;  // 5
                8'h17: key_offset =  8'sd7;  // T
                8'h23: key_offset =  8'sd8;  // 6
                8'h1C: key_offset =  8'sd9;  // Y
                8'h24: key_offset =  8'sd10; // 7
                8'h18: key_offset =  8'sd11; // U
                default: key_offset = 8'sd0;
            endcase
        end
    endfunction

    function is_note_key;
        input [7:0] k;
        begin
            case (k)
                8'h1D, 8'h16, 8'h1B, 8'h07, 8'h06, 8'h19,
                8'h0A, 8'h05, 8'h0B, 8'h11, 8'h0D, 8'h10,
                8'h14, 8'h1F, 8'h1A, 8'h20, 8'h08, 8'h15,
                8'h22, 8'h17, 8'h23, 8'h1C, 8'h24, 8'h18: is_note_key = 1'b1;
                default: is_note_key = 1'b0;
            endcase
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
    reg [2:0] match;
    reg signed [7:0] n8;
    reg       push;
    reg [15:0] push_word;

    always @* begin
        key   = (phase == 1'b0) ? prev_key[idx] : cur_key[idx];
        found = 1'b0;
        match = 3'd0;
        n8    = 8'sd0;
        push  = 1'b0;
        push_word = 16'd0;

        if (busy && phase == 1'b0 && key != 8'd0 && prev_seen[idx]) begin
            // OFF：上一报告有、当前报告没有
            for (i = 0; i < 6; i = i + 1)
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
            for (i = 0; i < 6; i = i + 1)
                if (prev_seen[i] && prev_key[i] == key) begin
                    found = 1'b1;
                    match = i[2:0];
                end
            if (!found && is_note_key(key)) begin
                n8 = $signed({1'b0, base_note}) + key_offset(key);
                if (n8 >= 8'sd1 && n8 <= 8'sd127) begin
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
            wptr <= 5'd0; rptr <= 5'd0; count <= 5'd0;
            panic <= 1'b0; timbre_valid <= 1'b0; timbre_value <= 8'd0;
            instr_toggle <= 1'b0; vol_up <= 1'b0; vol_down <= 1'b0;
            base_note <= 7'd60; overflow <= 1'b0;
            idx <= 3'd0; phase <= 1'b0; busy <= 1'b0; pending <= 1'b0;
            for (m = 0; m < 6; m = m + 1) begin
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
                mem[wp[3:0]] = push_word;
                wp = wp + 1;
                c  = c + 1;
            end else if (push && !clear_all && !room) begin
                overflow <= 1'b1;
            end
            if (ev_valid && ev_ready && !clear_all) begin
                rptr <= rptr + 1'b1;
                c = c - 1;
            end
            if (clear_all) begin
                count <= 5'd0;
                wptr  <= 4'd0;
                rptr  <= 4'd0;
                overflow <= 1'b0;
            end else begin
                count <= c[4:0];
                wptr  <= wp[3:0];
            end

            if (flush || link_timeout || device_notify) begin
                // 清除音符归属，但普通清音保留物理按键身份，持键须松开后再触发。
                // F6 会在当前报告提交前触发 flush，因此需从正在扫描的报告取键。
                busy <= 1'b0; pending <= 1'b0; phase <= 1'b0; idx <= 3'd0;
                for (m = 0; m < 6; m = m + 1) begin
                    prev_note[m] <= 7'd0;
                    prev_ok[m] <= 1'b0;
                    if (link_timeout || device_notify) begin
                        prev_key[m] <= 8'd0;
                        prev_seen[m] <= 1'b0;
                    end else if (report_valid) begin
                        prev_key[m] <= report[16 + 8*m +: 8];
                        prev_seen[m] <= (report[16 + 8*m +: 8] != 8'd0);
                    end else if (pending) begin
                        prev_key[m] <= pending_report[16 + 8*m +: 8];
                        prev_seen[m] <= (pending_report[16 + 8*m +: 8] != 8'd0);
                    end else if (busy) begin
                        prev_key[m] <= cur_key[m];
                        prev_seen[m] <= (cur_key[m] != 8'd0);
                    end
                end
            end else if (!busy) begin
                if (report_valid) begin
                    for (m = 0; m < 6; m = m + 1)
                        cur_key[m] <= report[16 + 8*m +: 8];
                    busy <= 1'b1; phase <= 1'b0; idx <= 3'd0;
                end else if (pending) begin
                    for (m = 0; m < 6; m = m + 1)
                        cur_key[m] <= pending_report[16 + 8*m +: 8];
                    pending <= 1'b0; busy <= 1'b1; phase <= 1'b0; idx <= 3'd0;
                end
            end else begin
                if (report_valid && !pending) begin pending <= 1'b1; pending_report <= report; end
                if (phase == 1'b0) begin
                // OFF 扫描只发 Note Off，不改 prev
                if (idx == 3'd5) begin phase <= 1'b1; idx <= 3'd0; end
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
                    if (n8 >= 8'sd1 && n8 <= 8'sd127) begin
                        next_note[idx] <= n8[6:0]; next_ok[idx] <= 1'b1;
                    end else begin
                        next_note[idx] <= 7'd0; next_ok[idx] <= 1'b0;
                    end
                end else begin
                    next_note[idx] <= 7'd0; next_ok[idx] <= 1'b0;
                    case (key)
                        8'h29: panic <= 1'b1;
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
                if (idx == 3'd5) begin phase <= 2'd2; idx <= 3'd0; end
                else idx <= idx + 1'b1;
            end else begin
                // 提交：next -> prev
                for (m = 0; m < 6; m = m + 1) begin
                    prev_key[m]  <= next_key[m];
                    prev_note[m] <= next_note[m];
                    prev_ok[m]   <= next_ok[m];
                    prev_seen[m] <= next_seen[m];
                end
                busy <= 1'b0; idx <= 3'd0;
                if (report_valid) begin
                    pending <= 1'b1; pending_report <= report;
                end
            end
        end
    end
    end
endmodule
