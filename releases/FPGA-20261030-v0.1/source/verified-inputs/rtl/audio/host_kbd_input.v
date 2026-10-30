// CH9350L 下位机串口输入封装：UART RX -> state-2 帧解析 -> 键位/移调/控制。
// kbd_tx 固定为高：下位机（SEL=1）只向上位机发帧，不要求 FPGA 回传；
// 保留该引脚便于将来接 LED 回传或握手，不在此模块内假装已实现。
//
// 断线策略 TIMEOUT_POLICY：
//   0 = strict   ：任何 WATCHDOG_MS 静默超时都清键（旧行为，兼容/硬件排查用）。
//   1 = idle-only：仅在无持键时接受静默超时，持键长按期间只依赖 0x86 拔出通知。
// 默认 idle-only 避免 CH9350L 长按期间不周期发帧时误清音；0x86 始终立即清键。
module host_kbd_input #(
    parameter integer CLK_HZ          = 27000000,
    parameter integer BAUD            = 115200,
    parameter integer WATCHDOG_MS     = 2000,
    parameter integer TIMEOUT_POLICY  = 1
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        kbd_rx,
    output wire        kbd_tx,
    input  wire        flush,
    output wire        ev_valid,
    output wire [15:0] ev_word,
    input  wire        ev_ready,
    output wire        panic,
    output wire        timbre_valid,
    output wire [7:0]  timbre_value,
    output wire        instr_toggle,
    output wire        mode_toggle,
    output wire        pause_toggle,
    output wire        vol_up,
    output wire        vol_down,
    output wire [6:0]  base_note,
    output wire [3:0]  held_count,
    output wire        overflow,
    output wire        link_timeout,
    output wire        device_notify,
    output wire        frame_valid
);
    wire [7:0] byte_data;
    wire       byte_valid, frame_error;

    kbd_uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
        .clk(clk), .rst(rst), .rx(kbd_rx),
        .data(byte_data), .valid(byte_valid), .frame_error(frame_error)
    );

    wire [63:0] report;
    wire        report_valid, frame_seen, heartbeat;
    wire        raw_link_timeout;

    ch9350_rx #(.CLK_HZ(CLK_HZ), .WATCHDOG_MS(WATCHDOG_MS)) u_parser (
        .clk(clk), .rst(rst),
        .byte_data(byte_data), .byte_valid(byte_valid), .frame_error(frame_error),
        .report(report), .report_valid(report_valid),
        .frame_seen(frame_seen), .device_notify(device_notify),
        .heartbeat(heartbeat), .link_timeout(raw_link_timeout)
    );

    wire held_any = (held_count != 4'd0);
    wire timeout_action;

    // 未显式配置时回落到 idle-only，避免新增参数写错后重新引入长按误清音。
    assign timeout_action = (TIMEOUT_POLICY == 0) ? raw_link_timeout :
                            (raw_link_timeout && !held_any);

    hid_keymap u_map (
        .clk(clk), .rst(rst),
        .report_valid(report_valid), .report(report),
        .flush(flush), .link_timeout(timeout_action), .device_notify(device_notify),
        .ev_valid(ev_valid), .ev_word(ev_word), .ev_ready(ev_ready),
        .panic(panic), .timbre_valid(timbre_valid), .timbre_value(timbre_value),
        .instr_toggle(instr_toggle), .mode_toggle(mode_toggle),
        .pause_toggle(pause_toggle),
        .vol_up(vol_up), .vol_down(vol_down),
        .base_note(base_note), .held_count(held_count), .overflow(overflow)
    );

    assign kbd_tx       = 1'b1;
    assign frame_valid  = frame_seen;
    assign link_timeout = timeout_action;
endmodule
