# Coverage exclusions for axi_ram (dut/axi_ram/axi_ram.v).
# Applied by scripts/cov_report.ps1 to the merged UCDB.  Every item below is
# unreachable for a reason given next to it; nothing is excluded because it was
# merely hard to hit.  Coverage is reported both without and with this file.

# --- Not hardware --------------------------------------------------------------
# 'i' and 'j' are integer loop indices of the memory-initialisation and
# byte-write loops.  They are simulation variables, not signals of the design.
coverage exclude -du axi_ram -togglenode i -comment "integer loop index, not a design signal"
coverage exclude -du axi_ram -togglenode j -comment "integer loop index of the initial block, not a design signal"

# --- Dead declaration ----------------------------------------------------------
# s_axi_rdata_next is declared (line 140) but never assigned or read.
coverage exclude -du axi_ram -togglenode s_axi_rdata_next -comment "declared but never driven or used in the RTL"

# --- Constants by design -------------------------------------------------------
# The RAM always answers OKAY: 'assign s_axi_bresp = 2'b00' / 'assign s_axi_rresp = 2'b00'.
coverage exclude -du axi_ram -togglenode s_axi_bresp -comment "tied to 2'b00 (OKAY) by continuous assignment"
coverage exclude -du axi_ram -togglenode s_axi_rresp -comment "tied to 2'b00 (OKAY) by continuous assignment"

# --- Illegal for a 32-bit data bus ---------------------------------------------
# AxSIZE[2]=1 means 16 bytes or more per beat.  AXI4 forbids a transfer wider
# than the data bus, so a legal address phase never has bit 2 set, and the RTL
# clamps the registered copies to 2 (lines 206, 309).  The port bits themselves
# do toggle (the VIP puts random values on the payload while VALID is low) and
# are therefore not excluded.
coverage exclude -du axi_ram -togglenode {write_size_reg[2]}  -comment "clamped to log2(STRB_WIDTH)=2 at line 206"
coverage exclude -du axi_ram -togglenode {write_size_next[2]} -comment "clamped to log2(STRB_WIDTH)=2 at line 206"
coverage exclude -du axi_ram -togglenode {read_size_reg[2]}   -comment "clamped to log2(STRB_WIDTH)=2 at line 309"
coverage exclude -du axi_ram -togglenode {read_size_next[2]}  -comment "clamped to log2(STRB_WIDTH)=2 at line 309"

# --- Unreachable case alternatives ---------------------------------------------
# 'case (write_state_reg)' at line 198 lists all three states the 2-bit register
# can hold; value 3 is never assigned.  'case (read_state_reg)' at line 301 lists
# both values of a 1-bit register.  Neither case can fall through.
coverage exclude -du axi_ram -srcfile dut/axi_ram/axi_ram.v -linerange 198 -allfalse -comment "write_state_reg is only ever IDLE, BURST or RESP"
coverage exclude -du axi_ram -srcfile dut/axi_ram/axi_ram.v -linerange 301 -allfalse -comment "1-bit state register, both values listed"

# --- Unreachable condition terms -----------------------------------------------
# Line 219, state BURST: 'if (s_axi_wready && s_axi_wvalid)'.  s_axi_wready_reg is
# set on every path that enters or stays in BURST, so s_axi_wready=0 never occurs here.
coverage exclude -du axi_ram -srcfile dut/axi_ram/axi_ram.v -feccondrow 219 1 -comment "s_axi_wready is always 1 in WRITE_STATE_BURST"
# Line 243, state RESP: 'if (s_axi_bready || !s_axi_bvalid)'.  RESP is entered only
# with s_axi_bvalid=1 and BREADY low, and bvalid stays 1 until BREADY, so the row
# 's_axi_bvalid=0 with s_axi_bready=0' cannot occur.
coverage exclude -du axi_ram -srcfile dut/axi_ram/axi_ram.v -feccondrow 243 3 -comment "s_axi_bvalid is always 1 in WRITE_STATE_RESP"
