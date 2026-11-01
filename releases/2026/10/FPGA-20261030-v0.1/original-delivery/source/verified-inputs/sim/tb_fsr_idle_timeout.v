`timescale 1ns/1ps
// Real 32-voice top, ADC/audio/core/CDC/watchdog logic. Only decoded UART
// events and a stable pedal are injected; shorten watchdog wall time to 4 ms.
module tb_fsr_idle_timeout #(parameter integer POLICY=1);
    reg clk=0,key_rst=0;
    always #18.5185185 clk=~clk;
    reg inject_valid=0,inject_on=0;
    reg [6:0] inject_note=60;
    reg pedal=1;
    wire [63:0] status;
    instrument32_top #(.HOST_KBD_ENABLE(1),.GPIO_KEY_ENABLE(0),
        .HOST_KBD_TIMEOUT_POLICY(POLICY)) dut(
        .clk_27m(clk),.clk_12m288(1'b0),.key_rst(key_rst),.key_s1(1'b1),.key_s2(1'b1),
        .uart_rx(1'b1),.kbd_uart_rx(1'b1),.gpio_key_n(12'hfff),.adc_miso(1'b0),.ui_status(status));
    defparam dut.g_host_kbd.u_host_kbd.u_parser.WATCHDOG_MS=4;
    task event_note(input on);
        begin
            @(negedge clk);inject_on=on;inject_valid=1;
            @(negedge clk);inject_valid=0;
            repeat(500)@(negedge clk);
        end
    endtask
    initial begin
        force dut.por=1'b0;
        force dut.demo_mode=1'b0;
        force dut.sustain_pressed=pedal;
        force dut.uart_ev_valid=inject_valid;
        force dut.uart_ev_on=inject_on;
        force dut.uart_ev_note=inject_note;
        force dut.uart_ev_vel=8'd100;
        repeat(8)@(negedge clk);key_rst=1;
        wait(!dut.rst && dut.core_initialized);
        event_note(1);
        wait(dut.u_ram32.u_sched.gate[0]);
        event_note(0);
        if(!dut.u_sustain.deferred[60] || !dut.u_ram32.u_sched.gate[0])
            $fatal(1,"setup failed: note not sustained after key release");
        wait(dut.hid_link_timeout);
        #1;
        $display("TIMEOUT_TRACE policy=%0d held=%0d pedal=%b clear=%b deferred=%b gate=%b",POLICY,
            dut.hid_held_count,dut.sustain_pressed,dut.clear_events,
            dut.u_sustain.deferred[60],dut.u_ram32.u_sched.gate[0]);
        if(POLICY!=0 && dut.clear_events)
            $fatal(1,"IDLE_TIMEOUT_CLEARS_SUSTAIN_WITH_PEDAL_DOWN");
        if(POLICY==0 && !dut.clear_events)$fatal(1,"strict timeout protection lost");
        repeat(2000)@(negedge clk);
        if(POLICY!=0)begin
            if(!status[41] || !dut.u_sustain.deferred[60] || !dut.u_ram32.u_sched.gate[0])
                $fatal(1,"pedal indicator or sustained note lost after idle timeout");
            pedal=0;
            repeat(2000)@(negedge clk);
            if(dut.u_sustain.deferred[60] || dut.u_ram32.u_sched.gate[0])
                $fatal(1,"real pedal release no longer releases note");
            // Real detach is still an emergency, even with the pedal held.
            pedal=1;event_note(1);event_note(0);
            if(!dut.u_sustain.deferred[60])$fatal(1,"detach setup not sustained");
            @(negedge clk);force dut.g_host_kbd.u_host_kbd.u_parser.device_notify=1'b1;
            #1;if(!dut.clear_events)$fatal(1,"detach clear protection lost");
            @(negedge clk);release dut.g_host_kbd.u_host_kbd.u_parser.device_notify;
            repeat(2000)@(negedge clk);
            if(dut.u_sustain.deferred[60] || dut.u_ram32.u_sched.gate[0])
                $fatal(1,"detach did not clear the sustained note");
            @(negedge clk);force dut.hid_panic=1'b1;
            #1;if(!dut.clear_events)$fatal(1,"keyboard panic protection lost");
            @(negedge clk);release dut.hid_panic;
        end else if(dut.u_sustain.deferred[60] || dut.u_ram32.u_sched.gate[0])
            $fatal(1,"strict timeout no longer clears audio");
        $display("PASS FSR_IDLE_TIMEOUT policy=%0d: actual watchdog, real top/CDC/32 voices, stable pedal and deliberate release",POLICY);
        $finish;
    end
    initial begin #12000000;$fatal(1,"FSR idle timeout bench deadline");end
endmodule
