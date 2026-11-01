// MCP3208 SPI mode-0 master, Microchip DS21298E frame.
//
// One start request transfers the complete 19-clock MCP3208 conversion frame:
//   clock 1..5   DIN  START, SGL/DIFF=1, D2..D0   (channel latched at start)
//   clock 6      DIN  "don't care"; the device ends its sample/hold period on
//                    this falling edge and starts driving the null bit
//   clock 7      DOUT null bit, ignored by this master
//   clock 8..19  DOUT B11..B0, MSB first, latched here on the rising edges
// The device drives DOUT on falling edges and the master latches on rising
// edges, so the first data bit is the 8th rising edge after CS falls and the
// last one is the 19th.  Reading only 18 clocks (as an earlier revision did)
// returns every code shifted right by one bit with B0 lost.
//
// The engine runs from clk and owns an independent SPI clock; it never waits
// for sample_tick or stretches the audio/I2S path.  `done`/`data_valid` are
// one-clock pulses raised together with CS returning high, and `data` is
// loaded at that same edge, so the held code only changes after the complete
// frame.  `adc_data` is an alias of the same hold register.
module mcp3208_spi #(
    parameter integer CLK_HZ = 27_000_000,
    parameter integer SPI_HZ = 250_000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [2:0]  channel,
    input  wire        miso,
    output reg         cs_n,
    output reg         sclk,
    output reg         mosi,
    output reg         busy,
    output reg         done,
    output reg  [11:0] data,
    output wire        data_valid,
    output wire [11:0] adc_data
);

    // Round to the nearest integer and keep a legal minimum of one clk.
    // SPI_HZ below 1 Hz would divide by zero during elaboration; the guard
    // turns such a parameter set into the slowest legal divider instead.
    localparam integer SPI_HZ_GUARD = (SPI_HZ < 1) ? 1 : SPI_HZ;
    localparam integer HALF_DIV_CALC = (CLK_HZ + SPI_HZ_GUARD) /
                                       (SPI_HZ_GUARD * 2);
    localparam integer HALF_DIV = (HALF_DIV_CALC < 1) ? 1 : HALF_DIV_CALC;

    localparam integer LAST_BIT = 18;       // 19 clocks, index 0..18
    localparam integer FIRST_DATA_BIT = 7;  // clock 8 carries B11

    reg [31:0] div_count;
    reg [4:0]  bit_index;       // 0..18, current bit on the wire
    reg [11:0] rx_shift;
    reg [4:0]  tx_command;
    reg        last_rise;

    wire spi_half_tick = (div_count == HALF_DIV - 1);

    assign data_valid = done;
    assign adc_data   = data;

    // Command bit order is MSB first.  Clocks 6..19 are the null/data portion
    // and MOSI is held low there, which the device treats as "don't care".
    function command_bit;
        input [4:0] index;
        begin
            case (index)
                5'd0: command_bit = 1'b1;              // START
                5'd1: command_bit = 1'b1;              // single-ended
                5'd2: command_bit = tx_command[2];
                5'd3: command_bit = tx_command[1];
                5'd4: command_bit = tx_command[0];
                default: command_bit = 1'b0;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            cs_n       <= 1'b1;
            sclk       <= 1'b0;
            mosi       <= 1'b0;
            busy       <= 1'b0;
            done       <= 1'b0;
            data       <= 12'd0;
            div_count  <= 32'd0;
            bit_index  <= 5'd0;
            rx_shift   <= 12'd0;
            tx_command <= 5'd0;
            last_rise  <= 1'b0;
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
                    // Rising edge: the device has driven its bit on the
                    // previous falling edge, so latch MISO here.
                    sclk <= 1'b1;
                    if ((bit_index >= FIRST_DATA_BIT) && (bit_index <= LAST_BIT)) begin
                        rx_shift <= {rx_shift[10:0], miso};
                    end
                    last_rise <= (bit_index == LAST_BIT);
                end else begin
                    // Falling edge: finish the frame or prepare the next bit.
                    sclk <= 1'b0;
                    if (last_rise) begin
                        cs_n      <= 1'b1;
                        busy      <= 1'b0;
                        done      <= 1'b1;
                        data      <= rx_shift;   // commit only after clock 19
                        mosi      <= 1'b0;
                        last_rise <= 1'b0;
                    end else begin
                        bit_index <= bit_index + 1'b1;
                        mosi      <= command_bit(bit_index + 1'b1);
                    end
                end
            end else begin
                div_count <= div_count + 1'b1;
            end
        end
    end
endmodule