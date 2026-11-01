// 32 声部控制前级：把演奏控制整理成"整束原子快照"再跨到计算域。
//
// 为什么不是逐位同步：控制束有 51 位（instrument/tone/volume/静音/压力/弯音），
// 按位打两拍再声称"多位一致"在原理上不成立——采样瞬间可能读到新旧混合值。
// 这里沿用事件通路的四相握手思路：数据整束先寄存一个 ref 拍，再翻转 req；
// 计算域同步到 req 边沿后一次性锁存整束，然后回 ack。ref 侧在 ack 前不再改数据，
// 因此计算域锁存时 51 位同时有效。
//
// 复用而非重写：压力/弯音的取样、中值滤波、IIR、±2 半音映射与 Q16 比率全部用
// 生产模块 rtl/audio/pressure_bend.v；主音量斜坡与曲线用 rtl/top.v 的同一张表
// （ram32_volume_curve.vh，由 top.v 原样抽取）。
module ram32_control_front #(
    parameter integer CLK_REF_HZ = 12288000,
    parameter integer CONTROL_HZ = 2000,
    parameter [11:0]  ADC_CENTER = 12'd2048
)(
    input  wire        clk_ref,
    input  wire        reset_ref,
    input  wire        clk_compute,
    input  wire        reset_compute,
    // 控制源：与 frame_tick 同域，准静态
    input  wire        instrument,
    input  wire [2:0]  piano_tone,
    input  wire [6:0]  volume_target,
    input  wire        mute,
    input  wire        pressure_enable,
    input  wire [11:0] pressure_adc,
    input  wire [11:0] bend_adc,
    input  wire        frame_tick,
    // 计算域输出（整束同一拍更新）
    output reg         instrument_c,
    output reg  [2:0]  piano_tone_c,
    output reg  [8:0]  volume_gain_c,
    output reg  [6:0]  volume_c,
    output reg         mute_c,
    output reg         pressure_enable_c,
    output reg  [11:0] pressure_level_c,
    output reg  [16:0] bend_ratio_c,
    output wire        control_busy
);
    `include "rtl/prototypes/ram32_volume_curve.vh"

    localparam integer CTRL_DIV = (CLK_REF_HZ / CONTROL_HZ) > 0 ? (CLK_REF_HZ / CONTROL_HZ) : 1;
    localparam integer CW = $clog2(CTRL_DIV + 1);

    // ---------------------------------------------------- ref: control tick ---
    reg [CW-1:0] ctrl_div = 0;
    wire control_tick = (ctrl_div == CTRL_DIV - 1);
    always @(posedge clk_ref or posedge reset_ref) begin
        if (reset_ref) ctrl_div <= 0;
        else ctrl_div <= control_tick ? {CW{1'b0}} : ctrl_div + 1'b1;
    end

    // ------------------------------------------- ref: pressure + bend (reuse) ---
    wire [11:0] pressure_filtered_unused;
    wire [11:0] pressure_level_ref;
    wire signed [15:0] bend_q8_ref;
    wire [31:0] phase_inc_unused;
    wire [16:0] bend_ratio_ref;
    pressure_bend #(.ADC_CENTER(ADC_CENTER)) u_bend (
        .clk(clk_ref), .rst(reset_ref), .control_tick(control_tick),
        .pressure_adc(pressure_adc), .bend_adc(bend_adc),
        .pressure_enable(pressure_enable), .base_phase_inc(32'd0),
        .pressure_filtered(pressure_filtered_unused), .pressure_level(pressure_level_ref),
        .bend_q8(bend_q8_ref), .bend_ratio_q16(bend_ratio_ref), .phase_inc_out(phase_inc_unused)
    );

    // ------------------------------------------------- ref: volume ramp (Q8) ---
    // 与生产一致：每帧 ±1 步，0..100；曲线查表得 Q8 增益（256 = 单位增益）。
    reg [6:0] volume_q = 7'd100;
    always @(posedge clk_ref or posedge reset_ref) begin
        if (reset_ref) volume_q <= 7'd100;
        else if (frame_tick) begin
            if (volume_q < volume_target) volume_q <= volume_q + 1'b1;
            else if (volume_q > volume_target) volume_q <= volume_q - 1'b1;
        end
    end
    wire [8:0] volume_gain_now = volume_gain(volume_q);

    // ------------------------------------------------------- ref: bundle ---
    localparam integer BW = 1 + 3 + 9 + 7 + 1 + 1 + 12 + 17;   // 51
    wire [BW-1:0] bundle_now = {instrument, piano_tone, volume_gain_now, volume_q,
                                mute, pressure_enable, pressure_level_ref, bend_ratio_ref};

    reg [BW-1:0] bundle_hold = {BW{1'b0}};
    reg          bundle_pending = 1'b0;
    reg          req = 1'b0;
    reg          busy = 1'b0;
    reg          ack_pin = 1'b0;          // 计算域产生，ref 域同步回读
    (* ASYNC_REG = "TRUE" *) reg ack_meta_a = 0, ack_sync_a = 0;
    reg          ack_seen = 0;
    always @(posedge clk_ref or posedge reset_ref) begin
        if (reset_ref) begin
            bundle_hold <= {BW{1'b0}}; bundle_pending <= 1'b0;
            req <= 1'b0; busy <= 1'b0;
            ack_meta_a <= 1'b0; ack_sync_a <= 1'b0; ack_seen <= 1'b0;
        end else begin
            ack_meta_a <= ack_pin; ack_sync_a <= ack_meta_a;
            ack_seen <= ack_sync_a;
            if (ack_sync_a ^ ack_seen) busy <= 1'b0;
            // 数据先寄存一拍，再翻 req：计算域采样时数据已稳定至少一个 ref 周期。
            if (bundle_pending) begin
                bundle_pending <= 1'b0;
                req <= ~req;
                busy <= 1'b1;
            end else if (!busy && (bundle_now != bundle_hold)) begin
                bundle_hold <= bundle_now;
                bundle_pending <= 1'b1;
            end
        end
    end
    assign control_busy = busy;

    // ------------------------------------------------- compute: snapshot ---
    (* ASYNC_REG = "TRUE" *) reg req_meta = 0, req_sync = 0;
    reg req_seen = 0;
    reg [BW-1:0] bundle_c = {BW{1'b0}};
    always @(posedge clk_compute or posedge reset_compute) begin
        if (reset_compute) begin
            req_meta <= 1'b0; req_sync <= 1'b0; req_seen <= 1'b0;
            ack_pin <= 1'b0; bundle_c <= {BW{1'b0}};
        end else begin
            req_meta <= req; req_sync <= req_meta; req_seen <= req_sync;
            if (req_sync ^ req_seen) begin
                bundle_c <= bundle_hold;
                ack_pin <= ~ack_pin;
            end
        end
    end

    // 拆包顺序必须与打包顺序严格相反。
    always @(posedge clk_compute or posedge reset_compute) begin
        if (reset_compute) begin
            instrument_c <= 1'b0; piano_tone_c <= 3'd0; volume_gain_c <= 9'd256; volume_c <= 7'd100;
            mute_c <= 1'b0; pressure_enable_c <= 1'b1; pressure_level_c <= 12'd3200; bend_ratio_c <= 17'd65536;
        end else begin
            instrument_c      <= bundle_c[BW-1];
            piano_tone_c      <= bundle_c[BW-2 -: 3];
            volume_gain_c     <= bundle_c[BW-5 -: 9];
            volume_c          <= bundle_c[BW-14 -: 7];
            mute_c            <= bundle_c[BW-21];
            pressure_enable_c <= bundle_c[BW-22];
            pressure_level_c  <= bundle_c[BW-23 -: 12];
            bend_ratio_c      <= bundle_c[BW-35 -: 17];
        end
    end

    // 静音来自控制束；压力开关同时决定 wide_master 是否采用压力增益。
    // 两者都在计算域单独寄存，避免组合穿透造成半帧不一致。
`ifdef SIMULATION
    initial if (CLK_REF_HZ % CONTROL_HZ != 0 || CONTROL_HZ < 1)
        $fatal(1, "ram32_control_front: CLK_REF_HZ must be a multiple of CONTROL_HZ");
`endif
endmodule
