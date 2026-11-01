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
    parameter integer VOICES = 8, parameter integer DECIMATION = 16,
    parameter integer WAVE_HOLD_WINDOWS = 1
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
    localparam integer HOLD_BITS = (WAVE_HOLD_WINDOWS>1) ? $clog2(WAVE_HOLD_WINDOWS) : 1;
    reg [HOLD_BITS-1:0] wave_hold_count;

    reg [7:0] spectrum_calc [0:7];
    localparam integer LEAVES = 2 ** $clog2(VOICES);
    reg [2:0] voice_band [0:VOICES-1];
    reg [6:0] voice_energy [0:VOICES-1];
    integer i;
    reg [7:0] decim_count;
    wire visual_tick = sample_tick && (decim_count == DECIMATION-1);
    always @(posedge clk) begin
        if(rst) decim_count<=0;
        else if(sample_tick) decim_count <= visual_tick ? 0 : decim_count+1'b1;
    end

    function [2:0] note_band;
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
    always @(posedge clk) begin
        for (i=0; i<VOICES; i=i+1) begin
            voice_band[i] <= rst ? 3'd0 : note_band(v_note[i*7 +: 7]);
            voice_energy[i] <= (rst || !v_gate[i]) ? 7'd0 : v_vel[i*8+1 +: 7];
        end
    end
    // One classification register stage, then a balanced, wide sum per band.
    // Saturation once after the sum is equivalent for nonnegative energies.
    genvar b, v, n;
    generate for (b=0; b<8; b=b+1) begin: g_band
        wire [$clog2(VOICES)+7:0] tree [1:2*LEAVES-1];
        for (v=0; v<LEAVES; v=v+1) begin: g_leaf
            if (v<VOICES) assign tree[LEAVES+v] = (voice_band[v]==b) ? voice_energy[v] : 0;
            else assign tree[LEAVES+v] = 0;
        end
        for (n=1; n<LEAVES; n=n+1) begin: g_sum
            assign tree[n] = tree[2*n] + tree[2*n+1];
        end
        // A single strong melody note should fill a useful part of its bar,
        // even when most of the 32 available voices are intentionally idle.
        wire [15:0] scaled = (VOICES>=32) ? (tree[1] << 1) : tree[1];
        // Separate the 32-way sum from attack/decay comparison. Otherwise
        // both paths form one long chain at the 54 MHz compute clock.
        always @(posedge clk)
            spectrum_calc[b] <= rst ? 8'd0 : (scaled>255) ? 8'hff : scaled[7:0];
    end endgenerate

    // Fixed 4x display gain, saturated; audio itself is never modified.
    reg [15:0] visual_peak;
    reg [3:0] display_shift;
    wire [15:0] magnitude=sample_in[15] ? (~sample_in+16'd1) : sample_in;
    wire [15:0] peak_now=(magnitude>visual_peak) ? magnitude : visual_peak;
    // Automatic display gain affects only the visual snapshot.
    always @(posedge clk) begin
        if(rst) begin visual_peak<=0;display_shift<=6;end
        else if(visual_tick) begin
            if(sample_index==63) begin
                visual_peak<=0;
                if(peak_now>=16384) display_shift<=8;
                else if(peak_now>=8192) display_shift<=7;
                else if(peak_now>=4096) display_shift<=6;
                else if(peak_now>=2048) display_shift<=5;
                else if(peak_now>=1024) display_shift<=4;
                else if(peak_now>=512) display_shift<=3;
                else display_shift<=2;
            end else visual_peak<=peak_now;
        end
    end
    wire signed [15:0] display_sample = sample_in >>> ((VOICES>=32) ? display_shift : 4'd6);
    wire signed [7:0] sample8 = (display_sample>127) ? 8'sd127 : (display_sample < -128) ? -8'sd128 : display_sample[7:0];
    wire [2:0] sample_coord = sample8[7:5] ^ 3'h4;
    wire [2:0] previous_coord = previous_sample[7:5] ^ 3'h4;
    wire [5:0] phase_index = {sample_coord, previous_coord};
    wire [3:0] sample_row = {1'b0, sample_coord};
    integer k;

    always @(posedge clk) begin
        if (rst) begin
            waveform        <= {64{4'd4}};
            spectrum        <= 64'd0;
            lissajous       <= 64'd0;
            snapshot_toggle <= 1'b0;
            phase_work      <= 64'd0;
            sample_index    <= 6'd0;
            previous_sample <= 8'sd0;
            wave_hold_count <= 0;
            wave_work <= 256'd0;
        end else if (visual_tick) begin
            wave_work[(sample_index * 4) +: 4] <= sample_row;
            phase_work[phase_index] <= 1'b1;
            previous_sample <= sample8;

            if (sample_index == 6'd63) begin
                // Include the newest sample explicitly because wave_work[63]
                // is updated on this same edge.
                // Hold complete waveforms between publications. The audio
                // capture interval and status/voice refresh stay unchanged.
                if (wave_hold_count == WAVE_HOLD_WINDOWS-1) begin
                    waveform <= wave_work;
                    waveform[63*4 +: 4] <= sample_row;
                    wave_hold_count <= 0;
                end else wave_hold_count <= wave_hold_count+1'b1;
                lissajous <= phase_work | (64'd1 << phase_index);
                for (k = 0; k < 8; k = k + 1)
                    if(spectrum_calc[k] >= spectrum[k*8 +: 8]) spectrum[k*8 +: 8] <= spectrum_calc[k];
                    else spectrum[k*8 +: 8] <= (spectrum[k*8 +: 8] > 4) ? spectrum[k*8 +: 8]-8'd4 : 8'd0;
                snapshot_toggle <= ~snapshot_toggle;
                sample_index <= 6'd0;
                phase_work <= 64'd0;
            end else begin
                sample_index <= sample_index + 1'b1;
            end
        end
    end
endmodule


