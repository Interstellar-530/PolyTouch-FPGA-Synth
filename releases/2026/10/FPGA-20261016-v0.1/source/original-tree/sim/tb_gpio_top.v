`timescale 1ns/1ps
// [S2-AI 新增] 本测试台由 AI 于 2026-10-14 为缺件期间任务清单 S2 编写，供后续智能体复查。
// 顶层模式回归：GPIO 按下退出演示、四键同拍、按住不重触发、Panic 与模式切换优先、
// 松开后再按恢复演奏、UART 演奏路径不受影响、以及从手动切回演示时按键保持安静。
//
// 计数方式：分配器每接受一个 Note On 就发一个单拍 v_start 脉冲。测试台用“基准差值”
// 而不是“清零计数”来判定增量，并在读计数前多等几拍，避免读到 v_start 生效前的那一刻。
// 上电演示按 tb_song_timing 的记录第一遍没有 Note On，首个音符约在 0.42 s，
// 因此这里不等待演示出声，只确认演示已武装。
module tb_gpio_top;

    localparam integer PRESS   = 27000;   // 与 gpio_keyboard 默认门限保持一致
    localparam integer RELEASE = 81000;

    reg clk = 1'b0, key_rst = 1'b0, key_s1 = 1'b1, key_s2 = 1'b1, uart_rx = 1'b1;
    reg [11:0] gpio_key_n = 12'hFFF;
    wire hp_bck, hp_ws, hp_din, pa_en, led, led_chord, led_t0, led_t1, uart_tx;

    integer cycles = 0, start_pulses = 0, baseline = 0;
    integer press_cycle = 0, latency = 0, i;
    integer find_voice;
    reg watch_manual = 1'b0;
    reg [11:0] manual_on_seen = 0, manual_off_seen = 0;
    integer manual_reads = 0, manual_ons = 0, manual_offs = 0;
    reg saw_full_replace = 1'b0;

    // [S4/S5/S6] 新增顶层端口与 MCP3208 器件模型：CH0 作压力、CH1 作弯音。
    // 弯音保持在中点 2048，比率恰为 1.0，因此本测试台原有的音频期望不变。
    wire adc_cs_n, adc_sck, adc_mosi, adc_miso;
    wire [3:0] clip_fold;
    reg [11:0] adc_ch0 = 12'd1024, adc_ch1 = 12'd2048;
    mcp3208_model u_adc_model (
        .cs_n(adc_cs_n), .sclk(adc_sck), .mosi(adc_mosi), .miso(adc_miso),
        .ch0(adc_ch0), .ch1(adc_ch1), .ch2(12'd0), .ch3(12'd0),
        .ch4(12'd0), .ch5(12'd0), .ch6(12'd0), .ch7(12'd0)
    );

    top dut (.clk_27m(clk), .key_rst(key_rst), .key_s1(key_s1), .key_s2(key_s2),
             .uart_rx(uart_rx), .gpio_key_n(gpio_key_n),
             .hp_bck(hp_bck), .hp_ws(hp_ws), .hp_din(hp_din),
             .pa_en(pa_en), .led(led), .led_chord(led_chord),
             .led_t0(led_t0), .led_t1(led_t1), .uart_tx(uart_tx),
             .adc_cs_n(adc_cs_n), .adc_sck(adc_sck), .adc_mosi(adc_mosi),
             .adc_miso(adc_miso), .clip_fold(clip_fold));


    always #18.5185 clk = ~clk;

    always @(posedge clk) begin
        cycles = cycles + 1;
        if (watch_manual && dut.man_rd && !dut.man_empty) begin
            if (dut.man_data[14:8] < 60 || dut.man_data[14:8] > 71)
                $fatal(1, "manual FIFO delivered an unexpected pitch");
            manual_reads = manual_reads + 1;
            if (dut.man_data[15]) begin
                if (manual_on_seen[dut.man_data[14:8]-60])
                    $fatal(1, "manual FIFO duplicated a Note On");
                manual_on_seen[dut.man_data[14:8]-60] = 1'b1;
                manual_ons = manual_ons + 1;
            end else begin
                if (manual_off_seen[dut.man_data[14:8]-60])
                    $fatal(1, "manual FIFO duplicated a Note Off");
                manual_off_seen[dut.man_data[14:8]-60] = 1'b1;
                manual_offs = manual_offs + 1;
            end
            if (dut.u_manual.full && dut.man_wr && dut.gp_ev_ready)
                saw_full_replace = 1'b1;
        end
        if (!dut.rst && (|dut.v_start)) begin
            start_pulses = start_pulses + 1;
            $display("note-on start: t=%0t count=%0d v_gate=%b v_note=%h",
                     $time, start_pulses, dut.v_gate, dut.v_note);
        end
    end

    // 找出当前 gate 打开且音高匹配的声部，找不到返回 -1。
    task find_gated_voice;
        input integer note;
        begin
            find_voice = -1;
            if (dut.v_gate[0] && (dut.v_note[6:0]   == note[6:0])) find_voice = 0;
            else if (dut.v_gate[1] && (dut.v_note[13:7]  == note[6:0])) find_voice = 1;
            else if (dut.v_gate[2] && (dut.v_note[20:14] == note[6:0])) find_voice = 2;
            else if (dut.v_gate[3] && (dut.v_note[27:21] == note[6:0])) find_voice = 3;
        end
    endtask

    task wait_cycles;
        input integer n;
        integer c;
        begin
            for (c = 0; c < n; c = c + 1) @(negedge clk);
        end
    endtask

    task send_byte;
        input [7:0] data;
        integer bitno;
        begin
            @(negedge clk); uart_rx = 0; #8680;
            for (bitno = 0; bitno < 8; bitno = bitno + 1) begin
                uart_rx = data[bitno]; #8680;
            end
            uart_rx = 1; #8680;
        end
    endtask

    task settle;
        begin repeat (12) @(negedge clk); end
    endtask

    initial begin
        #100000;
        key_rst = 1'b1;
        wait (!dut.rst);
        if (!dut.demo_mode) $fatal(1, "power-on demo missing");
        if (dut.v_gate !== 4'b0000) $fatal(1, "voices gated before any input");

        // ---- 1. GPIO 按下退出演示，并在有界时间内发声 ---------------------
        baseline = start_pulses;
        press_cycle = cycles;
        gpio_key_n[0] = 1'b0;
        wait (!dut.demo_mode);
        if (dut.v_gate !== 4'b0000)
            $fatal(1, "stale voices survived the GPIO mode switch");
        if (!dut.fifo_empty)
            $fatal(1, "demo FIFO not emptied on the GPIO mode switch");
        while (!(|dut.v_gate)) begin
            @(negedge clk);
            if ((cycles - press_cycle) > (PRESS + 2000))
                $fatal(1, "GPIO press-to-voice latency exceeded bound");
        end
        latency = cycles - press_cycle;
        wait_cycles(4);
        $display("ok   GPIO press-to-voice latency = %0d cycles (bound %0d)",
                 latency, PRESS + 2000);
        find_gated_voice(60);
        if (find_voice < 0) $fatal(1, "GPIO key 0 did not sound C4");
        if ((start_pulses - baseline) != 1)
            $fatal(1, "GPIO key 0 started %0d voices, want 1", start_pulses - baseline);

        // ---- 2. 按住不重触发 ---------------------------------------------
        baseline = start_pulses;
        wait_cycles(200000);
        if ((start_pulses - baseline) != 0) $fatal(1, "held GPIO key retriggered");
        if (dut.v_gate !== 4'b0001)
            $fatal(1, "held GPIO key gate changed to %b", dut.v_gate);

        // ---- 3. 再同拍按下三个 GPIO 键，四个声部占满 ----------------------
        baseline = start_pulses;
        gpio_key_n[3:1] = 3'b000;
        wait_cycles(PRESS + 400);
        if ((start_pulses - baseline) != 3)
            $fatal(1, "three more GPIO keys produced %0d starts, want 3",
                   start_pulses - baseline);
        if (dut.v_gate !== 4'b1111)
            $fatal(1, "four GPIO keys did not fill four voices, gate=%b", dut.v_gate);

        // ---- 4. Panic 优先，且按住键不重触发 -----------------------------
        send_byte("X"); send_byte(8'h0D); settle();
        if (dut.v_gate !== 4'b0000) $fatal(1, "panic did not release the voices");
        if (dut.demo_mode) $fatal(1, "panic wrongly enabled the demo");
        baseline = start_pulses;
        wait_cycles(200000);
        if ((start_pulses - baseline) != 0) $fatal(1, "held keys retriggered after panic");
        if (dut.v_gate !== 4'b0000) $fatal(1, "held keys gated again after panic");

        gpio_key_n = 12'hFFF;
        wait_cycles(RELEASE + 400);
        if (dut.v_gate !== 4'b0000) $fatal(1, "release after panic restarted a voice");
        if (!dut.u_manual.empty) $fatal(1, "manual FIFO not drained after panic");

        baseline = start_pulses;
        gpio_key_n[0] = 1'b0;
        wait_cycles(PRESS + 400);
        find_gated_voice(60);
        if (find_voice < 0) $fatal(1, "re-press after panic did not sound");
        if ((start_pulses - baseline) != 1)
            $fatal(1, "re-press after panic started %0d voices, want 1",
                   start_pulses - baseline);
        gpio_key_n = 12'hFFF;
        wait_cycles(RELEASE + 400);

        // ---- 5. UART 演奏路径不受 GPIO 接入影响 --------------------------
        send_byte("N"); send_byte("6"); send_byte("7"); send_byte(8'h0D); settle();
        find_gated_voice(67);
        if (find_voice < 0) $fatal(1, "UART note did not sound after adding the GPIO path");
        send_byte("O"); send_byte("6"); send_byte("7"); send_byte(8'h0D); settle();
        if (dut.v_gate !== 4'b0000) $fatal(1, "UART note off failed");

        // ---- 6. 手动切回演示并按住键：键保持安静，松开不重启手动 ---------
        baseline = start_pulses;
        gpio_key_n[0] = 1'b0;
        wait_cycles(PRESS + 400);
        if (dut.demo_mode) $fatal(1, "GPIO press did not enter manual mode");
        if ((start_pulses - baseline) != 1)
            $fatal(1, "GPIO press started %0d voices, want 1", start_pulses - baseline);
        send_byte("D"); send_byte("1"); send_byte(8'h0D); settle();
        if (!dut.demo_mode) $fatal(1, "D1 did not return to demo");
        if (dut.v_gate !== 4'b0000) $fatal(1, "D1 left a manual voice gated");
        for (i = 0; i < 100000; i = i + 1) begin
            @(negedge clk);
            if (!dut.u_manual.empty)
                $fatal(1, "held key queued an event after returning to demo");
            if (!dut.demo_mode)
                $fatal(1, "demo stopped while a key was merely held");
        end

        // 松开键：进入演示时已经清空声部，这次松键没有对象，按设计丢弃，
        // 既不能把演示拉回手动，也不能在队列里挡住后面的按键事件。
        gpio_key_n = 12'hFFF;
        wait_cycles(RELEASE + 400);
        if (!dut.demo_mode) $fatal(1, "GPIO release restarted manual mode during demo");
        if (dut.v_gate !== 4'b0000) $fatal(1, "released key left a voice gated");
        if (!dut.u_manual.empty) $fatal(1, "released key queued an event during demo");

        baseline = start_pulses;
        gpio_key_n[0] = 1'b0;
        wait_cycles(PRESS + 400);
        if (dut.demo_mode) $fatal(1, "press during demo did not return to manual");
        find_gated_voice(60);
        if (find_voice < 0) $fatal(1, "returning to manual did not sound key 0");
        if ((start_pulses - baseline) != 1)
            $fatal(1, "returning to manual started %0d voices, want 1",
                   start_pulses - baseline);
        if (!dut.u_manual.empty) $fatal(1, "manual FIFO not drained after returning");

        // ---- 7. UART 持续占用仲裁器，填满手动 FIFO 后让 GPIO 在上游等待 ----
        gpio_key_n = 12'hFFF;
        wait_cycles(RELEASE + 40);
        send_byte("D"); send_byte("0"); send_byte(8'h0D); settle();
        // 人为延长高优先级来源占用，检验实际仲裁/ready 连线；不加速按键消抖。
        force dut.uart_ev_valid = 1'b1;
        force dut.uart_ev_on = 1'b0;
        force dut.uart_ev_note = 7'd0;
        gpio_key_n = 12'h000;
        wait_cycles(PRESS + 40);
        gpio_key_n[3:0] = 4'hF;
        wait_cycles(RELEASE + 40);
        if (!dut.u_manual.full)
            $fatal(1, "manual FIFO did not fill with 12 On and 4 Off events");
        gpio_key_n[7:4] = 4'hF;
        wait_cycles(RELEASE + 40);
        if (!dut.gp_ev_valid || dut.gp_ev_ready || dut.u_gpio.drop_count !== 8'd0)
            $fatal(1, "GPIO did not retain events behind the full manual FIFO");
        watch_manual = 1'b1;
        release dut.uart_ev_valid;
        release dut.uart_ev_on;
        release dut.uart_ev_note;
        wait_cycles(100);
        watch_manual = 1'b0;
        if (manual_reads != 20 || manual_ons != 12 || manual_offs != 8 ||
            manual_on_seen !== 12'hFFF || manual_off_seen !== 12'h0FF ||
            !saw_full_replace || !dut.man_empty || dut.gp_ev_valid ||
            dut.u_gpio.drop_count !== 8'd0)
            $fatal(1, "full manual FIFO lost, duplicated or blocked events: reads=%0d On=%0d Off=%0d",
                   manual_reads, manual_ons, manual_offs);
        $display("ok   full manual FIFO: 16 resident + 4 retained, 20 events delivered, full read/write");

        $display("PASS tb_gpio_top: GPIO mode switch, 4-key burst, panic priority, UART path");
        $finish;
    end

    initial begin
        #120000000;
        $fatal(1, "FAIL tb_gpio_top: timeout");
    end
endmodule
