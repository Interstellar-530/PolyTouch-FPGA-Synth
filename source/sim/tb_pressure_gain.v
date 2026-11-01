`timescale 1ns/1ps
// Independent wide-integer reference: calibration, slew, bypass and clipping.
module tb_pressure_gain;
    reg clk=0; always #5 clk=~clk;
    reg rst=1, update=0, clear_clip=0, enable=1;
    reg [11:0] pressure=0;
    reg [7:0] weight=64;
    reg signed [18:0] sine_sum=20000, bright_sum=-10000;
    wire signed [15:0] actual,legacy,calibrated;
    wire [31:0] clips;
    wire clip_event;
    global_crossfade #(.PRESSURE_GAIN_ENABLE(1)) dut(
      .clk(clk),.rst(rst),.update(update),.clear_clip(clear_clip),
      .mix_weight(weight),.sine_sum(sine_sum),.bright_sum(bright_sum),
      .sample_out(actual),.clip_count(clips),.clip_event(clip_event),
      .pressure_enable(enable),.pressure_level(pressure));
    global_crossfade legacy_dut(
      .clk(clk),.rst(rst),.update(update),.clear_clip(clear_clip),
      .mix_weight(weight),.sine_sum(sine_sum),.bright_sum(bright_sum),
      .sample_out(legacy),.pressure_enable(enable),.pressure_level(pressure));
    global_crossfade #(.PRESSURE_GAIN_ENABLE(1),.PRESSURE_ADC_LOW(300),
      .PRESSURE_ADC_FULL(3900),.PRESSURE_MIN_GAIN_Q12(512),.PRESSURE_GAIN_STEP(4096)) cal_dut(
      .clk(clk),.rst(rst),.update(update),.clear_clip(clear_clip),
      .mix_weight(weight),.sine_sum(sine_sum),.bright_sum(bright_sum),
      .sample_out(calibrated),.pressure_enable(enable),.pressure_level(pressure));
    integer gain_ref=4096,target,cal_gain,i,cases=0,old_gain;
    reg [31:0] count_ref=0,rng=32'hf5022016;
    reg signed [63:0] pre_sat,base,expected,cal_expected,legacy_expected;
    function signed [63:0] master_ref;
      input integer s,b,w;reg signed [63:0] wide;
      begin wide=s;wide=wide*(255-w)+$signed(b)*w+127;
        master_ref=(wide>>>8)>>>1;end
    endfunction
    function signed [15:0] sat16;
      input signed [63:0] x;
      begin if(x>32767)sat16=32767;else if(x< -32768)sat16=-32768;else sat16=x;end
    endfunction
    function [31:0] rand32;
      input [31:0] x;reg [31:0] y;
      begin y=x^(x<<13);y=y^(y>>17);rand32=y^(y<<5);end
    endfunction
    task frame;
      begin
        @(negedge clk);update=1;
        target=pressure<=128 ? 1024 : pressure>=3200 ? 4096 : 1024+pressure-128;
        if(!enable)target=4096;
        old_gain=gain_ref;
        if(target>gain_ref+32)gain_ref=gain_ref+32;
        else if(target<gain_ref-32)gain_ref=gain_ref-32;
        else gain_ref=target;
        cal_gain=pressure<=300 ? 512 : pressure>=3900 ? 4096 :
                 512+((pressure-300)*3584)/3600;
        if(!enable)cal_gain=4096;
        base=master_ref(sine_sum,bright_sum,weight);
        pre_sat=(base*gain_ref)>>>12;
        expected=sat16(pre_sat);legacy_expected=sat16(base);
        cal_expected=sat16((base*cal_gain)>>>12);
        if(clear_clip)count_ref=0;
        else if(pre_sat>32767 || pre_sat< -32768)count_ref=count_ref+1;
        @(posedge clk);#1;
        if(actual!==expected[15:0] || legacy!==legacy_expected[15:0] ||
           calibrated!==cal_expected[15:0] || dut.g_pressure.gain_q12!==gain_ref[12:0] ||
           cal_dut.g_pressure.gain_q12!==cal_gain[12:0] ||
           clips!==count_ref || clip_event!==((pre_sat>32767)||(pre_sat< -32768)))
          $fatal(1,"gain case=%0d p=%0d gain=%0d actual=%0d expected=%0d legacy=%0d calibrated=%0d/%0d clips=%0d/%0d",
            cases,pressure,gain_ref,actual,expected,legacy,calibrated,cal_expected,clips,count_ref);
        if(gain_ref-old_gain>32 || old_gain-gain_ref>32)$fatal(1,"slew exceeded 32/frame");
        @(negedge clk);update=0;cases=cases+1;
      end
    endtask
    initial begin
      repeat(3)@(negedge clk);rst=0;
      repeat(100)frame();
      if(gain_ref!=1024)$fatal(1,"no-pressure floor not reached");
      pressure=4095;old_gain=dut.g_pressure.gain_q12;
      repeat(10)@(negedge clk);
      if(dut.g_pressure.gain_q12!==old_gain[12:0])$fatal(1,"gain moved off frame boundary");
      repeat(100)frame();
      if(gain_ref!=4096)$fatal(1,"full pressure did not reach unity");
      pressure=0;repeat(100)frame();enable=0;repeat(100)frame();
      if(actual!==legacy)$fatal(1,"runtime bypass differs after settling");
      enable=1;pressure=0;repeat(100)frame();
      for(i=0;i<4096;i=i+1)begin
        pressure=i;rng=rand32(rng);sine_sum=rng[18:0];
        rng=rand32(rng);bright_sum=rng[18:0];weight=rng[31:24];frame();
      end
      sine_sum=250000;bright_sum=250000;pressure=0;repeat(100)frame();
      if(actual>=32767 || legacy!==16'sd32767)$fatal(1,"VCA placed after clipping");
      clear_clip=1;frame();clear_clip=0;
      pressure=4095;repeat(100)frame();
      if(actual!==16'sd32767 || clips==0)$fatal(1,"post-VCA overdrive not counted");
      $display("METRIC pressure_gain adc_codes=4096 gain_floor=1024 gain_max=4096 slew=32/frame full_span_frames=96");
      $display("PASS tb_pressure_gain: %0d frames, signed reference, calibration, slew, both bypasses and pre-saturation VCA",cases);
      $finish;
    end
    initial begin #2_000_000;$fatal(1,"pressure gain timeout");end
endmodule
