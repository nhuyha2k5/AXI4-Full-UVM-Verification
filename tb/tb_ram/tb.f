// axi_ram testbench: one VIP master agent drives the RAM.
+incdir+axi4_vip
+define+AXI4_ADDR_WIDTH=16
+define+AXI4_DATA_WIDTH=32
+define+AXI4_ID_WIDTH=8
+define+AXI4_USER_WIDTH=1

axi4_vip/axi4_if.sv
axi4_vip/axi4_pkg.sv
tb/common/dv_clk_rst_if.sv
tb/common/dv_common_pkg.sv
tb/tb_ram/ram_test_pkg.sv
tb/tb_ram/tb_ram_top.sv
