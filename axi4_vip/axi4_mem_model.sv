// Sparse byte-addressable memory shared by the slave driver (as storage) and
// by scoreboards (as reference model / backdoor).
typedef enum int {
  AXI4_MEM_ZERO,       // unwritten bytes read as 0x00
  AXI4_MEM_ADDR_HASH   // unwritten bytes read as a deterministic function of the address
} axi4_mem_default_e;

class axi4_mem_model extends uvm_object;
  `uvm_object_utils(axi4_mem_model)

  bit [7:0]          mem[longint unsigned];
  axi4_mem_default_e default_mode = AXI4_MEM_ZERO;
  // Addresses are ANDed with this mask before use, which models a DUT that
  // decodes fewer address bits than the bus carries.
  longint unsigned   addr_mask = '1;

  function new(string name = "axi4_mem_model");
    super.new(name);
  endfunction

  // Non-zero, address-dependent default so a shifted or swapped byte is visible.
  static function bit [7:0] hash_byte(longint unsigned a);
    return 8'hA5 ^ a[7:0] ^ a[15:8] ^ a[23:16] ^ a[31:24];
  endfunction

  function bit [7:0] read_byte(longint unsigned a);
    a &= addr_mask;
    if (mem.exists(a)) return mem[a];
    return (default_mode == AXI4_MEM_ADDR_HASH) ? hash_byte(a) : 8'h00;
  endfunction

  function void write_byte(longint unsigned a, bit [7:0] d);
    mem[a & addr_mask] = d;
  endfunction

  function bit is_written(longint unsigned a);
    return mem.exists(a & addr_mask);
  endfunction

  function void clear();
    mem.delete();
  endfunction

  // Backdoor fill of [lo, lo+n) with random bytes.
  function void randomize_range(longint unsigned lo, int unsigned n);
    for (int unsigned i = 0; i < n; i++) write_byte(lo + i, $urandom_range(255, 0));
  endfunction
endclass
