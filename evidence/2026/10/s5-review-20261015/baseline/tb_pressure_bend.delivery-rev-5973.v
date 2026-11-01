// S5 self-checking model test.  Control values are sampled at a synthetic
// control_tick (the production target is 2 kHz); audio and envelope clocks are
// separate to show that a bend update does not retrigger ADSR.
module tb_pressure_bend;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg control_tick = 1'b0;
    reg sample_tick = 1'b0;
    reg [11:0] pressure_adc = 12'd0;
    reg [11:0] bend_adc = 12'd2048;
    reg pressure_enable = 1'b1;
    reg [31:0] base_phase_inc = 32'd1000000;
    wire [11:0] pressure_filtered;
    wire [11:0] pressure_level;
    wire signed [15:0] bend_q8;
    wire [16:0] bend_ratio_q16;
    wire [31:0] phase_inc_out;
    wire [15:0] env;
    wire env_idle;
    reg gate = 1'b0;
    reg retrigger = 1'b0;
    integer i;
    integer t90;
    reg [31:0] phase_center;
    reg [15:0] env_before;

    always #5 clk = ~clk;

    pressure_bend dut (
        .clk(clk), .rst(rst), .control_tick(control_tick),
        .pressure_adc(pressure_adc), .bend_adc(bend_adc),
        .pressure_enable(pressure_enable), .base_phase_inc(base_phase_inc),
        .pressure_filtered(pressure_filtered), .pressure_level(pressure_level),
        .bend_q8(bend_q8), .bend_ratio_q16(bend_ratio_q16),
        .phase_inc_out(phase_inc_out)
    );

    adsr env_dut (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .gate(gate), .retrigger(retrigger), .env(env), .idle(env_idle)
    );

    task control_step;
        input [11:0] next_pressure;
        input [11:0] next_bend;
        begin
            @(negedge clk);
            pressure_adc = next_pressure;
            bend_adc = next_bend;
            control_tick = 1'b1;
            @(posedge clk);
            #1 control_tick = 1'b0;
        end
    endtask

    task audio_step;
        begin
            @(negedge clk);
            sample_tick = 1'b1;
            @(posedge clk);
            #1 sample_tick = 1'b0;
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 1'b0;

        // Three-sample median + IIR step.  The median delays the edge by one
        // control tick; the IIR reaches 90% of 4095 on the fifth high tick.
        for (i = 0; i < 3; i = i + 1)
            control_step(12'd0, 12'd2048);
        control_step(12'd4095, 12'd2048);
        if (pressure_filtered !== 12'd0)
            $fatal(1, "median leaked first step sample: %0d", pressure_filtered);
        control_step(12'd4095, 12'd2048);
        if (pressure_filtered !== 12'd2047)
            $fatal(1, "first IIR step mismatch: %0d", pressure_filtered);
        control_step(12'd4095, 12'd2048);
        if (pressure_filtered !== 12'd3071)
            $fatal(1, "second IIR step mismatch: %0d", pressure_filtered);
        control_step(12'd4095, 12'd2048);
        if (pressure_filtered !== 12'd3583)
            $fatal(1, "third IIR step mismatch: %0d", pressure_filtered);
        t90 = 4;
        while ((pressure_filtered < 12'd3686) && (t90 < 32)) begin
            control_step(12'd4095, 12'd2048);
            t90 = t90 + 1;
        end
        if (t90 !== 5 || pressure_filtered < 12'd3686)
            $fatal(1, "90%% step response mismatch: ticks=%0d value=%0d", t90, pressure_filtered);
        if (pressure_filtered > 12'd4095)
            $fatal(1, "pressure wrapped above ADC range");

        // A single full-scale spike while settled at mid-scale is rejected by
        // the median.  The filtered value may move by at most one IIR LSB.
        for (i = 0; i < 8; i = i + 1)
            control_step(12'd2000, 12'd2048);
        env_before = pressure_filtered;
        control_step(12'd4095, 12'd2048);
        if ((pressure_filtered < env_before) ||
            (pressure_filtered - env_before > 12'd1))
            $fatal(1, "single pressure spike was not rejected: before=%0d after=%0d",
                   env_before, pressure_filtered);

        // Bends map to -2/0/+2 semitones and produce the fixed Q16 ratios.
        control_step(12'd2000, 12'd0);
        if (bend_q8 !== -16'sd512 || phase_inc_out !== 32'd891113)
            $fatal(1, "negative bend mismatch: q8=%0d phase=%0d", bend_q8, phase_inc_out);
        control_step(12'd2000, 12'd2048);
        if (bend_q8 !== 16'sd0 || phase_inc_out !== 32'd1000000)
            $fatal(1, "center bend mismatch: q8=%0d phase=%0d", bend_q8, phase_inc_out);
        phase_center = phase_inc_out;
        control_step(12'd0, 12'd4095);
        if (bend_q8 !== 16'sd512 || phase_inc_out !== 32'd1121978)
            $fatal(1, "positive bend mismatch: q8=%0d phase=%0d", bend_q8, phase_inc_out);
        if (phase_inc_out <= phase_center)
            $fatal(1, "positive bend did not increase sustained phase increment");

        // Pressure is expression only: it must not affect pitch.  Turning the
        // expression path off leaves the bend and phase path operational.
        control_step(12'd4095, 12'd2048);
        phase_center = phase_inc_out;
        pressure_enable = 1'b0;
        control_step(12'd0, 12'd2048);
        if (pressure_level !== 12'd0 || phase_inc_out !== phase_center)
            $fatal(1, "pressure path altered pitch or did not bypass cleanly");
        pressure_enable = 1'b1;

        // Bend while a note is held: no retrigger is asserted, and ADSR keeps
        // advancing through the bend update rather than returning to attack 0.
        gate = 1'b1;
        retrigger = 1'b1;
        audio_step();
        retrigger = 1'b0;
        audio_step();
        env_before = env;
        control_step(12'd1000, 12'd0);
        audio_step();
        if (env <= env_before || env_idle)
            $fatal(1, "bend update restarted or stopped held ADSR: before=%0d after=%0d",
                   env_before, env);

        $display("PASS tb_pressure_bend: bounded median/IIR, t90=%0d control ticks, bend Q8/phase and held ADSR", t90);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "tb_pressure_bend timeout");
    end
endmodule

