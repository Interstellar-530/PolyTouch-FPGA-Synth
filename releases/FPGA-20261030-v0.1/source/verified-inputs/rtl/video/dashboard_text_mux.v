// Fixed dashboard text layout. Only uppercase ASCII and digits are used, so the
// whole font fits in one 512-byte pROM. Geometry is calculated from pixel
// coordinates; no glyph map or frame buffer is stored.
module dashboard_text_mux #(
    parameter integer SAMPLE_RATE_48K = 0,
    parameter integer VOICE_GRID = 0
) (
    input  wire [10:0] x,
    input  wire [9:0]  y,
    input  wire [63:0] st,
    input  wire [31:0] voice_mask,
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
                5'd0:  s = VOICE_GRID ? "POLYTOUCH 32 VOICE              " : "POLYTOUCH FPGA SYNTH            ";
                5'd1:  s = "1024X600 60                     ";
                5'd2:  s = VOICE_GRID ? "LIVE NOTE FIELD                 " : "PITCH CLASS                     ";
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
                                                   "AUDIO 46.875 KHZ                ";
                5'd15: s = "PCM5102A I2S                    ";
                5'd16: s = "1024X600 60                     ";
                5'd17: s = "FPGA GW2A-18                    ";
                5'd18: s = VOICE_GRID ? "12 TOUCH KEYS                   " : "POLYTOUCH 2026                  ";
                5'd19: s = "46.9 KHZ                        ";
                5'd20: s = "48.0 KHZ                        ";
                5'd21: s = "WAVEFORM                        ";
                5'd22: s = "SPECTRUM                        ";
                5'd23: s = "PHASE                           ";
                5'd24: s = "32 VOICES                       ";
                5'd25: s = "512 PT WAVES                    ";
                5'd26: s = "MPR121 12 KEYS                  ";
                5'd27: s = "MCP3208 FSR                     ";
                5'd28: s = "GW2A-LV18                       ";
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
                4'd6: s = "PEDAL UP";
                4'd7: s = "PEDAL DN";
                4'd8: s = "PAUSED  ";
                4'd9: s = "SONG 1  ";
                4'd10: s = "SONG 2  ";
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
        input [3:0] idx;
        reg [3:0] tens;
        reg [3:0] ones;
        begin
            tens = (value / 10) % 10;
            ones = value % 10;
            dec2_char = idx>1 ? 8'h20 : idx[0] ? digit_char(ones) : digit_char(tens);
        end
    endfunction

    function [7:0] dec3_char;
        input [7:0] value;
        input [3:0] idx;
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
                2'd2: dec3_char = digit_char(ones);
                default: dec3_char = 8'h20;
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
        input [3:0] idx;
        reg [3:0] pc;
        reg [3:0] octave;
        begin
            pc = pitch % 12;
            octave = (pitch / 12 == 0) ? 4'd0 : (pitch / 12 - 1);
            case (idx)
                2'd0: note_char = note_letter(pc);
                2'd1: note_char = is_sharp(pc) ? "#" : 8'h20;
                2'd2: note_char = digit_char(octave);
                default: note_char = 8'h20;
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
        input [5:0] active;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: poly_char = dec2_char({2'd0,active},1'b0);
                3'd1: poly_char = dec2_char({2'd0,active},1'b1);
                3'd2: poly_char = "/";
                3'd3: poly_char = st[62] ? "3" : "0";
                default: poly_char = st[62] ? "2" : "8";
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
    reg [4:0] voice_index;
    reg [10:0] voice_dx;
    reg [9:0] voice_dy;
    reg [2:0] voice_col;
    reg [4:0] voice_cell;
    reg [6:0] voice_local;
    reg [1:0] voice_row;

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
        voice_dx=x-11'd56;voice_dy=y-10'd208;
        voice_cell=grid_cell(voice_dx[9:5]);voice_col=voice_cell[4:2];
        voice_local={voice_cell[1:0],voice_dx[4:0]};
        voice_row=voice_dy[7:6];
        voice_index={voice_row,voice_col};

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
        else if (VOICE_GRID && x>=11'd440 && x<11'd568 && y>=10'd160 && y<10'd176) begin
            text_on=1;char_code=word_char(st[41] ? 4'd7 : 4'd6,(x-11'd440)>>4);
            font_row=(y-10'd160)>>1;bit_index=((x-11'd440)>>1)&7;
            color=st[41] ? C_GREEN : C_GRAY;
        end
        else if (VOICE_GRID && x>=11'd632 && x<11'd760 && y>=10'd160 && y<10'd176) begin
            text_on=1;char_code=word_char(st[59] ? 4'd10 : 4'd9,(x-11'd632)>>4);
            font_row=(y-10'd160)>>1;bit_index=((x-11'd632)>>1)&7;color=C_CYAN;
        end
        else if (VOICE_GRID && x>=11'd680 && x<11'd808 &&
                 y>=10'd224 && y<10'd256) begin
            text_on=1'b1;
            char_code=note_char(st[22:16],(x-11'd680)>>5);
            font_row=(y-10'd224)>>2;
            bit_index=((x-11'd680)>>2)&7;
            color=C_WHITE;
        end
        // Dynamic note labels inside the twelve pads, scale 2.
        else if (1'b0 && VOICE_GRID && x>=56 && x<824 && y>=208 && y<464 &&
                 voice_local>=28 && voice_local<60 &&
                 voice_dy[5:0]>=20 && voice_dy[5:0]<36) begin
            text_on=1'b1;
            char_code=dec2_char({3'd0,voice_index}+8'd1,((voice_local-28)>>4)&1);
            font_row=(voice_dy[5:0]-20)>>1;
            bit_index=((voice_local-28)>>1)&7;
            color=voice_mask[voice_index] ? C_WHITE : C_GRAY;
        end
        else if (!VOICE_GRID && key_label_hit) begin
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
                    5'd1: char_code = word_char(st[39] ? (st[63] ? 4'd8 : 4'd3) : 4'd2, (x - 11'd1092) >> 4);
                    5'd2: begin char_code = word_char(st[44] ? 4'd4 : 4'd5, (x - 11'd1092) >> 4); color = st[44] ? C_RED : C_GREEN; end
                    5'd3: char_code = dec2_char({2'd0,st[61:60],st[15:12]}, (x - 11'd1092) >> 4);
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
        else if (!VOICE_GRID && (x >= 11'd56) && (x < 11'd200) && (y >= 10'd544) && (y < 10'd560)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd13, (x - 11'd56) >> 4);
            font_row  = ((y - 10'd544) >> 1) & 7;
            bit_index = ((x - 11'd56) >> 1) & 7;
            color     = C_GRAY;
        end
        else if (!VOICE_GRID && (x >= 11'd760) && (x < 11'd840) && (y >= 10'd544) && (y < 10'd560)) begin
            text_on   = 1'b1;
            char_code = poly_char({st[61:60],st[15:12]}, (x - 11'd760) >> 4);
            font_row  = ((y - 10'd544) >> 1) & 7;
            bit_index = ((x - 11'd760) >> 1) & 7;
            color     = C_GREEN;
        end
        // Visual feedback labels.  The underlying pixels are generated from
        // the audio-domain snapshot rather than a computer-side GUI.
        else if ((x >= 11'd932) && (x < 11'd1060) && (y >= 10'd480) && (y < 10'd492)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd21, (x - 11'd932) >> 4);
            font_row  = ((y - 10'd480) >> 1) & 7;
            bit_index = ((x - 11'd932) >> 1) & 7;
            color     = C_CYAN;
        end
        else if ((x >= 11'd932) && (x < 11'd1060) && (y >= 10'd536) && (y < 10'd548)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd22, (x - 11'd932) >> 4);
            font_row  = ((y - 10'd536) >> 1) & 7;
            bit_index = ((x - 11'd932) >> 1) & 7;
            color     = C_GREEN;
        end
        else if ((x >= 11'd132) && (x < 11'd260) && (y >= 10'd576) && (y < 10'd588)) begin
            text_on   = 1'b1;
            char_code = static_char(5'd23, (x - 11'd132) >> 4);
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
            char_code = static_char(VOICE_GRID ? 5'd25 : 5'd16, (x - 11'd536) >> 4);
            font_row  = ((y - 10'd656) >> 1) & 7;
            bit_index = ((x - 11'd536) >> 1) & 7;
            color     = C_GRAY;
        end
        else if ((x >= 11'd744) && (x < 11'd936) && (y >= 10'd656) && (y < 10'd672)) begin
            text_on   = 1'b1;
            char_code = static_char(VOICE_GRID ? 5'd24 : 5'd17, (x - 11'd744) >> 4);
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
        else if (VOICE_GRID && x>=11'd56 && x<11'd280 &&
                 y>=10'd688 && y<10'd704) begin
            text_on=1'b1;char_code=static_char(5'd28,(x-11'd56)>>4);
            font_row=(y-10'd688)>>1;bit_index=((x-11'd56)>>1)&7;color=C_CYAN;
        end
        else if (VOICE_GRID && x>=11'd312 && x<11'd536 &&
                 y>=10'd688 && y<10'd704) begin
            text_on=1'b1;char_code=static_char(5'd26,(x-11'd312)>>4);
            font_row=(y-10'd688)>>1;bit_index=((x-11'd312)>>1)&7;color=C_CYAN;
        end
        else if (VOICE_GRID && x>=11'd568 && x<11'd792 &&
                 y>=10'd688 && y<10'd704) begin
            text_on=1'b1;char_code=static_char(5'd27,(x-11'd568)>>4);
            font_row=(y-10'd688)>>1;bit_index=((x-11'd568)>>1)&7;color=C_CYAN;
        end
    end
endmodule

// Compact 1024x600 presentation. Status fields retain the original st encoding.
module dashboard_text_1024(
    input wire [10:0] x,input wire [9:0] y,input wire [63:0] st,
    output reg text_on,output reg [7:0] char_code,
    output reg [2:0] font_row,output reg [2:0] bit_index,
    output reg [23:0] color
);
    reg [5:0] id;
    reg [4:0] idx;
    reg [10:0] ox;
    reg [9:0] oy;
    reg [1:0] scale;
    reg [3:0] row;
    reg [127:0] s;
    reg [7:0] v;
    function [7:0] digit;
        input [7:0] n;
        begin digit=(n<10) ? (8'd48+n) : 8'd32;end
    endfunction
    always @* begin
        text_on=0;char_code=8'd32;font_row=0;bit_index=0;color=24'he8f0ff;
        id=0;idx=0;ox=0;oy=0;scale=0;row=0;s=0;v=0;
        if(x>=24 && x<536 && y>=20 && y<52) begin id=0;ox=24;oy=20;scale=2;color=24'h20d0f0;text_on=1;end
        else if(x>=640 && x<992 && y>=28 && y<60) begin id=1;ox=640;oy=28;scale=2;color=24'h40e090;text_on=1;end
        else if(x>=40 && x<296 && y>=108 && y<124) begin id=2;ox=40;oy=108;scale=1;color=24'h20d0f0;text_on=1;end
        else if(x>=560 && x<728 && y>=108 && y<124) begin id=32;ox=560;oy=108;scale=1;color=24'h40e090;text_on=1;end
        else if(x>=560 && x<688 && y>=140 && y<156) begin id=33;ox=560;oy=140;scale=1;color=24'hffa030;text_on=1;end
        else if(x>=600 && x<728 && y>=448 && y<464) begin id=3;ox=600;oy=448;scale=1;text_on=1;end
        else if(x>=776 && x<968 && y>=108 && y<124) begin id=4;ox=776;oy=108;scale=1;color=24'h20d0f0;text_on=1;end
        else if(x>=780 && x<992 && y>=148 && y<484) begin
            if(y>=468) row=8;
            else if(y>=428) row=7;
            else if(y>=388) row=6;
            else if(y>=348) row=5;
            else if(y>=308) row=4;
            else if(y>=268) row=3;
            else if(y>=228) row=2;
            else if(y>=188) row=1;
            oy=148+row*40;scale=1;text_on=(y<oy+16);
            // Long labels get 8 full cells. Their 3-digit values fit farther
            // right; the sample-rate row uses a short FS label to retain units.
            if((row==5 || row==6) && x<908) begin id=5+row;ox=780;color=24'h7890a8;end
            else if((row==5 || row==6) && x>=928) begin id=14+row;ox=928;color=24'he8f0ff;end
            else if(row==8 && x<812) begin id=13;ox=780;color=24'h7890a8;end
            else if(row==8 && x>=824) begin id=22;ox=824;color=24'he8f0ff;end
            else if(row!=5 && row!=6 && row!=8 && x<880) begin id=5+row;ox=780;color=24'h7890a8;end
            else if(row!=5 && row!=6 && row!=8 && x>=896) begin id=14+row;ox=896;color=24'he8f0ff;end
            else text_on=0;
        end
        else if(y>=552 && y<568 && x>=24 && x<1000) begin
            oy=552;scale=1;text_on=1;color=24'he8f0ff;
            if(x<216) begin id=23;ox=24;end
            else if(x<424) begin id=24;ox=216;end
            else if(x<648) begin id=25;ox=424;end
            else if(x<872) begin id=26;ox=648;end
            else begin id=27;ox=872;end
        end
        else if(y>=576 && y<592 && x>=24 && x<1000) begin
            oy=576;scale=1;text_on=1;color=24'h7890a8;
            if(x<264) begin id=28;ox=24;end
            else if(x<488) begin id=29;ox=264;end
            else if(x<744) begin id=30;ox=488;end
            else begin id=31;ox=744;end
        end
        if(text_on) begin
            idx=(x-ox)>>(3+scale);
            font_row=(y-oy)>>scale;
            bit_index=((x-ox)>>scale)&7;
            case(id)
                0:s="POLYTOUCH SYNTH ";
                1:s="1024X600 60     ";
                2:s="AUDIO WAVEFORM  ";
                3:s="                ";
                4:s="LIVE STATUS     ";
                5:s="INST            ";
                6:s="MODE            ";
                7:s="SOUND           ";
                8:s="VOICES          ";
                9:s="NOTE            ";
                10:s="VELOCITY        ";
                11:s="PRESSURE        ";
                12:s="TIMBRE          ";
                13:s="FS              ";
                14:begin if(st[43]) s="GUITAR          "; else s="PIANO           ";end
                15:begin if(st[39]) begin if(st[63]) s="PAUSED          "; else s="DEMO            ";end else s="MANUAL          ";end
                16:begin if(st[44]) s="MUTED           "; else s="LIVE            ";end
                22:s="46.875 KHZ      ";
                23:s="32 VOICES       ";
                24:s="USB KEYBOARD    ";
                25:s="512 PT WAVES    ";
                26:s="46.875 KHZ      ";
                27:s="GW2A-18         ";
                28:s="PCM5102A I2S    ";
                29:s="MCP3208 FSR     ";
                30:s="NO SOFT CPU     ";
                31:s="POLYTOUCH 2026  ";
                32:begin if(st[41]) s="PEDAL DOWN      "; else s="PEDAL UP        ";end
                33:begin if(st[59]) s="SONG 2          "; else s="SONG 1          ";end
                default:s="                ";
            endcase
            char_code=s[127-idx*8 -:8];
            if(id==17) begin
                if(idx==0) char_code=digit({2'd0,st[61:60],st[15:12]}/10);
                else if(idx==1) char_code=digit({2'd0,st[61:60],st[15:12]}%10);
                else if(idx==2) char_code="/";
                else if(idx==3) char_code="3";
                else if(idx==4) char_code="2";
            end
            if(id==18 || id==3) begin
                v=st[22:16];
                if(idx==0) char_code=digit(v/100);
                else if(idx==1) char_code=digit((v/10)%10);
                else if(idx==2) char_code=digit(v%10);
            end
            if(id==19 || id==20 || id==21) begin
                v=(id==19) ? st[30:23] : (id==20) ? st[38:31] : st[55:48];
                if(idx==0) char_code=digit(v/100);
                else if(idx==1) char_code=digit((v/10)%10);
                else if(idx==2) char_code=digit(v%10);
            end
        end
    end
endmodule
