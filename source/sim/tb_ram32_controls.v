`timescale 1ns/1ps
// 32 声部控制单元验收：控制束原子性、主音量 Q8 归零、压力码透传、弯音比率
// 施加到调度器的增量、五档音色不截位、32 音并发调度。
// 只实例化控制前级与调度器（不含波表引擎），因此仿真时间在毫秒级；
// 引擎整链由 tb_ram32_clocked / tb_ram32_complete 覆盖。
module tb_ram32_controls;
    localparam integer FRAME = 1536;      // 73.728 MHz / 48 kHz

    reg clk_ref = 0, clk_cmp = 0;
    always #40.69   clk_ref = ~clk_ref;   // 12.288 MHz
    always #6.782   clk_cmp = ~clk_cmp;   // 73.728 MHz
    reg reset = 1;
    reg frame_tick = 0;

    // ---------------------------------------------------------- control front ---
    reg instrument = 0;
    reg [2:0] piano_tone = 0;
    reg [6:0] volume_target = 7'd100;
    reg mute = 0, pressure_enable = 0;
    reg [11:0] pressure_adc = 12'd3200, bend_adc = 12'd2048;
    wire instrument_c, mute_c, pressure_enable_c;
    wire [2:0] piano_tone_c;
    wire [8:0] volume_gain_c;
    wire [6:0] volume_c;
    wire [11:0] pressure_level_c;
    wire [16:0] bend_ratio_c;
    wire ctrl_busy;

    ram32_control_front #(.CLK_REF_HZ(12288000)) u_front (
        .clk_ref(clk_ref), .reset_ref(reset),
        .clk_compute(clk_cmp), .reset_compute(reset),
        .instrument(instrument), .piano_tone(piano_tone), .volume_target(volume_target),
        .mute(mute), .pressure_enable(pressure_enable),
        .pressure_adc(pressure_adc), .bend_adc(bend_adc), .frame_tick(frame_tick),
        .instrument_c(instrument_c), .piano_tone_c(piano_tone_c),
        .volume_gain_c(volume_gain_c), .volume_c(volume_c),
        .mute_c(mute_c), .pressure_enable_c(pressure_enable_c),
        .pressure_level_c(pressure_level_c), .bend_ratio_c(bend_ratio_c),
        .control_busy(ctrl_busy)
    );

    // 两个域的帧节拍必须各自产生：参考域 12.288 MHz/48 kHz = 256 拍，
    // 计算域 73.728 MHz/48 kHz = 1536 拍。若用计算域单拍脉冲去驱动参考域斜坡，
    // 12.288 MHz 会漏掉其中 5/6，音量斜坡变成 1/6 速（曾在这个台里抓到）。
    integer ref_div = 0;
    always @(posedge clk_ref) begin
        if (reset) begin ref_div <= 0; frame_tick <= 0; end
        else begin
            frame_tick <= (ref_div == 255);
            ref_div    <= (ref_div == 255) ? 0 : ref_div + 1;
        end
    end
    reg sample_tick_c = 0;
    integer frame_div = 0;
    always @(posedge clk_cmp) begin
        if (reset) begin frame_div <= 0; sample_tick_c <= 0; end
        else begin
            sample_tick_c <= (frame_div == FRAME - 1);
            frame_div     <= (frame_div == FRAME - 1) ? 0 : frame_div + 1;
        end
    end

    // ------------------------------------------------------------- scheduler ---
    reg ev_valid = 0, ev_on = 0;
    reg [6:0] ev_note = 0;
    reg [7:0] ev_vel = 100;
    wire ev_ready;
    wire [5:0] cfg_voice, active_count;
    wire [31:0] cfg_increment;
    wire [15:0] cfg_envelope;
    wire [6:0] cfg_velocity;
    wire cfg_retrigger, cfg_valid;
    wire [23:0] cfg_param;
    wire [2:0] cfg_mask;

    voice_sched32 #(.VOICES(32)) u_sched (
        .clk(clk_cmp), .rst(reset), .sample_tick(sample_tick_c),
        .instrument(instrument_c), .piano_tone(piano_tone_c),
        .ev_valid(ev_valid), .ev_on(ev_on), .ev_note(ev_note), .ev_vel(ev_vel),
        .ev_ready(ev_ready),
        .cfg_voice(cfg_voice), .cfg_increment(cfg_increment), .cfg_envelope(cfg_envelope),
        .cfg_velocity(cfg_velocity), .cfg_retrigger(cfg_retrigger), .cfg_param(cfg_param),
        .cfg_mask(cfg_mask), .cfg_valid(cfg_valid), .cfg_ready(1'b1),
        .active_count(active_count), .bend_ratio(bend_ratio_c)
    );

    // ------------------------------------------------------------- 原子性监视 ---
    reg [5:0] atomic_old, atomic_new;
    reg atomic_armed = 0;
    always @(posedge clk_cmp) begin
        if (atomic_armed && !reset) begin
            if ({instrument_c, piano_tone_c, mute_c, pressure_enable_c} !== atomic_old &&
                {instrument_c, piano_tone_c, mute_c, pressure_enable_c} !== atomic_new)
                $fatal(1, "control bundle tore: %b is neither old %b nor new %b",
                       {instrument_c, piano_tone_c, mute_c, pressure_enable_c}, atomic_old, atomic_new);
        end
    end

    // ---------------------------------------------------------------- helpers ---
    task push_event;
        input on; input [6:0] note; input [7:0] vel;
        begin
            @(posedge clk_cmp);
            ev_on = on; ev_note = note; ev_vel = vel; ev_valid = 1'b1;
            @(posedge clk_cmp);
            while (!ev_ready) @(posedge clk_cmp);
            ev_valid = 1'b0;
        end
    endtask
    task wait_frames;
        input integer n;
        integer k;
        begin for (k = 0; k < n; k = k + 1) @(posedge frame_tick); end
    endtask
    task wait_bundle;
        integer g;
        begin
            g = 0;
            while (ctrl_busy && g < 100000) begin @(posedge clk_ref); g = g + 1; end
            if (ctrl_busy) $fatal(1, "front handshake stuck");
            repeat (4) @(posedge clk_ref);
        end
    endtask

    integer i, t, g;
    reg [31:0] base_inc, bent_inc;

    initial begin
        repeat (20) @(posedge clk_ref);
        reset = 1'b0;
        repeat (20) @(posedge clk_ref);

        // -------------------------------------------- T1: 32 音并发调度 ---
        for (i = 0; i < 32; i = i + 1) push_event(1'b1, 36 + i, 8'd100);
        wait_frames(3);
        if (active_count !== 6'd32) $fatal(1, "T1 active_count=%0d expect 32", active_count);
        $display("T1 ok: 32 voices allocated");

        // 释放到 idle，后续用单音做控制测量。
        for (i = 0; i < 32; i = i + 1) push_event(1'b0, 36 + i, 8'd0);
        g = 0;
        while (active_count != 0 && g < 4000) begin wait_frames(1); g = g + 1; end
        if (active_count !== 0) $fatal(1, "T1 release left %0d voices", active_count);
        push_event(1'b1, 7'd60, 8'd100);
        wait_frames(4);

        // ------------------------------------- T2: 离散字段整束原子 ---
        atomic_old = {instrument, piano_tone, mute, pressure_enable};
        atomic_new = {1'b1, 3'd3, 1'b1, 1'b1};
        atomic_armed = 1'b1;
        @(posedge clk_ref);
        instrument = atomic_new[5]; piano_tone = atomic_new[4:2];
        mute = atomic_new[1]; pressure_enable = atomic_new[0];
        wait_bundle;
        atomic_armed = 1'b0;
        if ({instrument_c, piano_tone_c, mute_c, pressure_enable_c} !== atomic_new)
            $fatal(1, "T2 bundle not applied: %b expect %b",
                   {instrument_c, piano_tone_c, mute_c, pressure_enable_c}, atomic_new);
        $display("T2 ok: discrete control fields applied atomically");

        @(posedge clk_ref);
        instrument = 1'b0; piano_tone = 3'd0; mute = 1'b0; pressure_enable = 1'b0;
        wait_bundle;

        // ------------------------------------------ T3: 主音量 Q8 精确归零 ---
        if (volume_gain_c !== 9'd256) $fatal(1, "T3 boot volume gain %0d expect 256", volume_gain_c);
        @(posedge clk_ref); volume_target = 7'd0;
        // 斜坡 100 帧 ± 握手延迟
        wait_frames(140);
        wait_bundle;
        if (volume_c !== 7'd0) $fatal(1, "T3 volume ramp stuck at %0d", volume_c);
        if (volume_gain_c !== 9'd0) $fatal(1, "T3 volume gain %0d expect exact 0", volume_gain_c);
        $display("T3 ok: volume 0 -> Q8 gain exactly 0");
        @(posedge clk_ref); volume_target = 7'd100;
        wait_frames(140); wait_bundle;
        if (volume_gain_c !== 9'd256) $fatal(1, "T3 volume restore gain %0d", volume_gain_c);

        // ------------------------------------------- T4: 压力码透传与开关 ---
        @(posedge clk_ref); pressure_enable = 1'b1; pressure_adc = 12'd3200;
        wait_frames(300); wait_bundle;
        if (pressure_enable_c !== 1'b1) $fatal(1, "T4 pressure_enable did not cross");
        if (pressure_level_c < 12'd3100 || pressure_level_c > 12'd3200)
            $fatal(1, "T4 pressure full-scale level %0d", pressure_level_c);
        // 压力滤波在 2 kHz 控制节拍上做 IIR，约 10 个 tick 才收敛，故等 500 帧。
        @(posedge clk_ref); pressure_adc = 12'd128;
        wait_frames(500); wait_bundle;
        if (pressure_level_c > 12'd600)
            $fatal(1, "T4 pressure low level %0d did not settle low", pressure_level_c);
        $display("T4 ok: pressure code tracks ADC through the bundle");

        // ---------------------------------------------------- T5: 弯音比率 ---
        @(posedge clk_ref); pressure_enable = 1'b0; bend_adc = 12'd2048;
        wait_frames(60); wait_bundle;
        if (bend_ratio_c !== 17'd65536) $fatal(1, "T5 center ratio %0d expect 65536", bend_ratio_c);
        // 取一个已知音高的基础增量，再与弯音后的增量比较。
        g = 0;
        while (!(cfg_valid && cfg_voice == 6'd0) && g < 20000) begin @(posedge clk_cmp); g = g + 1; end
        base_inc = cfg_increment;
        @(posedge clk_ref); bend_adc = 12'd4095;
        wait_frames(60); wait_bundle;
        if (bend_ratio_c < 17'd72000) $fatal(1, "T5 bend-up ratio %0d too small", bend_ratio_c);
        g = 0;
        while (!(cfg_valid && cfg_voice == 6'd0) && g < 20000) begin @(posedge clk_cmp); g = g + 1; end
        bent_inc = cfg_increment;
        if (bent_inc <= base_inc)
            $fatal(1, "T5 bent increment not raised: base=%0d bent=%0d", base_inc, bent_inc);
        if (bent_inc < (base_inc * 109) / 100 || bent_inc > (base_inc * 115) / 100)
            $fatal(1, "T5 bend ratio out of range: base=%0d bent=%0d", base_inc, bent_inc);
        $display("T5 ok: bend raises increment base=%0d -> %0d", base_inc, bent_inc);
        @(posedge clk_ref); bend_adc = 12'd2048;
        wait_frames(60); wait_bundle;

        // ------------------------------------------------ T6: 五档音色 ---
        for (t = 0; t < 5; t = t + 1) begin
            @(posedge clk_ref); piano_tone = t[2:0];
            wait_bundle;
            wait_frames(2);
            if (piano_tone_c !== t[2:0])
                $fatal(1, "T6 tone %0d not in compute domain (got %0d)", t, piano_tone_c);
            if (u_sched.tone_q !== t[2:0])
                $fatal(1, "T6 tone %0d not latched by scheduler", t);
            if (u_sched.start_stage !== ((t >= 3) ? 3'd4 : 3'd3))
                $fatal(1, "T6 tone %0d start_stage=%0d (production semantics: 0..2->3, 3..4->4)",
                       t, u_sched.start_stage);
        end
        $display("T6 ok: tones 0..4 all reach the engine, no truncation of the fifth level");

        // ---------------------------------------------- T7: 吉他/钢琴切换 ---
        @(posedge clk_ref); instrument = 1'b1;
        wait_bundle; wait_frames(2);
        if (instrument_c !== 1'b1 || u_sched.instrument_q !== 1'b1)
            $fatal(1, "T7 instrument switch did not cross or latch");
        $display("T7 ok: instrument switch crosses and latches");

        $display("PASS tb_ram32_controls: 32 voices, atomic bundle, exact-zero volume, pressure pass-through, bend ratio, five tones, instrument switch");
        $finish;
    end

    initial begin
        #50000000;   // 50 ms 仿真时间上限
        $fatal(1, "tb_ram32_controls timeout");
    end
endmodule
