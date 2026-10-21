// Crossbar configuration used by the testbench top (DUT parameters) and by the
// reference model in the scoreboard.  The values are packed exactly as
// axi_crossbar expects them: field 0 in the least significant bits.
//
// Address map (slave = crossbar master interface, 3 regions each):
//   slave 0 : r0 0x0000_0000/28   r1 0xF000_0000/28   r2 0x1000_0000/12
//   slave 1 : r0 0x3000_0000/28   r1 0xC000_0000/28   r2 unused
//   slave 2 : r0 0x5000_0000/28   r1 0xA000_0000/28   r2 0x8000_0000/16   (secure)
//   everything else is unmapped and must answer DECERR
// The two large regions of a slave differ in all four top address bits, so
// every address bit can toggle on every slave port.
// Connectivity: master 1 cannot write slave 1; master 0 cannot read slave 2.
package xbar_cfg_pkg;
  localparam int S_COUNT    = 2;   // AXI masters connected to the crossbar
  localparam int M_COUNT    = 3;   // AXI slaves connected to the crossbar
  localparam int M_REGIONS  = 3;
  localparam int ADDR_WIDTH = 32;
  localparam int DATA_WIDTH = 32;
  localparam int STRB_WIDTH = DATA_WIDTH / 8;
  localparam int S_ID_WIDTH = 4;
  localparam int M_ID_WIDTH = S_ID_WIDTH + $clog2(S_COUNT);
  localparam int USER_WIDTH = 2;

  localparam bit [M_COUNT*M_REGIONS*ADDR_WIDTH-1:0] M_BASE_ADDR = {
    32'h8000_0000, 32'hA000_0000, 32'h5000_0000,    // slave 2: r2, r1, r0
    32'h0000_0000, 32'hC000_0000, 32'h3000_0000,    // slave 1: r2 (unused), r1, r0
    32'h1000_0000, 32'hF000_0000, 32'h0000_0000 };  // slave 0: r2, r1, r0
  localparam bit [M_COUNT*M_REGIONS*32-1:0] M_ADDR_WIDTH = {
    32'd16, 32'd28, 32'd28,
    32'd0,  32'd28, 32'd28,
    32'd12, 32'd28, 32'd28 };
  // Bit (slave*S_COUNT + master).
  localparam bit [M_COUNT*S_COUNT-1:0] M_CONNECT_READ  = {2'b10, 2'b11, 2'b11};
  localparam bit [M_COUNT*S_COUNT-1:0] M_CONNECT_WRITE = {2'b11, 2'b01, 2'b11};
  localparam bit [M_COUNT-1:0]         M_SECURE        = 3'b100;

  // Concurrency limits.  Master 0 asks for more ID threads than it may have
  // operations in flight; the crossbar limits the thread count and warns.
  localparam bit [S_COUNT*32-1:0] S_THREADS = {32'd2, 32'd4};
  localparam bit [S_COUNT*32-1:0] S_ACCEPT  = {32'd4, 32'd2};
  localparam bit [M_COUNT*32-1:0] M_ISSUE      = {32'd1, 32'd2, 32'd4};   // slave 2, 1, 0
  localparam bit [M_COUNT*32-1:0] M_ISSUE_OPEN = {32'd2, 32'd4, 32'd1};   // build "open"

  // Register slices: every type (0 bypass, 1 simple buffer, 2 skid buffer) is
  // used on every channel by at least one port.
  localparam bit [S_COUNT*2-1:0] S_AW_REG_TYPE = {2'd1, 2'd0};
  localparam bit [S_COUNT*2-1:0] S_W_REG_TYPE  = {2'd2, 2'd0};
  localparam bit [S_COUNT*2-1:0] S_B_REG_TYPE  = {2'd0, 2'd1};
  localparam bit [S_COUNT*2-1:0] S_AR_REG_TYPE = {2'd1, 2'd0};
  localparam bit [S_COUNT*2-1:0] S_R_REG_TYPE  = {2'd0, 2'd2};
  localparam bit [M_COUNT*2-1:0] M_AW_REG_TYPE = {2'd0, 2'd2, 2'd1};
  localparam bit [M_COUNT*2-1:0] M_W_REG_TYPE  = {2'd0, 2'd1, 2'd2};
  localparam bit [M_COUNT*2-1:0] M_B_REG_TYPE  = {2'd1, 2'd2, 2'd0};
  localparam bit [M_COUNT*2-1:0] M_AR_REG_TYPE = {2'd0, 2'd2, 2'd1};
  localparam bit [M_COUNT*2-1:0] M_R_REG_TYPE  = {2'd2, 2'd1, 2'd0};

  function automatic bit [ADDR_WIDTH-1:0] region_base(int m, int r);
    return M_BASE_ADDR[(m*M_REGIONS + r)*ADDR_WIDTH +: ADDR_WIDTH];
  endfunction
  function automatic int region_width(int m, int r);
    return M_ADDR_WIDTH[(m*M_REGIONS + r)*32 +: 32];
  endfunction
  function automatic bit [ADDR_WIDTH-1:0] region_last(int m, int r);
    return region_base(m, r) | ((64'd1 << region_width(m, r)) - 1);
  endfunction
endpackage
