`timescale 1ns/1ps
module tb_note_ownership_top;
    reg clk=0;always #40.690104 clk=~clk;
    reg kr=0,rx=1;reg[11:0]keys=12'hfff;wire cs,sck,mosi,miso;integer cases=0;
    top #(.AUDIO_IF(1),.PRESSURE_ENABLE(0)) dut(.clk_27m(1'b0),.clk_12m288(clk),.key_rst(kr),
        .key_s1(1'b1),.key_s2(1'b1),.uart_rx(rx),.gpio_key_n(keys),
        .adc_cs_n(cs),.adc_sck(sck),.adc_mosi(mosi),.adc_miso(miso));
    mcp3208_model adc(cs,sck,mosi,miso,12'd3200,12'd2048,12'd0,12'd0,12'd0,12'd0,12'd0,12'd0);
    task byte_tx;input[7:0]data;integer bitno;
        begin @(negedge clk);rx=0;#8680;for(bitno=0;bitno<8;bitno=bitno+1)begin rx=data[bitno];#8680;end rx=1;#8680;end
    endtask
    task command;input[7:0]op,tens,ones;
        begin byte_tx(op);byte_tx(tens);byte_tx(ones);byte_tx(13);repeat(3)@(posedge dut.sample_tick);@(negedge clk);end
    endtask
    task require_held;
        integer v,found;
        begin found=0;for(v=0;v<4;v=v+1)if(dut.v_gate[v] && dut.v_note[v*7+:7]==60)found=found+1;
            if(found!=1)$fatal(1,"held C4 must have one voice, found=%0d",found);
        end
    endtask
    initial begin
        #100000;kr=1;wait(!dut.rst);command("D","0"," ");
        command("N","6","0");keys[0]=0;#1200000;require_held();
        command("O","6","0");require_held();cases=cases+1;
        keys[0]=1;#3200000;if(dut.v_gate!=0)$fatal(1,"last GPIO release lost");cases=cases+1;
        keys[0]=0;#1200000;command("N","6","0");require_held();
        keys[0]=1;#3200000;require_held();cases=cases+1;
        command("O","6","0");if(dut.v_gate!=0)$fatal(1,"last UART release lost");cases=cases+1;
        keys[0]=0;#1200000;command("N","6","0");command("X"," "," ");
        if(dut.v_gate!=0)$fatal(1,"panic did not clear mixed owners");
        command("N","6","0");command("O","6","0");
        if(dut.v_gate!=0)$fatal(1,"stale GPIO owner survived panic");cases=cases+1;
        $display("PASS tb_note_ownership_top: real UART/GPIO overlap, both release orders, final release and panic/rearm; cases=%0d",cases);$finish;
    end
    initial begin #60000000;$fatal(1,"ownership top timeout");end
endmodule
