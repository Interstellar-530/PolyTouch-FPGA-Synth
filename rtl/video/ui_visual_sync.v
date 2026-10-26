// Stable-bus/toggle CDC for the visual snapshot.  The source bus remains
// unchanged for an entire 64-sample window, so the pixel domain samples it only
// after the synchronized toggle changes.
module ui_visual_sync (
    input  wire         clk,
    input  wire         rst,
    input  wire [255:0] async_waveform,
    input  wire [63:0]  async_spectrum,
    input  wire [63:0]  async_lissajous,
    input  wire         async_toggle,
    output reg  [255:0] waveform,
    output reg  [63:0]  spectrum,
    output reg  [63:0]  lissajous,
    output reg          toggle_seen
);
    (* ASYNC_REG = "TRUE" *) reg toggle_meta;
    (* ASYNC_REG = "TRUE" *) reg toggle_sync;

    always @(posedge clk) begin
        if (rst) begin
            toggle_meta <= 1'b0;
            toggle_sync <= 1'b0;
            toggle_seen <= 1'b0;
            waveform    <= 512'd0;
            spectrum    <= 64'd0;
            lissajous   <= 64'd0;
        end else begin
            toggle_meta <= async_toggle;
            toggle_sync <= toggle_meta;
            if (toggle_sync != toggle_seen) begin
                waveform    <= async_waveform;
                spectrum    <= async_spectrum;
                lissajous   <= async_lissajous;
                toggle_seen <= toggle_sync;
            end
        end
    end
endmodule

