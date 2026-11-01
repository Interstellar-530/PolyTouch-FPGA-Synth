// PT8211 debug DAC transmitter for the Dock 3714 on-board audio path.
// 27 MHz in, BCK = 27/18 = 1.5 MHz, one 32-BCK frame = 46.875 kHz sample rate.
//
// The bit/word layout follows the Sipeed / Gowin vendor example
// (TangPrimer-20K-example, PT8211/src/pt8211_drive.v): the frame counter b_cnt
// runs 0..31, a new word is requested at b_cnt 0 and 16, and WS is placed at
// b_cnt 3 (low) and b_cnt 19 (high). PT8211 is the "Japanese" right-justified
// format, so this WS offset is what the DAC expects. A plain 15/31 WS toggle
// is one bit out of phase; the DAC then samples the word with the wrong sign
// bit and the result is heard as heavy distortion on top of the tone.
//
// Difference from the vendor example: DIN and WS are updated on the BCK
// falling edge instead of the rising edge. The DAC still samples on the BCK
// rising edge, so it sees the same vendor sequence, but with about half a BCK
// period of setup time instead of zero.
//
// The production audio path is still standard I2S to the external PCM5102A;
// this module only drives the on-board PT8211 debug jack.
module pt8211_tx (
    input  wire               clk,
    input  wire               rst,
    input  wire signed [15:0] sample_in,
    output reg                bck,
    output reg                ws,
    output reg                din,
    output reg                sample_tick
);

    reg [3:0]  div_cnt;     // 0..8, nine 27 MHz cycles per BCK half period
    reg [4:0]  b_cnt;       // 0..31, incremented once per BCK
    reg        req_r;       // word request, one BCK wide
    reg        req_r1;      // req_r delayed by one BCK
    reg [15:0] idata_r;     // serialiser shift register
    reg [15:0] frame_data;  // hold register so both channels see one sample

    wire bck_falling = (div_cnt == 4'd8) && bck;

    always @(posedge clk) begin
        if (rst) begin
            div_cnt     <= 4'd0;
            bck         <= 1'b0;
            b_cnt       <= 5'd0;
            req_r       <= 1'b0;
            req_r1      <= 1'b0;
            idata_r     <= 16'd0;
            frame_data  <= 16'd0;
            ws          <= 1'b0;
            din         <= 1'b0;
            sample_tick <= 1'b0;
        end else begin
            sample_tick <= 1'b0;

            if (div_cnt == 4'd8) begin
                div_cnt <= 4'd0;
                bck     <= ~bck;
            end else begin
                div_cnt <= div_cnt + 1'b1;
            end

            if (bck_falling) begin
                b_cnt <= b_cnt + 1'b1;

                // Vendor word framing: request at b_cnt 0 and 16, load the
                // held sample one BCK later, present its MSB on the next BCK.
                req_r   <= (b_cnt == 5'd0) || (b_cnt == 5'd16);
                req_r1  <= req_r;
                idata_r <= req_r1 ? frame_data : {idata_r[14:0], 1'b0};
                din     <= idata_r[15];

                // Vendor word select placement.
                if (b_cnt == 5'd3)
                    ws <= 1'b0;
                else if (b_cnt == 5'd19)
                    ws <= 1'b1;

                // Frame boundary: latch one sample for both channels and
                // advance the oscillator once per frame.
                if (b_cnt == 5'd31) begin
                    frame_data  <= sample_in;
                    sample_tick <= 1'b1;
                end
            end
        end
    end

endmodule

