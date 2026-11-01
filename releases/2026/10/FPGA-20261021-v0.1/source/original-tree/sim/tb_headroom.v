`timescale 1ns/1ps
module tb_headroom;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,update=0;reg[7:0]weight=0;
    reg signed[18:0]a=0,b=0;
    wire signed[15:0]local_sample,shared_sample;wire[31:0]lc,sc;wire le,se,request;
    wire signed[17:0]ma,mb;reg signed[35:0]product=0;
    always @(posedge clk)if(request)product<=ma*mb;
    global_crossfade #(.PRESSURE_GAIN_ENABLE(1),.MASTER_VOLUME_SHIFT(2)) local_xf(
        .clk(clk),.rst(rst),.update(update),.clear_clip(1'b0),.mix_weight(weight),.sine_sum(a),.bright_sum(b),
        .sample_out(local_sample),.clip_count(lc),.clip_event(le),.pressure_enable(1'b1),.pressure_level(12'd4095));
    global_crossfade #(.PRESSURE_GAIN_ENABLE(1),.MASTER_VOLUME_SHIFT(2),.SHARED_MULT_ENABLE(1)) shared_xf(
        .clk(clk),.rst(rst),.update(update),.clear_clip(1'b0),.mix_weight(weight),.sine_sum(a),.bright_sum(b),
        .sample_out(shared_sample),.clip_count(sc),.clip_event(se),.pressure_enable(1'b1),.pressure_level(12'd4095),
        .mult_request(request),.mult_operand_a(ma),.mult_operand_b(mb),.mult_result(product));
    integer w,j,n,k,frames=0,peak=0,legacy_clips=0,expected,mag;
    reg signed[63:0]numerator,legacy;
    reg signed[15:0]sine[0:511],bright[0:511];reg[7:0]presets[0:3];
    task frame;
        begin
            numerator=a;numerator=numerator*(255-weight);legacy=b;
            numerator=numerator+legacy*weight+127;
            expected=(numerator>>>8)>>>2;
            legacy=(numerator>>>8)>>>1;
            if(legacy>32767 || legacy< -32768)legacy_clips=legacy_clips+1;
            if(expected>32767 || expected< -32768)$fatal(1,"headroom bound violated");
            update=1;@(negedge clk);update=0;
            if(local_sample!==expected)$fatal(1,"local headroom reference");
            repeat(4)@(negedge clk);
            if(shared_sample!==expected || lc!=0 || sc!=0 || se || le)$fatal(1,"shared headroom or clipping");
            mag=expected<0?-expected:expected;if(mag>peak)peak=mag;frames=frames+1;
            repeat(2)@(negedge clk);
        end
    endtask
    initial begin
        presets[0]=0;presets[1]=64;presets[2]=160;presets[3]=255;
        $readmemh("rtl/audio/wave_sine.hex",sine);$readmemh("rtl/audio/wave_bright.hex",bright);
        repeat(4)@(negedge clk);rst=0;
        for(w=0;w<256;w=w+1)begin
            weight=w;
            for(j=0;j<4;j=j+1)begin
                a=(j&1)?19'sd131068:-19'sd131072;b=(j&2)?19'sd131068:-19'sd131072;frame();
            end
        end
        for(j=0;j<4;j=j+1)begin weight=presets[j];
            for(n=0;n<512;n=n+1)begin a=4*$signed(sine[n]);b=4*$signed(bright[n]);frame();end
        end
        for(n=0;n<4096;n=n+1)begin
            a=0;b=0;weight=$random;
            for(k=0;k<4;k=k+1)begin j=$urandom%512;a=a+$signed(sine[j]);b=b+$signed(bright[j]);end
            frame();
        end
        if(peak!=32640 || legacy_clips==0)$fatal(1,"coverage inadequate");
        $display("METRIC headroom frames=%0d weights=256 peak=%0d clipped_frames=0 legacy_clipped_frames=%0d",frames,peak,legacy_clips);
        $display("PASS tb_headroom: signed extrema, all weights, coherent and random-phase four-voice frames, local/shared exact");$finish;
    end
endmodule
