`timescale 1ns/1ps
module tb_timbre_audio;
    reg clk=0; always #5 clk=~clk;
    reg rst=1,update=0; reg [7:0] weight=64;
    reg signed [18:0] a=0,b=0;
    wire signed [15:0] plain,smooth;
    wire [31:0] clips1,clips2;
    wire ce1,ce2;
    global_crossfade direct(clk,rst,update,1'b0,weight,a,b,plain,clips1,ce1,1'b0,12'd0,,,,36'd0);
    global_crossfade #(.TIMBRE_SLEW_ENABLE(1)) slew(clk,rst,update,1'b0,weight,a,b,smooth,clips2,ce2,1'b0,12'd0,,,,36'd0);
    integer w,j,frames=0,state=64,expected_state,next_state,reference,previous,max_delta=0,delta,abrupt_delta;
    integer fd,p,n; reg [7:0] presets[0:3];
    reg signed [15:0] sine[0:511],bright[0:511];
    reg [2047:0] capture;
    reg signed [63:0] x,y,z;
    function integer ref_sample;
        input integer aa,bb,ww;
        reg signed [63:0] r;
        begin r=aa; r=r*(255-ww); r=r+$signed(bb)*$signed(ww)+127;
            r=(r>>>8)>>>1; ref_sample=(r>32767)?32767:(r < -32768)?-32768:r; end
    endfunction
    task frame;
        begin
            @(negedge clk); update=1;
            next_state=(weight>state)?state+1:(weight<state)?state-1:state;
            @(posedge clk); #1;
            reference=ref_sample(a,b,weight);
            if(plain!==reference) $fatal(1,"plain mismatch frame=%d w=%d a=%d b=%d got=%d ref=%d",frames,weight,a,b,plain,reference);
            reference=ref_sample(a,b,next_state);
            if(smooth!==reference || slew.weight_state!==next_state) $fatal(1,"slew reference mismatch");
            state=next_state; frames=frames+1;
            @(negedge clk); update=0;
        end
    endtask
    initial begin
        presets[0]=0; presets[1]=64; presets[2]=160; presets[3]=255;
        repeat(3) @(negedge clk); rst=0;
        for(w=0;w<256;w=w+1) begin
            weight=w;
            for(j=0;j<132;j=j+1) begin
                case(j)
                    0: begin a=-262144;b=262143;end
                    1: begin a=262143;b=-262144;end
                    2: begin a=-262144;b=-262144;end
                    3: begin a=262143;b=262143;end
                    default: begin a=$random;b=$random;end
                endcase
                frame();
            end
        end
        a=12000;b=-8000;weight=0;repeat(255) frame(); previous=smooth;
        abrupt_delta=ref_sample(a,b,255)-ref_sample(a,b,0);if(abrupt_delta<0)abrupt_delta=-abrupt_delta;
        weight=255;
        repeat(255) begin frame();delta=smooth-previous;if(delta<0)delta=-delta;
            if(delta>max_delta)max_delta=delta;previous=smooth;end
        if(max_delta>40 || state!=255) $fatal(1,"control discontinuity bound");
        expected_state=state; repeat(12) @(negedge clk);
        if(slew.weight_state!=expected_state) $fatal(1,"slew moved without valid frame");
        $readmemh("rtl/audio/wave_sine.hex",sine); $readmemh("rtl/audio/wave_bright.hex",bright);
        if($value$plusargs("CAPTURE=%s",capture)) begin
            fd=$fopen(capture,"w");if(!fd)$fatal(1,"capture open failed");
            $fwrite(fd,"weight,index,sample\n");
            for(p=0;p<4;p=p+1) begin
                weight=presets[p];a=0;b=0;repeat(255)frame();
                for(n=0;n<512;n=n+1) begin
                    a=sine[n];b=bright[n];frame();$fwrite(fd,"%0d,%0d,%0d\n",weight,n,smooth);
                end
            end
            $fclose(fd);
        end
        $display("METRIC timbre frames=%0d weights=256 max_control_step=%0d abrupt_control_step=%0d full_sweep_frames=255 variable_multipliers=1",frames,max_delta,abrupt_delta);
        $display("PASS tb_timbre_audio: signed 64-bit reference, opposite/full scale, random sums, slew/hold, preset capture");$finish;
    end
    initial begin #10000000; $fatal(1,"timeout"); end
endmodule
