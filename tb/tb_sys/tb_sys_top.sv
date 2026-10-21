`timescale 1ns/1ps
`include "axi4_defines.svh"
// System-level testbench:
//
//   AXI4 VIP master ("cpu") --> s0 +--------------+ m0 --> axi_ram 0 (0x0000_0000-0x0000_FFFF)
//                                  | axi_crossbar |
//   axi_cdma (DMA engine)   --> s1 +--------------+ m1 --> axi_ram 1 (0x0001_0000-0x0001_FFFF, output pipeline)
//
// The crossbar uses its default address computation (M_BASE_ADDR = 0).  Passive
// VIP agents watch the DMA port and both RAM ports.
module tb_sys_top;
  import uvm_pkg::*;
  import sys_test_pkg::*;

  localparam int AW = 32, DW = 32, SW = DW / 8;
  localparam int SID = 8;        // ID width of the masters
  localparam int MID = SID + 1;  // ID width towards the RAMs (one bit of master index)
  localparam int RAM_AW = 16;

  dv_clk_rst_if clk_rst();
  axi4_if cpu_if (.ACLK(clk_rst.clk), .ARESETn(clk_rst.rst_n));      // active master
  axi4_if dma_axi(.ACLK(clk_rst.clk), .ARESETn(clk_rst.rst_n));      // passive, axi_cdma -> crossbar
  axi4_if ram_if [2] (.ACLK(clk_rst.clk), .ARESETn(clk_rst.rst_n));  // passive, crossbar -> RAMs
  dma_if  dma(.clk(clk_rst.clk), .rst_n(clk_rst.rst_n));
  // The DMA package refers to the stream interface type; one idle instance.
  axis_if stream(.clk(clk_rst.clk), .rst_n(clk_rst.rst_n));
  assign stream.tvalid = 1'b0; assign stream.tready = 1'b0; assign stream.tdata = '0; assign stream.tkeep = '0;
  assign stream.tlast = 1'b0;  assign stream.tid = '0;      assign stream.tdest = '0; assign stream.tuser = 1'b0;

  // ---------------------------------------------------------------------------
  // DMA engine
  // ---------------------------------------------------------------------------
  wire [SID-1:0] c_awid, c_arid;
  assign dma_axi.AWID = c_awid;   // zero-extended to the VIP ID width
  assign dma_axi.ARID = c_arid;
  assign dma_axi.AWQOS = '0; assign dma_axi.AWREGION = '0; assign dma_axi.AWUSER = '0; assign dma_axi.WUSER = '0;
  assign dma_axi.ARQOS = '0; assign dma_axi.ARREGION = '0; assign dma_axi.ARUSER = '0;
  assign dma_axi.BUSER = '0; assign dma_axi.RUSER = '0;

  axi_cdma #(
    .AXI_DATA_WIDTH(DW), .AXI_ADDR_WIDTH(AW), .AXI_ID_WIDTH(SID), .AXI_MAX_BURST_LEN(16),
    .LEN_WIDTH(20), .TAG_WIDTH(8), .ENABLE_UNALIGNED(1)
  ) cdma (
    .clk(clk_rst.clk), .rst(clk_rst.rst),
    .s_axis_desc_read_addr(dma.read_addr), .s_axis_desc_write_addr(dma.write_addr), .s_axis_desc_len(dma.len), .s_axis_desc_tag(dma.tag),
    .s_axis_desc_valid(dma.valid), .s_axis_desc_ready(dma.ready),
    .m_axis_desc_status_tag(dma.st_tag), .m_axis_desc_status_error(dma.st_error), .m_axis_desc_status_valid(dma.st_valid),
    .m_axi_awid(c_awid), .m_axi_awaddr(dma_axi.AWADDR), .m_axi_awlen(dma_axi.AWLEN), .m_axi_awsize(dma_axi.AWSIZE), .m_axi_awburst(dma_axi.AWBURST),
    .m_axi_awlock(dma_axi.AWLOCK), .m_axi_awcache(dma_axi.AWCACHE), .m_axi_awprot(dma_axi.AWPROT), .m_axi_awvalid(dma_axi.AWVALID), .m_axi_awready(dma_axi.AWREADY),
    .m_axi_wdata(dma_axi.WDATA), .m_axi_wstrb(dma_axi.WSTRB), .m_axi_wlast(dma_axi.WLAST), .m_axi_wvalid(dma_axi.WVALID), .m_axi_wready(dma_axi.WREADY),
    .m_axi_bid(dma_axi.BID[SID-1:0]), .m_axi_bresp(dma_axi.BRESP), .m_axi_bvalid(dma_axi.BVALID), .m_axi_bready(dma_axi.BREADY),
    .m_axi_arid(c_arid), .m_axi_araddr(dma_axi.ARADDR), .m_axi_arlen(dma_axi.ARLEN), .m_axi_arsize(dma_axi.ARSIZE), .m_axi_arburst(dma_axi.ARBURST),
    .m_axi_arlock(dma_axi.ARLOCK), .m_axi_arcache(dma_axi.ARCACHE), .m_axi_arprot(dma_axi.ARPROT), .m_axi_arvalid(dma_axi.ARVALID), .m_axi_arready(dma_axi.ARREADY),
    .m_axi_rid(dma_axi.RID[SID-1:0]), .m_axi_rdata(dma_axi.RDATA), .m_axi_rresp(dma_axi.RRESP), .m_axi_rlast(dma_axi.RLAST),
    .m_axi_rvalid(dma_axi.RVALID), .m_axi_rready(dma_axi.RREADY),
    .enable(dma.enable)
  );
  assign dma.st_len = '0; assign dma.st_id = '0; assign dma.st_dest = '0; assign dma.st_user = 1'b0;

  // ---------------------------------------------------------------------------
  // Crossbar: s0 = cpu VIP, s1 = axi_cdma; m0/m1 = RAMs
  // ---------------------------------------------------------------------------
  wire [2*SID-1:0] s_bid, s_rid;
  wire [2*2-1:0]   s_bresp, s_rresp;
  wire [2*DW-1:0]  s_rdata;
  wire [1:0]       s_awready, s_wready, s_bvalid, s_arready, s_rlast, s_rvalid;

  wire [2*MID-1:0] m_awid, m_arid, m_bid, m_rid;
  wire [2*AW-1:0]  m_awaddr, m_araddr;
  wire [2*8-1:0]   m_awlen, m_arlen;
  wire [2*3-1:0]   m_awsize, m_arsize, m_awprot, m_arprot;
  wire [2*2-1:0]   m_awburst, m_arburst, m_bresp, m_rresp;
  wire [2*4-1:0]   m_awcache, m_arcache, m_awqos, m_arqos, m_awregion, m_arregion;
  wire [2*DW-1:0]  m_wdata, m_rdata;
  wire [2*SW-1:0]  m_wstrb;
  wire [1:0]       m_awlock, m_arlock, m_awvalid, m_awready, m_wlast, m_wvalid, m_wready,
                   m_bvalid, m_bready, m_arvalid, m_arready, m_rlast, m_rvalid, m_rready;

  axi_crossbar #(
    .S_COUNT(2), .M_COUNT(2), .DATA_WIDTH(DW), .ADDR_WIDTH(AW), .STRB_WIDTH(SW),
    .S_ID_WIDTH(SID), .M_ID_WIDTH(MID),
    .M_REGIONS(1), .M_BASE_ADDR(0), .M_ADDR_WIDTH({32'd16, 32'd16})
  ) xbar (
    .clk(clk_rst.clk), .rst(clk_rst.rst),
    .s_axi_awid({dma_axi.AWID[SID-1:0], cpu_if.AWID[SID-1:0]}), .s_axi_awaddr({dma_axi.AWADDR, cpu_if.AWADDR}),
    .s_axi_awlen({dma_axi.AWLEN, cpu_if.AWLEN}), .s_axi_awsize({dma_axi.AWSIZE, cpu_if.AWSIZE}), .s_axi_awburst({dma_axi.AWBURST, cpu_if.AWBURST}),
    .s_axi_awlock({dma_axi.AWLOCK, cpu_if.AWLOCK}), .s_axi_awcache({dma_axi.AWCACHE, cpu_if.AWCACHE}), .s_axi_awprot({dma_axi.AWPROT, cpu_if.AWPROT}),
    .s_axi_awqos({dma_axi.AWQOS, cpu_if.AWQOS}), .s_axi_awuser(2'b00),
    .s_axi_awvalid({dma_axi.AWVALID, cpu_if.AWVALID}), .s_axi_awready(s_awready),
    .s_axi_wdata({dma_axi.WDATA, cpu_if.WDATA}), .s_axi_wstrb({dma_axi.WSTRB, cpu_if.WSTRB}), .s_axi_wlast({dma_axi.WLAST, cpu_if.WLAST}),
    .s_axi_wuser(2'b00), .s_axi_wvalid({dma_axi.WVALID, cpu_if.WVALID}), .s_axi_wready(s_wready),
    .s_axi_bid(s_bid), .s_axi_bresp(s_bresp), .s_axi_buser(), .s_axi_bvalid(s_bvalid), .s_axi_bready({dma_axi.BREADY, cpu_if.BREADY}),
    .s_axi_arid({dma_axi.ARID[SID-1:0], cpu_if.ARID[SID-1:0]}), .s_axi_araddr({dma_axi.ARADDR, cpu_if.ARADDR}),
    .s_axi_arlen({dma_axi.ARLEN, cpu_if.ARLEN}), .s_axi_arsize({dma_axi.ARSIZE, cpu_if.ARSIZE}), .s_axi_arburst({dma_axi.ARBURST, cpu_if.ARBURST}),
    .s_axi_arlock({dma_axi.ARLOCK, cpu_if.ARLOCK}), .s_axi_arcache({dma_axi.ARCACHE, cpu_if.ARCACHE}), .s_axi_arprot({dma_axi.ARPROT, cpu_if.ARPROT}),
    .s_axi_arqos({dma_axi.ARQOS, cpu_if.ARQOS}), .s_axi_aruser(2'b00),
    .s_axi_arvalid({dma_axi.ARVALID, cpu_if.ARVALID}), .s_axi_arready(s_arready),
    .s_axi_rid(s_rid), .s_axi_rdata(s_rdata), .s_axi_rresp(s_rresp), .s_axi_rlast(s_rlast), .s_axi_ruser(),
    .s_axi_rvalid(s_rvalid), .s_axi_rready({dma_axi.RREADY, cpu_if.RREADY}),
    .m_axi_awid(m_awid), .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen), .m_axi_awsize(m_awsize), .m_axi_awburst(m_awburst),
    .m_axi_awlock(m_awlock), .m_axi_awcache(m_awcache), .m_axi_awprot(m_awprot), .m_axi_awqos(m_awqos), .m_axi_awregion(m_awregion),
    .m_axi_awuser(), .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
    .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb), .m_axi_wlast(m_wlast), .m_axi_wuser(), .m_axi_wvalid(m_wvalid), .m_axi_wready(m_wready),
    .m_axi_bid(m_bid), .m_axi_bresp(m_bresp), .m_axi_buser(2'b00), .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready),
    .m_axi_arid(m_arid), .m_axi_araddr(m_araddr), .m_axi_arlen(m_arlen), .m_axi_arsize(m_arsize), .m_axi_arburst(m_arburst),
    .m_axi_arlock(m_arlock), .m_axi_arcache(m_arcache), .m_axi_arprot(m_arprot), .m_axi_arqos(m_arqos), .m_axi_arregion(m_arregion),
    .m_axi_aruser(), .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
    .m_axi_rid(m_rid), .m_axi_rdata(m_rdata), .m_axi_rresp(m_rresp), .m_axi_rlast(m_rlast), .m_axi_ruser(2'b00),
    .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready)
  );

  // Crossbar outputs towards the two masters.
  assign cpu_if.AWREADY  = s_awready[0];  assign dma_axi.AWREADY = s_awready[1];
  assign cpu_if.WREADY   = s_wready[0];   assign dma_axi.WREADY  = s_wready[1];
  assign cpu_if.BID      = s_bid[0 +: SID];   assign dma_axi.BID   = s_bid[SID +: SID];
  assign cpu_if.BRESP    = s_bresp[1:0];      assign dma_axi.BRESP = s_bresp[3:2];
  assign cpu_if.BVALID   = s_bvalid[0];   assign dma_axi.BVALID  = s_bvalid[1];
  assign cpu_if.ARREADY  = s_arready[0];  assign dma_axi.ARREADY = s_arready[1];
  assign cpu_if.RID      = s_rid[0 +: SID];   assign dma_axi.RID   = s_rid[SID +: SID];
  assign cpu_if.RDATA    = s_rdata[0 +: DW];  assign dma_axi.RDATA = s_rdata[DW +: DW];
  assign cpu_if.RRESP    = s_rresp[1:0];      assign dma_axi.RRESP = s_rresp[3:2];
  assign cpu_if.RLAST    = s_rlast[0];    assign dma_axi.RLAST   = s_rlast[1];
  assign cpu_if.RVALID   = s_rvalid[0];   assign dma_axi.RVALID  = s_rvalid[1];
  assign cpu_if.BUSER    = '0;            assign cpu_if.RUSER    = '0;

  // ---------------------------------------------------------------------------
  // RAMs behind the crossbar
  // ---------------------------------------------------------------------------
  for (genvar i = 0; i < 2; i++) begin : g_ram
    assign ram_if[i].AWID = m_awid[i*MID +: MID];       assign ram_if[i].AWADDR = m_awaddr[i*AW +: AW];
    assign ram_if[i].AWLEN = m_awlen[i*8 +: 8];         assign ram_if[i].AWSIZE = m_awsize[i*3 +: 3];
    assign ram_if[i].AWBURST = m_awburst[i*2 +: 2];     assign ram_if[i].AWLOCK = m_awlock[i];
    assign ram_if[i].AWCACHE = m_awcache[i*4 +: 4];     assign ram_if[i].AWPROT = m_awprot[i*3 +: 3];
    assign ram_if[i].AWQOS = m_awqos[i*4 +: 4];         assign ram_if[i].AWREGION = m_awregion[i*4 +: 4];
    assign ram_if[i].AWUSER = '0;                       assign ram_if[i].AWVALID = m_awvalid[i];
    assign ram_if[i].WDATA = m_wdata[i*DW +: DW];       assign ram_if[i].WSTRB = m_wstrb[i*SW +: SW];
    assign ram_if[i].WLAST = m_wlast[i];                assign ram_if[i].WUSER = '0;
    assign ram_if[i].WVALID = m_wvalid[i];              assign ram_if[i].BREADY = m_bready[i];
    assign ram_if[i].ARID = m_arid[i*MID +: MID];       assign ram_if[i].ARADDR = m_araddr[i*AW +: AW];
    assign ram_if[i].ARLEN = m_arlen[i*8 +: 8];         assign ram_if[i].ARSIZE = m_arsize[i*3 +: 3];
    assign ram_if[i].ARBURST = m_arburst[i*2 +: 2];     assign ram_if[i].ARLOCK = m_arlock[i];
    assign ram_if[i].ARCACHE = m_arcache[i*4 +: 4];     assign ram_if[i].ARPROT = m_arprot[i*3 +: 3];
    assign ram_if[i].ARQOS = m_arqos[i*4 +: 4];         assign ram_if[i].ARREGION = m_arregion[i*4 +: 4];
    assign ram_if[i].ARUSER = '0;                       assign ram_if[i].ARVALID = m_arvalid[i];
    assign ram_if[i].RREADY = m_rready[i];
    assign ram_if[i].BUSER = '0;                        assign ram_if[i].RUSER = '0;

    assign m_awready[i] = ram_if[i].AWREADY;  assign m_wready[i] = ram_if[i].WREADY;
    assign m_bid[i*MID +: MID] = ram_if[i].BID[MID-1:0];  assign m_bresp[i*2 +: 2] = ram_if[i].BRESP;
    assign m_bvalid[i] = ram_if[i].BVALID;    assign m_arready[i] = ram_if[i].ARREADY;
    assign m_rid[i*MID +: MID] = ram_if[i].RID[MID-1:0];  assign m_rdata[i*DW +: DW] = ram_if[i].RDATA;
    assign m_rresp[i*2 +: 2] = ram_if[i].RRESP;  assign m_rlast[i] = ram_if[i].RLAST;  assign m_rvalid[i] = ram_if[i].RVALID;

    wire [MID-1:0] ram_bid, ram_rid;
    assign ram_if[i].BID = ram_bid;
    assign ram_if[i].RID = ram_rid;

    axi_ram #(.DATA_WIDTH(DW), .ADDR_WIDTH(RAM_AW), .ID_WIDTH(MID), .PIPELINE_OUTPUT(i)) ram (
      .clk(clk_rst.clk), .rst(clk_rst.rst),
      .s_axi_awid(ram_if[i].AWID[MID-1:0]), .s_axi_awaddr(ram_if[i].AWADDR[RAM_AW-1:0]), .s_axi_awlen(ram_if[i].AWLEN), .s_axi_awsize(ram_if[i].AWSIZE),
      .s_axi_awburst(ram_if[i].AWBURST), .s_axi_awlock(ram_if[i].AWLOCK), .s_axi_awcache(ram_if[i].AWCACHE), .s_axi_awprot(ram_if[i].AWPROT),
      .s_axi_awvalid(ram_if[i].AWVALID), .s_axi_awready(ram_if[i].AWREADY),
      .s_axi_wdata(ram_if[i].WDATA), .s_axi_wstrb(ram_if[i].WSTRB), .s_axi_wlast(ram_if[i].WLAST),
      .s_axi_wvalid(ram_if[i].WVALID), .s_axi_wready(ram_if[i].WREADY),
      .s_axi_bid(ram_bid), .s_axi_bresp(ram_if[i].BRESP), .s_axi_bvalid(ram_if[i].BVALID), .s_axi_bready(ram_if[i].BREADY),
      .s_axi_arid(ram_if[i].ARID[MID-1:0]), .s_axi_araddr(ram_if[i].ARADDR[RAM_AW-1:0]), .s_axi_arlen(ram_if[i].ARLEN), .s_axi_arsize(ram_if[i].ARSIZE),
      .s_axi_arburst(ram_if[i].ARBURST), .s_axi_arlock(ram_if[i].ARLOCK), .s_axi_arcache(ram_if[i].ARCACHE), .s_axi_arprot(ram_if[i].ARPROT),
      .s_axi_arvalid(ram_if[i].ARVALID), .s_axi_arready(ram_if[i].ARREADY),
      .s_axi_rid(ram_rid), .s_axi_rdata(ram_if[i].RDATA), .s_axi_rresp(ram_if[i].RRESP), .s_axi_rlast(ram_if[i].RLAST),
      .s_axi_rvalid(ram_if[i].RVALID), .s_axi_rready(ram_if[i].RREADY)
    );
  end

  initial begin
    uvm_config_db#(virtual axi4_if)::set(null, "uvm_test_top", "cpu_vif", cpu_if);
    uvm_config_db#(virtual axi4_if)::set(null, "uvm_test_top", "dma_axi_vif", dma_axi);
    uvm_config_db#(virtual axi4_if)::set(null, "uvm_test_top", "ram_vif0", ram_if[0]);
    uvm_config_db#(virtual axi4_if)::set(null, "uvm_test_top", "ram_vif1", ram_if[1]);
    uvm_config_db#(virtual dma_if)::set(null, "uvm_test_top", "dma_vif", dma);
    uvm_config_db#(virtual dv_clk_rst_if)::set(null, "uvm_test_top", "clk_rst_vif", clk_rst);
    run_test();
  end
endmodule
