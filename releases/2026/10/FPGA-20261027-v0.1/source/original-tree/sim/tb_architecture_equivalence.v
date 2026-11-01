`timescale 1ns/1ps
module tb_architecture_equivalence;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,tick=0;
    reg [31:0] inc0=0,inc1=0,inc2=0,inc3=0;
    reg [15:0] env0=0,env1=0,env2=0,env3=0;
    reg [7:0] vel0=0,vel1=0,vel2=0,vel3=0;
    wire signed [18:0] s0,b0,s1,b1;wire v0,v1;
    shared_wavetable_engine #(
        .BEND_SHARED_ENABLE(0), .SHARED_MULT_ENABLE(0),
        .BANDLIMIT_ENABLE(0), .GENERIC_BRIGHT_ENABLE(0), .GUITAR_ENABLE(0),
        .KEY_GAIN_ENABLE(0)
    ) optimized (
        .clk(clk), .rst(rst), .sample_tick(tick),
        .inc0(inc0), .inc1(inc1), .inc2(inc2), .inc3(inc3),
        .inc4(32'd0), .inc5(32'd0), .inc6(32'd0), .inc7(32'd0),
        .retrig0(1'b0), .retrig1(1'b0), .retrig2(1'b0), .retrig3(1'b0),
        .retrig4(1'b0), .retrig5(1'b0), .retrig6(1'b0), .retrig7(1'b0),
        .env0(env0), .env1(env1), .env2(env2), .env3(env3),
        .env4(16'd0), .env5(16'd0), .env6(16'd0), .env7(16'd0),
        .vel0(vel0), .vel1(vel1), .vel2(vel2), .vel3(vel3),
        .vel4(8'd0), .vel5(8'd0), .vel6(8'd0), .vel7(8'd0),
        .note0(7'd0), .note1(7'd0), .note2(7'd0), .note3(7'd0),
        .note4(7'd0), .note5(7'd0), .note6(7'd0), .note7(7'd0),
        .piano_enable(1'b0), .guitar_enable(1'b0), .piano_tone(3'd0),
        .sine_sum(s0), .bright_sum(b0), .sums_valid(v0),
        .bend_ratio_q16(17'd65536),
        .mult_request(), .mult_operand_a(), .mult_operand_b(),
        .mult_result(36'sd0)
    );
    baseline_shared_wavetable_engine baseline(clk,rst,tick,inc0,inc1,inc2,inc3,1'b0,1'b0,1'b0,1'b0,
        env0,env1,env2,env3,vel0,vel1,vel2,vel3,s1,b1,v1);
    integer frame,cycle,new_latency,old_latency,products,total_products=0;
    reg new_seen,old_seen;reg signed [18:0] new_s,new_b,old_s,old_b;
    initial begin
        repeat(4)@(negedge clk);rst=0;
        for(frame=0;frame<2048;frame=frame+1)begin
            inc0=$random;inc1=$random;inc2=$random;inc3=$random;
            env0=$random;env1=$random;env2=$random;env3=$random;
            // 力度按产品范围 0..127 驱动：15 位 key_a 只覆盖 C=256 下的 0..127，
            // >127 会回绕（见 v2.0.0 发布说明的已知限制），不是本台要测的语义。
            vel0=$random&8'h7f;vel1=$random&8'h7f;vel2=$random&8'h7f;vel3=$random&8'h7f;
            if(frame==0)begin env0=65535;env1=65535;env2=65535;env3=65535;vel0=127;vel1=127;vel2=127;vel3=127;end
            tick=1;@(negedge clk);tick=0;new_seen=0;old_seen=0;products=0;
            for(cycle=1;cycle<256;cycle=cycle+1)begin
                if(optimized.mul_enable)products=products+1;
                @(negedge clk);
                if(v0)begin if(new_seen)$fatal(1,"repeated optimized valid");new_seen=1;new_latency=cycle;new_s=s0;new_b=b0;end
                if(v1)begin if(old_seen)$fatal(1,"repeated baseline valid");old_seen=1;old_latency=cycle;old_s=s1;old_b=b1;end
            end
            if(!new_seen || !old_seen || new_s!==old_s || new_b!==old_b)$fatal(1,"frame mismatch %d",frame);
            if(new_latency!=72 || old_latency!=84 || products!=28)$fatal(1,"unexpected schedule %d %d %d",new_latency,old_latency,products);
            total_products=total_products+products;
        end
        $display("METRIC architecture frames=2048 old_cycles=84 new_cycles=72 saved_cycles=12 useful_products=28 period=256 register_enables=%0d",total_products);
        $display("PASS tb_architecture_equivalence: frame-bit-exact random phase/envelope/velocity, 72-cycle deadline (key-gain stage), single completion");$finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule




