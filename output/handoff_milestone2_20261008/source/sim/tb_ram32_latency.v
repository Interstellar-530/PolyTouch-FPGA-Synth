`timescale 1ns/1ps
// Compare 8/32 voices at the same validated 73.728 MHz / 48 kHz setting.
// Default production ADSR parameters are retained. A shadow engine receives
// identical background notes, but omits the final full-load note: the first
// pin-level sample difference then measures response in ongoing sound.
module ram_latency_probe #(parameter integer VOICES=32)(output reg done=0);
    reg clk=0; always #40.690104 clk=~clk;
    reg reset=1,ev_valid=0,ev_on=1,omit_shadow=0,use_uart=0,kbd_rx=1;
    reg [6:0] note=60;
    wire [1:0] ready_v,bck,lrck,din,decoded,initialized,sample_valid;
    wire [5:0] active[0:1];
    wire signed [23:0] dl[0:1],dr[0:1];
    wire hid_valid;
    wire [15:0] hid_word;
    wire ready=&ready_v;
    wire source_valid=use_uart?hid_valid:ev_valid;
    wire source_on=use_uart?hid_word[15]:ev_on;
    wire [6:0] source_note=use_uart?hid_word[14:8]:note;
    wire [7:0] source_vel=use_uart?hid_word[7:0]:8'd100;
    host_kbd_input #(.CLK_HZ(12288000),.BAUD(115200)) host(
        .clk(clk),.rst(reset),.kbd_rx(kbd_rx),.flush(1'b0),
        .ev_valid(hid_valid),.ev_word(hid_word),.ev_ready(use_uart && ready));
    genvar g;
    generate for(g=0;g<2;g=g+1) begin: pair
        ram32_clocked_top #(.MULT(6),.VOICES(VOICES)) dut(
            .clk_ref(clk),.reset(reset),.instrument(1'b0),.piano_tone(3'd4),
            .volume_target(7'd100),.mute(1'b0),.pressure_enable(1'b0),
            .pressure_adc(12'd3200),.bend_adc(12'd2048),
            .ev_valid(source_valid && (g==0 || !omit_shadow)),
            .ev_on(source_on),.ev_note(source_note),.ev_vel(source_vel),.ev_ready(ready_v[g]),
            .i2s_bck(bck[g]),.i2s_lrck(lrck[g]),.i2s_din(din[g]),
            .sample_valid(sample_valid[g]),.active_count(active[g]),.initialized(initialized[g]));
        i2s_rx_model #(.DATA_BITS(24)) rx(.bck(bck[g]),.rst(reset),
            .lrck(lrck[g]),.din(din[g]),.left_word(dl[g]),.right_word(dr[g]),.frame_valid(decoded[g]));
    end endgenerate

    reg single_watch=0,rise_watch=0,burst_watch=0,full_watch=0;
    realtime requested_at=0,first_pin=0,rise10=0,rise90=0,first_difference=0;
    realtime burst_start=0,burst_allocated=0,burst_rendered=0,accepted_at=0;
    realtime queue_min=1.0e9,queue_max=0,single_min=1.0e9,single_max=0,uart_latency=0;
    realtime burst_us=0,render_us=0,full_us=0,rise10_us=0,rise90_us=0;
    reg [VOICES-1:0] rendered=0;
    integer frame_cycle=0,max_tail=0,frames=0,accepted=0;
    always @(posedge clk) if(!reset && source_valid && ready) begin
        accepted_at=$realtime;accepted=accepted+1;
    end
    always @(posedge pair[0].dut.clk_compute) begin
        if(pair[0].dut.reset_compute) frame_cycle=0;
        else begin
            if(pair[0].dut.tick_compute) frame_cycle=0;else frame_cycle=frame_cycle+1;
            if(sample_valid[0] && frame_cycle>max_tail)max_tail=frame_cycle;
            if(sample_valid[0] && frame_cycle>=1536)$fatal(1,"voice%0d missed frame",VOICES);
            if(pair[0].dut.ev_valid_c && pair[0].dut.ev_ready_c) begin
                if($realtime-accepted_at<queue_min)queue_min=$realtime-accepted_at;
                if($realtime-accepted_at>queue_max)queue_max=$realtime-accepted_at;
            end
            if(rise_watch)begin
                if(rise10==0 && pair[0].dut.u_sched.env[0]>=6554)rise10=$realtime;
                if(rise90==0 && pair[0].dut.u_sched.env[0]>=58982)rise90=$realtime;
            end
            if(burst_watch && pair[0].dut.u_core.lane[0].u_core.state==pair[0].dut.u_core.lane[0].u_core.ACC &&
               (pair[0].dut.u_core.lane[0].u_core.sine_mix!=pair[0].dut.u_core.lane[0].u_core.sine_acc ||
                pair[0].dut.u_core.lane[0].u_core.bright_mix!=pair[0].dut.u_core.lane[0].u_core.bright_acc))begin
                rendered[pair[0].dut.u_core.lane[0].u_core.voice]=1;
                if((&rendered) && burst_rendered==0)burst_rendered=$realtime;
            end
        end
    end
    always @(posedge decoded[0])begin
        #1;
        frames=frames+1;
        if((^dl[0])===1'bx || dl[0]!==dr[0])$fatal(1,"invalid I2S voice%0d",VOICES);
        if(single_watch && first_pin==0 && dl[0]!=0)first_pin=$realtime;
        if(!omit_shadow && dl[0]!==dl[1])$fatal(1,"shadow baseline differs voice%0d",VOICES);
        if(full_watch && first_difference==0 && dl[0]!==dl[1])first_difference=$realtime;
    end
    task wait_frames;input integer n;integer j;begin
        for(j=0;j<n;j=j+1)@(posedge decoded[0]);@(negedge clk);
    end endtask
    task restart;begin
        @(negedge clk);reset=1;ev_valid=0;omit_shadow=0;use_uart=0;kbd_rx=1;
        single_watch=0;rise_watch=0;burst_watch=0;full_watch=0;
        repeat(20)@(negedge clk);reset=0;wait(&initialized);wait_frames(8);
    end endtask
    task send_event;input [6:0] n;begin
        @(negedge clk);while(!ready)@(negedge clk);
        note=n;ev_on=1;ev_valid=1;
        @(negedge clk);ev_valid=0;
    end endtask
    task uart_byte;input [7:0] b;integer j;begin
        kbd_rx=0;#8680.556;
        for(j=0;j<8;j=j+1)begin kbd_rx=b[j];#8680.556;end
        kbd_rx=1;#8680.556;
    end endtask
    integer trial,i;
    real one_us;
    initial begin
        for(trial=0;trial<4;trial=trial+1)begin
            restart();repeat(trial*64)@(negedge clk);
            requested_at=$realtime;first_pin=0;single_watch=1;
            if(trial==0)begin rise_watch=1;rise10=0;rise90=0;end
            send_event(60);wait(first_pin>0);@(negedge clk);
            one_us=(first_pin-requested_at)/1000.0;
            if(one_us<single_min)single_min=one_us;
            if(one_us>single_max)single_max=one_us;
            if(one_us>250)$fatal(1,"single response too slow voice%0d %.3fus",VOICES,one_us);
            if(trial==0)begin
                wait(rise90>0);rise_watch=0;
                rise10_us=(rise10-requested_at)/1000.0;rise90_us=(rise90-requested_at)/1000.0;
            end
        end
        restart();burst_start=$realtime;rendered=0;burst_rendered=0;burst_watch=1;
        for(i=0;i<VOICES;i=i+1)send_event(36+i);
        wait(active[0]==VOICES);burst_allocated=$realtime;
        wait(burst_rendered>0);burst_watch=0;
        burst_us=(burst_allocated-burst_start)/1000.0;render_us=(burst_rendered-burst_start)/1000.0;
        if(burst_us>1000 || render_us>1000)$fatal(1,"burst late voice%0d",VOICES);
        wait_frames(8);
        if(dl[0]!==dl[1])$fatal(1,"background not identical");
        requested_at=$realtime;omit_shadow=1;full_watch=1;first_difference=0;
        send_event(84);wait(first_difference>0);@(negedge clk);full_watch=0;
        full_us=(first_difference-requested_at)/1000.0;
        if(full_us>250 || active[0]!=VOICES)$fatal(1,"full-load response %.3fus voice%0d",full_us,VOICES);

        restart();use_uart=1;first_pin=0;single_watch=1;
        @(negedge clk);requested_at=$realtime;
        uart_byte(8'h57);uart_byte(8'hAB);uart_byte(1);uart_byte(0);uart_byte(0);
        uart_byte(8'h14);uart_byte(0);uart_byte(0);uart_byte(0);uart_byte(0);uart_byte(0);
        wait(first_pin>0);uart_latency=(first_pin-requested_at)/1000.0;
        if(uart_latency>1500)$fatal(1,"UART-to-I2S late %.3fus",uart_latency);
        $display("LATENCY voices=%0d single_min_us=%.3f single_max_us=%.3f full_load_change_us=%.3f burst_allocate_us=%.3f all_rendered_us=%.3f uart_start_to_i2s_us=%.3f env10_us=%.3f env90_us=%.3f max_tail_cycles=%0d frame_cycles=1536 queue_min_us=%.3f queue_max_us=%.3f",VOICES,single_min,single_max,full_us,burst_us,render_us,uart_latency,rise10_us,rise90_us,max_tail,queue_min/1000.0,queue_max/1000.0);
        done=1;
    end
endmodule

module tb_ram32_latency;
    wire done8,done32;
    ram_latency_probe #(.VOICES(8)) eight(done8);
    ram_latency_probe #(.VOICES(32)) thirtytwo(done32);
    initial begin wait(done8 && done32);
        $display("PASS tb_ram32_latency: default ADSR, 8/32 comparison, four event phases, full-load shadow I2S, real UART, all-voice contributions, frame deadlines");$finish;end
    initial begin #30000000;$fatal(1,"latency test timeout");end
endmodule
