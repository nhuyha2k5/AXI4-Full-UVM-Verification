# Coverage exclusions for the DMA engines (dut/dma/axi_dma_rd.v, axi_dma_wr.v, axi_cdma.v).
# Applied by scripts/cov_report.ps1 to the merged UCDB.  Every item is unreachable for the
# reason given with it; nothing is excluded because it was merely hard to hit.  Coverage
# is reported both without and with this file.
#
# Verified configurations: AXI_DATA_WIDTH = 32; AXI_MAX_BURST_LEN = 1, 16 and 256;
# ENABLE_UNALIGNED = 0 and 1; LEN_WIDTH = 20.  Items marked [CONFIG] are unreachable in
# these configurations only (they would need a data bus of 128 bits or more).

# ==============================================================================
# axi_dma_rd
# ==============================================================================
# --- Outputs tied to a constant by a continuous assignment -------------------------
# The engines always issue full-width INCR bursts with ID 0, no lock, CACHE 0011, PROT 010.
coverage exclude -du axi_dma_rd -togglenode {m_axi_arid} -comment "assign m_axi_arid = 0"
coverage exclude -du axi_dma_rd -togglenode {m_axi_arsize} -comment "assign m_axi_arsize = AXI_BURST_SIZE (constant)"
coverage exclude -du axi_dma_rd -togglenode {m_axi_arburst} -comment "assign m_axi_arburst = 2'b01 (INCR)"
coverage exclude -du axi_dma_rd -togglenode {m_axi_arlock} -comment "assign m_axi_arlock = 1'b0"
coverage exclude -du axi_dma_rd -togglenode {m_axi_arcache} -comment "assign m_axi_arcache = 4'b0011"
coverage exclude -du axi_dma_rd -togglenode {m_axi_arprot} -comment "assign m_axi_arprot = 3'b010"

# --- Status error code bits that no assigned value ever sets -----------------------
# axi_dma_rd reports 0 (none), 4 (read SLVERR) or 5 (read DECERR): bits 1 and 3 are never 1.
coverage exclude -du axi_dma_rd -togglenode {m_axis_read_desc_status_error[1]} -comment "only the codes 0, 4 and 5 are assigned"
coverage exclude -du axi_dma_rd -togglenode {m_axis_read_desc_status_error[3]} -comment "only the codes 0, 4 and 5 are assigned"
coverage exclude -du axi_dma_rd -togglenode {m_axis_read_desc_status_error_next[1]} -comment "only the codes 0, 4 and 5 are assigned"
coverage exclude -du axi_dma_rd -togglenode {m_axis_read_desc_status_error_next[3]} -comment "only the codes 0, 4 and 5 are assigned"
coverage exclude -du axi_dma_rd -togglenode {m_axis_read_desc_status_error_reg[1]} -comment "only the codes 0, 4 and 5 are assigned"
coverage exclude -du axi_dma_rd -togglenode {m_axis_read_desc_status_error_reg[3]} -comment "only the codes 0, 4 and 5 are assigned"

# --- Output FIFO can never be full -------------------------------------------------
# The 32-entry output FIFO stops its producer when it is half full (out_fifo_half_full_reg,
# registered, 16 entries).  The producer stops two cycles later and at most a few more
# entries are written (the ready signal is registered once more, plus one or two flush
# beats), so the fill level stays near 20, far below 32, and out_fifo_full is constant 0.
coverage exclude -du axi_dma_rd -togglenode {out_fifo_full} -comment "flow control at half full; the FIFO never fills"
coverage exclude -du axi_dma_rd -srcfile dut/dma/axi_dma_rd.v -fecexprrow 653 2 -comment "out_fifo_full is never 1 (flow control at half full)"
coverage exclude -du axi_dma_rd -srcfile dut/dma/axi_dma_rd.v -feccondrow 684 2 -comment "out_fifo_full is never 1 (flow control at half full)"

# --- Case statements that list every value their state register can hold ------------
coverage exclude -du axi_dma_rd -srcfile dut/dma/axi_dma_rd.v -linerange 326 -allfalse -comment "axi_state_reg is 1 bit, both values listed"
coverage exclude -du axi_dma_rd -srcfile dut/dma/axi_dma_rd.v -linerange 472 -allfalse -comment "axis_state_reg is 1 bit, both values listed"

