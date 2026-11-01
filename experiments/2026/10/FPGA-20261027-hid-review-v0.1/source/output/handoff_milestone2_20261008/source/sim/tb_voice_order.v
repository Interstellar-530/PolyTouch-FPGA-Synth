`timescale 1ns/1ps

// More than 65536 Note Ons must not corrupt the oldest-voice decision.
module tb_voice_order;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg ev_valid = 1'b0;
    reg [6:0] ev_note = 7'd0;
    wire [3:0] v_gate;
    wire [27:0] v_note;
    wire [31:0] v_vel;
    wire [3:0] v_start;
    integer n;

    always #5 clk = ~clk;

    voice_alloc dut (
        .clk(clk), .rst(rst), .ev_valid(ev_valid), .ev_on(1'b1),
        .ev_note(ev_note), .ev_vel(8'd100), .panic(1'b0),
        .voice_idle(4'b1111), .v_gate(v_gate), .v_note(v_note),
        .v_vel(v_vel), .v_start(v_start), .v_busy()
    );

    task note_on;
        input [6:0] note;
        begin
            @(negedge clk);
            ev_note = note;
            ev_valid = 1'b1;
            @(posedge clk);
            #1;
            @(negedge clk);
            ev_valid = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 1'b0;
        note_on(7'd60);
        for (n = 0; n < 65533; n = n + 1)
            note_on(7'd60);
        note_on(7'd62);
        note_on(7'd64);
        note_on(7'd65);
        if (v_gate !== 4'b1111 || v_note[6:0] !== 7'd60 ||
            v_note[13:7] !== 7'd62 || v_note[20:14] !== 7'd64 ||
            v_note[27:21] !== 7'd65)
            $fatal(1, "voice-order setup failed");
        note_on(7'd67);
        if (v_note[6:0] !== 7'd67 || v_note[27:21] !== 7'd65 ||
            v_start !== 4'b0001)
            $fatal(1, "oldest voice not stolen after 16-bit counter rollover");
        $display("PASS tb_voice_order: oldest voice remains correct after 65538 Note Ons");
        $finish;
    end

    initial begin
        #3000000;
        $fatal(1, "tb_voice_order timeout");
    end
endmodule
