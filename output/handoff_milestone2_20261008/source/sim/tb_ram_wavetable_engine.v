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
 reg signed[63:0]actual_s,actual_b;reg[1023:0]path;
 always @(posedge clk)cycles=cycles+1;
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
   end
   while(cycles<last_tick+PERIOD-1)@(negedge clk);
   tick=1;last_tick=cycles+1;@(negedge clk);tick=0;wait_cycles=0;
   while(!(&valid) && wait_cycles<PERIOD)begin @(negedge clk);wait_cycles=wait_cycles+1;end
   if(wait_cycles!=27*VOICES || !(&valid))$fatal(1,"RAM frame deadline %0d expected=%0d valid=%b",wait_cycles,27*VOICES,valid);
   actual_s=0;actual_b=0;
   for(n=0;n<LANES;n=n+1)begin actual_s=actual_s+$signed(ss[n]);actual_b=actual_b+$signed(bs[n]);end
   if(actual_s!==$signed(es) || actual_b!==$signed(eb))
    $fatal(1,"RAM frame=%0d expected=%0d/%0d actual=%0d/%0d",frames,es,eb,actual_s,actual_b);
   if(cap && case_id>=0)$fdisplay(cap,"%0d,%0d,%0d,%0d",frames,case_id,actual_s,actual_b);
   frames=frames+1;@(negedge clk);
  end
  $display("PASS tb_ram_wavetable_engine: voices=%0d lanes=%0d frames=%0d cycles/frame=%0d period=%0d",VOICES,LANES,frames,27*VOICES,PERIOD);$finish;
 end
 initial begin #5000000000;$fatal(1,"RAM engine timeout");end
endmodule
