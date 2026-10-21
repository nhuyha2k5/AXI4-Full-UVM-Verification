// =============================================================================
// AXI4 master sequence library.
//
// Every sequence runs on an axi4_sequencer and takes the port limits (address
// and ID width) from its cfg, so the same sequence works on any port.  None of
// them knows anything about a particular DUT.
// =============================================================================

// Base class: item creation, issue/wait helpers and directed read/write tasks.
class axi4_base_seq extends uvm_sequence #(axi4_seq_item);
  `uvm_object_utils(axi4_base_seq)
  `uvm_declare_p_sequencer(axi4_sequencer)

  axi4_agent_cfg cfg;
  axi4_seq_item  sent[$];   // items issued and not yet waited for

  function new(string n = "axi4_base_seq");
    super.new(n);
  endfunction

  virtual task pre_start();
    cfg = p_sequencer.cfg;
  endtask

  function axi4_seq_item new_item(string name = "t");
    axi4_seq_item t = axi4_seq_item::type_id::create(name);
    t.addr_width = cfg.addr_width; t.id_width = cfg.id_width; t.user_width = cfg.user_width;
    return t;
  endfunction

  // Hands an already randomized item to the driver.
  task issue(axi4_seq_item t, bit wait_done = 1);
    start_item(t);
    finish_item(t);
    if (wait_done) wait (t.done);
    else           sent.push_back(t);
  endtask

  task wait_all();
    foreach (sent[i]) wait (sent[i].done);
    sent.delete();
  endtask

  // Directed write of `d` starting at `addr`; every valid lane is strobed.
  task do_write(axi4_addr_t addr, axi4_data_t d[], axi4_id_t id = 0,
                bit [2:0] size = AXI4_MAX_SIZE, axi4_burst_e burst = AXI4_BURST_INCR, bit wait_done = 1);
    axi4_seq_item t = new_item("wr");
    if (!t.randomize() with {
          cmd == AXI4_WRITE; addr == local::addr; id == local::id; size == local::size;
          burst == local::burst; len == local::d.size() - 1; delay == 0;
        }) `uvm_fatal("AXI_SEQ", $sformatf("illegal directed write: addr=%h beats=%0d size=%0d %s", addr, d.size(), size, burst.name()))
    foreach (d[i]) t.data[i] = d[i];
    issue(t, wait_done);
  endtask

  task do_read(axi4_addr_t addr, int unsigned beats, output axi4_data_t d[], input axi4_id_t id = 0,
               bit [2:0] size = AXI4_MAX_SIZE, axi4_burst_e burst = AXI4_BURST_INCR);
    axi4_seq_item t = new_item("rd");
    if (!t.randomize() with {
          cmd == AXI4_READ; addr == local::addr; id == local::id; size == local::size;
          burst == local::burst; len == local::beats - 1; delay == 0;
        }) `uvm_fatal("AXI_SEQ", $sformatf("illegal directed read: addr=%h beats=%0d size=%0d %s", addr, beats, size, burst.name()))
    issue(t, 1);
    d = t.rdata;
  endtask
endclass

