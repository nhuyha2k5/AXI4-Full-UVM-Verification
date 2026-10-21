// AXI4 VIP package.  Compile axi4_if.sv and this file; nothing else is needed.
`include "axi4_defines.svh"
package axi4_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam int AXI4_ADDR_WIDTH = `AXI4_ADDR_WIDTH;
  localparam int AXI4_DATA_WIDTH = `AXI4_DATA_WIDTH;
  localparam int AXI4_ID_WIDTH   = `AXI4_ID_WIDTH;
  localparam int AXI4_USER_WIDTH = `AXI4_USER_WIDTH;

  `include "axi4_types.sv"
  `include "axi4_burst_utils.sv"
  `include "axi4_mem_model.sv"
  `include "axi4_agent_cfg.sv"
  `include "axi4_seq_item.sv"
  `include "axi4_sequencer.sv"
  `include "axi4_master_driver.sv"
  `include "axi4_slave_driver.sv"
  `include "axi4_monitor.sv"
  `include "axi4_coverage.sv"
  `include "axi4_mem_scoreboard.sv"
  `include "axi4_agent.sv"
  `include "axi4_seq_lib.sv"
endpackage
