// Audio-domain dashboard status snapshot. A 1 kHz toggle carries a 64-bit bus
// across into the pixel clock domain; the bus is stable for roughly 1 ms before
// the toggle edge is observed, so no multi-bit CDC encoding is required.
module ui_status_export #(
    parameter integer VOICES = 8,
    parameter integer TICK_DIV = 1000
) (
    input  wire                       clk,
    input  wire                       rst,
    input  wire [VOICES-1:0]          v_gate,
    input  wire [VOICES*7-1:0]        v_note,
    input  wire [VOICES*8-1:0]        v_vel,
    input  wire [11:0]                pressure_level,
    input  wire                       demo_mode,
    input  wire                       muted,
    input  wire                       piano_mode,
    input  wire                       guitar_mode,
    input  wire                       chord_set,
    input  wire                       show_timbre,
    input  wire [1:0]                 instrument_id,
    input  wire [1:0]                 tempo_sel,
    input  wire [7:0]                 timbre_target,
    input  wire [2:0]                 piano_tone,
    output reg  [63:0]                status,
    output reg                        status_toggle
);
    reg [3:0]  active_count;
    reg [6:0]  lead_note;
    reg [7:0]  lead_vel;
    reg [11:0] note_mask;
    integer i;

    always @* begin
        active_count = 4'd0;
        lead_note    = 7'd0;
        lead_vel     = 8'd0;
        note_mask    = 12'd0;
        for (i = 0; i < VOICES; i = i + 1) begin
            if (v_gate[i]) begin
                active_count = active_count + 1'b1;
                lead_note    = v_note[i*7 +: 7];
                lead_vel     = v_vel[i*8 +: 8];
                if ((v_note[i*7 +: 7] >= 7'd60) && (v_note[i*7 +: 7] < 7'd72))
                    note_mask[v_note[i*7 +: 7] - 7'd60] = 1'b1;
            end
        end
    end

    localparam integer CNT_W = (TICK_DIV > 1) ? $clog2(TICK_DIV) : 1;
    reg [CNT_W-1:0] tick_count;

    always @(posedge clk) begin
        if (rst) begin
            tick_count    <= {CNT_W{1'b0}};
            status        <= 64'd0;
            status_toggle <= 1'b0;
        end else if (tick_count == TICK_DIV-1) begin
            tick_count    <= {CNT_W{1'b0}};
            status        <= {
                4'd0,
                chord_set, show_timbre,
                tempo_sel, timbre_target, piano_tone,
                muted, guitar_mode, piano_mode, instrument_id, demo_mode,
                pressure_level[11:4], lead_vel, lead_note, active_count, note_mask
            };
            status_toggle <= ~status_toggle;
        end else begin
            tick_count <= tick_count + 1'b1;
        end
    end

`ifdef SIMULATION
    initial if (VOICES < 1 || VOICES > 8 || TICK_DIV < 1)
        $fatal(1, "UI_STATUS_EXPORT_PARAM_INVALID");
`endif
endmodule

// Pixel-domain receiver for the snapshot above. The first two registers are a
// standard asynchronous toggle synchronizer; the wide bus is sampled only
// after the synchronized toggle changes.
module ui_status_sync (
    input  wire        clk,
    input  wire        rst,
    input  wire [63:0] async_status,
    input  wire        async_toggle,
    output reg  [63:0] status,
    output reg         toggle_seen
);
    (* ASYNC_REG = "TRUE" *) reg toggle_meta;
    (* ASYNC_REG = "TRUE" *) reg toggle_sync;

    always @(posedge clk) begin
        if (rst) begin
            toggle_meta <= 1'b0;
            toggle_sync <= 1'b0;
            toggle_seen <= 1'b0;
            status      <= 64'd0;
        end else begin
            toggle_meta <= async_toggle;
            toggle_sync <= toggle_meta;
            if (toggle_sync != toggle_seen) begin
                status      <= async_status;
                toggle_seen <= toggle_sync;
            end
        end
    end
endmodule
