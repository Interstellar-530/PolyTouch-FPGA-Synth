`timescale 1ns/1ps
// 顶层 HID 控制补齐验收：CH9350L state-2 帧 -> top -> 统一音色/主音量状态。
// 覆盖：UART 兼容（D0/X/N/V）、首键、和弦、F6 钢琴/吉他切换、Up/Down 音量上下界、
// Esc 清音，以及切换乐器时清空旧声部、切换后重新按键能正常发声。
module tb_top_host_ctrl;
    reg clk27 = 0;
    always #18.5185 clk27 = ~clk27;

    reg key_rst = 0, s1 = 1, s2 = 1, uart_rx = 1, kbd_rx = 1;
    wire uart_tx, kbd_tx;
    wire hp_bck, hp_ws, hp_din, pa_en, led, led_chord, led_t0, led_t1;
    wire adc_cs_n, adc_sck, adc_mosi, adc_miso;
    wire [3:0] clip_fold;
    wire i2s_bck, i2s_lrck, i2s_din, dac_xsmt;

    mcp3208_model u_adc (
        .cs_n(adc_cs_n), .sclk(adc_sck), .mosi(adc_mosi), .miso(adc_miso),
        .ch0(12'd2048), .ch1(12'd2048), .ch2(12'd0), .ch3(12'd0),
        .ch4(12'd0), .ch5(12'd0), .ch6(12'd0), .ch7(12'd0)
    );

    top #(.AUDIO_IF(0), .VOICES(8), .MASTER_VOLUME_SHIFT(3),
          .GPIO_KEY_ENABLE(0), .HOST_KBD_ENABLE(1)) dut (
        .clk_27m(clk27), .clk_12m288(1'b0),
        .key_rst(key_rst), .key_s1(s1), .key_s2(s2),
        .uart_rx(uart_rx), .gpio_key_n(12'hFFF),
        .kbd_uart_rx(kbd_rx), .kbd_uart_tx(kbd_tx),
        .adc_cs_n(adc_cs_n), .adc_sck(adc_sck), .adc_mosi(adc_mosi), .adc_miso(adc_miso),
        .hp_bck(hp_bck), .hp_ws(hp_ws), .hp_din(hp_din), .pa_en(pa_en),
        .led(led), .led_chord(led_chord), .led_t0(led_t0), .led_t1(led_t1),
        .uart_tx(uart_tx), .clip_fold(clip_fold),
        .i2s_bck(i2s_bck), .i2s_lrck(i2s_lrck), .i2s_din(i2s_din), .dac_xsmt(dac_xsmt)
    );

    // ------------------------------------------------------------- observers ---
    integer gate_n, gi;
    always @* begin
        gate_n = 0;
        for (gi = 0; gi < 8; gi = gi + 1)
            if (dut.v_gate[gi]) gate_n = gate_n + 1;
    end
    always @(posedge clk27) begin
        if (dut.volume_target > 7'd100)
            $fatal(1, "volume target escaped range: %0d", dut.volume_target);
    end

    // ------------------------------------------------------------------ drivers ---
    task uart_byte;
        input [7:0] b;
        integer i;
        begin
            @(negedge clk27); uart_rx = 1'b0; #8667;
            for (i = 0; i < 8; i = i + 1) begin uart_rx = b[i]; #8667; end
            uart_rx = 1'b1; #8667;
        end
    endtask

    task uart_cmd2;
        input [7:0] a, b;
        begin uart_byte(a); uart_byte(b); uart_byte(8'h0D); end
    endtask

    task uart_cmd3;
        input [7:0] a, b, c;
        begin uart_byte(a); uart_byte(b); uart_byte(c); uart_byte(8'h0D); end
    endtask

    task kbd_byte;
        input [7:0] b;
        integer i;
        begin
            @(negedge clk27); kbd_rx = 1'b0; #8667;
            for (i = 0; i < 8; i = i + 1) begin kbd_rx = b[i]; #8667; end
            kbd_rx = 1'b1; #8667;
        end
    endtask

    task kbd_report;
        input [7:0] k0, k1, k2, k3, k4, k5;
        begin
            kbd_byte(8'h57); kbd_byte(8'hAB); kbd_byte(8'h01);
            kbd_byte(8'h00); kbd_byte(8'h00);
            kbd_byte(k0); kbd_byte(k1); kbd_byte(k2);
            kbd_byte(k3); kbd_byte(k4); kbd_byte(k5);
            repeat (20000) @(posedge clk27);
        end
    endtask

    task release_all;
        begin kbd_report(8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0); end
    endtask

    task tap_key;
        input [7:0] k;
        begin
            kbd_report(k, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0);
            kbd_report(8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0);
        end
    endtask

    // ------------------------------------------------------------------ checks ---
    task wait_gates;
        input integer want;
        integer t;
        begin
            t = 0;
            while (gate_n != want && t < 200000) begin @(posedge clk27); t = t + 1; end
            if (gate_n != want)
                $fatal(1, "gate count %0d, expect %0d", gate_n, want);
        end
    endtask

    task expect_note;
        input [6:0] n;
        integer v;
        reg hit;
        begin
            hit = 1'b0;
            for (v = 0; v < 8; v = v + 1)
                if (dut.v_gate[v] && (dut.v_note[v*7 +: 7] == n)) hit = 1'b1;
            if (!hit) $fatal(1, "note %0d is not gated", n);
        end
    endtask

    task wait_volume_target;
        input [6:0] want;
        integer t;
        begin
            t = 0;
            while (dut.volume_target != want && t < 200000) begin @(posedge clk27); t = t + 1; end
            if (dut.volume_target != want)
                $fatal(1, "volume target %0d, expect %0d", dut.volume_target, want);
        end
    endtask

    integer t, frames;

    initial begin
        repeat (20) @(posedge clk27);
        key_rst = 1'b1;
        while (dut.por) @(posedge clk27);
        repeat (20) @(posedge clk27);

        // 0) 用 UART 退出演示并清音，验证 HID 档下串口命令仍生效。
        uart_cmd2("D", "0");
        uart_cmd2("X", " ");
        t = 0;
        while (dut.demo_mode && t < 200000) begin @(posedge clk27); t = t + 1; end
        if (dut.demo_mode) $fatal(1, "D0 did not leave demo mode");
        wait_gates(0);
        if (dut.timbre_target !== 8'd64) $fatal(1, "boot timbre %0d expect 64", dut.timbre_target);

        // 1) CH9350L 接入。
        kbd_byte(8'h57); kbd_byte(8'hAB); kbd_byte(8'h86);
        kbd_byte(8'h57); kbd_byte(8'hAB); kbd_byte(8'h80); kbd_byte(8'hFF);
        kbd_byte(8'h57); kbd_byte(8'hAB); kbd_byte(8'h89);
        repeat (2000) @(posedge clk27);

        // 2) 首键：只占一个声部，音高 60。
        kbd_report(8'h14, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0);
        wait_gates(1);
        expect_note(7'd60);

        // 3) 和弦：Q + W -> 两个声部，60/62。
        kbd_report(8'h14, 8'h1A, 8'd0, 8'd0, 8'd0, 8'd0);
        wait_gates(2);
        expect_note(7'd60);
        expect_note(7'd62);

        // 4) F6：钢琴 -> 吉他，切换拍清声部与按键状态，不残留旧声部。
        if (dut.instrument_id !== 2'd0) $fatal(1, "boot instrument %0d", dut.instrument_id);
        kbd_report(8'h14, 8'h1A, 8'h3F, 8'd0, 8'd0, 8'd0);
        if (dut.instrument_id !== 2'd1)
            $fatal(1, "F6 instrument %0d expect 1", dut.instrument_id);
        if (!dut.guitar_mode) $fatal(1, "F6 did not enter guitar mode");
        wait_gates(0);
        repeat (2000) @(posedge clk27);
        if (dut.hid_held_count !== 4'd0)
            $fatal(1, "F6 left %0d held keys", dut.hid_held_count);
        if (dut.volume_target !== 7'd100)
            $fatal(1, "F6 disturbed volume target: %0d", dut.volume_target);

        // 持键重复上报及槽位重排不能再次切换，也不能重启已清除的音符。
        repeat (2) begin
            kbd_report(8'h14, 8'h1A, 8'h3F, 8'd0, 8'd0, 8'd0);
            if (dut.instrument_id !== 2'd1 || gate_n != 0 || dut.hid_held_count !== 4'd0)
                $fatal(1, "held F6 report retriggered instrument or notes");
        end
        kbd_report(8'h3F, 8'h1A, 8'h14, 8'd0, 8'd0, 8'd0);
        if (dut.instrument_id !== 2'd1 || gate_n != 0 || dut.hid_held_count !== 4'd0)
            $fatal(1, "reordered held F6 report retriggered instrument or notes");

        // 切换后重新按键必须在新乐器上正常发声。
        kbd_report(8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0);
        kbd_report(8'h14, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0);
        wait_gates(1);
        expect_note(7'd60);

        // F6 再切回钢琴，同样清声部。
        kbd_report(8'h14, 8'h3F, 8'd0, 8'd0, 8'd0, 8'd0);
        if (dut.instrument_id !== 2'd0)
            $fatal(1, "F6 back to %0d expect 0", dut.instrument_id);
        wait_gates(0);
        kbd_report(8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0);
        kbd_report(8'h14, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0);
        wait_gates(1);
        expect_note(7'd60);

        // 5) 音量上界：UART 置 95，Up 两次 -> 100 并钳位。
        uart_cmd3("V", "9", "5");
        wait_volume_target(7'd95);
        tap_key(8'h52);
        wait_volume_target(7'd100);
        tap_key(8'h52);
        repeat (20000) @(posedge clk27);
        if (dut.volume_target !== 7'd100)
            $fatal(1, "Up upper clamp failed: %0d", dut.volume_target);

        // 6) 音量下界：UART 置 5，Down 两次 -> 0 并钳位。
        uart_cmd3("V", "5", " ");
        wait_volume_target(7'd5);
        tap_key(8'h51);
        wait_volume_target(7'd0);
        tap_key(8'h51);
        repeat (20000) @(posedge clk27);
        if (dut.volume_target !== 7'd0)
            $fatal(1, "Down lower clamp failed: %0d", dut.volume_target);

        // 7) 步长：Up 一次回到 5，Down 一次回 0。
        tap_key(8'h52);
        wait_volume_target(7'd5);
        tap_key(8'h51);
        wait_volume_target(7'd0);

        // 8) 音量斜坡必须真正落到 0（volume_gain(0) 是数字静音）。
        frames = 0;
        while (dut.volume != 7'd0 && frames < 200000) begin
            @(posedge clk27); frames = frames + 1;
        end
        if (dut.volume != 7'd0) $fatal(1, "volume slew stuck at %0d", dut.volume);

        // 9) UART 兼容：先松开 HID，再用 N60 发声、X 清音。
        release_all();
        wait_gates(0);
        uart_cmd3("N", "6", "0");
        wait_gates(1);
        expect_note(7'd60);
        uart_cmd2("X", " ");
        wait_gates(0);

        // 10) Esc 清音：按住两键后 Esc 必须立即清空，且不留按键状态。
        kbd_report(8'h14, 8'h1A, 8'd0, 8'd0, 8'd0, 8'd0);
        wait_gates(2);
        kbd_report(8'h29, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0);
        wait_gates(0);
        repeat (2000) @(posedge clk27);
        if (dut.hid_held_count !== 4'd0)
            $fatal(1, "Esc left %0d held keys", dut.hid_held_count);
        release_all();
        repeat (50000) @(posedge clk27);
        if (gate_n != 0) $fatal(1, "residual voices after Esc: %b", dut.v_gate);

        $display("PASS tb_top_host_ctrl: UART compat, first key, chord, F6 piano/guitar switch, Up/Down volume clamps, Esc clear");
        $finish;
    end

    initial begin
        #300000000;
        $fatal(1, "timeout");
    end
endmodule
