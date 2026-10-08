// PT8211 debug DAC transmitter for the Dock 3714 on-board audio path.
// The board provides 27 MHz. BCK is approximately 1.5 MHz and WS is
// approximately 46.875 kHz in this first bring-up build. The standard I2S
// PCM5102A path will use an external 12.288 MHz source after pin confirmation.
module pt8211_tx (
    input  wire               clk,
    input  wire               rst,
    input  wire signed [15:0] sample_in,
    output reg                bck,
    output reg                ws,
    output reg                din,
    output reg                sample_tick
);

    reg [4:0]  div_cnt;
    reg [4:0]  bit_cnt;
    reg [15:0] shift_reg;

    always @(posedge clk) begin
        if (rst) begin
            div_cnt    <= 5'd0;
            bit_cnt    <= 5'd0;
            bck        <= 1'b0;
            ws         <= 1'b0;
            din        <= 1'b0;
            shift_reg  <= 16'd0;
            sample_tick <= 1'b0;
        end else begin
            sample_tick <= 1'b0;

            if (div_cnt == 5'd8) begin
                div_cnt <= 5'd0;

                if (bck) begin
                    // Falling BCK edge: present the current MSB and shift.
                    din       <= shift_reg[15];
                    shift_reg <= {shift_reg[14:0], 1'b0};

                    if (bit_cnt == 5'd15) begin
                        // End of the first channel: toggle WS and load
                        // the second channel. Both channels carry the same
                        // mono sample in this bring-up build.
                        ws        <= ~ws;
                        shift_reg <= sample_in;
                        bit_cnt   <= bit_cnt + 1'b1;
                    end else if (bit_cnt == 5'd31) begin
                        // End of the second channel: toggle WS and start
                        // the next stereo frame.
                        bit_cnt    <= 5'd0;
                        ws         <= ~ws;
                        shift_reg  <= sample_in;
                        sample_tick <= 1'b1;
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end

                bck <= ~bck;
            end else begin
                div_cnt <= div_cnt + 1'b1;
            end
        end
    end

endmodule