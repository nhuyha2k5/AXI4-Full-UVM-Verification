`timescale 1ns/1ps
// Testbench top for axi_crossbar: S_COUNT VIP masters and M_COUNT VIP slaves.
// The VIP interfaces use the compiled maximum widths (ID 8, USER 2); the
// crossbar ports take the low bits and its outputs are zero-extended.
module tb_xbar_top #(
  // Build configuration "open": every master is connected to every slave in
  // both directions and no slave is secure.  It exercises the routes that the
  // default configuration disconnects.
  parameter bit OPEN = 1'b0
);
  import uvm_pkg::*;
  import xbar_cfg_pkg::*;
  import xbar_test_pkg::*;

  localparam bit [M_COUNT*S_COUNT-1:0] CFG_CONNECT_READ  = OPEN ? {M_COUNT*S_COUNT{1'b1}} : M_CONNECT_READ;
  localparam bit [M_COUNT*S_COUNT-1:0] CFG_CONNECT_WRITE = OPEN ? {M_COUNT*S_COUNT{1'b1}} : M_CONNECT_WRITE;
  localparam bit [M_COUNT-1:0]         CFG_SECURE        = OPEN ? {M_COUNT{1'b0}}         : M_SECURE;
  // The issue limits are rotated in the "open" build so that every slave port
  // is verified both with a limit of one and with a higher limit.
  localparam bit [M_COUNT*32-1:0]      CFG_ISSUE         = OPEN ? M_ISSUE_OPEN            : M_ISSUE;

  dv_clk_rst_if clk_rst();
  axi4_if s_if [S_COUNT] (.ACLK(clk_rst.clk), .ARESETn(clk_rst.rst_n));   // crossbar slave ports  <- VIP masters
  axi4_if m_if [M_COUNT] (.ACLK(clk_rst.clk), .ARESETn(clk_rst.rst_n));   // crossbar master ports -> VIP slaves

  // Packed crossbar buses.
  wire [S_COUNT*S_ID_WIDTH-1:0] s_awid, s_bid, s_arid, s_rid;
  wire [S_COUNT*ADDR_WIDTH-1:0] s_awaddr, s_araddr;
  wire [S_COUNT*8-1:0]          s_awlen, s_arlen;
  wire [S_COUNT*3-1:0]          s_awsize, s_arsize, s_awprot, s_arprot;
  wire [S_COUNT*2-1:0]          s_awburst, s_arburst, s_bresp, s_rresp;
  wire [S_COUNT*4-1:0]          s_awcache, s_arcache, s_awqos, s_arqos;
  wire [S_COUNT*USER_WIDTH-1:0] s_awuser, s_wuser, s_buser, s_aruser, s_ruser;
  wire [S_COUNT*DATA_WIDTH-1:0] s_wdata, s_rdata;
  wire [S_COUNT*STRB_WIDTH-1:0] s_wstrb;
  wire [S_COUNT-1:0]            s_awlock, s_arlock, s_awvalid, s_awready, s_wlast, s_wvalid, s_wready,
                                s_bvalid, s_bready, s_arvalid, s_arready, s_rlast, s_rvalid, s_rready;

  wire [M_COUNT*M_ID_WIDTH-1:0] m_awid, m_bid, m_arid, m_rid;
  wire [M_COUNT*ADDR_WIDTH-1:0] m_awaddr, m_araddr;
  wire [M_COUNT*8-1:0]          m_awlen, m_arlen;
  wire [M_COUNT*3-1:0]          m_awsize, m_arsize, m_awprot, m_arprot;
  wire [M_COUNT*2-1:0]          m_awburst, m_arburst, m_bresp, m_rresp;
  wire [M_COUNT*4-1:0]          m_awcache, m_arcache, m_awqos, m_arqos, m_awregion, m_arregion;
  wire [M_COUNT*USER_WIDTH-1:0] m_awuser, m_wuser, m_buser, m_aruser, m_ruser;
  wire [M_COUNT*DATA_WIDTH-1:0] m_wdata, m_rdata;
  wire [M_COUNT*STRB_WIDTH-1:0] m_wstrb;
  wire [M_COUNT-1:0]            m_awlock, m_arlock, m_awvalid, m_awready, m_wlast, m_wvalid, m_wready,
                                m_bvalid, m_bready, m_arvalid, m_arready, m_rlast, m_rvalid, m_rready;

  for (genvar i = 0; i < S_COUNT; i++) begin : g_s
    // VIP master -> crossbar
    assign s_awid[i*S_ID_WIDTH +: S_ID_WIDTH] = s_if[i].AWID[S_ID_WIDTH-1:0];
    assign s_awaddr[i*ADDR_WIDTH +: ADDR_WIDTH] = s_if[i].AWADDR;
    assign s_awlen[i*8 +: 8]     = s_if[i].AWLEN;
    assign s_awsize[i*3 +: 3]    = s_if[i].AWSIZE;
    assign s_awburst[i*2 +: 2]   = s_if[i].AWBURST;
    assign s_awlock[i]           = s_if[i].AWLOCK;
    assign s_awcache[i*4 +: 4]   = s_if[i].AWCACHE;
    assign s_awprot[i*3 +: 3]    = s_if[i].AWPROT;
    assign s_awqos[i*4 +: 4]     = s_if[i].AWQOS;
    assign s_awuser[i*USER_WIDTH +: USER_WIDTH] = s_if[i].AWUSER[USER_WIDTH-1:0];
    assign s_awvalid[i]          = s_if[i].AWVALID;
    assign s_wdata[i*DATA_WIDTH +: DATA_WIDTH] = s_if[i].WDATA;
    assign s_wstrb[i*STRB_WIDTH +: STRB_WIDTH] = s_if[i].WSTRB;
    assign s_wlast[i]            = s_if[i].WLAST;
    assign s_wuser[i*USER_WIDTH +: USER_WIDTH] = s_if[i].WUSER[USER_WIDTH-1:0];
    assign s_wvalid[i]           = s_if[i].WVALID;
    assign s_bready[i]           = s_if[i].BREADY;
    assign s_arid[i*S_ID_WIDTH +: S_ID_WIDTH] = s_if[i].ARID[S_ID_WIDTH-1:0];
    assign s_araddr[i*ADDR_WIDTH +: ADDR_WIDTH] = s_if[i].ARADDR;
    assign s_arlen[i*8 +: 8]     = s_if[i].ARLEN;
    assign s_arsize[i*3 +: 3]    = s_if[i].ARSIZE;
    assign s_arburst[i*2 +: 2]   = s_if[i].ARBURST;
    assign s_arlock[i]           = s_if[i].ARLOCK;
    assign s_arcache[i*4 +: 4]   = s_if[i].ARCACHE;
    assign s_arprot[i*3 +: 3]    = s_if[i].ARPROT;
    assign s_arqos[i*4 +: 4]     = s_if[i].ARQOS;
    assign s_aruser[i*USER_WIDTH +: USER_WIDTH] = s_if[i].ARUSER[USER_WIDTH-1:0];
    assign s_arvalid[i]          = s_if[i].ARVALID;
    assign s_rready[i]           = s_if[i].RREADY;
    // crossbar -> VIP master
    assign s_if[i].AWREADY = s_awready[i];
    assign s_if[i].WREADY  = s_wready[i];
    assign s_if[i].BID     = s_bid[i*S_ID_WIDTH +: S_ID_WIDTH];
    assign s_if[i].BRESP   = s_bresp[i*2 +: 2];
    assign s_if[i].BUSER   = s_buser[i*USER_WIDTH +: USER_WIDTH];
    assign s_if[i].BVALID  = s_bvalid[i];
    assign s_if[i].ARREADY = s_arready[i];
    assign s_if[i].RID     = s_rid[i*S_ID_WIDTH +: S_ID_WIDTH];
    assign s_if[i].RDATA   = s_rdata[i*DATA_WIDTH +: DATA_WIDTH];
    assign s_if[i].RRESP   = s_rresp[i*2 +: 2];
    assign s_if[i].RLAST   = s_rlast[i];
    assign s_if[i].RUSER   = s_ruser[i*USER_WIDTH +: USER_WIDTH];
    assign s_if[i].RVALID  = s_rvalid[i];
  end

  for (genvar i = 0; i < M_COUNT; i++) begin : g_m
    // crossbar -> VIP slave
    assign m_if[i].AWID     = m_awid[i*M_ID_WIDTH +: M_ID_WIDTH];
    assign m_if[i].AWADDR   = m_awaddr[i*ADDR_WIDTH +: ADDR_WIDTH];
    assign m_if[i].AWLEN    = m_awlen[i*8 +: 8];
    assign m_if[i].AWSIZE   = m_awsize[i*3 +: 3];
    assign m_if[i].AWBURST  = m_awburst[i*2 +: 2];
    assign m_if[i].AWLOCK   = m_awlock[i];
    assign m_if[i].AWCACHE  = m_awcache[i*4 +: 4];
    assign m_if[i].AWPROT   = m_awprot[i*3 +: 3];
    assign m_if[i].AWQOS    = m_awqos[i*4 +: 4];
    assign m_if[i].AWREGION = m_awregion[i*4 +: 4];
    assign m_if[i].AWUSER   = m_awuser[i*USER_WIDTH +: USER_WIDTH];
    assign m_if[i].AWVALID  = m_awvalid[i];
    assign m_if[i].WDATA    = m_wdata[i*DATA_WIDTH +: DATA_WIDTH];
    assign m_if[i].WSTRB    = m_wstrb[i*STRB_WIDTH +: STRB_WIDTH];
    assign m_if[i].WLAST    = m_wlast[i];
    assign m_if[i].WUSER    = m_wuser[i*USER_WIDTH +: USER_WIDTH];
    assign m_if[i].WVALID   = m_wvalid[i];
    assign m_if[i].BREADY   = m_bready[i];
    assign m_if[i].ARID     = m_arid[i*M_ID_WIDTH +: M_ID_WIDTH];
    assign m_if[i].ARADDR   = m_araddr[i*ADDR_WIDTH +: ADDR_WIDTH];
    assign m_if[i].ARLEN    = m_arlen[i*8 +: 8];
    assign m_if[i].ARSIZE   = m_arsize[i*3 +: 3];
    assign m_if[i].ARBURST  = m_arburst[i*2 +: 2];
    assign m_if[i].ARLOCK   = m_arlock[i];
    assign m_if[i].ARCACHE  = m_arcache[i*4 +: 4];
    assign m_if[i].ARPROT   = m_arprot[i*3 +: 3];
    assign m_if[i].ARQOS    = m_arqos[i*4 +: 4];
    assign m_if[i].ARREGION = m_arregion[i*4 +: 4];
    assign m_if[i].ARUSER   = m_aruser[i*USER_WIDTH +: USER_WIDTH];
    assign m_if[i].ARVALID  = m_arvalid[i];
    assign m_if[i].RREADY   = m_rready[i];
    // VIP slave -> crossbar
    assign m_awready[i] = m_if[i].AWREADY;
    assign m_wready[i]  = m_if[i].WREADY;
    assign m_bid[i*M_ID_WIDTH +: M_ID_WIDTH] = m_if[i].BID[M_ID_WIDTH-1:0];
    assign m_bresp[i*2 +: 2] = m_if[i].BRESP;
    assign m_buser[i*USER_WIDTH +: USER_WIDTH] = m_if[i].BUSER[USER_WIDTH-1:0];
    assign m_bvalid[i]  = m_if[i].BVALID;
    assign m_arready[i] = m_if[i].ARREADY;
    assign m_rid[i*M_ID_WIDTH +: M_ID_WIDTH] = m_if[i].RID[M_ID_WIDTH-1:0];
    assign m_rdata[i*DATA_WIDTH +: DATA_WIDTH] = m_if[i].RDATA;
    assign m_rresp[i*2 +: 2] = m_if[i].RRESP;
    assign m_rlast[i]   = m_if[i].RLAST;
    assign m_ruser[i*USER_WIDTH +: USER_WIDTH] = m_if[i].RUSER[USER_WIDTH-1:0];
    assign m_rvalid[i]  = m_if[i].RVALID;
  end

  axi_crossbar #(
    .S_COUNT(S_COUNT), .M_COUNT(M_COUNT), .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .STRB_WIDTH(STRB_WIDTH),
    .S_ID_WIDTH(S_ID_WIDTH), .M_ID_WIDTH(M_ID_WIDTH),
    .AWUSER_ENABLE(1), .AWUSER_WIDTH(USER_WIDTH), .WUSER_ENABLE(1), .WUSER_WIDTH(USER_WIDTH),
    .BUSER_ENABLE(1), .BUSER_WIDTH(USER_WIDTH), .ARUSER_ENABLE(1), .ARUSER_WIDTH(USER_WIDTH),
    .RUSER_ENABLE(1), .RUSER_WIDTH(USER_WIDTH),
    .S_THREADS(S_THREADS), .S_ACCEPT(S_ACCEPT), .M_REGIONS(M_REGIONS),
    .M_BASE_ADDR(M_BASE_ADDR), .M_ADDR_WIDTH(M_ADDR_WIDTH),
    .M_CONNECT_READ(CFG_CONNECT_READ), .M_CONNECT_WRITE(CFG_CONNECT_WRITE), .M_ISSUE(CFG_ISSUE), .M_SECURE(CFG_SECURE),
    .S_AW_REG_TYPE(S_AW_REG_TYPE), .S_W_REG_TYPE(S_W_REG_TYPE), .S_B_REG_TYPE(S_B_REG_TYPE),
    .S_AR_REG_TYPE(S_AR_REG_TYPE), .S_R_REG_TYPE(S_R_REG_TYPE),
    .M_AW_REG_TYPE(M_AW_REG_TYPE), .M_W_REG_TYPE(M_W_REG_TYPE), .M_B_REG_TYPE(M_B_REG_TYPE),
    .M_AR_REG_TYPE(M_AR_REG_TYPE), .M_R_REG_TYPE(M_R_REG_TYPE)
  ) dut (
    .clk(clk_rst.clk), .rst(clk_rst.rst),
    .s_axi_awid(s_awid), .s_axi_awaddr(s_awaddr), .s_axi_awlen(s_awlen), .s_axi_awsize(s_awsize), .s_axi_awburst(s_awburst),
    .s_axi_awlock(s_awlock), .s_axi_awcache(s_awcache), .s_axi_awprot(s_awprot), .s_axi_awqos(s_awqos), .s_axi_awuser(s_awuser),
    .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
    .s_axi_wdata(s_wdata), .s_axi_wstrb(s_wstrb), .s_axi_wlast(s_wlast), .s_axi_wuser(s_wuser), .s_axi_wvalid(s_wvalid), .s_axi_wready(s_wready),
    .s_axi_bid(s_bid), .s_axi_bresp(s_bresp), .s_axi_buser(s_buser), .s_axi_bvalid(s_bvalid), .s_axi_bready(s_bready),
    .s_axi_arid(s_arid), .s_axi_araddr(s_araddr), .s_axi_arlen(s_arlen), .s_axi_arsize(s_arsize), .s_axi_arburst(s_arburst),
    .s_axi_arlock(s_arlock), .s_axi_arcache(s_arcache), .s_axi_arprot(s_arprot), .s_axi_arqos(s_arqos), .s_axi_aruser(s_aruser),
    .s_axi_arvalid(s_arvalid), .s_axi_arready(s_arready),
    .s_axi_rid(s_rid), .s_axi_rdata(s_rdata), .s_axi_rresp(s_rresp), .s_axi_rlast(s_rlast), .s_axi_ruser(s_ruser),
    .s_axi_rvalid(s_rvalid), .s_axi_rready(s_rready),
    .m_axi_awid(m_awid), .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen), .m_axi_awsize(m_awsize), .m_axi_awburst(m_awburst),
    .m_axi_awlock(m_awlock), .m_axi_awcache(m_awcache), .m_axi_awprot(m_awprot), .m_axi_awqos(m_awqos), .m_axi_awregion(m_awregion),
    .m_axi_awuser(m_awuser), .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
    .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb), .m_axi_wlast(m_wlast), .m_axi_wuser(m_wuser), .m_axi_wvalid(m_wvalid), .m_axi_wready(m_wready),
    .m_axi_bid(m_bid), .m_axi_bresp(m_bresp), .m_axi_buser(m_buser), .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready),
    .m_axi_arid(m_arid), .m_axi_araddr(m_araddr), .m_axi_arlen(m_arlen), .m_axi_arsize(m_arsize), .m_axi_arburst(m_arburst),
    .m_axi_arlock(m_arlock), .m_axi_arcache(m_arcache), .m_axi_arprot(m_arprot), .m_axi_arqos(m_arqos), .m_axi_arregion(m_arregion),
    .m_axi_aruser(m_aruser), .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
    .m_axi_rid(m_rid), .m_axi_rdata(m_rdata), .m_axi_rresp(m_rresp), .m_axi_rlast(m_rlast), .m_axi_ruser(m_ruser),
    .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready)
  );

  initial begin
    uvm_config_db#(virtual axi4_if)::set(null, "uvm_test_top", "s_vif0", s_if[0]);
    uvm_config_db#(virtual axi4_if)::set(null, "uvm_test_top", "s_vif1", s_if[1]);
    uvm_config_db#(virtual axi4_if)::set(null, "uvm_test_top", "m_vif0", m_if[0]);
    uvm_config_db#(virtual axi4_if)::set(null, "uvm_test_top", "m_vif1", m_if[1]);
    uvm_config_db#(virtual axi4_if)::set(null, "uvm_test_top", "m_vif2", m_if[2]);
    uvm_config_db#(virtual dv_clk_rst_if)::set(null, "uvm_test_top", "clk_rst_vif", clk_rst);
    uvm_config_db#(int)::set(null, "uvm_test_top", "xbar_open", OPEN);
    for (int i = 0; i < M_COUNT; i++)
      uvm_config_db#(int)::set(null, "uvm_test_top", $sformatf("m_issue%0d", i), CFG_ISSUE[i*32 +: 32]);
    // Register-slice types that were really built into the write and read
    // halves of the crossbar, for xbar_param_test (known issue XBAR-06).
    uvm_config_db#(int)::set(null, "uvm_test_top", "m_reg_types_built",
        {dut.axi_crossbar_rd_inst.M_R_REG_TYPE[M_COUNT*2-1:0], dut.axi_crossbar_rd_inst.M_AR_REG_TYPE[M_COUNT*2-1:0],
         dut.axi_crossbar_wr_inst.M_B_REG_TYPE[M_COUNT*2-1:0], dut.axi_crossbar_wr_inst.M_W_REG_TYPE[M_COUNT*2-1:0],
         dut.axi_crossbar_wr_inst.M_AW_REG_TYPE[M_COUNT*2-1:0]});
    uvm_config_db#(int)::set(null, "uvm_test_top", "m_reg_types_requested",
        {M_R_REG_TYPE, M_AR_REG_TYPE, M_B_REG_TYPE, M_W_REG_TYPE, M_AW_REG_TYPE});
    run_test();
  end
endmodule
