`timescale 1ns/1ps
module tb_frame_velocity;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,tick=0;reg[31:0]held_velocity=32'h7f64501e,live_velocity=32'h7f64501e;
    wire[1:0]valid;wire signed[18:0]sine_sum[0:1],bright_sum[0:1];
    genvar g;
    generate for(g=0;g<2;g=g+1)begin:lane
        wire[31:0]velocity=g==0?held_velocity:live_velocity;
        shared_wavetable_engine #(.BEND_SHARED_ENABLE(1)) dut(.clk(clk),.rst(rst),.sample_tick(tick),
            .piano_enable(1'b0), .piano_tone(3'd0),
            .inc0(32'd23409824),.inc1(32'd27839136),.inc2(32'd33106528),.inc3(32'd39370528),
            .retrig0(1'b0),.retrig1(1'b0),.retrig2(1'b0),.retrig3(1'b0),
            .env0(16'd65535),.env1(16'd40000),.env2(16'd12000),.env3(16'd60000),
            .vel0(velocity[7:0]),.vel1(velocity[15:8]),.vel2(velocity[23:16]),.vel3(velocity[31:24]),
            .bend_ratio_q16(17'd65536),.sine_sum(sine_sum[g]),.bright_sum(bright_sum[g]),.sums_valid(valid[g]));
    end endgenerate
    integer offset,frames=0;
    task compare_frame;
        begin
            wait(valid[0]);#1;
            if(valid!==2'b11 || sine_sum[0]!==sine_sum[1] || bright_sum[0]!==bright_sum[1])
                $fatal(1,"mid-frame velocity tearing: event_offset=%0d reference=%0d/%0d actual=%0d/%0d",offset,sine_sum[0],bright_sum[0],sine_sum[1],bright_sum[1]);
            frames=frames+1;repeat(3)@(negedge clk);
        end
    endtask
    initial begin
        for(offset=0;offset<76;offset=offset+1)begin
            rst=1;tick=0;held_velocity=32'h7f64501e;live_velocity=held_velocity;
            repeat(4)@(negedge clk);rst=0;tick=1;@(negedge clk);tick=0;
            repeat(offset)@(negedge clk);live_velocity=32'h143c787f;
            compare_frame();
            held_velocity=live_velocity;tick=1;@(negedge clk);tick=0;compare_frame();
        end
        $display("PASS tb_frame_velocity: event offsets=76 checked_frames=%0d; current frame holds old velocity, next frame adopts new velocity",frames);$finish;
    end
    initial begin #10000000;$fatal(1,"velocity frame timeout");end
endmodule
