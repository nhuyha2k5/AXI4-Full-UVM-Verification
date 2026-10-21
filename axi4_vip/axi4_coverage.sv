// =============================================================================
// AXI4 functional coverage.
//
// Each feature has its own covergroup, instantiated per direction (write and
// read) and only when axi4_agent_cfg declares that the port can show that
// feature (cov_* knobs).  A port that can only issue INCR bursts therefore has
// no FIXED/WRAP bins at all, instead of bins that can never be hit.
// =============================================================================

// Burst length up to 16 beats.
covergroup axi4_cg_len_short (string nm) with function sample(bit [7:0] len);
  option.per_instance = 1;
  option.name = nm;
  cp_len: coverpoint len {
    bins beats_1    = {0};
    bins beats_2_4  = {[1:3]};
    bins beats_5_8  = {[4:7]};
    bins beats_9_16 = {[8:15]};
  }
endgroup

// Burst length above 16 beats (INCR only).
covergroup axi4_cg_len_long (string nm) with function sample(bit [7:0] len);
  option.per_instance = 1;
  option.name = nm;
  cp_len: coverpoint len {
    bins beats_17_64   = {[16:63]};
    bins beats_65_128  = {[64:127]};
    bins beats_129_255 = {[128:254]};
    bins beats_256     = {255};
  }
endgroup

