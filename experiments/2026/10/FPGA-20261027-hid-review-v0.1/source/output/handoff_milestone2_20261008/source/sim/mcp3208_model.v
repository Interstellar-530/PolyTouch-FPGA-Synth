// Pin-level MCP3208 device model written from the Microchip MCP3204/3208
// datasheet (DS21298E, section 5.0 "Serial Communications" and Figure 6-1)
// so an RTL master is checked against the real device frame instead of
// against a copy of the master's own bit placement.
//
// Frame after CS falls:
//   * the start bit is the first SCLK rising edge with DIN high; leading zero
//     clocks before it are ignored by the device,
//   * DIN clocks 1..5   = START=1, SGL/DIFF=1, D2, D1, D0,
//   * DIN clock  6      = "don't care"; the sample/hold period ends on its
//     falling edge and the low null bit starts to be driven there,
//   * DOUT clock 7      = null bit (low),
//   * DOUT clocks 8..19 = B11..B0, MSB first.  The device drives DOUT on
//     falling edges, so the master latches B11 on the 8th rising edge and B0
//     on the 19th; a complete MSB-first read therefore needs 19 SCLK pulses.
// After B0 the model drives zeros.  The real device repeats the result LSB
// first and then zeroes indefinitely; no S4 test exercises that region.
module mcp3208_model (
    input  wire        cs_n,
    input  wire        sclk,
    input  wire        mosi,
    output reg         miso,
    input  wire [11:0] ch0,
    input  wire [11:0] ch1,
    input  wire [11:0] ch2,
    input  wire [11:0] ch3,
    input  wire [11:0] ch4,
    input  wire [11:0] ch5,
    input  wire [11:0] ch6,
    input  wire [11:0] ch7
);
    reg        started;     // start bit has been seen
    reg [4:0]  adc_clk;     // device clock index, 1 = start bit
    reg [2:0]  sel;         // channel latched from D2..D0
    reg [11:0] response;    // code supplied for the selected channel

    function [11:0] channel_value;
        input [2:0] ch;
        begin
            case (ch)
                3'd0: channel_value = ch0;
                3'd1: channel_value = ch1;
                3'd2: channel_value = ch2;
                3'd3: channel_value = ch3;
                3'd4: channel_value = ch4;
                3'd5: channel_value = ch5;
                3'd6: channel_value = ch6;
                default: channel_value = ch7;
            endcase
        end
    endfunction

    // CS rising resets the interface, including a frame that was interrupted
    // before its last clock.
    always @(negedge cs_n) begin
        started  = 1'b0;
        adc_clk  = 5'd0;
        sel      = 3'd0;
        response = 12'd0;
        miso     = 1'b0;
    end

    // DIN is latched on SCLK rising edges.
    always @(posedge sclk) begin
        if (!cs_n) begin
            if (!started) begin
                if (mosi) begin
                    started = 1'b1;
                    adc_clk = 5'd1;
                end
            end else begin
                adc_clk = adc_clk + 5'd1;
                case (adc_clk)
                    5'd3: sel[2] = mosi;
                    5'd4: sel[1] = mosi;
                    5'd5: begin
                        sel[0]   = mosi;
                        response = channel_value(sel);
                    end
                    default: ;                      // SGL/DIFF and "don't care"
                endcase
            end
        end
    end

    // DOUT changes on SCLK falling edges and is latched by the master on the
    // following rising edge: null bit on clock 7, B11..B0 on clocks 8..19.
    always @(negedge sclk) begin
        if (cs_n) begin
            miso = 1'b0;
        end else if ((adc_clk >= 5'd7) && (adc_clk <= 5'd18)) begin
            miso = response[5'd18 - adc_clk];
        end else begin
            miso = 1'b0;
        end
    end
endmodule