// 115200 8N1 UART 接收器，按 CLK_HZ 推导分频。
// 27 MHz 时 DIV=234（实际 115 384 baud，误差 0.16%），采样点在起始位中心。
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
    localparam integer DIV  = (CLK_HZ + BAUD/2) / BAUD;
    localparam integer HALF = DIV / 2;
    localparam [1:0] S_IDLE = 2'd0, S_START = 2'd1, S_DATA = 2'd2, S_STOP = 2'd3;

    reg [1:0]  sync = 2'b11;
    always @(posedge clk) sync <= {sync[0], rx};
    wire rxs = sync[1];

    reg [1:0]  st = S_IDLE;
    reg [15:0] cnt = 16'd0;
    reg [2:0]  bidx = 3'd0;
    reg [7:0]  sh = 8'd0;

    always @(posedge clk) begin
        if (rst) begin
            st <= S_IDLE; cnt <= 16'd0; bidx <= 3'd0; sh <= 8'd0;
            data <= 8'd0; valid <= 1'b0; frame_error <= 1'b0;
        end else begin
            valid <= 1'b0;
            frame_error <= 1'b0;
            case (st)
                S_IDLE: if (!rxs) begin st <= S_START; cnt <= HALF - 1; end
                S_START: begin
                    if (cnt == 0) begin
                        if (!rxs) begin st <= S_DATA; cnt <= DIV - 1; bidx <= 3'd0; end
                        else st <= S_IDLE;
                    end else cnt <= cnt - 1'b1;
                end
                S_DATA: begin
                    if (cnt == 0) begin
                        sh[bidx] <= rxs;
                        if (bidx == 3'd7) begin st <= S_STOP; cnt <= DIV - 1; end
                        else begin bidx <= bidx + 1'b1; cnt <= DIV - 1; end
                    end else cnt <= cnt - 1'b1;
                end
                S_STOP: begin
                    if (cnt == 0) begin
                        if (rxs) begin data <= sh; valid <= 1'b1; end
                        else frame_error <= 1'b1;
                        st <= S_IDLE;
                    end else cnt <= cnt - 1'b1;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
