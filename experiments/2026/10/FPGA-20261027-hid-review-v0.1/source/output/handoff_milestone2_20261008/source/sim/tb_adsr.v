`timescale 1ns/1ps

// Release must advance on every sample tick, including after an early note-off.
module tb_adsr;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg sample_tick = 1'b0;
    reg gate = 1'b0;
    reg retrigger = 1'b0;
    wire [15:0] env;
    wire idle;
    reg [15:0] previous;
    integer n;

    always #5 clk = ~clk;

    adsr #(
        .ATTACK_STEP(16'd16000),
        .DECAY_STEP(16'd8192),
        .RELEASE_STEP(16'd4096),
        .SUSTAIN_LEVEL(16'd32767)
    ) dut (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .gate(gate), .retrigger(retrigger), .env(env), .idle(idle)
    );

    task step;
        input next_gate;
        input next_retrigger;
        begin
            @(negedge clk);
            gate = next_gate;
            retrigger = next_retrigger;
            sample_tick = 1'b1;
            @(posedge clk);
            #1 sample_tick = 1'b0;
        end
    endtask

    task drain_release;
        begin
            for (n = 0; n < 20 && !idle; n = n + 1) begin
                previous = env;
                step(1'b0, 1'b0);
                if (env > previous)
                    $fatal(1, "release rose from %0d to %0d", previous, env);
            end
            if (!idle || env !== 16'd0)
                $fatal(1, "release did not reach idle and zero: env=%0d state=%0d", env, dut.state);
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 1'b0;

        // Note Off during ATTACK must release rather than pin its level.
        step(1'b1, 1'b1);
        step(1'b1, 1'b0);
        if (env !== 16'd16000 || idle) $fatal(1, "attack setup failed");
        step(1'b0, 1'b0);
        if (dut.state !== 3'd4 || env !== 16'd16000)
            $fatal(1, "early note-off did not enter release");
        drain_release();

        // Note Off during DECAY is also a valid release path.
        step(1'b1, 1'b1);
        for (n = 0; n < 5; n = n + 1) step(1'b1, 1'b0);
        if (dut.state !== 3'd2) $fatal(1, "decay setup failed");
        step(1'b0, 1'b0);
        if (dut.state !== 3'd4) $fatal(1, "decay note-off did not enter release");
        drain_release();

        // Sustain, release, then rapidly retrigger before the old tail ends.
        step(1'b1, 1'b1);
        for (n = 0; n < 20 && dut.state != 3'd3; n = n + 1)
            step(1'b1, 1'b0);
        if (dut.state !== 3'd3 || env !== 16'd32767)
            $fatal(1, "sustain setup failed: state=%0d env=%0d", dut.state, env);
        step(1'b0, 1'b0);
        previous = env;
        step(1'b0, 1'b0);
        if (env >= previous || idle) $fatal(1, "sustain release did not decrease");
        step(1'b1, 1'b1);
        if (dut.state !== 3'd1 || env !== 16'd0)
            $fatal(1, "rapid retrigger did not start a fresh attack");
        step(1'b1, 1'b0);
        if (env !== 16'd16000) $fatal(1, "retrigger attack did not advance");
        step(1'b0, 1'b0);
        drain_release();

        $display("PASS tb_adsr: attack/decay/sustain note-off, release and retrigger");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "tb_adsr timeout");
    end
endmodule
