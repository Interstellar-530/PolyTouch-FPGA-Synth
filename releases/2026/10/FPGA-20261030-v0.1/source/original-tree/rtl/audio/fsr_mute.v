// Momentary mute from the existing filtered FSR ADC code. The separated
// thresholds retain state around the touch boundary instead of chattering.
// Qualification counts fresh update samples, never system-clock cycles.
// Defaults preserve legacy mute behavior; the 32-voice pedal opts into debounce.
module fsr_mute #(
    parameter integer PRESS_ADC = 512,
    parameter integer RELEASE_ADC = 256,
    parameter integer PRESS_SAMPLES = 1,
    parameter integer RELEASE_SAMPLES = 1
)(
    input wire clk,
    input wire rst,
    input wire enable,
    input wire update,
    input wire [11:0] pressure,
    output reg muted
);
    localparam integer PRESS_BITS = (PRESS_SAMPLES > 1) ? $clog2(PRESS_SAMPLES) : 1;
    localparam integer RELEASE_BITS = (RELEASE_SAMPLES > 1) ? $clog2(RELEASE_SAMPLES) : 1;
    reg [PRESS_BITS-1:0] press_count = 0;
    reg [RELEASE_BITS-1:0] release_count = 0;
`ifdef SIMULATION
    initial begin
        if (RELEASE_ADC < 0 || PRESS_ADC > 4095 || RELEASE_ADC >= PRESS_ADC)
            $fatal(1,"FSR mute requires 0 <= RELEASE_ADC < PRESS_ADC <= 4095");
        if (PRESS_SAMPLES < 1 || RELEASE_SAMPLES < 1)
            $fatal(1,"FSR qualification sample counts must be positive");
    end
`endif
    always @(posedge clk) begin
        if (rst || !enable) begin
            muted <= 1'b0;
            press_count <= 0;
            release_count <= 0;
        end
        else if (update) begin
            if (!muted) begin
                release_count <= 0;
                if (pressure >= PRESS_ADC) begin
                    if (press_count == PRESS_SAMPLES-1) begin
                        muted <= 1'b1;
                        press_count <= 0;
                    end else press_count <= press_count + 1'b1;
                end else press_count <= 0;
            end else begin
                press_count <= 0;
                if (pressure <= RELEASE_ADC) begin
                    if (release_count == RELEASE_SAMPLES-1) begin
                        muted <= 1'b0;
                        release_count <= 0;
                    end else release_count <= release_count + 1'b1;
                end else release_count <= 0;
            end
        end
    end
endmodule

// Pedal switching uses a short median path; the display's IIR must not delay
// threshold crossings near RELEASE_ADC. At 2 kHz: median adds one update,
// followed by 2 press / 6 release confirmations. Worst sample alignment adds
// one interval: nominal bounded step response <= 4 ms, before audio release.
module fsr_pedal_conditioner(
    input wire clk,rst,enable,update,
    input wire [11:0] pressure,
    output wire pressed
);
    reg [11:0] prior0=0,prior1=0;
    wire [11:0] median =
        ((prior0<=prior1) && (prior1<=pressure)) ? prior1 :
        ((pressure<=prior1) && (prior1<=prior0)) ? prior1 :
        ((prior1<=prior0) && (prior0<=pressure)) ? prior0 :
        ((pressure<=prior0) && (prior0<=prior1)) ? prior0 : pressure;
    always @(posedge clk) begin
        if(rst || !enable) begin prior0<=0;prior1<=0;end
        else if(update) begin prior1<=prior0;prior0<=pressure;end
    end
    fsr_mute #(.PRESS_SAMPLES(2),.RELEASE_SAMPLES(6)) qualifier(
        .clk(clk),.rst(rst),.enable(enable),.update(update),
        .pressure(median),.muted(pressed));
endmodule
