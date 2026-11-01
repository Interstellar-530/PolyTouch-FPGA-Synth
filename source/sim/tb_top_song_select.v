`timescale 1ns/1ps
module tb_top_song_select;
    reg clk=0, key_rst=0, s1=1;
    always #18.5185 clk=~clk;
    top #(.AUDIO_IF(2),.VOICES(8),.GPIO_KEY_ENABLE(0),.HOST_KBD_ENABLE(0),
          .SONG_UNIT_SAMPLES(64)) dut (
        .clk_27m(clk),.clk_12m288(1'b0),.key_rst(key_rst),.key_s1(s1),.key_s2(1'b1),
        .uart_rx(1'b1),.gpio_key_n(12'hfff),.kbd_uart_rx(1'b1),.adc_miso(1'b0));
    integer changes=0;
    always @(posedge clk) if(!dut.rst && dut.song_change) changes=changes+1;
    task press;
        begin
            @(negedge clk); s1=0; repeat(35) @(negedge clk);
            s1=1; repeat(35) @(negedge clk);
        end
    endtask
    initial begin
        repeat(20) @(negedge clk); key_rst=1;
        wait(!dut.por); repeat(10) @(negedge clk);
        // Accelerate only the control's millisecond timebase; exercise its real synchronizer/debounce.
        force dut.u_controls.ms_tick=1'b1;
        if(dut.song_select!==0) $fatal(1,"power-on song not Wanye");
        press();
        if(dut.song_select!==1 || changes!=1 || !dut.demo_mode || dut.demo_paused)
            $fatal(1,"S1 did not select second song once");
        if(!dut.fifo_empty || dut.ev_q_valid) $fatal(1,"stale events survived switch");
        wait(dut.u_song.mel_idx==0); #1;
        if(dut.u_song.mel_cur_note!=77) $fatal(1,"top did not play second table");
        force dut.hid_pause_toggle=1'b1; @(negedge clk); release dut.hid_pause_toggle;
        press();
        if(dut.song_select!==0 || changes!=2 || dut.demo_paused) $fatal(1,"switch did not restart paused demo");
        force dut.uart_demo_off=1'b1; @(negedge clk); release dut.uart_demo_off;
        repeat(5) @(negedge clk);
        if(dut.demo_mode) $fatal(1,"manual fixture failed");
        press();
        if(!dut.demo_mode || dut.song_select!==1 || changes!=3) $fatal(1,"S1 did not enter selected demo from manual");
        // A long press changes timbre without changing song on release.
        @(negedge clk); s1=0; repeat(650) @(negedge clk);
        s1=1; repeat(35) @(negedge clk);
        if(changes!=3 || dut.song_select!==1) $fatal(1,"long press switched song");
        $display("PASS tb_top_song_select: physical S1 debounce, clear, pause/manual recovery, long press preserved");
        $finish;
    end
    initial begin #10000000; $fatal(1,"top song selection timeout"); end
endmodule
