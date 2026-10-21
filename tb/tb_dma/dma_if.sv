`timescale 1ns/1ps
`include "axi4_defines.svh"
// Descriptor, status and control signals of the DMA engines.  One interface
// serves axi_dma_rd, axi_dma_wr and axi_cdma; each uses the fields it has.
interface dma_if (input logic clk, input logic rst_n);
  // descriptor request
  logic [`AXI4_ADDR_WIDTH-1:0] read_addr;
  logic [`AXI4_ADDR_WIDTH-1:0] write_addr;
  logic [19:0]                 len;
  logic [7:0]                  tag;
  logic [7:0]                  id;     // axi_dma_rd: TID of the stream frame
  logic [7:0]                  dest;   // axi_dma_rd: TDEST of the stream frame
  logic                        user;   // axi_dma_rd: TUSER of the stream frame
  logic                        valid;
  logic                        ready;
  // status
  logic [19:0]                 st_len;   // axi_dma_wr only
  logic [7:0]                  st_tag;
  logic [7:0]                  st_id;    // axi_dma_wr only
  logic [7:0]                  st_dest;  // axi_dma_wr only
  logic                        st_user;  // axi_dma_wr only
  logic [3:0]                  st_error;
  logic                        st_valid;
  // control
  logic                        enable = 1'b1;
  logic                        abort  = 1'b0;   // axi_dma_wr only

  clocking cb @(posedge clk);
    default input #1step;
    input rst_n, read_addr, write_addr, len, tag, id, dest, user, valid, ready;
    input st_len, st_tag, st_id, st_dest, st_user, st_error, st_valid, enable, abort;
  endclocking
endinterface
