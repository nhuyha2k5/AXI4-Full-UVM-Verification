`timescale 1ns/1ps
`include "axi4_defines.svh"
// Testbench top for axi_cdma.  The engine's AXI4 master port is served by the
// AXI4 VIP in slave role.
module tb_cdma_top #(
  parameter int MAX_BURST_LEN    = 16,   // build configurations override these
  parameter int ENABLE_UNALIGNED = 1
);
  import uvm_pkg::*;
  import dma_tb_pkg::*;

  dv_clk_rst_if clk_rst();
  axi4_if bus(.ACLK(clk_rst.clk), .ARESETn(clk_rst.rst_n));
  dma_if  dma(.clk(clk_rst.clk), .rst_n(clk_rst.rst_n));
  // axi_cdma has no stream port.  The shared package refers to the stream
  // interface type, so one idle instance is kept here.
  axis_if stream(.clk(clk_rst.clk), .rst_n(clk_rst.rst_n));
  assign stream.tvalid = 1'b0; assign stream.tready = 1'b0; assign stream.tdata = '0; assign stream.tkeep = '0;
  assign stream.tlast = 1'b0;  assign stream.tid = '0;      assign stream.tdest = '0; assign stream.tuser = 1'b0;

  // The engine has no QOS/REGION/USER outputs.
  assign bus.AWQOS = '0; assign bus.AWREGION = '0; assign bus.AWUSER = '0; assign bus.WUSER = '0;
  assign bus.ARQOS = '0; assign bus.ARREGION = '0; assign bus.ARUSER = '0;

  axi_cdma #(
    .AXI_DATA_WIDTH(`AXI4_DATA_WIDTH), .AXI_ADDR_WIDTH(`AXI4_ADDR_WIDTH), .AXI_ID_WIDTH(`AXI4_ID_WIDTH), .AXI_MAX_BURST_LEN(MAX_BURST_LEN),
    .LEN_WIDTH(20), .TAG_WIDTH(8), .ENABLE_UNALIGNED(ENABLE_UNALIGNED)
  ) dut (
    .clk(clk_rst.clk), .rst(clk_rst.rst),
    .s_axis_desc_read_addr(dma.read_addr), .s_axis_desc_write_addr(dma.write_addr), .s_axis_desc_len(dma.len), .s_axis_desc_tag(dma.tag),
    .s_axis_desc_valid(dma.valid), .s_axis_desc_ready(dma.ready),
    .m_axis_desc_status_tag(dma.st_tag), .m_axis_desc_status_error(dma.st_error), .m_axis_desc_status_valid(dma.st_valid),
    .m_axi_awid(bus.AWID), .m_axi_awaddr(bus.AWADDR), .m_axi_awlen(bus.AWLEN), .m_axi_awsize(bus.AWSIZE), .m_axi_awburst(bus.AWBURST),
    .m_axi_awlock(bus.AWLOCK), .m_axi_awcache(bus.AWCACHE), .m_axi_awprot(bus.AWPROT), .m_axi_awvalid(bus.AWVALID), .m_axi_awready(bus.AWREADY),
    .m_axi_wdata(bus.WDATA), .m_axi_wstrb(bus.WSTRB), .m_axi_wlast(bus.WLAST), .m_axi_wvalid(bus.WVALID), .m_axi_wready(bus.WREADY),
    .m_axi_bid(bus.BID), .m_axi_bresp(bus.BRESP), .m_axi_bvalid(bus.BVALID), .m_axi_bready(bus.BREADY),
    .m_axi_arid(bus.ARID), .m_axi_araddr(bus.ARADDR), .m_axi_arlen(bus.ARLEN), .m_axi_arsize(bus.ARSIZE), .m_axi_arburst(bus.ARBURST),
    .m_axi_arlock(bus.ARLOCK), .m_axi_arcache(bus.ARCACHE), .m_axi_arprot(bus.ARPROT), .m_axi_arvalid(bus.ARVALID), .m_axi_arready(bus.ARREADY),
    .m_axi_rid(bus.RID), .m_axi_rdata(bus.RDATA), .m_axi_rresp(bus.RRESP), .m_axi_rlast(bus.RLAST), .m_axi_rvalid(bus.RVALID), .m_axi_rready(bus.RREADY),
    .enable(dma.enable)
  );
  // Status fields this engine does not have.
  assign dma.st_len = '0; assign dma.st_id = '0; assign dma.st_dest = '0; assign dma.st_user = 1'b0;

  initial begin
    uvm_config_db#(int)::set(null, "uvm_test_top", "dma_kind", DMA_CDMA);
    uvm_config_db#(int)::set(null, "uvm_test_top", "max_burst_len", MAX_BURST_LEN);
    uvm_config_db#(int)::set(null, "uvm_test_top", "enable_unaligned", ENABLE_UNALIGNED);
    uvm_config_db#(virtual axi4_if)::set(null, "uvm_test_top", "axi_vif", bus);
    uvm_config_db#(virtual dma_if)::set(null, "uvm_test_top", "dma_vif", dma);
    uvm_config_db#(virtual dv_clk_rst_if)::set(null, "uvm_test_top", "clk_rst_vif", clk_rst);
    run_test();
  end
endmodule
