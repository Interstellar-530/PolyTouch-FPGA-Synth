`timescale 1ns/1ps
// A2 table bench: reads all 48 instrument banks back through the real Gowin
// pROM model and compares them with the frozen expectation header.
//
// What this proves that the offline verifier cannot: the vendor initialisation,
// the bank/address mapping of instrument_rom_banks, the CE-gated group mux and
// the pROM read latency all deliver the table bytes the metadata claims.
//
// Checks per bank: FNV-1a over the 512 signed samples, peak magnitude, DC term,
// and the periodic seam against the largest interior step.  The sine table is
// additionally compared against an analytic full-scale sine so the harness
// itself is not trusted blindly.
module tb_opt_a_tables;
 localparam integer BANKS = 48;
 localparam integer DEPTH = 512;
 reg clk = 0;
 always #6.781684 clk = ~clk;
 reg rst = 1;
 reg ce = 0;
 reg [5:0] bank_sel = 0;
 reg [8:0] addr_sel = 0;
 wire [15:0] dout;
 wire [15:0] sine_dout;

 instrument_rom_banks u_banks (
  .clk(clk), .ce(ce), .rst(rst), .bank(bank_sel), .addr(addr_sel), .dout(dout));
 gowin_prom_wave_sine u_sine (
  .clk(clk), .ce(ce), .rst(rst), .addr(addr_sel), .dout(sine_dout));

 reg [31:0] exp_fnv [0:BANKS-1];
 integer exp_peak [0:BANKS-1];
 integer exp_sum [0:BANKS-1];
 integer TBL_COUNT = 0;

 task tbl_expect(input integer idx, input [31:0] fnv, input integer peak,
                 input integer sum);
  begin
   exp_fnv[idx] = fnv; exp_peak[idx] = peak; exp_sum[idx] = sum;
  end
 endtask

 task read_table(input [5:0] bank, input [8:0] addr, output [15:0] value);
  begin
   @(negedge clk);
   bank_sel = bank; addr_sel = addr; ce = 1'b1;
   @(negedge clk);
   ce = 1'b0;
   value = dout;
  end
 endtask

 task read_sine(input [8:0] addr, output [15:0] value);
  begin
   @(negedge clk);
   addr_sel = addr; ce = 1'b1;
   @(negedge clk);
   ce = 1'b0;
   value = sine_dout;
  end
 endtask

 function [31:0] fnv_step(input [31:0] state, input [15:0] value);
  begin
   fnv_step = (state ^ {16'd0, value}) * 32'd16777619;
  end
 endfunction

 integer bank_index, index;
 integer peak, total, dc, wrap_step, interior_step;
 reg [31:0] hash;
 reg [15:0] value, previous, first_value;
 reg signed [15:0] signed_value;
 integer checked, errors;

 initial begin
  `include "sim/opt_a/table_expect.vh"
  repeat (4) @(negedge clk);
  rst = 0;
  repeat (2) @(negedge clk);
  if (TBL_COUNT !== BANKS) $fatal(1, "expectation header has %0d banks", TBL_COUNT);
  checked = 0;
  errors = 0;
  for (bank_index = 0; bank_index < BANKS; bank_index = bank_index + 1) begin
   hash = 32'h811C9DC5;
   peak = 0;
   total = 0;
   interior_step = 0;
   for (index = 0; index < DEPTH; index = index + 1) begin
    bank_sel = bank_index;
    addr_sel = index;
    read_table(bank_index, index, value);
    hash = fnv_step(hash, value);
    signed_value = value;
    if (signed_value < 0 ? -signed_value > peak : signed_value > peak)
     peak = (signed_value < 0) ? -signed_value : signed_value;
    total = total + signed_value;
    if (index == 0) first_value = value;
    else begin
     signed_value = value - previous;
     if (signed_value < 0 ? -signed_value > interior_step : signed_value > interior_step)
      interior_step = (signed_value < 0) ? -signed_value : signed_value;
    end
    previous = value;
   end
   // Periodic seam: last sample back to the first.
   signed_value = first_value - previous;
   wrap_step = (signed_value < 0) ? -signed_value : signed_value;
   if (hash !== exp_fnv[bank_index]) begin
    $display("FATAL bank %0d fnv %08X expected %08X", bank_index, hash,
             exp_fnv[bank_index]);
    errors = errors + 1;
   end
   if (peak !== exp_peak[bank_index]) begin
    $display("FATAL bank %0d peak %0d expected %0d", bank_index, peak,
             exp_peak[bank_index]);
    errors = errors + 1;
   end
   // DC term: the offline verifier bounds |mean| <= 1 LSB, i.e. |sum| <= 512.
   dc = total;
   if (dc < 0) dc = -dc;
   if (dc > DEPTH) begin
    $display("FATAL bank %0d DC %0d exceeds 1 LSB", bank_index, total);
    errors = errors + 1;
   end
   if (wrap_step > interior_step) begin
    $display("FATAL bank %0d wrap step %0d above interior %0d", bank_index,
             wrap_step, interior_step);
    errors = errors + 1;
   end
   checked = checked + 1;
  end
  if (errors != 0) $fatal(1, "A2 table integrity failed for %0d banks", errors);

  // The sine table must be the analytic full-scale sine, phase 0 at address 0.
  read_sine(9'd0, value);
  if (value !== 16'h0000) $fatal(1, "sine[0] = %04x", value);
  read_sine(9'd128, value);
  if (value !== 16'h7FFF) $fatal(1, "sine[128] = %04x", value);
  read_sine(9'd256, value);
  if (value !== 16'h0000) $fatal(1, "sine[256] = %04x", value);
  read_sine(9'd384, value);
  if (value !== 16'h8001) $fatal(1, "sine[384] = %04x", value);
  // A full-scale sine at DEPTH=512: x[64] = round(32767*sin(pi/4)) = 23170.
  read_sine(9'd64, value);
  if (value !== 16'd23170) $fatal(1, "sine[64] = %04x expected 0x5A82", value);

  $display("METRIC a2_tables banks=%0d samples=%0d peak_checked=1 dc_checked=1 seam_checked=1",
           checked, checked * DEPTH);
  $display("PASS tb_opt_a_tables: 48 banks match the frozen init, sine analytic, no seam or DC");
  $finish;
 end

 initial begin
  #2000000;
  $fatal(1, "tb_opt_a_tables timeout");
 end
endmodule
