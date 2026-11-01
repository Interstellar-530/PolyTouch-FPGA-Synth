`timescale 1ns/1ps
// P1 定向验收：音区在起音锁存、音色阶段由独立计时器推进。
module tb_piano_stage;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1, tick = 0, piano_en = 1;
    reg [127:0] incs;
    reg [63:0]  envs = {4{16'hFFFF}};   // 包络恒定，阶段仍必须推进
    reg [31:0]  vels = 32'd0;           // layer 0
    reg [3:0]   retrigs = 4'b0001;
    reg [16:0]  ratio = 17'd65536;
    wire signed [18:0] ss, bs;
    wire valid, req;
    wire signed [17:0] ma, mb;
    reg signed [35:0] product = 0;
    always @(posedge clk) if (req) product <= ma * mb;

    shared_wavetable_engine #(
        .BEND_SHARED_ENABLE(0), .SHARED_MULT_ENABLE(0),
        .BANDLIMIT_ENABLE(1), .GENERIC_BRIGHT_ENABLE(1),
        .ZONE_LATCH_ENABLE(1), .STAGE_TIME_ENABLE(1),
        .STAGE_STEP_SAMPLES(8), .EXTRA_FRACTION_BITS(0)
    ) dut (
        .clk(clk), .rst(rst), .sample_tick(tick),
        .inc0(incs[31:0]), .inc1(incs[63:32]), .inc2(incs[95:64]), .inc3(incs[127:96]),
        .retrig0(retrigs[0]), .retrig1(retrigs[1]), .retrig2(retrigs[2]), .retrig3(retrigs[3]),
        .env0(envs[15:0]), .env1(envs[31:16]), .env2(envs[47:32]), .env3(envs[63:48]),
        .vel0(vels[7:0]), .vel1(vels[15:8]), .vel2(vels[23:16]), .vel3(vels[31:24]),
        .piano_enable(piano_en), .piano_tone(3'd0),
        .sine_sum(ss), .bright_sum(bs), .sums_valid(valid),
        .bend_ratio_q16(ratio),
        .mult_request(req), .mult_operand_a(ma), .mult_operand_b(mb), .mult_result(product)
    );

    reg [6:0] bank_cap = 0;
    always @(posedge clk) if (!rst && dut.state == 6'd1 && dut.vsel == 2'd0) bank_cap <= dut.selected_band[22:16];

    integer cycles;
    task frame;
        begin
            tick = 1; @(negedge clk); tick = 0;
            cycles = 0;
            while (!valid && cycles < 200) begin @(negedge clk); cycles = cycles + 1; end
            if (cycles >= 200) $fatal(1, "frame timeout");
            @(negedge clk);
        end
    endtask

    integer i;
    reg [6:0] bank0;
    initial begin
        incs = {4{32'h00600000}};   // zone 1
        repeat (4) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        // 起音：锁存 zone 1，stage 0
        frame();
        if (dut.zone_q[0] !== 3'd1) $fatal(1, "initial zone=%0d expect 1", dut.zone_q[0]);
        if (dut.stage_q[0] !== 3'd0) $fatal(1, "initial stage=%0d expect 0", dut.stage_q[0]);
        retrigs = 4'b0000;   // 只在本帧起音，后续帧不再复位阶段
        bank0 = bank_cap;
        if (bank0 !== 7'd3) $fatal(1, "start bank=%0d expect 3 (group0 stage3)", bank0);

        // 包络恒为 FFFF，仍应按 8 个采样推进阶段
        for (i = 0; i < 8; i = i + 1) frame();
        if (dut.stage_q[0] !== 3'd1)
            $fatal(1, "after 8 ticks stage=%0d expect 1 (envelope must not control stage)", dut.stage_q[0]);
        if (bank_cap !== 7'd2)
            $fatal(1, "stage1 bank=%0d expect 2 (group0 stage2)", bank_cap);

        // 弯音改变 inc 但不 retrig：音区必须保持 zone 1
        incs = {4{32'h01800000}};   // zone 3（0x01000000..0x02000000）
        repeat (2) @(negedge clk);
        frame();
        if (dut.zone_q[0] !== 3'd1)
            $fatal(1, "zone changed under bend without retrigger: %0d", dut.zone_q[0]);

        // retrig：用新的 inc 锁存 zone 3，stage 归零
        retrigs = 4'b0001;
        frame();
        if (dut.zone_q[0] !== 3'd3)
            $fatal(1, "retrigger zone=%0d expect 3", dut.zone_q[0]);
        if (dut.stage_q[0] !== 3'd0)
            $fatal(1, "retrigger stage=%0d expect 0", dut.stage_q[0]);

        $display("PASS tb_piano_stage: zone latched at note-on, stage advances on time with env held at FFFF");
        $finish;
    end

    initial begin
        #10000000;
        $fatal(1, "timeout");
    end
endmodule
