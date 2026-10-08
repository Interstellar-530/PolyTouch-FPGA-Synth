// Single-cycle wavetable DDS oscillator.
// One independent phase accumulator, frequency control word, and waveform table.
module dds_osc (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    input  wire        [31:0] phase_inc,
    output wire signed [15:0] sample
);

    reg [31:0] phase;
    reg signed [15:0] wave_rom [0:511];
    wire [8:0] wave_addr = phase[31:23];

    initial begin
        $readmemh("wave_sine.hex", wave_rom);
    end

    always @(posedge clk) begin
        if (rst) begin
            phase <= 32'd0;
        end else if (sample_tick) begin
            phase <= phase + phase_inc;
        end
    end

    assign sample = wave_rom[wave_addr];

endmodule
