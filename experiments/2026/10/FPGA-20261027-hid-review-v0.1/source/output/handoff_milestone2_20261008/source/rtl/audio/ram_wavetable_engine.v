// RAM-backed oscillator lane. Configuration supplies a bent increment and an
// externally managed envelope; event allocation/ADSR/voice fades are separate.
// Each voice uses four state words: gain/velocity/retrigger, phase, increment,
// reserved. Audio is24-bit, wave tables16-bit with9-bit phase interpolation.
module ram_wavetable_engine #(
 parameter integer VOICE_COUNT=8,parameter integer FRAME_CYCLES=1024
)(
 input wire clk,rst,sample_tick,
 input wire cfg_valid,output wire cfg_ready,input wire[4:0]cfg_voice,
 input wire[31:0]cfg_increment,input wire[15:0]cfg_envelope,
 input wire[6:0]cfg_velocity,input wire cfg_retrigger,
 output reg signed[31:0]sine_sum,output reg signed[31:0]bright_sum,output reg sums_valid,
 output wire busy,output wire initialized,
 input wire aux_request,output wire aux_ready,
 input wire signed[32:0]aux_operand_a,input wire signed[17:0]aux_operand_b,
 output wire signed[50:0]aux_product
);
 localparam [5:0] IDLE=0,ADDR_A=1,LATCH_A=2,ADDR_B=3,LATCH_B=4,
  INTERP_S=7,DIFF_B=8,INTERP_B=10,W_ENV_S=12,VEL_S=13,W_VEL_S=14,FIN_S=15,
  W_ENV_B=17,VEL_B=18,W_VEL_B=19,FIN_B=20,
  BANK_ADDR_A=26,BANK_LATCH_A=27,BANK_ADDR_B=28,BANK_LATCH_B=29,
  BANK_MUL=30,BANK_INTERP=31,BANK_MIX_MUL=32,BANK_MIX_APPLY=33,
  FETCH0=34,FETCH1=35,FETCH2=36,FETCH3=37,CFG0=38,CFG1=39;
 reg[5:0]state=IDLE;reg[4:0]voice=0,cfg_id=0;
 reg[31:0]cfg_word=0,cfg_inc=0,param_word=0,phase=0,increment=0;
 reg[15:0]envelope=0;reg[6:0]velocity=0;
 wire voice_audible=(envelope!=0 && velocity!=0);
 reg signed[31:0]sine_acc=0,bright_acc=0;
 localparam integer COUNT_BITS=$clog2(FRAME_CYCLES);
 reg[COUNT_BITS-1:0]frame_clock=0;reg seen_tick=0;
 wire ram_ready,ram_valid;wire[31:0]ram_data;
 wire ram_read=(state==FETCH0 || state==FETCH1 || state==FETCH2);
 wire[8:0]ram_read_addr={2'd0,voice,2'd0}+(state==FETCH1?9'd1:state==FETCH2?9'd2:9'd0);
 wire ram_write=state==CFG0 || state==CFG1 || state==LATCH_A || (state==ADDR_A && param_word[24]);
 wire[8:0]ram_write_addr=(state==CFG0 || state==CFG1)?
  ({2'd0,cfg_id,2'd0}+(state==CFG1?9'd2:9'd0)):
  ({2'd0,voice,2'd0}+(state==LATCH_A?9'd1:9'd0));
 wire[31:0]ram_write_data=state==CFG0?cfg_word:state==CFG1?cfg_inc:
  state==LATCH_A?phase:(param_word &32'hfeffffff);
 voice_state_ram u_state(clk,rst,ram_write,ram_write_addr,ram_write_data,
  ram_read,ram_read_addr,ram_data,ram_valid,ram_ready);
 assign initialized=ram_ready;
 assign busy=!ram_ready || state!=IDLE;
 // Leave enough clocks for the atomic two-word configuration write before
 // the next frame. The external tick must obey FRAME_CYCLES.
 assign cfg_ready=ram_ready && state==IDLE && !sample_tick &&
  (!seen_tick || frame_clock<FRAME_CYCLES-4);
 always @(posedge clk)begin
  if(rst)begin frame_clock<=0;seen_tick<=0;end
  else if(sample_tick)begin frame_clock<=0;seen_tick<=1;end
  else if(frame_clock<FRAME_CYCLES-1)frame_clock<=frame_clock+1'b1;
 end

 function[18:0]band_config;input[31:0]inc;begin
  if(inc>=32'h40000000)band_config={3'd4,16'd0};
  else if(inc>=32'h20000000)band_config={3'd3,inc[28:13]};
  else if(inc>=32'h10000000)band_config={3'd2,inc[27:12]};
  else if(inc>=32'h08000000)band_config={3'd1,inc[26:11]};
  else if(inc>=32'h04000000)band_config={3'd0,inc[25:10]};
  else band_config=0;
 end endfunction
 wire[18:0]selected_band=band_config(increment);
 reg[8:0]rom_addr=0,frac=0;reg[2:0]rom_bank=0,bank_low=0;reg[15:0]bank_weight=0;
 wire rom_ce=voice_audible && (state==ADDR_A || state==LATCH_A || state==ADDR_B);
 wire bank_ce=voice_audible && (rom_ce || state==BANK_ADDR_A || state==BANK_LATCH_A || state==BANK_ADDR_B);
 wire[15:0]sine_data,bright_data;
 gowin_prom_wave_sine u_sine(clk,rom_ce,rst,rom_addr,sine_data);
 gowin_prom_bright_bank u_bright(clk,bank_ce,rst,rom_bank,rom_addr,bright_data);
 reg signed[15:0]a_sine=0,a_bright=0,b_bright=0,bank_a=0;
 reg signed[23:0]interp_s=0,interp_b=0,scaled_s=0;
 reg signed[32:0]mul_a=0;reg signed[17:0]mul_b=0;
 wire signed[50:0]product;
 wire mul_enable=voice_audible && (state==DIFF_B || state==INTERP_S || state==W_ENV_S || state==W_VEL_S ||
  state==W_ENV_B || state==W_VEL_B || state==BANK_MUL || state==BANK_MIX_MUL);
 assign aux_ready=ram_ready && !sample_tick && (state==IDLE || state==CFG0 || state==CFG1);
 wire aux_enable=aux_ready && aux_request;
 wire signed[32:0]active_mul_a=aux_enable?aux_operand_a:mul_a;
 wire signed[17:0]active_mul_b=aux_enable?aux_operand_b:mul_b;
 split_audio_multiplier #(33) u_multiplier(clk,rst,mul_enable || aux_enable,active_mul_a,active_mul_b,product);
 assign aux_product=product;
 wire signed[50:0]interp_delta=(product+51'sd1) >>> 1;
 wire signed[23:0]bank_interpolated=($signed(bank_a) <<< 8)+interp_delta;
 wire signed[50:0]bank_delta=(product+51'sd32768) >>>16;
 wire signed[23:0]envelope_result=(product+51'sd32768) >>>16;
 wire signed[23:0]velocity_result=(product+51'sd64) >>>7;
 wire signed[31:0]scaled_s_extended={{8{scaled_s[23]}},scaled_s};
 wire signed[31:0]velocity_extended=voice_audible?{{8{velocity_result[23]}},velocity_result}:32'sd0;
 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;voice<=0;cfg_id<=0;cfg_word<=0;cfg_inc<=0;param_word<=0;
   phase<=0;increment<=0;envelope<=0;velocity<=0;sine_acc<=0;bright_acc<=0;
   sine_sum<=0;bright_sum<=0;sums_valid<=0;rom_addr<=0;frac<=0;rom_bank<=0;
   bank_low<=0;bank_weight<=0;mul_a<=0;mul_b<=0;interp_s<=0;interp_b<=0;scaled_s<=0;
  end else begin
   sums_valid<=0;
   case(state)
    IDLE:if(ram_ready)begin
     if(sample_tick)begin voice<=0;sine_acc<=0;bright_acc<=0;state<=FETCH0;end
     else if(cfg_valid && cfg_ready)begin
      cfg_id<=cfg_voice;cfg_inc<=cfg_increment;
      cfg_word<={7'd0,cfg_retrigger,1'b0,cfg_velocity,cfg_envelope};state<=CFG0;
     end
    end
    CFG0:state<=CFG1;
    CFG1:state<=IDLE;
    FETCH0:state<=FETCH1;
    FETCH1:begin param_word<=ram_data;envelope<=ram_data[15:0];velocity<=ram_data[22:16];state<=FETCH2;end
    FETCH2:begin phase<=ram_data;state<=FETCH3;end
    FETCH3:begin increment<=ram_data;phase<=param_word[24]?32'd0:phase+ram_data;state<=ADDR_A;end
    ADDR_A:begin
     rom_addr<=phase[31:23];frac<=phase[22:14];rom_bank<=selected_band[18:16];
     bank_low<=selected_band[18:16];bank_weight<=selected_band[15:0];state<=LATCH_A;
    end
    LATCH_A:begin rom_addr<=phase[31:23]+9'd1;state<=ADDR_B;end
    ADDR_B:begin a_sine<=sine_data;a_bright<=bright_data;state<=LATCH_B;end
    LATCH_B:begin
     b_bright<=bright_data;
     if(voice_audible)begin
      mul_a<=$signed({sine_data[15],sine_data})-$signed({a_sine[15],a_sine});mul_b<={9'd0,frac};
     end
     state<=DIFF_B;
    end
    DIFF_B:begin
     if(voice_audible)begin
      mul_a<=$signed({b_bright[15],b_bright})-$signed({a_bright[15],a_bright});mul_b<={9'd0,frac};
     end
     state<=INTERP_S;
    end
    INTERP_S:begin interp_s<=($signed(a_sine) <<<8)+interp_delta;state<=INTERP_B;end
    INTERP_B:begin interp_b<=($signed(a_bright) <<<8)+interp_delta;state<=BANK_ADDR_A;end
    BANK_ADDR_A:begin rom_bank<=bank_low==4?3'd4:bank_low+3'd1;rom_addr<=phase[31:23];state<=BANK_LATCH_A;end
    BANK_LATCH_A:begin rom_addr<=phase[31:23]+9'd1;state<=BANK_ADDR_B;end
    BANK_ADDR_B:begin bank_a<=bright_data;state<=BANK_LATCH_B;end
    BANK_LATCH_B:begin
     if(voice_audible)begin
      mul_a<=$signed({bright_data[15],bright_data})-$signed({bank_a[15],bank_a});mul_b<={9'd0,frac};
     end
     state<=BANK_MUL;
    end
    BANK_MUL:state<=BANK_INTERP;
    BANK_INTERP:begin
     if(voice_audible)begin
      mul_a<=$signed({{9{bank_interpolated[23]}},bank_interpolated})-$signed({{9{interp_b[23]}},interp_b});
      mul_b<=$signed({2'd0,bank_weight});
     end
     state<=BANK_MIX_MUL;
    end
    BANK_MIX_MUL:state<=BANK_MIX_APPLY;
    BANK_MIX_APPLY:begin
     interp_b<=interp_b+bank_delta;
     if(voice_audible)begin mul_a<=interp_s;mul_b<=$signed({2'd0,envelope});end
     state<=W_ENV_S;
    end
    W_ENV_S:state<=VEL_S;
    VEL_S:begin
     if(voice_audible)begin mul_a<=envelope_result;mul_b<={11'd0,velocity};end
     state<=W_VEL_S;
    end
    W_VEL_S:state<=FIN_S;
    FIN_S:begin
     scaled_s<=voice_audible?velocity_result:24'sd0;
     if(voice_audible)begin mul_a<=interp_b;mul_b<={2'd0,envelope};end
     state<=W_ENV_B;
    end
    W_ENV_B:state<=VEL_B;
    VEL_B:begin
     if(voice_audible)begin mul_a<=envelope_result;mul_b<={11'd0,velocity};end
     state<=W_VEL_B;
    end
    W_VEL_B:state<=FIN_B;
    FIN_B:begin
     sine_acc<=sine_acc+scaled_s_extended;bright_acc<=bright_acc+velocity_extended;
     if(voice==VOICE_COUNT-1)begin
      sine_sum<=sine_acc+scaled_s_extended;bright_sum<=bright_acc+velocity_extended;
      sums_valid<=1;state<=IDLE;
     end else begin voice<=voice+5'd1;state<=FETCH0;end
    end
    default:state<=IDLE;
   endcase
  end
 end
`ifdef SIMULATION
 initial if(VOICE_COUNT<1 || VOICE_COUNT>32 || FRAME_CYCLES<27*VOICE_COUNT+4)
  $fatal(1,"ram_wavetable_engine invalid voice/frame budget");
 always @(posedge clk)if(!rst)begin
  if(sample_tick && state!=IDLE)$fatal(1,"ram_wavetable_engine missed frame deadline");
  if(cfg_valid && cfg_ready && cfg_voice>=VOICE_COUNT)$fatal(1,"invalid configured voice");
 end
`endif
endmodule
