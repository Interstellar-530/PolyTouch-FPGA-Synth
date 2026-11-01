// HDMI dashboard top. Video is DVI/TMDS over the board HDMI connector; the
// dashboard itself carries no HDMI audio or infoframes.
module hdmi_dashboard #(parameter integer SAMPLE_RATE_48K = 0) (
    input  wire        clk_27m,
    input  wire        key_rst,       // active low
    input  wire [63:0] ui_status,
    input  wire        ui_status_toggle,
    input  wire [255:0] ui_waveform,
    input  wire [63:0]  ui_spectrum,
    input  wire [63:0]  ui_lissajous,
    input  wire         ui_visual_toggle,
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_data_p,
    output wire [2:0]  tmds_data_n
);
    wire serial_clk;
    wire pix_clk;
    wire pll_locked;
    wire pll_reset = ~key_rst;

    hdmi_clock u_hdmi_clock (
        .clk_27m(clk_27m), .reset(pll_reset),
        .serial_clk(serial_clk), .pix_clk(pix_clk), .locked(pll_locked)
    );

    reg [1:0] key_sync = 2'b11;
    reg [3:0] lock_pipe = 4'hF;
    always @(posedge pix_clk or negedge pll_locked) begin
        if (!pll_locked) begin
            key_sync  <= 2'b11;
            lock_pipe <= 4'hF;
        end else begin
            key_sync  <= {key_sync[0], key_rst};
            lock_pipe <= {lock_pipe[2:0], 1'b0};
        end
    end
    wire video_rst = lock_pipe[3] | ~key_sync[1];

    wire [63:0] pixel_status;
    wire        pixel_toggle_seen;
    ui_status_sync u_status (
        .clk(pix_clk), .rst(video_rst),
        .async_status(ui_status), .async_toggle(ui_status_toggle),
        .status(pixel_status), .toggle_seen(pixel_toggle_seen)
    );

    wire [255:0] pixel_waveform;
    wire [63:0]  pixel_spectrum;
    wire [63:0]  pixel_lissajous;
    wire         pixel_visual_seen;
    ui_visual_sync u_visual_sync (
        .clk(pix_clk), .rst(video_rst),
        .async_waveform(ui_waveform), .async_spectrum(ui_spectrum),
        .async_lissajous(ui_lissajous), .async_toggle(ui_visual_toggle),
        .waveform(pixel_waveform), .spectrum(pixel_spectrum),
        .lissajous(pixel_lissajous), .toggle_seen(pixel_visual_seen)
    );

    wire        hsync;
    wire        vsync;
    wire        de;
    wire [10:0] x;
    wire [9:0]  y;
    wire        frame_start;
    hdmi_720p_timing u_timing (
        .pix_clk(pix_clk), .rst(video_rst),
        .hsync(hsync), .vsync(vsync), .de(de), .x(x), .y(y),
        .frame_start(frame_start)
    );

    wire [7:0] pix_r;
    wire [7:0] pix_g;
    wire [7:0] pix_b;
    dashboard_renderer #(.SAMPLE_RATE_48K(SAMPLE_RATE_48K)) u_dashboard (
        .pix_clk(pix_clk), .rst(video_rst), .de(de), .x(x), .y(y),
        .st(pixel_status), .waveform(pixel_waveform),
        .spectrum(pixel_spectrum), .lissajous(pixel_lissajous),
        .rgb_r(pix_r), .rgb_g(pix_g), .rgb_b(pix_b)
    );

    // The renderer registers RGB one pixel after the timing inputs. Delay the
    // control signals by the same cycle so text and background remain aligned.
    reg de_d1, de_d2, de_d3, hs_d1, hs_d2, hs_d3, vs_d1, vs_d2, vs_d3;
    always @(posedge pix_clk) begin
        if (video_rst) begin
            de_d1 <= 1'b0; de_d2 <= 1'b0; de_d3 <= 1'b0;
            hs_d1 <= 1'b0; hs_d2 <= 1'b0; hs_d3 <= 1'b0;
            vs_d1 <= 1'b0; vs_d2 <= 1'b0; vs_d3 <= 1'b0;
        end else begin
            de_d1 <= de;     de_d2 <= de_d1; de_d3 <= de_d2;
            hs_d1 <= hsync;  hs_d2 <= hs_d1; hs_d3 <= hs_d2;
            vs_d1 <= vsync;  vs_d2 <= vs_d1; vs_d3 <= vs_d2;
        end
    end

    DVI_TX_Top u_dvi (
        .I_rst_n(~video_rst),
        .I_serial_clk(serial_clk),
        .I_rgb_clk(pix_clk),
        .I_rgb_vs(vs_d3),
        .I_rgb_hs(hs_d3),
        .I_rgb_de(de_d3),
        .I_rgb_r(pix_r),
        .I_rgb_g(pix_g),
        .I_rgb_b(pix_b),
        .O_tmds_clk_p(tmds_clk_p),
        .O_tmds_clk_n(tmds_clk_n),
        .O_tmds_data_p(tmds_data_p),
        .O_tmds_data_n(tmds_data_n)
    );
endmodule
