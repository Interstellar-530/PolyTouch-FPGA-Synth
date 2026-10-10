// Four-stage ADSR envelope generator.
//
// The step sizes are parameters so a polyphonic build can use snappier
// envelopes than the original single-voice bring-up: with four voices the
// release has to finish quickly enough for the allocator to reuse the voice.
module adsr #(
    parameter [15:0] ATTACK_STEP   = 16'd140,
    parameter [15:0] DECAY_STEP    = 16'd16,
    parameter [15:0] RELEASE_STEP  = 16'd48,
    parameter [15:0] SUSTAIN_LEVEL = 16'd45875   // 70 percent of full scale
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_tick,
    input  wire        gate,
    output reg  [15:0] env,
    output wire        idle
);

    localparam [2:0] ST_IDLE    = 3'd0;
    localparam [2:0] ST_ATTACK  = 3'd1;
    localparam [2:0] ST_DECAY   = 3'd2;
    localparam [2:0] ST_SUSTAIN = 3'd3;
    localparam [2:0] ST_RELEASE = 3'd4;

    reg [2:0] state;

    // idle is what the voice allocator watches to tell a finished voice from
    // one that is still ringing.
    assign idle = (state == ST_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            env   <= 16'd0;
        end else if (sample_tick) begin
            if (!gate && (state != ST_IDLE)) begin
                state <= ST_RELEASE;
            end else begin
                case (state)
                    ST_IDLE: begin
                        env <= 16'd0;
                        if (gate) state <= ST_ATTACK;
                    end
                    ST_ATTACK: begin
                        if (env >= (16'hFFFF - ATTACK_STEP))
                            begin env <= 16'hFFFF; state <= ST_DECAY; end
                        else
                            env <= env + ATTACK_STEP;
                    end
                    ST_DECAY: begin
                        if (env <= (SUSTAIN_LEVEL + DECAY_STEP))
                            begin env <= SUSTAIN_LEVEL; state <= ST_SUSTAIN; end
                        else
                            env <= env - DECAY_STEP;
                    end
                    ST_SUSTAIN: begin
                        env <= SUSTAIN_LEVEL;
                        if (!gate) state <= ST_RELEASE;
                    end
                    ST_RELEASE: begin
                        if (env <= RELEASE_STEP)
                            begin env <= 16'd0; state <= ST_IDLE; end
                        else
                            env <= env - RELEASE_STEP;
                    end
                    default: begin
                        state <= ST_IDLE;
                        env   <= 16'd0;
                    end
                endcase
            end
        end
    end

endmodule
