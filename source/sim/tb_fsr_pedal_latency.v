`timescale 1ns/1ps
// Real 2 kHz update cadence. A slower 1 MHz logic clock is conservative for
// the same clock-enabled algorithm used at 27 MHz on the production board.
module tb_fsr_pedal_latency;
    reg clk=0,rst=1,enable=1;
    always #500 clk=~clk;
    integer divider=0;
    wire update=(divider==499);
    always @(posedge clk) if(rst)divider<=0;else if(update)divider<=0;else divider<=divider+1;
    reg [11:0] raw=0;
    wire pedal;
    fsr_pedal_conditioner dut(.clk(clk),.rst(rst),.enable(enable),.update(update),.pressure(raw),.pressed(pedal));
    integer h,l,p,i,high_code,low_code;
    realtime started,elapsed,max_press=0,max_release=0;
    task settle(input integer code);
        begin @(negedge clk);raw=code;repeat(12)begin @(posedge clk);while(!update)@(posedge clk);end #1;end
    endtask
    task change_and_time(input integer code,input integer expected,input integer offset_ns);
        begin
            // Place the transition just after a sample, or half a sample later.
            @(posedge clk);while(!update)@(posedge clk);
            #2; #(offset_ns);raw=code;started=$realtime;
            fork : response
                begin wait(pedal==expected[0]);elapsed=$realtime-started;end
                begin #4999000;$fatal(1,"pedal response exceeded 5 ms h=%0d l=%0d phase=%0d",high_code,low_code,offset_ns);end
            join_any
            disable response;
            if(expected)begin if(elapsed>max_press)max_press=elapsed;end
            else if(elapsed>max_release)max_release=elapsed;
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=0;
        for(h=0;h<4;h=h+1)begin
            case(h)0:high_code=512;1:high_code=600;2:high_code=3000;3:high_code=4095;endcase
            for(l=0;l<3;l=l+1)begin
                case(l)0:low_code=0;1:low_code=128;2:low_code=256;endcase
                for(p=0;p<2;p=p+1)begin
                    settle(low_code);
                    change_and_time(high_code,1,p*250000);
                    settle(high_code);
                    // 2 ms low glitches at both alignment extremes must hold.
                    @(negedge clk);raw=low_code;#2000000;
                    if(!pedal)$fatal(1,"2 ms glitch dropped pedal");
                    raw=high_code;#2000000;
                    if(!pedal)$fatal(1,"glitch recovery dropped pedal");
                    settle(high_code);
                    change_and_time(low_code,0,p*250000);
                    settle(low_code);
                end
            end
        end
        $display("PASS tb_fsr_pedal_latency: 24 press/release cases, thresholds 512/256, 2 ms glitches, max_press_ms=%0.6f max_release_ms=%0.6f",max_press/1000000,max_release/1000000);
        $finish;
    end
    initial begin #1200000000;$fatal(1,"latency suite deadline");end
endmodule
