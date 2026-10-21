`timescale 1ns/1ps
module tb_review_velocity_equivalence;
reg clk=0; always #5 clk=~clk;
reg rst=1,tick=0,piano=1,guitar=0;
reg [31:0] inc[0:7]; reg [15:0] env[0:7];
reg [7:0] raw_velocity[0:7],reference_velocity[0:7];
reg [6:0] note[0:7]; reg [7:0] retrig=0;
reg [16:0] ratio=17'd65536;
wire [2:0] nv,rv,nreq,rreq;
wire signed [20:0] ns[0:2],nb[0:2],rs[0:2],rb[0:2];
wire signed [17:0] na[0:2],nbop[0:2],ra[0:2],rbop[0:2];
wire signed [18:0] ns0,nb0;
reg signed [35:0] nprod0=0;
always @(posedge clk) if(nreq[0]) nprod0<=na[0]*nbop[0];
shared_wavetable_engine #(.VOICES8(0),.EXTRA_FRACTION_BITS(0),.SHARED_MULT_ENABLE(0),.BEND_SHARED_ENABLE(0),.BANDLIMIT_ENABLE(0),.KEY_GAIN_ENABLE(1)) ndut0(.clk(clk),.rst(rst),.sample_tick(tick),.inc0(inc[0]),.env0(env[0]),.vel0(raw_velocity[0]),.note0(note[0]),.retrig0(retrig[0]),.inc1(inc[1]),.env1(env[1]),.vel1(raw_velocity[1]),.note1(note[1]),.retrig1(retrig[1]),.inc2(inc[2]),.env2(env[2]),.vel2(raw_velocity[2]),.note2(note[2]),.retrig2(retrig[2]),.inc3(inc[3]),.env3(env[3]),.vel3(raw_velocity[3]),.note3(note[3]),.retrig3(retrig[3]),.inc4(inc[4]),.env4(env[4]),.vel4(raw_velocity[4]),.note4(note[4]),.retrig4(retrig[4]),.inc5(inc[5]),.env5(env[5]),.vel5(raw_velocity[5]),.note5(note[5]),.retrig5(retrig[5]),.inc6(inc[6]),.env6(env[6]),.vel6(raw_velocity[6]),.note6(note[6]),.retrig6(retrig[6]),.inc7(inc[7]),.env7(env[7]),.vel7(raw_velocity[7]),.note7(note[7]),.retrig7(retrig[7]),.piano_enable(piano),.guitar_enable(guitar),.piano_tone(3'd4),.bend_ratio_q16(ratio),.sine_sum(ns0),.bright_sum(nb0),.sums_valid(nv[0]),.mult_request(nreq[0]),.mult_operand_a(na[0]),.mult_operand_b(nbop[0]),.mult_result(nprod0));
assign ns[0]=$signed(ns0); assign nb[0]=$signed(nb0);
wire signed [18:0] rs0,rb0;
reg signed [35:0] rprod0=0;
always @(posedge clk) if(rreq[0]) rprod0<=ra[0]*rbop[0];
review_baseline_engine #(.VOICES8(0),.EXTRA_FRACTION_BITS(0),.SHARED_MULT_ENABLE(0),.BEND_SHARED_ENABLE(0),.BANDLIMIT_ENABLE(0),.KEY_GAIN_ENABLE(1)) rdut0(.clk(clk),.rst(rst),.sample_tick(tick),.inc0(inc[0]),.env0(env[0]),.vel0(reference_velocity[0]),.note0(note[0]),.retrig0(retrig[0]),.inc1(inc[1]),.env1(env[1]),.vel1(reference_velocity[1]),.note1(note[1]),.retrig1(retrig[1]),.inc2(inc[2]),.env2(env[2]),.vel2(reference_velocity[2]),.note2(note[2]),.retrig2(retrig[2]),.inc3(inc[3]),.env3(env[3]),.vel3(reference_velocity[3]),.note3(note[3]),.retrig3(retrig[3]),.inc4(inc[4]),.env4(env[4]),.vel4(reference_velocity[4]),.note4(note[4]),.retrig4(retrig[4]),.inc5(inc[5]),.env5(env[5]),.vel5(reference_velocity[5]),.note5(note[5]),.retrig5(retrig[5]),.inc6(inc[6]),.env6(env[6]),.vel6(reference_velocity[6]),.note6(note[6]),.retrig6(retrig[6]),.inc7(inc[7]),.env7(env[7]),.vel7(reference_velocity[7]),.note7(note[7]),.retrig7(retrig[7]),.piano_enable(piano),.guitar_enable(guitar),.piano_tone(3'd4),.bend_ratio_q16(ratio),.sine_sum(rs0),.bright_sum(rb0),.sums_valid(rv[0]),.mult_request(rreq[0]),.mult_operand_a(ra[0]),.mult_operand_b(rbop[0]),.mult_result(rprod0));
assign rs[0]=$signed(rs0); assign rb[0]=$signed(rb0);
wire signed [20:0] ns1,nb1;
reg signed [35:0] nprod1=0;
always @(posedge clk) if(nreq[1]) nprod1<=na[1]*nbop[1];
shared_wavetable_engine #(.VOICES8(1),.EXTRA_FRACTION_BITS(2),.SHARED_MULT_ENABLE(1),.BEND_SHARED_ENABLE(1),.BANDLIMIT_ENABLE(1),.KEY_GAIN_ENABLE(1),.GENERIC_BRIGHT_ENABLE(1),.GUITAR_ENABLE(1),.ZONE_LATCH_ENABLE(1),.STAGE_TIME_ENABLE(1)) ndut1(.clk(clk),.rst(rst),.sample_tick(tick),.inc0(inc[0]),.env0(env[0]),.vel0(raw_velocity[0]),.note0(note[0]),.retrig0(retrig[0]),.inc1(inc[1]),.env1(env[1]),.vel1(raw_velocity[1]),.note1(note[1]),.retrig1(retrig[1]),.inc2(inc[2]),.env2(env[2]),.vel2(raw_velocity[2]),.note2(note[2]),.retrig2(retrig[2]),.inc3(inc[3]),.env3(env[3]),.vel3(raw_velocity[3]),.note3(note[3]),.retrig3(retrig[3]),.inc4(inc[4]),.env4(env[4]),.vel4(raw_velocity[4]),.note4(note[4]),.retrig4(retrig[4]),.inc5(inc[5]),.env5(env[5]),.vel5(raw_velocity[5]),.note5(note[5]),.retrig5(retrig[5]),.inc6(inc[6]),.env6(env[6]),.vel6(raw_velocity[6]),.note6(note[6]),.retrig6(retrig[6]),.inc7(inc[7]),.env7(env[7]),.vel7(raw_velocity[7]),.note7(note[7]),.retrig7(retrig[7]),.piano_enable(piano),.guitar_enable(guitar),.piano_tone(3'd4),.bend_ratio_q16(ratio),.sine_sum(ns1),.bright_sum(nb1),.sums_valid(nv[1]),.mult_request(nreq[1]),.mult_operand_a(na[1]),.mult_operand_b(nbop[1]),.mult_result(nprod1));
assign ns[1]=$signed(ns1); assign nb[1]=$signed(nb1);
wire signed [20:0] rs1,rb1;
reg signed [35:0] rprod1=0;
always @(posedge clk) if(rreq[1]) rprod1<=ra[1]*rbop[1];
review_baseline_engine #(.VOICES8(1),.EXTRA_FRACTION_BITS(2),.SHARED_MULT_ENABLE(1),.BEND_SHARED_ENABLE(1),.BANDLIMIT_ENABLE(1),.KEY_GAIN_ENABLE(1),.GENERIC_BRIGHT_ENABLE(1),.GUITAR_ENABLE(1),.ZONE_LATCH_ENABLE(1),.STAGE_TIME_ENABLE(1)) rdut1(.clk(clk),.rst(rst),.sample_tick(tick),.inc0(inc[0]),.env0(env[0]),.vel0(reference_velocity[0]),.note0(note[0]),.retrig0(retrig[0]),.inc1(inc[1]),.env1(env[1]),.vel1(reference_velocity[1]),.note1(note[1]),.retrig1(retrig[1]),.inc2(inc[2]),.env2(env[2]),.vel2(reference_velocity[2]),.note2(note[2]),.retrig2(retrig[2]),.inc3(inc[3]),.env3(env[3]),.vel3(reference_velocity[3]),.note3(note[3]),.retrig3(retrig[3]),.inc4(inc[4]),.env4(env[4]),.vel4(reference_velocity[4]),.note4(note[4]),.retrig4(retrig[4]),.inc5(inc[5]),.env5(env[5]),.vel5(reference_velocity[5]),.note5(note[5]),.retrig5(retrig[5]),.inc6(inc[6]),.env6(env[6]),.vel6(reference_velocity[6]),.note6(note[6]),.retrig6(retrig[6]),.inc7(inc[7]),.env7(env[7]),.vel7(reference_velocity[7]),.note7(note[7]),.retrig7(retrig[7]),.piano_enable(piano),.guitar_enable(guitar),.piano_tone(3'd4),.bend_ratio_q16(ratio),.sine_sum(rs1),.bright_sum(rb1),.sums_valid(rv[1]),.mult_request(rreq[1]),.mult_operand_a(ra[1]),.mult_operand_b(rbop[1]),.mult_result(rprod1));
assign rs[1]=$signed(rs1); assign rb[1]=$signed(rb1);
wire signed [20:0] ns2,nb2;
reg signed [35:0] nprod2=0;
always @(posedge clk) if(nreq[2]) nprod2<=na[2]*nbop[2];
shared_wavetable_engine #(.VOICES8(1),.EXTRA_FRACTION_BITS(2),.SHARED_MULT_ENABLE(0),.BEND_SHARED_ENABLE(0),.BANDLIMIT_ENABLE(0),.KEY_GAIN_ENABLE(0)) ndut2(.clk(clk),.rst(rst),.sample_tick(tick),.inc0(inc[0]),.env0(env[0]),.vel0(raw_velocity[0]),.note0(note[0]),.retrig0(retrig[0]),.inc1(inc[1]),.env1(env[1]),.vel1(raw_velocity[1]),.note1(note[1]),.retrig1(retrig[1]),.inc2(inc[2]),.env2(env[2]),.vel2(raw_velocity[2]),.note2(note[2]),.retrig2(retrig[2]),.inc3(inc[3]),.env3(env[3]),.vel3(raw_velocity[3]),.note3(note[3]),.retrig3(retrig[3]),.inc4(inc[4]),.env4(env[4]),.vel4(raw_velocity[4]),.note4(note[4]),.retrig4(retrig[4]),.inc5(inc[5]),.env5(env[5]),.vel5(raw_velocity[5]),.note5(note[5]),.retrig5(retrig[5]),.inc6(inc[6]),.env6(env[6]),.vel6(raw_velocity[6]),.note6(note[6]),.retrig6(retrig[6]),.inc7(inc[7]),.env7(env[7]),.vel7(raw_velocity[7]),.note7(note[7]),.retrig7(retrig[7]),.piano_enable(piano),.guitar_enable(guitar),.piano_tone(3'd4),.bend_ratio_q16(ratio),.sine_sum(ns2),.bright_sum(nb2),.sums_valid(nv[2]),.mult_request(nreq[2]),.mult_operand_a(na[2]),.mult_operand_b(nbop[2]),.mult_result(nprod2));
assign ns[2]=$signed(ns2); assign nb[2]=$signed(nb2);
wire signed [20:0] rs2,rb2;
reg signed [35:0] rprod2=0;
always @(posedge clk) if(rreq[2]) rprod2<=ra[2]*rbop[2];
review_baseline_engine #(.VOICES8(1),.EXTRA_FRACTION_BITS(2),.SHARED_MULT_ENABLE(0),.BEND_SHARED_ENABLE(0),.BANDLIMIT_ENABLE(0),.KEY_GAIN_ENABLE(0)) rdut2(.clk(clk),.rst(rst),.sample_tick(tick),.inc0(inc[0]),.env0(env[0]),.vel0(reference_velocity[0]),.note0(note[0]),.retrig0(retrig[0]),.inc1(inc[1]),.env1(env[1]),.vel1(reference_velocity[1]),.note1(note[1]),.retrig1(retrig[1]),.inc2(inc[2]),.env2(env[2]),.vel2(reference_velocity[2]),.note2(note[2]),.retrig2(retrig[2]),.inc3(inc[3]),.env3(env[3]),.vel3(reference_velocity[3]),.note3(note[3]),.retrig3(retrig[3]),.inc4(inc[4]),.env4(env[4]),.vel4(reference_velocity[4]),.note4(note[4]),.retrig4(retrig[4]),.inc5(inc[5]),.env5(env[5]),.vel5(reference_velocity[5]),.note5(note[5]),.retrig5(retrig[5]),.inc6(inc[6]),.env6(env[6]),.vel6(reference_velocity[6]),.note6(note[6]),.retrig6(retrig[6]),.inc7(inc[7]),.env7(env[7]),.vel7(reference_velocity[7]),.note7(note[7]),.retrig7(retrig[7]),.piano_enable(piano),.guitar_enable(guitar),.piano_tone(3'd4),.bend_ratio_q16(ratio),.sine_sum(rs2),.bright_sum(rb2),.sums_valid(rv[2]),.mult_request(rreq[2]),.mult_operand_a(ra[2]),.mult_operand_b(rbop[2]),.mult_result(rprod2));
assign rs[2]=$signed(rs2); assign rb[2]=$signed(rb2);

integer mode,v,i,j,cycle,frames=0,comparisons=0,negative_values=0,positive_values=0;
integer midframe_changes=0; reg [2:0] seen;
reg [31:0] seed=32'h613f2a09;
task set_reference;
 begin
  for(i=0;i<8;i=i+1)
   if(raw_velocity[i]>127) reference_velocity[i]=127;
   else reference_velocity[i]=raw_velocity[i];
 end
endtask
initial begin
 for(i=0;i<8;i=i+1)begin inc[i]=0;env[i]=0;raw_velocity[i]=0;reference_velocity[i]=0;note[i]=60;end
 repeat(4)@(negedge clk);rst=0;
 for(mode=0;mode<3;mode=mode+1)begin
  piano=(mode==0);guitar=(mode==1);
  for(v=0;v<256;v=v+1)begin
   for(i=0;i<8;i=i+1)begin
    seed={seed[30:0],seed[31]^seed[21]^seed[1]^seed[0]};
    raw_velocity[i]=(v+i*37)&255;
    env[i]=(v%19==0)?16'hffff:seed[15:0];
    if(v%23==0 && i==3)env[i]=0;
    note[i]=(v*7+i*19+mode*11)&127;
    inc[i]=32'd10000000+((v*83123+i*1122337)&32'h03ffffff);
    retrig[i]=(v%17==0);
   end
   ratio=17'd64000+(v*17);
   set_reference();tick=1;@(negedge clk);tick=0;
   cycle=0;seen=0;
   while(seen!=3'b111 && cycle<576)begin
    @(negedge clk);cycle=cycle+1;
    for(j=0;j<3;j=j+1)begin
     if(nv[j]!==rv[j] || nreq[j]!==rreq[j])
      $fatal(1,"schedule changed mode=%0d velocity=%0d lane=%0d cycle=%0d",mode,v,j,cycle);
     if(nreq[j] && (na[j]!==ra[j] || nbop[j]!==rbop[j]))
      $fatal(1,"multiplier operands differ mode=%0d velocity=%0d lane=%0d",mode,v,j);
     if(nv[j])begin
      if(seen[j])$fatal(1,"duplicate frame completion lane=%0d",j);
      if((^ns[j])===1'bx || (^nb[j])===1'bx || ns[j]!==rs[j] || nb[j]!==rb[j])
       $fatal(1,"signed result mismatch mode=%0d velocity=%0d lane=%0d got=%0d/%0d expected=%0d/%0d",mode,v,j,ns[j],nb[j],rs[j],rb[j]);
      seen[j]=1;comparisons=comparisons+1;
      if(ns[j]<0 || nb[j]<0)negative_values=negative_values+1;
      if(ns[j]>0 || nb[j]>0)positive_values=positive_values+1;
     end
    end
    if(cycle==(v%40)+1)begin
     for(i=0;i<8;i=i+1)raw_velocity[i]=255-raw_velocity[i];
     set_reference();midframe_changes=midframe_changes+1;
    end
   end
   if(seen!=3'b111)$fatal(1,"deadline mode=%0d velocity=%0d seen=%b",mode,v,seen);
   frames=frames+1;@(negedge clk);
  end
 end
 if(negative_values==0 || positive_values==0 || frames!=768 || comparisons!=2304)
  $fatal(1,"coverage missing frames=%0d comparisons=%0d positive=%0d negative=%0d",frames,comparisons,positive_values,negative_values);
 $display("PASS tb_review_velocity_equivalence: frames=%0d paired_results=%0d positive=%0d negative=%0d midframe_changes=%0d; 4/8 voices, local/shared, extra 0/2, piano/guitar/generic/bypass",frames,comparisons,positive_values,negative_values,midframe_changes);
 $finish;
end
initial begin #20000000;$fatal(1,"review timeout");end
endmodule