// -----------------------------------------------------------------------------
// Constrained-random traffic.  All knobs default to "everything legal".
// -----------------------------------------------------------------------------
class axi4_rand_seq extends axi4_base_seq;
  `uvm_object_utils(axi4_rand_seq)

  int unsigned num_txn    = 50;
  int unsigned wr_pct     = 50;    // share of writes
  bit          pipelined  = 1;     // 0: wait for each transaction before issuing the next
  int unsigned max_len    = 255;   // largest AxLEN
  bit          use_fixed  = 1;
  bit          use_incr   = 1;
  bit          use_wrap   = 1;
  bit          wrap_at_boundary = 0;  // WRAP bursts start on the wrap boundary (no address wrap)
  bit          narrow     = 1;     // allow sizes below the bus width
  bit          unaligned  = 1;     // allow unaligned start addresses
  bit          sideband   = 0;     // randomize LOCK/CACHE/PROT/QOS/REGION/USER
  int unsigned sparse_pct = 0;     // share of writes with partial strobes
  int unsigned idle_max   = 0;     // idle cycles before an item is handed over
  int unsigned id_lo      = 0;
  int unsigned id_hi      = '1;
  // Address windows; a burst never leaves the window it starts in.
  axi4_addr_t  win_lo[$];
  axi4_addr_t  win_hi[$];

  function new(string n = "axi4_rand_seq");
    super.new(n);
  endfunction

  function void add_window(axi4_addr_t lo, axi4_addr_t hi);
    win_lo.push_back(lo); win_hi.push_back(hi);
  endfunction

  // Hook for subclasses: adjust a randomized item before it is sent.
  virtual function void tweak(axi4_seq_item t);
  endfunction

  virtual function axi4_seq_item make_item();
    axi4_seq_item t = new_item("t");
    axi4_addr_t   lo, hi;
    int unsigned  w, id_max;
    if (win_lo.size() == 0) add_window(0, (64'd1 << cfg.addr_width) - 1);
    w  = $urandom_range(win_lo.size() - 1, 0);
    lo = win_lo[w]; hi = win_hi[w];
    id_max = (1 << cfg.id_width) - 1;
    if (id_hi > id_max) id_hi = id_max;
    if (sideband) t.c_sideband.constraint_mode(0);
    // The item's soft defaults (no idle, full strobes) would win over the
    // distributions below, so they are switched off here.
    t.c_delay.constraint_mode(0);
    t.c_strb_mode.constraint_mode(0);
    if (!t.randomize() with {
          cmd dist { AXI4_WRITE := local::wr_pct, AXI4_READ := 100 - local::wr_pct };
          len dist { 0 := 20, [1:3] := 20, [4:15] := 30, [16:63] := 15, [64:254] := 10, 255 := 5 };
          len <= local::max_len;
          !local::use_fixed -> burst != AXI4_BURST_FIXED;
          !local::use_incr  -> burst != AXI4_BURST_INCR;
          !local::use_wrap  -> burst != AXI4_BURST_WRAP;
          !local::narrow    -> size == AXI4_MAX_SIZE;
          !local::unaligned -> (addr & ((32'd1 << size) - 1)) == 0;
          (local::wrap_at_boundary && burst == AXI4_BURST_WRAP) -> (addr & (((len + 32'd1) << size) - 1)) == 0;
          id inside {[local::id_lo:local::id_hi]};
          addr inside {[local::lo:local::hi]};
          (local::hi - addr) >= (((len + 32'd1) << size) - 1);
          delay <= local::idle_max;
          sparse_strb dist { 1 := local::sparse_pct, 0 := 100 - local::sparse_pct };
        }) `uvm_fatal("AXI_SEQ", {get_type_name(), ": randomization failed (conflicting knobs?)"})
    if (sideband && cfg.user_width < AXI4_USER_WIDTH) t.auser &= ((1 << cfg.user_width) - 1);
    tweak(t);
    return t;
  endfunction

  virtual task body();
    repeat (num_txn) issue(make_item(), !pipelined);
    wait_all();
  endtask
endclass

// Write a random burst, wait, then read the same burst back.  The data check
// is done by the scoreboard; this sequence makes the result deterministic.
class axi4_write_read_seq extends axi4_rand_seq;
  `uvm_object_utils(axi4_write_read_seq)
  function new(string n = "axi4_write_read_seq");
    super.new(n);
    wr_pct = 100;
  endfunction
  virtual task body();
    axi4_seq_item wr, rd;
    repeat (num_txn) begin
      wr = make_item();
      issue(wr, 1);
      rd = new_item("rd");
      rd.copy(wr);
      rd.cmd = AXI4_READ; rd.data.delete(); rd.strb.delete(); rd.wuser.delete();
      rd.done = 0; rd.aborted = 0;
      issue(rd, 1);
    end
  endtask
endclass

// INCR bursts placed against 4 KB boundaries: ending exactly on one, and
// starting exactly on one.
class axi4_4k_boundary_seq extends axi4_rand_seq;
  `uvm_object_utils(axi4_4k_boundary_seq)
  function new(string n = "axi4_4k_boundary_seq");
    super.new(n);
    use_fixed = 0; use_wrap = 0;
  endfunction
  virtual function void tweak(axi4_seq_item t);
    longint unsigned nb    = 64'd1 << t.size;
    longint unsigned bytes = (t.len + 1) * nb;
    longint unsigned page  = (t.addr >> 12) << 12;
    if (bytes > 4096) return;
    if ($urandom_range(1, 0)) t.addr = page + 4096 - bytes;   // last byte is the last byte of the page
    else                      t.addr = page;                  // first byte is the first byte of the page
    t.fix_strobes();
  endfunction
endclass

