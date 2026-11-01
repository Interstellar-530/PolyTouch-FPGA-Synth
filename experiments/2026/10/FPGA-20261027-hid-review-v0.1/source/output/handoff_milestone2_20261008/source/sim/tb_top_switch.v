`timescale 1ns/1ps
// I0/I1 运行时切换：钢琴 -> 吉他 -> 钢琴，切换拍清声部，重新起音选对表。
module tb_top_switch;
    reg clk27 = 0, clk12 = 0;
    always #18.5185 clk27 = ~clk27;
    always #40.69 clk12 = ~clk12;

    reg rst = 0, s1 = 1, s2 = 1, uart_rx = 1;
    wire uart_tx, kbd_tx;
    wire hp_bck, hp_ws, hp_din, pa_en, led, led_chord, led_t0, led_t1;
    wire adc_cs_n, adc_sck, adc_mosi, adc_miso;
    wire [3:0] clip_fold;
    wire i2s_bck, i2s_lrck, i2s_din, dac_xsmt;

    mcp3208_model u_adc (
        .cs_n(adc_cs_n), .sclk(adc_sck), .mosi(adc_mosi), .miso(adc_miso),
        .ch0(12'd2048), .ch1(12'd2048), .ch2(12'd0), .ch3(12'd0),
        .ch4(12'd0), .ch5(12'd0), .ch6(12'd0), .ch7(12'd0)
    );

    top #(.AUDIO_IF(0), .VOICES(8), .MASTER_VOLUME_SHIFT(3),
          .GPIO_KEY_ENABLE(0), .HOST_KBD_ENABLE(0), .INSTRUMENT_DEFAULT(0)) dut (
        .clk_27m(clk27), .clk_12m288(clk12),
        .key_rst(rst), .key_s1(s1), .key_s2(s2),
        .uart_rx(uart_rx), .gpio_key_n(12'hFFF),
        .kbd_uart_rx(1'b1), .kbd_uart_tx(kbd_tx),
        .adc_cs_n(adc_cs_n), .adc_sck(adc_sck), .adc_mosi(adc_mosi), .adc_miso(adc_miso),
        .hp_bck(hp_bck), .hp_ws(hp_ws), .hp_din(hp_din), .pa_en(pa_en),
        .led(led), .led_chord(led_chord), .led_t0(led_t0), .led_t1(led_t1),
        .uart_tx(uart_tx), .clip_fold(clip_fold),
        .i2s_bck(i2s_bck), .i2s_lrck(i2s_lrck), .i2s_din(i2s_din), .dac_xsmt(dac_xsmt)
    );

    integer ev_count = 0;
    always @(posedge clk27) if (dut.uart_ev_valid) ev_count = ev_count + 1;

    task send_byte;
        input [7:0] b;
        integer i;
        begin
            @(negedge clk27); uart_rx = 1'b0; #8667;
            for (i = 0; i < 8; i = i + 1) begin uart_rx = b[i]; #8667; end
            uart_rx = 1'b1; #8667;
        end
    endtask

    task send_t252;
        begin
            send_byte("T"); send_byte("2"); send_byte("5"); send_byte("2"); send_byte(8'h0D);
        end
    endtask

    task send_i;
        input [7:0] d;
        begin
            send_byte("I"); send_byte(d); send_byte(8'h0D);
        end
    endtask

    task send_n69;
        begin
            send_byte("N"); send_byte("6"); send_byte("9"); send_byte(8'h0D);
        end
    endtask

    task wait_frames;
        input integer n;
        integer start;
        begin
            start = 0;
            while (start < n) begin @(posedge clk27); if (dut.sums_valid) start = start + 1; end
        end
    endtask

    initial begin
        repeat (20) @(posedge clk27);
        rst = 1;
        while (dut.por) @(posedge clk27);
        repeat (10) @(posedge clk27);
        send_byte("X"); send_byte(8'h0D);
        send_t252;
        send_n69;
        wait_frames(1500);
        if (dut.guitar_mode !== 1'b0) $fatal(1, "default not piano");
        if (dut.v_gate === 8'b0) $fatal(1, "piano voice not gated");
        if (dut.u_engine.piano_sel_q !== 1'b1) $fatal(1, "piano table not selected");

        send_i("1");
        repeat (300) @(posedge clk27);
        if (dut.guitar_mode !== 1'b1) $fatal(1, "I1 did not select guitar");
        if (dut.v_gate !== 8'b0) $fatal(1, "instrument change did not clear voice");
        send_n69;
        wait_frames(1500);
        if (dut.u_engine.guitar_sel_q !== 1'b1) $fatal(1, "guitar table not selected");
        if (dut.v_gate === 8'b0) $fatal(1, "guitar voice not gated: vgate=%b instr=%d ev=%0d nnote=%0d", dut.v_gate, dut.instrument_id, ev_count, dut.uart_ev_note);

        send_i("0");
        send_t252;
        repeat (300) @(posedge clk27);
        if (dut.guitar_mode !== 1'b0) $fatal(1, "I0 did not select piano");
        if (dut.v_gate !== 8'b0) $fatal(1, "second switch did not clear voice");
        send_n69;
        wait_frames(1500);
        if (dut.u_engine.piano_sel_q !== 1'b1) $fatal(1, "piano table not restored");
        $display("PASS tb_top_switch: I0/I1 runtime switch, voices cleared, tables re-selected");
        $finish;
    end

    initial begin #500000000; $fatal(1, "timeout"); end
endmodule
