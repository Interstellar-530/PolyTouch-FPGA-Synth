`timescale 1ns/1ps
module tb_mode_uart;
    reg clk = 0, key_rst = 0, key_s1 = 1, key_s2 = 1, uart_rx = 1;
    reg [11:0] gpio_key_n = 12'hFFF;    // [S2-AI] 全部松开；GPIO 交互另见 tb_gpio_top
    wire hp_bck, hp_ws, hp_din, pa_en, led, led_chord, led_t0, led_t1, uart_tx;
    integer err_count = 0, accepted = 0, replies_dequeued = 0, i;
    // [S4/S5/S6] 新增顶层端口与 MCP3208 器件模型：CH0 作压力、CH1 作弯音。
    // 弯音保持在中点 2048，比率恰为 1.0，因此本测试台原有的音频期望不变。
    wire adc_cs_n, adc_sck, adc_mosi, adc_miso;
    wire [3:0] clip_fold;
    reg [11:0] adc_ch0 = 12'd1024, adc_ch1 = 12'd2048;
    mcp3208_model u_adc_model (
        .cs_n(adc_cs_n), .sclk(adc_sck), .mosi(adc_mosi), .miso(adc_miso),
        .ch0(adc_ch0), .ch1(adc_ch1), .ch2(12'd0), .ch3(12'd0),
        .ch4(12'd0), .ch5(12'd0), .ch6(12'd0), .ch7(12'd0)
    );

    top #(.SONG_UNIT_SAMPLES(4)) dut (.clk_27m(clk), .key_rst(key_rst), .key_s1(key_s1), .key_s2(key_s2),
             .uart_rx(uart_rx), .gpio_key_n(gpio_key_n),
             .hp_bck(hp_bck), .hp_ws(hp_ws), .hp_din(hp_din),
             .pa_en(pa_en), .led(led), .led_chord(led_chord),
             .led_t0(led_t0), .led_t1(led_t1), .uart_tx(uart_tx),
             .adc_cs_n(adc_cs_n), .adc_sck(adc_sck), .adc_mosi(adc_mosi),
             .adc_miso(adc_miso), .clip_fold(clip_fold));

    always #18.5185 clk = ~clk;
    always @(posedge clk) begin
        if (dut.u_uart.reply_err) err_count = err_count + 1;
        if (dut.u_uart.reply_ok) accepted = accepted + 1;
        if (dut.u_uart.reply_pop) begin
            if (dut.u_uart.reply_queue[dut.u_uart.reply_rd_ptr] !==
                (replies_dequeued >= 6))
                $fatal(1, "UART reply queue lost command order at %0d", replies_dequeued);
            replies_dequeued = replies_dequeued + 1;
        end
    end

    task send_byte;
        input [7:0] data;
        integer bitno;
        begin
            @(negedge clk); uart_rx = 0; #8680;
            for (bitno = 0; bitno < 8; bitno = bitno + 1) begin
                uart_rx = data[bitno]; #8680;
            end
            uart_rx = 1; #8680;
        end
    endtask
    task settle;
        begin repeat (12) @(negedge clk); end
    endtask

    initial begin
        #100000; key_rst = 1;
        wait (!dut.rst);
        // Speed up song durations with a parameter. Holding sample_tick high
        // creates overlapping audio frames and invalidates shared-DSP timing.
        wait (dut.v_gate != 4'b0000);
        if (!dut.demo_mode) $fatal(1, "Power-on demo missing");

        send_byte("N"); send_byte("6"); send_byte("9"); send_byte(8'h0D); settle();
        if (dut.demo_mode || dut.v_gate == 0 || dut.fifo_empty !== 1'b1)
            $fatal(1, "First manual note failed to clear demo and play");
        if (!(dut.v_note[6:0] == 7'd69 || dut.v_note[13:7] == 7'd69 ||
              dut.v_note[20:14] == 7'd69 || dut.v_note[27:21] == 7'd69))
            $fatal(1, "First manual note was lost during mode switch");
        for (i = 0; i < 40000; i = i + 1) begin
            @(negedge clk);
            if (dut.sp_ev_wr || !dut.fifo_empty)
                $fatal(1, "Demo wrote events during manual mode");
        end

        send_byte("O"); send_byte("6"); send_byte("9"); send_byte(8'h0D); settle();
        if (dut.v_gate != 0) $fatal(1, "Manual Note Off was lost");
        send_byte("D"); send_byte("1"); send_byte(8'h0D); settle();
        if (!dut.demo_mode) $fatal(1, "D1 did not enable demo");
        wait (dut.v_gate != 0);
        send_byte("X"); send_byte(8'h0D); settle();
        if (dut.demo_mode || dut.v_gate != 0 || !dut.fifo_empty)
            $fatal(1, "Panic did not stop demo and clear queue");

        send_byte("D"); send_byte("1"); send_byte(8'h0D); settle();
        wait (dut.v_gate != 0);
        send_byte("D"); send_byte("0"); send_byte(8'h0D); settle();
        if (dut.demo_mode || dut.v_gate != 0)
            $fatal(1, "D0 did not stop demo");
        send_byte("F"); send_byte("4"); send_byte("4"); send_byte("0"); send_byte(8'h0D);
        send_byte("N"); send_byte("9"); send_byte("9"); send_byte("9"); send_byte(8'h0D);
        send_byte("N"); send_byte("1"); send_byte("2"); send_byte("3"); send_byte("4"); send_byte(8'h0D);
        send_byte("M"); send_byte("2"); send_byte(8'h0D);
        send_byte("D"); send_byte("2"); send_byte(8'h0D); settle();
        if (err_count != 5 || dut.demo_mode || dut.v_gate != 0)
            $fatal(1, "Invalid commands: errors=%0d mode=%b gate=%b",
                   err_count, dut.demo_mode, dut.v_gate);
        if (accepted != 6)
            $fatal(1, "Valid command replies missing: %0d", accepted);
        wait (replies_dequeued == 11 && dut.u_uart.reply_count == 0 &&
              dut.u_uart.msg_state == 0);
        if (dut.u_uart.reply_drop_count != 0)
            $fatal(1, "UART response queue overflowed");
        $display("PASS tb_mode_uart: manual priority, demo restart, panic, invalid commands");
        $finish;
    end
    initial begin #300000000; $fatal(1, "Mode/UART integration timeout"); end
endmodule
