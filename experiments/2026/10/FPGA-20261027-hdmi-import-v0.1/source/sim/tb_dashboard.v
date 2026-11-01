`timescale 1ns/1ps
module tb_dashboard;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg de = 1'b1;
    reg [10:0] x = 11'd0;
    reg [9:0]  y = 10'd0;
    reg [63:0] st = 64'd0;
    reg [255:0] waveform = 256'd0;
    reg [63:0] spectrum = 64'd0;
    reg [63:0] lissajous = 64'd0;
    wire text_on;
    wire [7:0] text_char;
    wire [2:0] text_row;
    wire [2:0] text_bit;
    wire [23:0] text_color;
    wire [7:0] rr, gg, bb;
    wire [7:0] font_byte;
    reg [8:0] font_addr = 9'd0;
    reg       font_row_lsb = 1'b0;

    always #5 clk = ~clk;

    dashboard_text_mux u_text (
        .x(x), .y(y), .st(st), .text_on(text_on), .char_code(text_char),
        .font_row(text_row), .bit_index(text_bit), .color(text_color)
    );

    dashboard_font_prom u_font (
        .clk(clk), .ce(1'b1), .rst(rst), .addr(font_addr),
        .row_lsb(font_row_lsb), .dout(font_byte)
    );

    dashboard_renderer u_renderer (
        .pix_clk(clk), .rst(rst), .de(de), .x(x), .y(y), .st(st),
        .waveform(waveform), .spectrum(spectrum), .lissajous(lissajous),
        .rgb_r(rr), .rgb_g(gg), .rgb_b(bb)
    );

    task expect_char;
        input [10:0] tx;
        input [9:0]  ty;
        input [7:0]  expected;
        input [255:0] name;
        begin
            x = tx;
            y = ty;
            #1;
            if (!text_on || text_char !== expected)
                $fatal(1, "TEXT_MISS %0s x=%0d y=%0d on=%b got=%02h exp=%02h",
                       name, tx, ty, text_on, text_char, expected);
        end
    endtask

    initial begin
        st[15:12] = 4'd3;
        st[22:16] = 7'd61;
        st[30:23] = 8'd100;
        st[38:31] = 8'd200;
        st[55:48] = 8'd252;

        repeat (3) @(posedge clk);
        rst <= 1'b0;

        expect_char(11'd48,  10'd32,  "P", "title");
        expect_char(11'd912, 10'd40,  "H", "header");
        expect_char(11'd1092,10'd208, "P", "piano");
        st[43] = 1'b1;
        expect_char(11'd1092,10'd208, "G", "guitar");
        st[43] = 1'b0;
        expect_char(11'd1092,10'd336, "C", "note");
        expect_char(11'd102, 10'd264, "C", "key-label");
        expect_char(11'd1092,10'd464, "4", "sample-rate");

        // Font byte for 'A' row 1: (0x41-0x20)*8 + 1 = 265.
        font_addr = 9'd132;
        font_row_lsb = 1'b1;
        repeat (4) @(posedge clk);
        #1;
        if (font_byte !== 8'h44)
            $fatal(1, "FONT_ROM got=%02h exp=44", font_byte);

        // Geometry: inactive then active pad 0.
        st[0] = 1'b0;
        x = 11'd60;
        y = 10'd220;
        repeat (4) @(posedge clk);
        #1;
        if ({rr,gg,bb} !== 24'h1B2A49)
            $fatal(1, "KEY_IDLE_COLOR=%06h", {rr,gg,bb});
        st[0] = 1'b1;
        repeat (4) @(posedge clk);
        #1;
        if ({rr,gg,bb} !== 24'h176B72)
            $fatal(1, "KEY_ACTIVE_COLOR=%06h", {rr,gg,bb});

        waveform[63*4 +: 4] = 4'd2;
        x = 11'd1184;
        y = 10'd500;
        repeat (4) @(posedge clk);
        #1;
        if ({rr,gg,bb} !== 24'h20D0F0)
            $fatal(1, "WAVEFORM_COLOR=%06h", {rr,gg,bb});

        spectrum[3*8 +: 8] = 8'hff;
        x = 11'd1048;
        y = 10'd580;
        repeat (4) @(posedge clk);
        #1;
        if ({rr,gg,bb} !== 24'h40E090)
            $fatal(1, "SPECTRUM_COLOR=%06h", {rr,gg,bb});

        lissajous[3*8 + 3] = 1'b1;
        x = 11'd86;
        y = 10'd598;
        repeat (4) @(posedge clk);
        #1;
        if ({rr,gg,bb} !== 24'hFFA030)
            $fatal(1, "PHASE_COLOR=%06h", {rr,gg,bb});

        $display("DASHBOARD_PASS title/header/dynamic/key/font/geometry/wave/spectrum/phase");
        $finish;
    end

    initial begin
        repeat (200) @(posedge clk);
        $fatal(1, "DASHBOARD_TIMEOUT");
    end
endmodule
