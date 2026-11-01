`timescale 1ns/1ps
module tb_adc_reset_top;
    parameter integer AUDIO_IF=1;
    localparam real HALF_CLK_NS=(AUDIO_IF==1)?40.690104:18.518519;
    reg clk=0;always #(HALF_CLK_NS)clk=~clk;
    reg key_rst=0;reg[11:0]pressure=1200,bend=2750;
    wire cs,sck,mosi,miso;
    integer pass=0,cycle_no=0,n;
    top #(.AUDIO_IF(AUDIO_IF)) dut(.clk_27m(clk),.clk_12m288(clk),.key_rst(key_rst),
        .key_s1(1'b1),.key_s2(1'b1),.uart_rx(1'b1),.gpio_key_n(12'hfff),
        .adc_cs_n(cs),.adc_sck(sck),.adc_mosi(mosi),.adc_miso(miso));
    mcp3208_model adc(cs,sck,mosi,miso,pressure,bend,12'd0,12'd0,12'd0,12'd0,12'd0,12'd0);
    task check_reset;
        begin
            if(dut.ctrl_div!==0 || dut.control_tick!==0 || dut.control_sample_tick!==0 || dut.adc_pair_active!==0 || dut.adc_start!==0 || dut.adc_sel!==0 ||
               dut.adc_gap_count!==0 || dut.pressure_raw!==0 || dut.bend_raw!==2048 || dut.adc_busy!==0 || cs!==1)
                $fatal(1,"ADC/control reset state is inconsistent");
        end
    endtask
    initial begin
        repeat(8)@(negedge clk);key_rst=1;wait(!dut.rst);
        wait(dut.pressure_raw==pressure && dut.bend_raw==bend);
        for(n=0;n<4;n=n+1)begin
            if(n<3)begin @(negedge cs);repeat(2+n*5)@(posedge sck);end
            else begin wait(cs);repeat(10)@(negedge clk);end
            key_rst=0;wait(dut.rst);repeat(3)@(negedge clk);check_reset();
            pressure=1500+n*400;bend=1000+n*300;
            repeat(100)begin @(negedge clk);check_reset();end
            key_rst=1;wait(!dut.rst);
            @(negedge cs);if(dut.adc_sel!==1)$fatal(1,"restart did not begin with CH1");
            // CH0 now starts immediately after CH1; do not skip its falling
            // CS edge by waiting four system clocks as the old poller did.
            @(posedge cs);@(negedge cs);
            if(dut.bend_raw!==bend || dut.pressure_raw!==0)$fatal(1,"stale data leaked after reset");
            if(dut.adc_sel!==0)$fatal(1,"CH0 did not follow CH1");
            @(posedge cs);repeat(4)@(negedge clk);
            if(dut.pressure_raw!==pressure)$fatal(1,"new pressure conversion missing");
            pass=pass+1;
        end
        $display("PASS tb_adc_reset_top: AUDIO_IF=%0d mid-transaction phases plus idle reset, clean raw codes and channel restart, cases=%0d",AUDIO_IF,pass);$finish;
    end
    initial begin #40000000;$fatal(1,"ADC reset timeout");end
endmodule
