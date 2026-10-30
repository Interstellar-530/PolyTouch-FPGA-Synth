// Production 32-voice front end, extracted from the validated top.v controls.
// Audio is rendered by the existing RAM-backed scheduler/core at 54 MHz.
`include "rtl/audio/clk_params.vh"

// 音频接口由编译期参数 AUDIO_IF 选择，不做运行时切钟，避免时钟毛刺与 CDC：
//   AUDIO_IF = 0：板载 PT8211，27 MHz / 46.875 kHz，18 拍 BCK 帧；点流与引脚维持原样。
//   AUDIO_IF = 1：外置 PCM5102A 标准 I2S（Philips），12.288 MHz / 48 kHz、BCK 3.072 MHz、
//   AUDIO_IF = 2：外置 PCM5102A 标准 I2S，板载 27 MHz / 46.875 kHz、BCK 3.000 MHz、
//                 每帧 64 个 BCK（27e6/9/64 = 46875 整除）。这是 12.288 MHz 成品时钟
//                 缺件时的替代档：采样率是 46.875 kHz，不是 48 kHz，音高由 FS_HZ 保证。
// 三档互斥；0/2 用 27 MHz，只有 1 用外部 12.288 MHz。
// 与时钟配套的时间常数都按 AUDIO_CLK_HZ / AUDIO_FS_HZ 推导（UART 波特率分频、GPIO 消抖
// 门限、ADC 控制节拍、曲目节拍与音高相位增量），避免只换时钟而漏改分频常数。
module instrument32_top #(
    parameter integer AUDIO_IF      = 2,
    parameter integer AUDIO_CLK_HZ  = (AUDIO_IF == 1) ? `FPGA_AUDIO_STD_CLK_HZ : `FPGA_AUDIO_DBG_CLK_HZ,
    parameter integer AUDIO_FS_HZ   = (AUDIO_IF == 1) ? `FPGA_AUDIO_STD_FS_HZ  : `FPGA_AUDIO_DBG_FS_HZ,
    parameter integer I2S_DATA_BITS = 24,                     // AUDIO_IF=1/2 时每声道槽宽
    // 曲目单位时长：81 BPM 的十六分音符。48 kHz 档为 8889 采样（185.19 ms），
    // 调试档 46875 Hz 为 8681 采样（185.17 ms），偏差都在 0.01% 以内。
    parameter integer SONG_UNIT_SAMPLES = (AUDIO_IF == 1) ? 8889 : 8681,
    // 演奏输入选择：标准 27 MHz 生产档停用 12 路 GPIO 键（GPIO_KEY_ENABLE=0），
    // 由 USB 电脑键盘经 CH9350L 串口输入（HOST_KBD_ENABLE=1）。旧 debug/standard
    // profile 保持 GPIO=1、HOST=0，便于回归与回退。
    parameter integer GPIO_KEY_ENABLE = 1,
    parameter integer HOST_KBD_ENABLE = 0,
    // 0 = strict；1 = idle-only（默认，持键静默不误清音）。
    parameter integer HOST_KBD_TIMEOUT_POLICY = 1,
    // FSR is a momentary mute in demo and manual modes. Standard profiles
    // enabled; legacy PT8211 bypassed unless explicitly enabled by its wrapper.
    parameter integer PRESSURE_ENABLE = (AUDIO_IF != 0),
    // Retained legacy pressure-gain parameters for source compatibility.
    parameter integer PRESSURE_ADC_LOW = 128,
    parameter integer PRESSURE_ADC_FULL = 3200,
    parameter integer PRESSURE_MIN_GAIN_Q12 = 1024,
    parameter integer PRESSURE_GAIN_STEP = 32,
    // Four signed 16-bit voices, unity pressure gain: divide by four before
    // saturation. This adds 6.02 dB headroom over the historical shift=1.
    parameter integer VOICES = 32,
    parameter integer INSTRUMENT_DEFAULT = 0,
    parameter integer MASTER_VOLUME_SHIFT = 2,
    parameter integer CORE_EXTRA_FRACTION_BITS = 2
) (
    input  wire clk_27m,     // H11，板载 27 MHz；AUDIO_IF=1 时不使用，0/2 使用
    input  wire clk_12m288,  // T7（J14-10，GCLKT_3），外置 3.3 V CMOS 12.288 MHz 有源晶振；仅 AUDIO_IF=1 使用
    input  wire key_rst,     // S3 / D7, active-low design reset
    input  wire key_s1,      // S1 / T3, active-low, chord set A/B
    input  wire key_s2,      // S2 / T2，低有效；下一速度档并重启曲目
    input  wire uart_rx,     // T13, from BL702 UART1_TX
    input  wire kbd_uart_rx, // 标准档：CH9350L 下位机 TXD -> FPGA（L9 / J5-5）
    output wire kbd_uart_tx, // 标准档：FPGA -> CH9350L RXD（N8 / J5-6），当前固定高
    input  wire [11:0] gpio_key_n, // [S2-AI] 12 路琴键，低有效，外部上拉；键 0 = C4
    // [S4] MCP3208 SPI：CH0 = 压力 FSR，CH1 = 弯音电位器。
    output wire             adc_cs_n,
    output wire             adc_sck,
    output wire             adc_mosi,
    input  wire             adc_miso,
    output wire hp_bck,
    output wire hp_ws,
    output wire hp_din,
    output wire pa_en,
    output wire led,         // N16，曲目循环标记；数字静音时常亮
    output wire led_chord,   // N14, lit while chord set B is selected
    output wire led_t0,      // L14, tempo preset bit 0
    output wire led_t1,      // L16, tempo preset bit 1
    output wire uart_tx,     // M11, to BL702 UART1_RX
    // [S6/S5] 削波计数与压力/弯音观测值折叠成的草稿输出，引脚待实物核对。
    output wire [3:0]       clip_fold,
    // [集成] 外置 PCM5102A 标准 I2S 三线；AUDIO_IF=0 时这三根与 dac_xsmt 固定为低。
    output wire             i2s_bck,
    output wire             i2s_lrck,
    output wire             i2s_din,
    output wire             dac_xsmt,     // PCM5102A 软静音控制，1 = 解除静音
    // HDMI dashboard snapshot. Stable bus plus a 1 kHz toggle for CDC.
    output wire [63:0]      ui_status,
    output wire             ui_status_toggle,
    output wire [255:0]     ui_waveform,
    output wire [63:0]      ui_spectrum,
    output wire [63:0]      ui_lissajous,
    output wire             ui_visual_toggle,
    // 1 = HDMI external display, 0 = computer dashboard over UART.
    output wire             display_route,
    output wire [31:0] ui_voice_mask
);

    // 编译期选择的内部音频时钟。AUDIO_IF 是常数，综合会把它折叠成直连，
    // 因此不存在运行时切换时钟源的毛刺风险，也没有跨时钟域逻辑。
    wire clk_audio = (AUDIO_IF == 1) ? clk_12m288 : clk_27m;

    // 与音频时钟配套的编译期常数：2 kHz 控制节拍与约 111 ms 的循环标记。
    localparam integer CTRL_TICK_DIV = AUDIO_CLK_HZ / 2000;
    localparam integer BLINK_CYCLES  = AUDIO_CLK_HZ / 9;

    // ------------------------------------------------------- reset tree ---
    // por 在配置结束约 2.4 ms 后释放；rst = por | S3 软件复位。
    // PT8211 时钟与 pa_en 只受 por 控制，S3 不会重启 DAC 串行时钟或关闭耳放。
    // S3 会把 final_sample 置零；实际爆音/底噪仍需实测，不能由此保证消除。
    // 采样节拍由当前选用的发送器给出：调试档 46.875 kHz（pt8211_tx），
    // 标准档 48 kHz（i2s_tx）。两者都是单 clk 脉冲，整条合成链以它为唯一样本节拍。
    wire sample_tick;

    // 显式初值用于配置启动和 RTL 仿真；不要假定所有未初始化寄存器都为零。
    // reset_cnt 若从 X 开始，比较和自增不能让 por 在仿真中正常释放。
    reg [15:0] reset_cnt = 16'd0;
    always @(posedge clk_audio)
        if (reset_cnt != 16'hFFFF)
            reset_cnt <= reset_cnt + 1'b1;

    wire por = (reset_cnt != 16'hFFFF);
    assign pa_en = ~por;

    // S3 on D7 is a plain 1.5 V user IO; S0/T10 is reserved for the
    // configuration SSPI and S4/B10 is RECONFIG_N, so neither can be used.
    reg [1:0] rst_key_sync = 2'b11;
    always @(posedge clk_audio)
        rst_key_sync <= {rst_key_sync[0], key_rst};

    wire soft_rst = ~rst_key_sync[1];
    wire rst      = por | soft_rst;

    // ------------------------------------------------------ user keys -----
    wire s1_press, s2_press;
    wire uart_timbre_valid;
    wire [7:0] uart_timbre_value, timbre_target;
    // HID 键盘的 F1-F5 与 UART 的 T250-T254 共用音色入口；同一拍 HID 优先。
    // F6 与串口 I0/I1 同义（钢琴/吉他切换），Up/Down 单步调节主音量。
    wire hid_timbre_valid;
    wire [7:0] hid_timbre_value;
    wire hid_instr_toggle;
    wire hid_mode_toggle;
    wire hid_pause_toggle;
    wire hid_vol_up;
    wire hid_vol_down;
    wire       uart_instr_valid;
    wire [1:0] uart_instr_id;
    wire       uart_vol_valid;
    wire [6:0] uart_vol_value;
    wire       timbre_valid_mux = uart_timbre_valid | hid_timbre_valid;
    wire [7:0] timbre_value_mux = hid_timbre_valid ? hid_timbre_value : uart_timbre_value;
    // 乐器运行时切换：I0 钢琴，I1 吉他。切换拍清声部/事件，避免持音中途换表。
    reg  [1:0] instrument_id;
    reg        instrument_change;
    always @(posedge clk_audio) begin
        if (rst) begin
            instrument_id <= INSTRUMENT_DEFAULT[1:0];
            instrument_change <= 1'b0;
        end else begin
            instrument_change <= 1'b0;
            if (uart_instr_valid && (uart_instr_id != instrument_id)) begin
                instrument_id <= uart_instr_id;
                instrument_change <= 1'b1;
            end else if (hid_instr_toggle) begin
                // F6 等价 I0/I1 切换；切换拍清事件与按键，避免持音中途换表。
                instrument_id <= instrument_id ^ 2'd1;
                instrument_change <= 1'b1;
            end
        end
    end
    wire guitar_mode = (instrument_id != 2'd0);
    wire piano_mode = !guitar_mode && (timbre_target >= 8'd250);
    wire [2:0] piano_tone = piano_mode ? (timbre_target - 8'd250) : 3'd0;
    wire [7:0] timbre_mix_weight = (piano_mode || guitar_mode) ? 8'hff : timbre_target;
    wire show_timbre;
    wire [1:0] timbre_preset;
    instrument_controls #(.CLK_HZ(AUDIO_CLK_HZ)) u_controls (
        .clk(clk_audio), .por(por), .rst(rst), .key_s1(key_s1), .key_s2(key_s2),
        .timbre_valid(timbre_valid_mux), .timbre_value(timbre_value_mux),
        .s1_short(s1_press), .s2_press(s2_press), .timbre_target(timbre_target),
        .show_timbre(show_timbre), .preset(timbre_preset)
    );

    // S1 short press commits on debounced release; long press selects timbre.
    // Both profiles debounce for 20 ms; S2 press still selects tempo immediately.
    // 档位索引 0..3 对应每个曲目时间单位的 1..4 倍时长，并非逐档翻倍。
    // 本组寄存器仅用 por 复位：S3 保留和弦集和速度档，rst 会重启演奏逻辑。
    reg chord_set;
    reg song_select;
    reg song_change;
    reg restart;
    reg [1:0] tempo_sel;

    always @(posedge clk_audio) begin
        if (por) begin
            song_select <= 1'b0;
            song_change <= 1'b0;
            chord_set <= 1'b0;
            restart   <= 1'b0;
            // Preset index 0 (1x) is the score tempo of the new test tune:
            // quarter = 81, exactly as written, so a cold boot is already the
            // strict-tempo run.  The LEDs are active low and driven as
            // ~tempo_sel[bit], so a lit LED means that bit is one.  S2 steps
            // through all four presets for slow-motion listening.
            tempo_sel <= 2'd0;
        end else begin
            song_change <= s1_press;
            if (s1_press)
                song_select <= ~song_select;
            if (s2_press)
                tempo_sel <= tempo_sel + 2'd1;   // wraps 3 -> 0
            restart <= s2_press;
        end
    end

    // ------------------------------------------------------- note events ---
    wire        sp_ev_wr;
    wire [15:0] sp_ev_data;
    wire [7:0]  mel_idx_dbg;
    wire        fifo_empty;
    wire        fifo_full;
    wire        fifo_ready;
    wire [15:0] fifo_data;
    wire        fifo_rd;
    wire        uart_ev_valid, uart_ev_on, uart_panic, uart_muted;
    wire        uart_demo_on, uart_demo_off;
    wire        demo_on_request, demo_off_request;
    wire [6:0]  uart_ev_note;
    wire [7:0]  uart_ev_vel;

    // [S2-AI-BEGIN] 手动来源：GPIO（旧档）与 CH9350L HID（标准档）共用 16 项 FIFO。
    // 优先级：清理（Panic/模式切换/断线）> 首事件暂存 > UART > 手动 FIFO > 演示 FIFO。
    wire        gp_ev_valid, gp_ev_on;
    wire [6:0]  gp_ev_note;
    wire [7:0]  gp_ev_vel;
    wire        gp_ev_ready;
    wire        hid_ev_valid, hid_ev_on;
    wire [6:0]  hid_ev_note;
    wire [7:0]  hid_ev_vel;
    wire        hid_ev_ready;
    wire        hid_panic, hid_link_timeout, hid_device_notify, hid_overflow;
    wire [6:0]  hid_base_note;
    wire [3:0]  hid_held_count;
    wire        man_empty, man_ready;
    wire [15:0] man_data;
    wire        man_rd;

    // X 全松键、D1/D0 模式切换、HID Esc 或断线时，丢弃未发送的手动事件并重新武装输入：
    // 已经按住的键必须松开再按才会重新起音。这里不能直接用 clear_events 驱动，
    // 否则由输入触发的那次“退出演示”会把首个按键事件一起清掉。
    // IdleOnly timeout means no physical keys are held, not USB detach.
    // Sustained notes / release tails can still sound. Reset the HID parser's
    // local state, but never clear the musical state on that idle observation.
    // Strict policy and explicit detach keep their emergency clear behavior.
    wire hid_audio_timeout = (HOST_KBD_TIMEOUT_POLICY == 0) && hid_link_timeout;
    wire manual_flush = uart_panic || hid_panic || hid_audio_timeout || hid_device_notify ||
                        instrument_change || song_change ||
                        demo_on_request || demo_off_request;

    // 标准 27 MHz 档不再使用 12 路 GPIO 演奏键；旧 debug/standard 档保留以便回退。
    generate
        if (GPIO_KEY_ENABLE) begin : g_gpio_keys
            gpio_keyboard #(.CLK_HZ(AUDIO_CLK_HZ)) u_gpio (
                .clk       (clk_audio),
                .rst       (rst),
                .key_in    (gpio_key_n),
                .flush     (manual_flush),
                .ev_ready  (gp_ev_ready),
                .ev_valid  (gp_ev_valid),
                .ev_on     (gp_ev_on),
                .ev_note   (gp_ev_note),
                .ev_vel    (gp_ev_vel),
                .key_pressed()
            );
        end else begin : g_no_gpio_keys
            assign gp_ev_valid = 1'b0;
            assign gp_ev_on    = 1'b0;
            assign gp_ev_note  = 7'd0;
            assign gp_ev_vel   = 8'd0;
        end
    endgenerate

    // 标准档演奏输入：CH9350L 下位机 state 2。kbd_uart_rx 未连接时按空闲高处理，
    // 避免旧测试台省略该端口后出现 X 传播。
    wire kbd_rx_i = (kbd_uart_rx === 1'b0) ? 1'b0 : 1'b1;
    generate
        if (HOST_KBD_ENABLE) begin : g_host_kbd
            host_kbd_input #(.CLK_HZ(AUDIO_CLK_HZ), .TIMEOUT_POLICY(HOST_KBD_TIMEOUT_POLICY)) u_host_kbd (
                .clk(clk_audio), .rst(rst), .kbd_rx(kbd_rx_i), .kbd_tx(kbd_uart_tx),
                .flush(manual_flush),
                .ev_valid(hid_ev_valid), .ev_word({hid_ev_on, hid_ev_note, hid_ev_vel}),
                .ev_ready(hid_ev_ready),
                .panic(hid_panic), .timbre_valid(hid_timbre_valid),
                .timbre_value(hid_timbre_value),
                .instr_toggle(hid_instr_toggle), .mode_toggle(hid_mode_toggle),
                .pause_toggle(hid_pause_toggle),
                .vol_up(hid_vol_up), .vol_down(hid_vol_down),
                .base_note(hid_base_note), .held_count(hid_held_count),
                .overflow(hid_overflow), .link_timeout(hid_link_timeout), .device_notify(hid_device_notify),
                .frame_valid()
            );
        end else begin : g_no_host_kbd
            assign hid_ev_valid  = 1'b0;
            assign hid_ev_on     = 1'b0;
            assign hid_ev_note   = 7'd0;
            assign hid_ev_vel    = 8'd0;
            assign hid_panic     = 1'b0;
            assign hid_timbre_valid = 1'b0;
            assign hid_timbre_value = 8'd0;
            assign hid_instr_toggle = 1'b0;
            assign hid_mode_toggle = 1'b0;
            assign hid_pause_toggle = 1'b0;
            assign hid_vol_up    = 1'b0;
            assign hid_vol_down  = 1'b0;
            assign hid_base_note = 7'd60;
            assign hid_held_count = 4'd0;
            assign hid_overflow  = 1'b0;
            assign hid_link_timeout = 1'b0;
            assign hid_device_notify = 1'b0;
            assign kbd_uart_tx   = 1'b1;
        end
    endgenerate

    reg         demo_mode;
    reg         demo_paused;
    wire demo_transport_paused = demo_mode && demo_paused;
    // Explicit UART D0/D1 wins if both interfaces request a mode on this clock.
    wire hid_mode_request = hid_mode_toggle && !uart_demo_on && !uart_demo_off;
    assign demo_on_request  = uart_demo_on  || (hid_mode_request && !demo_mode);
    assign demo_off_request = uart_demo_off || (hid_mode_request &&  demo_mode);
    reg         pending_valid;
    reg [15:0]  pending_word;

    // GPIO 与 HID 共用一个手动 FIFO：GPIO 优先，HID 在 ready 前保持自己的事件。
    // 演示模式期间只接收 Note On；松键不进队列，避免挡住后面真正的按键。
    // In demo mode, Note Offs from a held manual key are intentionally dropped.
    // They must still be acknowledged with ev_ready, otherwise the upstream
    // GPIO/HID queue keeps the stale Note Off and blocks the next Note On.
    wire gp_drop  = demo_mode && gp_ev_valid && !gp_ev_on;
    wire hid_drop = demo_mode && hid_ev_valid && !hid_ev_on;
    wire gp_ok  = gp_ev_valid && !gp_drop;
    wire hid_ok = hid_ev_valid && !hid_drop;
    wire use_gpio = gp_ok;
    wire man_wr = man_ready && (gp_ok || hid_ok);
    wire [15:0] man_wr_data = use_gpio ? {gp_ev_on, gp_ev_note, gp_ev_vel}
                                       : {hid_ev_on, hid_ev_note, hid_ev_vel};
    assign gp_ev_ready  = gp_drop || (man_ready && use_gpio);
    assign hid_ev_ready = hid_drop || (man_ready && !use_gpio);

    event_fifo u_manual (
        .clk     (clk_audio),
        .rst     (rst | manual_flush),
        .wr_en   (man_wr),
        .wr_data (man_wr_data),
        .rd_en   (man_rd),
        .rd_data (man_data),
        .empty   (man_empty),
        .full    (),
        .wr_ready(man_ready)
    );

    wire        man_ev_valid = !man_empty;   // event_fifo 的 rd_data 是队首组合输出
    wire [15:0] man_ev_word  = man_data;
    wire        man_ev_on    = man_ev_word[15];
    // [S2-AI-END]

    // [S2-AI] 只有 GPIO 的 Note On 才触发退出演示；单纯松开一个键不应该把
    // 已经回到演示的设计再次拉进手动模式。
    wire        manual_transition = demo_mode && (uart_ev_valid || uart_panic ||
                                                  (gp_ev_valid && gp_ev_on) ||
                                                  (hid_ev_valid && hid_ev_on) ||
                                                  (man_ev_valid && man_ev_on));
    wire        clear_events = demo_on_request || demo_off_request ||
                               manual_transition || uart_panic || hid_panic ||
                               hid_audio_timeout || hid_device_notify || instrument_change || song_change || (restart && demo_mode);

    always @(posedge clk_audio) begin
        if (rst) begin
            demo_mode     <= 1'b1; // preserve power-on song demonstration
            demo_paused   <= 1'b0;
            pending_valid <= 1'b0;
            pending_word  <= 16'd0;
        end else begin
            pending_valid <= 1'b0;
            if (demo_on_request || song_change)
                demo_mode <= 1'b1;
            else if (demo_off_request || manual_transition)
                demo_mode <= 1'b0;
            if (demo_on_request || demo_off_request || manual_transition || song_change)
                demo_paused <= 1'b0;
            else if (hid_pause_toggle && demo_mode)
                demo_paused <= !demo_paused;
            // 退出演示这一拍先清队列并松开旧声部，把首个 N/O 事件暂存一拍，
            // 下一拍再送分配器，避免同拍 panic 吞掉它；并非等 Release 完成。
            // pending_valid 没有 ready 握手且只保留一拍。UART 命令相隔多个字节
            // 时间，适用本版稀疏输入；未来 GPIO 连续突发须使用持有/背压队列。
            if (manual_transition && uart_ev_valid) begin
                pending_valid <= 1'b1;
                pending_word  <= {uart_ev_on, uart_ev_note, uart_ev_vel};
            end
        end
    end

    song_player32 #(.UNIT_SAMPLES(SONG_UNIT_SAMPLES), .SONG_SELECT_ENABLE(1)) u_song (
        .clk          (clk_audio),
        .rst          (rst | ~demo_mode),
        .sample_tick  (sample_tick && !demo_transport_paused),
        .restart      (restart | demo_on_request | song_change),
        .song_select  (song_select),
        .chord_set    (chord_set),
        .tempo_sel    (tempo_sel),
        .ev_ready     (fifo_ready && !demo_transport_paused),
        .ev_wr        (sp_ev_wr),
        .ev_data      (sp_ev_data),
        .mel_idx_dbg  (mel_idx_dbg),
        .chord_idx_dbg()
    );

    // ------------------------------------------------------- loop marker ---
    // 旋律索引返回 0 时亮灯约 111 ms，便于测量循环间隔。
    // 周期随 tempo_sel + 1 成比例变化；切换模式/重启也可能触发索引回零。
    reg [7:0]  mel_idx_d;
    reg [21:0] loop_blink_cnt;
    reg        loop_blink;

    always @(posedge clk_audio) begin
        if (por) begin
            mel_idx_d      <= 8'd0;
            loop_blink_cnt <= 22'd0;
            loop_blink     <= 1'b0;
        end else begin
            mel_idx_d <= mel_idx_dbg;
            if ((mel_idx_dbg == 8'd0) && (mel_idx_d != 8'd0)) begin
                loop_blink_cnt <= BLINK_CYCLES[21:0];   // about 111 ms
                loop_blink     <= 1'b1;
            end else if (loop_blink_cnt != 22'd0) begin
                loop_blink_cnt <= loop_blink_cnt - 22'd1;
                if (loop_blink_cnt == 22'd1)
                    loop_blink <= 1'b0;
            end
        end
    end

    event_fifo u_fifo (
        .clk     (clk_audio),
        .rst     (rst | clear_events),
        .wr_en   (sp_ev_wr & demo_mode & !demo_transport_paused),
        .wr_data (sp_ev_data),
        .rd_en   (fifo_rd),
        .rd_data (fifo_data),
        .empty   (fifo_empty),
        .full    (fifo_full),
        .wr_ready(fifo_ready)
    );

    uart_ctrl #(.CLK_HZ(AUDIO_CLK_HZ)) u_uart (
        .clk      (clk_audio),
        .rst      (rst),
        .uart_rx  (uart_rx),
        .uart_tx  (uart_tx),
        .ui_status (ui_status), .ui_waveform (ui_waveform),
        .ui_spectrum (ui_spectrum), .ui_lissajous (ui_lissajous),
        .ev_valid (uart_ev_valid),
        .ev_on    (uart_ev_on),
        .ev_note  (uart_ev_note),
        .ev_vel   (uart_ev_vel),
        .panic    (uart_panic),
        .muted    (uart_muted),
        .demo_on  (uart_demo_on),
        .demo_off (uart_demo_off),
        .timbre_valid (uart_timbre_valid), .timbre_value (uart_timbre_value),
        .instr_valid (uart_instr_valid), .instr_id (uart_instr_id),
        .vol_valid (uart_vol_valid), .vol_value (uart_vol_value),
        .display_route (display_route)
    );

    // 模式切换、X 或演示重启先清 FIFO 并撤销旧声部 gate，走正常 Release。
    // 同拍禁止分发新事件；之后优先级为首事件暂存 > UART N/O > GPIO 手动 FIFO > 演示 FIFO。
    // 分配器每个 clk 可接收一个事件；UART 事件没有反压端口，GPIO 手动 FIFO 有 ready。
    wire        uart_direct  = uart_ev_valid && !manual_transition;
    // [S2-AI] 手动 FIFO 只在非演示模式送出；演示期间的 GPIO 松键已在 man_wr 处过滤。
    wire        man_deliver  = man_ev_valid && !demo_mode;
    wire        demo_deliver = demo_mode && !demo_transport_paused && !fifo_empty;
    wire        ev_valid = !clear_events &&
                           (pending_valid || uart_direct || man_deliver || demo_deliver);
    wire [15:0] ev_word  = pending_valid ? pending_word :
                           uart_direct  ? {uart_ev_on, uart_ev_note, uart_ev_vel} :
                           man_deliver  ? man_ev_word : fifo_data;
    assign fifo_rd = demo_deliver && !clear_events && !pending_valid &&
                     !uart_direct && !man_deliver && event_room;
    // [S2-AI] 手动 FIFO 的弹出条件与上面的优先级一致：清理那一拍不消费，
    // 于是由 GPIO 触发的“退出演示”不会把触发它的那个事件丢掉。
    assign man_rd = man_deliver && !clear_events && !pending_valid && !uart_direct && event_room;

    // ------------------------------------------- [S4/S5] ADC 控制路径 ---
    // 2 kHz 控制节拍，分频数按当前主时钟推导：调试档 27 MHz / 13 500 = 2 kHz，
    // 标准档 12.288 MHz / 6 144 = 2 kHz。一次 ADC 事务约 76 us（19 拍 SCLK 周期），
    // 每个节拍连续采集 CH1、CH0，整组约 155 us；每路获得真正的 2 kHz 新样本。
    // 滤波仅在整组完成后推进一次，不能把保持的原始值重复送入中值历史。
    reg [15:0] ctrl_div = 16'd0;
    reg        control_tick = 1'b0;
    always @(posedge clk_audio) begin
        if (rst) begin
            ctrl_div<=0;control_tick<=0;
        end else if (ctrl_div == (CTRL_TICK_DIV - 1)) begin
            ctrl_div     <= 16'd0;
            control_tick <= 1'b1;
        end else begin
            ctrl_div     <= ctrl_div + 1'b1;
            control_tick <= 1'b0;
        end
    end

    // CH0 = 压力 FSR，CH1 = 弯音电位器；每组先 CH1 再 CH0。
    // 显式 1 位通道选择：写成 ~adc_channel[0] 会被上下文补成 3 位（得到 6/7），
    // 这是本仓库第三次遇到 Verilog 上下文位宽坑，故用独立 1 位寄存器。
    reg         adc_sel      = 1'b0;      // 0 = 压力 CH0, 1 = 弯音 CH1
    reg         adc_start    = 1'b0;
    reg         adc_pair_active = 1'b0;
    reg         control_sample_tick = 1'b0;
    // MCP3208 tCSH is at least 500 ns; reserve a full microsecond between
    // the two conversions instead of restarting on the next system clock.
    localparam integer ADC_GAP_CYCLES = (AUDIO_CLK_HZ + 999999) / 1000000;
    reg [$clog2(ADC_GAP_CYCLES+1)-1:0] adc_gap_count = 0;
    reg  [11:0] pressure_raw = 12'd0;
    reg  [11:0] bend_raw     = 12'd2048;
    wire        adc_busy;
    wire        adc_done;
    wire        adc_valid;
    wire [11:0] adc_data;

    always @(posedge clk_audio) begin
      if(rst)begin
        adc_sel<=0;adc_start<=0;adc_pair_active<=0;control_sample_tick<=0;
        adc_gap_count<=0;
        pressure_raw<=0;bend_raw<=12'd2048;
      end else begin
        adc_start <= 1'b0;
        control_sample_tick <= 1'b0;
        if(adc_gap_count!=0) begin
            adc_gap_count<=adc_gap_count-1'b1;
            if(adc_gap_count==1) adc_start<=1'b1;
        end
        if (control_tick && !adc_busy && !adc_pair_active) begin
            adc_start   <= 1'b1;
            adc_sel     <= 1'b1;
            adc_pair_active <= 1'b1;
        end
        if (adc_done) begin
            if (adc_sel) begin
                bend_raw <= adc_data;
                adc_sel <= 1'b0;
                adc_gap_count <= ADC_GAP_CYCLES;
            end else begin
                pressure_raw <= adc_data;
                adc_pair_active <= 1'b0;
                control_sample_tick <= 1'b1;
            end
        end
      end
    end

    mcp3208_spi #(.CLK_HZ(AUDIO_CLK_HZ), .SPI_HZ(250_000)) u_adc (
        .clk (clk_audio), .rst (rst), .start (adc_start),
        .channel ({2'b00, adc_sel}),
        .miso (adc_miso), .cs_n (adc_cs_n), .sclk (adc_sck), .mosi (adc_mosi),
        .busy (adc_busy), .done (adc_done), .data (adc_data),
        .data_valid (adc_valid), .adc_data ()
    );

    wire [11:0]        pressure_filtered;
    wire [11:0]        pressure_level;
    wire signed [15:0] bend_q8;
    wire [16:0]        bend_ratio_q16;
    wire [31:0]        bend_inc0;      // 声部 0 的弯音后增量

    pressure_bend #(.PIPELINE_FINE_RATIO_ENABLE(1)) u_bend (
        .clk (clk_audio), .rst (rst), .control_tick (control_sample_tick),
        .pressure_adc (pressure_raw), .bend_adc (bend_raw),
        .pressure_enable (1'b1), .base_phase_inc (32'd0),
        .pressure_filtered (pressure_filtered), .pressure_level (pressure_level),
        .bend_q8 (bend_q8), .bend_ratio_q16 (bend_ratio_q16),
        .phase_inc_out (bend_inc0)
    );

    wire sustain_pressed;
    wire audio_muted = uart_muted | demo_transport_paused;
    // Separate median-only pedal switching from the display's slower IIR.
    // At 2 kHz: 2/6 confirmations plus median/alignment stay within 4 ms
    // of a sustained raw threshold crossing (ADC/audio stages are additional).
    fsr_pedal_conditioner u_fsr_pedal_detector (
        .clk(clk_audio), .rst(rst), .enable(PRESSURE_ENABLE != 0),
        .update(control_sample_tick), .pressure(pressure_raw), .pressed(sustain_pressed)
    );

    function [8:0] volume_gain;
        input [6:0] v;
        begin
            case (v)
                7'd0: volume_gain = 9'd0;
                7'd1: volume_gain = 9'd0;
                7'd2: volume_gain = 9'd0;
                7'd3: volume_gain = 9'd0;
                7'd4: volume_gain = 9'd0;
                7'd5: volume_gain = 9'd1;
                7'd6: volume_gain = 9'd1;
                7'd7: volume_gain = 9'd1;
                7'd8: volume_gain = 9'd2;
                7'd9: volume_gain = 9'd2;
                7'd10: volume_gain = 9'd3;
                7'd11: volume_gain = 9'd3;
                7'd12: volume_gain = 9'd4;
                7'd13: volume_gain = 9'd4;
                7'd14: volume_gain = 9'd5;
                7'd15: volume_gain = 9'd6;
                7'd16: volume_gain = 9'd7;
                7'd17: volume_gain = 9'd7;
                7'd18: volume_gain = 9'd8;
                7'd19: volume_gain = 9'd9;
                7'd20: volume_gain = 9'd10;
                7'd21: volume_gain = 9'd11;
                7'd22: volume_gain = 9'd12;
                7'd23: volume_gain = 9'd14;
                7'd24: volume_gain = 9'd15;
                7'd25: volume_gain = 9'd16;
                7'd26: volume_gain = 9'd17;
                7'd27: volume_gain = 9'd19;
                7'd28: volume_gain = 9'd20;
                7'd29: volume_gain = 9'd22;
                7'd30: volume_gain = 9'd23;
                7'd31: volume_gain = 9'd25;
                7'd32: volume_gain = 9'd26;
                7'd33: volume_gain = 9'd28;
                7'd34: volume_gain = 9'd30;
                7'd35: volume_gain = 9'd31;
                7'd36: volume_gain = 9'd33;
                7'd37: volume_gain = 9'd35;
                7'd38: volume_gain = 9'd37;
                7'd39: volume_gain = 9'd39;
                7'd40: volume_gain = 9'd41;
                7'd41: volume_gain = 9'd43;
                7'd42: volume_gain = 9'd45;
                7'd43: volume_gain = 9'd47;
                7'd44: volume_gain = 9'd50;
                7'd45: volume_gain = 9'd52;
                7'd46: volume_gain = 9'd54;
                7'd47: volume_gain = 9'd57;
                7'd48: volume_gain = 9'd59;
                7'd49: volume_gain = 9'd61;
                7'd50: volume_gain = 9'd64;
                7'd51: volume_gain = 9'd67;
                7'd52: volume_gain = 9'd69;
                7'd53: volume_gain = 9'd72;
                7'd54: volume_gain = 9'd75;
                7'd55: volume_gain = 9'd77;
                7'd56: volume_gain = 9'd80;
                7'd57: volume_gain = 9'd83;
                7'd58: volume_gain = 9'd86;
                7'd59: volume_gain = 9'd89;
                7'd60: volume_gain = 9'd92;
                7'd61: volume_gain = 9'd95;
                7'd62: volume_gain = 9'd98;
                7'd63: volume_gain = 9'd102;
                7'd64: volume_gain = 9'd105;
                7'd65: volume_gain = 9'd108;
                7'd66: volume_gain = 9'd112;
                7'd67: volume_gain = 9'd115;
                7'd68: volume_gain = 9'd118;
                7'd69: volume_gain = 9'd122;
                7'd70: volume_gain = 9'd125;
                7'd71: volume_gain = 9'd129;
                7'd72: volume_gain = 9'd133;
                7'd73: volume_gain = 9'd136;
                7'd74: volume_gain = 9'd140;
                7'd75: volume_gain = 9'd144;
                7'd76: volume_gain = 9'd148;
                7'd77: volume_gain = 9'd152;
                7'd78: volume_gain = 9'd156;
                7'd79: volume_gain = 9'd160;
                7'd80: volume_gain = 9'd164;
                7'd81: volume_gain = 9'd168;
                7'd82: volume_gain = 9'd172;
                7'd83: volume_gain = 9'd176;
                7'd84: volume_gain = 9'd181;
                7'd85: volume_gain = 9'd185;
                7'd86: volume_gain = 9'd189;
                7'd87: volume_gain = 9'd194;
                7'd88: volume_gain = 9'd198;
                7'd89: volume_gain = 9'd203;
                7'd90: volume_gain = 9'd207;
                7'd91: volume_gain = 9'd212;
                7'd92: volume_gain = 9'd217;
                7'd93: volume_gain = 9'd221;
                7'd94: volume_gain = 9'd226;
                7'd95: volume_gain = 9'd231;
                7'd96: volume_gain = 9'd236;
                7'd97: volume_gain = 9'd241;
                7'd98: volume_gain = 9'd246;
                7'd99: volume_gain = 9'd251;
                7'd100: volume_gain = 9'd256;
                default: volume_gain = 9'd0;
            endcase
        end
    endfunction

    reg [6:0] volume_target = 7'd100;
    reg [6:0] volume = 7'd100;
    always @(posedge clk_audio) begin
        if (rst) begin
            volume_target <= 7'd100;
            volume <= 7'd100;
        end else begin
            // UART 的 V 命令设绝对值；HID 的 Up/Down 以 5 为步长单步调整并钳在 0..100。
            // volume_gain 只定义到 100，越过上界会静音，因此必须先钳位再写 target。
            if (uart_vol_valid) volume_target <= uart_vol_value;
            else if (hid_vol_up)
                volume_target <= (volume_target >= 7'd96) ? 7'd100 : volume_target + 7'd5;
            else if (hid_vol_down)
                volume_target <= (volume_target <= 7'd5) ? 7'd0 : volume_target - 7'd5;
            if (sample_tick) begin
                if (volume < volume_target) volume <= volume + 7'd1;
                else if (volume > volume_target) volume <= volume - 7'd1;
            end
        end
    end

    wire event_room,event_empty,event_ready,sustain_ready,sustain_valid;
    wire [15:0] event_data;
    wire [15:0] sustain_word;
    wire owned_ev_valid;
    note_ownership u_ownership(
        .clk(clk_audio),.rst(rst),.clear(clear_events),.manual_mode(!demo_mode),
        .event_valid(ev_valid && event_room),.event_on(ev_word[15]),.note(ev_word[14:8]),
        .source_uart(pending_valid || uart_direct),.forward_valid(owned_ev_valid));
    event_fifo u_compute_events(
        .clk(clk_audio),.rst(rst || clear_events),.wr_en(owned_ev_valid),.wr_data(ev_word),
        .rd_en(!event_empty && sustain_ready),.rd_data(event_data),.empty(event_empty),
        .full(),.wr_ready(event_room));
    sustain_pedal u_sustain(.clk(clk_audio),.rst(rst),.clear(clear_events),
        .pedal(sustain_pressed && !demo_mode),.in_valid(!event_empty),.in_word(event_data),
        .in_ready(sustain_ready),.out_valid(sustain_valid),.out_word(sustain_word),.out_ready(event_ready));
    wire signed [23:0] final_sample24;
    wire core_locked,core_initialized;
    ram32_board_engine u_ram32(
        .clk_ref(clk_audio),.rst(rst),.clear(clear_events),.sample_tick(sample_tick),
        .ev_valid(sustain_valid),.ev_word(sustain_word),.ev_ready(event_ready),
        .control_in({pressure_level,bend_ratio_q16,volume_gain(volume),timbre_mix_weight,
            guitar_mode,piano_tone,audio_muted,demo_mode,piano_mode,instrument_id,
            song_select,demo_paused,show_timbre,tempo_sel,timbre_target,sustain_pressed}),
        .sample_out(final_sample24),.ui_status(ui_status),.ui_status_toggle(ui_status_toggle),
        .ui_voice_mask(ui_voice_mask),.ui_waveform(ui_waveform),.ui_spectrum(ui_spectrum),
        .ui_lissajous(ui_lissajous),.ui_visual_toggle(ui_visual_toggle),
        .locked(core_locked),.initialized(core_initialized));
    i2s_tx #(.CLK_HZ(AUDIO_CLK_HZ),.SAMPLE_RATE_HZ(AUDIO_FS_HZ),.DATA_BITS(24)) u_i2s(
        .clk(clk_audio),.rst(por),.sample_l(final_sample24),.sample_r(final_sample24),
        .bck(i2s_bck),.lrck(i2s_lrck),.din(i2s_din),.sample_tick(sample_tick));
    assign hp_bck=0;assign hp_ws=0;assign hp_din=0;assign dac_xsmt=1;
    assign clip_fold=pressure_level[11:8] ^ bend_ratio_q16[15:12];
    assign led=audio_muted ? 1'b0 : ~loop_blink;
    assign led_chord=~song_select;
    assign led_t0=~(show_timbre ? timbre_preset[0] : tempo_sel[0]);
    assign led_t1=~(show_timbre ? timbre_preset[1] : tempo_sel[1]);
`ifdef SIMULATION
    initial if(VOICES!=32 || AUDIO_IF!=2 || AUDIO_CLK_HZ!=27000000 || AUDIO_FS_HZ!=46875)
        $fatal(1,"Production32 requires 32 voices, board 27 MHz and I2S 46.875 kHz");
    always @(posedge clk_audio) if(!rst && uart_ev_valid && !manual_transition && !event_room)
        $fatal(1,"Production32 UART event queue overflow");
`endif
endmodule


