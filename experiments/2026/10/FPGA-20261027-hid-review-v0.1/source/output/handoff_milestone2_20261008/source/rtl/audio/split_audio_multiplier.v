// Exact signed A_WIDTH x 18 product using two physical 18x18 multipliers.
// Supports a 24-bit audio sample or a positive 33-bit frequency/control word.
// One registered multiply edge, combinational reconstruction; CE holds result.
module split_audio_multiplier #(parameter integer A_WIDTH=33)(
 input wire clk,rst,enable,
 input wire signed[A_WIDTH-1:0]operand_a,input wire signed[17:0]operand_b,
 output wire signed[A_WIDTH+17:0]product
);
 // Native ASIGN lets the low limb be unsigned without widening it to19 bits.
 // Explicit primitives prevent synthesis from consuming a third DSP for ALU.
 wire [17:0]a_high={{(36-A_WIDTH){operand_a[A_WIDTH-1]}},operand_a[A_WIDTH-1:18]};
`ifdef SIMULATION
 reg signed[35:0]low_product=0,high_product=0;
 always @(posedge clk)begin
  if(rst)begin low_product<=0;high_product<=0;end
  else if(enable)begin
   low_product<=$signed({1'b0,operand_a[17:0]})*operand_b;
   high_product<=$signed(a_high)*operand_b;
  end
 end
`else
 wire signed[35:0]low_product,high_product;
 MULT18X18 #(.AREG(0),.BREG(0),.OUT_REG(1),.PIPE_REG(0),.MULT_RESET_MODE("SYNC")) u_low(
  .A(operand_a[17:0]),.B(operand_b),.ASIGN(1'b0),.BSIGN(1'b1),.CLK(clk),.CE(enable),.RESET(rst),
  .ASEL(1'b0),.BSEL(1'b0),.SIA(18'd0),.SIB(18'd0),.DOUT(low_product),.SOA(),.SOB());
 MULT18X18 #(.AREG(0),.BREG(0),.OUT_REG(1),.PIPE_REG(0),.MULT_RESET_MODE("SYNC")) u_high(
  .A(a_high),.B(operand_b),.ASIGN(1'b1),.BSIGN(1'b1),.CLK(clk),.CE(enable),.RESET(rst),
  .ASEL(1'b0),.BSEL(1'b0),.SIA(18'd0),.SIB(18'd0),.DOUT(high_product),.SOA(),.SOB());
`endif
 wire signed[A_WIDTH+17:0]low_extended=low_product;
 wire signed[A_WIDTH+17:0]high_extended=high_product;
 assign product=low_extended+(high_extended <<< 18);
`ifdef SIMULATION
 initial if(A_WIDTH<19 || A_WIDTH>35)$fatal(1,"split_audio_multiplier A_WIDTH must be 19..35");
`endif
endmodule
