`timescale 1ns/1ps
module tb_ui_audio_visual_export;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg sample_tick = 1'b0;
    reg signed [15:0] sample_in = 16'sd0;
    reg [3:0] v_gate = 4'b0101;
    reg [27:0] v_note = 28'd0;
    reg [31:0] v_vel = 32'd0;
    wire [255:0] waveform;
    wire [63:0] spectrum;
    wire [63:0] lissajous;
    wire snapshot_toggle;

    always #5 clk = ~clk;

    ui_audio_visual_export #(.VOICES(4)) dut (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .sample_in(sample_in), .v_gate(v_gate), .v_note(v_note), .v_vel(v_vel),
        .waveform(waveform), .spectrum(spectrum),
        .lissajous(lissajous), .snapshot_toggle(snapshot_toggle)
    );

    integer i;
    reg old_toggle;
    initial begin
        v_note[0*7 +: 7] = 7'd60;
        v_note[2*7 +: 7] = 7'd84;
        v_vel[0*8 +: 8] = 8'd120;
        v_vel[2*8 +: 8] = 8'd80;
        repeat (3) @(posedge clk);
        rst <= 1'b0;
        old_toggle = snapshot_toggle;
        for (i = 0; i < 64; i = i + 1) begin
            @(negedge clk);
            sample_in <= $signed((i - 32) <<< 8);
            sample_tick <= 1'b1;
            @(negedge clk);
            sample_tick <= 1'b0;
        end
        wait (snapshot_toggle != old_toggle);
        if (waveform[3:0] !== 4'd3)
            $fatal(1, "VIS_WAVE_FIRST=%0d", waveform[3:0]);
        if (waveform[63*4 +: 4] !== 4'd4)
            $fatal(1, "VIS_WAVE_LAST=%0d", waveform[63*4 +: 4]);
        if (spectrum[5*8 +: 8] == 0 || spectrum[7*8 +: 8] == 0)
            $fatal(1, "VIS_SPECTRUM=%h", spectrum);
        if (lissajous == 0)
            $fatal(1, "VIS_PHASE_EMPTY");
        $display("UI_VISUAL_PASS wave_rows=%0d..%0d spectrum=%h", waveform[3:0],
                 waveform[63*4 +: 4], spectrum);
        $finish;
    end

    initial begin
        repeat (5000) @(posedge clk);
        $fatal(1, "UI_VISUAL_TIMEOUT");
    end
endmodule
