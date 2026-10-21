// axi_dma_rd testbench: AXI4 VIP slave as memory, descriptor agent, stream agent.
+incdir+axi4_vip
+define+AXI4_ADDR_WIDTH=32
+define+AXI4_DATA_WIDTH=32
+define+AXI4_ID_WIDTH=8
+define+AXI4_USER_WIDTH=1

axi4_vip/axi4_if.sv
axi4_vip/axi4_pkg.sv
tb/common/dv_clk_rst_if.sv
tb/common/dv_common_pkg.sv
tb/common/axis_if.sv
tb/common/axis_pkg.sv
tb/tb_dma/dma_if.sv
tb/tb_dma/dma_tb_pkg.sv
tb/tb_dma/tb_dma_rd_top.sv
