`timescale 1ns/1ps
// Testbench top for axi_ram.  The VIP is compiled with exactly the DUT widths
// (ADDR 16, DATA 32, ID 8), so the interface connects to the ports directly.
module tb_ram_top #(
  parameter int PIPELINE_OUTPUT = 0,   // build configurations: 0 (default) and 1 (pipe)
  parameter     INIT_FILE       = ""   // build configuration "init": preloaded memory
);
  import uvm_pkg::*;
  import ram_test_pkg::*;

  dv_clk_rst_if clk_rst();
  axi4_if bus(.ACLK(clk_rst.clk), .ARESETn(clk_rst.rst_n));

  // axi_ram has no USER ports.
  assign bus.BUSER = '0;
  assign bus.RUSER = '0;

  // AXI_RAM_UPSTREAM: the unmodified axi_ram of verilog-axi, which has no INIT_FILE parameter.
`ifdef AXI_RAM_UPSTREAM
  axi_ram #(
    .DATA_WIDTH(`AXI4_DATA_WIDTH), .ADDR_WIDTH(`AXI4_ADDR_WIDTH), .ID_WIDTH(`AXI4_ID_WIDTH),
    .PIPELINE_OUTPUT(PIPELINE_OUTPUT)
  ) dut (
`else
  axi_ram #(
    .DATA_WIDTH(`AXI4_DATA_WIDTH), .ADDR_WIDTH(`AXI4_ADDR_WIDTH), .ID_WIDTH(`AXI4_ID_WIDTH),
    .PIPELINE_OUTPUT(PIPELINE_OUTPUT), .INIT_FILE(INIT_FILE)
  ) dut (
`endif
    .clk(clk_rst.clk), .rst(clk_rst.rst),
    .s_axi_awid(bus.AWID), .s_axi_awaddr(bus.AWADDR), .s_axi_awlen(bus.AWLEN), .s_axi_awsize(bus.AWSIZE),
    .s_axi_awburst(bus.AWBURST), .s_axi_awlock(bus.AWLOCK), .s_axi_awcache(bus.AWCACHE), .s_axi_awprot(bus.AWPROT),
    .s_axi_awvalid(bus.AWVALID), .s_axi_awready(bus.AWREADY),
    .s_axi_wdata(bus.WDATA), .s_axi_wstrb(bus.WSTRB), .s_axi_wlast(bus.WLAST),
    .s_axi_wvalid(bus.WVALID), .s_axi_wready(bus.WREADY),
    .s_axi_bid(bus.BID), .s_axi_bresp(bus.BRESP), .s_axi_bvalid(bus.BVALID), .s_axi_bready(bus.BREADY),
    .s_axi_arid(bus.ARID), .s_axi_araddr(bus.ARADDR), .s_axi_arlen(bus.ARLEN), .s_axi_arsize(bus.ARSIZE),
    .s_axi_arburst(bus.ARBURST), .s_axi_arlock(bus.ARLOCK), .s_axi_arcache(bus.ARCACHE), .s_axi_arprot(bus.ARPROT),
    .s_axi_arvalid(bus.ARVALID), .s_axi_arready(bus.ARREADY),
    .s_axi_rid(bus.RID), .s_axi_rdata(bus.RDATA), .s_axi_rresp(bus.RRESP), .s_axi_rlast(bus.RLAST),
    .s_axi_rvalid(bus.RVALID), .s_axi_rready(bus.RREADY)
  );

  string init_file = INIT_FILE;

  initial begin
    uvm_config_db#(virtual axi4_if)::set(null, "uvm_test_top", "bus_vif", bus);
    uvm_config_db#(virtual dv_clk_rst_if)::set(null, "uvm_test_top", "clk_rst_vif", clk_rst);
    uvm_config_db#(int)::set(null, "uvm_test_top", "pipeline_output", PIPELINE_OUTPUT);
    uvm_config_db#(string)::set(null, "uvm_test_top", "init_file", init_file);
    run_test();
  end
endmodule
