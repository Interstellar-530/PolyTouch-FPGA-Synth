// Scanline dashboard renderer. It receives one pixel coordinate per clock and
// emits RGB directly; no frame buffer is required.
module dashboard_renderer #(
    parameter integer SAMPLE_RATE_48K = 0,
    parameter integer VOICE_GRID = 0
) (
    input  wire        pix_clk,
    input  wire        rst,
    input  wire        de,
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire [63:0] st,
    input  wire [31:0] voice_mask,
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

        dashboard_text_mux #(.SAMPLE_RATE_48K(SAMPLE_RATE_48K),.VOICE_GRID(VOICE_GRID)) u_text (
            .x(x), .y(y), .st(st),.voice_mask(voice_mask),
            .text_on(text_on), .char_code(text_char), .font_row(text_row),
            .bit_index(text_bit), .color(text_color));

    reg [7:0] text_char_s;
    reg [2:0] text_row_s, text_bit_s;
    reg text_on_s, de_s;
    reg [23:0] text_color_s, geometry_s;
    wire [8:0] font_addr = (text_char_s >= 8'd32 && text_char_s < 8'd96) ?
                           ((text_char_s - 8'd32) << 2) + {6'd0, text_row_s[2:1]} : 9'd0;
    wire [7:0] font_data;
    dashboard_font_prom u_font (
        .clk(pix_clk), .ce(1'b1), .rst(rst),
        .addr(font_addr), .row_lsb(text_row_s[0]), .dout(font_data)
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
    reg [5:0]  voices;
    reg [10:0] slot_dx;
    reg [9:0] slot_dy;
    reg [2:0] slot_col;
    reg [4:0] slot_cell;
    reg [6:0] slot_local;
    reg [4:0] slot_index;
    reg [5:0]  wave_index;
    reg [3:0]  wave_value;
    reg [3:0]  wave_row;
    reg [2:0]  spectrum_index;
    reg [7:0]  spectrum_value;
    reg [5:0]  spectrum_height;
    reg [3:0]  phase_x;
    reg [3:0]  phase_y;
    reg [5:0]  phase_index;

    function [4:0] grid_cell;
        input [4:0] q;
        begin case(q)
            5'd0: grid_cell=5'd0;
            5'd1: grid_cell=5'd1;
            5'd2: grid_cell=5'd2;
            5'd3: grid_cell=5'd4;
            5'd4: grid_cell=5'd5;
            5'd5: grid_cell=5'd6;
            5'd6: grid_cell=5'd8;
            5'd7: grid_cell=5'd9;
            5'd8: grid_cell=5'd10;
            5'd9: grid_cell=5'd12;
            5'd10: grid_cell=5'd13;
            5'd11: grid_cell=5'd14;
            5'd12: grid_cell=5'd16;
            5'd13: grid_cell=5'd17;
            5'd14: grid_cell=5'd18;
            5'd15: grid_cell=5'd20;
            5'd16: grid_cell=5'd21;
            5'd17: grid_cell=5'd22;
            5'd18: grid_cell=5'd24;
            5'd19: grid_cell=5'd25;
            5'd20: grid_cell=5'd26;
            5'd21: grid_cell=5'd28;
            5'd22: grid_cell=5'd29;
            5'd23: grid_cell=5'd30;
            default: grid_cell=5'd0;
        endcase end
    endfunction

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
        if (!VOICE_GRID && key_hit) begin
            draw = st[key_index] ? KEY_ACT : (key_sharp ? KEY_SHARP : KEY_IDLE);
            if ((x < px + 11'd3) || (x >= px + 11'd121) ||
                (y < py + 10'd3) || (y >= py + 10'd141))
                draw = st[key_index] ? CYAN : BORDER;
        end

        // Polyphony bar: eight equal slots.
        slot_dx=x-11'd56;slot_dy=y-10'd208;
        slot_cell=grid_cell(slot_dx[9:5]);slot_col=slot_cell[4:2];
        slot_local={slot_cell[1:0],slot_dx[4:0]};
        slot_index={slot_dy[7:6],slot_col};
        if(VOICE_GRID && x>=56 && x<824 && y>=208 && y<464 &&
            slot_local<88 && slot_dy[5:0]<56) begin
            draw=voice_mask[slot_index] ? KEY_ACT : KEY_IDLE;
            if(slot_local<2 || slot_dy[5:0]<2 ||
               slot_local>=86 || slot_dy[5:0]>=54)
                draw=voice_mask[slot_index] ? CYAN : BORDER;
        end        voices = VOICE_GRID ? ({st[61:60],st[15:12]}>32 ? 6'd32 : {st[61:60],st[15:12]}) :
                             (st[15:12]>8 ? 6'd8 : {2'd0,st[15:12]});
        if (!VOICE_GRID && (x >= 11'd216) && (x < 11'd848) &&
            (y >= 10'd548) && (y < 10'd566)) begin
            draw = BORDER;
            if ((x >= 11'd220) && (x < (VOICE_GRID ? 11'd732 : 11'd844)) &&
                (y >= 10'd552) && (y < 10'd562)) begin
                draw = PANEL;
                if (x < voice_limit_p) draw = GREEN;
            end
        end

        // Small fixed accent blocks help identify the active panel on a monitor.
        if ((x >= 11'd932) && (x < 11'd1220) &&
            (y >= 10'd184) && (y < 10'd187)) draw = CYAN;
        if (!VOICE_GRID && (x >= 11'd56) && (x < 11'd860) &&
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
            spectrum_height = spectrum_value >> 2;
            if (((x - 11'd932) & 11'd31) >= 11'd4 &&
                ((x - 11'd932) & 11'd31) < 11'd28 &&
                y >= (10'd610 - spectrum_height)) begin
                draw = (y < 10'd568) ? ORANGE : (y < 10'd590) ? CYAN : GREEN;
                if(y < (10'd612 - spectrum_height)) draw = WHITE;
            end
            if (y == 10'd610) draw = BORDER;
        end

        // 16x16 phase/Lissajous occupancy bitmap, enlarged 4x.  Each bit is
        // set from adjacent audio samples in the audio-domain snapshot.
        if (!VOICE_GRID && (x >= 11'd56) && (x < 11'd120) &&
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
            text_char_s <= 8'd32; text_row_s <= 0; text_bit_s <= 0;
            text_on_s <= 0; de_s <= 0; text_color_s <= 0; geometry_s <= 0;
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
            text_char_s <= text_char; text_row_s <= text_row; text_bit_s <= text_bit;
            text_on_s <= text_on; de_s <= de; text_color_s <= text_color; geometry_s <= draw;
            text_on_p    <= text_on_s;
            text_bit_p   <= text_bit_s;
            text_color_p <= text_color_s;
            geometry_p   <= geometry_s;
            de_p         <= de_s;
            voice_limit_p <= VOICE_GRID ? (11'd220 + {1'd0,voices,4'd0}) :
                                         (11'd220 + ({5'd0,voices} * 8'd78));

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

// Native 1024x600 scanline renderer for the 32-voice HDMI build.
module dashboard_renderer_1024(
    input wire pix_clk,rst,de,input wire [10:0] x,input wire [9:0] y,
    input wire [63:0] st,input wire [31:0] voice_mask,
    input wire [255:0] waveform,input wire [63:0] spectrum,lissajous,
    output reg [7:0] rgb_r,rgb_g,rgb_b
);
    wire text_on;
    wire [7:0] text_char;
    wire [2:0] text_row,text_bit;
    wire [23:0] text_color;
    dashboard_text_1024 u_text(.x(x),.y(y),.st(st),.text_on(text_on),
        .char_code(text_char),.font_row(text_row),.bit_index(text_bit),.color(text_color));
    reg [7:0] char_s;
    reg [2:0] row_s,bit_s,bit_p;
    reg text_s,text_p,text_p2,de_s,de_p,de_p2;
    reg [23:0] color_s,color_p,color_p2,geom_s,geom_p,geom_p2;
    reg font_pixel_p;
    wire [8:0] font_addr=(char_s>=32 && char_s<96) ?
        ((char_s-8'd32)<<2)+{6'd0,row_s[2:1]} : 9'd0;
    wire [7:0] font_data;
    dashboard_font_prom u_font(.clk(pix_clk),.ce(1'b1),.rst(rst),
        .addr(font_addr),.row_lsb(row_s[0]),.dout(font_data));
    reg [23:0] draw;
    reg [2:0] col, row;
    reg [5:0] dx,dy;
    reg [3:0] key;
    reg [5:0] wave_col;
    reg [3:0] wave_now,wave_next;
    reg [9:0] trace_y,next_y,low_y,high_y;
    reg [4:0] slot;
    always @* begin
        draw=24'h090e1c;col=0;row=0;dx=0;dy=0;key=0;
        if(y<80) draw=24'h111b35;
        if(y>=78 && y<81) draw=24'h20d0f0;
        if(x>=24 && x<736 && y>=104 && y<528) draw=24'h10182d;
        if(x>=760 && x<1000 && y>=104 && y<528) draw=24'h151f38;
        if(y>=540) draw=24'h111b35;
        if(y>=540 && y<543) draw=24'h20d0f0;
        wave_col=0;wave_now=4;wave_next=4;
        trace_y=304;next_y=304;low_y=304;high_y=304;slot=0;
        // 64 real audio columns. Bright dots and connected stems form a
        // vibrating oscilloscope trace; no framebuffer or new DSP is needed.
        if(x>=64 && x<576 && y>=160 && y<432) begin
            wave_col=(x-64)>>3;
            wave_now=waveform[{wave_col,2'b00} +: 4];
            wave_next=4;
            trace_y=10'd176+{2'd0,wave_now[2:0],5'd0};
            next_y=10'd304;
            low_y=trace_y<next_y ? trace_y : next_y;
            high_y=trace_y>next_y ? trace_y : next_y;
            if(x[5:0]==0 || y[5:0]==0) draw=24'h17283b;
            if(y==304) draw=24'h2a3b5e;
            if(x[2:0]==4 && y[2:0]<2 && y>=low_y && y<=high_y) draw=24'h176b72;
            if(y+6>=trace_y && y<=trace_y+6) draw=24'h123e50;
            if(y+2>=trace_y && y<=trace_y+2 && x[2:0]>=2 && x[2:0]<=6) draw=24'h20d0f0;
            if(y==trace_y && x[2:0]>=3 && x[2:0]<=5) draw=24'he8f0ff;
        end
        // All 32 actual allocator slots, packed into a small 4x8 matrix.
        if(x>=600 && x<728 && y>=176 && y<432) begin
            slot=((y-10'd176)>>5)*4+((x-11'd600)>>5);
            if(((x-600)&31)<26 && ((y-176)&31)<24)
                draw=voice_mask[slot] ? 24'h40e090 : 24'h1b2a49;
        end
        if(x>=40 && x<712 && y>=482 && y<518) begin
            if(x>=656) key=11;else if(x>=600) key=10;
            else if(x>=544) key=9;else if(x>=488) key=8;
            else if(x>=432) key=7;else if(x>=376) key=6;
            else if(x>=320) key=5;else if(x>=264) key=4;
            else if(x>=208) key=3;else if(x>=152) key=2;
            else if(x>=96) key=1;
            dx=x-(11'd40+key*6'd56);
            draw=(dx>=50) ? 24'h10182d :
                (st[key] && y>=488 && y<512) ? 24'h20d0f0 :
                st[key] ? 24'h176b72 : 24'h1b2a49;
        end
        if(x>=780 && x<980 && y>=496 && y<512) begin
            draw=24'h2a3b5e;
            if(x<780+{2'd0,st[61:60],st[15:12],2'd0}) draw=24'h40e090;
        end
    end
    always @(posedge pix_clk) begin
        if(rst) begin
            char_s<=32;row_s<=0;bit_s<=0;text_s<=0;de_s<=0;color_s<=0;geom_s<=0;
            bit_p<=0;text_p<=0;de_p<=0;color_p<=0;geom_p<=0;
            text_p2<=0;de_p2<=0;color_p2<=0;geom_p2<=0;font_pixel_p<=0;
            rgb_r<=0;rgb_g<=0;rgb_b<=0;
        end else begin
            char_s<=text_char;row_s<=text_row;bit_s<=text_bit;text_s<=text_on;
            de_s<=de;color_s<=text_color;geom_s<=draw;
            bit_p<=bit_s;text_p<=text_s;de_p<=de_s;color_p<=color_s;geom_p<=geom_s;
            text_p2<=text_p;de_p2<=de_p;color_p2<=color_p;geom_p2<=geom_p;
            font_pixel_p<=font_data[7-bit_p];
            if(de_p2) begin
                if(text_p2 && font_pixel_p) begin
                    rgb_r<=color_p2[23:16];rgb_g<=color_p2[15:8];rgb_b<=color_p2[7:0];
                end else begin
                    rgb_r<=geom_p2[23:16];rgb_g<=geom_p2[15:8];rgb_b<=geom_p2[7:0];
                end
            end else begin rgb_r<=0;rgb_g<=0;rgb_b<=0;end
        end
    end
endmodule

