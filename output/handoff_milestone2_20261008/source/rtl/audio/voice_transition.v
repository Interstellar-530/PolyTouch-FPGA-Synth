// De-click a reused voice before replacing its pitch/velocity. The allocator
// keeps immediate note ownership; only the rendered state waits for silence.
// There is no additional oscillator, waveform memory or multiplier.
module voice_transition #(
    parameter integer FADE_LOG2 = 6,
    parameter [15:0] ATTACK_STEP=16'd140,
    parameter [15:0] DECAY_STEP=16'd16,
    parameter [15:0] RELEASE_STEP=16'd48,
    parameter [15:0] SUSTAIN_LEVEL=16'd45875
)(
    input wire clk,rst,sample_tick,gate,retrigger,
    input wire [6:0] note,
    input wire [7:0] velocity,
    output wire [6:0] render_note,
    output wire [7:0] render_velocity,
    output wire render_retrigger,
    output wire [15:0] env,
    output wire idle
);
    reg [6:0] active_note,pending_note;
    reg [7:0] active_velocity,pending_velocity;
    reg fading;
    reg [15:0] fade_env,fade_step;
    wire [15:0] raw_env;
    wire raw_idle;
    wire requested=gate && retrigger;
    wire immediate=requested && !fading && raw_env==0;
    wire begin_fade=requested && !fading && raw_env!=0;
    wire finishing=fading && fade_env<=fade_step;
    wire restart=finishing && gate;
    wire [6:0] next_note=requested?note:pending_note;
    wire [7:0] next_velocity=requested?velocity:pending_velocity;
    assign render_note=restart?next_note:(immediate?note:active_note);
    assign render_velocity=restart?next_velocity:(immediate?velocity:active_velocity);
    assign render_retrigger=immediate || restart;
    assign env=fading?fade_env:raw_env;
    assign idle=!fading && raw_idle;
    wire adsr_gate=finishing?gate:((fading || begin_fade)?1'b0:gate);
    // If the queued note was released while fading, discard it and clear the
    // hidden ADSR tail at the same sample boundary. It must not reappear.
    wire adsr_reset=rst || (sample_tick && finishing && !gate);
    adsr #(.ATTACK_STEP(ATTACK_STEP),.DECAY_STEP(DECAY_STEP),
           .RELEASE_STEP(RELEASE_STEP),.SUSTAIN_LEVEL(SUSTAIN_LEVEL)) u_adsr(
        .clk(clk),.rst(adsr_reset),.sample_tick(sample_tick),.gate(adsr_gate),
        .retrigger(render_retrigger),.env(raw_env),.idle(raw_idle));

    wire [16:0] rounded_step={1'b0,raw_env}+((1<<FADE_LOG2)-1);
    always @(posedge clk)begin
        if(rst)begin
            active_note<=0;pending_note<=0;active_velocity<=0;pending_velocity<=0;
            fading<=0;fade_env<=0;fade_step<=1;
        end else if(sample_tick)begin
            if(requested)begin pending_note<=note;pending_velocity<=velocity;end
            if(fading)begin
                if(finishing)begin
                    fading<=0;fade_env<=0;
                    if(gate)begin active_note<=next_note;active_velocity<=next_velocity;end
                end else fade_env<=fade_env-fade_step;
            end else if(begin_fade)begin
                fading<=1;fade_env<=raw_env;fade_step<=rounded_step>>FADE_LOG2;
            end else if(immediate)begin active_note<=note;active_velocity<=velocity;end
        end
    end
`ifdef SIMULATION
    initial if(FADE_LOG2<1 || FADE_LOG2>8)$fatal(1,"FADE_LOG2 must be 1..8");
`endif
endmodule
