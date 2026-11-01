`timescale 1ns/1ps
// [集成] 27 MHz 标准 I2S 档顶层验收（top 的 AUDIO_IF=2：板载 27 MHz / 46.875 kHz / 24 位槽）。
//
// 与 tb_top_i2s 的区别：不驱动 12.288 MHz，系统时钟只有 H11 的 27 MHz；帧长 576 拍，
// BCK 9 拍（高 4 低 5），LRCK 46.875 kHz。判据仍从 i2s_bck/i2s_lrck/i2s_din 三根引脚
// 重新解码；只有相位增量直读 dut.inc*（属于被测接口本身）。
//
// 覆盖：
//   1) sample_tick 单拍、间隔 576 个 clk_27m（46.875 kHz）；
//   2) BCK 周期 9 拍 = 3.000 MHz、高 4 低 5；LRCK 周期 576 拍；每帧 64 个 BCK；
//   3) DIN 只在 BCK 下降沿变化；位置 0 与 25..31 为零填充；
//   4) 每帧解出的 24 位字与 DUT 的 final_sample24 对齐；
//   5) 未选中的板载 PT8211 三线恒低、dac_xsmt 恒高、三线无 X；
//   6) A4 解码波形向上过零平均周期 = 46875/440 = 106.53 拍（±1%）；
//   7) A4 相位增量与 440*2^32/46875 相差 < 3 ppm（不是 48 kHz 常数）；
//   8) UART X 退出演示、M0 数字静音、M1 恢复。
module tb_top_i2s_27m;
    reg clk27 = 1'b0, clk12 = 1'b0;
    reg key_rst = 1'b0, key_s1 = 1'b1, key_s2 = 1'b1, uart_rx = 1'b1;
    reg kbd_rx = 1'b1;
    wire kbd_tx;
    reg [11:0] gpio_key_n = 12'hFFF;
    wire hp_bck, hp_ws, hp_din, pa_en, led, led_chord, led_t0, led_t1, uart_tx;
    wire adc_cs_n, adc_sck, adc_mosi, adc_miso;
    wire [3:0] clip_fold;
    wire i2s_bck, i2s_lrck, i2s_din, dac_xsmt;
    reg [11:0] adc_ch0 = 12'd2048, adc_ch1 = 12'd2048;

    always #18.5185 clk27 = ~clk27;   // 27 MHz（半周期 18.5185 ns）
    // clk_12m288 在本档不参与逻辑，但顶层端口必须被驱动。
    always #40.69   clk12 = ~clk12;

    mcp3208_model u_adc_model (
        .cs_n(adc_cs_n), .sclk(adc_sck), .mosi(adc_mosi), .miso(adc_miso),
        .ch0(adc_ch0), .ch1(adc_ch1), .ch2(12'd0), .ch3(12'd0),
        .ch4(12'd0), .ch5(12'd0), .ch6(12'd0), .ch7(12'd0)
    );

    top #(.AUDIO_IF(2), .I2S_DATA_BITS(24),
          .VOICES(8), .MASTER_VOLUME_SHIFT(3),
          .GPIO_KEY_ENABLE(0), .HOST_KBD_ENABLE(1)) dut (
        .clk_27m(clk27), .clk_12m288(clk12),
        .key_rst(key_rst), .key_s1(key_s1), .key_s2(key_s2),
        .uart_rx(uart_rx), .gpio_key_n(12'hFFF),
        .kbd_uart_rx(kbd_rx), .kbd_uart_tx(kbd_tx),
        .adc_cs_n(adc_cs_n), .adc_sck(adc_sck), .adc_mosi(adc_mosi), .adc_miso(adc_miso),
        .hp_bck(hp_bck), .hp_ws(hp_ws), .hp_din(hp_din), .pa_en(pa_en),
        .led(led), .led_chord(led_chord), .led_t0(led_t0), .led_t1(led_t1),
        .uart_tx(uart_tx), .clip_fold(clip_fold),
        .i2s_bck(i2s_bck), .i2s_lrck(i2s_lrck), .i2s_din(i2s_din), .dac_xsmt(dac_xsmt)
    );

    integer errors = 0;
    integer cyc = 0;
    integer last_tick = -1, tick_cnt = 0, tick_width_bad = 0, tick_gap_bad = 0;
    reg     tick_seen = 1'b0;
    integer last_bck_rise = -1, bck_period_bad = 0, bck_high_bad = 0, bck_cnt = 0;
    integer last_lrck_fall = -1, lrck_period_bad = 0, frame_cnt = 0;
    integer din_bad = 0, pad_bad = 0, word_bad = 0, x_bad = 0;
    integer slot = 0;
    reg [23:0] word = 24'd0;
    reg [23:0] exp_word = 24'd0;
    reg [23:0] decoded_latest = 24'd0;
    integer frames_checked = 0;

    reg signed [23:0] final_pipe = 24'sd0;
    reg bck_q = 1'b0, din_q = 1'b1;
    reg mon_en = 1'b0;

    integer xing = 0, first_xing = -1, last_xing = -1, samp_idx = 0, peak = 0;
    reg signed [15:0] prev_samp = 16'sd0;

    // 音高用引擎正弦分量的过零测；解码后的 16 位字受钢琴谐波与量化影响，过零会偏多。
    integer sxing = 0, sfirst = -1, slast = -1, sidx = 0;
    reg signed [20:0] sprev = 21'sd0;
    always @(posedge clk27) if (dut.sums_valid) begin
        sidx = sidx + 1;
        if (sprev <= 0 && dut.sine_sum > 0) begin
            sxing = sxing + 1;
            if (sfirst < 0) sfirst = sidx;
            slast = sidx;
        end
        sprev <= dut.sine_sum;
    end

    always @(posedge clk27) begin
        cyc = cyc + 1;
        final_pipe <= dut.final_sample24;

        if (!mon_en) begin
            bck_q = i2s_bck;
            din_q = i2s_din;
        end else begin
        if (^{i2s_bck, i2s_lrck, i2s_din, dac_xsmt} === 1'bx)
            x_bad = x_bad + 1;

        if (i2s_din !== din_q) begin
            if (!(bck_q === 1'b1 && i2s_bck === 1'b0)) begin
                if (din_bad < 5)
                    $display("FAIL tb_top_i2s_27m: DIN changed off a BCK falling edge at cyc=%0d", cyc);
                din_bad = din_bad + 1;
                errors = errors + 1;
            end
        end
        bck_q = i2s_bck;
        din_q = i2s_din;

        if (dut.sample_tick) begin
            if (tick_seen) begin
                tick_width_bad = tick_width_bad + 1;
                errors = errors + 1;
            end
            if (last_tick >= 0 && (cyc - last_tick) != 576) begin
                if (tick_gap_bad < 3)
                    $display("FAIL tb_top_i2s_27m: sample_tick interval=%0d expect 576", cyc - last_tick);
                tick_gap_bad = tick_gap_bad + 1;
                errors = errors + 1;
            end
            last_tick = cyc;
            tick_cnt  = tick_cnt + 1;
            tick_seen = 1'b1;
        end else
            tick_seen = 1'b0;
        end
    end

    always @(posedge i2s_bck) begin
        #1;
        if (mon_en) begin
        if (last_bck_rise >= 0 && (cyc - last_bck_rise) != 9) begin
            if (bck_period_bad < 3)
                $display("FAIL tb_top_i2s_27m: BCK period=%0d expect 9", cyc - last_bck_rise);
            bck_period_bad = bck_period_bad + 1;
            errors = errors + 1;
        end
        last_bck_rise = cyc;
        bck_cnt = bck_cnt + 1;

        slot = slot + 1;
        if (slot == 1 || slot == 33 || (slot >= 26 && slot <= 32) || (slot >= 58 && slot <= 64)) begin
            if (i2s_din !== 1'b0) begin
                if (pad_bad < 5)
                    $display("FAIL tb_top_i2s_27m: non-zero padding bit in slot %0d (frame %0d)", slot, frame_cnt);
                pad_bad = pad_bad + 1;
                errors = errors + 1;
            end
        end
        if ((slot >= 2 && slot <= 25) || (slot >= 34 && slot <= 57))
            word = {word[22:0], i2s_din};

        if (slot == 32) begin
            if (word !== exp_word) begin
                if (word_bad < 5)
                    $display("FAIL tb_top_i2s_27m: left word=%h expect=%h (frame %0d)", word, exp_word, frame_cnt);
                word_bad = word_bad + 1;
                errors = errors + 1;
            end
            decoded_latest = word;
            frames_checked = frames_checked + 1;
            begin : stats
                reg signed [15:0] s;
                s = word[23:8];
                samp_idx = samp_idx + 1;
                if (s > peak) peak = s;
                if (-s > peak) peak = -s;
                if (prev_samp <= 16'sd0 && s > 16'sd0) begin
                    xing = xing + 1;
                    if (first_xing < 0) first_xing = samp_idx;
                    last_xing = samp_idx;
                end
                prev_samp = s;
            end
            word = 24'd0;
        end
        if (slot == 64) begin
            if (word !== exp_word) begin
                if (word_bad < 5)
                    $display("FAIL tb_top_i2s_27m: right word=%h expect=%h (frame %0d)", word, exp_word, frame_cnt);
                word_bad = word_bad + 1;
                errors = errors + 1;
            end
            word = 24'd0;
            slot = 0;
        end
        end
    end

    always @(negedge i2s_lrck) begin
        #1;
        if (mon_en) begin
        if (last_lrck_fall >= 0 && (cyc - last_lrck_fall) != 576) begin
            if (lrck_period_bad < 3)
                $display("FAIL tb_top_i2s_27m: LRCK frame=%0d expect 576", cyc - last_lrck_fall);
            lrck_period_bad = lrck_period_bad + 1;
            errors = errors + 1;
        end
        last_lrck_fall = cyc;
        frame_cnt = frame_cnt + 1;
        exp_word = final_pipe;
        word = 24'd0;
        slot = 0;
        end
    end

    always @(negedge i2s_bck) begin
        #1;
        if (mon_en) begin
        if (last_bck_rise >= 0 && (cyc - last_bck_rise) != 4) begin
            if (bck_high_bad < 3)
                $display("FAIL tb_top_i2s_27m: BCK high=%0d expect 4", cyc - last_bck_rise);
            bck_high_bad = bck_high_bad + 1;
            errors = errors + 1;
        end
        end
    end

    task send_byte;
        input [7:0] data;
        integer bitno;
        begin
            @(negedge clk27); uart_rx = 1'b0; #8667;
            for (bitno = 0; bitno < 8; bitno = bitno + 1) begin
                uart_rx = data[bitno]; #8667;
            end
            uart_rx = 1'b1; #8667;
        end
    endtask

    task send_cmd3;
        input [7:0] c1; input [7:0] c2; input [7:0] c3;
        begin
            send_byte(c1); send_byte(c2); send_byte(c3); send_byte(8'h0D);
        end
    endtask

    task send_kbd_byte;
        input [7:0] data;
        integer bitno;
        begin
            @(negedge clk27); kbd_rx = 1'b0; #8667;
            for (bitno = 0; bitno < 8; bitno = bitno + 1) begin
                kbd_rx = data[bitno]; #8667;
            end
            kbd_rx = 1'b1; #8667;
        end
    endtask

    task send_kbd_report;
        input [7:0] k0, k1, k2, k3, k4, k5;
        begin
            send_kbd_byte(8'h57); send_kbd_byte(8'hAB); send_kbd_byte(8'h01);
            send_kbd_byte(8'h00); send_kbd_byte(8'h00);
            send_kbd_byte(k0); send_kbd_byte(k1); send_kbd_byte(k2);
            send_kbd_byte(k3); send_kbd_byte(k4); send_kbd_byte(k5);
        end
    endtask

    task wait_frames;
        input integer n;
        integer target;
        begin
            target = frame_cnt + n;
            while (frame_cnt < target) @(posedge clk27);
        end
    endtask

    integer diff, ideal, win_start;
    integer period_x100;

    initial begin
        repeat (8) @(posedge clk27);
        key_rst = 1'b1;
        while (dut.por) @(posedge clk27);      // 上电复位计数 65536 拍 ≈ 2.43 ms
        @(negedge i2s_lrck); #1;
        mon_en = 1'b1;
        wait_frames(8);

        // 1) 未使用的板载 PT8211 三线与 XSMT
        if (hp_bck !== 1'b0 || hp_ws !== 1'b0 || hp_din !== 1'b0) begin
            $display("FAIL tb_top_i2s_27m: unused PT8211 lines not low (bck=%b ws=%b din=%b)",
                     hp_bck, hp_ws, hp_din);
            errors = errors + 1;
        end
        if (dac_xsmt !== 1'b1) begin
            $display("FAIL tb_top_i2s_27m: dac_xsmt=%b expect 1", dac_xsmt);
            errors = errors + 1;
        end

        // 2) X 退出演示；随后只弹 A4
        send_cmd3("X", " ", " ");
        wait_frames(20);
        send_cmd3("N", "6", "9");
        wait_frames(800);

        if (dut.v_gate !== 8'b0000_0001) begin
            $display("FAIL tb_top_i2s_27m: expected only voice 0 gated, v_gate=%b", dut.v_gate);
            errors = errors + 1;
        end

        // 3) 单音 A4 过零平均周期（0.15 s ≈ 7031 帧；取 7200）
        sxing = 0; sfirst = -1; slast = -1; sidx = 0; sprev = 21'sd0;
        peak = 0;
        win_start = frame_cnt;
        while (frame_cnt - win_start < 7200) @(posedge clk27);
        if (sxing < 40) begin
            $display("FAIL tb_top_i2s_27m: only %0d sine zero crossings in 0.15 s", sxing);
            errors = errors + 1;
        end else begin
            period_x100 = ((slast - sfirst) * 100) / (sxing - 1);
            if (period_x100 < 10546 || period_x100 > 10760) begin
                $display("FAIL tb_top_i2s_27m: sine period=%0d.%02d samples expect 106.53",
                         period_x100 / 100, period_x100 % 100);
                errors = errors + 1;
            end else
                $display("INFO tb_top_i2s_27m: A4 sine period=%0d.%02d samples over %0d crossings",
                         period_x100 / 100, period_x100 % 100, sxing);
        end
        if (peak < 1000) begin
            $display("FAIL tb_top_i2s_27m: decoded peak=%0d too small", peak);
            errors = errors + 1;
        end

        // 4) A4 相位增量必须按 46.875 kHz 计算：440*2^32/46875 = 40315427
        if (dut.v_note[6:0] !== 7'd69) begin
            $display("FAIL tb_top_i2s_27m: voice 0 note=%0d expect 69", dut.v_note[6:0]);
            errors = errors + 1;
        end else begin
            ideal = 40315427;
            diff = dut.inc[0] - ideal;
            if (diff < 0) diff = -diff;
            if (diff > 120) begin
                $display("FAIL tb_top_i2s_27m: A4 inc=%0d ideal=%0d diff=%0d", dut.inc[0], ideal, diff);
                errors = errors + 1;
            end else
                $display("INFO tb_top_i2s_27m: A4 inc=%0d ideal=%0d diff=%0d", dut.inc[0], ideal, diff);
        end

        // 5) 数字静音 M0 / 恢复 M1
        send_cmd3("M", "0", " ");
        wait_frames(140);
        if (decoded_latest !== 24'd0) begin
            $display("FAIL tb_top_i2s_27m: M0 did not zero the DAC word (%h)", decoded_latest);
            errors = errors + 1;
        end
        send_cmd3("M", "1", " ");
        wait_frames(40);
        if (decoded_latest === 24'd0) begin
            $display("FAIL tb_top_i2s_27m: M1 did not restore the DAC word");
            errors = errors + 1;
        end

        // 6) HID 电脑键盘：Q -> Note On 60，松键 -> Note Off（GPIO 已停用）
        send_cmd3("X", " ", " ");
        wait_frames(6000);   // 等旧 A4 释放完成，避免 HID 音被分配到别的声部
        send_kbd_report(8'h14, 0, 0, 0, 0, 0);
        wait_frames(3000);
        if (dut.v_gate !== 8'b0000_0001 || dut.v_note[6:0] !== 7'd60) begin
            $display("FAIL tb_top_i2s_27m: HID Q gate=%b note=%0d expect 0001/60",
                     dut.v_gate, dut.v_note[6:0]);
            errors = errors + 1;
        end
        send_kbd_report(0, 0, 0, 0, 0, 0);
        wait_frames(3000);
        if (dut.v_gate !== 8'b0000_0000) begin
            $display("FAIL tb_top_i2s_27m: HID note did not release, gate=%b", dut.v_gate);
            errors = errors + 1;
        end

        // 7) 汇总
        if (bck_period_bad || bck_high_bad || lrck_period_bad || din_bad || pad_bad ||
            word_bad || x_bad || tick_width_bad || tick_gap_bad) begin
            $display("FAIL tb_top_i2s_27m counters: bck=%0d bck_high=%0d lrck=%0d din=%0d pad=%0d word=%0d x=%0d tick_w=%0d tick_gap=%0d",
                     bck_period_bad, bck_high_bad, lrck_period_bad, din_bad, pad_bad,
                     word_bad, x_bad, tick_width_bad, tick_gap_bad);
            errors = errors + 1;
        end
        if (errors != 0) $fatal(1, "tb_top_i2s_27m failures=%0d", errors);
        $display("PASS tb_top_i2s_27m: %0d frames decoded, %0d sample ticks, 27 MHz/46.875 kHz/9-clock BCK, A4 inc from 46875",
                 frames_checked, tick_cnt);
        $finish;
    end
endmodule
