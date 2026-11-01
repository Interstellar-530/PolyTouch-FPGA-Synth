`timescale 1ns/1ps
// Real standard27 parameters, UART and ADC pins, independent I2S decoding.
module tb_pressure_top;
 reg clk=0,kr=0,uart_rx=1; always #18.5185 clk=~clk;
 reg [11:0] pressure=0,bend=2048;
 wire cs,sck,mosi,miso,bck,lrck,din,xsmt;
 // Only shorten the song unit; audio clocks, ADC and UART retain production timing.
 top #(.AUDIO_IF(2),.VOICES(8),.MASTER_VOLUME_SHIFT(3),.SONG_UNIT_SAMPLES(1024),.GPIO_KEY_ENABLE(0),.HOST_KBD_ENABLE(1)) dut(
  .clk_27m(clk),.clk_12m288(1'b0),.key_rst(kr),.key_s1(1'b1),.key_s2(1'b1),.uart_rx(uart_rx),.gpio_key_n(12'hfff),
  .kbd_uart_rx(1'b1),.kbd_uart_tx(),.adc_cs_n(cs),.adc_sck(sck),.adc_mosi(mosi),.adc_miso(miso),
  .i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),.dac_xsmt(xsmt));
 mcp3208_model adc(.cs_n(cs),.sclk(sck),.mosi(mosi),.miso(miso),.ch0(pressure),.ch1(bend),
  .ch2(12'd0),.ch3(12'd0),.ch4(12'd0),.ch5(12'd0),.ch6(12'd0),.ch7(12'd0));
 wire signed [23:0] left_word,right_word; wire valid;
 i2s_rx_model #(.DATA_BITS(24)) rx(.bck(bck),.rst(dut.por),.lrck(lrck),.din(din),
  .left_word(left_word),.right_word(right_word),.frame_valid(valid),.slot_l(),.slot_r(),.align_discards());
 integer cycles=0,last_bck=-1,last_frame=-1,frames=0;reg held_check=0;
 always @(posedge clk)begin
  cycles=cycles+1;
  if(held_check && dut.v_retrig!==0)$fatal(1,"FSR retriggered held note");
 end
 always @(posedge bck)begin
  #1;if(!dut.por)begin
   if(last_bck>=0 && cycles-last_bck!=9)$fatal(1,"FSR changed BCK period");last_bck=cycles;
  end
 end
 always @(posedge valid)begin
  #1;if(last_frame>=0 && cycles-last_frame!=576)$fatal(1,"FSR changed LRCK period");
  last_frame=cycles;frames=frames+1;
  if(^left_word===1'bx || left_word!==right_word || xsmt!==1'b1)$fatal(1,"Invalid I2S or DAC hardware mute");
 end
 task byte_tx(input [7:0] value);
  integer bitno;begin
   @(negedge clk);uart_rx=0;#8681;
   for(bitno=0;bitno<8;bitno=bitno+1)begin uart_rx=value[bitno];#8681;end
   uart_rx=1;#8681;
  end
 endtask
 task command(input [7:0] a,b,c);
  begin byte_tx(a);byte_tx(b);byte_tx(c);byte_tx(13);end
 endtask
 task wait_frames(input integer count);
  begin repeat(count)begin @(posedge valid);#2;end end
 endtask
 task audio_check(input integer silent);
  integer i,nonzero,peak,value;begin
   nonzero=0;peak=0;
   for(i=0;i<64;i=i+1)begin
    @(posedge valid);#2;value=$signed(left_word);
    if(value!=0)nonzero=nonzero+1;if(value<0)value=-value;if(value>peak)peak=value;
   end
   if(silent && nonzero!=0)$fatal(1,"Expected exact silence: peak=%0d",peak);
   if(!silent && (nonzero<60 || peak<10000))$fatal(1,"Audio did not resume: peak=%0d nonzero=%0d",peak,nonzero);
  end
 endtask
 initial begin
  repeat(8)@(negedge clk);kr=1;wait(!dut.rst);wait(dut.v_gate!=0);wait_frames(128);audio_check(0);
  pressure=4095;wait(dut.fsr_muted);wait_frames(160);audio_check(1);
  if(!dut.demo_mode || dut.v_gate==0)$fatal(1,"FSR stopped demo instead of muting output");
  pressure=300;wait_frames(200);if(!dut.fsr_muted)$fatal(1,"FSR hysteresis released too early");audio_check(1);
  pressure=0;wait(!dut.fsr_muted);wait_frames(160);audio_check(0);
  command("X"," "," ");command("I","0"," ");command("T","0"," ");command("N","6","9");
  wait_frames(600);audio_check(0);if(dut.demo_mode || dut.v_gate==0)$fatal(1,"UART manual note missing");held_check=1;
  pressure=4095;wait(dut.fsr_muted);wait_frames(160);audio_check(1);
  command("M","0"," ");pressure=0;wait(!dut.fsr_muted);wait_frames(160);audio_check(1);
  if(!dut.uart_muted)$fatal(1,"FSR release cleared UART mute");
  command("M","1"," ");wait_frames(160);audio_check(0);
  bend=4095;wait_frames(160);audio_check(0);if(dut.bend_ratio_q16<70000 || dut.v_gate==0)$fatal(1,"Bend or held note lost");
  pressure=4095;wait(dut.fsr_muted);command("M","1"," ");wait_frames(160);audio_check(1);
  pressure=0;wait(!dut.fsr_muted);wait_frames(160);audio_check(0);held_check=0;
  $display("PASS tb_pressure_top: %0d I2S frames; demo/manual mute, hysteresis, UART priority, clocks and bend",frames);$finish;
 end
 initial begin #120000000;$fatal(1,"FSR production integration timeout");end
endmodule
