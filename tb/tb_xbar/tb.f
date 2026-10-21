// axi_crossbar testbench: 2 VIP masters, 3 VIP slaves.
+incdir+axi4_vip
+define+AXI4_ADDR_WIDTH=32
+define+AXI4_DATA_WIDTH=32
+define+AXI4_ID_WIDTH=8
+define+AXI4_USER_WIDTH=2

axi4_vip/axi4_if.sv
axi4_vip/axi4_pkg.sv
tb/common/dv_clk_rst_if.sv
tb/common/dv_common_pkg.sv
tb/tb_xbar/xbar_cfg_pkg.sv
tb/tb_xbar/xbar_test_pkg.sv
tb/tb_xbar/tb_xbar_top.sv
