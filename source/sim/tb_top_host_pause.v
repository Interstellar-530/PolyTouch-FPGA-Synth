`timescale 1ns/1ps
module tb_top_host_pause;
    reg clk = 0;
    always #18.5185 clk = ~clk;
    reg key_rst = 0, kbd_rx = 1;
    wire adc_cs, adc_clk, adc_mosi, adc_miso, bck;
    top #(.AUDIO_IF(2), .VOICES(8), .GPIO_KEY_ENABLE(0),
          .HOST_KBD_ENABLE(1), .SONG_UNIT_SAMPLES(64)) dut (
        .clk_27m(clk), .clk_12m288(1'b0), .key_rst(key_rst),
        .key_s1(1'b1), .key_s2(1'b1), .uart_rx(1'b1),
        .gpio_key_n(12'hFFF), .kbd_uart_rx(kbd_rx),
        .adc_cs_n(adc_cs), .adc_sck(adc_clk), .adc_mosi(adc_mosi),
        .adc_miso(adc_miso), .i2s_bck(bck)
    );
    mcp3208_model adc (
        .cs_n(adc_cs), .sclk(adc_clk), .mosi(adc_mosi), .miso(adc_miso),
        .ch0(12'd0), .ch1(12'd2048), .ch2(12'd0), .ch3(12'd0),
        .ch4(12'd0), .ch5(12'd0), .ch6(12'd0), .ch7(12'd0)
    );
    integer edges = 0, audible = 0;
    always @(posedge bck) edges = edges + 1;
    always @(posedge clk)
        if (!dut.rst && dut.sample_tick && dut.final_sample24 != 0)
            audible = audible + 1;
    task byte_out;
        input [7:0] value;
        integer i;
        begin
            @(negedge clk); kbd_rx = 0; #8667;
            for (i = 0; i < 8; i = i + 1) begin kbd_rx = value[i]; #8667; end
            kbd_rx = 1; #8667;
        end
    endtask
    task report;
        input [7:0] a, b;
        begin
            byte_out(8'h57); byte_out(8'hAB); byte_out(8'h01);
            byte_out(0); byte_out(0); byte_out(a); byte_out(b);
            byte_out(0); byte_out(0); byte_out(0); byte_out(0);
            repeat (100) @(posedge clk);
        end
    endtask
    reg [15:0] saved_tick;
    reg [7:0] saved_mel, saved_left, saved_chord_left;
    reg [5:0] saved_chord;
    integer saved_edges, saved_audible;
    initial begin
        repeat (20) @(posedge clk); key_rst = 1;
        wait (!dut.por);
        repeat (40000) @(posedge clk);
        report(8'h41, 0);
        if (!dut.demo_mode || !dut.demo_paused) $fatal(1, "F8 did not pause demo");
        saved_tick = dut.u_song.tick_cnt; saved_mel = dut.u_song.mel_idx;
        saved_left = dut.u_song.mel_left; saved_chord = dut.u_song.chord_idx;
        saved_chord_left = dut.u_song.chord_left; saved_edges = edges;
        report(8'h41, 0); report(0, 8'h41);
        repeat (60000) @(posedge clk);
        if (!dut.demo_paused) $fatal(1, "held/reordered F8 resumed demo");
        if (dut.u_song.tick_cnt != saved_tick || dut.u_song.mel_idx != saved_mel ||
            dut.u_song.mel_left != saved_left || dut.u_song.chord_idx != saved_chord ||
            dut.u_song.chord_left != saved_chord_left) $fatal(1, "paused score advanced");
        if (edges <= saved_edges + 1000) $fatal(1, "pause stopped I2S clock");
        if (dut.final_sample24 !== 24'sd0) $fatal(1, "pause did not reach digital silence");
        if (audible == 0) $fatal(1, "demo never generated audio before pause");
        report(0, 0); saved_audible = audible;
        report(8'h41, 0);
        if (dut.demo_paused || !dut.demo_mode) $fatal(1, "F8 did not resume demo");
        repeat (60000) @(posedge clk);
        if (dut.u_song.mel_idx == saved_mel && dut.u_song.mel_left == saved_left &&
            dut.u_song.tick_cnt == saved_tick) $fatal(1, "resumed score did not advance");
        if (audible <= saved_audible) $fatal(1, "resume produced no audio");
        report(0, 0); report(8'h41, 0); report(0, 0);
        report(8'h40, 0);
        if (dut.demo_mode || dut.demo_paused) $fatal(1, "F7 left pause set in manual mode");
        report(8'h41, 0);
        if (dut.demo_mode || dut.demo_paused) $fatal(1, "F8 affected manual mode");
        report(0, 0); report(8'h40, 0);
        if (!dut.demo_mode || dut.demo_paused) $fatal(1, "F7 did not start unpaused demo");
        $display("PASS tb_top_host_pause: F8 pause/resume, dedup, frozen position, I2S continuous, silence/audio recovery, F7 and manual compatibility");
        $finish;
    end
    initial begin #60000000; $fatal(1, "pause test timeout"); end
endmodule
