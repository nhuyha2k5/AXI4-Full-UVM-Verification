`timescale 1ns/1ps
`include "axi4_defines.svh"
// Testbench top for axi_dma_wr.  The engine's AXI4 master port is served by the
// AXI4 VIP in slave role, its input stream by an axis source.
module tb_dma_wr_top #(
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
  // No read channels.
  assign bus.ARVALID = 1'b0; assign bus.RREADY = 1'b0;
  assign bus.ARID = '0; assign bus.ARADDR = '0; assign bus.ARLEN = '0; assign bus.ARSIZE = '0; assign bus.ARBURST = '0;
  assign bus.ARLOCK = '0; assign bus.ARCACHE = '0; assign bus.ARPROT = '0;
  axi_dma_wr #(
    .AXI_DATA_WIDTH(`AXI4_DATA_WIDTH), .AXI_ADDR_WIDTH(`AXI4_ADDR_WIDTH), .AXI_ID_WIDTH(`AXI4_ID_WIDTH), .AXI_MAX_BURST_LEN(MAX_BURST_LEN),
    .LEN_WIDTH(20), .TAG_WIDTH(8), .ENABLE_UNALIGNED(ENABLE_UNALIGNED),
    .AXIS_DATA_WIDTH(`AXI4_DATA_WIDTH), .AXIS_KEEP_ENABLE(1), .AXIS_KEEP_WIDTH(`AXI4_DATA_WIDTH/8), .AXIS_LAST_ENABLE(1),
    .AXIS_ID_ENABLE(1), .AXIS_ID_WIDTH(8), .AXIS_DEST_ENABLE(1), .AXIS_DEST_WIDTH(8), .AXIS_USER_ENABLE(1), .AXIS_USER_WIDTH(1)
  ) dut (
    .clk(clk_rst.clk), .rst(clk_rst.rst),
    .s_axis_write_desc_addr(dma.write_addr), .s_axis_write_desc_len(dma.len), .s_axis_write_desc_tag(dma.tag),
    .s_axis_write_desc_valid(dma.valid), .s_axis_write_desc_ready(dma.ready),
    .m_axis_write_desc_status_len(dma.st_len), .m_axis_write_desc_status_tag(dma.st_tag), .m_axis_write_desc_status_id(dma.st_id),
    .m_axis_write_desc_status_dest(dma.st_dest), .m_axis_write_desc_status_user(dma.st_user),
    .m_axis_write_desc_status_error(dma.st_error), .m_axis_write_desc_status_valid(dma.st_valid),
    .s_axis_write_data_tdata(stream.tdata), .s_axis_write_data_tkeep(stream.tkeep), .s_axis_write_data_tvalid(stream.tvalid),
    .s_axis_write_data_tready(stream.tready), .s_axis_write_data_tlast(stream.tlast),
    .s_axis_write_data_tid(stream.tid), .s_axis_write_data_tdest(stream.tdest), .s_axis_write_data_tuser(stream.tuser),
    .m_axi_awid(bus.AWID), .m_axi_awaddr(bus.AWADDR), .m_axi_awlen(bus.AWLEN), .m_axi_awsize(bus.AWSIZE), .m_axi_awburst(bus.AWBURST),
    .m_axi_awlock(bus.AWLOCK), .m_axi_awcache(bus.AWCACHE), .m_axi_awprot(bus.AWPROT), .m_axi_awvalid(bus.AWVALID), .m_axi_awready(bus.AWREADY),
    .m_axi_wdata(bus.WDATA), .m_axi_wstrb(bus.WSTRB), .m_axi_wlast(bus.WLAST), .m_axi_wvalid(bus.WVALID), .m_axi_wready(bus.WREADY),
    .m_axi_bid(bus.BID), .m_axi_bresp(bus.BRESP), .m_axi_bvalid(bus.BVALID), .m_axi_bready(bus.BREADY),
    .enable(dma.enable), .abort(dma.abort)
  );

  initial begin
    uvm_config_db#(int)::set(null, "uvm_test_top", "dma_kind", DMA_WR);
    uvm_config_db#(int)::set(null, "uvm_test_top", "max_burst_len", MAX_BURST_LEN);
    uvm_config_db#(int)::set(null, "uvm_test_top", "enable_unaligned", ENABLE_UNALIGNED);
    uvm_config_db#(virtual axi4_if)::set(null, "uvm_test_top", "axi_vif", bus);
    uvm_config_db#(virtual dma_if)::set(null, "uvm_test_top", "dma_vif", dma);
    uvm_config_db#(virtual dv_clk_rst_if)::set(null, "uvm_test_top", "clk_rst_vif", clk_rst);
    uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top", "stream_vif", stream);
    run_test();
  end
endmodule
