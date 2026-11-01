`timescale 1ns/1ps
// P0 选表语义定向验收：
//   BANDLIMIT_ENABLE=1、GENERIC_BRIGHT_ENABLE=1 时，
//   piano_enable=0 必须选 gowin_prom_bright_bank（6 级通用表），
//   piano_enable=1 必须选 gowin_prom_piano_bank（12 张钢琴表），
//   且 120 拍/帧、44 次乘积的当前截止时间不变。
module tb_generic_bright;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1, tick = 0;
    reg [127:0] incs = {4{32'h10000000}};
    reg [63:0]  envs = {4{16'h8000}};
    reg [31:0]  vels = {4{8'h7F}};
    reg [3:0]   retrigs = 4'hF;
    reg [16:0]  ratio = 17'd65536;
    reg         piano_enable = 1'b0;

    wire signed [20:0] ss, bs;
    wire valid;
    wire req;
    wire signed [17:0] ma, mb;
    reg signed [35:0] product = 0;
    always @(posedge clk) if (req) product <= ma * mb;

    shared_wavetable_engine #(
        .BEND_SHARED_ENABLE(1), .SHARED_MULT_ENABLE(0),
        .BANDLIMIT_ENABLE(1), .GENERIC_BRIGHT_ENABLE(1),
        .EXTRA_FRACTION_BITS(2)
    ) dut (
        .clk(clk), .rst(rst), .sample_tick(tick),
        .inc0(incs[31:0]), .inc1(incs[63:32]), .inc2(incs[95:64]), .inc3(incs[127:96]),
        .retrig0(retrigs[0]), .retrig1(retrigs[1]), .retrig2(retrigs[2]), .retrig3(retrigs[3]),
        .env0(envs[15:0]), .env1(envs[31:16]), .env2(envs[47:32]), .env3(envs[63:48]),
        .vel0(vels[7:0]), .vel1(vels[15:8]), .vel2(vels[23:16]), .vel3(vels[31:24]),
        .piano_enable(piano_enable), .guitar_enable(1'b0), .piano_tone(3'd2),
        .sine_sum(ss), .bright_sum(bs), .sums_valid(valid),
        .bend_ratio_q16(ratio),
        .mult_request(req), .mult_operand_a(ma), .mult_operand_b(mb), .mult_result(product)
    );

    integer mux_errors = 0;
    integer cycles = 0;
    integer products = 0;
    reg signed [20:0] generic_sum, piano_sum;

    // 选择器不变量：任何时刻 rom_bright_d 必须等于 piano_sel_q 选中的那个 ROM 输出。
    wire [15:0] selected_rom = dut.piano_sel_q ?
        dut.g_banked.u_piano_rom.dout : dut.g_banked.g_generic.u_bright_rom.dout;
    always @(negedge clk) begin
        if (!rst && (dut.rom_bright_d !== selected_rom)) begin
            if (mux_errors < 5)
                $display("FAIL tb_generic_bright: mux mismatch at t=%0t sel=%b rom=%h exp=%h",
                         $time, dut.piano_sel_q, dut.rom_bright_d, selected_rom);
            mux_errors = mux_errors + 1;
        end
    end

    task run_frame(output integer clocks, output integer prods, output signed [20:0] sum);
        begin
            tick = 1; @(negedge clk); tick = 0;
            clocks = 0; prods = 0;
            while (!valid && clocks < 200) begin
                if (req) prods = prods + 1;
                @(negedge clk); clocks = clocks + 1;
            end
            sum = bs;
            @(negedge clk);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);
        // Bank selection is evaluated with a moving phase; holding retrig high
        // would reset every frame to table address zero and make both sums zero.
        retrigs = 4'h0;

        // 1) 非钢琴：必须走通用明亮表
        piano_enable = 1'b0;
        repeat (2) @(negedge clk);
        run_frame(cycles, products, generic_sum);
        if (cycles != 120 || products != 44)
            $fatal(1, "generic frame deadline cycles=%0d products=%0d expect 120/44", cycles, products);
        if (dut.piano_sel_q !== 1'b0)
            $fatal(1, "generic frame latched piano_sel_q=%b", dut.piano_sel_q);
        if (generic_sum == 0)
            $fatal(1, "generic bright_sum is zero");

        // 2) 钢琴：必须走钢琴表，且与通用表结果不同
        piano_enable = 1'b1;
        repeat (2) @(negedge clk);
        run_frame(cycles, products, piano_sum);
        if (cycles != 120 || products != 44)
            $fatal(1, "piano frame deadline cycles=%0d products=%0d expect 120/44", cycles, products);
        if (dut.piano_sel_q !== 1'b1)
            $fatal(1, "piano frame latched piano_sel_q=%b", dut.piano_sel_q);
        if (piano_sum == 0)
            $fatal(1, "piano bright_sum is zero");
        if (generic_sum === piano_sum)
            $fatal(1, "generic and piano paths produced identical output (%0d); tables not separated", generic_sum);

        if (mux_errors != 0)
            $fatal(1, "rom mux mismatches=%0d", mux_errors);
        $display("PASS tb_generic_bright: generic=%0d piano=%0d, 120 clocks/44 products, no mux mismatch",
                 generic_sum, piano_sum);
        $finish;
    end

    initial begin
        #20000000;
        $fatal(1, "timeout");
    end
endmodule
