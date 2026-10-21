`timescale 1ns/1ps
module tb_hid_repeat_review;
reg clk=0; always #5 clk=~clk;
reg rst=1,rv=0,manual_flush=0,timeout=0,notify=0;
reg [63:0] report=0;
wire valid,panic,tv,toggle,up,down,overflow;
wire [15:0] word;wire [7:0] timbre;wire [6:0] base;wire [3:0] held;
reg instrument_change=0;
always @(posedge clk) instrument_change<=toggle;
hid_keymap dut(.clk(clk),.rst(rst),.report_valid(rv),.report(report),
 .flush(manual_flush|instrument_change),.link_timeout(timeout),.device_notify(notify),
 .ev_valid(valid),.ev_word(word),.ev_ready(1'b1),.panic(panic),
 .timbre_valid(tv),.timbre_value(timbre),.instr_toggle(toggle),.vol_up(up),.vol_down(down),
 .base_note(base),.held_count(held),.overflow(overflow));
integer toggles=0,ups=0,downs=0,ons=0,offs=0,i,baseline;
always @(posedge clk)if(!rst)begin
 if(toggle)toggles=toggles+1;if(up)ups=ups+1;if(down)downs=downs+1;
 if(valid)begin if(word[15])ons=ons+1;else offs=offs+1;end
end
task send;
 input [7:0] a,b;
 begin
  @(negedge clk);report={32'd0,b,a,16'd0};rv=1;
  @(negedge clk);rv=0;repeat(40)@(negedge clk);
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 // Instrument change arrives while the report is still being scanned.
 send(8'h3f,8'h14);
 if(toggles!=1 || held!=0)$fatal(1,"first F6 failed count=%0d held=%0d",toggles,held);
 baseline=ons;
 for(i=0;i<4;i=i+1)begin
  send(8'h3f,8'h14);
  if(toggles!=1 || ons!=baseline || held!=0)
   $fatal(1,"held F6 report retriggered count=%0d note_ons=%0d held=%0d",toggles,ons,held);
 end
 // Slot reordering cannot turn a held key into a second press.
 send(8'h14,8'h3f);
 if(toggles!=1)$fatal(1,"slot reorder retriggered F6");
 send(0,0);send(8'h3f,0);
 if(toggles!=2)$fatal(1,"released F6 did not rearm count=%0d",toggles);
 send(0,0);send(8'h52,0);repeat(3)send(8'h52,0);
 if(ups!=1)$fatal(1,"held Up repeated count=%0d",ups);
 send(0,0);send(8'h51,0);repeat(3)send(8'h51,0);
 if(downs!=1)$fatal(1,"held Down repeated count=%0d",downs);
 send(0,0);send(8'h14,0);baseline=ons;
 @(negedge clk);manual_flush=1;@(negedge clk);manual_flush=0;
 repeat(4)@(negedge clk);
 repeat(3)send(8'h14,0);
 if(ons!=baseline || held!=0)$fatal(1,"flush rearmed a held note");
 send(0,0);send(8'h14,0);
 if(ons!=baseline+1 || held!=1)$fatal(1,"released note did not rearm");
 // Disconnect/timeout really forget physical identities for a fresh device.
 baseline=ons;
 @(negedge clk);notify=1;@(negedge clk);notify=0;send(8'h14,0);
 if(ons!=baseline+1)$fatal(1,"device reconnect did not rearm");
 if(overflow)$fatal(1,"unexpected event overflow");
 $display("PASS tb_hid_repeat_review: F6 repeat/reorder/release, Up/Down held, flush-held note suppression, reconnect");
 $finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
