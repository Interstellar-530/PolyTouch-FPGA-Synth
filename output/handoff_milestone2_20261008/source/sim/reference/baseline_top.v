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
//                 每帧 64 个 BCK；全部逻辑改由 clk_12m288 驱动，27 MHz 输入不使用。
// 与时钟配套的时间常数都按 AUDIO_CLK_HZ / AUDIO_FS_HZ 推导（UART 波特率分频、GPIO 消抖
// 门限、ADC 控制节拍、曲目节拍与音高相位增量），避免只换时钟而漏改分频常数。
module baseline_top #(
    parameter integer AUDIO_IF      = 0,
    parameter integer AUDIO_CLK_HZ  = (AUDIO_IF == 0) ? `FPGA_AUDIO_DBG_CLK_HZ : `FPGA_AUDIO_STD_CLK_HZ,
    parameter integer AUDIO_FS_HZ   = (AUDIO_IF == 0) ? `FPGA_AUDIO_DBG_FS_HZ  : `FPGA_AUDIO_STD_FS_HZ,
    parameter integer I2S_DATA_BITS = 24,                     // AUDIO_IF=1 时每声道槽宽
    // 曲目单位时长：调试档 9766 采样 @46.875 kHz = 208.34 ms；48 kHz 档按同一时长
    // 换算得 10000.4，取 10000（208.33 ms，偏差 0.004%）。
    parameter integer SONG_UNIT_SAMPLES = (AUDIO_IF == 0) ? 9766 : 10000,
    // FSR controls one global VCA. Standard profile enabled, legacy PT8211
    // profile bypassed. These are provisional ADC calibration values, not N.
    parameter integer PRESSURE_ENABLE = (AUDIO_IF == 1),
    parameter integer PRESSURE_ADC_LOW = 128,
    parameter integer PRESSURE_ADC_FULL = 3200,
    parameter integer PRESSURE_MIN_GAIN_Q12 = 1024,
    parameter integer PRESSURE_GAIN_STEP = 32
) (
    input  wire clk_27m,     // H11，板载 27 MHz；AUDIO_IF=1 时不使用
    input  wire clk_12m288,  // T7（J14-10，GCLKT_3），外置 3.3 V CMOS 12.288 MHz 有源晶振
    input  wire key_rst,     // S3 / D7, active-low design reset
    input  wire key_s1,      // S1 / T3, active-low, chord set A/B
    input  wire key_s2,      // S2 / T2，低有效；下一速度档并重启曲目
    input  wire uart_rx,     // T13, from BL702 UART1_TX
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
    wire clk_audio = (AUDIO_IF == 0) ? clk_27m : clk_12m288;

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
    wire show_timbre;
    wire [1:0] timbre_preset;
    instrument_controls #(.CLK_HZ(AUDIO_CLK_HZ)) u_controls (
        .clk(clk_audio), .por(por), .rst(rst), .key_s1(key_s1), .key_s2(key_s2),
        .timbre_valid(uart_timbre_valid), .timbre_value(uart_timbre_value),
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

    // [S2-AI-BEGIN] GPIO 手动来源：同步/消抖后的琴键事件进入 16 项手动 FIFO。
    // gpio_keyboard 在没有 ready 时把事件留在自己的每键队列里，因此这里不会丢事件。
    // 优先级定为：清理（Panic/模式切换）> 首事件暂存 > UART > GPIO 手动 FIFO > 演示 FIFO。
    wire        gp_ev_valid, gp_ev_on, gp_ev_ready;
    wire [6:0]  gp_ev_note;
    wire [7:0]  gp_ev_vel;
    wire        man_empty, man_ready;
    wire [15:0] man_data;
    wire        man_rd;

    // X 全松键与 D1/D0 模式切换时，丢弃未发送的手动事件并重新武装琴键：
    // 已经按住的键必须松开再按才会重新起音。这里不能直接用 clear_events 驱动，
    // 否则由 GPIO 触发的那次“退出演示”会把首个按键事件一起清掉。
    wire manual_flush = uart_panic || uart_demo_on || uart_demo_off;

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
        .key_pressed()          // 预留：后续可用于琴键指示 LED 或 GAO 观察
    );

    reg         demo_mode;
    reg         pending_valid;
    reg [15:0]  pending_word;

    // 演示模式期间只接收按键（Note On）事件：进入演示时已经清空声部，
    // 此时松键没有可关闭的音符，若把它排进队列，还会挡住后面真正的按键事件。
    wire man_wr = gp_ev_valid && !(demo_mode && !gp_ev_on);

    event_fifo u_manual (
        .clk     (clk_audio),
        .rst     (rst | manual_flush),
        .wr_en   (man_wr),
        .wr_data ({gp_ev_on, gp_ev_note, gp_ev_vel}),
        .rd_en   (man_rd),
        .rd_data (man_data),
        .empty   (man_empty),
        .full    (),
        .wr_ready(gp_ev_ready)
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
                               manual_transition || uart_panic || (restart && demo_mode);

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
        .timbre_valid (uart_timbre_valid), .timbre_value (uart_timbre_value)
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
    wire [3:0]  v_gate;
    wire [27:0] v_note;      // 4 x 7 bit
    wire [31:0] v_vel;       // 4 x 8 bit
    wire [3:0]  v_idle;
    wire [3:0]  v_start;

    voice_alloc u_alloc (
        .clk        (clk_audio),
        .rst        (rst),
        .ev_valid   (ev_valid),
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
    wire [31:0] inc0, inc1, inc2, inc3;

    note_phase_inc #(.FS_HZ(AUDIO_FS_HZ)) u_inc0 (.note(v_note[6:0]),   .inc(inc0));
    note_phase_inc #(.FS_HZ(AUDIO_FS_HZ)) u_inc1 (.note(v_note[13:7]),  .inc(inc1));
    note_phase_inc #(.FS_HZ(AUDIO_FS_HZ)) u_inc2 (.note(v_note[20:14]), .inc(inc2));
    note_phase_inc #(.FS_HZ(AUDIO_FS_HZ)) u_inc3 (.note(v_note[27:21]), .inc(inc3));

    // ------------------------------------------- [S4/S5] ADC 控制路径 ---
    // 2 kHz 控制节拍，分频数按当前主时钟推导：调试档 27 MHz / 13 500 = 2 kHz，
    // 标准档 12.288 MHz / 6 144 = 2 kHz。一次 ADC 事务约 76 us（19 拍 SCLK 周期），
    // 短于节拍周期，因此 SPI 不会阻塞音频帧；压力与弯音只在节拍上更新。
    reg [15:0] ctrl_div = 16'd0;
    reg        control_tick = 1'b0;
    always @(posedge clk_audio) begin
        if (ctrl_div == (CTRL_TICK_DIV - 1)) begin
            ctrl_div     <= 16'd0;
            control_tick <= 1'b1;
        end else begin
            ctrl_div     <= ctrl_div + 1'b1;
            control_tick <= 1'b0;
        end
    end

    // CH0 = 压力 FSR，CH1 = 弯音电位器；空闲时按节拍轮流发起。
    // 显式 1 位通道选择：写成 ~adc_channel[0] 会被上下文补成 3 位（得到 6/7），
    // 这是本仓库第三次遇到 Verilog 上下文位宽坑，故用独立 1 位寄存器。
    reg         adc_sel      = 1'b0;      // 0 = 压力 CH0, 1 = 弯音 CH1
    reg         adc_start    = 1'b0;
    reg  [11:0] pressure_raw = 12'd2048;
    reg  [11:0] bend_raw     = 12'd2048;
    wire        adc_busy;
    wire        adc_done;
    wire        adc_valid;
    wire [11:0] adc_data;

    always @(posedge clk_audio) begin
        adc_start <= 1'b0;
        if (control_tick && !adc_busy) begin
            adc_start   <= 1'b1;
            adc_sel     <= ~adc_sel;
        end
        if (adc_done) begin
            if (adc_sel) bend_raw     <= adc_data;
            else                pressure_raw <= adc_data;
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

    pressure_bend u_bend (
        .clk (clk_audio), .rst (rst), .control_tick (control_tick),
        .pressure_adc (pressure_raw), .bend_adc (bend_raw),
        .pressure_enable (1'b1), .base_phase_inc (inc0),
        .pressure_filtered (pressure_filtered), .pressure_level (pressure_level),
        .bend_q8 (bend_q8), .bend_ratio_q16 (bend_ratio_q16),
        .phase_inc_out (bend_inc0)
    );

    // ----------------------------------------------------------- voices ---
    // [S6] 双波表声部：相位增量先按弯音比率缩放（声部 0 用上面的输出，其余各一次乘法）。
    // 显式加宽再截断，避免依赖工具对乘积宽度的上下文推断（同 S5 的修正口径）。
    wire [48:0] bend_mul1 = {17'd0, inc1} * {32'd0, bend_ratio_q16};
    wire [48:0] bend_mul2 = {17'd0, inc2} * {32'd0, bend_ratio_q16};
    wire [48:0] bend_mul3 = {17'd0, inc3} * {32'd0, bend_ratio_q16};
    wire [31:0] bend_inc1 = bend_mul1 >> 16;
    wire [31:0] bend_inc2 = bend_mul2 >> 16;
    wire [31:0] bend_inc3 = bend_mul3 >> 16;
    // 音色目标由 S1/串口设置，global_crossfade 在帧边界平滑更新。

    // [S6 共享引擎] 包络留在顶层（每声部一个 adsr），振荡/插值/混合交给共享引擎
    // 时分复用：整机 2 个 pROM、一组共享乘法器、交叉混合全局一次。
    wire [15:0] v_env0, v_env1, v_env2, v_env3;

    // 与 poly_voice_s6 相同的“start 暂存到 sample_tick”口径，避免事件不对齐采样点。
    reg  [3:0] v_pending = 4'd0;
    always @(posedge clk_audio) begin
        if (rst)
            v_pending <= 4'd0;
        else if (sample_tick)
            v_pending <= 4'd0;
        else
            v_pending <= v_pending | v_start;
    end
    wire [3:0] v_retrig = v_gate & (v_start | v_pending);

    adsr u_env0 (
        .clk (clk_audio), .rst (rst), .sample_tick (sample_tick),
        .gate (v_gate[0]), .retrigger (v_retrig[0]), .env (v_env0), .idle (v_idle[0])
    );
    adsr u_env1 (
        .clk (clk_audio), .rst (rst), .sample_tick (sample_tick),
        .gate (v_gate[1]), .retrigger (v_retrig[1]), .env (v_env1), .idle (v_idle[1])
    );
    adsr u_env2 (
        .clk (clk_audio), .rst (rst), .sample_tick (sample_tick),
        .gate (v_gate[2]), .retrigger (v_retrig[2]), .env (v_env2), .idle (v_idle[2])
    );
    adsr u_env3 (
        .clk (clk_audio), .rst (rst), .sample_tick (sample_tick),
        .gate (v_gate[3]), .retrigger (v_retrig[3]), .env (v_env3), .idle (v_idle[3])
    );

    wire signed [18:0] sine_sum, bright_sum;
    wire               sums_valid;

    shared_wavetable_engine u_engine (
        .clk (clk_audio), .rst (rst), .sample_tick (sample_tick),
        .inc0 (bend_inc0), .inc1 (bend_inc1), .inc2 (bend_inc2), .inc3 (bend_inc3),
        .retrig0 (v_retrig[0]), .retrig1 (v_retrig[1]),
        .retrig2 (v_retrig[2]), .retrig3 (v_retrig[3]),
        .env0 (v_env0), .env1 (v_env1), .env2 (v_env2), .env3 (v_env3),
        .vel0 (v_vel[7:0]), .vel1 (v_vel[15:8]), .vel2 (v_vel[23:16]), .vel3 (v_vel[31:24]),
        .sine_sum (sine_sum), .bright_sum (bright_sum), .sums_valid (sums_valid)
    );

    wire signed [15:0] mixed_shared;
    wire [31:0] xf_clip_count;
    wire        xf_clip_event;

    global_crossfade #(
        .CLIP_COUNTER_WIDTH(32), .PRESSURE_GAIN_ENABLE(PRESSURE_ENABLE),
        .PRESSURE_ADC_LOW(PRESSURE_ADC_LOW), .PRESSURE_ADC_FULL(PRESSURE_ADC_FULL),
        .PRESSURE_MIN_GAIN_Q12(PRESSURE_MIN_GAIN_Q12),
        .PRESSURE_GAIN_STEP(PRESSURE_GAIN_STEP), .TIMBRE_SLEW_ENABLE(1)
    ) u_xf (
        .clk (clk_audio), .rst (rst), .update (sums_valid), .clear_clip (1'b0),
        .mix_weight (timbre_target),
        .sine_sum (sine_sum), .bright_sum (bright_sum), .sample_out (mixed_shared),
        .clip_count (xf_clip_count), .clip_event (xf_clip_event),
        .pressure_enable (!demo_mode), .pressure_level (pressure_level)
    );

    // ------------------------------------------------------------ mixer ---
    // [S6 共享引擎] 逐声部的 mixer_s6 四路求和与 VOLUME_SHIFT=1 主增益已经由
    // global_crossfade 接管：交叉混合与“除以 2”在同一处各做一次，削波统计也在
    // 同一个主增益边界上计数，不会重复计数。mixer_s6 与它的 (1,4,6,4,1) FIR 仍
    // 留在库里并由 tb_s6_audio 覆盖，产品顶层不再实例化：顶层再串一级只会多出
    // 一拍延迟和一份死逻辑。FIR 仍然旁路，启用会把 10 kHz 压到约 -8.5 dB，
    // 音频验收基线要重做。
    wire signed [15:0] mixed;
    assign mixed = mixed_shared;

    // 把削波计数与压力/弯音观测值折成 4 位，避免综合把未接引脚的通路裁掉。
    wire [3:0] fold_clip = xf_clip_count[31:28] ^ xf_clip_count[27:24] ^ xf_clip_count[23:20] ^
                           xf_clip_count[19:16] ^ xf_clip_count[15:12] ^ xf_clip_count[11:8] ^
                           xf_clip_count[7:4] ^ xf_clip_count[3:0] ^ {3'd0, xf_clip_event};
    wire [3:0] fold_pressure = pressure_level[11:8] ^ pressure_level[7:4] ^ pressure_level[3:0] ^
                               pressure_filtered[11:8] ^ pressure_filtered[7:4] ^ pressure_filtered[3:0];
    wire [3:0] fold_bend = bend_q8[15:12] ^ bend_q8[11:8] ^ bend_q8[7:4] ^ bend_q8[3:0] ^
                           {2'b00, adc_busy, adc_valid};
    assign clip_fold = fold_clip ^ fold_pressure ^ fold_bend;

    // M0 只把送入 DAC 的数字采样置零，不切断 pa_en，也不停止声部/曲目计时。
    // 静音仍有噪声时应继续检查供电、接地、DAC/耳放模拟路径。
    wire signed [15:0] final_sample = (rst | uart_muted) ? 16'sd0 : mixed;

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
            // 合成链本身是 16 位样值。槽宽 24 位时把样值放到高 16 位、低 8 位补零，
            // 帧格式满足 24 位槽（赛题要求 48 kHz/24 位/64 BCK），但有效位深仍是 16 位，
            // 不据此宣称已经具备 24 位合成精度；真正的 24 位数据通路属于后续工作。
            wire signed [23:0] audio_24 = {final_sample, 8'b0};

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
