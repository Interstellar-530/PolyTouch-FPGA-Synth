`timescale 1ns/1ps
module tb_voice_sched32_review;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,tick=0,valid=0,on=0,ready=0,instrument=0;
    reg [1:0] tone=0;
    reg [6:0] note=0;reg [7:0] velocity=100;
    wire ev_ready,cv,retrigger;wire [5:0] voice,active;
    wire [31:0] increment;wire [15:0] envelope;wire [6:0] vel;wire [23:0] param;
    reg [23:0] observed[0:31];
    always @(posedge clk)if(!rst && cv && ready)observed[voice]<=param;
    voice_sched32 dut(.clk(clk),.rst(rst),.sample_tick(tick),.instrument(instrument),.piano_tone(tone),.ev_valid(valid),
        .ev_on(on),.ev_note(note),.ev_vel(velocity),.ev_ready(ev_ready),
        .cfg_voice(voice),.cfg_increment(increment),.cfg_envelope(envelope),
        .cfg_velocity(vel),.cfg_retrigger(retrigger),.cfg_param(param),.cfg_valid(cv),.cfg_ready(ready),.active_count(active));
    integer which,i,count62,cycles,first_case,last_case;
    reg [31:0] saved_inc;
    task step;begin @(posedge clk);#1;@(negedge clk);end endtask
    task send;
        input [6:0] n;
        begin
            while(!ev_ready)step();
            note=n;on=1;valid=1;step();valid=0;
        end
    endtask
    task drain;
        begin
            cycles=0;
            while(dut.ev_state!=0 || dut.ev_q_valid)begin
                step();cycles=cycles+1;
                if(cycles>150)$fatal(1,"event search stalled");
            end
        end
    endtask
    initial begin
        if($value$plusargs("case=%d",first_case))last_case=first_case;
        else begin first_case=1;last_case=5;end
        for(which=first_case;which<=last_case;which=which+1)begin
        rst=1;ready=0;valid=0;velocity=100;instrument=0;tone=0;
        repeat(4)step();rst=0;step();
        case(which)
        1:begin
            send(60);drain();send(61);drain();send(62);drain();
            send(62);send(63);drain();
            count62=0;
            for(i=0;i<32;i=i+1)if(dut.gate[i] && dut.note[i]==62)count62=count62+1;
            if(count62!=1 || active!=4 || dut.note[2]!=62 || dut.note[3]!=63)
                $fatal(1,"queued_note_corrupted_retrigger count62=%0d active=%0d",count62,active);
        end
        2:begin
            for(i=0;i<32;i=i+1)begin send(36+i[6:0]);drain();end
            send(67);drain();send(100);drain();
            if(dut.note[0]!=100 || dut.note[1]!=37)
                $fatal(1,"age_wrap_wrong_steal voice0=%0d voice1=%0d",dut.note[0],dut.note[1]);
            for(i=0;i<70;i=i+1)begin send(67);drain();end
            send(101);drain();
            if(dut.note[1]!=101)$fatal(1,"repeated retriggers changed oldest voice");
        end
        3:begin
            send(60);drain();ready=1;
            while(!cv)step();
            saved_inc=increment;ready=0;
            repeat(3)begin
                step();if(!cv || increment!==saved_inc || vel!=100 || !retrigger)
                    $fatal(1,"config_dropped_under_backpressure");
            end
            velocity=63;send(60);drain();
            if(!cv || increment!==saved_inc || vel!=100 || !retrigger)
                $fatal(1,"pending_config_payload_changed");
            ready=1;step();
            cycles=0;
            while(!cv)begin step();cycles=cycles+1;if(cycles>33)$fatal(1,"new dirty update lost after a complete scan");end
            if(vel!=63 || !retrigger)$fatal(1,"new retrigger lost while old config waited");
            step();
        end
        4:begin
            velocity=128;send(60);drain();ready=1;
            while(!cv)step();
            if(vel!=127)$fatal(1,"velocity_truncated_to_silence got=%0d",vel);
        end
        5:begin
            velocity=32;send(40);drain();send(60);drain();ready=1;
            instrument=1;tick=1;step();tick=0;repeat(80)step();
            if(observed[0][21:16]!=14 || observed[1][21:16]!=19 || observed[0][15:0]!=0)
                $fatal(1,"guitar production band/velocity mapping changed low=%0d C4=%0d",observed[0][21:16],observed[1][21:16]);
            tone=3;instrument=0;send(78);drain();tick=1;step();tick=0;repeat(80)step();
            if(observed[2][21:16]!=10)$fatal(1,"piano production zone mapping changed");
            dut.stage_q[2]=4;tone=0;tick=1;step();tick=0;repeat(80)step();
            if(observed[2][21:16]!=6)$fatal(1,"piano tone change underflowed stage");
        end
        default:$fatal(1,"unknown case");
        endcase
        $display("PASS tb_voice_sched32_review case=%0d",which);
        end
        $finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
