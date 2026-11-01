// Scanline dashboard renderer. It receives one pixel coordinate per clock and
// emits RGB directly; no frame buffer is required.
module dashboard_renderer #(
    parameter integer SAMPLE_RATE_48K = 0
) (
    input  wire        pix_clk,
    input  wire        rst,
    input  wire        de,
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire [63:0] st,
    input  wire [255:0] waveform,
    input  wire [63:0]  spectrum,
    input  wire [63:0]  lissajous,
    output reg  [7:0]  rgb_r,
    output reg  [7:0]  rgb_g,
    output reg  [7:0]  rgb_b
);
    localparam [23:0] BG       = 24'h090E1C;
    localparam [23:0] HEADER   = 24'h111B35;
    localparam [23:0] PANEL    = 24'h151F38;
    localparam [23:0] PANEL_2  = 24'h10182D;
    localparam [23:0] BORDER   = 24'h2A3B5E;
    localparam [23:0] KEY_IDLE = 24'h1B2A49;
    localparam [23:0] KEY_SHARP= 24'h111A2E;
    localparam [23:0] KEY_ACT  = 24'h176B72;
    localparam [23:0] CYAN     = 24'h20D0F0;
    localparam [23:0] GREEN    = 24'h40E090;
    localparam [23:0] ORANGE   = 24'hFFA030;
    localparam [23:0] WHITE    = 24'hE8F0FF;

    wire        text_on;
    wire [7:0]  text_char;
    wire [2:0]  text_row;
    wire [2:0]  text_bit;
    wire [23:0] text_color;

    dashboard_text_mux #(.SAMPLE_RATE_48K(SAMPLE_RATE_48K)) u_text (
        .x(x), .y(y), .st(st),
        .text_on(text_on), .char_code(text_char), .font_row(text_row),
        .bit_index(text_bit), .color(text_color)
    );

    wire [8:0] font_addr = (text_char >= 8'd32 && text_char < 8'd96) ?
                           ((text_char - 8'd32) << 2) + {6'd0, text_row[2:1]} : 9'd0;
    wire [7:0] font_data;
    dashboard_font_prom u_font (
        .clk(pix_clk), .ce(1'b1), .rst(rst),
        .addr(font_addr), .row_lsb(text_row[0]), .dout(font_data)
    );
    reg        text_on_p;
    reg [2:0]  text_bit_p;
    reg [23:0] text_color_p;
    reg [23:0] geometry_p;
    reg        de_p;
    reg [10:0] voice_limit_p;
    reg        text_on_p2;
    reg [23:0] text_color_p2;
    reg [23:0] geometry_p2;
    reg        font_pixel_p;
    reg        de_p2;
    wire font_pixel = font_data[7 - text_bit_p];

    reg [23:0] draw;
    reg [10:0] key_dx;
    reg [9:0]  key_dy;
    reg [10:0] px;
    reg [9:0]  py;
    reg [2:0]  key_col;
    reg        key_row;
    reg [3:0]  key_index;
    reg        key_hit;
    reg        key_sharp;
    reg [3:0]  voices;
    reg [5:0]  wave_index;
    reg [3:0]  wave_value;
    reg [3:0]  wave_row;
    reg [2:0]  spectrum_index;
    reg [7:0]  spectrum_value;
    reg [5:0]  spectrum_height;
    reg [3:0]  phase_x;
    reg [3:0]  phase_y;
    reg [5:0]  phase_index;

    always @* begin
        draw = BG;

        if (y < 10'd120) draw = HEADER;
        if ((y >= 10'd116) && (y < 10'd120)) draw = CYAN;

        if ((x >= 11'd916) && (x < 11'd1236) &&
            (y >= 10'd156) && (y < 10'd620)) draw = PANEL;
        if ((x >= 11'd56) && (x < 11'd860) &&
            (y >= 10'd200) && (y < 10'd512)) draw = PANEL_2;
        if ((x >= 11'd56) && (x < 11'd860) &&
            (y >= 10'd536) && (y < 10'd568)) draw = PANEL_2;
        if ((y >= 10'd632) && (y < 10'd720)) draw = HEADER;
        if ((y >= 10'd632) && (y < 10'd635)) draw = CYAN;

        // Twelve 124x144 pads with a 12-pixel horizontal and 16-pixel
        // vertical gap. Constant coordinate selection keeps the status bit
        // out of a long twelve-way priority chain.
        key_dx = 11'd0;
        key_dy = 10'd0;
        key_col = 3'd0;
        key_row = 1'b0;
        key_index = 4'd0;
        key_hit = 1'b0;
        key_sharp = 1'b0;
        px = 11'd0;
        py = 10'd0;
        wave_index = 6'd0;
        wave_value = 4'd0;
        wave_row = 4'd0;
        spectrum_index = 3'd0;
        spectrum_value = 8'd0;
        spectrum_height = 6'd0;
        phase_x = 4'd0;
        phase_y = 4'd0;
        phase_index = 6'd0;
        if ((x >= 11'd56) && (x < 11'd860) &&
            (y >= 10'd208) && (y < 10'd512)) begin
            key_dx = x - 11'd56;
            key_dy = y - 10'd208;
            if (key_dx >= 11'd680) key_col = 3'd5;
            else if (key_dx >= 11'd544) key_col = 3'd4;
            else if (key_dx >= 11'd408) key_col = 3'd3;
            else if (key_dx >= 11'd272) key_col = 3'd2;
            else if (key_dx >= 11'd136) key_col = 3'd1;
            else key_col = 3'd0;
            key_row = (key_dy >= 10'd160);
            case (key_col)
                3'd0: px = 11'd56;
                3'd1: px = 11'd192;
                3'd2: px = 11'd328;
                3'd3: px = 11'd464;
                3'd4: px = 11'd600;
                default: px = 11'd736;
            endcase
            py = key_row ? 10'd368 : 10'd208;
            key_index = key_row ? (4'd6 + {1'b0, key_col}) : {1'b0, key_col};
            key_hit = (x < px + 11'd124) && (y < py + 10'd144);
            case (key_index)
                4'd1, 4'd3, 4'd6, 4'd8, 4'd10: key_sharp = 1'b1;
                default: key_sharp = 1'b0;
            endcase
        end
        if (key_hit) begin
            draw = st[key_index] ? KEY_ACT : (key_sharp ? KEY_SHARP : KEY_IDLE);
            if ((x < px + 11'd3) || (x >= px + 11'd121) ||
                (y < py + 10'd3) || (y >= py + 10'd141))
                draw = st[key_index] ? CYAN : BORDER;
        end

        // Polyphony bar: eight equal slots.
        voices = (st[15:12] > 8) ? 4'd8 : st[15:12];
        if ((x >= 11'd216) && (x < 11'd848) &&
            (y >= 10'd548) && (y < 10'd566)) begin
            draw = BORDER;
            if ((x >= 11'd220) && (x < 11'd844) &&
                (y >= 10'd552) && (y < 10'd562)) begin
                draw = PANEL;
                if (x < voice_limit_p) draw = GREEN;
            end
        end

        // Small fixed accent blocks help identify the active panel on a monitor.
        if ((x >= 11'd932) && (x < 11'd1220) &&
            (y >= 10'd184) && (y < 10'd187)) draw = CYAN;
        if ((x >= 11'd56) && (x < 11'd860) &&
            (y >= 10'd192) && (y < 10'd195)) draw = BORDER;

        // The waveform snapshot is 64 signed 8-bit samples.  Four horizontal
        // pixels represent one sample, with a one-pixel trace around the
        // sample position and a quiet center line for orientation.
        if ((x >= 11'd932) && (x < 11'd1220) &&
            (y >= 10'd492) && (y < 10'd540)) begin
            draw = PANEL_2;
            wave_index = (x - 11'd932) >> 2;
            if (wave_index > 6'd63) wave_index = 6'd63;
            wave_value = waveform[(wave_index * 4) +: 4];
            wave_row = (y - 10'd484) >> 3;
            if (wave_row > 4'd7) wave_row = 4'd7;
            if (y == 10'd516) draw = BORDER;
            if (wave_row == wave_value) draw = CYAN;
        end

        // Eight compact frequency-band activity bars.  The source values are
        // generated in the audio clock domain from active note/velocity state.
        if ((x >= 11'd932) && (x < 11'd1220) &&
            (y >= 10'd550) && (y < 10'd612)) begin
            draw = PANEL_2;
            // Eight 32-pixel slots avoid a divider/modulo in the 74.25 MHz
            // pixel path.  Each slot has a 24-pixel bar and an 8-pixel gap.
            spectrum_index = (x - 11'd932) >> 5;
            if (spectrum_index > 3'd7) spectrum_index = 3'd7;
            spectrum_value = spectrum[(spectrum_index * 8) +: 8];
            spectrum_height = spectrum_value >> 3;
            if (((x - 11'd932) & 11'd31) >= 11'd4 &&
                ((x - 11'd932) & 11'd31) < 11'd28 &&
                y >= (10'd610 - spectrum_height)) draw = GREEN;
            if (y == 10'd610) draw = BORDER;
        end

        // 16x16 phase/Lissajous occupancy bitmap, enlarged 4x.  Each bit is
        // set from adjacent audio samples in the audio-domain snapshot.
        if ((x >= 11'd56) && (x < 11'd120) &&
            (y >= 10'd568) && (y < 10'd632)) begin
            draw = PANEL_2;
            phase_x = (x - 11'd56) >> 3;
            phase_y = (y - 10'd568) >> 3;
            phase_index = {phase_y[2:0], phase_x[2:0]};
            if (lissajous[phase_index]) draw = ORANGE;
            if (phase_x == 4'd4 || phase_y == 4'd4) draw = BORDER;
        end

    end

    // Stage 1 latches geometry and text metadata. The pROM samples font_addr
    // on the same edge, so its one-cycle output aligns with these registers.
    // Stage 2 combines the font bit with the registered geometry and RGB.
    always @(posedge pix_clk) begin
        if (rst) begin
            text_on_p    <= 1'b0;
            text_bit_p   <= 3'd0;
            text_color_p <= 24'd0;
            geometry_p   <= 24'd0;
            de_p         <= 1'b0;
            voice_limit_p <= 11'd220;
            text_on_p2   <= 1'b0;
            text_color_p2 <= 24'd0;
            geometry_p2  <= 24'd0;
            font_pixel_p <= 1'b0;
            de_p2        <= 1'b0;
            rgb_r        <= 8'd0;
            rgb_g        <= 8'd0;
            rgb_b        <= 8'd0;
        end else begin
            text_on_p    <= text_on;
            text_bit_p   <= text_bit;
            text_color_p <= text_color;
            geometry_p   <= draw;
            de_p         <= de;
            voice_limit_p <= 11'd220 + ({7'd0, voices} * 8'd78);

            text_on_p2    <= text_on_p;
            text_color_p2 <= text_color_p;
            geometry_p2   <= geometry_p;
            font_pixel_p  <= font_pixel;
            de_p2         <= de_p;

            if (de_p2) begin
                if (text_on_p2 && font_pixel_p) begin
                    rgb_r <= text_color_p2[23:16];
                    rgb_g <= text_color_p2[15:8];
                    rgb_b <= text_color_p2[7:0];
                end else begin
                    rgb_r <= geometry_p2[23:16];
                    rgb_g <= geometry_p2[15:8];
                    rgb_b <= geometry_p2[7:0];
                end
            end else begin
                rgb_r <= 8'd0;
                rgb_g <= 8'd0;
                rgb_b <= 8'd0;
            end
        end
    end
endmodule
