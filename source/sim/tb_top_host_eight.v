`timescale 1ns/1ps
// Actual 27 MHz UART -> parser -> mapper -> allocator -> eight shared audio
// slots -> serial I2S, with no forced events, clocks, envelopes or wave samples.
module tb_top_host_eight;
    reg clk=0;
    always #18.5185 clk=~clk;
    reg key_rst=0,kbd_rx=1;
    wire cs,sck,mosi,miso,bck,lrck,din;
    top #(.AUDIO_IF(2),.VOICES(8),.MASTER_VOLUME_SHIFT(2),
          .GPIO_KEY_ENABLE(0),.HOST_KBD_ENABLE(1)) dut(
        .clk_27m(clk),.clk_12m288(1'b0),.key_rst(key_rst),
        .key_s1(1'b1),.key_s2(1'b1),.uart_rx(1'b1),
        .gpio_key_n(12'hFFF),.kbd_uart_rx(kbd_rx),
        .adc_cs_n(cs),.adc_sck(sck),.adc_mosi(mosi),.adc_miso(miso),
        .i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din));
    mcp3208_model adc(.cs_n(cs),.sclk(sck),.mosi(mosi),.miso(miso),
        .ch0(12'd0),.ch1(12'd2048),.ch2(12'd0),.ch3(12'd0),
        .ch4(12'd0),.ch5(12'd0),.ch6(12'd0),.ch7(12'd0));
    wire signed [23:0] left_word,right_word;
    wire frame;
    i2s_rx_model #(.DATA_BITS(24)) rx(.bck(bck),.rst(dut.rst),
        .lrck(lrck),.din(din),.left_word(left_word),.right_word(right_word),.frame_valid(frame));
    reg observe=0;
    reg [7:0] rendered=0;
    integer frames=0,audible=0,fd;
    always @(posedge clk) if(observe && dut.u_engine.state==dut.u_engine.ST_FIN_B &&
        dut.u_engine.scaled_s_ext!=0) rendered[dut.u_engine.vsel]=1'b1;
    always @(posedge frame) if(observe) begin
        if((^left_word)===1'bx || left_word!==right_word) $fatal(1,"invalid I2S samples");
        if(left_word!=0) audible=audible+1;
        frames=frames+1;
        $fdisplay(fd,"%0d,%0d",left_word,right_word);
    end
    task byte_out;
        input [7:0] b;
        integer i;
        begin
            @(negedge clk);kbd_rx=0;#8667;
            for(i=0;i<8;i=i+1) begin kbd_rx=b[i];#8667;end
            kbd_rx=1;#8667;
        end
    endtask
    task rpt;
        input [7:0] mods,k0,k1,k2,k3,k4,k5;
        begin
            byte_out(8'h57);byte_out(8'hAB);byte_out(1);byte_out(mods);byte_out(0);
            byte_out(k0);byte_out(k1);byte_out(k2);byte_out(k3);byte_out(k4);byte_out(k5);
            repeat(3000) @(posedge clk);
        end
    endtask
    task note_present;
        input [6:0] n;
        integer v;
        reg found;
        begin
            found=0;
            for(v=0;v<8;v=v+1) if(dut.v_gate[v] && dut.v_note[7*v+:7]==n) found=1;
            if(!found) $fatal(1,"note %0d missing",n);
        end
    endtask
    initial begin
        fd=$fopen("host_eight_i2s.csv","w");
        if(fd==0) $fatal(1,"cannot create capture");
        repeat(20) @(posedge clk);key_rst=1;wait(!dut.por);
        rpt(0,8'h40,0,0,0,0,0);rpt(0,0,0,0,0,0,0);
        if(dut.demo_mode) $fatal(1,"F7 did not enter manual");
        // Six normal notes plus LCtrl/RWin occupy eight distinct voices.
        rpt(8'h81,8'h14,8'h08,8'h17,8'h0C,8'h13,8'h30);
        if(dut.v_gate!==8'hFF || dut.hid_held_count!=8) $fatal(1,"eight voices not allocated");
        note_present(40);note_present(47);note_present(60);note_present(64);
        note_present(67);note_present(72);note_present(76);note_present(79);
        observe=1;
        wait(frames>=256);@(negedge clk);observe=0;
        if(rendered!==8'hFF || audible<240) $fatal(1,"silent voice/audio rendered=%h audible=%0d",rendered,audible);
        // Slot ordering changes do not retrigger or clear the eight notes.
        rpt(8'h81,8'h30,8'h13,8'h0C,8'h17,8'h08,8'h14);
        if(dut.v_gate!==8'hFF || dut.hid_overflow) $fatal(1,"held chord lost state");
        // Ninth independent source is handled by the existing voice stealing.
        rpt(8'h83,8'h30,8'h13,8'h0C,8'h17,8'h08,8'h14);
        if(dut.v_gate!==8'hFF) $fatal(1,"ninth key changed voice capacity");note_present(41);
        rpt(0,0,0,0,0,0,0);
        if(dut.v_gate!==0 || dut.hid_held_count!=0) $fatal(1,"release left stuck notes");
        $fclose(fd);
        $display("PASS tb_top_host_eight: real UART, eight distinct allocated/rendered voices, %0d decoded I2S frames, %0d nonzero, ninth-key stealing, full release",frames,audible);
        $finish;
    end
    initial begin #40000000;$fatal(1,"timeout");end
endmodule
