`timescale 1ns/1ps
// 手工调试工具（不在门禁内）：逐拍打印共享引擎两条链的关键寄存器，
// 用于定位读窗口/捕获点/共享乘法器时序问题。
// 运行：iverilog -g2012 -I . -o dbg.vvp sim/dbg_shared_engine.v \
//         rtl/audio/shared_wavetable_engine.v rtl/audio/gowin_prom_wave_sine.v \
//         rtl/audio/gowin_prom_wave_bright.v sim/gowin_prom_model.v ; vvp dbg.vvp
module dbg_shared_engine;
    reg clk = 0; always #5 clk = ~clk;
    reg rst = 1;
    reg sample_tick = 0;
    // 带小数的相位：idx=64、frac=511，能同时暴露读窗口与插值问题
    reg [31:0] ph = 32'h2001_FFC0 >> 0;

    wire signed [18:0] sine_sum, bright_sum;
    wire sums_valid;
    shared_wavetable_engine u_eng (
        .clk(clk), .rst(rst), .sample_tick(sample_tick),
        .inc0(32'd1), .inc1(32'd1), .inc2(32'd1), .inc3(32'd1),
        .retrig0(1'b0), .retrig1(1'b0), .retrig2(1'b0), .retrig3(1'b0),
        .env0(16'd65535), .env1(16'd65535), .env2(16'd65535), .env3(16'd65535),
        .vel0(8'd127), .vel1(8'd127), .vel2(8'd127), .vel3(8'd127),
        .sine_sum(sine_sum), .bright_sum(bright_sum), .sums_valid(sums_valid)
    );

    integer dbg = 0;
    always @(posedge clk) begin
        if (dbg < 46) begin
            dbg = dbg + 1;
            $display("t=%0d st=%0d addr=%0d cer=%0b rs=%0d rb=%0d a_s=%0d b_s=%0d a_b=%0d b_b=%0d is=%0d ib=%0d ss=%0d sb=%0d p=%0d",
                     dbg, u_eng.state, u_eng.rom_addr, u_eng.rom_ce,
                     u_eng.rom_sine_d, u_eng.rom_bright_d,
                     u_eng.a_sine, u_eng.b_sine, u_eng.a_bright, u_eng.b_bright,
                     u_eng.interp_s, u_eng.interp_b, u_eng.scaled_s, u_eng.scaled_b,
                     u_eng.mul_p[31:0]);
        end
        if (sums_valid) $display("SUMS sine=%0d bright=%0d (expect per voice later)", sine_sum, bright_sum);
    end

    initial begin
        repeat (4) @(posedge clk);
        rst = 0;
        force u_eng.phase0 = ph;
        force u_eng.phase1 = ph;
        force u_eng.phase2 = ph;
        force u_eng.phase3 = ph;
        repeat (6) @(posedge clk);
        @(negedge clk); sample_tick = 1;
        @(negedge clk); sample_tick = 0;
        repeat (120) @(posedge clk);
        $finish;
    end
endmodule