// Pin-level MCP3208 single-ended mode-0 model for RTL verification.
// The model samples the command on SCLK rising edges and changes MISO on
// falling edges, matching the device's setup/hold relationship.  A separate
// value can be supplied for every channel; no analog conversion is implied.
module mcp3208_model (
    input  wire       cs_n,
    input  wire       sclk,
    input  wire       mosi,
    output reg        miso,
    input  wire [11:0] ch0,
    input  wire [11:0] ch1,
    input  wire [11:0] ch2,
    input  wire [11:0] ch3,
    input  wire [11:0] ch4,
    input  wire [11:0] ch5,
    input  wire [11:0] ch6,
    input  wire [11:0] ch7
);
    reg [4:0] command;
    reg [4:0] rising_count;
    reg [11:0] response;

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

    always @(negedge cs_n) begin
        command      = 5'd0;
        rising_count = 5'd0;
        response     = 12'd0;
        miso         = 1'b0;
    end

    always @(posedge sclk) begin
        if (!cs_n) begin
            if (rising_count < 5)
                command[4-rising_count] = mosi;
            rising_count = rising_count + 1'b1;
            if (rising_count == 5)
                response = channel_value(command[2:0]);
        end
    end

    always @(negedge sclk) begin
        if (!cs_n) begin
            // Rising count 6 has just completed the null bit, so prepare
            // DATA[11] for the seventh rising edge.  Counts 6..17 therefore
            // select DATA[11:0] on the following edge.
            if ((rising_count >= 6) && (rising_count <= 17))
                miso = response[17-rising_count];
            else
                miso = 1'b0;
        end else begin
            miso = 1'b0;
        end
    end
endmodule
