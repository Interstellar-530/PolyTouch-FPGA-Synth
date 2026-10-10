// Single-cycle wavetable DDS oscillator with linear interpolation.
// One independent phase accumulator, frequency control word and waveform table.
//
// The bare lookup with a 512-entry table throws away every phase bit below
// bit 23. The resulting staircase error has harmonics spread over the whole
// table length; everything above the 23.4 kHz Nyquist limit of the 46.875 kHz
// debug sample rate folds back into the audio band and is heard as a
// shimmering background noise on top of the tone. Interpolating between the
// two table entries that bracket the phase turns that first-order staircase
// error into a second-order one, which drops the error floor by roughly 45 dB.
//
// phase[31:23] selects the table entry, phase[22:14] is the 9-bit fraction
// used to interpolate towards the next entry. One 17x9 multiply does the job;
// the 18x18 DSP block on the GW2A has room to spare.
module dds_osc (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    input  wire        [31:0] phase_inc,
    output reg  signed [15:0] sample
);

    reg [31:0] phase;
    reg signed [15:0] wave_rom [0:511];

    wire [8:0] idx_a = phase[31:23];
    wire [8:0] idx_b = idx_a + 9'd1;          // wraps to entry 0 at the top
    wire signed [9:0] frac = {1'b0, phase[22:14]};

    wire signed [15:0] ya = wave_rom[idx_a];
    wire signed [15:0] yb = wave_rom[idx_b];

    wire signed [16:0] diff = yb - ya;
    wire signed [26:0] prod = diff * frac;    // both operands signed on purpose

    // Round, then scale the 9-bit fraction back out.
    wire signed [17:0] corr = (prod + 27'sd256) >>> 9;
    wire signed [18:0] interp = ya + corr;

    initial begin
        $readmemh("rtl/audio/wave_sine.hex", wave_rom);
    end

    always @(posedge clk) begin
        if (rst) begin
            phase <= 32'd0;
            sample <= 16'sd0;
        end else begin
            if (sample_tick)
                phase <= phase + phase_inc;

            // Registered so the ROM read, the interpolating multiply and the
            // envelope multiply in voice.v are not chained into one 37 ns path.
            sample <= interp[15:0];
        end
    end

endmodule
