`timescale 1ns/1ps
// Actual GPIO + MCP3208 + synthesis + independent serial-I2S decode.
module tb_pressure_top;
    reg clk=0;always #40.690104 clk=~clk;
    reg kr=0;reg [11:0] keys=12'hfff;
    reg [11:0] pressure=0,bend=2048;
    wire cs0,sc0,mo0,mi0,cs1,sc1,mo1,mi1,bck,lrck,din;
    top #(.AUDIO_IF(1)) a(.clk_27m(1'b0),.clk_12m288(clk),.key_rst(kr),
      .key_s1(1'b1),.key_s2(1'b1),.uart_rx(1'b1),.gpio_key_n(keys),
      .adc_cs_n(cs0),.adc_sck(sc0),.adc_mosi(mo0),.adc_miso(mi0),
      .i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din));
    top #(.AUDIO_IF(1),.PRESSURE_ENABLE(0)) b(
      .clk_27m(1'b0),.clk_12m288(clk),.key_rst(kr),.key_s1(1'b1),.key_s2(1'b1),
      .uart_rx(1'b1),.gpio_key_n(keys),.adc_cs_n(cs1),.adc_sck(sc1),.adc_mosi(mo1),.adc_miso(mi1));
    mcp3208_model m0(.cs_n(cs0),.sclk(sc0),.mosi(mo0),.miso(mi0),
      .ch0(pressure),.ch1(bend),.ch2(12'd0),.ch3(12'd0),.ch4(12'd0),.ch5(12'd0),.ch6(12'd0),.ch7(12'd0));
    mcp3208_model m1(.cs_n(cs1),.sclk(sc1),.mosi(mo1),.miso(mi1),
      .ch0(pressure),.ch1(bend),.ch2(12'd0),.ch3(12'd0),.ch4(12'd0),.ch5(12'd0),.ch6(12'd0),.ch7(12'd0));
    wire signed [23:0] left_word,right_word;
    wire frame_valid;
    i2s_rx_model #(.DATA_BITS(24)) rx(.bck(bck),.rst(a.por),.lrck(lrck),.din(din),
      .left_word(left_word),.right_word(right_word),.frame_valid(frame_valid));
    reg [23:0] sent_current=0,sent_previous=0;
    integer serial_frames=0,frames=0,gain_reference,weight_reference;
    reg monitor=0,held_check=0;
    reg signed [63:0] master_before,expected,code;
    reg signed [63:0] low_energy=0,high_energy=0;
    real step_time,response_time,rms_ratio;
    always @(negedge lrck)begin
      sent_previous=sent_current;sent_current={a.final_sample,8'b0};
    end
    always @(posedge frame_valid)begin
      #1;
      if(monitor)begin
        if(left_word!==sent_previous || left_word!==right_word || left_word[7:0]!==0)
          $fatal(1,"I2S sample mismatch left=%h right=%h expected=%h",left_word,right_word,sent_previous);
        serial_frames=serial_frames+1;
      end
    end
    always @(posedge clk)begin
      if(held_check && a.v_retrig!==0)$fatal(1,"pressure retriggered held ADSR");
      if(a.sums_valid && !a.rst)begin
        weight_reference=a.u_xf.active_weight;
        master_before=$signed(a.sine_sum);
        master_before=master_before*(255-weight_reference);
        expected=$signed(a.bright_sum);
        master_before=(master_before+expected*weight_reference+127)>>>(8+a.MASTER_VOLUME_SHIFT);
        // The independent model uses signed integers on both operands. Mixing
        // unsigned Q12 into a signed product would make >>> a logical shift.
        gain_reference=a.u_xf.g_pressure.gain_next;
        expected=(master_before*gain_reference)>>>12;
        if(expected>32767)expected=32767;if(expected< -32768)expected=-32768;
      end
      if(a.u_xf.result_valid && !a.rst)begin
        #1;
        if(a.mixed_shared!==expected[15:0])
          $fatal(1,"top pressure sample mismatch: actual=%0d expected=%0d master=%0d gain=%0d",
                 a.mixed_shared,expected,master_before,gain_reference);
        if(a.u_engine.phase0!==b.u_engine.phase0 || a.v_env0!==b.v_env0 ||
           a.bend_inc0!==b.bend_inc0 || a.v_gate!==b.v_gate)
          $fatal(1,"pressure changed phase, bend, ADSR or voice allocation");
        frames=frames+1;
      end
    end
    initial begin
      repeat(10)@(negedge clk);kr=1;wait(!a.por);
      repeat(20)@(posedge a.sample_tick);
      if(a.u_xf.g_pressure.gain_q12!==4096)$fatal(1,"demo pressure bypass failed");
      @(negedge clk);keys[9]=0;
      repeat(2200)@(posedge a.sample_tick);#1;
      if(a.v_gate!==4'b0001 || a.u_xf.g_pressure.gain_q12!==1024)
        $fatal(1,"low pressure held-note setup failed");
      held_check=1;monitor=1;
      repeat(512)begin @(posedge frame_valid);#2;code=$signed(left_word[23:8]);low_energy=low_energy+code*code;end
      @(negedge clk);pressure=4095;step_time=$realtime;
      wait(a.u_xf.g_pressure.gain_q12>=3788);response_time=$realtime-step_time;
      repeat(300)@(posedge a.sample_tick);
      repeat(512)begin @(posedge frame_valid);#2;code=$signed(left_word[23:8]);high_energy=high_energy+code*code;end
      if(a.u_xf.g_pressure.gain_q12!==4096 || low_energy==0 || high_energy<low_energy*14 || high_energy>low_energy*18)
        $fatal(1,"pressure audio energy ratio outside 14..18: %0d/%0d",high_energy,low_energy);
      if(response_time>5_000_000.0)$fatal(1,"pressure t90 exceeded 5 ms: %f ns",response_time);
      rms_ratio=$sqrt(real'(high_energy)/real'(low_energy));
      $display("METRIC pressure_top decoded_frames=%0d checked_mix_frames=%0d rms_high_over_low=%.6f step_t90_us=%.3f",serial_frames,frames,rms_ratio,response_time/1000.0);
      held_check=0;keys[9]=1;repeat(1300)@(posedge a.sample_tick);#1;
      if(a.v_gate!==0 || a.v_env0!==0 || a.final_sample!==0)$fatal(1,"pressure note release did not finish");
      $display("PASS tb_pressure_top: GPIO/ADC/VCA/I2S, independent pitch/envelope, demo bypass and release");
      $finish;
    end
    initial begin #150_000_000;$fatal(1,"pressure top timeout");end
endmodule
