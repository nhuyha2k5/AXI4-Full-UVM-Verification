// AXI4 transaction: one write burst or one read burst.
class axi4_seq_item extends uvm_sequence_item;
  `uvm_object_utils(axi4_seq_item)

  // ---------------- request ----------------
  rand axi4_cmd_e   cmd;
  rand axi4_id_t    id;
  rand axi4_addr_t  addr;
  rand bit [7:0]    len;      // beats - 1
  rand bit [2:0]    size;     // log2(bytes per beat)
  rand axi4_burst_e burst;
  rand bit          lock;
  rand bit [3:0]    cache;
  rand bit [2:0]    prot;
  rand bit [3:0]    qos;
  rand bit [3:0]    region;
  rand axi4_user_t  auser;
  rand axi4_data_t  data[];   // write data, one entry per beat
  rand axi4_strb_t  strb[];
  rand axi4_user_t  wuser[];
  rand int unsigned delay;    // idle cycles before the driver accepts the item
  // 0: every valid byte lane is strobed.  1: random subset of the valid lanes.
  rand bit          sparse_strb;

  // Port limits; a sequence copies them from the agent cfg before randomize().
  int unsigned addr_width = AXI4_ADDR_WIDTH;
  int unsigned id_width   = AXI4_ID_WIDTH;
  int unsigned user_width = AXI4_USER_WIDTH;

  // ---------------- response (driver and monitor) ----------------
  axi4_data_t  rdata[];
  axi4_resp_e  rresp[];
  axi4_user_t  ruser[];
  axi4_resp_e  bresp;
  axi4_user_t  buser;
  bit          done;      // transaction finished on the bus
  bit          aborted;   // dropped because of reset

  // ---------------- observed by the monitor ----------------
  longint unsigned seq_no;        // acceptance order of the address phase, per direction
  int unsigned     outstanding;   // same-direction transactions in flight at acceptance
  int unsigned     addr_stall;    // cycles AxVALID waited for AxREADY
  int unsigned     data_stall;    // longest wait of a W/R beat for its READY
  int unsigned     resp_stall;    // cycles BVALID waited for BREADY
  bit              w_before_aw;   // W burst completed before its AW was accepted
  time             t_start, t_end;
  int unsigned     age;           // monitor watchdog
  bit              mon_w_done;
  longint unsigned mon_w_cycle;   // cycle the request phase completed (W burst associated / AR accepted)
  bit              mon_b_flagged;  // early-response violation already reported

  // ---------------- driver scratch ----------------
  bit drv_aw_done;

  // ---------------- constraints ----------------
  constraint c_width {
    (addr_width < AXI4_ADDR_WIDTH) -> ((addr >> addr_width) == 0);
    (id_width   < AXI4_ID_WIDTH)   -> ((id   >> id_width)   == 0);
    (user_width < AXI4_USER_WIDTH) -> ((auser >> user_width) == 0);
  }
  constraint c_size  { size <= AXI4_MAX_SIZE; }
  constraint c_burst { burst != AXI4_BURST_RSVD; }
  constraint c_len {
    (burst == AXI4_BURST_WRAP)  -> (len inside {1, 3, 7, 15});
    (burst == AXI4_BURST_FIXED) -> (len <= 15);
  }
  // WRAP bursts must start at an address aligned to the transfer size.
  constraint c_wrap_align { (burst == AXI4_BURST_WRAP) -> ((addr & ((32'd1 << size) - 1)) == 0); }
  // INCR bursts must not cross a 4 KB boundary.
  constraint c_4k {
    (burst == AXI4_BURST_INCR) ->
      (((addr & 32'hFFF) & ~((32'd1 << size) - 1)) + ((len + 32'd1) << size) <= 32'd4096);
  }
  constraint c_arrays {
    if (cmd == AXI4_WRITE) {
      data.size() == len + 1; strb.size() == len + 1; wuser.size() == len + 1;
    } else {
      data.size() == 0; strb.size() == 0; wuser.size() == 0;
    }
  }
  constraint c_order { solve cmd, len before data, strb, wuser; }
  constraint c_delay { soft delay == 0; }
  constraint c_sideband {
    soft lock == 0; soft cache == 0; soft prot == 0; soft qos == 0; soft region == 0; soft auser == 0;
  }
  constraint c_strb_mode { soft sparse_strb == 0; }

  function new(string name = "axi4_seq_item");
    super.new(name);
  endfunction

  function void post_randomize();
    fix_strobes();
  endfunction

  // Keep strobes inside the byte lanes that are valid for each beat.
  function void fix_strobes();
    axi4_strb_t mask;
    foreach (strb[i]) begin
      mask = axi4_lane_mask(addr, i, len, size, burst);
      strb[i] = sparse_strb ? (strb[i] & mask) : mask;
      if (user_width < AXI4_USER_WIDTH) wuser[i] &= ((1 << user_width) - 1);
    end
  endfunction

  function int unsigned beats();
    return len + 1;
  endfunction

  function axi4_addr_t beat_addr(int unsigned i);
    return axi4_beat_addr(addr, i, len, size, burst);
  endfunction

  function bit has_error_resp();
    if (cmd == AXI4_WRITE) return bresp inside {AXI4_RESP_SLVERR, AXI4_RESP_DECERR};
    foreach (rresp[i]) if (rresp[i] inside {AXI4_RESP_SLVERR, AXI4_RESP_DECERR}) return 1;
    return 0;
  endfunction

  function string data2string(axi4_data_t d[], int unsigned max_show = 4);
    string s = "[";
    foreach (d[i]) begin
      if (i == max_show) begin s = {s, $sformatf(" ..+%0d", d.size() - max_show)}; break; end
      s = {s, (i == 0) ? "" : " ", $sformatf("%h", d[i])};
    end
    return {s, "]"};
  endfunction

  virtual function string convert2string();
    string s;
    s = $sformatf("%s id=%0h addr=%h len=%0d size=%0d %s",
                  (cmd == AXI4_WRITE) ? "WR" : "RD", id, addr, len, size, burst.name());
    if (lock || cache != 0 || prot != 0 || qos != 0 || region != 0)
      s = {s, $sformatf(" lock=%0b cache=%0h prot=%0h qos=%0h region=%0h", lock, cache, prot, qos, region)};
    if (cmd == AXI4_WRITE) begin
      s = {s, $sformatf(" data=%s", data2string(data))};
      if (strb.size() > 0) s = {s, $sformatf(" strb0=%0h", strb[0])};
      if (done) s = {s, $sformatf(" bresp=%s", bresp.name())};
    end else if (done) begin
      s = {s, $sformatf(" rdata=%s", data2string(rdata))};
      if (rresp.size() > 0) s = {s, $sformatf(" rresp=%s%s", rresp[0].name(), has_error_resp() ? "(ERR)" : "")};
    end
    if (aborted) s = {s, " ABORTED"};
    return s;
  endfunction

  virtual function void do_copy(uvm_object rhs);
    axi4_seq_item r;
    super.do_copy(rhs);
    if (!$cast(r, rhs)) return;
    cmd = r.cmd; id = r.id; addr = r.addr; len = r.len; size = r.size; burst = r.burst;
    lock = r.lock; cache = r.cache; prot = r.prot; qos = r.qos; region = r.region; auser = r.auser;
    data = r.data; strb = r.strb; wuser = r.wuser; delay = r.delay; sparse_strb = r.sparse_strb;
    addr_width = r.addr_width; id_width = r.id_width; user_width = r.user_width;
    rdata = r.rdata; rresp = r.rresp; ruser = r.ruser; bresp = r.bresp; buser = r.buser;
    done = r.done; aborted = r.aborted;
    seq_no = r.seq_no; outstanding = r.outstanding; addr_stall = r.addr_stall;
    data_stall = r.data_stall; resp_stall = r.resp_stall; w_before_aw = r.w_before_aw;
    t_start = r.t_start; t_end = r.t_end;
  endfunction

  // Compares the bus-visible content of two transactions.
  virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    axi4_seq_item r;
    if (!$cast(r, rhs)) return 0;
    if (cmd != r.cmd || addr != r.addr || len != r.len || size != r.size || burst != r.burst) return 0;
    if (lock != r.lock || cache != r.cache || prot != r.prot || qos != r.qos) return 0;
    if (cmd == AXI4_WRITE) begin
      if (data.size() != r.data.size()) return 0;
      foreach (data[i]) if (data[i] != r.data[i] || strb[i] != r.strb[i]) return 0;
      return bresp == r.bresp;
    end
    if (rdata.size() != r.rdata.size()) return 0;
    foreach (rdata[i]) if (rdata[i] != r.rdata[i] || rresp[i] != r.rresp[i]) return 0;
    return 1;
  endfunction
endclass
