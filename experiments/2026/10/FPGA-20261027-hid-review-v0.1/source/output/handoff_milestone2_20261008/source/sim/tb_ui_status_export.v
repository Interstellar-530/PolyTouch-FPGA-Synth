`timescale 1ns/1ps
module tb_ui_status_export;
    reg audio_clk = 1'b0;
    reg pixel_clk = 1'b0;
    reg rst = 1'b1;
    reg [3:0] v_gate = 4'b0101;
    reg [27:0] v_note;
    reg [31:0] v_vel;
    wire [63:0] async_status;
    wire async_toggle;
    wire [63:0] pixel_status;
    wire toggle_seen;

    always #4 audio_clk = ~audio_clk;
    always #7 pixel_clk = ~pixel_clk;

    initial begin
        v_note = 28'd0;
        v_note[0*7 +: 7] = 7'd60;
        v_note[1*7 +: 7] = 7'd62;
        v_note[2*7 +: 7] = 7'd64;
        v_note[3*7 +: 7] = 7'd67;
        v_vel = 32'd0;
        v_vel[0*8 +: 8] = 8'd80;
        v_vel[1*8 +: 8] = 8'd81;
        v_vel[2*8 +: 8] = 8'd99;
        v_vel[3*8 +: 8] = 8'd100;
    end

    ui_status_export #(.VOICES(4), .TICK_DIV(4)) u_export (
        .clk(audio_clk), .rst(rst),
        .v_gate(v_gate), .v_note(v_note), .v_vel(v_vel),
        .pressure_level(12'hAB0), .demo_mode(1'b0), .muted(1'b1),
        .piano_mode(1'b1), .guitar_mode(1'b0),
        .chord_set(1'b1), .show_timbre(1'b1),
        .instrument_id(2'd0), .tempo_sel(2'd2),
        .timbre_target(8'd252), .piano_tone(3'd2),
        .status(async_status), .status_toggle(async_toggle)
    );

    ui_status_sync u_sync (
        .clk(pixel_clk), .rst(rst),
        .async_status(async_status), .async_toggle(async_toggle),
        .status(pixel_status), .toggle_seen(toggle_seen)
    );

    integer wait_count;
    initial begin
        repeat (5) @(posedge audio_clk);
        rst <= 1'b0;
        wait_count = 0;
        while (pixel_status[15:12] != 4'd2 && wait_count < 100) begin
            @(posedge pixel_clk);
            wait_count = wait_count + 1;
        end
        if (pixel_status[11:0] !== 12'b0001_0001)
            $fatal(1, "UI_NOTE_MASK=%04h", pixel_status[11:0]);
        if (pixel_status[15:12] !== 4'd2)
            $fatal(1, "UI_ACTIVE_COUNT=%0d", pixel_status[15:12]);
        if (pixel_status[22:16] !== 7'd64)
            $fatal(1, "UI_LEAD_NOTE=%0d", pixel_status[22:16]);
        if (pixel_status[30:23] !== 8'd99)
            $fatal(1, "UI_LEAD_VEL=%0d", pixel_status[30:23]);
        if (pixel_status[38:31] !== 8'hAB)
            $fatal(1, "UI_PRESSURE=%02h", pixel_status[38:31]);
        if (pixel_status[39] !== 1'b0 || pixel_status[44] !== 1'b1)
            $fatal(1, "UI_MODE_FIELDS demo=%b muted=%b", pixel_status[39], pixel_status[44]);
        if (pixel_status[55:48] !== 8'd252 || pixel_status[57:56] !== 2'd2)
            $fatal(1, "UI_TONE_FIELDS timbre=%0d tempo=%0d", pixel_status[55:48], pixel_status[57:56]);
        $display("UI_STATUS_PASS mask=%04h active=%0d note=%0d", pixel_status[11:0], pixel_status[15:12], pixel_status[22:16]);
        $finish;
    end

    initial begin
        repeat (1000) @(posedge pixel_clk);
        $fatal(1, "UI_STATUS_TIMEOUT");
    end
endmodule
