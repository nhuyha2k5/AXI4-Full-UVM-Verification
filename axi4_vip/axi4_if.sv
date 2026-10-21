`timescale 1ns/1ps
`include "axi4_defines.svh"
// =============================================================================
// AXI4-Full interface used by every agent of the VIP.
//
// - Always instantiated with the compiled maximum widths, so one
//   `virtual axi4_if` type fits every port.  Connect narrower DUT ports to the
//   low bits at tb top and tie unused inputs (for example xUSER) to zero.
// - Agents sample through the clocking block and drive with non-blocking
//   assignments.  Signals owned by a DUT are driven by continuous assignment.
// - Signal-level protocol rules are checked here with SVA; failures are
//   reported as UVM_ERROR with id AXI4_SVA.  Transaction-level rules (beat
//   counts, ID matching, ordering) are checked by axi4_monitor.
// =============================================================================
interface axi4_if #(
  parameter int ADDR_WIDTH = `AXI4_ADDR_WIDTH,
  parameter int DATA_WIDTH = `AXI4_DATA_WIDTH,
  parameter int ID_WIDTH   = `AXI4_ID_WIDTH,
  parameter int USER_WIDTH = `AXI4_USER_WIDTH,
  parameter int STRB_WIDTH = DATA_WIDTH / 8
) (
  input logic ACLK,
  input logic ARESETn
);
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Write address channel
  logic [ID_WIDTH-1:0]   AWID;
  logic [ADDR_WIDTH-1:0] AWADDR;
  logic [7:0]            AWLEN;
  logic [2:0]            AWSIZE;
  logic [1:0]            AWBURST;
  logic                  AWLOCK;
  logic [3:0]            AWCACHE;
  logic [2:0]            AWPROT;
  logic [3:0]            AWQOS;
  logic [3:0]            AWREGION;
  logic [USER_WIDTH-1:0] AWUSER;
  logic                  AWVALID;
  logic                  AWREADY;
  // Write data channel
  logic [DATA_WIDTH-1:0] WDATA;
  logic [STRB_WIDTH-1:0] WSTRB;
  logic                  WLAST;
  logic [USER_WIDTH-1:0] WUSER;
  logic                  WVALID;
  logic                  WREADY;
  // Write response channel
  logic [ID_WIDTH-1:0]   BID;
  logic [1:0]            BRESP;
  logic [USER_WIDTH-1:0] BUSER;
  logic                  BVALID;
  logic                  BREADY;
  // Read address channel
  logic [ID_WIDTH-1:0]   ARID;
  logic [ADDR_WIDTH-1:0] ARADDR;
  logic [7:0]            ARLEN;
  logic [2:0]            ARSIZE;
  logic [1:0]            ARBURST;
  logic                  ARLOCK;
  logic [3:0]            ARCACHE;
  logic [2:0]            ARPROT;
  logic [3:0]            ARQOS;
  logic [3:0]            ARREGION;
  logic [USER_WIDTH-1:0] ARUSER;
  logic                  ARVALID;
  logic                  ARREADY;
  // Read data channel
  logic [ID_WIDTH-1:0]   RID;
  logic [DATA_WIDTH-1:0] RDATA;
  logic [1:0]            RRESP;
  logic                  RLAST;
  logic [USER_WIDTH-1:0] RUSER;
  logic                  RVALID;
  logic                  RREADY;

  // Set to 0 by a test that deliberately violates the protocol.
  bit sva_enable = 1'b1;

  clocking cb @(posedge ACLK);
    default input #1step;
    input ARESETn;
    input AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION, AWUSER, AWVALID, AWREADY;
    input WDATA, WSTRB, WLAST, WUSER, WVALID, WREADY;
    input BID, BRESP, BUSER, BVALID, BREADY;
    input ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION, ARUSER, ARVALID, ARREADY;
    input RID, RDATA, RRESP, RLAST, RUSER, RVALID, RREADY;
  endclocking

  // ---------------------------------------------------------------------------
  // Signal-level protocol assertions
  // ---------------------------------------------------------------------------
  `define AXI4_SVA(NAME, PROP, MSG) \
    NAME: assert property (@(posedge ACLK) disable iff (!ARESETn || !sva_enable) PROP) \
      else `uvm_error("AXI4_SVA", $sformatf("%m.%s: %s", `"NAME`", MSG))

  // A3.2.1: once VALID is asserted it stays asserted, with stable payload, until READY.
  `AXI4_SVA(A_AW_STABLE, AWVALID && !AWREADY |=> AWVALID &&
            $stable({AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION, AWUSER}),
            "AW payload changed or AWVALID dropped before AWREADY")
  `AXI4_SVA(A_W_STABLE, WVALID && !WREADY |=> WVALID && $stable({WDATA, WSTRB, WLAST, WUSER}),
            "W payload changed or WVALID dropped before WREADY")
  `AXI4_SVA(A_B_STABLE, BVALID && !BREADY |=> BVALID && $stable({BID, BRESP, BUSER}),
            "B payload changed or BVALID dropped before BREADY")
  `AXI4_SVA(A_AR_STABLE, ARVALID && !ARREADY |=> ARVALID &&
            $stable({ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION, ARUSER}),
            "AR payload changed or ARVALID dropped before ARREADY")
  `AXI4_SVA(A_R_STABLE, RVALID && !RREADY |=> RVALID && $stable({RID, RDATA, RRESP, RLAST, RUSER}),
            "R payload changed or RVALID dropped before RREADY")

  // No X/Z on a channel while its VALID is high, and no X/Z on VALID/READY.
  `AXI4_SVA(A_HS_KNOWN, !$isunknown({AWVALID, AWREADY, WVALID, WREADY, BVALID, BREADY, ARVALID, ARREADY, RVALID, RREADY}),
            "X/Z on a VALID or READY signal")
  `AXI4_SVA(A_AW_KNOWN, AWVALID |-> !$isunknown({AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWLOCK, AWCACHE, AWPROT, AWQOS, AWREGION, AWUSER}),
            "X/Z on AW payload")
  `AXI4_SVA(A_W_KNOWN, WVALID |-> !$isunknown({WSTRB, WLAST, WUSER}), "X/Z on WSTRB/WLAST/WUSER")
  `AXI4_SVA(A_B_KNOWN, BVALID |-> !$isunknown({BID, BRESP, BUSER}), "X/Z on B payload")
  `AXI4_SVA(A_AR_KNOWN, ARVALID |-> !$isunknown({ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARLOCK, ARCACHE, ARPROT, ARQOS, ARREGION, ARUSER}),
            "X/Z on AR payload")
  `AXI4_SVA(A_R_KNOWN, RVALID |-> !$isunknown({RID, RRESP, RLAST, RUSER}), "X/Z on RID/RRESP/RLAST/RUSER")

  // A3.4.1 burst rules.
  `AXI4_SVA(A_AWBURST, AWVALID |-> AWBURST != 2'b11, "reserved AWBURST encoding")
  `AXI4_SVA(A_ARBURST, ARVALID |-> ARBURST != 2'b11, "reserved ARBURST encoding")
  `AXI4_SVA(A_AWSIZE,  AWVALID |-> AWSIZE <= $clog2(STRB_WIDTH), "AWSIZE wider than the data bus")
  `AXI4_SVA(A_ARSIZE,  ARVALID |-> ARSIZE <= $clog2(STRB_WIDTH), "ARSIZE wider than the data bus")
  `AXI4_SVA(A_AWWRAP_LEN, AWVALID && AWBURST == 2'b10 |-> AWLEN inside {8'd1, 8'd3, 8'd7, 8'd15}, "WRAP write burst length is not 2/4/8/16")
  `AXI4_SVA(A_ARWRAP_LEN, ARVALID && ARBURST == 2'b10 |-> ARLEN inside {8'd1, 8'd3, 8'd7, 8'd15}, "WRAP read burst length is not 2/4/8/16")
  `AXI4_SVA(A_AWWRAP_ALIGN, AWVALID && AWBURST == 2'b10 |-> (AWADDR & ((32'd1 << AWSIZE) - 1)) == 0, "WRAP write burst start address not aligned to AWSIZE")
  `AXI4_SVA(A_ARWRAP_ALIGN, ARVALID && ARBURST == 2'b10 |-> (ARADDR & ((32'd1 << ARSIZE) - 1)) == 0, "WRAP read burst start address not aligned to ARSIZE")
  `AXI4_SVA(A_AWFIXED_LEN, AWVALID && AWBURST == 2'b00 |-> AWLEN <= 8'd15, "FIXED write burst longer than 16 beats")
  `AXI4_SVA(A_ARFIXED_LEN, ARVALID && ARBURST == 2'b00 |-> ARLEN <= 8'd15, "FIXED read burst longer than 16 beats")
  // Only INCR bursts can cross a 4 KB boundary, so only they are checked.
  `AXI4_SVA(A_AW_4K, AWVALID && AWBURST == 2'b01 |->
            (((AWADDR & 32'hFFF) & ~((32'd1 << AWSIZE) - 1)) + ((AWLEN + 32'd1) << AWSIZE)) <= 32'd4096,
            "INCR write burst crosses a 4KB boundary")
  `AXI4_SVA(A_AR_4K, ARVALID && ARBURST == 2'b01 |->
            (((ARADDR & 32'hFFF) & ~((32'd1 << ARSIZE) - 1)) + ((ARLEN + 32'd1) << ARSIZE)) <= 32'd4096,
            "INCR read burst crosses a 4KB boundary")
  `undef AXI4_SVA

  // A3.1.2: all VALID outputs are low from the second clock edge of reset onwards.
  A_RESET_VALID: assert property (@(posedge ACLK) disable iff (!sva_enable)
      (!ARESETn ##1 !ARESETn) |-> !(AWVALID === 1'b1 || WVALID === 1'b1 || ARVALID === 1'b1 || BVALID === 1'b1 || RVALID === 1'b1))
    else `uvm_error("AXI4_SVA", $sformatf("%m.A_RESET_VALID: a VALID signal is high during reset"))
endinterface
