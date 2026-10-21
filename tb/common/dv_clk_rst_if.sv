`timescale 1ns/1ps
// Clock and reset generator shared by all testbenches.  Tests reach it through
// a virtual interface to apply a reset in the middle of traffic.
interface dv_clk_rst_if #(parameter real PERIOD_NS = 10.0) ();
  logic clk   = 1'b0;
  logic rst_n = 1'b0;   // active low
  wire  rst   = ~rst_n; // active high, for DUTs that want it

  always #(PERIOD_NS / 2.0) clk = ~clk;

  initial begin
    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
  end

  // Synchronous reset pulse of `cycles` clock cycles.
  task automatic apply_reset(int unsigned cycles = 5);
    @(posedge clk);
    rst_n <= 1'b0;
    repeat (cycles) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);
  endtask

  // Same, but the reset is asserted in the current time step (for a caller that
  // has just woken on a clock edge and wants the design to see it at the next one).
  task automatic apply_reset_now(int unsigned cycles = 5);
    rst_n <= 1'b0;
    repeat (cycles) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);
  endtask

  task automatic wait_clocks(int unsigned n);
    repeat (n) @(posedge clk);
  endtask

  task automatic wait_reset_done();
    while (rst_n !== 1'b1) @(posedge clk);
  endtask
endinterface
