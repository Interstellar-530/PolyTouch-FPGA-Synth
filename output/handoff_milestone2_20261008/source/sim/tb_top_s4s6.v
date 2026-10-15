
`timescale 1ns/1ps
// S4/S5/S6 顶层接线自检：2 kHz 控制节拍上的 ADC 轮询、压力/弯音映射、
// 压力不改音高，以及折叠观测输出不留 X。
//
// 弯音的期望值取自 S5 复核确定的映射：ADC 0 -> Q8 -512（-2 半音）、
// 2048 -> 0、4095 -> +512，锚点比率 58400 / 65536 / 73530。
module tb_top_s4s6;
    reg clk = 1'b0;
    reg key_rst = 1'b0, key_s1 = 1'b1, key_s2 = 1'b1, uart_rx = 1'b1;
    reg [11:0] gpio_key_n = 12'hFFF;
    wire hp_bck, hp_ws, hp_din, pa_en, led, led_chord, led_t0, led_t1, uart_tx;
    wire adc_cs_n, adc_sck, adc_mosi, adc_miso;
    wire [3:0] clip_fold;
    reg [11:0] adc_ch0 = 12'd2048, adc_ch1 = 12'd2048;

    mcp3208_model u_adc_model (
        .cs_n(adc_cs_n), .sclk(adc_sck), .mosi(adc_mosi), .miso(adc_miso),
        .ch0(adc_ch0), .ch1(adc_ch1), .ch2(12'd0), .ch3(12'd0),
        .ch4(12'd0), .ch5(12'd0), .ch6(12'd0), .ch7(12'd0)
    );

    top dut (
        .clk_27m(clk), .key_rst(key_rst), .key_s1(key_s1), .key_s2(key_s2),
        .uart_rx(uart_rx), .gpio_key_n(gpio_key_n),
        .hp_bck(hp_bck), .hp_ws(hp_ws), .hp_din(hp_din),
        .pa_en(pa_en), .led(led), .led_chord(led_chord),
        .led_t0(led_t0), .led_t1(led_t1), .uart_tx(uart_tx),
        .adc_cs_n(adc_cs_n), .adc_sck(adc_sck), .adc_mosi(adc_mosi),
        .adc_miso(adc_miso), .clip_fold(clip_fold)
    );

    always #18.5185 clk = ~clk;

    integer errors = 0;
    integer i;
    reg [47:0] exp_mul;
    reg signed [15:0] q8_before;
    reg [31:0] inc_before;

    task wait_poll;
        begin
            @(posedge dut.control_tick);
            repeat (12) @(posedge clk);   // 让一次完整 SPI 事务结束
        end
    endtask

    task expect_bend;
        input [11:0] adc;
        input signed [15:0] want_q8;
        input [16:0] want_ratio;
        begin
            adc_ch1 = adc;
            repeat (3) wait_poll();
            #1;
            if (dut.bend_q8 !== want_q8) begin
                $display("FAIL bend adc=%0d: q8=%0d expect=%0d", adc, dut.bend_q8, want_q8);
                errors = errors + 1;
            end
            if (dut.bend_ratio_q16 !== want_ratio) begin
                $display("FAIL bend adc=%0d: ratio=%0d expect=%0d", adc, dut.bend_ratio_q16, want_ratio);
                errors = errors + 1;
            end
            // 声部 0 直接用 pressure_bend 的输出，其余声部为显式加宽乘法；
            // 这里按参考值核对声部 1 的弯音后增量。
            exp_mul = {16'd0, dut.inc1} * {31'd0, want_ratio};
            if (dut.bend_inc1 !== exp_mul[47:16]) begin
                $display("FAIL bend adc=%0d: bend_inc1=%0d expect=%0d", adc, dut.bend_inc1, exp_mul[47:16]);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (40) @(posedge clk);
        key_rst = 1'b1;                  // 释放复位
        while (dut.por) @(posedge clk);  // 等上电复位计数走完（约 2.4 ms）
        repeat (4) wait_poll();          // 先让两路各采到一次

        // 1) 两个通道都要被轮询到：先给不同的值，观察原值寄存器。
        adc_ch0 = 12'd300;
        adc_ch1 = 12'd2048;
        repeat (4) wait_poll();
        #1;
        if (dut.pressure_raw !== 12'd300) begin
            $display("FAIL pressure_raw=%0d expect=300", dut.pressure_raw);
            errors = errors + 1;
        end
        if (dut.bend_raw !== 12'd2048) begin
            $display("FAIL bend_raw=%0d expect=2048", dut.bend_raw);
            errors = errors + 1;
        end

        // 2) 弯音映射逐值核对（端点与中点）。
        expect_bend(12'd0,    -16'sd512, 17'd58400);
        expect_bend(12'd2048,  16'sd0,   17'd65536);
        expect_bend(12'd4095,  16'sd512, 17'd73530);
        expect_bend(12'd1024, -16'sd256, 17'd61858);   // -1 半音锚点

        // 3) 压力只做表情：改变压力不改变弯音与增量。
        q8_before  = dut.bend_q8;
        inc_before = dut.bend_inc1;
        adc_ch0 = 12'd3800;
        repeat (6) wait_poll();
        #1;
        if (dut.bend_q8 !== q8_before || dut.bend_inc1 !== inc_before) begin
            $display("FAIL pressure changed pitch: q8 %0d -> %0d, inc1 %0d -> %0d",
                     q8_before, dut.bend_q8, inc_before, dut.bend_inc1);
            errors = errors + 1;
        end
        if (dut.pressure_filtered < 12'd2000) begin
            $display("FAIL pressure_filtered did not follow 3800: %0d", dut.pressure_filtered);
            errors = errors + 1;
        end

        // 4) 折叠观测输出必须是确定值（不留 X）。
        if (clip_fold === 4'bxxxx) begin
            $display("FAIL clip_fold is X");
            errors = errors + 1;
        end

        if (errors != 0) $fatal(1, "tb_top_s4s6 failures=%0d", errors);
        $display("PASS tb_top_s4s6: ADC poll, pressure/bend mapping, pitch invariance, folded observables");
        $finish;
    end

    initial begin
        #40_000_000;
        $fatal(1, "FAIL tb_top_s4s6: timeout");
    end
endmodule
