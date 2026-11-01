`timescale 1ns/1ps
module tb_board_only;
    reg clk=0,rst=0,rx=1;
    always #18.5185 clk=~clk;
    wire bck,ws,din,pa,tx;
    board_only_top dut(.clk_27m(clk),.key_rst(rst),.key_s1(1'b1),.key_s2(1'b1),
        .uart_rx(rx),.hp_bck(bck),.hp_ws(ws),.hp_din(din),.pa_en(pa),.uart_tx(tx));
    integer cycles=0,last_tick=-1,ticks=0,accepted=0,frames=0;
    reg monitor=0,prev_tick=0,prev_ws=0,synced=0;
    reg [15:0] shift=0,left=0,reference=0;
    integer bits=0;
    always @(posedge clk) begin
        cycles=cycles+1;
        if(dut.u_top.u_uart.reply_ok)accepted=accepted+1;
        if(dut.u_top.u_uart.reply_err)$fatal(1,"valid UART command rejected");
        if(monitor)begin
            if(dut.u_top.gpio_key_n!==12'hfff)$fatal(1,"external key input not isolated");
            if(dut.u_top.bend_ratio_q16!==17'd65536)$fatal(1,"bend is not unity");
            if(dut.u_top.sample_tick)begin
                if(prev_tick || (last_tick>=0 && cycles-last_tick!=576))$fatal(1,"tick width/period");
                last_tick=cycles;ticks=ticks+1;
            end
            prev_tick=dut.u_top.sample_tick;
        end
    end
    always @(posedge bck)begin
        #1;
        if(!dut.u_top.por)begin
            if(!synced)begin
                if(prev_ws && !ws)begin synced=1;bits=1;shift={15'd0,din};reference=dut.u_top.g_pt8211.u_pt8211.frame_data;end
            end else if(ws==prev_ws)begin shift={shift[14:0],din};bits=bits+1;end
            else begin
                if(bits!=16)$fatal(1,"PT8211 word width");
                if(!prev_ws)begin left=shift;if(left!==reference)$fatal(1,"left serial decode mismatch");end
                else begin
                    if(shift!==left || shift!==reference)$fatal(1,"right serial decode mismatch");
                    frames=frames+1;reference=dut.u_top.g_pt8211.u_pt8211.frame_data;
                end
                shift={15'd0,din};bits=1;
            end
            prev_ws=ws;
        end
    end
    task byte_tx;input [7:0] value;integer k;
      begin @(negedge clk);rx=0;#8680;
        for(k=0;k<8;k=k+1)begin rx=value[k];#8680;end rx=1;#8680;end
    endtask
    task cmd;input string value;integer k,before_count;
      begin before_count=accepted;for(k=0;k<value.len();k=k+1)byte_tx(value[k]);byte_tx(13);
        #1000000;if(accepted!=before_count+1)$fatal(1,"UART command count %s",value);end
    endtask
    task wait_ticks;input integer count;
      begin repeat(count)begin @(posedge dut.u_top.sample_tick);@(negedge dut.u_top.sample_tick);end end
    endtask
    initial begin
        #100000;rst=1;wait(!dut.u_top.rst);#3000000;monitor=1;
        cmd("D0");wait_ticks(1600);
        cmd("M1");cmd("T0");cmd("N69");wait_ticks(600);
        if(dut.u_top.v_gate==0 || dut.u_top.final_sample===16'd0)$fatal(1,"A4 missing");
        if(dut.u_top.timbre_target!=0)$fatal(1,"T0 not applied");
        cmd("T255");wait_ticks(300);
        if(dut.u_top.timbre_target!=255 || dut.u_top.u_xf.weight_state!=255)$fatal(1,"T255 not applied");
        cmd("X");wait_ticks(1600);
        cmd("N60");cmd("N64");cmd("N67");cmd("N71");wait_ticks(600);
        if(dut.u_top.v_gate!==4'b1111)$fatal(1,"four voice chord missing");
        cmd("M0");wait_ticks(300);if(dut.u_top.final_sample!==16'd0)$fatal(1,"mute failed");
        cmd("M1");wait_ticks(300);if(dut.u_top.v_gate!==15)$fatal(1,"mute released chord");
        cmd("X");wait_ticks(2000);if(dut.u_top.v_gate!==0 || dut.u_top.final_sample!==16'd0)$fatal(1,"panic release failed");
        if(frames<6000 || ticks<6000 || !pa)$fatal(1,"insufficient decoded frames or PA disabled");
        $display("PASS tb_board_only: commands=%0d decoded_frames=%0d neutral_bend_ticks=%0d; UART, 4 voices, timbre, mute, release",accepted,frames,ticks);
        $finish;
    end
    initial begin #500000000;$fatal(1,"timeout");end
endmodule
