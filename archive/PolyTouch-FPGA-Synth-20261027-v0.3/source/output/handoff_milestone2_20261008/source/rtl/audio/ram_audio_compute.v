// Frame-scheduled compute/master block, independent of the serializer clock.
module ram_audio_compute #(
 parameter integer VOICES=64,parameter integer FRAME_CYCLES=1024
)(
 input wire clk,rst,sample_tick,input wire cfg_valid,output wire cfg_ready,
 input wire[5:0]cfg_voice,input wire[31:0]cfg_increment,input wire[15:0]cfg_envelope,
 input wire[6:0]cfg_velocity,input wire cfg_retrigger,
 input wire[7:0]mix_weight,input wire pressure_enable,input wire[11:0]pressure_level,input wire mute,
 output wire signed[23:0]audio_sample,output wire sample_valid,
 output wire[31:0]clip_count,output wire initialized,
 output wire signed[31:0]sine_total,bright_total,output wire sums_valid,
 output wire master_req,master_ready
);
 localparam integer LANES=VOICES>32?2:1;
 localparam integer LANE_VOICES=VOICES/LANES;
 wire[LANES-1:0]cfg_ready_v,valid_v,busy_v,init_v,aux_ready_v;
 wire signed[31:0]sine_v[0:LANES-1],bright_v[0:LANES-1];
 wire signed[50:0]product_v[0:LANES-1];
 wire master_busy;wire signed[32:0]master_a;wire signed[17:0]master_b;
 wire selected_lane=cfg_voice>=LANE_VOICES;
 wire[4:0]selected_voice=cfg_voice%LANE_VOICES;
 genvar g;generate for(g=0;g<LANES;g=g+1)begin:lane
  ram_wavetable_engine #(.VOICE_COUNT(LANE_VOICES),.FRAME_CYCLES(FRAME_CYCLES)) u_core(
   .clk(clk),.rst(rst),.sample_tick(sample_tick),.cfg_valid(cfg_valid && (LANES==1 || selected_lane==g)),
   .cfg_ready(cfg_ready_v[g]),.cfg_voice(selected_voice),.cfg_increment(cfg_increment),
   .cfg_envelope(cfg_envelope),.cfg_velocity(cfg_velocity),.cfg_retrigger(cfg_retrigger),
   .sine_sum(sine_v[g]),.bright_sum(bright_v[g]),.sums_valid(valid_v[g]),.busy(busy_v[g]),.initialized(init_v[g]),
   .aux_request(g==0?master_req:1'b0),.aux_ready(aux_ready_v[g]),
   .aux_operand_a(g==0?master_a:33'sd0),.aux_operand_b(g==0?master_b:18'sd0),.aux_product(product_v[g]));
 end endgenerate
 assign cfg_ready=cfg_ready_v[LANES==1?0:selected_lane];
 assign initialized=&init_v;assign master_ready=aux_ready_v[0];
 generate if(LANES==1)begin:single_lane
  assign sine_total=sine_v[0];assign bright_total=bright_v[0];
 end else begin:dual_lane
  assign sine_total=sine_v[0]+sine_v[1];assign bright_total=bright_v[0]+bright_v[1];
 end endgenerate
 assign sums_valid=&valid_v;
 wide_master #(.VOICE_SHIFT($clog2(VOICES))) u_master(
  .clk(clk),.rst(rst),.update(sums_valid),.sine_sum(sine_total),.bright_sum(bright_total),
  .mix_weight(mix_weight),.pressure_enable(pressure_enable),.pressure_level(pressure_level),.mute(mute),
  .sample_out(audio_sample),.result_valid(sample_valid),.busy(master_busy),.clip_count(clip_count),.clip_event(),
  .mult_request(master_req),.mult_ready(master_ready),.mult_operand_a(master_a),.mult_operand_b(master_b),.mult_product(product_v[0]));
`ifdef SIMULATION
 initial if(VOICES!=8 && VOICES!=32 && VOICES!=64)$fatal(1,"RAM audio prototype supports8/32/64 voices");
 always @(posedge clk)if(!rst)begin
  if((|valid_v) && !(&valid_v))$fatal(1,"RAM lane completion skew");
  if(cfg_valid && cfg_ready && cfg_voice>=VOICES)$fatal(1,"invalid RAM audio configuration voice");
 end
`endif
endmodule
