`timescale 1ns/1ps
// Codex 2026-10-23: peripheral timing budget at the interface pins.
module tb_standard27_io_budget;
 reg clk=0; always #18.5185185 clk=~clk;
 reg rst=1,start=0;
 wire bck,lrck,din,tick;
 i2s_tx #(.CLK_HZ(27000000),.SAMPLE_RATE_HZ(46875),.DATA_BITS(24)) audio(
 .clk(clk),.rst(rst),.sample_l(24'sh5a5a5a),.sample_r(24'sha5a5a5),
 .bck(bck),.lrck(lrck),.din(din),.sample_tick(tick));
 wire cs,sck,mosi,miso,busy,done;wire[11:0] data;
 mcp3208_spi adc(.clk(clk),.rst(rst),.start(start),.channel(3'd0),.miso(miso),
 .cs_n(cs),.sclk(sck),.mosi(mosi),.busy(busy),.done(done),.data(data),.data_valid(),.adc_data());
 // Worst budgets: 20ns output + 10ns board, 800ns device, 10ns board + 20ns input.
 wire ext_cs,ext_sck,ext_mosi,device_miso;
 assign #30 ext_cs=cs;assign #30 ext_sck=sck;assign #30 ext_mosi=mosi;
 assign #830 miso=device_miso;
 mcp3208_model device(.cs_n(ext_cs),.sclk(ext_sck),.mosi(ext_mosi),.miso(device_miso),
 .ch0(12'habc),.ch1(12'd0),.ch2(12'd0),.ch3(12'd0),.ch4(12'd0),.ch5(12'd0),.ch6(12'd0),.ch7(12'd0));
 genvar g;
 generate for(g=0;g<2;g=g+1)begin:corners
  wire pin_bck,pin_lrck,pin_din;
  assign #(g==0?0:40) pin_bck=bck;
  assign #(g==0?40:0) pin_lrck=lrck;
  assign #(g==0?40:0) pin_din=din;
  realtime last_data=0,last_lrck=0,last_rise=0,last_fall=0;
  integer rises=0;
  always @(pin_din)begin
   if(!rst && rises>3 && $realtime-last_rise<20) $fatal(1,"I2S hold <20ns");
   last_data=$realtime;
  end
  always @(pin_lrck)begin
   if(!rst && rises>3 && $realtime-last_rise<20) $fatal(1,"LRCK hold <20ns");
   last_lrck=$realtime;
  end
  always @(posedge pin_bck)begin
   if(!rst && rises>3)begin
    if($realtime-last_data<20 || $realtime-last_lrck<20) $fatal(1,"I2S setup <20ns");
    if($realtime-last_fall<100) $fatal(1,"BCK low pulse budget");
   end
   if(!rst) rises=rises+1;
   last_rise=$realtime;
  end
  always @(negedge pin_bck)begin
   if(!rst && rises>3 && $realtime-last_rise<100) $fatal(1,"BCK high pulse budget");
   last_fall=$realtime;
  end
 end endgenerate
 integer completed=0;
 always @(posedge clk) if(!rst && done)begin
  if(data!==12'habc)$fatal(1,"ADC delayed response actual=%h expected=abc",data);
  completed=completed+1;
 end
 initial begin
  repeat(20)@(negedge clk);rst=0;
  repeat(3)begin
   @(negedge clk);start=1;@(negedge clk);start=0;
   wait(busy);wait(done);repeat(60)@(negedge clk);
  end
  if(completed!=3 || corners[0].rises<100 || corners[1].rises<100)$fatal(1,"coverage incomplete");
  $display("PASS standard27 IO budget: two I2S skew corners and 3 ADC frames with 800ns device delay");$finish;
 end
 initial begin #1000000;$fatal(1,"IO budget timeout");end
endmodule
