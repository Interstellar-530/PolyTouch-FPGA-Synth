// Toolchain smoke design only. Not the instrument RTL and not for programming.
module top(input wire clk, output wire led);
    reg [23:0] count = 24'd0;
    always @(posedge clk) count <= count + 1'b1;
    assign led = count[23];
endmodule
