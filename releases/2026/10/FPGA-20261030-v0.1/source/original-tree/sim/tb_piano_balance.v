`timescale 1ns/1ps
module tb_piano_balance;
    reg clk=0,rst=1;
    always #5 clk=~clk;
    wire [15:0] envelope;
    wire valid;
    voice_sched32 #(.HIGH_NOTE_BALANCE(1)) dut(
        .clk(clk),.rst(rst),.sample_tick(1'b0),.instrument(1'b0),
        .piano_tone(3'd0),.ev_valid(1'b0),.ev_on(1'b0),
        .ev_note(7'd0),.ev_vel(8'd0),.ev_ready(),
        .cfg_voice(),.cfg_increment(),.cfg_envelope(envelope),
        .cfg_velocity(),.cfg_retrigger(),.cfg_param(),.cfg_mask(),
        .cfg_valid(valid),.cfg_ready(1'b1),.active_count(),
        .bend_ratio(17'd65536),.voice_active(),.voice_notes(),.voice_velocities());
    task check_gain;
        input [6:0] pitch;
        input [8:0] expected;
        begin
            if(dut.piano_note_gain_q8(pitch)!==expected)
                $fatal(1,"gain curve note %0d expected %0d",pitch,expected);
        end
    endtask
    initial begin
        check_gain(72,256);check_gain(73,251);check_gain(78,228);
        check_gain(84,202);check_gain(96,160);check_gain(99,152);
        check_gain(127,152);
        repeat(3)@(negedge clk);rst=0;
        // Exercise the actual configuration register for the C6 = MIDI84 case.
        @(negedge clk);
        dut.snap_valid=1;dut.snap_phase=2;dut.snap_note=84;
        dut.snap_env=16'd40000;dut.snap_vel=100;dut.snap_mask=3'b001;
        dut.cfg_pend=0;dut.instrument_q=0;
        @(posedge clk);#1;
        if(!valid || envelope!==16'd31563)
            $fatal(1,"balanced piano envelope expected 31563 got %0d",envelope);
        @(negedge clk);
        dut.snap_valid=1;dut.snap_phase=2;dut.snap_note=84;
        dut.snap_env=16'd40000;dut.instrument_q=1;dut.cfg_pend=0;
        @(posedge clk);#1;
        if(envelope!==16'd40000)
            $fatal(1,"guitar envelope changed by piano balance");
        $display("PASS tb_piano_balance: Q8 curve, C6 envelope and guitar bypass");
        $finish;
    end
endmodule
