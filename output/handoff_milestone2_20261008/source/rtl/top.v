// SRAM 0x5633 发布基线：Tang Primer 20K Dock 上的四声部演示/电脑演奏。
// 实际路径：song_player -> event_fifo --+
//          uart_ctrl -> 首事件暂存/直送 --+-> voice_alloc -> 4 个 poly_voice
//                                      -> mixer -> pt8211_tx -> 板载耳机路径。
// 演示事件经过 FIFO；UART 音符绕过 FIFO，由下方仲裁逻辑直接交给声部分配器。
// [S2-AI 新增] 12 路 GPIO 琴键经 gpio_keyboard 同步/消抖后进入独立的手动事件
// FIFO，再与 UART、演示事件在同一仲裁器汇合。GPIO 突发不再走 UART 的单拍入口。
// 标准档接入 MCP3208 压力/弯音与 PCM5102A I2S；MPR121 仍为备选。
//
// S1 短按松开切伴奏，长按 600 ms 切音色；S2 速度；S3 复位演奏逻辑。
// UART 115200 8N1：N<note>/O<note>/X 发音/松键/全部松键，M0/M1 数字静音/恢复，
// T0..T255 设音色权重；D0 手动等待、D1 重启演示；N/O/X 也会退出演示。命令以 CR 或 LF 结束。
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
module top #(
    parameter integer AUDIO_IF      = 0,
    parameter integer AUDIO_CLK_HZ  = (AUDIO_IF == 1) ? `FPGA_AUDIO_STD_CLK_HZ : `FPGA_AUDIO_DBG_CLK_HZ,
    parameter integer AUDIO_FS_HZ   = (AUDIO_IF == 1) ? `FPGA_AUDIO_STD_FS_HZ  : `FPGA_AUDIO_DBG_FS_HZ,
    parameter integer I2S_DATA_BITS = 24,                     // AUDIO_IF=1/2 时每声道槽宽
    // 曲目单位时长：调试档 9766 采样 @46.875 kHz = 208.34 ms；48 kHz 档按同一时长
    // 换算得 10000.4，取 10000（208.33 ms，偏差 0.004%）。
    parameter integer SONG_UNIT_SAMPLES = (AUDIO_IF == 1) ? 10000 : 9766,
    // 演奏输入选择：标准 27 MHz 生产档停用 12 路 GPIO 键（GPIO_KEY_ENABLE=0），
    // 由 USB 电脑键盘经 CH9350L 串口输入（HOST_KBD_ENABLE=1）。旧 debug/standard
    // profile 保持 GPIO=1、HOST=0，便于回归与回退。
    parameter integer GPIO_KEY_ENABLE = 1,
    parameter integer HOST_KBD_ENABLE = 0,
    // FSR controls one global VCA. Standard profiles (1 and 2) enabled, legacy
    // PT8211 profile bypassed. These are provisional ADC calibration values, not N.
    parameter integer PRESSURE_ENABLE = (AUDIO_IF != 0),
    parameter integer PRESSURE_ADC_LOW = 128,
    parameter integer PRESSURE_ADC_FULL = 3200,
    parameter integer PRESSURE_MIN_GAIN_Q12 = 1024,
    parameter integer PRESSURE_GAIN_STEP = 32,
    // Four signed 16-bit voices, unity pressure gain: divide by four before
    // saturation. This adds 6.02 dB headroom over the historical shift=1.
    parameter integer VOICES = 4,
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
    output wire             dac_xsmt      // PCM5102A 软静音控制，1 = 解除静音
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
    wire hid_timbre_valid;
    wire [7:0] hid_timbre_value;
    wire       uart_instr_valid;
    wire [1:0] uart_instr_id;
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
    reg restart;
    reg [1:0] tempo_sel;

    always @(posedge clk_audio) begin
        if (por) begin
            chord_set <= 1'b0;
            restart   <= 1'b0;
            // Preset index 1 (2x) is the state that was reported as the right
            // playback speed: L14 lit, L16 dark.  The LEDs are active low and
            // driven as ~tempo_sel[bit], so a lit LED means that bit is one.
            // S2 steps through all four presets.
            tempo_sel <= 2'd1;
        end else begin
            if (s1_press)
                chord_set <= ~chord_set;
            if (s2_press)
                tempo_sel <= tempo_sel + 2'd1;   // wraps 3 -> 0
            restart <= s2_press;
        end
    end

    // ------------------------------------------------------- note events ---
    wire        sp_ev_wr;
    wire [15:0] sp_ev_data;
    wire [5:0]  mel_idx_dbg;
    wire        fifo_empty;
    wire        fifo_full;
    wire        fifo_ready;
    wire [15:0] fifo_data;
    wire        fifo_rd;
    wire        uart_ev_valid, uart_ev_on, uart_panic, uart_muted;
    wire        uart_demo_on, uart_demo_off;
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
    wire manual_flush = uart_panic || hid_panic || hid_link_timeout || hid_device_notify ||
                        instrument_change ||
                        uart_demo_on || uart_demo_off;

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
            host_kbd_input #(.CLK_HZ(AUDIO_CLK_HZ)) u_host_kbd (
                .clk(clk_audio), .rst(rst), .kbd_rx(kbd_rx_i), .kbd_tx(kbd_uart_tx),
                .flush(manual_flush),
                .ev_valid(hid_ev_valid), .ev_word({hid_ev_on, hid_ev_note, hid_ev_vel}),
                .ev_ready(hid_ev_ready),
                .panic(hid_panic), .timbre_valid(hid_timbre_valid),
                .timbre_value(hid_timbre_value),
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
            assign hid_base_note = 7'd60;
            assign hid_held_count = 4'd0;
            assign hid_overflow  = 1'b0;
            assign hid_link_timeout = 1'b0;
            assign hid_device_notify = 1'b0;
            assign kbd_uart_tx   = 1'b1;
        end
    endgenerate

    reg         demo_mode;
    reg         pending_valid;
    reg [15:0]  pending_word;

    // GPIO 与 HID 共用一个手动 FIFO：GPIO 优先，HID 在 ready 前保持自己的事件。
    // 演示模式期间只接收 Note On；松键不进队列，避免挡住后面真正的按键。
    wire gp_ok  = gp_ev_valid && !(demo_mode && !gp_ev_on);
    wire hid_ok = hid_ev_valid && !(demo_mode && !hid_ev_on);
    wire use_gpio = gp_ok;
    wire man_wr = man_ready && (gp_ok || hid_ok);
    wire [15:0] man_wr_data = use_gpio ? {gp_ev_on, gp_ev_note, gp_ev_vel}
                                       : {hid_ev_on, hid_ev_note, hid_ev_vel};
    assign gp_ev_ready  = man_ready && use_gpio;
    assign hid_ev_ready = man_ready && !use_gpio;

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
                                                  (man_ev_valid && man_ev_on));
    wire        clear_events = uart_demo_on || uart_demo_off ||
                               manual_transition || uart_panic || hid_panic ||
                               hid_link_timeout || hid_device_notify || instrument_change || (restart && demo_mode);

    always @(posedge clk_audio) begin
        if (rst) begin
            demo_mode     <= 1'b1; // preserve power-on song demonstration
            pending_valid <= 1'b0;
            pending_word  <= 16'd0;
        end else begin
            pending_valid <= 1'b0;
            if (uart_demo_on)
                demo_mode <= 1'b1;
            else if (uart_demo_off || manual_transition)
                demo_mode <= 1'b0;
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

    song_player #(.UNIT_SAMPLES(SONG_UNIT_SAMPLES)) u_song (
        .clk          (clk_audio),
        .rst          (rst | ~demo_mode),
        .sample_tick  (sample_tick),
        .restart      (restart | uart_demo_on),
        .chord_set    (chord_set),
        .tempo_sel    (tempo_sel),
        .ev_ready     (fifo_ready),
        .ev_wr        (sp_ev_wr),
        .ev_data      (sp_ev_data),
        .mel_idx_dbg  (mel_idx_dbg),
        .chord_idx_dbg()
    );

    // ------------------------------------------------------- loop marker ---
    // 旋律索引返回 0 时亮灯约 111 ms，便于测量循环间隔。
    // 周期随 tempo_sel + 1 成比例变化；切换模式/重启也可能触发索引回零。
    reg [5:0]  mel_idx_d;
    reg [21:0] loop_blink_cnt;
    reg        loop_blink;

    always @(posedge clk_audio) begin
        if (por) begin
            mel_idx_d      <= 6'd0;
            loop_blink_cnt <= 22'd0;
            loop_blink     <= 1'b0;
        end else begin
            mel_idx_d <= mel_idx_dbg;
            if ((mel_idx_dbg == 6'd0) && (mel_idx_d != 6'd0)) begin
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
        .wr_en   (sp_ev_wr & demo_mode),
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
        .ev_valid (uart_ev_valid),
        .ev_on    (uart_ev_on),
        .ev_note  (uart_ev_note),
        .ev_vel   (uart_ev_vel),
        .panic    (uart_panic),
        .muted    (uart_muted),
        .demo_on  (uart_demo_on),
        .demo_off (uart_demo_off),
        .timbre_valid (uart_timbre_valid), .timbre_value (uart_timbre_value),
        .instr_valid (uart_instr_valid), .instr_id (uart_instr_id)
    );

    // 模式切换、X 或演示重启先清 FIFO 并撤销旧声部 gate，走正常 Release。
    // 同拍禁止分发新事件；之后优先级为首事件暂存 > UART N/O > GPIO 手动 FIFO > 演示 FIFO。
    // 分配器每个 clk 可接收一个事件；UART 事件没有反压端口，GPIO 手动 FIFO 有 ready。
    wire        uart_direct  = uart_ev_valid && !manual_transition;
    // [S2-AI] 手动 FIFO 只在非演示模式送出；演示期间的 GPIO 松键已在 man_wr 处过滤。
    wire        man_deliver  = man_ev_valid && !demo_mode;
    wire        demo_deliver = demo_mode && !fifo_empty;
    wire        ev_valid = !clear_events &&
                           (pending_valid || uart_direct || man_deliver || demo_deliver);
    wire [15:0] ev_word  = pending_valid ? pending_word :
                           uart_direct  ? {uart_ev_on, uart_ev_note, uart_ev_vel} :
                           man_deliver  ? man_ev_word : fifo_data;
    assign fifo_rd = demo_deliver && !clear_events && !pending_valid &&
                     !uart_direct && !man_deliver;
    // [S2-AI] 手动 FIFO 的弹出条件与上面的优先级一致：清理那一拍不消费，
    // 于是由 GPIO 触发的“退出演示”不会把触发它的那个事件丢掉。
    assign man_rd = man_deliver && !clear_events && !pending_valid && !uart_direct;

    // ---------------------------------------------------- voice control ---
    wire [VOICES-1:0]   v_gate;
    wire [VOICES*7-1:0] v_note;      // VOICES x 7 bit
    wire [VOICES*8-1:0] v_vel;       // VOICES x 8 bit
    wire [VOICES-1:0]   v_idle;
    wire [VOICES-1:0]   v_start;
    wire owned_ev_valid;
    note_ownership u_ownership(
        .clk(clk_audio),.rst(rst),.clear(clear_events),.manual_mode(!demo_mode),
        .event_valid(ev_valid),.event_on(ev_word[15]),.note(ev_word[14:8]),
        .source_uart(pending_valid || uart_direct),.forward_valid(owned_ev_valid));

    voice_alloc #(.VOICES(VOICES)) u_alloc (
        .clk        (clk_audio),
        .rst        (rst),
        .ev_valid   (owned_ev_valid),
        .ev_on      (ev_word[15]),
        .ev_note    (ev_word[14:8]),
        .ev_vel     (ev_word[7:0]),
        .panic      (clear_events),
        .voice_idle (v_idle),
        .v_gate     (v_gate),
        .v_note     (v_note),
        .v_vel      (v_vel),
        .v_start    (v_start),
        .v_busy     ()
    );

    // ----------------------------------------------------------- voices ---
    // 每声部一条相位增量；旧档 VOICES=4，标准 27 MHz 档 VOICES=8。
    wire [31:0] inc [0:7];           // 只驱动 0..VOICES-1，其余未用
    wire [VOICES*7-1:0] render_note;
    wire [VOICES*8-1:0] render_velocity;
    wire [VOICES-1:0] render_retrigger;
    genvar gi;
    generate
        for (gi = 0; gi < VOICES; gi = gi + 1) begin : g_inc
            note_phase_inc #(.FS_HZ(AUDIO_FS_HZ)) u_inc (
                .note(render_note[gi*7 +: 7]), .inc(inc[gi]));
        end
    endgenerate

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
        .pressure_enable (1'b1), .base_phase_inc (inc[0]),
        .pressure_filtered (pressure_filtered), .pressure_level (pressure_level),
        .bend_q8 (bend_q8), .bend_ratio_q16 (bend_ratio_q16),
        .phase_inc_out (bend_inc0)
    );

    // ----------------------------------------------------------- voices ---
    // Reference bend increments remain observable for simulation. The audio
    // engine uses base increments and shares its multiplier for all four;
    // these unused reference products are removed from the hardware netlist.
    // 显式加宽再截断，避免依赖工具对乘积宽度的上下文推断（同 S5 的修正口径）。
    wire [48:0] bend_mul1 = {17'd0, inc[1]} * {32'd0, bend_ratio_q16};
    wire [48:0] bend_mul2 = {17'd0, inc[2]} * {32'd0, bend_ratio_q16};
    wire [48:0] bend_mul3 = {17'd0, inc[3]} * {32'd0, bend_ratio_q16};
    wire [31:0] bend_inc1 = bend_mul1 >> 16;
    wire [31:0] bend_inc2 = bend_mul2 >> 16;
    wire [31:0] bend_inc3 = bend_mul3 >> 16;
    // 音色目标由 S1/串口设置，global_crossfade 在帧边界平滑更新。

    // [S6 共享引擎] 包络留在顶层（每声部一个 adsr），振荡/插值/混合交给共享引擎
    // 时分复用：整机 2 个 pROM、一组共享乘法器、交叉混合全局一次。
    wire [15:0] v_env [0:7];   // 只驱动 0..VOICES-1

    // 与 poly_voice_s6 相同的“start 暂存到 sample_tick”口径，避免事件不对齐采样点。
    reg  [VOICES-1:0] v_pending = {VOICES{1'b0}};
    always @(posedge clk_audio) begin
        if (rst)
            v_pending <= {VOICES{1'b0}};
        else if (sample_tick)
            v_pending <= {VOICES{1'b0}};
        else
            v_pending <= v_pending | v_start;
    end
    wire [VOICES-1:0] v_retrig = v_gate & (v_start | v_pending);

    generate
        for (gi = 0; gi < VOICES; gi = gi + 1) begin : g_voice
            voice_transition u_env (
                .clk (clk_audio), .rst (rst), .sample_tick (sample_tick),
                .piano_mode (piano_mode), .guitar_mode (guitar_mode),
                .note(v_note[gi*7 +: 7]), .velocity(v_vel[gi*8 +: 8]),
                .render_note(render_note[gi*7 +: 7]),
                .render_velocity(render_velocity[gi*8 +: 8]),
                .render_retrigger(render_retrigger[gi]),
                .gate (v_gate[gi]), .retrigger (v_retrig[gi]),
                .env (v_env[gi]), .idle (v_idle[gi])
            );
        end
    endgenerate

    wire signed [18+CORE_EXTRA_FRACTION_BITS:0] sine_sum, bright_sum;
    wire               sums_valid;
    // 引擎和交叉淡化共用一套 18x18 乘法器：请求-下一拍读结果，分拍调度。
    // 8 声部的音高 bug 已由“ST_BEND_APPLY 只更新当前 vsel”修复，不需要第二乘法器。
    wire engine_mult_req,xf_mult_req;
    wire signed[17:0] engine_mult_a,engine_mult_b,xf_mult_a,xf_mult_b;
    reg signed[35:0] audio_mult_result;
    wire signed[17:0] audio_mult_a=engine_mult_req?engine_mult_a:xf_mult_a;
    wire signed[17:0] audio_mult_b=engine_mult_req?engine_mult_b:xf_mult_b;
    always @(posedge clk_audio)begin
        if(rst)audio_mult_result<=0;
        else if(engine_mult_req || xf_mult_req) audio_mult_result<=audio_mult_a*audio_mult_b;
    end
`ifdef SIMULATION
    always @(posedge clk_audio)if(!rst && engine_mult_req && xf_mult_req)$fatal(1,"audio multiplier collision");
`endif

    // 4/8 声部共用同一套 ROM 与乘法器；VOICES8 只改变 FSM 轮询次数。
    wire [7:0] retrig8;
    wire [63:0] vel8;
    assign retrig8[VOICES-1:0] = render_retrigger;
    assign vel8[VOICES*8-1:0] = render_velocity;
    generate
        if (VOICES < 8) begin : g_retrig_pad
            assign retrig8[7:VOICES] = 8'd0;
            assign vel8[63:VOICES*8] = 64'd0;
        end
    endgenerate

    shared_wavetable_engine #(.BEND_SHARED_ENABLE(1),.BANDLIMIT_ENABLE(1),.GENERIC_BRIGHT_ENABLE(1),
        .ZONE_LATCH_ENABLE(1),.STAGE_TIME_ENABLE(1),.STAGE_STEP_SAMPLES(8192),
        .VOICES8((VOICES == 8) ? 1 : 0),.SHARED_MULT_ENABLE(1),.GUITAR_ENABLE(1),
        .EXTRA_FRACTION_BITS(CORE_EXTRA_FRACTION_BITS)) u_engine (
        .clk (clk_audio), .rst (rst), .sample_tick (sample_tick),
        .inc0 (inc[0]), .inc1 (inc[1]), .inc2 (inc[2]), .inc3 (inc[3]),
        .inc4 (inc[4]), .inc5 (inc[5]), .inc6 (inc[6]), .inc7 (inc[7]),
        .bend_ratio_q16(bend_ratio_q16),
        .piano_enable(piano_mode), .guitar_enable(guitar_mode),
        .piano_tone(piano_tone),
        .mult_request(engine_mult_req),.mult_operand_a(engine_mult_a),.mult_operand_b(engine_mult_b),.mult_result(audio_mult_result),
        .retrig0 (retrig8[0]), .retrig1 (retrig8[1]), .retrig2 (retrig8[2]), .retrig3 (retrig8[3]),
        .retrig4 (retrig8[4]), .retrig5 (retrig8[5]), .retrig6 (retrig8[6]), .retrig7 (retrig8[7]),
        .env0 (v_env[0]), .env1 (v_env[1]), .env2 (v_env[2]), .env3 (v_env[3]),
        .env4 (v_env[4]), .env5 (v_env[5]), .env6 (v_env[6]), .env7 (v_env[7]),
        .vel0 (vel8[7:0]), .vel1 (vel8[15:8]),
        .vel2 (vel8[23:16]), .vel3 (vel8[31:24]),
        .vel4 (vel8[39:32]), .vel5 (vel8[47:40]),
        .vel6 (vel8[55:48]), .vel7 (vel8[63:56]),
        .sine_sum (sine_sum), .bright_sum (bright_sum), .sums_valid (sums_valid)
    );

    wire signed [15:0] mixed_shared;
    wire signed [23:0] mixed_shared24;
    wire [31:0] xf_clip_count;
    wire        xf_clip_event;

    global_crossfade #(
        .CLIP_COUNTER_WIDTH(32), .PRESSURE_GAIN_ENABLE(PRESSURE_ENABLE),
        .PRESSURE_ADC_LOW(PRESSURE_ADC_LOW), .PRESSURE_ADC_FULL(PRESSURE_ADC_FULL),
        .PRESSURE_MIN_GAIN_Q12(PRESSURE_MIN_GAIN_Q12),
        .PRESSURE_GAIN_STEP(PRESSURE_GAIN_STEP), .TIMBRE_SLEW_ENABLE(1),.SHARED_MULT_ENABLE(1),
        .MASTER_VOLUME_SHIFT(MASTER_VOLUME_SHIFT), .MUTE_SLEW_ENABLE(1),
        .EXTRA_FRACTION_BITS(CORE_EXTRA_FRACTION_BITS),.REGISTER_MIX_INPUTS_ENABLE(1),.SOFT_LIMIT_ENABLE((VOICES==8)?1:0)
    ) u_xf (
        .clk (clk_audio), .rst (rst), .update (sums_valid), .clear_clip (1'b0),
        .mix_weight (timbre_mix_weight),
        .mult_request(xf_mult_req),.mult_operand_a(xf_mult_a),.mult_operand_b(xf_mult_b),.mult_result(audio_mult_result),
        .sine_sum (sine_sum), .bright_sum (bright_sum), .sample_out (mixed_shared),
        .sample_out24(mixed_shared24),
        .clip_count (xf_clip_count), .clip_event (xf_clip_event),
        .pressure_enable (!demo_mode), .pressure_level (pressure_level), .mute(uart_muted)
    );

    // ------------------------------------------------------------ mixer ---
    // 全局模块统一执行交叉混合、固定余量（生产默认除以4）、VCA及最终量化，
    // 削波只在这一主增益边界计数。mixer_s6 与它的 (1,4,6,4,1) FIR 仍
    // 留在库里并由 tb_s6_audio 覆盖，产品顶层不再实例化：顶层再串一级只会多出
    // 一拍延迟和一份死逻辑。FIR 仍然旁路，启用会把 10 kHz 压到约 -8.5 dB，
    // 音频验收基线要重做。
    // 高音区偏尖锐：主混合后加一级一阶低通，a=0.5 -> fc≈5.2 kHz（46.875 kHz）。
    // 只用移位，不新增乘法器；低音区 3 kHz 以上能量很少，主要压高音。
    reg signed [15:0] mix_lp_y;
    wire signed [16:0] mix_lp_diff = mixed_shared - mix_lp_y;
    wire signed [15:0] mixed_lpf = mix_lp_y + (mix_lp_diff >>> 1);
    always @(posedge clk_audio) begin
        if (rst) mix_lp_y <= 16'sd0;
        else if (sums_valid) mix_lp_y <= mixed_lpf;
    end
    wire signed [15:0] mixed = mixed_lpf;

    // 把削波计数与压力/弯音观测值折成 4 位，避免综合把未接引脚的通路裁掉。
    wire [3:0] fold_clip = xf_clip_count[31:28] ^ xf_clip_count[27:24] ^ xf_clip_count[23:20] ^
                           xf_clip_count[19:16] ^ xf_clip_count[15:12] ^ xf_clip_count[11:8] ^
                           xf_clip_count[7:4] ^ xf_clip_count[3:0] ^ {3'd0, xf_clip_event};
    wire [3:0] fold_pressure = pressure_level[11:8] ^ pressure_level[7:4] ^ pressure_level[3:0] ^
                               pressure_filtered[11:8] ^ pressure_filtered[7:4] ^ pressure_filtered[3:0];
    wire [3:0] fold_bend = bend_q8[15:12] ^ bend_q8[11:8] ^ bend_q8[7:4] ^ bend_q8[3:0] ^
                           {2'b00, adc_busy, adc_valid};
    assign clip_fold = fold_clip ^ fold_pressure ^ fold_bend;

    // M0 通过现有全局VCA逐帧淡出，不切断 pa_en，也不停止声部/曲目计时。
    // 静音仍有噪声时应继续检查供电、接地、DAC/耳放模拟路径。
    wire signed [15:0] final_sample = rst ? 16'sd0 : mixed;
    wire signed [23:0] final_sample24 = rst ? 24'sd0 : mixed_shared24;

    // ------------------------------------------------------- audio output ---
    // AUDIO_IF 是编译期常数，两条接口互斥；未选中的那组输出固定为低电平，
    // 不留未驱动网络。por 只复位串行时钟，数字静音仍走 final_sample 置零。
    generate
        if (AUDIO_IF == 0) begin : g_pt8211
            pt8211_tx u_pt8211 (
                .clk         (clk_audio),
                .rst         (por),
                .sample_in   (final_sample),
                .bck         (hp_bck),
                .ws          (hp_ws),
                .din         (hp_din),
                .sample_tick (sample_tick)
            );
            assign i2s_bck  = 1'b0;
            assign i2s_lrck = 1'b0;
            assign i2s_din  = 1'b0;
            assign dac_xsmt = 1'b0;
        end else begin : g_i2s
            // Keep two fractional bits through interpolation/envelope/velocity,
            // then quantize the VCA product directly into the 24-bit I2S word.
            // Numerical output width does not imply 24-bit analog SNR.
            wire signed [23:0] audio_24 = final_sample24;

            // 嵌套的 generate 区不能再写 generate/endgenerate 关键字（Verilog 限制）。
            if (I2S_DATA_BITS == 24) begin : g_24
                i2s_tx #(.CLK_HZ(AUDIO_CLK_HZ), .SAMPLE_RATE_HZ(AUDIO_FS_HZ),
                         .DATA_BITS(24)) u_i2s (
                    .clk (clk_audio), .rst (por),
                    .sample_l (audio_24), .sample_r (audio_24),
                    .bck (i2s_bck), .lrck (i2s_lrck), .din (i2s_din),
                    .sample_tick (sample_tick)
                );
            end else begin : g_16
                i2s_tx #(.CLK_HZ(AUDIO_CLK_HZ), .SAMPLE_RATE_HZ(AUDIO_FS_HZ),
                         .DATA_BITS(16)) u_i2s (
                    .clk (clk_audio), .rst (por),
                    .sample_l (final_sample), .sample_r (final_sample),
                    .bck (i2s_bck), .lrck (i2s_lrck), .din (i2s_din),
                    .sample_tick (sample_tick)
                );
            end

            assign dac_xsmt = 1'b1;
            assign hp_bck   = 1'b0;
            assign hp_ws    = 1'b0;
            assign hp_din   = 1'b0;
        end
    endgenerate

    // ---------------------------------------------------------- display ---
    // The user LEDs are active low.  N16 is the loop marker: it lights for
    // about 110 ms at the start of every pass through the tune, and stays lit
    // while the output is muted.  Timing the gap between flashes measures the
    // loop directly.  N14 shows the chord set, L14/L16 the tempo preset.
    assign led       = uart_muted ? 1'b0 : ~loop_blink;
    assign led_chord = ~chord_set;
    assign led_t0    = ~(show_timbre ? timbre_preset[0] : tempo_sel[0]);
    assign led_t1    = ~(show_timbre ? timbre_preset[1] : tempo_sel[1]);

endmodule
