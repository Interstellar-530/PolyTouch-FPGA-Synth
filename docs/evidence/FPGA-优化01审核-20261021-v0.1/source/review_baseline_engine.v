// 共享波表引擎原型：4 个声部共用 1 个 sine ROM 与 1 个 bright ROM，
// 用一条 FSM 按时分复用完成“相邻地址读取 -> 9 位插值 -> 包络缩放 -> 力度缩放”，
// 输出两条分量和（sine 和、bright 和），交叉混合交给全局模块做一次。
//
// 与逐声部版（wavetable_osc_dual_s6 + poly_voice_s6 的逐声部混合）的差别：
//   * ROM：整机 2 个，而不是每声部 2 个（同 512 点表）；
//   * 乘法器：整机只写一条乘法表达式（乘数与被乘数来自 mux），综合后约 1-2 个；
//   * 交叉混合：全局一次（global_crossfade.v），而不是每声部一次。
// 默认兼容路径每声部15拍，含共享弯音19拍，带限时27拍。
// 标准档每帧256拍，调试档576拍；四声部带限引擎108拍。
// EXTRA_FRACTION_BITS=0保留旧数值；生产值2保留两个小数位并就近舍入。
//
// 数值口径与逐声部版一致的地方：插值 (yb-ya)*frac + 256 >>> 9；包络缩放取
// [31:16]、力度缩放取 [22:7]。唯一不同的是交叉混合的舍入位置，
// 偏差界记录在集成复核记录里。
module review_baseline_engine #(
    parameter integer BEND_SHARED_ENABLE = 0,
    parameter integer SHARED_MULT_ENABLE = 0,
    parameter integer BANDLIMIT_ENABLE = 0,
    parameter integer GENERIC_BRIGHT_ENABLE = 0,
    parameter integer GUITAR_ENABLE = 0,
    parameter integer KEY_GAIN_ENABLE = 0,
    parameter integer ZONE_LATCH_ENABLE = 0,
    parameter integer STAGE_TIME_ENABLE = 0,
    parameter integer STAGE_STEP_SAMPLES = 5859,
    parameter integer VOICES8 = 0,
    parameter integer EXTRA_FRACTION_BITS = 0
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    input  wire [31:0]        inc0, inc1, inc2, inc3,
    input  wire [31:0]        inc4, inc5, inc6, inc7,
    input  wire               retrig0, retrig1, retrig2, retrig3,
    input  wire               retrig4, retrig5, retrig6, retrig7,
    input  wire [15:0]        env0, env1, env2, env3,
    input  wire [15:0]        env4, env5, env6, env7,
    input  wire [7:0]         vel0, vel1, vel2, vel3,
    input  wire [7:0]         vel4, vel5, vel6, vel7,
    input  wire [6:0]         note0, note1, note2, note3,
    input  wire [6:0]         note4, note5, note6, note7,
    input  wire               piano_enable,
    input  wire               guitar_enable,
    input  wire [2:0]         piano_tone,
    output reg signed [18+EXTRA_FRACTION_BITS:0]  sine_sum,
    output reg signed [18+EXTRA_FRACTION_BITS:0]  bright_sum,
    output reg                sums_valid,
    input wire [16:0]         bend_ratio_q16,
    output wire mult_request,
    output wire signed [17:0] mult_operand_a,mult_operand_b,
    input wire signed [35:0] mult_result
);

    // ---------------------------------------------------- phase accumulators ---
    reg [31:0] phase_v [0:7];
    localparam integer NV = (VOICES8 != 0) ? 8 : 4;
    localparam integer STAGE_STEP = (STAGE_STEP_SAMPLES > 0) ? STAGE_STEP_SAMPLES : 1;

    // 每声部输入的数组视图，便于用 for 循环展开 4/8 声部。
    wire [31:0] inc_v    [0:7];
    wire        retrig_v [0:7];
    wire [15:0] env_v    [0:7];
    wire [7:0]  vel_v    [0:7];
    assign inc_v[0]=inc0; assign inc_v[1]=inc1; assign inc_v[2]=inc2; assign inc_v[3]=inc3;
    assign inc_v[4]=inc4; assign inc_v[5]=inc5; assign inc_v[6]=inc6; assign inc_v[7]=inc7;
    assign retrig_v[0]=retrig0; assign retrig_v[1]=retrig1;
    assign retrig_v[2]=retrig2; assign retrig_v[3]=retrig3;
    assign retrig_v[4]=retrig4; assign retrig_v[5]=retrig5;
    assign retrig_v[6]=retrig6; assign retrig_v[7]=retrig7;
    assign env_v[0]=env0; assign env_v[1]=env1; assign env_v[2]=env2; assign env_v[3]=env3;
    assign env_v[4]=env4; assign env_v[5]=env5; assign env_v[6]=env6; assign env_v[7]=env7;
    assign vel_v[0]=vel0; assign vel_v[1]=vel1; assign vel_v[2]=vel2; assign vel_v[3]=vel3;
    assign vel_v[4]=vel4; assign vel_v[5]=vel5; assign vel_v[6]=vel6; assign vel_v[7]=vel7;

    localparam [5:0] ST_IDLE     = 5'd0,
                     ST_ADDR_A   = 5'd1,  ST_LATCH_A = 5'd2,
                     ST_ADDR_B   = 5'd3,  ST_LATCH_B = 5'd4,
                     ST_DIFF_S   = 5'd5,  ST_W_DIFF_S = 5'd6,  ST_INTERP_S = 5'd7,
                     ST_DIFF_B   = 5'd8,  ST_W_DIFF_B = 5'd9,  ST_INTERP_B = 5'd10,
                     ST_ENV_S    = 5'd11, ST_W_ENV_S  = 5'd12, ST_VEL_S    = 5'd13,
                     ST_W_VEL_S  = 5'd14, ST_FIN_S    = 5'd15,
                     ST_ENV_B    = 5'd16, ST_W_ENV_B  = 5'd17, ST_VEL_B    = 5'd18,
                     ST_W_VEL_B  = 5'd19, ST_FIN_B    = 5'd20,
                     ST_ACC      = 5'd21,
                     ST_BEND_LO=5'd22, ST_BEND_HI=5'd23,
                     ST_BEND_WAIT=5'd24, ST_BEND_APPLY=5'd25,
                     ST_BANK_ADDR_A=6'd26, ST_BANK_LATCH_A=6'd27,
                     ST_BANK_ADDR_B=6'd28, ST_BANK_LATCH_B=6'd29,
                     ST_BANK_MUL=6'd30, ST_BANK_INTERP=6'd31,
                     ST_BANK_MIX_MUL=6'd32, ST_BANK_MIX_APPLY=6'd33,
                     ST_GAIN_SET=6'd34, ST_GAIN_WAIT=6'd35, ST_GAIN_LATCH=6'd36;

    reg [5:0]  state = ST_IDLE;

    // ------------------------------------------------------- shared ROM ports ---
    // CE 必须覆盖 b 的读取窗口：地址在 LATCH_A 期间切到 idx_b，
    // 数据在 ADDR_B 这一拍被 pROM 寄存，因此在 LATCH_B 捕获。
    wire        rom_ce = (state == ST_ADDR_A) || (state == ST_LATCH_A) ||
                         (state == ST_ADDR_B);
    reg  [8:0]  rom_addr = 9'd0;
    wire [15:0] rom_sine_d, rom_bright_d;
    wire [15:0] bright_piano_d, bright_generic_d, bright_legacy_d, guitar_d;
    reg         piano_sel_q = 1'b0, guitar_sel_q = 1'b0;

    gowin_prom_wave_sine u_sine_rom (
        .clk(clk), .ce(rom_ce), .rst(rst), .addr(rom_addr), .dout(rom_sine_d));
    reg [6:0] rom_bank=0,bank_low=0;
    reg [15:0] bank_weight=0;
    wire bank_ce=rom_ce || state==ST_BANK_ADDR_A ||
                 state==ST_BANK_LATCH_A || state==ST_BANK_ADDR_B;
    generate
        if(BANDLIMIT_ENABLE) begin:g_banked
            gowin_prom_piano_bank u_piano_rom (
                .clk(clk),.ce(bank_ce),.rst(rst),.bank(rom_bank[5:0]),.addr(rom_addr),.dout(bright_piano_d));
            if(GENERIC_BRIGHT_ENABLE) begin:g_generic
                // 非钢琴音色走 6 级通用明亮表（3 块 BSRAM），不再把 bank 0..4 误当钢琴表。
                // piano_sel_q 在 ST_ADDR_A 与本帧 bank/地址同拍锁存，整个读取窗口保持稳定；
                // 钢琴路径的选择与改动前逐位相同，只有 piano_enable=0 时切到通用表。
                gowin_prom_bright_bank u_bright_rom (
                    .clk(clk),.ce(bank_ce),.rst(rst),.bank(rom_bank[2:0]),.addr(rom_addr),.dout(bright_generic_d));
                if(GUITAR_ENABLE) begin:g_guitar
                    // 6 张带限吉他表，3 块 BSRAM；与钢琴/通用表共用 bank 地址。
                    gowin_prom_guitar_bank u_guitar_rom (
                        .clk(clk),.ce(bank_ce),.rst(rst),.bank(rom_bank[5:0]),.addr(rom_addr),.dout(guitar_d));
                    assign rom_bright_d = guitar_sel_q ? guitar_d :
                                          (piano_sel_q ? bright_piano_d : bright_generic_d);
                end else begin:g_no_guitar
                    assign rom_bright_d = piano_sel_q ? bright_piano_d : bright_generic_d;
                end
            end else begin:g_piano_only
                assign rom_bright_d = bright_piano_d;
            end
        end else begin:g_original
            gowin_prom_wave_bright u_bright_rom (
                .clk(clk), .ce(rom_ce), .rst(rst), .addr(rom_addr), .dout(bright_legacy_d));
            assign rom_bright_d = bright_legacy_d;
        end
    endgenerate

    // Each richer bank reaches zero weight before its highest harmonic reaches
    // Nyquist. Frequency is the actual bent phase increment, so Fs cancels.
    function [18:0] band_config;
        input [31:0] inc;
        begin
            if(inc>=32'h40000000) band_config={3'd4,16'd0};
            else if(inc>=32'h20000000) band_config={3'd3,inc[28:13]};
            else if(inc>=32'h10000000) band_config={3'd2,inc[27:12]};
            else if(inc>=32'h08000000) band_config={3'd1,inc[26:11]};
            else if(inc>=32'h04000000) band_config={3'd0,inc[25:10]};
            else band_config=19'd0;
        end
    endfunction

    // Piano mode uses all six ROM slots as a continuous body-to-hammer
    // sequence. The upper envelope bits advance toward the hammer tables;
    // the lower bits interpolate between adjacent stages.
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

    // 36-table e-piano layout: bank = zone*6 + stage. stage 5 is the bright
    // attack; the engine walks toward stage 0 (body). A 0..5 stage is absolute.
    function [22:0] piano_band_config;
        input [2:0] stage;
        input [2:0] zone;
        input [12:0] frac;
        reg [5:0] bank;
        begin
            if (stage >= 3'd5) begin
                bank = {3'd0, zone} * 6'd6 + 6'd4;
                piano_band_config = {1'b0, bank, 16'hffff};
            end else begin
                bank = {3'd0, zone} * 6'd6 + {3'd0, stage};
                piano_band_config = {1'b0, bank, {frac, 3'b000}};
            end
        end
    endfunction

    // 当前声部的相位/参数
    reg [2:0]  vsel = 3'd0;
    reg [31:0] cur_phase;
    reg [15:0] cur_env;
    reg [7:0]  cur_vel;
    reg [255:0] inc_frame;
    reg [63:0] velocity_frame;
    reg [55:0] note_frame;
    reg [14:0] key_a = 15'd0;
    reg [6:0]  cur_note;
    reg [16:0] ratio_frame, phase_low;
    reg [7:0]  retrig_frame;
    // The shared multiplier result is used by shared_inc below, so keep these
    // declarations before the first continuous assignment that reads it.
    reg  signed [17:0] mul_a = 18'sd0;
    reg  signed [17:0] mul_b = 18'sd0;
    reg signed [35:0] local_product = 0;
    wire signed [35:0] mul_p = SHARED_MULT_ENABLE ? mult_result : local_product;
    wire [31:0] cur_inc = inc_frame >> (vsel*32);
    wire [31:0] shared_inc = mul_p[31:0] + {15'd0,phase_low};
    reg [31:0] bent_inc=0;
    wire [31:0] piano_inc = BEND_SHARED_ENABLE ? bent_inc : cur_inc;

    // P1：音区在起音时锁存（用未弯音的 inc），弯音不再把音符硬切到相邻音区；
    // 音色阶段由独立计时器推进，不再借用包络高 3 位，因此 F5/tone 不会长期钉在最亮阶段。
    reg [2:0]  zone_q  [0:7];
    reg [2:0]  stage_q [0:7];
    reg [15:0] stage_timer [0:7];
    integer    vz;

    // 6 段吉他频段：MIDI 48/60/67/76/84 为边界，返回 {bank, weight}。
    // 36-table guitar layout: bank = band*6 + variant. Variant follows the
    // velocity top bits (0..5), so soft notes use green/p and hard notes
    // progress toward black/f. Six MIDI bands cover E2..E6.
    function [22:0] guitar_band_config;
        input [31:0] inc;
        input [7:0] vel;
        reg [2:0] band;
        reg [2:0] variant;
        reg [5:0] bank;
        begin
            if (inc < 32'd11985848) band = 3'd0;
            else if (inc < 32'd23971696) band = 3'd1;
            else if (inc < 32'd35916962) band = 3'd2;
            else if (inc < 32'd60404889) band = 3'd3;
            else if (inc < 32'd95886784) band = 3'd4;
            else band = 3'd5;
            if (band <= 3'd1) begin
                // 低音区没有 E2 采样，统一用 green/f，避免 p 的噪声底被放大。
                if (vel >= 8'd112) variant = 3'd5;
                else variant = 3'd2;
            end else begin
                if (vel >= 8'd112) variant = 3'd5;
                else if (vel >= 8'd96) variant = 3'd4;
                else if (vel >= 8'd64) variant = 3'd2;
                else if (vel >= 8'd32) variant = 3'd1;
                else variant = 3'd0;
            end
            bank = {3'd0, band} * 6'd6 + {3'd0, variant};
            guitar_band_config = {1'b0, bank, 16'h0000};
        end
    endfunction

    wire [2:0] cur_zone  = ZONE_LATCH_ENABLE ? zone_q[vsel] : piano_zone(piano_inc);
    wire [15:0] cur_stage_timer = stage_timer[vsel];
    // 起音从较亮表开始，随时间连续衰减到琴体表（不是从琴体走向击弦并停住）。
    // F1-F3 从第 4 级起步（跳过最硬的第 5 级），F4-F5 从第 5 级起步。
    wire [2:0] start_stage = (piano_tone >= 3'd3) ? 3'd4 : 3'd3;
    wire [2:0] stage_pos = (stage_q[vsel] < start_stage) ?
                           (start_stage - stage_q[vsel]) : 3'd0;
    wire [2:0] cur_stage = STAGE_TIME_ENABLE ? stage_pos : cur_env[15:13];
    // 权重从 1 连续降到 0：到本阶段末尾正好等于下一张表，切级时不跳变。
    wire [12:0] cur_frac = STAGE_TIME_ENABLE ?
                           (13'd8191 - cur_stage_timer[12:0]) : cur_env[12:0];
    // STAGE_TIME_ENABLE=1 时 stage_pos 已是绝对 0..5，tone 传 0；旧模式保留原语义。
    // Shared 25-entry 0..-6 dB ramp. Guitar uses the first 21 entries and
    // clamps at -5 dB; piano clamps at -6 dB. 256=1.0, 128=-6 dB.
    function [8:0] key_coeff;
        input [6:0] note;
        input guitar;
        input enable;
        reg [5:0] idx;
        begin
            if (!enable) key_coeff = 9'd256;
            else if (note <= 7'd60) key_coeff = 9'd256;
            else begin
                idx = note - 7'd60;
                if (guitar && idx > 6'd20) idx = 6'd20;
                if (!guitar && idx > 6'd24) idx = 6'd24;
                case (idx)
                    6'd0:  key_coeff = 9'd256; 6'd1:  key_coeff = 9'd249;
                    6'd2:  key_coeff = 9'd242; 6'd3:  key_coeff = 9'd235;
                    6'd4:  key_coeff = 9'd228; 6'd5:  key_coeff = 9'd222;
                    6'd6:  key_coeff = 9'd215; 6'd7:  key_coeff = 9'd209;
                    6'd8:  key_coeff = 9'd203; 6'd9:  key_coeff = 9'd198;
                    6'd10: key_coeff = 9'd192; 6'd11: key_coeff = 9'd187;
                    6'd12: key_coeff = 9'd181; 6'd13: key_coeff = 9'd176;
                    6'd14: key_coeff = 9'd171; 6'd15: key_coeff = 9'd166;
                    6'd16: key_coeff = 9'd162; 6'd17: key_coeff = 9'd157;
                    6'd18: key_coeff = 9'd152; 6'd19: key_coeff = 9'd148;
                    6'd20: key_coeff = 9'd144; 6'd21: key_coeff = 9'd140;
                    6'd22: key_coeff = 9'd136; 6'd23: key_coeff = 9'd132;
                    default: key_coeff = 9'd128;
                endcase
            end
        end
    endfunction

    wire key_enable = KEY_GAIN_ENABLE && (piano_enable || guitar_enable);
    wire [22:0] guitar_band = guitar_band_config(piano_inc, cur_vel);
    wire [22:0] selected_band = (GUITAR_ENABLE && guitar_enable) ? guitar_band :
        piano_enable ?
        piano_band_config(cur_stage, cur_zone, cur_frac) :
        {4'd0,band_config(piano_inc)};

    always @(posedge clk) begin
        if (rst) begin
            for (vz = 0; vz < 8; vz = vz + 1) begin
                zone_q[vz] <= 3'd0;
                stage_q[vz] <= 3'd0;
                stage_timer[vz] <= 16'd0;
            end
        end else if (sample_tick) begin
            for (vz = 0; vz < NV; vz = vz + 1) begin
                if (retrig_v[vz]) begin
                    zone_q[vz] <= piano_zone(inc_v[vz]);
                    stage_q[vz] <= 3'd0;
                    stage_timer[vz] <= 16'd0;
                end else if (stage_q[vz] >= start_stage) begin
                    // 已到琴体表：计时器停在阶段末，保持 frac=0，不再周期性跳回上一张表。
                    stage_timer[vz] <= STAGE_STEP - 1;
                end else if (stage_timer[vz] >= STAGE_STEP - 1) begin
                    stage_timer[vz] <= 16'd0;
                    stage_q[vz] <= stage_q[vz] + 1'b1;
                end else stage_timer[vz] <= stage_timer[vz] + 1'b1;
            end
        end
    end

    always @* begin
        cur_phase = phase_v[vsel];
        cur_env   = env_v[vsel];
        cur_vel   = velocity_frame[vsel*8 +: 8];
        cur_note  = note_frame[vsel*7 +: 7];
    end

    // ------------------------------------------------------------- 共享乘法器 ---
    // 全模块只写这一条乘法表达式：插值、包络缩放、力度缩放共用同一对寄存器，
    // 由 FSM 在不同节拍装入不同操作数，因此综合后只有一组乘法器。
    // Differences need 17 signed bits, samples at most 18, unsigned envelopes
    // 17 and velocity 9. A single signed 18x18 operation covers every stage.
    wire mul_enable = (state == ST_GAIN_WAIT) || (state == ST_DIFF_B) || (state == ST_INTERP_S) ||
                      (state == ST_W_ENV_S) || (state == ST_W_VEL_S) ||
                      (state == ST_W_ENV_B) || (state == ST_W_VEL_B) ||
                      (state == ST_BEND_HI) || (state == ST_BEND_WAIT) ||
                      (BANDLIMIT_ENABLE && ((state==ST_BANK_MUL) || (state==ST_BANK_MIX_MUL)));
    assign mult_request=mul_enable;
    assign mult_operand_a=mul_a;
    assign mult_operand_b=mul_b;

    // ------------------------------------------------------------------- FSM ---
    // Interpolation products are issued on consecutive clocks and read on
    // consecutive clocks. Envelope/velocity keep their original two-edge
    // dependency. Only the six useful products per voice enable the register.

    reg [8:0]  frac_q = 9'd0;
    reg signed [15:0] a_sine = 16'sd0, b_sine = 16'sd0;
    reg signed [15:0] a_bright = 16'sd0, b_bright = 16'sd0;
    reg signed [17:0] interp_s = 18'sd0, interp_b = 18'sd0;
    reg signed [15:0] bank_a=0;
    wire signed [35:0] interpolation_delta = (mul_p + (36'sd256 >>> EXTRA_FRACTION_BITS)) >>> (9-EXTRA_FRACTION_BITS);
    wire signed [17:0] bank_interpolated = ($signed(bank_a) <<< EXTRA_FRACTION_BITS) + interpolation_delta;
    wire signed [35:0] bank_mixed_delta = (mul_p + 36'sd32768) >>> 16;
    reg signed [15+EXTRA_FRACTION_BITS:0] scaled_s = 0, scaled_b = 0;
    reg signed [18+EXTRA_FRACTION_BITS:0] sine_acc = 0, bright_acc = 0;
    reg [15:0] env_q = 16'd0;
    reg [7:0]  vel_q = 8'd0;

    // 累加前必须按 16 位有符号符号扩展：{13'd0, scaled_s} 会把它当无符号数：
    // −20840 会变成 +44744，在输出上留下约半个满量程的直流偏置。
    wire signed [18+EXTRA_FRACTION_BITS:0] scaled_s_ext = {{3{scaled_s[15+EXTRA_FRACTION_BITS]}}, scaled_s};
    wire signed [18+EXTRA_FRACTION_BITS:0] scaled_b_ext = {{3{scaled_b[15+EXTRA_FRACTION_BITS]}}, scaled_b};
    wire signed [17:0] envelope_result=(mul_p+(EXTRA_FRACTION_BITS>0?36'sd32768:36'sd0)) >>> 16;
    // A = vel_raw * C (15 bit). C=256 makes this exactly the old *vel/128 path.
    wire signed [15+EXTRA_FRACTION_BITS:0] amp_result=(mul_p+(EXTRA_FRACTION_BITS>0?36'sd16384:36'sd0)) >>> 15;
    wire signed [18+EXTRA_FRACTION_BITS:0] amp_result_ext={{3{amp_result[15+EXTRA_FRACTION_BITS]}},amp_result};
`ifdef SIMULATION
    initial if(EXTRA_FRACTION_BITS<0 || EXTRA_FRACTION_BITS>2)
        $fatal(1,"EXTRA_FRACTION_BITS must be 0..2 for the 18x18 datapath");
`endif

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            vsel <= 3'd0;
            sine_acc <= 19'sd0;
            bright_acc <= 19'sd0;
            sums_valid <= 1'b0;
            sine_sum <= 19'sd0;
            bright_sum <= 19'sd0;
            phase_v[0]<=0;phase_v[1]<=0;phase_v[2]<=0;phase_v[3]<=0;
            phase_v[4]<=0;phase_v[5]<=0;phase_v[6]<=0;phase_v[7]<=0;
            inc_frame<=0;ratio_frame<=65536;retrig_frame<=0;phase_low<=0;
            velocity_frame<=0;note_frame<=0;key_a<=15'd0;
            rom_bank<=0;bank_low<=0;bank_weight<=0;bent_inc<=0;bank_a<=0;piano_sel_q<=1'b0;guitar_sel_q<=1'b0;
        end else begin
            sums_valid <= 1'b0;
            if(sample_tick && BEND_SHARED_ENABLE==0) begin
                for (vz = 0; vz < NV; vz = vz + 1)
                    phase_v[vz] <= retrig_v[vz] ? 32'd0 : phase_v[vz] + inc_v[vz];
            end
            if (!SHARED_MULT_ENABLE && mul_enable) local_product <= mul_a * mul_b;
            case (state)
                ST_IDLE: begin
                    if (sample_tick) begin
                        vsel       <= 3'd0;
                        sine_acc   <= 19'sd0;
                        bright_acc <= 19'sd0;
                        inc_frame<={inc_v[7],inc_v[6],inc_v[5],inc_v[4],inc_v[3],inc_v[2],inc_v[1],inc_v[0]};
                        ratio_frame<=bend_ratio_q16;
                        velocity_frame<={vel_v[7],vel_v[6],vel_v[5],vel_v[4],vel_v[3],vel_v[2],vel_v[1],vel_v[0]};
                        note_frame<={note7,note6,note5,note4,note3,note2,note1,note0};
                        retrig_frame<={retrig_v[7],retrig_v[6],retrig_v[5],retrig_v[4],retrig_v[3],retrig_v[2],retrig_v[1],retrig_v[0]};
                        state <= ST_GAIN_SET;
                    end
                end
                ST_BEND_LO: begin
                    mul_a<=$signed({2'd0,cur_inc[15:0]});mul_b<=$signed({1'b0,ratio_frame});
                    state<=ST_BEND_HI;
                end
                ST_BEND_HI: begin
                    mul_a<=$signed({2'd0,cur_inc[31:16]});mul_b<=$signed({1'b0,ratio_frame});
                    state<=ST_BEND_WAIT;
                end
                ST_BEND_WAIT: begin phase_low<=mul_p[32:16];state<=ST_BEND_APPLY;end
                ST_BEND_APPLY: begin
                    bent_inc<=shared_inc;
                    // 只推进当前 vsel 的相位；shared_inc 是“这个声部”的弯音后增量。
                    // 8 声部时若在这里 for 全部相位，会把当前声部的增量加到别的声部上。
                    phase_v[vsel] <= retrig_frame[vsel] ? 32'd0 : phase_v[vsel] + shared_inc;
                    state<=ST_ADDR_A;
                end
                ST_GAIN_SET: begin
                    mul_a <= $signed({8'd0, cur_vel});
                    mul_b <= $signed({9'd0, key_coeff(cur_note, guitar_enable, key_enable)});
                    state <= ST_GAIN_WAIT;
                end
                ST_GAIN_WAIT: begin
                    state <= ST_GAIN_LATCH;
                end
                ST_GAIN_LATCH: begin
                    key_a <= mul_p[14:0];
                    state <= BEND_SHARED_ENABLE ? ST_BEND_LO : ST_ADDR_A;
                end
                ST_ADDR_A: begin
                    if(BANDLIMIT_ENABLE) begin
                        bank_low<=selected_band[22:16];rom_bank<=selected_band[22:16];
                        bank_weight<=selected_band[15:0];
                        piano_sel_q<=piano_enable;guitar_sel_q<=guitar_enable;
                    end
                    rom_addr <= cur_phase[31:23];
                    frac_q   <= cur_phase[22:14];
                    state    <= ST_LATCH_A;
                end
                ST_LATCH_A: begin
                    rom_addr <= cur_phase[31:23] + 9'd1;
                    state    <= ST_ADDR_B;
                end
                ST_ADDR_B: begin
                    a_sine   <= rom_sine_d;             // idx_a 的数据此刻有效
                    a_bright <= rom_bright_d;
                    state    <= ST_LATCH_B;
                end
                ST_LATCH_B: begin
                    b_sine   <= rom_sine_d;             // idx_b 的数据此刻有效
                    b_bright <= rom_bright_d;
                    mul_a <= $signed({rom_sine_d[15],rom_sine_d}) - $signed({a_sine[15],a_sine});
                    mul_b <= {9'd0,frac_q};
                    state <= ST_DIFF_B;
                end
                ST_DIFF_S: begin
                    mul_a <= $signed(b_sine) - $signed(a_sine);
                    mul_b <= {23'd0, frac_q};
                    state <= ST_W_DIFF_S;
                end
                ST_W_DIFF_S: begin
                    state <= ST_INTERP_S;
                end
                ST_INTERP_S: begin
                    interp_s <= ($signed(a_sine) <<< EXTRA_FRACTION_BITS) + interpolation_delta;
                    state    <= ST_INTERP_B;
                end
                ST_DIFF_B: begin
                    mul_a <= $signed(b_bright) - $signed(a_bright);
                    mul_b <= {9'd0, frac_q};
                    state <= ST_INTERP_S;
                end
                ST_W_DIFF_B: begin
                    state <= ST_INTERP_B;
                end
                ST_INTERP_B: begin
                    interp_b <= ($signed(a_bright) <<< EXTRA_FRACTION_BITS) + interpolation_delta;
                    env_q    <= cur_env;
                    vel_q    <= cur_vel;
                    mul_a <= $signed(interp_s);
                    mul_b <= $signed({2'd0,cur_env});
                    state <= BANDLIMIT_ENABLE ? ST_BANK_ADDR_A : ST_W_ENV_S;
                end
                ST_BANK_ADDR_A: begin
                    rom_bank<=bank_low+7'd1;
                    rom_addr<=cur_phase[31:23];state<=ST_BANK_LATCH_A;
                end
                ST_BANK_LATCH_A: begin
                    rom_addr<=cur_phase[31:23]+9'd1;state<=ST_BANK_ADDR_B;
                end
                ST_BANK_ADDR_B: begin bank_a<=rom_bright_d;state<=ST_BANK_LATCH_B;end
                ST_BANK_LATCH_B: begin
                    mul_a<=$signed({rom_bright_d[15],rom_bright_d})-$signed({bank_a[15],bank_a});
                    mul_b<={9'd0,frac_q};state<=ST_BANK_MUL;
                end
                ST_BANK_MUL: state<=ST_BANK_INTERP;
                ST_BANK_INTERP: begin
                    mul_a<=bank_interpolated-interp_b;
                    mul_b<=$signed({2'd0,bank_weight});state<=ST_BANK_MIX_MUL;
                end
                ST_BANK_MIX_MUL: state<=ST_BANK_MIX_APPLY;
                ST_BANK_MIX_APPLY: begin
                    interp_b<=interp_b+bank_mixed_delta;
                    mul_a<=interp_s;mul_b<=$signed({2'd0,env_q});state<=ST_W_ENV_S;
                end
                ST_ENV_S: begin
                    mul_a <= $signed(interp_s);
                    mul_b <= $signed({16'd0, env_q});
                    state <= ST_W_ENV_S;
                end
                ST_W_ENV_S: begin
                    state <= ST_VEL_S;
                end
                ST_VEL_S: begin
                    mul_a <= envelope_result;
                    mul_b <= $signed({3'd0, key_a});
                    state <= ST_W_VEL_S;
                end
                ST_W_VEL_S: begin
                    state <= ST_FIN_S;
                end
                ST_FIN_S: begin
                    scaled_s <= amp_result;
                    mul_a <= $signed(interp_b);
                    mul_b <= $signed({2'd0,env_q});
                    state <= ST_W_ENV_B;
                end
                ST_ENV_B: begin
                    mul_a <= $signed(interp_b);
                    mul_b <= $signed({16'd0, env_q});
                    state <= ST_W_ENV_B;
                end
                ST_W_ENV_B: begin
                    state <= ST_VEL_B;
                end
                ST_VEL_B: begin
                    mul_a <= envelope_result;
                    mul_b <= $signed({3'd0, key_a});
                    state <= ST_W_VEL_B;
                end
                ST_W_VEL_B: begin
                    state <= ST_FIN_B;
                end
                ST_FIN_B: begin
                    scaled_b <= amp_result;
                    sine_acc <= sine_acc + scaled_s_ext;
                    bright_acc <= bright_acc + amp_result_ext;
                    if(vsel==NV-1) begin
                        sine_sum <= sine_acc + scaled_s_ext;
                        bright_sum <= bright_acc + amp_result_ext;
                        sums_valid<=1'b1;state<=ST_IDLE;
                    end else begin vsel<=vsel+1'b1;state<=ST_GAIN_SET;end
                end
                default: begin
                    sine_acc   <= sine_acc + scaled_s_ext;
                    bright_acc <= bright_acc + scaled_b_ext;
                    if (vsel == NV-1) begin
                        sine_sum   <= sine_acc + scaled_s_ext;
                        bright_sum <= bright_acc + scaled_b_ext;
                        sums_valid <= 1'b1;
                        state      <= ST_IDLE;
                    end else begin
                        vsel  <= vsel + 3'd1;
                        state <= ST_GAIN_SET;
                    end
                end
            endcase
        end
    end
endmodule
