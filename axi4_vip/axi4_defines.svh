`ifndef AXI4_DEFINES_SVH
`define AXI4_DEFINES_SVH
  // Maximum bus widths the VIP is compiled for.  Every axi4_if instance uses
  // these widths so that a single `virtual axi4_if` type serves all agents.
  // A DUT port that is narrower is connected to the low bits at tb top, and
  // the agent's axi4_agent_cfg records the width that is really in use.
  // Override per testbench with +define+AXI4_xxx_WIDTH=n in the filelist.
  `ifndef AXI4_ADDR_WIDTH
    `define AXI4_ADDR_WIDTH 32
  `endif
  `ifndef AXI4_DATA_WIDTH
    `define AXI4_DATA_WIDTH 32
  `endif
  `ifndef AXI4_ID_WIDTH
    `define AXI4_ID_WIDTH 8
  `endif
  `ifndef AXI4_USER_WIDTH
    `define AXI4_USER_WIDTH 1
  `endif
`endif
