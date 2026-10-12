`timescale 1ns/1ps
// Read-only regression against the audited ADSR. No production RTL is changed.
module tb_adsr_release_audit;
  reg clk = 0;
  reg rst = 1;
  reg gate = 0;
  wire [15:0] env;
  wire idle;
  reg [15:0] held_env;
  always #5 clk = ~clk;
  adsr dut(.clk(clk), .rst(rst), .sample_tick(1'b1),
           .gate(gate), .env(env), .idle(idle));
  initial begin
    repeat(4) @(negedge clk);
    rst = 0;
    gate = 1;
    repeat(1800) @(negedge clk);
    if (env == 0 || idle) $fatal(1, "setup failed: note did not attack");
    held_env = env;
    $display("Before note-off: env=%0d idle=%b state=%0d", env, idle, dut.state);
    gate = 0;
    // Full-scale release should finish in ceil(65535/48)+2 sample ticks.
    repeat(2000) @(negedge clk);
    $display("After 2000 release ticks: env=%0d idle=%b state=%0d held_env=%0d",
             env, idle, dut.state, held_env);
    if (env !== 0 || idle !== 1'b1)
      $fatal(1, "ADSR note-off never drains the envelope");
    $display("PASS tb_adsr_release_audit");
    $finish;
  end
  initial begin
    #100000;
    $fatal(1, "timeout");
  end
endmodule
