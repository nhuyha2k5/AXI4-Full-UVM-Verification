// =============================================================================
// AXI4 monitor and transaction-level protocol checker.
//
// Rebuilds transactions from the five channels and publishes them:
//   addr_ap : when the address phase (AW or AR) is accepted
//   ap      : when the transaction completes (B handshake or last R beat);
//             the same object that was sent on addr_ap, now complete
//
// Protocol rules checked here (reported as UVM_ERROR, id AXI_PROTOCOL):
//   - W beat count matches AWLEN and WLAST is on the last beat only
//   - a B response has an outstanding AW with that ID, and BVALID is asserted
//     only after the AW and the last W beat of that write were accepted (A3.3.1)
//   - an R beat has an outstanding AR with that ID, RVALID is asserted only
//     after that AR was accepted, and RLAST is on the last beat only
//   - EXOKAY only answers an exclusive access
//   - no transaction stays outstanding longer than cfg.timeout_cycles
//   - nothing is left outstanding at the end of the test
// =============================================================================
class axi4_monitor extends uvm_monitor;
  `uvm_component_utils(axi4_monitor)

  axi4_agent_cfg  cfg;
  virtual axi4_if vif;
  uvm_analysis_port #(axi4_seq_item) ap;
  uvm_analysis_port #(axi4_seq_item) addr_ap;

  protected axi4_seq_item aw_wait_w[$];              // AW accepted, W burst not yet seen
  protected axi4_seq_item w_orphans[$];              // W bursts completed before their AW
  protected axi4_data_t   wq_data[$];                // W burst in progress
  protected axi4_strb_t   wq_strb[$];
  protected axi4_user_t   wq_user[$];
  protected int unsigned  wq_stall;
  protected axi4_seq_item wr_by_id[axi4_id_t][$];
  protected axi4_seq_item rd_by_id[axi4_id_t][$];
  protected int unsigned  wr_out, rd_out;
  protected int unsigned  aw_stall, w_stall, b_stall, ar_stall;
  protected int unsigned  r_stall;
  protected longint unsigned wr_seq, rd_seq;
  protected longint unsigned cycle;
  protected axi4_resp_e   early_b[axi4_id_t][$];   // B responses that arrived before their AW
  protected bit           r_orphan_flagged;

  // Statistics for the end-of-test summary.
  int unsigned n_wr, n_rd, n_wr_beats, n_rd_beats, n_err_resp, n_proto_err, n_resets;
  int unsigned max_wr_out, max_rd_out;

  function new(string n, uvm_component p);
    super.new(n, p);
    ap      = new("ap", this);
    addr_ap = new("addr_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (cfg == null && !uvm_config_db#(axi4_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CFG", "Missing axi4_agent_cfg")
    vif = cfg.vif;
    if (vif == null) `uvm_fatal("CFG", {cfg.name, ": virtual interface not set"})
  endfunction

  protected function void proto_err(string msg);
    n_proto_err++;
    if (cfg.enable_checker) `uvm_error("AXI_PROTOCOL", {cfg.name, ": ", msg})
  endfunction

  protected function void flush();
    if (wr_out + rd_out + w_orphans.size() + wq_data.size() > 0)
      `uvm_info("AXI_MON", $sformatf("%s: reset dropped %0d write(s) and %0d read(s) in flight", cfg.name, wr_out, rd_out), UVM_MEDIUM)
    aw_wait_w.delete(); w_orphans.delete(); wq_data.delete(); wq_strb.delete(); wq_user.delete();
    wr_by_id.delete(); rd_by_id.delete(); early_b.delete(); r_orphan_flagged = 0;
    wr_out = 0; rd_out = 0; aw_stall = 0; w_stall = 0; b_stall = 0; ar_stall = 0; r_stall = 0; wq_stall = 0;
  endfunction

  task run_phase(uvm_phase phase);
    bit was_in_reset = 1;
    forever begin
      @(vif.cb);
      if (vif.cb.ARESETn !== 1'b1) begin
        if (!was_in_reset) begin n_resets++; flush(); end
        was_in_reset = 1;
        continue;
      end
      was_in_reset = 0;
      cycle++;
      watchdog();
      sample_aw();
      sample_w();
      sample_b();
      sample_ar();
      sample_r();
    end
  endtask

  protected function void watchdog();
    foreach (wr_by_id[id, i]) begin
      wr_by_id[id][i].age++;
      if (wr_by_id[id][i].age == cfg.timeout_cycles)
        proto_err($sformatf("write id=%0h addr=%h outstanding for %0d cycles", id, wr_by_id[id][i].addr, cfg.timeout_cycles));
    end
    foreach (rd_by_id[id, i]) begin
      rd_by_id[id][i].age++;
      if (rd_by_id[id][i].age == cfg.timeout_cycles)
        proto_err($sformatf("read id=%0h addr=%h outstanding for %0d cycles", id, rd_by_id[id][i].addr, cfg.timeout_cycles));
    end
  endfunction

  protected function void attach_w(axi4_seq_item t, axi4_seq_item w);
    t.data = w.data; t.strb = w.strb; t.wuser = w.wuser;
    t.data_stall = w.data_stall;
    t.mon_w_done  = 1;
    t.mon_w_cycle = cycle;
    if (t.data.size() != t.len + 1)
      proto_err($sformatf("write id=%0h addr=%h: %0d W beats for AWLEN=%0d (WLAST misplaced)", t.id, t.addr, t.data.size(), t.len));
  endfunction

  protected function void sample_aw();
    axi4_seq_item t;
    if (vif.cb.AWVALID !== 1'b1) return;
    if (vif.cb.AWREADY !== 1'b1) begin aw_stall++; return; end
    t = axi4_seq_item::type_id::create("wr");
    t.cmd = AXI4_WRITE; t.id = vif.cb.AWID; t.addr = vif.cb.AWADDR; t.len = vif.cb.AWLEN;
    t.size = vif.cb.AWSIZE; t.burst = axi4_burst_e'(vif.cb.AWBURST); t.lock = vif.cb.AWLOCK;
    t.cache = vif.cb.AWCACHE; t.prot = vif.cb.AWPROT; t.qos = vif.cb.AWQOS; t.region = vif.cb.AWREGION;
    t.auser = vif.cb.AWUSER;
    t.addr_stall = aw_stall; aw_stall = 0;
    t.seq_no = wr_seq++; t.outstanding = wr_out; t.t_start = $time;
    wr_out++; if (wr_out > max_wr_out) max_wr_out = wr_out;
    wr_by_id[t.id].push_back(t);
    if (w_orphans.size() > 0) begin
      t.w_before_aw = 1;
      attach_w(t, w_orphans.pop_front());
    end else begin
      aw_wait_w.push_back(t);
    end
    addr_ap.write(t);
    // The response to this write was already seen (and reported as issued
    // too early): close the transaction with it instead of waiting forever.
    if (early_b.exists(t.id) && early_b[t.id].size() > 0) begin
      t.bresp = early_b[t.id].pop_front();
      if (early_b[t.id].size() == 0) early_b.delete(t.id);
      void'(wr_by_id[t.id].pop_back());
      if (wr_by_id[t.id].size() == 0) wr_by_id.delete(t.id);
      wr_out--;
      n_wr++;
      complete(t);
    end
  endfunction

  protected function void sample_w();
    axi4_seq_item w;
    if (vif.cb.WVALID !== 1'b1) return;
    if (vif.cb.WREADY !== 1'b1) begin w_stall++; return; end
    wq_data.push_back(vif.cb.WDATA); wq_strb.push_back(vif.cb.WSTRB); wq_user.push_back(vif.cb.WUSER);
    for (int b = 0; b < AXI4_DATA_BYTES; b++)
      if (vif.cb.WSTRB[b] === 1'b1 && $isunknown(vif.cb.WDATA[8*b +: 8])) begin
        proto_err($sformatf("X/Z on WDATA byte lane %0d while its strobe is set", b));
        break;
      end
    if (w_stall > wq_stall) wq_stall = w_stall;
    w_stall = 0;
    n_wr_beats++;
    if (aw_wait_w.size() > 0 && vif.cb.WLAST !== 1'b1 && wq_data.size() == aw_wait_w[0].len + 1)
      proto_err($sformatf("write id=%0h addr=%h: WLAST missing on beat %0d (AWLEN=%0d)",
                          aw_wait_w[0].id, aw_wait_w[0].addr, wq_data.size(), aw_wait_w[0].len));
    if (vif.cb.WLAST !== 1'b1) return;
    w = axi4_seq_item::type_id::create("w_burst");
    w.data = new[wq_data.size()]; w.strb = new[wq_data.size()]; w.wuser = new[wq_data.size()];
    foreach (wq_data[i]) begin w.data[i] = wq_data[i]; w.strb[i] = wq_strb[i]; w.wuser[i] = wq_user[i]; end
    w.data_stall = wq_stall;
    wq_data.delete(); wq_strb.delete(); wq_user.delete(); wq_stall = 0;
    if (aw_wait_w.size() > 0) attach_w(aw_wait_w.pop_front(), w);
    else                      w_orphans.push_back(w);
  endfunction

  protected function void sample_b();
    axi4_seq_item t;
    axi4_id_t     id;
    if (vif.cb.BVALID !== 1'b1) return;
    id = vif.cb.BID;
    // A3.3.1: BVALID may only be asserted after the write's AW and last W beat
    // have been accepted, i.e. in a later cycle.  Checked once per response.
    if (wr_by_id.exists(id) && wr_by_id[id].size() > 0) begin
      t = wr_by_id[id][0];
      if (!t.mon_b_flagged && (!t.mon_w_done || t.mon_w_cycle == cycle)) begin
        axi4_resp_e r = axi4_resp_e'(vif.cb.BRESP);
        t.mon_b_flagged = 1;
        proto_err($sformatf("write id=%0h addr=%h: BVALID asserted before the last W beat was accepted (response %s issued too early)", id, t.addr, r.name()));
      end
    end
    if (vif.cb.BREADY !== 1'b1) begin b_stall++; return; end
    if (!wr_by_id.exists(id) || wr_by_id[id].size() == 0) begin
      axi4_resp_e r = axi4_resp_e'(vif.cb.BRESP);
      proto_err($sformatf("B response with BID=%0h has no accepted AW (response %s issued too early)", id, r.name()));
      early_b[id].push_back(r);
      b_stall = 0;
      return;
    end
    t = wr_by_id[id].pop_front();
    if (wr_by_id[id].size() == 0) wr_by_id.delete(id);
    // A write answered early stays in aw_wait_w so that its W burst, when it
    // arrives, is still associated with it and not with the next write.
    t.bresp = axi4_resp_e'(vif.cb.BRESP); t.buser = vif.cb.BUSER;
    t.resp_stall = b_stall; b_stall = 0;
    if (t.bresp == AXI4_RESP_EXOKAY && !t.lock)
      proto_err($sformatf("write id=%0h addr=%h: EXOKAY for a non-exclusive access", id, t.addr));
    wr_out--;
    n_wr++;
    complete(t);
  endfunction

  protected function void sample_ar();
    axi4_seq_item t;
    if (vif.cb.ARVALID !== 1'b1) return;
    if (vif.cb.ARREADY !== 1'b1) begin ar_stall++; return; end
    t = axi4_seq_item::type_id::create("rd");
    t.cmd = AXI4_READ; t.id = vif.cb.ARID; t.addr = vif.cb.ARADDR; t.len = vif.cb.ARLEN;
    t.size = vif.cb.ARSIZE; t.burst = axi4_burst_e'(vif.cb.ARBURST); t.lock = vif.cb.ARLOCK;
    t.cache = vif.cb.ARCACHE; t.prot = vif.cb.ARPROT; t.qos = vif.cb.ARQOS; t.region = vif.cb.ARREGION;
    t.auser = vif.cb.ARUSER;
    t.addr_stall = ar_stall; ar_stall = 0;
    t.seq_no = rd_seq++; t.outstanding = rd_out; t.t_start = $time;
    t.mon_w_cycle = cycle;   // acceptance cycle of the AR
    rd_out++; if (rd_out > max_rd_out) max_rd_out = rd_out;
    rd_by_id[t.id].push_back(t);
    addr_ap.write(t);
  endfunction

  protected function void sample_r();
    axi4_seq_item t;
    axi4_id_t     id;
    int unsigned  n;
    bit           last;
    if (vif.cb.RVALID !== 1'b1) begin r_orphan_flagged = 0; return; end
    id = vif.cb.RID;
    // A3.3.1: RVALID may only be asserted after the AR of that read was
    // accepted, i.e. in a later cycle.  Checked once per read.
    if (!rd_by_id.exists(id) || rd_by_id[id].size() == 0) begin
      if (!r_orphan_flagged) begin
        axi4_resp_e r = axi4_resp_e'(vif.cb.RRESP);
        proto_err($sformatf("R beat with RID=%0h has no accepted AR (response %s issued too early)", id, r.name()));
      end
      r_orphan_flagged = (vif.cb.RREADY !== 1'b1);
      r_stall = 0;
      return;
    end
    t = rd_by_id[id][0];
    if (!t.mon_b_flagged && t.rdata.size() == 0 && t.mon_w_cycle == cycle) begin
      axi4_resp_e r = axi4_resp_e'(vif.cb.RRESP);
      t.mon_b_flagged = 1;
      proto_err($sformatf("read id=%0h addr=%h: RVALID asserted before the AR handshake completed (response %s issued too early)", id, t.addr, r.name()));
    end
    if (vif.cb.RREADY !== 1'b1) begin r_stall++; return; end
    n = t.rdata.size();
    if (n <= t.len) begin
      axi4_strb_t mask = axi4_lane_mask(t.addr, n, t.len, t.size, t.burst);
      for (int b = 0; b < AXI4_DATA_BYTES; b++)
        if (mask[b] && $isunknown(vif.cb.RDATA[8*b +: 8])) begin
          proto_err($sformatf("read id=%0h addr=%h: X/Z on valid RDATA byte lane %0d of beat %0d", id, t.addr, b, n + 1));
          break;
        end
    end
    t.rdata = new[n + 1](t.rdata); t.rdata[n] = vif.cb.RDATA;
    t.rresp = new[n + 1](t.rresp); t.rresp[n] = axi4_resp_e'(vif.cb.RRESP);
    t.ruser = new[n + 1](t.ruser); t.ruser[n] = vif.cb.RUSER;
    if (r_stall > t.data_stall) t.data_stall = r_stall;
    r_stall = 0;
    n_rd_beats++;
    last = (vif.cb.RLAST === 1'b1);
    if (t.rresp[n] == AXI4_RESP_EXOKAY && !t.lock)
      proto_err($sformatf("read id=%0h addr=%h: EXOKAY for a non-exclusive access", id, t.addr));
    if (last != (n == t.len))
      proto_err($sformatf("read id=%0h addr=%h: RLAST=%0b on beat %0d of %0d", id, t.addr, last, n + 1, t.len + 1));
    if (!last && n != t.len) return;
    void'(rd_by_id[id].pop_front());
    if (rd_by_id[id].size() == 0) rd_by_id.delete(id);
    rd_out--;
    n_rd++;
    complete(t);
  endfunction

  protected function void complete(axi4_seq_item t);
    t.t_end = $time;
    t.done  = 1;
    if (t.has_error_resp()) n_err_resp++;
    if (cfg.log_txn)
      `uvm_info("AXI_TXN", $sformatf("%s: %s  stall(addr/data/resp)=%0d/%0d/%0d out=%0d t=%0t..%0t",
                cfg.name, t.convert2string(), t.addr_stall, t.data_stall, t.resp_stall, t.outstanding, t.t_start, t.t_end), UVM_MEDIUM)
    ap.write(t);
  endfunction

  // Transactions whose address has been accepted and whose response is not complete yet.
  function int unsigned num_outstanding();
    return wr_out + rd_out;
  endfunction
  function int unsigned num_wr_outstanding();
    return wr_out;
  endfunction
  function int unsigned num_rd_outstanding();
    return rd_out;
  endfunction

  function void check_phase(uvm_phase phase);
    if (!cfg.allow_pending_at_end && (wr_out + rd_out + w_orphans.size() > 0))
      proto_err($sformatf("%0d write(s), %0d read(s) and %0d W burst(s) without AW still outstanding at end of test",
                          wr_out, rd_out, w_orphans.size()));
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("AXI_MON", $sformatf("%s: writes=%0d (%0d beats) reads=%0d (%0d beats) error_responses=%0d max_outstanding(wr/rd)=%0d/%0d resets=%0d protocol_errors=%0d",
              cfg.name, n_wr, n_wr_beats, n_rd, n_rd_beats, n_err_resp, max_wr_out, max_rd_out, n_resets, n_proto_err), UVM_LOW)
  endfunction
endclass
