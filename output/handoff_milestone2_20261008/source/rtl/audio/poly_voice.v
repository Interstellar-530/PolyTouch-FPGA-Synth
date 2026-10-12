// One complete polyphonic voice: interpolating DDS oscillator, ADSR amplitude
// and a velocity scale.
//
// Every voice owns its phase accumulator and its envelope, which is what the
// competition rules ask for.  The three multiplies are the interpolating
// lookup (inside dds_osc), the envelope and the velocity; four voices use
// twelve 18x18 multipliers in total, far below the 48 the GW2A-18 provides.
module poly_voice (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    input  wire               gate,
    input  wire               start,         // one clk pulse from the allocator
    input  wire        [31:0] phase_inc,
    input  wire        [7:0]  velocity,     // 0 .. 127
    output wire signed [15:0] sample,
    output wire               idle          // envelope is back at zero
);

    wire signed [15:0] osc_sample;
    wire        [15:0] env;
    reg                start_pending;
    wire               restart_sample = gate & (start | start_pending);

    // Note events are not aligned to the audio frame.  Keep a one-clock start
    // pulse until the next sample tick, where phase and envelope restart
    // together.  A note released before that tick is not started again.
    always @(posedge clk) begin
        if (rst)
            start_pending <= 1'b0;
        else if (sample_tick)
            start_pending <= 1'b0;
        else if (start)
            start_pending <= 1'b1;
    end

    dds_osc u_dds (
        .clk         (clk),
        .rst         (rst),
        .sample_tick (sample_tick),
        .retrigger   (restart_sample),
        .phase_inc   (phase_inc),
        .sample      (osc_sample)
    );

    adsr u_adsr (
        .clk         (clk),
        .rst         (rst),
        .sample_tick (sample_tick),
        .gate        (gate),
        .retrigger   (restart_sample),
        .env         (env),
        .idle        (idle)
    );

    // osc * env, normalised by 2^16.  The 16 bit operands keep the 32 bit
    // product inside range: 32767 * 65535 is just under 2^31.
    wire signed [31:0] osc_ext = {{16{osc_sample[15]}}, osc_sample};
    wire signed [31:0] env_ext = {16'd0, env};
    wire signed [31:0] env_mul = osc_ext * env_ext;
    wire signed [15:0] voiced  = env_mul[31:16];

    // Velocity 0..127 scales the voice by 0..1.  Shifting back by 7 bits
    // normalises the 8 bit control value.
    wire signed [31:0] vel_mul = voiced * $signed({1'b0, velocity});

    assign sample = vel_mul[22:7];

endmodule
