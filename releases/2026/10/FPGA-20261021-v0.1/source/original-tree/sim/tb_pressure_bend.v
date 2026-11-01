`timescale 1ns/1ps
// S5 pressure/bend self-check, independent review revision (2026-10-15).
//
// The DUT is driven by vectors generated from tools/pressure_bend_ref.py, so
// every control tick of a step/ramp/spike/pseudo-random pressure sequence and
// every one of the 4096 bend ADC codes is compared value by value instead of
// against a handful of hand written expectations.  The qualitative checks of
// the delivered test (median plus IIR step, 90 percent response, single sample
// spike rejection, bend edges, pressure-off bypass, held note bend without an
// ADSR retrigger) are kept, and pressure-off playability was added.
//
// Regenerate the vectors with:
//   python source/tools/pressure_bend_ref.py --vectors source/sim/vectors
module tb_pressure_bend;
    localparam integer PRESSURE_VECTORS = 640;
    localparam integer BEND_VECTORS     = 4096;
    localparam [11:0]  MID              = 12'd2048;
    localparam [31:0]  BASE_PHASE       = 32'd1000000;
    localparam [11:0]  T90_TARGET       = 12'd3686;   // 90 percent of 4095

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg control_tick = 1'b0;
    reg sample_tick = 1'b0;
    reg [11:0] pressure_adc = 12'd0;
    reg [11:0] bend_adc = MID;
    reg pressure_enable = 1'b1;
    reg [31:0] base_phase_inc = BASE_PHASE;

    wire [11:0] pressure_filtered;
    wire [11:0] pressure_level;
    wire signed [15:0] bend_q8;
    wire [16:0] bend_ratio_q16;
    wire [31:0] phase_inc_out;

    reg gate = 1'b0;
    reg retrigger = 1'b0;
    wire [15:0] env;
    wire env_idle;

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

    // Vectors written by tools/pressure_bend_ref.py --vectors sim/vectors
    reg [11:0] p_in  [0:PRESSURE_VECTORS-1];
    reg [11:0] p_exp [0:PRESSURE_VECTORS-1];
    reg [15:0] b_q8  [0:BEND_VECTORS-1];
    reg [16:0] b_rat [0:BEND_VECTORS-1];
    reg [31:0] b_ph  [0:BEND_VECTORS-1];

    integer failures;
    integer i, k;
    integer t90_ticks;
    reg [31:0] phase_ref;
    reg [15:0] env_before;

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
        $readmemh("sim/vectors/pressure_inputs.hex", p_in);
        $readmemh("sim/vectors/pressure_expected.hex", p_exp);
        $readmemh("sim/vectors/bend_q8_expected.hex", b_q8);
        $readmemh("sim/vectors/bend_ratio_expected.hex", b_rat);
        $readmemh("sim/vectors/bend_phase_expected.hex", b_ph);
    end

    initial begin
        failures = 0;
        t90_ticks = 0;

        repeat (2) @(negedge clk);
        rst = 1'b0;

        // ---- 1) pressure filter, value by value -------------------------
        // The vector sequence is 8 zero ticks, a full scale step, a full
        // scale step down, a 128 tick ramp, a settled mid value, isolated
        // spikes and a fixed seed pseudo random tail.
        for (i = 0; i < PRESSURE_VECTORS; i = i + 1) begin
            control_step(p_in[i], MID);
            if (pressure_filtered !== p_exp[i]) begin
                $display("FAIL pressure tick %0d: adc=%0d dut=%0d ref=%0d",
                         i, p_in[i], pressure_filtered, p_exp[i]);
                failures = failures + 1;
            end
            if (pressure_level !== pressure_filtered) begin
                $display("FAIL pressure level tick %0d: level=%0d filtered=%0d",
                         i, pressure_level, pressure_filtered);
                failures = failures + 1;
            end
            if (phase_inc_out !== BASE_PHASE) begin
                $display("FAIL pressure tick %0d changed pitch: phase=%0d", i, phase_inc_out);
                failures = failures + 1;
            end
            // 90 percent step metric, counted from the first high input tick
            if ((t90_ticks == 0) && (p_in[i] == 12'd4095) && (pressure_filtered >= T90_TARGET))
                t90_ticks = i - 8 + 1;
        end
        if (t90_ticks !== 5) begin
            $display("FAIL 90 percent step response: %0d control ticks", t90_ticks);
            failures = failures + 1;
        end

        // ---- 2) bend map and Q16 ratio, every ADC code -------------------
        for (i = 0; i < BEND_VECTORS; i = i + 1) begin
            control_step(12'd1000, i[11:0]);
            if (bend_q8 !== $signed(b_q8[i])) begin
                $display("FAIL bend q8 at adc=%0d: dut=%0d ref=%0d", i, bend_q8, $signed(b_q8[i]));
                failures = failures + 1;
            end
            if (bend_ratio_q16 !== b_rat[i]) begin
                $display("FAIL bend ratio at adc=%0d: dut=%0d ref=%0d", i, bend_ratio_q16, b_rat[i]);
                failures = failures + 1;
            end
            if (phase_inc_out !== b_ph[i]) begin
                $display("FAIL bend phase at adc=%0d: dut=%0d ref=%0d", i, phase_inc_out, b_ph[i]);
                failures = failures + 1;
            end
        end
        // Bend edges and centre, as required by the task list.
        control_step(12'd1000, 12'd0);
        if (bend_q8 !== -16'sd512) begin
            $display("FAIL bend low edge: q8=%0d", bend_q8);
            failures = failures + 1;
        end
        control_step(12'd1000, MID);
        if (bend_q8 !== 16'sd0 || phase_inc_out !== BASE_PHASE) begin
            $display("FAIL bend centre: q8=%0d phase=%0d", bend_q8, phase_inc_out);
            failures = failures + 1;
        end
        control_step(12'd1000, 12'd4095);
        if (bend_q8 !== 16'sd512) begin
            $display("FAIL bend high edge: q8=%0d", bend_q8);
            failures = failures + 1;
        end

        // A different base increment must scale the same ratio without
        // truncation surprises.
        for (k = 0; k < 3; k = k + 1) begin
            case (k)
                0: base_phase_inc = 32'd500000;
                1: base_phase_inc = 32'd2000000;
                default: base_phase_inc = 32'd4000000;
            endcase
            for (i = 0; i < BEND_VECTORS; i = i + 4095) begin
                control_step(MID, i[11:0]);
                phase_ref = ({32'd0, base_phase_inc} * {47'd0, b_rat[i]}) >> 16;
                if (phase_inc_out !== phase_ref) begin
                    $display("FAIL base=%0d adc=%0d: phase=%0d expected=%0d",
                             base_phase_inc, i, phase_inc_out, phase_ref);
                    failures = failures + 1;
                end
            end
        end
        base_phase_inc = BASE_PHASE;

        // ---- 3) pressure is expression only, and off is still playable ----
        control_step(MID, MID);
        phase_ref = phase_inc_out;
        for (i = 0; i < 4096; i = i + 7) begin
            control_step(i[11:0], MID);
            if (phase_inc_out !== phase_ref) begin
                $display("FAIL pressure sweep changed pitch at adc=%0d: %0d", i, phase_inc_out);
                failures = failures + 1;
            end
        end
        pressure_enable = 1'b0;
        control_step(12'd4095, MID);
        if (pressure_level !== 12'd0 || phase_inc_out !== phase_ref) begin
            $display("FAIL pressure disable: level=%0d phase=%0d", pressure_level, phase_inc_out);
            failures = failures + 1;
        end
        // With pressure disabled a held note must still run.
        gate = 1'b1;
        retrigger = 1'b1;
        audio_step();
        retrigger = 1'b0;
        env_before = env;
        audio_step();
        audio_step();
        if (env_idle || (env <= env_before)) begin
            $display("FAIL pressure disabled stopped the note: env=%0d idle=%b", env, env_idle);
            failures = failures + 1;
        end
        gate = 1'b0;
        pressure_enable = 1'b1;

        // ---- 4) bend during a held note must not retrigger the ADSR ------
        gate = 1'b1;
        retrigger = 1'b1;
        audio_step();
        retrigger = 1'b0;
        audio_step();
        env_before = env;
        control_step(12'd1000, 12'd0);
        audio_step();
        if (env <= env_before || env_idle) begin
            $display("FAIL bend restarted or stopped the held ADSR: before=%0d after=%0d",
                     env_before, env);
            failures = failures + 1;
        end

        if (failures != 0) $fatal(1, "tb_pressure_bend failures=%0d", failures);
        $display("PASS tb_pressure_bend: %0d pressure ticks and %0d ADC codes match the reference, t90=%0d control ticks",
                 PRESSURE_VECTORS, BEND_VECTORS, t90_ticks);
        $finish;
    end

    initial begin
        #10_000_000;
        $fatal(1, "FAIL tb_pressure_bend: timeout");
    end
endmodule