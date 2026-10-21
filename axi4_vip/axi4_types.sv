// Common AXI4 enums and typedefs used by the reusable VIP.
typedef enum bit { AXI4_READ = 1'b0, AXI4_WRITE = 1'b1 } axi4_cmd_e;

typedef enum bit [1:0] {
  AXI4_BURST_FIXED = 2'b00,
  AXI4_BURST_INCR  = 2'b01,
  AXI4_BURST_WRAP  = 2'b10,
  AXI4_BURST_RSVD  = 2'b11   // reserved encoding; never generated, only observed
} axi4_burst_e;

typedef enum bit [1:0] {
  AXI4_RESP_OKAY   = 2'b00,
  AXI4_RESP_EXOKAY = 2'b01,
  AXI4_RESP_SLVERR = 2'b10,
  AXI4_RESP_DECERR = 2'b11
} axi4_resp_e;

typedef enum int {
  AXI4_MASTER_AGENT,
  AXI4_SLAVE_AGENT,
  AXI4_PASSIVE_AGENT
} axi4_agent_role_e;

typedef bit [AXI4_ADDR_WIDTH-1:0]   axi4_addr_t;
typedef bit [AXI4_DATA_WIDTH-1:0]   axi4_data_t;
typedef bit [AXI4_DATA_WIDTH/8-1:0] axi4_strb_t;
typedef bit [AXI4_ID_WIDTH-1:0]     axi4_id_t;
typedef bit [AXI4_USER_WIDTH-1:0]   axi4_user_t;

localparam int AXI4_DATA_BYTES = AXI4_DATA_WIDTH / 8;
localparam int AXI4_MAX_SIZE   = $clog2(AXI4_DATA_WIDTH / 8);
