`timescale 1ns/1ps
module tb_timbre_top;
    reg clk=0;always #40.690104 clk=~clk;
    reg key_rst=0,k1=1,rx=1;
    wire cs,sck,mosi,miso,bck,lrck,din;
    wire [23:0] left,right;wire frame_valid;
    integer frames=0,audible=0,checked=0;
    reg monitor=0;
    reg [31:0] e0,e1,e2,e3;
    time start_time,sweep_ns;
    top #(.AUDIO_IF(1),.PRESSURE_ENABLE(0)) dut(
        .clk_27m(1'b0),.clk_12m288(clk),.key_rst(key_rst),.key_s1(k1),.key_s2(1'b1),
        .uart_rx(rx),.gpio_key_n(12'hfff),.adc_cs_n(cs),.adc_sck(sck),.adc_mosi(mosi),.adc_miso(miso),
        .i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din));
    defparam dut.u_controls.DEBOUNCE_MS=1;
    defparam dut.u_controls.LONG_PRESS_MS=4;
    defparam dut.u_controls.SHOW_MS=5;
    mcp3208_model adc(cs,sck,mosi,miso,12'd3200,12'd2048,12'd0,12'd0,12'd0,12'd0,12'd0,12'd0);
    i2s_rx_model #(.DATA_BITS(24)) receiver(.bck(bck),.rst(dut.por),.lrck(lrck),.din(din),
        .left_word(left),.right_word(right),.frame_valid(frame_valid));
    always @(posedge frame_valid) begin
        frames=frames+1;
        if(left!==right)$fatal(1,"stereo mismatch");
        if(^left===1'bx)$fatal(1,"unknown decoded audio");
        if(left!=0)audible=audible+1;
    end
    always @(posedge clk) if(monitor) begin
        e0=dut.u_engine.phase0;e1=dut.u_engine.phase1;e2=dut.u_engine.phase2;e3=dut.u_engine.phase3;
        if(dut.sample_tick)begin
            e0=e0+dut.bend_inc0;e1=e1+dut.bend_inc1;e2=e2+dut.bend_inc2;e3=e3+dut.bend_inc3;
        end
        if(dut.v_retrig || dut.v_gate!==4'b1111 || dut.restart || dut.demo_mode)
            $fatal(1,"timbre disturbed held chord/mode");
        #1;
        if(dut.u_engine.phase0!==e0 || dut.u_engine.phase1!==e1 || dut.u_engine.phase2!==e2 || dut.u_engine.phase3!==e3)
            $fatal(1,"phase discontinuity");
        checked=checked+1;
    end
    task byte_tx;input [7:0] data;integer bitno;
        begin @(negedge clk);rx=0;#8680;
            for(bitno=0;bitno<8;bitno=bitno+1)begin rx=data[bitno];#8680;end
            rx=1;#8680;end
    endtask
    task note;input [7:0] tens,ones;
        begin byte_tx("N");byte_tx(tens);byte_tx(ones);byte_tx(13);#20000;end
    endtask
    initial begin
        #100000;key_rst=1;wait(!dut.rst);#1000000;
        byte_tx("D");byte_tx("0");byte_tx(13);#20000;
        note("6","0");note("6","4");note("6","7");note("7","1");#100000;
        if(dut.v_gate!=15)$fatal(1,"four voices not held");
        @(negedge clk);monitor=1;
        byte_tx("T");byte_tx("0");byte_tx(13);wait(dut.u_xf.weight_state==0);
        byte_tx("T");byte_tx("2");byte_tx("5");byte_tx("5");byte_tx(13);
        wait(dut.timbre_target==255);start_time=$time;
        wait(dut.u_xf.weight_state==255);sweep_ns=$time-start_time;
        if(sweep_ns>5334000 || sweep_ns<5270000)$fatal(1,"unexpected full sweep %t",sweep_ns);
        k1=0;#6500000;k1=1;#2000000;
        if(dut.timbre_target!=0 || dut.chord_set!=0 || dut.tempo_sel!=1)$fatal(1,"long press changed other controls");
        #6000000;if(dut.show_timbre)$fatal(1,"top LED overlay stuck");
        if(frames<500 || audible<200)$fatal(1,"insufficient real I2S audio");
        $display("METRIC top_timbre frames=%0d audible=%0d phase_checks=%0d full_sweep_ns=%0d",frames,audible,checked,sweep_ns);
        $display("PASS tb_timbre_top: real UART, four held voices, continuous phases, real I2S, long press and overlay");$finish;
    end
    initial begin #60000000;$fatal(1,"timeout");end
endmodule
