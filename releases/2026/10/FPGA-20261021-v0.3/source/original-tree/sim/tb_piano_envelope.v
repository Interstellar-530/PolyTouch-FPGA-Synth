`timescale 1ns/1ps
// Piano mode is latched at note onset. A held piano note attacks quickly and
// decays to silence; changing mode during the note must not redefine it.
module tb_piano_envelope;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1, tick = 1'b0, gate = 1'b0, retrigger = 1'b0, piano_mode = 1'b0;
    reg [6:0] note = 7'd60;
    reg [7:0] velocity = 8'd100;
    wire [6:0] render_note;
    wire [7:0] render_velocity;
    wire restart, idle;
    wire [15:0] env;

    voice_transition #(
        .ATTACK_STEP(16'd8192), .DECAY_STEP(16'd4096),
        .RELEASE_STEP(16'd2048), .SUSTAIN_LEVEL(16'd32767),
        .PIANO_ATTACK_STEP(16'd8192), .PIANO_DECAY_STEP(16'd8192),
        .PIANO_RELEASE_STEP(16'd4096), .PIANO_SUSTAIN_LEVEL(16'd0)
    ) dut(
        .clk(clk), .rst(rst), .sample_tick(tick), .gate(gate),
        .retrigger(retrigger), .piano_mode(piano_mode), .guitar_mode(1'b0), .note(note),
        .velocity(velocity), .render_note(render_note),
        .render_velocity(render_velocity), .render_retrigger(restart),
        .env(env), .idle(idle));

    integer n;
    task step;
        begin
            tick = 1'b1; @(posedge clk); #1;
            @(negedge clk); tick = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask
    task note_on;
        input piano;
        begin
            piano_mode = piano; gate = 1'b1; retrigger = 1'b1;
            step(); retrigger = 1'b0;
        end
    endtask
    task settle_sustain;
        begin
            for (n = 0; n < 32 && env != 32767; n = n + 1) step();
            if (env != 32767) $fatal(1, "normal sustain did not settle");
        end
    endtask
    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b0;

        // Start with the normal long-sustain envelope.
        note_on(1'b0);
        settle_sustain();
        if (idle) $fatal(1, "normal note unexpectedly idle");

        // Switching to piano while held must not abruptly change this note.
        piano_mode = 1'b1;
        repeat (20) step();
        if (env != 32767 || idle) $fatal(1, "held normal note was not mode-latched");

        gate = 1'b0;
        for (n = 0; n < 64 && !idle; n = n + 1) step();
        if (!idle) $fatal(1, "normal note did not release");

        // A fresh note in piano mode must decay while the key remains held.
        note_on(1'b1);
        repeat (4) step();
        if (env == 0) $fatal(1, "piano attack produced no envelope");
        repeat (16) step();
        if (env != 0) $fatal(1, "held piano note did not decay to silence");
        gate = 1'b0;
        for (n = 0; n < 4 && !idle; n = n + 1) step();
        if (!idle) $fatal(1, "released piano note did not become idle");

        $display("PASS tb_piano_envelope: onset latches mode, held note decays, release returns idle");
        $finish;
    end
    initial begin #1000000; $fatal(1, "tb_piano_envelope timeout"); end
endmodule
