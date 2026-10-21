// Environment and tests of the VIP self-test bench (master agent <-> slave agent).
package vip_test_pkg;
  timeunit 1ns;
  timeprecision 1ps;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import axi4_pkg::*;
  import dv_common_pkg::*;

  class vip_env extends uvm_env;
    `uvm_component_utils(vip_env)
    axi4_agent_cfg      mst_cfg, slv_cfg;
    axi4_agent          mst, slv;
    axi4_mem_scoreboard sb;

    function new(string n, uvm_component p);
      super.new(n, p);
    endfunction

    function void build_phase(uvm_phase phase);
      mst = axi4_agent::type_id::create("mst", this);
      slv = axi4_agent::type_id::create("slv", this);
      sb  = axi4_mem_scoreboard::type_id::create("sb", this);
      mst.cfg = mst_cfg;
      slv.cfg = slv_cfg;
      sb.vif  = mst_cfg.vif;
    endfunction

    function void connect_phase(uvm_phase phase);
      mst.addr_ap.connect(sb.addr_export);
      mst.ap.connect(sb.done_export);
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Base test: builds the env, exposes the usual knobs as plusargs.
  // ---------------------------------------------------------------------------
  virtual class vip_base_test extends dv_base_test;
    vip_env               env;
    axi4_agent_cfg        mst_cfg, slv_cfg;
    virtual axi4_if       vif;
    virtual dv_clk_rst_if clk_rst;

    function new(string n, uvm_component p);
      super.new(n, p);
      dut_name = "none (AXI4 VIP master agent connected directly to AXI4 VIP slave agent)";
      checking = "axi4_mem_scoreboard with its own reference memory; axi4_monitor protocol checks; axi4_if SVA";
    endfunction

    // Hook: adjust agent configuration before the env is built.
    virtual function void configure();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axi4_if)::get(this, "", "bus_vif", vif)) `uvm_fatal("CFG", "bus_vif missing")
      if (!uvm_config_db#(virtual dv_clk_rst_if)::get(this, "", "clk_rst_vif", clk_rst)) `uvm_fatal("CFG", "clk_rst_vif missing")
      mst_cfg = axi4_agent_cfg::type_id::create("mst_cfg");
      slv_cfg = axi4_agent_cfg::type_id::create("slv_cfg");
      mst_cfg.name = "mst"; mst_cfg.role = AXI4_MASTER_AGENT; mst_cfg.vif = vif;
      slv_cfg.name = "slv"; slv_cfg.role = AXI4_SLAVE_AGENT;  slv_cfg.vif = vif;
      slv_cfg.log_txn = 0;            // same bus as mst: one log line per transaction is enough
      slv_cfg.enable_coverage = 0;
      mst_cfg.cov_sideband = 1; mst_cfg.cov_prot = 1; mst_cfg.cov_qos = 1; mst_cfg.cov_sparse_strb = 1;
      configure();
      cfg_lines.push_back(mst_cfg.convert2string());
      cfg_lines.push_back(slv_cfg.convert2string());
      env = vip_env::type_id::create("env", this);
      env.mst_cfg = mst_cfg;
      env.slv_cfg = slv_cfg;
    endfunction

    virtual function int unsigned num_checks();
      return env.sb.num_checks();
    endfunction

    virtual function void result_lines(ref string q[$]);
      q.push_back({"scoreboard       : ", env.sb.summary()});
      q.push_back($sformatf("bus traffic      : writes=%0d reads=%0d write_beats=%0d read_beats=%0d max_outstanding(wr/rd)=%0d/%0d",
                            env.mst.monitor.n_wr, env.mst.monitor.n_rd, env.mst.monitor.n_wr_beats, env.mst.monitor.n_rd_beats,
                            env.mst.monitor.max_wr_out, env.mst.monitor.max_rd_out));
      q.push_back($sformatf("functional cov   : %0.1f%% of the mst covergroups in this test alone", env.mst.coverage.get_coverage()));
    endfunction

    // Body of the test, run between the objection raise and drop.
    pure virtual task main();

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      clk_rst.wait_reset_done();
      main();
      clk_rst.wait_clocks(20);
      phase.drop_objection(this);
    endtask
  endclass

  // Directed write/read of every sequence in the library.
  class vip_directed_test extends vip_base_test;
    `uvm_component_utils(vip_directed_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "every directed sequence of the VIP library works on an ideal (always ready) bus";
      stimulus = "addr walk, data walk, 4KB-boundary INCR, wrapping WRAP, 256-beat INCR, write-then-read of all burst types";
    endfunction
    task main();
      axi4_addr_walk_seq   s_addr = axi4_addr_walk_seq::type_id::create("s_addr");
      axi4_data_walk_seq   s_data = axi4_data_walk_seq::type_id::create("s_data");
      axi4_4k_boundary_seq s_4k   = axi4_4k_boundary_seq::type_id::create("s_4k");
      axi4_wrap_seq        s_wrap = axi4_wrap_seq::type_id::create("s_wrap");
      axi4_max_burst_seq   s_max  = axi4_max_burst_seq::type_id::create("s_max");
      axi4_write_read_seq  s_wr   = axi4_write_read_seq::type_id::create("s_wr");
      s_addr.start(env.mst.sequencer);
      s_data.start(env.mst.sequencer);
      s_4k.num_txn = 40;   s_4k.start(env.mst.sequencer);
      s_wrap.num_txn = 40; s_wrap.start(env.mst.sequencer);
      s_max.num_txn = 6;   s_max.start(env.mst.sequencer);
      s_wr.num_txn = 60; s_wr.sparse_pct = 30; s_wr.sideband = 1; s_wr.start(env.mst.sequencer);
    endtask
  endclass

  // Fully random, pipelined traffic with random backpressure on every channel.
  class vip_random_test extends vip_base_test;
    `uvm_component_utils(vip_random_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "pipelined random traffic keeps data integrity and protocol under random backpressure, reordering and interleaving";
      stimulus = "axi4_rand_seq: all burst types/sizes/lengths, 8 IDs, sparse strobes, 16 KB window so reads hit written data";
    endfunction
    virtual function void configure();
      int bp = dv_plusarg_int("BP_PCT", $urandom_range(100, 30));
      mst_cfg.set_backpressure(bp, 4);
      slv_cfg.set_backpressure(dv_plusarg_int("SLV_BP_PCT", $urandom_range(100, 30)), 4);
      slv_cfg.b_reorder = 1; slv_cfg.rd_reorder = 1; slv_cfg.rd_interleave = $urandom_range(1, 0);
      mst_cfg.max_wr_outstanding = 8; mst_cfg.max_rd_outstanding = 8;
    endfunction
    task main();
      axi4_rand_seq s = axi4_rand_seq::type_id::create("s");
      s.num_txn = dv_plusarg_int("NUM_TXN", 400);
      s.sparse_pct = 30; s.sideband = 1; s.idle_max = 3;
      s.add_window(32'h0001_0000, 32'h0001_3FFF);
      s.start(env.mst.sequencer);
    endtask
  endclass

  // The slave answers part of the address space with SLVERR and DECERR.
  class vip_error_resp_test extends vip_base_test;
    `uvm_component_utils(vip_error_resp_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "error responses are returned, carried through driver and monitor, and do not corrupt memory";
      stimulus = "random traffic over three 4 KB pages: page 0 OKAY, page 1 SLVERR, page 2 DECERR";
      checking = {checking, "; every item's response is compared with the page it addressed"};
    endfunction
    virtual function void configure();
      slv_cfg.add_error_range(32'h0000_1000, 32'h0000_1FFF, AXI4_RESP_SLVERR);
      slv_cfg.add_error_range(32'h0000_2000, 32'h0000_2FFF, AXI4_RESP_DECERR);
      mst_cfg.cov_err_resp = 1;
    endfunction
    function void end_of_elaboration_phase(uvm_phase phase);
      env.sb.expect_okay = 0;   // error responses are intended here
    endfunction
    int unsigned n_resp_checked;
    virtual function int unsigned num_checks();
      return n_resp_checked;
    endfunction
    task main();
      axi4_rand_seq s = axi4_rand_seq::type_id::create("s");
      axi4_resp_e   exp;
      s.num_txn = 300; s.pipelined = 1;
      s.add_window(32'h0000_0000, 32'h0000_0FFF);
      s.add_window(32'h0000_1000, 32'h0000_1FFF);
      s.add_window(32'h0000_2000, 32'h0000_2FFF);
      fork
        s.start(env.mst.sequencer);
      join_none
      // Check each completed transaction against the page it addressed.
      forever begin
        axi4_seq_item t;
        mon_fifo.get(t);
        exp = (t.addr[15:12] == 1) ? AXI4_RESP_SLVERR : (t.addr[15:12] == 2) ? AXI4_RESP_DECERR : AXI4_RESP_OKAY;
        if (t.cmd == AXI4_WRITE) begin
          if (t.bresp != exp) `uvm_error("VIP_RESP", $sformatf("expected %s: %s", exp.name(), t.convert2string()))
        end else begin
          foreach (t.rresp[i]) if (t.rresp[i] != exp) `uvm_error("VIP_RESP", $sformatf("beat %0d expected %s: %s", i, exp.name(), t.convert2string()))
        end
        n_resp_checked++;
        if (n_resp_checked == s.num_txn) break;
      end
    endtask
    uvm_tlm_analysis_fifo #(axi4_seq_item) mon_fifo;
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      mon_fifo = new("mon_fifo", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      env.mst.ap.connect(mon_fifo.analysis_export);
    endfunction
  endclass

  // Reset in the middle of pipelined traffic, then traffic again.
  class vip_reset_test extends vip_base_test;
    `uvm_component_utils(vip_reset_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "a reset during traffic aborts everything in flight and both agents recover";
      stimulus = "random pipelined traffic, reset asserted three times at random points, then write-then-read traffic";
    endfunction
    virtual function void configure();
      mst_cfg.set_backpressure(70, 3);
      slv_cfg.set_backpressure(70, 3);
    endfunction
    task main();
      axi4_rand_seq       s;
      axi4_write_read_seq r = axi4_write_read_seq::type_id::create("r");
      repeat (3) begin
        s = axi4_rand_seq::type_id::create("s");
        s.num_txn = 200; s.add_window(32'h0, 32'h3FFF);
        fork
          s.start(env.mst.sequencer);
        join_none
        clk_rst.wait_clocks($urandom_range(400, 60));
        clk_rst.apply_reset($urandom_range(8, 2));
        s.wait_for_sequence_state(UVM_FINISHED);
      end
      r.num_txn = 60; r.add_window(32'h0, 32'h3FFF);
      r.start(env.mst.sequencer);
    endtask
  endclass

  // ---------------------------------------------------------------------------
  // Negative tests: the slave violates the protocol, the checker must object.
  // ---------------------------------------------------------------------------
  virtual class vip_neg_base_test extends vip_base_test;
    function new(string n, uvm_component p);
      super.new(n, p);
      stimulus = "a few single transactions against a slave with one protocol fault injected";
      checking = "negative test: passes only if axi4_monitor reports AXI_PROTOCOL";
      min_checks = 0;
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      expect_error("AXI_PROTOCOL");          // must be reported
      expect_error("AXI_DRV", 0);            // side effects of the fault, tolerated
      expect_error("AXI_SB", 0);
      mst_cfg.timeout_cycles = 300;
      slv_cfg.timeout_cycles = 300;
    endfunction
    task main();
      axi4_rand_seq s = axi4_rand_seq::type_id::create("s");
      s.num_txn = 6; s.max_len = 7; s.use_wrap = 0; s.use_fixed = 0; s.id_hi = 3;
      s.add_window(32'h0, 32'hFFF);
      fork
        s.start(env.mst.sequencer);
      join_none
      clk_rst.wait_clocks(600);
    endtask
  endclass

  class vip_neg_early_rlast_test extends vip_neg_base_test;
    `uvm_component_utils(vip_neg_early_rlast_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent = "checker detects RLAST asserted one beat early";
    endfunction
    virtual function void configure();
      slv_cfg.inj_early_rlast = 1;
    endfunction
  endclass

  class vip_neg_wrong_bid_test extends vip_neg_base_test;
    `uvm_component_utils(vip_neg_wrong_bid_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent = "checker detects a B response whose ID matches no outstanding write";
    endfunction
    virtual function void configure();
      slv_cfg.inj_wrong_bid = 1;
      mst_cfg.allow_pending_at_end = 1; slv_cfg.allow_pending_at_end = 1;
    endfunction
  endclass

  class vip_neg_no_response_test extends vip_neg_base_test;
    `uvm_component_utils(vip_neg_no_response_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent = "checker detects transactions that never get a response (watchdog)";
    endfunction
    virtual function void configure();
      slv_cfg.inj_no_b = 1; slv_cfg.inj_no_r = 1;
      mst_cfg.allow_pending_at_end = 1; slv_cfg.allow_pending_at_end = 1;
    endfunction
  endclass
endpackage
