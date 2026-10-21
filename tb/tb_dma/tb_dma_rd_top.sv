`timescale 1ns/1ps
`include "axi4_defines.svh"
// Testbench top for axi_dma_rd.  The engine's AXI4 master port is served by the
// AXI4 VIP in slave role, its output stream by an axis sink.
module tb_dma_rd_top #(
  parameter int MAX_BURST_LEN    = 16,   // build configurations override these
  parameter int ENABLE_UNALIGNED = 1
);
  import uvm_pkg::*;
  import dma_tb_pkg::*;

  dv_clk_rst_if clk_rst();
  axi4_if bus(.ACLK(clk_rst.clk), .ARESETn(clk_rst.rst_n));
  dma_if  dma(.clk(clk_rst.clk), .rst_n(clk_rst.rst_n));
  axis_if stream(.clk(clk_rst.clk), .rst_n(clk_rst.rst_n));

  // The engine has no QOS/REGION/USER outputs.
  assign bus.AWQOS = '0; assign bus.AWREGION = '0; assign bus.AWUSER = '0; assign bus.WUSER = '0;
  assign bus.ARQOS = '0; assign bus.ARREGION = '0; assign bus.ARUSER = '0;
  // No write channels.
  assign bus.AWVALID = 1'b0; assign bus.WVALID = 1'b0; assign bus.BREADY = 1'b0;
  assign bus.AWID = '0; assign bus.AWADDR = '0; assign bus.AWLEN = '0; assign bus.AWSIZE = '0; assign bus.AWBURST = '0;
  assign bus.AWLOCK = '0; assign bus.AWCACHE = '0; assign bus.AWPROT = '0; assign bus.WDATA = '0; assign bus.WSTRB = '0; assign bus.WLAST = '0;
  axi_dma_rd #(
    .AXI_DATA_WIDTH(`AXI4_DATA_WIDTH), .AXI_ADDR_WIDTH(`AXI4_ADDR_WIDTH), .AXI_ID_WIDTH(`AXI4_ID_WIDTH), .AXI_MAX_BURST_LEN(MAX_BURST_LEN),
    .LEN_WIDTH(20), .TAG_WIDTH(8), .ENABLE_UNALIGNED(ENABLE_UNALIGNED),
    .AXIS_DATA_WIDTH(`AXI4_DATA_WIDTH), .AXIS_KEEP_ENABLE(1), .AXIS_KEEP_WIDTH(`AXI4_DATA_WIDTH/8), .AXIS_LAST_ENABLE(1),
    .AXIS_ID_ENABLE(1), .AXIS_ID_WIDTH(8), .AXIS_DEST_ENABLE(1), .AXIS_DEST_WIDTH(8), .AXIS_USER_ENABLE(1), .AXIS_USER_WIDTH(1)
  ) dut (
    .clk(clk_rst.clk), .rst(clk_rst.rst),
    .s_axis_read_desc_addr(dma.read_addr), .s_axis_read_desc_len(dma.len), .s_axis_read_desc_tag(dma.tag),
    .s_axis_read_desc_id(dma.id), .s_axis_read_desc_dest(dma.dest), .s_axis_read_desc_user(dma.user),
    .s_axis_read_desc_valid(dma.valid), .s_axis_read_desc_ready(dma.ready),
    .m_axis_read_desc_status_tag(dma.st_tag), .m_axis_read_desc_status_error(dma.st_error), .m_axis_read_desc_status_valid(dma.st_valid),
    .m_axis_read_data_tdata(stream.tdata), .m_axis_read_data_tkeep(stream.tkeep), .m_axis_read_data_tvalid(stream.tvalid),
    .m_axis_read_data_tready(stream.tready), .m_axis_read_data_tlast(stream.tlast),
    .m_axis_read_data_tid(stream.tid), .m_axis_read_data_tdest(stream.tdest), .m_axis_read_data_tuser(stream.tuser),
    .m_axi_arid(bus.ARID), .m_axi_araddr(bus.ARADDR), .m_axi_arlen(bus.ARLEN), .m_axi_arsize(bus.ARSIZE), .m_axi_arburst(bus.ARBURST),
    .m_axi_arlock(bus.ARLOCK), .m_axi_arcache(bus.ARCACHE), .m_axi_arprot(bus.ARPROT), .m_axi_arvalid(bus.ARVALID), .m_axi_arready(bus.ARREADY),
    .m_axi_rid(bus.RID), .m_axi_rdata(bus.RDATA), .m_axi_rresp(bus.RRESP), .m_axi_rlast(bus.RLAST), .m_axi_rvalid(bus.RVALID), .m_axi_rready(bus.RREADY),
    .enable(dma.enable)
  );
  // Status fields this engine does not have.
  assign dma.st_len = '0; assign dma.st_id = '0; assign dma.st_dest = '0; assign dma.st_user = 1'b0;

  initial begin
    uvm_config_db#(int)::set(null, "uvm_test_top", "dma_kind", DMA_RD);
    uvm_config_db#(int)::set(null, "uvm_test_top", "max_burst_len", MAX_BURST_LEN);
    uvm_config_db#(int)::set(null, "uvm_test_top", "enable_unaligned", ENABLE_UNALIGNED);
    uvm_config_db#(virtual axi4_if)::set(null, "uvm_test_top", "axi_vif", bus);
    uvm_config_db#(virtual dma_if)::set(null, "uvm_test_top", "dma_vif", dma);
    uvm_config_db#(virtual dv_clk_rst_if)::set(null, "uvm_test_top", "clk_rst_vif", clk_rst);
    uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top", "stream_vif", stream);
    run_test();
  end
endmodule
