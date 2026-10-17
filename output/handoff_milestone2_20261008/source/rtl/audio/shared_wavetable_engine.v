// 共享波表引擎原型：4 个声部共用 1 个 sine ROM 与 1 个 bright ROM，
// 用一条 FSM 按时分复用完成“相邻地址读取 -> 9 位插值 -> 包络缩放 -> 力度缩放”，
// 输出两条分量和（sine 和、bright 和），交叉混合交给全局模块做一次。
//
// 与逐声部版（wavetable_osc_dual_s6 + poly_voice_s6 的逐声部混合）的差别：
//   * ROM：整机 2 个，而不是每声部 2 个（同 512 点表）；
//   * 乘法器：整机只写一条乘法表达式（乘数与被乘数来自 mux），综合后约 1-2 个；
//   * 交叉混合：全局一次（global_crossfade.v），而不是每声部一次。
// 无弯音时每声部15拍，含共享弯音时19拍（四声部76拍）。
// 标准档每帧256拍，调试档576拍；新增弯音仍复用同一乘法器。
// 分量和是 19 位，插值/包络/力度仍保持原来的逐级舍入位置。
//
// 数值口径与逐声部版一致的地方：插值 (yb-ya)*frac + 256 >>> 9；包络缩放取
// [31:16]、力度缩放取 [22:7]。唯一不同的是交叉混合的舍入位置，
// 偏差界记录在集成复核记录里。
module shared_wavetable_engine #(
    parameter integer BEND_SHARED_ENABLE = 0,
    parameter integer SHARED_MULT_ENABLE = 0,
    parameter integer BANDLIMIT_ENABLE = 0
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    input  wire [31:0]        inc0, inc1, inc2, inc3,
    input  wire               retrig0, retrig1, retrig2, retrig3,
    input  wire [15:0]        env0, env1, env2, env3,
    input  wire [7:0]         vel0, vel1, vel2, vel3,
    output reg signed [18:0]  sine_sum,
    output reg signed [18:0]  bright_sum,
    output reg                sums_valid,
    input wire [16:0]         bend_ratio_q16,
    output wire mult_request,
    output wire signed [17:0] mult_operand_a,mult_operand_b,
    input wire signed [35:0] mult_result
);

    // ---------------------------------------------------- phase accumulators ---
    reg [31:0] phase0 = 32'd0, phase1 = 32'd0, phase2 = 32'd0, phase3 = 32'd0;

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
                     ST_BANK_MIX_MUL=6'd32, ST_BANK_MIX_APPLY=6'd33;

    reg [5:0]  state = ST_IDLE;

    // ------------------------------------------------------- shared ROM ports ---
    // CE 必须覆盖 b 的读取窗口：地址在 LATCH_A 期间切到 idx_b，
    // 数据在 ADDR_B 这一拍被 pROM 寄存，因此在 LATCH_B 捕获。
    wire        rom_ce = (state == ST_ADDR_A) || (state == ST_LATCH_A) ||
                         (state == ST_ADDR_B);
    reg  [8:0]  rom_addr = 9'd0;
    wire [15:0] rom_sine_d, rom_bright_d;

    gowin_prom_wave_sine u_sine_rom (
        .clk(clk), .ce(rom_ce), .rst(rst), .addr(rom_addr), .dout(rom_sine_d));
    reg [2:0] rom_bank=0,bank_low=0;
    reg [15:0] bank_weight=0;
    wire bank_ce=rom_ce || state==ST_BANK_ADDR_A ||
                 state==ST_BANK_LATCH_A || state==ST_BANK_ADDR_B;
    generate if(BANDLIMIT_ENABLE) begin:g_banked
        gowin_prom_bright_bank u_bright_rom (
            .clk(clk),.ce(bank_ce),.rst(rst),.bank(rom_bank),.addr(rom_addr),.dout(rom_bright_d));
    end else begin:g_original
    gowin_prom_wave_bright u_bright_rom (
        .clk(clk), .ce(rom_ce), .rst(rst), .addr(rom_addr), .dout(rom_bright_d));
    end endgenerate

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

    // 当前声部的相位/参数
    reg [1:0]  vsel = 2'd0;
    reg [31:0] cur_phase;
    reg [15:0] cur_env;
    reg [7:0]  cur_vel;
    reg [127:0] inc_frame;
    reg [31:0] velocity_frame;
    reg [16:0] ratio_frame, phase_low;
    reg [3:0] retrig_frame;
    wire [31:0] cur_inc = inc_frame >> (vsel*32);
    wire [31:0] shared_inc = mul_p[31:0] + {15'd0,phase_low};
    reg [31:0] bent_inc=0;
    wire [18:0] selected_band=band_config(BEND_SHARED_ENABLE?bent_inc:cur_inc);

    always @* begin
        case (vsel)
            2'd0:    begin cur_phase = phase0; cur_env = env0; cur_vel = velocity_frame[7:0]; end
            2'd1:    begin cur_phase = phase1; cur_env = env1; cur_vel = velocity_frame[15:8]; end
            2'd2:    begin cur_phase = phase2; cur_env = env2; cur_vel = velocity_frame[23:16]; end
            default: begin cur_phase = phase3; cur_env = env3; cur_vel = velocity_frame[31:24]; end
        endcase
    end

    // ------------------------------------------------------------- 共享乘法器 ---
    // 全模块只写这一条乘法表达式：插值、包络缩放、力度缩放共用同一对寄存器，
    // 由 FSM 在不同节拍装入不同操作数，因此综合后只有一组乘法器。
    // Differences need 17 signed bits, samples at most 18, unsigned envelopes
    // 17 and velocity 9. A single signed 18x18 operation covers every stage.
    reg  signed [17:0] mul_a = 18'sd0;
    reg  signed [17:0] mul_b = 18'sd0;
    reg signed [35:0] local_product = 0;
    wire signed [35:0] mul_p=SHARED_MULT_ENABLE?mult_result:local_product;
    wire mul_enable = (state == ST_DIFF_B) || (state == ST_INTERP_S) ||
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
    wire signed [17:0] bank_interpolated = $signed(bank_a) + $signed((mul_p[26:0]+27'sd256) >>> 9);
    wire signed [35:0] bank_mixed_delta = (mul_p + 36'sd32768) >>> 16;
    reg signed [15:0] scaled_s = 16'sd0, scaled_b = 16'sd0;
    reg signed [18:0] sine_acc = 19'sd0, bright_acc = 19'sd0;
    reg [15:0] env_q = 16'd0;
    reg [7:0]  vel_q = 8'd0;

    // 累加前必须按 16 位有符号符号扩展：{13'd0, scaled_s} 会把它当无符号数：
    // −20840 会变成 +44744，在输出上留下约半个满量程的直流偏置。
    wire signed [18:0] scaled_s_ext = {{3{scaled_s[15]}}, scaled_s};
    wire signed [18:0] scaled_b_ext = {{3{scaled_b[15]}}, scaled_b};

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            vsel <= 2'd0;
            sine_acc <= 19'sd0;
            bright_acc <= 19'sd0;
            sums_valid <= 1'b0;
            sine_sum <= 19'sd0;
            bright_sum <= 19'sd0;
            phase0<=0;phase1<=0;phase2<=0;phase3<=0;
            inc_frame<=0;ratio_frame<=65536;retrig_frame<=0;phase_low<=0;
            velocity_frame<=0;
            rom_bank<=0;bank_low<=0;bank_weight<=0;bent_inc<=0;bank_a<=0;
        end else begin
            sums_valid <= 1'b0;
            if(sample_tick && BEND_SHARED_ENABLE==0) begin
                phase0<=retrig0?0:phase0+inc0;phase1<=retrig1?0:phase1+inc1;
                phase2<=retrig2?0:phase2+inc2;phase3<=retrig3?0:phase3+inc3;
            end
            if (!SHARED_MULT_ENABLE && mul_enable) local_product <= mul_a * mul_b;
            case (state)
                ST_IDLE: begin
                    if (sample_tick) begin
                        vsel       <= 2'd0;
                        sine_acc   <= 19'sd0;
                        bright_acc <= 19'sd0;
                        inc_frame<={inc3,inc2,inc1,inc0};ratio_frame<=bend_ratio_q16;
                        velocity_frame<={vel3,vel2,vel1,vel0};
                        retrig_frame<={retrig3,retrig2,retrig1,retrig0};
                        state <= BEND_SHARED_ENABLE ? ST_BEND_LO : ST_ADDR_A;
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
                    case(vsel)
                        0:phase0<=retrig_frame[0]?0:phase0+shared_inc;
                        1:phase1<=retrig_frame[1]?0:phase1+shared_inc;
                        2:phase2<=retrig_frame[2]?0:phase2+shared_inc;
                        3:phase3<=retrig_frame[3]?0:phase3+shared_inc;
                    endcase
                    state<=ST_ADDR_A;
                end
                ST_ADDR_A: begin
                    if(BANDLIMIT_ENABLE) begin
                        bank_low<=selected_band[18:16];rom_bank<=selected_band[18:16];
                        bank_weight<=selected_band[15:0];
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
                    interp_s <= $signed(a_sine) + $signed((mul_p[26:0] + 27'sd256) >>> 9);
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
                    interp_b <= $signed(a_bright) + $signed((mul_p[26:0] + 27'sd256) >>> 9);
                    env_q    <= cur_env;
                    vel_q    <= cur_vel;
                    mul_a <= $signed(interp_s);
                    mul_b <= $signed({2'd0,cur_env});
                    state <= BANDLIMIT_ENABLE ? ST_BANK_ADDR_A : ST_W_ENV_S;
                end
                ST_BANK_ADDR_A: begin
                    rom_bank<=bank_low==4?3'd4:bank_low+3'd1;
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
                    mul_a <= $signed(mul_p[31:16]);     // (interp*env) >> 16
                    mul_b <= $signed({10'd0, vel_q});
                    state <= ST_W_VEL_S;
                end
                ST_W_VEL_S: begin
                    state <= ST_FIN_S;
                end
                ST_FIN_S: begin
                    scaled_s <= $signed(mul_p[22:7]);   // (voiced*vel) >> 7
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
                    mul_a <= $signed(mul_p[31:16]);
                    mul_b <= $signed({10'd0, vel_q});
                    state <= ST_W_VEL_B;
                end
                ST_W_VEL_B: begin
                    state <= ST_FIN_B;
                end
                ST_FIN_B: begin
                    scaled_b <= $signed(mul_p[22:7]);
                    sine_acc <= sine_acc + scaled_s_ext;
                    bright_acc <= bright_acc + {{3{mul_p[22]}},mul_p[22:7]};
                    if(vsel==3) begin
                        sine_sum <= sine_acc + scaled_s_ext;
                        bright_sum <= bright_acc + {{3{mul_p[22]}},mul_p[22:7]};
                        sums_valid<=1'b1;state<=ST_IDLE;
                    end else begin vsel<=vsel+1'b1;state<=BEND_SHARED_ENABLE?ST_BEND_LO:ST_ADDR_A;end
                end
                default: begin
                    sine_acc   <= sine_acc + scaled_s_ext;
                    bright_acc <= bright_acc + scaled_b_ext;
                    if (vsel == 2'd3) begin
                        sine_sum   <= sine_acc + scaled_s_ext;
                        bright_sum <= bright_acc + scaled_b_ext;
                        sums_valid <= 1'b1;
                        state      <= ST_IDLE;
                    end else begin
                        vsel  <= vsel + 2'd1;
                        state <= ST_ADDR_A;
                    end
                end
            endcase
        end
    end
endmodule
