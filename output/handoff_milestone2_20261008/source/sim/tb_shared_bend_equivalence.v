`timescale 1ns/1ps
module tb_shared_bend_equivalence;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,tick=0;
    reg [31:0] inc0=0,inc1=0,inc2=0,inc3=0;
    reg [15:0] env0=0,env1=0,env2=0,env3=0;
    reg [7:0] vel0=0,vel1=0,vel2=0,vel3=0;
    wire signed [18:0] s0,b0,s1,b1;wire v0,v1;
    reg [16:0] ratio=65536;reg [3:0] retrig=0;
    wire[48:0] m0=inc0*ratio,m1=inc1*ratio,m2=inc2*ratio,m3=inc3*ratio;
    wire[31:0] bent0=m0>>16,bent1=m1>>16,bent2=m2>>16,bent3=m3>>16;
    shared_wavetable_engine #(.BEND_SHARED_ENABLE(1)) optimized(clk,rst,tick,inc0,inc1,inc2,inc3,retrig[0],retrig[1],retrig[2],retrig[3],
        env0,env1,env2,env3,vel0,vel1,vel2,vel3,s0,b0,v0,ratio,,,,36'd0);
    baseline_shared_wavetable_engine baseline(clk,rst,tick,bent0,bent1,bent2,bent3,retrig[0],retrig[1],retrig[2],retrig[3],
        env0,env1,env2,env3,vel0,vel1,vel2,vel3,s1,b1,v1);
    integer frame,cycle,new_latency,old_latency,products,total_products=0;
    reg new_seen,old_seen;reg signed [18:0] new_s,new_b,old_s,old_b;
    initial begin
        repeat(4)@(negedge clk);rst=0;
        for(frame=0;frame<2048;frame=frame+1)begin
            inc0=$random;inc1=$random;inc2=$random;inc3=$random;
            env0=$random;env1=$random;env2=$random;env3=$random;
            vel0=$random;vel1=$random;vel2=$random;vel3=$random;
            if(frame==0)begin env0=65535;env1=65535;env2=65535;env3=65535;vel0=255;vel1=255;vel2=255;vel3=255;end
            ratio=58400+($urandom%15131);retrig=$random;
            if(frame==0)ratio=0;if(frame==1)ratio=131071;
            tick=1;@(negedge clk);tick=0;new_seen=0;old_seen=0;products=0;
            for(cycle=1;cycle<256;cycle=cycle+1)begin
                if(optimized.mul_enable)products=products+1;
                @(negedge clk);
                if(v0)begin if(new_seen)$fatal(1,"repeated optimized valid");new_seen=1;new_latency=cycle;new_s=s0;new_b=b0;end
                if(v1)begin if(old_seen)$fatal(1,"repeated baseline valid");old_seen=1;old_latency=cycle;old_s=s1;old_b=b1;end
            end
            if(!new_seen || !old_seen || new_s!==old_s || new_b!==old_b)$fatal(1,"frame mismatch %d",frame);
            if(new_latency!=76 || old_latency!=84 || products!=32)$fatal(1,"unexpected schedule %d %d %d",new_latency,old_latency,products);
            total_products=total_products+products;
        end
        $display("METRIC shared_bend frames=2048 old_cycles=84 new_cycles=76 saved_cycles=8 useful_products=32 period=256 register_enables=%0d",total_products);
        $display("PASS tb_shared_bend_equivalence: frame-bit-exact random base increments/ratios/retrigger/envelopes, 76-cycle deadline, single completion");$finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