# --- Redundant guards in the data-transfer state ------------------------------------
# Line 512, 'if (input_active_reg)', sits in the branch taken only in the first input cycle
# of a burst (first cycle && bubble_cycle); input_active_reg is set when the burst is loaded
# and cannot have been cleared before its first cycle.
coverage exclude -du axi_dma_rd -srcfile dut/dma/axi_dma_rd.v -linerange 512 -allfalse -comment "input_active_reg is always 1 in the first input cycle"
# Line 527, 'if (output_active_reg)': output_active_reg is cleared only by the output cycle
# that also ends the operation (output_last_cycle_reg), after which the state is IDLE.
coverage exclude -du axi_dma_rd -srcfile dut/dma/axi_dma_rd.v -linerange 527 -allfalse -comment "output_active_reg is always 1 while the transfer state is active"
# Line 509, 'transfer_in_save = m_axi_rready && m_axi_rvalid', is evaluated only when
# '(m_axi_rready && m_axi_rvalid) || !input_active_reg' holds.  m_axi_rready is registered
# from 'm_axis_read_data_tready_int && input_active_next' on every path, so rready=1 implies
# input_active_reg=1 and the row "rready=1, rvalid=0" cannot occur inside the branch.
coverage exclude -du axi_dma_rd -srcfile dut/dma/axi_dma_rd.v -fecexprrow 509 3 -comment "m_axi_rready=1 implies input_active_reg=1; row unreachable inside the branch"

