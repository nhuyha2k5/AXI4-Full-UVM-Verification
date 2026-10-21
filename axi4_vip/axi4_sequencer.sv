// Sequencer for AXI4 transactions.  Sequences read the port limits from cfg.
class axi4_sequencer extends uvm_sequencer #(axi4_seq_item);
  `uvm_component_utils(axi4_sequencer)
  axi4_agent_cfg cfg;
  function new(string n, uvm_component p);
    super.new(n, p);
  endfunction
endclass
