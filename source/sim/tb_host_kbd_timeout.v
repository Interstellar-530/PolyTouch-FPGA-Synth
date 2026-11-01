`timescale 1ns/1ps
// 优化 07：CH9350L 长按与断线策略。
// 并排验证 idle-only（默认）与 strict（旧行为）：
//   1. 无持键静默超时两档都生效；
//   2. 持键静默只让 strict 清键，idle-only 保持长音；
//   3. 0x82 心跳允许两档持续长按；
//   4. 0x86 拔出通知两档都立即清键，之后可重新起音。
module tb_host_kbd_timeout #(parameter integer LONG_HOLD_MS = 5000);
    localparam integer CLK_HZ = 1000000;
    localparam integer BAUD = 100000;
    localparam integer WATCHDOG_MS = 20;

    reg clk = 0;
    always #500 clk = ~clk;       // 1 MHz，等比例缩短仿真时间

    reg rst = 1;
    reg kbd_rx = 1;

    wire safe_tx, strict_tx;
    wire safe_ev_valid, strict_ev_valid;
    wire [15:0] safe_ev_word, strict_ev_word;
    wire safe_panic, strict_panic;
    wire safe_timbre_valid, strict_timbre_valid;
    wire [7:0] safe_timbre_value, strict_timbre_value;
    wire safe_instr_toggle, strict_instr_toggle;
    wire safe_vol_up, strict_vol_up;
    wire safe_vol_down, strict_vol_down;
    wire [6:0] safe_base_note, strict_base_note;
    wire [3:0] safe_held_count, strict_held_count;
    wire safe_overflow, strict_overflow;
    wire safe_link_timeout, strict_link_timeout;
    wire safe_device_notify, strict_device_notify;
    wire safe_frame_valid, strict_frame_valid;

    host_kbd_input #(
        .CLK_HZ(CLK_HZ), .BAUD(BAUD),
        .WATCHDOG_MS(WATCHDOG_MS), .TIMEOUT_POLICY(1)
    ) dut_safe (
        .clk(clk), .rst(rst), .kbd_rx(kbd_rx), .kbd_tx(safe_tx),
        .flush(1'b0),
        .ev_valid(safe_ev_valid), .ev_word(safe_ev_word), .ev_ready(1'b1),
        .panic(safe_panic), .timbre_valid(safe_timbre_valid), .timbre_value(safe_timbre_value),
        .instr_toggle(safe_instr_toggle), .vol_up(safe_vol_up), .vol_down(safe_vol_down),
        .base_note(safe_base_note), .held_count(safe_held_count),
        .overflow(safe_overflow), .link_timeout(safe_link_timeout),
        .device_notify(safe_device_notify), .frame_valid(safe_frame_valid)
    );

    host_kbd_input #(
        .CLK_HZ(CLK_HZ), .BAUD(BAUD),
        .WATCHDOG_MS(WATCHDOG_MS), .TIMEOUT_POLICY(0)
    ) dut_strict (
        .clk(clk), .rst(rst), .kbd_rx(kbd_rx), .kbd_tx(strict_tx),
        .flush(1'b0),
        .ev_valid(strict_ev_valid), .ev_word(strict_ev_word), .ev_ready(1'b1),
        .panic(strict_panic), .timbre_valid(strict_timbre_valid), .timbre_value(strict_timbre_value),
        .instr_toggle(strict_instr_toggle), .vol_up(strict_vol_up), .vol_down(strict_vol_down),
        .base_note(strict_base_note), .held_count(strict_held_count),
        .overflow(strict_overflow), .link_timeout(strict_link_timeout),
        .device_notify(strict_device_notify), .frame_valid(strict_frame_valid)
    );

    integer safe_ev = 0, strict_ev = 0;
    integer safe_to = 0, strict_to = 0;
    always @(posedge clk) begin
        if (!rst) begin
            if (safe_ev_valid) safe_ev = safe_ev + 1;
            if (strict_ev_valid) strict_ev = strict_ev + 1;
            if (safe_link_timeout) safe_to = safe_to + 1;
            if (strict_link_timeout) strict_to = strict_to + 1;
        end
    end

    task send_byte;
        input [7:0] b;
        integer i;
        begin
            @(negedge clk); kbd_rx = 1'b0; #10000;
            for (i = 0; i < 8; i = i + 1) begin
                kbd_rx = b[i]; #10000;
            end
            kbd_rx = 1'b1; #10000;
        end
    endtask

    task send_report;
        input [7:0] k0, k1, k2, k3, k4, k5;
        begin
            send_byte(8'h57); send_byte(8'hAB); send_byte(8'h01);
            send_byte(8'h00); send_byte(8'h00);
            send_byte(k0); send_byte(k1); send_byte(k2);
            send_byte(k3); send_byte(k4); send_byte(k5);
        end
    endtask

    task send_heartbeat;
        begin
            send_byte(8'h57); send_byte(8'hAB); send_byte(8'h82); send_byte(8'h01);
        end
    endtask

    task send_detach;
        begin
            send_byte(8'h57); send_byte(8'hAB); send_byte(8'h86);
        end
    endtask

    task wait_cycles;
        input integer n;
        begin
            repeat (n) @(posedge clk);
        end
    endtask

    task wait_ms;
        input integer ms;
        begin
            repeat (CLK_HZ / 1000 * ms) @(posedge clk);
        end
    endtask

    task expect_safe_held;
        input [3:0] want;
        integer n;
        begin
            n = 0;
            while (safe_held_count !== want && n < 10000) begin
                @(posedge clk); n = n + 1;
            end
            if (safe_held_count !== want)
                $fatal(1, "safe held_count=%0d expect %0d", safe_held_count, want);
        end
    endtask

    task expect_strict_held;
        input [3:0] want;
        integer n;
        begin
            n = 0;
            while (strict_held_count !== want && n < 10000) begin
                @(posedge clk); n = n + 1;
            end
            if (strict_held_count !== want)
                $fatal(1, "strict held_count=%0d expect %0d", strict_held_count, want);
        end
    endtask

    task check_both_held;
        input [3:0] safe_want, strict_want;
        begin
            if (safe_held_count !== safe_want)
                $fatal(1, "safe held_count=%0d expect %0d", safe_held_count, safe_want);
            if (strict_held_count !== strict_want)
                $fatal(1, "strict held_count=%0d expect %0d", strict_held_count, strict_want);
        end
    endtask

    integer safe_ev_mark, strict_ev_mark, safe_to_mark, strict_to_mark;
    initial begin
        repeat (20) @(posedge clk);
        rst = 0;
        repeat (10) @(posedge clk);

        // 设备接入，建立 link 基线。
        send_byte(8'h57); send_byte(8'hAB); send_byte(8'h86);
        wait_cycles(300);

        // 1) 无持键静默：两档都应报告有效超时。
        safe_to_mark = safe_to; strict_to_mark = strict_to;
        wait_ms(25);
        wait_cycles(100);
        if (safe_to == safe_to_mark)
            $fatal(1, "idle-only did not report timeout while idle");
        if (strict_to == strict_to_mark)
            $fatal(1, "strict did not report timeout while idle");

        // 2) 持键后连续 5 秒无心跳：idle-only 保持长音，strict 清键。
        send_report(8'h14, 0, 0, 0, 0, 0);
        expect_safe_held(4'd1);
        expect_strict_held(4'd1);
        safe_ev_mark = safe_ev; strict_ev_mark = strict_ev;
        safe_to_mark = safe_to; strict_to_mark = strict_to;
        if (LONG_HOLD_MS < 3 * WATCHDOG_MS) $fatal(1, "hold must span at least three watchdog windows");
        wait_ms(LONG_HOLD_MS);
        wait_cycles(100);
        check_both_held(4'd1, 4'd0);
        if (safe_ev != safe_ev_mark || strict_ev != strict_ev_mark)
            $fatal(1, "timeout generated note events: safe=%0d/%0d strict=%0d/%0d",
                   safe_ev, safe_ev_mark, strict_ev, strict_ev_mark);
        if (safe_to != safe_to_mark)
            $fatal(1, "idle-only timeout leaked while a key was held");
        if (strict_to == strict_to_mark)
            $fatal(1, "strict timeout did not clear the held key");

        // 3) 心跳续期：两档都不再超时；strict 的旧键已被清，重发按下应重新起音。
        send_heartbeat();
        wait_cycles(300);
        check_both_held(4'd1, 4'd0);
        send_report(8'h14, 0, 0, 0, 0, 0);
        expect_safe_held(4'd1);
        expect_strict_held(4'd1);
        if (safe_ev != safe_ev_mark)
            $fatal(1, "idle-only retriggered a still-held key after heartbeat");
        if (strict_ev != strict_ev_mark + 1)
            $fatal(1, "strict did not retrigger after heartbeat recovery");

        // 4) 周期心跳持续长按：多次超过单次 watchdog 周期仍保持。
        safe_ev_mark = safe_ev; strict_ev_mark = strict_ev;
        repeat (4) begin
            send_heartbeat();
            wait_ms(10);
        end
        wait_cycles(200);
        check_both_held(4'd1, 4'd1);
        if (safe_ev != safe_ev_mark || strict_ev != strict_ev_mark)
            $fatal(1, "heartbeat sustain generated unexpected events");

        // 5) 0x86 拔出通知：两档立即清键，随后可重新起音。
        send_detach();
        wait_cycles(300);
        check_both_held(4'd0, 4'd0);
        send_report(8'h14, 0, 0, 0, 0, 0);
        expect_safe_held(4'd1);
        expect_strict_held(4'd1);

        $display("PASS tb_host_kbd_timeout: idle-only long hold (%0d ms), strict compatibility, heartbeat sustain, detach recovery", LONG_HOLD_MS);
        $finish;
    end

    initial begin
        #10000000000;
        $fatal(1, "timeout");
    end
endmodule
