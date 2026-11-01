// RAM-backed oscillator lane, pipelined schedule.
//
// Eight state words per voice: 0=env/vel/retrig, 1=phase, 2=increment,
// 4={8'd0, bank[5:0], weight[15:0]}. The original 27-clock schedule serialised
// every multiply and waited for each ROM read; this version overlaps them:
//   - the four table reads run back to back (the bank selector registers the
//     bank used for each read, see instrument_rom_banks),
//   - the interpolation, bank-mix and amplitude multiplies are issued as soon
//     as their operands are ready and consumed two clocks later,
//   - envelope and velocity are folded into one 16-bit coefficient, so the sine
//     and bright paths need one amplitude multiply each.
// Net cost is 16 clocks per voice instead of 27. The folded coefficient is the
// only arithmetic change (at most one LSB versus the sequential rounding).
module instrument_ram_wavetable_engine #(
 parameter integer VOICE_COUNT=8,parameter integer FRAME_CYCLES=1024
)(
 input wire clk,rst,sample_tick,
 input wire cfg_valid,output wire cfg_ready,input wire[4:0]cfg_voice,
 input wire[31:0]cfg_increment,input wire[15:0]cfg_envelope,
 input wire[6:0]cfg_velocity,input wire cfg_retrigger,
 input wire[23:0]cfg_param,input wire[2:0]cfg_mask,
 output reg signed[31:0]sine_sum,output reg signed[31:0]bright_sum,output reg sums_valid,
 output wire busy,output wire initialized,
 input wire aux_request,output wire aux_ready,
 input wire signed[32:0]aux_operand_a,input wire signed[17:0]aux_operand_b,
 output wire signed[50:0]aux_product
);
 // 16-clock voice schedule.
 localparam [5:0] IDLE=0,
  F0=1,F1=2,F2=3,F3=4,
  A0=5,A1=6,B1=7,BA=8,BB=9,
  M1=10,M2=11,M3=12,M4=13,M5=14,M6=15,ACC=16,
  CFG0=20,CFG1=21,CFG2=22;
 reg[5:0]state=IDLE;reg[4:0]voice=0,cfg_id=0;
 reg[31:0]cfg_word=0,cfg_inc=0,cfg_param_r=0,param_word=0,phase=0,increment=0;
 reg[2:0]cfg_mask_r=0;
 reg[15:0]envelope=0,env_vel=0;reg[6:0]velocity=0;
 wire voice_audible=(envelope!=0 && velocity!=0);
 reg signed[31:0]sine_acc=0,bright_acc=0;
 localparam integer COUNT_BITS=$clog2(FRAME_CYCLES);
 reg[COUNT_BITS-1:0]frame_clock=0;reg seen_tick=0;
 wire ram_ready,ram_valid;wire[31:0]ram_data;
 wire ram_read=(state==F0 || state==F1 || state==F2 || state==F3);
 wire[8:0]ram_read_addr={1'b0,voice,3'b000}+(state==F1?9'd1:state==F2?9'd2:state==F3?9'd4:9'd0);
 wire cfg_accept=(state==IDLE && cfg_valid && cfg_ready);
 wire ram_write=cfg_accept || state==CFG1 || state==CFG2 || state==A1 || (state==A0 && param_word[24]);
 wire[8:0]ram_write_addr=cfg_accept?{1'b0,cfg_voice,3'b000}:
  (state==CFG1 || state==CFG2)?
  ({1'b0,cfg_id,3'b000}+(state==CFG2?9'd4:9'd2)):
  ({1'b0,voice,3'b000}+(state==A1?9'd1:9'd0));
 wire[31:0]ram_write_data=cfg_accept?{7'd0,cfg_retrigger,1'b0,cfg_velocity,cfg_envelope}:
  state==CFG1?cfg_inc:state==CFG2?{8'd0,cfg_param_r[23:0]}:
  state==A1?phase:(param_word &32'hfeffffff);
 voice_state_ram u_state(clk,rst,ram_write,ram_write_addr,ram_write_data,
  ram_read,ram_read_addr,ram_data,ram_valid,ram_ready);
 assign initialized=ram_ready;
 assign busy=!ram_ready || state!=IDLE;
 assign cfg_ready=ram_ready && state==IDLE && !sample_tick &&
  (!seen_tick || frame_clock<FRAME_CYCLES-4);
 always @(posedge clk)begin
  if(rst)begin frame_clock<=0;seen_tick<=0;end
  else if(sample_tick)begin frame_clock<=0;seen_tick<=1;end
  else if(frame_clock<FRAME_CYCLES-1)frame_clock<=frame_clock+1'b1;
 end

 reg[8:0]rom_addr=0,frac=0;reg[5:0]rom_bank=0,bank_low=0;reg[15:0]bank_weight=0;
 wire rom_ce=voice_audible && (state==A0 || state==A1 || state==B1 || state==BA);
 wire bank_ce=voice_audible && rom_ce;
 wire[15:0]sine_data,bright_data;
 gowin_prom_wave_sine u_sine(clk,rom_ce,rst,rom_addr,sine_data);
 instrument_rom_banks u_banks(clk,bank_ce,rst,rom_bank,rom_addr,bright_data);
 reg signed[15:0]a_sine=0,a_bright=0,b_sine=0,b_bright=0,bank_a=0,bank_b=0;
 reg signed[23:0]interp_s=0,interp_b=0;
 reg signed[32:0]mul_a=0;reg signed[17:0]mul_b=0;
 wire signed[50:0]product;
 wire mul_issue=(state==BA || state==BB || state==M1 || state==M2 || state==M3 ||
                 state==M4 || state==M5);
 wire mul_enable=voice_audible && mul_issue;
 assign aux_ready=ram_ready && !sample_tick && (state==IDLE || state==CFG0 || state==CFG1 || state==CFG2);
 wire aux_enable=aux_ready && aux_request;
 wire signed[32:0]active_mul_a=aux_enable?aux_operand_a:mul_a;
 wire signed[17:0]active_mul_b=aux_enable?aux_operand_b:mul_b;
 split_audio_multiplier #(33) u_multiplier(clk,rst,mul_enable || aux_enable,active_mul_a,active_mul_b,product);
 assign aux_product=product;
 wire signed[50:0]interp_delta=(product+51'sd1) >>> 1;
 wire signed[23:0]bank_interpolated=($signed(bank_a) <<< 8)+interp_delta;
 wire signed[50:0]bank_delta=(product+51'sd32768) >>>16;
 wire signed[23:0]env_vel_result=(product+51'sd64) >>>7;
 wire signed[23:0]amp_result=(product+51'sd32768) >>>16;
 wire signed[23:0]interp_b_new=interp_b+bank_delta;
 reg signed[23:0]scaled_s=0;
 wire signed[23:0]bright_amp=voice_audible?amp_result:24'sd0;
 wire signed[31:0]sine_mix=sine_acc+{{8{scaled_s[23]}},scaled_s};
 wire signed[31:0]bright_mix=bright_acc+{{8{bright_amp[23]}},bright_amp};

 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;voice<=0;cfg_id<=0;cfg_word<=0;cfg_inc<=0;cfg_param_r<=0;param_word<=0;
   phase<=0;increment<=0;envelope<=0;velocity<=0;env_vel<=0;sine_acc<=0;bright_acc<=0;
   sine_sum<=0;bright_sum<=0;sums_valid<=0;rom_addr<=0;frac<=0;rom_bank<=0;
   bank_low<=0;bank_weight<=0;mul_a<=0;mul_b<=0;interp_s<=0;interp_b<=0;
   a_sine<=0;a_bright<=0;b_sine<=0;b_bright<=0;bank_a<=0;bank_b<=0;scaled_s<=0;
  end else begin
   sums_valid<=0;
   case(state)
    IDLE:if(ram_ready)begin
     if(sample_tick)begin voice<=0;sine_acc<=0;bright_acc<=0;state<=F0;end
     else if(cfg_valid && cfg_ready)begin
      cfg_id<=cfg_voice;cfg_inc<=cfg_increment;
      cfg_word<={7'd0,cfg_retrigger,1'b0,cfg_velocity,cfg_envelope};
      cfg_param_r<=cfg_param;cfg_mask_r<=cfg_mask;
      state<=cfg_mask[1]?CFG1:(cfg_mask[2]?CFG2:IDLE);
     end
    end
    CFG1:state<=cfg_mask_r[2]?CFG2:IDLE;
    CFG2:state<=IDLE;
    // Fetch four state words; the three read words are issued back to back.
    F0:state<=F1;
    F1:begin param_word<=ram_data;envelope<=ram_data[15:0];velocity<=ram_data[22:16];state<=F2;end
    F2:begin phase<=ram_data;state<=F3;end
    F3:begin increment<=ram_data;phase<=param_word[24]?32'd0:phase+ram_data;state<=A0;end
    // Four table reads: bright/sine A, bright/sine B, then bank+1 A/B.
    A0:begin
     rom_addr<=phase[31:23];frac<=phase[22:14];
     rom_bank<=ram_data[21:16];bank_low<=ram_data[21:16];bank_weight<=ram_data[15:0];
     state<=A1;
    end
    A1:begin
     a_sine<=sine_data;a_bright<=bright_data;
     rom_addr<=phase[31:23]+9'd1;state<=B1;
    end
    B1:begin
     b_sine<=sine_data;b_bright<=bright_data;
     rom_bank<=(bank_low==6'd47)?6'd47:(bank_low+6'd1);
     rom_addr<=phase[31:23];state<=BA;
    end
    BA:begin
     bank_a<=bright_data;rom_addr<=phase[31:23]+9'd1;
     if(voice_audible)begin
      mul_a<=$signed({b_sine[15],b_sine})-$signed({a_sine[15],a_sine});
      mul_b<={9'd0,frac};
     end
     state<=BB;
    end
    BB:begin
     bank_b<=bright_data;
     if(voice_audible)begin
      mul_a<=$signed({b_bright[15],b_bright})-$signed({a_bright[15],a_bright});
      mul_b<={9'd0,frac};
     end
     state<=M1;
    end
    M1:begin
     interp_s<=($signed(a_sine) <<<8)+interp_delta;
     if(voice_audible)begin
      mul_a<=$signed({bank_b[15],bank_b})-$signed({bank_a[15],bank_a});
      mul_b<={9'd0,frac};
     end
     state<=M2;
    end
    M2:begin
     interp_b<=($signed(a_bright) <<<8)+interp_delta;
     if(voice_audible)begin mul_a<=$signed({17'd0,envelope});mul_b<={11'd0,velocity};end
     state<=M3;
    end
    M3:begin
     if(voice_audible)begin
      mul_a<=$signed({{9{bank_interpolated[23]}},bank_interpolated})-$signed({{9{interp_b[23]}},interp_b});
      mul_b<=$signed({2'd0,bank_weight});
     end
     state<=M4;
    end
    M4:begin
     env_vel<=env_vel_result[15:0];
     if(voice_audible)begin mul_a<=interp_s;mul_b<={2'd0,env_vel_result[15:0]};end
     state<=M5;
    end
    M5:begin
     if(voice_audible)begin
      mul_a<=$signed({{9{interp_b_new[23]}},interp_b_new});mul_b<={2'd0,env_vel};
     end
     scaled_s<=voice_audible?amp_result:24'sd0;
     state<=M6;
    end
    M6:begin
     interp_b<=interp_b_new;
     state<=ACC;
    end
    ACC:begin
     sine_acc<=sine_mix;bright_acc<=bright_mix;
     if(voice==VOICE_COUNT-1)begin
      sine_sum<=sine_mix;bright_sum<=bright_mix;sums_valid<=1;state<=IDLE;
     end else begin voice<=voice+5'd1;state<=F0;end
    end
    default:state<=IDLE;
   endcase
  end
 end
`ifdef SIMULATION
 initial if(VOICE_COUNT<1 || VOICE_COUNT>32 || FRAME_CYCLES<16*VOICE_COUNT+4)
  $fatal(1,"instrument_ram_wavetable_engine invalid voice/frame budget");
 always @(posedge clk)if(!rst)begin
  if(sample_tick && state!=IDLE)$fatal(1,"instrument_ram_wavetable_engine missed frame deadline");
  if(cfg_valid && cfg_ready && cfg_voice>=VOICE_COUNT)$fatal(1,"invalid configured voice");
 end
`endif
endmodule
