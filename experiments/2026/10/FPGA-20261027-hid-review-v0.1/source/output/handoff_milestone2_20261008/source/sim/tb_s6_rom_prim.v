`timescale 1ns/1ps
// 原语等价性自检：行为版 wavetable_osc_dual_s6 与显式 pROM 版
// wavetable_osc_dual_prom 在同一相位与混合设置下逐值比较。
//
// 覆盖全部 512 个地址 × 5 个小数位（含 0、1、127、255、511），三种混合设置
// （纯 sine、纯 bright、50% 交叉混合），共 7680 个比较点。
// 运行需要厂商原语模型 tools/vendor/gowin/prim_sim.v（pROM）。
module tb_s6_rom_prim;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg en = 1'b1;
    reg [31:0] phase = 32'd0;
    reg mix_enable = 1'b0;
    reg [7:0] mix_weight = 8'd0;

    wire signed [15:0] beh_sample, prom_sample;

    wavetable_osc_dual_s6 u_beh (
        .clk(clk), .rst(rst), .en(en), .phase(phase),
        .mix_enable(mix_enable), .mix_weight(mix_weight), .sample_q(beh_sample)
    );
    wavetable_osc_dual_prom u_prom (
        .clk(clk), .rst(rst), .en(en), .phase(phase),
        .mix_enable(mix_enable), .mix_weight(mix_weight), .sample_q(prom_sample)
    );

    integer failures = 0;
    integer addr, fi, wi;
    integer fracs [0:4];
    integer weights [0:2];
    integer enables [0:2];

    task compare_at;
        input [31:0] ph;
        input [7:0]  label_a;
        begin
            phase = ph;
            repeat (3) @(posedge clk);
            #1;
            if (beh_sample !== prom_sample) begin
                failures = failures + 1;
                if (failures < 8)
                    $display("FAIL phase=%h weight=%0d enable=%b: behavioural=%0d pROM=%0d",
                             ph, mix_weight, mix_enable, beh_sample, prom_sample);
            end
        end
    endtask

    initial begin
        fracs[0] = 0; fracs[1] = 1; fracs[2] = 127; fracs[3] = 255; fracs[4] = 511;
        weights[0] = 0; weights[1] = 128; weights[2] = 255;
        enables[0] = 0; enables[1] = 1; enables[2] = 0;

        repeat (4) @(posedge clk);
        rst = 1'b0;

        for (wi = 0; wi < 3; wi = wi + 1) begin
            mix_weight = weights[wi][7:0];
            mix_enable = enables[wi][0];
            for (addr = 0; addr < 512; addr = addr + 1) begin
                for (fi = 0; fi < 5; fi = fi + 1) begin
                    compare_at({addr[8:0], fracs[fi][8:0], 14'd0}, 8'd0);
                end
            end
        end

        // 相位环绕接缝：地址 511 且小数位 511，以及 32 位全 1。
        mix_enable = 1'b0; mix_weight = 8'd0;
        compare_at(32'hFFFFFFFF, 8'd0);
        mix_enable = 1'b1; mix_weight = 8'd128;
        compare_at(32'hFFFFFFFF, 8'd0);

        if (failures != 0) $fatal(1, "tb_s6_rom_prim failures=%0d", failures);
        $display("PASS tb_s6_rom_prim: pROM and behavioural wavetable ROM agree on %0d comparisons",
                 3 * 512 * 5 + 2);
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "FAIL tb_s6_rom_prim: timeout");
    end
endmodule