`timescale 1ns/1ps
module tb_pressure_duplicate;
    reg clk=0; always #40.690104 clk=~clk;
    reg key_rst=0;
    reg [11:0] pressure=0,bend=2048;
    wire cs,sck,mosi,miso;
    integer peak=0,spike_conversions=0,bend_conversions=0,bend_changes=0;
    integer ratio_low=100000,ratio_high=0,last_ratio=65536;
    reg observe=0,noise=0,noise_bit=0;
    top #(.AUDIO_IF(1)) dut(.clk_27m(clk),.clk_12m288(clk),.key_rst(key_rst),
        .key_s1(1'b1),.key_s2(1'b1),.uart_rx(1'b1),.gpio_key_n(12'hfff),
        .adc_cs_n(cs),.adc_sck(sck),.adc_mosi(mosi),.adc_miso(miso));
    mcp3208_model adc(cs,sck,mosi,miso,pressure,bend,12'd0,12'd0,12'd0,12'd0,12'd0,12'd0);
    always @(negedge cs) if(noise && dut.adc_sel) begin
        noise_bit=~noise_bit;
        bend=noise_bit?2047:2049;
        bend_conversions=bend_conversions+1;
    end
    always @(posedge clk) if(!dut.rst)begin
        if(dut.adc_done && !dut.adc_sel && dut.adc_data==4095)
            spike_conversions=spike_conversions+1;
        if(dut.control_tick && observe)begin
            #1;
            if(dut.pressure_filtered>peak)peak=dut.pressure_filtered;
            $display("tick time_ns=%0t pressure_raw=%0d filtered=%0d bend_raw=%0d ratio_q16=%0d",$time,dut.pressure_raw,dut.pressure_filtered,dut.bend_raw,dut.bend_ratio_q16);
            if(noise && dut.bend_raw!=2048)begin
                if(dut.bend_ratio_q16<ratio_low)ratio_low=dut.bend_ratio_q16;
                if(dut.bend_ratio_q16>ratio_high)ratio_high=dut.bend_ratio_q16;
                if(dut.bend_ratio_q16!=last_ratio)bend_changes=bend_changes+1;
                last_ratio=dut.bend_ratio_q16;
            end
        end
    end
    initial begin
        repeat(8)@(negedge clk);key_rst=1;wait(!dut.rst);
        repeat(6)@(posedge cs);
        observe=1;
        // One physical CH0 conversion at full scale, then restore zero before
        // the following conversion. The real top scheduler supplies the hold.
        @(negedge cs);while(dut.adc_sel)@(negedge cs);
        pressure=4095;
        @(posedge cs);pressure=0;
        #4500000;
        if(spike_conversions!=1)$fatal(1,"test setup did not generate exactly one bad ADC conversion");
        if(peak!=3071)$fatal(1,"unexpected duplicate-sampling peak=%0d",peak);
        $display("CONFIRMED pressure_duplicate: physical_spikes=%0d filter_peak=%0d of4095",spike_conversions,peak);
        noise=1;
        #8500000;
        if(ratio_low!=65532 || ratio_high!=65540 || bend_changes<6)$fatal(1,"unexpected bend noise response low=%0d high=%0d changes=%0d",ratio_low,ratio_high,bend_changes);
        $display("CONFIRMED bend_raw_noise: adc_codes=2047/2049 ratio_q16_min=%0d max=%0d change_count=%0d physical_conversions=%0d interval_us=1000",ratio_low,ratio_high,bend_changes,bend_conversions);
        $display("PASS audit probe: reproduced issues without changing production RTL");$finish;
    end
    initial begin #30000000;$fatal(1,"probe timeout");end
endmodule
