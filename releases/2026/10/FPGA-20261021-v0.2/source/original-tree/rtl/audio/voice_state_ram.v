// One Gowin SDP block: 512 words x32, one read and one write each clock.
// Reset clears outputs immediately, then clears all words in512 clocks.
// Clients wait for ready and avoid concurrent read/write of the same word.
module voice_state_ram(
 input wire clk,rst,write_enable,input wire[8:0]write_addr,input wire[31:0]write_data,
 input wire read_enable,input wire[8:0]read_addr,output wire[31:0]read_data,
 output reg read_valid=0,output reg ready=0
);
 reg[8:0]clear_addr=0;
 wire write_ce=!rst && (!ready || write_enable);
 wire read_ce=!rst && ready && read_enable;
 wire[8:0]actual_write_addr=ready?write_addr:clear_addr;
 wire[31:0]actual_write_data=ready?write_data:32'd0;
 always @(posedge clk)begin
  if(rst)begin ready<=0;clear_addr<=0;read_valid<=0;end
  else begin
   read_valid<=read_ce;
   if(!ready)begin
    if(clear_addr==511)ready<=1;else clear_addr<=clear_addr+9'd1;
   end
  end
 end
`ifdef SIMULATION
 reg[31:0]memory[0:511];reg[31:0]data_q=0;
 assign read_data=data_q;
 always @(posedge clk)begin
  if(write_ce)memory[actual_write_addr]<=actual_write_data;
  if(rst)data_q<=0;else if(read_ce)data_q<=memory[read_addr];
  if(!rst && ready && write_enable && read_enable && write_addr==read_addr)
   $fatal(1,"voice_state_ram: same-address read/write must be arbitrated");
 end
`else
 SDP #(.READ_MODE(1'b0),.BIT_WIDTH_0(32),.BIT_WIDTH_1(32),.BLK_SEL(3'd0),.RESET_MODE("SYNC")) u_state(
  .DO(read_data),.DI(actual_write_data),.BLKSEL(3'd0),
  // In32-bit SDP mode ADA[3:0] are byte-write enables, not address padding.
  .ADA({actual_write_addr,1'b0,4'b1111}),.ADB({read_addr,5'b0}),
  .WREA(1'b1),.WREB(1'b0),.CLKA(clk),.CLKB(clk),.CEA(write_ce),.CEB(read_ce),
  .OCE(1'b1),.RESETA(rst),.RESETB(rst));
`endif
endmodule
