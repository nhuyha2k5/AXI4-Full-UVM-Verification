// =============================================================================
// AXI4 agent.  Role comes from axi4_agent_cfg:
//   AXI4_MASTER_AGENT  : sequencer + master driver + monitor
//   AXI4_SLAVE_AGENT   : reactive slave driver (memory model) + monitor
//   AXI4_PASSIVE_AGENT : monitor only
// The monitor also performs the transaction-level protocol checks, and a
// coverage collector is attached when cfg.enable_coverage is set.
// =============================================================================
class axi4_agent extends uvm_agent;
  `uvm_component_utils(axi4_agent)

  axi4_agent_cfg       cfg;
  axi4_sequencer       sequencer;
  axi4_master_driver   master_driver;
  axi4_slave_driver    slave_driver;
  axi4_monitor         monitor;
  axi4_coverage        coverage;
  uvm_analysis_port #(axi4_seq_item) ap;       // completed transactions
  uvm_analysis_port #(axi4_seq_item) addr_ap;  // accepted address phases

  function new(string n, uvm_component p);
    super.new(n, p);
    ap      = new("ap", this);
    addr_ap = new("addr_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (cfg == null && !uvm_config_db#(axi4_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("CFG", "Missing axi4_agent_cfg")
    if (cfg.role == AXI4_PASSIVE_AGENT) cfg.is_active = UVM_PASSIVE;
    uvm_config_db#(axi4_agent_cfg)::set(this, "*", "cfg", cfg);

    monitor = axi4_monitor::type_id::create("monitor", this);
    if (cfg.enable_coverage) coverage = axi4_coverage::type_id::create("coverage", this);
    if (cfg.is_active == UVM_ACTIVE) begin
      if (cfg.role == AXI4_MASTER_AGENT) begin
        sequencer     = axi4_sequencer::type_id::create("sequencer", this);
        sequencer.cfg = cfg;
        master_driver = axi4_master_driver::type_id::create("driver", this);
      end else begin
        if (cfg.mem == null) cfg.mem = axi4_mem_model::type_id::create({cfg.name, "_mem"});
        slave_driver = axi4_slave_driver::type_id::create("driver", this);
      end
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    monitor.ap.connect(ap);
    monitor.addr_ap.connect(addr_ap);
    if (coverage != null) monitor.ap.connect(coverage.analysis_export);
    if (master_driver != null) master_driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass
