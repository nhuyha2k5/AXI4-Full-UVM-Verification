// =============================================================================
// Per-agent configuration.  One object per AXI4 port.  The testbench creates
// it, fills in the interface handle and the knobs it needs, and publishes it
// to the agent with uvm_config_db#(axi4_agent_cfg)::set(..., "cfg", cfg).
// All knobs may be changed while the test is running.
// =============================================================================
class axi4_agent_cfg extends uvm_object;
  `uvm_object_utils(axi4_agent_cfg)

  // ---------------- identity ----------------
  string                  name      = "axi4";
  axi4_agent_role_e       role      = AXI4_MASTER_AGENT;
  uvm_active_passive_enum is_active = UVM_ACTIVE;
  virtual axi4_if         vif;

  // Widths really used on this port (<= the compiled maximum).
  int unsigned addr_width = AXI4_ADDR_WIDTH;
  int unsigned id_width   = AXI4_ID_WIDTH;
  int unsigned user_width = AXI4_USER_WIDTH;

  // ---------------- checking / reporting ----------------
  bit          enable_checker       = 1;      // transaction-level protocol checks in the monitor
  bit          enable_coverage      = 1;
  bit          log_txn              = 1;      // one log line per completed transaction
  int unsigned timeout_cycles       = 20000;  // max age of an outstanding transaction
  bit          allow_pending_at_end = 0;      // tests that end with traffic in flight
  // While a channel's VALID is low its payload is "don't care".  With this knob
  // the drivers put random values there, so a DUT that looks at a payload
  // without qualifying it with VALID is found out.
  bit          randomize_idle       = 1;

  // ---------------- master knobs ----------------
  int unsigned max_wr_outstanding = 8;
  int unsigned max_rd_outstanding = 8;
  int unsigned aw_delay_max   = 0;    // idle cycles before AWVALID
  int unsigned w_delay_max    = 0;    // idle cycles before each WVALID
  int unsigned ar_delay_max   = 0;    // idle cycles before ARVALID
  int unsigned zero_delay_pct = 50;   // chance of no delay when a *_delay_max is non-zero
  int unsigned bready_pct     = 100;  // per-cycle chance that BREADY is high
  int unsigned rready_pct     = 100;  // per-cycle chance that RREADY is high
  bit          w_follows_aw   = 0;    // 1: a W burst starts only after its AW handshake

  // ---------------- slave knobs ----------------
  int unsigned awready_pct = 100;
  int unsigned wready_pct  = 100;
  int unsigned arready_pct = 100;
  int unsigned b_delay_max      = 0;  // cycles between write completion and BVALID
  int unsigned r_delay_max      = 0;  // cycles between AR and the first RVALID
  int unsigned r_beat_delay_max = 0;  // idle cycles between R beats
  int unsigned slv_max_wr = 16;       // AW accepted and not yet answered
  int unsigned slv_max_rd = 16;
  bit          b_reorder     = 0;     // B responses out of order across IDs
  bit          rd_reorder    = 0;     // read bursts out of order across IDs
  bit          rd_interleave = 0;     // R beats of different IDs interleaved
  axi4_resp_e  wr_resp      = AXI4_RESP_OKAY;  // response to every write
  axi4_resp_e  rd_resp      = AXI4_RESP_OKAY;  // response to read beats
  int          rd_resp_beat = -1;              // >=0: rd_resp only on this beat index
  // Address windows that answer with an error regardless of wr_resp/rd_resp.
  axi4_addr_t  err_lo[$];
  axi4_addr_t  err_hi[$];
  axi4_resp_e  err_resp[$];
  bit          rand_resp_user = 1;    // random BUSER/RUSER (user signals are free-form)
  axi4_mem_model mem;                 // storage; created by the agent when null

  // Protocol faults the slave can inject (for checker qualification only).
  bit inj_early_rlast = 0;   // RLAST one beat early
  bit inj_wrong_bid   = 0;   // BID with bit 0 flipped
  bit inj_no_b        = 0;   // never answer writes
  bit inj_no_r        = 0;   // never answer reads

  // ---------------- functional coverage scope ----------------
  // Bins exist only for behaviour the port can legally show in this testbench.
  bit cov_wr          = 1;
  bit cov_rd          = 1;
  bit cov_long_bursts = 1;   // bursts longer than 16 beats
  bit cov_fixed       = 1;   // FIXED bursts in addition to INCR
  bit cov_wrap        = 1;   // WRAP bursts
  bit cov_narrow      = 1;   // sizes below the bus width
  bit cov_unaligned   = 1;   // unaligned start address
  bit cov_err_resp    = 0;   // SLVERR / DECERR
  bit cov_multi_id    = 1;   // more than one ID value
  int cov_outstanding = 2;   // in-flight depth the port can reach: 0 none, 1 one other, 2 two or more
  bit cov_sideband    = 0;   // LOCK/CACHE
  bit cov_prot        = 0;   // PROT
  bit cov_qos         = 0;   // QOS
  bit cov_sparse_strb = 0;   // partial write strobes
  // A phase without any stalled cycle.  Clear the knob for a channel on which
  // the other side can never answer in the first cycle.
  bit cov_aw_nostall  = 1;
  bit cov_ar_nostall  = 1;
  bit cov_w_nostall   = 1;
  bit cov_r_nostall   = 1;
  bit cov_b_nostall   = 1;

  function new(string name = "axi4_agent_cfg");
    super.new(name);
  endfunction

  function void add_error_range(axi4_addr_t lo, axi4_addr_t hi, axi4_resp_e resp);
    err_lo.push_back(lo); err_hi.push_back(hi); err_resp.push_back(resp);
  endfunction

  // Convenience: same backpressure level on every channel the agent drives.
  function void set_backpressure(int unsigned ready_pct, int unsigned delay_max);
    bready_pct = ready_pct; rready_pct = ready_pct;
    awready_pct = ready_pct; wready_pct = ready_pct; arready_pct = ready_pct;
    aw_delay_max = delay_max; w_delay_max = delay_max; ar_delay_max = delay_max;
    b_delay_max = delay_max; r_delay_max = delay_max; r_beat_delay_max = delay_max;
  endfunction

  function string convert2string();
    string s;
    s = $sformatf("%s role=%s addr_w=%0d id_w=%0d user_w=%0d", name, role.name(), addr_width, id_width, user_width);
    if (role == AXI4_MASTER_AGENT)
      s = {s, $sformatf(" max_out(wr/rd)=%0d/%0d valid_delay_max(aw/w/ar)=%0d/%0d/%0d ready_pct(b/r)=%0d/%0d w_follows_aw=%0b",
                        max_wr_outstanding, max_rd_outstanding, aw_delay_max, w_delay_max, ar_delay_max,
                        bready_pct, rready_pct, w_follows_aw)};
    if (role == AXI4_SLAVE_AGENT)
      s = {s, $sformatf(" ready_pct(aw/w/ar)=%0d/%0d/%0d delay_max(b/r/rbeat)=%0d/%0d/%0d reorder(b/rd)=%0b/%0b interleave=%0b resp(wr/rd)=%s/%s err_windows=%0d",
                        awready_pct, wready_pct, arready_pct, b_delay_max, r_delay_max, r_beat_delay_max,
                        b_reorder, rd_reorder, rd_interleave, wr_resp.name(), rd_resp.name(), err_lo.size())};
    return s;
  endfunction
endclass
