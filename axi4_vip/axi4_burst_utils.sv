// Shared AXI4 burst address and byte-lane calculations (AXI4 spec A3.4).

// Address of beat `i` (0-based).  The first beat uses the start address as
// given; later INCR/WRAP beats are aligned to the transfer size.
function automatic axi4_addr_t axi4_beat_addr(
  input axi4_addr_t  start,
  input int unsigned i,
  input bit [7:0]    len,
  input bit [2:0]    size,
  input bit [1:0]    burst
);
  longint unsigned nb      = 64'd1 << size;
  longint unsigned aligned = (start / nb) * nb;
  longint unsigned total, lo;
  if (i == 0 || burst == 2'b00) return start;
  if (burst == 2'b10) begin
    total = nb * (len + 1);
    lo    = (start / total) * total;
    return lo + ((aligned - lo + i * nb) % total);
  end
  return aligned + i * nb;
endfunction

// Byte lanes that carry valid data in beat `i`.
function automatic axi4_strb_t axi4_lane_mask(
  input axi4_addr_t  start,
  input int unsigned i,
  input bit [7:0]    len,
  input bit [2:0]    size,
  input bit [1:0]    burst
);
  axi4_strb_t      mask = '0;
  longint unsigned nb   = 64'd1 << size;
  longint unsigned a    = axi4_beat_addr(start, i, len, size, burst);
  int unsigned     lo   = a % AXI4_DATA_BYTES;
  int unsigned     hi   = ((a / nb) * nb) % AXI4_DATA_BYTES + nb - 1;
  for (int unsigned b = lo; b <= hi && b < AXI4_DATA_BYTES; b++) mask[b] = 1'b1;
  return mask;
endfunction

// Memory address of byte lane `lane` for a beat at address `beat_addr`.
function automatic axi4_addr_t axi4_lane_addr(input axi4_addr_t beat_addr, input int unsigned lane);
  return (beat_addr / AXI4_DATA_BYTES) * AXI4_DATA_BYTES + lane;
endfunction

function automatic bit axi4_is_aligned(input axi4_addr_t addr, input bit [2:0] size);
  return (addr & ((64'd1 << size) - 1)) == 0;
endfunction

// True when an INCR burst would cross a 4 KB boundary (illegal in AXI4).
function automatic bit axi4_crosses_4k(
  input axi4_addr_t addr,
  input bit [7:0]   len,
  input bit [2:0]   size,
  input bit [1:0]   burst
);
  longint unsigned nb = 64'd1 << size;
  longint unsigned lo = ((addr & 12'hFFF) / nb) * nb;
  if (burst != 2'b01) return 0;
  return (lo + (len + 1) * nb) > 4096;
endfunction
