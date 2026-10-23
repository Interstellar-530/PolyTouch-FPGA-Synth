//24-bit global mix/VCA, using an existing lane's two-DSP backend in its idle
// window. No arithmetic multiplier is instantiated here.
module wide_master #(
 parameter integer VOICE_SHIFT=6,
 parameter integer PRESSURE_ADC_LOW=128,PRESSURE_ADC_FULL=3200,
 parameter integer PRESSURE_MIN_GAIN_Q12=1024,PRESSURE_GAIN_STEP=32
)(
 input wire clk,rst,update,input wire signed[31:0]sine_sum,bright_sum,
 input wire[7:0]mix_weight,input wire pressure_enable,input wire[11:0]pressure_level,input wire mute,
 input wire[8:0]volume_gain_q8,
 output reg signed[23:0]sample_out,output reg result_valid,output wire busy,
 output reg[31:0]clip_count,output reg clip_event,
 output wire mult_request,input wire mult_ready,
 output reg signed[32:0]mult_operand_a,output reg signed[17:0]mult_operand_b,
 input wire signed[50:0]mult_product
);
 reg[2:0]state=0;
 reg[7:0]weight_state=64,frame_weight=64;
 wire[7:0]active_weight=mix_weight>weight_state?weight_state+8'd1:
  mix_weight<weight_state?weight_state-8'd1:weight_state;
 reg[12:0]gain_q12=4096,frame_gain=4096;
 localparam integer ADC_SPAN=PRESSURE_ADC_FULL-PRESSURE_ADC_LOW;
 localparam integer GAIN_SPAN=4096-PRESSURE_MIN_GAIN_Q12;
 wire[11:0]pressure_delta=pressure_level-PRESSURE_ADC_LOW;
 wire[31:0]mapped_delta;
 generate if(ADC_SPAN==GAIN_SPAN)begin:unit_slope
  assign mapped_delta={20'd0,pressure_delta};
 end else begin:calibrated_slope
  assign mapped_delta=({20'd0,pressure_delta}*GAIN_SPAN)/ADC_SPAN;
 end endgenerate
 wire[12:0]calibrated_gain=pressure_level<=PRESSURE_ADC_LOW?PRESSURE_MIN_GAIN_Q12:
  pressure_level>=PRESSURE_ADC_FULL?13'd4096:PRESSURE_MIN_GAIN_Q12+mapped_delta;
 wire[12:0]target_gain=mute?13'd0:pressure_enable?calibrated_gain:13'd4096;
 // 主音量(选项A)：与压力增益合成同一个 Q12 增益，13x9 乘每帧一次，不额外占 DSP。
 // volume_gain_q8 是 top.v 的同一条曲线（256=单位增益），default 256 保持旧行为。
 wire[21:0]combined_gain_prod={9'd0,target_gain}*{13'd0,volume_gain_q8};
 wire[13:0]combined_gain_shift=combined_gain_prod>>8;
 wire[12:0]combined_gain=combined_gain_shift>14'd4096?13'd4096:combined_gain_shift[12:0];
 reg[12:0]gain_next;
 always @*begin
  gain_next=combined_gain;
  if(combined_gain>gain_q12 && combined_gain-gain_q12>PRESSURE_GAIN_STEP)gain_next=gain_q12+PRESSURE_GAIN_STEP;
  else if(gain_q12>combined_gain && gain_q12-combined_gain>PRESSURE_GAIN_STEP)gain_next=gain_q12-PRESSURE_GAIN_STEP;
 end
 reg signed[31:0]saved_sine=0,saved_bright=0;
 reg signed[50:0]base=0;
 wire signed[50:0]sine_extended=saved_sine;
 wire signed[50:0]numerator=base+mult_product;
 wire signed[50:0]master_sample=numerator >>> (8+VOICE_SHIFT);
 wire signed[50:0]output_value=(mult_product+51'sd2048) >>>12;
 wire raw_clip=output_value>51'sd8388607 || output_value< -51'sd8388608;
 wire signed[23:0]saturated=output_value>51'sd8388607 ? 24'sh7fffff :
  output_value< -51'sd8388608 ? 24'sh800000 : output_value[23:0];
 assign busy=state!=0;
 assign mult_request=(state==2 || state==4);
 always @(posedge clk)begin
  if(rst)begin
   state<=0;weight_state<=64;frame_weight<=64;gain_q12<=4096;frame_gain<=4096;
   saved_sine<=0;saved_bright<=0;base<=0;mult_operand_a<=0;mult_operand_b<=0;
   sample_out<=0;result_valid<=0;clip_count<=0;clip_event<=0;
  end else begin
   result_valid<=0;clip_event<=0;
   case(state)
    0:if(update)begin
     saved_sine<=sine_sum;saved_bright<=bright_sum;
     frame_weight<=active_weight;weight_state<=active_weight;
     frame_gain<=gain_next;gain_q12<=gain_next;state<=1;
    end
    1:begin
     mult_operand_a<=$signed({saved_bright[31],saved_bright})-$signed({saved_sine[31],saved_sine});
     mult_operand_b<={10'd0,frame_weight};
     base<=(sine_extended <<<8)-sine_extended+(51'sd1 << (7+VOICE_SHIFT));state<=2;
    end
    2:if(mult_ready)state<=3;
    3:begin
     mult_operand_a<=master_sample;mult_operand_b<={5'd0,frame_gain};state<=4;
    end
    4:if(mult_ready)state<=5;
    5:begin
     sample_out<=saturated;result_valid<=1;clip_event<=raw_clip;
     if(raw_clip && clip_count!=32'hffffffff)clip_count<=clip_count+32'd1;
     state<=0;
    end
    default:state<=0;
   endcase
  end
 end
`ifdef SIMULATION
 initial if(VOICE_SHIFT<2 || VOICE_SHIFT>8 || ADC_SPAN<1 || PRESSURE_GAIN_STEP<1)
  $fatal(1,"invalid wide_master parameters");
 always @(posedge clk)if(!rst && update && busy)$fatal(1,"wide_master frame overrun");
`endif
endmodule
