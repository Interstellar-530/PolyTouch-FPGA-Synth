`timescale 1ns/1ps
// [S3-AI | deepseek | 2026-10-14] S3 第十三台门禁：标准 I2S 发送器与统一时钟参数。
//
// 被测对象是 rtl/audio/i2s_tx.v，验收来自引脚级独立解码（sim/i2s_rx_model.v）与
// 四个组合自检盒（sim/i2s_tx_checker.v）：
//   标准档 12.288 MHz / 48 kHz 的 16 位与 24 位，调试档 27 MHz / 46.875 kHz 的 16 位与 24 位。
// 每个组合至少 264 个完整数据帧，另含启动帧、三次硬复位恢复和数字静音。
//
// 时钟用取整到 1 ps 的周期驱动：81.380 ns（12.288 MHz 取整，相对误差约 2.6 ppm）与
// 37.038 ns（27 MHz 取整，约 0.03 ppm）。断言全部按系统拍计数，不把小数周期当作 48 kHz 的证明。
//
// 本台还先用人工构造的 I2S 位串检查接收模型本身，再用模型检查发送器。
`include "rtl/audio/clk_params.vh"

module tb_i2s_tx;

    localparam integer STD_CLK = `FPGA_AUDIO_STD_CLK_HZ;
    localparam integer STD_FS  = `FPGA_AUDIO_STD_FS_HZ;
    localparam integer DBG_CLK = `FPGA_AUDIO_DBG_CLK_HZ;
    localparam integer DBG_FS  = `FPGA_AUDIO_DBG_FS_HZ;

    // ---------------------------------------------------------------- 时钟 ---
    reg clk_a = 1'b0;
    reg clk_b = 1'b0;
    always #40.690 clk_a = ~clk_a;   // 81.380 ns
    always #18.519 clk_b = ~clk_b;   // 37.038 ns

    reg run = 1'b0;

    // ------------------------------------------------------------ 四个组合 ---
    wire c1_done, c2_done, c3_done, c4_done;
    wire [31:0] c1_frames, c2_frames, c3_frames, c4_frames;
    wire [31:0] c1_vec, c2_vec, c3_vec, c4_vec;
    wire [31:0] c1_prng, c2_prng, c3_prng, c4_prng;
    wire [31:0] c1_tear, c2_tear, c3_tear, c4_tear;
    wire [31:0] c1_mute, c2_mute, c3_mute, c4_mute;
    wire [31:0] c1_rst, c2_rst, c3_rst, c4_rst;
    wire [31:0] c1_tick, c2_tick, c3_tick, c4_tick;
    wire [31:0] c1_fmin, c2_fmin, c3_fmin, c4_fmin;
    wire [31:0] c1_fmax, c2_fmax, c3_fmax, c4_fmax;
    wire [31:0] c1_hmin, c2_hmin, c3_hmin, c4_hmin;
    wire [31:0] c1_hmax, c2_hmax, c3_hmax, c4_hmax;
    wire [31:0] c1_lmin, c2_lmin, c3_lmin, c4_lmin;
    wire [31:0] c1_lmax, c2_lmax, c3_lmax, c4_lmax;
    wire [31:0] c1_lj, c2_lj, c3_lj, c4_lj;
    wire [31:0] c1_rj, c2_rj, c3_rj, c4_rj;
    wire [31:0] c1_sw, c2_sw, c3_sw, c4_sw;
    wire [31:0] c1_fl, c2_fl, c3_fl, c4_fl;
    wire [31:0] c1_al, c2_al, c3_al, c4_al;

    i2s_tx_checker #(.CLK_HZ(STD_CLK), .SAMPLE_RATE_HZ(STD_FS), .DATA_BITS(16)) c_std16 (
        .clk(clk_a), .run(run), .done(c1_done),
        .m_frames(c1_frames), .m_vector_frames(c1_vec), .m_prng_frames(c1_prng),
        .m_tear_frames(c1_tear), .m_mute_frames(c1_mute), .m_resets(c1_rst), .m_ticks(c1_tick),
        .m_frame_gap_min(c1_fmin), .m_frame_gap_max(c1_fmax),
        .m_bck_high_min(c1_hmin), .m_bck_high_max(c1_hmax),
        .m_bck_low_min(c1_lmin), .m_bck_low_max(c1_lmax),
        .m_neg_lj(c1_lj), .m_neg_rj(c1_rj), .m_neg_swap(c1_sw), .m_neg_flip(c1_fl),
        .m_align_discards(c1_al));

    i2s_tx_checker #(.CLK_HZ(STD_CLK), .SAMPLE_RATE_HZ(STD_FS), .DATA_BITS(24)) c_std24 (
        .clk(clk_a), .run(run), .done(c2_done),
        .m_frames(c2_frames), .m_vector_frames(c2_vec), .m_prng_frames(c2_prng),
        .m_tear_frames(c2_tear), .m_mute_frames(c2_mute), .m_resets(c2_rst), .m_ticks(c2_tick),
        .m_frame_gap_min(c2_fmin), .m_frame_gap_max(c2_fmax),
        .m_bck_high_min(c2_hmin), .m_bck_high_max(c2_hmax),
        .m_bck_low_min(c2_lmin), .m_bck_low_max(c2_lmax),
        .m_neg_lj(c2_lj), .m_neg_rj(c2_rj), .m_neg_swap(c2_sw), .m_neg_flip(c2_fl),
        .m_align_discards(c2_al));

    i2s_tx_checker #(.CLK_HZ(DBG_CLK), .SAMPLE_RATE_HZ(DBG_FS), .DATA_BITS(16)) c_dbg16 (
        .clk(clk_b), .run(run), .done(c3_done),
        .m_frames(c3_frames), .m_vector_frames(c3_vec), .m_prng_frames(c3_prng),
        .m_tear_frames(c3_tear), .m_mute_frames(c3_mute), .m_resets(c3_rst), .m_ticks(c3_tick),
        .m_frame_gap_min(c3_fmin), .m_frame_gap_max(c3_fmax),
        .m_bck_high_min(c3_hmin), .m_bck_high_max(c3_hmax),
        .m_bck_low_min(c3_lmin), .m_bck_low_max(c3_lmax),
        .m_neg_lj(c3_lj), .m_neg_rj(c3_rj), .m_neg_swap(c3_sw), .m_neg_flip(c3_fl),
        .m_align_discards(c3_al));

    i2s_tx_checker #(.CLK_HZ(DBG_CLK), .SAMPLE_RATE_HZ(DBG_FS), .DATA_BITS(24)) c_dbg24 (
        .clk(clk_b), .run(run), .done(c4_done),
        .m_frames(c4_frames), .m_vector_frames(c4_vec), .m_prng_frames(c4_prng),
        .m_tear_frames(c4_tear), .m_mute_frames(c4_mute), .m_resets(c4_rst), .m_ticks(c4_tick),
        .m_frame_gap_min(c4_fmin), .m_frame_gap_max(c4_fmax),
        .m_bck_high_min(c4_hmin), .m_bck_high_max(c4_hmax),
        .m_bck_low_min(c4_lmin), .m_bck_low_max(c4_lmax),
        .m_neg_lj(c4_lj), .m_neg_rj(c4_rj), .m_neg_swap(c4_sw), .m_neg_flip(c4_fl),
        .m_align_discards(c4_al));

    // --------------------------------------------- 接收模型自检：人工位串 ---
    reg mbck = 1'b0, mlrck = 1'b0, mdin = 1'b0, mrst = 1'b1;
    wire signed [15:0] m_left, m_right;
    wire m_valid;
    wire [31:0] m_slot_l, m_slot_r, m_disc;
    integer mp, mf, selftest_frames, selftest_fails;
    reg [15:0] mwl, mwr, mgot;

    i2s_rx_model #(.DATA_BITS(16), .HALF_SLOTS(32)) m_rx (
        .bck(mbck), .rst(mrst), .lrck(mlrck), .din(mdin),
        .left_word(m_left), .right_word(m_right), .frame_valid(m_valid),
        .slot_l(m_slot_l), .slot_r(m_slot_r), .align_discards(m_disc)
    );

    // 标准 I2S 半帧：位置 0 发 0，位置 1..16 发 MSB 在前。
    task send_half_i2s;
        input [15:0] word;
        input        right;      // 0 = 左半帧（LRCK 低），1 = 右半帧（LRCK 高）
        begin
            mlrck = right;
            for (mp = 0; mp < 32; mp = mp + 1) begin
                mdin = (mp == 0) ? 1'b0 : ((mp <= 16) ? word[16-mp] : 1'b0);
                #10 mbck = 1'b1;
                #10 mbck = 1'b0;
            end
        end
    endtask

    // 左对齐（错误偏移）：位置 0 直接发 MSB。
    task send_half_lj;
        input [15:0] word;
        input        right;
        begin
            mlrck = right;
            for (mp = 0; mp < 32; mp = mp + 1) begin
                mdin = (mp < 16) ? word[15-mp] : 1'b0;
                #10 mbck = 1'b1;
                #10 mbck = 1'b0;
            end
        end
    endtask

    // 记录模型每次发布的左右字，供自检比较（不能从解码结果反推期望值）。
    integer pub_count;
    reg [15:0] pub_l [0:7];
    reg [15:0] pub_r [0:7];

    always @(posedge m_valid) begin
        if (pub_count < 8) begin
            pub_l[pub_count] = m_left;
            pub_r[pub_count] = m_right;
        end
        pub_count = pub_count + 1;
    end

    initial begin : model_selftest
        selftest_frames = 0;
        selftest_fails  = 0;
        pub_count = 0;
        mrst = 1'b1; mbck = 1'b0; mlrck = 1'b0; mdin = 1'b0;
        #200;
        mrst = 1'b0;

        // 四帧标准 I2S：位置 0 为 0，位置 1..16 为 MSB 在前。
        for (mf = 0; mf < 4; mf = mf + 1) begin
            case (mf)
                0: begin mwl = 16'h0000; mwr = 16'h0000; end
                1: begin mwl = 16'h8000; mwr = 16'h0001; end
                2: begin mwl = 16'h7FFF; mwr = 16'hFFFF; end
                default: begin mwl = 16'h1234; mwr = 16'hD00D; end
            endcase
            send_half_i2s(mwl, 1'b0);
            send_half_i2s(mwr, 1'b1);
        end
        send_half_i2s(16'h0000, 1'b0);      // 触发最后一帧发布
        #80;

        if (pub_count != 4) begin
            selftest_fails = selftest_fails + 1;
            $display("  自检失败：模型发布 %0d 组，期望 4 组", pub_count);
        end else begin
            for (mf = 0; mf < 4; mf = mf + 1) begin
                case (mf)
                    0: begin mwl = 16'h0000; mwr = 16'h0000; end
                    1: begin mwl = 16'h8000; mwr = 16'h0001; end
                    2: begin mwl = 16'h7FFF; mwr = 16'hFFFF; end
                    default: begin mwl = 16'h1234; mwr = 16'hD00D; end
                endcase
                if ((pub_l[mf] !== mwl) || (pub_r[mf] !== mwr)) begin
                    selftest_fails = selftest_fails + 1;
                    $display("  自检失败：帧 %0d 解出 L=%h/%h R=%h/%h",
                             mf, pub_l[mf], mwl, pub_r[mf], mwr);
                end
                selftest_frames = selftest_frames + 1;
            end
        end

        if (selftest_fails != 0)
            $fatal(1, "接收模型自检失败 %0d 项", selftest_fails);
        $display("自检：接收模型对人工构造的 I2S 位串解码正确（%0d 帧，含零、最小负数与左右不同值）",
                 selftest_frames);
    end

    // ------------------------------------------------------------ 指标输出 ---
    reg [8*260-1:0] metrics_path;
    integer mfd;
    initial begin
        mfd = 0;
        if ($value$plusargs("METRICS_FILE=%s", metrics_path))
            mfd = $fopen(metrics_path, "w");
    end

    task write_combo;
        input [8*8-1:0]  name;
        input integer    clk_hz;
        input integer    fs_hz;
        input integer    data_bits;
        input [31:0]     frames, vec, prng, tear, mute, resets, ticks;
        input [31:0]     fmin, fmax, hmin, hmax, lmin, lmax;
        input [31:0]     nlj, nrj, nsw, nfl, al;
        input integer    last;      // 1 = 数组最后一项，不加尾逗号
        begin
            $fwrite(mfd, "    {\"name\":\"%0s\",\"clk_hz\":%0d,\"sample_rate_hz\":%0d,\"data_bits\":%0d,\n",
                    name, clk_hz, fs_hz, data_bits);
            $fwrite(mfd, "     \"frames_checked\":%0d,\"vector_frames\":%0d,\"prng_frames\":%0d,\n",
                    frames, vec, prng);
            $fwrite(mfd, "     \"tear_frames\":%0d,\"mute_frames\":%0d,\"reset_recoveries\":%0d,\"ticks\":%0d,\n",
                    tear, mute, resets, ticks);
            $fwrite(mfd, "     \"frame_gap_clk_min\":%0d,\"frame_gap_clk_max\":%0d,\n", fmin, fmax);
            $fwrite(mfd, "     \"bck_high_clk_min\":%0d,\"bck_high_clk_max\":%0d,\"bck_low_clk_min\":%0d,\"bck_low_clk_max\":%0d,\n",
                    hmin, hmax, lmin, lmax);
            $fwrite(mfd, "     \"neg_offset_mismatch_frames\":%0d,\"neg_right_justified_mismatch_frames\":%0d,\n", nlj, nrj);
            $fwrite(mfd, "     \"neg_channel_swap_mismatch_frames\":%0d,\"neg_bit_flip_mismatch_frames\":%0d,\n", nsw, nfl);
            if (last)
                $fwrite(mfd, "     \"align_discard_halves\":%0d}\n", al);
            else
                $fwrite(mfd, "     \"align_discard_halves\":%0d},\n", al);
        end
    endtask

    task check_combo;
        input [8*8-1:0] name;
        input [31:0]    frames, vec, prng, tear, mute, resets;
        input [31:0]    nlj, nrj, nsw, nfl;
        begin
            if (frames < 270)
                $fatal(1, "%0s: 只检查了 %0d 帧，少于 270", name, frames);
            if (vec != 16 || prng != 208 || tear != 24)
                $fatal(1, "%0s: 阶段帧数异常 vec=%0d prng=%0d tear=%0d", name, vec, prng, tear);
            if (mute < 8)
                $fatal(1, "%0s: 数字静音帧只有 %0d，少于 8", name, mute);
            if (resets != 3)
                $fatal(1, "%0s: 复位恢复只完成 %0d 次，期望 3", name, resets);
            if (nlj < 16 || nrj < 16 || nsw < 16 || nfl < 16)
                $fatal(1, "%0s: 负面控制分歧帧不足 lj=%0d rj=%0d swap=%0d flip=%0d",
                       name, nlj, nrj, nsw, nfl);
        end
    endtask

    // ------------------------------------------------------------ 主流程 ---
    initial begin
        repeat (8) @(posedge clk_a);
        run <= 1'b1;
        wait (c1_done && c2_done && c3_done && c4_done);
        repeat (64) @(posedge clk_a);

        check_combo("std16", c1_frames, c1_vec, c1_prng, c1_tear, c1_mute, c1_rst,
                    c1_lj, c1_rj, c1_sw, c1_fl);
        check_combo("std24", c2_frames, c2_vec, c2_prng, c2_tear, c2_mute, c2_rst,
                    c2_lj, c2_rj, c2_sw, c2_fl);
        check_combo("dbg16", c3_frames, c3_vec, c3_prng, c3_tear, c3_mute, c3_rst,
                    c3_lj, c3_rj, c3_sw, c3_fl);
        check_combo("dbg24", c4_frames, c4_vec, c4_prng, c4_tear, c4_mute, c4_rst,
                    c4_lj, c4_rj, c4_sw, c4_fl);

        if ((c1_fmin != 256) || (c1_fmax != 256) || (c3_fmin != 576) || (c3_fmax != 576))
            $fatal(1, "帧边界间隔不严格等于帧长：std=%0d..%0d dbg=%0d..%0d",
                   c1_fmin, c1_fmax, c3_fmin, c3_fmax);
        if ((c1_hmin != 2) || (c1_hmax != 2) || (c1_lmin != 2) || (c1_lmax != 2))
            $fatal(1, "标准档 BCK 高/低电平不是 2 拍：高 %0d..%0d 低 %0d..%0d",
                   c1_hmin, c1_hmax, c1_lmin, c1_lmax);
        if ((c3_hmin != 4) || (c3_hmax != 4) || (c3_lmin != 5) || (c3_lmax != 5))
            $fatal(1, "调试档 BCK 高/低电平不是 4/5 拍：高 %0d..%0d 低 %0d..%0d",
                   c3_hmin, c3_hmax, c3_lmin, c3_lmax);

        $display("PASS tb_i2s_tx: 四组合 I2S 时序、一位延迟、逐位解码、抗撕裂、复位恢复、负面控制");
        $display("  std16: 帧=%0d 帧长=%0d 拍 BCK 高/低=%0d/%0d tick=%0d 复位=%0d",
                 c1_frames, c1_fmax, c1_hmax, c1_lmax, c1_tick, c1_rst);
        $display("  std24: 帧=%0d 帧长=%0d 拍 BCK 高/低=%0d/%0d tick=%0d 复位=%0d",
                 c2_frames, c2_fmax, c2_hmax, c2_lmax, c2_tick, c2_rst);
        $display("  dbg16: 帧=%0d 帧长=%0d 拍 BCK 高/低=%0d/%0d tick=%0d 复位=%0d",
                 c3_frames, c3_fmax, c3_hmax, c3_lmax, c3_tick, c3_rst);
        $display("  dbg24: 帧=%0d 帧长=%0d 拍 BCK 高/低=%0d/%0d tick=%0d 复位=%0d",
                 c4_frames, c4_fmax, c4_hmax, c4_lmax, c4_tick, c4_rst);
        $display("  负面控制分歧帧 std16 offset=%0d 右对齐=%0d 声道互换=%0d 位翻转=%0d",
                 c1_lj, c1_rj, c1_sw, c1_fl);

        if (mfd != 0) begin
            $fwrite(mfd, "{\n");
            $fwrite(mfd, "  \"result\": \"PASS\",\n");
            $fwrite(mfd, "  \"simulation\": {\n");
            $fwrite(mfd, "    \"status\": \"PASS\",\n");
            $fwrite(mfd, "    \"clock_note\": \"clk_a=81.380ns (12.288MHz, +2.6ppm), clk_b=37.038ns (27MHz, +0.03ppm); 断言按系统拍计数\",\n");
            $fwrite(mfd, "    \"model_selftest_frames\": %0d,\n", selftest_frames);
            $fwrite(mfd, "    \"prng_seed\": \"32'h53A32026\",\n");
            $fwrite(mfd, "    \"vectors_16bit\": \"0000 0001 7FFF 8000 FFFF 5555 AAAA 8001 + 独立右路序列\",\n");
            $fwrite(mfd, "    \"vectors_24bit\": \"000000 000001 7FFFFF 800000 FFFFFF 555555 AAAAAA 800001 + 独立右路序列\",\n");
            $fwrite(mfd, "    \"combos\": [\n");
            write_combo("std16", STD_CLK, STD_FS, 16, c1_frames, c1_vec, c1_prng, c1_tear, c1_mute,
                        c1_rst, c1_tick, c1_fmin, c1_fmax, c1_hmin, c1_hmax, c1_lmin, c1_lmax,
                        c1_lj, c1_rj, c1_sw, c1_fl, c1_al, 0);
            write_combo("std24", STD_CLK, STD_FS, 24, c2_frames, c2_vec, c2_prng, c2_tear, c2_mute,
                        c2_rst, c2_tick, c2_fmin, c2_fmax, c2_hmin, c2_hmax, c2_lmin, c2_lmax,
                        c2_lj, c2_rj, c2_sw, c2_fl, c2_al, 0);
            write_combo("dbg16", DBG_CLK, DBG_FS, 16, c3_frames, c3_vec, c3_prng, c3_tear, c3_mute,
                        c3_rst, c3_tick, c3_fmin, c3_fmax, c3_hmin, c3_hmax, c3_lmin, c3_lmax,
                        c3_lj, c3_rj, c3_sw, c3_fl, c3_al, 0);
            write_combo("dbg24", DBG_CLK, DBG_FS, 24, c4_frames, c4_vec, c4_prng, c4_tear, c4_mute,
                        c4_rst, c4_tick, c4_fmin, c4_fmax, c4_hmin, c4_hmax, c4_lmin, c4_lmax,
                        c4_lj, c4_rj, c4_sw, c4_fl, c4_al, 1);
            $fwrite(mfd, "    ]\n");
            $fwrite(mfd, "  },\n");
            $fwrite(mfd, "  \"synthesis\": {\"status\": \"not_run_by_simulation\", \"entry\": \"build/build_i2s_tx.ps1\"},\n");
            $fwrite(mfd, "  \"hardware\": {\"status\": \"not_tested\"}\n");
            $fwrite(mfd, "}\n");
            $fclose(mfd);
        end

        $finish;
    end

    // 超时保护：正常约 6 ms 仿真时间结束。
    initial begin
        #50ms;
        $fatal(1, "tb_i2s_tx 超时：frames std=%0d/%0d dbg=%0d/%0d",
               c1_frames, c2_frames, c3_frames, c4_frames);
    end

endmodule
