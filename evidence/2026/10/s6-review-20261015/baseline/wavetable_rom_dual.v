// S6 dual 512-point wavetable wrapper.
//
// The generic model below has the same contract as a Gowin BSRAM ROM wrapper:
// both memories are read synchronously, so an address presented before a
// rising edge appears at sine_q/bright_q after that edge.  A production Gowin
// build can replace the two array declarations/always block with generated
// pROM/BSRAM instances without changing the module interface.  The behavioral
// model is deliberately kept here for deterministic RTL simulation.
//
// `mix_weight` is an unsigned 8-bit cross-fade (0 = sine, 8'hff = bright).
// With `mix_enable=0`, its high bit selects a table exactly; with
// `mix_enable=1`, the full 8-bit value blends the registered outputs.  The
// output is saturated before it is exposed as a signed sample.
module wavetable_rom_dual #(
    parameter integer DEPTH = 512,
    parameter integer ADDR_WIDTH = 9,
    parameter SINE_INIT = "rtl/audio/wave_sine.hex",
    parameter BRIGHT_INIT = "rtl/audio/wave_bright.hex"
) (
    input  wire                    clk,
    input  wire                    en,
    input  wire [ADDR_WIDTH-1:0]   addr,
    input  wire                    mix_enable,
    input  wire [7:0]              mix_weight,
    output reg  signed [15:0]      sine_q,
    output reg  signed [15:0]      bright_q,
    output wire signed [15:0]      sample_q
);

    // The exact dimensions are part of the S6 acceptance contract.  Do not
    // replace these arrays with a large case statement: Gowin BSRAM inference
    // or generated ROM IP is required for hardware.
    reg signed [15:0] sine_rom [0:DEPTH-1];
    reg signed [15:0] bright_rom [0:DEPTH-1];

    initial begin
        $readmemh(SINE_INIT, sine_rom);
        $readmemh(BRIGHT_INIT, bright_rom);
    end

    always @(posedge clk) begin
        if (en) begin
            sine_q   <= sine_rom[addr];
            bright_q <= bright_rom[addr];
        end
    end

    // Registered ROM samples are sign-extended before blending.  Explicitly
    // wide operands avoid Verilog's context-dependent multiplication width.
    // The 25-bit products and 26-bit sum cover both weighted 16-bit samples.
    wire signed [24:0] sine_ext = {{9{sine_q[15]}}, sine_q};
    wire signed [24:0] bright_ext = {{9{bright_q[15]}}, bright_q};
    wire signed [24:0] sine_weight = {17'd0, (8'hff - mix_weight)};
    wire signed [24:0] bright_weight = {17'd0, mix_weight};
    wire signed [49:0] sine_prod_full = sine_ext * sine_weight;
    wire signed [49:0] bright_prod_full = bright_ext * bright_weight;
    wire signed [25:0] blend_sum = sine_prod_full[25:0] + bright_prod_full[25:0] + 26'sd127;
    wire signed [25:0] blend_value = blend_sum >>> 8;
    wire signed [15:0] blend_value_sat =
        (blend_value > 26'sd32767)  ? 16'sd32767 :
        (blend_value < -26'sd32768) ? -16'sd32768 : blend_value[15:0];
    reg signed [15:0] selected_table;
    always @* begin
        if (mix_weight[7])
            selected_table = bright_q;
        else
            selected_table = sine_q;
        // synthesis translate_off
        // synthesis translate_on
    end

    assign sample_q = mix_enable ? blend_value_sat : selected_table;

endmodule

