// Three registered stages, one code per clock throughput. No DSP or BSRAM.
// Lookup -> parallel 3/4-bit shift-adds -> rounded interpolation and base add.
module bend_ratio_pipeline(
 input wire clk,rst,update,input wire[11:0]code,
 output reg[16:0]ratio=65536,output reg valid=0
);
`include "rtl/audio/bend_coefficients.vh"
 reg[1:0]pending=0;
 reg[16:0]base0=65536,base1=65536;
 reg[9:0]delta=0;reg[6:0]fraction=0;
 reg[16:0]part0=0,part1=0;
 wire[26:0]coefficient=fine_coefficient_from_adc(code);
 reg[16:0]low_sum,high_sum;
 integer i;
 always @* begin
  low_sum=17'd64;high_sum=0;
  for(i=0;i<3;i=i+1)if(fraction[i])low_sum=low_sum+({7'd0,delta} << i);
  for(i=3;i<7;i=i+1)if(fraction[i])high_sum=high_sum+({7'd0,delta} << i);
 end
 wire[17:0]interpolation_product={1'b0,part0}+{1'b0,part1};
 always @(posedge clk)begin
  if(rst)begin
   pending<=0;valid<=0;ratio<=65536;base0<=65536;base1<=65536;
   delta<=0;fraction<=0;part0<=0;part1<=0;
  end else begin
   pending<={pending[0],update};valid<=pending[1];
   if(update)begin base0<=coefficient[26:10];delta<=coefficient[9:0];fraction<=code[6:0];end
   if(pending[0])begin base1<=base0;part0<=low_sum;part1<=high_sum;end
   if(pending[1])ratio<=base1+(interpolation_product >> 7);
  end
 end
endmodule
