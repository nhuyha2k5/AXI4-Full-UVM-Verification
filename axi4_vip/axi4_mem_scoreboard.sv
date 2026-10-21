// =============================================================================
// Memory-model scoreboard for an AXI4 slave that behaves like a RAM.
//
// Works with fully pipelined, concurrent traffic:
//   - A write updates the reference memory when its response arrives.  Each
//     byte remembers the acceptance order (seq_no) of the write that last set
//     it, so writes that complete out of order still leave the right value.
//   - A read byte is compared only if no write to that byte was in flight at
//     any time between the read's AR and its last beat.  Such bytes are
//     counted as "skipped (concurrent write)" instead of being guessed.
//   - Bytes of writes cut off by a reset are unknown until rewritten.
// Connect addr_export to monitor.addr_ap and done_export to monitor.ap.
// =============================================================================
`uvm_analysis_imp_decl(_axi4_addr)
`uvm_analysis_imp_decl(_axi4_done)

class axi4_mem_scoreboard extends uvm_component;
  `uvm_component_utils(axi4_mem_scoreboard)

  uvm_analysis_imp_axi4_addr #(axi4_seq_item, axi4_mem_scoreboard) addr_export;
  uvm_analysis_imp_axi4_done #(axi4_seq_item, axi4_mem_scoreboard) done_export;

  axi4_mem_model  mem;                 // reference memory; created here when null
  virtual axi4_if vif;                 // optional: lets the scoreboard see resets
  bit             expect_okay = 1;     // an error response is itself an error
  int unsigned    max_err_print = 20;

  // A transaction in flight and the byte addresses it touches.
  class live_txn;
    axi4_seq_item    t;
    longint unsigned bytes[$];
    bit              in_range[longint unsigned];
    bit              taint[longint unsigned];   // read bytes a concurrent write may have changed
  endclass

  protected live_txn         wr_live[$];
  protected live_txn         rd_live[$];
  protected longint unsigned last_seq[longint unsigned];
  protected bit              unknown[longint unsigned];

  int unsigned n_wr_txn, n_rd_txn, n_wr_bytes, n_rd_checked, n_rd_skipped, n_mismatch, n_err_resp;

  function new(string n, uvm_component p);
    super.new(n, p);
    addr_export = new("addr_export", this);
    done_export = new("done_export", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (mem == null) mem = axi4_mem_model::type_id::create("ref_mem");
  endfunction

  task run_phase(uvm_phase phase);
    if (vif == null) return;
    forever begin
      @(vif.cb);
      if (vif.cb.ARESETn !== 1'b1 && (wr_live.size() + rd_live.size() > 0)) reset();
    end
  endtask

  // Drop in-flight state; bytes of interrupted writes become unknown.
  function void reset();
    foreach (wr_live[i]) foreach (wr_live[i].bytes[j]) unknown[wr_live[i].bytes[j]] = 1;
    wr_live.delete();
    rd_live.delete();
  endfunction

  protected function live_txn make_live(axi4_seq_item t);
    live_txn    l = new();
    axi4_strb_t mask;
    axi4_addr_t ba;
    longint unsigned a;
    l.t = t;
    for (int unsigned i = 0; i <= t.len; i++) begin
      ba   = t.beat_addr(i);
      mask = axi4_lane_mask(t.addr, i, t.len, t.size, t.burst);
      for (int b = 0; b < AXI4_DATA_BYTES; b++) if (mask[b]) begin
        a = axi4_lane_addr(ba, b) & mem.addr_mask;
        if (!l.in_range.exists(a)) begin l.in_range[a] = 1; l.bytes.push_back(a); end
      end
    end
    return l;
  endfunction

  function void write_axi4_addr(axi4_seq_item t);
    live_txn l = make_live(t);
    if (t.cmd == AXI4_WRITE) begin
      foreach (rd_live[k]) foreach (l.bytes[j])
        if (rd_live[k].in_range.exists(l.bytes[j])) rd_live[k].taint[l.bytes[j]] = 1;
      wr_live.push_back(l);
    end else begin
      foreach (wr_live[k]) foreach (wr_live[k].bytes[j])
        if (l.in_range.exists(wr_live[k].bytes[j])) l.taint[wr_live[k].bytes[j]] = 1;
      rd_live.push_back(l);
    end
  endfunction

  function void write_axi4_done(axi4_seq_item t);
    if (t.cmd == AXI4_WRITE) done_write(t);
    else                     done_read(t);
  endfunction

  protected function void done_write(axi4_seq_item t);
    longint unsigned a;
    foreach (wr_live[i]) if (wr_live[i].t == t) begin wr_live.delete(i); break; end
    n_wr_txn++;
    if (t.bresp != AXI4_RESP_OKAY) begin
      n_err_resp++;
      if (expect_okay) `uvm_error("AXI_SB", $sformatf("unexpected write response %s: %s", t.bresp.name(), t.convert2string()))
      return;
    end
    foreach (t.data[i]) begin
      axi4_addr_t ba = t.beat_addr(i);
      for (int b = 0; b < AXI4_DATA_BYTES; b++) if (t.strb[i][b]) begin
        a = axi4_lane_addr(ba, b) & mem.addr_mask;
        if (!last_seq.exists(a) || t.seq_no >= last_seq[a]) begin
          mem.write_byte(a, t.data[i][8*b +: 8]);
          last_seq[a] = t.seq_no;
        end
        unknown.delete(a);
        n_wr_bytes++;
      end
    end
  endfunction

  protected function void done_read(axi4_seq_item t);
    live_txn         l;
    longint unsigned a;
    bit [7:0]        exp, act;
    foreach (rd_live[i]) if (rd_live[i].t == t) begin l = rd_live[i]; rd_live.delete(i); break; end
    n_rd_txn++;
    if (l == null) begin
      `uvm_error("AXI_SB", $sformatf("read completed without a matching address phase: %s", t.convert2string()))
      return;
    end
    foreach (t.rdata[i]) begin
      axi4_addr_t ba   = t.beat_addr(i);
      axi4_strb_t mask = axi4_lane_mask(t.addr, i, t.len, t.size, t.burst);
      if (t.rresp[i] != AXI4_RESP_OKAY) begin
        n_err_resp++;
        if (expect_okay) `uvm_error("AXI_SB", $sformatf("unexpected read response %s on beat %0d: %s", t.rresp[i].name(), i, t.convert2string()))
        continue;
      end
      for (int b = 0; b < AXI4_DATA_BYTES; b++) if (mask[b]) begin
        a = axi4_lane_addr(ba, b) & mem.addr_mask;
        if (l.taint.exists(a) || unknown.exists(a)) begin n_rd_skipped++; continue; end
        exp = mem.read_byte(a);
        act = t.rdata[i][8*b +: 8];
        n_rd_checked++;
        if (exp !== act) begin
          n_mismatch++;
          if (n_mismatch <= max_err_print)
            `uvm_error("AXI_SB", $sformatf("read data mismatch at byte %h: expected %h, got %h (beat %0d lane %0d of %s)",
                                          a, exp, act, i, b, t.convert2string()))
        end
      end
    end
    `uvm_info("AXI_SB", $sformatf("read checked: id=%0h addr=%h beats=%0d (total bytes checked=%0d skipped=%0d mismatches=%0d)",
              t.id, t.addr, t.len + 1, n_rd_checked, n_rd_skipped, n_mismatch), UVM_HIGH)
  endfunction

  function int unsigned num_checks();
    return n_rd_checked;
  endfunction

  function string summary();
    return $sformatf("writes=%0d (%0d bytes applied) reads=%0d bytes_checked=%0d bytes_skipped_concurrent=%0d mismatches=%0d error_responses=%0d",
                     n_wr_txn, n_wr_bytes, n_rd_txn, n_rd_checked, n_rd_skipped, n_mismatch, n_err_resp);
  endfunction

  function void report_phase(uvm_phase phase);
    if (n_mismatch > max_err_print)
      `uvm_error("AXI_SB", $sformatf("%0d further data mismatches were not printed", n_mismatch - max_err_print))
    `uvm_info("AXI_SB", {"memory scoreboard: ", summary()}, UVM_LOW)
  endfunction
endclass
