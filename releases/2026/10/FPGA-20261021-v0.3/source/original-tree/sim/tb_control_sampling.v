`timescale 1ns/1ps
module tb_control_sampling;
    parameter integer AUDIO_IF=1;
    localparam real HALF_CLK_NS=AUDIO_IF?40.690104:18.518519;
    reg clk=0;always #(HALF_CLK_NS)clk=~clk;
    reg kr=0;reg[11:0]keys=12'hfff;reg[11:0]pressure=0,bend=2048;
    wire cs,sck,mosi,miso;
    top #(.AUDIO_IF(AUDIO_IF),.PRESSURE_ENABLE(1)) dut(.clk_27m(clk),.clk_12m288(clk),.key_rst(kr),
        .key_s1(1'b1),.key_s2(1'b1),.uart_rx(1'b1),.gpio_key_n(keys),
        .adc_cs_n(cs),.adc_sck(sck),.adc_mosi(mosi),.adc_miso(miso));
    mcp3208_model adc(cs,sck,mosi,miso,pressure,bend,12'd0,12'd0,12'd0,12'd0,12'd0,12'd0);
    integer d0=0,d1=0,filtered=0,med,samples=0,conversions=0,spikes=0,expected_channel=1;
    integer peak=0,k;reg last_tick=0,observe=0;
    real previous_tick=0,last_cs_rise=0,delta,started,elapsed,worst=0,best=1e12;
    always @(posedge cs)last_cs_rise=$realtime;
    always @(negedge cs) if(!dut.rst)begin
        if(conversions>0 && $realtime-last_cs_rise<500)$fatal(1,"MCP3208 CS high interval too short");
        if(dut.adc_sel!==expected_channel[0])$fatal(1,"ADC pair channel order");
        expected_channel=1-expected_channel;conversions=conversions+1;
    end
    always @(posedge clk)begin
        if(dut.rst)begin d0=0;d1=0;filtered=0;last_tick=0;previous_tick=0;expected_channel=1;end
        else begin
            if(dut.adc_done && !dut.adc_sel && dut.adc_data==4095 && observe)spikes=spikes+1;
            if(last_tick && dut.control_sample_tick)$fatal(1,"sample valid wider than one clock");
            last_tick=dut.control_sample_tick;
            if(dut.control_sample_tick)begin
                if(previous_tick!=0)begin delta=$realtime-previous_tick;if(delta<499900 || delta>500100)$fatal(1,"fresh pair rate %f ns",delta);end
                previous_tick=$realtime;
                if((d0<=d1 && d1<=dut.pressure_raw)||(dut.pressure_raw<=d1 && d1<=d0))med=d1;
                else if((d1<=d0 && d0<=dut.pressure_raw)||(dut.pressure_raw<=d0 && d0<=d1))med=d0;
                else med=dut.pressure_raw;
                filtered=filtered+((med-filtered)>>>1);d1=d0;d0=dut.pressure_raw;
                samples=samples+1;
                #1;
                if(dut.pressure_filtered!==filtered || dut.u_bend.bend_sample!==dut.bend_raw)$fatal(1,"fresh sample reference");
                if(observe && dut.pressure_filtered>peak)peak=dut.pressure_filtered;
            end
        end
    end
    initial begin
        repeat(8)@(negedge clk);kr=1;wait(!dut.rst);keys[0]=0;
        repeat(12)@(posedge dut.control_sample_tick);@(negedge clk);
        if(dut.demo_mode || dut.u_xf.g_pressure.gain_q12!=1024)$fatal(1,"manual pressure setup");
        observe=1;
        @(negedge cs);while(dut.adc_sel)@(negedge cs);
        pressure=4095;@(posedge cs);pressure=0;
        repeat(8)@(posedge dut.control_sample_tick);@(negedge clk);observe=0;
        if(spikes!=1 || peak!=0)$fatal(1,"single conversion spike not rejected: count=%0d peak=%0d",spikes,peak);
        for(k=0;k<8;k=k+1)begin
            pressure=0;repeat(20)@(posedge dut.control_sample_tick);@(negedge clk);
            if(dut.u_xf.g_pressure.gain_q12!=1024)$fatal(1,"step did not settle low");
            @(posedge dut.control_tick);#(k*62500);pressure=4095;started=$realtime;
            wait(dut.u_xf.g_pressure.gain_q12>=3788);elapsed=$realtime-started;
            if(elapsed>3500000)$fatal(1,"phase-sweep pressure response %f ns",elapsed);
            if(elapsed>worst)worst=elapsed;if(elapsed<best)best=elapsed;
        end
        $display("METRIC control_sampling profile=%0d fresh_hz_per_channel=2000 checked_pairs=%0d conversions=%0d single_spike_peak=%0d step_phases=8 best_t90_us=%.3f worst_t90_us=%.3f",AUDIO_IF,samples,conversions,peak,best/1000,worst/1000);
        $display("PASS tb_control_sampling: pin-level ADC, pair order/rate, no stale filter updates, one-conversion spike rejection and VCA response phase sweep");$finish;
    end
    initial begin #200000000;$fatal(1,"control sampling timeout");end
endmodule
