// 27 MHz * 19 / 2 = 256.5 MHz serial; CLKDIV5 = 51.3 MHz pixel.
// 27 MHz -> 371.25 MHz serial clock / 74.25 MHz pixel clock, matching the
// Sipeed Tang Primer 20K HDMI reference design.
module hdmi_clock (
    input  wire clk_27m,
    input  wire reset,       // active high
    output wire serial_clk,
    output wire pix_clk,
    output wire locked
);
    wire gw_gnd = 1'b0;
    wire clkoutp_o;
    wire clkoutd_o;
    wire clkoutd3_o;

    rPLL rpll_inst (
        .CLKOUT(serial_clk),
        .LOCK(locked),
        .CLKOUTP(clkoutp_o),
        .CLKOUTD(clkoutd_o),
        .CLKOUTD3(clkoutd3_o),
        .RESET(reset),
        .RESET_P(gw_gnd),
        .CLKIN(clk_27m),
        .CLKFB(gw_gnd),
        .FBDSEL(6'd0),
        .IDSEL(6'd0),
        .ODSEL(6'd0),
        .PSDA(4'd0),
        .DUTYDA(4'd0),
        .FDLY(4'd0)
    );
    defparam rpll_inst.FCLKIN = "27";
    defparam rpll_inst.DYN_IDIV_SEL = "false";
    defparam rpll_inst.IDIV_SEL = 1;
    defparam rpll_inst.DYN_FBDIV_SEL = "false";
    defparam rpll_inst.FBDIV_SEL = 18;
    defparam rpll_inst.DYN_ODIV_SEL = "false";
    defparam rpll_inst.ODIV_SEL = 4;
    defparam rpll_inst.PSDA_SEL = "0000";
    defparam rpll_inst.DYN_DA_EN = "true";
    defparam rpll_inst.DUTYDA_SEL = "1000";
    defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
    defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
    defparam rpll_inst.CLKOUT_DLY_STEP = 0;
    defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
    defparam rpll_inst.CLKFB_SEL = "internal";
    defparam rpll_inst.CLKOUT_BYPASS = "false";
    defparam rpll_inst.CLKOUTP_BYPASS = "false";
    defparam rpll_inst.CLKOUTD_BYPASS = "false";
    defparam rpll_inst.DYN_SDIV_SEL = 2;
    defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
    defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
    defparam rpll_inst.DEVICE = "GW2A-18C";

    CLKDIV u_clkdiv (
        .RESETN(~reset & locked),
        .HCLKIN(serial_clk),
        .CLKOUT(pix_clk),
        .CALIB(1'b1)
    );
    defparam u_clkdiv.DIV_MODE = "5";
    defparam u_clkdiv.GSREN = "false";
endmodule
