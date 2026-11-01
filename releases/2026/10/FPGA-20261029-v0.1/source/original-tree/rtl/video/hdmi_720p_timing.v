// 1024x600 compatibility timing, 51.3 MHz / (1344*635) = 60.1097 Hz.
// CEA-861 1280x720@60 timing. Pixel clock is 74.25 MHz, 5x serial clock
// is 371.25 MHz. Sync pulses are positive.
module hdmi_720p_timing (
    input  wire        pix_clk,
    input  wire        rst,       // active high
    output reg         hsync,
    output reg         vsync,
    output reg         de,
    output reg  [10:0] x,
    output reg  [9:0]  y,
    output reg         frame_start
);
    localparam integer H_SYNC   = 20;
    localparam integer H_BACK   = 140;
    localparam integer H_ACTIVE = 1024;
    localparam integer H_FRONT  = 160;
    localparam integer H_TOTAL  = 1344;

    localparam integer V_SYNC   = 3;
    localparam integer V_BACK   = 20;
    localparam integer V_ACTIVE = 600;
    localparam integer V_FRONT  = 12;
    localparam integer V_TOTAL  = 635;

    reg [10:0] h_count;
    reg [9:0]  v_count;

    always @(posedge pix_clk) begin
        if (rst) begin
            h_count     <= 11'd0;
            v_count     <= 10'd0;
            hsync       <= 1'b1;
            vsync       <= 1'b1;
            de          <= 1'b0;
            x           <= 11'd0;
            y           <= 10'd0;
            frame_start <= 1'b0;
        end else begin
            frame_start <= 1'b0;
            if (h_count == H_TOTAL-1) begin
                h_count <= 11'd0;
                if (v_count == V_TOTAL-1) begin
                    v_count     <= 10'd0;
                    frame_start <= 1'b1;
                end else begin
                    v_count <= v_count + 1'b1;
                end
            end else begin
                h_count <= h_count + 1'b1;
            end

            hsync <= (h_count < H_SYNC);
            vsync <= (v_count < V_SYNC);
            de    <= (h_count >= H_SYNC + H_BACK) &&
                     (h_count <  H_SYNC + H_BACK + H_ACTIVE) &&
                     (v_count >= V_SYNC + V_BACK) &&
                     (v_count <  V_SYNC + V_BACK + V_ACTIVE);
            x <= (h_count >= H_SYNC + H_BACK) ? h_count - (H_SYNC + H_BACK) : 11'd0;
            y <= (v_count >= V_SYNC + V_BACK) ? v_count - (V_SYNC + V_BACK) : 10'd0;
        end
    end

`ifdef SIMULATION
    initial begin
        if ((H_TOTAL != 1344) || (V_TOTAL != 635) || (H_ACTIVE != 1024) || (V_ACTIVE != 600))
            $fatal(1, "HDMI_720P_TIMING_PARAM_INVALID");
    end
`endif
endmodule
