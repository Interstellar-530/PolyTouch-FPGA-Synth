`timescale 1ns/1ps
module tb_ui_status32;
    reg clk=0,rst=1;
    reg [31:0] gates=0;
    reg [223:0] notes=0;
    reg [255:0] velocities={32{8'd100}};
    wire [63:0] status;
    wire [31:0] mask;
    integer i,n;
    always #5 clk=~clk;
    ui_status_export #(.VOICES(32),.TICK_DIV(128),.TRANSPORT_ENABLE(1)) dut(
        .clk(clk),.rst(rst),.v_gate(gates),.v_note(notes),.v_vel(velocities),
        .pressure_level(12'd1024),.demo_mode(1'b0),.muted(1'b0),.piano_mode(1'b1),.guitar_mode(1'b0),
        .chord_set(1'b1),.show_timbre(1'b0),.instrument_id(2'b10),.tempo_sel(2'd0),
        .timbre_target(8'd252),.piano_tone(3'd2),.paused(1'b0),.status(status),.active_mask(mask),.status_toggle());
    initial begin
        for(i=0;i<32;i=i+1)notes[i*7 +: 7]=36+i;
        repeat(4) @(negedge clk);rst=0;
        for(n=0;n<=32;n=n+1)begin
            gates=(33'b1<<n)-1;
            repeat(260) @(negedge clk);
            if({status[61:60],status[15:12]}!==n || mask!==gates || !status[62])
                $fatal(1,"status count/mask wrap n=%0d got=%0d mask=%h",n,{status[61:60],status[15:12]},mask);
            if(n && !status[(35+n)%12]) $fatal(1,"octave-independent pitch class missing");
        end
        if(!status[41] || !status[59] || status[44])$fatal(1,"pedal/song status fields");
        $display("PASS tb_ui_status32: every count 0..32, true slot mask, pitch classes, transport fields");$finish;
    end
endmodule
