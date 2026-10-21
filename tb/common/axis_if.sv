`timescale 1ns/1ps
`include "axi4_defines.svh"
// AXI4-Stream interface for the DMA stream ports.  TDATA has the AXI data
// width of the testbench; TID/TDEST are 8 bits and TUSER 1 bit.
interface axis_if (input logic clk, input logic rst_n);
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  logic [`AXI4_DATA_WIDTH-1:0]   tdata;
  logic [`AXI4_DATA_WIDTH/8-1:0] tkeep;
  logic                          tvalid;
  logic                          tready;
  logic                          tlast;
  logic [7:0]                    tid;
  logic [7:0]                    tdest;
  logic                          tuser;

  clocking cb @(posedge clk);
    default input #1step;
    input rst_n, tdata, tkeep, tvalid, tready, tlast, tid, tdest, tuser;
  endclocking

  // Once asserted, TVALID and the payload hold until TREADY.
  A_AXIS_STABLE: assert property (@(posedge clk) disable iff (!rst_n)
      tvalid && !tready |=> tvalid && $stable({tdata, tkeep, tlast, tid, tdest, tuser}))
    else `uvm_error("AXIS_SVA", $sformatf("%m: TVALID dropped or payload changed before TREADY"))
  A_AXIS_HS_KNOWN: assert property (@(posedge clk) disable iff (!rst_n) !$isunknown({tvalid, tready}))
    else `uvm_error("AXIS_SVA", $sformatf("%m: X/Z on TVALID or TREADY"))
  A_AXIS_KNOWN: assert property (@(posedge clk) disable iff (!rst_n)
      tvalid |-> !$isunknown({tkeep, tlast, tid, tdest, tuser}))
    else `uvm_error("AXIS_SVA", $sformatf("%m: X/Z on a stream control signal"))
endinterface
