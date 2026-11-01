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
// 门限起点仍按硬件文档：按下 1 ms、松开 3 ms。CLK_HZ 是主时钟频率，
// PRESS_CYCLES/RELEASE_CYCLES 默认由它推导，所以换用 12.288 MHz（标准 I2S 档）
// 时只要把 CLK_HZ 传对，门限的毫秒数不变；显式指定两个门限的测试不受影响。
// 本模块只做数字逻辑；实物上拉、共地与触点抖动仍需按硬件文档实测复核，
// 仿真通过不等于实物按键已经验收。
//
// 缓冲与延迟上界：每键最多缓存 2 个未发送事件，12 键合计 24 个。
// 顶层在本模块后再接一个 16 项手动 FIFO，两者相加是 40 个事件。
// 若下游持续每拍消费、没有清理或高优先级来源占用，排队开销最多约 40 拍。
// PRESS_CYCLES + 队列/同步开销约为 1.0 ms（27 MHz）；持续背压时不承诺此上界。
// 容量按键分配：同一键已积压 2 项时再来第 3 个边沿就会丢弃，
// 即使其它键的队列尚空。drop_count 饱和统计发生丢弃的时钟拍数。
module gpio_keyboard #(
    parameter integer KEYS           = 12,
    parameter integer CLK_HZ         = 27_000_000,        // 主时钟，门限换算基准
    parameter integer PRESS_CYCLES   = CLK_HZ / 1000,          // 1 ms
    parameter integer RELEASE_CYCLES = (3 * CLK_HZ) / 1000,    // 3 ms
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

    // 各过程使用独立的循环变量，避免多个 always 块驱动同一个 integer。
    integer db_k;
    integer commit_k;
    integer emit_k;
    integer queue_k;

    // ------------------------------------------------------- 同步与消抖 ---
    always @(posedge clk) begin
        if (rst) begin
            sync_m <= {KEYS{1'b1}};
            sync_s <= {KEYS{1'b1}};
            stable <= {KEYS{1'b1}};
            db_cnt <= {(KEYS*CW){1'b0}};
        end else begin
            // flush 保留消抖状态；下方 suppress_on 阻止正在按下的键补发起音。
            sync_m <= key_in;
            sync_s <= sync_m;
            for (db_k = 0; db_k < KEYS; db_k = db_k + 1) begin
                if (sync_s[db_k] == stable[db_k])
                    db_cnt[db_k*CW +: CW] <= {CW{1'b0}};
                else if (db_cnt[db_k*CW +: CW] ==
                         (sync_s[db_k] ? (RELEASE_CYCLES - 1) : (PRESS_CYCLES - 1))) begin
                    stable[db_k] <= sync_s[db_k];
                    db_cnt[db_k*CW +: CW] <= {CW{1'b0}};
                end else begin
                    db_cnt[db_k*CW +: CW] <= db_cnt[db_k*CW +: CW] + 1'b1;
                end
            end
        end
    end

    assign key_pressed = ~stable;

    // 本拍消抖器将要提交状态改变。提交方向就是同步后的电平 sync_s[k]。
    reg [KEYS-1:0] db_commit;
    always @(*) begin
        for (commit_k = 0; commit_k < KEYS; commit_k = commit_k + 1)
            db_commit[commit_k] = (sync_s[commit_k] != stable[commit_k]) &&
                                  (db_cnt[commit_k*CW +: CW] ==
                                   (sync_s[commit_k] ? (RELEASE_CYCLES - 1) : (PRESS_CYCLES - 1)));
    end

    // ------------------------------------------------ 每键 2 深度事件队列 ---
    reg [KEYS-1:0] q0_v, q1_v;      // 队首/队尾有效
    reg [KEYS-1:0] q0_on, q1_on;    // 对应事件方向，1 = Note On
    reg [KEYS-1:0] suppress_on;    // flush 时已按下或正在按下的键，松开前禁止起音
    reg [KEYS-1:0] n_q0_v, n_q1_v, n_q0_on, n_q1_on, n_dropped;

    reg            emit_found;
    integer        emit_key;
    wire           pop;
    reg [7:0]      drop_count;      // 满载且仍有新边沿时饱和计数，仅供工程观察

    assign pop = ev_valid && ev_ready;

    // 选择本拍事件：先按键编号找待发 Note Off，随后找 Note On；各键内部保持顺序。
    always @(*) begin
        emit_found = 1'b0;
        emit_key   = 0;
        for (emit_k = 0; emit_k < KEYS; emit_k = emit_k + 1)
            if (!emit_found && q0_v[emit_k] && !q0_on[emit_k]) begin
                emit_found = 1'b1;
                emit_key   = emit_k;
            end
        for (emit_k = 0; emit_k < KEYS; emit_k = emit_k + 1)
            if (!emit_found && q0_v[emit_k] && q0_on[emit_k]) begin
                emit_found = 1'b1;
                emit_key   = emit_k;
            end
    end

    assign ev_valid = emit_found;
    assign ev_on    = emit_found && q0_on[emit_key];
    assign ev_note  = KEY_BASE_NOTE + emit_key[6:0];
    assign ev_vel   = KEY_VELOCITY;

    // 组合计算下一状态：先装载当前值，再应用本拍弹出，最后应用本轮边沿。
    reg push0_v, push0_on, push1_v, push1_on;
    always @(*) begin
        for (queue_k = 0; queue_k < KEYS; queue_k = queue_k + 1) begin
            push0_v  = q0_v[queue_k];
            push0_on = q0_on[queue_k];
            push1_v  = q1_v[queue_k];
            push1_on = q1_on[queue_k];
            if (pop && (emit_key == queue_k)) begin
                push0_v  = q1_v[queue_k];
                push0_on = q1_on[queue_k];
                push1_v  = 1'b0;
                push1_on = 1'b0;
            end
            n_dropped[queue_k] = 1'b0;
            if (db_commit[queue_k] && (sync_s[queue_k] || !suppress_on[queue_k])) begin
                if (!push0_v) begin
                    push0_v  = 1'b1;
                    push0_on = ~sync_s[queue_k];
                end else if (!push1_v) begin
                    push1_v  = 1'b1;
                    push1_on = ~sync_s[queue_k];
                end else begin
                    n_dropped[queue_k] = 1'b1;
                end
            end
            n_q0_v[queue_k]  = push0_v;
            n_q0_on[queue_k] = push0_on;
            n_q1_v[queue_k]  = push1_v;
            n_q1_on[queue_k] = push1_on;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            q0_v  <= {KEYS{1'b0}};
            q1_v  <= {KEYS{1'b0}};
            q0_on <= {KEYS{1'b0}};
            q1_on <= {KEYS{1'b0}};
            suppress_on <= {KEYS{1'b0}};
            drop_count <= 8'd0;
        end else if (flush) begin
            q0_v  <= {KEYS{1'b0}};
            q1_v  <= {KEYS{1'b0}};
            q0_on <= {KEYS{1'b0}};
            q1_on <= {KEYS{1'b0}};
            // raw 与两级同步/稳定态都要看，覆盖恰在消抖窗口内到来的 Panic。
            suppress_on <= ~key_in | ~sync_m | ~sync_s | ~stable;
        end else begin
            q0_v  <= n_q0_v;
            q1_v  <= n_q1_v;
            q0_on <= n_q0_on;
            q1_on <= n_q1_on;
            // 键和同步链都回到松开态后重新武装；松键事件仍可送出。
            suppress_on <= suppress_on & ~(key_in & sync_m & sync_s & stable);
            if ((n_dropped != {KEYS{1'b0}}) && (drop_count != 8'hFF))
                drop_count <= drop_count + 8'd1;
        end
    end

endmodule
