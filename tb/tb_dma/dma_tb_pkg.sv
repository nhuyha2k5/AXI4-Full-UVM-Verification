// Shared verification environment of the three DMA engines:
//   axi_dma_rd  : memory -> AXI4-Stream
//   axi_dma_wr  : AXI4-Stream -> memory
//   axi_cdma    : memory -> memory
// The AXI4 master port of the engine is served by the AXI4 VIP in slave role
// (memory model, backpressure, error injection); the stream port by axis_pkg.
`include "axi4_defines.svh"
package dma_tb_pkg;
  timeunit 1ns;
  timeprecision 1ps;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import axi4_pkg::*;
  import axis_pkg::*;
  import dv_common_pkg::*;

  typedef enum int { DMA_RD, DMA_WR, DMA_CDMA } dma_kind_e;
  typedef bit [AXI4_ADDR_WIDTH-1:0] dma_addr_t;

  // DMA status error codes (from the RTL localparams).
  localparam bit [3:0] DMA_ERR_NONE = 0, DMA_ERR_RD_SLVERR = 4, DMA_ERR_RD_DECERR = 5, DMA_ERR_WR_SLVERR = 6, DMA_ERR_WR_DECERR = 7;

  // ---------------------------------------------------------------------------
  // Descriptor / status transaction and its agent.
  // ---------------------------------------------------------------------------
  class dma_desc_item extends uvm_sequence_item;
    `uvm_object_utils(dma_desc_item)
    // request
    dma_addr_t   read_addr, write_addr;
    bit [19:0]   len;
    bit [7:0]    tag, id, dest;
    bit          user;
    int unsigned gap;          // idle cycles before the descriptor is offered
    int unsigned frame_len;    // axi_dma_wr: length of the stream frame that goes with it
    bit          skip;         // set by a stopped sequence: the driver discards the item
    // status
    bit          is_status;
    bit [19:0]   st_len;
    bit [7:0]    st_tag, st_id, st_dest;
    bit          st_user;
    bit [3:0]    st_error;
    bit          done;
    function new(string name = "dma_desc_item");
      super.new(name);
    endfunction
    virtual function string convert2string();
      if (is_status) return $sformatf("status tag=%0h error=%0d len=%0d id=%0h dest=%0h user=%0b", st_tag, st_error, st_len, st_id, st_dest, st_user);
      return $sformatf("descriptor rd_addr=%h wr_addr=%h len=%0d tag=%0h id=%0h dest=%0h user=%0b", read_addr, write_addr, len, tag, id, dest, user);
    endfunction
  endclass

  class dma_desc_driver extends uvm_driver #(dma_desc_item);
    `uvm_component_utils(dma_desc_driver)
    virtual dma_if vif;
    function new(string n, uvm_component p);
      super.new(n, p);
    endfunction
    protected time t_cb;   // time of the last clocking event this thread woke on
    protected task tick();
      @(vif.cb);
      t_cb = $time;
    endtask
    task run_phase(uvm_phase phase);
      dma_desc_item t;
      vif.valid <= 1'b0; vif.read_addr <= '0; vif.write_addr <= '0; vif.len <= '0; vif.tag <= '0;
      vif.id <= '0; vif.dest <= '0; vif.user <= 1'b0;
      forever begin
        seq_item_port.get_next_item(t);
        `uvm_info("DMA_DRV", $sformatf("driving %s (gap %0d)", t.convert2string(), t.gap), UVM_HIGH)
        // An item can arrive at any point of a time step.  Signals are only
        // driven after a clocking event, otherwise the DUT and this driver
        // could disagree about the cycle in which VALID rose.
        if ($time != t_cb) tick();
        if (t.skip) begin t.done = 1; seq_item_port.item_done(); continue; end
        while (vif.cb.rst_n !== 1'b1) tick();
        begin
          bit reset_seen = 0;
          repeat (t.gap) begin tick(); if (vif.cb.rst_n !== 1'b1) reset_seen = 1; end
          // A descriptor that was waiting when a reset came is not issued.
          if (reset_seen) begin t.done = 1; seq_item_port.item_done(); continue; end
        end
        vif.read_addr <= t.read_addr; vif.write_addr <= t.write_addr; vif.len <= t.len; vif.tag <= t.tag;
        vif.id <= t.id; vif.dest <= t.dest; vif.user <= t.user;
        vif.valid <= 1'b1;
        // The request is withdrawn if a reset arrives before it is accepted.
        do tick(); while (vif.cb.ready !== 1'b1 && vif.cb.rst_n === 1'b1);
        vif.valid <= 1'b0;
        t.done = 1;
        seq_item_port.item_done();
      end
    endtask
  endclass

  class dma_desc_monitor extends uvm_monitor;
    `uvm_component_utils(dma_desc_monitor)
    virtual dma_if vif;
    uvm_analysis_port #(dma_desc_item) req_ap;
    uvm_analysis_port #(dma_desc_item) status_ap;
    int unsigned n_req, n_status;
    function new(string n, uvm_component p);
      super.new(n, p);
      req_ap = new("req_ap", this);
      status_ap = new("status_ap", this);
    endfunction
    task run_phase(uvm_phase phase);
      dma_desc_item t;
      forever begin
        @(vif.cb);
        if (vif.cb.rst_n !== 1'b1) continue;
        if (vif.cb.valid === 1'b1 && vif.cb.ready === 1'b1) begin
          t = dma_desc_item::type_id::create("req");
          t.read_addr = vif.cb.read_addr; t.write_addr = vif.cb.write_addr; t.len = vif.cb.len; t.tag = vif.cb.tag;
          t.id = vif.cb.id; t.dest = vif.cb.dest; t.user = vif.cb.user;
          n_req++;
          `uvm_info("DMA_DESC", $sformatf("#%0d accepted: %s", n_req, t.convert2string()), UVM_MEDIUM)
          req_ap.write(t);
        end
        if (vif.cb.st_valid === 1'b1) begin
          t = dma_desc_item::type_id::create("status");
          t.is_status = 1; t.st_len = vif.cb.st_len; t.st_tag = vif.cb.st_tag; t.st_id = vif.cb.st_id;
          t.st_dest = vif.cb.st_dest; t.st_user = vif.cb.st_user; t.st_error = vif.cb.st_error;
          n_status++;
          status_ap.write(t);
        end
      end
    endtask
  endclass

  // ---------------------------------------------------------------------------
  // Testbench configuration.
  // ---------------------------------------------------------------------------
  class dma_tb_cfg extends uvm_object;
    `uvm_object_utils(dma_tb_cfg)
    dma_kind_e       kind;
    virtual dma_if   dma_vif;
    int unsigned     max_burst_len    = 16;   // DUT parameter AXI_MAX_BURST_LEN
    bit              enable_unaligned = 1;    // DUT parameter ENABLE_UNALIGNED
    axi4_agent_cfg   axi_cfg;
    axis_cfg         stream_cfg;
    function new(string name = "dma_tb_cfg");
      super.new(name);
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Functional coverage of a completed descriptor.
  // ---------------------------------------------------------------------------
  covergroup dma_cg_shape (string nm, int burst_bytes) with function sample(int unsigned len, bit cross_4k, int unsigned bursts);
    option.per_instance = 1;
    option.name = nm;
    cp_len: coverpoint len {
      bins one            = {1};
      bins below_word     = {[2:3]};
      bins one_word       = {4};
      bins below_burst    = {[5:burst_bytes-1]};
      bins one_burst      = {burst_bytes};
      bins above_burst    = {[burst_bytes+1:4095]};
      bins page_or_more   = {[4096:65535]};
      bins very_long      = {[65536:$]};
    }
    cp_bursts:   coverpoint bursts { bins one = {1}; bins two = {2}; bins several = {[3:$]}; }
    cp_cross_4k: coverpoint cross_4k;
  endgroup

  // Byte offsets of the first and last byte; only for engines built with ENABLE_UNALIGNED.
  covergroup dma_cg_align (string nm) with function sample(bit [1:0] start_off, bit [1:0] end_off, bit short_len);
    option.per_instance = 1;
    option.name = nm;
    cp_start: coverpoint start_off;
    cp_end:   coverpoint end_off;
    cp_short: coverpoint short_len { bins up_to_a_word = {1}; bins longer = {0}; }
    start_x_end:   cross cp_start, cp_end;
    start_x_short: cross cp_start, cp_short;
  endgroup

  // Status error codes; one group per AXI direction the engine has.
  covergroup dma_cg_rd_error (string nm) with function sample(bit [3:0] err);
    option.per_instance = 1;
    option.name = nm;
    cp_err: coverpoint err { bins none = {0}; bins slverr = {4}; bins decerr = {5}; }
  endgroup

  covergroup dma_cg_wr_error (string nm) with function sample(bit [3:0] err);
    option.per_instance = 1;
    option.name = nm;
    cp_err: coverpoint err { bins none = {0}; bins slverr = {6}; bins decerr = {7}; }
  endgroup

  // axi_dma_wr: stream frame length relative to the descriptor length.
  covergroup dma_cg_frame (string nm) with function sample(int rel, bit last_beat_partial);
    option.per_instance = 1;
    option.name = nm;
    cp_rel:     coverpoint rel { bins shorter = {-1}; bins exact = {0}; bins longer = {1}; }
    cp_partial: coverpoint last_beat_partial;
  endgroup

  class dma_coverage extends uvm_component;
    `uvm_component_utils(dma_coverage)
    dma_tb_cfg      cfg;
    dma_cg_shape    cg_shape;
    dma_cg_align    cg_align;
    dma_cg_rd_error cg_rd_error;
    dma_cg_wr_error cg_wr_error;
    dma_cg_frame    cg_frame;

    function new(string n, uvm_component p);
      super.new(n, p);
    endfunction

    // Only the groups that apply to this engine and build are created.
    function void build_phase(uvm_phase phase);
      cg_shape = new("dma_shape", cfg.max_burst_len * AXI4_DATA_BYTES);
      if (cfg.enable_unaligned) cg_align    = new("dma_align");
      if (cfg.kind != DMA_WR)   cg_rd_error = new("dma_rd_error");
      if (cfg.kind != DMA_RD)   cg_wr_error = new("dma_wr_error");
      if (cfg.kind == DMA_WR)   cg_frame    = new("dma_frame");
    endfunction

    function void sample_error(bit [3:0] err);
      if (cg_rd_error != null && err inside {0, 4, 5}) cg_rd_error.sample(err);
      if (cg_wr_error != null && err inside {0, 6, 7}) cg_wr_error.sample(err);
    endfunction

    function real get_coverage();
      real s = cg_shape.get_inst_coverage(); int n = 1;
      if (cg_align    != null) begin s += cg_align.get_inst_coverage();    n++; end
      if (cg_rd_error != null) begin s += cg_rd_error.get_inst_coverage(); n++; end
      if (cg_wr_error != null) begin s += cg_wr_error.get_inst_coverage(); n++; end
      if (cg_frame    != null) begin s += cg_frame.get_inst_coverage();    n++; end
      return s / n;
    endfunction
  endclass
  // ---------------------------------------------------------------------------
  // Scoreboard.
  // ---------------------------------------------------------------------------
  `uvm_analysis_imp_decl(_dma_req)
  `uvm_analysis_imp_decl(_dma_status)
  `uvm_analysis_imp_decl(_dma_frame)
  `uvm_analysis_imp_decl(_dma_axi)

  // Everything known about one descriptor.
  class dma_ctx;
    dma_desc_item    d, st;
    axis_item        frame;
    bit [7:0]        rbytes[longint unsigned];   // bytes the engine read on AXI
    bit [7:0]        wbytes[longint unsigned];   // bytes the engine wrote on AXI
    axi4_resp_e      rd_err = AXI4_RESP_OKAY;    // most recent read error response
    axi4_resp_e      wr_err = AXI4_RESP_OKAY;    // most recent write error response
    int unsigned     n_ar, n_aw;
    bit              cross_4k;
  endclass

  class dma_scoreboard extends uvm_component;
    `uvm_component_utils(dma_scoreboard)
    uvm_analysis_imp_dma_req    #(dma_desc_item, dma_scoreboard) req_export;
    uvm_analysis_imp_dma_status #(dma_desc_item, dma_scoreboard) status_export;
    uvm_analysis_imp_dma_frame  #(axis_item,     dma_scoreboard) frame_export;
    uvm_analysis_imp_dma_axi    #(axi4_seq_item, dma_scoreboard) axi_export;

    dma_tb_cfg   cfg;
    dma_coverage cov;
    protected dma_ctx   pending[$];
    protected axis_item spare_frames[$];   // axi_dma_wr: frames seen before their descriptor
    protected dma_ctx          rd_ctx, wr_ctx;   // descriptors whose read / write bursts are arriving
    protected longint unsigned rd_end, wr_end;   // word-aligned end of their last burst
    protected longint unsigned rd_addr;          // start address of the last read burst

    int unsigned n_desc_done, n_bytes_checked, n_err_status, n_mismatch, n_flushed;

    function new(string n, uvm_component p);
      super.new(n, p);
      req_export = new("req_export", this);
      status_export = new("status_export", this);
      frame_export = new("frame_export", this);
      axi_export = new("axi_export", this);
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(cfg.dma_vif.cb);
        if (cfg.dma_vif.cb.rst_n !== 1'b1 && (pending.size() + spare_frames.size() > 0)) begin
          n_flushed += pending.size();
          `uvm_info("DMA_SB", $sformatf("reset: %0d descriptor(s) in flight dropped", pending.size()), UVM_MEDIUM)
          pending.delete(); spare_frames.delete(); rd_ctx = null; wr_ctx = null;
        end
      end
    endtask

    protected function void err(string msg);
      n_mismatch++;
      if (n_mismatch <= 30) `uvm_error("DMA_SB", msg)
    endfunction

    function void write_dma_req(dma_desc_item t);
      dma_ctx c = new();
      c.d = t;
      if (cfg.kind == DMA_WR && spare_frames.size() > 0) c.frame = spare_frames.pop_front();
      pending.push_back(c);
    endfunction

    function void write_dma_status(dma_desc_item t);
      foreach (pending[i]) if (pending[i].st == null) begin
        pending[i].st = t;
        `uvm_info("DMA_DESC", $sformatf("%s  (for %s)", t.convert2string(), pending[i].d.convert2string()), UVM_MEDIUM)
        finish_ready();
        return;
      end
      err({"status without a pending descriptor: ", t.convert2string()});
    endfunction

    function void write_dma_frame(axis_item f);
      if (cfg.kind == DMA_CDMA) return;
      foreach (pending[i]) if (pending[i].frame == null) begin
        pending[i].frame = f;
        finish_ready();
        return;
      end
      if (cfg.kind == DMA_WR) spare_frames.push_back(f);
      else err({"stream frame without a pending descriptor: ", f.convert2string()});
    endfunction

    // Start and (exclusive) end of the bytes a descriptor moves on one side.
    // axi_dma_wr stops early when the input frame is shorter than the descriptor.
    protected function longint unsigned range_start(dma_ctx c, bit is_wr);
      return is_wr ? c.d.write_addr : c.d.read_addr;
    endfunction
    protected function longint unsigned range_end(dma_ctx c, bit is_wr);
      int unsigned n = c.d.len;
      if (is_wr && cfg.kind == DMA_WR && c.frame != null && c.frame.bytes.size() < n) n = c.frame.bytes.size();
      return range_start(c, is_wr) + n;
    endfunction

    // Finds the descriptor an AXI burst belongs to.
    //
    // The engines accept the next descriptor, and may start on it, before the
    // status of the current one is out, so bursts cannot be matched by status.
    // They are followed as a chain instead: the first burst of a descriptor
    // starts in the word of its address, every later burst starts where the
    // previous one ended, and the next descriptor begins once the range of the
    // current one is covered.
    //
    // axi_cdma is different on the read side: every chunk (its size is set by
    // the destination address) reads from the exact byte where the previous
    // chunk stopped, so a source word can be read twice - even after the whole
    // range has been covered.  Its read chain therefore continues with any burst
    // that starts behind the previous one inside the last word that was read.
    // If the next descriptor starts at exactly that byte the burst is taken as
    // the start of the next descriptor.
    protected function dma_ctx attribute(axi4_seq_item t, bit is_wr);
      dma_ctx          c    = is_wr ? wr_ctx : rd_ctx;
      longint unsigned cend = is_wr ? wr_end : rd_end;
      dma_ctx          nxt;
      bit              cont;
      foreach (pending[i]) if ((is_wr ? pending[i].n_aw : pending[i].n_ar) == 0) begin nxt = pending[i]; break; end
      if (c == null || c.st != null) begin
        cont = 0;
      end else if (!is_wr && cfg.kind == DMA_CDMA) begin
        cont = (t.addr > rd_addr && t.addr + AXI4_DATA_BYTES > cend && t.addr <= cend && t.addr < range_end(c, 0));
        if (cont && cend >= range_end(c, 0) && nxt != null && t.addr == nxt.d.read_addr) cont = 0;
      end else begin
        cont = (cend < range_end(c, is_wr) && t.addr / AXI4_DATA_BYTES == cend / AXI4_DATA_BYTES);
      end
      if (!cont) begin
        c = nxt;
        if (c != null && t.addr / AXI4_DATA_BYTES != range_start(c, is_wr) / AXI4_DATA_BYTES) c = null;
      end
      if (c != null) begin
        cend = (t.addr / AXI4_DATA_BYTES) * AXI4_DATA_BYTES + (t.len + 1) * AXI4_DATA_BYTES;
        if (is_wr) begin wr_ctx = c; wr_end = cend; end
        else       begin rd_ctx = c; rd_end = cend; rd_addr = t.addr; end
      end
      return c;
    endfunction
    function void write_dma_axi(axi4_seq_item t);
      longint unsigned lo, hi, a;
      dma_ctx          c;
      bit              is_wr = (t.cmd == AXI4_WRITE);
      if (t.burst != AXI4_BURST_INCR || t.size != AXI4_MAX_SIZE)
        err({"engine issued a burst that is not full-width INCR: ", t.convert2string()});
      if (t.len + 1 > cfg.max_burst_len)
        err($sformatf("burst of %0d beats exceeds AXI_MAX_BURST_LEN=%0d: %s", t.len + 1, cfg.max_burst_len, t.convert2string()));
      if (t.id != 0) err({"engine used a non-zero AXI ID: ", t.convert2string()});

      c = attribute(t, is_wr);
      if (c == null) begin
        err({"AXI burst neither continues the current descriptor nor starts the next one: ", t.convert2string()});
        return;
      end
      lo = (range_start(c, is_wr) / AXI4_DATA_BYTES) * AXI4_DATA_BYTES;
      hi = range_start(c, is_wr) + c.d.len;   // exclusive
      if (t.addr < lo || t.addr >= hi)
        err($sformatf("AXI burst outside the range of its descriptor (%s): %s", c.d.convert2string(), t.convert2string()));
      if (is_wr) begin
        c.n_aw++;
        if (t.bresp inside {AXI4_RESP_SLVERR, AXI4_RESP_DECERR}) c.wr_err = t.bresp;
        foreach (t.data[i]) for (int b = 0; b < AXI4_DATA_BYTES; b++) if (t.strb[i][b]) begin
          a = axi4_lane_addr(t.beat_addr(i), b);
          if (c.wbytes.exists(a)) err($sformatf("byte %h written twice for one descriptor", a));
          c.wbytes[a] = t.data[i][8*b +: 8];
        end
      end else begin
        c.n_ar++;
        foreach (t.rdata[i]) begin
          axi4_strb_t mask = axi4_lane_mask(t.addr, i, t.len, t.size, t.burst);
          if (t.rresp[i] inside {AXI4_RESP_SLVERR, AXI4_RESP_DECERR}) c.rd_err = t.rresp[i];
          for (int b = 0; b < AXI4_DATA_BYTES; b++) if (mask[b]) c.rbytes[axi4_lane_addr(t.beat_addr(i), b)] = t.rdata[i][8*b +: 8];
        end
      end
      if ((t.addr >> 12) != ((hi - 1) >> 12) || (t.addr >> 12) != (lo >> 12)) c.cross_4k = 1;
    endfunction
    // Checks descriptors in order as soon as everything about them is known.
    protected function void finish_ready();
      while (pending.size() > 0 && pending[0].st != null && (cfg.kind == DMA_CDMA || pending[0].frame != null)) begin
        check_ctx(pending[0]);
        void'(pending.pop_front());
      end
    endfunction

    protected function bit [3:0] expected_error(dma_ctx c);
      if (c.rd_err == AXI4_RESP_SLVERR) return DMA_ERR_RD_SLVERR;
      if (c.rd_err == AXI4_RESP_DECERR) return DMA_ERR_RD_DECERR;
      if (c.wr_err == AXI4_RESP_SLVERR) return DMA_ERR_WR_SLVERR;
      if (c.wr_err == AXI4_RESP_DECERR) return DMA_ERR_WR_DECERR;
      return DMA_ERR_NONE;
    endfunction

    protected function void check_ctx(dma_ctx c);
      string           what  = c.d.convert2string();
      bit [3:0]        exp_e = expected_error(c);
      longint unsigned ra = c.d.read_addr, wa = c.d.write_addr;
      int unsigned     n = c.d.len;
      int              rel = 0;
      dma_addr_t       start_addr = (cfg.kind == DMA_WR) ? c.d.write_addr : c.d.read_addr;

      if (c.st.st_tag != c.d.tag) err($sformatf("status tag %0h, expected %0h: %s", c.st.st_tag, c.d.tag, what));
      if (c.st.st_error != exp_e) err($sformatf("status error %0d, expected %0d (from the AXI responses seen): %s", c.st.st_error, exp_e, what));
      if (exp_e != DMA_ERR_NONE) n_err_status++;

      case (cfg.kind)
        DMA_RD: begin
          if (c.frame.keep_error) err({"output stream TKEEP is not contiguous/full: ", what});
          if (c.frame.bytes.size() != n) err($sformatf("output frame has %0d bytes, expected %0d: %s", c.frame.bytes.size(), n, what));
          if (c.frame.tid != c.d.id || c.frame.tdest != c.d.dest || c.frame.tuser != c.d.user)
            err($sformatf("output frame tid/tdest/tuser = %0h/%0h/%0b, expected %0h/%0h/%0b: %s", c.frame.tid, c.frame.tdest, c.frame.tuser, c.d.id, c.d.dest, c.d.user, what));
          for (int unsigned i = 0; i < n && i < c.frame.bytes.size(); i++) begin
            if (!c.rbytes.exists(ra + i)) begin err($sformatf("byte %h was never read on AXI: %s", ra + i, what)); break; end
            if (c.frame.bytes[i] !== c.rbytes[ra + i]) begin
              err($sformatf("stream byte %0d = %h, AXI read data at %h = %h: %s", i, c.frame.bytes[i], ra + i, c.rbytes[ra + i], what));
              break;
            end
            n_bytes_checked++;
          end
        end
        DMA_WR: begin
          int unsigned exp_n = (c.frame.bytes.size() < n) ? c.frame.bytes.size() : n;
          rel = (c.frame.bytes.size() < n) ? -1 : (c.frame.bytes.size() > n) ? 1 : 0;
          if (c.st.st_len != exp_n) err($sformatf("status len %0d, expected %0d (descriptor %0d, frame %0d bytes): %s", c.st.st_len, exp_n, n, c.frame.bytes.size(), what));
          if (c.st.st_id != c.frame.tid || c.st.st_dest != c.frame.tdest || c.st.st_user != c.frame.tuser)
            err($sformatf("status id/dest/user = %0h/%0h/%0b, frame had %0h/%0h/%0b: %s", c.st.st_id, c.st.st_dest, c.st.st_user, c.frame.tid, c.frame.tdest, c.frame.tuser, what));
          if (c.wbytes.num() != exp_n) err($sformatf("%0d bytes written on AXI, expected %0d: %s", c.wbytes.num(), exp_n, what));
          for (int unsigned i = 0; i < exp_n; i++) begin
            if (!c.wbytes.exists(wa + i)) begin err($sformatf("byte %h was never written on AXI: %s", wa + i, what)); break; end
            if (c.wbytes[wa + i] !== c.frame.bytes[i]) begin
              err($sformatf("AXI write data at %h = %h, stream byte %0d = %h: %s", wa + i, c.wbytes[wa + i], i, c.frame.bytes[i], what));
              break;
            end
            n_bytes_checked++;
          end
          n = exp_n;
          if (cov.cg_frame != null) cov.cg_frame.sample(rel, (c.frame.bytes.size() % AXI4_DATA_BYTES) != 0);
        end
        DMA_CDMA: begin
          if (exp_e == DMA_ERR_NONE) begin
            if (c.wbytes.num() != n) err($sformatf("%0d bytes written on AXI, expected %0d: %s", c.wbytes.num(), n, what));
            for (int unsigned i = 0; i < n; i++) begin
              if (!c.rbytes.exists(ra + i)) begin err($sformatf("source byte %h was never read: %s", ra + i, what)); break; end
              if (!c.wbytes.exists(wa + i)) begin err($sformatf("destination byte %h was never written: %s", wa + i, what)); break; end
              if (c.wbytes[wa + i] !== c.rbytes[ra + i]) begin
                err($sformatf("destination %h = %h, source %h = %h: %s", wa + i, c.wbytes[wa + i], ra + i, c.rbytes[ra + i], what));
                break;
              end
              n_bytes_checked++;
            end
          end
        end
      endcase

      n_desc_done++;
      cov.cg_shape.sample(c.d.len, c.cross_4k, (c.n_ar > c.n_aw) ? c.n_ar : c.n_aw);
      if (cov.cg_align != null) cov.cg_align.sample(start_addr[1:0], (start_addr + c.d.len) % AXI4_DATA_BYTES, c.d.len <= AXI4_DATA_BYTES);
      cov.sample_error(c.st.st_error);
    endfunction

    function int unsigned num_pending();
      return pending.size();
    endfunction

    function int unsigned num_checks();
      return n_bytes_checked + n_err_status;
    endfunction

    function string summary();
      return $sformatf("descriptors_checked=%0d bytes_compared=%0d error_statuses_checked=%0d dropped_by_reset=%0d mismatches=%0d",
                       n_desc_done, n_bytes_checked, n_err_status, n_flushed, n_mismatch);
    endfunction

    function void check_phase(uvm_phase phase);
      if (pending.size() > 0)
        err($sformatf("%0d descriptor(s) never completed, first: %s", pending.size(), pending[0].d.convert2string()));
    endfunction

    function void report_phase(uvm_phase phase);
      if (n_mismatch > 30) `uvm_error("DMA_SB", $sformatf("%0d further mismatches were not printed", n_mismatch - 30))
      `uvm_info("DMA_SB", {"DMA scoreboard: ", summary()}, UVM_LOW)
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Environment.
  // ---------------------------------------------------------------------------
  class dma_env extends uvm_env;
    `uvm_component_utils(dma_env)
    dma_tb_cfg                     cfg;
    uvm_sequencer #(dma_desc_item) desc_sqr;
    dma_desc_driver                desc_drv;
    dma_desc_monitor               desc_mon;
    axi4_agent                     axi;      // VIP slave on the engine's AXI master port
    axis_agent                     stream;   // sink for axi_dma_rd, source for axi_dma_wr
    dma_scoreboard                 sb;
    dma_coverage                   cov;

    function new(string n, uvm_component p);
      super.new(n, p);
    endfunction

    function void build_phase(uvm_phase phase);
      desc_sqr = uvm_sequencer #(dma_desc_item)::type_id::create("desc_sqr", this);
      desc_drv = dma_desc_driver::type_id::create("desc_drv", this);
      desc_mon = dma_desc_monitor::type_id::create("desc_mon", this);
      desc_drv.vif = cfg.dma_vif;
      desc_mon.vif = cfg.dma_vif;
      axi = axi4_agent::type_id::create("axi", this);
      axi.cfg = cfg.axi_cfg;
      if (cfg.kind != DMA_CDMA) begin
        stream = axis_agent::type_id::create("stream", this);
        stream.cfg = cfg.stream_cfg;
      end
      sb  = dma_scoreboard::type_id::create("sb", this);
      cov = dma_coverage::type_id::create("cov", this);
      sb.cfg = cfg; sb.cov = cov; cov.cfg = cfg;
    endfunction

    function void connect_phase(uvm_phase phase);
      desc_drv.seq_item_port.connect(desc_sqr.seq_item_export);
      desc_mon.req_ap.connect(sb.req_export);
      desc_mon.status_ap.connect(sb.status_export);
      axi.ap.connect(sb.axi_export);
      if (stream != null) stream.monitor.ap.connect(sb.frame_export);
    endfunction
  endclass

  // ---------------------------------------------------------------------------
  // Sequences: a list of descriptors (and, for axi_dma_wr, of frames).
  // ---------------------------------------------------------------------------
  class dma_desc_list_seq extends uvm_sequence #(dma_desc_item);
    `uvm_object_utils(dma_desc_list_seq)
    dma_desc_item list[$];
    bit           abort;   // set by the test: remaining items are handed over marked "skip"
    function new(string n = "dma_desc_list_seq");
      super.new(n);
    endfunction
    task body();
      foreach (list[i]) begin
        start_item(list[i]);
        list[i].skip = abort;
        finish_item(list[i]);
      end
    endtask
  endclass

  class dma_frame_list_seq extends uvm_sequence #(axis_item);
    `uvm_object_utils(dma_frame_list_seq)
    dma_desc_item list[$];
    bit           abort;
    function new(string n = "dma_frame_list_seq");
      super.new(n);
    endfunction
    task body();
      foreach (list[i]) begin
        axis_item f = axis_item::type_id::create("f");
        f.randomize_bytes(list[i].frame_len);
        f.tid = $urandom_range(255, 0); f.tdest = $urandom_range(255, 0); f.tuser = $urandom_range(1, 0);
        start_item(f);
        f.skip = abort;
        finish_item(f);
      end
    endtask
  endclass

  // ---------------------------------------------------------------------------
  // Base test.
  // ---------------------------------------------------------------------------
  virtual class dma_base_test extends dv_base_test;
    dma_env               env;
    dma_tb_cfg            cfg;
    virtual dv_clk_rst_if clk_rst;
    virtual axi4_if       axi_vif;
    virtual axis_if       stream_vif;
    // Knobs of the random descriptor generator (see make_desc).
    int unsigned max_len       = 300;   // upper bound of "ordinary" lengths
    int unsigned gap_max       = 0;     // idle cycles between descriptors
    int unsigned short_pct     = 20;    // axi_dma_wr: frames shorter than the descriptor
    int unsigned long_pct      = 20;    // axi_dma_wr: frames longer than the descriptor
    bit          preload       = 1;     // fill the source range with random bytes before the transfer

    function new(string n, uvm_component p);
      super.new(n, p);
      checking = "dma_scoreboard: per descriptor, stream bytes vs AXI bytes in order, byte count, tag/id/dest/user, status length and error code; burst legality; axi4_monitor protocol checks; axi4_if and axis_if SVA";
    endfunction

    virtual function void configure();
    endfunction

    function void build_phase(uvm_phase phase);
      int k, mbl, una;
      super.build_phase(phase);
      cfg = dma_tb_cfg::type_id::create("cfg");
      if (!uvm_config_db#(int)::get(this, "", "dma_kind", k)) `uvm_fatal("CFG", "dma_kind missing")
      void'(uvm_config_db#(int)::get(this, "", "max_burst_len", mbl));
      void'(uvm_config_db#(int)::get(this, "", "enable_unaligned", una));
      cfg.kind = dma_kind_e'(k); cfg.max_burst_len = mbl; cfg.enable_unaligned = una;
      if (!uvm_config_db#(virtual dma_if)::get(this, "", "dma_vif", cfg.dma_vif)) `uvm_fatal("CFG", "dma_vif missing")
      if (!uvm_config_db#(virtual axi4_if)::get(this, "", "axi_vif", axi_vif)) `uvm_fatal("CFG", "axi_vif missing")
      if (!uvm_config_db#(virtual dv_clk_rst_if)::get(this, "", "clk_rst_vif", clk_rst)) `uvm_fatal("CFG", "clk_rst_vif missing")
      dut_name = $sformatf("%s (AXI_DATA_WIDTH=%0d AXI_ADDR_WIDTH=%0d AXI_MAX_BURST_LEN=%0d ENABLE_UNALIGNED=%0d LEN_WIDTH=20 TAG_WIDTH=8)",
                           (cfg.kind == DMA_RD) ? "axi_dma_rd" : (cfg.kind == DMA_WR) ? "axi_dma_wr" : "axi_cdma",
                           AXI4_DATA_WIDTH, AXI4_ADDR_WIDTH, cfg.max_burst_len, cfg.enable_unaligned);

      cfg.axi_cfg = axi4_agent_cfg::type_id::create("axi_cfg");
      cfg.axi_cfg.name = "mem"; cfg.axi_cfg.role = AXI4_SLAVE_AGENT; cfg.axi_cfg.vif = axi_vif;
      cfg.axi_cfg.mem = axi4_mem_model::type_id::create("mem");
      cfg.axi_cfg.mem.default_mode = AXI4_MEM_ADDR_HASH;
      // Coverage scope of the engine's AXI port: full-width INCR bursts of at
      // most AXI_MAX_BURST_LEN beats, a single ID, no sideband use.
      cfg.axi_cfg.cov_wr = (cfg.kind != DMA_RD); cfg.axi_cfg.cov_rd = (cfg.kind != DMA_WR);
      cfg.axi_cfg.cov_long_bursts = 0; cfg.axi_cfg.cov_fixed = 0; cfg.axi_cfg.cov_wrap = 0; cfg.axi_cfg.cov_narrow = 0;
      cfg.axi_cfg.cov_unaligned = 0; cfg.axi_cfg.cov_multi_id = 0; cfg.axi_cfg.cov_outstanding = 0;
      cfg.axi_cfg.cov_err_resp = 1; cfg.axi_cfg.cov_sparse_strb = 0;

      if (cfg.kind != DMA_CDMA) begin
        if (!uvm_config_db#(virtual axis_if)::get(this, "", "stream_vif", stream_vif)) `uvm_fatal("CFG", "stream_vif missing")
        cfg.stream_cfg = axis_cfg::type_id::create("stream_cfg");
        cfg.stream_cfg.name = (cfg.kind == DMA_RD) ? "stream_out" : "stream_in";
        cfg.stream_cfg.role = (cfg.kind == DMA_RD) ? AXIS_SINK : AXIS_SOURCE;
        cfg.stream_cfg.vif  = stream_vif;
      end
      configure();
      cfg_lines.push_back(cfg.axi_cfg.convert2string());
      if (cfg.stream_cfg != null)
        cfg_lines.push_back($sformatf("%s valid_pct=%0d ready_pct=%0d", cfg.stream_cfg.name, cfg.stream_cfg.valid_pct, cfg.stream_cfg.ready_pct));
      env = dma_env::type_id::create("env", this);
      env.cfg = cfg;
    endfunction

    virtual function int unsigned num_checks();
      return env.sb.num_checks();
    endfunction

    virtual function void result_lines(ref string q[$]);
      q.push_back({"scoreboard       : ", env.sb.summary()});
      q.push_back($sformatf("descriptors      : accepted=%0d statuses=%0d", env.desc_mon.n_req, env.desc_mon.n_status));
      q.push_back($sformatf("AXI traffic      : write_bursts=%0d (%0d beats) read_bursts=%0d (%0d beats) error_responses=%0d",
                            env.axi.monitor.n_wr, env.axi.monitor.n_wr_beats, env.axi.monitor.n_rd, env.axi.monitor.n_rd_beats, env.axi.monitor.n_err_resp));
      if (env.stream != null)
        q.push_back($sformatf("stream traffic   : frames=%0d beats=%0d bytes=%0d", env.stream.monitor.n_frames, env.stream.monitor.n_beats, env.stream.monitor.n_bytes));
      q.push_back($sformatf("functional cov   : %0.1f%% of the DMA covergroups in this test alone", env.cov.get_coverage()));
    endfunction

    // Random backpressure on the AXI port and the stream port.
    function void random_backpressure();
      cfg.axi_cfg.set_backpressure(dv_plusarg_int("BP_PCT", $urandom_range(100, 25)), $urandom_range(5, 0));
      if (cfg.stream_cfg != null) begin
        cfg.stream_cfg.valid_pct = dv_plusarg_int("BP_PCT", $urandom_range(100, 25));
        cfg.stream_cfg.ready_pct = dv_plusarg_int("BP_PCT", $urandom_range(100, 25));
      end
    endfunction

    // Lengths: mostly up to max_len, with the values around a word, a burst
    // and a 4 KB page picked often.
    function int unsigned pick_len();
      int unsigned bb = cfg.max_burst_len * AXI4_DATA_BYTES;
      randcase
        20: return $urandom_range(AXI4_DATA_BYTES + 1, 1);
        15: return bb + $urandom_range(2, 0) - 1;
        10: return 2 * bb + $urandom_range(2, 0) - 1;
        5:  return 4096 + $urandom_range(2, 0) - 1;
        50: return $urandom_range(max_len, 1);
      endcase
    endfunction

    // One random descriptor.  Addresses are word aligned unless the engine
    // supports unaligned transfers; one in four starts close to a 4 KB boundary.
    virtual function dma_desc_item make_desc(int unsigned len = 0);
      dma_desc_item    d = dma_desc_item::type_id::create("d");
      longint unsigned ra, wa, span;
      d.len = (len == 0) ? pick_len() : len;
      span  = d.len + 2 * AXI4_DATA_BYTES;
      ra = {$urandom(), $urandom()} % ((64'd1 << AXI4_ADDR_WIDTH) - span);
      if ($urandom_range(3, 0) == 0) ra = ((ra >> 12) << 12) + 4096 - $urandom_range(2 * AXI4_DATA_BYTES + 2, 1);
      // The destination is kept clear of the source by more than the length.
      do wa = {$urandom(), $urandom()} % ((64'd1 << AXI4_ADDR_WIDTH) - span);
      while ((wa > ra ? wa - ra : ra - wa) < span);
      if ($urandom_range(3, 0) == 0) wa = ((wa >> 12) << 12) + 4096 - $urandom_range(2 * AXI4_DATA_BYTES + 2, 1);
      if (!cfg.enable_unaligned) begin
        ra = (ra / AXI4_DATA_BYTES) * AXI4_DATA_BYTES;
        wa = (wa / AXI4_DATA_BYTES) * AXI4_DATA_BYTES;
      end
      d.read_addr = ra; d.write_addr = wa;
      d.tag = $urandom_range(255, 0); d.id = $urandom_range(255, 0); d.dest = $urandom_range(255, 0); d.user = $urandom_range(1, 0);
      d.gap = $urandom_range(gap_max, 0);
      // axi_dma_wr: frame shorter than, equal to or longer than the descriptor.
      d.frame_len = d.len;
      if (cfg.kind == DMA_WR) begin
        int r = $urandom_range(99, 0);
        if (r < short_pct && d.len > 1) d.frame_len = $urandom_range(d.len - 1, 1);
        else if (r < short_pct + long_pct) d.frame_len = d.len + $urandom_range(3 * AXI4_DATA_BYTES, 1);
      end
      if (preload && cfg.kind != DMA_WR) cfg.axi_cfg.mem.randomize_range((ra / AXI4_DATA_BYTES) * AXI4_DATA_BYTES, d.len + 2 * AXI4_DATA_BYTES);
      return d;
    endfunction

    // Issues the descriptors (and frames) and waits until each has been checked.
    dma_desc_list_seq  cur_ds;   // sequences of the most recent run_list()
    dma_frame_list_seq cur_fs;

    // Stops the current descriptor/frame lists.  To be followed by a reset,
    // which ends whatever item the drivers are busy with.
    task stop_lists();
      cur_ds.abort = 1; cur_fs.abort = 1;
    endtask
    task wait_lists_stopped();
      cur_ds.wait_for_sequence_state(UVM_FINISHED);
      if (cfg.kind == DMA_WR) cur_fs.wait_for_sequence_state(UVM_FINISHED);
    endtask

    task run_list(dma_desc_item list[$], bit wait_done = 1);
      dma_desc_list_seq  ds = dma_desc_list_seq::type_id::create("ds");
      dma_frame_list_seq fs = dma_frame_list_seq::type_id::create("fs");
      int unsigned       target = env.sb.n_desc_done + list.size();
      cur_ds = ds; cur_fs = fs;
      ds.list = list; fs.list = list;
      `uvm_info("DMA_TEST", $sformatf("issuing %0d descriptor(s); %0d checked so far", list.size(), env.sb.n_desc_done), UVM_MEDIUM)
      fork
        ds.start(env.desc_sqr);
        if (cfg.kind == DMA_WR) fs.start(env.stream.sequencer);
      join_none
      if (wait_done) wait_checked(target);
    endtask

    task wait_checked(int unsigned target);
      while (env.sb.n_desc_done < target) clk_rst.wait_clocks(4);
    endtask

    task run_random(int unsigned n);
      dma_desc_item list[$];
      repeat (dv_plusarg_int("NUM_DESC", n)) list.push_back(make_desc());
      run_list(list);
    endtask

    pure virtual task main();

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      clk_rst.wait_reset_done();
      main();
      clk_rst.wait_clocks(30);
      phase.drop_objection(this);
    endtask
  endclass

  // ---------------------------------------------------------------------------
  // Tests.  Each one runs on all three engines.
  // ---------------------------------------------------------------------------
  class dma_smoke_test extends dma_base_test;
    `uvm_component_utils(dma_smoke_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "one short and one multi-burst transfer complete with the right data and status";
      stimulus = "two descriptors, 16 and 200 bytes, aligned, no backpressure";
    endfunction
    task main();
      dma_desc_item list[$];
      list.push_back(make_desc(16));
      list.push_back(make_desc(200));
      foreach (list[i]) begin
        list[i].read_addr = (list[i].read_addr >> 12) << 12; list[i].write_addr = (list[i].write_addr >> 12) << 12;
        list[i].frame_len = list[i].len;
      end
      cfg.axi_cfg.mem.randomize_range(list[0].read_addr, 32);
      cfg.axi_cfg.mem.randomize_range(list[1].read_addr, 256);
      run_list(list);
    endtask
  endclass

  class dma_random_test extends dma_base_test;
    `uvm_component_utils(dma_random_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "random transfers of every length class and alignment are correct under random backpressure, with descriptors queued back to back";
      stimulus = "60 random descriptors: lengths around word/burst/4KB boundaries and up to 300 bytes, random (unaligned) addresses, 1 in 4 next to a 4KB boundary; axi_dma_wr frames shorter/equal/longer";
    endfunction
    virtual function void configure();
      random_backpressure();
      gap_max = $urandom_range(1, 0) ? 0 : 6;
    endfunction
    task main();
      run_random(60);
    endtask
  endclass

  class dma_backpressure_test extends dma_base_test;
    `uvm_component_utils(dma_backpressure_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "the engine stalls and resumes correctly when memory and stream are rarely ready (internal FIFOs fill up)";
      stimulus = "25 random descriptors with every READY high only 12% of the time and VALID delayed";
    endfunction
    virtual function void configure();
      cfg.axi_cfg.set_backpressure(12, 6);
      if (cfg.stream_cfg != null) begin cfg.stream_cfg.valid_pct = 30; cfg.stream_cfg.ready_pct = 12; end
      max_len = 600;
    endfunction
    task main();
      run_random(25);
    endtask
  endclass

  // Fast memory and fast/slow stream combinations fill the engine's FIFOs in
  // different ways; four phases with the knobs changed in between.
  class dma_throughput_test extends dma_base_test;
    `uvm_component_utils(dma_throughput_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "all combinations of a fast or slow memory with a fast or slow stream";
      stimulus = "4 phases of 12 descriptors (up to 1500 bytes): AXI ready 100% or 15%, stream ready/valid 100% or 15%";
    endfunction
    task main();
      max_len = 1500;
      for (int phase_i = 0; phase_i < 4; phase_i++) begin
        cfg.axi_cfg.set_backpressure(phase_i[0] ? 15 : 100, phase_i[0] ? 3 : 0);
        if (cfg.stream_cfg != null) begin
          cfg.stream_cfg.valid_pct = phase_i[1] ? 15 : 100;
          cfg.stream_cfg.ready_pct = phase_i[1] ? 15 : 100;
        end
        run_random(12);
      end
    endtask
  endclass

  class dma_error_test extends dma_base_test;
    `uvm_component_utils(dma_error_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "SLVERR and DECERR from the memory are reported in the status of the right descriptor and the engine keeps working";
      stimulus = "40 random descriptors; a third of them have a SLVERR or DECERR window placed at the start, middle or end of their address range";
    endfunction
    virtual function void configure();
      random_backpressure();
      preload = 0;
    endfunction
    task main();
      dma_desc_item list[$];
      repeat (40) begin
        dma_desc_item d = make_desc();
        if ($urandom_range(2, 0) == 0) begin
          // Error window inside the read range, or inside the write range.
          bit        on_write = (cfg.kind == DMA_WR) || (cfg.kind == DMA_CDMA && $urandom_range(1, 0));
          dma_addr_t base = on_write ? d.write_addr : d.read_addr;
          dma_addr_t lo   = base + $urandom_range(d.len - 1, 0);
          lo = (lo >> 2) << 2;
          cfg.axi_cfg.add_error_range(lo, lo + 3, $urandom_range(1, 0) ? AXI4_RESP_SLVERR : AXI4_RESP_DECERR);
        end
        list.push_back(d);
      end
      run_list(list);
    endtask
  endclass

  class dma_reset_test extends dma_base_test;
    `uvm_component_utils(dma_reset_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "a reset in the middle of a transfer returns the engine to idle; later descriptors are served correctly";
      stimulus = "4 times: 8 long descriptors started, reset at a random point; 6 resets at 1..6 cycles after the edge that accepts a descriptor; axi_dma_wr: 2 resets while a descriptor waits for stream data; then 15 descriptors that must complete";
    endfunction
    virtual function void configure();
      random_backpressure();
      max_len = 1200;
      cfg.axi_cfg.allow_pending_at_end = 0;
    endfunction
    task main();
      repeat (4) begin
        dma_desc_item list[$];
        repeat (8) list.push_back(make_desc());
        run_list(list, 0);
        clk_rst.wait_clocks($urandom_range(600, 30));
        // The rest of the batch is abandoned, then the engine is reset.
        stop_lists();
        clk_rst.apply_reset($urandom_range(6, 2));
        wait_lists_stopped();
        clk_rst.wait_clocks(5);
      end
      // Reset 1..6 cycles after the clock edge that accepts a descriptor: reaches
      // the one-cycle pipeline states that a reset at a random time rarely meets.
      // (The descriptor signals are read just after the edge, before any update,
      // i.e. with the values the design has just sampled.)
      for (int k = 0; k < 6; k++) begin
        dma_desc_item list[$];
        list.push_back(make_desc());
        run_list(list, 0);
        do clk_rst.wait_clocks(1); while (!(cfg.dma_vif.valid === 1'b1 && cfg.dma_vif.ready === 1'b1));
        clk_rst.wait_clocks(k);
        stop_lists();
        clk_rst.apply_reset_now($urandom_range(6, 2));
        wait_lists_stopped();
        clk_rst.wait_clocks(5);
      end
      // axi_dma_wr launches the first burst of a descriptor only when stream
      // data is there.  Hold the stream back and reset the engine while it waits.
      if (cfg.kind == DMA_WR) repeat (2) begin
        dma_desc_item list[$];
        int unsigned  keep = cfg.stream_cfg.valid_pct;
        cfg.stream_cfg.valid_pct = 0;
        repeat (2) list.push_back(make_desc());
        run_list(list, 0);
        clk_rst.wait_clocks($urandom_range(40, 15));
        stop_lists();
        clk_rst.apply_reset($urandom_range(6, 2));
        wait_lists_stopped();
        cfg.stream_cfg.valid_pct = keep;
        clk_rst.wait_clocks(5);
      end
      run_random(15);
    endtask
  endclass

  class dma_enable_test extends dma_base_test;
    `uvm_component_utils(dma_enable_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "with enable low no descriptor is accepted and no AXI traffic starts; work resumes when enable returns";
      stimulus = "6 times: enable=0, two descriptors offered for 60 cycles, enable=1, enable dropped once more mid-transfer; then 24 descriptors while enable toggles at random";
    endfunction
    virtual function void configure();
      max_len = 400;
    endfunction
    task main();
      repeat (6) begin
        dma_desc_item list[$];
        int unsigned  req_before, wr_before, rd_before;
        int unsigned  target = env.sb.n_desc_done + 2;
        cfg.dma_vif.enable <= 1'b0;
        clk_rst.wait_clocks(3);
        req_before = env.desc_mon.n_req; wr_before = env.axi.monitor.n_wr; rd_before = env.axi.monitor.n_rd;
        list.push_back(make_desc());
        list.push_back(make_desc());
        run_list(list, 0);
        clk_rst.wait_clocks(60);
        if (env.desc_mon.n_req != req_before || env.axi.monitor.n_wr != wr_before || env.axi.monitor.n_rd != rd_before)
          `uvm_error("DMA_ENABLE", "descriptor accepted or AXI burst completed while enable was low")
        cfg.dma_vif.enable <= 1'b1;
        // Drop enable again while the transfers run; they must still finish.
        clk_rst.wait_clocks($urandom_range(40, 5));
        cfg.dma_vif.enable <= 1'b0;
        clk_rst.wait_clocks($urandom_range(20, 3));
        cfg.dma_vif.enable <= 1'b1;
        wait_checked(target);
        clk_rst.wait_clocks(10);
      end
      // enable low only keeps new descriptors out: whatever was accepted must
      // finish, at whatever point of a transfer enable changes.
      begin
        bit stop;
        long_pct = 40;
        fork
          while (!stop) begin
            cfg.dma_vif.enable <= 1'b0; clk_rst.wait_clocks($urandom_range(12, 1));
            cfg.dma_vif.enable <= 1'b1; clk_rst.wait_clocks($urandom_range(25, 1));
          end
          begin run_random(24); stop = 1; end
        join
        cfg.dma_vif.enable <= 1'b1;
      end
    endtask
  endclass

  // One very long transfer: exercises the upper bits of the length and cycle counters.
  class dma_long_test extends dma_base_test;
    `uvm_component_utils(dma_long_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      timeout_us = 60000;
      intent   = "transfers close to the maximum descriptor length (2^20-1 bytes) complete with every byte checked";
      stimulus = "two descriptors of 2^20-1 bytes (byte offsets 3 and 0), each followed by a 64-byte one so that the counters fall back; no backpressure";
    endfunction
    virtual function void configure();
      cfg.axi_cfg.log_txn = 0;
      cfg.axi_cfg.timeout_cycles = 2000000;
      preload = 0;
    endfunction
    task main();
      dma_desc_item list[$];
      list.push_back(make_desc(20'hFFFFF));
      list.push_back(make_desc(64));
      list.push_back(make_desc(20'hFFFFF));
      list.push_back(make_desc(64));
      foreach (list[i]) begin
        // Offset 3 makes the number of AXI beats one more than the number of
        // stream beats for the first long transfer; offset 0 for the second.
        int unsigned off = (cfg.enable_unaligned && i == 0) ? 3 : 0;
        list[i].read_addr  = ((list[i].read_addr  >> 2) << 2) + off;
        list[i].write_addr = ((list[i].write_addr >> 2) << 2) + ((off + 2) % 4) * cfg.enable_unaligned;
        list[i].frame_len  = list[i].len;
      end
      run_list(list);
    endtask
  endclass

  // Walks the address, tag, id, dest and user inputs through all-ones and
  // walking-one values so that every bit of the request and status path toggles.
  class dma_field_walk_test extends dma_base_test;
    `uvm_component_utils(dma_field_walk_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "every bit of the descriptor fields (addresses, tag, id, dest, user) is carried through to the AXI address, the stream and the status";
      stimulus = "8-byte transfers with walking-one and walking-zero addresses and tags";
    endfunction
    task main();
      dma_desc_item list[$];
      for (int i = 0; i < 2 * AXI4_ADDR_WIDTH + 2; i++) begin
        dma_desc_item    d = make_desc(8);
        longint unsigned ones = (64'd1 << AXI4_ADDR_WIDTH) - 64;
        longint unsigned a, b;
        if (i < AXI4_ADDR_WIDTH)            begin a = 64'd1 << i; b = ones & ~(64'd1 << i); end
        else if (i < 2 * AXI4_ADDR_WIDTH)   begin b = 64'd1 << (i - AXI4_ADDR_WIDTH); a = ones & ~(64'd1 << (i - AXI4_ADDR_WIDTH)); end
        else                                begin a = (i[0]) ? ones : 0; b = (i[0]) ? 64 : ones; end
        if (a > ones) a = ones;
        if (b > ones) b = ones;
        a = (a >> 3) << 3; b = (b >> 3) << 3;
        if (a == b) b = a ^ 64'h1000;
        d.read_addr = a; d.write_addr = b;
        d.tag  = (i < 8) ? (8'd1 << i) : ~(8'd1 << (i % 8));
        d.id   = ~d.tag; d.dest = d.tag ^ 8'h5A; d.user = i[0];
        d.frame_len = 8;
        cfg.axi_cfg.mem.randomize_range(a, 16);
        list.push_back(d);
      end
      run_list(list);
    endtask
  endclass

  // axi_cdma: copies whose source byte offset is larger than the destination
  // offset, issued back to back against a memory that answers immediately.
  // The read data of the next burst is then already waiting when a burst
  // finishes (known issue CDMA-01 on the original RTL).
  class dma_cdma_offset_test extends dma_base_test;
    `uvm_component_utils(dma_cdma_offset_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "copies with every combination of source and destination byte offset are exact when read data arrives without gaps";
      stimulus = "for each of the 16 source/destination offset pairs: 3 descriptors of 70..200 bytes, no backpressure, descriptors queued back to back";
    endfunction
    task main();
      dma_desc_item list[$];
      for (int so = 0; so < 4; so++) for (int d_o = 0; d_o < 4; d_o++) repeat (3) begin
        dma_desc_item d = make_desc($urandom_range(200, 70));
        d.read_addr  = ((d.read_addr  >> 12) << 12) + 32'h100 + so;
        d.write_addr = ((d.write_addr >> 12) << 12) + 32'h800 + d_o;
        cfg.axi_cfg.mem.randomize_range(d.read_addr & ~32'h3, d.len + 8);
        list.push_back(d);
      end
      run_list(list);
    endtask
  endclass

  // axi_dma_wr: frames that end early, with the last beat straddling the end
  // of an AXI burst (4 KB boundary), each followed immediately by another
  // frame (known issue DMAWR-01 on the original RTL).
  class dma_wr_short_frame_split_test extends dma_base_test;
    `uvm_component_utils(dma_wr_short_frame_split_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "a frame shorter than its descriptor, whose last beat is split over two AXI bursts, does not disturb the next frame";
      stimulus = "descriptors starting 1..3 bytes before a 4 KB boundary with frames 1..4 bytes shorter than the descriptor, alternating with ordinary descriptors; frames sent back to back";
    endfunction
    task main();
      dma_desc_item list[$];
      for (int lead = 1; lead <= 3; lead++) for (int extra = 1; extra <= 12; extra += 2) begin
        dma_desc_item d = make_desc(lead + extra);
        dma_desc_item n = make_desc($urandom_range(140, 20));
        d.write_addr = ((d.write_addr >> 12) << 12) + 4096 - lead;
        d.frame_len  = d.len - $urandom_range((extra > 4) ? 4 : extra, 1);
        n.frame_len  = n.len;
        list.push_back(d);
        list.push_back(n);
      end
      run_list(list);
    endtask
  endclass

  // axi_dma_wr and axi_cdma: the memory takes write bursts but holds back the
  // write responses.  The engines keep one status-FIFO entry per unanswered
  // burst (32 entries) and must stop issuing bursts when it is full.
  class dma_resp_backlog_test extends dma_base_test;
    `uvm_component_utils(dma_resp_backlog_test)
    localparam int unsigned LIMIT = 32;   // 2**STATUS_FIFO_ADDR_WIDTH of the engines
    function new(string n, uvm_component p);
      super.new(n, p);
      timeout_us = 30000;
      intent   = "with write responses held back the engine stops at its limit of 32 unanswered bursts and finishes everything correctly once the responses arrive";
      stimulus = "9 rounds with the responses held back until the engine stalls: 45 single-burst descriptors (the 32nd with a frame shorter than, equal to or longer than its descriptor), or one descriptor of about 45 bursts";
      checking = {checking, "; test: exactly 32 unanswered write bursts when the engine has stalled"};
    endfunction
    virtual function void configure();
      cfg.axi_cfg.slv_max_wr = 256;          // the memory itself never limits the backlog
      cfg.axi_cfg.timeout_cycles = 200000;   // the responses are late on purpose
    endfunction
    // Waits until no further write address has been accepted for 300 cycles.
    task wait_aw_stall();
      int unsigned last = env.axi.monitor.num_wr_outstanding(), quiet = 0;
      while (quiet < 300) begin
        clk_rst.wait_clocks(10);
        if (env.axi.monitor.num_wr_outstanding() == last) quiet += 10;
        else begin quiet = 0; last = env.axi.monitor.num_wr_outstanding(); end
      end
    endtask
    task main();
      int unsigned bb = cfg.max_burst_len * AXI4_DATA_BYTES;
      if (cfg.kind == DMA_RD) `uvm_fatal("DMA_TEST", "dma_resp_backlog_test applies to axi_dma_wr and axi_cdma only")
      for (int r = 0; r < 9; r++) begin
        dma_desc_item list[$];
        int unsigned  target, n_out;
        cfg.axi_cfg.inj_no_b = 1;
        if (r < 6) begin
          for (int k = 0; k < 45; k++) begin
            dma_desc_item d = make_desc($urandom_range(bb / 2, bb / 4));
            // One burst each: both addresses are kept away from the 4 KB boundaries.
            d.read_addr  = ((d.read_addr  >> 12) << 12) + 32'h200 + (d.read_addr  & 32'hFF);
            d.write_addr = ((d.write_addr >> 12) << 12) + 32'h200 + (d.write_addr & 32'hFF);
            if (cfg.kind == DMA_CDMA) cfg.axi_cfg.mem.randomize_range((d.read_addr >> 2) << 2, d.len + 8);
            d.frame_len = d.len;
            if (k == LIMIT - 1) case (r % 3)
              0: d.frame_len = d.len - $urandom_range(d.len - 2, 9);   // ends at least one AXI beat early
              2: d.frame_len = d.len + $urandom_range(12, 1);          // the rest of the frame is dropped
              default: ;
            endcase
            list.push_back(d);
          end
        end else begin
          dma_desc_item d = make_desc(45 * bb - $urandom_range(bb - 1, 0));
          d.frame_len = d.len;
          list.push_back(d);
        end
        target = env.sb.n_desc_done + list.size();
        run_list(list, 0);
        wait_aw_stall();
        n_out = env.axi.monitor.num_wr_outstanding();
        if (n_out != LIMIT)
          `uvm_error("DMA_BACKLOG", $sformatf("round %0d: engine stalled with %0d unanswered write bursts, expected %0d", r, n_out, LIMIT))
        else
          `uvm_info("DMA_BACKLOG", $sformatf("round %0d: engine stalled with %0d unanswered write bursts, as expected", r, n_out), UVM_LOW)
        cfg.axi_cfg.inj_no_b = 0;
        wait_checked(target);
      end
    endtask
  endclass

  // axi_dma_wr only: the abort input is declared but not used by the RTL
  // (known limitation DMA-01).  This test shows that pulsing it changes nothing.
  class dma_wr_abort_test extends dma_base_test;
    `uvm_component_utils(dma_wr_abort_test)
    function new(string n, uvm_component p);
      super.new(n, p);
      intent   = "pulsing 'abort' has no effect on running transfers (the input is not implemented, limitation DMA-01)";
      stimulus = "20 random descriptors while abort is pulsed every 20..80 cycles";
    endfunction
    task main();
      fork
        forever begin
          clk_rst.wait_clocks($urandom_range(80, 20));
          cfg.dma_vif.abort <= 1'b1;
          clk_rst.wait_clocks($urandom_range(5, 1));
          cfg.dma_vif.abort <= 1'b0;
        end
      join_none
      run_random(20);
      disable fork;
      cfg.dma_vif.abort <= 1'b0;
    endtask
  endclass
endpackage
