// Fixed dashboard text layout. Only uppercase ASCII and digits are used, so the
// whole font fits in one 512-byte pROM. Geometry is calculated from pixel
// coordinates; no glyph map or frame buffer is stored.
module dashboard_text_mux #(
    parameter integer SAMPLE_RATE_48K = 0
) (
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire [63:0] st,
    output reg         text_on,
    output reg  [7:0]  char_code,
    output reg  [2:0]  font_row,
    output reg  [2:0]  bit_index,
    output reg  [23:0] color
);
    function [7:0] static_char;
        input [4:0] id;
        input [5:0] idx;
        reg [255:0] s;
        begin
            case (id)
                5'd0:  s = "POLYTOUCH FPGA SYNTH            ";
                5'd1:  s = "HDMI 720P60                     ";
                5'd2:  s = "TOUCH KEYS                      ";
                5'd3:  s = "LIVE STATUS                     ";
                5'd4:  s = "INST                            ";
                5'd5:  s = "MODE                            ";
                5'd6:  s = "SOUND                           ";
                5'd7:  s = "VOICES                          ";
                5'd8:  s = "NOTE                            ";
                5'd9:  s = "VELOCITY                        ";
                5'd10: s = "PRESSURE                        ";
                5'd11: s = "TIMBRE                          ";
                5'd12: s = "SAMPLE                          ";
                5'd13: s = "POLYPHONY                       ";
                5'd14: s = SAMPLE_RATE_48K ? "AUDIO 48.0 KHZ                  " :
                                                   "AUDIO 46.9 KHZ                  ";
                5'd15: s = "PCM5102A I2S                    ";
                5'd16: s = "HDMI 720P60                     ";
                5'd17: s = "FPGA GW2A-18                    ";
                5'd18: s = "POLYTOUCH 2026                  ";
                5'd19: s = "46.9 KHZ                        ";
                5'd20: s = "48.0 KHZ                        ";
                5'd21: s = "WAVEFORM                        ";
                5'd22: s = "SPECTRUM                        ";
                5'd23: s = "PHASE                           ";
                default: s = "                                ";
            endcase
            static_char = s[255 - (idx * 8) -: 8];
        end
    endfunction

    function [7:0] word_char;
        input [3:0] id;
        input [3:0] idx;
        reg [63:0] s;
        begin
            case (id)
                4'd0: s = "PIANO   ";
                4'd1: s = "GUITAR  ";
                4'd2: s = "MANUAL  ";
                4'd3: s = "DEMO    ";
                4'd4: s = "MUTED   ";
                4'd5: s = "LIVE    ";
                default: s = "        ";
            endcase
            word_char = (idx < 8) ? s[63 - (idx * 8) -: 8] : 8'h20;
        end
    endfunction

    function [7:0] digit_char;
        input [3:0] d;
        begin
            digit_char = (d < 10) ? (8'd48 + {4'd0, d}) : 8'h20;
        end
    endfunction

    function [7:0] dec2_char;
        input [7:0] value;
        input        idx;
        reg [3:0] tens;
        reg [3:0] ones;
        begin
            tens = (value / 10) % 10;
            ones = value % 10;
            dec2_char = idx ? digit_char(ones) : digit_char(tens);
        end
    endfunction

    function [7:0] dec3_char;
        input [7:0] value;
        input [1:0] idx;
        reg [3:0] hundreds;
        reg [3:0] tens;
        reg [3:0] ones;
        begin
            hundreds = (value / 100) % 10;
            tens     = (value / 10) % 10;
            ones     = value % 10;
            case (idx)
                2'd0: dec3_char = digit_char(hundreds);
                2'd1: dec3_char = digit_char(tens);
                default: dec3_char = digit_char(ones);
            endcase
        end
    endfunction

    function [7:0] note_letter;
        input [3:0] pc;
        begin
            case (pc)
                4'd0:  note_letter = "C";
                4'd1:  note_letter = "C";
                4'd2:  note_letter = "D";
                4'd3:  note_letter = "D";
                4'd4:  note_letter = "E";
                4'd5:  note_letter = "F";
                4'd6:  note_letter = "F";
                4'd7:  note_letter = "G";
                4'd8:  note_letter = "G";
                4'd9:  note_letter = "A";
                4'd10: note_letter = "A";
                4'd11: note_letter = "B";
                default: note_letter = 8'h20;
            endcase
        end
    endfunction

    function is_sharp;
        input [3:0] pc;
        begin
            case (pc)
                4'd1, 4'd3, 4'd6, 4'd8, 4'd10: is_sharp = 1'b1;
                default: is_sharp = 1'b0;
            endcase
        end
    endfunction

    function [7:0] note_char;
        input [6:0] pitch;
        input [1:0] idx;
        reg [3:0] pc;
        reg [3:0] octave;
        begin
            pc = pitch % 12;
            octave = (pitch / 12 == 0) ? 4'd0 : (pitch / 12 - 1);
            case (idx)
                2'd0: note_char = note_letter(pc);
                2'd1: note_char = is_sharp(pc) ? "#" : 8'h20;
                default: note_char = digit_char(octave);
            endcase
        end
    endfunction

    function [7:0] key_label_char;
        input [3:0] key;
        input        idx;
        begin
            key_label_char = (idx == 1'b0) ? note_letter(key) :
                             (is_sharp(key) ? "#" : 8'h20);
        end
    endfunction

    function [7:0] poly_char;
        input [3:0] active;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: poly_char = 8'd48;
                3'd1: poly_char = digit_char(active);
                3'd2: poly_char = "/";
                3'd3: poly_char = 8'd48;
                default: poly_char = 8'd56;
            endcase
        end
    endfunction

    localparam [23:0] C_CYAN   = 24'h20D0F0;
    localparam [23:0] C_GREEN  = 24'h40E090;
    localparam [23:0] C_WHITE  = 24'hE8F0FF;
    localparam [23:0] C_GRAY   = 24'h7890A8;
    localparam [23:0] C_ORANGE = 24'hFFA030;
    localparam [23:0] C_RED    = 24'hFF6070;

    reg        key_label_hit;
    reg [3:0]  key_label_index;
    reg [10:0] pad_x;
    reg [9:0]  pad_y;
    reg [10:0] key_dx;
    reg [9:0]  key_dy;
    reg [2:0]  key_col;
    reg        key_row;
    reg [4:0]  temp4;

    // Key pads are 6 columns by 2 rows. Resolve the index arithmetically so
    // the font address path does not include a twelve-entry priority chain.
    always @* begin
        key_label_hit   = 1'b0;
        key_label_index = 4'd0;
        pad_x = 11'd0;
        pad_y = 10'd0;
        key_dx = 11'd0;
        key_dy = 10'd0;
        key_col = 3'd0;
        key_row = 1'b0;
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
                3'd0: pad_x = 11'd56;
                3'd1: pad_x = 11'd192;
                3'd2: pad_x = 11'd328;
                3'd3: pad_x = 11'd464;
                3'd4: pad_x = 11'd600;
                default: pad_x = 11'd736;
            endcase
            pad_y = key_row ? 10'd368 : 10'd208;
            key_label_index = key_row ? (4'd6 + {1'b0, key_col}) : {1'b0, key_col};
            if ((x >= pad_x + 11'd46) && (x < pad_x + 11'd78) &&
                (y >= pad_y + 10'd56) && (y < pad_y + 10'd72))
                key_label_hit = 1'b1;
        end
    end

    always @* begin
        text_on    = 1'b0;
        char_code  = 8'h20;
        font_row   = 3'd0;
        bit_index  = 3'd0;
        color      = C_WHITE;
        temp4      = 5'd0;

        // Title, scale 4.
        if ((x >= 11'd48) && (x < 11'd688) && (y >= 10'd32) && (y < 10'd64)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd0, (x - 11'd48) >> 5);
            font_row  = ((y - 10'd32) >> 2) & 7;
            bit_index = ((x - 11'd48) >> 2) & 7;
            color     = C_CYAN;
        end
        // Header right, scale 4.
        else if ((x >= 11'd912) && (x < 11'd1264) && (y >= 10'd40) && (y < 10'd72)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd1, (x - 11'd912) >> 5);
            font_row  = ((y - 10'd40) >> 2) & 7;
            bit_index = ((x - 11'd912) >> 2) & 7;
            color     = C_GREEN;
        end
        // Left section heading, scale 2.
        else if ((x >= 11'd56) && (x < 11'd216) && (y >= 10'd160) && (y < 10'd176)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd2, (x - 11'd56) >> 4);
            font_row  = ((y - 10'd160) >> 1) & 7;
            bit_index = ((x - 11'd56) >> 1) & 7;
            color     = C_GRAY;
        end
        // Dynamic note labels inside the twelve pads, scale 2.
        else if (key_label_hit) begin
            text_on   = 1'b1;
            char_code = key_label_char(key_label_index, x[4]);
            font_row  = ((y - (10'd208 + (key_label_index / 6) * 10'd160) - 10'd56) >> 1) & 7;
            bit_index = ((x - (11'd56 + (key_label_index % 6) * 11'd136) - 11'd46) >> 1) & 7;
            color     = C_WHITE;
        end
        // Right panel heading.
        else if ((x >= 11'd932) && (x < 11'd1108) && (y >= 10'd160) && (y < 10'd176)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd3, (x - 11'd932) >> 4);
            font_row  = ((y - 10'd160) >> 1) & 7;
            bit_index = ((x - 11'd932) >> 1) & 7;
            color     = C_CYAN;
        end
        // Right panel labels and values, scale 2.
        else if ((y >= 10'd208) && (y < 10'd480) && (y[4:0] >= 5'd16)) begin
            temp4 = (y - 10'd208) >> 5;  // 0..8
            if ((x >= 11'd932) && (x < 11'd1060)) begin
                text_on   = 1'b1;
                char_code = static_char(5'd4 + temp4, (x - 11'd932) >> 4);
                font_row  = ((y - (10'd208 + temp4 * 10'd32)) >> 1) & 7;
                bit_index = ((x - 11'd932) >> 1) & 7;
                color     = C_GRAY;
            end else if ((x >= 11'd1092) && (x < 11'd1228)) begin
                text_on   = 1'b1;
                font_row  = ((y - (10'd208 + temp4 * 10'd32)) >> 1) & 7;
                bit_index = ((x - 11'd1092) >> 1) & 7;
                color     = C_WHITE;
                case (temp4)
                    5'd0: begin char_code = word_char(st[43] ? 4'd1 : 4'd0, (x - 11'd1092) >> 4); color = st[43] ? C_ORANGE : C_GREEN; end
                    5'd1: char_code = word_char(st[39] ? 4'd3 : 4'd2, (x - 11'd1092) >> 4);
                    5'd2: begin char_code = word_char(st[44] ? 4'd4 : 4'd5, (x - 11'd1092) >> 4); color = st[44] ? C_RED : C_GREEN; end
                    5'd3: char_code = dec2_char({4'd0, st[15:12]}, (x - 11'd1092) >> 4);
                    5'd4: char_code = note_char(st[22:16], (x - 11'd1092) >> 4);
                    5'd5: char_code = dec3_char(st[30:23], (x - 11'd1092) >> 4);
                    5'd6: char_code = dec3_char(st[38:31], (x - 11'd1092) >> 4);
                    5'd7: char_code = dec3_char(st[55:48], (x - 11'd1092) >> 4);
                    5'd8: char_code = static_char(SAMPLE_RATE_48K ? 5'd20 : 5'd19, (x - 11'd1092) >> 4);
                    default: char_code = 8'h20;
                endcase
            end
        end
        // Polyphony readout.
        else if ((x >= 11'd56) && (x < 11'd200) && (y >= 10'd544) && (y < 10'd560)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd13, (x - 11'd56) >> 4);
            font_row  = ((y - 10'd544) >> 1) & 7;
            bit_index = ((x - 11'd56) >> 1) & 7;
            color     = C_GRAY;
        end
        else if ((x >= 11'd760) && (x < 11'd840) && (y >= 10'd544) && (y < 10'd560)) begin
            text_on   = 1'b1;
            char_code = poly_char(st[15:12], (x - 11'd760) >> 4);
            font_row  = ((y - 10'd544) >> 1) & 7;
            bit_index = ((x - 11'd760) >> 1) & 7;
            color     = C_GREEN;
        end
        // Visual feedback labels.  The underlying pixels are generated from
        // the audio-domain snapshot rather than a computer-side GUI.
        else if ((x >= 11'd932) && (x < 11'd1060) && (y >= 10'd480) && (y < 10'd492)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd21, (x - 11'd932) >> 3);
            font_row  = ((y - 10'd480) >> 1) & 7;
            bit_index = ((x - 11'd932) >> 1) & 7;
            color     = C_CYAN;
        end
        else if ((x >= 11'd932) && (x < 11'd1060) && (y >= 10'd536) && (y < 10'd548)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd22, (x - 11'd932) >> 3);
            font_row  = ((y - 10'd536) >> 1) & 7;
            bit_index = ((x - 11'd932) >> 1) & 7;
            color     = C_GREEN;
        end
        else if ((x >= 11'd132) && (x < 11'd260) && (y >= 10'd576) && (y < 10'd588)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd23, (x - 11'd132) >> 3);
            font_row  = ((y - 10'd576) >> 1) & 7;
            bit_index = ((x - 11'd132) >> 1) & 7;
            color     = C_ORANGE;
        end
        // Footer labels.
        else if ((x >= 11'd56) && (x < 11'd280) && (y >= 10'd656) && (y < 10'd672)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd14, (x - 11'd56) >> 4);
            font_row  = ((y - 10'd656) >> 1) & 7;
            bit_index = ((x - 11'd56) >> 1) & 7;
            color     = C_GRAY;
        end
        else if ((x >= 11'd312) && (x < 11'd504) && (y >= 10'd656) && (y < 10'd672)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd15, (x - 11'd312) >> 4);
            font_row  = ((y - 10'd656) >> 1) & 7;
            bit_index = ((x - 11'd312) >> 1) & 7;
            color     = C_GRAY;
        end
        else if ((x >= 11'd536) && (x < 11'd712) && (y >= 10'd656) && (y < 10'd672)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd16, (x - 11'd536) >> 4);
            font_row  = ((y - 10'd656) >> 1) & 7;
            bit_index = ((x - 11'd536) >> 1) & 7;
            color     = C_GRAY;
        end
        else if ((x >= 11'd744) && (x < 11'd936) && (y >= 10'd656) && (y < 10'd672)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd17, (x - 11'd744) >> 4);
            font_row  = ((y - 10'd656) >> 1) & 7;
            bit_index = ((x - 11'd744) >> 1) & 7;
            color     = C_GRAY;
        end
        else if ((x >= 11'd1000) && (x < 11'd1224) && (y >= 10'd656) && (y < 10'd672)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd18, (x - 11'd1000) >> 4);
            font_row  = ((y - 10'd656) >> 1) & 7;
            bit_index = ((x - 11'd1000) >> 1) & 7;
            color     = C_GRAY;
        end
    end
endmodule
