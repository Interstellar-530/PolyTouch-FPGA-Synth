`timescale 1ns/1ps
// Independent signed-integer model and production-rate scheduling audit.
module tb_review_engine;
    reg clk=0; always #5 clk=~clk;
    reg rst=1, tick=0;
    reg [31:0] ph0,ph1,ph2,ph3;
    reg [15:0] en0,en1,en2,en3;
    reg [7:0] ve0,ve1,ve2,ve3;
    wire signed [18:0] ss,bs;
    wire valid;
    shared_wavetable_engine dut(.clk(clk),.rst(rst),.sample_tick(tick),
      .inc0(32'd1),.inc1(32'd1),.inc2(32'd1),.inc3(32'd1),
      .retrig0(1'b0),.retrig1(1'b0),.retrig2(1'b0),.retrig3(1'b0),
      .env0(en0),.env1(en1),.env2(en2),.env3(en3),
      .vel0(ve0),.vel1(ve1),.vel2(ve2),.vel3(ve3),
      .sine_sum(ss),.bright_sum(bs),.sums_valid(valid));
    reg signed [15:0] sine[0:511],bright[0:511];
    reg [31:0] rng=32'h76101642;
    integer i,cycles,maxcycles=0,mincycles=9999,es,eb;
    function [31:0] rand32;
      input [31:0] x;
      reg [31:0] y;
      begin y=x^(x<<13); y=y^(y>>17); rand32=y^(y<<5); end
    endfunction
    function integer voice_ref;
      input [31:0] ph; input [15:0] en; input [7:0] vel; input integer tableid;
      integer addr,frac,ya,yb; reg signed [63:0] interpolated,product,voiced;
      begin
        addr=ph>>23; frac=(ph>>14)&511;
        ya=tableid ? $signed(bright[addr]) : $signed(sine[addr]);
        yb=tableid ? $signed(bright[(addr+1)&511]) : $signed(sine[(addr+1)&511]);
        interpolated=ya+(($signed(yb-ya)*frac+256)>>>9);
        product=interpolated*$signed({1'b0,en}); voiced=product>>>16;
        product=voiced*$signed({1'b0,vel}); voice_ref=product>>>7;
      end
    endfunction
    initial begin
      $readmemh("rtl/audio/wave_sine.hex",sine);
      $readmemh("rtl/audio/wave_bright.hex",bright);
      en0=0;en1=0;en2=0;en3=0;ve0=0;ve1=0;ve2=0;ve3=0;
      ph0=0;ph1=0;ph2=0;ph3=0;
      force dut.phase0=ph0;force dut.phase1=ph1;
      force dut.phase2=ph2;force dut.phase3=ph3;
      repeat(4) @(negedge clk);rst=0;
      for(i=0;i<2048;i=i+1) begin
        rng=rand32(rng);ph0=rng;rng=rand32(rng);ph1=rng;
        rng=rand32(rng);ph2=rng;rng=rand32(rng);ph3=rng;
        rng=rand32(rng);en0=rng[15:0];en1=rng[31:16];
        rng=rand32(rng);en2=rng[15:0];en3=rng[31:16];
        rng=rand32(rng);ve0={1'b0,rng[6:0]};ve1={1'b0,rng[14:8]};
        ve2={1'b0,rng[22:16]};ve3={1'b0,rng[30:24]};
        es=voice_ref(ph0,en0,ve0,0)+voice_ref(ph1,en1,ve1,0)+
           voice_ref(ph2,en2,ve2,0)+voice_ref(ph3,en3,ve3,0);
        eb=voice_ref(ph0,en0,ve0,1)+voice_ref(ph1,en1,ve1,1)+
           voice_ref(ph2,en2,ve2,1)+voice_ref(ph3,en3,ve3,1);
        @(negedge clk);tick=1;@(negedge clk);tick=0;cycles=0;
        while(!valid && cycles<256) begin @(negedge clk);cycles=cycles+1;end
        if(!valid || $signed(ss)!=es || $signed(bs)!=eb)
          $fatal(1,"engine case=%0d sine=%0d ref=%0d bright=%0d ref=%0d cycles=%0d",i,ss,es,bs,eb,cycles);
        if(cycles>maxcycles)maxcycles=cycles;if(cycles<mincycles)mincycles=cycles;
        repeat(256-cycles-1) @(negedge clk);
      end
      $display("METRIC engine cases=2048 voices=4 cycles_min=%0d cycles_max=%0d frame_budget=256",mincycles,maxcycles);
      $display("PASS tb_review_engine: random phases, signed sums, full envelope and MIDI velocities");$finish;
    end
    initial begin #20_000_000;$fatal(1,"review engine timeout");end
endmodule
