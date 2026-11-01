// MIDI-style sustain: keep Note Offs while down, drain them on release.
// The source FIFO and held output provide backpressure during the release scan.
module sustain_pedal(
    input wire clk,rst,clear,pedal,
    input wire in_valid,input wire [15:0] in_word,output wire in_ready,
    output reg out_valid,output reg [15:0] out_word,input wire out_ready
);
    reg [127:0] held=0,deferred=0;
    reg pedal_q=0,scanning=0;
    reg [6:0] ptr=0;
    wire room=!out_valid || out_ready;
    wire falling=pedal_q && !pedal;
    assign in_ready=room && !scanning && !falling && !clear && !rst;
    always @(posedge clk) begin
        if(rst || clear) begin
            held<=0;deferred<=0;pedal_q<=0;scanning<=0;ptr<=0;out_valid<=0;out_word<=0;
        end else begin
            pedal_q<=pedal;
            if(out_valid && out_ready) out_valid<=0;
            if(falling) begin scanning<=1;ptr<=0;end
            else if(scanning && room) begin
                if(!pedal && deferred[ptr] && !held[ptr]) begin
                    out_valid<=1;out_word<={1'b0,ptr,8'd0};deferred[ptr]<=0;
                end
                if(ptr==127 || pedal) scanning<=0;else ptr<=ptr+1'b1;
            end else if(in_valid && in_ready) begin
                held[in_word[14:8]]<=in_word[15];
                if(in_word[15]) begin
                    deferred[in_word[14:8]]<=0;
                    out_valid<=1;out_word<=in_word;
                end else if(pedal) deferred[in_word[14:8]]<=1;
                else begin
                    deferred[in_word[14:8]]<=0;
                    out_valid<=1;out_word<=in_word;
                end
            end
        end
    end
endmodule
