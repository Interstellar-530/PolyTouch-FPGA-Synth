// 电脑演奏 ASCII 协议，默认 27 MHz / 115200、8N1；不是 USB MIDI 协议。
// Dock 的 BL702 仅作 USB-UART 桥：FPGA M11=TX，T13=RX，音频合成在 FPGA 中。
// ev_valid、panic、demo_on/off 均为 clk 单拍脉冲；没有事件 ready 或 RTS/CTS。
//
// 命令大小写均可，以 CR 或 LF 结束；空格/Tab 被忽略，单独换行无回复。
//   N<note> / O<note>：1..3 位十进制，范围 1..127；发音力度固定 DEFAULT_VEL。
//   X：无数字参数，全部松键（top 撤销 gate，包络正常释音）。
//   M0 / M1：恰好 1 位参数，数字静音/恢复；不停止曲目或切换演奏模式。
//   D0 / D1：恰好 1 位参数，手动等待/重启演示；N/O/X 的模式切换由 top 完成。
//   T<weight>：1..3 位十进制，范围 0..255；改变音色，不改变模式或音符。
// 每个有效命令排队回复 "OK\r\n"，格式错误回复 "ERR\r\n"；CRLF 不重复执行。
module uart_ctrl #(
    parameter integer CLK_HZ      = 27000000,
    parameter integer BAUD        = 115200,
    parameter [7:0]   DEFAULT_VEL = 8'd100
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       uart_rx,
    output wire       uart_tx,
    output reg        ev_valid,      // one clock pulse per accepted note event
    output reg        ev_on,
    output reg [6:0]  ev_note,
    output reg [7:0]  ev_vel,
    output reg        panic,         // one clock pulse, all notes off
    output reg        muted,
    output reg        demo_on,
    output reg        demo_off,
    output reg        timbre_valid,
    output reg [7:0]  timbre_value,
    output reg        instr_valid,
    output reg [1:0]  instr_id,
    output reg        vol_valid,
    output reg [6:0]  vol_value
);

    // 整数四舍五入分频，默认 234 个 clk/位；RX 先在半位确认起始位，再逐位采样。
    localparam integer BAUD_DIV  = (CLK_HZ + BAUD/2) / BAUD;
    localparam integer BAUD_HALF = BAUD_DIV / 2;

    // ---------------------------------------------------------------- RX ---
    reg [1:0] rx_sync; // 外部异步 RX 经两级同步；本版不另报停止位/帧错误
    always @(posedge clk)
        rx_sync <= {rx_sync[0], uart_rx};

    wire rx_line = rx_sync[1];

    localparam [2:0] RX_IDLE = 3'd0, RX_START = 3'd1, RX_DATA = 3'd2, RX_STOP = 3'd3;

    reg [2:0]  rx_state;
    reg [15:0] rx_cnt;
    reg [3:0]  rx_bit;
    reg [7:0]  rx_shift;
    reg [7:0]  rx_byte;
    reg        rx_valid;

    always @(posedge clk) begin
        if (rst) begin
            rx_state <= RX_IDLE;
            rx_cnt   <= 16'd0;
            rx_bit   <= 4'd0;
            rx_shift <= 8'd0;
            rx_byte  <= 8'd0;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            case (rx_state)
                RX_IDLE: if (!rx_line) begin
                    rx_cnt   <= 16'd0;
                    rx_state <= RX_START;
                end
                RX_START: begin
                    if (rx_cnt == BAUD_HALF[15:0]) begin
                        rx_cnt <= 16'd0;
                        if (!rx_line) begin
                            rx_bit   <= 4'd0;
                            rx_state <= RX_DATA;
                        end else begin
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_cnt <= rx_cnt + 1'b1;
                    end
                end
                RX_DATA: begin
                    if (rx_cnt == BAUD_DIV[15:0] - 16'd1) begin
                        rx_cnt   <= 16'd0;
                        rx_shift <= {rx_line, rx_shift[7:1]};
                        if (rx_bit == 4'd7)
                            rx_state <= RX_STOP;
                        else
                            rx_bit <= rx_bit + 1'b1;
                    end else begin
                        rx_cnt <= rx_cnt + 1'b1;
                    end
                end
                RX_STOP: begin
                    if (rx_cnt == BAUD_DIV[15:0] - 16'd1) begin
                        rx_cnt   <= 16'd0;
                        rx_state <= RX_IDLE;
                        rx_byte  <= rx_shift;
                        rx_valid <= 1'b1;
                    end else begin
                        rx_cnt <= rx_cnt + 1'b1;
                    end
                end
                default: rx_state <= RX_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------- parse ---
    localparam [2:0] CMD_NONE = 3'd0, CMD_NOTE = 3'd1,
                     CMD_MUTE = 3'd2, CMD_DEMO = 3'd3, CMD_TIMBRE = 3'd4, CMD_INSTR = 3'd5, CMD_VOL = 3'd6;

    reg [2:0]  cmd;
    reg [11:0] note_acc;
    reg [2:0]  digit_cnt; // 到 4 饱和：第 4 位即令行结束检查失败，避免超长数回绕
    reg        have_digit;
    reg        want_on;
    reg        have_panic;
    reg        invalid;
    reg        reply_ok;
    reg        reply_err;

    always @(posedge clk) begin
        if (rst) begin
            cmd        <= CMD_NONE;
            note_acc   <= 12'd0;
            digit_cnt  <= 3'd0;
            have_digit <= 1'b0;
            want_on    <= 1'b1;
            have_panic <= 1'b0;
            invalid    <= 1'b0;
            ev_valid   <= 1'b0;
            ev_on      <= 1'b1;
            ev_note    <= 7'd60;
            ev_vel     <= DEFAULT_VEL;
            panic      <= 1'b0;
            muted      <= 1'b0;
            demo_on    <= 1'b0;
            demo_off   <= 1'b0;
            timbre_valid <= 1'b0;
            timbre_value <= 8'd64;
            instr_valid <= 1'b0;
            instr_id <= 2'd0;
            vol_valid <= 1'b0;
            vol_value <= 7'd100;
            reply_ok   <= 1'b0;
            reply_err  <= 1'b0;
        end else begin
            // 默认清脉冲，在完整一行解析成功后才触发；主机应按行发送。
            ev_valid  <= 1'b0;
            panic     <= 1'b0;
            demo_on   <= 1'b0;
            demo_off  <= 1'b0;
            timbre_valid <= 1'b0;
            instr_valid <= 1'b0;
            vol_valid <= 1'b0;
            reply_ok  <= 1'b0;
            reply_err <= 1'b0;

            if (rx_valid) begin
                if ((rx_byte == 8'h0D) || (rx_byte == 8'h0A)) begin
                    if (!invalid && (cmd == CMD_NOTE) && have_digit &&
                        (digit_cnt <= 3'd3) &&
                        (note_acc >= 12'd1) && (note_acc <= 12'd127)) begin
                        ev_valid <= 1'b1;
                        ev_on    <= want_on;
                        ev_note  <= note_acc[6:0];
                        ev_vel   <= DEFAULT_VEL;
                        reply_ok <= 1'b1;
                    end else if (!invalid && (cmd == CMD_MUTE) &&
                                 (digit_cnt == 3'd1) && (note_acc <= 12'd1)) begin
                        muted    <= (note_acc == 12'd0);
                        reply_ok <= 1'b1;
                    end else if (!invalid && (cmd == CMD_DEMO) &&
                                 (digit_cnt == 3'd1) && (note_acc <= 12'd1)) begin
                        demo_on  <= (note_acc == 12'd1);
                        demo_off <= (note_acc == 12'd0);
                        reply_ok <= 1'b1;
                    end else if (!invalid && (cmd == CMD_TIMBRE) && have_digit &&
                                 (digit_cnt <= 3'd3) && (note_acc <= 12'd255)) begin
                        timbre_value <= note_acc[7:0];
                        timbre_valid <= 1'b1;
                        reply_ok <= 1'b1;
                    end else if (!invalid && (cmd == CMD_INSTR) &&
                                 (digit_cnt == 3'd1) && (note_acc <= 12'd1)) begin
                        instr_id <= note_acc[1:0];
                        instr_valid <= 1'b1;
                        reply_ok <= 1'b1;
                    end else if (!invalid && (cmd == CMD_VOL) &&
                                 (digit_cnt >= 3'd1) && (digit_cnt <= 3'd3) &&
                                 (note_acc <= 12'd100)) begin
                        vol_value <= note_acc[6:0];
                        vol_valid <= 1'b1;
                        reply_ok <= 1'b1;
                    end else if (!invalid && have_panic && (cmd == CMD_NONE)) begin
                        panic    <= 1'b1;
                        reply_ok <= 1'b1;
                    end else if (!invalid && (cmd == CMD_NONE) && !have_panic) begin
                        // bare newline: stay quiet
                    end else begin
                        reply_err <= 1'b1;
                    end
                    cmd        <= CMD_NONE;
                    have_digit <= 1'b0;
                    have_panic <= 1'b0;
                    invalid    <= 1'b0;
                    note_acc   <= 12'd0;
                    digit_cnt  <= 3'd0;
                end else if ((rx_byte == "N") || (rx_byte == "n")) begin
                    if ((cmd != CMD_NONE) || have_panic) invalid <= 1'b1;
                    cmd        <= CMD_NOTE;
                    want_on    <= 1'b1;
                    have_digit <= 1'b0;
                    note_acc   <= 12'd0;
                    digit_cnt  <= 3'd0;
                end else if ((rx_byte == "O") || (rx_byte == "o")) begin
                    if ((cmd != CMD_NONE) || have_panic) invalid <= 1'b1;
                    cmd        <= CMD_NOTE;
                    want_on    <= 1'b0;
                    have_digit <= 1'b0;
                    note_acc   <= 12'd0;
                    digit_cnt  <= 3'd0;
                end else if ((rx_byte == "X") || (rx_byte == "x")) begin
                    if ((cmd != CMD_NONE) || have_panic) invalid <= 1'b1;
                    have_panic <= 1'b1;
                end else if ((rx_byte == "M") || (rx_byte == "m")) begin
                    if ((cmd != CMD_NONE) || have_panic) invalid <= 1'b1;
                    cmd        <= CMD_MUTE;
                    have_digit <= 1'b0;
                    digit_cnt  <= 3'd0;
                end else if ((rx_byte == "D") || (rx_byte == "d")) begin
                    if ((cmd != CMD_NONE) || have_panic) invalid <= 1'b1;
                    cmd        <= CMD_DEMO;
                    have_digit <= 1'b0;
                    note_acc   <= 12'd0;
                    digit_cnt  <= 3'd0;
                end else if ((rx_byte == "T") || (rx_byte == "t")) begin
                    if ((cmd != CMD_NONE) || have_panic) invalid <= 1'b1;
                    cmd <= CMD_TIMBRE;
                    have_digit <= 1'b0; note_acc <= 12'd0; digit_cnt <= 3'd0;
                end else if ((rx_byte == "I") || (rx_byte == "i")) begin
                    if ((cmd != CMD_NONE) || have_panic) invalid <= 1'b1;
                    cmd <= CMD_INSTR;
                    have_digit <= 1'b0; note_acc <= 12'd0; digit_cnt <= 3'd0;
                end else if ((rx_byte == "V") || (rx_byte == "v")) begin
                    if ((cmd != CMD_NONE) || have_panic) invalid <= 1'b1;
                    cmd <= CMD_VOL;
                    have_digit <= 1'b0; note_acc <= 12'd0; digit_cnt <= 3'd0;
                end else if ((rx_byte >= "0") && (rx_byte <= "9")) begin
                    if (cmd != CMD_NONE) begin
                        if (digit_cnt < 3'd3)
                            note_acc <= (note_acc * 12'd10) + (rx_byte - "0");
                        if (digit_cnt < 3'd4) digit_cnt <= digit_cnt + 1'b1;
                        have_digit <= 1'b1;
                    end else invalid <= 1'b1;
                end else if ((rx_byte != " ") && (rx_byte != 8'h09)) begin
                    invalid <= 1'b1;
                end
            end
        end
    end

    // ---------------------------------------------------------------- TX ---
    reg  [9:0]  tx_sr;
    reg  [15:0] tx_cnt;
    reg  [3:0]  tx_bit;
    reg         tx_busy;
    reg  [7:0]  send_byte;
    reg         send_valid;

    assign uart_tx = tx_busy ? tx_sr[0] : 1'b1;

    always @(posedge clk) begin
        if (rst) begin
            tx_sr   <= 10'h3FF;
            tx_cnt  <= 16'd0;
            tx_bit  <= 4'd0;
            tx_busy <= 1'b0;
        end else if (!tx_busy) begin
            if (send_valid) begin
                tx_sr   <= {1'b1, send_byte, 1'b0};
                tx_cnt  <= 16'd0;
                tx_bit  <= 4'd0;
                tx_busy <= 1'b1;
            end
        end else begin
            if (tx_cnt == BAUD_DIV[15:0] - 16'd1) begin
                tx_cnt <= 16'd0;
                if (tx_bit == 4'd9)
                    tx_busy <= 1'b0;
                else begin
                    tx_bit <= tx_bit + 1'b1;
                    tx_sr  <= {1'b1, tx_sr[9:1]};
                end
            end else begin
                tx_cnt <= tx_cnt + 1'b1;
            end
        end
    end

    // -------------------------------------------------------- reply pump ---
    localparam [1:0] TX_IDLE = 2'd0, TX_SEND = 2'd1, TX_WAIT = 2'd2, TX_DONE = 2'd3;

    reg [1:0] msg_state;
    reg [2:0] msg_idx;
    reg       msg_err;
    // 队列存 16 个回复类型位（0=OK，1=ERR），另有一个正在发送的消息。
    // 发送比短命令执行慢，因此必须排队；满且同拍弹出时仍可接受新回复。
    reg [15:0] reply_queue;
    reg [3:0]  reply_wr_ptr, reply_rd_ptr;
    reg [4:0]  reply_count;
    reg [15:0] reply_drop_count; // 回复满时计数，到 65535 饱和；仅仿真/GAO 内部可见
    wire reply_push = reply_ok || reply_err;
    wire reply_pop  = (msg_state == TX_IDLE) && (reply_count != 0);
    wire reply_room = (reply_count != 5'd16) || reply_pop;

    wire [2:0] msg_len = msg_err ? 3'd5 : 3'd4;

    wire [7:0] msg_byte =
        msg_err ? (msg_idx == 3'd0 ? "E" :
                   msg_idx == 3'd1 ? "R" :
                   msg_idx == 3'd2 ? "R" :
                   msg_idx == 3'd3 ? 8'h0D : 8'h0A)
                : (msg_idx == 3'd0 ? "O" :
                   msg_idx == 3'd1 ? "K" :
                   msg_idx == 3'd2 ? 8'h0D : 8'h0A);

    always @(posedge clk) begin
        if (rst) begin
            msg_state  <= TX_IDLE;
            msg_idx    <= 3'd0;
            msg_err    <= 1'b0;
            reply_wr_ptr <= 4'd0;
            reply_rd_ptr <= 4'd0;
            reply_count <= 5'd0;
            reply_drop_count <= 16'd0;
            send_byte  <= 8'd0;
            send_valid <= 1'b0;
        end else begin
            // DROP 只丢回复，不回滚已经执行的音符/模式命令，也不会串口发送 DROP。
            // 无无限突发保证；主机以收到回复/合理限速推进，不能仅凭无回复判断未执行。
            if (reply_push && reply_room) begin
                reply_queue[reply_wr_ptr] <= reply_err;
                reply_wr_ptr <= reply_wr_ptr + 1'b1;
            end else if (reply_push && reply_drop_count != 16'hFFFF)
                reply_drop_count <= reply_drop_count + 1'b1;
            if (reply_pop)
                reply_rd_ptr <= reply_rd_ptr + 1'b1;
            case ({reply_push && reply_room, reply_pop})
                2'b10: reply_count <= reply_count + 1'b1;
                2'b01: reply_count <= reply_count - 1'b1;
                default: ;
            endcase
            case (msg_state)
                TX_IDLE: if (reply_pop) begin
                    msg_err   <= reply_queue[reply_rd_ptr];
                    msg_idx   <= 3'd0;
                    msg_state <= TX_SEND;
                end
                TX_SEND: if (!tx_busy) begin
                    send_byte  <= msg_byte;
                    send_valid <= 1'b1;
                    msg_state  <= TX_WAIT;
                end
                TX_WAIT: if (tx_busy) begin
                    send_valid <= 1'b0;
                    msg_state  <= TX_DONE;
                end
                TX_DONE: if (!tx_busy) begin
                    if (msg_idx == msg_len - 3'd1)
                        msg_state <= TX_IDLE;
                    else begin
                        msg_idx   <= msg_idx + 1'b1;
                        msg_state <= TX_SEND;
                    end
                end
                default: msg_state <= TX_IDLE;
            endcase
        end
    end

endmodule
