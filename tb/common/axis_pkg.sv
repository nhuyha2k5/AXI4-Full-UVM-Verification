// Small AXI4-Stream agent used by the DMA testbenches (not part of the AXI4 VIP).
// A frame is a list of bytes; the driver packs them into beats, the monitor
// unpacks them again using TKEEP.
`include "axi4_defines.svh"
package axis_pkg;
  timeunit 1ns;
  timeprecision 1ps;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam int AXIS_BYTES = `AXI4_DATA_WIDTH / 8;

  typedef enum int { AXIS_SOURCE, AXIS_SINK, AXIS_PASSIVE } axis_role_e;

  class axis_cfg extends uvm_object;
    `uvm_object_utils(axis_cfg)
    string          name = "axis";
    axis_role_e     role = AXIS_SOURCE;
    virtual axis_if vif;
    int unsigned    valid_pct = 100;   // source: per-cycle chance to present the next beat
    int unsigned    ready_pct = 100;   // sink: per-cycle chance that TREADY is high
    bit             log_frames = 1;
    // source: random payload (including TLAST) while TVALID is low, so that a
    // DUT that looks at the payload without TVALID is found out
    bit             randomize_idle = 1;
    function new(string name = "axis_cfg");
      super.new(name);
    endfunction
  endclass

  class axis_item extends uvm_sequence_item;
    `uvm_object_utils(axis_item)
    bit [7:0]    bytes[$];
    bit [7:0]    tid;
    bit [7:0]    tdest;
    bit          tuser;
    // observed by the monitor
    int unsigned beats;
    int unsigned stall_max;      // longest wait of a beat for TREADY
    bit          keep_error;     // TKEEP was not "all ones, then low bytes on the last beat"
    bit          skip;           // set by a stopped sequence: the driver discards the item
    time         t_start, t_end;
    bit          done;
    function new(string name = "axis_item");
      super.new(name);
    endfunction
    function void randomize_bytes(int unsigned n);
      bytes.delete();
      repeat (n) bytes.push_back($urandom_range(255, 0));
    endfunction
    virtual function string convert2string();
      string s = $sformatf("frame %0d bytes in %0d beats tid=%0h tdest=%0h tuser=%0b data=[", bytes.size(), beats, tid, tdest, tuser);
      foreach (bytes[i]) begin
        if (i == 8) begin s = {s, $sformatf(" ..+%0d", bytes.size() - 8)}; break; end
        s = {s, $sformatf("%02h", bytes[i])};
      end
      return {s, "]"};
    endfunction
  endclass

  class axis_source_driver extends uvm_driver #(axis_item);
    `uvm_component_utils(axis_source_driver)
    axis_cfg        cfg;
    virtual axis_if vif;
    function new(string n, uvm_component p);
      super.new(n, p);
    endfunction
    function void build_phase(uvm_phase phase);
      vif = cfg.vif;
    endfunction
    protected function void idle();
      vif.tvalid <= 1'b0;
      if (cfg.randomize_idle) begin
        for (int k = 0; k < `AXI4_DATA_WIDTH; k += 32) vif.tdata[k +: 32] <= $urandom();
        vif.tkeep <= $urandom(); vif.tlast <= $urandom(); vif.tid <= $urandom(); vif.tdest <= $urandom(); vif.tuser <= $urandom();
      end else begin
        vif.tdata <= '0; vif.tkeep <= '0; vif.tlast <= 1'b0;
        vif.tid <= '0; vif.tdest <= '0; vif.tuser <= 1'b0;
      end
    endfunction
    protected time t_cb;   // time of the last clocking event this thread woke on
    protected task tick();
      @(vif.cb);
      t_cb = $time;
    endtask
    // Sends one frame; returns early (frame abandoned) if reset is asserted.
    protected task send(axis_item t);
      int unsigned n = t.bytes.size();
      int unsigned nbeats = (n + AXIS_BYTES - 1) / AXIS_BYTES;
      for (int unsigned b = 0; b < nbeats; b++) begin
        logic [`AXI4_DATA_WIDTH-1:0]   d = '0;
        logic [`AXI4_DATA_WIDTH/8-1:0] k = '0;
        for (int i = 0; i < AXIS_BYTES; i++) if (b * AXIS_BYTES + i < n) begin
          d[8*i +: 8] = t.bytes[b * AXIS_BYTES + i];
          k[i] = 1'b1;
        end
        while ($urandom_range(99, 0) >= cfg.valid_pct) begin
          idle();
          tick();
          if (vif.cb.rst_n !== 1'b1) return;
        end
        vif.tdata <= d; vif.tkeep <= k; vif.tlast <= (b == nbeats - 1);
        vif.tid <= t.tid; vif.tdest <= t.tdest; vif.tuser <= t.tuser;
        vif.tvalid <= 1'b1;
        do begin
          tick();
          if (vif.cb.rst_n !== 1'b1) return;
        end while (vif.cb.tready !== 1'b1);
        idle();
      end
    endtask
    task run_phase(uvm_phase phase);
      axis_item t;
      idle();
      forever begin
        seq_item_port.get_next_item(t);
        // Drive only after a clocking event (an item can arrive mid time step).
        if ($time != t_cb) tick();
        if (t.skip) begin t.done = 1; seq_item_port.item_done(); continue; end
        while (vif.cb.rst_n !== 1'b1) begin idle(); tick(); end
        send(t);
        if (vif.cb.rst_n !== 1'b1) idle();
        t.done = 1;
        seq_item_port.item_done();
      end
    endtask
  endclass

  class axis_sink_driver extends uvm_component;
    `uvm_component_utils(axis_sink_driver)
    axis_cfg        cfg;
    virtual axis_if vif;
    function new(string n, uvm_component p);
      super.new(n, p);
    endfunction
    function void build_phase(uvm_phase phase);
      vif = cfg.vif;
    endfunction
    task run_phase(uvm_phase phase);
      vif.tready <= 1'b0;
      forever begin
        @(vif.cb);
        vif.tready <= (vif.cb.rst_n === 1'b1) && ($urandom_range(99, 0) < cfg.ready_pct);
      end
    endtask
  endclass

  class axis_monitor extends uvm_monitor;
    `uvm_component_utils(axis_monitor)
    axis_cfg        cfg;
    virtual axis_if vif;
    uvm_analysis_port #(axis_item) ap;
    int unsigned n_frames, n_beats, n_bytes;
    function new(string n, uvm_component p);
      super.new(n, p);
      ap = new("ap", this);
    endfunction
    function void build_phase(uvm_phase phase);
      vif = cfg.vif;
    endfunction
    task run_phase(uvm_phase phase);
      axis_item    t;
      int unsigned stall;
      forever begin
        @(vif.cb);
        if (vif.cb.rst_n !== 1'b1) begin t = null; stall = 0; continue; end
        if (vif.cb.tvalid !== 1'b1) continue;
        if (vif.cb.tready !== 1'b1) begin stall++; continue; end
        if (t == null) begin
          t = axis_item::type_id::create("frame");
          t.t_start = $time;
        end
        // TKEEP must be contiguous from byte 0, and full on every beat but the last.
        begin
          int unsigned cnt = 0;
          for (int i = 0; i < AXIS_BYTES; i++) if (vif.cb.tkeep[i]) begin
            if (cnt != i) t.keep_error = 1;
            t.bytes.push_back(vif.cb.tdata[8*i +: 8]);
            cnt++;
          end
          if (!vif.cb.tlast && cnt != AXIS_BYTES) t.keep_error = 1;
        end
        t.beats++;
        if (stall > t.stall_max) t.stall_max = stall;
        stall = 0;
        n_beats++;
        if (vif.cb.tlast === 1'b1) begin
          t.tid = vif.cb.tid; t.tdest = vif.cb.tdest; t.tuser = vif.cb.tuser;
          t.t_end = $time;
          n_frames++; n_bytes += t.bytes.size();
          if (cfg.log_frames) `uvm_info("AXIS_FRAME", $sformatf("%s: %s", cfg.name, t.convert2string()), UVM_MEDIUM)
          ap.write(t);
          t = null;
        end
      end
    endtask
  endclass

  class axis_agent extends uvm_agent;
    `uvm_component_utils(axis_agent)
    axis_cfg                    cfg;
    uvm_sequencer #(axis_item)  sequencer;
    axis_source_driver          source;
    axis_sink_driver            sink;
    axis_monitor                monitor;
    function new(string n, uvm_component p);
      super.new(n, p);
    endfunction
    function void build_phase(uvm_phase phase);
      monitor = axis_monitor::type_id::create("monitor", this);
      monitor.cfg = cfg;
      if (cfg.role == AXIS_SOURCE) begin
        sequencer = uvm_sequencer #(axis_item)::type_id::create("sequencer", this);
        source    = axis_source_driver::type_id::create("driver", this);
        source.cfg = cfg;
      end else if (cfg.role == AXIS_SINK) begin
        sink = axis_sink_driver::type_id::create("driver", this);
        sink.cfg = cfg;
      end
    endfunction
    function void connect_phase(uvm_phase phase);
      if (source != null) source.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
  endclass
endpackage
