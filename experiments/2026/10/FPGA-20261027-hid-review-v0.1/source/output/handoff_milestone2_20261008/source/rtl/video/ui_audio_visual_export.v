// Audio-domain visual snapshot for the HDMI dashboard.
//
// The waveform row and phase plot are derived from the actual final audio
// sample.  Four bits per waveform column are enough for the 720p trace and
// keep the CDC/display path small.
// The eight spectrum bars are frequency-band activity from the active FPGA
// voices (note octave weighted by velocity).  This keeps the visualizer out of
// the audio multiplier scheduler while still making the display follow the
// hardware-generated sound in real time.
module ui_audio_visual_export #(
    parameter integer VOICES = 8
) (
    input  wire                         clk,
    input  wire                         rst,
    input  wire                         sample_tick,
    input  wire signed [15:0]           sample_in,
    input  wire [VOICES-1:0]            v_gate,
    input  wire [VOICES*7-1:0]          v_note,
    input  wire [VOICES*8-1:0]          v_vel,
    output reg  [255:0]                 waveform,
    output reg  [63:0]                  spectrum,
    output reg  [63:0]                  lissajous,
    output reg                          snapshot_toggle
);
    reg [255:0] wave_work;
    reg [63:0] phase_work;
    reg [5:0] sample_index;
    reg signed [7:0] previous_sample;

    reg [7:0] spectrum_calc [0:7];
    reg [7:0] spectrum_tmp [0:7];
    integer i;
    integer band;
    integer add_energy;

    function integer note_band;
        input [6:0] note;
        begin
            if      (note < 7'd12) note_band = 0;
            else if (note < 7'd24) note_band = 1;
            else if (note < 7'd36) note_band = 2;
            else if (note < 7'd48) note_band = 3;
            else if (note < 7'd60) note_band = 4;
            else if (note < 7'd72) note_band = 5;
            else if (note < 7'd84) note_band = 6;
            else                  note_band = 7;
        end
    endfunction

    // Map active notes into eight octave bands.  The result is a compact
    // hardware activity view for the dashboard; it is not used by the audio
    // path and does not claim to replace an offline FFT measurement.
    always @* begin
        for (i = 0; i < 8; i = i + 1)
            spectrum_tmp[i] = 8'd0;
        for (i = 0; i < VOICES; i = i + 1) begin
            band = note_band(v_note[i*7 +: 7]);
            add_energy = v_gate[i] ? (v_vel[i*8 +: 8] >> 1) : 0;
            if (add_energy > 0) begin
                if ((spectrum_tmp[band] + add_energy) > 255)
                    spectrum_tmp[band] = 8'hff;
                else
                    spectrum_tmp[band] = spectrum_tmp[band] + add_energy[7:0];
            end
        end
        for (i = 0; i < 8; i = i + 1)
            spectrum_calc[i] = spectrum_tmp[i];
    end

    wire signed [7:0] sample8 = sample_in[15:8];
    wire [2:0] sample_coord = sample8[7:5] ^ 3'h4;
    wire [2:0] previous_coord = previous_sample[7:5] ^ 3'h4;
    wire [5:0] phase_index = {sample_coord, previous_coord};
    wire [3:0] sample_row = {1'b0, sample_coord};
    integer k;

    always @(posedge clk) begin
        if (rst) begin
            waveform        <= 512'd0;
            spectrum        <= 64'd0;
            lissajous       <= 64'd0;
            snapshot_toggle <= 1'b0;
            phase_work      <= 64'd0;
            sample_index    <= 6'd0;
            previous_sample <= 8'sd0;
            wave_work <= 256'd0;
        end else if (sample_tick) begin
            wave_work[(sample_index * 4) +: 4] <= sample_row;
            phase_work[phase_index] <= 1'b1;
            previous_sample <= sample8;

            if (sample_index == 6'd63) begin
                // Include the newest sample explicitly because wave_work[63]
                // is updated on this same edge.
                waveform <= wave_work;
                waveform[63*4 +: 4] <= sample_row;
                lissajous <= phase_work;
                for (k = 0; k < 8; k = k + 1)
                    spectrum[k*8 +: 8] <= spectrum_calc[k];
                snapshot_toggle <= ~snapshot_toggle;
                sample_index <= 6'd0;
                phase_work <= 256'd0;
            end else begin
                sample_index <= sample_index + 1'b1;
            end
        end
    end
endmodule

