// Instrument table selector for the 32-voice RAM prototype.
// bank  0..11 : e-piano  (2 groups x 6 stages,   6 pROMs)
// bank 12..41 : guitar   (5 groups x 6 variants, 15 pROMs)
// bank 42..47 : generic bright spectra (6 tables, 3 pROMs)
// Only the selected group is clock-enabled; the others hold their last value,
// so the output is a mux, never an OR of stale data.
module instrument_rom_banks(
    input  wire       clk,
    input  wire       ce,
    input  wire       rst,
    input  wire [5:0] bank,
    input  wire [8:0] addr,
    output wire [15:0] dout
);
    wire piano_ce  = ce && (bank < 6'd12);
    wire guitar_ce = ce && (bank >= 6'd12) && (bank < 6'd42);
    wire bright_ce = ce && (bank >= 6'd42);
    wire [5:0] guitar_bank = bank - 6'd12;
    wire [5:0] bright_bank = bank - 6'd42;
    wire [15:0] piano_d, guitar_d, bright_d;

    gowin_prom_piano_bank u_piano (
        .clk(clk), .ce(piano_ce), .rst(rst), .bank({2'b00, bank[3:0]}),
        .addr(addr), .dout(piano_d));
    gowin_prom_guitar_bank u_guitar (
        .clk(clk), .ce(guitar_ce), .rst(rst), .bank(guitar_bank),
        .addr(addr), .dout(guitar_d));
    gowin_prom_bright_bank u_bright (
        .clk(clk), .ce(bright_ce), .rst(rst), .bank(bright_bank[2:0]),
        .addr(addr), .dout(bright_d));

    // pROM output is registered; preserve its group while CE is low and the
    // caller changes the next address/bank. CE is not an output mux select.
    reg [1:0] selected=0;
    always @(posedge clk)begin
        if(rst)selected<=0;
        else if(ce)selected<=bank<12?0:bank<42?1:2;
    end
    assign dout = selected==0 ? piano_d : selected==1 ? guitar_d : bright_d;
`ifdef SIMULATION
    always @(posedge clk)if(!rst && ce && bank>=48)$fatal(1,"invalid instrument bank");
`endif
endmodule
