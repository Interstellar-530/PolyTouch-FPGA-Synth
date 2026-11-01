`timescale 1ns/1ps
module tb_bank_audio_ab;
reg clk=0;always #5 clk=~clk;
reg rst=1,tick=0,retrigger=0;
reg [31:0] inc=0;reg [15:0] env=65535;reg [7:0] velocity=100;
reg [6:0] note=60;reg [2:0] tone=0;integer kind=1;
wire signed [20:0] old_s,old_b,new_s,new_b;wire old_v,new_v;
shared_wavetable_engine #(.BEND_SHARED_ENABLE(1),.BANDLIMIT_ENABLE(1),.GENERIC_BRIGHT_ENABLE(1),.GUITAR_ENABLE(1),.KEY_GAIN_ENABLE(1),.ZONE_LATCH_ENABLE(1),.STAGE_TIME_ENABLE(1),.STAGE_STEP_SAMPLES(8),.VOICES8(1),.EXTRA_FRACTION_BITS(2)) new_dut(.clk(clk),.rst(rst),.sample_tick(tick),.inc0(inc),.env0(env),.vel0(velocity),.note0(note),.retrig0(retrigger),.inc1(32'd0),.env1(16'd0),.vel1(8'd0),.note1(7'd0),.retrig1(1'b0),.inc2(32'd0),.env2(16'd0),.vel2(8'd0),.note2(7'd0),.retrig2(1'b0),.inc3(32'd0),.env3(16'd0),.vel3(8'd0),.note3(7'd0),.retrig3(1'b0),.inc4(32'd0),.env4(16'd0),.vel4(8'd0),.note4(7'd0),.retrig4(1'b0),.inc5(32'd0),.env5(16'd0),.vel5(8'd0),.note5(7'd0),.retrig5(1'b0),.inc6(32'd0),.env6(16'd0),.vel6(8'd0),.note6(7'd0),.retrig6(1'b0),.inc7(32'd0),.env7(16'd0),.vel7(8'd0),.note7(7'd0),.retrig7(1'b0),.piano_enable(kind==1),.guitar_enable(kind==2),.piano_tone(tone),.bend_ratio_q16(17'd65536),.mult_result(36'sd0),.mult_request(),.mult_operand_a(),.mult_operand_b(),.sine_sum(new_s),.bright_sum(new_b),.sums_valid(new_v));
old_shared_wavetable_engine #(.BEND_SHARED_ENABLE(1),.BANDLIMIT_ENABLE(1),.GENERIC_BRIGHT_ENABLE(1),.GUITAR_ENABLE(1),.KEY_GAIN_ENABLE(1),.ZONE_LATCH_ENABLE(1),.STAGE_TIME_ENABLE(1),.STAGE_STEP_SAMPLES(8),.VOICES8(1),.EXTRA_FRACTION_BITS(2)) old_dut(.clk(clk),.rst(rst),.sample_tick(tick),.inc0(inc),.env0(env),.vel0(velocity),.note0(note),.retrig0(retrigger),.inc1(32'd0),.env1(16'd0),.vel1(8'd0),.note1(7'd0),.retrig1(1'b0),.inc2(32'd0),.env2(16'd0),.vel2(8'd0),.note2(7'd0),.retrig2(1'b0),.inc3(32'd0),.env3(16'd0),.vel3(8'd0),.note3(7'd0),.retrig3(1'b0),.inc4(32'd0),.env4(16'd0),.vel4(8'd0),.note4(7'd0),.retrig4(1'b0),.inc5(32'd0),.env5(16'd0),.vel5(8'd0),.note5(7'd0),.retrig5(1'b0),.inc6(32'd0),.env6(16'd0),.vel6(8'd0),.note6(7'd0),.retrig6(1'b0),.inc7(32'd0),.env7(16'd0),.vel7(8'd0),.note7(7'd0),.retrig7(1'b0),.piano_enable(kind==1),.guitar_enable(kind==2),.piano_tone(tone),.bend_ratio_q16(17'd65536),.mult_result(36'sd0),.mult_request(),.mult_operand_a(),.mult_operand_b(),.sine_sum(old_s),.bright_sum(old_b),.sums_valid(old_v));
integer cfg,results,code,n,k,v,t,increment,c,frame,cycles,total=0,delta;
reg [2047:0] cases_path,results_path;
initial begin
 if(!$value$plusargs("cases=%s",cases_path) || !$value$plusargs("results=%s",results_path))$fatal(1,"missing paths");
 cfg=$fopen(cases_path,"r");results=$fopen(results_path,"w");
 if(!cfg || !results)$fatal(1,"file open failed");
 $fdisplay(results,"kind,note,velocity,tone,frame,env,old,new");
 while(!$feof(cfg))begin
  code=$fscanf(cfg,"%d %d %d %d %d\n",k,n,v,t,increment);
  if(code==5)begin
   rst=1;repeat(3)@(negedge clk);kind=k;note=n;velocity=v;tone=t;inc=increment;rst=0;
   for(frame=0;frame<64;frame=frame+1)begin
    case(frame%6) 0:env=0;1:env=1;2:env=256;3:env=8192;4:env=32768;5:env=65535;endcase
    retrigger=(frame==0);tick=1;@(negedge clk);tick=0;
    cycles=0;
    while(!new_v || !old_v)begin
     @(negedge clk);cycles=cycles+1;
     if(new_v!==old_v || cycles>500)$fatal(1,"frame timing changed");
    end
    if((^old_b===1'bx)||(^new_b===1'bx)||old_s!==new_s)$fatal(1,"unknown result or sine changed");
    delta=$signed(new_b)-$signed(old_b);
    if(k!=1 && delta!=0)$fatal(1,"unchanged instrument differs");
    if(delta>324 || delta< -324)$fatal(1,"piano exceeds table-derived error bound: %0d",delta);
    $fdisplay(results,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",k,n,v,t,frame,env,$signed(old_b),$signed(new_b));
    total=total+1;@(negedge clk);
   end
  end
 end
 $fclose(cfg);$fclose(results);$display("PASS tb_bank_audio_ab: %0d paired frames, mapping/timing/sine unchanged, guitar exact, piano bounded",total);$finish;
end
initial begin #50000000;$fatal(1,"timeout");end
endmodule
