`timescale 1ns/1ps
module tb_timbre_uart;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,rx=1;wire tx,tv;wire [7:0] value;
    integer valid=0,ok=0,err=0,n,before_valid,before_err;
    uart_ctrl #(.CLK_HZ(1000000),.BAUD(100000)) dut(
        .clk(clk),.rst(rst),.uart_rx(rx),.uart_tx(tx),.timbre_valid(tv),.timbre_value(value));
    always @(negedge clk) begin
        if(tv)valid=valid+1;if(dut.reply_ok)ok=ok+1;if(dut.reply_err)err=err+1;
        if(tv && (dut.ev_valid || dut.panic || dut.demo_on || dut.demo_off)) $fatal(1,"T emitted note/mode event");
    end
    task byte_tx; input [7:0] c;integer bitno;
        begin @(negedge clk);rx=0;repeat(10)@(negedge clk);
            for(bitno=0;bitno<8;bitno=bitno+1)begin rx=c[bitno];repeat(10)@(negedge clk);end
            rx=1;repeat(10)@(negedge clk);end
    endtask
    task drain; begin repeat(650)@(negedge clk);end endtask
    task number;input integer k;
        begin if(k>=100)byte_tx("0"+k/100);if(k>=10)byte_tx("0"+(k/10)%10);byte_tx("0"+k%10);end
    endtask
    initial begin
        repeat(5)@(negedge clk);rst=0;
        for(n=0;n<256;n=n+1)begin
            byte_tx((n%2)?"t":"T");number(n);byte_tx(13);byte_tx(10);drain();
            if(valid!=n+1 || value!==n || ok!=n+1 || err!=0)$fatal(1,"T command mismatch n=%d",n);
        end
        before_valid=valid;before_err=err;
        byte_tx("T");byte_tx(13);drain();
        byte_tx("T");number(256);byte_tx(13);drain();
        byte_tx("T");number(999);byte_tx(13);drain();
        byte_tx("T");byte_tx("0");byte_tx("0");byte_tx("0");byte_tx("0");byte_tx(13);drain();
        byte_tx("T");byte_tx("1");byte_tx("N");byte_tx("2");byte_tx(13);drain();
        if(valid!=before_valid || err-before_err!=5 || value!=255)$fatal(1,"invalid command changed state");
        if(dut.reply_drop_count!=0)$fatal(1,"reply lost");
        $display("PASS tb_timbre_uart: all 256 values, mixed case, CRLF once, 5 format/range checks, independent note/mode path");$finish;
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
