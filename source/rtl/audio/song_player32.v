// Event ROM sequencer; shared by the generated score and listening preview.
// 0000 loops; 00nn waits nn sixteenth units; all other words are note events.
module song_player32 #(
    parameter integer UNIT_SAMPLES=8681,
    parameter integer SECOND_UNIT_SAMPLES=(UNIT_SAMPLES*81+50)/100,
    parameter integer SONG_SELECT_ENABLE=1
)(
    input wire clk,rst,sample_tick,restart,song_select,chord_set,
    input wire [1:0] tempo_sel,
    input wire ev_ready,
    output wire ev_wr,
    output wire [15:0] ev_data,
    output wire [7:0] mel_idx_dbg,
    output wire [5:0] chord_idx_dbg
);
    `include "rtl/audio/arrangement32_layout.vh"
    reg [12:0] address;
    wire [12:0] base=(SONG_SELECT_ENABLE && song_select)?SECOND_BASE:13'd0;
    wire [15:0] word;
    arrangement32_rom rom(.clk(clk),.addr(address),.data(word));
    reg [2:0] state;
    localparam FETCH=0, SETTLE=1, DECODE=2, SEND=3, WAIT_TIME=4;
    reg [7:0] units_left;
    reg [15:0] samples_left;
    reg [15:0] event_word;
    wire [31:0] period=((SONG_SELECT_ENABLE && song_select)?SECOND_UNIT_SAMPLES:UNIT_SAMPLES)*(tempo_sel+1);
    assign ev_wr=state==SEND;
    assign ev_data=event_word;
    assign mel_idx_dbg=address[7:0];
    assign chord_idx_dbg=address[12:7];
    always @(posedge clk) begin
        if(rst || restart) begin
            address<=base;state<=FETCH;units_left<=0;samples_left<=0;event_word<=0;
        end else case(state)
            FETCH: state<=SETTLE;
            SETTLE: state<=DECODE;
            DECODE: begin
                if(word==0) begin address<=base;state<=FETCH;end
                else if(word[15:8]==0) begin
                    units_left<=word[7:0];samples_left<=period[15:0]-1'b1;state<=WAIT_TIME;
                end else begin event_word<=word;state<=SEND;end
            end
            SEND: if(ev_ready) begin address<=address+1'b1;state<=FETCH;end
            WAIT_TIME: if(sample_tick) begin
                if(samples_left!=0) samples_left<=samples_left-1'b1;
                else if(units_left>1) begin units_left<=units_left-1'b1;samples_left<=period[15:0]-1'b1;end
                else begin address<=address+1'b1;state<=FETCH;end
            end
            default: state<=FETCH;
        endcase
    end
endmodule
