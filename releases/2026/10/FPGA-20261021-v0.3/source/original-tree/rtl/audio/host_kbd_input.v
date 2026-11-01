// CH9350L 下位机串口输入封装：UART RX -> state-2 帧解析 -> 键位/移调/控制。
// kbd_tx 固定为高：下位机（SEL=1）只向上位机发帧，不要求 FPGA 回传；
// 保留该引脚便于将来接 LED 回传或握手，不在此模块内假装已实现。
module host_kbd_input #(
    parameter integer CLK_HZ      = 27000000,
    parameter integer BAUD        = 115200,
    parameter integer WATCHDOG_MS = 2000
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

    ch9350_rx #(.CLK_HZ(CLK_HZ), .WATCHDOG_MS(WATCHDOG_MS)) u_parser (
        .clk(clk), .rst(rst),
        .byte_data(byte_data), .byte_valid(byte_valid), .frame_error(frame_error),
        .report(report), .report_valid(report_valid),
        .frame_seen(frame_seen), .device_notify(device_notify),
        .heartbeat(heartbeat), .link_timeout(link_timeout)
    );

    hid_keymap u_map (
        .clk(clk), .rst(rst),
        .report_valid(report_valid), .report(report),
        .flush(flush), .link_timeout(link_timeout), .device_notify(device_notify),
        .ev_valid(ev_valid), .ev_word(ev_word), .ev_ready(ev_ready),
        .panic(panic), .timbre_valid(timbre_valid), .timbre_value(timbre_value),
        .base_note(base_note), .held_count(held_count), .overflow(overflow)
    );

    assign kbd_tx      = 1'b1;
    assign frame_valid = frame_seen;
endmodule
