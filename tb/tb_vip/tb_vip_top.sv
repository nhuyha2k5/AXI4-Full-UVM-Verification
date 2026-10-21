`timescale 1ns/1ps
// VIP self-test: an AXI4 master agent and an AXI4 slave agent share one
// interface, with no DUT in between.  Qualifies the VIP itself.
module tb_vip_top;
  import uvm_pkg::*;
  import vip_test_pkg::*;

  dv_clk_rst_if clk_rst();
  axi4_if bus(.ACLK(clk_rst.clk), .ARESETn(clk_rst.rst_n));

  initial begin
    uvm_config_db#(virtual axi4_if)::set(null, "uvm_test_top", "bus_vif", bus);
    uvm_config_db#(virtual dv_clk_rst_if)::set(null, "uvm_test_top", "clk_rst_vif", clk_rst);
    run_test();
  end
endmodule
