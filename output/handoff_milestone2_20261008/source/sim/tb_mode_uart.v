`timescale 1ns/1ps
module tb_mode_uart;
    reg clk = 0, key_rst = 0, key_s1 = 1, key_s2 = 1, uart_rx = 1;
    wire hp_bck, hp_ws, hp_din, pa_en, led, led_chord, led_t0, led_t1, uart_tx;
    integer err_count = 0, accepted = 0, replies_dequeued = 0, i;
    top dut (.clk_27m(clk), .key_rst(key_rst), .key_s1(key_s1), .key_s2(key_s2),
             .uart_rx(uart_rx), .hp_bck(hp_bck), .hp_ws(hp_ws), .hp_din(hp_din),
             .pa_en(pa_en), .led(led), .led_chord(led_chord),
             .led_t0(led_t0), .led_t1(led_t1), .uart_tx(uart_tx));
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
        force dut.sample_tick = 1'b1; // speed up the sequencer, not the UART
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
