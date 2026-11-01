// 12.288 MHz reference -> 4x/6x/8x compute clock. I2S stays on the reference.
// Static divisors: IDIV=1, FBDIV=MULT, ODIV=16 (MULT=4) or 8 (MULT=6/8).
//   MULT=4 -> 49.152 MHz, VCO 786.432 MHz
//   MULT=6 -> 73.728 MHz, VCO 589.824 MHz
//   MULT=8 -> 98.304 MHz, VCO 786.432 MHz
module audio_pll_clock #(parameter integer MULT=4)(
 input wire clk_ref,reset,
 output wire clk_compute,locked,reset_compute,reset_audio
);
`ifdef SIMULATION
 initial if(MULT!=4 && MULT!=6 && MULT!=8)
  $fatal(1,"audio_pll_clock MULT must be 4, 6, or 8; got %0d",MULT);
`endif
 localparam integer FB_SEL = MULT-1;                 // FBDIV = MULT
 localparam integer ODIV   = (MULT==4) ? 16 : 8;     // keep VCO in range
 reg[3:0]startup=0;
 always @(posedge clk_ref or posedge reset)begin
  if(reset)startup<=0;else if(!startup[3])startup<=startup+4'd1;
 end
 wire pll_reset=reset || !startup[3];
 rPLL #(.FCLKIN("12.288"),.DYN_IDIV_SEL("false"),.IDIV_SEL(0),
  .DYN_FBDIV_SEL("false"),.FBDIV_SEL(FB_SEL),.DYN_ODIV_SEL("false"),.ODIV_SEL(ODIV),
  .PSDA_SEL("0000"),.DUTYDA_SEL("1000"),.DYN_DA_EN("false"),
  .CLKFB_SEL("internal"),.CLKOUT_BYPASS("false"),.DEVICE("GW2A-18C")) u_pll(
  .CLKIN(clk_ref),.CLKFB(1'b0),.RESET(pll_reset),.RESET_P(1'b0),
  .FBDSEL(6'd0),.IDSEL(6'd0),.ODSEL(6'd0),.PSDA(4'd0),.DUTYDA(4'd0),.FDLY(4'd0),
  .CLKOUT(clk_compute),.LOCK(locked),.CLKOUTP(),.CLKOUTD(),.CLKOUTD3());
 reg[3:0]compute_reset_pipe=4'hf,audio_reset_pipe=4'hf;
 always @(posedge clk_compute or posedge pll_reset or negedge locked)begin
  if(pll_reset || !locked)compute_reset_pipe<=4'hf;
  else compute_reset_pipe<={compute_reset_pipe[2:0],1'b0};
 end
 always @(posedge clk_ref or posedge pll_reset or negedge locked)begin
  if(pll_reset || !locked)audio_reset_pipe<=4'hf;
  else audio_reset_pipe<={audio_reset_pipe[2:0],1'b0};
 end
 assign reset_compute=compute_reset_pipe[3];
 assign reset_audio=audio_reset_pipe[3];
endmodule
