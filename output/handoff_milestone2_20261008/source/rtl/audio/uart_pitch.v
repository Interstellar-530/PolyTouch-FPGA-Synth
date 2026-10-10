// UART pitch control, 115200 8N1.
//
// The Dock routes the BL702 USB-UART bridge to the FPGA on N6 / N7:
//   N6 = BL702_UART1_TX  -> this module's uart_rx input
//   N7 = BL702_UART1_RX  -> this module's uart_tx output
// Those two nets are shared with the RGB LCD connector, so they are only free
// while no RGB panel is plugged in.
//
// Commands, ASCII, terminated by CR or LF, case insensitive:
//   F<number>   set the pitch in Hz, 16 .. 20000, for example "F440"
//   M0 / M1     mute / unmute the DAC output (audible-noise diagnosis)
// The module answers "OK\r\n" or "ERR\r\n" so the host can confirm the link
// without listening to the headphones.
//
// freq_to_phase_inc() is the whole point of this file: it turns a human
// frequency into the DDS frequency control word for the 46.875 kHz debug
// sample rate, so the host writes a real note frequency instead of a magic
// phase increment.
module uart_pitch #(
    parameter integer CLK_HZ   = 27000000,
    parameter integer BAUD     = 115200,
    parameter [15:0]  FREQ_MIN = 16'd16,
    parameter [15:0]  FREQ_MAX = 16'd20000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        uart_rx,
    output wire        uart_tx,
    output reg  [31:0] phase_inc,
    output reg  [15:0] freq_hz,
    output reg         muted,
    output reg         accepted          // one-clock pulse on a good command
);

    // fs = 27e6 / 18 / 32 = 46875 Hz, so the DDS control word is
    // freq * 2^32 / 46875 = freq * 91625.937. The integer constant below is
    // 0.0012 cent sharp, far below any audible threshold.
    function [31:0] freq_to_phase_inc;
        input [15:0] f;
        begin
            freq_to_phase_inc = f * 32'd91626;
        end
    endfunction

    localparam integer BAUD_DIV  = (CLK_HZ + BAUD/2) / BAUD;  // 234 at 115200
    localparam integer BAUD_HALF = BAUD_DIV / 2;

    // ---------------------------------------------------------------- RX ---
    reg [1:0] rx_sync;
    always @(posedge clk)
        rx_sync <= {rx_sync[0], uart_rx};

    wire rx_line = rx_sync[1];

    localparam [2:0] RX_IDLE = 3'd0,
                     RX_START = 3'd1,
                     RX_DATA = 3'd2,
                     RX_STOP = 3'd3;

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
    localparam [1:0] CMD_NONE = 2'd0, CMD_FREQ = 2'd1, CMD_MUTE = 2'd2;

    reg [1:0]  cmd;
    reg [15:0] freq_acc;
    reg [2:0]  digit_cnt;
    reg        have_digit;
    reg        have_mute;
    reg        mute_value;
    reg        reply_ok;
    reg        reply_err;

    always @(posedge clk) begin
        if (rst) begin
            cmd        <= CMD_NONE;
            freq_acc   <= 16'd0;
            digit_cnt  <= 3'd0;
            have_digit <= 1'b0;
            have_mute  <= 1'b0;
            mute_value <= 1'b0;
            phase_inc  <= freq_to_phase_inc(16'd440);
            freq_hz    <= 16'd440;
            muted      <= 1'b0;
            accepted   <= 1'b0;
            reply_ok   <= 1'b0;
            reply_err  <= 1'b0;
        end else begin
            accepted  <= 1'b0;
            reply_ok  <= 1'b0;
            reply_err <= 1'b0;

            if (rx_valid) begin
                if ((rx_byte == 8'h0D) || (rx_byte == 8'h0A)) begin
                    if ((cmd == CMD_FREQ) && have_digit &&
                        (freq_acc >= FREQ_MIN) && (freq_acc <= FREQ_MAX)) begin
                        phase_inc <= freq_to_phase_inc(freq_acc);
                        freq_hz   <= freq_acc;
                        accepted  <= 1'b1;
                        reply_ok  <= 1'b1;
                    end else if ((cmd == CMD_MUTE) && have_mute) begin
                        muted    <= mute_value;
                        accepted <= 1'b1;
                        reply_ok <= 1'b1;
                    end else if (cmd == CMD_NONE) begin
                        // bare newline: stay quiet
                    end else begin
                        reply_err <= 1'b1;
                    end
                    cmd        <= CMD_NONE;
                    have_digit <= 1'b0;
                    have_mute  <= 1'b0;
                    freq_acc   <= 16'd0;
                    digit_cnt  <= 3'd0;
                end else if ((rx_byte == "F") || (rx_byte == "f")) begin
                    cmd        <= CMD_FREQ;
                    have_digit <= 1'b0;
                    freq_acc   <= 16'd0;
                    digit_cnt  <= 3'd0;
                end else if ((rx_byte == "M") || (rx_byte == "m")) begin
                    cmd       <= CMD_MUTE;
                    have_mute <= 1'b0;
                end else if ((rx_byte >= "0") && (rx_byte <= "9")) begin
                    if (cmd == CMD_FREQ) begin
                        if (digit_cnt < 3'd5) begin
                            freq_acc  <= (freq_acc * 16'd10) + (rx_byte - "0");
                            digit_cnt <= digit_cnt + 1'b1;
                        end
                        have_digit <= 1'b1;
                    end else if (cmd == CMD_MUTE) begin
                        mute_value <= (rx_byte == "0");
                        have_mute  <= 1'b1;
                    end
                end else if ((rx_byte != " ") && (rx_byte != 8'h09)) begin
                    cmd <= CMD_NONE;      // unknown token, wait for a new line
                    have_digit <= 1'b0;
                    have_mute  <= 1'b0;
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
            tx_sr      <= 10'h3FF;
            tx_cnt     <= 16'd0;
            tx_bit     <= 4'd0;
            tx_busy    <= 1'b0;
        end else if (!tx_busy) begin
            if (send_valid) begin
                tx_sr      <= {1'b1, send_byte, 1'b0};
                tx_cnt     <= 16'd0;
                tx_bit     <= 4'd0;
                tx_busy    <= 1'b1;
            end
        end else begin
            if (tx_cnt == BAUD_DIV[15:0] - 16'd1) begin
                tx_cnt <= 16'd0;
                if (tx_bit == 4'd9) begin
                    tx_busy <= 1'b0;
                end else begin
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
            msg_state <= TX_IDLE;
            msg_idx   <= 3'd0;
            msg_err   <= 1'b0;
            send_byte <= 8'd0;
            send_valid <= 1'b0;
        end else begin
            case (msg_state)
                TX_IDLE: begin
                    if (reply_ok || reply_err) begin
                        msg_err   <= reply_err;
                        msg_idx   <= 3'd0;
                        msg_state <= TX_SEND;
                    end
                end
                TX_SEND: begin
                    if (!tx_busy) begin
                        send_byte  <= msg_byte;
                        send_valid <= 1'b1;
                        msg_state  <= TX_WAIT;
                    end
                end
                TX_WAIT: begin
                    if (tx_busy) begin
                        send_valid <= 1'b0;
                        msg_state  <= TX_DONE;
                    end
                end
                TX_DONE: begin
                    if (!tx_busy) begin
                        if (msg_idx == msg_len - 3'd1)
                            msg_state <= TX_IDLE;
                        else begin
                            msg_idx   <= msg_idx + 1'b1;
                            msg_state <= TX_SEND;
                        end
                    end
                end
                default: msg_state <= TX_IDLE;
            endcase
        end
    end

endmodule