// FIXED bursts next to INCR.
covergroup axi4_cg_burst (string nm) with function sample(bit [1:0] burst);
  option.per_instance = 1;
  option.name = nm;
  cp_burst: coverpoint burst {
    bins fixed = {2'b00};
    bins incr  = {2'b01};
  }
endgroup

// WRAP bursts of every legal length, starting on and off the wrap boundary.
covergroup axi4_cg_wrap (string nm) with function sample(bit [7:0] len, bit at_boundary);
  option.per_instance = 1;
  option.name = nm;
  cp_wrap_len: coverpoint len {
    bins wrap_2  = {1};
    bins wrap_4  = {3};
    bins wrap_8  = {7};
    bins wrap_16 = {15};
  }
  cp_wrap_start: coverpoint at_boundary { bins wraps_around = {0}; bins starts_at_boundary = {1}; }
endgroup

// Transfer size from one byte up to the full bus width.
covergroup axi4_cg_size (string nm, int max_size) with function sample(bit [2:0] size);
  option.per_instance = 1;
  option.name = nm;
  cp_size: coverpoint size { bins sz[] = {[0:max_size]}; }
endgroup

// Start address aligned or not to the transfer size.
covergroup axi4_cg_align (string nm) with function sample(bit unaligned);
  option.per_instance = 1;
  option.name = nm;
  cp_align: coverpoint unaligned { bins aligned = {0}; bins unaligned = {1}; }
endgroup

// Error responses.
covergroup axi4_cg_resp (string nm) with function sample(bit [1:0] resp);
  option.per_instance = 1;
  option.name = nm;
  cp_resp: coverpoint resp {
    bins okay   = {2'b00};
    bins slverr = {2'b10};
    bins decerr = {2'b11};
  }
endgroup

// ID values in use.
covergroup axi4_cg_id (string nm, int max_id, int mid_lo, int mid_hi) with function sample(axi4_id_t id);
  option.per_instance = 1;
  option.name = nm;
  cp_id: coverpoint id {
    bins id_zero = {0};
    bins id_max  = {max_id};
    bins id_mid  = {[mid_lo:mid_hi]};   // equals the full range when the ID is one bit wide
  }
endgroup

// Transactions of the same direction already in flight when one is accepted.
covergroup axi4_cg_outstanding (string nm) with function sample(int unsigned outstanding);
  option.per_instance = 1;
  option.name = nm;
  cp_outstanding: coverpoint outstanding { bins none = {0}; bins one = {1}; }
endgroup

// Two or more already in flight (ports that can pipeline that deep).
covergroup axi4_cg_outstanding_deep (string nm) with function sample(int unsigned outstanding);
  option.per_instance = 1;
  option.name = nm;
  cp_outstanding: coverpoint outstanding { bins two_plus = {[2:$]}; }
endgroup

// LOCK / CACHE.
covergroup axi4_cg_sideband (string nm) with function sample(bit lock, bit [3:0] cache);
  option.per_instance = 1;
  option.name = nm;
  cp_lock:   coverpoint lock;
  cp_cache:  coverpoint cache  { bins c[4] = {[0:15]}; }
endgroup

// PROT (all eight values).
covergroup axi4_cg_prot (string nm) with function sample(bit [2:0] prot);
  option.per_instance = 1;
  option.name = nm;
  cp_prot: coverpoint prot;
endgroup

// QOS.  (AxREGION is produced by an interconnect, so its coverage belongs to
// the testbench of that interconnect, not to the generic port model.)
covergroup axi4_cg_qos (string nm) with function sample(bit [3:0] qos);
  option.per_instance = 1;
  option.name = nm;
  cp_qos: coverpoint qos { bins q[4] = {[0:15]}; }
endgroup

// Backpressure seen on the address and data phases.
covergroup axi4_cg_stall (string nm) with function sample(int unsigned addr_stall, int unsigned data_stall);
  option.per_instance = 1;
  option.name = nm;
  cp_addr_stall: coverpoint addr_stall { bins short_ = {[1:3]}; bins long_ = {[4:$]}; }
  cp_data_stall: coverpoint data_stall { bins short_ = {[1:3]}; bins long_ = {[4:$]}; }
endgroup

// Backpressure on the write response channel.
covergroup axi4_cg_bstall (string nm) with function sample(int unsigned resp_stall);
  option.per_instance = 1;
  option.name = nm;
  cp_resp_stall: coverpoint resp_stall { bins stalled = {[1:$]}; }
endgroup

// A phase that went through without a single stalled cycle.  One instance per
// channel; a covergroup of its own because some ports cannot show it (for
// example a response that has to win an arbitration first), see the
// cov_*_nostall knobs of axi4_agent_cfg.
covergroup axi4_cg_nostall (string nm) with function sample(int unsigned stall);
  option.per_instance = 1;
  option.name = nm;
  cp_stall: coverpoint stall { bins none = {0}; }
endgroup

// Write strobes: all valid lanes, a subset, or none.
covergroup axi4_cg_strobe (string nm) with function sample(bit [1:0] kind);
  option.per_instance = 1;
  option.name = nm;
  cp_strb: coverpoint kind { bins full = {0}; bins partial = {1}; bins none = {2}; }
endgroup

class axi4_coverage extends uvm_subscriber #(axi4_seq_item);
  `uvm_component_utils(axi4_coverage)

  axi4_agent_cfg cfg;

  // Index 0 = read, 1 = write.
  axi4_cg_len_short cg_len_short[2];
  axi4_cg_len_long  cg_len_long[2];
  axi4_cg_burst     cg_burst[2];
  axi4_cg_wrap      cg_wrap[2];
  axi4_cg_qos       cg_qos[2];
  axi4_cg_size      cg_size[2];
  axi4_cg_align     cg_align[2];
  axi4_cg_resp      cg_resp[2];
  axi4_cg_id        cg_id[2];
  axi4_cg_outstanding      cg_out[2];
  axi4_cg_outstanding_deep cg_out_deep[2];
  axi4_cg_sideband  cg_sideband[2];
  axi4_cg_prot      cg_prot[2];
  axi4_cg_stall     cg_stall[2];
  axi4_cg_nostall   cg_addr_nostall[2];
  axi4_cg_nostall   cg_data_nostall[2];
  axi4_cg_nostall   cg_resp_nostall;
  axi4_cg_bstall    cg_bstall;
  axi4_cg_strobe    cg_strobe;

  function new(string n, uvm_component p);
    super.new(n, p);
  endfunction

  function void build_phase(uvm_phase phase);
    string dir[2] = '{"rd", "wr"};
    bit    en[2];
    if (cfg == null && !uvm_config_db#(axi4_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CFG", "Missing axi4_agent_cfg")
    en[0] = cfg.cov_rd; en[1] = cfg.cov_wr;
    for (int d = 0; d < 2; d++) begin
      string nm = {cfg.name, "_", dir[d]};
      if (!en[d]) continue;
      cg_len_short[d] = new({nm, "_len_short"});
      cg_stall[d]     = new({nm, "_stall"});
      if (d ? cfg.cov_aw_nostall : cfg.cov_ar_nostall) cg_addr_nostall[d] = new({nm, "_addr_nostall"});
      if (d ? cfg.cov_w_nostall  : cfg.cov_r_nostall)  cg_data_nostall[d] = new({nm, "_data_nostall"});
      if (cfg.cov_long_bursts) cg_len_long[d] = new({nm, "_len_long"});
      if (cfg.cov_fixed)       cg_burst[d]    = new({nm, "_burst"});
      if (cfg.cov_wrap)        cg_wrap[d]     = new({nm, "_wrap"});
      if (cfg.cov_qos)         cg_qos[d]      = new({nm, "_qos"});
      if (cfg.cov_narrow)      cg_size[d]     = new({nm, "_size"}, AXI4_MAX_SIZE);
      if (cfg.cov_unaligned)   cg_align[d]    = new({nm, "_align"});
      if (cfg.cov_err_resp)    cg_resp[d]     = new({nm, "_resp"});
      if (cfg.cov_sideband)    cg_sideband[d] = new({nm, "_sideband"});
      if (cfg.cov_prot)        cg_prot[d]     = new({nm, "_prot"});
      if (cfg.cov_outstanding >= 1) cg_out[d]      = new({nm, "_outstanding"});
      if (cfg.cov_outstanding >= 2) cg_out_deep[d] = new({nm, "_outstanding_deep"});
      if (cfg.cov_multi_id) begin
        int max_id = (1 << cfg.id_width) - 1;
        if (max_id >= 2) cg_id[d] = new({nm, "_id"}, max_id, 1, max_id - 1);
        else             cg_id[d] = new({nm, "_id"}, max_id, 0, max_id);
      end
    end
    if (cfg.cov_wr) cg_bstall = new({cfg.name, "_wr_bstall"});
    if (cfg.cov_wr && cfg.cov_b_nostall) cg_resp_nostall = new({cfg.name, "_wr_resp_nostall"});
    if (cfg.cov_wr && cfg.cov_sparse_strb) cg_strobe = new({cfg.name, "_wr_strobe"});
  endfunction

  function void write(axi4_seq_item t);
    int         d = (t.cmd == AXI4_WRITE);
    bit [1:0]   resp;
    if (cg_len_short[d] == null) return;
    cg_len_short[d].sample(t.len);
    cg_stall[d].sample(t.addr_stall, t.data_stall);
    if (cg_addr_nostall[d] != null) cg_addr_nostall[d].sample(t.addr_stall);
    if (cg_data_nostall[d] != null) cg_data_nostall[d].sample(t.data_stall);
    if (t.cmd == AXI4_WRITE && cg_bstall != null) cg_bstall.sample(t.resp_stall);
    if (t.cmd == AXI4_WRITE && cg_resp_nostall != null) cg_resp_nostall.sample(t.resp_stall);
    if (cg_len_long[d] != null && t.len > 15) cg_len_long[d].sample(t.len);
    if (cg_burst[d]    != null && t.burst != AXI4_BURST_WRAP) cg_burst[d].sample(t.burst);
    if (cg_wrap[d]     != null && t.burst == AXI4_BURST_WRAP) cg_wrap[d].sample(t.len, (t.addr % ((t.len + 1) << t.size)) == 0);
    if (cg_qos[d]      != null) cg_qos[d].sample(t.qos);
    if (cg_size[d]     != null) cg_size[d].sample(t.size);
    if (cg_align[d]    != null) cg_align[d].sample(!axi4_is_aligned(t.addr, t.size));
    if (cg_id[d]       != null) cg_id[d].sample(t.id);
    if (cg_out[d]      != null && t.outstanding < 2)  cg_out[d].sample(t.outstanding);
    if (cg_out_deep[d] != null && t.outstanding >= 2) cg_out_deep[d].sample(t.outstanding);
    if (cg_sideband[d] != null) cg_sideband[d].sample(t.lock, t.cache);
    if (cg_prot[d]     != null) cg_prot[d].sample(t.prot);
    if (cg_resp[d] != null) begin
      resp = t.bresp;
      if (t.cmd == AXI4_READ) begin
        resp = AXI4_RESP_OKAY;
        foreach (t.rresp[i]) if (t.rresp[i] != AXI4_RESP_OKAY) resp = t.rresp[i];
      end
      cg_resp[d].sample(resp);
    end
    if (t.cmd == AXI4_WRITE && cg_strobe != null) begin
      bit any_partial = 0, any_set = 0;
      foreach (t.strb[i]) begin
        axi4_strb_t mask = axi4_lane_mask(t.addr, i, t.len, t.size, t.burst);
        if (t.strb[i] != 0) any_set = 1;
        if (t.strb[i] != mask && t.strb[i] != 0) any_partial = 1;
      end
      cg_strobe.sample(!any_set ? 2 : (any_partial ? 1 : 0));
    end
  endfunction

  // Mean coverage of the covergroups this instance owns.
  function real get_coverage();
    real sum = 0; int n = 0;
    for (int d = 0; d < 2; d++) begin
      if (cg_len_short[d] != null) begin sum += cg_len_short[d].get_inst_coverage(); n++; end
      if (cg_stall[d]     != null) begin sum += cg_stall[d].get_inst_coverage();     n++; end
      if (cg_addr_nostall[d] != null) begin sum += cg_addr_nostall[d].get_inst_coverage(); n++; end
      if (cg_data_nostall[d] != null) begin sum += cg_data_nostall[d].get_inst_coverage(); n++; end
      if (cg_len_long[d]  != null) begin sum += cg_len_long[d].get_inst_coverage();  n++; end
      if (cg_burst[d]     != null) begin sum += cg_burst[d].get_inst_coverage();     n++; end
      if (cg_wrap[d]      != null) begin sum += cg_wrap[d].get_inst_coverage();      n++; end
      if (cg_qos[d]       != null) begin sum += cg_qos[d].get_inst_coverage();       n++; end
      if (cg_size[d]      != null) begin sum += cg_size[d].get_inst_coverage();      n++; end
      if (cg_align[d]     != null) begin sum += cg_align[d].get_inst_coverage();     n++; end
      if (cg_resp[d]      != null) begin sum += cg_resp[d].get_inst_coverage();      n++; end
      if (cg_id[d]        != null) begin sum += cg_id[d].get_inst_coverage();        n++; end
      if (cg_out[d]       != null) begin sum += cg_out[d].get_inst_coverage();       n++; end
      if (cg_out_deep[d]  != null) begin sum += cg_out_deep[d].get_inst_coverage();  n++; end
      if (cg_sideband[d]  != null) begin sum += cg_sideband[d].get_inst_coverage();  n++; end
      if (cg_prot[d]      != null) begin sum += cg_prot[d].get_inst_coverage();      n++; end
    end
    if (cg_bstall != null) begin sum += cg_bstall.get_inst_coverage(); n++; end
    if (cg_resp_nostall != null) begin sum += cg_resp_nostall.get_inst_coverage(); n++; end
    if (cg_strobe != null) begin sum += cg_strobe.get_inst_coverage(); n++; end
    return (n == 0) ? 100.0 : sum / n;
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("AXI_COV", $sformatf("%s: functional coverage of this test alone = %0.1f%%", cfg.name, get_coverage()), UVM_LOW)
  endfunction
endclass
