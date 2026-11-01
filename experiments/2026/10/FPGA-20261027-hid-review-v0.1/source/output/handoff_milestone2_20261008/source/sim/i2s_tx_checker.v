// [S3-AI | deepseek | 2026-10-14] 单个档案的 I2S 发送器自检盒（仅仿真用）。
// [S3-REVIEW | Codex | 2026-10-14] 补齐填充/tick/非零复位探针，三种复位位置实际逐项验证。
//
// 一个实例包含：被测 i2s_tx、独立接收模型 i2s_rx_model、激励与期望队列、引脚级断言和指标。
// 期望值只由本模块驱动的输入产生（在帧边界之前稳定），绝不从解码结果反推。
// 输入在 negedge clk 改变，避免与 DUT 的锁存边沿竞争。
//
// 帧序列（data_idx 计正常数据帧）：0..15 定向向量；16..223 固定种子 32'h53A32026 伪随机；
// 224..247 撕裂/中途改变（左声道中途、左右边界、右声道中途各改变一次输入）；
// 248..263 数字静音（两路置零，时钟与 tick 连续，随后恢复非零）；
// 之后注入三次硬复位（左数据中途、右数据中途、填充槽中途）并各恢复一次。
//
// 任何普通失败都用 $fatal(1,...)，只有全部自检通过才置 done。
module i2s_tx_checker #(
    parameter integer CLK_HZ         = 12288000,
    parameter integer SAMPLE_RATE_HZ = 48000,
    parameter integer DATA_BITS      = 16
)(
    input  wire clk,
    input  wire run,          // 1 = 释放复位开始检查；0 = 保持复位
    output reg  done,
    output reg [31:0] m_frames,
    output reg [31:0] m_vector_frames,
    output reg [31:0] m_prng_frames,
    output reg [31:0] m_tear_frames,
    output reg [31:0] m_mute_frames,
    output reg [31:0] m_resets,
    output reg [31:0] m_ticks,
    output reg [31:0] m_frame_gap_min,
    output reg [31:0] m_frame_gap_max,
    output reg [31:0] m_bck_high_min,
    output reg [31:0] m_bck_high_max,
    output reg [31:0] m_bck_low_min,
    output reg [31:0] m_bck_low_max,
    output reg [31:0] m_neg_lj,
    output reg [31:0] m_neg_rj,
    output reg [31:0] m_neg_swap,
    output reg [31:0] m_neg_flip,
    output reg [31:0] m_align_discards
);

    localparam integer FRAME_CYC = CLK_HZ / SAMPLE_RATE_HZ;
    localparam integer HALF_CYC  = FRAME_CYC / 2;
    localparam integer BCK_CYC   = FRAME_CYC / 64;
    localparam integer BCK_HIGH  = BCK_CYC / 2;
    localparam integer BCK_LOW   = BCK_CYC - BCK_HIGH;
    localparam integer F_VEC     = 16;
    localparam integer F_PRNG    = 208;
    localparam integer F_TEAR    = 24;
    localparam integer F_MUTE    = 16;
    localparam integer F_ALL     = F_VEC + F_PRNG + F_TEAR + F_MUTE;   // 264
    localparam integer N_RESET   = 3;
    localparam integer QDEPTH    = 8;
    localparam [31:0] PADDING_MASK = (32'h1 << (31 - DATA_BITS)) - 1;

    // ------------------------------------------------------------ 被测与模型 ---
    reg                         rst;
    reg  signed [DATA_BITS-1:0] drive_l, drive_r;
    wire                        bck, lrck, din, tick;
    wire signed [DATA_BITS-1:0] dec_l, dec_r;
    wire                        dec_valid;
    wire [31:0]                 slot_l, slot_r;
    wire [31:0]                 align_discards;

    i2s_tx #(.CLK_HZ(CLK_HZ), .SAMPLE_RATE_HZ(SAMPLE_RATE_HZ), .DATA_BITS(DATA_BITS)) dut (
        .clk(clk), .rst(rst), .sample_l(drive_l), .sample_r(drive_r),
        .bck(bck), .lrck(lrck), .din(din), .sample_tick(tick)
    );

    i2s_rx_model #(.DATA_BITS(DATA_BITS), .HALF_SLOTS(32)) rx (
        .bck(bck), .rst(rst), .lrck(lrck), .din(din),
        .left_word(dec_l), .right_word(dec_r), .frame_valid(dec_valid),
        .slot_l(slot_l), .slot_r(slot_r), .align_discards(align_discards)
    );

    // ------------------------------------------------------------ 期望模式 ---
    reg signed [DATA_BITS-1:0] dl [0:F_ALL-1];
    reg signed [DATA_BITS-1:0] dr [0:F_ALL-1];
    reg signed [DATA_BITS-1:0] vec_l [0:7];
    reg signed [DATA_BITS-1:0] vec_r [0:7];
    reg signed [DATA_BITS-1:0] probe_l, probe_r, tear_probe_l, tear_probe_r;
    integer i;
    reg [31:0] lfsr;

    initial begin
        if (DATA_BITS == 16) begin
            vec_l[0] = 16'h0000; vec_r[0] = 16'hFFFF;
            vec_l[1] = 16'h0001; vec_r[1] = 16'h7FFE;
            vec_l[2] = 16'h7FFF; vec_r[2] = 16'h8000;
            vec_l[3] = 16'h8000; vec_r[3] = 16'h0000;
            vec_l[4] = 16'hFFFF; vec_r[4] = 16'h5555;
            vec_l[5] = 16'h5555; vec_r[5] = 16'hAAAA;
            vec_l[6] = 16'hAAAA; vec_r[6] = 16'h1234;
            vec_l[7] = 16'h8001; vec_r[7] = 16'h4321;
        end else begin
            vec_l[0] = 24'h000000; vec_r[0] = 24'hFFFFFF;
            vec_l[1] = 24'h000001; vec_r[1] = 24'h7FFFFE;
            vec_l[2] = 24'h7FFFFF; vec_r[2] = 24'h800000;
            vec_l[3] = 24'h800000; vec_r[3] = 24'h000000;
            vec_l[4] = 24'hFFFFFF; vec_r[4] = 24'h555555;
            vec_l[5] = 24'h555555; vec_r[5] = 24'hAAAAAA;
            vec_l[6] = 24'hAAAAAA; vec_r[6] = 24'h123456;
            vec_l[7] = 24'h800001; vec_r[7] = 24'h43210F;
        end

        lfsr = 32'h53A32026;
        for (i = 0; i < F_ALL; i = i + 1) begin
            if (i < F_VEC) begin
                dl[i] = vec_l[i % 8];                  // 定向向量，左右不相同
                dr[i] = vec_r[i % 8];
            end else if (i < F_VEC + F_PRNG) begin
                lfsr  = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
                if (DATA_BITS == 16) begin
                    dl[i] = lfsr[15:0];
                    dr[i] = ~lfsr[15:0];               // 独立且不相等的右路序列
                end else begin
                    dl[i] = lfsr[23:0];
                    dr[i] = {lfsr[7:0], ~lfsr[23:16], lfsr[15:8]};
                end
            end else if (i < F_VEC + F_PRNG + F_TEAR) begin
                dl[i] = (i % 2) ? vec_l[5] : vec_l[6]; // 撕裂期交替两个明显不同的值
                dr[i] = ~dl[i];
            end else begin
                dl[i] = {DATA_BITS{1'b0}};             // 数字静音
                dr[i] = {DATA_BITS{1'b0}};
            end
        end

        probe_l      = vec_l[2];                       // 复位测试期间的非零输入
        probe_r      = vec_r[5];                       // 两路探针都非零，避免把静音算作恢复
        tear_probe_l = ~vec_l[0];                      // 既不是本帧也不是下帧的期望值
        tear_probe_r = ~vec_r[1];

        m_frame_gap_min = 32'hFFFFFFFF;                // 指标初值
        m_bck_high_min  = 32'hFFFFFFFF;
        m_bck_low_min   = 32'hFFFFFFFF;
    end

    // ------------------------------------------------------------ 驱动 ---
    // 0 = 静音；1 = 数据帧；2 = 复位探针；3 = 撕裂探针
    integer drive_mode;
    integer drive_idx;

    always @(negedge clk) begin
        if (drive_mode == 1) begin
            drive_l <= dl[drive_idx];
            drive_r <= dr[drive_idx];
        end else if (drive_mode == 2) begin
            drive_l <= probe_l;
            drive_r <= probe_r;
        end else if (drive_mode == 3) begin
            drive_l <= tear_probe_l;
            drive_r <= tear_probe_r;
        end else begin
            drive_l <= {DATA_BITS{1'b0}};
            drive_r <= {DATA_BITS{1'b0}};
        end
    end

    // -------------------------------------------------------- 期望队列 ---
    reg signed [DATA_BITS-1:0] q_l [0:QDEPTH-1];
    reg signed [DATA_BITS-1:0] q_r [0:QDEPTH-1];
    integer q_head, q_tail, q_count;
    reg signed [DATA_BITS-1:0] exp_l, exp_r;

    // ---------------------------------------------------------- 时序状态 ---
    integer cyc;
    integer sub_cnt;
    integer frames_seen;
    integer data_idx;
    integer next_idx;
    integer zero_push_left;
    integer probe_wait_left;   // 复位后还要比几帧才算完成一次恢复（残帧+零帧+探针帧）
    integer reset_round;
    integer reset_at;          // 本次复位注入在帧内的系统拍位置
    integer rst_hold;          // 复位保持拍数
    integer last_frame_cyc, last_lrck_cyc, last_tick_cyc, last_bck_cyc;
    integer startup_cyc;
    integer gap_meas, lrck_meas, hi_meas, lo_meas;
    integer bck_rise_in_half;
    reg     prev_lrck, prev_bck, prev_din, prev_tick, prev_rst;
    reg     half_pending;      // 已看到半帧的低→高，接下来的高→低才是帧边界
    reg     want_reset;
    reg     inject_reset;
    reg     finishing;
    reg     frame_edge;
    reg     halt_push;         // 三次复位恢复跑完后停止推入，等待队列排空

    // 所有状态显式初值：复位从 0 时刻就有效，避免 X 被当成"非复位"。
    initial begin
        rst = 1'b1; prev_rst = 1'b1;
        drive_mode = 0; drive_idx = 0; data_idx = 0; next_idx = 0;
        zero_push_left = 0; probe_wait_left = 0; reset_round = 0; reset_at = 0;
        q_head = 0; q_tail = 0; q_count = 0;
        cyc = 0; sub_cnt = 0; frames_seen = 0; bck_rise_in_half = 0;
        last_frame_cyc = -1; last_lrck_cyc = -1; last_tick_cyc = -1; last_bck_cyc = -1;
        startup_cyc = 0;
        prev_lrck = 1'b0; prev_bck = 1'b0; prev_din = 1'b0; prev_tick = 1'b0;
        half_pending = 1'b0; want_reset = 1'b0; inject_reset = 1'b0; finishing = 1'b0;
        frame_edge = 1'b0; rst_hold = 0; halt_push = 1'b0;
        done = 1'b0;
        m_frames = 0; m_vector_frames = 0; m_prng_frames = 0; m_tear_frames = 0;
        m_mute_frames = 0; m_resets = 0; m_ticks = 0;
        m_frame_gap_max = 0; m_bck_high_max = 0; m_bck_low_max = 0;
        m_neg_lj = 0; m_neg_rj = 0; m_neg_swap = 0; m_neg_flip = 0;
        m_align_discards = 0;
    end

    always @(posedge clk) begin
        cyc       <= cyc + 1;
        prev_lrck <= lrck;
        prev_bck  <= bck;
        prev_din  <= din;
        prev_tick <= tick;
        prev_rst  <= rst;

        if (rst) begin
            // 同步复位至少要采样一次之后才检查引脚定义。
            if ((cyc > 2) && ((^{bck, lrck, din, tick}) === 1'bx))
                $fatal(1, "%m: 复位期间引脚出现 X bck=%b lrck=%b din=%b tick=%b rst=%b cyc=%0d",
                       bck, lrck, din, tick, rst, cyc);
            if ((cyc > 2) && (din !== 1'b0))
                $fatal(1, "%m: 复位期间 DIN 不是 0");
            // 复位沿不能当成帧边界：清掉与边界相关的记录。
            last_frame_cyc   <= -1;
            last_lrck_cyc    <= -1;
            last_tick_cyc    <= -1;
            last_bck_cyc     <= -1;
            half_pending     <= 1'b0;
            bck_rise_in_half <= 0;
            sub_cnt          <= 0;
        end else begin
            if ((^{bck, lrck, din, tick}) === 1'bx)
                $fatal(1, "%m: 引脚出现 X");

            // DIN 与 LRCK 的稳态变化只允许发生在 BCK 下降沿。
            if ((din !== prev_din) && !(prev_bck && !bck))
                $fatal(1, "%m: DIN 在非 BCK 下降沿改变");
            if ((lrck !== prev_lrck) && !(prev_bck && !bck))
                $fatal(1, "%m: LRCK 在非 BCK 下降沿改变");

            // ---------------- 复位释放后的重新武装 ----------------
            if (prev_rst) begin
                startup_cyc <= cyc;
                // 复位释放到 E0 之间的半帧是完整的（槽计数器从 0 开始），模型会把它作为
                // 第一帧发布，所以这里先推一条强制零的期望，与它对齐。
                q_head         <= 0;
                q_tail         <= 1;
                q_count        <= 1;
                q_l[0]         <= {DATA_BITS{1'b0}};
                q_r[0]         <= {DATA_BITS{1'b0}};
                zero_push_left <= 1;                   // 再一帧：E0 之后的强制零帧
                if (finishing) begin
                    drive_mode  <= 2;                  // 复位探针：输入保持非零
                    probe_wait_left <= 3;              // 三次比较后记一次复位恢复
                    reset_round <= reset_round + 1;
                end else begin
                    drive_mode <= 1;                   // 正常启动：从第一个数据帧开始
                    drive_idx  <= 0;
                    data_idx   <= 0;
                end
            end

            // ---------------- 帧边界：LRCK 高→低 ----------------
            frame_edge = prev_lrck && !lrck && half_pending;
            if (frame_edge !== tick)
                $fatal(1, "S3_TICK_BOUNDARY: %m tick 与帧边界不一致");
            if (!prev_rst && last_frame_cyc < 0 && cyc - startup_cyc > FRAME_CYC + BCK_CYC)
                $fatal(1, "S3_STARTUP_TIMEOUT: %m 未在规定拍数内出现 E0");
            if (frame_edge) begin
                half_pending <= 1'b0;
                sub_cnt      <= 0;
                if (last_frame_cyc >= 0) begin
                    gap_meas = cyc - last_frame_cyc;
                    if (gap_meas < m_frame_gap_min) m_frame_gap_min <= gap_meas;
                    if (gap_meas > m_frame_gap_max) m_frame_gap_max <= gap_meas;
                    if (gap_meas != FRAME_CYC)
                        $fatal(1, "%m: 帧边界间隔 %0d 拍，期望 %0d", gap_meas, FRAME_CYC);
                end
                last_frame_cyc <= cyc;

                if (q_count >= QDEPTH)
                    $fatal(1, "%m: 期望队列溢出");
                if (zero_push_left > 0) begin
                    q_l[q_tail] = {DATA_BITS{1'b0}};
                    q_r[q_tail] = {DATA_BITS{1'b0}};
                    zero_push_left = zero_push_left - 1;
                end else begin
                    q_l[q_tail] = drive_l;             // 边界前稳定的输入就是本帧期望
                    q_r[q_tail] = drive_r;
                    if (!finishing) begin
                        if (data_idx < F_VEC) m_vector_frames <= m_vector_frames + 1;
                        else if (data_idx < F_VEC + F_PRNG) m_prng_frames <= m_prng_frames + 1;
                        else if (data_idx < F_VEC + F_PRNG + F_TEAR) m_tear_frames <= m_tear_frames + 1;
                        else if (data_idx < F_ALL) m_mute_frames <= m_mute_frames + 1;
                    end
                    next_idx   <= (data_idx + 1 < F_ALL) ? (data_idx + 1) : (F_ALL - 1);
                end
                q_tail  <= (q_tail + 1) % QDEPTH;
                q_count <= q_count + 1;

                if (want_reset) begin
                    inject_reset <= 1'b1;
                    want_reset   <= 1'b0;
                    if (reset_round == 0) reset_at <= 8 * BCK_CYC;
                    else if (reset_round == 1) reset_at <= HALF_CYC + 8 * BCK_CYC;
                    else reset_at <= FRAME_CYC - 2 * BCK_CYC;
                end else if (!finishing && (data_idx >= F_ALL - 1)) begin
                    finishing <= 1'b1;                 // 数据帧跑完，三次复位即将开始
                    want_reset <= 1'b1;
                end else if (finishing && (reset_round < N_RESET) && (probe_wait_left == 0)) begin
                    want_reset <= 1'b1;                // 上一轮恢复比对完成后再安排下一次复位
                end
            end else if (sub_cnt < FRAME_CYC * 2) begin
                sub_cnt <= sub_cnt + 1;
            end

            // ---------------- 半帧起点：LRCK 低→高 ----------------
            if (lrck !== prev_lrck) begin
                // 相邻两次 LRCK 跳变的间隔必须是半个帧（两种方向都要量）。
                if (last_lrck_cyc >= 0) begin
                    lrck_meas = cyc - last_lrck_cyc;
                    if (lrck_meas != HALF_CYC)
                        $fatal(1, "%m: LRCK 半周期 %0d 拍，期望 %0d", lrck_meas, HALF_CYC);
                end
                last_lrck_cyc <= cyc;
            end
            if (!prev_lrck && lrck) begin
                half_pending <= 1'b1;
                if (!finishing && (data_idx >= F_VEC + F_PRNG) && (data_idx < F_VEC + F_PRNG + F_TEAR))
                    drive_mode <= 3;                   // 撕裂期：左右边界处打探针
            end

            // 左声道中途换到下一帧的值；右声道中途恢复该值（撕裂期先被打过探针）。
            if (!finishing && sub_cnt == HALF_CYC / 2) begin
                drive_mode <= 1;
                drive_idx  <= next_idx;
                data_idx   <= next_idx;
            end
            if (!finishing && sub_cnt == HALF_CYC + HALF_CYC / 2) begin
                drive_mode <= 1;
                drive_idx  <= next_idx;
            end

            // ---------------- tick 断言 ----------------
            if (tick) begin
                if (prev_tick)
                    $fatal(1, "%m: sample_tick 宽于一个系统拍");
                if (last_tick_cyc >= 0 && (cyc - last_tick_cyc != FRAME_CYC))
                    $fatal(1, "%m: sample_tick 周期 %0d 拍，期望 %0d",
                           cyc - last_tick_cyc, FRAME_CYC);
                if ((lrck !== 1'b0) || !prev_lrck)
                    $fatal(1, "%m: sample_tick 不在 LRCK 高→低的帧边界上");
                last_tick_cyc <= cyc;
                m_ticks       <= m_ticks + 1;
            end

            // ---------------- 位置 0 是零延迟位，半帧内 32 个上升沿 ----------------
            if (lrck !== prev_lrck) begin
                if (last_lrck_cyc >= 0 && bck_rise_in_half != 32)
                    $fatal(1, "S3_HALF_SLOTS: %m 半帧仅有 %0d 个 BCK 上升沿", bck_rise_in_half);
                bck_rise_in_half <= 0;
            end else if (bck && !prev_bck) begin
                if (bck_rise_in_half == 0 && din !== 1'b0)
                    $fatal(1, "%m: 位置 0 不是零延迟位");
                if (bck_rise_in_half >= 32)
                    $fatal(1, "%m: 半帧内 BCK 上升沿超过 32 个");
                bck_rise_in_half <= bck_rise_in_half + 1;
            end

            // ---------------- BCK 高/低电平宽度 ----------------
            if (bck !== prev_bck) begin
                if (last_bck_cyc >= 0) begin
                    if (!bck) begin
                        hi_meas = cyc - last_bck_cyc;
                        if (hi_meas < m_bck_high_min) m_bck_high_min <= hi_meas;
                        if (hi_meas > m_bck_high_max) m_bck_high_max <= hi_meas;
                        if (hi_meas != BCK_HIGH)
                            $fatal(1, "%m: BCK 高电平 %0d 拍，期望 %0d", hi_meas, BCK_HIGH);
                    end else begin
                        lo_meas = cyc - last_bck_cyc;
                        if (lo_meas < m_bck_low_min) m_bck_low_min <= lo_meas;
                        if (lo_meas > m_bck_low_max) m_bck_low_max <= lo_meas;
                        if (lo_meas != BCK_LOW)
                            $fatal(1, "%m: BCK 低电平 %0d 拍，期望 %0d", lo_meas, BCK_LOW);
                    end
                end
                last_bck_cyc <= cyc;
            end
        end
    end

    // 指标：模型丢弃的残段数直接来自模型计数。
    always @(posedge clk) m_align_discards <= align_discards;

    // ------------------------------------------------------------ 复位控制 ---
    // rst 只在本块驱动：run 为低时保持复位，注入时拉高 4 拍再释放。
    // 用 negedge 释放/拉高，避免复位沿与 BCK 沿同拍造成接收模型在释放那一拍上竞态。
    always @(negedge clk) begin
        if (!run) begin
            rst          <= 1'b1;
            rst_hold     <= 0;
            inject_reset <= 1'b0;
        end else if (inject_reset && finishing && (sub_cnt == reset_at)) begin
            $display("S3_RESET_INJECT: %m round=%0d frame_cycle=%0d", reset_round + 1, sub_cnt);
            rst          <= 1'b1;
            rst_hold     <= 4;
            inject_reset <= 1'b0;
        end else if (rst_hold > 0) begin
            rst_hold <= rst_hold - 1;
            if (rst_hold == 1)
                rst <= 1'b0;
        end else if (rst) begin
            rst <= 1'b0;                       // run 释放后的正常启动
        end
    end

    // -------------------------------------------------- 帧比较与负面控制 ---
    always @(posedge dec_valid) begin
        if (!rst) begin
            if (q_count == 0)
                $fatal(1, "%m: 解码出帧但期望队列为空");
            exp_l   = q_l[q_head];
            exp_r   = q_r[q_head];
            q_head  = (q_head + 1) % QDEPTH;
            q_count = q_count - 1;

            if ((dec_l !== exp_l) || (dec_r !== exp_r))
                $fatal(1, "%m: 第 %0d 帧解码不一致 L=%h/%h R=%h/%h",
                       frames_seen, dec_l, exp_l, dec_r, exp_r);
            if (((slot_l & PADDING_MASK) !== 32'd0) || ((slot_r & PADDING_MASK) !== 32'd0))
                $fatal(1, "S3_PADDING_NONZERO: %m 数据后的填充位不是零");

            // 负面控制：错误偏移、声道互换、单比特翻转都必须能被察觉。
            if ((slot_l[31 -: DATA_BITS] !== exp_l) || (slot_r[31 -: DATA_BITS] !== exp_r))
                m_neg_lj <= m_neg_lj + 1;
            if ((slot_l[DATA_BITS-1:0] !== exp_l) || (slot_r[DATA_BITS-1:0] !== exp_r))
                m_neg_rj <= m_neg_rj + 1;
            if ((dec_l !== exp_r) || (dec_r !== exp_l))
                m_neg_swap <= m_neg_swap + 1;
            if (((dec_l ^ {{(DATA_BITS-1){1'b0}}, 1'b1}) !== exp_l) ||
                ((dec_r ^ {{(DATA_BITS-1){1'b0}}, 1'b1}) !== exp_r))
                m_neg_flip <= m_neg_flip + 1;

            frames_seen <= frames_seen + 1;
            m_frames    <= m_frames + 1;
            if (probe_wait_left > 0) begin
                probe_wait_left <= probe_wait_left - 1;
                if (probe_wait_left == 1) begin
                    if ((exp_l !== probe_l) || (exp_r !== probe_r) || dec_l == 0 || dec_r == 0)
                        $fatal(1, "S3_RESET_PROBE: %m 复位后未解出双路非零探针");
                    $display("S3_RESET_RECOVERED: %m round=%0d L=%h R=%h", reset_round, dec_l, dec_r);
                    m_resets <= m_resets + 1;
                end
            end
        end
    end

    // ------------------------------------------------------------ 结束条件 ---
    always @(posedge clk) begin
        // 三次复位恢复都完成后即可收尾；此后仍在推入期望，队列不会空，所以不把队列空当条件。
        if (run && finishing && (reset_round >= N_RESET) && (probe_wait_left == 0))
            done <= 1'b1;
    end

endmodule
