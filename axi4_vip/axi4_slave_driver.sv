// =============================================================================
// Reactive AXI4 slave driver with a byte-addressable memory.
//
// Each channel is an independent thread, so the slave accepts new addresses
// while it is still returning data or responses.  W bursts may arrive before
// their AW.  Ready throttling, response delays, response ordering, error
// responses and protocol-fault injection are all controlled by axi4_agent_cfg
// and may change during the test.
// =============================================================================
class axi4_slave_driver extends uvm_driver #(axi4_seq_item);
  `uvm_component_utils(axi4_slave_driver)

  axi4_agent_cfg  cfg;
  virtual axi4_if vif;

  protected axi4_seq_item aw_fifo[$];   // accepted AW, data not yet matched
  protected axi4_seq_item w_fifo[$];    // complete W bursts, AW not yet matched
  protected axi4_data_t   wq_data[$];   // W burst being received
  protected axi4_strb_t   wq_strb[$];
  protected axi4_seq_item b_q[$];       // writes ready to be answered
  protected axi4_seq_item rd_q[$];      // accepted reads
  protected longint unsigned ready_at[axi4_seq_item];  // earliest response cycle
  protected int unsigned     rd_beat[axi4_seq_item];
  protected longint unsigned cycle;

  function new(string n, uvm_component p);
    super.new(n, p);
  endfunction

  function void build_phase(uvm_phase phase);
    if (cfg == null && !uvm_config_db#(axi4_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CFG", "Missing axi4_agent_cfg")
    vif = cfg.vif;
    if (vif == null) `uvm_fatal("CFG", {cfg.name, ": virtual interface not set"})
    if (cfg.mem == null) cfg.mem = axi4_mem_model::type_id::create({cfg.name, "_mem"});
  endfunction

  protected function void idle_signals();
    vif.AWREADY <= 1'b0; vif.WREADY <= 1'b0; vif.ARREADY <= 1'b0;
    vif.BVALID <= 1'b0; vif.BID <= '0; vif.BRESP <= '0; vif.BUSER <= '0;
    vif.RVALID <= 1'b0; vif.RID <= '0; vif.RDATA <= '0; vif.RRESP <= '0; vif.RLAST <= 1'b0; vif.RUSER <= '0;
  endfunction

  protected function void flush();
    aw_fifo.delete(); w_fifo.delete(); wq_data.delete(); wq_strb.delete();
    b_q.delete(); rd_q.delete(); ready_at.delete(); rd_beat.delete();
  endfunction

  // Response for an access to `addr`: an error window wins over the default.
  protected function axi4_resp_e resp_for(axi4_addr_t addr, axi4_resp_e dflt);
    foreach (cfg.err_lo[i])
      if (addr >= cfg.err_lo[i] && addr <= cfg.err_hi[i]) return cfg.err_resp[i];
    return dflt;
  endfunction

  task run_phase(uvm_phase phase);
    idle_signals();
    forever begin
      flush();
      idle_signals();
      do @(vif.cb); while (vif.cb.ARESETn !== 1'b1);
      fork begin : channels
        fork
          forever begin @(vif.cb); cycle++; end
          aw_thread();
          w_thread();
          b_thread();
          ar_thread();
          r_thread();
        join_none
        do @(vif.cb); while (vif.cb.ARESETn === 1'b1);
        disable fork;
      end join
    end
  endtask

  // Pair accepted AWs with complete W bursts in order and execute the write.
  protected function void match_writes();
    while (aw_fifo.size() > 0 && w_fifo.size() > 0) begin
      axi4_seq_item a = aw_fifo.pop_front();
      axi4_seq_item w = w_fifo.pop_front();
      a.bresp = resp_for(a.addr, cfg.wr_resp);
      if (a.bresp == AXI4_RESP_OKAY) begin
        foreach (w.data[i]) begin
          axi4_addr_t ba = axi4_beat_addr(a.addr, i, a.len, a.size, a.burst);
          for (int b = 0; b < AXI4_DATA_BYTES; b++)
            if (w.strb[i][b]) cfg.mem.write_byte(axi4_lane_addr(ba, b), w.data[i][8*b +: 8]);
        end
      end
      ready_at[a] = cycle + $urandom_range(cfg.b_delay_max, 0);
      b_q.push_back(a);
    end
  endfunction

  protected task aw_thread();
    forever begin
      vif.AWREADY <= ((aw_fifo.size() + b_q.size()) < cfg.slv_max_wr) && ($urandom_range(99, 0) < cfg.awready_pct);
      @(vif.cb);
      if (vif.cb.AWVALID === 1'b1 && vif.cb.AWREADY === 1'b1) begin
        axi4_seq_item a = axi4_seq_item::type_id::create("slv_aw");
        a.cmd = AXI4_WRITE; a.id = vif.cb.AWID; a.addr = vif.cb.AWADDR; a.len = vif.cb.AWLEN;
        a.size = vif.cb.AWSIZE; a.burst = axi4_burst_e'(vif.cb.AWBURST);
        aw_fifo.push_back(a);
        match_writes();
      end
    end
  endtask

  protected task w_thread();
    forever begin
      vif.WREADY <= (w_fifo.size() < cfg.slv_max_wr) && ($urandom_range(99, 0) < cfg.wready_pct);
      @(vif.cb);
      if (vif.cb.WVALID === 1'b1 && vif.cb.WREADY === 1'b1) begin
        wq_data.push_back(vif.cb.WDATA);
        wq_strb.push_back(vif.cb.WSTRB);
        if (vif.cb.WLAST === 1'b1) begin
          axi4_seq_item w = axi4_seq_item::type_id::create("slv_w");
          w.data = new[wq_data.size()]; w.strb = new[wq_strb.size()];
          foreach (wq_data[i]) begin w.data[i] = wq_data[i]; w.strb[i] = wq_strb[i]; end
          wq_data.delete(); wq_strb.delete();
          w_fifo.push_back(w);
          match_writes();
        end
      end
    end
  endtask

  // Index into `q` of the next transaction to answer, or -1.  Per-ID order is
  // always kept; with `reorder` any ID whose oldest entry is ready may go first.
  protected function int pick(ref axi4_seq_item q[$], input bit reorder);
    int cand[$];
    bit seen[axi4_id_t];
    foreach (q[i]) begin
      if (seen.exists(q[i].id)) continue;
      seen[q[i].id] = 1;
      if (ready_at[q[i]] <= cycle) begin
        if (!reorder) return i;
        cand.push_back(i);
      end else if (!reorder) return -1;
    end
    if (cand.size() == 0) return -1;
    return cand[$urandom_range(cand.size() - 1, 0)];
  endfunction

  protected task b_thread();
    int           idx;
    axi4_seq_item a;
    forever begin
      idx = cfg.inj_no_b ? -1 : pick(b_q, cfg.b_reorder);
      if (idx < 0) begin @(vif.cb); continue; end
      a = b_q[idx];
      vif.BID    <= cfg.inj_wrong_bid ? (a.id ^ 1) : a.id;
      vif.BRESP  <= a.bresp;
      vif.BUSER  <= cfg.rand_resp_user ? ($urandom() & ((1 << cfg.user_width) - 1)) : '0;
      vif.BVALID <= 1'b1;
      do @(vif.cb); while (vif.cb.BREADY !== 1'b1);
      vif.BVALID <= 1'b0;
      if (cfg.randomize_idle) begin vif.BID <= $urandom(); vif.BRESP <= $urandom(); vif.BUSER <= $urandom(); end
      ready_at.delete(a);
      remove(b_q, a);
    end
  endtask

  protected function void remove(ref axi4_seq_item q[$], input axi4_seq_item t);
    foreach (q[i]) if (q[i] == t) begin q.delete(i); return; end
  endfunction

  protected task ar_thread();
    forever begin
      vif.ARREADY <= (rd_q.size() < cfg.slv_max_rd) && ($urandom_range(99, 0) < cfg.arready_pct);
      @(vif.cb);
      if (vif.cb.ARVALID === 1'b1 && vif.cb.ARREADY === 1'b1) begin
        axi4_seq_item a = axi4_seq_item::type_id::create("slv_ar");
        a.cmd = AXI4_READ; a.id = vif.cb.ARID; a.addr = vif.cb.ARADDR; a.len = vif.cb.ARLEN;
        a.size = vif.cb.ARSIZE; a.burst = axi4_burst_e'(vif.cb.ARBURST);
        ready_at[a] = cycle + $urandom_range(cfg.r_delay_max, 0);
        rd_beat[a]  = 0;
        rd_q.push_back(a);
      end
    end
  endtask

  protected task r_thread();
    int              idx;
    axi4_seq_item    a;
    int unsigned     i;
    axi4_addr_t      ba;
    axi4_data_t      d;
    axi4_resp_e      resp;
    forever begin
      // Stay on the current burst unless interleaving is enabled.
      if (a == null || cfg.rd_interleave) begin
        idx = cfg.inj_no_r ? -1 : pick(rd_q, cfg.rd_reorder || cfg.rd_interleave);
        if (idx < 0) begin a = null; @(vif.cb); continue; end
        a = rd_q[idx];
      end
      i  = rd_beat[a];
      if (i != 0) repeat ($urandom_range(cfg.r_beat_delay_max, 0)) @(vif.cb);
      ba = axi4_beat_addr(a.addr, i, a.len, a.size, a.burst);
      for (int b = 0; b < AXI4_DATA_BYTES; b++) d[8*b +: 8] = cfg.mem.read_byte(axi4_lane_addr(ba, b));
      resp = resp_for(a.addr, AXI4_RESP_OKAY);
      if (resp == AXI4_RESP_OKAY && (cfg.rd_resp_beat < 0 || cfg.rd_resp_beat == i)) resp = cfg.rd_resp;
      vif.RID    <= a.id;
      vif.RDATA  <= d;
      vif.RRESP  <= resp;
      vif.RLAST  <= cfg.inj_early_rlast ? (i + 1 == a.len) : (i == a.len);
      vif.RUSER  <= cfg.rand_resp_user ? ($urandom() & ((1 << cfg.user_width) - 1)) : '0;
      vif.RVALID <= 1'b1;
      do @(vif.cb); while (vif.cb.RREADY !== 1'b1);
      vif.RVALID <= 1'b0;
      vif.RLAST  <= 1'b0;
      if (cfg.randomize_idle) begin
        vif.RID <= $urandom(); vif.RRESP <= $urandom(); vif.RLAST <= $urandom(); vif.RUSER <= $urandom();
        for (int k = 0; k < AXI4_DATA_WIDTH; k += 32) vif.RDATA[k +: 32] <= $urandom();
      end
      if (i == a.len) begin
        ready_at.delete(a); rd_beat.delete(a);
        remove(rd_q, a);
        a = null;
      end else begin
        rd_beat[a] = i + 1;
      end
    end
  endtask
endclass
