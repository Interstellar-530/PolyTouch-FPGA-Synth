`timescale 1ns/1ps
// Boundary checks plus production median-only pedal -> sustain events.
module tb_fsr_sustain;
    reg clk=0,rst=1,enable=1,update=0;
    reg [11:0] direct=0,raw=0;
    wire pressed,pedal;
    wire [11:0] filtered;
    always #5 clk=~clk;
    fsr_mute #(.PRESS_SAMPLES(2),.RELEASE_SAMPLES(6)) detector(
        .clk(clk),.rst(rst),.enable(enable),.update(update),.pressure(direct),.muted(pressed));
    pressure_bend filter(.clk(clk),.rst(rst),.control_tick(update),
        .pressure_adc(raw),.bend_adc(12'd2048),.pressure_enable(1'b1),
        .base_phase_inc(32'd0),.pressure_filtered(filtered),.pressure_level(),
        .bend_q8(),.bend_ratio_q16(),.phase_inc_out());
    fsr_pedal_conditioner filtered_detector(
        .clk(clk),.rst(rst),.enable(enable),.update(update),.pressure(raw),.pressed(pedal));
    reg valid=0;
    reg [15:0] word_in=0;
    wire in_ready,out_valid;
    wire [15:0] word_out;
    integer ons=0,offs=0,n,k;
    sustain_pedal sustain(.clk(clk),.rst(rst),.clear(!enable),.pedal(pedal),
        .in_valid(valid),.in_word(word_in),.in_ready(in_ready),
        .out_valid(out_valid),.out_word(word_out),.out_ready(1'b1));
    always @(posedge clk) if(!rst && out_valid) begin
        if(word_out[15]) ons=ons+1;else offs=offs+1;
    end
    task sample(input integer d,input integer r);
        begin
            @(negedge clk);direct=d;raw=r;update=1;
            @(negedge clk);update=0;
            repeat(20) @(negedge clk);
        end
    endtask
    task expect_direct(input integer expected);
        if(pressed!==expected[0]) $fatal(1,"qualification boundary pressed=%b expected=%d",pressed,expected);
    endtask
    task send(input on);
        begin
            @(negedge clk);valid=1;word_in={on,7'd60,8'd100};
            do @(posedge clk);while(!in_ready);
            @(negedge clk);valid=0;
            repeat(5)@(negedge clk);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=0;
        sample(512,0);expect_direct(0);
        sample(511,0);expect_direct(0); // interrupted press must restart
        sample(512,0);expect_direct(0);
        sample(512,0);expect_direct(1);
        for(n=0;n<5;n=n+1)begin sample(256,0);expect_direct(1);end
        // Clocks without update cannot finish qualification.
        repeat(1000)@(negedge clk);expect_direct(1);
        sample(257,0);expect_direct(1); // hysteresis band cancels release count
        for(n=0;n<5;n=n+1)begin sample(0,0);expect_direct(1);end
        sample(256,0);expect_direct(0); // exact sixth fresh low sample
        sample(4095,0);sample(4095,0);expect_direct(1);
        sample(0,0);enable=0;@(negedge clk);expect_direct(0);
        enable=1;sample(4095,0);expect_direct(0);sample(4095,0);expect_direct(1);
        rst=1;@(negedge clk);expect_direct(0);rst=0;
        for(n=0;n<16;n=n+1)sample(3000,3000);
        if(!pedal)$fatal(1,"filtered FSR did not press");
        send(1);send(0);
        if(ons!=1 || offs!=0)$fatal(1,"pedal did not defer Note Off");
        // The <=5 ms response contract rejects 2 ms, not 5 ms, outages.
        for(k=0;k<12;k=k+1)begin
            for(n=0;n<4;n=n+1)begin
                sample(0,0);
                if(!pedal || offs!=0)$fatal(1,"FSR_DROPOUT_RELEASED_NOTE");
            end
            for(n=0;n<16;n=n+1)begin
                sample(3000,3000);
                if(!pedal || offs!=0)$fatal(1,"recovery emitted deferred Note Off");
            end
        end
        n=0;
        while(pedal && n<20)begin sample(0,0);n=n+1;end
        if(pedal || n>8)$fatal(1,"pedal release exceeded 4 ms update budget: samples=%0d",n);
        $display("FSR_RELEASE_UPDATES=%0d nominal_ms=%0d/2 (median + detector, excludes ADC/DAC)",n,n);
        repeat(200)@(negedge clk);
        if(pedal || offs!=1)$fatal(1,"true release must emit exactly one deferred Note Off");
        repeat(200)@(negedge clk);
        if(offs!=1)$fatal(1,"duplicate deferred Note Off");
        $display("PASS tb_fsr_sustain: exact thresholds/counts, interrupted qualification, update gating, reset/disable, 12 filtered dropouts, single real release");
        $finish;
    end
    initial begin #1000000;$fatal(1,"FSR sustain timeout");end
endmodule
