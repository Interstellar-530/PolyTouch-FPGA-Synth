`timescale 1ns/1ps
module tb_hdmi_timing;
    reg clk = 1'b0;
    reg rst = 1'b1;
    wire hsync, vsync, de, frame_start;
    wire [10:0] x;
    wire [9:0]  y;
    integer de_count = 0;
    integer line_count = 0;
    integer hsync_count = 0;
    integer vsync_count = 0;
    reg seen_frame = 1'b0;

    always #5 clk = ~clk;

    hdmi_720p_timing dut (
        .pix_clk(clk), .rst(rst), .hsync(hsync), .vsync(vsync),
        .de(de), .x(x), .y(y), .frame_start(frame_start)
    );

    always @(posedge clk) begin
        if (rst) begin
            de_count <= 0;
            line_count <= 0;
            hsync_count <= 0;
            vsync_count <= 0;
            seen_frame <= 1'b0;
        end else if (frame_start) begin
            if (seen_frame) begin
                if (de_count != 1280*720)
                    $fatal(1, "HDMI_DE_COUNT=%0d", de_count);
                if (line_count != 720)
                    $fatal(1, "HDMI_LINE_COUNT=%0d", line_count);
                if (hsync_count != 750*40)
                    $fatal(1, "HDMI_HSYNC_COUNT=%0d", hsync_count);
                if (vsync_count != 5*1650)
                    $fatal(1, "HDMI_VSYNC_COUNT=%0d", vsync_count);
                $display("HDMI_TIMING_PASS pixels=%0d lines=%0d", de_count, line_count);
                $finish;
            end
            seen_frame <= 1'b1;
            de_count <= 0;
            line_count <= 0;
            hsync_count <= 0;
            vsync_count <= 0;
        end else if (seen_frame) begin
            if (de) begin
                de_count <= de_count + 1;
                if (x == 0) line_count <= line_count + 1;
            end
            if (hsync) hsync_count <= hsync_count + 1;
            if (vsync) vsync_count <= vsync_count + 1;
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        rst <= 1'b0;
        repeat (3000000) @(posedge clk);
        $fatal(1, "HDMI_TIMING_TIMEOUT");
    end
endmodule
