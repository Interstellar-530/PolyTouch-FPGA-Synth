`timescale 1ns/1ps
module tb_note_ownership;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,clear=0,manual=1,valid=0,on_event=0,uart=0;reg[6:0]note=60;wire forwarded;
    reg[127:0]ref_uart=0,ref_gpio=0;integer checks=0,k;reg expected;
    note_ownership dut(.clk(clk),.rst(rst),.clear(clear),.manual_mode(manual),.event_valid(valid),.event_on(on_event),.source_uart(uart),.note(note),.forward_valid(forwarded));
    task event_send;input source,on;input[6:0]key;
        begin
            @(negedge clk);uart=source;on_event=on;note=key;valid=1;
            expected=!clear && (!manual || on || !(source?ref_gpio[key]:ref_uart[key]));#1;
            if(forwarded!==expected)$fatal(1,"ownership decision source=%0d on=%0d note=%0d",source,on,key);
            if(manual)begin if(source)ref_uart[key]=on;else ref_gpio[key]=on;end
            @(posedge clk);#1;@(negedge clk);valid=0;checks=checks+1;
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=0;
        event_send(1,1,60);event_send(0,1,60);event_send(1,0,60);event_send(0,0,60);
        event_send(0,1,64);event_send(1,1,64);event_send(0,0,64);event_send(1,0,64);
        for(k=0;k<2048;k=k+1)event_send($random,$random,60+($urandom%12));
        clear=1;@(posedge clk);#1;ref_uart=0;ref_gpio=0;@(negedge clk);clear=0;
        event_send(1,0,60);event_send(0,0,64);
        manual=0;event_send(0,1,80);event_send(0,0,80);manual=1;
        if(dut.uart_held!==ref_uart || dut.gpio_held!==ref_gpio[71:60])$fatal(1,"ownership state reference");
        $display("PASS tb_note_ownership: %0d source events, both release orders, repeated on/off, clear and demo bypass",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"ownership timeout");end
endmodule
