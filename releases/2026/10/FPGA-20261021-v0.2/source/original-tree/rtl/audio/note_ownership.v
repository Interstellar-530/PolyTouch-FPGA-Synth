// Keep UART and GPIO ownership separate while preserving the existing
// allocator event format. Note On retains retrigger semantics; Note Off only
// reaches the allocator when no other manual source still holds this pitch.
module note_ownership #(
    parameter integer GPIO_BASE_NOTE=60,
    parameter integer GPIO_KEYS=12
)(
    input wire clk,rst,clear,manual_mode,
    input wire event_valid,event_on,source_uart,
    input wire [6:0]note,
    output wire forward_valid
);
    reg [127:0] uart_held;
    reg [GPIO_KEYS-1:0] gpio_held;
    wire gpio_range=(note>=GPIO_BASE_NOTE && note<GPIO_BASE_NOTE+GPIO_KEYS);
    wire [6:0] gpio_index=note-GPIO_BASE_NOTE;
    wire other_held=source_uart?(gpio_range?gpio_held[gpio_index]:1'b0):uart_held[note];
    assign forward_valid=event_valid && !clear && (!manual_mode || event_on || !other_held);
    always @(posedge clk)begin
        if(rst || clear)begin uart_held<=0;gpio_held<=0;end
        else if(event_valid && manual_mode)begin
            if(source_uart)uart_held[note]<=event_on;
            else if(gpio_range)gpio_held[gpio_index]<=event_on;
        end
    end
`ifdef SIMULATION
    initial if(GPIO_KEYS<1 || GPIO_BASE_NOTE<0 || GPIO_BASE_NOTE+GPIO_KEYS>128)$fatal(1,"invalid GPIO ownership range");
`endif
endmodule
