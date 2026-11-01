`timescale 1ns/1ps

// Exercise the allocator together with real voice envelopes and oscillators.
module tb_voice_retrigger;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg sample_tick = 1'b0;
    reg ev_valid = 1'b0;
    reg ev_on = 1'b0;
    reg [6:0] ev_note = 7'd0;
    reg [7:0] ev_vel = 8'd100;
    reg panic = 1'b0;
    wire [3:0] voice_idle;
    wire [3:0] v_gate;
    wire [27:0] v_note;
    wire [31:0] v_vel;
    wire [3:0] v_start;
    integer n;

    always #5 clk = ~clk;

    voice_alloc dut (
        .clk(clk), .rst(rst), .ev_valid(ev_valid), .ev_on(ev_on),
        .ev_note(ev_note), .ev_vel(ev_vel), .panic(panic),
        .voice_idle(voice_idle), .v_gate(v_gate), .v_note(v_note),
        .v_vel(v_vel), .v_start(v_start), .v_busy()
    );

    genvar g;
    generate for (g = 0; g < 4; g = g + 1) begin: voices
        wire [31:0] inc;
        wire signed [15:0] audio;
        note_phase_inc u_inc (.note(v_note[g*7 +: 7]), .inc(inc));
        poly_voice u_voice (
            .clk(clk), .rst(rst), .sample_tick(sample_tick),
            .gate(v_gate[g]), .start(v_start[g]), .phase_inc(inc),
            .velocity(v_vel[g*8 +: 8]), .sample(audio), .idle(voice_idle[g])
        );
    end endgenerate

    task note_event;
        input on;
        input [6:0] note;
        begin
            @(negedge clk);
            ev_valid = 1'b1;
            ev_on = on;
            ev_note = note;
            @(posedge clk);
            #1;
            @(negedge clk);
            ev_valid = 1'b0;
        end
    endtask

    task audio_tick;
        begin
            @(negedge clk);
            sample_tick = 1'b1;
            @(posedge clk);
            #1 sample_tick = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 1'b0;

        note_event(1'b1, 7'd60);
        if (v_gate !== 4'b0001 || v_start !== 4'b0001 || v_note[6:0] !== 7'd60)
            $fatal(1, "first note did not allocate voice 0");
        audio_tick();
        audio_tick();
        if (voices[0].u_voice.u_adsr.env == 0 || voices[0].u_voice.u_dds.phase == 0)
            $fatal(1, "first voice did not start");

        // A held note reuses its own voice, even while three free voices exist.
        note_event(1'b1, 7'd60);
        if (v_gate !== 4'b0001 || v_start !== 4'b0001)
            $fatal(1, "repeated note allocated a duplicate voice");
        audio_tick();
        if (voices[0].u_voice.u_adsr.env !== 16'd0 ||
            voices[0].u_voice.u_adsr.state !== 3'd1 ||
            voices[0].u_voice.u_dds.phase !== 32'd0 || v_start !== 4'b0000)
            $fatal(1, "repeated note did not restart phase and attack");
        audio_tick();

        note_event(1'b1, 7'd62);
        audio_tick();
        note_event(1'b1, 7'd64);
        audio_tick();
        note_event(1'b1, 7'd65);
        audio_tick();
        if (v_gate !== 4'b1111 || voices[0].u_voice.u_adsr.env == 0)
            $fatal(1, "four-voice setup failed");

        // With every voice held, the oldest note (voice 0) is stolen.
        note_event(1'b1, 7'd67);
        if (v_note[6:0] !== 7'd67 || v_start !== 4'b0001 || v_gate !== 4'b1111)
            $fatal(1, "full-polyphony steal did not choose the oldest voice");
        audio_tick();
        if (voices[0].u_voice.u_adsr.env !== 16'd0 ||
            voices[0].u_voice.u_adsr.state !== 3'd1 ||
            voices[0].u_voice.u_dds.phase !== 32'd0)
            $fatal(1, "stolen voice retained its old envelope or phase");
        audio_tick();
        note_event(1'b0, 7'd60);
        if (v_gate[0] !== 1'b1 || v_note[6:0] !== 7'd67)
            $fatal(1, "old note-off silenced a stolen voice's new note");

        // A note in release is reused before any still-held note is stolen.
        note_event(1'b0, 7'd62);
        audio_tick();
        if (v_gate[1] !== 1'b0 || voice_idle[1] !== 1'b0)
            $fatal(1, "released voice setup failed");
        note_event(1'b1, 7'd69);
        if (v_gate[1] !== 1'b1 || v_note[13:7] !== 7'd69 || v_start !== 4'b0010)
            $fatal(1, "released voice was not reused first");
        audio_tick();
        if (voices[1].u_voice.u_adsr.env !== 16'd0 ||
            voices[1].u_voice.u_adsr.state !== 3'd1)
            $fatal(1, "reused released voice did not restart");
        audio_tick();
        note_event(1'b0, 7'd69);
        audio_tick();
        for (n = 0; n < 20 && !voice_idle[1]; n = n + 1) audio_tick();
        if (!voice_idle[1] || voices[1].u_voice.u_adsr.env !== 16'd0)
            $fatal(1, "reused voice did not finish release");

        $display("PASS tb_voice_retrigger: repeat, held steal, release reuse and drain");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "tb_voice_retrigger timeout");
    end
endmodule
