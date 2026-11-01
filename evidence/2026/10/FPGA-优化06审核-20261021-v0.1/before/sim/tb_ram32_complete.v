`timescale 1ns/1ps
// 32-voice complete prototype: events -> scheduler ADSR/steal/retrigger ->
// RAM wavetable core -> wide master -> I2S, all in one frame budget.
//
// Checks: 32 simultaneous voices with per-voice increments (no pitch crossing),
// per-frame phase advance equals each voice's own increment, steal of the oldest
// voice, retrigger of a held note, release to zero, and the worst-case frame
// cost (render + configuration writes) inside 1024 clocks at 49.152 MHz.
module tb_ram32_complete;
    localparam integer CLOCK_HZ = 49152000;
    localparam integer PERIOD   = CLOCK_HZ / 48000;   // 1024

    reg clk = 0;
    always #(1.0e9 / (2.0 * CLOCK_HZ)) clk = ~clk;

    reg rst = 1;
    reg ev_valid = 0, ev_on = 0;
    reg [6:0] ev_note = 0;
    reg [7:0] ev_vel = 8'd120;
    wire ev_ready, bck, lrck, din, tick, valid, initialized;
    wire signed [23:0] audio;
    wire [5:0] active;
    wire [31:0] clips;

    ram32_top #(.ATTACK_STEP(16'd8192), .DECAY_STEP(16'd4096),
                .RELEASE_STEP(16'd4096), .SUSTAIN_LEVEL(16'd32768)) dut (
        .clk(clk), .rst(rst),
        .ev_valid(ev_valid), .ev_on(ev_on), .ev_note(ev_note), .ev_vel(ev_vel),
        .ev_ready(ev_ready),
        .i2s_bck(bck), .i2s_lrck(lrck), .i2s_din(din),
        .audio_sample(audio), .sample_valid(valid),
        .active_count(active), .clip_count(clips), .tick(tick), .initialized(initialized)
    );

    // Reference increments, one module per expected voice.
    reg [6:0] want_note [0:31];
    wire [31:0] ref_inc [0:31];
    genvar gi;
    generate
        for (gi = 0; gi < 32; gi = gi + 1) begin : g_ref
            note_phase_inc #(.FS_HZ(48000)) u_ref (.note(want_note[gi]), .inc(ref_inc[gi]));
        end
    endgenerate

    integer i, k;
    integer frames = 0, cfg_count = 0, render_cycles = 0, budget_ok = 1, max_cfg = 0, max_cost = 0;
    integer cost;
    integer phase0 [0:31];
    integer phase1 [0:31];
    integer inc_seen;

    // ------------------------------------------------------------ frame timer ---
    reg got_valid = 0;
    always @(posedge clk) begin
        if (tick) begin
            if (frames > 1 && got_valid) begin
                cost = render_cycles + 3 * cfg_count;
                if (cost > max_cost) max_cost = cost;
                if (cost > PERIOD - 8) budget_ok = 0;
            end
            frames = frames + 1;
            cfg_count = 0;
            render_cycles = 0;
            got_valid = 0;
        end else begin
            if (!got_valid) render_cycles = render_cycles + 1;
            if (valid) got_valid = 1;
            if (dut.u_dp.u_compute.cfg_ready && dut.u_dp.u_compute.cfg_valid)
                cfg_count = cfg_count + 1;
            if (cfg_count > max_cfg) max_cfg = cfg_count;
        end
    end

    task send_event;
        input on;
        input [6:0] n;
        begin
            while (!ev_ready) @(negedge clk);
            @(negedge clk);
            ev_valid = 1'b1; ev_on = on; ev_note = n;
            @(negedge clk);
            ev_valid = 1'b0; ev_on = 1'b0;
        end
    endtask

    task wait_ticks;
        input integer n;
        integer t;
        begin
            for (t = 0; t < n; t = t + 1) @(posedge tick);
            @(negedge clk);
        end
    endtask

    task check_inc;
        input integer v;
        begin
            if (dut.u_dp.u_compute.lane[0].u_core.u_state.memory[v * 4 + 2] !== ref_inc[v])
                $fatal(1, "voice %0d increment %h expect %h", v,
                       dut.u_dp.u_compute.lane[0].u_core.u_state.memory[v * 4 + 2], ref_inc[v]);
        end
    endtask

    task check_env;
        input integer v;
        input integer expected;
        input integer tol;
        integer got;
        begin
            got = dut.u_dp.u_compute.lane[0].u_core.u_state.memory[v * 4] & 32'h0000ffff;
            if ((got - expected) > tol || (expected - got) > tol)
                $fatal(1, "voice %0d env %0d expect %0d+-%0d", v, got, expected, tol);
        end
    endtask

    initial begin
        for (i = 0; i < 32; i = i + 1) want_note[i] = 7'd36 + i[6:0];
        repeat (5) @(negedge clk);
        rst = 1'b0;
        wait (initialized);
        repeat (4) @(negedge clk);

        // 1) 32 simultaneous voices, one note each.
        for (i = 0; i < 32; i = i + 1) send_event(1'b1, 7'd36 + i[6:0]);
        wait_ticks(60);
        if (active !== 6'd32) $fatal(1, "active=%0d expect 32", active);
        for (i = 0; i < 32; i = i + 1) begin
            check_inc(i);
            check_env(i, 32768, 64);
            if (((dut.u_dp.u_compute.lane[0].u_core.u_state.memory[i * 4] >> 16) & 7'h7f) !== 7'd120)
                $fatal(1, "voice %0d velocity wrong", i);
        end
        $display("INFO 32 voices allocated, increments and envelopes match");

        // 2) Pitch isolation: each phase advances by its own increment per frame.
        for (i = 0; i < 32; i = i + 1)
            phase0[i] = dut.u_dp.u_compute.lane[0].u_core.u_state.memory[i * 4 + 1];
        wait_ticks(1);
        for (i = 0; i < 32; i = i + 1)
            phase1[i] = dut.u_dp.u_compute.lane[0].u_core.u_state.memory[i * 4 + 1];
        for (i = 0; i < 32; i = i + 1) begin
            if (((phase1[i] - phase0[i]) & 32'hffffffff) !== ref_inc[i])
                $fatal(1, "voice %0d phase step %h expect %h", i,
                       (phase1[i] - phase0[i]) & 32'hffffffff, ref_inc[i]);
        end
        $display("INFO phase step per voice matches its own increment (no cross-talk)");

        // 3) Steal: the 33rd note must replace the oldest voice (voice 0).
        want_note[0] = 7'd100;
        send_event(1'b1, 7'd100);
        wait_ticks(3);
        if (active !== 6'd32) $fatal(1, "steal changed active=%0d", active);
        check_inc(0);
        if ((dut.u_dp.u_compute.lane[0].u_core.u_state.memory[0] & 32'hffff) > 30000) $fatal(1, "stolen voice did not restart");
        for (i = 1; i < 32; i = i + 1) check_inc(i);
        $display("INFO steal took the oldest voice and kept the other 31 intact");

        // 4) Retrigger a held note: same voice, envelope restarted.
        want_note[4] = 7'd40;
        for (i = 0; i < 32; i = i + 1) begin
            if (i != 4) want_note[i] = 7'd36 + i[6:0];
        end
        want_note[0] = 7'd100;
        send_event(1'b1, 7'd40);
        wait_ticks(3);
        check_inc(4);
        if ((dut.u_dp.u_compute.lane[0].u_core.u_state.memory[4 * 4] & 32'hffff) > 30000) $fatal(1, "retrigger did not restart voice 4");
        if (active !== 6'd32) $fatal(1, "retrigger changed active=%0d", active);
        $display("INFO retrigger reused voice 4 and restarted its envelope");

        // 5) Release: note-off must decay to zero and free the voice.
        send_event(1'b0, 7'd40);
        wait_ticks(24);
        check_env(4, 0, 0);
        if (active !== 6'd31) $fatal(1, "release left active=%0d expect 31", active);
        check_inc(4);
        $display("INFO release reached zero and freed voice 4");

        // 6) Frame budget: render plus configuration writes inside one frame.
        wait_ticks(60);
        if (!budget_ok) $fatal(1, "frame budget exceeded: render=%0d cfg=%0d max_cfg=%0d",
                               render_cycles, cfg_count, max_cfg);
        if (max_cfg > 32) $fatal(1, "more than 32 config transactions in a frame: %0d", max_cfg);
        if (clips != 0) $fatal(1, "clip counter moved: %0d", clips);
        $display("INFO worst frame cost %0d cycles (render+master+3*cfg), limit %0d, max_cfg %0d",
                 max_cost, PERIOD - 8, max_cfg);

        $display("PASS tb_ram32_complete: 32 voices, per-voice pitch, steal, retrigger, release, budget");
        $finish;
    end

    initial begin
        #200000000;
        $fatal(1, "timeout");
    end
endmodule
