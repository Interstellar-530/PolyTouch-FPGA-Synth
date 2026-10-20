// De-click a reused voice before replacing its pitch/velocity. The allocator
// keeps immediate note ownership; only the rendered state waits for silence.
// There is no additional oscillator, waveform memory or multiplier.
module voice_transition #(
    parameter integer FADE_LOG2 = 6,
    parameter [15:0] ATTACK_STEP=16'd140,
    parameter [15:0] DECAY_STEP=16'd16,
    parameter [15:0] RELEASE_STEP=16'd48,
    parameter [15:0] SUSTAIN_LEVEL=16'd45875,
    parameter [15:0] PIANO_ATTACK_STEP=16'd1024,
    parameter [15:0] PIANO_DECAY_STEP=16'd2,
    parameter [15:0] PIANO_RELEASE_STEP=16'd32,
    parameter [15:0] PIANO_SUSTAIN_LEVEL=16'd32768,
    parameter [15:0] GUITAR_ATTACK_STEP=16'd256,
    parameter [15:0] GUITAR_DECAY_STEP=16'd8,
    parameter [15:0] GUITAR_RELEASE_STEP=16'd8,
    parameter [15:0] GUITAR_SUSTAIN_LEVEL=16'd16384
)(
    input wire clk,rst,sample_tick,gate,retrigger,
    input wire piano_mode,
    input wire guitar_mode,
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
    reg active_piano,pending_piano;
    reg active_guitar,pending_guitar;
    reg fading;
    reg [15:0] fade_env,fade_step;
    wire [15:0] normal_env,piano_env,guitar_env,raw_env;
    wire normal_idle,piano_idle,guitar_idle,raw_idle;
    wire requested=gate && retrigger;
    wire next_piano=requested?piano_mode:pending_piano;
    wire next_guitar=requested?guitar_mode:pending_guitar;
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
        .retrigger(render_retrigger),.env(normal_env),.idle(normal_idle));
    adsr #(.ATTACK_STEP(GUITAR_ATTACK_STEP),.DECAY_STEP(GUITAR_DECAY_STEP),
           .RELEASE_STEP(GUITAR_RELEASE_STEP),.SUSTAIN_LEVEL(GUITAR_SUSTAIN_LEVEL)) u_adsr_guitar(
        .clk(clk),.rst(adsr_reset),.sample_tick(sample_tick),.gate(adsr_gate),
        .retrigger(render_retrigger),.env(guitar_env),.idle(guitar_idle));
    adsr #(.ATTACK_STEP(PIANO_ATTACK_STEP),.DECAY_STEP(PIANO_DECAY_STEP),
           .RELEASE_STEP(PIANO_RELEASE_STEP),.SUSTAIN_LEVEL(PIANO_SUSTAIN_LEVEL)) u_adsr_piano(
        .clk(clk),.rst(adsr_reset),.sample_tick(sample_tick),.gate(adsr_gate),
        .retrigger(render_retrigger),.env(piano_env),.idle(piano_idle));
    assign raw_env=active_guitar?guitar_env:(active_piano?piano_env:normal_env);
    assign raw_idle=active_guitar?guitar_idle:(active_piano?piano_idle:normal_idle);

    wire [16:0] rounded_step={1'b0,raw_env}+((1<<FADE_LOG2)-1);
    always @(posedge clk)begin
        if(rst)begin
            active_note<=0;pending_note<=0;active_velocity<=0;pending_velocity<=0;
            active_piano<=0;pending_piano<=0;active_guitar<=0;pending_guitar<=0;
            fading<=0;fade_env<=0;fade_step<=1;
        end else if(sample_tick)begin
            if(requested)begin
                pending_note<=note;pending_velocity<=velocity;pending_piano<=piano_mode;pending_guitar<=guitar_mode;
            end
            if(fading)begin
                if(finishing)begin
                    fading<=0;fade_env<=0;
                    if(gate)begin
                        active_note<=next_note;active_velocity<=next_velocity;
                        active_piano<=next_piano;active_guitar<=next_guitar;
                    end
                end else fade_env<=fade_env-fade_step;
            end else if(begin_fade)begin
                fading<=1;fade_env<=raw_env;fade_step<=rounded_step>>FADE_LOG2;
            end else if(immediate)begin
                active_note<=note;active_velocity<=velocity;active_piano<=piano_mode;active_guitar<=guitar_mode;
            end
        end
    end
`ifdef SIMULATION
    initial if(FADE_LOG2<1 || FADE_LOG2>8)$fatal(1,"FADE_LOG2 must be 1..8");
`endif
endmodule
