// Environment, routing scoreboard, coverage and tests for axi_crossbar.
package xbar_test_pkg;
  timeunit 1ns;
  timeprecision 1ps;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import axi4_pkg::*;
  import dv_common_pkg::*;
  import xbar_cfg_pkg::*;

  typedef enum int { XBAR_ROUTED, XBAR_UNMAPPED, XBAR_SECURE, XBAR_NOT_CONNECTED } xbar_route_e;

  // Set by the base test from the build configuration (see tb_xbar_top.OPEN).
  bit xbar_open = 0;

  // ---------------------------------------------------------------------------
  // Reference model of the address decoder (written from the crossbar
  // documentation, independent of the RTL).  Returns the destination slave and
  // region, or the reason why the access must be answered with DECERR.
  // ---------------------------------------------------------------------------
  function automatic xbar_route_e xbar_decode(int master, bit is_write, bit [31:0] addr, bit [2:0] prot,
                                              output int slave, output int region);
    bit in_range = 0, secure_block = 0, connect_block = 0;
    bit connected;
    slave = -1; region = -1;
    for (int m = 0; m < M_COUNT; m++) for (int r = 0; r < M_REGIONS; r++) begin
      if (region_width(m, r) == 0) continue;
      if (addr < region_base(m, r) || addr > region_last(m, r)) continue;
      in_range  = 1;
      connected = xbar_open || (is_write ? M_CONNECT_WRITE[m*S_COUNT + master] : M_CONNECT_READ[m*S_COUNT + master]);
      if (!connected)                             begin connect_block = 1; continue; end
      if (!xbar_open && M_SECURE[m] && prot[1])   begin secure_block  = 1; continue; end
      slave = m; region = r;
    end
    if (slave >= 0)    return XBAR_ROUTED;
    if (!in_range)     return XBAR_UNMAPPED;
    if (connect_block) return XBAR_NOT_CONNECTED;
    return XBAR_SECURE;
  endfunction

  // ---------------------------------------------------------------------------
  // Functional coverage specific to the crossbar.
  // ---------------------------------------------------------------------------
  class xbar_coverage extends uvm_component;
    `uvm_component_utils(xbar_coverage)

    covergroup cg_route with function sample(int master, bit is_write, int slave, int region);
      option.per_instance = 1;
      cp_master: coverpoint master   { bins m[] = {[0:S_COUNT-1]}; }
      cp_cmd:    coverpoint is_write { bins read = {0}; bins write = {1}; }
      cp_slave:  coverpoint slave    { bins s[] = {[0:M_COUNT-1]}; }
      cp_region: coverpoint region   { bins r[] = {[0:M_REGIONS-1]}; }
      // Every master reaches every slave it is connected to, in both directions.
      route: cross cp_master, cp_cmd, cp_slave {
        ignore_bins m1_cannot_write_s1 = binsof(cp_master) intersect {1} && binsof(cp_cmd) intersect {1} && binsof(cp_slave) intersect {1};
        ignore_bins m0_cannot_read_s2  = binsof(cp_master) intersect {0} && binsof(cp_cmd) intersect {0} && binsof(cp_slave) intersect {2};
      }
      // Every configured region of every slave is addressed.
      region_of_slave: cross cp_slave, cp_region {
        ignore_bins s1_r2_unused = binsof(cp_slave) intersect {1} && binsof(cp_region) intersect {2};
      }
    endgroup

    covergroup cg_decerr with function sample(int master, bit is_write, xbar_route_e why);
      option.per_instance = 1;
      cp_master: coverpoint master   { bins m[] = {[0:S_COUNT-1]}; }
      cp_cmd:    coverpoint is_write { bins read = {0}; bins write = {1}; }
      cp_why:    coverpoint why      { bins unmapped = {XBAR_UNMAPPED}; bins secure = {XBAR_SECURE}; bins not_connected = {XBAR_NOT_CONNECTED}; }
      why_x_cmd: cross cp_why, cp_cmd;
      unmapped_per_master: cross cp_master, cp_cmd iff (why == XBAR_UNMAPPED);
    endgroup

    // Was the other master busy with the same slave when this access was accepted?
    covergroup cg_contention with function sample(int slave, bit is_write, bit contended);
      option.per_instance = 1;
      cp_slave:     coverpoint slave    { bins s[] = {[0:M_COUNT-1]}; }
      cp_cmd:       coverpoint is_write { bins read = {0}; bins write = {1}; }
      cp_contended: coverpoint contended { bins alone = {0}; bins both_masters = {1}; }
      // Slave 1 is written by master 0 only and slave 2 is read by master 1 only.
      x: cross cp_slave, cp_cmd, cp_contended {
        ignore_bins s1_wr = binsof(cp_slave) intersect {1} && binsof(cp_cmd) intersect {1} && binsof(cp_contended) intersect {1};
        ignore_bins s2_rd = binsof(cp_slave) intersect {2} && binsof(cp_cmd) intersect {0} && binsof(cp_contended) intersect {1};
      }
    endgroup

    function new(string n, uvm_component p);
      super.new(n, p);
      cg_route = new(); cg_decerr = new(); cg_contention = new();
    endfunction

    function real get_coverage();
      return (cg_route.get_inst_coverage() + cg_decerr.get_inst_coverage() + cg_contention.get_inst_coverage()) / 3.0;
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Routing scoreboard.
  //
  // For every transaction completed on a master port the reference decoder
  // gives the expected destination.
  //   - DECERR expected: the response must be DECERR on every beat and no slave
  //     may ever see the transaction.
  //   - routed: the same transaction must appear on exactly that slave port
  //     with ID = {master index, original ID}, AxREGION = region index and an
  //     unchanged payload; the response the slave gave must be the response
  //     the master received (data included for reads).
  // Master-side and slave-side transactions are paired per (slave, master, ID,
  // direction) in order.  Anything left unpaired at the end is an error.
  // ---------------------------------------------------------------------------
  class xbar_scoreboard extends uvm_component;
    `uvm_component_utils(xbar_scoreboard)

    xbar_coverage   cov;
    virtual axi4_if vif;   // any port; used to see resets

    protected axi4_seq_item mst_q[string][$];
    protected axi4_seq_item slv_q[string][$];
    protected int           exp_region[axi4_seq_item];
    protected int           inflight[2][S_COUNT][M_COUNT];   // [is_write][master][slave]
    protected int           route_of[axi4_seq_item];          // slave index decided at the address phase

    int unsigned n_routed, n_decerr, n_mismatch;
    int unsigned n_route_cnt[S_COUNT][M_COUNT];

    function new(string n, uvm_component p);
      super.new(n, p);
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(vif.cb);
        if (vif.cb.ARESETn !== 1'b1) flush();
      end
    endtask

    function void flush();
      mst_q.delete(); slv_q.delete(); exp_region.delete(); route_of.delete();
      foreach (inflight[w, s, m]) inflight[w][s][m] = 0;
    endfunction

    protected function string key(int slave, int master, int id, axi4_cmd_e cmd);
      return $sformatf("s%0d.m%0d.id%0d.%s", slave, master, id, cmd.name());
    endfunction

    protected function void err(string msg);
      n_mismatch++;
      `uvm_error("XBAR_SB", msg)
    endfunction

    // Address phase accepted on master port `master`.
    function void mst_addr(int master, axi4_seq_item t);
      int          slave, region;
      bit          w = (t.cmd == AXI4_WRITE);
      xbar_route_e r = xbar_decode(master, w, t.addr, t.prot, slave, region);
      route_of[t] = (r == XBAR_ROUTED) ? slave : -1;
      if (r != XBAR_ROUTED) return;
      begin
        bit contended = 0;
        for (int o = 0; o < S_COUNT; o++) if (o != master && inflight[w][o][slave] > 0) contended = 1;
        cov.cg_contention.sample(slave, w, contended);
        inflight[w][master][slave]++;
      end
    endfunction

    // Transaction completed on master port `master`.
    function void mst_done(int master, axi4_seq_item t);
      int          slave, region;
      bit          w = (t.cmd == AXI4_WRITE);
      xbar_route_e r = xbar_decode(master, w, t.addr, t.prot, slave, region);
      string       k;
      if (route_of.exists(t)) begin
        if (route_of[t] >= 0) inflight[w][master][route_of[t]]--;
        route_of.delete(t);
      end
      if (r != XBAR_ROUTED) begin
        cov.cg_decerr.sample(master, w, r);
        n_decerr++;
        if (w) begin
          if (t.bresp != AXI4_RESP_DECERR)
            err($sformatf("master %0d: expected DECERR (%s) but got %s: %s", master, r.name(), t.bresp.name(), t.convert2string()));
        end else begin
          if (t.rdata.size() != t.len + 1)
            err($sformatf("master %0d: DECERR read returned %0d beats, expected %0d: %s", master, t.rdata.size(), t.len + 1, t.convert2string()));
          foreach (t.rresp[i]) if (t.rresp[i] != AXI4_RESP_DECERR) begin
            err($sformatf("master %0d: expected DECERR (%s) on beat %0d but got %s: %s", master, r.name(), i, t.rresp[i].name(), t.convert2string()));
            break;
          end
        end
        `uvm_info("XBAR_SB", $sformatf("master %0d %s addr=%h prot=%0h -> DECERR as expected (%s)", master, w ? "WR" : "RD", t.addr, t.prot, r.name()), UVM_HIGH)
        return;
      end
      cov.cg_route.sample(master, w, slave, region);
      exp_region[t] = region;
      k = key(slave, master, t.id, t.cmd);
      mst_q[k].push_back(t);
      try_match(k, slave, master);
    endfunction

    // Transaction completed on slave port `slave`.
    function void slv_done(int slave, axi4_seq_item t);
      int    master = t.id >> S_ID_WIDTH;
      int    id     = t.id & ((1 << S_ID_WIDTH) - 1);
      string k      = key(slave, master, id, t.cmd);
      if (master >= S_COUNT) begin
        err($sformatf("slave %0d: ID %0h carries master index %0d, which does not exist", slave, t.id, master));
        return;
      end
      slv_q[k].push_back(t);
      try_match(k, slave, master);
    endfunction

    protected function void try_match(string k, int slave, int master);
      while (mst_q.exists(k) && slv_q.exists(k) && mst_q[k].size() > 0 && slv_q[k].size() > 0) begin
        axi4_seq_item m = mst_q[k].pop_front();
        axi4_seq_item s = slv_q[k].pop_front();
        compare(slave, master, m, s);
        exp_region.delete(m);
      end
    endfunction

    protected function void compare(int slave, int master, axi4_seq_item m, axi4_seq_item s);
      string where = $sformatf("master %0d -> slave %0d", master, slave);
      string diff  = "";
      if (m.addr != s.addr || m.len != s.len || m.size != s.size || m.burst != s.burst) diff = {diff, " addr/len/size/burst"};
      if (m.lock != s.lock || m.cache != s.cache || m.prot != s.prot || m.qos != s.qos) diff = {diff, " lock/cache/prot/qos"};
      if (m.auser != s.auser) diff = {diff, " AxUSER"};
      if (s.region != exp_region[m]) diff = {diff, $sformatf(" AxREGION(got %0d, expected %0d)", s.region, exp_region[m])};
      if (m.cmd == AXI4_WRITE) begin
        if (m.data.size() != s.data.size()) diff = {diff, " W beat count"};
        else foreach (m.data[i]) if (m.data[i] != s.data[i] || m.strb[i] != s.strb[i] || m.wuser[i] != s.wuser[i]) begin
          diff = {diff, $sformatf(" WDATA/WSTRB/WUSER(beat %0d)", i)}; break;
        end
        if (m.bresp != s.bresp) diff = {diff, $sformatf(" BRESP(master %s, slave %s)", m.bresp.name(), s.bresp.name())};
        if (m.buser != s.buser) diff = {diff, " BUSER"};
      end else begin
        if (m.rdata.size() != s.rdata.size()) diff = {diff, " R beat count"};
        else foreach (m.rdata[i]) if (m.rdata[i] != s.rdata[i] || m.rresp[i] != s.rresp[i] || m.ruser[i] != s.ruser[i]) begin
          diff = {diff, $sformatf(" RDATA/RRESP/RUSER(beat %0d)", i)}; break;
        end
      end
      n_routed++;
      n_route_cnt[master][slave]++;
      if (diff != "")
        err($sformatf("%s: mismatch in%s\n   master side: %s\n   slave side : %s", where, diff, m.convert2string(), s.convert2string()));
      else
        `uvm_info("XBAR_SB", $sformatf("%s region %0d OK: %s", where, s.region, m.convert2string()), UVM_HIGH)
    endfunction

    function int unsigned num_checks();
      return n_routed + n_decerr;
    endfunction

    function string summary();
      string s = $sformatf("routed_and_compared=%0d decerr_checked=%0d mismatches=%0d  per route (master->slave):", n_routed, n_decerr, n_mismatch);
      foreach (n_route_cnt[m, sl]) s = {s, $sformatf(" %0d->%0d:%0d", m, sl, n_route_cnt[m][sl])};
      return s;
    endfunction

    function void check_phase(uvm_phase phase);
      foreach (mst_q[k]) if (mst_q[k].size() > 0)
        err($sformatf("%0d transaction(s) completed on the master side never appeared on the expected slave (%s), first: %s", mst_q[k].size(), k, mst_q[k][0].convert2string()));
      foreach (slv_q[k]) if (slv_q[k].size() > 0)
        err($sformatf("%0d transaction(s) reached a slave that no master-side transaction accounts for (%s), first: %s", slv_q[k].size(), k, slv_q[k][0].convert2string()));
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("XBAR_SB", {"routing scoreboard: ", summary()}, UVM_LOW)
    endfunction
  endclass

  // Forwards a monitor's analysis ports to the scoreboard together with the port index.
  class xbar_tap extends uvm_subscriber #(axi4_seq_item);
    `uvm_component_utils(xbar_tap)
    xbar_scoreboard sb;
    int             idx;
    bit             is_master;
    bit             is_addr;
    function new(string n, uvm_component p);
      super.new(n, p);
    endfunction
    function void write(axi4_seq_item t);
      if (is_master && is_addr) sb.mst_addr(idx, t);
      else if (is_master)       sb.mst_done(idx, t);
      else if (!is_addr)        sb.slv_done(idx, t);
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Environment.
  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // Concurrency limits, checked cycle by cycle at the ports of the crossbar.
  //
  // M_ISSUE: a slave port never has more than M_ISSUE transactions of one
  // direction in flight (address accepted, response not complete).  Seen from
  // outside this bound is exact: the crossbar counts a transaction no later
  // than its address reaches the port and releases it no earlier than its
  // response has left the port.
  //
  // S_ACCEPT: a master port never has more than S_ACCEPT routed transactions of
  // one direction in flight.  At the port a transaction is seen earlier and its
  // response later than by the crossbar's counter when there are register
  // slices on the address and response channels, so the bound checked is
  // S_ACCEPT plus the depths of those two slices (0, 1 or 2 entries for type
  // 0, 1, 2).  Rejected (DECERR) accesses are not counted by the crossbar and
  // not by this checker.
  // ---------------------------------------------------------------------------
  class xbar_limit_checker extends uvm_component;
    `uvm_component_utils(xbar_limit_checker)
    virtual axi4_if s_vif[S_COUNT];
    virtual axi4_if m_vif[M_COUNT];
    int unsigned    issue[M_COUNT];                            // M_ISSUE of this build
    int unsigned    accept_wr[S_COUNT], accept_rd[S_COUNT];    // S_ACCEPT plus slice depths
    int             m_wr[M_COUNT], m_rd[M_COUNT], s_wr[S_COUNT], s_rd[S_COUNT];
    int unsigned    m_wr_max[M_COUNT], m_rd_max[M_COUNT], s_wr_max[S_COUNT], s_rd_max[S_COUNT];
    int unsigned    n_viol, n_checks;
    protected bit   wr_routed[S_COUNT][int][$];   // per master and ID: was the access routed?
    protected bit   rd_routed[S_COUNT][int][$];
    protected bit   flagged[string];

    function new(string n, uvm_component p);
      super.new(n, p);
    endfunction

    function void build_phase(uvm_phase phase);
      foreach (accept_wr[m]) begin
        accept_wr[m] = S_ACCEPT[m*32 +: 32] + S_AW_REG_TYPE[m*2 +: 2] + S_B_REG_TYPE[m*2 +: 2];
        accept_rd[m] = S_ACCEPT[m*32 +: 32] + S_AR_REG_TYPE[m*2 +: 2] + S_R_REG_TYPE[m*2 +: 2];
      end
    endfunction

    protected function void bound(string key, int value, int unsigned limit, string what);
      n_checks++;
      if (value <= int'(limit)) return;
      n_viol++;
      if (flagged.exists(key)) return;
      flagged[key] = 1;
      `uvm_error("XBAR_LIMIT", $sformatf("%s: %0d in flight, limit is %0d (further violations of this limit are counted, not printed)", what, value, limit))
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        // Read just after the clock edge, before any update of this time step:
        // these are the values the crossbar has just sampled.
        @(posedge m_vif[0].ACLK);
        if (m_vif[0].ARESETn !== 1'b1) begin
          foreach (m_wr[n]) begin m_wr[n] = 0; m_rd[n] = 0; end
          foreach (s_wr[m]) begin s_wr[m] = 0; s_rd[m] = 0; wr_routed[m].delete(); rd_routed[m].delete(); end
          continue;
        end
        foreach (m_vif[n]) begin
          if (m_vif[n].AWVALID === 1'b1 && m_vif[n].AWREADY === 1'b1) m_wr[n]++;
          if (m_vif[n].BVALID  === 1'b1 && m_vif[n].BREADY  === 1'b1) m_wr[n]--;
          if (m_vif[n].ARVALID === 1'b1 && m_vif[n].ARREADY === 1'b1) m_rd[n]++;
          if (m_vif[n].RVALID  === 1'b1 && m_vif[n].RREADY  === 1'b1 && m_vif[n].RLAST === 1'b1) m_rd[n]--;
          if (m_wr[n] > int'(m_wr_max[n])) m_wr_max[n] = m_wr[n];
          if (m_rd[n] > int'(m_rd_max[n])) m_rd_max[n] = m_rd[n];
          bound($sformatf("mw%0d", n), m_wr[n], issue[n], $sformatf("slave port %0d, writes (M_ISSUE)", n));
          bound($sformatf("mr%0d", n), m_rd[n], issue[n], $sformatf("slave port %0d, reads (M_ISSUE)", n));
        end
        foreach (s_vif[m]) begin
          int slave, region, id;
          if (s_vif[m].AWVALID === 1'b1 && s_vif[m].AWREADY === 1'b1) begin
            bit r = (xbar_decode(m, 1, s_vif[m].AWADDR, s_vif[m].AWPROT, slave, region) == XBAR_ROUTED);
            id = s_vif[m].AWID[S_ID_WIDTH-1:0];
            wr_routed[m][id].push_back(r);
            if (r) s_wr[m]++;
          end
          if (s_vif[m].BVALID === 1'b1 && s_vif[m].BREADY === 1'b1) begin
            id = s_vif[m].BID[S_ID_WIDTH-1:0];
            if (wr_routed[m].exists(id) && wr_routed[m][id].size() > 0 && wr_routed[m][id].pop_front()) s_wr[m]--;
          end
          if (s_vif[m].ARVALID === 1'b1 && s_vif[m].ARREADY === 1'b1) begin
            bit r = (xbar_decode(m, 0, s_vif[m].ARADDR, s_vif[m].ARPROT, slave, region) == XBAR_ROUTED);
            id = s_vif[m].ARID[S_ID_WIDTH-1:0];
            rd_routed[m][id].push_back(r);
            if (r) s_rd[m]++;
          end
          if (s_vif[m].RVALID === 1'b1 && s_vif[m].RREADY === 1'b1 && s_vif[m].RLAST === 1'b1) begin
            id = s_vif[m].RID[S_ID_WIDTH-1:0];
            if (rd_routed[m].exists(id) && rd_routed[m][id].size() > 0 && rd_routed[m][id].pop_front()) s_rd[m]--;
          end
          if (s_wr[m] > int'(s_wr_max[m])) s_wr_max[m] = s_wr[m];
          if (s_rd[m] > int'(s_rd_max[m])) s_rd_max[m] = s_rd[m];
          bound($sformatf("sw%0d", m), s_wr[m], accept_wr[m], $sformatf("master port %0d, routed writes (S_ACCEPT + register slices)", m));
          bound($sformatf("sr%0d", m), s_rd[m], accept_rd[m], $sformatf("master port %0d, routed reads (S_ACCEPT + register slices)", m));
        end
      end
    endtask

    function string summary();
      string s = "in flight, highest seen / limit:";
      foreach (issue[n]) s = {s, $sformatf("  slave%0d wr=%0d/%0d rd=%0d/%0d", n, m_wr_max[n], issue[n], m_rd_max[n], issue[n])};
      foreach (accept_wr[m]) s = {s, $sformatf("  master%0d wr=%0d/%0d rd=%0d/%0d", m, s_wr_max[m], accept_wr[m], s_rd_max[m], accept_rd[m])};
      return {s, $sformatf("  violations=%0d", n_viol)};
    endfunction
  endclass

  class xbar_env extends uvm_env;
    `uvm_component_utils(xbar_env)
    axi4_agent_cfg  mst_cfg[S_COUNT];
    axi4_agent_cfg  slv_cfg[M_COUNT];
    axi4_agent      mst[S_COUNT];
    axi4_agent      slv[M_COUNT];
    xbar_scoreboard sb;
    xbar_coverage   cov;
    xbar_tap        tap_addr[S_COUNT], tap_mst[S_COUNT], tap_slv[M_COUNT];
    xbar_limit_checker limits;
    int unsigned    m_issue[M_COUNT];

    function new(string n, uvm_component p);
      super.new(n, p);
    endfunction

    function void build_phase(uvm_phase phase);
      limits = xbar_limit_checker::type_id::create("limits", this);
      foreach (mst_cfg[i]) limits.s_vif[i] = mst_cfg[i].vif;
      foreach (slv_cfg[i]) begin limits.m_vif[i] = slv_cfg[i].vif; limits.issue[i] = m_issue[i]; end
      sb  = xbar_scoreboard::type_id::create("sb", this);
      cov = xbar_coverage::type_id::create("cov", this);
      sb.cov = cov;
      sb.vif = mst_cfg[0].vif;
      foreach (mst[i]) begin
        mst[i] = axi4_agent::type_id::create($sformatf("mst%0d", i), this);
        mst[i].cfg = mst_cfg[i];
        tap_addr[i] = xbar_tap::type_id::create($sformatf("tap_addr%0d", i), this);
        tap_mst[i]  = xbar_tap::type_id::create($sformatf("tap_mst%0d", i), this);
        tap_addr[i].sb = sb; tap_addr[i].idx = i; tap_addr[i].is_master = 1; tap_addr[i].is_addr = 1;
        tap_mst[i].sb  = sb; tap_mst[i].idx  = i; tap_mst[i].is_master  = 1;
      end
      foreach (slv[i]) begin
        slv[i] = axi4_agent::type_id::create($sformatf("slv%0d", i), this);
        slv[i].cfg = slv_cfg[i];
        tap_slv[i] = xbar_tap::type_id::create($sformatf("tap_slv%0d", i), this);
        tap_slv[i].sb = sb; tap_slv[i].idx = i;
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      foreach (mst[i]) begin
        mst[i].addr_ap.connect(tap_addr[i].analysis_export);
        mst[i].ap.connect(tap_mst[i].analysis_export);
      end
      foreach (slv[i]) slv[i].ap.connect(tap_slv[i].analysis_export);
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Sequences.
  // ---------------------------------------------------------------------------
  // Random traffic of one master over a chosen mix of mapped and unmapped space.
  class xbar_rand_seq extends axi4_rand_seq;
    `uvm_object_utils(xbar_rand_seq)
    bit mapped   = 1;   // include every configured region
    bit unmapped = 0;   // include address space no slave owns
    int master   = 0;   // crossbar slave port this sequence runs on
    // Known issue XBAR-03: a DECERR response is not kept in order with other
    // responses of the same ID.  With this knob set, accesses the crossbar will
    // reject use IDs with the top bit set and all others IDs with it clear, so
    // the two kinds never share an ID while in flight.
    bit split_decerr_ids = 1;
    function new(string n = "xbar_rand_seq");
      super.new(n);
      sideband = 1; sparse_pct = 20;
    endfunction
    virtual function void tweak(axi4_seq_item t);
      int slave, region;
      if (!split_decerr_ids) return;
      if (xbar_decode(master, t.cmd == AXI4_WRITE, t.addr, t.prot, slave, region) == XBAR_ROUTED) t.id[S_ID_WIDTH-1] = 1'b0;
      else                                                                                       t.id[S_ID_WIDTH-1] = 1'b1;
    endfunction
    virtual task pre_start();
      super.pre_start();
      if (mapped) for (int m = 0; m < M_COUNT; m++) for (int r = 0; r < M_REGIONS; r++)
        if (region_width(m, r) != 0) add_window(region_base(m, r), region_last(m, r));
      if (unmapped) begin
        add_window(32'h2000_0000, 32'h2FFF_FFFF);
        add_window(32'h7000_0000, 32'h7FFF_FFFF);
        add_window(32'h1000_1000, 32'h1FFF_FFFF);   // just above slave 0's 4 KB region
        add_window(32'hE000_0000, 32'hEFFF_FFFF);
      end
    endtask
  endclass

  // ---------------------------------------------------------------------------
  // Base test.
  // ---------------------------------------------------------------------------
  virtual class xbar_base_test extends dv_base_test;
    xbar_env              env;
    axi4_agent_cfg        mst_cfg[S_COUNT];
    axi4_agent_cfg        slv_cfg[M_COUNT];
    int unsigned          m_issue[M_COUNT];
    virtual dv_clk_rst_if clk_rst;
    // Known issue XBAR-01: the DECERR response the crossbar generates for an
    // access it rejects is not sequenced after the request (BVALID before the
    // AW handshake or the last W beat, RVALID together with the AR handshake).
    // Waived by default so that tests mixing legal and rejected accesses remain
    // usable; every occurrence is counted in the summary and the violation is
    // demonstrated by xbar_decerr_b_order_test, which runs without the waiver.
    bit waive_xbar01 = 1;

    function new(string n, uvm_component p);
      super.new(n, p);
      dut_name = $sformatf("axi_crossbar (S_COUNT=%0d M_COUNT=%0d M_REGIONS=%0d DATA=%0d ADDR=%0d S_ID=%0d M_ID=%0d USER=%0d, see tb/tb_xbar/xbar_cfg_pkg.sv)",
                           S_COUNT, M_COUNT, M_REGIONS, DATA_WIDTH, ADDR_WIDTH, S_ID_WIDTH, M_ID_WIDTH, USER_WIDTH);
      timeout_us = 8000;
      checking = "xbar_scoreboard: reference address decoder, per-route payload/ID/region/response comparison, DECERR for illegal routes; xbar_limit_checker: M_ISSUE and S_ACCEPT bounds every cycle; axi4_monitor protocol checks on all 5 ports; axi4_if SVA";
    endfunction

    virtual function void configure();
    endfunction

    function void build_phase(uvm_phase phase);
      virtual axi4_if v;
      super.build_phase(phase);
      if (!uvm_config_db#(virtual dv_clk_rst_if)::get(this, "", "clk_rst_vif", clk_rst)) `uvm_fatal("CFG", "clk_rst_vif missing")
      begin
        int open;
        void'(uvm_config_db#(int)::get(this, "", "xbar_open", open));
        xbar_open = open;
        if (xbar_open) cfg_lines.push_back("build 'open': all routes connected, no secure slave (overrides the connectivity in xbar_cfg_pkg)");
      end
      if (waive_xbar01)
        waive_known_issue("XBAR-01", "AXI_PROTOCOL", "(response AXI4_RESP_DECERR issued too early)");
      foreach (mst_cfg[i]) begin
        if (!uvm_config_db#(virtual axi4_if)::get(this, "", $sformatf("s_vif%0d", i), v)) `uvm_fatal("CFG", "s_vif missing")
        mst_cfg[i] = axi4_agent_cfg::type_id::create($sformatf("mst_cfg%0d", i));
        mst_cfg[i].name = $sformatf("mst%0d", i); mst_cfg[i].role = AXI4_MASTER_AGENT; mst_cfg[i].vif = v;
        mst_cfg[i].id_width = S_ID_WIDTH; mst_cfg[i].user_width = USER_WIDTH;
        mst_cfg[i].max_wr_outstanding = 8; mst_cfg[i].max_rd_outstanding = 8;
        mst_cfg[i].cov_err_resp = 1; mst_cfg[i].cov_sideband = 1; mst_cfg[i].cov_prot = 1; mst_cfg[i].cov_qos = 1; mst_cfg[i].cov_sparse_strb = 1;
      end
      // In-flight depth each port can reach follows S_ACCEPT (masters) and M_ISSUE (slaves).
      mst_cfg[0].cov_outstanding = 1;   // S_ACCEPT = 2
      mst_cfg[1].cov_outstanding = 2;   // S_ACCEPT = 4
      // A master port without an address register (type 0, bypass) gets its
      // AxREADY from the decoder, at the earliest two cycles after AxVALID.
      foreach (mst_cfg[i]) begin
        mst_cfg[i].cov_aw_nostall = (S_AW_REG_TYPE[i*2 +: 2] != 0);
        mst_cfg[i].cov_ar_nostall = (S_AR_REG_TYPE[i*2 +: 2] != 0);
      end
      foreach (slv_cfg[i]) begin
        if (!uvm_config_db#(virtual axi4_if)::get(this, "", $sformatf("m_vif%0d", i), v)) `uvm_fatal("CFG", "m_vif missing")
        slv_cfg[i] = axi4_agent_cfg::type_id::create($sformatf("slv_cfg%0d", i));
        slv_cfg[i].name = $sformatf("slv%0d", i); slv_cfg[i].role = AXI4_SLAVE_AGENT; slv_cfg[i].vif = v;
        slv_cfg[i].id_width = M_ID_WIDTH; slv_cfg[i].user_width = USER_WIDTH;
        slv_cfg[i].mem = axi4_mem_model::type_id::create($sformatf("slv%0d_mem", i));
        slv_cfg[i].mem.default_mode = AXI4_MEM_ADDR_HASH;
        slv_cfg[i].log_txn = 0;   // the master-side log line already describes the transaction
        slv_cfg[i].cov_err_resp = 1; slv_cfg[i].cov_sideband = 1; slv_cfg[i].cov_qos = 1; slv_cfg[i].cov_sparse_strb = 1;
      end
      foreach (slv_cfg[i]) begin
        int issue = 1;
        void'(uvm_config_db#(int)::get(this, "", $sformatf("m_issue%0d", i), issue));
        m_issue[i] = issue;
        slv_cfg[i].cov_outstanding = (issue >= 4) ? 2 : (issue >= 2) ? 1 : 0;
        cfg_lines.push_back($sformatf("slave %0d: M_ISSUE=%0d", i, issue));
      end
      // A slave port without a response register (type 0, bypass) gets its
      // BREADY/RREADY from the response arbiter, one cycle after xVALID at the earliest.
      foreach (slv_cfg[i]) begin
        slv_cfg[i].cov_b_nostall = (M_B_REG_TYPE[i*2 +: 2] != 0);
        slv_cfg[i].cov_r_nostall = (M_R_REG_TYPE[i*2 +: 2] != 0);
      end
      // Slave 2 is the secure slave: the crossbar only forwards PROT[1]=0 to it.
      slv_cfg[0].cov_prot = 1; slv_cfg[1].cov_prot = 1; slv_cfg[2].cov_prot = 0;
      configure();
      foreach (mst_cfg[i]) cfg_lines.push_back(mst_cfg[i].convert2string());
      foreach (slv_cfg[i]) cfg_lines.push_back(slv_cfg[i].convert2string());
      env = xbar_env::type_id::create("env", this);
      env.mst_cfg = mst_cfg;
      env.slv_cfg = slv_cfg;
      env.m_issue = m_issue;
    endfunction

    virtual function int unsigned num_checks();
      return env.sb.num_checks();
    endfunction

    virtual function void result_lines(ref string q[$]);
      q.push_back({"scoreboard       : ", env.sb.summary()});
      foreach (env.mst[i])
        q.push_back($sformatf("master %0d traffic : writes=%0d reads=%0d error_responses=%0d max_outstanding(wr/rd)=%0d/%0d",
                              i, env.mst[i].monitor.n_wr, env.mst[i].monitor.n_rd, env.mst[i].monitor.n_err_resp,
                              env.mst[i].monitor.max_wr_out, env.mst[i].monitor.max_rd_out));
      foreach (env.slv[i])
        q.push_back($sformatf("slave %0d traffic  : writes=%0d reads=%0d max_outstanding(wr/rd)=%0d/%0d",
                              i, env.slv[i].monitor.n_wr, env.slv[i].monitor.n_rd, env.slv[i].monitor.max_wr_out, env.slv[i].monitor.max_rd_out));
      q.push_back({"limits           : ", env.limits.summary()});
      q.push_back($sformatf("functional cov   : crossbar route/decerr/contention = %0.1f%% in this test alone", env.cov.get_coverage()));
    endfunction

    // Random backpressure on every port unless +BP_PCT fixes it.
    function void random_backpressure();
      foreach (mst_cfg[i]) mst_cfg[i].set_backpressure(dv_plusarg_int("BP_PCT", $urandom_range(100, 30)), $urandom_range(4, 0));
      foreach (slv_cfg[i]) begin
        slv_cfg[i].set_backpressure(dv_plusarg_int("BP_PCT", $urandom_range(100, 30)), $urandom_range(4, 0));
        // Read data is never interleaved between bursts: known issue XBAR-04
        // (see xbar_read_interleave_test).  Bursts may still complete out of order.
        slv_cfg[i].b_reorder = $urandom_range(1, 0); slv_cfg[i].rd_reorder = $urandom_range(1, 0);
      end
    endfunction

    // Runs one sequence per master in parallel and waits for all of them.
    task run_on_all(axi4_base_seq s[S_COUNT]);
      fork
        s[0].start(env.mst[0].sequencer);
        s[1].start(env.mst[1].sequencer);
      join
    endtask

    pure virtual task main();

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      clk_rst.wait_reset_done();
      main();
      clk_rst.wait_clocks(40);
      phase.drop_objection(this);
    endtask
  endclass

  // Known issue XBAR-06: axi_crossbar does not pass its M_*_REG_TYPE parameters
  // on to axi_crossbar_wr / axi_crossbar_rd.  The testbench top reads the
  // parameters of the two sub-modules back; this test compares them with what
  // was requested (and runs the smoke traffic so that the build is exercised).
  class xbar_param_test extends xbar_base_test;
    `uvm_component_utils(xbar_param_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "the register-slice types requested with M_AW/W/B/AR/R_REG_TYPE are the ones built into the crossbar";
      stimulus = "elaborated parameters of axi_crossbar_wr and axi_crossbar_rd read back by the testbench top; one write-then-read per master and slave";
      checking = {checking, "; test: built M_*_REG_TYPE values equal the requested ones"};
    endfunction
    task main();
      int built, requested;
      string names[5] = '{"M_AW_REG_TYPE", "M_W_REG_TYPE", "M_B_REG_TYPE", "M_AR_REG_TYPE", "M_R_REG_TYPE"};
      if (!uvm_config_db#(int)::get(this, "", "m_reg_types_built", built) ||
          !uvm_config_db#(int)::get(this, "", "m_reg_types_requested", requested))
        `uvm_fatal("XBAR_PARAM", "register types not published by the testbench top")
      foreach (names[k]) begin
        // two bits per slave port, slave 0 in the least significant bits
        bit [M_COUNT*2-1:0] b = built     >> (k * M_COUNT * 2);
        bit [M_COUNT*2-1:0] r = requested >> (k * M_COUNT * 2);
        if (b != r)
          `uvm_error("XBAR_PARAM", $sformatf("%s: requested %0d'b%b at axi_crossbar, built with %0d'b%b (parameter not passed on)", names[k], M_COUNT * 2, r, M_COUNT * 2, b))
        else
          `uvm_info("XBAR_PARAM", $sformatf("%s = %0d'b%b as requested", names[k], M_COUNT * 2, b), UVM_LOW)
      end
      for (int s = 0; s < S_COUNT; s++) for (int m = 0; m < M_COUNT; m++) begin
        axi4_write_read_seq q = axi4_write_read_seq::type_id::create("q");
        int unused_s, unused_r;
        // Skip routes the build does not connect (the scoreboard checks the others).
        if (xbar_decode(s, 1, region_base(m, 0), 3'b000, unused_s, unused_r) != XBAR_ROUTED) continue;
        if (xbar_decode(s, 0, region_base(m, 0), 3'b000, unused_s, unused_r) != XBAR_ROUTED) continue;
        q.num_txn = 2; q.max_len = 7;
        q.add_window(region_base(m, 0), region_last(m, 0));
        q.start(env.mst[s].sequencer);
      end
    endtask
  endclass

  // Each master writes then reads one burst in every region it may use.
  class xbar_smoke_test extends xbar_base_test;
    `uvm_component_utils(xbar_smoke_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "every master reaches every region of every slave it is connected to, one at a time";
      stimulus = "per master: write-then-read of 4 random bursts in each configured region, masters one after the other";
    endfunction
    task main();
      for (int s = 0; s < S_COUNT; s++)
        for (int m = 0; m < M_COUNT; m++) for (int r = 0; r < M_REGIONS; r++) if (region_width(m, r) != 0) begin
          axi4_write_read_seq q = axi4_write_read_seq::type_id::create("q");
          q.num_txn = 4; q.max_len = 15;
          q.add_window(region_base(m, r), region_last(m, r));
          q.start(env.mst[s].sequencer);
        end
    endtask
  endclass

  // Both masters, all regions plus unmapped space, random everything.
  class xbar_random_test extends xbar_base_test;
    `uvm_component_utils(xbar_random_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "concurrent random traffic of both masters is routed, arbitrated and answered correctly under random backpressure";
      stimulus = "xbar_rand_seq on both masters at once: all regions and unmapped space, all burst types/sizes/lengths, random ID/PROT/QOS/USER, pipelined; slaves answer out of order";
    endfunction
    virtual function void configure();
      random_backpressure();
    endfunction
    task main();
      axi4_base_seq s[S_COUNT];
      foreach (s[i]) begin
        xbar_rand_seq q = xbar_rand_seq::type_id::create($sformatf("q%0d", i)); q.master = i;
        q.num_txn = dv_plusarg_int("NUM_TXN", 300);
        q.unmapped = 1; q.max_len = 63; q.idle_max = 2;
        s[i] = q;
      end
      run_on_all(s);
    endtask
  endclass

  // Only illegal destinations, mixed with a little legal traffic.
  class xbar_decerr_test extends xbar_base_test;
    `uvm_component_utils(xbar_decerr_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "unmapped addresses, non-secure access to the secure slave and unconnected routes answer DECERR and never reach a slave";
      stimulus = "both masters: unmapped windows, slave 2 with random PROT, slave 1 writes from master 1, slave 2 reads from master 0; long bursts included";
    endfunction
    virtual function void configure();
      random_backpressure();
    endfunction
    task main();
      axi4_base_seq s[S_COUNT];
      foreach (s[i]) begin
        xbar_rand_seq q = xbar_rand_seq::type_id::create($sformatf("q%0d", i)); q.master = i;
        q.num_txn = 250; q.mapped = 0; q.unmapped = 1;
        // Regions of the secure slave and of the slave with restricted connectivity.
        q.add_window(region_base(2, 0), region_last(2, 0));
        q.add_window(region_base(2, 2), region_last(2, 2));
        q.add_window(region_base(1, 0), region_last(1, 0));
        s[i] = q;
      end
      run_on_all(s);
    endtask
  endclass

  // Few IDs, many outstanding transactions: exercises the ID-thread tracking
  // and the accept/issue limits of the crossbar.
  class xbar_id_thread_test extends xbar_base_test;
    `uvm_component_utils(xbar_id_thread_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "transactions with the same ID to different slaves stay ordered; S_THREADS, S_ACCEPT and M_ISSUE limits throttle without loss";
      stimulus = "pipelined short bursts using only 2 or 3 ID values spread over all slaves; slow slave responses keep many transactions in flight";
    endfunction
    virtual function void configure();
      foreach (mst_cfg[i]) begin mst_cfg[i].max_wr_outstanding = 12; mst_cfg[i].max_rd_outstanding = 12; end
      foreach (slv_cfg[i]) begin
        slv_cfg[i].b_delay_max = 12; slv_cfg[i].r_delay_max = 12;
        slv_cfg[i].b_reorder = 1; slv_cfg[i].rd_reorder = 1;
      end
    endfunction
    task main();
      axi4_base_seq s[S_COUNT];
      foreach (s[i]) begin
        xbar_rand_seq q = xbar_rand_seq::type_id::create($sformatf("q%0d", i)); q.master = i;
        q.num_txn = 400; q.max_len = 3; q.id_hi = (seed % 2) ? 1 : 2;   // rejected accesses use these IDs + 8
        s[i] = q;
      end
      run_on_all(s);
    endtask
  endclass

  class xbar_backpressure_test extends xbar_base_test;
    `uvm_component_utils(xbar_backpressure_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "every register slice and mux holds its data while the downstream side is not ready";
      stimulus = "random traffic with READY high only 20% of the time on all ten channel directions and VALID delayed on all sources";
    endfunction
    virtual function void configure();
      foreach (mst_cfg[i]) mst_cfg[i].set_backpressure(20, 5);
      foreach (slv_cfg[i]) slv_cfg[i].set_backpressure(20, 5);
    endfunction
    task main();
      axi4_base_seq s[S_COUNT];
      foreach (s[i]) begin
        xbar_rand_seq q = xbar_rand_seq::type_id::create($sformatf("q%0d", i)); q.master = i;
        q.num_txn = 150; q.max_len = 15; q.unmapped = 1;
        s[i] = q;
      end
      run_on_all(s);
    endtask
  endclass

  // Slaves answer with SLVERR in part of their space; the crossbar must pass it on.
  class xbar_slave_error_test extends xbar_base_test;
    `uvm_component_utils(xbar_slave_error_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "error responses produced by a slave reach the right master unchanged";
      stimulus = "every slave answers SLVERR in the 3rd quarter and DECERR in the 4th quarter of its r0 region; random traffic of both masters";
    endfunction
    virtual function void configure();
      foreach (slv_cfg[i]) begin
        bit [31:0] b = region_base(i, 0);
        slv_cfg[i].add_error_range(b + 32'h0800_0000, b + 32'h0BFF_FFFF, AXI4_RESP_SLVERR);
        slv_cfg[i].add_error_range(b + 32'h0C00_0000, b + 32'h0FFF_FFFF, AXI4_RESP_DECERR);
      end
      random_backpressure();
    endfunction
    task main();
      axi4_base_seq s[S_COUNT];
      foreach (s[i]) begin
        xbar_rand_seq q = xbar_rand_seq::type_id::create($sformatf("q%0d", i)); q.master = i;
        q.num_txn = 250; q.max_len = 31;
        s[i] = q;
      end
      run_on_all(s);
    endtask
  endclass

  class xbar_reset_test extends xbar_base_test;
    `uvm_component_utils(xbar_reset_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "a reset during traffic returns the crossbar to idle and it routes correctly afterwards";
      stimulus = "random traffic of both masters interrupted by 3 resets, then traffic that must complete";
    endfunction
    virtual function void configure();
      random_backpressure();
    endfunction
    task main();
      axi4_base_seq s[S_COUNT];
      repeat (3) begin
        xbar_rand_seq q[S_COUNT];
        foreach (q[i]) begin
          q[i] = xbar_rand_seq::type_id::create($sformatf("q%0d", i)); q[i].master = i;
          q[i].num_txn = 120; q[i].max_len = 31; q[i].unmapped = 1;
        end
        fork
          q[0].start(env.mst[0].sequencer);
          q[1].start(env.mst[1].sequencer);
        join_none
        clk_rst.wait_clocks($urandom_range(500, 50));
        clk_rst.apply_reset($urandom_range(6, 2));
        q[0].wait_for_sequence_state(UVM_FINISHED); q[1].wait_for_sequence_state(UVM_FINISHED);
      end
      foreach (s[i]) begin
        xbar_rand_seq q = xbar_rand_seq::type_id::create($sformatf("r%0d", i)); q.master = i;
        q.num_txn = 120; q.max_len = 31; q.unmapped = 1;
        s[i] = q;
      end
      run_on_all(s);
    endtask
  endclass

  // A two-beat write and read with ID all-zeros and ID all-ones to every slave.
  class xbar_id_corner_seq extends axi4_base_seq;
    `uvm_object_utils(xbar_id_corner_seq)
    function new(string n = "xbar_id_corner_seq");
      super.new(n);
    endfunction
    virtual task body();
      axi4_data_t d[] = new[2];
      axi4_data_t r[];
      for (int m = 0; m < M_COUNT; m++) for (int k = 0; k < 2; k++) begin
        axi4_id_t id = k ? ((1 << S_ID_WIDTH) - 1) : 0;
        foreach (d[i]) d[i] = $urandom();
        do_write(region_base(m, 0) + 32'h40 + 8 * k, d, id);
        do_read (region_base(m, 0) + 32'h40 + 8 * k, 2, r, id);
      end
    endtask
  endclass

  // One 64-beat write to an address no slave owns.
  class xbar_long_unmapped_write_seq extends axi4_base_seq;
    `uvm_object_utils(xbar_long_unmapped_write_seq)
    function new(string n = "xbar_long_unmapped_write_seq");
      super.new(n);
    endfunction
    virtual task body();
      axi4_data_t d[] = new[64];
      foreach (d[i]) d[i] = $urandom();
      do_write(32'h2000_0000 + ($urandom_range(900, 0) << 2), d, (1 << (S_ID_WIDTH - 1)) | $urandom_range(7, 0));
    endtask
  endclass

  // A reset while the crossbar is discarding the data of a rejected write.
  // The "discard" flag (w_drop_reg) is not cleared by reset, so afterwards the
  // crossbar must not take write data before it has a new write command; this
  // is the reset corner of known issue XBAR-05.
  class xbar_reset_drop_test extends xbar_base_test;
    `uvm_component_utils(xbar_reset_drop_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "after a reset in the middle of a rejected (DECERR) write, the next legal writes of each master arrive complete at the slave";
      stimulus = "6 times, both masters: a 64-beat write to unmapped space with slow data, reset in the middle, then short writes whose data is presented before the address, read back";
    endfunction
    task main();
      repeat (6) begin
        xbar_long_unmapped_write_seq bad[S_COUNT];
        axi4_base_seq                s[S_COUNT];
        foreach (mst_cfg[i]) begin mst_cfg[i].aw_delay_max = 0; mst_cfg[i].w_delay_max = 8; mst_cfg[i].zero_delay_pct = 0; end
        foreach (bad[i]) bad[i] = xbar_long_unmapped_write_seq::type_id::create($sformatf("bad%0d", i));
        fork
          bad[0].start(env.mst[0].sequencer);
          bad[1].start(env.mst[1].sequencer);
        join_none
        clk_rst.wait_clocks($urandom_range(150, 40));
        clk_rst.apply_reset($urandom_range(6, 2));
        bad[0].wait_for_sequence_state(UVM_FINISHED); bad[1].wait_for_sequence_state(UVM_FINISHED);
        // Data first, address up to 10 cycles later.
        foreach (mst_cfg[i]) begin mst_cfg[i].aw_delay_max = 10; mst_cfg[i].w_delay_max = 0; end
        foreach (s[i]) begin
          axi4_write_read_seq q = axi4_write_read_seq::type_id::create($sformatf("good%0d", i));
          q.num_txn = 6; q.max_len = 1;
          q.add_window(region_base(0, 0), region_last(0, 0));
          s[i] = q;
        end
        run_on_all(s);
      end
    endtask
  endclass

  // Demonstrates known issue XBAR-01 (no waiver): expected to fail.
  class xbar_decerr_b_order_test extends xbar_base_test;
    `uvm_component_utils(xbar_decerr_b_order_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      waive_xbar01 = 0;
      intent   = "a write that the crossbar rejects with DECERR is answered only after its write data has been accepted (AXI4 A3.3.1)";
      stimulus = "master 0 writes 8-beat bursts to unmapped addresses with slow write data";
    endfunction
    virtual function void configure();
      mst_cfg[0].w_delay_max = 6; mst_cfg[0].zero_delay_pct = 0;
    endfunction
    task main();
      xbar_rand_seq q = xbar_rand_seq::type_id::create("q");
      q.num_txn = 10; q.wr_pct = 100; q.mapped = 0; q.unmapped = 1; q.pipelined = 0;
      q.use_fixed = 0; q.use_wrap = 0;
      q.start(env.mst[0].sequencer);
    endtask
  endclass

  // A rejected access followed by legal traffic on the same master.  On the
  // original RTL this locks the master out (known issue XBAR-02); it passes
  // with the fix enabled.
  class xbar_decerr_lockup_test extends xbar_base_test;
    `uvm_component_utils(xbar_decerr_lockup_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      timeout_us = 2000;
      intent   = "after DECERR responses a master can still use every slave (transaction counters stay balanced)";
      stimulus = "per master, repeated: one write and one read to unmapped space while idle, then 6 write-then-read bursts to mapped regions";
    endfunction
    task main();
      axi4_base_seq s[S_COUNT];
      repeat (4) begin
        foreach (s[i]) begin
          xbar_rand_seq q = xbar_rand_seq::type_id::create($sformatf("bad%0d", i)); q.master = i;
          q.num_txn = 2; q.mapped = 0; q.unmapped = 1; q.pipelined = 0; q.max_len = 7;
          s[i] = q;
        end
        run_on_all(s);
        foreach (s[i]) begin
          axi4_write_read_seq q = axi4_write_read_seq::type_id::create($sformatf("good%0d", i));
          q.num_txn = 6; q.max_len = 7;
          q.add_window(region_base(0, 0), region_last(0, 0));
          q.add_window(region_base(0, 1), region_last(0, 1));
          s[i] = q;
        end
        run_on_all(s);
      end
    endtask
  endclass

  // Legal writes right after rejected writes, with the write data ready early.
  // Without the fix for known issue XBAR-05 the first data beat of such a
  // write is lost; with the fix every beat arrives.
  class xbar_decerr_wdata_test extends xbar_base_test;
    `uvm_component_utils(xbar_decerr_wdata_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      timeout_us = 3000;
      intent   = "write data of a legal write that follows a rejected (DECERR) write arrives complete at the slave";
      stimulus = "master 1, pipelined: multi-beat writes alternating between slave 0 and unmapped space, AW delayed and W not delayed so data waits at the crossbar";
    endfunction
    virtual function void configure();
      mst_cfg[1].aw_delay_max = 6; mst_cfg[1].w_delay_max = 0;
      foreach (slv_cfg[i]) slv_cfg[i].set_backpressure(60, 2);
    endfunction
    task main();
      xbar_rand_seq q = xbar_rand_seq::type_id::create("q"); q.master = 1;
      q.num_txn = 120; q.wr_pct = 100; q.mapped = 0; q.unmapped = 1; q.max_len = 31; q.use_fixed = 0; q.use_wrap = 0;
      q.add_window(region_base(0, 0), region_last(0, 0));
      q.add_window(region_base(0, 0), region_last(0, 0));
      q.add_window(region_base(0, 1), region_last(0, 1));
      q.add_window(region_base(0, 1), region_last(0, 1));
      q.start(env.mst[1].sequencer);
    endtask
  endclass

  // All traffic on one slave at a time, answered slowly: the slave's issue
  // limit (M_ISSUE) and the masters' accept limits are reached and released.
  class xbar_issue_limit_test extends xbar_base_test;
    `uvm_component_utils(xbar_issue_limit_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "M_ISSUE and S_ACCEPT throttle new addresses while responses are outstanding and let them through as soon as one completes";
      stimulus = "3 phases, one per slave: both masters send pipelined single-beat and short bursts to that slave only; slave answers after up to 30 cycles";
    endfunction
    virtual function void configure();
      foreach (mst_cfg[i]) begin mst_cfg[i].max_wr_outstanding = 16; mst_cfg[i].max_rd_outstanding = 16; end
      foreach (slv_cfg[i]) begin slv_cfg[i].b_delay_max = 30; slv_cfg[i].r_delay_max = 30; slv_cfg[i].b_reorder = 1; slv_cfg[i].rd_reorder = 1; end
    endfunction
    task main();
      for (int m = 0; m < M_COUNT; m++) begin
        axi4_base_seq s[S_COUNT];
        foreach (s[i]) begin
          xbar_rand_seq q = xbar_rand_seq::type_id::create($sformatf("q%0d", i)); q.master = i;
          q.num_txn = 200; q.max_len = 1; q.mapped = 0; q.sideband = 0;
          q.add_window(region_base(m, 0), region_last(m, 0));
          q.add_window(region_base(m, 1), region_last(m, 1));
          s[i] = q;
        end
        run_on_all(s);
      end
    endtask
  endclass

  // Rejected accesses back to back while the master is slow to take responses:
  // a new DECERR has to wait for the previous one.
  class xbar_decerr_backlog_test extends xbar_base_test;
    `uvm_component_utils(xbar_decerr_backlog_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "DECERR responses queue up correctly when the master accepts them slowly";
      stimulus = "both masters: pipelined accesses to unmapped space only, BREADY/RREADY high 8% of the time";
    endfunction
    virtual function void configure();
      foreach (mst_cfg[i]) begin mst_cfg[i].bready_pct = 8; mst_cfg[i].rready_pct = 8; end
    endfunction
    task main();
      axi4_base_seq s[S_COUNT];
      foreach (s[i]) begin
        xbar_rand_seq q = xbar_rand_seq::type_id::create($sformatf("q%0d", i)); q.master = i;
        q.num_txn = 120; q.max_len = 3; q.mapped = 0; q.unmapped = 1;
        s[i] = q;
      end
      run_on_all(s);
    endtask
  endclass

  // Slaves that are slow on one request channel and fast on the others, so
  // that write data completes before its address is taken and vice versa.
  class xbar_slave_skew_test extends xbar_base_test;
    `uvm_component_utils(xbar_slave_skew_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "address and data of a write may reach the slave in either order and with any gap";
      stimulus = "2 phases of single-beat and short writes/reads: slaves with AWREADY/ARREADY 6% and WREADY 100%, then AWREADY 100% and WREADY 6%";
    endfunction
    task main();
      for (int ph = 0; ph < 2; ph++) begin
        axi4_base_seq s[S_COUNT];
        foreach (slv_cfg[i]) begin
          slv_cfg[i].awready_pct = ph ? 100 : 6; slv_cfg[i].arready_pct = ph ? 100 : 6; slv_cfg[i].wready_pct = ph ? 6 : 100;
        end
        foreach (s[i]) begin
          xbar_rand_seq q = xbar_rand_seq::type_id::create($sformatf("q%0d_%0d", i, ph)); q.master = i;
          q.num_txn = 150; q.max_len = 2;
          s[i] = q;
        end
        run_on_all(s);
      end
    endtask
  endclass

  // Demonstrates known issue XBAR-04: expected to fail.
  class xbar_read_interleave_test extends xbar_base_test;
    `uvm_component_utils(xbar_read_interleave_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      timeout_us = 3000;
      intent   = "read data that a slave interleaves between bursts of different IDs (allowed by AXI4) reaches only the master it belongs to";
      stimulus = "both masters read slave 0 with pipelined multi-beat bursts; the slave interleaves R beats of different IDs";
    endfunction
    virtual function void configure();
      slv_cfg[0].rd_interleave = 1; slv_cfg[0].r_beat_delay_max = 2;
    endfunction
    task main();
      axi4_base_seq s[S_COUNT];
      foreach (s[i]) begin
        xbar_rand_seq q = xbar_rand_seq::type_id::create($sformatf("q%0d", i)); q.master = i;
        q.num_txn = 60; q.wr_pct = 0; q.mapped = 0; q.max_len = 15; q.sideband = 0;
        q.add_window(region_base(0, 0), region_last(0, 0));
        s[i] = q;
      end
      run_on_all(s);
    endtask
  endclass

  // Demonstrates known issue XBAR-03 (IDs not split): expected to fail.
  class xbar_decerr_id_order_test extends xbar_base_test;
    `uvm_component_utils(xbar_decerr_id_order_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "a DECERR response keeps its place among the responses of the same ID (AXI4 A5.3.1 ordering)";
      stimulus = "master 1, one ID only: pipelined writes and reads to a slow slave mixed with accesses to unmapped space";
    endfunction
    virtual function void configure();
      foreach (slv_cfg[i]) begin slv_cfg[i].b_delay_max = 20; slv_cfg[i].r_delay_max = 20; end
    endfunction
    task main();
      xbar_rand_seq q = xbar_rand_seq::type_id::create("q"); q.master = 1;
      q.num_txn = 60; q.max_len = 3; q.unmapped = 1; q.split_decerr_ids = 0; q.id_lo = 5; q.id_hi = 5;
      q.start(env.mst[1].sequencer);
    endtask
  endclass

  // Address and data walks on every route, long bursts, all WRAP lengths.
  class xbar_directed_test extends xbar_base_test;
    `uvm_component_utils(xbar_directed_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "address, data and burst-geometry corner cases pass through the crossbar unchanged";
      stimulus = "per master: walking address over all 32 bits (mapped and unmapped), walking data in each slave, 256-beat bursts, wrapping WRAP bursts, 4KB-boundary bursts, ID all-zeros and all-ones to every slave";
    endfunction
    task main();
      for (int s = 0; s < S_COUNT; s++) begin
        axi4_addr_walk_seq   a  = axi4_addr_walk_seq::type_id::create("a");
        axi4_4k_boundary_seq k  = axi4_4k_boundary_seq::type_id::create("k");
        axi4_wrap_seq        w  = axi4_wrap_seq::type_id::create("w");
        axi4_max_burst_seq   mx = axi4_max_burst_seq::type_id::create("mx");
        a.start(env.mst[s].sequencer);
        begin
          xbar_id_corner_seq ids = xbar_id_corner_seq::type_id::create("ids");
          ids.start(env.mst[s].sequencer);
        end
        for (int m = 0; m < M_COUNT; m++) begin
          axi4_data_walk_seq d = axi4_data_walk_seq::type_id::create("d");
          d.base = region_base(m, 1) + 32'h100;
          d.start(env.mst[s].sequencer);
          k.win_lo.delete(); k.win_hi.delete(); w.win_lo.delete(); w.win_hi.delete(); mx.win_lo.delete(); mx.win_hi.delete();
          k.add_window(region_base(m, 0), region_last(m, 0));  k.num_txn = 20; k.sideband = 1; k.pipelined = 0;
          w.add_window(region_base(m, 1), region_last(m, 1));  w.num_txn = 20; w.sideband = 1; w.pipelined = 0;
          mx.add_window(region_base(m, 0), region_last(m, 0)); mx.num_txn = 4; mx.pipelined = 0;
          k.start(env.mst[s].sequencer);
          w.start(env.mst[s].sequencer);
          mx.start(env.mst[s].sequencer);
        end
      end
    endtask
  endclass
endpackage
