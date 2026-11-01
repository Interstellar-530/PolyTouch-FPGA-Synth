// UART note control for the PolyTouch instrument, 115200 8N1.
//
// The Dock routes the BL702 USB-UART bridge to the FPGA on M11 (TX) and
// T13 (RX).  This module is the second source on the shared note event bus and
// is what proves the keyboard interface before the MPR121 touch controller
// exists: it presents exactly the same {valid, on, note, velocity} signals
// that the touch controller will drive later.
//
// Commands, ASCII, terminated by CR or LF, case insensitive:
//   N<note>   note on,  note is a MIDI number 1 .. 127
//   O<note>   note off
//   X         all notes off
//   M0 / M1   mute / unmute the DAC output
// The module answers "OK\r\n" or "ERR\r\n" so the host can confirm the link
// without listening to the headphones.
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
    output reg        muted
);

    localparam integer BAUD_DIV  = (CLK_HZ + BAUD/2) / BAUD;
    localparam integer BAUD_HALF = BAUD_DIV / 2;

    // ---------------------------------------------------------------- RX ---
    reg [1:0] rx_sync;
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
    localparam [1:0] CMD_NONE = 2'd0, CMD_NOTE = 2'd1, CMD_MUTE = 2'd2;

    reg [1:0]  cmd;
    reg [7:0]  note_acc;
    reg [2:0]  digit_cnt;
    reg        have_digit;
    reg        want_on;
    reg        have_panic;
    reg        reply_ok;
    reg        reply_err;

    always @(posedge clk) begin
        if (rst) begin
            cmd        <= CMD_NONE;
            note_acc   <= 8'd0;
            digit_cnt  <= 3'd0;
            have_digit <= 1'b0;
            want_on    <= 1'b1;
            have_panic <= 1'b0;
            ev_valid   <= 1'b0;
            ev_on      <= 1'b1;
            ev_note    <= 7'd60;
            ev_vel     <= DEFAULT_VEL;
            panic      <= 1'b0;
            muted      <= 1'b0;
            reply_ok   <= 1'b0;
            reply_err  <= 1'b0;
        end else begin
            ev_valid  <= 1'b0;
            panic     <= 1'b0;
            reply_ok  <= 1'b0;
            reply_err <= 1'b0;

            if (rx_valid) begin
                if ((rx_byte == 8'h0D) || (rx_byte == 8'h0A)) begin
                    if ((cmd == CMD_NOTE) && have_digit &&
                        (note_acc >= 8'd1) && (note_acc <= 8'd127)) begin
                        ev_valid <= 1'b1;
                        ev_on    <= want_on;
                        ev_note  <= note_acc[6:0];
                        ev_vel   <= DEFAULT_VEL;
                        reply_ok <= 1'b1;
                    end else if ((cmd == CMD_MUTE) && have_digit) begin
                        muted    <= (note_acc == 8'd0);
                        reply_ok <= 1'b1;
                    end else if (have_panic) begin
                        panic    <= 1'b1;
                        reply_ok <= 1'b1;
                    end else if (cmd == CMD_NONE) begin
                        // bare newline: stay quiet
                    end else begin
                        reply_err <= 1'b1;
                    end
                    cmd        <= CMD_NONE;
                    have_digit <= 1'b0;
                    have_panic <= 1'b0;
                    note_acc   <= 8'd0;
                    digit_cnt  <= 3'd0;
                end else if ((rx_byte == "N") || (rx_byte == "n")) begin
                    cmd        <= CMD_NOTE;
                    want_on    <= 1'b1;
                    have_digit <= 1'b0;
                    note_acc   <= 8'd0;
                    digit_cnt  <= 3'd0;
                end else if ((rx_byte == "O") || (rx_byte == "o")) begin
                    cmd        <= CMD_NOTE;
                    want_on    <= 1'b0;
                    have_digit <= 1'b0;
                    note_acc   <= 8'd0;
                    digit_cnt  <= 3'd0;
                end else if ((rx_byte == "X") || (rx_byte == "x")) begin
                    have_panic <= 1'b1;
                end else if ((rx_byte == "M") || (rx_byte == "m")) begin
                    cmd        <= CMD_MUTE;
                    have_digit <= 1'b0;
                    digit_cnt  <= 3'd0;
                end else if ((rx_byte >= "0") && (rx_byte <= "9")) begin
                    if (cmd != CMD_NONE) begin
                        if (digit_cnt < 3'd3)
                            note_acc <= (note_acc * 8'd10) + (rx_byte - "0");
                        digit_cnt  <= digit_cnt + 1'b1;
                        have_digit <= 1'b1;
                    end
                end else if ((rx_byte != " ") && (rx_byte != 8'h09)) begin
                    cmd        <= CMD_NONE;
                    have_digit <= 1'b0;
                    have_panic <= 1'b0;
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
            send_byte  <= 8'd0;
            send_valid <= 1'b0;
        end else begin
            case (msg_state)
                TX_IDLE: if (reply_ok || reply_err) begin
                    msg_err   <= reply_err;
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
