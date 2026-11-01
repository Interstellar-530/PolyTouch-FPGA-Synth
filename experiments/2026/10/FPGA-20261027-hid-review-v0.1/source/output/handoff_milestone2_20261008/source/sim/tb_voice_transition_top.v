`timescale 1ns/1ps
module tb_voice_transition_top;
    reg clk=0;always #40.690104 clk=~clk;
    reg kr=0,rx=1;wire cs,sck,mosi,miso;integer checks=0;
    top #(.AUDIO_IF(1),.PRESSURE_ENABLE(0)) dut(.clk_27m(1'b0),.clk_12m288(clk),.key_rst(kr),
        .key_s1(1'b1),.key_s2(1'b1),.uart_rx(rx),.gpio_key_n(12'hfff),
        .adc_cs_n(cs),.adc_sck(sck),.adc_mosi(mosi),.adc_miso(miso));
    mcp3208_model adc(cs,sck,mosi,miso,12'd3200,12'd2048,12'd0,12'd0,12'd0,12'd0,12'd0,12'd0);
    task byte_tx;input[7:0]data;integer bitno;
        begin @(negedge clk);rx=0;#8680;for(bitno=0;bitno<8;bitno=bitno+1)begin rx=data[bitno];#8680;end rx=1;#8680;end
    endtask
    task command;input[7:0]op,tens,ones;
        begin byte_tx(op);byte_tx(tens);byte_tx(ones);byte_tx(13);end
    endtask
    initial begin
        #100000;kr=1;wait(!dut.rst);command("D","0"," ");
        command("N","6","0");command("N","6","4");command("N","6","7");command("N","7","1");
        repeat(1800)@(posedge dut.sample_tick);@(negedge clk);
        if(dut.v_gate!=15)$fatal(1,"four-note setup");
        command("N","6","0");wait(dut.g_voice[0].u_env.fading);
        if(dut.render_note[6:0]!=60 || dut.v_env[0]==0)$fatal(1,"repeat cut old wave");
        wait(!dut.g_voice[0].u_env.fading);checks=checks+1;
        command("N","7","2");wait(dut.g_voice[1].u_env.fading);
        if(dut.v_note[13:7]!=72 || dut.render_note[13:7]!=64 || dut.v_env[1]==0)$fatal(1,"oldest voice not retained during steal");
        command("O","7","2");wait(!dut.g_voice[1].u_env.fading);@(negedge clk);
        if(dut.v_gate[1] || dut.v_env[1]!=0 || !dut.v_idle[1])$fatal(1,"cancelled pending note returned");checks=checks+1;
        command("N","7","3");repeat(3)@(posedge dut.sample_tick);@(negedge clk);
        if(dut.render_note[13:7]!=73 || !dut.v_gate[1])$fatal(1,"cancelled voice did not accept fresh note");checks=checks+1;
        command("M","0"," ");repeat(200)@(posedge dut.sample_tick);@(negedge clk);
        if(dut.final_sample!=0)$fatal(1,"mute did not finish");
        command("M","1"," ");repeat(160)@(posedge dut.sample_tick);@(negedge clk);
        if(dut.u_xf.g_pressure.gain_q12!=4096)$fatal(1,"restore gain");checks=checks+1;
        $display("PASS tb_voice_transition_top: UART four-note repeat, oldest steal, pending note-off cancellation, reuse and mute/restore; cases=%0d",checks);$finish;
    end
    initial begin #100000000;$fatal(1,"top transition timeout");end
endmodule
