`timescale 1ns/1ps
module tb_production32;
    reg clk=0,key_rst=0,uart_rx=1,s1=1;
    always #18.5185185 clk=~clk;
    reg [11:0] pressure=0,bend=2048;
    wire cs,sck,mosi,miso,bck,lrck,din;
    wire [63:0] status;
    wire [31:0] mask;
    instrument32_top #(.AUDIO_IF(2),.VOICES(32),.HOST_KBD_ENABLE(1),.GPIO_KEY_ENABLE(0),.SONG_UNIT_SAMPLES(64)) dut(
        .clk_27m(clk),.clk_12m288(1'b0),.key_rst(key_rst),.key_s1(s1),.key_s2(1'b1),
        .uart_rx(uart_rx),.kbd_uart_rx(1'b1),.gpio_key_n(12'hfff),
        .adc_cs_n(cs),.adc_sck(sck),.adc_mosi(mosi),.adc_miso(miso),
        .i2s_bck(bck),.i2s_lrck(lrck),.i2s_din(din),.ui_status(status),.ui_voice_mask(mask));
    mcp3208_model adc(.cs_n(cs),.sclk(sck),.mosi(mosi),.miso(miso),
        .ch0(pressure),.ch1(bend),.ch2(12'd0),.ch3(12'd0),.ch4(12'd0),.ch5(12'd0),.ch6(12'd0),.ch7(12'd0));
    wire signed [23:0] dl,dr;
    wire decoded;
    i2s_rx_model #(.DATA_BITS(24)) rx(.bck(bck),.lrck(lrck),.din(din),.rst(dut.por),
        .left_word(dl),.right_word(dr),.frame_valid(decoded));
    integer frames=0,audible=0,cycles=0,last_tick=0,contributed=0;
    reg [31:0] seen=0;
    always @(posedge clk)begin
        cycles=cycles+1;
        if(dut.sample_tick)begin
            if(last_tick && cycles-last_tick!=576)$fatal(1,"I2S frame period changed");
            last_tick=cycles;
        end
    end
    always @(posedge decoded)begin
        #1;if(dl!==dr || ^dl===1'bx)$fatal(1,"I2S stereo/unknown data");
        frames=frames+1;if(dl!=0)audible=audible+1;
    end
    // ACC=19: each configured lane contributes its own oscillator result.
    always @(posedge dut.u_ram32.clk_compute)begin
        if(!dut.u_ram32.reset_c && dut.u_ram32.u_core.lane[0].u_core.state==19 &&
            dut.u_ram32.u_core.lane[0].u_core.envelope!=0)
            seen[dut.u_ram32.u_core.lane[0].u_core.voice]=1;
    end
    task byte_out;
        input [7:0] b;integer k;
        begin
            @(negedge clk);uart_rx=0;repeat(234)@(negedge clk);
            for(k=0;k<8;k=k+1)begin uart_rx=b[k];repeat(234)@(negedge clk);end
            uart_rx=1;repeat(234)@(negedge clk);
        end
    endtask
    task note_command;
        input [7:0] op;input integer note;
        begin byte_out(op);byte_out(48+note/10);byte_out(48+note%10);byte_out(13);end
    endtask
    integer i,saved_audible;
    initial begin
        repeat(20)@(negedge clk);key_rst=1;wait(!dut.por);
        byte_out("D");byte_out("0");byte_out(13);
        for(i=0;i<32;i=i+1) note_command("N",48+i);
        repeat(60000)@(negedge clk);
        if(dut.u_ram32.active_count!=32 || mask!=32'hffffffff || {status[61:60],status[15:12]}!=32)
            $fatal(1,"32 production voices not active core=%0d mask=%h status=%h",dut.u_ram32.active_count,mask,status);
        if(seen!=32'hffffffff || audible<10)$fatal(1,"32 voices not all rendered to audible I2S");
        for(i=0;i<32;i=i+1)if(dut.u_ram32.u_sched.note[i]!=48+i || dut.u_ram32.u_sched.env[i]==0)
            $fatal(1,"32 voice state alias at %0d",i);
        // Independent rotation changes pitch while pressure and held notes stay fixed.
        bend=3072;repeat(90000)@(negedge clk);
        if(dut.u_ram32.u_sched.ratio_q<=65536 || dut.sustain_pressed || dut.u_ram32.active_count!=32)
            $fatal(1,"bend dimension coupled to pressure/note state");
        // Hold pedal, release a key, then release pedal: FSR must never mute audio.
        pressure=3000;repeat(150000)@(negedge clk);saved_audible=audible;
        note_command("O",48);repeat(10000)@(negedge clk);
        if(!dut.sustain_pressed || !dut.u_ram32.u_sched.gate[0] || dut.audio_muted || audible<=saved_audible)
            $fatal(1,"FSR sustain failed or muted audio");
        // A 2 ms raw dropout must not release the pedal or deferred Note Off.
        // Longer outages may be a release under the <=5 ms response contract.
        pressure=0;repeat(54000)@(negedge clk);
        if(!dut.sustain_pressed || !dut.u_ram32.u_sched.gate[0])
            $fatal(1,"brief FSR dropout released a sustained note");
        pressure=3000;repeat(135000)@(negedge clk);
        if(!dut.sustain_pressed || !dut.u_ram32.u_sched.gate[0])
            $fatal(1,"FSR recovery lost sustain");
        pressure=0;
        fork : pedal_release_deadline
            begin wait(!dut.sustain_pressed);end
            begin #5000000;$fatal(1,"real ADC pedal state release exceeded 5 ms");end
        join_any
        disable pedal_release_deadline;
        repeat(20000)@(negedge clk);
        if(dut.sustain_pressed || dut.u_ram32.u_sched.gate[0] || dut.u_ram32.u_sched.note[1]!=49)
            $fatal(1,"pedal release did not release exactly the deferred note");
        // S1 still selects either local song and flushes sustain/manual state.
        force dut.u_controls.ms_tick=1'b1;
        s1=0;repeat(35)@(negedge clk);s1=1;repeat(35)@(negedge clk);
        if(!dut.song_select || !dut.demo_mode || dut.u_sustain.deferred!=0)$fatal(1,"song switch/pedal clear failed");
        repeat(40000)@(negedge clk);
        begin : check_lead integer j; reg found; found=0; for(j=0;j<32;j=j+1) if(dut.u_ram32.u_sched.gate[j] && dut.u_ram32.u_sched.note[j]==77 && dut.u_ram32.u_sched.vel[j]==112) found=1; if(!found)$fatal(1,"second song lead not integrated");end
        $display("PASS tb_production32: UART32, per-voice state/render, real I2S, frame deadlines, independent bend/FSR sustain, song switch");$finish;
    end
    initial begin #100000000;$fatal(1,"production32 timeout");end
endmodule

