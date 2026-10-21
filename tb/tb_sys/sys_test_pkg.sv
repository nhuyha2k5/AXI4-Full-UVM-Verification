// Environment and tests of the system-level testbench
// (AXI4 VIP master + axi_cdma -> axi_crossbar -> 2 x axi_ram).
package sys_test_pkg;
  timeunit 1ns;
  timeprecision 1ps;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import axi4_pkg::*;
  import dv_common_pkg::*;
  import dma_tb_pkg::*;

  // Address map produced by the crossbar's default address computation.
  localparam bit [31:0] RAM0_BASE = 32'h0000_0000;
  localparam bit [31:0] RAM1_BASE = 32'h0001_0000;
  // Each RAM is split in two halves: the lower one is used by the cpu master,
  // the upper one by the DMA engine, so the two never write the same bytes at
  // the same time (the reference memory is shared, the ordering between two
  // independent masters is not defined).
  localparam bit [31:0] HALF = 32'h0000_8000;

  class sys_env extends uvm_env;
    `uvm_component_utils(sys_env)
    axi4_agent_cfg                 cpu_cfg, dma_port_cfg, ram_cfg[2];
    axi4_agent                     cpu, dma_port, ram_port[2];
    dma_tb_cfg                     dma_cfg;
    uvm_sequencer #(dma_desc_item) desc_sqr;
    dma_desc_driver                desc_drv;
    dma_desc_monitor               desc_mon;
    dma_scoreboard                 dma_sb;       // copy semantics of the DMA engine
    dma_coverage                   dma_cov;
    axi4_mem_scoreboard            cpu_sb;       // everything the cpu master reads
    axi4_mem_scoreboard            dma_mem_sb;   // everything the DMA engine reads; its writes update the same memory

    function new(string n, uvm_component p);
      super.new(n, p);
    endfunction

    function void build_phase(uvm_phase phase);
      cpu = axi4_agent::type_id::create("cpu", this);           cpu.cfg = cpu_cfg;
      dma_port = axi4_agent::type_id::create("dma_port", this); dma_port.cfg = dma_port_cfg;
      foreach (ram_port[i]) begin
        ram_port[i] = axi4_agent::type_id::create($sformatf("ram_port%0d", i), this);
        ram_port[i].cfg = ram_cfg[i];
      end
      desc_sqr = uvm_sequencer #(dma_desc_item)::type_id::create("desc_sqr", this);
      desc_drv = dma_desc_driver::type_id::create("desc_drv", this);
      desc_mon = dma_desc_monitor::type_id::create("desc_mon", this);
      desc_drv.vif = dma_cfg.dma_vif;
      desc_mon.vif = dma_cfg.dma_vif;
      dma_sb  = dma_scoreboard::type_id::create("dma_sb", this);
      dma_cov = dma_coverage::type_id::create("dma_cov", this);
      dma_sb.cfg = dma_cfg; dma_sb.cov = dma_cov; dma_cov.cfg = dma_cfg;
      cpu_sb     = axi4_mem_scoreboard::type_id::create("cpu_sb", this);
      dma_mem_sb = axi4_mem_scoreboard::type_id::create("dma_mem_sb", this);
      // One reference memory for both scoreboards.
      cpu_sb.mem     = axi4_mem_model::type_id::create("ref_mem");
      dma_mem_sb.mem = cpu_sb.mem;
      cpu_sb.vif     = cpu_cfg.vif;
      dma_mem_sb.vif = cpu_cfg.vif;
    endfunction

    function void connect_phase(uvm_phase phase);
      desc_drv.seq_item_port.connect(desc_sqr.seq_item_export);
      desc_mon.req_ap.connect(dma_sb.req_export);
      desc_mon.status_ap.connect(dma_sb.status_export);
      dma_port.ap.connect(dma_sb.axi_export);
      cpu.addr_ap.connect(cpu_sb.addr_export);
      cpu.ap.connect(cpu_sb.done_export);
      dma_port.addr_ap.connect(dma_mem_sb.addr_export);
      dma_port.ap.connect(dma_mem_sb.done_export);
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Base test.
  // ---------------------------------------------------------------------------
  virtual class sys_base_test extends dv_base_test;
    sys_env               env;
    virtual dv_clk_rst_if clk_rst;

    function new(string n, uvm_component p);
      super.new(n, p);
      dut_name = "system: axi_cdma + AXI4 VIP master -> axi_crossbar (2x2, default address map) -> 2 x axi_ram (PIPELINE_OUTPUT 0 and 1); RTL built with the opt-in fixes listed for testbench sys in scripts/dv_config.ps1";
      checking = "cpu_sb / dma_mem_sb: shared byte-accurate reference memory (what one master wrote, the other must read); dma_scoreboard: copy semantics and status; axi4_monitor protocol checks on cpu, DMA and both RAM ports; axi4_if SVA";
    endfunction

    virtual function void configure();
    endfunction

    function axi4_agent_cfg make_cfg(string name, string vif_key, axi4_agent_role_e role, int id_width);
      axi4_agent_cfg  c = axi4_agent_cfg::type_id::create({name, "_cfg"});
      virtual axi4_if v;
      if (!uvm_config_db#(virtual axi4_if)::get(this, "", vif_key, v)) `uvm_fatal("CFG", {vif_key, " missing"})
      c.name = name; c.role = role; c.vif = v; c.id_width = id_width;
      c.enable_coverage = (role == AXI4_MASTER_AGENT);
      c.log_txn = (role == AXI4_MASTER_AGENT) || (name == "dma_port");
      return c;
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual dv_clk_rst_if)::get(this, "", "clk_rst_vif", clk_rst)) `uvm_fatal("CFG", "clk_rst_vif missing")
      env = sys_env::type_id::create("env", this);
      env.cpu_cfg      = make_cfg("cpu", "cpu_vif", AXI4_MASTER_AGENT, 8);
      env.dma_port_cfg = make_cfg("dma_port", "dma_axi_vif", AXI4_PASSIVE_AGENT, 8);
      env.ram_cfg[0]   = make_cfg("ram0", "ram_vif0", AXI4_PASSIVE_AGENT, 9);
      env.ram_cfg[1]   = make_cfg("ram1", "ram_vif1", AXI4_PASSIVE_AGENT, 9);
      // Coverage scope of the cpu port: what axi_ram supports behind the crossbar.
      env.cpu_cfg.cov_wrap = 0; env.cpu_cfg.cov_err_resp = 0; env.cpu_cfg.cov_sparse_strb = 1;
      // The crossbar port of the cpu has no address register: AxREADY comes from the decoder.
      env.cpu_cfg.cov_aw_nostall = 0; env.cpu_cfg.cov_ar_nostall = 0;
      env.cpu_cfg.max_wr_outstanding = 6; env.cpu_cfg.max_rd_outstanding = 6;
      env.dma_cfg = dma_tb_cfg::type_id::create("dma_cfg");
      env.dma_cfg.kind = DMA_CDMA; env.dma_cfg.max_burst_len = 16; env.dma_cfg.enable_unaligned = 1;
      if (!uvm_config_db#(virtual dma_if)::get(this, "", "dma_vif", env.dma_cfg.dma_vif)) `uvm_fatal("CFG", "dma_vif missing")
      configure();
      cfg_lines.push_back(env.cpu_cfg.convert2string());
      cfg_lines.push_back("address map: RAM0 0x0000_0000-0x0000_FFFF, RAM1 0x0001_0000-0x0001_FFFF; cpu uses the lower half of each RAM, the DMA engine the upper half");
    endfunction

    virtual function int unsigned num_checks();
      return env.cpu_sb.num_checks() + env.dma_mem_sb.num_checks() + env.dma_sb.num_checks();
    endfunction

    virtual function void result_lines(ref string q[$]);
      q.push_back({"cpu reads        : ", env.cpu_sb.summary()});
      q.push_back({"DMA reads/writes : ", env.dma_mem_sb.summary()});
      q.push_back({"DMA descriptors  : ", env.dma_sb.summary()});
      q.push_back($sformatf("traffic          : cpu wr/rd=%0d/%0d  dma wr/rd=%0d/%0d  ram0 wr/rd=%0d/%0d  ram1 wr/rd=%0d/%0d",
                            env.cpu.monitor.n_wr, env.cpu.monitor.n_rd, env.dma_port.monitor.n_wr, env.dma_port.monitor.n_rd,
                            env.ram_port[0].monitor.n_wr, env.ram_port[0].monitor.n_rd, env.ram_port[1].monitor.n_wr, env.ram_port[1].monitor.n_rd));
    endfunction

    // cpu traffic restricted to one or more windows; WRAP bursts never wrap (axi_ram limitation RAM-01).
    function axi4_rand_seq cpu_seq(string name, int unsigned n, bit readback);
      axi4_rand_seq s;
      if (readback) begin axi4_write_read_seq w = axi4_write_read_seq::type_id::create(name); s = w; end
      else          s = axi4_rand_seq::type_id::create(name);
      s.num_txn = n; s.wrap_at_boundary = 1; s.sideband = 1; s.sparse_pct = 20; s.max_len = 255;
      return s;
    endfunction

    // A copy inside the DMA halves of the two RAMs, source and destination apart.
    bit [31:0] prev_src_end;
    function dma_desc_item make_copy(int unsigned max_len = 600);
      dma_desc_item d = dma_desc_item::type_id::create("d");
      bit [31:0]    base[2] = '{RAM0_BASE + HALF, RAM1_BASE + HALF};
      int unsigned  src_ram = $urandom_range(1, 0), dst_ram = $urandom_range(1, 0);
      d.len = $urandom_range(max_len, 1);
      // A copy never starts in the last source word of the previous copy:
      // axi_cdma may read that word a second time, and the DMA scoreboard could
      // not tell that burst from the first burst of this copy.
      do d.read_addr = base[src_ram] + $urandom_range(HALF - d.len - 8, 0);
      while (d.read_addr + 8 > prev_src_end && d.read_addr <= prev_src_end);
      prev_src_end = d.read_addr + d.len;

      do d.write_addr = base[dst_ram] + $urandom_range(HALF - d.len - 8, 0);
      while (src_ram == dst_ram && ((d.write_addr > d.read_addr ? d.write_addr - d.read_addr : d.read_addr - d.write_addr) < d.len + 8));
      d.tag = $urandom_range(255, 0);
      return d;
    endfunction

    task run_copies(dma_desc_item list[$]);
      dma_desc_list_seq ds = dma_desc_list_seq::type_id::create("ds");
      int unsigned      target = env.dma_sb.n_desc_done + list.size();
      ds.list = list;
      ds.start(env.desc_sqr);
      while (env.dma_sb.n_desc_done < target) clk_rst.wait_clocks(4);
    endtask

    // One descriptor at a time: the next one is issued after the status of the previous one.
    task run_copies_serial(dma_desc_item list[$]);
      foreach (list[i]) begin
        dma_desc_item one[$];
        one.push_back(list[i]);
        run_copies(one);
      end
    endtask

    // 256-beat writes of random data that cover both DMA halves; sent by the
    // cpu master so that the DMA engine has real data to copy.
    axi4_seq_item fill_q[$];
    function void cpu_fill_dma_halves();
      fill_q.delete();
      for (int r = 0; r < 2; r++) for (bit [31:0] a = HALF; a < 2 * HALF; a += 1024) begin
        axi4_seq_item t = axi4_seq_item::type_id::create("t");
        bit [31:0]    target = (r ? RAM1_BASE : RAM0_BASE) + a;
        if (!t.randomize() with { cmd == AXI4_WRITE; addr == local::target; len == 255; size == 2; burst == AXI4_BURST_INCR; id < 256; })
          `uvm_fatal("SYS", "fill item randomization failed")
        fill_q.push_back(t);
      end
    endfunction

    // Reads both DMA halves back through the cpu master (checked by cpu_sb).
    task cpu_read_dma_halves();
      for (int r = 0; r < 2; r++) begin
        axi4_region_read_seq rd = axi4_region_read_seq::type_id::create("rd");
        rd.lo = (r ? RAM1_BASE : RAM0_BASE) + HALF; rd.hi = (r ? RAM1_BASE : RAM0_BASE) + 2 * HALF - 1; rd.beats = 256;
        rd.start(env.cpu.sequencer);
      end
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

  // Sends a prepared list of items on the cpu sequencer.
  class sys_item_list_seq extends axi4_base_seq;
    `uvm_object_utils(sys_item_list_seq)
    axi4_seq_item list[$];
    function new(string n = "sys_item_list_seq");
      super.new(n);
    endfunction
    virtual task body();
      foreach (list[i]) issue(list[i], 0);
      wait_all();
    endtask
  endclass

  class sys_smoke_test extends sys_base_test;
    `uvm_component_utils(sys_smoke_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "data written by the cpu master to one RAM is copied by the DMA engine to the other RAM and read back correctly by the cpu master";
      stimulus = "cpu fills the DMA halves; 4 DMA copies (RAM0->RAM1, RAM1->RAM0, within RAM0, within RAM1); cpu reads everything back";
    endfunction
    task main();
      sys_item_list_seq fill = sys_item_list_seq::type_id::create("fill");
      dma_desc_item     list[$];
      cpu_fill_dma_halves();
      fill.list = fill_q;
      fill.start(env.cpu.sequencer);
      repeat (4) list.push_back(make_copy());
      list[0].read_addr = RAM0_BASE + HALF + 32'h101; list[0].write_addr = RAM1_BASE + HALF + 32'h2003;
      list[1].read_addr = RAM1_BASE + HALF + 32'h4ffe; list[1].write_addr = RAM0_BASE + HALF + 32'h6000;
      run_copies(list);
      cpu_read_dma_halves();
    endtask
  endclass

  class sys_random_test extends sys_base_test;
    `uvm_component_utils(sys_random_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      timeout_us = 40000;
      intent   = "the cpu master and the DMA engine use both RAMs through the crossbar at the same time without disturbing each other";
      stimulus = "cpu fills the DMA halves; then 40 random DMA copies run while the cpu does 300 random pipelined accesses in its own halves; finally the cpu reads all DMA results back";
    endfunction
    virtual function void configure();
      env.cpu_cfg.set_backpressure(dv_plusarg_int("BP_PCT", $urandom_range(100, 30)), $urandom_range(3, 0));
    endfunction
    task main();
      sys_item_list_seq fill = sys_item_list_seq::type_id::create("fill");
      axi4_rand_seq     traffic = cpu_seq("traffic", 300, 0);
      axi4_rand_seq     verify  = cpu_seq("verify", 80, 1);
      dma_desc_item     list[$];
      cpu_fill_dma_halves();
      fill.list = fill_q;
      fill.start(env.cpu.sequencer);
      repeat (40) list.push_back(make_copy());
      traffic.add_window(RAM0_BASE, RAM0_BASE + HALF - 1);
      traffic.add_window(RAM1_BASE, RAM1_BASE + HALF - 1);
      fork
        run_copies(list);
        traffic.start(env.cpu.sequencer);
      join
      verify.add_window(RAM0_BASE, RAM0_BASE + HALF - 1);
      verify.add_window(RAM1_BASE, RAM1_BASE + HALF - 1);
      verify.start(env.cpu.sequencer);
      cpu_read_dma_halves();
    endtask
  endclass

  // Accesses outside both RAMs: the crossbar answers DECERR and the DMA engine
  // reports it in its status.
  class sys_decerr_test extends sys_base_test;
    `uvm_component_utils(sys_decerr_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "a DMA descriptor that points outside the address map ends with a read or write DECERR status; the engine and the cpu master keep working afterwards";
      stimulus = "6 DMA copies issued one at a time, three of them with an unmapped source or destination; cpu accesses to unmapped space; then 4 legal copies back to back";
      checking = {checking, "; DECERR status codes 5 (read) and 7 (write) derived from the responses seen on the DMA port"};
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      // Known issue XBAR-01 (response of a rejected access issued too early), see docs/KNOWN_ISSUES.md.
      waive_known_issue("XBAR-01", "AXI_PROTOCOL", "(response AXI4_RESP_DECERR issued too early)");
    endfunction
    function void end_of_elaboration_phase(uvm_phase phase);
      env.cpu_sb.expect_okay = 0;
      env.dma_mem_sb.expect_okay = 0;
    endfunction
    task main();
      sys_item_list_seq fill = sys_item_list_seq::type_id::create("fill");
      axi4_rand_seq     bad  = cpu_seq("bad", 20, 0);
      dma_desc_item     list[$];
      cpu_fill_dma_halves();
      fill.list = fill_q;
      fill.start(env.cpu.sequencer);
      repeat (6) list.push_back(make_copy(200));
      list[0].read_addr  = 32'h0004_0000 + $urandom_range(4000, 0);   // unmapped source
      list[2].write_addr = 32'h7000_0000 + $urandom_range(4000, 0);   // unmapped destination
      list[4].read_addr  = 32'hFFFF_0000;                             // unmapped source again
      // One descriptor at a time.  axi_cdma uses a single AXI ID and starts on
      // the next descriptor before the last response of the current one is in;
      // with a rejected access in that window the crossbar returns the DECERR
      // out of order (known issue XBAR-03, shown by sys_decerr_pipelined_test).
      run_copies_serial(list);
      // One access at a time: known issue XBAR-03 concerns pipelined accesses with one ID.
      bad.pipelined = 0; bad.add_window(32'h0002_0000, 32'h0FFF_FFFF);
      bad.start(env.cpu.sequencer);
      list.delete();
      repeat (4) list.push_back(make_copy(200));
      run_copies(list);
      cpu_read_dma_halves();
    endtask
  endclass

  // Demonstrates the system-level effect of known issue XBAR-03: expected to fail.
  // axi_cdma starts the first write of the next descriptor before the last
  // write response of the current one has arrived, and all its accesses use
  // AXI ID 0.  The DECERR that the crossbar generates for the rejected write
  // overtakes the response of the RAM, so the engine reports the error in the
  // status of the wrong descriptor.
  class sys_decerr_pipelined_test extends sys_base_test;
    `uvm_component_utils(sys_decerr_pipelined_test)
    uvm_tlm_analysis_fifo #(dma_desc_item) status_fifo;
    function new(string n, uvm_component p);
      super.new(n, p);
      status_fifo = new("status_fifo", this);
      intent   = "a DMA copy to an unmapped destination that directly follows a legal copy reports the DECERR in its own status, and the legal copy reports no error";
      stimulus = "10 pairs of descriptors issued back to back (legal copy, then a copy with an unmapped destination) while the cpu writes long bursts to the same RAMs";
      checking = {checking, "; test: status of every legal copy must be error 0 and of every rejected copy error 7 (write DECERR)"};
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      waive_known_issue("XBAR-01", "AXI_PROTOCOL", "(response AXI4_RESP_DECERR issued too early)");
    endfunction
    function void connect_phase(uvm_phase phase);
      env.desc_mon.status_ap.connect(status_fifo.analysis_export);
    endfunction
    function void end_of_elaboration_phase(uvm_phase phase);
      env.cpu_sb.expect_okay = 0;
      env.dma_mem_sb.expect_okay = 0;
    endfunction
    task main();
      sys_item_list_seq fill = sys_item_list_seq::type_id::create("fill");
      axi4_rand_seq     traffic = cpu_seq("traffic", 120, 0);
      dma_desc_item     list[$];
      dma_desc_item     st;
      cpu_fill_dma_halves();
      fill.list = fill_q;
      fill.start(env.cpu.sequencer);
      repeat (20) list.push_back(make_copy(200));
      for (int i = 1; i < 20; i += 2) list[i].write_addr = 32'h7000_0000 + $urandom_range(4000, 0);   // unmapped destination
      traffic.wr_pct = 100; traffic.max_len = 255; traffic.use_fixed = 0; traffic.use_wrap = 0;
      traffic.add_window(RAM0_BASE, RAM0_BASE + HALF - 1);
      traffic.add_window(RAM1_BASE, RAM1_BASE + HALF - 1);
      fork
        run_copies(list);
        traffic.start(env.cpu.sequencer);
      join
      foreach (list[i]) begin
        bit [3:0] exp_e = (i % 2) ? DMA_ERR_WR_DECERR : DMA_ERR_NONE;
        if (!status_fifo.try_get(st)) begin `uvm_error("SYS_DECERR", $sformatf("no status for descriptor %0d", i)) break; end
        if (st.st_tag != list[i].tag || st.st_error != exp_e)
          `uvm_error("SYS_DECERR", $sformatf("descriptor %0d (%s): status tag=%0h error=%0d, expected tag=%0h error=%0d",
                                             i, (i % 2) ? "unmapped destination" : "legal copy", st.st_tag, st.st_error, list[i].tag, exp_e))
      end
    endtask
  endclass
endpackage