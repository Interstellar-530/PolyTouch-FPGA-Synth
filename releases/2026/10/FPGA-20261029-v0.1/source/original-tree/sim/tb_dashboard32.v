`timescale 1ns/1ps
module tb_dashboard32;
    reg clk=0,rst=1,de=1;
    reg [10:0] x=0;
    reg [9:0] y=0;
    reg [63:0] st=64'h600402c8324f0000;
    reg [31:0] mask=0;
    wire [23:0] rgb;
    integer i,n,fd,pix;
    reg [4095:0] ppm_path;
    always #5 clk=~clk;
    dashboard_renderer_1024 dut(.pix_clk(clk),.rst(rst),.de(de),.x(x),.y(y),.st(st),
        .voice_mask(mask),.waveform({16{16'h3456}}),.spectrum(64'h4030206040503020),.lissajous(64'h8040201008040201),
        .rgb_r(rgb[23:16]),.rgb_g(rgb[15:8]),.rgb_b(rgb[7:0]));
    task count_text;
        input integer count;
        begin
            st[15:12]=count&15;st[61:60]=count>>4;st[62]=1;
            x=900;y=268;#1;if(dut.u_text.char_code!=48+count/10)$fatal(1,"count tens %0d",count);
            x=916;#1;if(dut.u_text.char_code!=48+count%10)$fatal(1,"count ones %0d",count);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst=0;
        count_text(0);count_text(6);count_text(8);count_text(16);count_text(32);
        for(i=0;i<12;i=i+1)begin
            @(negedge clk);st[11:0]=12'b1<<i;x=40+i*56+8;y=500;
            repeat(6)@(posedge clk);#1;
            if(rgb!==24'h20d0f0)$fatal(1,"active note %0d pixel=%h",i,rgb);
            @(negedge clk);st[11:0]=0;repeat(6)@(posedge clk);#1;
            if(rgb!==24'h1b2a49)$fatal(1,"inactive note %0d pixel=%h",i,rgb);
        end
        @(negedge clk);x=68;y=368;st[11:0]=1;
        repeat(6)@(posedge clk);#1;
        if(rgb!==24'he8f0ff)$fatal(1,"waveform dot %h",rgb);
        for(i=0;i<32;i=i+1) begin
            @(negedge clk);mask=32'b1<<i;x=604+(i%4)*32;y=180+(i/4)*32;
            repeat(6)@(posedge clk);#1;
            if(rgb!==24'h40e090)$fatal(1,"voice activity slot %0d",i);
        end
        x=24;y=552;#1;if(dut.u_text.char_code!="3")$fatal(1,"voice metric");
        x=216;#1;if(dut.u_text.char_code!="M")$fatal(1,"touch metric");
        x=264;y=576;#1;if(dut.u_text.char_code!="M")$fatal(1,"FSR metric");
        // An optional real RTL raster export for visual review, not an artist's mockup.
        if($value$plusargs("UI_PPM_FILE=%s",ppm_path))begin
            fd=$fopen(ppm_path,"wb");if(!fd)$fatal(1,"PPM open failed");
            $fwrite(fd,"P6\n1024 600\n255\n");mask=32'hffffffff;count_text(32);st[41]=1;st[59]=1;
            for(pix=0;pix<1024*600+3;pix=pix+1)begin
                @(negedge clk);x=pix%1024;y=pix/1024;de=(pix<1024*600);
                @(posedge clk);#1;
                if(pix>=3)$fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
            end
            $fclose(fd);
        end
        $display("PASS tb_dashboard32: note field, waveform dots and 32 activity slots, metrics and 00/06/08/16/32 voice counts");$finish;
    end
endmodule
