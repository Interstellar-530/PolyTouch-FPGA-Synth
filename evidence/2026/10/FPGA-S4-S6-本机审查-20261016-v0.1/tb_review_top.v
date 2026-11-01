`timescale 1ns/1ps
// Two complete products with identical keys/pitch but different FSR pressure.
// This is an observation test: it expects to reproduce the known missing route.
module tb_review_top;
    reg clk=0;always #40.690104 clk=~clk;
    reg kr=0;reg [11:0] keys=12'hfff;
    reg [11:0] p0=0,p1=4095,bend=2048;
    wire cs0,sc0,mo0,mi0,cs1,sc1,mo1,mi1;
    top #(.AUDIO_IF(1)) a(.clk_27m(1'b0),.clk_12m288(clk),.key_rst(kr),
      .key_s1(1'b1),.key_s2(1'b1),.uart_rx(1'b1),.gpio_key_n(keys),
      .adc_cs_n(cs0),.adc_sck(sc0),.adc_mosi(mo0),.adc_miso(mi0));
    top #(.AUDIO_IF(1)) b(.clk_27m(1'b0),.clk_12m288(clk),.key_rst(kr),
      .key_s1(1'b1),.key_s2(1'b1),.uart_rx(1'b1),.gpio_key_n(keys),
      .adc_cs_n(cs1),.adc_sck(sc1),.adc_mosi(mo1),.adc_miso(mi1));
    mcp3208_model m0(.cs_n(cs0),.sclk(sc0),.mosi(mo0),.miso(mi0),
      .ch0(p0),.ch1(bend),.ch2(12'd0),.ch3(12'd0),.ch4(12'd0),.ch5(12'd0),.ch6(12'd0),.ch7(12'd0));
    mcp3208_model m1(.cs_n(cs1),.sclk(sc1),.mosi(mo1),.miso(mi1),
      .ch0(p1),.ch1(bend),.ch2(12'd0),.ch3(12'd0),.ch4(12'd0),.ch5(12'd0),.ch6(12'd0),.ch7(12'd0));
    integer i,nonzero=0,different=0;
    integer cyc=0,lastcs=-1,cs_gap=0,lastcommit=-1;
    real starttime,firsttime;
    always @(posedge clk) cyc=cyc+1;
    always @(negedge cs0) begin if(lastcs>=0)cs_gap=cyc-lastcs;lastcs=cyc;end
    initial begin
      repeat(10) @(negedge clk);kr=1;wait(!a.por);
      @(negedge clk);keys[9]=0;starttime=$realtime;
      wait(a.v_gate!=0);wait(a.final_sample!=0);firsttime=$realtime;
      $display("METRIC key_edge_to_first_internal_nonzero_us=%.3f",(firsttime-starttime)/1000.0);
      // Let pressure and envelope settle sufficiently for an audible comparison.
      repeat(800) @(posedge a.sample_tick);
      for(i=0;i<512;i=i+1) begin
        @(posedge a.sample_tick);#1;
        if(a.final_sample!==b.final_sample)different=different+1;
        if(a.final_sample!=0)nonzero=nonzero+1;
      end
      if(a.pressure_raw!==0 || b.pressure_raw!==4095 || nonzero<400)
        $fatal(1,"invalid pressure comparison setup p0=%0d p1=%0d nonzero=%0d",a.pressure_raw,b.pressure_raw,nonzero);
      $display("FINDING pressure_raw=0 versus 4095: compared=512 different_audio_frames=%0d nonzero_frames=%0d filtered=%0d/%0d",different,nonzero,a.pressure_level,b.pressure_level);
      if(different!=0)$fatal(1,"pressure-route finding no longer reproduces: update review");
      $display("METRIC ADC transaction_spacing_cycles=%0d per_channel_hz=1000 control_hz=2000",cs_gap);
      // A soft reset is expected to preserve old raw samples in this revision.
      bend=4095;repeat(6) @(posedge a.control_tick);#1;
      if(a.bend_raw!==4095)$fatal(1,"bend endpoint setup failed");
      @(negedge clk);kr=0;repeat(10) @(negedge clk);
      $display("FINDING soft_reset bend_raw=%0d pressure_raw=%0d adc_sel=%0d",a.bend_raw,a.pressure_raw,a.adc_sel);
      kr=1;
      repeat(6) @(posedge a.control_tick);#1;
      if(a.bend_q8!==512)$fatal(1,"bend did not recover after soft reset");
      $display("PASS tb_review_top: missing FSR audio route reproduced; ADC polling and reset observations captured");$finish;
    end
    initial begin #70_000_000;$fatal(1,"review top timeout");end
endmodule
