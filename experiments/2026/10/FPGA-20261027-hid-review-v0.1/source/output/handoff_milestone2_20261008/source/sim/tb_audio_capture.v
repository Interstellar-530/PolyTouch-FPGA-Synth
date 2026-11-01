`timescale 1ns/1ps
// S1: capture the actual top-level PT8211 pins at the real 27 MHz clock.
// No force, accelerated sample_tick or shortcut note-event injection is used.
// Decode one 16-bit word between successive WS changes, sampling DIN on BCK
// rising edges. Internal frame_data is only an independent equality reference;
// the decoder never reads the serializer's bit counter or shift register.
module tb_audio_capture;
    reg clk = 0, key_rst = 0, key_s1 = 1, key_s2 = 1, uart_rx = 1;
    reg [11:0] gpio_key_n = 12'hFFF;    // [S2-AI] 全部松开；本台只走 UART 演奏路径
    wire hp_bck, hp_ws, hp_din, pa_en, led, led_chord, led_t0, led_t1, uart_tx;
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
    localparam real UART_BIT_NS = 1000000000.0 / 115200.0;
    // Production M0/M1 now slews the existing Q12 VCA by 32 per frame:
    // 4096/32 = 128 frames. Include serial latch/decoder margin, then retain
    // the exact-zero and held-voice checks below. Capture lengths are unchanged.
    localparam integer MUTE_SETTLE_FRAMES = 140;

    integer cycles = 0, last_tick_cycle = -1, last_bck_cycle = -1;
    integer last_frame_cycle = -1, tick_count = 0, bck_count = 0;
    integer uart_accepted = 0, half_bits = 0, frame_index = 0;
    integer csv_file, manifest_file, written_frames = 0;
    reg previous_tick = 0, previous_ws = 0, decoder_synced = 0;
    reg [15:0] word_shift = 0, left_word = 0, left_reference = 0;
    reg signed [15:0] decoded_left, decoded_right, frame_reference;
    string capture_dir;
    event frame_done;

    // Observe the native clock enable, including its width and full period.
    // sample_tick is read before this edge's nonblocking assignments, so it is
    // one clk later than the serializer's latch edge; its 576-clk spacing holds.
    always @(posedge clk) begin
        cycles = cycles + 1;
        if (dut.por) begin
            previous_tick = 0;
            last_tick_cycle = -1;
        end else begin
            if ((^{hp_bck, hp_ws, hp_din, dut.sample_tick}) === 1'bx)
                $fatal(1, "Unknown audio pin or sample_tick at clk %0d", cycles);
            if (dut.sample_tick) begin
                if (previous_tick)
                    $fatal(1, "sample_tick lasts longer than one clk");
                if (last_tick_cycle >= 0 && cycles - last_tick_cycle != 576)
                    $fatal(1, "sample_tick interval=%0d, expected 576", cycles-last_tick_cycle);
                last_tick_cycle = cycles;
                tick_count = tick_count + 1;
            end
            previous_tick = dut.sample_tick;
        end
        if (!dut.rst) begin
            if (dut.u_uart.reply_err)
                $fatal(1, "UART rejected a valid capture command");
            if (dut.u_uart.reply_ok) uart_accepted = uart_accepted + 1;
            if (dut.u_uart.reply_drop_count != 0)
                $fatal(1, "UART response queue overflow");
        end
    end

    // PT8211 实例在顶层 audio output 的 generate 分支 g_pt8211 内（另一分支是标准 I2S），
// 因此层次路径是 dut.g_pt8211.u_pt8211.*。本台只跑默认的 AUDIO_IF=0 调试档。
// PT8211 receives data on BCK rising edges. WS transitions begin the new
    // word with its MSB on that same rising edge (16-bit right-aligned words).
    // Synchronize at a complete right-to-left boundary to skip startup padding.
    always @(posedge hp_bck) begin
        #1;
        if (!dut.por) begin
            if (last_bck_cycle >= 0 && cycles - last_bck_cycle != 18)
                $fatal(1, "BCK interval=%0d, expected 18", cycles-last_bck_cycle);
            last_bck_cycle = cycles;
            bck_count = bck_count + 1;
            if ((^{hp_ws, hp_din}) === 1'bx)
                $fatal(1, "Unknown PT8211 serial bit");
            if (!decoder_synced) begin
                if (previous_ws && !hp_ws) begin
                    decoder_synced = 1;
                    half_bits = 1;
                    word_shift = {15'd0, hp_din};
                    left_reference = dut.g_pt8211.u_pt8211.frame_data;
                end
            end else if (hp_ws == previous_ws) begin
                if (half_bits >= 16)
                    $fatal(1, "WS word contains more than 16 BCK edges");
                word_shift = {word_shift[14:0], hp_din};
                half_bits = half_bits + 1;
            end else begin
                if (half_bits != 16)
                    $fatal(1, "WS word contains %0d BCK edges, expected 16", half_bits);
                if (!previous_ws) begin
                    left_word = word_shift;
                    if (left_word !== left_reference)
                        $fatal(1, "Left serial/reference mismatch at frame %0d: %h vs %h",
                               frame_index, left_word, left_reference);
                end else begin
                    decoded_left = left_word;
                    decoded_right = word_shift;
                    frame_reference = left_reference;
                    if (decoded_right !== decoded_left)
                        $fatal(1, "PT8211 left/right mismatch at frame %0d", frame_index);
                    if (decoded_right !== frame_reference)
                        $fatal(1, "Right serial/reference mismatch at frame %0d", frame_index);
                    if (last_frame_cycle >= 0 && cycles - last_frame_cycle != 576)
                        $fatal(1, "Stereo frame interval=%0d, expected 576", cycles-last_frame_cycle);
                    last_frame_cycle = cycles;
                    frame_index = frame_index + 1;
                    -> frame_done;
                    // frame_data has already latched the NEXT frame while the
                    // previous right word was finishing. Save it at left start;
                    // comparing the finished right word directly to current
                    // frame_data would introduce a false one-frame mismatch.
                    left_reference = dut.g_pt8211.u_pt8211.frame_data;
                end
                word_shift = {15'd0, hp_din};
                half_bits = 1;
            end
            previous_ws = hp_ws;
        end
    end

    // These pins may change on a BCK falling edge, never during its high phase.
    always @(hp_ws or hp_din) begin
        if (!dut.por && decoder_synced && hp_bck !== 1'b0)
            $fatal(1, "PT8211 WS/DIN changed while BCK was high");
    end

    task send_byte;
        input [7:0] value;
        integer bit_index;
        begin
            @(negedge clk); uart_rx = 0; #(UART_BIT_NS);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx = value[bit_index]; #(UART_BIT_NS);
            end
            uart_rx = 1; #(UART_BIT_NS);
        end
    endtask

    task send_command;
        input string command;
        integer char_index, accepted_before;
        begin
            accepted_before = uart_accepted;
            for (char_index = 0; char_index < command.len(); char_index = char_index + 1)
                send_byte(command[char_index]);
            send_byte(8'h0d);
            repeat (20) @(negedge clk);
            if (uart_accepted != accepted_before + 1)
                $fatal(1, "UART command %s was not accepted once", command);
            if (dut.demo_mode !== 1'b0)
                $fatal(1, "Demo/manual conflict after command %s", command);
        end
    endtask

    task wait_frames;
        input integer count;
        begin repeat (count) @(frame_done); end
    endtask

    // The mask is by pitch, not by allocator index: bit 0=60, 1=63, 2=66, 3=69.
    // Assert distinct active voices, exact notes and idle status for released
    // voices after their settle window. A4 release capture permits non-idle tails.
    task check_notes;
        input [3:0] expected_notes;
        input require_released_idle;
        reg [3:0] seen;
        integer voice_index, pitch_bit;
        reg [6:0] pitch;
        begin
            if ((^{dut.v_gate, dut.v_idle, dut.v_note}) === 1'bx)
                $fatal(1, "Unknown voice metadata");
            seen = 0;
            for (voice_index = 0; voice_index < 4; voice_index = voice_index + 1) begin
                if (dut.v_gate[voice_index]) begin
                    if (dut.v_idle[voice_index])
                        $fatal(1, "Held voice %0d is idle", voice_index);
                    pitch = dut.v_note[voice_index*7 +: 7];
                    case (pitch)
                        60: pitch_bit = 0;
                        63: pitch_bit = 1;
                        66: pitch_bit = 2;
                        69: pitch_bit = 3;
                        default: $fatal(1, "Unexpected active pitch %0d", pitch);
                    endcase
                    if (seen[pitch_bit]) $fatal(1, "Duplicate held pitch %0d", pitch);
                    seen[pitch_bit] = 1;
                end else if (require_released_idle && !dut.v_idle[voice_index]) begin
                    $fatal(1, "Released voice %0d did not become idle", voice_index);
                end
            end
            if (seen !== expected_notes)
                $fatal(1, "Held-note mask=%b, expected %b", seen, expected_notes);
        end
    endtask

    task capture_stage;
        input string stage_name;
        input integer count;
        input [3:0] expected_notes;
        input require_released_idle;
        input require_zero;
        integer sample_index, nonzero_count;
        begin
            nonzero_count = 0;
            $display("CAPTURE %s: %0d native PT8211 frames", stage_name, count);
            for (sample_index = 0; sample_index < count; sample_index = sample_index + 1) begin
                @(frame_done);
                check_notes(expected_notes, require_released_idle);
                if ((^{decoded_left, decoded_right, frame_reference}) === 1'bx)
                    $fatal(1, "Unknown decoded sample in %s", stage_name);
                if (require_zero && (decoded_left !== 16'sd0 || decoded_right !== 16'sd0))
                    $fatal(1, "Nonzero serial sample in %s: %0d/%0d",
                           stage_name, decoded_left, decoded_right);
                if (decoded_left != 0) nonzero_count = nonzero_count + 1;
                $fdisplay(csv_file, "%0d,%0d,%0d,%s,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                          frame_index, decoded_left, decoded_right, stage_name,
                          dut.v_gate, dut.v_idle, dut.v_note[6:0], dut.v_note[13:7],
                          dut.v_note[20:14], dut.v_note[27:21], frame_reference);
                written_frames = written_frames + 1;
            end
            if (!require_zero && expected_notes != 0 && nonzero_count == 0)
                $fatal(1, "Held notes produced no serial audio in %s", stage_name);
            $fdisplay(manifest_file, "stage_count_%s,%0d", stage_name, count);
            case (expected_notes)
                4'b0000: $fdisplay(manifest_file, "expected_notes_%s,none", stage_name);
                4'b1000: $fdisplay(manifest_file, "expected_notes_%s,69", stage_name);
                4'b1111: $fdisplay(manifest_file, "expected_notes_%s,60;63;66;69", stage_name);
                4'b1110: $fdisplay(manifest_file, "expected_notes_%s,63;66;69", stage_name);
                4'b1100: $fdisplay(manifest_file, "expected_notes_%s,66;69", stage_name);
                default: $fatal(1, "Missing manifest pitch mask %b", expected_notes);
            endcase
        end
    endtask

    initial begin
        if (!$value$plusargs("CAPTURE_DIR=%s", capture_dir)) capture_dir = "sim/audio_capture";
        csv_file = $fopen({capture_dir, "/audio_capture.csv"}, "w");
        manifest_file = $fopen({capture_dir, "/capture_manifest.csv"}, "w");
        if (!csv_file || !manifest_file)
            $fatal(1, "Create CAPTURE_DIR before simulation: %s", capture_dir);
        $fdisplay(csv_file, "frame,left,right,stage,gate_mask,idle_mask,note0,note1,note2,note3,final_sample_reference");
        $fdisplay(manifest_file, "key,value");
        $fdisplay(manifest_file, "sample_rate,46875");
        $fdisplay(manifest_file, "clk_hz,27000000");
        $fdisplay(manifest_file, "uart_baud,115200");
        $fdisplay(manifest_file, "clock_half_period_ns,18.5185");
        $fdisplay(manifest_file, "bits_per_word,16");
        $fdisplay(manifest_file, "bck_period_clocks,18");
        $fdisplay(manifest_file, "frame_period_clocks,576");
        $fdisplay(manifest_file, "settle_frames,2000");
        $fdisplay(manifest_file, "release_settle_frames,1600");
        $fdisplay(manifest_file, "muting_flush_frames,%0d", MUTE_SETTLE_FRAMES);
        $fdisplay(manifest_file, "A4_hz,440");
        $fdisplay(manifest_file, "channel_format,PT8211_16bit_right_aligned");
        $fdisplay(manifest_file, "decoder_uses_serializer_bit_counter,false");
        $fdisplay(manifest_file, "sample_tick_forced,false");

        #100000; key_rst = 1;
        wait (!dut.rst);
        send_command("D0");
        wait_frames(1600);
        capture_stage("initial_silence", 512, 4'b0000, 1, 1);

        send_command("N69");
        wait_frames(2000);
        capture_stage("a4_steady", 32768, 4'b1000, 1, 0);
        send_command("O69");
        capture_stage("release_a4", 4096, 4'b0000, 0, 0);
        check_notes(4'b0000, 1);
        if (decoded_left !== 16'sd0) $fatal(1, "A4 release did not end in digital silence");

        send_command("N60"); send_command("N63");
        send_command("N66"); send_command("N69");
        wait_frames(2000);
        capture_stage("chord4", 4096, 4'b1111, 1, 0);
        send_command("O60"); wait_frames(1600);
        capture_stage("after_off60", 4096, 4'b1110, 1, 0);
        send_command("O63"); wait_frames(1600);
        capture_stage("after_off63", 4096, 4'b1100, 1, 0);
        send_command("O66"); wait_frames(1600);
        capture_stage("after_off66", 4096, 4'b1000, 1, 0);
        send_command("O69"); wait_frames(1600);
        capture_stage("all_released", 512, 4'b0000, 1, 1);

        // M0/M1 must silence and restore active synthesis without releasing it.
        send_command("N60"); send_command("N63");
        send_command("N66"); send_command("N69");
        wait_frames(2000);
        send_command("M0"); wait_frames(MUTE_SETTLE_FRAMES);
        if (dut.uart_muted !== 1'b1) $fatal(1, "M0 failed to set digital mute");
        capture_stage("muted_active", 512, 4'b1111, 1, 1);
        send_command("M1"); wait_frames(MUTE_SETTLE_FRAMES);
        if (dut.uart_muted !== 1'b0) $fatal(1, "M1 failed to clear digital mute");
        capture_stage("unmuted_active", 4096, 4'b1111, 1, 0);

        if (written_frames != 58880)
            $fatal(1, "Capture count=%0d, expected 58880", written_frames);
        $fdisplay(manifest_file, "captured_frames,%0d", written_frames);
        $fdisplay(manifest_file, "decoded_frames,%0d", frame_index);
        $fdisplay(manifest_file, "checked_sample_ticks,%0d", tick_count);
        $fdisplay(manifest_file, "checked_bck_rises,%0d", bck_count);
        $fdisplay(manifest_file, "uart_commands_accepted,%0d", uart_accepted);
        $fdisplay(manifest_file, "result,PASS");
        $fclose(csv_file); $fclose(manifest_file);
        $display("PASS tb_audio_capture: %0d frames, native tick, independent PT8211 decode, UART/ADSR/mute/chord",
                 written_frames);
        $finish;
    end
    initial begin #3000000000; $fatal(1, "Real audio capture timeout"); end
endmodule
