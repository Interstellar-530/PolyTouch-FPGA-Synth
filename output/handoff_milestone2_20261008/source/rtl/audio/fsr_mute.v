// Momentary mute from the existing filtered FSR ADC code. The separated
// thresholds retain state around the touch boundary instead of chattering.
module fsr_mute #(
    parameter integer PRESS_ADC = 512,
    parameter integer RELEASE_ADC = 256
)(
    input wire clk,
    input wire rst,
    input wire enable,
    input wire update,
    input wire [11:0] pressure,
    output reg muted
);
`ifdef SIMULATION
    initial begin
        if (RELEASE_ADC < 0 || PRESS_ADC > 4095 || RELEASE_ADC >= PRESS_ADC)
            $fatal(1,"FSR mute requires 0 <= RELEASE_ADC < PRESS_ADC <= 4095");
    end
`endif
    always @(posedge clk) begin
        if (rst || !enable) muted <= 1'b0;
        else if (update) begin
            if (pressure >= PRESS_ADC) muted <= 1'b1;
            else if (pressure <= RELEASE_ADC) muted <= 1'b0;
        end
    end
endmodule
