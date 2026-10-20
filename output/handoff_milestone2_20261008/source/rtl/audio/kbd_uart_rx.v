// CH9350L 115200 8N1 byte receiver.
// The upper-level ch9350_rx parser needs a one-cycle frame_error pulse when
// the stop bit is low, so this block is intentionally separate from uart_ctrl.
module kbd_uart_rx #(
    parameter integer CLK_HZ = 27000000,
    parameter integer BAUD   = 115200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid,
    output reg        frame_error
);
    localparam integer BAUD_DIV  = (CLK_HZ + (BAUD / 2)) / BAUD;
    localparam integer BAUD_HALF = BAUD_DIV / 2;

    localparam [1:0] RX_IDLE  = 2'd0,
                     RX_START = 2'd1,
                     RX_DATA  = 2'd2,
                     RX_STOP  = 2'd3;

    reg [1:0]  rx_sync;
    reg [1:0]  state;
    reg [15:0] count;
    reg [2:0]  bit_index;
    reg [7:0]  shift;

    always @(posedge clk) begin
        if (rst) begin
            rx_sync     <= 2'b11;
            state       <= RX_IDLE;
            count       <= 16'd0;
            bit_index   <= 3'd0;
            shift       <= 8'd0;
            data        <= 8'd0;
            valid       <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            rx_sync <= {rx_sync[0], rx};
            valid <= 1'b0;
            frame_error <= 1'b0;
            case (state)
                RX_IDLE: begin
                    if (!rx_sync[1]) begin
                        count <= 16'd0;
                        state <= RX_START;
                    end
                end
                RX_START: begin
                    if (count == BAUD_HALF[15:0] - 16'd1) begin
                        count <= 16'd0;
                        if (!rx_sync[1]) begin
                            bit_index <= 3'd0;
                            state     <= RX_DATA;
                        end else begin
                            state <= RX_IDLE;
                        end
                    end else begin
                        count <= count + 1'b1;
                    end
                end
                RX_DATA: begin
                    if (count == BAUD_DIV[15:0] - 16'd1) begin
                        count <= 16'd0;
                        shift <= {rx_sync[1], shift[7:1]};
                        if (bit_index == 3'd7)
                            state <= RX_STOP;
                        else
                            bit_index <= bit_index + 1'b1;
                    end else begin
                        count <= count + 1'b1;
                    end
                end
                RX_STOP: begin
                    if (count == BAUD_DIV[15:0] - 16'd1) begin
                        count <= 16'd0;
                        state <= RX_IDLE;
                        data  <= shift;
                        if (rx_sync[1])
                            valid <= 1'b1;
                        else
                            frame_error <= 1'b1;
                    end else begin
                        count <= count + 1'b1;
                    end
                end
                default: state <= RX_IDLE;
            endcase
        end
    end
endmodule