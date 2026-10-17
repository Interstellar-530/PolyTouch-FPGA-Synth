`timescale 1ns/1ps
module tb_ram_wavetable_engine #(
 parameter integer VOICES=8,parameter integer LANES=1,parameter integer PERIOD=256
);
`ifdef GOWIN_VENDOR_MODEL
 GSR GSR(.GSRI(1'b1));
`endif
 reg clk=0;always #(1.0e9/(2.0*48000*PERIOD))clk=~clk;
 reg rst=1,tick=0;reg[LANES-1:0]cfg_valid=0;
 wire[LANES-1:0]cfg_ready,valid,busy,initialized;
 reg[4:0]cfg_voice=0;reg[31:0]cfg_inc=0;reg[15:0]cfg_env=0;reg[6:0]cfg_vel=0;reg cfg_rt=0;
 wire signed[31:0]ss[0:LANES-1],bs[0:LANES-1];
 genvar g;generate for(g=0;g<LANES;g=g+1)begin:lane
  ram_wavetable_engine #(.VOICE_COUNT(VOICES),.FRAME_CYCLES(PERIOD)) dut(
   .clk(clk),.rst(rst),.sample_tick(tick),.cfg_valid(cfg_valid[g]),.cfg_ready(cfg_ready[g]),
   .cfg_voice(cfg_voice),.cfg_increment(cfg_inc),.cfg_envelope(cfg_env),.cfg_velocity(cfg_vel),.cfg_retrigger(cfg_rt),
   .sine_sum(ss[g]),.bright_sum(bs[g]),.sums_valid(valid[g]),.busy(busy[g]),.initialized(initialized[g]));
 end endgenerate
 integer fd,cap=0,rc,voice_id,case_id,es,eb,frames=0,cycles=0,last_tick=0,n,wait_cycles;
 integer product_requests=0,rom_reads=0,active_count=0;
 integer total_products=0,avoided_products=0;
 reg[VOICES*LANES-1:0]active_voices=0;
 wire[LANES-1:0]mult_en,sine_ce,bright_ce;
 generate for(genvar j=0;j<LANES;j=j+1)begin:activity
  assign mult_en[j]=lane[j].dut.mul_enable;
  assign sine_ce[j]=lane[j].dut.rom_ce;
  assign bright_ce[j]=lane[j].dut.bank_ce;
  reg signed[32:0]previous_a=0;reg signed[17:0]previous_b=0;reg previous_audible=0,previous_reset=1;
  always @(negedge clk)begin
   if(!rst && !previous_reset && !previous_audible && !lane[j].dut.voice_audible &&
      (previous_a!==lane[j].dut.mul_a || previous_b!==lane[j].dut.mul_b))
    $fatal(1,"inactive multiplier operands toggled");
   previous_a=lane[j].dut.mul_a;previous_b=lane[j].dut.mul_b;
   previous_audible=lane[j].dut.voice_audible;previous_reset=rst;
  end
 end endgenerate
 reg signed[63:0]actual_s,actual_b;reg[1023:0]path;
 always @(posedge clk)begin
  cycles=cycles+1;
  if(tick)begin product_requests=0;rom_reads=0;end
  for(integer j=0;j<LANES;j=j+1)begin
   if(mult_en[j])product_requests=product_requests+1;
   if(sine_ce[j])rom_reads=rom_reads+1;
   if(bright_ce[j])rom_reads=rom_reads+1;
  end
 end
 initial begin
  if(!$value$plusargs("VECTORS=%s",path))path="sim/vectors/ram_engine_smoke.txt";
  fd=$fopen(path,"r");if(!fd)$fatal(1,"RAM engine vector file unavailable");
  if($value$plusargs("CAPTURE=%s",path))cap=$fopen(path,"w");
  if(cap)$fdisplay(cap,"frame,case_id,sine,bright");
  repeat(4)@(negedge clk);rst=0;wait(&initialized);@(negedge clk);
  while(!$feof(fd))begin
   rc=$fscanf(fd,"%d %h %h %h %d %d %d %d\n",voice_id,cfg_inc,cfg_env,cfg_vel,cfg_rt,case_id,es,eb);
   if(rc!=8)$fatal(1,"malformed RAM vectors frame=%0d",frames);
   if(voice_id>=0)begin
    if(voice_id>=VOICES*LANES)$fatal(1,"wrong vector profile");
    cfg_voice=voice_id%VOICES;
    wait(cfg_ready[voice_id/VOICES]);@(negedge clk);cfg_valid=1<<(voice_id/VOICES);
    @(negedge clk);cfg_valid=0;wait(!(|busy));@(negedge clk);
    active_voices[voice_id]=(cfg_env!=0 && cfg_vel!=0);
   end
   while(cycles<last_tick+PERIOD-1)@(negedge clk);
   tick=1;last_tick=cycles+1;@(negedge clk);tick=0;wait_cycles=0;
   while(!(&valid) && wait_cycles<PERIOD)begin @(negedge clk);wait_cycles=wait_cycles+1;end
   if(wait_cycles!=27*VOICES || !(&valid))$fatal(1,"RAM frame deadline %0d expected=%0d valid=%b",wait_cycles,27*VOICES,valid);
   active_count=0;for(n=0;n<VOICES*LANES;n=n+1)if(active_voices[n])active_count=active_count+1;
   if(product_requests!=8*active_count || rom_reads!=9*active_count)
    $fatal(1,"inactive activity gating mismatch products=%0d ROM=%0d active=%0d",product_requests,rom_reads,active_count);
   total_products=total_products+product_requests;avoided_products=avoided_products+8*(VOICES*LANES-active_count);
   actual_s=0;actual_b=0;
   for(n=0;n<LANES;n=n+1)begin actual_s=actual_s+$signed(ss[n]);actual_b=actual_b+$signed(bs[n]);end
   if(actual_s!==$signed(es) || actual_b!==$signed(eb))
    $fatal(1,"RAM frame=%0d expected=%0d/%0d actual=%0d/%0d",frames,es,eb,actual_s,actual_b);
   if(cap && case_id>=0)$fdisplay(cap,"%0d,%0d,%0d,%0d",frames,case_id,actual_s,actual_b);
   frames=frames+1;@(negedge clk);
  end
  $display("PASS tb_ram_wavetable_engine: voices=%0d lanes=%0d frames=%0d cycles/frame=%0d period=%0d products=%0d avoided_products=%0d",VOICES,LANES,frames,27*VOICES,PERIOD,total_products,avoided_products);$finish;
 end
 initial begin #5000000000;$fatal(1,"RAM engine timeout");end
endmodule
