`timescale 1ns/1ps
module tb_voice_transition;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,tick=0,gate=0,retrigger=0;reg[6:0]note=60;reg[7:0]velocity=100;
    wire[6:0]render_note;wire[7:0]render_velocity;wire restart,idle;wire[15:0]env;
    voice_transition #(.ATTACK_STEP(8192),.DECAY_STEP(4096),.RELEASE_STEP(2048),.SUSTAIN_LEVEL(32767)) dut(
        .clk(clk),.rst(rst),.sample_tick(tick),.gate(gate),.retrigger(retrigger),.note(note),.velocity(velocity),
        .render_note(render_note),.render_velocity(render_velocity),.render_retrigger(restart),.env(env),.idle(idle));
    integer n,cases=0;reg[15:0]previous,start_env;reg saw_restart;
    task step;
        begin tick=1;@(posedge clk);#1;@(negedge clk);tick=0;repeat(2)@(negedge clk);end
    endtask
    task on;input[6:0]key;input[7:0]vel;
        begin note=key;velocity=vel;gate=1;retrigger=1;step();retrigger=0;end
    endtask
    task sustain;
        begin for(n=0;n<32 && env!=32767;n=n+1)step();if(env!=32767)$fatal(1,"sustain setup");end
    endtask
    task finish_fade;input[6:0]key;input[7:0]vel;
        integer j;
        begin
            previous=env;saw_restart=0;
            for(j=0;j<66 && dut.fading;j=j+1)begin
                if(restart)saw_restart=1;
                step();
                // The upcoming note is presented before the finishing sample
                // edge so the engine can snapshot pitch and reset atomically.
                if(dut.fading && (env>previous || (!dut.finishing && (render_note!=dut.active_note || render_velocity!=dut.active_velocity))))$fatal(1,"old render state changed during fade");
                previous=env;
            end
            if(j>64 || dut.fading || !saw_restart || env!=0 || render_note!=key || render_velocity!=vel)$fatal(1,"fade did not atomically restart in 64 frames");
            cases=cases+1;
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=0;on(60,100);
        if(env!=0 || render_note!=60 || render_velocity!=100)$fatal(1,"idle onset changed");
        sustain();start_env=env;on(60,127);
        if(env!=start_env || !dut.fading || render_velocity!=100)$fatal(1,"repeat hard-cut or early velocity");
        finish_fade(60,127);sustain();start_env=env;on(72,80);
        if(env!=start_env || render_note!=60 || render_velocity!=127)$fatal(1,"steal changed old pitch/velocity");
        repeat(5)step();on(67,30);finish_fade(67,30);sustain();
        on(69,100);repeat(4)step();gate=0;
        for(n=0;n<66 && dut.fading;n=n+1)step();
        if(!idle || env!=0)$fatal(1,"released pending note reappeared");cases=cases+1;
        on(65,100);step();gate=0;step();on(70,110);finish_fade(70,110);
        rst=1;step();rst=0;
        if(env!=0 || !idle || dut.fading)$fatal(1,"reset did not clear transition");
        $display("PASS tb_voice_transition: repeat, steal, latest pending event, cancel, release reuse and reset; bounded fade cases=%0d",cases);$finish;
    end
    initial begin #1000000;$fatal(1,"voice transition timeout");end
endmodule
