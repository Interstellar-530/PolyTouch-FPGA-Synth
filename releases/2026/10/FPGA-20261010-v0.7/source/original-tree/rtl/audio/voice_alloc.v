// Four-voice note allocator.
//
// This module is the boundary the future performance keyboard plugs into:
// anything that can present {valid, on/off, note, velocity} gets a voice.
// Today the sequencer feeds it; later the MPR121 touch controller or the UART
// controller feeds the same port.
//
// Allocation order:
//   1. a voice whose envelope has already reached zero,
//   2. the oldest voice that is in release,
//   3. the oldest voice still held.
// That keeps a held chord from being cut when the melody retriggers.
module voice_alloc #(
    parameter integer VOICES = 4
)(
    input  wire                clk,
    input  wire                rst,
    input  wire                ev_valid,
    input  wire                ev_on,        // 1 = note on, 0 = note off
    input  wire [6:0]          ev_note,
    input  wire [7:0]          ev_vel,
    input  wire                panic,        // release every voice
    input  wire [VOICES-1:0]   voice_idle,   // from poly_voice
    output reg  [VOICES-1:0]   v_gate,
    output reg  [VOICES*7-1:0] v_note,
    output reg  [VOICES*8-1:0] v_vel,
    output wire [VOICES-1:0]   v_busy
);

    reg [VOICES*16-1:0] v_age;
    reg [15:0]          age_cnt;

    integer k;
    reg [VOICES-1:0] free_mask;
    reg [VOICES-1:0] rel_mask;
    reg [7:0]        pick;
    reg              picked;
    reg [15:0]       best_age;

    assign v_busy = v_gate;

    // ------------------------------------------------------- pick a voice --
    always @(*) begin
        free_mask = {VOICES{1'b0}};
        rel_mask  = {VOICES{1'b0}};
        best_age  = 16'hFFFF;      // assigned on every path so no latch is inferred
        for (k = 0; k < VOICES; k = k + 1) begin
            free_mask[k] = voice_idle[k] & ~v_gate[k];
            rel_mask[k]  = ~v_gate[k];
        end

        pick   = 8'd0;
        picked = 1'b0;

        // 1. envelope already at zero
        for (k = 0; k < VOICES; k = k + 1)
            if (!picked && free_mask[k]) begin
                pick   = k[7:0];
                picked = 1'b1;
            end

        // 2. oldest voice in release
        if (!picked) begin
            best_age = 16'hFFFF;
            for (k = 0; k < VOICES; k = k + 1)
                if (rel_mask[k] && (v_age[k*16 +: 16] < best_age)) begin
                    best_age = v_age[k*16 +: 16];
                    pick     = k[7:0];
                    picked   = 1'b1;
                end
        end

        // 3. oldest held voice
        if (!picked) begin
            best_age = 16'hFFFF;
            for (k = 0; k < VOICES; k = k + 1)
                if (v_age[k*16 +: 16] < best_age) begin
                    best_age = v_age[k*16 +: 16];
                    pick     = k[7:0];
                end
        end
    end

    // ------------------------------------------------------ update voices --
    always @(posedge clk) begin
        if (rst) begin
            v_gate  <= {VOICES{1'b0}};
            v_note  <= {(VOICES*7){1'b0}};
            v_vel   <= {(VOICES*8){1'b0}};
            v_age   <= {(VOICES*16){1'b0}};
            age_cnt <= 16'd0;
        end else if (panic) begin
            v_gate <= {VOICES{1'b0}};
        end else if (ev_valid) begin
            if (ev_on) begin
                v_gate[pick]        <= 1'b1;
                v_note[pick*7 +: 7] <= ev_note;
                v_vel[pick*8 +: 8]  <= ev_vel;
                v_age[pick*16 +: 16] <= age_cnt;
                age_cnt             <= age_cnt + 16'd1;
            end else begin
                for (k = 0; k < VOICES; k = k + 1)
                    if (v_gate[k] && (v_note[k*7 +: 7] == ev_note))
                        v_gate[k] <= 1'b0;
            end
        end
    end

endmodule