# --- [CONFIG] Limited by the 32-bit data bus ------------------------------------------
# One AXI burst moves at most AXI_MAX_BURST_LEN * 4 = 1024 bytes (256 beats is the AXI4
# maximum), so the per-burst byte and beat counters never use their upper bits, and the
# term 'word_count >> 12 != 0' is never true where a remainder of at most one burst is
# handled.  The registers are LEN_WIDTH wide because the same code serves wider buses.
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_next[11]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_next[12]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_next[13]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_next[14]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_next[15]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_next[16]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_next[17]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_next[18]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_next[19]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_reg[11]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_reg[12]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_reg[13]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_reg[14]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_reg[15]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_reg[16]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_reg[17]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_reg[18]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -togglenode {tr_word_count_reg[19]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_rd -srcfile dut/dma/axi_dma_rd.v -feccondrow 388 4 -comment "CONFIG-LIMITED: the remainder is at most one burst (1024 bytes) here, never 4096 or more"

# --- Whole-descriptor beat count ------------------------------------------------------
# The output beat count of a descriptor is (len-1)>>2 <= 0x3FFFF for LEN_WIDTH=20: bit 18 is never 1.
coverage exclude -du axi_dma_rd -togglenode {axis_cmd_output_cycle_count_next[18]} -comment "(2^20-2)>>2 = 0x3FFFF is the largest value"
coverage exclude -du axi_dma_rd -togglenode {axis_cmd_output_cycle_count_reg[18]} -comment "(2^20-2)>>2 = 0x3FFFF is the largest value"

# --- TKEEP bit 0 --------------------------------------------------------------------
# Every output beat carries at least byte 0: tkeep is all ones, or all ones shifted right.
coverage exclude -du axi_dma_rd -togglenode {m_axis_read_data_tkeep_int[0]} -comment "bit 0 of TKEEP is 1 on every beat"
coverage exclude -du axi_dma_rd -togglenode {m_axis_read_data_tkeep_reg[0]} -comment "bit 0 of TKEEP is 1 on every beat (never returns to 0)"
coverage exclude -du axi_dma_rd -togglenode {m_axis_read_data_tkeep[0]} -comment "bit 0 of TKEEP is 1 on every beat (never returns to 0)"

# ==============================================================================
# axi_dma_wr
# ==============================================================================
# --- Outputs tied to a constant by a continuous assignment -------------------------
# The engines always issue full-width INCR bursts with ID 0, no lock, CACHE 0011, PROT 010.
coverage exclude -du axi_dma_wr -togglenode {m_axi_awid} -comment "assign m_axi_awid = 0"
coverage exclude -du axi_dma_wr -togglenode {m_axi_awsize} -comment "assign m_axi_awsize = AXI_BURST_SIZE (constant)"
coverage exclude -du axi_dma_wr -togglenode {m_axi_awburst} -comment "assign m_axi_awburst = 2'b01 (INCR)"
coverage exclude -du axi_dma_wr -togglenode {m_axi_awlock} -comment "assign m_axi_awlock = 1'b0"
coverage exclude -du axi_dma_wr -togglenode {m_axi_awcache} -comment "assign m_axi_awcache = 4'b0011"
coverage exclude -du axi_dma_wr -togglenode {m_axi_awprot} -comment "assign m_axi_awprot = 3'b010"

# --- Status error code bits that no assigned value ever sets -----------------------
# axi_dma_wr reports the codes 0, 6 and 7 only, so bit 3 is never 1.
coverage exclude -du axi_dma_wr -togglenode {m_axis_write_desc_status_error[3]} -comment "only the codes 0, 6 and 7 are assigned"
coverage exclude -du axi_dma_wr -togglenode {m_axis_write_desc_status_error_next[3]} -comment "only the codes 0, 6 and 7 are assigned"
coverage exclude -du axi_dma_wr -togglenode {m_axis_write_desc_status_error_reg[3]} -comment "only the codes 0, 6 and 7 are assigned"

# --- Output FIFO can never be full -------------------------------------------------
# The 32-entry output FIFO stops its producer when it is half full (out_fifo_half_full_reg,
# registered, 16 entries).  The producer stops two cycles later and at most a few more
# entries are written (the ready signal is registered once more, plus one or two flush
# beats), so the fill level stays near 20, far below 32, and out_fifo_full is constant 0.
coverage exclude -du axi_dma_wr -togglenode {out_fifo_full} -comment "flow control at half full; the FIFO never fills"
coverage exclude -du axi_dma_wr -srcfile dut/dma/axi_dma_wr.v -fecexprrow 915 2 -comment "out_fifo_full is never 1 (flow control at half full)"
coverage exclude -du axi_dma_wr -srcfile dut/dma/axi_dma_wr.v -feccondrow 937 2 -comment "out_fifo_full is never 1 (flow control at half full)"

# --- Case statements that list every value their state register can hold ------------
coverage exclude -du axi_dma_wr -srcfile dut/dma/axi_dma_wr.v -linerange 433 -allfalse -comment "state_reg only ever holds the six listed states (values 6 and 7 are never assigned)"

# --- Stream handshake rows that cannot occur inside their branch ---------------------
# Line 550 (STATE_WRITE) and line 757 (STATE_DROP_DATA): 'if (s_axis_write_data_tready &&
# s_axis_write_data_tvalid)' could see tready=1 with tvalid=0 only if the enclosing branch
# was entered without a stream beat, i.e. in the extra cycle after TLAST or with the input
# side inactive.  In both cases s_axis_write_data_tready_next was computed as 0 one cycle
# earlier (shift_axis_input_tready=0, respectively !input_active && !last_transfer).
coverage exclude -du axi_dma_wr -srcfile dut/dma/axi_dma_wr.v -feccondrow 550 3 -comment "tready=1 with tvalid=0 cannot occur inside the transfer branch"
coverage exclude -du axi_dma_wr -srcfile dut/dma/axi_dma_wr.v -feccondrow 757 3 -comment "tready=1 with tvalid=0 cannot occur while the shifter holds the TLAST beat"

# --- Not hardware / constant bit -----------------------------------------------------
coverage exclude -du axi_dma_wr -togglenode {i} -comment "integer loop index, not a design signal"
# strb_offset_mask = {4{1'b1}} << offset with offset 0..3: bit 3 is always 1.
coverage exclude -du axi_dma_wr -togglenode {strb_offset_mask_next[3]} -comment "all-ones shifted left by 0..3: bit 3 is always 1"
coverage exclude -du axi_dma_wr -togglenode {strb_offset_mask_reg[3]} -comment "all-ones shifted left by 0..3: bit 3 is always 1"

# --- [CONFIG] Limited by the 32-bit data bus ------------------------------------------
# One AXI burst moves at most AXI_MAX_BURST_LEN * 4 = 1024 bytes (256 beats is the AXI4
# maximum), so the per-burst byte and beat counters never use their upper bits, and the
# term 'word_count >> 12 != 0' is never true where a remainder of at most one burst is
# handled.  The registers are LEN_WIDTH wide because the same code serves wider buses.
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_next[11]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_next[12]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_next[13]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_next[14]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_next[15]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_next[16]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_next[17]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_next[18]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_next[19]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_reg[11]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_reg[12]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_reg[13]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_reg[14]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_reg[15]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_reg[16]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_reg[17]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_reg[18]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -togglenode {tr_word_count_reg[19]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_dma_wr -srcfile dut/dma/axi_dma_wr.v -feccondrow 471 4 -comment "CONFIG-LIMITED: the remainder is at most one burst (1024 bytes) here, never 4096 or more"

# ==============================================================================
# axi_cdma
# ==============================================================================
# --- Outputs tied to a constant by a continuous assignment -------------------------
# The engines always issue full-width INCR bursts with ID 0, no lock, CACHE 0011, PROT 010.
coverage exclude -du axi_cdma -togglenode {m_axi_arid} -comment "assign m_axi_arid = 0"
coverage exclude -du axi_cdma -togglenode {m_axi_arsize} -comment "assign m_axi_arsize = AXI_BURST_SIZE (constant)"
coverage exclude -du axi_cdma -togglenode {m_axi_arburst} -comment "assign m_axi_arburst = 2'b01 (INCR)"
coverage exclude -du axi_cdma -togglenode {m_axi_arlock} -comment "assign m_axi_arlock = 1'b0"
coverage exclude -du axi_cdma -togglenode {m_axi_arcache} -comment "assign m_axi_arcache = 4'b0011"
coverage exclude -du axi_cdma -togglenode {m_axi_arprot} -comment "assign m_axi_arprot = 3'b010"
coverage exclude -du axi_cdma -togglenode {m_axi_awid} -comment "assign m_axi_awid = 0"
coverage exclude -du axi_cdma -togglenode {m_axi_awsize} -comment "assign m_axi_awsize = AXI_BURST_SIZE (constant)"
coverage exclude -du axi_cdma -togglenode {m_axi_awburst} -comment "assign m_axi_awburst = 2'b01 (INCR)"
coverage exclude -du axi_cdma -togglenode {m_axi_awlock} -comment "assign m_axi_awlock = 1'b0"
coverage exclude -du axi_cdma -togglenode {m_axi_awcache} -comment "assign m_axi_awcache = 4'b0011"
coverage exclude -du axi_cdma -togglenode {m_axi_awprot} -comment "assign m_axi_awprot = 3'b010"

# --- Status error code bits that no assigned value ever sets -----------------------
# axi_cdma reports the codes 0, 4, 5, 6 and 7 only, so bit 3 is never 1.
coverage exclude -du axi_cdma -togglenode {m_axis_desc_status_error[3]} -comment "only the codes 0, 4, 5, 6 and 7 are assigned"
coverage exclude -du axi_cdma -togglenode {m_axis_desc_status_error_next[3]} -comment "only the codes 0, 4, 5, 6 and 7 are assigned"
coverage exclude -du axi_cdma -togglenode {m_axis_desc_status_error_reg[3]} -comment "only the codes 0, 4, 5, 6 and 7 are assigned"

# --- Output FIFO can never be full -------------------------------------------------
# The 32-entry output FIFO stops its producer when it is half full (out_fifo_half_full_reg,
# registered, 16 entries).  The producer stops two cycles later and at most a few more
# entries are written (the ready signal is registered once more, plus one or two flush
# beats), so the fill level stays near 20, far below 32, and out_fifo_full is constant 0.
coverage exclude -du axi_cdma -togglenode {out_fifo_full} -comment "flow control at half full; the FIFO never fills"
coverage exclude -du axi_cdma -srcfile dut/dma/axi_cdma.v -fecexprrow 771 2 -comment "out_fifo_full is never 1 (flow control at half full)"
coverage exclude -du axi_cdma -srcfile dut/dma/axi_cdma.v -feccondrow 793 2 -comment "out_fifo_full is never 1 (flow control at half full)"

# --- Case statements that list every value their state register can hold ------------
coverage exclude -du axi_cdma -srcfile dut/dma/axi_cdma.v -linerange 323 -allfalse -comment "read_state_reg is 2 bits, all four values listed"
coverage exclude -du axi_cdma -srcfile dut/dma/axi_cdma.v -linerange 513 -allfalse -comment "axi_state_reg is 1 bit, both values listed"

# --- Redundant guards in the data-transfer state ------------------------------------
# Line 559, 'if (input_active_reg)', sits in the branch taken only in the first input cycle
# of a burst (first cycle && bubble_cycle); input_active_reg is set when the burst is loaded
# and cannot have been cleared before its first cycle.
coverage exclude -du axi_cdma -srcfile dut/dma/axi_cdma.v -linerange 559 -allfalse -comment "input_active_reg is always 1 in the first input cycle"
# Line 574, 'if (output_active_reg)': output_active_reg is cleared only by the output cycle
# that also ends the operation (output_last_cycle_reg), after which the state is IDLE.
coverage exclude -du axi_cdma -srcfile dut/dma/axi_cdma.v -linerange 574 -allfalse -comment "output_active_reg is always 1 while the transfer state is active"
# Line 556, 'transfer_in_save = m_axi_rready && m_axi_rvalid', is evaluated only when
# '(m_axi_rready && m_axi_rvalid) || !input_active_reg' holds.  m_axi_rready is registered
# from 'm_axi_wready_int && input_active_next' on every path, so rready=1 implies
# input_active_reg=1 and the row "rready=1, rvalid=0" cannot occur inside the branch.
# (True for the RTL with the CDMA-01 fix, which is the RTL coverage is measured on.)
coverage exclude -du axi_cdma -srcfile dut/dma/axi_cdma.v -fecexprrow 556 3 -comment "m_axi_rready=1 implies input_active_reg=1; row unreachable inside the branch"

# --- [CONFIG] Limited by the 32-bit data bus ------------------------------------------
# One AXI burst moves at most AXI_MAX_BURST_LEN * 4 = 1024 bytes (256 beats is the AXI4
# maximum), so the per-burst byte and beat counters never use their upper bits, and the
# term 'word_count >> 12 != 0' is never true where a remainder of at most one burst is
# handled.  The registers are LEN_WIDTH wide because the same code serves wider buses.
coverage exclude -du axi_cdma -togglenode {tr_word_count_next[11]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_next[12]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_next[13]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_next[14]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_next[15]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_next[16]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_next[17]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_next[18]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_next[19]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_reg[11]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_reg[12]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_reg[13]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_reg[14]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_reg[15]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_reg[16]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_reg[17]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_reg[18]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {tr_word_count_reg[19]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -srcfile dut/dma/axi_cdma.v -feccondrow 350 4 -comment "CONFIG-LIMITED: the remainder is at most one burst (1024 bytes) here, never 4096 or more"
coverage exclude -du axi_cdma -srcfile dut/dma/axi_cdma.v -feccondrow 405 4 -comment "CONFIG-LIMITED: the remainder is at most one burst (1024 bytes) here, never 4096 or more"
coverage exclude -du axi_cdma -togglenode {axi_word_count_next[11]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_next[12]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_next[13]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_next[14]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_next[15]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_next[16]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_next[17]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_next[18]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_next[19]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_reg[11]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_reg[12]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_reg[13]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_reg[14]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_reg[15]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_reg[16]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_reg[17]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_reg[18]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
coverage exclude -du axi_cdma -togglenode {axi_word_count_reg[19]} -comment "CONFIG-LIMITED: at most 1024 bytes per burst on a 32-bit bus"
# Beats of one chunk: at most 257 read beats (bit 8) and 256 write beats (AWLEN <= 255).
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_next[9]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_next[10]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_next[11]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_next[12]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_next[13]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_next[14]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_next[15]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_next[16]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_next[17]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_next[18]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_reg[9]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_reg[10]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_reg[11]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_reg[12]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_reg[13]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_reg[14]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_reg[15]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_reg[16]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_reg[17]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_input_cycle_count_reg[18]} -comment "CONFIG-LIMITED: at most 257 read beats per chunk"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_next[8]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_next[9]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_next[10]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_next[11]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_next[12]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_next[13]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_next[14]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_next[15]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_next[16]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_next[17]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_next[18]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_reg[8]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_reg[9]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_reg[10]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_reg[11]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_reg[12]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_reg[13]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_reg[14]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_reg[15]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_reg[16]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_reg[17]} -comment "CONFIG-LIMITED: AWLEN is at most 255"
coverage exclude -du axi_cdma -togglenode {axi_cmd_output_cycle_count_reg[18]} -comment "CONFIG-LIMITED: AWLEN is at most 255"

