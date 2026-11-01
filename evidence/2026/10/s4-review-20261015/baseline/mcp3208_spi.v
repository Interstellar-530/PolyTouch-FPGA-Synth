// MCP3208 SPI mode-0 master.
//
// One request transfers the complete 18-bit MCP3208 command/data frame:
//   START, SGL/DIFF=1, D2..D0, NULL, DATA[11:0].
// The engine runs from clk and owns an independent SPI clock; it never waits
// for sample_tick or stretches the audio/I2S path.  `done`/`data_valid` are
// one-clock pulses after CS returns high and `data` is held until the next
// completed transaction.
module mcp3208_spi #(
    parameter integer CLK_HZ = 27_000_000,
    parameter integer SPI_HZ = 250_000
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [2:0] channel,
    input  wire       miso,
    output reg        cs_n,
    output reg        sclk,
    output reg        mosi,
    output reg        busy,
    output reg        done,
    output reg [11:0] data,
    output wire       data_valid,
    output wire [11:0] adc_data
);

    // Round to the nearest integer and keep a legal minimum of one clk.
    localparam integer HALF_DIV_CALC = (CLK_HZ + (SPI_HZ * 1)) /
                                       (SPI_HZ * 2);
    localparam integer HALF_DIV = (HALF_DIV_CALC < 1) ? 1 : HALF_DIV_CALC;

    reg [31:0] div_count;
    reg [4:0]  bit_index;       // 0..17, current bit on the wire
    reg [11:0] rx_shift;
    reg [4:0]  tx_command;
    reg        last_rise;

    wire spi_half_tick = (div_count == HALF_DIV - 1);

    assign data_valid = done;
    assign adc_data   = data;

    // Command bit order is MSB first.  Bits 5..17 are the null/data portion
    // and MOSI is held low there, as required by the MCP3208 protocol.
    function command_bit;
        input [4:0] index;
        begin
            case (index)
                5'd0: command_bit = 1'b1;              // START
                5'd1: command_bit = 1'b1;              // single-ended
                5'd2: command_bit = tx_command[2];
                5'd3: command_bit = tx_command[1];
                5'd4: command_bit = tx_command[0];
                default: command_bit = 1'b0;           // NULL + read data
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            cs_n      <= 1'b1;
            sclk      <= 1'b0;
            mosi      <= 1'b0;
            busy      <= 1'b0;
            done      <= 1'b0;
            data      <= 12'd0;
            div_count <= 32'd0;
            bit_index <= 5'd0;
            rx_shift  <= 12'd0;
            tx_command<= 5'd0;
            last_rise <= 1'b0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                cs_n      <= 1'b1;
                sclk      <= 1'b0;
                mosi      <= 1'b0;
                div_count <= 32'd0;
                if (start) begin
                    busy       <= 1'b1;
                    cs_n       <= 1'b0;
                    bit_index  <= 5'd0;
                    rx_shift   <= 12'd0;
                    tx_command <= channel;
                    // Present START before the first rising edge.
                    mosi       <= 1'b1;
                end
            end else if (spi_half_tick) begin
                div_count <= 32'd0;

                if (!sclk) begin
                    // Rising edge: the ADC changes no data in mode 0; sample
                    // MISO here after the master has presented the bit.
                    sclk <= 1'b1;
                    if ((bit_index >= 5'd6) && (bit_index <= 5'd17)) begin
                        if (bit_index == 5'd17)
                            data <= {rx_shift[10:0], miso};
                        rx_shift <= {rx_shift[10:0], miso};
                    end
                    last_rise <= (bit_index == 5'd17);
                end else begin
                    // Falling edge: finish the frame or prepare the next bit.
                    sclk <= 1'b0;
                    if (last_rise) begin
                        cs_n <= 1'b1;
                        busy <= 1'b0;
                        done <= 1'b1;
                        mosi <= 1'b0;
                        last_rise <= 1'b0;
                    end else begin
                        bit_index <= bit_index + 1'b1;
                        mosi <= command_bit(bit_index + 1'b1);
                    end
                end
            end else begin
                div_count <= div_count + 1'b1;
            end
        end
    end
endmodule
