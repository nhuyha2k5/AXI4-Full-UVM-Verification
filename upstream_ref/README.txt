Reference copies of four files of https://github.com/alexforencich/verilog-axi (branch master, rtl/),
downloaded unchanged on 2026-10-13: axi_ram.v, axi_dma_rd.v, axi_dma_wr.v, axi_cdma.v.
They are the files that differ from the copies in dut/.  The testbenches dma_rd_up, dma_wr_up and cdma_up
(scripts/dv_config.ps1) compile these files instead of dut/dma/*.v, to tell defects of the original
library from defects introduced by the changes made in this project.  The other RTL files in dut/ are
identical to the upstream ones.
