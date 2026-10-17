`timescale 1ns/1ps
// [集成] 标准 I2S 档顶层验收（top 的 AUDIO_IF=1，12.288 MHz / 48 kHz / 24 位槽）。
//
// 判据全部从 i2s_bck/i2s_lrck/i2s_din 三根引脚重新解码后再下结论；只有相位增量
// 一项直接读 dut.inc*（那是 note_phase_inc 的输出端口，属于被测接口本身）。
//
// 覆盖：
//   1) sample_tick 单拍、间隔 256 个 clk_12m288（48 kHz）；
//   2) BCK 周期 4 拍 = 3.072 MHz、高/低各 2 拍；LRCK 周期 256 拍；每帧 64 个 BCK；
//   3) DIN 只在 BCK 下降沿变化；左右半帧各 32 槽、位置 0 与 25..31 为零填充；
//   4) 每帧解出的 24 位槽与 DUT 的 final_sample 对齐：高 16 位相等、低 8 位为零；
//   5) 未选中的板载 PT8211 三线恒低、dac_xsmt 恒高、三线无 X；
//   6) 单音 A4 的解码波形向上过零平均周期 = 48000/440 = 109.09 拍（±1%）；
//   7) 四个音的相位增量与 440*2^((n-69)/12)*2^32/48000 相差 < 3 ppm；
//   8) UART X 退出演示后音频非零；M0 数字静音后字全零；M1 恢复。
module tb_top_i2s;
    reg clk27 = 1'b0, clk12 = 1'b0;
    reg key_rst = 1'b0, key_s1 = 1'b1, key_s2 = 1'b1, uart_rx = 1'b1;
    reg [11:0] gpio_key_n = 12'hFFF;
    wire hp_bck, hp_ws, hp_din, pa_en, led, led_chord, led_t0, led_t1, uart_tx;
    wire adc_cs_n, adc_sck, adc_mosi, adc_miso;
    wire [3:0] clip_fold;
    wire i2s_bck, i2s_lrck, i2s_din, dac_xsmt;
    reg [11:0] adc_ch0 = 12'd2048, adc_ch1 = 12'd2048;

    always #18.5185 clk27 = ~clk27;   // 本档不使用，但端口必须被驱动
    always #40.69   clk12 = ~clk12;   // 12.288 MHz（半周期 40.69 ns）

    mcp3208_model u_adc_model (
        .cs_n(adc_cs_n), .sclk(adc_sck), .mosi(adc_mosi), .miso(adc_miso),
        .ch0(adc_ch0), .ch1(adc_ch1), .ch2(12'd0), .ch3(12'd0),
        .ch4(12'd0), .ch5(12'd0), .ch6(12'd0), .ch7(12'd0)
    );

    top #(.AUDIO_IF(1), .I2S_DATA_BITS(24)) dut (
        .clk_27m(clk27), .clk_12m288(clk12),
        .key_rst(key_rst), .key_s1(key_s1), .key_s2(key_s2),
        .uart_rx(uart_rx), .gpio_key_n(gpio_key_n),
        .adc_cs_n(adc_cs_n), .adc_sck(adc_sck), .adc_mosi(adc_mosi), .adc_miso(adc_miso),
        .hp_bck(hp_bck), .hp_ws(hp_ws), .hp_din(hp_din), .pa_en(pa_en),
        .led(led), .led_chord(led_chord), .led_t0(led_t0), .led_t1(led_t1),
        .uart_tx(uart_tx), .clip_fold(clip_fold),
        .i2s_bck(i2s_bck), .i2s_lrck(i2s_lrck), .i2s_din(i2s_din), .dac_xsmt(dac_xsmt)
    );

    integer errors = 0;
    integer cyc = 0;                       // clk12 拍计数
    integer last_tick = -1, tick_cnt = 0, tick_width_bad = 0, tick_gap_bad = 0;
    reg     tick_seen = 1'b0;
    integer last_bck_rise = -1, bck_high_bad = 0, bck_low_bad = 0, bck_cnt = 0;
    integer last_lrck_fall = -1, lrck_period_bad = 0, frame_cnt = 0;
    integer din_bad = 0, pad_bad = 0, word_bad = 0, x_bad = 0;
    integer slot = 0;                      // 帧内第几个 BCK 上升沿，1..64
    reg [23:0] word = 24'd0;
    reg [23:0] exp_word = 24'd0;
    reg [23:0] decoded_latest = 24'd0;
    integer frames_checked = 0;

    reg signed [15:0] final_pipe = 16'sd0; // dut.final_sample 的一拍流水
    reg bck_q = 1'b0, din_q = 1'b1;
    reg mon_en = 1'b0;      // 上电复位释放后才开始判定，复位期间的 X/过渡不计分

    // 过零与峰值统计（只用左声道解码值）
    integer xing = 0, first_xing = -1, last_xing = -1, samp_idx = 0, peak = 0;
    reg signed [15:0] prev_samp = 16'sd0;

    // 时钟域监视：采样节拍间隔、DIN 稳定性、LRCK/BCK 周期
    always @(posedge clk12) begin
        cyc = cyc + 1;
        final_pipe <= dut.final_sample;

        if (!mon_en) begin
            bck_q = i2s_bck;
            din_q = i2s_din;
        end else begin
        if (^{i2s_bck, i2s_lrck, i2s_din, dac_xsmt} === 1'bx)
            x_bad = x_bad + 1;

        // DIN 只允许在 BCK 下降沿变化
        if (i2s_din !== din_q) begin
            if (!(bck_q === 1'b1 && i2s_bck === 1'b0)) begin
                if (din_bad < 5)
                    $display("FAIL tb_top_i2s: DIN changed off a BCK falling edge at cyc=%0d", cyc);
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
            if (last_tick >= 0 && (cyc - last_tick) != 256) begin
                if (tick_gap_bad < 3)
                    $display("FAIL tb_top_i2s: sample_tick interval=%0d expect 256", cyc - last_tick);
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

    // BCK 上升沿：数周期、推进帧内槽（mon_en 之前只等待，不判定）
    always @(posedge i2s_bck) begin
        #1;
        if (mon_en) begin
        if (last_bck_rise >= 0 && (cyc - last_bck_rise) != 4) begin
            if (bck_low_bad < 3)
                $display("FAIL tb_top_i2s: BCK period=%0d expect 4", cyc - last_bck_rise);
            bck_low_bad = bck_low_bad + 1;
            errors = errors + 1;
        end
        last_bck_rise = cyc;
        bck_cnt = bck_cnt + 1;

        slot = slot + 1;
        // 位置 0（slot 1、33）与位置 25..31（slot 26..32、58..64）必须是零填充
        if (slot == 1 || slot == 33 || (slot >= 26 && slot <= 32) || (slot >= 58 && slot <= 64)) begin
            if (i2s_din !== 1'b0) begin
                if (pad_bad < 5)
                    $display("FAIL tb_top_i2s: non-zero padding bit in slot %0d (frame %0d)", slot, frame_cnt);
                pad_bad = pad_bad + 1;
                errors = errors + 1;
            end
        end
        // 位置 1..24 是 MSB 在前的数据位
        if ((slot >= 2 && slot <= 25) || (slot >= 34 && slot <= 57))
            word = {word[22:0], i2s_din};

        if (slot == 32) begin
            if (word !== exp_word) begin
                if (word_bad < 5)
                    $display("FAIL tb_top_i2s: left word=%h expect=%h (frame %0d)", word, exp_word, frame_cnt);
                word_bad = word_bad + 1;
                errors = errors + 1;
            end
            decoded_latest = word;
            frames_checked = frames_checked + 1;
            // 过零与峰值
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
                    $display("FAIL tb_top_i2s: right word=%h expect=%h (frame %0d)", word, exp_word, frame_cnt);
                word_bad = word_bad + 1;
                errors = errors + 1;
            end
            word = 24'd0;
            slot = 0;
        end
        end
    end

    // LRCK 帧边界：周期 256 拍，锁存本帧的期望字
    always @(negedge i2s_lrck) begin
        #1;
        if (mon_en) begin
        if (last_lrck_fall >= 0 && (cyc - last_lrck_fall) != 256) begin
            if (lrck_period_bad < 3)
                $display("FAIL tb_top_i2s: LRCK frame=%0d expect 256", cyc - last_lrck_fall);
            lrck_period_bad = lrck_period_bad + 1;
            errors = errors + 1;
        end
        last_lrck_fall = cyc;
        frame_cnt = frame_cnt + 1;
        exp_word = {final_pipe[15:0], 8'b0};
        word = 24'd0;
        slot = 0;
        end
    end

    // BCK 下降沿：占空比 2/2（mon_en 之前不判定）
    always @(negedge i2s_bck) begin
        #1;
        if (mon_en) begin
        if (last_bck_rise >= 0 && (cyc - last_bck_rise) != 2) begin
            if (bck_high_bad < 3)
                $display("FAIL tb_top_i2s: BCK high=%0d expect 2", cyc - last_bck_rise);
            bck_high_bad = bck_high_bad + 1;
            errors = errors + 1;
        end
        end
    end

    // ------------------------------------------------------------- UART 发送 ---
    task send_byte;
        input [7:0] data;
        integer bitno;
        begin
            @(negedge clk12); uart_rx = 1'b0; #8681;
            for (bitno = 0; bitno < 8; bitno = bitno + 1) begin
                uart_rx = data[bitno]; #8681;
            end
            uart_rx = 1'b1; #8681;
        end
    endtask

    // 逐字节发送 "A B C" 三个字符（第三位用空格表示无参数）
    task send_cmd3;
        input [7:0] c1; input [7:0] c2; input [7:0] c3;
        begin
            send_byte(c1); send_byte(c2); send_byte(c3); send_byte(8'h0D);
        end
    endtask

    task wait_frames;
        input integer n;
        integer target;
        begin
            target = frame_cnt + n;
            while (frame_cnt < target) @(posedge clk12);
        end
    endtask

    // ---------------------------------------------------------------- 主流程 ---
    integer i, diff, ideal;
    integer period_x100;
    reg [127:0] inc_bus;
    integer win_start;

    initial begin
        repeat (8) @(posedge clk12);
        key_rst = 1'b1;
        while (dut.por) @(posedge clk12);      // 上电复位计数约 5.3 ms @12.288 MHz
        // 在一个真实的帧边界之后使能监视：槽计数从帧首开始，复位与启动过渡不计分。
        @(negedge i2s_lrck); #1;
        mon_en = 1'b1;
        wait_frames(8);                        // 跳过启动序列的强制零帧（E0/E1）

        // 1) 未使用的板载 PT8211 三线与 XSMT
        if (hp_bck !== 1'b0 || hp_ws !== 1'b0 || hp_din !== 1'b0) begin
            $display("FAIL tb_top_i2s: unused PT8211 lines not low (bck=%b ws=%b din=%b)",
                     hp_bck, hp_ws, hp_din);
            errors = errors + 1;
        end
        if (dac_xsmt !== 1'b1) begin
            $display("FAIL tb_top_i2s: dac_xsmt=%b expect 1", dac_xsmt);
            errors = errors + 1;
        end

        // 2) X 退出演示、松掉所有演示声部；随后只弹 A4 做单音测量
        send_cmd3("X", " ", " ");
        wait_frames(20);
        send_cmd3("N", "6", "9");
        wait_frames(800);                      // 约 16.7 ms，包络起音完成（10 ms）

        if (dut.v_gate !== 4'b0001) begin
            $display("FAIL tb_top_i2s: expected only voice 0 gated, v_gate=%b", dut.v_gate);
            errors = errors + 1;
        end

        // 3) 单音 A4 的过零平均周期（0.15 s 窗口 = 7200 帧）
        xing = 0; first_xing = -1; last_xing = -1; samp_idx = 0; peak = 0; prev_samp = 16'sd0;
        win_start = frame_cnt;
        while (frame_cnt - win_start < 7200) @(posedge clk12);
        if (xing < 40) begin
            $display("FAIL tb_top_i2s: only %0d upward zero crossings in 0.15 s", xing);
            errors = errors + 1;
        end else begin
            period_x100 = ((last_xing - first_xing) * 100) / (xing - 1);
            if (period_x100 < 10800 || period_x100 > 11020) begin
                $display("FAIL tb_top_i2s: zero-crossing period=%0d.%02d samples expect 109.09",
                         period_x100 / 100, period_x100 % 100);
                errors = errors + 1;
            end else
                $display("INFO tb_top_i2s: A4 period=%0d.%02d samples over %0d crossings",
                         period_x100 / 100, period_x100 % 100, xing);
        end
        if (peak < 1000) begin
            $display("FAIL tb_top_i2s: decoded peak=%0d too small", peak);
            errors = errors + 1;
        end

        // 4) 补齐四个音，核对相位增量与 48 kHz 理想值的偏差
        send_cmd3("N", "6", "6");
        send_cmd3("N", "6", "3");
        send_cmd3("N", "6", "0");
        wait_frames(400);
        inc_bus = {dut.inc3, dut.inc2, dut.inc1, dut.inc0};
        for (i = 0; i < 4; i = i + 1) begin
            if (dut.v_gate[i]) begin
                case (dut.v_note[7*i +: 7])
                    7'd60:   ideal = 23409859;
                    7'd63:   ideal = 27839171;
                    7'd66:   ideal = 33106541;
                    7'd69:   ideal = 39370534;
                    default: ideal = -1;
                endcase
                if (ideal < 0) begin
                    $display("FAIL tb_top_i2s: unexpected note %0d on voice %0d",
                             dut.v_note[7*i +: 7], i);
                    errors = errors + 1;
                end else begin
                    diff = inc_bus[32*i +: 32] - ideal;
                    if (diff < 0) diff = -diff;
                    if (diff > 64) begin
                        $display("FAIL tb_top_i2s: voice %0d note %0d inc=%0d ideal=%0d diff=%0d",
                                 i, dut.v_note[7*i +: 7], inc_bus[32*i +: 32], ideal, diff);
                        errors = errors + 1;
                    end else
                        $display("INFO tb_top_i2s: voice %0d note %0d inc=%0d ideal=%0d diff=%0d",
                                 i, dut.v_note[7*i +: 7], inc_bus[32*i +: 32], ideal, diff);
                end
            end
        end
        if (dut.v_gate !== 4'b1111) begin
            $display("FAIL tb_top_i2s: four note-ons should gate four voices, v_gate=%b", dut.v_gate);
            errors = errors + 1;
        end

        // 5) 数字静音 M0 / 恢复 M1
        send_cmd3("M", "0", " ");
        // Unity-to-zero slew is 4096/32 = 128 frames, plus serial buffering.
        wait_frames(140);
        if (decoded_latest !== 24'd0) begin
            $display("FAIL tb_top_i2s: M0 did not zero the DAC word (%h)", decoded_latest);
            errors = errors + 1;
        end
        send_cmd3("M", "1", " ");
        wait_frames(40);
        if (decoded_latest === 24'd0) begin
            $display("FAIL tb_top_i2s: M1 did not restore the DAC word");
            errors = errors + 1;
        end

        // 6) 汇总
        if (bck_low_bad || bck_high_bad || lrck_period_bad || din_bad || pad_bad ||
            word_bad || x_bad || tick_width_bad || tick_gap_bad) begin
            $display("FAIL tb_top_i2s counters: bck_period=%0d bck_high=%0d lrck=%0d din=%0d pad=%0d word=%0d x=%0d tick_w=%0d tick_gap=%0d",
                     bck_low_bad, bck_high_bad, lrck_period_bad, din_bad, pad_bad,
                     word_bad, x_bad, tick_width_bad, tick_gap_bad);
            errors = errors + 1;
        end
        if (errors != 0) $fatal(1, "tb_top_i2s failures=%0d", errors);
        $display("PASS tb_top_i2s: %0d frames decoded, %0d sample ticks, 24-bit slots match final_sample, A4 within 1 percent",
                 frames_checked, tick_cnt);
        $finish;
    end
endmodule
