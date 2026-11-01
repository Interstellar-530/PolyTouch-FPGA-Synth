`timescale 1ns/1ps
// Independent coverage: enumerate HID usages, observe events rather than call
// the DUT's mapping function. Check uniqueness/range, modifier chords, off
// identities after transpose, duplicate slots and FIFO backpressure/wrap.
module tb_hid_full_keyboard;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, valid=0, flush=0, ready=1;
    reg [63:0] report=0;
    wire ev_valid, overflow;
    wire [15:0] ev_word;
    wire [3:0] held;
    wire [6:0] base;
    hid_keymap dut(.clk(clk),.rst(rst),.report_valid(valid),.report(report),
        .flush(flush),.link_timeout(1'b0),.device_notify(1'b0),
        .ev_valid(ev_valid),.ev_word(ev_word),.ev_ready(ready),
        .base_note(base),.held_count(held),.overflow(overflow));
    reg [15:0] log[0:2047];
    integer ne=0, rd=0;
    always @(posedge clk) if(ev_valid && ready) begin log[ne]=ev_word; ne=ne+1; end

    task rpt;
        input [7:0] mods,k0,k1,k2,k3,k4,k5;
        begin
            @(negedge clk);report={k5,k4,k3,k2,k1,k0,8'd0,mods};valid=1;
            @(negedge clk);valid=0;
            repeat(50) @(negedge clk);
        end
    endtask
    task check_ev;
        input on;
        input [6:0] note;
        begin
            if(rd>=ne || log[rd] !== {on,note,8'd100})
                $fatal(1,"event %0d got %h expected on=%b note=%0d ne=%0d",rd,log[rd],on,note,ne);
            rd=rd+1;
        end
    endtask
    task quiet;
        begin if(ne!=rd) $fatal(1,"unexpected events %0d",ne-rd); end
    endtask
    reg [127:0] seen=0;
    reg [6:0] n;
    integer u, count=0, before_n, k;
    initial begin
        repeat(5) @(negedge clk);rst=0;
        // All non-control ordinary physical usages in a standard full keyboard.
        for(u=4;u<=99;u=u+1) begin
            if(u!=41 && u!=44 && u!=50 && !(u>=58 && u<=65) && u!=75 && u!=78 &&
               u!=81 && u!=82 && u!=83) begin
                rpt(0,u[7:0],0,0,0,0,0);
                if(ne!=rd+1 || log[rd][15]!==1'b1) $fatal(1,"unmapped usage %h",u);
                n=log[rd][14:8];
                if(n<21 || n>108 || seen[n]) $fatal(1,"range/alias usage=%h note=%0d",u,n);
                seen[n]=1;count=count+1;
                check_ev(1,n);
                rpt(0,0,0,0,0,0,0);check_ev(0,n);quiet();
            end
        end
        for(u=0;u<8;u=u+1) begin
            rpt(8'h01<<u,0,0,0,0,0,0);
            if(ne!=rd+1) $fatal(1,"modifier missing %0d",u);
            n=log[rd][14:8];
            if(n!=(40+u) || seen[n]) $fatal(1,"modifier note %0d",n);
            seen[n]=1;count=count+1;check_ev(1,n);
            rpt(0,0,0,0,0,0,0);check_ev(0,n);quiet();
        end
        if(count!=88 || seen[108:21]!=={88{1'b1}}) $fatal(1,"coverage count=%0d",count);

        // 6 ordinary + 8 modifier bits: 14 independent source identities.
        rpt(8'hFF,8'h14,8'h1A,8'h08,8'h15,8'h17,8'h1C);
        if(held!=14 || ne!=rd+14) $fatal(1,"14-key extraction held=%0d",held);
        rd=ne;before_n=ne;
        rpt(8'hFF,8'h1C,8'h17,8'h15,8'h08,8'h1A,8'h14);
        if(ne!=before_n) $fatal(1,"reordered report retriggered");
        rpt(0,0,0,0,0,0,0);
        if(held!=0 || ne!=rd+14) $fatal(1,"14-key release missing");rd=ne;

        rpt(0,8'h14,8'h14,8'h14,0,0,0);check_ev(1,60);
        if(held!=1) $fatal(1,"duplicate physical key counted multiple times");
        rpt(0,0,8'h14,0,0,0,0);quiet();
        rpt(0,0,0,0,0,0,0);check_ev(0,60);

        // Hold both ends of the keyboard across transpose; release old pitches.
        rpt(1,8'h45,0,0,0,0,0);check_ev(1,108);check_ev(1,40);
        rpt(1,8'h45,8'h4B,0,0,0,0);quiet();
        if(base!=72) $fatal(1,"transpose failed");
        rpt(0,0,0,0,0,0,0);check_ev(0,108);check_ev(0,40);
        rpt(0,8'h4B,0,0,0,0,0);rpt(0,0,0,0,0,0,0);
        if(base!=84) $fatal(1,"second transpose failed");
        rpt(0,8'h45,0,0,0,0,0);quiet(); // MIDI132 rejected, never wraps
        rpt(0,0,0,0,0,0,0);quiet();
        rpt(0,8'h4E,0,0,0,0,0);rpt(0,0,0,0,0,0,0);
        rpt(0,8'h4E,0,0,0,0,0);rpt(0,0,0,0,0,0,0);

        // Fill 32 entries, pause consumer, then ensure the stalled releases
        // eventually arrive once each, in order, across pointer wrap.
        ready=0;
        for(k=0;k<16;k=k+1) begin
            rpt(0,8'h14,0,0,0,0,0);rpt(0,0,0,0,0,0,0);
        end
        if(dut.count!=32) $fatal(1,"FIFO not full count=%0d",dut.count);
        rpt(0,8'h14,0,0,0,0,0);
        rpt(0,0,0,0,0,0,0);
        ready=1;repeat(200) @(negedge clk);
        for(k=0;k<17;k=k+1) begin check_ev(1,60);check_ev(0,60);end
        quiet();
        if(held!=0 || overflow) $fatal(1,"backpressure dropped state");
        $display("PASS tb_hid_full_keyboard: 88 unique notes A0-C8, 14 report identities, dedup, transpose, backpressure/wrap");
        $finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