// WRAP bursts that really wrap: the start address is never the wrap boundary.
class axi4_wrap_seq extends axi4_rand_seq;
  `uvm_object_utils(axi4_wrap_seq)
  function new(string n = "axi4_wrap_seq");
    super.new(n);
    use_fixed = 0; use_incr = 0;
  endfunction
  virtual function void tweak(axi4_seq_item t);
    longint unsigned nb    = 64'd1 << t.size;
    longint unsigned total = (t.len + 1) * nb;
    longint unsigned base  = (t.addr / total) * total;
    t.addr = base + nb * $urandom_range(t.len, 1);
    t.fix_strobes();
  endfunction
endclass

// Longest legal INCR burst (256 beats), full width, page aligned.
class axi4_max_burst_seq extends axi4_rand_seq;
  `uvm_object_utils(axi4_max_burst_seq)
  function new(string n = "axi4_max_burst_seq");
    super.new(n);
    use_fixed = 0; use_wrap = 0; narrow = 0; unaligned = 0;
  endfunction
  virtual function void tweak(axi4_seq_item t);
    int unsigned beats = 4096 >> AXI4_MAX_SIZE;
    if (beats > 256) beats = 256;
    t.len  = beats - 1;
    t.addr = (t.addr >> 12) << 12;
    if (t.cmd == AXI4_WRITE) begin
      t.data = new[beats]; t.strb = new[beats]; t.wuser = new[beats];
      foreach (t.data[i]) begin
        for (int b = 0; b < AXI4_DATA_BYTES; b++) t.data[i][8*b +: 8] = $urandom_range(255, 0);
      end
    end
    t.fix_strobes();
  endfunction
endclass

// Reads the address range [lo, hi] with full-width INCR bursts.  Used to make
// a scoreboard check everything a region contains.
class axi4_region_read_seq extends axi4_base_seq;
  `uvm_object_utils(axi4_region_read_seq)
  axi4_addr_t  lo = 0;
  axi4_addr_t  hi = 0;
  int unsigned beats = 16;
  function new(string n = "axi4_region_read_seq");
    super.new(n);
  endfunction
  virtual task body();
    axi4_data_t      r[];
    longint unsigned a = lo;
    longint unsigned step = beats * AXI4_DATA_BYTES;
    while (a <= hi) begin
      do_read(a, beats, r, $urandom_range((1 << cfg.id_width) - 1, 0));
      a += step;
    end
  endtask
endclass

// Single-beat accesses whose address walks a one, then a zero, through every
// address bit of the port.  Exercises address decoding and address toggling.
class axi4_addr_walk_seq extends axi4_base_seq;
  `uvm_object_utils(axi4_addr_walk_seq)
  bit en_write = 1;
  bit en_read  = 1;
  function new(string n = "axi4_addr_walk_seq");
    super.new(n);
  endfunction
  task access(axi4_addr_t a);
    axi4_data_t d[] = new[1];
    axi4_data_t r[];
    a = (a >> AXI4_MAX_SIZE) << AXI4_MAX_SIZE;
    for (int b = 0; b < AXI4_DATA_BYTES; b++) d[0][8*b +: 8] = $urandom_range(255, 0);
    if (en_write) do_write(a, d, $urandom_range((1 << cfg.id_width) - 1, 0));
    if (en_read)  do_read(a, 1, r, $urandom_range((1 << cfg.id_width) - 1, 0));
  endtask
  virtual task body();
    axi4_addr_t all_ones = (64'd1 << cfg.addr_width) - 1;
    access(0);
    for (int unsigned i = AXI4_MAX_SIZE; i < cfg.addr_width; i++) access(axi4_addr_t'(64'd1 << i));
    for (int unsigned i = AXI4_MAX_SIZE; i < cfg.addr_width; i++) access(all_ones & ~axi4_addr_t'(64'd1 << i));
    access(all_ones);
  endtask
endclass

// Single-beat writes of walking-one / walking-zero / all-ones / all-zeros data,
// each read back.  Toggles every data bit in both directions.
class axi4_data_walk_seq extends axi4_base_seq;
  `uvm_object_utils(axi4_data_walk_seq)
  axi4_addr_t base = 0;
  function new(string n = "axi4_data_walk_seq");
    super.new(n);
  endfunction
  task pattern(axi4_data_t v);
    axi4_data_t d[] = new[1];
    axi4_data_t r[];
    d[0] = v;
    do_write(base, d);
    do_read(base, 1, r);
  endtask
  virtual task body();
    pattern('0);
    pattern('1);
    for (int i = 0; i < AXI4_DATA_WIDTH; i++) pattern(axi4_data_t'(1) << i);
    for (int i = 0; i < AXI4_DATA_WIDTH; i++) pattern(~(axi4_data_t'(1) << i));
    pattern('0);
  endtask
endclass
