// Environment and tests for axi_ram.
package ram_test_pkg;
  timeunit 1ns;
  timeprecision 1ps;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import axi4_pkg::*;
  import dv_common_pkg::*;

  class ram_env extends uvm_env;
    `uvm_component_utils(ram_env)
    axi4_agent_cfg      cfg;
    axi4_agent          mst;
    axi4_mem_scoreboard sb;
    function new(string n, uvm_component p);
      super.new(n, p);
    endfunction
    function void build_phase(uvm_phase phase);
      mst = axi4_agent::type_id::create("mst", this);
      sb  = axi4_mem_scoreboard::type_id::create("sb", this);
      mst.cfg = cfg;
      sb.vif  = cfg.vif;
    endfunction
    function void connect_phase(uvm_phase phase);
      mst.addr_ap.connect(sb.addr_export);
      mst.ap.connect(sb.done_export);
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Base test.
  // ---------------------------------------------------------------------------
  virtual class ram_base_test extends dv_base_test;
    ram_env               env;
    axi4_agent_cfg        cfg;
    virtual axi4_if       vif;
    virtual dv_clk_rst_if clk_rst;
    int                   pipeline_output;
    string                init_file;

    function new(string n, uvm_component p);
      super.new(n, p);
      checking = "axi4_mem_scoreboard (byte-accurate reference memory, strobe aware); axi4_monitor protocol checks; axi4_if SVA";
    endfunction

    virtual function void configure();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual axi4_if)::get(this, "", "bus_vif", vif)) `uvm_fatal("CFG", "bus_vif missing")
      if (!uvm_config_db#(virtual dv_clk_rst_if)::get(this, "", "clk_rst_vif", clk_rst)) `uvm_fatal("CFG", "clk_rst_vif missing")
      void'(uvm_config_db#(int)::get(this, "", "pipeline_output", pipeline_output));
      void'(uvm_config_db#(string)::get(this, "", "init_file", init_file));
      dut_name = $sformatf("axi_ram (DATA_WIDTH=%0d ADDR_WIDTH=%0d ID_WIDTH=%0d PIPELINE_OUTPUT=%0d INIT_FILE=\"%s\")",
                           AXI4_DATA_WIDTH, AXI4_ADDR_WIDTH, AXI4_ID_WIDTH, pipeline_output, init_file);
      cfg = axi4_agent_cfg::type_id::create("cfg");
      cfg.name = "ram_mst"; cfg.role = AXI4_MASTER_AGENT; cfg.vif = vif;
      cfg.max_wr_outstanding = 4; cfg.max_rd_outstanding = 4;
      // Coverage scope of this port.  axi_ram never answers with an error, has
      // no QOS/REGION ports, does not implement WRAP (see axi_ram_wrap_test) and
      // holds at most one finished burst while it accepts the next one.
      cfg.cov_wrap = 0; cfg.cov_err_resp = 0; cfg.cov_qos = 0; cfg.cov_outstanding = 1;
      cfg.cov_sideband = 1; cfg.cov_prot = 1; cfg.cov_sparse_strb = 1;
      configure();
      cfg_lines.push_back(cfg.convert2string());
      env = ram_env::type_id::create("env", this);
      env.cfg = cfg;
    endfunction

    virtual function int unsigned num_checks();
      return env.sb.num_checks();
    endfunction

    virtual function void result_lines(ref string q[$]);
      q.push_back({"scoreboard       : ", env.sb.summary()});
      q.push_back($sformatf("bus traffic      : writes=%0d reads=%0d write_beats=%0d read_beats=%0d max_outstanding(wr/rd)=%0d/%0d resets=%0d",
                            env.mst.monitor.n_wr, env.mst.monitor.n_rd, env.mst.monitor.n_wr_beats, env.mst.monitor.n_rd_beats,
                            env.mst.monitor.max_wr_out, env.mst.monitor.max_rd_out, env.mst.monitor.n_resets));
      q.push_back($sformatf("functional cov   : %0.1f%% of the port covergroups in this test alone", env.mst.coverage.get_coverage()));
    endfunction

    // Random backpressure level for this seed unless +BP_PCT fixes it.
    function void random_backpressure();
      cfg.set_backpressure(dv_plusarg_int("BP_PCT", $urandom_range(100, 20)), dv_plusarg_int("DELAY_MAX", $urandom_range(6, 0)));
    endfunction

    function axi4_rand_seq rand_seq(string name, int unsigned n);
      axi4_rand_seq s = axi4_rand_seq::type_id::create(name);
      s.num_txn = dv_plusarg_int("NUM_TXN", n);
      // axi_ram does not wrap (see axi_ram_wrap_test).  WRAP bursts that start
      // on the wrap boundary never need to wrap and are legal stimulus for it.
      s.wrap_at_boundary = 1;
      s.sideband = 1;
      s.sparse_pct = 30;
      return s;
    endfunction

    pure virtual task main();

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      clk_rst.wait_reset_done();
      main();
      clk_rst.wait_clocks(20);
      phase.drop_objection(this);
    endtask
  endclass

  typedef class ram_smoke_seq;

  class axi_ram_smoke_test extends ram_base_test;
    `uvm_component_utils(axi_ram_smoke_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "basic write then read of one 4-beat INCR burst and one single beat";
      stimulus = "directed: write 4 words at 0x0100, read them back; write/read one word at 0xFFFC";
    endfunction
    task main();
      ram_smoke_seq s = ram_smoke_seq::type_id::create("s");
      s.start(env.mst.sequencer);
    endtask
  endclass

  class ram_smoke_seq extends axi4_base_seq;
    `uvm_object_utils(ram_smoke_seq)
    function new(string n = "ram_smoke_seq");
      super.new(n);
    endfunction
    virtual task body();
      axi4_data_t d[]   = '{32'hDEADBEEF, 32'h01234567, 32'h89ABCDEF, 32'hA5A55A5A};
      axi4_data_t one[] = '{32'hCAFEF00D};
      axi4_data_t r[];
      do_write(16'h0100, d, 8'h11);
      do_read(16'h0100, 4, r, 8'h22);
      do_write(16'hFFFC, one, 8'hFF);
      do_read(16'hFFFC, 1, r, 8'h00);
    endtask
  endclass

  class axi_ram_directed_test extends ram_base_test;
    `uvm_component_utils(axi_ram_directed_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "corner cases of address, data and burst geometry";
      stimulus = "address walk over all 16 address bits, walking data, INCR against 4KB boundaries, 256-beat bursts, FIXED bursts, write-then-read";
    endfunction
    task main();
      axi4_addr_walk_seq   s_addr = axi4_addr_walk_seq::type_id::create("s_addr");
      axi4_data_walk_seq   s_data = axi4_data_walk_seq::type_id::create("s_data");
      axi4_4k_boundary_seq s_4k   = axi4_4k_boundary_seq::type_id::create("s_4k");
      axi4_max_burst_seq   s_max  = axi4_max_burst_seq::type_id::create("s_max");
      axi4_write_read_seq  s_fix  = axi4_write_read_seq::type_id::create("s_fix");
      s_addr.start(env.mst.sequencer);
      s_data.base = 16'h4000; s_data.start(env.mst.sequencer);
      s_4k.num_txn = 60; s_4k.pipelined = 0; s_4k.start(env.mst.sequencer);
      s_max.num_txn = 8; s_max.pipelined = 0; s_max.start(env.mst.sequencer);
      s_fix.num_txn = 40; s_fix.use_incr = 0; s_fix.use_wrap = 0; s_fix.start(env.mst.sequencer);
    endtask
  endclass

  class axi_ram_write_read_test extends ram_base_test;
    `uvm_component_utils(axi_ram_write_read_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "data integrity for every burst type, size, alignment and strobe pattern the RAM supports";
      stimulus = "axi4_write_read_seq: random FIXED/INCR burst written, then the same burst read back; random backpressure";
    endfunction
    virtual function void configure();
      random_backpressure();
    endfunction
    task main();
      axi4_write_read_seq s = axi4_write_read_seq::type_id::create("s");
      s.num_txn = dv_plusarg_int("NUM_TXN", 150);
      s.wrap_at_boundary = 1; s.sideband = 1; s.sparse_pct = 40;
      s.start(env.mst.sequencer);
    endtask
  endclass

  class axi_ram_random_test extends ram_base_test;
    `uvm_component_utils(axi_ram_random_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "pipelined, concurrent reads and writes over the whole memory under random backpressure";
      stimulus = "axi4_rand_seq: FIXED/INCR, all sizes and lengths, unaligned, sparse strobes, all 256 IDs, random LOCK/CACHE/PROT";
    endfunction
    virtual function void configure();
      random_backpressure();
    endfunction
    task main();
      axi4_rand_seq s = rand_seq("s", 400);
      s.idle_max = 2;
      // Half of the seeds use a small window so that reads hit written data.
      if (seed % 2) s.add_window(16'h2000, 16'h3FFF);
      s.start(env.mst.sequencer);
    endtask
  endclass

  class axi_ram_backpressure_test extends ram_base_test;
    `uvm_component_utils(axi_ram_backpressure_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "the RAM holds responses and read data while the master is not ready, also with the next burst already accepted";
      stimulus = "pipelined short bursts with BREADY/RREADY high only 15% of the time";
    endfunction
    virtual function void configure();
      cfg.bready_pct = 15; cfg.rready_pct = 15;
    endfunction
    task main();
      axi4_rand_seq s = rand_seq("s", 300);
      s.max_len = 7;
      s.add_window(16'h8000, 16'h8FFF);
      s.start(env.mst.sequencer);
    endtask
  endclass

  class axi_ram_reset_test extends ram_base_test;
    `uvm_component_utils(axi_ram_reset_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "reset in the middle of bursts: the RAM returns to idle, keeps earlier contents and works again";
      stimulus = "random pipelined traffic interrupted by 4 resets at random times, then write-then-read traffic";
    endfunction
    virtual function void configure();
      cfg.set_backpressure(60, 3);
    endfunction
    task main();
      axi4_rand_seq       s;
      axi4_write_read_seq r = axi4_write_read_seq::type_id::create("r");
      repeat (4) begin
        s = rand_seq("s", 150);
        s.add_window(16'h0000, 16'h1FFF);
        fork
          s.start(env.mst.sequencer);
        join_none
        clk_rst.wait_clocks($urandom_range(300, 40));
        clk_rst.apply_reset($urandom_range(6, 2));
        s.wait_for_sequence_state(UVM_FINISHED);
      end
      r.num_txn = 60; r.use_wrap = 0; r.add_window(16'h0000, 16'h1FFF);
      r.start(env.mst.sequencer);
    endtask
  endclass

  // WRAP bursts that really wrap.  The scoreboard models AXI4; axi_ram treats
  // WRAP as INCR, so this test documents that limitation (expected to fail).
  class axi_ram_wrap_test extends ram_base_test;
    `uvm_component_utils(axi_ram_wrap_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "WRAP bursts wrap at the burst-size boundary as AXI4 requires";
      stimulus = "axi4_wrap_seq: WRAP bursts of 2/4/8/16 beats starting above the wrap boundary, written then read with INCR";
    endfunction
    task main();
      axi4_wrap_seq        s  = axi4_wrap_seq::type_id::create("s");
      axi4_region_read_seq rd = axi4_region_read_seq::type_id::create("rd");
      s.num_txn = 20; s.wr_pct = 100; s.pipelined = 0; s.narrow = 0;
      s.add_window(16'h1000, 16'h1FFF);
      s.start(env.mst.sequencer);
      // Read the whole window back with INCR so the stored result is checked.
      rd.lo = 16'h1000; rd.hi = 16'h1FFF;
      rd.start(env.mst.sequencer);
    endtask
  endclass

  // Build configuration "init": memory preloaded from a hex file.
  class axi_ram_init_file_test extends ram_base_test;
    `uvm_component_utils(axi_ram_init_file_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "INIT_FILE preloads the memory; the preloaded words read back and can be overwritten";
      stimulus = "read the whole 64 KB memory with 256-beat bursts, then random write-then-read over it";
    endfunction
    task main();
      axi4_region_read_seq rd = axi4_region_read_seq::type_id::create("rd");
      axi4_write_read_seq  s  = axi4_write_read_seq::type_id::create("s");
      bit [31:0]           img[0:16383];
      if (init_file == "") `uvm_fatal("RAM_INIT", "this test needs the 'init' build configuration (INIT_FILE set)")
      $readmemh(init_file, img);
      // Mirror the image into the reference memory.
      foreach (img[w]) for (int lane = 0; lane < 4; lane++) env.sb.mem.write_byte(w * 4 + lane, img[w][8*lane +: 8]);
      rd.lo = 16'h0000; rd.hi = 16'hFFFF; rd.beats = 256;
      rd.start(env.mst.sequencer);
      s.num_txn = 60; s.use_wrap = 0;
      s.start(env.mst.sequencer);
    endtask
  endclass
endpackage
