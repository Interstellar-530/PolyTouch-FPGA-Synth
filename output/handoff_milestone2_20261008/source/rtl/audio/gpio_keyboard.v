// [S2-AI 新增] 本文件由 AI 于 2026-10-14 为缺件期间任务清单 S2 编写，供后续智能体复查、审核与修补。
// 除本文件外，top.v、CST 和三个既有顶层测试台内的 [S2-AI] 段落同样为本轮新增。
//
// gpio_keyboard：12 路独立演奏输入的同步、消抖与音符事件生成。
// 每一路的数据通路是：
//   两级同步 -> 独立消抖（按下/松开可用不同门限）-> 边沿检测
//   -> 每路 2 深度事件队列 -> 单拍事件输出（带 ready 握手）。
// 同一轮内先提交全部 Note Off，再提交 Note On；上游未 ready 时事件留在队列里，
// 不丢弃。flush 供 Panic 与模式切换使用：丢弃未发送事件并重新武装，
// 已经按住的键必须松开再按才会重新起音。
//
// 门限默认按硬件文档给出的起点：按下 1 ms、松开 3 ms，主时钟 27 MHz。
// 换用 12.288 MHz 或其它主时钟时必须同步改 PRESS_CYCLES/RELEASE_CYCLES。
// 本模块只做数字逻辑；实物上拉、共地与触点抖动仍需按硬件文档实测复核，
// 仿真通过不等于实物按键已经验收。
//
// 缓冲与延迟上界：每键最多缓存 2 个未发送事件，12 键合计 24 个。
// 顶层在本模块后再接一个 16 项手动 FIFO，两者相加是 40 个事件。
// 下游每拍至少消费 1 个事件，因此按键稳定后的数字响应上界是
// PRESS_CYCLES + 40 + 常数拍，约 1.0 ms（27 MHz）。
// 只有在超过 24 个事件完全不被消费时才会出现丢弃，丢弃计入 drop_count，
// 用于工程判断，不当作正常路径。
module gpio_keyboard #(
    parameter integer KEYS           = 12,
    parameter integer PRESS_CYCLES   = 27000,   // 1 ms @ 27 MHz
    parameter integer RELEASE_CYCLES = 81000,   // 3 ms @ 27 MHz
    parameter [6:0]   KEY_BASE_NOTE  = 7'd60,   // 键 0 = C4（MIDI 60）
    parameter [7:0]   KEY_VELOCITY   = 8'd100
)(
    input  wire             clk,
    input  wire             rst,
    input  wire [KEYS-1:0]  key_in,       // 原始输入：1 = 松开，0 = 按下（外部上拉）
    input  wire             flush,        // 单拍：丢弃未发送事件并重新武装
    input  wire             ev_ready,     // 下游本拍接受当前事件
    output wire             ev_valid,     // 有事件待发；直到 ev_ready 才撤销
    output wire             ev_on,        // 1 = Note On，0 = Note Off
    output wire [6:0]       ev_note,
    output wire [7:0]       ev_vel,
    output wire [KEYS-1:0]  key_pressed   // 消抖后的稳定按下状态，供显示与测试
);

    localparam integer CW = $clog2(RELEASE_CYCLES + 1);

    reg [KEYS-1:0]    sync_m, sync_s;
    reg [KEYS-1:0]    stable;                 // 1 = 松开，0 = 按下
    reg [KEYS*CW-1:0] db_cnt;

    integer k;

    // ------------------------------------------------------- 同步与消抖 ---
    always @(posedge clk) begin
        if (rst) begin
            sync_m <= {KEYS{1'b1}};
            sync_s <= {KEYS{1'b1}};
            stable <= {KEYS{1'b1}};
            db_cnt <= {(KEYS*CW){1'b0}};
        end else begin
            // flush 只清事件队列，保留消抖状态：仍然按住的键不会因此重新起音。
            sync_m <= key_in;
            sync_s <= sync_m;
            for (k = 0; k < KEYS; k = k + 1) begin
                if (sync_s[k] == stable[k])
                    db_cnt[k*CW +: CW] <= {CW{1'b0}};
                else if (db_cnt[k*CW +: CW] ==
                         (sync_s[k] ? (RELEASE_CYCLES - 1) : (PRESS_CYCLES - 1))) begin
                    stable[k] <= sync_s[k];
                    db_cnt[k*CW +: CW] <= {CW{1'b0}};
                end else begin
                    db_cnt[k*CW +: CW] <= db_cnt[k*CW +: CW] + 1'b1;
                end
            end
        end
    end

    assign key_pressed = ~stable;

    // 本拍消抖器将要提交状态改变。提交方向就是同步后的电平 sync_s[k]。
    reg [KEYS-1:0] db_commit;
    always @(*) begin
        for (k = 0; k < KEYS; k = k + 1)
            db_commit[k] = (sync_s[k] != stable[k]) &&
                           (db_cnt[k*CW +: CW] ==
                            (sync_s[k] ? (RELEASE_CYCLES - 1) : (PRESS_CYCLES - 1)));
    end

    // ------------------------------------------------ 每键 2 深度事件队列 ---
    reg [KEYS-1:0] q0_v, q1_v;      // 队首/队尾有效
    reg [KEYS-1:0] q0_on, q1_on;    // 对应事件方向，1 = Note On
    reg [KEYS-1:0] n_q0_v, n_q1_v, n_q0_on, n_q1_on, n_dropped;

    reg            emit_found;
    integer        emit_key;
    reg            pop;
    reg [7:0]      drop_count;      // 满载且仍有新边沿时饱和计数，仅供工程观察

    assign pop = ev_valid && ev_ready;

    // 选择本拍要发送的事件：第一遍找最早的待发 Note Off，第二遍才找 Note On。
    always @(*) begin
        emit_found = 1'b0;
        emit_key   = 0;
        for (k = 0; k < KEYS; k = k + 1)
            if (!emit_found && q0_v[k] && !q0_on[k]) begin
                emit_found = 1'b1;
                emit_key   = k;
            end
        for (k = 0; k < KEYS; k = k + 1)
            if (!emit_found && q0_v[k] && q0_on[k]) begin
                emit_found = 1'b1;
                emit_key   = k;
            end
    end

    assign ev_valid = emit_found;
    assign ev_on    = emit_found && q0_on[emit_key];
    assign ev_note  = KEY_BASE_NOTE + emit_key[6:0];
    assign ev_vel   = KEY_VELOCITY;

    // 组合计算下一状态：先装载当前值，再应用本拍弹出，最后应用本轮边沿。
    reg push0_v, push0_on, push1_v, push1_on;
    always @(*) begin
        for (k = 0; k < KEYS; k = k + 1) begin
            push0_v  = q0_v[k];
            push0_on = q0_on[k];
            push1_v  = q1_v[k];
            push1_on = q1_on[k];
            if (pop && (emit_key == k)) begin
                push0_v  = q1_v[k];
                push0_on = q1_on[k];
                push1_v  = 1'b0;
                push1_on = 1'b0;
            end
            n_dropped[k] = 1'b0;
            if (db_commit[k]) begin
                if (!push0_v) begin
                    push0_v  = 1'b1;
                    push0_on = ~sync_s[k];
                end else if (!push1_v) begin
                    push1_v  = 1'b1;
                    push1_on = ~sync_s[k];
                end else begin
                    n_dropped[k] = 1'b1;
                end
            end
            n_q0_v[k]  = push0_v;
            n_q0_on[k] = push0_on;
            n_q1_v[k]  = push1_v;
            n_q1_on[k] = push1_on;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            q0_v  <= {KEYS{1'b0}};
            q1_v  <= {KEYS{1'b0}};
            q0_on <= {KEYS{1'b0}};
            q1_on <= {KEYS{1'b0}};
            drop_count <= 8'd0;
        end else if (flush) begin
            q0_v  <= {KEYS{1'b0}};
            q1_v  <= {KEYS{1'b0}};
            q0_on <= {KEYS{1'b0}};
            q1_on <= {KEYS{1'b0}};
        end else begin
            q0_v  <= n_q0_v;
            q1_v  <= n_q1_v;
            q0_on <= n_q0_on;
            q1_on <= n_q1_on;
            if ((n_dropped != {KEYS{1'b0}}) && (drop_count != 8'hFF))
                drop_count <= drop_count + 8'd1;
        end
    end

endmodule
