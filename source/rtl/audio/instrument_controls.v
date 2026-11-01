// Board-only controls. One millisecond timebase shared by debounce, long press
// and LED overlay. S1 short press commits on release; long press never repeats.
module instrument_controls #(
    parameter integer CLK_HZ = 27000000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer LONG_PRESS_MS = 600,
    parameter integer SHOW_MS = 1000
) (
    input wire clk, input wire por, input wire rst,
    input wire key_s1, input wire key_s2,
    input wire timbre_valid, input wire [7:0] timbre_value,
    output reg s1_short, output reg s2_press,
    output reg [7:0] timbre_target,
    output wire show_timbre, output reg [1:0] preset
);
    localparam integer DIV = CLK_HZ / 1000;
    localparam integer DW = (DIV > 1) ? $clog2(DIV) : 1;
    localparam integer BW = (DEBOUNCE_MS > 1) ? $clog2(DEBOUNCE_MS) : 1;
    localparam integer LW = $clog2(LONG_PRESS_MS + 1);
    localparam integer SW = $clog2(SHOW_MS + 1);
    reg [DW-1:0] ms_count;
    wire ms_tick = (ms_count == DIV-1);
    reg [1:0] sync1, sync2, stable;
    reg [BW-1:0] db1, db2;
    reg [LW-1:0] held_ms;
    reg long_done;
    reg [SW-1:0] show_left;
    wire release1 = ms_tick && !sync2[0] && stable[0] && db1 == DEBOUNCE_MS-1;
    wire press2 = ms_tick && sync2[1] && !stable[1] && db2 == DEBOUNCE_MS-1;
    // Start counting after the accepted press. Cancel on an actual release,
    // before waiting for release debounce, to avoid a false long press.
    wire long1 = ms_tick && stable[0] && sync2[0] && !long_done && held_ms == LONG_PRESS_MS-1;
    function [7:0] weight;
        input [1:0] index;
        case(index)
            0: weight=0; 1: weight=64; 2: weight=160; 3: weight=255;
        endcase
    endfunction
    assign show_timbre = (show_left != 0);
    always @(posedge clk) begin
        if (rst) begin
            ms_count<=0; sync1<=0; sync2<=0; stable<=0;
            db1<=0; db2<=0; held_ms<=0; long_done<=0;
            s1_short<=0; s2_press<=0;
        end else begin
            sync1<={~key_s2,~key_s1}; sync2<=sync1;
            ms_count<=ms_tick ? 0 : ms_count+1'b1;
            s1_short<=0; s2_press<=0;
            if (ms_tick) begin
                if(sync2[0]==stable[0]) db1<=0;
                else if(db1==DEBOUNCE_MS-1) begin stable[0]<=sync2[0]; db1<=0; end
                else db1<=db1+1'b1;
                if(sync2[1]==stable[1]) db2<=0;
                else if(db2==DEBOUNCE_MS-1) begin stable[1]<=sync2[1]; db2<=0; end
                else db2<=db2+1'b1;
                if (!stable[0]) begin held_ms<=0; long_done<=0; end
                else if (sync2[0] && !long_done) begin
                    if(long1) long_done<=1;
                    else held_ms<=held_ms+1'b1;
                end
                s1_short<=release1 && !long_done;
                s2_press<=press2;
            end
        end
    end
    // Selection survives S3, matching chord/tempo settings. UART wins a same
    // cycle conflict; the next board preset advances from the nearest preset.
    always @(posedge clk) begin
        if(por) begin timbre_target<=64; preset<=1; show_left<=0; end
        else begin
            if(ms_tick && show_left!=0 && !rst) show_left<=show_left-1'b1;
            if(long1 && !rst) begin
                preset<=preset+1'b1; timbre_target<=weight(preset+2'd1); show_left<=SHOW_MS;
            end
            if(timbre_valid && !rst) begin
                timbre_target<=timbre_value; show_left<=SHOW_MS;
                if(timbre_value<32) preset<=0;
                else if(timbre_value<112) preset<=1;
                else if(timbre_value<208) preset<=2;
                else preset<=3;
            end
        end
    end
`ifdef SIMULATION
    initial if(CLK_HZ<1000 || CLK_HZ%1000!=0 || DEBOUNCE_MS<1 || LONG_PRESS_MS<1 || SHOW_MS<1)
        $fatal(1,"Invalid instrument control timing");
`endif
endmodule
