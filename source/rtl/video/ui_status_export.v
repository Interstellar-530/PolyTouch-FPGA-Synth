// Audio-domain dashboard status snapshot. A 1 kHz toggle carries a 64-bit bus
// across into the pixel clock domain; the bus is stable for roughly 1 ms before
// the toggle edge is observed, so no multi-bit CDC encoding is required.
module ui_status_export #(
    parameter integer VOICES = 8,
    parameter integer TICK_DIV = 1000,
    parameter integer TRANSPORT_ENABLE = 0
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
    input  wire                       paused,
    output reg  [63:0]                status,
    output reg  [31:0]                active_mask,
    output reg                        status_toggle
);
    reg [5:0]  active_count;
    reg [6:0]  lead_note;
    reg [7:0]  lead_vel;
    reg [11:0] note_mask;
    reg [31:0] scan_mask;
    integer i;

    generate if(VOICES<=8) begin: g_small
    always @* begin
        active_count = 6'd0;
        lead_note    = 7'd0;
        lead_vel     = 8'd0;
        note_mask    = 12'd0;
        for (i = 0; i < VOICES; i = i + 1) begin
            if (v_gate[i]) begin
                active_count = active_count + 1'b1;
                lead_note    = v_note[i*7 +: 7];
                lead_vel     = v_vel[i*8 +: 8];
                note_mask[v_note[i*7 +: 7] % 12] = 1'b1;
            end
        end
    end
    end else begin: g_scan
        // Snapshot then scan: no 32-way priority/count/modulo chain at 54 MHz.
        reg [VOICES-1:0] gate_hold;
        reg [VOICES*7-1:0] note_hold;
        reg [VOICES*8-1:0] vel_hold;
        reg [4:0] ptr;
        reg busy,phase,sel_gate;
        reg [6:0] sel_note;
        reg [7:0] sel_vel;
        reg [5:0] count_work;
        reg [6:0] lead_work;
        reg [7:0] vel_work;
        reg [11:0] mask_work;
        wire [3:0] pc=sel_note%12;
        always @(posedge clk) begin
            if(rst) begin
                gate_hold<=0;note_hold<=0;vel_hold<=0;ptr<=0;busy<=0;phase<=0;
                sel_gate<=0;sel_note<=0;sel_vel<=0;count_work<=0;lead_work<=0;vel_work<=0;mask_work<=0;
                active_count<=0;lead_note<=0;lead_vel<=0;note_mask<=0;scan_mask<=0;
            end else if(!busy) begin
                gate_hold<=v_gate;note_hold<=v_note;vel_hold<=v_vel;
                ptr<=0;busy<=1;phase<=0;count_work<=0;lead_work<=0;vel_work<=0;mask_work<=0;
            end else if(!phase) begin
                sel_gate<=gate_hold[ptr];sel_note<=note_hold[ptr*7 +: 7];sel_vel<=vel_hold[ptr*8 +: 8];
                phase<=1;
            end else begin
                if(sel_gate) begin
                    count_work<=count_work+1'b1;lead_work<=sel_note;vel_work<=sel_vel;mask_work[pc]<=1;
                end
                phase<=0;
                if(ptr==VOICES-1) begin
                    busy<=0;
                    active_count<=count_work+sel_gate;
                    scan_mask<=gate_hold;
                    lead_note<=sel_gate ? sel_note : lead_work;
                    lead_vel<=sel_gate ? sel_vel : vel_work;
                    note_mask<=mask_work | (sel_gate ? (12'b1<<pc) : 12'd0);
                end else ptr<=ptr+1'b1;
            end
        end
    end endgenerate

    localparam integer CNT_W = (TICK_DIV > 1) ? $clog2(TICK_DIV) : 1;
    reg [CNT_W-1:0] tick_count;

    always @(posedge clk) begin
        if (rst) begin
            tick_count    <= {CNT_W{1'b0}};
            status        <= 64'd0;
            active_mask   <= 32'd0;
            status_toggle <= 1'b0;
        end else if (tick_count == TICK_DIV-1) begin
            tick_count    <= {CNT_W{1'b0}};
            status        <= {
                (TRANSPORT_ENABLE ? paused : 1'b0), (VOICES==32), active_count[5:4],
                chord_set, show_timbre,
                tempo_sel, timbre_target, piano_tone,
                muted, guitar_mode, piano_mode, instrument_id, demo_mode,
                pressure_level[11:4], lead_vel, lead_note, active_count[3:0], note_mask
            };
            if(VOICES<=8) active_mask <= {{(32-VOICES){1'b0}},v_gate};
            else active_mask <= scan_mask;
            status_toggle <= ~status_toggle;
        end else begin
            tick_count <= tick_count + 1'b1;
        end
    end

`ifdef SIMULATION
    initial if (VOICES < 1 || VOICES > 32 || TICK_DIV < 1)
        $fatal(1, "UI_STATUS_EXPORT_PARAM_INVALID");
`endif
endmodule

// Pixel-domain receiver for the snapshot above. The first two registers are a
// standard asynchronous toggle synchronizer; the wide bus is sampled only
// after the synchronized toggle changes.
module ui_status_sync #(parameter integer WIDTH=64) (
    input  wire        clk,
    input  wire        rst,
    input  wire [WIDTH-1:0] async_status,
    input  wire        async_toggle,
    output reg  [WIDTH-1:0] status,
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
