// Tang Primer 20K production clock: 27 MHz -> 54 MHz (VCO 864 MHz).
module board_audio_clock(input wire clk_ref,reset,
    output wire clk_compute,locked,reset_compute);
    rPLL #(.FCLKIN("27"),.DYN_IDIV_SEL("false"),.IDIV_SEL(0),
        .DYN_FBDIV_SEL("false"),.FBDIV_SEL(1),.DYN_ODIV_SEL("false"),.ODIV_SEL(16),
        .PSDA_SEL("0000"),.DUTYDA_SEL("1000"),.DYN_DA_EN("false"),
        .CLKFB_SEL("internal"),.CLKOUT_BYPASS("false"),.DEVICE("GW2A-18C")) u_pll(
        .CLKIN(clk_ref),.CLKFB(1'b0),.RESET(reset),.RESET_P(1'b0),
        .FBDSEL(6'd0),.IDSEL(6'd0),.ODSEL(6'd0),.PSDA(4'd0),.DUTYDA(4'd0),.FDLY(4'd0),
        .CLKOUT(clk_compute),.LOCK(locked),.CLKOUTP(),.CLKOUTD(),.CLKOUTD3());
    reg [3:0] pipe=4'hf;
    always @(posedge clk_compute or posedge reset or negedge locked)
        if(reset || !locked) pipe<=4'hf; else pipe<={pipe[2:0],1'b0};
    assign reset_compute=pipe[3];
endmodule
