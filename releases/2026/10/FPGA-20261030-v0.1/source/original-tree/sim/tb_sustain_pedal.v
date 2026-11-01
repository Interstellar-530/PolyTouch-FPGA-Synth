`timescale 1ns/1ps
module tb_sustain_pedal;
    reg clk=0,rst=1,clear=0,pedal=0,valid=0,ready=1;
    reg [15:0] word_in=0;
    wire in_ready,out_valid;
    wire [15:0] word_out;
    integer ons=0,offs=0,lastoff=0;
    always #5 clk=~clk;
    sustain_pedal dut(.clk(clk),.rst(rst),.clear(clear),.pedal(pedal),.in_valid(valid),
        .in_word(word_in),.in_ready(in_ready),.out_valid(out_valid),.out_word(word_out),.out_ready(ready));
    always @(posedge clk) if(out_valid && ready) begin
        if(word_out[15]) ons=ons+1;else begin offs=offs+1;lastoff=word_out[14:8];end
    end
    task send;
        input on;input [6:0] note;
        begin
            @(negedge clk);valid=1;word_in={on,note,8'd100};
            do @(posedge clk); while(!in_ready);
            @(negedge clk);valid=0;
            repeat(3) @(negedge clk);
        end
    endtask
    reg [15:0] held_word;
    initial begin
        repeat(4) @(negedge clk);rst=0;
        send(1,60);send(0,60);
        if(ons!=1 || offs!=1) $fatal(1,"ordinary note off lost");
        pedal=1;send(1,60);send(0,60);send(1,64);send(0,64);
        if(offs!=1) $fatal(1,"pedal did not hold notes");
        send(1,60); // physically re-held note must survive the old deferred off
        ready=0;pedal=0;
        wait(out_valid);held_word=word_out;
        repeat(50) begin @(negedge clk);if(!out_valid || word_out!==held_word)$fatal(1,"release backpressure");end
        ready=1;repeat(140) @(negedge clk);
        if(offs!=2 || lastoff!=64) $fatal(1,"pedal released the wrong note");
        send(0,60);
        if(offs!=3 || lastoff!=60) $fatal(1,"re-held note off lost");
        pedal=1;send(1,67);send(0,67);
        clear=1;@(negedge clk);clear=0;pedal=0;
        repeat(150) @(negedge clk);
        if(offs!=3 || dut.deferred!=0 || dut.held!=0) $fatal(1,"panic retained pedal state");
        $display("PASS tb_sustain_pedal: hold, release, repeat note, held-key exception, backpressure, panic");$finish;
    end
    initial begin #20000;$fatal(1,"sustain timeout");end
endmodule
