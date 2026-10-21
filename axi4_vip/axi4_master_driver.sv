// =============================================================================
// AXI4 master driver.
//
// The five channels run as independent threads, so address, data and response
// phases of different transactions overlap.  An item is taken from the
// sequencer as soon as the outstanding limit allows it and item_done() is
// called immediately; the sequence waits for completion on item.done when it
// needs the response.  This is what allows more than one transaction in
// flight.  A reset aborts everything in flight (item.aborted = 1).
// =============================================================================
class axi4_master_driver extends uvm_driver #(axi4_seq_item);
  `uvm_component_utils(axi4_master_driver)

  axi4_agent_cfg  cfg;
  virtual axi4_if vif;

  protected axi4_seq_item aw_q[$];     // address phase pending
  protected axi4_seq_item w_q[$];      // data phase pending (same order as aw_q)
  protected axi4_seq_item ar_q[$];
  protected axi4_seq_item wr_pend[$];  // writes waiting for B
  protected axi4_seq_item rd_pend[$];  // reads waiting for RLAST
  protected bit           in_reset = 1;

  function new(string n, uvm_component p);
    super.new(n, p);
  endfunction

  function void build_phase(uvm_phase phase);
    if (cfg == null && !uvm_config_db#(axi4_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CFG", "Missing axi4_agent_cfg")
    vif = cfg.vif;
    if (vif == null) `uvm_fatal("CFG", {cfg.name, ": virtual interface not set"})
  endfunction

  protected function void idle_signals();
    vif.AWVALID <= 1'b0; vif.WVALID <= 1'b0; vif.ARVALID <= 1'b0;
    vif.BREADY  <= 1'b0; vif.RREADY <= 1'b0;
    vif.AWID <= '0; vif.AWADDR <= '0; vif.AWLEN <= '0; vif.AWSIZE <= '0; vif.AWBURST <= '0;
    vif.AWLOCK <= '0; vif.AWCACHE <= '0; vif.AWPROT <= '0; vif.AWQOS <= '0; vif.AWREGION <= '0; vif.AWUSER <= '0;
    vif.WDATA <= '0; vif.WSTRB <= '0; vif.WLAST <= '0; vif.WUSER <= '0;
    vif.ARID <= '0; vif.ARADDR <= '0; vif.ARLEN <= '0; vif.ARSIZE <= '0; vif.ARBURST <= '0;
    vif.ARLOCK <= '0; vif.ARCACHE <= '0; vif.ARPROT <= '0; vif.ARQOS <= '0; vif.ARREGION <= '0; vif.ARUSER <= '0;
  endfunction

  // Random payload for an idle channel (no effect unless cfg.randomize_idle).
  protected function void idle_aw();
    if (!cfg.randomize_idle) return;
    vif.AWID <= $urandom(); vif.AWADDR <= {$urandom(), $urandom()}; vif.AWLEN <= $urandom(); vif.AWSIZE <= $urandom();
    vif.AWBURST <= $urandom(); vif.AWLOCK <= $urandom(); vif.AWCACHE <= $urandom(); vif.AWPROT <= $urandom();
    vif.AWQOS <= $urandom(); vif.AWREGION <= $urandom(); vif.AWUSER <= $urandom();
  endfunction
  protected function void idle_w();
    if (!cfg.randomize_idle) return;
    for (int i = 0; i < AXI4_DATA_WIDTH; i += 32) vif.WDATA[i +: 32] <= $urandom();
    vif.WSTRB <= $urandom(); vif.WLAST <= $urandom(); vif.WUSER <= $urandom();
  endfunction
  protected function void idle_ar();
    if (!cfg.randomize_idle) return;
    vif.ARID <= $urandom(); vif.ARADDR <= {$urandom(), $urandom()}; vif.ARLEN <= $urandom(); vif.ARSIZE <= $urandom();
    vif.ARBURST <= $urandom(); vif.ARLOCK <= $urandom(); vif.ARCACHE <= $urandom(); vif.ARPROT <= $urandom();
    vif.ARQOS <= $urandom(); vif.ARREGION <= $urandom(); vif.ARUSER <= $urandom();
  endfunction

  protected function int unsigned rand_delay(int unsigned max);
    if (max == 0) return 0;
    if ($urandom_range(99, 0) < cfg.zero_delay_pct) return 0;
    return $urandom_range(max, 1);
  endfunction

  protected function void finish(axi4_seq_item t, bit aborted);
    t.aborted = aborted;
    t.done    = 1;
  endfunction

  protected function void abort_all();
    foreach (wr_pend[i]) finish(wr_pend[i], 1);
    foreach (rd_pend[i]) finish(rd_pend[i], 1);
    aw_q.delete(); w_q.delete(); ar_q.delete(); wr_pend.delete(); rd_pend.delete();
  endfunction

  task run_phase(uvm_phase phase);
    idle_signals();
    fork
      dispatch();
    join_none
    forever begin
      in_reset = 1;
      idle_signals();
      do @(vif.cb); while (vif.cb.ARESETn !== 1'b1);
      in_reset = 0;
      fork begin : channels
        fork
          aw_thread();
          w_thread();
          b_thread();
          ar_thread();
          r_thread();
        join_none
        do @(vif.cb); while (vif.cb.ARESETn === 1'b1);
        disable fork;
      end join
      abort_all();
    end
  endtask

  // Takes items from the sequencer whenever the outstanding limit has room.
  protected task dispatch();
    axi4_seq_item t;
    forever begin
      seq_item_port.get_next_item(t);
      t.done = 0; t.aborted = 0; t.drv_aw_done = 0;
      repeat (t.delay) @(vif.cb);
      forever begin
        if (!in_reset) begin
          if (t.cmd == AXI4_WRITE && wr_pend.size() < cfg.max_wr_outstanding) break;
          if (t.cmd == AXI4_READ  && rd_pend.size() < cfg.max_rd_outstanding) break;
        end
        @(vif.cb);
      end
      if (t.cmd == AXI4_WRITE) begin
        wr_pend.push_back(t); aw_q.push_back(t); w_q.push_back(t);
      end else begin
        t.rdata.delete(); t.rresp.delete(); t.ruser.delete();
        rd_pend.push_back(t); ar_q.push_back(t);
      end
      seq_item_port.item_done();
    end
  endtask

  protected task aw_thread();
    axi4_seq_item t;
    forever begin
      while (aw_q.size() == 0) @(vif.cb);
      t = aw_q[0];
      repeat (rand_delay(cfg.aw_delay_max)) @(vif.cb);
      vif.AWID <= t.id; vif.AWADDR <= t.addr; vif.AWLEN <= t.len; vif.AWSIZE <= t.size;
      vif.AWBURST <= t.burst; vif.AWLOCK <= t.lock; vif.AWCACHE <= t.cache; vif.AWPROT <= t.prot;
      vif.AWQOS <= t.qos; vif.AWREGION <= t.region; vif.AWUSER <= t.auser;
      vif.AWVALID <= 1'b1;
      do @(vif.cb); while (vif.cb.AWREADY !== 1'b1);
      vif.AWVALID <= 1'b0;
      idle_aw();
      t.drv_aw_done = 1;
      void'(aw_q.pop_front());
    end
  endtask

  protected task w_thread();
    axi4_seq_item t;
    forever begin
      while (w_q.size() == 0) @(vif.cb);
      t = w_q[0];
      if (cfg.w_follows_aw) while (!t.drv_aw_done) @(vif.cb);
      foreach (t.data[i]) begin
        repeat (rand_delay(cfg.w_delay_max)) @(vif.cb);
        vif.WDATA <= t.data[i]; vif.WSTRB <= t.strb[i]; vif.WUSER <= t.wuser[i];
        vif.WLAST <= (i == t.len);
        vif.WVALID <= 1'b1;
        do @(vif.cb); while (vif.cb.WREADY !== 1'b1);
        vif.WVALID <= 1'b0;
        vif.WLAST  <= 1'b0;
        idle_w();
      end
      void'(w_q.pop_front());
    end
  endtask

  protected task b_thread();
    forever begin
      vif.BREADY <= ($urandom_range(99, 0) < cfg.bready_pct);
      @(vif.cb);
      if (vif.cb.BVALID === 1'b1 && vif.cb.BREADY === 1'b1) begin
        int idx[$] = wr_pend.find_first_index(x) with (x.id == vif.cb.BID);
        if (idx.size() == 0) begin
          `uvm_error("AXI_DRV", $sformatf("%s: B response with BID=%0h matches no outstanding write", cfg.name, vif.cb.BID))
        end else begin
          axi4_seq_item t = wr_pend[idx[0]];
          t.bresp = axi4_resp_e'(vif.cb.BRESP);
          t.buser = vif.cb.BUSER;
          wr_pend.delete(idx[0]);
          finish(t, 0);
        end
      end
    end
  endtask

  protected task ar_thread();
    axi4_seq_item t;
    forever begin
      while (ar_q.size() == 0) @(vif.cb);
      t = ar_q[0];
      repeat (rand_delay(cfg.ar_delay_max)) @(vif.cb);
      vif.ARID <= t.id; vif.ARADDR <= t.addr; vif.ARLEN <= t.len; vif.ARSIZE <= t.size;
      vif.ARBURST <= t.burst; vif.ARLOCK <= t.lock; vif.ARCACHE <= t.cache; vif.ARPROT <= t.prot;
      vif.ARQOS <= t.qos; vif.ARREGION <= t.region; vif.ARUSER <= t.auser;
      vif.ARVALID <= 1'b1;
      do @(vif.cb); while (vif.cb.ARREADY !== 1'b1);
      vif.ARVALID <= 1'b0;
      idle_ar();
      void'(ar_q.pop_front());
    end
  endtask

  protected task r_thread();
    forever begin
      vif.RREADY <= ($urandom_range(99, 0) < cfg.rready_pct);
      @(vif.cb);
      if (vif.cb.RVALID === 1'b1 && vif.cb.RREADY === 1'b1) begin
        int idx[$] = rd_pend.find_first_index(x) with (x.id == vif.cb.RID);
        if (idx.size() == 0) begin
          `uvm_error("AXI_DRV", $sformatf("%s: R beat with RID=%0h matches no outstanding read", cfg.name, vif.cb.RID))
        end else begin
          axi4_seq_item t = rd_pend[idx[0]];
          int unsigned  n = t.rdata.size();
          t.rdata = new[n + 1](t.rdata); t.rdata[n] = vif.cb.RDATA;
          t.rresp = new[n + 1](t.rresp); t.rresp[n] = axi4_resp_e'(vif.cb.RRESP);
          t.ruser = new[n + 1](t.ruser); t.ruser[n] = vif.cb.RUSER;
          if (vif.cb.RLAST === 1'b1 || n == t.len) begin
            rd_pend.delete(idx[0]);
            finish(t, 0);
          end
        end
      end
    end
  endtask
endclass
