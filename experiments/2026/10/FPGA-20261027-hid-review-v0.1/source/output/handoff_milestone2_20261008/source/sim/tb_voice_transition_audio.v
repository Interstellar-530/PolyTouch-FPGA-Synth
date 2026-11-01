`timescale 1ns/1ps
module tb_voice_transition_audio;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,tick=0,gate=1,event_on=0;reg[6:0]note=60;reg[7:0]weight=0;
    wire[6:0]render_note;wire[7:0]render_velocity;wire restart;wire[15:0]soft_env,hard_env;
    wire[31:0]soft_inc,hard_inc;
    wire[1:0]valid;wire signed[18:0]ss[0:1],bs[0:1];wire signed[15:0]audio[0:1];
    voice_transition voice_soft(.clk(clk),.rst(rst),.sample_tick(tick),.gate(gate),.retrigger(event_on),.piano_mode(1'b0),.guitar_mode(1'b0),.note(note),.velocity(8'd100),
        .render_note(render_note),.render_velocity(render_velocity),.render_retrigger(restart),.env(soft_env),.idle());
    adsr hard(.clk(clk),.rst(rst),.sample_tick(tick),.gate(gate),.retrigger(event_on),.env(hard_env),.idle());
    note_phase_inc #(.FS_HZ(48000)) s_inc(render_note,soft_inc),h_inc(note,hard_inc);
    genvar g;
    generate for(g=0;g<2;g=g+1)begin:lane
        shared_wavetable_engine #(.BEND_SHARED_ENABLE(1)) core(.clk(clk),.rst(rst),.sample_tick(tick),
            .piano_enable(1'b0), .piano_tone(3'd0),
            .inc0(g==0?soft_inc:hard_inc),.inc1(32'd0),.inc2(32'd0),.inc3(32'd0),
            .retrig0(g==0?restart:event_on),.retrig1(1'b0),.retrig2(1'b0),.retrig3(1'b0),
            .env0(g==0?soft_env:hard_env),.env1(16'd0),.env2(16'd0),.env3(16'd0),
            .vel0(g==0?render_velocity:8'd100),.vel1(8'd0),.vel2(8'd0),.vel3(8'd0),
            .bend_ratio_q16(17'd65536),.sine_sum(ss[g]),.bright_sum(bs[g]),.sums_valid(valid[g]));
        global_crossfade #(.MASTER_VOLUME_SHIFT(2)) xf(.clk(clk),.rst(rst),.update(valid[g]),.clear_clip(1'b0),
            .mix_weight(weight),.sine_sum(ss[g]),.bright_sum(bs[g]),.sample_out(audio[g]));
    end endgenerate
    integer c,n,fd=0,frames=0,latency;reg[2047:0]capture;
    task frame;
        begin tick=1;@(negedge clk);tick=0;wait(valid[0]);repeat(3)@(negedge clk);
            if(valid[1]!==0 && valid[1]!==1)$fatal(1,"unknown frame");frames=frames+1;
        end
    endtask
    initial begin
        if($value$plusargs("CAPTURE=%s",capture))begin
            fd=$fopen(capture,"w");if(!fd)$fatal(1,"capture open");
            $fwrite(fd,"case_id,weight,frame,soft,hard,env,render_note\n");
        end
        for(c=0;c<16;c=c+1)begin
            rst=1;event_on=0;note=c<8?60:48;weight=c<8?0:255;
            repeat(4)@(negedge clk);rst=0;event_on=1;frame();event_on=0;
            repeat(2048+(c%8)*23)frame();latency=-1;
            for(n=0;n<1024;n=n+1)begin
                if(n==256)begin event_on=1;note=c<8?64:55;end
                frame();event_on=0;
                if(n>=256 && !voice_soft.fading && latency<0)latency=n-256;
                if(fd)$fwrite(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",c,weight,n,audio[0],audio[1],soft_env,render_note);
            end
            if(latency<0 || latency>64)$fatal(1,"restart latency %0d",latency);
        end
        if(fd)$fclose(fd);$display("PASS tb_voice_transition_audio: 16 phase/timbre cases, actual waveform chains, captured_frames=16384 total_frames=%0d restart_delay<=64",frames);$finish;
    end
    initial begin #100000000;$fatal(1,"transition audio timeout");end
endmodule
