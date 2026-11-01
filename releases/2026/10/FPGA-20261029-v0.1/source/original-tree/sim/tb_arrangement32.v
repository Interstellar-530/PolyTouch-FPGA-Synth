`timescale 1ns/1ps
module tb_arrangement32;
 reg clk=0,rst=1,restart=0,song=0,ready=1,tick=0;
 always #5 clk=~clk;
 wire valid; wire [15:0] data;
 song_player32 #(.UNIT_SAMPLES(64),.SECOND_UNIT_SAMPLES(64)) dut(
 .clk(clk),.rst(rst),.sample_tick(tick),.restart(restart),.song_select(song),
 .chord_set(1'b0),.tempo_sel(2'd0),.ev_ready(ready),.ev_wr(valid),.ev_data(data),.mel_idx_dbg(),.chord_idx_dbg());
 integer cycles=0,events=0,leads=0,beds=0,peak=0,count=0,n,k;
 reg [127:0] gates=0;
 reg [15:0] held; reg stalled=0;
 always @(negedge clk) begin
   cycles=cycles+1;tick=(cycles%32==0);ready=(cycles%11!=0 && cycles%11!=1);
 end
 always @(posedge clk) if(!rst && !restart) begin
   if(stalled && (!valid || data!==held)) $fatal(1,"backpressure changed event");
   stalled=valid&&!ready;held=data;
   if(valid&&ready) begin
     n=data[14:8]; if(n==0) $fatal(1,"zero-note event");
     if(data[15]) begin
       if(gates[n]) $fatal(1,"duplicate held note %d",n);
       gates[n]=1;
       if(data[7:0]==112) leads=leads+1;
       else begin
         if(data[7:0]==16 || data[7:0]==18) begin
           k=(n+12-(song?8:0))%12;
           if(k!=0 && k!=2 && k!=4 && k!=7 && k!=9) $fatal(1,"non-pentatonic moving line");
         end
         if(data[7:0]>42) $fatal(1,"accompaniment masks lead");
         beds=beds+1;
       end
     end else gates[n]=0;
     count=0;for(k=0;k<128;k=k+1) if(gates[k]) count=count+1;
     if(count>32) $fatal(1,"capacity exceeded");if(count>peak) peak=count;
     events=events+1;
   end
 end
 task run_song;
 input integer which;
 integer starts;
 begin
   @(negedge clk);rst=1;song=which;gates=0;events=0;leads=0;beds=0;peak=0;stalled=0;
   repeat(4) @(negedge clk);rst=0;
   wait(dut.state==4); // first wait follows opening event burst
   starts=events;
   wait(dut.state==2 && dut.word==0); #1;
   if(gates!==0) $fatal(1,"hanging notes on loop");
   if(leads!=(which==0?136:46)) $fatal(1,"original melody attack count changed %d",leads);
   if(beds<100 || peak<8 || peak>16) $fatal(1,"missing arrangement layers %d %d",beds,peak);
   $display("ARRANGEMENT32 song=%d events=%d lead=%d bed=%d peak_gates=%d",which,events,leads,beds,peak);
 end
 endtask
 initial begin run_song(0);run_song(1);$display("ARRANGEMENT32_PASS");$finish;end
 initial begin #30000000;$fatal(1,"arrangement timeout");end
endmodule
