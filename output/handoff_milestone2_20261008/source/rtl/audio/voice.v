// One complete polyphonic voice: DDS oscillator plus ADSR amplitude.
module voice (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    input  wire               gate,
    input  wire        [31:0] phase_inc,
    output wire signed [15:0] sample
);

    wire signed [15:0] osc_sample;
    wire        [15:0] env;
    wire signed [31:0] osc_ext;
    wire signed [31:0] env_ext;
    wire signed [31:0] product;

    dds_osc u_dds (
        .clk         (clk),
        .rst         (rst),
        .sample_tick (sample_tick),
        .phase_inc   (phase_inc),
        .sample      (osc_sample)
    );

    adsr u_adsr (
        .clk         (clk),
        .rst         (rst),
        .sample_tick (sample_tick),
        .gate        (gate),
        .env         (env)
    );

    assign osc_ext = {{16{osc_sample[15]}}, osc_sample};
    assign env_ext = {16'd0, env};
    assign product = osc_ext * env_ext;
    assign sample  = product[31:16];

endmodule
