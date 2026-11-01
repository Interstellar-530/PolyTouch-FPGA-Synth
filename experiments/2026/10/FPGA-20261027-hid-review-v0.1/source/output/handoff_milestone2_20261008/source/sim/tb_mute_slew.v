`timescale 1ns/1ps
module tb_mute_slew;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,update=0,mute=0;reg[11:0]pressure=4095;
    wire signed[15:0]value[0:3];wire[3:0]request;
    wire signed[17:0]ma[0:3],mb[0:3];reg signed[35:0]product[0:3];
    integer expected_gain[0:3];integer n,j,target,expected,frames=0,fd=0;reg[2047:0]capture;
    genvar g;
    generate for(g=0;g<4;g=g+1)begin:cases
        always @(posedge clk)if(request[g])product[g]<=ma[g]*mb[g];
        global_crossfade #(.PRESSURE_GAIN_ENABLE(g/2),.MUTE_SLEW_ENABLE(1),.SHARED_MULT_ENABLE(g%2),.MASTER_VOLUME_SHIFT(2)) dut(
            .clk(clk),.rst(rst),.update(update),.clear_clip(1'b0),.mix_weight(8'd128),
            .sine_sum(19'sd100000),.bright_sum(19'sd100000),.sample_out(value[g]),
            .pressure_enable(1'b1),.pressure_level(pressure),.mute(mute),
            .mult_request(request[g]),.mult_operand_a(ma[g]),.mult_operand_b(mb[g]),.mult_result(product[g]));
    end endgenerate
    task frame;
        begin
            for(j=0;j<4;j=j+1)begin
                target=mute?0:((j/2)==0?4096:(pressure>=3200?4096:(pressure<=128?1024:1024+pressure-128)));
                if(target>expected_gain[j]+32)expected_gain[j]=expected_gain[j]+32;
                else if(expected_gain[j]>target+32)expected_gain[j]=expected_gain[j]-32;
                else expected_gain[j]=target;
            end
            update=1;@(negedge clk);update=0;repeat(4)@(negedge clk);
            for(j=0;j<4;j=j+1)begin
                expected=(24902*expected_gain[j])>>>12;
                if(value[j]!==expected)$fatal(1,"mute slew path=%0d frame=%0d actual=%0d expected=%0d",j,frames,value[j],expected);
            end
            if(fd)$fwrite(fd,"%0d,%0d,%0d,%0d\n",frames,mute,value[1],mute?0:24902);
            frames=frames+1;repeat(2)@(negedge clk);
        end
    endtask
    initial begin
        if($value$plusargs("CAPTURE=%s",capture))begin fd=$fopen(capture,"w");if(!fd)$fatal(1,"capture");$fwrite(fd,"frame,mute,smooth,hard\n");end
        for(j=0;j<4;j=j+1)begin product[j]=0;expected_gain[j]=4096;end
        repeat(4)@(negedge clk);rst=0;
        repeat(32)frame();mute=1;repeat(160)frame();
        for(j=0;j<4;j=j+1)if(value[j]!==0)$fatal(1,"mute did not reach zero");
        mute=0;repeat(160)frame();pressure=0;repeat(160)frame();
        mute=1;repeat(160)frame();pressure=4095;repeat(32)frame();
        for(j=0;j<4;j=j+1)if(value[j]!==0)$fatal(1,"pressure unmuted the VCA");
        mute=0;repeat(160)frame();
        // Rapid command reversals must slew from the current gain, not restart.
        for(n=0;n<64;n=n+1)begin mute=~mute;repeat(3)frame();end
        if(fd)$fclose(fd);
        $display("PASS tb_mute_slew: frames=%0d local/shared, pressure on/off, exact slew, pressure during mute and rapid reversals; max ramp=128 frames",frames);$finish;
    end
    initial begin #1000000;$fatal(1,"mute slew timeout");end
endmodule
