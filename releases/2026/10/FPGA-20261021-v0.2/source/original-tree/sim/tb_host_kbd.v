`timescale 1ns/1ps
// CH9350L state-2 键盘输入链路验收：UART RX -> 帧解析 -> 键位/移调/控制。
//
// 覆盖：按下/松开、报告重复去重、和弦、移调后松开用按下时音高、PageDown、
// Esc 全松键、F1 音色、截断帧 1 ms 重同步、rollover 释放。
module tb_host_kbd;
    reg clk = 0;
    always #18.5185 clk = ~clk;   // 27 MHz

    reg rst = 1;
    reg kbd_rx = 1;
    reg flush = 0;
    wire kbd_tx;
    wire ev_valid;
    wire [15:0] ev_word;
    wire panic, timbre_valid;
    wire [7:0] timbre_value;
    wire [6:0] base_note;
    wire [3:0] held_count;
    wire overflow, link_timeout, frame_valid;

    host_kbd_input #(.CLK_HZ(27000000), .BAUD(115200), .WATCHDOG_MS(100)) dut (
        .clk(clk), .rst(rst), .kbd_rx(kbd_rx), .kbd_tx(kbd_tx),
        .flush(flush),
        .ev_valid(ev_valid), .ev_word(ev_word), .ev_ready(1'b1),
        .panic(panic), .timbre_valid(timbre_valid), .timbre_value(timbre_value),
        .base_note(base_note), .held_count(held_count),
        .overflow(overflow), .link_timeout(link_timeout), .frame_valid(frame_valid)
    );

    integer nev = 0;
    integer rd  = 0;
    integer k;
    reg [15:0] evlog [0:255];
    always @(posedge clk) begin
        if (ev_valid) begin
            evlog[nev] = ev_word;
            nev = nev + 1;
        end
    end

    reg panic_seen = 0, timbre_seen = 0;
    reg [7:0] timbre_cap = 0;
    always @(posedge clk) begin
        if (panic) panic_seen <= 1'b1;
        if (timbre_valid) begin timbre_seen <= 1'b1; timbre_cap <= timbre_value; end
    end

    task send_byte;
        input [7:0] b;
        integer i;
        begin
            @(negedge clk); kbd_rx = 1'b0; #8667;
            for (i = 0; i < 8; i = i + 1) begin
                kbd_rx = b[i]; #8667;
            end
            kbd_rx = 1'b1; #8667;
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

    task expect_ev;
        input on;
        input [6:0] note;
        integer t;
        begin
            t = 0;
            while (nev <= rd && t < 20000) begin @(posedge clk); t = t + 1; end
            if (nev <= rd)
                $fatal(1, "timeout waiting event %0d", rd);
            if (evlog[rd][15] !== on || evlog[rd][14:8] !== note)
                $fatal(1, "event %0d got on=%b note=%0d, expect on=%b note=%0d",
                       rd, evlog[rd][15], evlog[rd][14:8], on, note);
            rd = rd + 1;
        end
    endtask

    task expect_quiet;
        input integer cycles;
        begin
            repeat (cycles) @(posedge clk);
            if (nev != rd)
                $fatal(1, "unexpected events: %0d extra (last on=%b note=%0d)",
                       nev - rd, evlog[nev-1][15], evlog[nev-1][14:8]);
        end
    endtask

    integer t;
    initial begin
        repeat (20) @(posedge clk);
        rst = 0;
        repeat (10) @(posedge clk);

        // attach 序列：86 / 80 FF / 89
        send_byte(8'h57); send_byte(8'hAB); send_byte(8'h86);
        expect_quiet(200);
        send_byte(8'h57); send_byte(8'hAB); send_byte(8'h80); send_byte(8'hFF);
        send_byte(8'h57); send_byte(8'hAB); send_byte(8'h89);
        expect_quiet(200);

        // Q -> Note On 60
        send_report(8'h14, 0, 0, 0, 0, 0);
        expect_ev(1'b1, 7'd60);
        // 同一报告重复 3 次 -> 不去重就失败
        send_report(8'h14, 0, 0, 0, 0, 0);
        send_report(8'h14, 0, 0, 0, 0, 0);
        send_report(8'h14, 0, 0, 0, 0, 0);
        expect_quiet(2000);

        // Q + W -> 只新增 W (62)
        send_report(8'h14, 8'h1A, 0, 0, 0, 0);
        expect_ev(1'b1, 7'd62);
        expect_quiet(2000);

        // 松开 Q，W 仍按住 -> Note Off 60
        send_report(8'h1A, 0, 0, 0, 0, 0);
        expect_ev(1'b0, 7'd60);
        // 松开 W，按 Z -> Off 62, On 48
        send_report(8'h1D, 0, 0, 0, 0, 0);
        expect_ev(1'b0, 7'd62);
        expect_ev(1'b1, 7'd48);

        // Z 按住时 PageDown -> base 变 48，Z 不重新触发
        send_report(8'h1D, 8'h4E, 0, 0, 0, 0);
        expect_quiet(2000);
        if (base_note !== 7'd48)
            $fatal(1, "PageDown base_note=%0d expect 48", base_note);
        // 松开 PageDown
        send_report(8'h1D, 0, 0, 0, 0, 0);
        expect_quiet(2000);
        // 松开 Z -> 必须用按下时存下的 48，而不是 36
        send_report(0, 0, 0, 0, 0, 0);
        expect_ev(1'b0, 7'd48);
        if (base_note !== 7'd48)
            $fatal(1, "base_note changed on release: %0d", base_note);

        // PageUp 回 60
        send_report(8'h4B, 0, 0, 0, 0, 0);
        expect_quiet(2000);
        send_report(0, 0, 0, 0, 0, 0);
        expect_quiet(2000);
        if (base_note !== 7'd60)
            $fatal(1, "PageUp base_note=%0d expect 60", base_note);

        // Esc -> panic
        send_report(8'h29, 0, 0, 0, 0, 0);
        expect_quiet(2000);
        if (!panic_seen) $fatal(1, "Esc did not pulse panic");
        send_report(0, 0, 0, 0, 0, 0);
        expect_quiet(2000);

        // F1 -> T250
        send_report(8'h3A, 0, 0, 0, 0, 0);
        expect_quiet(2000);
        if (!timbre_seen || timbre_cap !== 8'd250)
            $fatal(1, "F1 timbre seen=%b value=%0d expect 250", timbre_seen, timbre_cap);
        send_report(0, 0, 0, 0, 0, 0);
        expect_quiet(2000);

        // 截断帧 + 1 ms 间隔 -> 重同步后仍能收 Q
        send_byte(8'h57); send_byte(8'hAB); send_byte(8'h01);
        send_byte(8'h00); send_byte(8'h00);
        #2000000;   // 2 ms > 1 ms 字节间隔超时
        send_report(8'h14, 0, 0, 0, 0, 0);
        expect_ev(1'b1, 7'd60);

        // rollover (0x01) -> 释放 Q
        send_report(8'h01, 8'h01, 8'h01, 8'h01, 8'h01, 8'h01);
        expect_ev(1'b0, 7'd60);
        expect_quiet(2000);


        // FIFO 回绕：20 次按/松 = 40 事件，跨 16 项两次
        for (k = 0; k < 20; k = k + 1) begin
            send_report(8'h14, 0, 0, 0, 0, 0);
            expect_ev(1'b1, 7'd60);
            send_report(0, 0, 0, 0, 0, 0);
            expect_ev(1'b0, 7'd60);
        end
        expect_quiet(100);
        if (dut.u_map.count !== 5'd0)
            $fatal(1, "FIFO count after wrap=%0d", dut.u_map.count);

        // flush 清空事件队列和音符归属；仍按住的键须松开后才能再次触发。
        send_report(8'h14, 0, 0, 0, 0, 0);
        expect_ev(1'b1, 7'd60);
        flush = 1'b1; repeat (3) @(posedge clk); flush = 1'b0;
        expect_quiet(200);
        if (dut.u_map.count !== 5'd0 || held_count !== 4'd0)
            $fatal(1, "flush left queue=%0d held=%0d prev_ok=%b seen=%b key=%h busy=%b phase=%d count=%0d", dut.u_map.count, held_count, dut.u_map.prev_ok[0], dut.u_map.prev_seen[0], dut.u_map.prev_key[0], dut.u_map.busy, dut.u_map.phase, dut.u_map.count);

        send_report(8'h14, 0, 0, 0, 0, 0);
        expect_quiet(200);
        if (held_count !== 4'd0) $fatal(1, "held key retriggered after flush");
        send_report(0, 0, 0, 0, 0, 0);
        expect_quiet(100);

        // 0x86 拔出通知：清按键/队列，不残留事件
        send_report(8'h14, 0, 0, 0, 0, 0);
        expect_ev(1'b1, 7'd60);
        send_byte(8'h57); send_byte(8'hAB); send_byte(8'h86);
        expect_quiet(500);
        if (dut.u_map.count !== 5'd0 || held_count !== 4'd0)
            $fatal(1, "device notify left queue=%0d held=%0d", dut.u_map.count, held_count);
        if (overflow) $fatal(1, "event FIFO overflow");

        $display("PASS tb_host_kbd: press/release, dedup, chord, transpose-held, Esc, F1, resync, rollover");
        $finish;
    end

    initial begin
        #200000000;
        $fatal(1, "timeout");
    end
endmodule
